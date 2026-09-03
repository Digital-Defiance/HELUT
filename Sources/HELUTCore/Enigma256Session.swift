import CryptoKit
import Foundation

// MARK: - Enigma 256 session API (control plane)
//
// IKM → day key → per-message nonce → seal/open. Reciprocal cipher body:
// seal ≡ open with the same day key + nonce. Wire/file containers use AEAD
// (HMAC-SHA512) via `sealAEAD` / `Enigma256ProtectedSession`.

/// Sealed blob: public nonce + ciphertext + optional AEAD tag.
package struct Enigma256SealedBox: Sendable, Equatable {
    package var nonce: Data
    package var ciphertext: [UInt8]
    /// HMAC-SHA512 truncated tag (32 bytes). Nil only for legacy v1 containers.
    package var tag: Data?

    package init(nonce: Data, ciphertext: [UInt8], tag: Data? = nil) {
        precondition(!nonce.isEmpty, "nonce must be non-empty")
        self.nonce = nonce
        self.ciphertext = ciphertext
        self.tag = tag
    }

    /// On-wire container: `E256` | ver | nlen | nonce | ciphertext [| tag].
    /// ver=2 includes 32-byte tag; ver=1 is legacy body-only (tests / migration).
    package func encode() -> Data {
        precondition(nonce.count <= 255)
        var out = Data("E256".utf8)
        if let tag, tag.count == Enigma256AEAD.tagLength {
            out.append(Enigma256AEAD.containerVersion)
            out.append(UInt8(nonce.count))
            out.append(nonce)
            out.append(contentsOf: ciphertext)
            out.append(tag)
        } else {
            out.append(1)
            out.append(UInt8(nonce.count))
            out.append(nonce)
            out.append(contentsOf: ciphertext)
        }
        return out
    }

    package static func decode(_ data: Data) throws -> Enigma256SealedBox {
        guard data.count >= 6 else { throw Enigma256SessionError.truncatedContainer }
        let magic = String(data: data.prefix(4), encoding: .utf8)
        guard magic == "E256" else { throw Enigma256SessionError.badMagic }
        let version = data[4]
        let nlen = Int(data[5])
        guard data.count >= 6 + nlen else { throw Enigma256SessionError.truncatedContainer }
        let nonce = data.subdata(in: 6 ..< (6 + nlen))
        let rest = data.subdata(in: (6 + nlen) ..< data.count)
        switch version {
        case 1:
            return Enigma256SealedBox(nonce: nonce, ciphertext: [UInt8](rest), tag: nil)
        case Enigma256AEAD.containerVersion:
            guard rest.count >= Enigma256AEAD.tagLength else {
                throw Enigma256SessionError.truncatedContainer
            }
            let ctEnd = rest.count - Enigma256AEAD.tagLength
            let ct = [UInt8](rest.prefix(ctEnd))
            let tag = Data(rest.suffix(Enigma256AEAD.tagLength))
            return Enigma256SealedBox(nonce: nonce, ciphertext: ct, tag: tag)
        default:
            throw Enigma256SessionError.unsupportedVersion(version)
        }
    }
}

package enum Enigma256SessionError: Error, Equatable {
    case truncatedContainer
    case badMagic
    case unsupportedVersion(UInt8)
    case emptyPlaintext
}

