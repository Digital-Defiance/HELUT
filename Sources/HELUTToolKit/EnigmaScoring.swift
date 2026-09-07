import Foundation
import HELUTCore

/// Ranking objective for phase-2 plugboard search.
///
/// The full bigram/IC/crib attack score and trigram score have different scales, so
/// each contribution is measured in its own deterministic 72-symbol random-control
/// standard deviations. Because those controls show the components are correlated,
/// the trigram z-component is discounted by its non-shared fraction, `1 - rho`.
/// This is a ranking heuristic, not a probability or confidence.
enum EnigmaSearchObjective {
    static let modelID =
        "helut-enigma-search-n72-correlation-discounted-z-06f8694e-e08a5659-v2"
    static let attackRandomMean = -4.947650
    static let attackRandomDeviation = 0.233407
    static let attackTrigramCorrelation = 0.500650
    static let trigramWeight = 0.499350

    static var isFullyAvailable: Bool { GermanTrigrams.isLoaded }

    static var description: String {
        isFullyAvailable
            ? "correlation-discounted standardized bigram/IC/crib + trigram"
            : "standardized bigram/IC/crib fallback"
    }

    static func scoreRequiringTrigram(_ plaintext: [Int]) -> Double? {
        guard let trigram = GermanTrigrams.scoreIfLoaded(plaintext) else { return nil }
        let attack = HostM4Bombe.attackScore(plaintext: plaintext, scorer: .germanMilitary())
        let attackComponent =
            (attack - attackRandomMean) / attackRandomDeviation
        let trigramComponent =
            (trigram - GermanTrigrams.Calibration.randomMean)
            / GermanTrigrams.Calibration.randomDeviation
        return (attackComponent + trigramWeight * trigramComponent)
            / (1.0 + trigramWeight)
    }

    /// Search remains usable without the runtime fixture, but reports that it fell back.
    /// No final assessment can pass in that state.
    static func score(_ plaintext: [Int]) -> Double {
        if let combined = scoreRequiringTrigram(plaintext) { return combined }
        let attack = HostM4Bombe.attackScore(plaintext: plaintext, scorer: .germanMilitary())
        return (attack - attackRandomMean) / attackRandomDeviation
    }
}

/// Publication gate kept separate from search ranking.
///
/// The Core verdict supplies bigram calibration position, IC, and structural crib
/// evidence. This ToolKit layer additionally requires the exact frozen trigram model
/// and the conservative post-Bombe trigram threshold. Missing model evidence fails
/// closed rather than silently becoming another bigram score.
enum EnigmaFinalAssessment {
    enum Status: String, Sendable {
        case modelUnavailable = "model-unavailable"
        case rejected
        case possibleBreak = "possible-break"
    }

    struct Result: Sendable {
        let status: Status
        let coreVerdict: HostM4Bombe.BreakVerdict
        let trigramScore: Double?
        let trigramThreshold: Double
        let reason: String

        var isPossibleBreak: Bool { status == .possibleBreak }
    }

    static let trigramThreshold = PostBombeDiscriminator.breakThreshold

    static func evaluate(plaintext: [Int]) -> Result {
        evaluate(
            plaintext: plaintext,
            verifiedTrigramScore: GermanTrigrams.scoreIfLoaded(plaintext)
        )
    }

    /// Injection seam used to prove that publication fails closed when trigram
    /// evidence is unavailable. A supplied score is treated as already model-verified.
    static func evaluate(
        plaintext: [Int],
        verifiedTrigramScore: Double?
    ) -> Result {
        let core = HostM4Bombe.evaluateBreak(plaintext: plaintext)
        guard let trigram = verifiedTrigramScore else {
            return Result(
                status: .modelUnavailable,
                coreVerdict: core,
                trigramScore: nil,
                trigramThreshold: trigramThreshold,
                reason: "NO BREAK. Attested trigram model unavailable; final assessment fails closed."
            )
        }
        guard core.isPossibleBreak else {
            return Result(
                status: .rejected,
                coreVerdict: core,
                trigramScore: trigram,
                trigramThreshold: trigramThreshold,
                reason: core.reason
            )
        }
        guard trigram > trigramThreshold else {
            return Result(
                status: .rejected,
                coreVerdict: core,
                trigramScore: trigram,
                trigramThreshold: trigramThreshold,
                reason: String(
                    format: "NO BREAK. Trigram %.4f does not clear the attested %.4f threshold.",
                    trigram,
                    trigramThreshold
                )
            )
        }
        return Result(
            status: .possibleBreak,
            coreVerdict: core,
            trigramScore: trigram,
            trigramThreshold: trigramThreshold,
            reason: "*** Possible break — core bigram/IC/structure criteria and the attested "
                + "trigram threshold pass; verify Kenngruppen/Grund ***"
        )
    }
}
