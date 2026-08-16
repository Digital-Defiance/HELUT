import XCTest
@testable import HELUTCore

/// How many *independent* samples does the accumulator estimator really buy?
///
/// `identityAllCoefficients` collects N residuals per bootstrap, but the CMUX
/// ladder mixes external-product error across coefficients, so the residuals are
/// identically distributed without being independent. The χ² confidence bound
/// assumes independence, so treating N residuals as N samples would produce a
/// bound that is too tight — the dangerous direction.
///
/// AUDIT §13.4 sketched this optimisation as "~N samples per trial, a ~1000×
/// improvement". That was a guess. These tests measure it, and the guess is
/// wrong: at N=64 one bootstrap buys about 7 effective samples, not 64.
///
/// Method. For n independent samples the relative spread of σ̂ over repeated
/// runs is `sd(σ̂)/mean(σ̂) ≈ 1/√(2n)`, so inverting the observed spread gives
/// n_eff. That asymptotic assumes a Gaussian residual, and the residual here is
/// a bounded sum with excess kurtosis, which biases the absolute figure low.
/// A control at a *known* independent sample count calibrates that bias, and the
/// reported gain is the ratio of the two — where the bias cancels.
final class TFHENoisyBKEffectiveSampleTests: XCTestCase {

    /// Repeats per configuration. n_eff is itself estimated to about
    /// ±1/√(2·repeats) relative, so 48 gives roughly ±10%.
    private static let repeats = 48

    /// Control bootstraps. These are genuinely independent draws, so the
    /// harness should recover a number near this.
    private static let controlTrials = 64

    private func rig(degree: Int) -> (TFHESecretKey, GGSWParams) {
        let params = GGSWParams.cryptoPublicMS(degree: degree)
        let secret = TFHESecretKey.random(params: params.tfhe, seed: 0xB401)
        return (secret, params)
    }

    /// Invert `sd/mean ≈ 1/√(2n)` to recover an effective sample count.
    private func effectiveSamples(_ sigmas: [Double]) -> Double {
        let n = Double(sigmas.count)
        let mean = sigmas.reduce(0, +) / n
        guard mean > 0, n > 1 else { return 0 }
        let variance = sigmas.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / (n - 1)
        let relSpread = variance.squareRoot() / mean
        guard relSpread > 0 else { return .infinity }
        return 1.0 / (2.0 * relSpread * relSpread)
    }

    private struct Row {
        var degree: Int
        var accEff: Double
        var controlEff: Double
        var accSigma: Double
        var controlSigma: Double
        /// Effective samples per bootstrap, with the kurtosis bias divided out.
        var gainPerBootstrap: Double { accEff / (controlEff / Double(controlTrials)) }
        var fractionOfN: Double { gainPerBootstrap / Double(degree) }
    }

    /// Measure the gain and how it scales with N, rather than extrapolating it.
    func testEffectiveSampleSizeScaling() {
        let noise = TFHENoiseParams(bound: 8)
        var rows: [Row] = []

        for degree in [32, 64, 128, 256] {
            let (secret, params) = rig(degree: degree)

            // Accumulator: exactly one bootstrap per run, so all of the spread
            // reduction comes from the N coefficients.
            var accSigmas: [Double] = []
            for r in 0..<Self.repeats {
                let m = TFHENoisyBKMeasurement.identityAllCoefficients(
                    secret: secret, params: params, noise: noise,
                    trials: 1, seed: UInt32(truncatingIfNeeded: 0x51000 + r * 7919)
                )
                accSigmas.append(m.sigmaHat)
            }

            var controlSigmas: [Double] = []
            for r in 0..<Self.repeats {
                let m = TFHENoisyBKMeasurement.identity(
                    secret: secret, params: params, noise: noise,
                    trials: Self.controlTrials,
                    seed: UInt32(truncatingIfNeeded: 0x72000 + r * 7919)
                )
                controlSigmas.append(m.sigmaHat)
            }

            rows.append(
                Row(
                    degree: degree,
                    accEff: effectiveSamples(accSigmas),
                    controlEff: effectiveSamples(controlSigmas),
                    accSigma: accSigmas.reduce(0, +) / Double(Self.repeats),
                    controlSigma: controlSigmas.reduce(0, +) / Double(Self.repeats)
                )
            )
        }

        var out = """

        === accumulator sampling: measured effective sample size ===
        inject B=8, \(Self.repeats) repeats, control \(Self.controlTrials) PBS

        |    N | acc sigma | ctl sigma | acc n_eff | ctl n_eff | gain/PBS | % of N |
        |------|-----------|-----------|-----------|-----------|----------|--------|

        """
        for r in rows {
            out += String(
                format: "| %4d | %9.0f | %9.0f | %9.1f | %9.1f | %7.1fx | %5.1f%% |\n",
                r.degree, r.accSigma, r.controlSigma,
                r.accEff, r.controlEff, r.gainPerBootstrap, 100 * r.fractionOfN
            )
        }
        out += """

        gain/PBS = effective samples one bootstrap buys, kurtosis bias divided
        out via the control. AUDIT 13.4 assumed this equals N.

        """
        print(out)

        for r in rows {
            // Control sanity: the harness must recover a known-independent count
            // to within a factor of ~3, else it measures nothing trustworthy.
            XCTAssertTrue(
                r.controlEff > Double(Self.controlTrials) / 3
                    && r.controlEff < Double(Self.controlTrials) * 3,
                """
                N=\(r.degree): control n_eff \(r.controlEff) far from \
                \(Self.controlTrials) independent trials — spread-inversion \
                harness unreliable here.
                """
            )

            // The optimisation must be real: one bootstrap has to buy
            // meaningfully more than one sample.
            XCTAssertGreaterThan(
                r.gainPerBootstrap, 4.0,
                """
                N=\(r.degree): one bootstrap bought only \(r.gainPerBootstrap) \
                effective samples. The accumulator coefficients are too \
                correlated for this optimisation to be worth its complexity.
                """
            )

            // And it cannot exceed N — that would mean the harness is broken.
            XCTAssertLessThan(
                r.gainPerBootstrap, Double(r.degree) * 1.5,
                "N=\(r.degree): gain \(r.gainPerBootstrap) implausibly exceeds N"
            )
        }

        // The claim that must not silently regress: the naive "N samples per
        // bootstrap" reading is wrong by a large factor. Printed so that if the
        // correlation structure ever changes, the number moves visibly.
        let worst = rows.map(\.fractionOfN).min() ?? 0
        XCTAssertLessThan(
            worst, 0.75,
            """
            measured gain reached \(100 * worst)% of N. If coefficients really \
            are near-independent, AUDIT 13.4 and this test's premise both need \
            revisiting.
            """
        )
    }
}
