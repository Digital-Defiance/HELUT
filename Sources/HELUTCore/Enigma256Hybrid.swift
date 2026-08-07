import CryptoKit
import Foundation

// MARK: - Hybrid post-quantum KEM (control plane only)
//
// Store-now-decrypt-later defense without touching Verilog:
//   IKM_input = X25519_shared || ML-KEM_shared
//   IKM       = HKDF-SHA512(IKM_input, salt, info)
//
// XWingMLKEM768X25519 is also exposed as a single CryptoKit hybrid KEM when
// the deployment target supports it (macOS 26+).

package enum Enigma256HybridError: Error, Equatable {
    case unavailable
    case invalidPublicKey
    case invalidCiphertext
    case peerMismatch
    case burned
}

package enum Enigma256KEMSuite: UInt8, Sendable {
    /// Classical only (legacy wire HELLO/ACK).
    case x25519 = 1
    /// Explicit concat: X25519 ‖ ML-KEM-768 → HKDF-SHA512.
    case x25519MLKEM768 = 2
    /// CryptoKit X-Wing hybrid KEM → HKDF-SHA512.
    case xwingMLKEM768X25519 = 3
}

/// Expand concatenated (or hybrid-KEM) shared secrets into day-key IKM.
package enum Enigma256HybridKDF {
    package static let hybridInfo = Data("enigma256-hybrid-v1".utf8)
    package static let xwingInfo = Data("enigma256-xwing-v1".utf8)
    package static let defaultIKMLength = 64

    package static func deriveIKM(
        concatenatedSecrets: Data,
        salt: Data,
        info: Data = hybridInfo,
        outputByteCount: Int = defaultIKMLength
    ) -> Data {
        Enigma256KDF.hkdf(
            ikm: concatenatedSecrets,
            salt: salt,
            info: info,
            length: outputByteCount
        )
    }

    package static func symmetricKeyBytes(_ key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }
}

// MARK: - Explicit X25519 ‖ ML-KEM-768

/// Ephemeral hybrid identity: X25519 + ML-KEM-768 keypairs.
@available(macOS 26.0, *)
package final class Enigma256HybridEphemeral: @unchecked Sendable {
    package let x25519: Enigma256EphemeralIdentity
    private var mlkemPrivate: MLKEM768.PrivateKey?
    package let mlkemPublicRaw: Data

    package init() throws {
        self.x25519 = Enigma256EphemeralIdentity()
        let sk = try MLKEM768.PrivateKey.generate()
        self.mlkemPrivate = sk
        self.mlkemPublicRaw = sk.publicKey.rawRepresentation
    }

    package var publicBlob: Data {
        var out = x25519.publicKeyRaw
        out.append(mlkemPublicRaw)
        return out
    }

    /// Initiator: ECDH with peer X25519 + encapsulate to peer ML-KEM.
    package func initiate(
        peerX25519Public: Data,
        peerMLKEMPublic: Data,
        salt: Data
    ) throws -> (ikm: Data, ciphertext: Data) {
        let xSS = try x25519.sharedSecretRaw(peerPublicKeyRaw: peerX25519Public)
        let peerKEM = try MLKEM768.PublicKey(rawRepresentation: peerMLKEMPublic)
        let enc = try peerKEM.encapsulate()
        let mlSS = Enigma256HybridKDF.symmetricKeyBytes(enc.sharedSecret)
        var concat = xSS
        concat.append(mlSS)
        let ikm = Enigma256HybridKDF.deriveIKM(concatenatedSecrets: concat, salt: salt)
        return (ikm, enc.encapsulated)
    }

    /// Responder: ECDH with peer X25519 + decapsulate initiator ciphertext.
    package func respond(
        peerX25519Public: Data,
        ciphertext: Data,
        salt: Data
    ) throws -> Data {
        guard let mlkemPrivate else { throw Enigma256HybridError.burned }
        let xSS = try x25519.sharedSecretRaw(peerPublicKeyRaw: peerX25519Public)
        let mlSS: Data
        do {
            mlSS = Enigma256HybridKDF.symmetricKeyBytes(try mlkemPrivate.decapsulate(ciphertext))
        } catch {
            throw Enigma256HybridError.invalidCiphertext
        }
        var concat = xSS
        concat.append(mlSS)
        return Enigma256HybridKDF.deriveIKM(concatenatedSecrets: concat, salt: salt)
    }

    package func burn() {
        x25519.burn()
        mlkemPrivate = nil
    }

    package var isBurned: Bool { x25519.isBurned || mlkemPrivate == nil }
}

