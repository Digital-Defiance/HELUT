import CryptoKit
import Foundation

// MARK: - Enigma 256 ephemeral X25519 handshake (control plane only)
//
// Spec §§2–3 / 7.2: ECDH runs in software. No Verilog — the FPGA only sees
// the derived day-key tables pushed over AXI after HKDF expansion.
//
// Suite default: HKDF-SHA512. For hybrid PQ + MitM binding see
// `Enigma256Hybrid.swift` / `Enigma256Auth.swift` (still control-plane only).

package enum Enigma256ECDHError: Error, Equatable {
    case invalidPublicKey
    case burned
    case peerMismatch
}

/// Ephemeral X25519 identity for one session. Call `burn()` when the link ends.
package final class Enigma256EphemeralIdentity: @unchecked Sendable {
    private var privateKey: Curve25519.KeyAgreement.PrivateKey?
    package let publicKeyRaw: Data

    package init() {
        let key = Curve25519.KeyAgreement.PrivateKey()
        self.privateKey = key
        self.publicKeyRaw = key.publicKey.rawRepresentation
    }

    /// Reconstruct a peer public key from 32 raw bytes.
    package static func parsePublicKey(_ raw: Data) throws -> Curve25519.KeyAgreement.PublicKey {
        guard raw.count == 32 else { throw Enigma256ECDHError.invalidPublicKey }
        do {
            return try Curve25519.KeyAgreement.PublicKey(rawRepresentation: raw)
        } catch {
            throw Enigma256ECDHError.invalidPublicKey
        }
    }

    /// Raw 32-byte X25519 shared secret (pre-HKDF). Used by hybrid KEM concat.
    package func sharedSecretRaw(peerPublicKeyRaw: Data) throws -> Data {
        guard let privateKey else { throw Enigma256ECDHError.burned }
        let peer = try Self.parsePublicKey(peerPublicKeyRaw)
        let shared = try privateKey.sharedSecretFromKeyAgreement(with: peer)
        return shared.withUnsafeBytes { Data($0) }
    }

    /// ECDH → IKM via HKDF-SHA512 (salt + info bind the cipher suite).
    package func deriveIKM(
        peerPublicKeyRaw: Data,
        salt: Data = Data(),
        info: Data = Data("enigma256-ecdh-v2".utf8),
        outputByteCount: Int = 64
    ) throws -> Data {
        guard let privateKey else { throw Enigma256ECDHError.burned }
        let peer = try Self.parsePublicKey(peerPublicKeyRaw)
        let shared = try privateKey.sharedSecretFromKeyAgreement(with: peer)
        let derived = shared.hkdfDerivedSymmetricKey(
            using: SHA512.self,
            salt: salt,
            sharedInfo: info,
            outputByteCount: outputByteCount
        )
        return derived.withUnsafeBytes { Data($0) }
    }

    /// Build a day-key context from ECDH with the peer.
    package func openContext(
        peerPublicKeyRaw: Data,
        salt: Data = Data(),
        info: Data = Data("enigma256-ecdh-v2".utf8)
    ) throws -> Enigma256Context {
        let ikm = try deriveIKM(peerPublicKeyRaw: peerPublicKeyRaw, salt: salt, info: info)
        return Enigma256Context(ikm: ikm, salt: salt)
    }

    /// Destroy the ephemeral private key (perfect forward secrecy for future capture).
    package func burn() {
        privateKey = nil
    }

    package var isBurned: Bool { privateKey == nil }
}

/// Two-sided channel after public-key exchange: shared `Enigma256Context` + burn.
package final class Enigma256SecureChannel: @unchecked Sendable {
    package private(set) var context: Enigma256Context?
    package private(set) var local: Enigma256EphemeralIdentity
    package let peerPublicKeyRaw: Data
    package let salt: Data

    package init(
        local: Enigma256EphemeralIdentity = Enigma256EphemeralIdentity(),
        peerPublicKeyRaw: Data,
        salt: Data = Data()
    ) throws {
        self.local = local
        self.peerPublicKeyRaw = peerPublicKeyRaw
        self.salt = salt
        self.context = try local.openContext(peerPublicKeyRaw: peerPublicKeyRaw, salt: salt)
    }

    /// Channel from a pre-derived IKM (hybrid / passphrase paths).
    package init(
        context: Enigma256Context,
        local: Enigma256EphemeralIdentity,
        peerPublicKeyRaw: Data,
        salt: Data
    ) {
        self.context = context
        self.local = local
        self.peerPublicKeyRaw = peerPublicKeyRaw
        self.salt = salt
    }

    package func seal(_ plaintext: [UInt8], nonce: Data) throws -> Enigma256SealedBox {
        guard let context else { throw Enigma256ECDHError.burned }
        return context.seal(plaintext, nonce: nonce)
    }

    package func seal(_ plaintext: [UInt8]) throws -> Enigma256SealedBox {
        guard let context else { throw Enigma256ECDHError.burned }
        return context.seal(plaintext)
    }

    package func open(_ box: Enigma256SealedBox) throws -> [UInt8] {
        guard let context else { throw Enigma256ECDHError.burned }
        return context.open(box)
    }

    /// Drop context + ephemeral private key.
    package func burn() {
        context = nil
        local.burn()
    }

    package var isBurned: Bool { context == nil || local.isBurned }
}

/// Convenience: Alice/Bob complete handshake and return paired channels (same IKM).
package enum Enigma256Handshake {
    package static func paired(salt: Data = Data()) throws -> (
        alice: Enigma256SecureChannel,
        bob: Enigma256SecureChannel
    ) {
        let a = Enigma256EphemeralIdentity()
        let b = Enigma256EphemeralIdentity()
        let alice = try Enigma256SecureChannel(local: a, peerPublicKeyRaw: b.publicKeyRaw, salt: salt)
        let bob = try Enigma256SecureChannel(local: b, peerPublicKeyRaw: a.publicKeyRaw, salt: salt)
        // Same IKM both ways (X25519 is symmetric).
        guard alice.context?.ikm == bob.context?.ikm else {
            throw Enigma256ECDHError.peerMismatch
        }
        return (alice, bob)
    }
}
