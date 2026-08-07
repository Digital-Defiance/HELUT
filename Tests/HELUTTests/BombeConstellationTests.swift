import Foundation
import XCTest
@testable import HELUTCore
@testable import HELUTToolKit

final class BombeConstellationTests: XCTestCase {
    private let ciphertext = EnigmaAlphabet.normalize(ControlMessageP1030684.ciphertext)
    private let plaintext = EnigmaAlphabet.normalize(ControlMessageP1030684.plaintext)

    private var truth: (Int, Int, Int, Int) {
        EnigmaM4Key.positions(fromLetters: ControlMessageP1030684.positions)
    }

    private func anchor(_ range: Range<Int>) -> (text: String, offset: Int) {
        (EnigmaAlphabet.string(from: Array(plaintext[range])), range.lowerBound)
    }

    func testBuilderKeepsIndependentAnchorsSeparateAndBuildsAbsoluteSteps() throws {
        let menu = try BombeMenuBuilder.constellation(
            anchors: [anchor(0..<8), anchor(30..<38)], ciphertext: ciphertext
        )
        XCTAssertEqual(menu.anchors.count, 2)
        XCTAssertEqual(menu.anchors.map(\.offset), [0, 30])
        XCTAssertEqual(menu.steps, Array(0..<8) + Array(30..<38))
        XCTAssertEqual(menu.coveredPlaintextIndices, Array(0..<8) + Array(30..<38))
        XCTAssertEqual(menu.constraintCount, 16)
        XCTAssertEqual(menu.stepHorizon, 38)
        XCTAssertEqual(menu.lastCoveredEnd, 38)
        XCTAssertTrue(menu.description.contains(" + "))
        XCTAssertEqual(menu.constraints.count, 16)
    }

    func testTrueSettingSurvivesTwoAnchorConstellation() throws {
        let menu = try BombeMenuBuilder.constellation(
            anchors: [anchor(0..<8), anchor(30..<38)], ciphertext: ciphertext
        )
        let bombe = ControlMessageP1030684.bombe()
        let stops = bombe.test(menu: menu, start: truth)
        XCTAssertFalse(stops.isEmpty, "joint menu killed the true setting")
        let trueStecker = ControlMessageP1030684.trueStecker
        XCTAssertNotNil(stops.first { stop in
            (0..<26).allSatisfy {
                !stop.determined[$0] || stop.stecker[$0] == trueStecker[$0]
            }
        })

        let scramblers = bombe.scramblers(menu: menu, start: truth)
        let completions = PostBombeDiscriminator.completedSteckers(
            menu: menu, scramblers: scramblers, maxPlugs: 10
        )
        XCTAssertFalse(completions.isEmpty, "joint menu has no physical completion at truth")
    }

    func testAnchorExactnessIsConjunctiveAndIdentifiesWrongAnchor() throws {
        let menu = try BombeMenuBuilder.constellation(
            anchors: [anchor(0..<8), anchor(30..<38)], ciphertext: ciphertext
        )
        XCTAssertEqual(
            PostBombeDiscriminator.anchorMatches(plain: plaintext, menu: menu),
            [true, true]
        )
        var wrongSecond = plaintext
        wrongSecond[34] = (wrongSecond[34] + 1) % 26
        XCTAssertEqual(
            PostBombeDiscriminator.anchorMatches(plain: wrongSecond, menu: menu),
            [true, false]
        )
        var wrongFirst = plaintext
        wrongFirst[4] = (wrongFirst[4] + 1) % 26
        XCTAssertEqual(
            PostBombeDiscriminator.anchorMatches(plain: wrongFirst, menu: menu),
            [false, true]
        )
    }

