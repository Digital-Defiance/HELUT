import CryptoKit
import Foundation
import XCTest
@testable import HELUTCore
@testable import HELUTToolKit

final class P1030684SparseControlFixtureTests: XCTestCase {
    /// Minimal dense harness for typed reference-oracle controls.
    ///
    /// The expected receipt was generated from the strict A...Z bytes by an external Python tally
    /// and independently cross-checked with Ruby. It is deliberately not derived by Swift code.
    private struct SparseControlFixture {
        let targetID: String
        let ciphertext: String
        let plaintext: String
        let expectedPlaintextSHA256: String
        let expectedSampleCount: Int
        let expectedHistogramAZ: [Int]
        let expectedOrderedICNumerator: Int
        let expectedOrderedICDenominator: Int

        static let p1030684Dense = SparseControlFixture(
            targetID: "P1030684",
            ciphertext: ControlMessageP1030684.ciphertext,
            plaintext: ControlMessageP1030684.plaintext,
            expectedPlaintextSHA256:
                "e355b691e78cd71bc1ed816e0808ab4f18aeb73376008b2a71dced197ad07145",
            expectedSampleCount: 120,
            expectedHistogramAZ: [
                3, 3, 3, 5, 13, 0, 0, 3, 16, 0, 0, 3, 1,
                11, 5, 1, 0, 9, 11, 5, 9, 6, 4, 2, 3, 4,
            ],
            expectedOrderedICNumerator: 912,
            expectedOrderedICDenominator: 14_280
        )
    }

    /// Independently audited in read-only Python and Ruby implementations.
    ///
    /// These constants are intentionally not derived from the Swift evaluator or adapters.
    private enum DenseNGramAuditReceipt {
        static let bigramIndices = [
            567, 567, 566, 540, 540, 541, 554, 225, 460, 482, 365, 30, 117, 351,
            358, 531, 290, 112, 221, 356, 491, 621, 610, 320, 227, 514, 540, 540,
            541, 554, 225, 460, 476, 209, 30, 117, 351, 358, 531, 311, 672, 586,
            388, 645, 554, 225, 460, 476, 209, 30, 117, 351, 358, 531, 289, 95,
            446, 112, 232, 649, 672, 586, 367, 95, 446, 112, 226, 472, 106, 59,
            200, 472, 112, 221, 356, 492, 649, 672, 586, 367, 95, 446, 112, 211,
            95, 446, 112, 208, 2, 59, 201, 498, 112, 221, 356, 471, 95, 446, 112,
            222, 372, 227, 507, 338, 2, 59, 204, 597, 668, 487, 498, 117, 353,
            390, 18, 486, 476, 225, 461,
        ]
        static let trigramIndices = [
            14_763, 14_762, 14_736, 14_060, 14_061, 14_074, 14_421, 5_868, 11_974,
            12_533, 9_494, 793, 3_055, 9_146, 9_319, 13_810, 7_548, 2_925, 5_764,
            9_279, 12_789, 16_158, 15_868, 8_339, 5_922, 13_384, 14_060, 14_061,
            14_074, 14_421, 5_868, 11_968, 12_377, 5_438, 793, 3_055, 9_146, 9_319,
            13_831, 8_108, 17_486, 15_260, 10_109, 16_778, 14_421, 5_868, 11_968,
            12_377, 5_438, 793, 3_055, 9_146, 9_319, 13_809, 7_531, 2_474, 11_604,
            2_936, 6_057, 16_896, 17_486, 15_239, 9_559, 2_474, 11_604, 2_930,
            5_880, 12_274, 2_763, 1_552, 5_204, 12_280, 2_925, 5_764, 9_280,
            12_817, 16_896, 17_486, 15_239, 9_559, 2_474, 11_604, 2_915, 5_503,
            2_474, 11_604, 2_912, 5_410, 59, 1_553, 5_230, 12_956, 2_925, 5_764,
            9_259, 12_263, 2_474, 11_604, 2_926, 5_780, 9_691, 5_915, 13_182,
            8_790, 59, 1_556, 5_329, 15_540, 17_387, 12_666, 12_961, 3_057, 9_178,
            10_158, 486, 12_644, 12_393, 5_869,
        ]
        static let bigramFloorWindowStarts: [Int] = []
        static let trigramFloorWindowStarts: [Int] = []
        static let bigramTotalLogProbabilityBitPattern: UInt64 = 0xc075_02db_7cf3_4e60
        static let bigramMeanLogProbabilityBitPattern: UInt64 = 0xc006_99a9_6621_ac81
        static let trigramTotalLogProbabilityBitPattern: UInt64 = 0xc074_ff34_c92f_2376
        static let trigramMeanLogProbabilityBitPattern: UInt64 = 0xc006_c6bb_6dc2_51db
    }