@available(macOS 26.0, *)
package enum Enigma256HybridHandshake {
    /// Alice initiates (encapsulates); Bob responds (decapsulates). Same IKM both sides.
    package static func paired(salt: Data = Data()) throws -> (
        alice: Enigma256SecureChannel,
        bob: Enigma256SecureChannel
    ) {
        let aliceId = try Enigma256HybridEphemeral()
        let bobId = try Enigma256HybridEphemeral()

        let (ikm, ct) = try aliceId.initiate(
            peerX25519Public: bobId.x25519.publicKeyRaw,
            peerMLKEMPublic: bobId.mlkemPublicRaw,
            salt: salt
        )
        let bobIKM = try bobId.respond(
            peerX25519Public: aliceId.x25519.publicKeyRaw,
            ciphertext: ct,
            salt: salt
        )
        guard ikm == bobIKM else { throw Enigma256HybridError.peerMismatch }

        let aliceCtx = Enigma256Context(ikm: ikm, salt: salt)
        let bobCtx = Enigma256Context(ikm: bobIKM, salt: salt)
        let alice = Enigma256SecureChannel(
            context: aliceCtx,
            local: aliceId.x25519,
            peerPublicKeyRaw: bobId.x25519.publicKeyRaw,
            salt: salt
        )
        let bob = Enigma256SecureChannel(
            context: bobCtx,
            local: bobId.x25519,
            peerPublicKeyRaw: aliceId.x25519.publicKeyRaw,
            salt: salt
        )
        return (alice, bob)
    }
}

// MARK: - X-Wing (combined hybrid KEM)

@available(macOS 26.0, *)
package final class Enigma256XWingEphemeral: @unchecked Sendable {
    private var privateKey: XWingMLKEM768X25519.PrivateKey?
    package let publicKeyRaw: Data

    package init() throws {
        let sk = try XWingMLKEM768X25519.PrivateKey.generate()
        self.privateKey = sk
        self.publicKeyRaw = sk.publicKey.rawRepresentation
    }

    package func encapsulate(to peerPublicRaw: Data, salt: Data) throws -> (ikm: Data, ciphertext: Data) {
        let peer = try XWingMLKEM768X25519.PublicKey(rawRepresentation: peerPublicRaw)
        let enc = try peer.encapsulate()
        let ss = Enigma256HybridKDF.symmetricKeyBytes(enc.sharedSecret)
        let ikm = Enigma256HybridKDF.deriveIKM(
            concatenatedSecrets: ss,
            salt: salt,
            info: Enigma256HybridKDF.xwingInfo
        )
        return (ikm, enc.encapsulated)
    }

    package func decapsulate(_ ciphertext: Data, salt: Data) throws -> Data {
        guard let privateKey else { throw Enigma256HybridError.burned }
        let ss: Data
        do {
            ss = Enigma256HybridKDF.symmetricKeyBytes(try privateKey.decapsulate(ciphertext))
        } catch {
            throw Enigma256HybridError.invalidCiphertext
        }
        return Enigma256HybridKDF.deriveIKM(
            concatenatedSecrets: ss,
            salt: salt,
            info: Enigma256HybridKDF.xwingInfo
        )
    }

    package func burn() {
        privateKey = nil
    }
}

@available(macOS 26.0, *)
package enum Enigma256XWingHandshake {
    /// Responder holds X-Wing key; initiator encapsulates. Same IKM both sides.
    package static func paired(salt: Data = Data()) throws -> (initiatorIKM: Data, responderIKM: Data) {
        let responder = try Enigma256XWingEphemeral()
        let (ikm, ct) = try Enigma256XWingEphemeral().encapsulate(
            to: responder.publicKeyRaw,
            salt: salt
        )
        let bobIKM = try responder.decapsulate(ct, salt: salt)
        guard ikm == bobIKM else { throw Enigma256HybridError.peerMismatch }
        return (ikm, bobIKM)
    }
}
