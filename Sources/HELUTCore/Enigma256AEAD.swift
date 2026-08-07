import CryptoKit
import Foundation

// MARK: - Enigma 256 AEAD + monotonic nonce (control plane)
//
// Ciphertext malleability fix: HMAC-SHA512 over (nonce || ciphertext) with a
// key derived from the session IKM. Tag is verified *before* any SoftBus/AXI
// stream. Nonce reuse is rejected via a monotonic 64-bit counter packed into
// the public nonce.

package enum Enigma256AEADError: Error, Equatable {
    case authenticationFailed
    case nonceReused
    case counterExhausted
    case badTag
}

package enum Enigma256AEAD {
    package static let macInfo = Data("enigma256-mac-v1".utf8)
    package static let tagLength = 32 // truncated HMAC-SHA512
    package static let containerVersion: UInt8 = 2

    package static func macKey(ikm: Data, salt: Data) -> SymmetricKey {
        let raw = Enigma256KDF.hkdf(ikm: ikm, salt: salt, info: macInfo, length: 64)
        return SymmetricKey(data: raw)
    }

    package static func tag(macKey: SymmetricKey, nonce: Data, ciphertext: [UInt8]) -> Data {
        var msg = nonce
        msg.append(contentsOf: ciphertext)
        let full = HMAC<SHA512>.authenticationCode(for: msg, using: macKey)
        return Data(full).prefix(tagLength)
    }

    package static func verify(macKey: SymmetricKey, nonce: Data, ciphertext: [UInt8], tag: Data) -> Bool {
        let expect = Self.tag(macKey: macKey, nonce: nonce, ciphertext: ciphertext)
        return tagsEqual(expect, tag)
    }

    /// Constant-time equality for MAC tags.
    package static func tagsEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0 ..< a.count {
            diff |= a[i] ^ b[i]
        }
        return diff == 0
    }
}

extension Enigma256Context {
    package var macKey: SymmetricKey {
        Enigma256AEAD.macKey(ikm: ikm, salt: salt)
    }

    /// Confidentiality-only (RTL golden / SoftBus body). Prefer `sealAEAD` on the wire.
    package func sealBody(_ plaintext: [UInt8], nonce: Data) -> [UInt8] {
        let (key, wiring) = messageState(nonce: nonce)
        var machine = Enigma256Machine(
            wiring: wiring,
            lfsrSeed: key.lfsrSeed,
            positions: key.positions,
            centerMaskKey: key.centerMaskKey,
            generation: profile
        )
        return machine.process(plaintext)
    }

    /// AEAD seal: reciprocal body + HMAC-SHA512 tag (truncated 32).
    package func sealAEAD(_ plaintext: [UInt8], nonce: Data) -> Enigma256SealedBox {
        let ct = sealBody(plaintext, nonce: nonce)
        let tag = Enigma256AEAD.tag(macKey: macKey, nonce: nonce, ciphertext: ct)
        return Enigma256SealedBox(nonce: nonce, ciphertext: ct, tag: tag)
    }

    /// Verify tag then decrypt. Throws on authentication failure.
    package func openAEAD(_ box: Enigma256SealedBox) throws -> [UInt8] {
        let tag = box.tag ?? Data()
        let expect = Enigma256AEAD.tag(macKey: macKey, nonce: box.nonce, ciphertext: box.ciphertext)
        guard Enigma256AEAD.tagsEqual(expect, tag) else {
            throw Enigma256AEADError.authenticationFailed
        }
        return sealBody(box.ciphertext, nonce: box.nonce)
    }
}

/// Session wrapper: monotonic nonce counter + AEAD by default.
package final class Enigma256ProtectedSession: @unchecked Sendable {
    package let context: Enigma256Context
    private var counter: UInt64
    private var usedNonces: Set<Data>
    private let lock = NSLock()

    package init(context: Enigma256Context, startCounter: UInt64 = 0) {
        self.context = context
        self.counter = startCounter
        self.usedNonces = []
    }

    package convenience init(ikm: Data, salt: Data = Data()) {
        self.init(context: Enigma256Context(ikm: ikm, salt: salt))
    }

    /// 8 random bytes ‖ 8-byte big-endian counter (never reused under this session).
    package func nextNonce() throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        guard counter < UInt64.max else { throw Enigma256AEADError.counterExhausted }
        var nonce = Data(count: 16)
        var rng = SystemRandomNumberGenerator()
        for i in 0 ..< 8 {
            nonce[i] = UInt8.random(in: .min ... .max, using: &rng)
        }
        var be = counter.bigEndian
        withUnsafeBytes(of: &be) { nonce.replaceSubrange(8 ..< 16, with: $0) }
        counter += 1
        guard usedNonces.insert(nonce).inserted else { throw Enigma256AEADError.nonceReused }
        return nonce
    }

    package func registerNonce(_ nonce: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        guard usedNonces.insert(nonce).inserted else { throw Enigma256AEADError.nonceReused }
    }

    package func seal(_ plaintext: [UInt8]) throws -> Enigma256SealedBox {
        let nonce = try nextNonce()
        return context.sealAEAD(plaintext, nonce: nonce)
    }

    package func seal(_ plaintext: [UInt8], nonce: Data) throws -> Enigma256SealedBox {
        try registerNonce(nonce)
        return context.sealAEAD(plaintext, nonce: nonce)
    }

    package func open(_ box: Enigma256SealedBox) throws -> [UInt8] {
        try context.openAEAD(box)
    }
}
