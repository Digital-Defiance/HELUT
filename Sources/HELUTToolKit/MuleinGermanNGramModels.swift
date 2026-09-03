import HELUTCore

/// Failures while freezing a canonical German table behind the Mulein lookup boundary.
enum MuleinGermanNGramModelError: Error, Equatable, Sendable {
    case trigramFixtureUnavailable
    case tableShapeMismatch(
        modelID: String,
        expected: Int,
        logProbabilityCount: Int,
        observedEntryCount: Int
    )
    case nonFiniteTableEntry(modelID: String, tableIndex: Int)
}

/// Immutable adapter over the canonical embedded add-0.5 German bigram table.
struct MuleinGermanBigramModel: MuleinNGramModel {
    static let stableModelID = "helut-german-bigram-add-k-0.5-v1"
    static let expectedEntryCount = 676

    let modelID = stableModelID
    let order = 2
    let entryCount: Int

    private let logProbabilities: [Double]
    private let observedEntries: [Bool]

    init() throws {
        let logProbabilities = LanguageScorer.germanBigramLogProbs
        let observedEntries = LanguageScorer.germanBigramCounts.map { $0 != 0 }
        guard logProbabilities.count == Self.expectedEntryCount,
              observedEntries.count == Self.expectedEntryCount else {
            throw MuleinGermanNGramModelError.tableShapeMismatch(
                modelID: Self.stableModelID,
                expected: Self.expectedEntryCount,
                logProbabilityCount: logProbabilities.count,
                observedEntryCount: observedEntries.count
            )
        }
        if let tableIndex = logProbabilities.firstIndex(where: { !$0.isFinite }) {
            throw MuleinGermanNGramModelError.nonFiniteTableEntry(
                modelID: Self.stableModelID,
                tableIndex: tableIndex
            )
        }

        self.entryCount = logProbabilities.count
        self.logProbabilities = logProbabilities
        self.observedEntries = observedEntries
    }

    func lookup(tableIndex: Int) -> MuleinNGramLookup {
        precondition(logProbabilities.indices.contains(tableIndex))
        let logProbability = logProbabilities[tableIndex]
        return observedEntries[tableIndex]
            ? .entry(logProbability: logProbability)
            : .floor(logProbability: logProbability)
    }
}

/// Immutable adapter over the canonical fixture-backed add-0.5 German trigram table.
struct MuleinGermanTrigramModel: MuleinNGramModel {
    static let stableModelID = "helut-german-trigram-add-k-0.5-v1"
    static let expectedEntryCount = 17_576

    let modelID = stableModelID
    let order = 3
    let entryCount: Int

    private let logProbabilities: [Double]
    private let observedEntries: [Bool]

    init() throws {
        guard let logProbabilities = GermanTrigrams.logProbs,
              let observedEntries = GermanTrigrams.observedEntries else {
            throw MuleinGermanNGramModelError.trigramFixtureUnavailable
        }
        guard logProbabilities.count == Self.expectedEntryCount,
              observedEntries.count == Self.expectedEntryCount else {
            throw MuleinGermanNGramModelError.tableShapeMismatch(
                modelID: Self.stableModelID,
                expected: Self.expectedEntryCount,
                logProbabilityCount: logProbabilities.count,
                observedEntryCount: observedEntries.count
            )
        }
        if let tableIndex = logProbabilities.firstIndex(where: { !$0.isFinite }) {
            throw MuleinGermanNGramModelError.nonFiniteTableEntry(
                modelID: Self.stableModelID,
                tableIndex: tableIndex
            )
        }

        self.entryCount = logProbabilities.count
        self.logProbabilities = logProbabilities
        self.observedEntries = observedEntries
    }

    func lookup(tableIndex: Int) -> MuleinNGramLookup {
        precondition(logProbabilities.indices.contains(tableIndex))
        let logProbability = logProbabilities[tableIndex]
        return observedEntries[tableIndex]
            ? .entry(logProbability: logProbability)
            : .floor(logProbability: logProbability)
    }
}
