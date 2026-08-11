import Foundation

// MARK: - Enigma 256 session API (control plane)
//
// IKM → day key → per-message nonce → seal/open. Reciprocal cipher: seal ≡ open
// with the same day key + nonce. FPGA programming goes through `Enigma256CoreHandle`
// (see ENIGMA256_REGMAP.md).

/// Sealed blob: public nonce + ciphertext (no MAC; confidentiality only).
package struct Enigma256SealedBox: Sendable, Equatable {
    package var nonce: Data
    package var ciphertext: [UInt8]

    package init(nonce: Data, ciphertext: [UInt8]) {
        precondition(!nonce.isEmpty, "nonce must be non-empty")
        self.nonce = nonce
        self.ciphertext = ciphertext
    }

    /// On-wire container: `E256` | ver=1 | nlen | nonce | ciphertext.
    package func encode() -> Data {
        precondition(nonce.count <= 255)
        var out = Data("E256".utf8)
        out.append(1) // version
        out.append(UInt8(nonce.count))
        out.append(nonce)
        out.append(contentsOf: ciphertext)
        return out
    }

    package static func decode(_ data: Data) throws -> Enigma256SealedBox {
        guard data.count >= 6 else { throw Enigma256SessionError.truncatedContainer }
        let magic = String(data: data.prefix(4), encoding: .utf8)
        guard magic == "E256" else { throw Enigma256SessionError.badMagic }
        let version = data[4]
        guard version == 1 else { throw Enigma256SessionError.unsupportedVersion(version) }
        let nlen = Int(data[5])
        guard data.count >= 6 + nlen else { throw Enigma256SessionError.truncatedContainer }
        let nonce = data.subdata(in: 6 ..< (6 + nlen))
        let ct = [UInt8](data.subdata(in: (6 + nlen) ..< data.count))
        return Enigma256SealedBox(nonce: nonce, ciphertext: ct)
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
    package let day: Enigma256DayKey

    package init(ikm: Data, salt: Data = Data()) {
        precondition(!ikm.isEmpty, "IKM must be non-empty")
        self.ikm = ikm
        self.salt = salt
        self.day = Enigma256KDF.deriveDayKey(ikm: ikm, salt: salt)
    }

    /// Derive message key + active wiring for a nonce (does not encrypt).
    package func messageState(nonce: Data) -> (key: Enigma256MessageKey, wiring: Enigma256Wiring) {
        let key = Enigma256KDF.deriveMessageKey(masterIKM: ikm, nonce: nonce)
        return (key, key.wiring(from: day))
    }

    /// Encrypt (or decrypt — reciprocal) under a fresh or caller-supplied nonce.
    package func seal(_ plaintext: [UInt8], nonce: Data) -> Enigma256SealedBox {
        let (key, wiring) = messageState(nonce: nonce)
        var machine = Enigma256Machine(wiring: wiring, lfsrSeed: key.lfsrSeed, positions: key.positions)
        let ct = machine.process(plaintext)
        return Enigma256SealedBox(nonce: nonce, ciphertext: ct)
    }

    /// Open a sealed box (same as seal on the ciphertext).
    package func open(_ box: Enigma256SealedBox) -> [UInt8] {
        seal(box.ciphertext, nonce: box.nonce).ciphertext
    }

    /// Random 16-byte nonce + seal.
    package func seal(_ plaintext: [UInt8]) -> Enigma256SealedBox {
        var nonceBytes = [UInt8](repeating: 0, count: 16)
        var rng = SystemRandomNumberGenerator()
        for i in 0 ..< 16 {
            nonceBytes[i] = UInt8.random(in: .min ... .max, using: &rng)
        }
        return seal(plaintext, nonce: Data(nonceBytes))
    }
}

// MARK: - Bitbang core handle (AXI-lite register map simulator)

/// Mirrors `ENIGMA256_REGMAP.md` / `enigma_256_core` host programming.
package final class Enigma256CoreHandle: @unchecked Sendable {
    package private(set) var wiring = Enigma256Wiring.identity
    package private(set) var machine: Enigma256Machine
    package private(set) var transactionLog: [Enigma256BusTxn] = []

    /// Scratch message-key registers (written before `pulseLoadState`).
    package var regLFSR: UInt64 = 1
    package var regPos: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)

    package init() {
        self.machine = Enigma256Machine(wiring: .identity, lfsrSeed: 1, positions: (0, 0, 0, 0))
    }

    /// `WR_SEL` / `WR_ADDR` / `WR_DATA` + assert write strobe.
    package func writeTableByte(sel: Enigma256TableSel, addr: UInt8, data: UInt8) {
        transactionLog.append(.tableWrite(sel: sel.rawValue, addr: addr, data: data))
        var tables = (0 ..< 10).map { Enigma256Bridge.table(wiring, sel: Enigma256TableSel(rawValue: $0)!) }
        tables[sel.rawValue][Int(addr)] = data
        wiring = Enigma256Bridge.wiring(fromTables: tables)
    }

    /// Program all ten BRAMs from active-slot wiring.
    package func programTables(_ wiring: Enigma256Wiring) {
        for sel in Enigma256TableSel.allCases {
            let bytes = Enigma256Bridge.table(wiring, sel: sel)
            for (addr, byte) in bytes.enumerated() {
                writeTableByte(sel: sel, addr: UInt8(addr), data: byte)
            }
        }
    }

    package func writeMessageKey(_ key: Enigma256MessageKey) {
        regLFSR = key.lfsrSeed == 0 ? 1 : key.lfsrSeed
        regPos = key.positions
        transactionLog.append(.messageKey(lfsr: regLFSR, positions: regPos))
    }

    /// Pulse `LOAD_STATE` — capture LFSR + Grundstellung into the stream engine.
    package func pulseLoadState() {
        transactionLog.append(.loadState)
        machine = Enigma256Machine(wiring: wiring, lfsrSeed: regLFSR, positions: regPos)
    }

    /// Full host bring-up: tables → message key → load.
    package func configure(day: Enigma256DayKey, message: Enigma256MessageKey) {
        let w = message.wiring(from: day)
        programTables(w)
        writeMessageKey(message)
        pulseLoadState()
    }

    package func configure(context: Enigma256Context, nonce: Data) {
        let (key, _) = context.messageState(nonce: nonce)
        configure(day: context.day, message: key)
    }

    /// One `DATA_IN`/`VALID_IN` beat → `DATA_OUT`.
    package func transfer(_ byte: UInt8) -> UInt8 {
        transactionLog.append(.stream(byte))
        return machine.process(byte)
    }

    package func transfer(_ bytes: [UInt8]) -> [UInt8] {
        bytes.map { transfer($0) }
    }
}

package enum Enigma256BusTxn: Sendable, Equatable {
    case tableWrite(sel: Int, addr: UInt8, data: UInt8)
    case messageKey(lfsr: UInt64, positions: (UInt8, UInt8, UInt8, UInt8))
    case loadState
    case stream(UInt8)

    package static func == (lhs: Enigma256BusTxn, rhs: Enigma256BusTxn) -> Bool {
        switch (lhs, rhs) {
        case let (.tableWrite(s1, a1, d1), .tableWrite(s2, a2, d2)):
            return s1 == s2 && a1 == a2 && d1 == d2
        case let (.messageKey(l1, p1), .messageKey(l2, p2)):
            return l1 == l2 && p1.0 == p2.0 && p1.1 == p2.1 && p1.2 == p2.2 && p1.3 == p2.3
        case (.loadState, .loadState):
            return true
        case let (.stream(a), .stream(b)):
            return a == b
        default:
            return false
        }
    }
}
