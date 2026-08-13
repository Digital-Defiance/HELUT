import Foundation

// MARK: - Exact public-MS covering (Pillar I / H4 obstruction)
//
// Under q = 2^w and power-of-two N, rotation spacing is δ = q/(2N) = 2^{w−(1+v)}
// with v = log₂(N). Exact public MS wants g₀ = δ, so baseLog = 1+v.
// Exact covering decomposition (Metal EP / digit extract) wants baseLog·ℓ = w.
// Those constraints hold together iff (1+v) | w.
//
// When w is itself a power of two, every divisor of w is a power of two, so
// 1+v = 2^a ⇒ N = 2^{2^a − 1}. Among practical HELUT sizes N ∈ {8,…,2048},
// only N = 8 and N = 128 qualify — for *any* such w (**C29**). In particular
// widening the limb (UInt64, …) does **not** unlock production N = 1024.
// Native path uses w = 32 (**C27**); **C26** measured the residual blow-up.

package enum GGSWPublicMSCoveringLemma: String, Sendable {
    /// For power-of-two N, public-MS baseLog equals 1 + log₂(N) (= log₂(2N)).
    case publicMSBaseLog
    /// Covering requires baseLog·ℓ = 32 with integer ℓ ≥ 1, i.e. baseLog | 32.
    case coveringDividesWord
    /// Exact public-MS covering ⇔ power-of-two N and (1+log₂ N) | 32.
    case exactPublicMSCovering
    /// Among N∈{8,16,…,2048}, only 8 and 128 are exact.
    case practicalDegrees
    /// For any power-of-two word *w*, baseLog must itself be a power of two ⇒ among
    /// practical degrees only N∈{8,128}; N=1024 (baseLog=11) never exact (**C29**).
    case powerOfTwoWordObstruction
}

package struct GGSWPublicMSCoveringProofStep: Sendable, Equatable {
    package var lemma: GGSWPublicMSCoveringLemma
    package var holds: Bool
    package var note: String

    package init(lemma: GGSWPublicMSCoveringLemma, holds: Bool, note: String = "") {
        self.lemma = lemma
        self.holds = holds
        self.note = note
    }
}

package struct GGSWPublicMSCoveringCertificate: Sendable, Equatable {
    package var steps: [GGSWPublicMSCoveringProofStep]
    package var hypotheses: [String]
    package var exactDegrees: [Int]

    package var allHold: Bool { steps.allSatisfy(\.holds) }

    package func assertValid(file: StaticString = #file, line: UInt = #line) {
        precondition(allHold, "GGSWPublicMSCoveringCertificate failed at \(file):\(line)")
    }
}

