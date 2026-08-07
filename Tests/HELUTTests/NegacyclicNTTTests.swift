import XCTest
@testable import HELUTCore

/// Phase 2 NTT: 3-prime twisted NTT ≡ schoolbook in `Z/2^{32}Z[X]/(X^N+1)`.
final class NegacyclicNTTTests: XCTestCase {
    func testNTTMatchesSchoolbookEdgeVectors() {
        for n in [8, 16, 32, 64, 128, 256] {
            let zero = [UInt32](repeating: 0, count: n)
            var one = zero
            one[0] = 1
            var x = zero
            x[1] = 1
            let allOnes = [UInt32](repeating: 1, count: n)
            let allMax = [UInt32](repeating: UInt32.max, count: n)
            var rng = LCG32(state: UInt32(0xA11E ^ (n &* 0x9E37)))
            let randomA = (0..<n).map { _ in rng.next() }
            let randomB = (0..<n).map { _ in rng.next() }
            let cases: [(String, [UInt32], [UInt32])] = [
                ("0*0", zero, zero),
                ("0*r", zero, randomB),
                ("1*b", one, randomB),
                ("a*1", randomA, one),
                ("X*a", x, randomA),
                ("ones", allOnes, allOnes),
                ("max", allMax, randomB),
                ("rand", randomA, randomB)
            ]
            for (label, a, b) in cases {
                let school = negacyclicPolynomialMultiply(a, b)
                let ntt = NegacyclicNTT.multiply(a, b)
                XCTAssertEqual(ntt, school, "NTT \(label) N=\(n)")
            }
        }
    }

    func testNTTMatchesSchoolbookManySeeds() {
        for n in [8, 32, 64, 128] {
            for seed in 0..<16 {
                var rng = LCG32(state: UInt32(0x4E77 &+ UInt32(n &* 19) &+ UInt32(seed)))
                let a = (0..<n).map { _ in rng.next() }
                let b = (0..<n).map { _ in rng.next() }
                XCTAssertEqual(
                    NegacyclicNTT.multiply(a, b),
                    negacyclicPolynomialMultiply(a, b),
                    "NTT seed=\(seed) N=\(n)"
                )
            }
        }
    }

    func testNTTMatchesSchoolbookN1024Spot() {
        let n = 1024
        var rng = LCG32(state: 0x1024_4E77)
        let a = (0..<n).map { _ in rng.next() }
        let b = (0..<n).map { _ in rng.next() }
        XCTAssertEqual(
            NegacyclicNTT.multiply(a, b),
            negacyclicPolynomialMultiply(a, b),
            "NTT N=1024 random"
        )
        var one = [UInt32](repeating: 0, count: n)
        one[0] = 1
        XCTAssertEqual(NegacyclicNTT.multiply(a, one), a)
    }

    func testForwardInverseRoundtrip() {
        for n in [8, 64, 256] {
            for pi in 0..<NegacyclicNTT.primeCount {
                let m = NegacyclicNTT.modulus(primeIndex: pi, n: n)
                var rng = LCG32(state: UInt32(0xF00D &+ UInt32(n) &+ UInt32(pi)))
                let a = (0..<n).map { _ in rng.next() % m.p }
                let lifted = a // already < p
                let hat = NegacyclicNTT.forwardTwisted(lifted, m)
                let back = NegacyclicNTT.inverseTwisted(hat, m)
                XCTAssertEqual(back, lifted, "roundtrip p[\(pi)] N=\(n)")
            }
        }
    }

    func testCRTModulusProduct() {
        let P = NegacyclicNTT.crtModulusProduct
        XCTAssertEqual(P.hi, 0x5898000)
        XCTAssertEqual(P.lo, 0x4b90000100000001)
    }

    func testCRTRecoversSmallNegatives() {
        let cases: [(Int, UInt32)] = [
            (-6, 4294967290),
            (-1, UInt32.max),
            (0, 0),
            (1, 1),
            (8, 8)
        ]
        for n in [8, 16] {
            var residues = [
                [UInt32](repeating: 0, count: n),
                [UInt32](repeating: 0, count: n),
                [UInt32](repeating: 0, count: n)
            ]
            for (offset, want) in cases {
                for pi in 0..<3 {
                    let p = NegacyclicNTT.primes[pi]
                    residues[pi][0] = offset >= 0
                        ? UInt32(offset)
                        : p &- UInt32(-offset)
                }
                let got = NegacyclicNTT.crtToUInt32(residues, n: n)
                XCTAssertEqual(got[0], want, "CRT offset=\(offset) N=\(n)")
            }
        }
    }

    func testPrimesDivideTwoN() {
        for n in [8, 16, 32, 64, 128, 256, 512, 1024] {
            let twoN = UInt32(2 * n)
            for p in NegacyclicNTT.primes {
                XCTAssertEqual((p - 1) % twoN, 0, "2N=\(twoN) | \(p)-1")
            }
            _ = NegacyclicNTT.modulus(primeIndex: 0, n: n)
        }
    }
}
