import XCTest
@testable import HELUTCore
@testable import HELUTToolKit

final class MuleinGermanNGramModelTests: XCTestCase {
    private func letter(_ rawValue: Int) -> EnigmaLetter {
        guard let letter = EnigmaLetter(rawValue: rawValue) else {
            preconditionFailure("invalid synthetic Enigma letter \(rawValue)")
        }
        return letter
    }

    private func adjacencyOrderTrace(
        order: Int,
        symbols: [EnigmaLetter]
    ) -> MuleinAdjacencyOrderTrace {
        guard symbols.count >= order else {
            return MuleinAdjacencyOrderTrace(order: order, windows: [])
        }
        let windows = (0...(symbols.count - order)).map { start in
            MuleinAdjacencyWindowTrace(
                transmittedSteps: Array(start..<(start + order)),
                symbols: Array(symbols[start..<(start + order)])
            )
        }
        return MuleinAdjacencyOrderTrace(order: order, windows: windows)
    }

    func testCanonicalAdaptersExposeExactShapesAndSourcePresence() throws {
        let bigram = try MuleinGermanBigramModel()
        let trigram = try MuleinGermanTrigramModel()
        let trigramLogProbabilities = try XCTUnwrap(GermanTrigrams.logProbs)
        let trigramObservedEntries = try XCTUnwrap(GermanTrigrams.observedEntries)

        XCTAssertEqual(bigram.modelID, MuleinGermanBigramModel.stableModelID)
        XCTAssertEqual(bigram.order, 2)
        XCTAssertEqual(bigram.entryCount, 676)
        XCTAssertEqual(LanguageScorer.germanBigramCounts.count, 676)
        XCTAssertEqual(LanguageScorer.germanBigramLogProbs.count, 676)

        XCTAssertEqual(trigram.modelID, MuleinGermanTrigramModel.stableModelID)
        XCTAssertEqual(trigram.order, 3)
        XCTAssertEqual(trigram.entryCount, 17_576)
        XCTAssertEqual(trigramLogProbabilities.count, 17_576)
        XCTAssertEqual(trigramObservedEntries.count, 17_576)
        XCTAssertEqual(trigramObservedEntries.filter { $0 }.count, 14_947)
        XCTAssertEqual(trigramObservedEntries.filter { !$0 }.count, 2_629)

        let aa = 0
        let aj = 9
        XCTAssertGreaterThan(LanguageScorer.germanBigramCounts[aa], 0)
        XCTAssertEqual(LanguageScorer.germanBigramCounts[aj], 0)
        XCTAssertEqual(
            bigram.lookup(tableIndex: aa),
            .entry(logProbability: LanguageScorer.germanBigramLogProbs[aa])
        )
        XCTAssertEqual(
            bigram.lookup(tableIndex: aj),
            .floor(logProbability: LanguageScorer.germanBigramLogProbs[aj])
        )

        let abc = 28
        let qzq = 11_482
        let zzz = 17_575
        XCTAssertTrue(trigramObservedEntries[abc])
        XCTAssertFalse(trigramObservedEntries[qzq])
        XCTAssertTrue(trigramObservedEntries[zzz])
        XCTAssertEqual(
            trigram.lookup(tableIndex: abc),
            .entry(logProbability: trigramLogProbabilities[abc])
        )
        XCTAssertEqual(
            trigram.lookup(tableIndex: qzq),
            .floor(logProbability: trigramLogProbabilities[qzq])
        )
        XCTAssertEqual(
            trigram.lookup(tableIndex: zzz),
            .entry(logProbability: trigramLogProbabilities[zzz])
        )
    }

    func testCanonicalAdaptersExactlyMatchLegacyDenseScores() throws {
        let rawSymbols = EnigmaAlphabet.normalize(ControlMessageP1030684.plaintext)
        let symbols = rawSymbols.map(letter)
        let trigramObservedEntries = try XCTUnwrap(GermanTrigrams.observedEntries)
        let adjacency = MuleinAdjacencyTrace(
            eligiblePlaintext: [],
            runs: [],
            barriers: [],
            orderTraces: [
                adjacencyOrderTrace(order: 2, symbols: symbols),
                adjacencyOrderTrace(order: 3, symbols: symbols),
            ]
        )
        let traces = try MuleinSparseReferenceEvaluator.evaluateNGrams(
            adjacency,
            using: [
                try MuleinGermanBigramModel(),
                try MuleinGermanTrigramModel(),
            ]
        )
        let bigramTrace = traces[0]
        let trigramTrace = traces[1]

        XCTAssertEqual(bigramTrace.windows.count, rawSymbols.count - 1)
        XCTAssertEqual(bigramTrace.normalizationCount, rawSymbols.count - 1)
        XCTAssertEqual(
            bigramTrace.meanLogProbability,
            LanguageScorer.bigramScore(rawSymbols)
        )
        let expectedBigramFloors = (0..<(rawSymbols.count - 1)).filter { index in
            let tableIndex = rawSymbols[index] * 26 + rawSymbols[index + 1]
            return LanguageScorer.germanBigramCounts[tableIndex] == 0
        }.count
        XCTAssertEqual(bigramTrace.windows.filter(\.usedFloor).count, expectedBigramFloors)

        XCTAssertEqual(trigramTrace.windows.count, rawSymbols.count - 2)
        XCTAssertEqual(trigramTrace.normalizationCount, rawSymbols.count - 2)
        XCTAssertEqual(trigramTrace.meanLogProbability, GermanTrigrams.score(rawSymbols))
        let expectedTrigramFloors = (0..<(rawSymbols.count - 2)).filter { index in
            let tableIndex = rawSymbols[index] * 676
                + rawSymbols[index + 1] * 26
                + rawSymbols[index + 2]
            return !trigramObservedEntries[tableIndex]
        }.count
        XCTAssertEqual(trigramTrace.windows.filter(\.usedFloor).count, expectedTrigramFloors)
    }
}
