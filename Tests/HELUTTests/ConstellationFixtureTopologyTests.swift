import Foundation
import XCTest
@testable import HELUTCore
@testable import HELUTToolKit

/// The constellation fixtures carry a `selectionReceipt` written by
/// `Scripts/constellation_crib_generator.py`, which computes loops and components with its own
/// union-find. This suite proves the Swift board agrees with that independent implementation, so
/// a topology quoted to the campaign team (or to a collaborator) is never just the generator
/// asserting its own arithmetic.
///
/// It also pins the campaign doctrine the fixture is supposed to satisfy: single component only,
/// no anchor overlap, both anchors inside the real P1030680 ciphertext, and no evaluated setting.
final class ConstellationFixtureTopologyTests: XCTestCase {
    private struct Fixture: Decodable {
        struct Constellation: Decodable {
            struct Anchor: Decodable {
                let text: String
                let offset: Int
            }
            struct Receipt: Decodable {
                let edges: Int
                let letters: Int
                let components: Int
                let loops: Int
                let stepHorizon: Int
            }
            let id: String
            let anchors: [Anchor]
            let selectionReceipt: Receipt
        }
        let target: String
        let ciphertext: String
        let constellations: [Constellation]
    }

    private func load(_ name: String) throws -> Fixture {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Fixtures/\(name)")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Fixture.self, from: data)
    }

    func testProcedureNeustadtFixtureTopologyMatchesTheBoard() throws {
        let fixture = try load("p1030680_wenselaers_procedure_neustadt_constellations.json")
        XCTAssertEqual(fixture.target, "P1030680")

        // The fixture's ciphertext must be the real target, not a transcribed copy.
        let ciphertext = EnigmaAlphabet.normalize(fixture.ciphertext)
        XCTAssertEqual(
            ciphertext, EnigmaAlphabet.normalize(U534MessageP1030680.ciphertext),
            "fixture ciphertext drifted from the canonical P1030680 stream"
        )
        XCTAssertEqual(ciphertext.count, 72)

        XCTAssertFalse(fixture.constellations.isEmpty)
        var seen = Set<String>()
        var offsetUse: [String: Int] = [:]

        for constellation in fixture.constellations {
            XCTAssertTrue(seen.insert(constellation.id).inserted,
                          "duplicate constellation id \(constellation.id)")
            let menu = try BombeMenuBuilder.constellation(
                anchors: constellation.anchors.map { ($0.text, $0.offset) },
                ciphertext: ciphertext,
                maximumEdges: welchmanMaxEdges
            )
            let receipt = constellation.selectionReceipt

            // Independent-implementation agreement: Python union-find vs Swift board.
            XCTAssertEqual(menu.edgeCount, receipt.edges, "edges \(constellation.id)")
            XCTAssertEqual(menu.letters.count, receipt.letters, "letters \(constellation.id)")
            XCTAssertEqual(menu.components, receipt.components,
                           "components \(constellation.id)")
            XCTAssertEqual(menu.loops, receipt.loops, "loops \(constellation.id)")
            XCTAssertEqual(menu.stepHorizon, receipt.stepHorizon,
                           "stepHorizon \(constellation.id)")

            // Campaign doctrine: split menus make ghosts (Phase 4), so every shipped row is
            // one component and carries real loops.
            XCTAssertEqual(menu.components, 1, "split menu shipped: \(constellation.id)")
            XCTAssertGreaterThan(menu.loops, 0, "loopless menu: \(constellation.id)")

            // Anchors stay independent evidence: no overlap, in range, and never concatenated.
            XCTAssertEqual(menu.anchors.count, 2)
            let ranges = menu.anchors.map(\.range)
            XCTAssertFalse(ranges[0].overlaps(ranges[1]),
                           "overlapping anchors: \(constellation.id)")
            for anchor in menu.anchors {
                XCTAssertGreaterThanOrEqual(anchor.offset, 0)
                XCTAssertLessThanOrEqual(anchor.range.upperBound, ciphertext.count)
                for index in anchor.letters.indices {
                    XCTAssertNotEqual(
                        anchor.letters[index], ciphertext[anchor.offset + index],
                        "self-encipherment survived in \(constellation.id)"
                    )
                }
            }
            // Every edge endpoint is rebuilt from the root ciphertext, never from the fixture.
            for index in menu.steps.indices {
                XCTAssertEqual(menu.ends[index].1, ciphertext[menu.steps[index]])
            }
            // Metal packing must succeed for anything we intend to sweep.
            XCTAssertNoThrow(try packWelchmanMenu(menu))

            for anchor in constellation.anchors {
                offsetUse["\(anchor.text)@\(anchor.offset)", default: 0] += 1
            }
        }

        // The fixture's own selection rule: no single anchor placement is leaned on more than
        // twice, so the plan cannot be one offset wearing 24 disguises.
        for (placement, count) in offsetUse {
            XCTAssertLessThanOrEqual(count, 2, "anchor placement \(placement) reused \(count)x")
        }
    }

    func testBothAnchorStringsAreRepoVerbatimSomewhereInTheCorpus() throws {
        // The doctrine is that only attested strings get board time. Both anchors must appear
        // verbatim in the mined corpus; this fails loudly if a fixture ever ships an invented
        // sentence.
        let fixture = try load("p1030680_wenselaers_procedure_neustadt_constellations.json")
        let corpusURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Fixtures/u534_corpus.json")
        let corpus = try String(contentsOf: corpusURL, encoding: .utf8)
        let normalized = corpus.uppercased().filter { $0.isLetter }

        let texts = Set(fixture.constellations.flatMap { $0.anchors.map(\.text) })
        XCTAssertEqual(texts, ["FFFTTTBLEIBTBESETZT", "NEUSTADT"])
        for text in texts {
            XCTAssertTrue(
                normalized.contains(text),
                "anchor '\(text)' is not verbatim in u534_corpus.json — invented crib"
            )
        }
    }
}
