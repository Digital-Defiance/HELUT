import XCTest
@testable import HELUTCore

final class MuleinFutureTests: XCTestCase {
    private let ciphertext = (0..<24).map { ($0 % 25) + 1 }

    private func evidence(crib: String = "AAAAAAAA", offset: Int = 0) -> MuleinFutureEvidence {
        MuleinFutureEvidence(
            targetID: "synthetic",
            sourceID: "future-lattice-tests",
            cribID: "crib-a",
            crib: crib,
            transmittedOffset: offset,
            ciphertext: ciphertext
        )
    }

    func testExactGeometryPreservesBothCoordinateDirections() throws {
        let future = try MuleinFutureLattice.compile(
            evidence: evidence(offset: 3), hypothesis: .exact
        )

        XCTAssertEqual(future.geometry.transmittedLength, ciphertext.count)
        XCTAssertEqual(future.geometry.recordedIndexByTransmittedStep, (0..<24).map(Optional.some))
        XCTAssertEqual(future.geometry.transmittedStepByRecordedIndex, (0..<24).map(Optional.some))
        XCTAssertEqual(future.menu.steps, Array(3..<11))
        XCTAssertEqual(future.edges.map(\.id.cribIndex), Array(0..<8))
        XCTAssertEqual(future.boardEdges.count, 8)
        XCTAssertEqual(future.receipts.first?.label, "exact")
    }

    func testMissingRecordingRetainsGapEvidenceButOmitsBoardEdges() throws {
        let edit = MuleinTranscriptEdit.missingFromRecording(
            transmitted: MuleinSpan(start: 10, length: 4),
            recordedBoundary: 10
        )
        let future = try MuleinFutureLattice.compile(
            evidence: evidence(offset: 8),
            hypothesis: MuleinFutureHypothesis(label: "lost group", edits: [edit]),
            minimumEdges: 4
        )

        XCTAssertEqual(future.geometry.transmittedLength, 28)
        XCTAssertEqual(Array(future.geometry.recordedIndexByTransmittedStep[10..<14]),
                       [nil, nil, nil, nil])
        XCTAssertEqual(future.geometry.recordedIndexByTransmittedStep[14], 10)
        XCTAssertEqual(future.edges.count, 8, "receipt keeps every crib position")
        XCTAssertEqual(future.boardEdges.count, 4, "the four unrecorded constraints are absent")
        XCTAssertEqual(future.menu.steps, [8, 9, 14, 15])
        XCTAssertEqual(future.edges.filter { !$0.isBoardConstraint }.map(\.id.cribIndex),
                       [2, 3, 4, 5])
    }

    func testEquivalentPostGapSplicesMergeReceiptsWithoutDuplicatingWork() {
        let hypotheses = [
            MuleinFutureHypothesis(
                label: "gap before head",
                edits: [.missingFromRecording(
                    transmitted: MuleinSpan(start: 0, length: 4), recordedBoundary: 0
                )]
            ),
            MuleinFutureHypothesis(
                label: "later equivalent gap",
                edits: [.missingFromRecording(
                    transmitted: MuleinSpan(start: 4, length: 4), recordedBoundary: 4
                )]
            )
        ]
        let lattice = MuleinFutureLattice.build(
            evidence: evidence(offset: 12), hypotheses: hypotheses
        )

        XCTAssertTrue(lattice.rejected.isEmpty)
        XCTAssertEqual(lattice.futures.count, 1)
        XCTAssertEqual(lattice.futures[0].receipts.count, 2)
        XCTAssertEqual(Set(lattice.futures[0].receipts.map(\.label)),
                       Set(["gap before head", "later equivalent gap"]))
        XCTAssertEqual(lattice.futures[0].menu.steps, Array(12..<20))
        XCTAssertEqual(lattice.futures[0].boardEdges.map(\.id.recordedIndex),
                       Array(8..<16).map(Optional.some))
    }

    func testExtraRecordingSkipsSymbolsWithoutAdvancingTheMachine() throws {
        let edit = MuleinTranscriptEdit.extraInRecording(
            recorded: MuleinSpan(start: 4, length: 2),
            transmittedBoundary: 4
        )
        let future = try MuleinFutureLattice.compile(
            evidence: evidence(crib: "AAAA", offset: 4),
            hypothesis: MuleinFutureHypothesis(label: "two extras", edits: [edit])
        )

        XCTAssertEqual(future.geometry.transmittedLength, 22)
        XCTAssertNil(future.geometry.transmittedStepByRecordedIndex[4])
        XCTAssertNil(future.geometry.transmittedStepByRecordedIndex[5])
        XCTAssertEqual(future.geometry.recordedIndexByTransmittedStep[4], 6)
        XCTAssertEqual(future.boardEdges.map(\.id.recordedIndex),
                       [6, 7, 8, 9].map(Optional.some))
    }

