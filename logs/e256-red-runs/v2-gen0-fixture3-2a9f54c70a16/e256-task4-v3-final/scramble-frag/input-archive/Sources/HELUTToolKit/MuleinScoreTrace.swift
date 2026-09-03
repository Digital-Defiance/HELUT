import Foundation
import HELUTCore

/// One plaintext symbol retained by a sparse evaluation, with its physical provenance.
struct MuleinEligiblePlaintextTrace: Codable, Hashable, Sendable {
    let transmittedStep: Int
    let edgeID: MuleinEdgeID?
    let symbol: EnigmaLetter
}

/// One maximal run of eligible, physically consecutive plaintext symbols.
struct MuleinKnownRunTrace: Codable, Hashable, Sendable {
    /// Positions in the enclosing trace's `eligiblePlaintext` occupied by this run.
    let eligibleRange: Range<Int>
    let transmittedSpan: MuleinSpan
}

/// One explicit scoring boundary retained by the trace.
struct MuleinScoreBarrierTrace: Codable, Hashable, Sendable {
    let transmittedStep: Int
    let edgeID: MuleinEdgeID?
    let reason: MuleinPlaintextBarrier
}

/// One physically contiguous, unweighted n-gram window.
struct MuleinAdjacencyWindowTrace: Codable, Hashable, Sendable {
    let transmittedSteps: [Int]
    let symbols: [EnigmaLetter]
}

/// Every unweighted window emitted for one requested order.
struct MuleinAdjacencyOrderTrace: Codable, Hashable, Sendable {
    let order: Int
    let windows: [MuleinAdjacencyWindowTrace]
}

/// Complete geometry receipt produced before any table index or language weight exists.
struct MuleinAdjacencyTrace: Codable, Hashable, Sendable {
    let eligiblePlaintext: [MuleinEligiblePlaintextTrace]
    let runs: [MuleinKnownRunTrace]
    let barriers: [MuleinScoreBarrierTrace]
    let orderTraces: [MuleinAdjacencyOrderTrace]
}

/// Exact count data underlying an Index of Coincidence result.
struct MuleinICTrace: Codable, Hashable, Sendable {
    /// Physical steps contributing to the histogram, in canonical ascending order.
    let transmittedSteps: [Int]
    /// Canonical A...Z frequency vector.
    let frequencies: [Int]
    let sampleCount: Int
    /// `sum(f * (f - 1))` over the frequency vector.
    let coincidencePairCount: Int
    /// `sampleCount * (sampleCount - 1)`; zero when fewer than two symbols are eligible.
    let possiblePairCount: Int
}

/// One n-gram table lookup, including the exact physical window that authorized it.
struct MuleinNGramWindowTrace: Codable, Hashable, Sendable {
    let transmittedSteps: [Int]
    let symbols: [EnigmaLetter]
    let tableIndex: Int
    let logProbability: Double
    let usedFloor: Bool
}

/// Ordered contributions from one fixed-order language model.
struct MuleinNGramTrace: Codable, Hashable, Sendable {
    let modelID: String
    let order: Int
    let windows: [MuleinNGramWindowTrace]
    let totalLogProbability: Double
    let normalizationCount: Int
    /// Nil when no complete window is eligible.
    let meanLogProbability: Double?
}

/// Full differential receipt shared by the typed reference oracle and compiled evaluator.
///
/// This is intentionally not part of the campaign JSONL schema. The optimized production path may
/// retain a smaller receipt after trace-level parity has been established by the control suite.
struct MuleinSparseScoreTrace: Codable, Hashable, Sendable {
    let receiptID: MuleinHypothesisID
    let gapMembers: [MuleinGapMemberID]
    let eligiblePlaintext: [MuleinEligiblePlaintextTrace]
    let runs: [MuleinKnownRunTrace]
    let barriers: [MuleinScoreBarrierTrace]
    let ic: MuleinICTrace
    let ngrams: [MuleinNGramTrace]
}