/// Long-lived day-key context. Cheap to derive once; seal/open per message.
package struct Enigma256Context: Sendable {
    package let ikm: Data
    package let salt: Data
    package let profile: Enigma256Generation
    package let day: Enigma256DayKey

    package init(
        ikm: Data,
        salt: Data = Data(),
        profile: Enigma256Generation = .v2Gen0
    ) {
        precondition(!ikm.isEmpty, "IKM must be non-empty")
        precondition((try? profile.validate()) != nil, "invalid E256 generation")
        self.ikm = ikm
        self.salt = salt
        self.profile = profile
        self.day = Enigma256KDF.deriveDayKey(ikm: ikm, salt: salt, info: profile.dayInfo)
    }

    /// Derive message key + active wiring for a nonce (does not encrypt).
    package func messageState(nonce: Data) -> (key: Enigma256MessageKey, wiring: Enigma256Wiring) {
        let key = Enigma256KDF.deriveMessageKey(
            masterIKM: ikm,
            nonce: nonce,
            info: profile.messageInfo,
            centerMaskKeyInfo: profile.centerMaskKeyInfo
        )
        return (key, key.wiring(from: day))
    }

    /// Body-only encrypt (no MAC). Prefer `sealAEAD` for wire/file.
    package func seal(_ plaintext: [UInt8], nonce: Data) -> Enigma256SealedBox {
        let ct = sealBody(plaintext, nonce: nonce)
        return Enigma256SealedBox(nonce: nonce, ciphertext: ct, tag: nil)
    }

    /// Open body (reciprocal). For AEAD boxes call `openAEAD` / ProtectedSession.
    package func open(_ box: Enigma256SealedBox) -> [UInt8] {
        sealBody(box.ciphertext, nonce: box.nonce)
    }

    /// Random 16-byte nonce + AEAD seal (no reuse tracking — use ProtectedSession).
    package func seal(_ plaintext: [UInt8]) -> Enigma256SealedBox {
        var nonceBytes = [UInt8](repeating: 0, count: 16)
        var rng = SystemRandomNumberGenerator()
        for i in 0 ..< 16 {
            nonceBytes[i] = UInt8.random(in: .min ... .max, using: &rng)
        }
        return sealAEAD(plaintext, nonce: Data(nonceBytes))
    }
}

// MARK: - Bitbang core handle (AXI-lite register map simulator)

