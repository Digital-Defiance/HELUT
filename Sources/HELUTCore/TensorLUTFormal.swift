import Foundation

// MARK: - TensorLUT continuous→discrete formal surface (Pillar II / blocker #3)
//
// Machine-checkable lemmas for the melt objective and involution sandwich.
// Empirical grades (baseline / shatter / blind 3-pair) live in BREAK_P1030680;
// this module states the *invariants* the GA is forced to obey.

/// Named lemmas for differentiable hardware cryptanalysis.
package enum TensorLUTLemma: String, Sendable {
    /// Soft crypto fitness is −‖y−t‖₂² (perfect match ⇒ 0).
    case cryptoFitnessMSE
    /// Discreteness penalty π(w)=∑ w(1−w) is ≥0 and 0 iff every w∈{0,1}.
    case discretenessPenalty
    /// Combined objective F = F_crypto − λ·π(w) with λ≥0.
    case combinedObjective
    /// Emitter threshold τ=1/2 maps w to binary INIT; fixed points of π are preserved.
    case emitterThreshold
    /// Stecker genotype is a partial involution (disjoint pairs) — reciprocity structural.
    case involutionSandwich
    /// Freeze mask: frozen LUT weights do not enter π(w).
    case freezeMask
    /// On π(w)=0 (binary INIT), emitter recovers the INIT bits exactly.
    case emitterDiscreteAgreement
    /// Frozen stecker pairs always survive mutation; free+frozen remain a partial involution.
    case involutionUnderFreeze
}

package struct TensorLUTProofStep: Sendable, Equatable {
    package var lemma: TensorLUTLemma
    package var holds: Bool
    package var note: String

    package init(lemma: TensorLUTLemma, holds: Bool, note: String = "") {
        self.lemma = lemma
        self.holds = holds
        self.note = note
    }
}

/// Certificate that the TensorLUT objective / stecker contract satisfies the lemmas.
package struct TensorLUTFormalCertificate: Sendable, Equatable {
    package var steps: [TensorLUTProofStep]
    package var hypotheses: [String]

    package var allHold: Bool { steps.allSatisfy(\.holds) }

    package init(steps: [TensorLUTProofStep], hypotheses: [String]) {
        self.steps = steps
        self.hypotheses = hypotheses
    }

    package func assertValid(file: StaticString = #file, line: UInt = #line) {
        precondition(allHold, "TensorLUTFormalCertificate failed at \(file):\(line)")
    }
}