    func testBuilderRejectsOverlapOutOfRangeSelfEnciphermentAndOverCap() throws {
        XCTAssertThrowsError(try BombeMenuBuilder.constellation(
            anchors: [anchor(0..<8), anchor(7..<15)], ciphertext: ciphertext
        )) { error in
            guard case BombeMenuBuildError.overlappingAnchors = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
        XCTAssertThrowsError(try BombeMenuBuilder.constellation(
            anchors: [("ABCDEFGH", -1), anchor(30..<38)], ciphertext: ciphertext
        ))
        let selfText = EnigmaAlphabet.string(from: Array(ciphertext[0..<8]))
        XCTAssertThrowsError(try BombeMenuBuilder.constellation(
            anchors: [(selfText, 0), anchor(30..<38)], ciphertext: ciphertext
        )) { error in
            guard case BombeMenuBuildError.selfEncipherment = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
        XCTAssertNoThrow(try BombeMenuBuilder.constellation(
            anchors: [anchor(0..<20), anchor(40..<60)],
            ciphertext: ciphertext,
            maximumEdges: 40
        ))
        XCTAssertThrowsError(try BombeMenuBuilder.constellation(
            anchors: [anchor(0..<20), anchor(40..<61)],
            ciphertext: ciphertext,
            maximumEdges: 40
        )) { error in
            XCTAssertEqual(error as? BombeMenuBuildError, .tooManyEdges(actual: 41, maximum: 40))
        }
    }

    func testConstellationTailDoesNotInventAdjacencyAcrossAnchors() throws {
        let menu = try BombeMenuBuilder.constellation(
            anchors: [anchor(2..<5), anchor(10..<12)], ciphertext: ciphertext
        )
        let observed = PostBombeDiscriminator.tailScore(plain: plaintext, menu: menu)
        let covered = Set([2, 3, 4, 10, 11])
        var runs: [[Int]] = [], run: [Int] = []
        for index in plaintext.indices {
            if covered.contains(index) {
                if !run.isEmpty { runs.append(run); run = [] }
            } else { run.append(plaintext[index]) }
        }
        if !run.isEmpty { runs.append(run) }
        var total = 0.0, windows = 0
        for run in runs where run.count >= 3 {
            total += GermanTrigrams.score(run) * Double(run.count - 2)
            windows += run.count - 2
        }
        XCTAssertEqual(observed, total / Double(windows), accuracy: 1e-12)

        // The legacy one-anchor path keeps its historical concatenating statistic unchanged.
        let legacy = try XCTUnwrap(BombeMenuBuilder.menu(
            crib: anchor(2..<5).text, offset: 2, ciphertext: ciphertext
        ))
        let legacyTail = plaintext.indices.filter { !legacy.coveredPlaintextIndices.contains($0) }
            .map { plaintext[$0] }
        XCTAssertEqual(
            PostBombeDiscriminator.tailScore(plain: plaintext, menu: legacy),
            GermanTrigrams.score(legacyTail),
            accuracy: 1e-12
        )
    }

    func testPackingPreservesSeparatedStepsAndFailsBeforeNarrowing() throws {
        let menu = try BombeMenuBuilder.constellation(
            anchors: [anchor(0..<8), anchor(30..<38)], ciphertext: ciphertext
        )
        let packed = try packWelchmanMenu(menu)
        XCTAssertEqual(packed.edgeStep, (Array(0..<8) + Array(30..<38)).map(UInt8.init))
        XCTAssertEqual(packed.edgeA.count, 16)
        XCTAssertEqual(packed.edgeB.count, 16)

        let overstep = try XCTUnwrap(BombeMenuBuilder.assemble(
            crib: "AB", offset: 0, steps: [0, 256], ends: [(0, 1), (1, 2)]
        ))
        XCTAssertThrowsError(try packWelchmanMenu(overstep)) { error in
            XCTAssertEqual(
                error as? WelchmanMenuPackingError,
                .stepOutOfRange(edge: 1, step: 256)
            )
        }
    }

    func testLegacyMenuRetainsOneAnchorAndOriginalGeometry() throws {
        let text = anchor(0..<16).text
        let menu = try XCTUnwrap(BombeMenuBuilder.menu(
            crib: text, offset: 0, ciphertext: ciphertext
        ))
        XCTAssertEqual(menu.anchors, [BombeMenuAnchor(text: text, offset: 0)])
        XCTAssertEqual(menu.steps, Array(0..<16))
        XCTAssertEqual(menu.constraintCount, menu.edgeCount)
        XCTAssertEqual(menu.stepHorizon, 16)
        XCTAssertEqual(menu.anchorSummary, "\(text)@0")
    }

    func testConstellationFixtureLoadsAtomicallyAndRebuildsEndpoints() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("helut-constellation-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let payload: [String: Any] = [
            "schemaVersion": 2,
            "target": "P1030684",
            "ciphertext": EnigmaAlphabet.string(from: ciphertext),
            "cribs": [],
            "constellations": [[
                "id": "control-two-anchor",
                "anchors": [
                    ["text": anchor(0..<8).text, "offset": 0],
                    ["text": anchor(30..<38).text, "offset": 30],
                ],
            ]],
        ]
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
            .write(to: url)
        let loaded = try XCTUnwrap(loadCribMenus(path: url.path))
        XCTAssertEqual(loaded.menus.count, 1)
        let menu = loaded.menus[0]
        XCTAssertEqual(menu.anchors.count, 2)
        for index in menu.steps.indices {
            XCTAssertEqual(menu.ends[index].1, ciphertext[menu.steps[index]])
        }
    }
}
