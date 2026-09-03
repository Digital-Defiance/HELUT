import Foundation

// MARK: - Incomplete public-MS covering gap (H4 Track A / approximate path)
//
// `cryptoPublicMS` keeps g₀ = δ but uses ℓ = ⌊32 / baseLog⌋, so at N = 1024
// baseLog·ℓ = 22 ≠ 32. The uncovered high bits are a structural truncation
// budget — not SoftBus. Exact covering is impossible for this (N, q) (**C29**);
// this module grades the *gap* an approximate gadget would have to absorb (**C31**).

package enum GGSWIncompleteCoveringLemma: String, Sendable {
    /// uncoveredBits = 32 − baseLog·ℓ for the live cryptoPublicMS gadget.
    case uncoveredBitsMatchLive
    /// Exact degrees have uncoveredBits = 0; N=1024 has uncoveredBits = 10.
    case productionGap
    /// Reconstruction: covering decomp recovers every UInt32; incomplete leaves
    /// a residual congruent to the value mod 2^{uncoveredBits}.
    case reconstructionGap
    /// Closest covering baseLog ≤ publicMSBaseLog among divisors of 32 is the
    /// classic crypto gadget (baseLog=8 at N=1024) — g₀ ≠ δ (**approx candidate**).
    case closestCoveringCandidate
}

package struct GGSWIncompleteCoveringProofStep: Sendable, Equatable {
    package var lemma: GGSWIncompleteCoveringLemma
    package var holds: Bool
    package var note: String

    package init(lemma: GGSWIncompleteCoveringLemma, holds: Bool, note: String = "") {
        self.lemma = lemma
        self.holds = holds
        self.note = note
    }
}

package struct GGSWIncompleteCoveringCertificate: Sendable, Equatable {
    package var steps: [GGSWIncompleteCoveringProofStep]
    package var hypotheses: [String]
    package var productionUncoveredBits: Int

    package var allHold: Bool { steps.allSatisfy(\.holds) }

    package func assertValid(file: StaticString = #file, line: UInt = #line) {
        precondition(allHold, "GGSWIncompleteCoveringCertificate failed at \(file):\(line)")
    }
}

