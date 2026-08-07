import Foundation

// MARK: - Gaussian asymptotic noise / failure-probability certificate (step 10k)
//
// Concrete security under an independent Gaussian noise model (Chillotti-style
// variance tracking + erfc tails). This is the standard *parameter* argument used
// in production TFHE stacks — not a reduction from LWE hardness.
//
// Hypotheses (must hold for the certificate to apply):
// 1. Fresh encrypt noise ~ N(0, σ²) independent across coeffs (torus)
// 2. Homomorphic linear ops add variances as stated
// 3. Exact lattice ingest MS succeeds whenever |e| < δ/2
// 4. Noiseless BK ⇒ PBS output variance floor = 0 (HELUT e=0 BK path)
// 5. Failure events union-bounded across input wires / LUT depth as noted

/// Gaussian encrypt / security parameters for HELUT’s encrypted path.
package struct TFHEGaussianParams: Sendable, Equatable {
    /// Fresh LWE/GLWE body noise standard deviation (torus units).
    package var sigma: Double
    /// Message spacing Δ.
    package var delta: UInt32
    package var lweDimension: Int
    package var polynomialDegree: Int
    /// Target failure probability as log2 (e.g. `-64` ⇒ ≤ 2^{-64}).
    package var targetFailureLog2: Int

    package init(
        sigma: Double,
        delta: UInt32,
        lweDimension: Int,
        polynomialDegree: Int,
        targetFailureLog2: Int = -64
    ) {
        precondition(sigma > 0)
        precondition(delta >= 2)
        precondition(lweDimension > 0 && polynomialDegree > 0)
        precondition(targetFailureLog2 < 0)
        self.sigma = sigma
        self.delta = delta
        self.lweDimension = lweDimension
        self.polynomialDegree = polynomialDegree
        self.targetFailureLog2 = targetFailureLog2
    }

    package var variance: Double { sigma * sigma }

    package var decodingHalfGap: Double { Double(delta) / 2 }

    /// Production-shaped boolean params: N=1024, σ = 2^{16} (≪ δ/2 = 2^{20}), ε ≤ 2^{-64}.
    package static func productionBoolean64(polynomialDegree n: Int = 1024) -> TFHEGaussianParams {
        let delta = rotationScale(polynomialDegree: n)
        let sigma = Double(1 << 16)
        precondition(sigma < Double(delta) / 2)
        return TFHEGaussianParams(
            sigma: sigma,
            delta: delta,
            lweDimension: n,
            polynomialDegree: n,
            targetFailureLog2: -64
        )
    }

    /// Demo N=8 params still aiming at ε ≤ 2^{-64} via tiny σ / δ ratio.
    package static func demoBoolean64(polynomialDegree n: Int = 8) -> TFHEGaussianParams {
        let delta = rotationScale(polynomialDegree: n)
        let sigma = Double(delta) / Double(1 << 20)
        return TFHEGaussianParams(
            sigma: sigma,
            delta: delta,
            lweDimension: n,
            polynomialDegree: n,
            targetFailureLog2: -64
        )
    }
}

/// Tracked noise variance under the Gaussian model.
package struct TFHEGaussianVariance: Sendable, Equatable {
    package private(set) var variance: Double

    package init(variance: Double = 0) {
        precondition(variance >= 0 && variance.isFinite)
        self.variance = variance
    }

    package static func fresh(params: TFHEGaussianParams) -> TFHEGaussianVariance {
        TFHEGaussianVariance(variance: params.variance)
    }

    package mutating func afterAdd(_ other: TFHEGaussianVariance) {
        variance += other.variance
    }

    package mutating func scale(by scalar: Double) {
        variance *= scalar * scalar
    }

    /// Exact lattice MS conditioned on |e| < δ/2: message noise floor → 0.
    package mutating func afterExactModulusSwitchSuccess() {
        variance = 0
    }

    /// Noiseless BK PBS refresh.
    package mutating func afterBlindRotateNoiselessBK() {
        variance = 0
    }

    package var stddev: Double { sqrt(variance) }
}

/// Complementary error function erfc(x) for x ≥ 0 (Abramowitz–Stegun 7.1.26).
package func erfcApprox(_ x: Double) -> Double {
    if x < 0 { return 2 - erfcApprox(-x) }
    if x > 20 { return 0 }
    let p = 0.3275911
    let a1 = 0.254829592
    let a2 = -0.284496736
    let a3 = 1.421413741
    let a4 = -1.453152027
    let a5 = 1.061405429
    let t = 1 / (1 + p * x)
    let poly = ((((a5 * t + a4) * t + a3) * t + a2) * t + a1) * t
    return poly * exp(-x * x)
}

/// Two-sided Gaussian tail: P(|Z| ≥ t) for Z ~ N(0, σ²).
package func gaussianTwoSidedTail(stddev: Double, threshold: Double) -> Double {
    precondition(stddev >= 0 && threshold >= 0)
    if stddev == 0 {
        return threshold > 0 ? 0 : 1
    }
    let z = threshold / (stddev * sqrt(2))
    return erfcApprox(z)
}