/// Structural facts about simultaneous g₀=δ and covering under q=2^w.
package enum GGSWPublicMSCovering {
    /// Powers of two from 8 through 2048 (HELUT demo → extrapolated).
    package static let practicalDegrees: [Int] = [8, 16, 32, 64, 128, 256, 512, 1024, 2048]

    /// Exact public-MS covering degrees in `practicalDegrees` (must be {8, 128}).
    package static let exactPracticalDegrees: [Int] = [8, 128]

    /// baseLog so that g₀ = 2^{32−baseLog} equals δ = q/(2N).
    package static func publicMSBaseLog(degree n: Int) -> Int {
        precondition(n >= 2 && n.nonzeroBitCount == 1, "degree must be a power of two")
        return 1 + n.trailingZeroBitCount
    }

    /// Power-of-two torus word sizes (limb widths) used in the C29 obstruction.
    package static let powerOfTwoWordBits: [Int] = [16, 32, 64, 128]

    /// True when some integer ℓ ≥ 1 satisfies baseLog·ℓ = wordBits.
    package static func dividesWord(_ baseLog: Int, wordBits: Int = 32) -> Bool {
        baseLog > 0 && baseLog <= wordBits && wordBits % baseLog == 0
    }

    /// Covering level count when `dividesWord(baseLog)`; else nil.
    package static func coveringLevelCount(baseLog: Int, wordBits: Int = 32) -> Int? {
        guard dividesWord(baseLog, wordBits: wordBits) else { return nil }
        return wordBits / baseLog
    }

    /// Exact public-MS covering at this power-of-two degree under torus word `wordBits`.
    package static func isExactPublicMSCovering(degree n: Int, wordBits: Int = 32) -> Bool {
        guard n >= 2, n.nonzeroBitCount == 1 else { return false }
        return dividesWord(publicMSBaseLog(degree: n), wordBits: wordBits)
    }

    /// Matches `GGSWParams.cryptoPublicMS` when covering; else documents the gap.
    package static func cryptoPublicMSIsCovering(degree n: Int) -> Bool {
        let p = GGSWParams.cryptoPublicMS(degree: n)
        return p.baseLog * p.levelCount == 32
    }

    package static func checkPublicMSBaseLog() -> Bool {
        for n in practicalDegrees {
            let want = 1 + n.trailingZeroBitCount
            if publicMSBaseLog(degree: n) != want { return false }
            // g₀ from gadget[0] of a ℓ=1 public-MS shaped gadget equals δ.
            let delta = rotationScale(polynomialDegree: n)
            let g0Shift = 32 - want
            let g0 = g0Shift >= 0 ? (1 as UInt32) &<< UInt32(g0Shift) : 0
            if g0 != delta { return false }
        }
        return true
    }

    package static func checkCoveringDividesWord() -> Bool {
        // Positive controls
        for b in [1, 2, 4, 8, 16, 32] where !dividesWord(b) { return false }
        // Negative controls (production public-MS baseLogs)
        for b in [5, 6, 7, 9, 10, 11, 12] where dividesWord(b) { return false }
        if coveringLevelCount(baseLog: 8) != 4 { return false }
        if coveringLevelCount(baseLog: 11) != nil { return false }
        return true
    }

    package static func checkExactPublicMSCovering() -> Bool {
        for n in practicalDegrees {
            let exact = isExactPublicMSCovering(degree: n)
            let live = cryptoPublicMSIsCovering(degree: n)
            if exact != live { return false }
            if exact {
                let b = publicMSBaseLog(degree: n)
                let ell = coveringLevelCount(baseLog: b)!
                let p = GGSWParams.cryptoPublicMS(degree: n)
                if p.baseLog != b || p.levelCount != ell { return false }
            } else {
                // Incomplete: cryptoPublicMS uses ⌊32/baseLog⌋ so product < 32.
                let p = GGSWParams.cryptoPublicMS(degree: n)
                if p.baseLog * p.levelCount == 32 { return false }
            }
        }
        // Production N is not exact.
        if isExactPublicMSCovering(degree: 1024) { return false }
        return true
    }

    package static func checkPracticalDegrees() -> Bool {
        let found = practicalDegrees.filter { isExactPublicMSCovering(degree: $0) }
        return found == exactPracticalDegrees
    }

    /// Divisors of a power-of-two word are themselves powers of two, so
    /// `1+log₂ N` must be a power of two ⇒ `N = 2^{2^a − 1}`.
    /// Among practical degrees that yields only {8, 128}; never 1024.
    package static func checkPowerOfTwoWordObstruction() -> Bool {
        for w in powerOfTwoWordBits {
            guard w >= 2, w.nonzeroBitCount == 1 else { return false }
            let found = practicalDegrees.filter { isExactPublicMSCovering(degree: $0, wordBits: w) }
            if found != exactPracticalDegrees { return false }
            // N=1024 ⇒ baseLog=11, and 11 never divides a power of two.
            if isExactPublicMSCovering(degree: 1024, wordBits: w) { return false }
            if dividesWord(11, wordBits: w) { return false }
        }
        // Positive: N=8,128 remain exact at every listed power-of-two word.
        for w in powerOfTwoWordBits {
            if !isExactPublicMSCovering(degree: 8, wordBits: w) { return false }
            if !isExactPublicMSCovering(degree: 128, wordBits: w) { return false }
        }
        return true
    }

    package static func certificate() -> GGSWPublicMSCoveringCertificate {
        let steps: [GGSWPublicMSCoveringProofStep] = [
            .init(lemma: .publicMSBaseLog, holds: checkPublicMSBaseLog()),
            .init(lemma: .coveringDividesWord, holds: checkCoveringDividesWord()),
            .init(lemma: .exactPublicMSCovering, holds: checkExactPublicMSCovering()),
            .init(lemma: .practicalDegrees, holds: checkPracticalDegrees(),
                  note: "exact degrees = \(exactPracticalDegrees)"),
            .init(lemma: .powerOfTwoWordObstruction, holds: checkPowerOfTwoWordObstruction(),
                  note: "words \(powerOfTwoWordBits); N=1024 never exact")
        ]
        return GGSWPublicMSCoveringCertificate(
            steps: steps,
            hypotheses: [
                "Torus modulus q = 2^w for power-of-two word w (native UInt32 ⇒ w=32)",
                "Polynomial degree N is a power of two",
                "δ = q/(2N) is the rotation / boolean message spacing",
                "Exact public MS wants g₀ = δ (ACC stays on δ-lattice)",
                "Exact covering / Metal EP wants baseLog·ℓ = w",
                "C27: under w=32 exact degrees among practical = {8,128}",
                "C29: for any power-of-two w, practical exact degrees stay {8,128}; widening limb ≠ Track A unlock",
                "C26 measures residual blow-up when inject≠0 at incomplete N=1024 gadget"
            ],
            exactDegrees: exactPracticalDegrees
        )
    }
}