    func testP1030684DenseNGramTraceMatchesExternalAuditReceipt() throws {
        let fixture = SparseControlFixture.p1030684Dense
        let transcript = try denseTranscript(from: fixture)
        let validated = try MuleinSparseReferenceEvaluator.validate(transcript)
        let adjacency = MuleinSparseReferenceEvaluator.traceAdjacency(
            validated,
            orders: [2, 3]
        )
        let expectedSymbols = try fixture.plaintext.utf8.map { byte in
            try XCTUnwrap(EnigmaLetter(rawValue: Int(byte) - 65))
        }

        XCTAssertEqual(
            adjacency.eligiblePlaintext.map(\.transmittedStep),
            Array(0..<fixture.expectedSampleCount)
        )
        XCTAssertTrue(adjacency.eligiblePlaintext.allSatisfy { $0.edgeID == nil })
        XCTAssertEqual(adjacency.eligiblePlaintext.map(\.symbol), expectedSymbols)
        XCTAssertTrue(adjacency.barriers.isEmpty)
        XCTAssertEqual(
            adjacency.runs,
            [
                MuleinKnownRunTrace(
                    eligibleRange: 0..<fixture.expectedSampleCount,
                    transmittedSpan: MuleinSpan(start: 0, length: fixture.expectedSampleCount)
                ),
            ]
        )
        XCTAssertEqual(adjacency.orderTraces.map(\.order), [2, 3])

        let bigramAdjacency = try XCTUnwrap(
            adjacency.orderTraces.first { $0.order == 2 }
        )
        let trigramAdjacency = try XCTUnwrap(
            adjacency.orderTraces.first { $0.order == 3 }
        )
        XCTAssertEqual(
            DenseNGramAuditReceipt.bigramIndices.count,
            fixture.expectedSampleCount - 1
        )
        XCTAssertEqual(
            DenseNGramAuditReceipt.trigramIndices.count,
            fixture.expectedSampleCount - 2
        )
        XCTAssertEqual(bigramAdjacency.windows.count, fixture.expectedSampleCount - 1)
        XCTAssertEqual(trigramAdjacency.windows.count, fixture.expectedSampleCount - 2)

        let traces = try MuleinSparseReferenceEvaluator.evaluateNGrams(
            adjacency,
            using: [
                try MuleinGermanBigramModel(),
                try MuleinGermanTrigramModel(),
            ]
        )
        XCTAssertEqual(
            traces.map(\.modelID),
            [
                "helut-german-bigram-add-k-0.5-v1",
                "helut-german-trigram-add-k-0.5-v1",
            ]
        )
        XCTAssertEqual(traces.map(\.order), [2, 3])

        let bigramTrace = try XCTUnwrap(
            traces.first { $0.modelID == "helut-german-bigram-add-k-0.5-v1" }
        )
        let trigramTrace = try XCTUnwrap(
            traces.first { $0.modelID == "helut-german-trigram-add-k-0.5-v1" }
        )
        let trigramLogProbabilities = try XCTUnwrap(GermanTrigrams.logProbs)
        let trigramObservedEntries = try XCTUnwrap(GermanTrigrams.observedEntries)

        XCTAssertEqual(bigramTrace.windows.count, fixture.expectedSampleCount - 1)
        XCTAssertEqual(bigramTrace.normalizationCount, fixture.expectedSampleCount - 1)
        XCTAssertEqual(
            bigramTrace.windows.map(\.tableIndex),
            DenseNGramAuditReceipt.bigramIndices
        )
        XCTAssertEqual(
            bigramTrace.windows.enumerated().compactMap {
                $0.element.usedFloor ? $0.offset : nil
            },
            DenseNGramAuditReceipt.bigramFloorWindowStarts
        )
        for (windowStart, window) in bigramTrace.windows.enumerated() {
            let coordinates = Array(windowStart..<(windowStart + 2))
            let symbols = Array(expectedSymbols[windowStart..<(windowStart + 2)])
            let frozenTableIndex = DenseNGramAuditReceipt.bigramIndices[windowStart]
            let independentlyReducedIndex = symbols[0].rawValue * 26 + symbols[1].rawValue

            XCTAssertEqual(window.transmittedSteps, coordinates, "bigram window \(windowStart)")
            XCTAssertEqual(window.symbols, symbols, "bigram window \(windowStart)")
            XCTAssertEqual(window.tableIndex, frozenTableIndex, "bigram window \(windowStart)")
            XCTAssertEqual(
                frozenTableIndex,
                independentlyReducedIndex,
                "bigram window \(windowStart)"
            )
            XCTAssertEqual(
                window.logProbability,
                LanguageScorer.germanBigramLogProbs[frozenTableIndex],
                "bigram window \(windowStart)"
            )
            XCTAssertEqual(
                window.usedFloor,
                LanguageScorer.germanBigramCounts[frozenTableIndex] == 0,
                "bigram window \(windowStart)"
            )
            XCTAssertEqual(
                window.transmittedSteps,
                bigramAdjacency.windows[windowStart].transmittedSteps
            )
            XCTAssertEqual(window.symbols, bigramAdjacency.windows[windowStart].symbols)
        }

        XCTAssertEqual(trigramTrace.windows.count, fixture.expectedSampleCount - 2)
        XCTAssertEqual(trigramTrace.normalizationCount, fixture.expectedSampleCount - 2)
        XCTAssertEqual(
            trigramTrace.windows.map(\.tableIndex),
            DenseNGramAuditReceipt.trigramIndices
        )
        XCTAssertEqual(
            trigramTrace.windows.enumerated().compactMap {
                $0.element.usedFloor ? $0.offset : nil
            },
            DenseNGramAuditReceipt.trigramFloorWindowStarts
        )
        for (windowStart, window) in trigramTrace.windows.enumerated() {
            let coordinates = Array(windowStart..<(windowStart + 3))
            let symbols = Array(expectedSymbols[windowStart..<(windowStart + 3)])
            let frozenTableIndex = DenseNGramAuditReceipt.trigramIndices[windowStart]
            let independentlyReducedIndex = symbols[0].rawValue * 676
                + symbols[1].rawValue * 26
                + symbols[2].rawValue

            XCTAssertEqual(window.transmittedSteps, coordinates, "trigram window \(windowStart)")
            XCTAssertEqual(window.symbols, symbols, "trigram window \(windowStart)")
            XCTAssertEqual(window.tableIndex, frozenTableIndex, "trigram window \(windowStart)")
            XCTAssertEqual(
                frozenTableIndex,
                independentlyReducedIndex,
                "trigram window \(windowStart)"
            )
            XCTAssertEqual(
                window.logProbability,
                trigramLogProbabilities[frozenTableIndex],
                "trigram window \(windowStart)"
            )
            XCTAssertEqual(
                window.usedFloor,
                !trigramObservedEntries[frozenTableIndex],
                "trigram window \(windowStart)"
            )
            XCTAssertEqual(
                window.transmittedSteps,
                trigramAdjacency.windows[windowStart].transmittedSteps
            )
            XCTAssertEqual(window.symbols, trigramAdjacency.windows[windowStart].symbols)
        }

        XCTAssertEqual(
            bigramTrace.totalLogProbability.bitPattern,
            DenseNGramAuditReceipt.bigramTotalLogProbabilityBitPattern
        )
        let bigramMean = try XCTUnwrap(bigramTrace.meanLogProbability)
        XCTAssertEqual(
            bigramMean.bitPattern,
            DenseNGramAuditReceipt.bigramMeanLogProbabilityBitPattern
        )
        XCTAssertEqual(
            trigramTrace.totalLogProbability.bitPattern,
            DenseNGramAuditReceipt.trigramTotalLogProbabilityBitPattern
        )
        let trigramMean = try XCTUnwrap(trigramTrace.meanLogProbability)
        XCTAssertEqual(
            trigramMean.bitPattern,
            DenseNGramAuditReceipt.trigramMeanLogProbabilityBitPattern
        )
    }