/// Structural gap between g₀=δ public-MS and exact covering under q=2³².
package enum GGSWIncompleteCovering {
    package static let wordBits = 32
    package static let productionDegree = 1024
    /// 32 − 11·2 for cryptoPublicMS(N=1024).
    package static let productionUncoveredBits = 10

    package static func uncoveredBits(baseLog: Int, levelCount: Int) -> Int {
        max(0, wordBits - baseLog * levelCount)
    }

    package static func uncoveredBits(degree n: Int) -> Int {
        let p = GGSWParams.cryptoPublicMS(degree: n)
        return uncoveredBits(baseLog: p.baseLog, levelCount: p.levelCount)
    }

    /// Reconstruct Σ digit_i · g_i after `gadgetDecomposeScalar`.
    package static func reconstruct(_ value: UInt32, baseLog: Int, levelCount: Int) -> UInt32 {
        let digits = gadgetDecomposeScalar(value, baseLog: baseLog, levelCount: levelCount)
        var sum: UInt32 = 0
        for i in 0..<levelCount {
            let shift = wordBits - (i + 1) * baseLog
            if shift >= 0 {
                sum &+= digits[i] &<< UInt32(shift)
            }
        }
        return sum
    }

    /// Largest baseLog ≤ publicMSBaseLog(n) that divides 32 (covering candidate).
    package static func closestCoveringBaseLog(degree n: Int) -> Int {
        let ideal = GGSWPublicMSCovering.publicMSBaseLog(degree: n)
        var best = 1
        for b in 1...ideal where wordBits % b == 0 {
            best = b
        }
        return best
    }

    package static func checkUncoveredBitsMatchLive() -> Bool {
        for n in GGSWPublicMSCovering.practicalDegrees {
            let p = GGSWParams.cryptoPublicMS(degree: n)
            let want = uncoveredBits(baseLog: p.baseLog, levelCount: p.levelCount)
            if uncoveredBits(degree: n) != want { return false }
            let exact = GGSWPublicMSCovering.isExactPublicMSCovering(degree: n)
            if exact && want != 0 { return false }
            if !exact && want == 0 { return false }
        }
        return true
    }

    package static func checkProductionGap() -> Bool {
        uncoveredBits(degree: productionDegree) == productionUncoveredBits
            && GGSWParams.cryptoPublicMS(degree: productionDegree).baseLog == 11
            && GGSWParams.cryptoPublicMS(degree: productionDegree).levelCount == 2
    }

    package static func checkReconstructionGap() -> Bool {
        // Covering: full recovery.
        let covering = GGSWParams.crypto(degree: 1024)
        for raw in [0 as UInt32, 1, 0xFF, 0x1234_5678, UInt32.max] {
            if reconstruct(raw, baseLog: covering.baseLog, levelCount: covering.levelCount) != raw {
                return false
            }
        }
        // Incomplete public-MS at N=1024: recovers only the top baseLog·ℓ bits.
        let p = GGSWParams.cryptoPublicMS(degree: productionDegree)
        let lowMask = (UInt32(1) &<< UInt32(productionUncoveredBits)) &- 1
        let highMask = ~lowMask
        for raw in [0 as UInt32, 1, 0x3FF, 0x400, 0xABCD_EF01, UInt32.max] {
            let got = reconstruct(raw, baseLog: p.baseLog, levelCount: p.levelCount)
            if (got & highMask) != (raw & highMask) { return false }
            if (got & lowMask) != 0 { return false }
        }
        return true
    }

    package static func checkClosestCoveringCandidate() -> Bool {
        // At N=1024, closest covering baseLog ≤ 11 among divisors of 32 is 8 → `.crypto`.
        if closestCoveringBaseLog(degree: 1024) != 8 { return false }
        let crypto = GGSWParams.crypto(degree: 1024)
        if crypto.baseLog != 8 || crypto.levelCount != 4 { return false }
        if crypto.baseLog * crypto.levelCount != 32 { return false }
        // g₀(crypto) = 2^{24} ≠ δ = 2^{21}.
        let delta = rotationScale(polynomialDegree: 1024)
        if crypto.gadget[0] == delta { return false }
        // Exact degrees: closest covering baseLog equals public-MS baseLog.
        for n in GGSWPublicMSCovering.exactPracticalDegrees {
            if closestCoveringBaseLog(degree: n) != GGSWPublicMSCovering.publicMSBaseLog(degree: n) {
                return false
            }
        }
        return true
    }

    package static func certificate() -> GGSWIncompleteCoveringCertificate {
        let steps: [GGSWIncompleteCoveringProofStep] = [
            .init(lemma: .uncoveredBitsMatchLive, holds: checkUncoveredBitsMatchLive()),
            .init(lemma: .productionGap, holds: checkProductionGap(),
                  note: "N=1024 uncoveredBits=\(productionUncoveredBits)"),
            .init(lemma: .reconstructionGap, holds: checkReconstructionGap()),
            .init(lemma: .closestCoveringCandidate, holds: checkClosestCoveringCandidate(),
                  note: "approx candidate = crypto baseLog=8 (g₀≠δ)")
        ]
        return GGSWIncompleteCoveringCertificate(
            steps: steps,
            hypotheses: [
                "q = 2³² native UInt32 torus",
                "cryptoPublicMS keeps g₀ = δ with ℓ = ⌊32/baseLog⌋ (may be incomplete)",
                "Exact covering needs baseLog·ℓ = 32 (**C27**/**C29**)",
                "Uncovered bits bound the incomplete-decomp truncation (Track A approx budget)",
                "Closest covering baseLog ≤ ideal is the classic .crypto gadget at N=1024",
                "Does not claim noisy BK PASS at N=1024 — see C26 / H4 Track A"
            ],
            productionUncoveredBits: productionUncoveredBits
        )
    }
}
