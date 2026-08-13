import Foundation

// MARK: - Exact public-MS covering (Pillar I / H4 obstruction)
//
// Under q = 2³² and power-of-two N, rotation spacing is δ = q/(2N) = 2^{32−(1+v)}
// with v = log₂(N). Exact public MS wants g₀ = δ, so baseLog = 1+v.
// Exact covering decomposition (Metal EP / digit extract) wants baseLog·ℓ = 32.
// Those constraints hold together iff (1+v) | 32.
//
// Among practical HELUT sizes N ∈ {8,…,2048}, only N = 8 and N = 128 qualify.
// Production N = 1024 cannot be both covering and g₀ = δ — **C26** measured the
// residual blow-up; this module states the structural reason (**C27**).

package enum GGSWPublicMSCoveringLemma: String, Sendable {
    /// For power-of-two N, public-MS baseLog equals 1 + log₂(N) (= log₂(2N)).
    case publicMSBaseLog
    /// Covering requires baseLog·ℓ = 32 with integer ℓ ≥ 1, i.e. baseLog | 32.
    case coveringDividesWord
    /// Exact public-MS covering ⇔ power-of-two N and (1+log₂ N) | 32.
    case exactPublicMSCovering
    /// Among N∈{8,16,…,2048}, only 8 and 128 are exact.
    case practicalDegrees
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

/// Structural facts about simultaneous g₀=δ and covering under q=2³².
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

    /// True when some integer ℓ ≥ 1 satisfies baseLog·ℓ = 32.
    package static func dividesWord(_ baseLog: Int) -> Bool {
        baseLog > 0 && baseLog <= 32 && 32 % baseLog == 0
    }

    /// Covering level count when `dividesWord(baseLog)`; else nil.
    package static func coveringLevelCount(baseLog: Int) -> Int? {
        guard dividesWord(baseLog) else { return nil }
        return 32 / baseLog
    }

    /// Exact public-MS covering at this power-of-two degree.
    package static func isExactPublicMSCovering(degree n: Int) -> Bool {
        guard n >= 2, n.nonzeroBitCount == 1 else { return false }
        return dividesWord(publicMSBaseLog(degree: n))
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

    package static func certificate() -> GGSWPublicMSCoveringCertificate {
        let steps: [GGSWPublicMSCoveringProofStep] = [
            .init(lemma: .publicMSBaseLog, holds: checkPublicMSBaseLog()),
            .init(lemma: .coveringDividesWord, holds: checkCoveringDividesWord()),
            .init(lemma: .exactPublicMSCovering, holds: checkExactPublicMSCovering()),
            .init(lemma: .practicalDegrees, holds: checkPracticalDegrees(),
                  note: "exact degrees = \(exactPracticalDegrees)")
        ]
        return GGSWPublicMSCoveringCertificate(
            steps: steps,
            hypotheses: [
                "Torus modulus q = 2³² (native UInt32)",
                "Polynomial degree N is a power of two",
                "δ = q/(2N) is the rotation / boolean message spacing",
                "Exact public MS wants g₀ = δ (ACC stays on δ-lattice)",
                "Exact covering / Metal EP wants baseLog·ℓ = 32",
                "Structural — not a claim that noisy BK is impossible under other (q,N)",
                "C26 measures residual blow-up when inject≠0 at incomplete N=1024 gadget"
            ],
            exactDegrees: exactPracticalDegrees
        )
    }
}
