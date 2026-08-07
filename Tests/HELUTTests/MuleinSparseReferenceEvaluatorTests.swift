import XCTest
@testable import HELUTCore
@testable import HELUTToolKit

final class MuleinSparseReferenceEvaluatorTests: XCTestCase {
    private let validReceiptRawID = "mulein-sparse-validator-seed"

    private func letter(_ rawValue: Int) -> EnigmaLetter {
        guard let letter = EnigmaLetter(rawValue: rawValue) else {
            preconditionFailure("invalid synthetic Enigma letter \(rawValue)")
        }
        return letter
    }

    private func receipt(rawID: String? = nil) -> MuleinHypothesisReceipt {
        MuleinHypothesisReceipt(
            id: MuleinHypothesisID(rawValue: rawID ?? validReceiptRawID),
            targetID: "synthetic",
            sourceID: "sparse-validator-tests",
            cribID: "mixed-four-cell-seed",
            label: "valid mixed topology",
            edits: [
                .missingFromRecording(
                    transmitted: MuleinSpan(start: 1, length: 1),
                    recordedBoundary: 1
                ),
            ]
        )
    }

    private func edge(
        cribIndex: Int,
        transmittedStep: Int,
        recordedIndex: Int
    ) -> MuleinEdgeID {
        MuleinEdgeID(
            sourceID: "sparse-validator-tests",
            cribID: "mixed-four-cell-seed",
            cribIndex: cribIndex,
            transmittedStep: transmittedStep,
            recordedIndex: recordedIndex
        )
    }

    /// Valid seed containing every state needed by the first topology rejection matrix:
    /// recorded/eligible, physical hole, unresolved correction, and excluded recorded edge.
    private func validSeed() -> MuleinSparseTranscript {
        let receipt = receipt()
        let member = MuleinGapMemberID(
            receiptID: receipt.id,
            transmittedSpan: MuleinSpan(start: 1, length: 1)
        )
        let geometry = MuleinTranscriptGeometry(
            recordedIndexByTransmittedStep: [0, nil, 1, 2],
            transmittedStepByRecordedIndex: [0, 2, 3]
        )
        let cells = [
            MuleinSparseTranscriptCell(
                transmittedStep: 0,
                edgeID: edge(cribIndex: 0, transmittedStep: 0, recordedIndex: 0),
                ciphertext: .recorded(
                    observed: letter(0), effective: letter(0), recordedIndex: 0
                ),
                plaintext: .eligible(symbol: letter(1))
            ),
            MuleinSparseTranscriptCell(
                transmittedStep: 1,
                edgeID: nil,
                ciphertext: .physicalHole(member: member),
                plaintext: .barrier(reason: .physicalHole(member: member))
            ),
            MuleinSparseTranscriptCell(
                transmittedStep: 2,
                edgeID: edge(cribIndex: 2, transmittedStep: 2, recordedIndex: 1),
                ciphertext: .unresolvedCorrection(observed: letter(2), recordedIndex: 1),
                plaintext: .barrier(reason: .unresolvedCorrection)
            ),
            MuleinSparseTranscriptCell(
                transmittedStep: 3,
                edgeID: edge(cribIndex: 3, transmittedStep: 3, recordedIndex: 2),
                ciphertext: .recorded(
                    observed: letter(3), effective: letter(3), recordedIndex: 2
                ),
                plaintext: .barrier(reason: .excludedEdge)
            ),
        ]
        return MuleinSparseTranscript(
            receipt: receipt,
            gapMembers: [member],
            geometry: geometry,
            cells: cells
        )
    }

    private func replacing(
        _ transcript: MuleinSparseTranscript,
        receipt: MuleinHypothesisReceipt? = nil,
        gapMembers: [MuleinGapMemberID]? = nil,
        geometry: MuleinTranscriptGeometry? = nil,
        cells: [MuleinSparseTranscriptCell]? = nil
    ) -> MuleinSparseTranscript {
        MuleinSparseTranscript(
            receipt: receipt ?? transcript.receipt,
            gapMembers: gapMembers ?? transcript.gapMembers,
            geometry: geometry ?? transcript.geometry,
            cells: cells ?? transcript.cells
        )
    }