/// `log₂ P(|Z| ≥ t)` with asymptotic erfc for large z (avoids false −∞ underflow).
package func log2GaussianTwoSidedTail(stddev: Double, threshold: Double) -> Double {
    precondition(stddev >= 0 && threshold >= 0)
    if stddev == 0 {
        return threshold > 0 ? -Double.infinity : 0
    }
    let z = threshold / (stddev * sqrt(2))
    if z < 0 {
        return 0
    }
    // erfcApprox underflows to 0 for z ≳ 20; use erfc asymptotic:
    // erfc(z) ∼ exp(−z²) / (z √π)
    if z >= 12 {
        let lnErfc = -z * z - log(z * sqrt(.pi))
        return lnErfc / log(2)  // two-sided ≈ erfc for large z (factor 2 absorbed in ≈)
    }
    let p = erfcApprox(z)
    return log2Probability(p)
}

package func log2Probability(_ p: Double) -> Double {
    if p <= 0 { return -Double.infinity }
    if p >= 1 { return 0 }
    return log(p) / log(2)
}

// MARK: - Sampling uncertainty on a measured σ̂
//
// ε here is an analytic Gaussian tail evaluated at a *measured* σ̂, and
// log₂ε ≈ −(δ/2)²/(2σ̂² ln 2) — that is, log₂ε ∝ −1/σ̂². A relative error r in
// σ̂ therefore moves log₂ε by roughly 2·|log₂ε|·r. At |log₂ε| = 65 a 1% error in
// σ̂ is worth 1.3 orders, and σ̂ estimated from m samples carries a standard
// error of about 1/√(2m).
//
// The practical consequence, found during the 2026-08-15 re-validation: an ε
// measured at m = 4 samples has ±46 orders of slack at that scale, so a point
// estimate of −65.4 says nothing about whether the 2⁻⁶⁴ bar is met. Anything
// quoting ε against a bar must quote the confidence bound too.

/// Upper quantile of the chi-square distribution (Wilson--Hilferty).
/// Accurate to a few tenths of a percent for `dof >= 2`, which is far inside the
/// uncertainty this is used to describe.
package func chiSquareQuantile(probability p: Double, degreesOfFreedom dof: Int) -> Double {
    precondition(p > 0 && p < 1 && dof >= 1)
    let m = Double(dof)
    let z = standardNormalQuantile(p)
    let base = 1 - 2 / (9 * m) + z * (2 / (9 * m)).squareRoot()
    return m * base * base * base
}

/// Inverse standard normal CDF (Acklam's rational approximation).
package func standardNormalQuantile(_ p: Double) -> Double {
    precondition(p > 0 && p < 1)
    let a = [-3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02,
             1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00]
    let b = [-5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02,
             6.680131188771972e+01, -1.328068155288572e+01]
    let c = [-7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00,
             -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00]
    let d = [7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00,
             3.754408661907416e+00]
    let plow = 0.02425
    if p < plow {
        let q = (-2 * log(p)).squareRoot()
        return (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5])
            / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
    }
    if p > 1 - plow {
        let q = (-2 * log(1 - p)).squareRoot()
        return -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5])
            / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
    }
    let q = p - 0.5
    let r = q * q
    return (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q
        / (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1)
}

/// One-sided upper confidence bound on σ given an RMS estimate over `samples`
/// zero-mean observations. Uses `m·σ̂²/σ² ~ χ²(m)`.
package func sigmaUpperConfidenceBound(
    sigmaHat: Double,
    samples: Int,
    confidence: Double = 0.95
) -> Double {
    precondition(sigmaHat >= 0 && samples >= 1)
    guard samples > 1, sigmaHat > 0 else { return .infinity }
    let lower = chiSquareQuantile(probability: 1 - confidence, degreesOfFreedom: samples)
    guard lower > 0 else { return .infinity }
    return sigmaHat * (Double(samples) / lower).squareRoot()
}

/// How many orders of `log₂ε` the sample size cannot resolve:
/// `2·|log₂ε|/√(2m)`. If this exceeds the distance to the target bar, the
/// measurement cannot decide whether the bar is met.
package func epsilonResolutionOrders(failureLog2: Double, samples: Int) -> Double {
    guard samples >= 1, failureLog2.isFinite else { return .infinity }
    return 2 * abs(failureLog2) / (2 * Double(samples)).squareRoot()
}

/// Samples needed to resolve `log₂ε` to `±orders`.
package func samplesForEpsilonResolution(failureLog2: Double, orders: Double = 1) -> Int {
    guard failureLog2.isFinite, orders > 0 else { return Int.max }
    let r = orders / (2 * abs(failureLog2))
    guard r > 0 else { return Int.max }
    return Int((1 / (2 * r * r)).rounded(.up))
}

