import XCTest
@testable import HELUTCore
@testable import HELUTToolKit

final class MuleinNGramReferenceEvaluatorTests: XCTestCase {
    private struct IndexEchoModel: MuleinNGramModel {
        let modelID: String
        let order: Int
        let entryCount: Int

        func lookup(tableIndex: Int) -> MuleinNGramLookup {
            .entry(logProbability: -Double(tableIndex))
        }
    }

    private struct FixedLookupModel: MuleinNGramModel {
        let modelID: String
        let order: Int
        let entryCount: Int
        let result: MuleinNGramLookup

        func lookup(tableIndex: Int) -> MuleinNGramLookup {
            result
        }
    }

    private func letter(_ rawValue: Int) -> EnigmaLetter {
        guard let letter = EnigmaLetter(rawValue: rawValue) else {
            preconditionFailure("invalid synthetic Enigma letter \(rawValue)")
        }
        return letter
    }

    private func window(
        transmittedSteps: [Int],
        symbols: [Int]
    ) -> MuleinAdjacencyWindowTrace {
        MuleinAdjacencyWindowTrace(
            transmittedSteps: transmittedSteps,
            symbols: symbols.map(letter)
        )
    }

    private func adjacency(
        _ orderTraces: [MuleinAdjacencyOrderTrace]
    ) -> MuleinAdjacencyTrace {
        MuleinAdjacencyTrace(
            eligiblePlaintext: [],
            runs: [],
            barriers: [],
            orderTraces: orderTraces
        )
    }