    private func replacing(
        _ cell: MuleinSparseTranscriptCell,
        transmittedStep: Int? = nil,
        edgeID: MuleinEdgeID? = nil,
        clearEdgeID: Bool = false,
        ciphertext: MuleinCiphertextCell? = nil,
        plaintext: MuleinPlaintextCell? = nil
    ) -> MuleinSparseTranscriptCell {
        MuleinSparseTranscriptCell(
            transmittedStep: transmittedStep ?? cell.transmittedStep,
            edgeID: clearEdgeID ? nil : (edgeID ?? cell.edgeID),
            ciphertext: ciphertext ?? cell.ciphertext,
            plaintext: plaintext ?? cell.plaintext
        )
    }

    private func assertRejected(
        _ transcript: MuleinSparseTranscript,
        as expected: MuleinSparseEvaluationError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try MuleinSparseReferenceEvaluator.validate(transcript),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? MuleinSparseEvaluationError,
                expected,
                file: file,
                line: line
            )
        }
    }

    private enum AdjacencyFixtureCell {
        case eligible(Int)
        case physicalHole
        case unresolvedCorrection
        case excludedEdge

        var isPhysicalHole: Bool {
            if case .physicalHole = self { return true }
            return false
        }
    }

    /// Builds a complete synthetic transcript whose recorded/transmitted maps, gap receipts,
    /// members, and edge identities all agree with the requested physical cell sequence.
    private func adjacencyFixture(
        _ fixtureCells: [AdjacencyFixtureCell],
        rawID: String
    ) -> MuleinSparseTranscript {
        var recordedIndexByTransmittedStep: [Int?] = []
        var transmittedStepByRecordedIndex: [Int?] = []
        recordedIndexByTransmittedStep.reserveCapacity(fixtureCells.count)

        for (transmittedStep, fixtureCell) in fixtureCells.enumerated() {
            if fixtureCell.isPhysicalHole {
                recordedIndexByTransmittedStep.append(nil)
            } else {
                recordedIndexByTransmittedStep.append(transmittedStepByRecordedIndex.count)
                transmittedStepByRecordedIndex.append(transmittedStep)
            }
        }

        var holeSpans: [MuleinSpan] = []
        var cursor = 0
        while cursor < fixtureCells.count {
            guard fixtureCells[cursor].isPhysicalHole else {
                cursor += 1
                continue
            }
            let start = cursor
            repeat { cursor += 1 } while
                cursor < fixtureCells.count && fixtureCells[cursor].isPhysicalHole
            holeSpans.append(MuleinSpan(start: start, length: cursor - start))
        }

        let sourceID = "sparse-adjacency-tests"
        let cribID = "adjacency-\(rawID)"
        let receipt = MuleinHypothesisReceipt(
            id: MuleinHypothesisID(rawValue: rawID),
            targetID: "synthetic",
            sourceID: sourceID,
            cribID: cribID,
            label: "unweighted adjacency geometry",
            edits: holeSpans.map { span in
                .missingFromRecording(
                    transmitted: span,
                    recordedBoundary: recordedIndexByTransmittedStep[..<span.start]
                        .compactMap { $0 }
                        .count
                )
            }
        )
        let gapMembers = holeSpans.map {
            MuleinGapMemberID(receiptID: receipt.id, transmittedSpan: $0)
        }
        let geometry = MuleinTranscriptGeometry(
            recordedIndexByTransmittedStep: recordedIndexByTransmittedStep,
            transmittedStepByRecordedIndex: transmittedStepByRecordedIndex
        )

        let cells = fixtureCells.enumerated().map { transmittedStep, fixtureCell in
            if case .physicalHole = fixtureCell {
                guard let member = gapMembers.first(where: {
                    $0.transmittedSpan.range.contains(transmittedStep)
                }) else {
                    preconditionFailure("physical hole has no synthetic gap member")
                }
                return MuleinSparseTranscriptCell(
                    transmittedStep: transmittedStep,
                    edgeID: nil,
                    ciphertext: .physicalHole(member: member),
                    plaintext: .barrier(reason: .physicalHole(member: member))
                )
            }

            guard let recordedIndex = recordedIndexByTransmittedStep[transmittedStep] else {
                preconditionFailure("recorded synthetic cell has no recorded index")
            }
            let edgeID = MuleinEdgeID(
                sourceID: sourceID,
                cribID: cribID,
                cribIndex: transmittedStep,
                transmittedStep: transmittedStep,
                recordedIndex: recordedIndex
            )
            let observed = letter((transmittedStep + 13) % 26)

            switch fixtureCell {
            case let .eligible(rawValue):
                return MuleinSparseTranscriptCell(
                    transmittedStep: transmittedStep,
                    edgeID: edgeID,
                    ciphertext: .recorded(
                        observed: observed,
                        effective: observed,
                        recordedIndex: recordedIndex
                    ),
                    plaintext: .eligible(symbol: letter(rawValue))
                )
            case .unresolvedCorrection:
                return MuleinSparseTranscriptCell(
                    transmittedStep: transmittedStep,
                    edgeID: edgeID,
                    ciphertext: .unresolvedCorrection(
                        observed: observed,
                        recordedIndex: recordedIndex
                    ),
                    plaintext: .barrier(reason: .unresolvedCorrection)
                )
            case .excludedEdge:
                return MuleinSparseTranscriptCell(
                    transmittedStep: transmittedStep,
                    edgeID: edgeID,
                    ciphertext: .recorded(
                        observed: observed,
                        effective: observed,
                        recordedIndex: recordedIndex
                    ),
                    plaintext: .barrier(reason: .excludedEdge)
                )
            case .physicalHole:
                preconditionFailure("physical hole handled before recorded cell construction")
            }
        }

        return MuleinSparseTranscript(
            receipt: receipt,
            gapMembers: gapMembers,
            geometry: geometry,
            cells: cells
        )
    }

    private func expectedWindows(
        _ transmittedSteps: [[Int]]
    ) -> [MuleinAdjacencyWindowTrace] {
        transmittedSteps.map { steps in
            MuleinAdjacencyWindowTrace(
                transmittedSteps: steps,
                symbols: steps.map(letter)
            )
        }
    }

    func testAdjacencyDenseFiveLetterRunEmitsEveryPhysicalWindow() throws {
        let transcript = adjacencyFixture(
            [.eligible(0), .eligible(1), .eligible(2), .eligible(3), .eligible(4)],
            rawID: "mulein-adjacency-dense-five"
        )
        let validated = try MuleinSparseReferenceEvaluator.validate(transcript)
        let trace = MuleinSparseReferenceEvaluator.traceAdjacency(
            validated,
            orders: [2, 3, 4]
        )

        XCTAssertEqual(trace.eligiblePlaintext.map(\.transmittedStep), [0, 1, 2, 3, 4])
        XCTAssertEqual(trace.eligiblePlaintext.map { $0.symbol.rawValue }, [0, 1, 2, 3, 4])
        XCTAssertEqual(trace.eligiblePlaintext.map(\.edgeID), transcript.cells.map(\.edgeID))
        XCTAssertEqual(
            trace.runs,
            [
                MuleinKnownRunTrace(
                    eligibleRange: 0..<5,
                    transmittedSpan: MuleinSpan(start: 0, length: 5)
                ),
            ]
        )
        XCTAssertEqual(trace.barriers, [])
        XCTAssertEqual(trace.orderTraces.map { $0.windows.count }, [4, 3, 2])
        XCTAssertEqual(
            trace.orderTraces,
            [
                MuleinAdjacencyOrderTrace(
                    order: 2,
                    windows: expectedWindows([[0, 1], [1, 2], [2, 3], [3, 4]])
                ),
                MuleinAdjacencyOrderTrace(
                    order: 3,
                    windows: expectedWindows([[0, 1, 2], [1, 2, 3], [2, 3, 4]])
                ),
                MuleinAdjacencyOrderTrace(
                    order: 4,
                    windows: expectedWindows([[0, 1, 2, 3], [1, 2, 3, 4]])
                ),
            ]
        )
    }

    func testAdjacencySplitRunsFlushEveryBarrierAndIgnoreAdjacentBarriers() throws {
        let transcript = adjacencyFixture(
            [
                .eligible(0),
                .eligible(1),
                .physicalHole,
                .eligible(3),
                .eligible(4),
                .eligible(5),
                .unresolvedCorrection,
                .excludedEdge,
                .eligible(8),
                .eligible(9),
            ],
            rawID: "mulein-adjacency-split-runs"
        )
        let validated = try MuleinSparseReferenceEvaluator.validate(transcript)
        let trace = MuleinSparseReferenceEvaluator.traceAdjacency(
            validated,
            orders: [2, 3, 4]
        )
        let physicalMember = try XCTUnwrap(transcript.gapMembers.first)

        XCTAssertEqual(trace.eligiblePlaintext.map(\.transmittedStep), [0, 1, 3, 4, 5, 8, 9])
        XCTAssertEqual(trace.eligiblePlaintext.map { $0.symbol.rawValue }, [0, 1, 3, 4, 5, 8, 9])
        XCTAssertEqual(
            trace.runs,
            [
                MuleinKnownRunTrace(
                    eligibleRange: 0..<2,
                    transmittedSpan: MuleinSpan(start: 0, length: 2)
                ),
                MuleinKnownRunTrace(
                    eligibleRange: 2..<5,
                    transmittedSpan: MuleinSpan(start: 3, length: 3)
                ),
                MuleinKnownRunTrace(
                    eligibleRange: 5..<7,
                    transmittedSpan: MuleinSpan(start: 8, length: 2)
                ),
            ]
        )
        XCTAssertEqual(trace.barriers.map(\.transmittedStep), [2, 6, 7])
        XCTAssertEqual(
            trace.barriers.map(\.reason),
            [.physicalHole(member: physicalMember), .unresolvedCorrection, .excludedEdge]
        )
        XCTAssertEqual(trace.barriers.map { $0.edgeID != nil }, [false, true, true])
        XCTAssertEqual(trace.orderTraces.map { $0.windows.count }, [4, 1, 0])
        XCTAssertEqual(
            trace.orderTraces,
            [
                MuleinAdjacencyOrderTrace(
                    order: 2,
                    windows: expectedWindows([[0, 1], [3, 4], [4, 5], [8, 9]])
                ),
                MuleinAdjacencyOrderTrace(
                    order: 3,
                    windows: expectedWindows([[3, 4, 5]])
                ),
                MuleinAdjacencyOrderTrace(order: 4, windows: [])
            ]
        )
    }

    func testAdjacencyLeadingAndTrailingBarriersBoundOneRun() throws {
        let transcript = adjacencyFixture(
            [.physicalHole, .eligible(1), .eligible(2), .eligible(3), .excludedEdge],
            rawID: "mulein-adjacency-bounded-run"
        )
        let validated = try MuleinSparseReferenceEvaluator.validate(transcript)
        let trace = MuleinSparseReferenceEvaluator.traceAdjacency(
            validated,
            orders: [2, 3, 4]
        )
        let physicalMember = try XCTUnwrap(transcript.gapMembers.first)

        XCTAssertEqual(trace.eligiblePlaintext.map(\.transmittedStep), [1, 2, 3])
        XCTAssertEqual(trace.eligiblePlaintext.map { $0.symbol.rawValue }, [1, 2, 3])
        XCTAssertEqual(
            trace.runs,
            [
                MuleinKnownRunTrace(
                    eligibleRange: 0..<3,
                    transmittedSpan: MuleinSpan(start: 1, length: 3)
                ),
            ]
        )
        XCTAssertEqual(trace.barriers.map(\.transmittedStep), [0, 4])
        XCTAssertEqual(
            trace.barriers.map(\.reason),
            [.physicalHole(member: physicalMember), .excludedEdge]
        )
        XCTAssertEqual(trace.barriers.map { $0.edgeID != nil }, [false, true])
        XCTAssertEqual(trace.orderTraces.map { $0.windows.count }, [2, 1, 0])
        XCTAssertEqual(
            trace.orderTraces,
            [
                MuleinAdjacencyOrderTrace(
                    order: 2,
                    windows: expectedWindows([[1, 2], [2, 3]])
                ),
                MuleinAdjacencyOrderTrace(
                    order: 3,
                    windows: expectedWindows([[1, 2, 3]])
                ),
                MuleinAdjacencyOrderTrace(order: 4, windows: [])
            ]
        )
    }

    func testValidMixedSeedPassesTopologyGatekeeper() throws {
        _ = try MuleinSparseReferenceEvaluator.validate(validSeed())
    }

    func testICAccumulatorKeepsEmptyTranscriptAsExactZeroCounts() throws {
        let emptyReceipt = MuleinHypothesisReceipt(
            id: MuleinHypothesisID(rawValue: "mulein-sparse-empty"),
            targetID: "synthetic",
            sourceID: "sparse-validator-tests",
            cribID: "empty",
            label: "empty exact topology",
            edits: []
        )
        let transcript = MuleinSparseTranscript(
            receipt: emptyReceipt,
            gapMembers: [],
            geometry: MuleinTranscriptGeometry(
                recordedIndexByTransmittedStep: [],
                transmittedStepByRecordedIndex: []
            ),
            cells: []
        )

        let validated = try MuleinSparseReferenceEvaluator.validate(transcript)
        let trace = MuleinSparseReferenceEvaluator.accumulateIC(validated)

        XCTAssertEqual(trace.transmittedSteps, [])
        XCTAssertEqual(trace.frequencies, [Int](repeating: 0, count: 26))
        XCTAssertEqual(trace.sampleCount, 0)
        XCTAssertEqual(trace.coincidencePairCount, 0)
        XCTAssertEqual(trace.possiblePairCount, 0)
    }

    func testICAccumulatorKeepsSingletonAndSkipsEveryBarrier() throws {
        let validated = try MuleinSparseReferenceEvaluator.validate(validSeed())
        let trace = MuleinSparseReferenceEvaluator.accumulateIC(validated)
        var expectedFrequencies = [Int](repeating: 0, count: 26)
        expectedFrequencies[1] = 1

        XCTAssertEqual(trace.transmittedSteps, [0])
        XCTAssertEqual(trace.frequencies, expectedFrequencies)
        XCTAssertEqual(trace.sampleCount, 1)
        XCTAssertEqual(trace.coincidencePairCount, 0)
        XCTAssertEqual(trace.possiblePairCount, 0)
    }

    func testRejectsWrongCellCount() {
        let seed = validSeed()
        let subject = replacing(seed, cells: Array(seed.cells.dropLast()))

        assertRejected(subject, as: .cellCountMismatch(expected: 4, actual: 3))
    }

    func testRejectsSkippedTransmittedStep() {
        let seed = validSeed()
        var cells = seed.cells
        cells[1] = replacing(cells[1], transmittedStep: 2)

        assertRejected(
            replacing(seed, cells: cells),
            as: .unexpectedTransmittedStep(cellIndex: 1, expected: 1, actual: 2)
        )
    }

    func testRejectsDuplicateTransmittedStep() {
        let seed = validSeed()
        var cells = seed.cells
        cells[2] = replacing(cells[2], transmittedStep: 1)

        assertRejected(
            replacing(seed, cells: cells),
            as: .unexpectedTransmittedStep(cellIndex: 2, expected: 2, actual: 1)
        )
    }

    func testRejectsRegressingTransmittedStep() {
        let seed = validSeed()
        var cells = seed.cells
        cells[3] = replacing(cells[3], transmittedStep: 0)

        assertRejected(
            replacing(seed, cells: cells),
            as: .unexpectedTransmittedStep(cellIndex: 3, expected: 3, actual: 0)
        )
    }

    func testRejectsEdgeStepMismatch() {
        let seed = validSeed()
        var cells = seed.cells
        let wrongEdge = edge(cribIndex: 0, transmittedStep: 1, recordedIndex: 0)
        cells[0] = replacing(cells[0], edgeID: wrongEdge)

        assertRejected(
            replacing(seed, cells: cells),
            as: .edgeStepMismatch(cellStep: 0, edgeStep: 1)
        )
    }

    func testRejectsBidirectionalGeometryMismatch() {
        let seed = validSeed()
        let geometry = MuleinTranscriptGeometry(
            recordedIndexByTransmittedStep: [0, nil, 1, 2],
            transmittedStepByRecordedIndex: [0, 3, 3]
        )

        assertRejected(
            replacing(seed, geometry: geometry),
            as: .geometryReverseMismatch(
                transmittedStep: 2,
                recordedIndex: 1,
                reverseStep: 3
            )
        )
    }

    func testRejectsRecordedCellAtPhysicalHole() {
        let seed = validSeed()
        var cells = seed.cells
        cells[1] = replacing(
            cells[1],
            ciphertext: .recorded(
                observed: letter(0), effective: letter(0), recordedIndex: 0
            )
        )

        assertRejected(
            replacing(seed, cells: cells),
            as: .recordedCellAtPhysicalHole(transmittedStep: 1)
        )
    }

    func testRejectsPhysicalHoleAtRecordedStep() {
        let seed = validSeed()
        let member = seed.gapMembers[0]
        var cells = seed.cells
        cells[0] = replacing(cells[0], ciphertext: .physicalHole(member: member))

        assertRejected(
            replacing(seed, cells: cells),
            as: .physicalHoleAtRecordedStep(transmittedStep: 0, recordedIndex: 0)
        )
    }

    func testRejectsPhysicalHoleWithEligiblePlaintext() {
        let seed = validSeed()
        var cells = seed.cells
        cells[1] = replacing(cells[1], plaintext: .eligible(symbol: letter(0)))

        assertRejected(
            replacing(seed, cells: cells),
            as: .physicalHoleHasEligiblePlaintext(transmittedStep: 1)
        )
    }

    func testRejectsDifferentCiphertextAndPlaintextGapMembers() {
        let seed = validSeed()
        let alternate = MuleinGapMemberID(
            receiptID: seed.receipt.id,
            transmittedSpan: MuleinSpan(start: 0, length: 2)
        )
        var cells = seed.cells
        cells[1] = replacing(
            cells[1],
            plaintext: .barrier(reason: .physicalHole(member: alternate))
        )

        assertRejected(
            replacing(seed, cells: cells),
            as: .physicalHoleMemberMismatch(transmittedStep: 1)
        )
    }

    func testRejectsGapMemberFromAnotherReceipt() {
        let seed = validSeed()
        let foreignReceipt = receipt(rawID: "mulein-foreign-receipt")

        assertRejected(
            replacing(seed, receipt: foreignReceipt),
            as: .gapMemberReceiptMismatch(
                transmittedStep: 1,
                expected: foreignReceipt.id,
                actual: seed.receipt.id
            )
        )
    }

    func testRejectsUnresolvedCorrectionWithEligiblePlaintext() {
        let seed = validSeed()
        var cells = seed.cells
        cells[2] = replacing(cells[2], plaintext: .eligible(symbol: letter(0)))

        assertRejected(
            replacing(seed, cells: cells),
            as: .unresolvedCorrectionHasEligiblePlaintext(transmittedStep: 2)
        )
    }

    func testRejectsExcludedEdgeWithoutStableEdgeID() {
        let seed = validSeed()
        var cells = seed.cells
        cells[3] = replacing(cells[3], clearEdgeID: true)

        assertRejected(
            replacing(seed, cells: cells),
            as: .excludedEdgeHasNoEdgeID(transmittedStep: 3)
        )
    }
}