    private func denseTranscript(
        from fixture: SparseControlFixture
    ) throws -> MuleinSparseTranscript {
        let ciphertextLetters = try fixture.ciphertext.utf8.map { byte in
            try XCTUnwrap(EnigmaLetter(rawValue: Int(byte) - 65))
        }
        let plaintext = try fixture.plaintext.utf8.map { byte in
            try XCTUnwrap(EnigmaLetter(rawValue: Int(byte) - 65))
        }
        let ciphertext = try XCTUnwrap(
            ciphertextLetters.count == plaintext.count ? ciphertextLetters : nil,
            "P1030684 ciphertext/plaintext lengths must match"
        )

        let receipt = MuleinHypothesisReceipt(
            id: MuleinHypothesisID(rawValue: "mulein-p1030684-dense-ic-control"),
            targetID: fixture.targetID,
            sourceID: "ControlMessageP1030684",
            cribID: "dense-ic-baseline",
            label: "dense known-plaintext IC control",
            edits: []
        )
        let coordinates = Array(plaintext.indices)
        let geometry = MuleinTranscriptGeometry(
            recordedIndexByTransmittedStep: coordinates.map(Optional.some),
            transmittedStepByRecordedIndex: coordinates.map(Optional.some)
        )
        let cells = coordinates.map { step in
            MuleinSparseTranscriptCell(
                transmittedStep: step,
                edgeID: nil,
                ciphertext: .recorded(
                    observed: ciphertext[step],
                    effective: ciphertext[step],
                    recordedIndex: step
                ),
                plaintext: .eligible(symbol: plaintext[step])
            )
        }
        return MuleinSparseTranscript(
            receipt: receipt,
            gapMembers: [],
            geometry: geometry,
            cells: cells
        )
    }