/// Mirrors `ENIGMA256_REGMAP.md` / `enigma_256_core` host programming.
package final class Enigma256CoreHandle: @unchecked Sendable {
    package private(set) var wiring = Enigma256Wiring.identity
    package private(set) var generation: Enigma256Generation
    package private(set) var machine: Enigma256Machine
    package private(set) var transactionLog: [Enigma256BusTxn] = []

    /// Scratch message-key registers (written before `pulseLoadState`).
    package var regLFSR: UInt64 = 1
    package var regPos: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)
    package var regCenterMaskKey = Data(repeating: 0, count: Enigma256CenterMask.keyLength)
    package var regByteCounter: UInt64 = 0

    package init(generation: Enigma256Generation = .v2Gen0) {
        precondition((try? generation.validate()) != nil, "invalid E256 generation")
        self.generation = generation
        self.machine = Enigma256Machine(
            wiring: .identity,
            lfsrSeed: 1,
            positions: (0, 0, 0, 0),
            centerMaskKey: Data(repeating: 0, count: Enigma256CenterMask.keyLength),
            generation: generation
        )
    }

    package func bindGeneration(_ generation: Enigma256Generation) {
        precondition((try? generation.validate()) != nil, "invalid E256 generation")
        self.generation = generation
    }

    /// `WR_SEL` / `WR_ADDR` / `WR_DATA` + assert write strobe.
    package func writeTableByte(sel: Enigma256TableSel, addr: UInt8, data: UInt8) {
        transactionLog.append(.tableWrite(sel: sel.rawValue, addr: addr, data: data))
        var tables = Enigma256TableSel.allCases.map { Enigma256Bridge.table(wiring, sel: $0) }
        tables[sel.rawValue][Int(addr)] = data
        wiring = Enigma256Bridge.wiring(fromTables: tables)
    }

    /// Program all nine BRAMs from active-slot wiring.
    package func programTables(_ wiring: Enigma256Wiring) {
        for sel in Enigma256TableSel.allCases {
            let bytes = Enigma256Bridge.table(wiring, sel: sel)
            for (addr, byte) in bytes.enumerated() {
                writeTableByte(sel: sel, addr: UInt8(addr), data: byte)
            }
        }
    }

    /// Burst-oriented table load (models AXI-Stream DMA of 2,304 bytes).
    package func programTablesBurst(_ wiring: Enigma256Wiring) {
        precondition((try? wiring.validate()) != nil, "invalid E256 wiring")
        transactionLog.append(.tableBurst(byteCount: Enigma256TableSel.allCases.count * 256))
        self.wiring = wiring
    }

    package func writeMessageKey(_ key: Enigma256MessageKey) {
        regLFSR = key.lfsrSeed == 0 ? 1 : key.lfsrSeed
        regPos = key.positions
        regCenterMaskKey = key.centerMaskKey
        regByteCounter = 0
        transactionLog.append(.messageKey(lfsr: regLFSR, positions: regPos))
    }

    /// Pulse `LOAD_STATE` — capture LFSR + Grundstellung into the stream engine.
    package func pulseLoadState() {
        transactionLog.append(.loadState)
        machine = Enigma256Machine(
            wiring: wiring,
            lfsrSeed: regLFSR,
            positions: regPos,
            centerMaskKey: regCenterMaskKey,
            absoluteByteCounter: regByteCounter,
            generation: generation
        )
    }

    /// Full host bring-up: tables → message key → load.
    package func configure(
        day: Enigma256DayKey,
        message: Enigma256MessageKey,
        generation: Enigma256Generation = .v2Gen0,
        burstTables: Bool = true
    ) {
        precondition((try? generation.validate()) != nil, "invalid E256 generation")
        self.generation = generation
        let w = message.wiring(from: day)
        if burstTables {
            programTablesBurst(w)
        } else {
            programTables(w)
        }
        writeMessageKey(message)
        pulseLoadState()
    }

    package func configure(context: Enigma256Context, nonce: Data, burstTables: Bool = true) {
        let (key, _) = context.messageState(nonce: nonce)
        configure(
            day: context.day,
            message: key,
            generation: context.profile,
            burstTables: burstTables
        )
    }

    /// One atomic payload/mask/counter beat → `DATA_OUT`.
    package func transfer(_ byte: UInt8, centerMask: UInt8, counter: UInt64) -> UInt8 {
        precondition(counter == machine.absoluteByteCounter, "E256 counter transport desynchronized")
        transactionLog.append(.stream(byte: byte, centerMask: centerMask, counter: counter))
        return machine.processTraced(byte, centerMask: centerMask).output
    }

    package func transfer(_ byte: UInt8) -> UInt8 {
        transfer(
            byte,
            centerMask: machine.currentCenterMask,
            counter: machine.absoluteByteCounter
        )
    }

    package func transfer(_ bytes: [UInt8]) -> [UInt8] {
        bytes.map { transfer($0) }
    }
}

package enum Enigma256BusTxn: Sendable, Equatable {
    case tableWrite(sel: Int, addr: UInt8, data: UInt8)
    case tableBurst(byteCount: Int)
    case messageKey(lfsr: UInt64, positions: (UInt8, UInt8, UInt8, UInt8))
    case loadState
    case stream(byte: UInt8, centerMask: UInt8, counter: UInt64)

    package static func == (lhs: Enigma256BusTxn, rhs: Enigma256BusTxn) -> Bool {
        switch (lhs, rhs) {
        case let (.tableWrite(s1, a1, d1), .tableWrite(s2, a2, d2)):
            return s1 == s2 && a1 == a2 && d1 == d2
        case let (.tableBurst(a), .tableBurst(b)):
            return a == b
        case let (.messageKey(l1, p1), .messageKey(l2, p2)):
            return l1 == l2 && p1.0 == p2.0 && p1.1 == p2.1 && p1.2 == p2.2 && p1.3 == p2.3
        case (.loadState, .loadState):
            return true
        case let (.stream(byteA, maskA, counterA), .stream(byteB, maskB, counterB)):
            return byteA == byteB && maskA == maskB && counterA == counterB
        default:
            return false
        }
    }
}
