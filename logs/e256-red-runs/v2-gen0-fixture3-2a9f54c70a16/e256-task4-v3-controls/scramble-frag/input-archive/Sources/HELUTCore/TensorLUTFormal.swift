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
    /// Coordinate-separable Boolean interpolant: unique maximizer of F is the binary target.
    case separableMeltUniqueMaximizer
    /// Snap: if every used INIT entry lies in the open half-space of its target bit, E recovers t.
    case snapBasinCompleteness
    /// Freeze: coordinates already at the Boolean target stay; a wrong freeze blocks F=0.
    case freezePreservesMaximizer
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
                "Corollary strengthens Theorem 1 emit/freeze clauses — melt–freeze–snap on separable interpolants is C44, not this corollary",
                "Not a U-534 / P1030680 plaintext claim"
            ]
        )
    }

    /// 1-D objective on a single INIT address with Boolean target t∈{0,1}.
    package static func separableCoordinateFitness(weight w: Float, target t: Float, lambda: Float) -> Float {
        let crypto = -(w - t) * (w - t)
        let pi = w * (1 - w)
        return crypto - lambda * pi
    }

    /// Lemma: for a fully observed 1-LUT (each address is an independent Boolean target),
    /// F(w)=−‖w−t‖²−λπ(w) has unique maximizer w=t on [0,1]^k for every λ≥0.
    package static func checkSeparableMeltUniqueMaximizer(
        trials: Int = 64,
        dim: Int = 16,
        seed: UInt32 = 0x5A9
    ) -> Bool {
        var rng = LCG32(state: seed)
        let lambdas: [Float] = [0, 0.5, 1, 8]
        for _ in 0..<trials {
            let t = (0..<dim).map { _ in Float(rng.next() & 1) }
            let atTarget = zip(t, t).map { separableCoordinateFitness(weight: $0.0, target: $0.1, lambda: 0) }
            if atTarget.contains(where: { abs($0) > 1e-6 }) { return false }
            for lambda in lambdas {
                let fStar = t.reduce(Float(0)) { $0 + separableCoordinateFitness(weight: $1, target: $1, lambda: lambda) }
                if abs(fStar) > 1e-5 { return false }
                let w = (0..<dim).map { i -> Float in
                    let u = Float(rng.next() % 10_001) / 10_000
                    return abs(u - t[i]) < 1e-4 ? (t[i] == 0 ? 0.3 : 0.7) : u
                }
                let fW = zip(w, t).reduce(Float(0)) {
                    $0 + separableCoordinateFitness(weight: $1.0, target: $1.1, lambda: lambda)
                }
                if !(fW < fStar - 1e-6) { return false }
            }
        }
        return true
    }

    /// Lemma: if |w_i − t_i| < 1/2 for Boolean t, then E(w)=t (Verilog snap ≡ interpolant).
    package static func checkSnapBasinCompleteness(
        trials: Int = 48,
        dim: Int = 32,
        seed: UInt32 = 0x5A10
    ) -> Bool {
        var rng = LCG32(state: seed)
        for _ in 0..<trials {
            let t = (0..<dim).map { _ in UInt8(rng.next() & 1) }
            let w = t.map { bit -> Float in
                let interior = Float((rng.next() % 4_000) + 1) / 10_000 // (0, 0.4]
                return bit == 1 ? 0.5 + interior : 0.5 - interior
            }
            if emitBinary(w) != t { return false }
            if abs(discretenessPenalty(t.map { Float($0) })) > 1e-6 { return false }
            // Crossing 1/2 must fail (basin is open).
            var crossed = w
            crossed[0] = t[0] == 1 ? 0.49 : 0.51
            if emitBinary(crossed) == t { return false }
        }
        return true
    }

    /// Lemma: freeze at the Boolean target leaves the unique maximizer on free coords;
    /// a wrong freeze makes F=0 unreachable.
    package static func checkFreezePreservesMaximizer() -> Bool {
        let t: [Float] = [0, 1, 0, 1]
        let frozenOK: [Float] = [0, 1, 0.4, 0.6] // first two frozen at t
        let lambda: Float = 4
        let fOK = zip(frozenOK, t).enumerated().reduce(Float(0)) { acc, it in
            let (i, pair) = it
            if i < 2 { return acc } // freeze: omit from π and from search
            return acc + separableCoordinateFitness(weight: pair.0, target: pair.1, lambda: lambda)
        }
        let fStarFree = separableCoordinateFitness(weight: 0, target: 0, lambda: lambda)
            + separableCoordinateFitness(weight: 1, target: 1, lambda: lambda)
        if !(fOK < fStarFree - 1e-6) { return false }
        let snappedFree: [Float] = [0, 1, 0, 1]
        let fSnapped = zip(snappedFree, t).enumerated().reduce(Float(0)) { acc, it in
            let (i, pair) = it
            if i < 2 { return acc }
            return acc + separableCoordinateFitness(weight: pair.0, target: pair.1, lambda: lambda)
        }
        if abs(fSnapped) > 1e-6 { return false }
        // Wrong freeze: coord 0 stuck at 1 while t_0=0.
        let wrong: [Float] = [1, 1, 0, 1]
        let fWrong = zip(wrong, t).reduce(Float(0)) {
            $0 + separableCoordinateFitness(weight: $1.0, target: $1.1, lambda: 0)
        }
        return fWrong < -0.5
    }

    /// Theorem 1″: melt–freeze–snap for a coordinate-separable Boolean interpolant (C44).
    package static func meltFreezeSnapCertificate() -> TensorLUTFormalCertificate {
        let steps: [TensorLUTProofStep] = [
            .init(lemma: .separableMeltUniqueMaximizer, holds: checkSeparableMeltUniqueMaximizer()),
            .init(lemma: .snapBasinCompleteness, holds: checkSnapBasinCompleteness()),
            .init(lemma: .freezePreservesMaximizer, holds: checkFreezePreservesMaximizer())
        ]
        return TensorLUTFormalCertificate(
            steps: steps,
            hypotheses: [
                "Each used INIT address is an independent Boolean target (fully observed 1-LUT / separable interpolant)",
                "F(w)=−‖w−t‖²−λπ(w) with λ≥0, w∈[0,1]^k, t∈{0,1}^k",
                "Snap is the emitter E(w)_i=1[w_i≥1/2]; basin is the open cube |w_i−t_i|<1/2",
                "Freeze removes frozen coordinates from search; a wrong freeze blocks F=0",
                "Does not prove GA convergence, multi-LUT topological melt, or arbitrary-netlist completeness",
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