    func testReplacementAndTranspositionChangeValuesNotGeometry() throws {
        let edits: [MuleinTranscriptEdit] = [
            .transposition(
                recorded: MuleinSpan(start: 0, length: 3),
                permutation: [1, 0, 2]
            ),
            .replacement(recordedIndex: 2, observed: 3, hypothesized: 7)
        ]
        let future = try MuleinFutureLattice.compile(
            evidence: evidence(crib: "AAAA", offset: 0),
            hypothesis: MuleinFutureHypothesis(label: "swap and replace", edits: edits)
        )

        XCTAssertEqual(future.geometry.recordedIndexByTransmittedStep,
                       (0..<24).map(Optional.some))
        XCTAssertEqual(future.edges.map(\.observedCiphertext),
                       [1, 2, 3, 4].map(Optional.some))
        XCTAssertEqual(future.edges.map(\.effectiveCiphertext),
                       [2, 1, 7, 4].map(Optional.some))
        XCTAssertEqual(future.menu.ends.map(\.1), [2, 1, 7, 4])
    }

    func testInvalidHypothesisIsQuarantinedWithReason() {
        let bad = MuleinFutureHypothesis(
            label: "wrong observed symbol",
            edits: [.replacement(recordedIndex: 2, observed: 9, hypothesized: 7)]
        )
        let lattice = MuleinFutureLattice.build(evidence: evidence(), hypotheses: [bad])

        XCTAssertTrue(lattice.futures.isEmpty)
        XCTAssertEqual(lattice.rejected.count, 1)
        XCTAssertTrue(lattice.rejected[0].reason.contains("recorded evidence"))
    }

    func testHypothesisAndEdgeIDsAreStableAndRepairUsesEdgeIdentity() throws {
        let first = try MuleinFutureLattice.compile(evidence: evidence(), hypothesis: .exact)
        let second = try MuleinFutureLattice.compile(evidence: evidence(), hypothesis: .exact)

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(first.edges.map(\.id), second.edges.map(\.id))
        let repair = MuleinBoardRepairReceipt(droppedEdgeIDs: [first.boardEdges[3].id])
        XCTAssertEqual(repair.minimumDropCount, 1)
        XCTAssertEqual(repair.droppedEdgeIDs[0].cribIndex, 3)
        XCTAssertTrue(MuleinBoardRepairReceipt.exact.droppedEdgeIDs.isEmpty)
    }

    func testLeadingDeltaSixAndEightStayInsideEightyStepEnvelope() throws {
        let recording = (0..<72).map { ($0 % 25) + 1 }

        for delta in [6, 8] {
            let transmittedOffset = 64 + delta
            let envelopeEvidence = MuleinFutureEvidence(
                targetID: "synthetic",
                sourceID: "future-lattice-tests",
                cribID: "leading-delta-\(delta)",
                crib: "AAAAAAAA",
                transmittedOffset: transmittedOffset,
                ciphertext: recording
            )
            let future = try MuleinFutureLattice.compile(
                evidence: envelopeEvidence,
                hypothesis: MuleinFutureHypothesis(
                    label: "leading-delta-\(delta)",
                    edits: [.missingFromRecording(
                        transmitted: MuleinSpan(start: 0, length: delta),
                        recordedBoundary: 0
                    )]
                ),
                minimumEdges: 8
            )

            XCTAssertEqual(future.geometry.transmittedLength, 72 + delta)
            XCTAssertEqual(
                Array(future.geometry.recordedIndexByTransmittedStep.prefix(delta)),
                [Int?](repeating: nil, count: delta)
            )
            XCTAssertEqual(
                future.geometry.transmittedStepByRecordedIndex,
                Array(delta..<(72 + delta)).map(Optional.some)
            )
            XCTAssertEqual(
                future.boardEdges.map(\.id.recordedIndex),
                Array(64..<72).map(Optional.some)
            )
            XCTAssertEqual(future.menu.steps, Array(transmittedOffset..<(72 + delta)))
            XCTAssertEqual(future.menu.steps.max(), delta == 6 ? 77 : 79)
        }
    }
}

