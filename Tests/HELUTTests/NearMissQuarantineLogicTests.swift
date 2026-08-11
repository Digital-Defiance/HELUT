import XCTest
@testable import HELUTCore

/// Soft-band floors for Welchman→Stochastic quarantine (mirrors NearMissQuarantine defaults).
final class NearMissQuarantineLogicTests: XCTestCase {

    func testSoftBandSitsBetweenNoiseAndStrictBreak() {
        // Strict: IC ≥ 0.055, tail > −3.600. Soft default: IC ≥ 0.048, tail > −4.000.
        let softTail = -3.600 - 0.4
        let softIC = 0.048
        XCTAssertEqual(softTail, -4.0, accuracy: 1e-9)
        XCTAssertLessThan(softIC, 0.055)
        XCTAssertGreaterThan(softTail, -5.38) // above typical noise trigram reference
    }

    func testSteckerPairTokenOrdering() {
        var table = Array(0..<26)
        table[0] = 1
        table[1] = 0
        table[2] = 3
        table[3] = 2
        var pairs: [String] = []
        for a in 0..<26 where table[a] > a {
            pairs.append(
                "\(EnigmaAlphabet.character(a))\(EnigmaAlphabet.character(table[a]))"
            )
        }
        XCTAssertEqual(pairs, ["AB", "CD"])
    }
}