    private func assertRejected(
        _ adjacency: MuleinAdjacencyTrace,
        models: [any MuleinNGramModel],
        as expected: MuleinNGramEvaluationError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try MuleinSparseReferenceEvaluator.evaluateNGrams(adjacency, using: models),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? MuleinNGramEvaluationError,
                expected,
                file: file,
                line: line
            )
        }
    }

    func testIndexEchoProvesBigEndianBase26AndExactReceipts() throws {
        let abc = window(transmittedSteps: [10, 11, 12], symbols: [0, 1, 2])
        let abcd = window(transmittedSteps: [20, 21, 22, 23], symbols: [0, 1, 2, 3])
        let zzzz = window(transmittedSteps: [30, 31, 32, 33], symbols: [25, 25, 25, 25])
        let subject = adjacency([
            MuleinAdjacencyOrderTrace(order: 3, windows: [abc]),
            MuleinAdjacencyOrderTrace(order: 4, windows: [abcd, zzzz]),
        ])
        let traces = try MuleinSparseReferenceEvaluator.evaluateNGrams(
            subject,
            using: [
                IndexEchoModel(modelID: "index-echo-3", order: 3, entryCount: 17_576),
                IndexEchoModel(modelID: "index-echo-4", order: 4, entryCount: 456_976),
            ]
        )

        XCTAssertEqual(
            traces,
            [
                MuleinNGramTrace(
                    modelID: "index-echo-3",
                    order: 3,
                    windows: [
                        MuleinNGramWindowTrace(
                            transmittedSteps: [10, 11, 12],
                            symbols: [letter(0), letter(1), letter(2)],
                            tableIndex: 28,
                            logProbability: -28.0,
                            usedFloor: false
                        ),
                    ],
                    totalLogProbability: -28.0,
                    normalizationCount: 1,
                    meanLogProbability: -28.0
                ),
                MuleinNGramTrace(
                    modelID: "index-echo-4",
                    order: 4,
                    windows: [
                        MuleinNGramWindowTrace(
                            transmittedSteps: [20, 21, 22, 23],
                            symbols: [letter(0), letter(1), letter(2), letter(3)],
                            tableIndex: 731,
                            logProbability: -731.0,
                            usedFloor: false
                        ),
                        MuleinNGramWindowTrace(
                            transmittedSteps: [30, 31, 32, 33],
                            symbols: [letter(25), letter(25), letter(25), letter(25)],
                            tableIndex: 456_975,
                            logProbability: -456_975.0,
                            usedFloor: false
                        ),
                    ],
                    totalLogProbability: -457_706.0,
                    normalizationCount: 2,
                    meanLogProbability: -228_853.0
                ),
            ]
        )
    }

    func testModelsOfSameOrderShareOneTraceWithoutSharingLookupSemantics() throws {
        let az = window(transmittedSteps: [4, 5], symbols: [0, 25])
        let subject = adjacency([
            MuleinAdjacencyOrderTrace(order: 2, windows: [az]),
        ])
        let traces = try MuleinSparseReferenceEvaluator.evaluateNGrams(
            subject,
            using: [
                IndexEchoModel(modelID: "index-echo-2", order: 2, entryCount: 676),
                FixedLookupModel(
                    modelID: "synthetic-floor-2",
                    order: 2,
                    entryCount: 676,
                    result: .floor(logProbability: -9.25)
                ),
            ]
        )

        XCTAssertEqual(traces.map(\.modelID), ["index-echo-2", "synthetic-floor-2"])
        XCTAssertEqual(traces.map { $0.windows[0].tableIndex }, [25, 25])
        XCTAssertEqual(traces.map { $0.windows[0].logProbability }, [-25.0, -9.25])
        XCTAssertEqual(traces.map { $0.windows[0].usedFloor }, [false, true])
    }

    func testOrderWithoutCompleteWindowsHasExactEmptyScore() throws {
        let subject = adjacency([
            MuleinAdjacencyOrderTrace(order: 3, windows: []),
        ])
        let traces = try MuleinSparseReferenceEvaluator.evaluateNGrams(
            subject,
            using: [
                IndexEchoModel(modelID: "empty-index-echo-3", order: 3, entryCount: 17_576),
            ]
        )
        let trace = try XCTUnwrap(traces.first)

        XCTAssertEqual(trace.windows, [])
        XCTAssertEqual(trace.totalLogProbability, 0.0)
        XCTAssertEqual(trace.normalizationCount, 0)
        XCTAssertNil(trace.meanLogProbability)
    }

    func testRejectsEmptyModelID() {
        assertRejected(
            adjacency([]),
            models: [IndexEchoModel(modelID: "", order: 2, entryCount: 676)],
            as: .emptyModelID(modelIndex: 0)
        )
    }

    func testRejectsDuplicateModelIDBeforeLookup() {
        let subject = adjacency([
            MuleinAdjacencyOrderTrace(order: 2, windows: []),
            MuleinAdjacencyOrderTrace(order: 3, windows: []),
        ])
        assertRejected(
            subject,
            models: [
                IndexEchoModel(modelID: "duplicate", order: 2, entryCount: 676),
                IndexEchoModel(modelID: "duplicate", order: 3, entryCount: 17_576),
            ],
            as: .duplicateModelID(modelID: "duplicate")
        )
    }

    func testRejectsInvalidModelOrder() {
        assertRejected(
            adjacency([]),
            models: [IndexEchoModel(modelID: "invalid-order", order: 1, entryCount: 26)],
            as: .invalidModelOrder(modelID: "invalid-order", order: 1)
        )
    }

    func testRejectsInvalidAdjacencyOrder() {
        assertRejected(
            adjacency([MuleinAdjacencyOrderTrace(order: 1, windows: [])]),
            models: [],
            as: .invalidAdjacencyOrder(orderTraceIndex: 0, order: 1)
        )
    }

    func testRejectsDuplicateAdjacencyOrder() {
        let subject = adjacency([
            MuleinAdjacencyOrderTrace(order: 3, windows: []),
            MuleinAdjacencyOrderTrace(order: 3, windows: []),
        ])
        assertRejected(
            subject,
            models: [IndexEchoModel(modelID: "index-echo-3", order: 3, entryCount: 17_576)],
            as: .duplicateAdjacencyOrder(order: 3)
        )
    }

    func testRejectsMissingAdjacencyOrderForModel() {
        assertRejected(
            adjacency([]),
            models: [IndexEchoModel(modelID: "index-echo-3", order: 3, entryCount: 17_576)],
            as: .missingAdjacencyOrder(modelID: "index-echo-3", order: 3)
        )
    }

    func testRejectsAdjacencyOrderWithoutModel() {
        let subject = adjacency([
            MuleinAdjacencyOrderTrace(order: 3, windows: []),
            MuleinAdjacencyOrderTrace(order: 4, windows: []),
        ])
        assertRejected(
            subject,
            models: [IndexEchoModel(modelID: "index-echo-3", order: 3, entryCount: 17_576)],
            as: .missingModelForAdjacencyOrder(order: 4)
        )
    }

    func testRejectsWrongModelEntryCount() {
        let subject = adjacency([
            MuleinAdjacencyOrderTrace(order: 3, windows: []),
        ])
        assertRejected(
            subject,
            models: [IndexEchoModel(modelID: "short-table", order: 3, entryCount: 17_575)],
            as: .entryCountMismatch(
                modelID: "short-table",
                order: 3,
                expected: 17_576,
                actual: 17_575
            )
        )
    }

    func testRejectsWindowWhoseCoordinatesAndSymbolsDoNotMatchOrder() {
        let malformed = window(transmittedSteps: [7, 8, 9], symbols: [0, 1])
        let subject = adjacency([
            MuleinAdjacencyOrderTrace(order: 3, windows: [malformed]),
        ])
        assertRejected(
            subject,
            models: [IndexEchoModel(modelID: "index-echo-3", order: 3, entryCount: 17_576)],
            as: .windowOrderMismatch(
                order: 3,
                windowIndex: 0,
                transmittedStepCount: 3,
                symbolCount: 2
            )
        )
    }

    func testVirtualZCapacityRejectsOrderFourteenEvenWithoutWindows() {
        let subject = adjacency([
            MuleinAdjacencyOrderTrace(order: 14, windows: []),
        ])
        assertRejected(
            subject,
            models: [IndexEchoModel(modelID: "impossible-order", order: 14, entryCount: 0)],
            as: .tableIndexSpaceOverflow(order: 14, symbolOffset: 13)
        )
    }

    func testRejectsEveryNonFiniteLookupBeforeWritingReceipt() {
        let subject = adjacency([
            MuleinAdjacencyOrderTrace(
                order: 2,
                windows: [window(transmittedSteps: [0, 1], symbols: [0, 1])]
            ),
        ])

        for value in [Double.nan, Double.infinity, -Double.infinity] {
            assertRejected(
                subject,
                models: [
                    FixedLookupModel(
                        modelID: "non-finite",
                        order: 2,
                        entryCount: 676,
                        result: .entry(logProbability: value)
                    ),
                ],
                as: .nonFiniteLogProbability(
                    modelID: "non-finite",
                    order: 2,
                    tableIndex: 1
                )
            )
        }
    }

    func testRejectsNonFiniteAggregateOfIndividuallyFiniteLookups() {
        let subject = adjacency([
            MuleinAdjacencyOrderTrace(
                order: 2,
                windows: [
                    window(transmittedSteps: [0, 1], symbols: [0, 1]),
                    window(transmittedSteps: [1, 2], symbols: [1, 2]),
                ]
            ),
        ])
        assertRejected(
            subject,
            models: [
                FixedLookupModel(
                    modelID: "finite-overflow",
                    order: 2,
                    entryCount: 676,
                    result: .entry(logProbability: Double.greatestFiniteMagnitude)
                ),
            ],
            as: .nonFiniteTotal(modelID: "finite-overflow", order: 2, windowIndex: 1)
        )
    }
}