    func testP1030684DenseReferenceICMatchesExternalAuditReceipt() throws {
        let fixture = SparseControlFixture.p1030684Dense
        let transcript = try denseTranscript(from: fixture)
        let validated = try MuleinSparseReferenceEvaluator.validate(transcript)
        let trace = MuleinSparseReferenceEvaluator.accumulateIC(validated)

        XCTAssertEqual(trace.transmittedSteps, Array(0..<fixture.expectedSampleCount))
        XCTAssertEqual(trace.frequencies, fixture.expectedHistogramAZ)
        XCTAssertEqual(trace.sampleCount, fixture.expectedSampleCount)
        XCTAssertEqual(trace.coincidencePairCount, fixture.expectedOrderedICNumerator)
        XCTAssertEqual(trace.possiblePairCount, fixture.expectedOrderedICDenominator)
        XCTAssertEqual(
            trace.coincidencePairCount * 595,
            trace.possiblePairCount * 38
        )
    }

    func testP1030684DenseICAuditReceiptMatchesCanonicalPlaintext() {
        let fixture = SparseControlFixture.p1030684Dense
        let plaintextBytes = Array(fixture.plaintext.utf8)
        let ciphertextBytes = Array(fixture.ciphertext.utf8)

        XCTAssertEqual(fixture.targetID, "P1030684")
        XCTAssertTrue(plaintextBytes.allSatisfy { (65...90).contains($0) })
        XCTAssertTrue(ciphertextBytes.allSatisfy { (65...90).contains($0) })
        XCTAssertEqual(plaintextBytes.count, fixture.expectedSampleCount)
        XCTAssertEqual(ciphertextBytes.count, fixture.expectedSampleCount)

        let digest = SHA256.hash(data: Data(plaintextBytes))
            .map { String(format: "%02x", $0) }
            .joined()
        XCTAssertEqual(digest, fixture.expectedPlaintextSHA256)

        var histogram = [Int](repeating: 0, count: 26)
        for byte in plaintextBytes {
            histogram[Int(byte - 65)] += 1
        }
        XCTAssertEqual(histogram, fixture.expectedHistogramAZ)
        XCTAssertEqual(histogram.count, 26)
        XCTAssertEqual(histogram.reduce(0, +), fixture.expectedSampleCount)

        let orderedNumerator = histogram.reduce(0) { total, frequency in
            total + frequency * (frequency - 1)
        }
        let orderedDenominator = plaintextBytes.count * (plaintextBytes.count - 1)
        XCTAssertEqual(orderedNumerator, fixture.expectedOrderedICNumerator)
        XCTAssertEqual(orderedDenominator, fixture.expectedOrderedICDenominator)

        let unorderedNumerator = histogram.reduce(0) { total, frequency in
            total + frequency * (frequency - 1) / 2
        }
        let unorderedDenominator = orderedDenominator / 2
        XCTAssertEqual(unorderedNumerator * 2, orderedNumerator)
        XCTAssertEqual(unorderedDenominator * 2, orderedDenominator)
        XCTAssertEqual(orderedNumerator * 595, orderedDenominator * 38)
    }
}
