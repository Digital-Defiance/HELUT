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
