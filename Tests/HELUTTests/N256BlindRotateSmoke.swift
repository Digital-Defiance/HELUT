import XCTest
@testable import HELUTCore

/// Large-N blind-rotate smokes (release config recommended).
final class N256BlindRotateSmoke: XCTestCase {
    func testArity3CarryAtDegrees() throws {
        let lutTruth = "11101000"
        let width = 3
        var table = [UInt32](repeating: 0, count: 1 << width)
        for mask in 0..<(1 << width) {
            let charIndex = lutTruth.count - 1 - mask
            let ch = lutTruth[lutTruth.index(lutTruth.startIndex, offsetBy: charIndex)]
            table[mask] = ch == "1" ? 1 : 0
        }
        for degree in [64, 128, 256, 1024] {
            let params = GGSWParams.crypto(degree: degree)
            let secret = TFHESecretKey.random(params: params.tfhe, seed: 0xA301)
            var rng = LCG32(state: 0xA302)
            let bk = bootstrapKey(secret: secret, params: params, rng: &rng)
            let twoN = 2 * degree
            let scale = rotationScale(polynomialDegree: degree)
            for a in 0...1 {
                for b in 0...1 {
                    for cin in 0...1 {
                        let bits = [UInt32(a), UInt32(b), UInt32(cin)]
                        let inputs = bits.map {
                            encryptLWERotationNative(
                                message: $0, secret: secret.lweSecret, twoN: twoN, rng: &rng
                            )
                        }
                        let out = evaluateLUTBlindRotate(
                            truthTable: table, inputs: inputs, bootstrapKey: bk, scale: scale
                        )
                        let got = decodeRotationBoolean(decryptLWE(out, secret: secret), scale: scale)
                        let want = table[a | (b << 1) | (cin << 2)]
                        XCTAssertEqual(got, want, "N=\(degree) a=\(a) b=\(b) cin=\(cin)")
                    }
                }
            }
        }
    }
}
