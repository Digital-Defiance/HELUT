import CryptoKit
import Foundation

// MARK: - Long-term Ed25519 identity (MitM binding, control plane only)
//
// Ephemeral X25519 / hybrid KEM pubs are signed with a durable identity key so
// a network adversary cannot complete separate sessions with each endpoint.
// Verification happens in software before any IKM reaches HKDF / AXI.

package enum Enigma256AuthError: Error, Equatable {
    case invalidIdentityKey
    case badSignature
    case untrustedIdentity
    case burned
}

/// Long-term Ed25519 signing identity for one node.
package final class Enigma256Identity: @unchecked Sendable {
    private var privateKey: Curve25519.Signing.PrivateKey?
    package let publicKeyRaw: Data

    package init() {
        let key = Curve25519.Signing.PrivateKey()
        self.privateKey = key
        self.publicKeyRaw = key.publicKey.rawRepresentation
    }

    package init(privateKey: Curve25519.Signing.PrivateKey) {
        self.privateKey = privateKey
        self.publicKeyRaw = privateKey.publicKey.rawRepresentation
    }

    package static func parsePublicKey(_ raw: Data) throws -> Curve25519.Signing.PublicKey {
        guard raw.count == 32 else { throw Enigma256AuthError.invalidIdentityKey }
        do {
            return try Curve25519.Signing.PublicKey(rawRepresentation: raw)
        } catch {
            throw Enigma256AuthError.invalidIdentityKey
        }
    }

    /// Sign a handshake transcript (ephemeral material + salt + role tag).
    package func sign(_ message: Data) throws -> Data {
        guard let privateKey else { throw Enigma256AuthError.burned }
        return try privateKey.signature(for: message)
    }

    package static func verify(publicKeyRaw: Data, message: Data, signature: Data) throws {
        let pk = try parsePublicKey(publicKeyRaw)
        guard pk.isValidSignature(signature, for: message) else {
            throw Enigma256AuthError.badSignature
        }
    }

    package func burn() {
        privateKey = nil
    }

    package var isBurned: Bool { privateKey == nil }
}

package enum Enigma256Transcript {
    /// Domain-separated transcript for signed HELLO / ACK payloads.
    package static func handshake(
        role: String,
        suite: UInt8,
        ephemeralBlob: Data,
        salt: Data,
        peerIdentityHint: Data = Data()
    ) -> Data {
        var out = Data("enigma256-auth-v1|".utf8)
        out.append(contentsOf: role.utf8)
        out.append(0)
        out.append(suite)
        out.append(ephemeralBlob)
        out.append(UInt8(min(salt.count, 255)))
        out.append(salt.prefix(255))
        if !peerIdentityHint.isEmpty {
            out.append(peerIdentityHint)
        }
        return out
    }
}
