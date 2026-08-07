import Foundation

// MARK: - LWE hardness binding (graduation step 10n)
//
// Standard decision-LWE → IND-CPA binding for HELUT’s `encryptLWE` samples, plus a
// conservative classical core-SVP *estimate* for concrete parameters.
//
// This is a parameter / reduction *certificate* in the usual cryptanalytic sense —
// not a new proof that lattice problems are hard. Hypotheses are explicit below.

/// Decision-LWE instance parameters over `Z_q` with `q = 2^{32}` (HELUT torus).
package struct TFHELWEParams: Sendable, Equatable {
    package var dimension: Int
    package var logModulus: Int
    /// Gaussian error stddev on the torus (same units as `TFHEGaussianParams.sigma`).
    package var sigma: Double
    /// Binary secret (`s_i ∈ {0,1}`).
    package var binarySecret: Bool

    package init(
        dimension: Int,
        logModulus: Int = 32,
        sigma: Double,
        binarySecret: Bool = true
    ) {
        precondition(dimension > 0)
        precondition(logModulus == 32, "HELUT torus is Z_{2^{32}}")
        precondition(sigma > 0)
        self.dimension = dimension
        self.logModulus = logModulus
        self.sigma = sigma
        self.binarySecret = binarySecret
    }

    package var modulus: UInt64 { 1 << logModulus }

    /// Bind from HELUT Gaussian encrypt params (n = LWE dimension).
    package static func fromGaussian(_ g: TFHEGaussianParams) -> TFHELWEParams {
        TFHELWEParams(dimension: g.lweDimension, sigma: g.sigma, binarySecret: true)
    }
}

/// Reduction claim: HELUT LWE encrypt IND-CPA ≤ Decision-LWE.
package struct TFHELWEHardnessCertificate: Sendable, Equatable {
    package var lwe: TFHELWEParams
    package var targetSecurityBits: Int
    package var estimatedClassicalBits: Double
    package var hypotheses: [String]

    package var meetsTarget: Bool {
        estimatedClassicalBits + 1e-9 >= Double(targetSecurityBits)
    }

    package init(
        lwe: TFHELWEParams,
        targetSecurityBits: Int,
        estimatedClassicalBits: Double,
        hypotheses: [String]
    ) {
        self.lwe = lwe
        self.targetSecurityBits = targetSecurityBits
        self.estimatedClassicalBits = estimatedClassicalBits
        self.hypotheses = hypotheses
    }

    /// Certificate for HELUT’s encryption game under Decision-LWE.
    ///
    /// Reduction sketch (standard hybrid):
    /// 1. HELUT `encryptLWE(m)` = `(a, ⟨a,s⟩ + e + m)` with uniform `a`, `e ~ χ`
    /// 2. Replacing `(a, ⟨a,s⟩+e)` by uniform `(a,u)` is Decision-LWE
    /// 3. Resulting ciphertext is independent of `m` ⇒ IND-CPA
    ///
    /// Netlist evaluation / BK are public algorithms on ciphertexts; they do not
    /// open a new attack surface beyond LWE of the wire samples (under e=0 BK).
    package static func forHELUTEncrypt(
        gaussian: TFHEGaussianParams,
        targetSecurityBits: Int = 128
    ) -> TFHELWEHardnessCertificate {
        let lwe = TFHELWEParams.fromGaussian(gaussian)
        let bits = estimateClassicalCoreSVPBits(lwe: lwe)
        return TFHELWEHardnessCertificate(
            lwe: lwe,
            targetSecurityBits: targetSecurityBits,
            estimatedClassicalBits: bits,
            hypotheses: [
                "Decision-LWE(n=\(lwe.dimension), q=2^\(lwe.logModulus), χ=N(0,σ²)) is hard",
                "HELUT encryptLWE samples are exact LWE instances (binary secret)",
                "Standard hybrid: LWE → IND-CPA for single encrypt",
                "BK treated as public; noiseless BK does not add fresh LWE samples to attack",
                "Classical core-SVP estimate is calibrated (TFHELWECalibration), not a lattice-estimator run",
                "Quantum / polynomial-memory / side-channel attacks out of scope"
            ]
        )
    }

    package func assertMeetsTarget(file: StaticString = #file, line: UInt = #line) {
        precondition(
            meetsTarget,
            "TFHELWEHardnessCertificate: est \(estimatedClassicalBits) bits < target \(targetSecurityBits) at \(file):\(line)"
        )
    }
}

/// Conservative classical core-SVP *estimate* for binary-secret LWE (step 10n/10o).
///
/// Least-squares fit to `TFHELWECalibration.anchors` (TFHE-style boolean
/// ballparks at q=2³²). Not a lattice-estimator run — verify before production
/// key sizes. Domain: n ≥ 128; smaller n uses a trivial exhaustive-search floor.
///
/// Shape (binary secret, n ≥ 128):
/// `bits ≈ 0.1566·n − 15.04·log₂σ + 256`
package func estimateClassicalCoreSVPBits(lwe: TFHELWEParams) -> Double {
    let n = Double(lwe.dimension)
    // Out of calibration domain: binary secret is at most ~n-bit exhaustive.
    if lwe.dimension < 128 {
        let floor = lwe.binarySecret ? 0.5 * n : 0.25 * n
        return max(floor, 0)
    }
    let logSigma = log2(max(lwe.sigma, 1))
    // Fit coefficients: see TFHELWECalibration (step 10o).
    var bits = 0.156625 * n - 15.042862 * logSigma + 256.007839
    if !lwe.binarySecret {
        bits -= 10
    }
    return max(bits, 0)
}

/// Production LWE binding: same (n,σ) as `TFHEGaussianParams.productionBoolean64`.
package enum TFHELWEProduction {
    package static func certificate128() -> TFHELWEHardnessCertificate {
        TFHELWEHardnessCertificate.forHELUTEncrypt(
            gaussian: .productionBoolean64(polynomialDegree: 1024),
            targetSecurityBits: 128
        )
    }
}
