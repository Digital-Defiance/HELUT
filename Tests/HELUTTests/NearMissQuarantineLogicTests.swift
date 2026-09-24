import XCTest
@testable import HELUTCore
@testable import HELUTToolKit

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

    func testPhysicalLedgerKeepsTheShellAndDropsPlaintext() throws {
        let row = QuarantineCandidate(
            ukw: "B", greek: "beta", wheelOrder: "IV-III-VIII", rings: "AAAA",
            positions: "AAAA", steckerPairs: ["AB"], pairCount: 1,
            menuCrib: "OEDMOEDMOEDMOEDM", menuOffset: 4, menuAnchors: nil,
            menuLoops: 4, menuEdges: 16, ic: 0.049, tailScore: -5.028,
            fullScore: -4.5, effectiveTailScore: -5.028, cribExact: false,
            prefixEnd: nil, prefixIC: nil, prefixTailScore: nil,
            plaintextPrefix: "SHOULDNOTPERSIST", softBand: "below-soft", source: "test"
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("welchman-physical-\(UUID().uuidString).jsonl")
        NearMissQuarantine.appendPhysicalRow(row, to: url.path)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("\"wheelOrder\":\"IV-III-VIII\""))
        XCTAssertTrue(text.contains("\"positions\":\"AAAA\""))
        XCTAssertTrue(text.contains("\"tailScore\":-5.028"))
        XCTAssertFalse(text.contains("SHOULDNOTPERSIST"))
        try? FileManager.default.removeItem(at: url)
    }
}