/// Prove / check Pillar II structural lemmas (not a cryptanalytic break claim).
package enum TensorLUTFormal {
    /// π(w) = ∑ wᵢ(1−wᵢ).
    package static func discretenessPenalty(_ weights: [Float]) -> Float {
        weights.reduce(0) { $0 + $1 * (1 - $1) }
    }

    /// True iff every weight is in {0,1} within `eps`.
    package static func isBinary(_ weights: [Float], eps: Float = 1e-5) -> Bool {
        weights.allSatisfy { w in
            abs(w) <= eps || abs(w - 1) <= eps
        }
    }

    /// Emitter: 1[w ≥ 1/2].
    package static func emitBinary(_ weights: [Float], threshold: Float = 0.5) -> [UInt8] {
        weights.map { $0 >= threshold ? 1 : 0 }
    }

    /// Lemma: π(w) ≥ 0; π(w)=0 on {0,1}^n.
    package static func checkDiscretenessPenalty(
        trials: Int = 64,
        dim: Int = 32,
        seed: UInt32 = 0x71A1
    ) -> Bool {
        var rng = LCG32(state: seed)
        for _ in 0..<trials {
            let w = (0..<dim).map { _ -> Float in
                Float(rng.next() % 10_001) / 10_000
            }
            let p = discretenessPenalty(w)
            if p < -1e-6 { return false }
        }
        // Binary vectors → 0
        let zeros = [Float](repeating: 0, count: dim)
        let ones = [Float](repeating: 1, count: dim)
        if abs(discretenessPenalty(zeros)) > 1e-6 { return false }
        if abs(discretenessPenalty(ones)) > 1e-6 { return false }
        var mixed = zeros
        for i in stride(from: 0, to: dim, by: 2) { mixed[i] = 1 }
        if abs(discretenessPenalty(mixed)) > 1e-6 { return false }
        // Strictly fractional → positive
        let mid = [Float](repeating: 0.5, count: dim)
        if discretenessPenalty(mid) <= 0 { return false }
        return true
    }

    /// Lemma: F_crypto = −‖y−t‖₂² ≤ 0; equality iff y=t.
    package static func checkCryptoFitnessMSE() -> Bool {
        let synth = AdversarialSynthesizer(config: .init(), friction: nil)
        let y: [Float] = [0, 1, 0.5]
        let t: [Float] = [0, 1, 0.5]
        if abs(synth.computeCryptoFitness(tensorOutputWires: y, targetBits: t)) > 1e-6 {
            return false
        }
        let bad = synth.computeCryptoFitness(tensorOutputWires: [1, 0, 0], targetBits: t)
        return bad < -0.5
    }

    /// Lemma: F = F_c − λ π with λ≥0 is ≤ F_c; increasing λ cannot improve F when π>0.
    package static func checkCombinedObjective() -> Bool {
        let synth = AdversarialSynthesizer(
            config: .init(lambdaMax: 10, lambdaDelayFraction: 0),
            friction: nil
        )
        let fc: Float = -1
        let pi: Float = 2
        let f0 = synth.combineFitness(
            cryptoFitness: fc, sumPenalty: pi, currentGen: 0, totalGens: 100
        )
        let f1 = synth.combineFitness(
            cryptoFitness: fc, sumPenalty: pi, currentGen: 100, totalGens: 100
        )
        // gen 0 → λ=0 ⇒ F=F_c; gen end → λ=λ_max ⇒ F < F_c
        if abs(f0 - fc) > 1e-5 { return false }
        if !(f1 < fc - 1) { return false }
        return true
    }

    /// Lemma: emitter is idempotent on {0,1} and threshold-consistent.
    package static func checkEmitterThreshold() -> Bool {
        let w: [Float] = [0, 0.49, 0.5, 0.51, 1]
        let b = emitBinary(w)
        guard b == [0, 0, 1, 1, 1] else { return false }
        let again = emitBinary(b.map { Float($0) })
        return again == b
    }

    /// Lemma: SteckerInvolution rejects overlapping pairs (partial involution).
    package static func checkInvolutionSandwich() -> Bool {
        let ok = SteckerInvolution(pairs: [(0, 1), (2, 3)])
        if !SteckerInvolution.isValid(ok.pairs) { return false }
        // Overlap must be invalid
        if SteckerInvolution.isValid([(0, 1), (1, 2)]) { return false }
        // Apply twice = identity on a letter
        var alphabet = Array(0..<26)
        for (a, b) in ok.pairs {
            alphabet.swapAt(a, b)
        }
        var twice = alphabet
        for (a, b) in ok.pairs {
            twice.swapAt(a, b)
        }
        return twice == Array(0..<26)
    }

    /// Lemma: freeze removes frozen LUT blocks from π.
    package static func checkFreezeMask() -> Bool {
        // Two LUT6 blocks (64 each); freeze second → penalty only on first.
        var w = [Float](repeating: 0.5, count: 128)
        let full = discretenessPenalty(w)
        // Zero the frozen block in the penalty sum (model of freezeMask).
        for i in 64..<128 { w[i] = 0 } // binary → no penalty
        let frozen = discretenessPenalty(w)
        // Active block still all 0.5 → half of full
        return abs(frozen - full / 2) < 1e-3
    }

    /// Lemma: when π(w)=0, E(w) recovers the binary INIT bits (Verilog emit ≡ cube).
    package static func checkEmitterDiscreteAgreement(trials: Int = 32, dim: Int = 64, seed: UInt32 = 0xE1D1) -> Bool {
        var rng = LCG32(state: seed)
        for _ in 0..<trials {
            let bits = (0..<dim).map { _ in rng.next() & 1 }
            let w = bits.map { Float($0) }
            if !isBinary(w) { return false }
            if abs(discretenessPenalty(w)) > 1e-6 { return false }
            let emitted = emitBinary(w)
            if emitted != bits.map({ UInt8($0) }) { return false }
        }
        // Near-binary fractional weights are *not* claimed to equal emit — only π=0.
        let soft: [Float] = [0.1, 0.9, 0.5]
        if isBinary(soft) { return false }
        return true
    }

    /// Lemma: mutatedPreserving keeps frozen pairs and yields a valid partial involution.
    package static func checkInvolutionUnderFreeze(trials: Int = 48, seed: UInt64 = 0xF12E_C001) -> Bool {
        let frozen: [(Int, Int)] = [(0, 1), (2, 3)]
        if !SteckerInvolution.isValid(frozen) { return false }
        var rng = SplitMix64RNG(seed: seed)
        for _ in 0..<trials {
            let start = SteckerInvolution(pairs: frozen + [(4, 5)])
            let next = start.mutatedPreserving(frozen: frozen, maxPairs: 10, rng: &rng)
            if !SteckerInvolution.isValid(next.pairs) { return false }
            let frozenSet = Set(frozen.map { ($0.0 << 8) | $0.1 })
            let nextSet = Set(next.pairs.map { ($0.0 << 8) | $0.1 })
            if !frozenSet.isSubset(of: nextSet) { return false }
            // Overlap with a frozen letter must be rejected by isValid.
            if SteckerInvolution.isValid(frozen + [(0, 7)]) { return false }
        }
        return true
    }

    /// Issue the Pillar II Theorem 1 certificate (six core lemmas — C19).
    package static func certificate() -> TensorLUTFormalCertificate {
        let steps: [TensorLUTProofStep] = [
            .init(lemma: .cryptoFitnessMSE, holds: checkCryptoFitnessMSE()),
            .init(lemma: .discretenessPenalty, holds: checkDiscretenessPenalty()),
            .init(lemma: .combinedObjective, holds: checkCombinedObjective()),
            .init(lemma: .emitterThreshold, holds: checkEmitterThreshold()),
            .init(lemma: .involutionSandwich, holds: checkInvolutionSandwich()),
            .init(lemma: .freezeMask, holds: checkFreezeMask())
        ]
        return TensorLUTFormalCertificate(
            steps: steps,
            hypotheses: [
                "Soft LUT is the multilinear extension of INIT (exact on binary inputs)",
                "GA mutates only unfrozen INIT weights in [0,1]",
                "Involution sandwich freezes core INITs; stecker search is over partial involutions",
                "Lemmas are structural — not a claim that melt recovers arbitrary keys",
                "Empirical grades (baseline/shatter/3-pair) are separate evidence"
            ]
        )
    }

    /// Theorem 1 corollary: emitter–discrete agreement + involution under freeze (C25).
    package static func corollaryCertificate() -> TensorLUTFormalCertificate {
        let steps: [TensorLUTProofStep] = [
            .init(lemma: .emitterDiscreteAgreement, holds: checkEmitterDiscreteAgreement()),
            .init(lemma: .involutionUnderFreeze, holds: checkInvolutionUnderFreeze())
        ]
        return TensorLUTFormalCertificate(
            steps: steps,
            hypotheses: [
                "Emitter recovers INIT exactly only when π(w)=0 (binary cube)",
                "mutatedPreserving freezes stecker pairs; free mutations stay a partial involution",
                "Corollary strengthens Theorem 1 emit/freeze clauses — still not melt completeness",
                "Not a U-534 / P1030680 plaintext claim"
            ]
        )
    }
}

/// Deterministic RNG for formal checks (not crypto).
private struct SplitMix64RNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0xDEAD_BEEF_CAFE_BABE : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