extension MuleinFutureTests {
    private func syntheticMenu(
        steps: [Int], ends: [(Int, Int)], central: Int = 0
    ) -> BombeMenu {
        let letters = Array(Set(ends.flatMap { [$0.0, $0.1] })).sorted()
        let components = ends.isEmpty ? 0 : 1
        return BombeMenu(
            crib: String(repeating: "A", count: ends.count),
            offset: 0,
            steps: steps,
            ends: ends,
            letters: letters,
            loops: ends.count - letters.count + components,
            central: central
        )
    }

    private func swapRow(_ first: Int, _ second: Int) -> [UInt8] {
        var row = (0..<26).map(UInt8.init)
        row[first] = UInt8(second)
        row[second] = UInt8(first)
        return row
    }

    func testPositiveTolerancePreservesExactCandidateWithoutRepair() throws {
        let menu = syntheticMenu(steps: [0], ends: [(0, 1)])
        let result = try XCTUnwrap(MuleinBoard.propagate(
            menu: menu,
            scramblers: [swapRow(0, 1)],
            seedLetter: 0,
            seedValue: 1,
            tolerance: 1
        ))

        XCTAssertTrue(result.exact)
        XCTAssertEqual(result.droppedEdges, [])
        XCTAssertEqual(result.pairCount, 1)
        XCTAssertEqual(result.determinedCount, 2)
    }

    func testExactBudgetFailureCanBeRepairedByOneEdge() throws {
        let menu = syntheticMenu(
            steps: [0, 1],
            ends: [(0, 2), (0, 1)]
        )
        let rows = [swapRow(1, 3), swapRow(0, 1)]

        let exact = try XCTUnwrap(MuleinBoard.propagate(
            menu: menu,
            scramblers: rows,
            seedLetter: 0,
            seedValue: 1,
            tolerance: 0,
            maxPlugs: 2,
            exactPlugs: 2
        ))
        XCTAssertEqual(exact.pairCount, 2)
        XCTAssertEqual(exact.droppedEdges, [])

        XCTAssertNil(MuleinBoard.propagate(
            menu: menu,
            scramblers: rows,
            seedLetter: 0,
            seedValue: 1,
            tolerance: 0,
            maxPlugs: 1
        ))

        let repaired = try XCTUnwrap(MuleinBoard.propagate(
            menu: menu,
            scramblers: rows,
            seedLetter: 0,
            seedValue: 1,
            tolerance: 1,
            maxPlugs: 1
        ))
        XCTAssertFalse(repaired.exact)
        XCTAssertEqual(repaired.droppedEdges, [0])
        XCTAssertEqual(repaired.pairCount, 1)
        XCTAssertEqual(repaired.determinedCount, 2)
    }

    func testToleranceIsMonotoneAndInvalidBudgetsFailClosed() {
        let menu = syntheticMenu(
            steps: [0, 1],
            ends: [(0, 2), (0, 1)]
        )
        let rows = [swapRow(1, 3), swapRow(0, 1)]

        func survivors(tolerance: Int) -> Set<Int> {
            Set((0..<26).filter { seed in
                MuleinBoard.propagate(
                    menu: menu,
                    scramblers: rows,
                    seedLetter: 0,
                    seedValue: seed,
                    tolerance: tolerance,
                    maxPlugs: 1
                ) != nil
            })
        }

        let tolerance0 = survivors(tolerance: 0)
        let tolerance1 = survivors(tolerance: 1)
        let tolerance2 = survivors(tolerance: 2)
        XCTAssertTrue(tolerance0.isSubset(of: tolerance1))
        XCTAssertTrue(tolerance1.isSubset(of: tolerance2))
        XCTAssertFalse(tolerance0.contains(1))
        XCTAssertTrue(tolerance1.contains(1))

        XCTAssertNil(MuleinBoard.propagate(
            menu: menu,
            scramblers: rows,
            seedLetter: 0,
            seedValue: 1,
            tolerance: -1
        ))
        XCTAssertNil(MuleinBoard.propagate(
            menu: menu,
            scramblers: rows,
            seedLetter: 0,
            seedValue: 1,
            tolerance: 1,
            maxPlugs: 1,
            exactPlugs: 2
        ))
    }
}