/// Smallest sample count at which the 95% bound *clears* `targetLog2`, or `nil`
/// if no sample size can.
///
/// This is the question that actually matters, and it is not the same question
/// `samplesForEpsilonResolution` answers. Resolving ε to ±1 order is a
/// self-imposed standard no bar-clearing claim needs; AUDIT §14 records getting
/// this wrong and concluding a claim was undecidable when it was merely
/// under-sampled.
///
/// The required count depends only on how far the point estimate sits from the
/// bar. Because the bound is `σ̂·√(m/χ²₀.₀₅(m))` and `log₂ε ∝ −1/σ²`, the bound
/// clears the bar iff `|point| ≥ (m/χ²₀.₀₅(m))·|target|`. That ratio falls
/// monotonically in `m`, so there is a single threshold and a scan finds it.
///
/// Returns `nil` when the *point estimate itself* fails the bar: no amount of
/// sampling rescues a measurement whose central value is on the wrong side, and
/// callers must weaken the claim rather than buy more compute.
package func samplesToClearFailureTarget(
    sigmaHat: Double,
    threshold: Double,
    targetLog2: Double,
    confidence: Double = 0.95,
    cap: Int = 4_000_000
) -> Int? {
    guard sigmaHat > 0, threshold > 0, targetLog2.isFinite else { return nil }
    let point = log2GaussianTwoSidedTail(stddev: sigmaHat, threshold: threshold)
    // Unreachable: the bound can never be better than the point estimate.
    guard point <= targetLog2 else { return nil }

    func clears(_ m: Int) -> Bool {
        let upper = sigmaUpperConfidenceBound(
            sigmaHat: sigmaHat, samples: m, confidence: confidence
        )
        guard upper.isFinite, upper > 0 else { return false }
        return log2GaussianTwoSidedTail(stddev: upper, threshold: threshold) <= targetLog2
    }

    // Exponential bracket then bisect: the predicate is monotone in `m`.
    var hi = 2
    while hi < cap, !clears(hi) { hi *= 2 }
    guard clears(hi) else { return nil }
    var lo = max(2, hi / 2)
    while lo < hi {
        let mid = lo + (hi - lo) / 2
        if clears(mid) { hi = mid } else { lo = mid + 1 }
    }
    return lo
}

/// Asymptotic / concrete failure-probability certificate (Gaussian model).
package struct TFHEAsymptoticSecurityCertificate: Sendable, Equatable {
    package var params: TFHEGaussianParams
    package var inputWireCount: Int
    package var lutCount: Int
    package var ingestFailureProbability: Double
    package var unionFailureProbability: Double
    package var hypotheses: [String]

    package var targetEpsilon: Double {
        pow(2, Double(params.targetFailureLog2))
    }

    package var isSecure: Bool {
        unionFailureProbability <= targetEpsilon
    }

    package var failureLog2: Double {
        log2Probability(unionFailureProbability)
    }

    package init(
        params: TFHEGaussianParams,
        inputWireCount: Int,
        lutCount: Int,
        ingestFailureProbability: Double,
        unionFailureProbability: Double,
        hypotheses: [String]
    ) {
        self.params = params
        self.inputWireCount = inputWireCount
        self.lutCount = lutCount
        self.ingestFailureProbability = ingestFailureProbability
        self.unionFailureProbability = unionFailureProbability
        self.hypotheses = hypotheses
    }

    /// Certificate for HELUT encrypted netlist under noiseless BK + lattice ingest MS.
    ///
    /// Dominant failure: some primary wire has `|e| ≥ δ/2` before ingest MS.
    /// After successful ingest, PBS + publicMS keep variance 0 ⇒ no further decode fail.
    package static func forEncryptedNetlist(
        params: TFHEGaussianParams,
        inputWireCount: Int,
        lutCount: Int
    ) -> TFHEAsymptoticSecurityCertificate {
        precondition(inputWireCount >= 0 && lutCount >= 0)
        let half = params.decodingHalfGap
        let pOne = gaussianTwoSidedTail(stddev: params.sigma, threshold: half)
        // Union bound over primary input wires.
        let pUnion = min(1, Double(max(inputWireCount, 1)) * pOne)
        return TFHEAsymptoticSecurityCertificate(
            params: params,
            inputWireCount: inputWireCount,
            lutCount: lutCount,
            ingestFailureProbability: pOne,
            unionFailureProbability: pUnion,
            hypotheses: [
                "Independent Gaussian N(0,σ²) fresh encrypt noise",
                "Ingest lattice MS exact iff |e| < δ/2",
                "Noiseless BK ⇒ PBS output variance 0",
                "publicMS/secret refresh preserves floor 0 under HELUT lattice BK",
                "Union bound over primary input wires (conservative)",
                "Does not claim LWE hardness / IND-CPA reduction"
            ]
        )
    }

    package func assertSecure(file: StaticString = #file, line: UInt = #line) {
        precondition(
            isSecure,
            "TFHEAsymptoticSecurityCertificate insecure: P≈2^\(failureLog2) > 2^\(params.targetFailureLog2) at \(file):\(line)"
        )
    }
}

/// Bridge discrete-inject B into a Gaussian σ proxy (uniform[-B,B] ≲ σ = B/√3).
package func gaussianSigmaProxy(uniformBound B: UInt32) -> Double {
    Double(B) / sqrt(3)
}
