import CommonCrypto
import Foundation

// MARK: - Passphrase → IKM (spec §3 control plane)
//
// Apple Silicon / CryptoKit has no Argon2; we use PBKDF2-HMAC-SHA512 via
// CommonCrypto (RFC 8018). Same Enigma256Context as ECDH once IKM exists.

package enum Enigma256PassphraseError: Error, Equatable {
    case emptyPassphrase
    case derivationFailed(Int32)
}

package enum Enigma256Passphrase {
    /// Default work factor for interactive HELUT demos (raise for production offline).
    package static let defaultIterations = 210_000
    /// Match HKDF-SHA512 IKM width used by ECDH / hybrid paths.
    package static let defaultIKMLength = 64
    package static let defaultSaltLength = 16

    /// PBKDF2-HMAC-SHA512 → raw IKM bytes.
    package static func deriveIKM(
        passphrase: String,
        salt: Data,
        iterations: Int = defaultIterations,
        byteCount: Int = defaultIKMLength
    ) throws -> Data {
        guard !passphrase.isEmpty else { throw Enigma256PassphraseError.emptyPassphrase }
        precondition(iterations >= 1)
        precondition(byteCount >= 16)

        var out = [UInt8](repeating: 0, count: byteCount)
        let password = Array(passphrase.utf8)
        let status = password.withUnsafeBytes { passRaw in
            salt.withUnsafeBytes { saltRaw in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passRaw.bindMemory(to: Int8.self).baseAddress,
                    password.count,
                    saltRaw.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512),
                    UInt32(iterations),
                    &out,
                    byteCount
                )
            }
        }
        guard status == kCCSuccess else {
            throw Enigma256PassphraseError.derivationFailed(status)
        }
        return Data(out)
    }

    /// Random salt for new passphrase sessions.
    package static func randomSalt(byteCount: Int = defaultSaltLength) -> Data {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        var rng = SystemRandomNumberGenerator()
        for i in 0 ..< byteCount {
            bytes[i] = UInt8.random(in: .min ... .max, using: &rng)
        }
        return Data(bytes)
    }

    /// Day-key context from a human passphrase (salt binds the session).
    package static func openContext(
        passphrase: String,
        salt: Data,
        iterations: Int = defaultIterations
    ) throws -> Enigma256Context {
        let ikm = try deriveIKM(passphrase: passphrase, salt: salt, iterations: iterations)
        return Enigma256Context(ikm: ikm, salt: salt)
    }
}
