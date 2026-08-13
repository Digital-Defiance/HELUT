import Foundation
import Darwin

// MARK: - Noisy BK depth certificate (research-release / step 10p)
//
// HELUT’s default BK path is e=0 (noiseless gadget encrypt). Production TFHE
// uses noisy BK; this module makes the depth / failure story *explicit* so the
// ε-certificate’s “noiseless BK” hypothesis is not silent.
//
// Under publicMS after each BR: decode/MS succeeds iff |e| < δ/2. With BK body
// noise bound B_bk (∞-norm) or Gaussian σ_bk, every LUT is a fresh failure event.

/// Discrete ∞-norm BK noise floor after one blind-rotate.
package struct TFHENoisyBKParams: Sendable, Equatable {
    /// Worst-case centered |e| on the extracted LWE after BR (torus).
    package var outputNoiseBound: UInt32
    package var delta: UInt32
    package var lutCount: Int

    package init(outputNoiseBound: UInt32, delta: UInt32, lutCount: Int) {
        precondition(delta >= 2)
        precondition(lutCount >= 0)
        self.outputNoiseBound = outputNoiseBound
        self.delta = delta
        self.lutCount = lutCount
    }

    package var decodingHalfGap: UInt32 { delta / 2 }

    /// HELUT e=0 BK (current Metal/CPU crypto gadget encrypt).
    package static func noiseless(polynomialDegree n: Int, lutCount: Int) -> TFHENoisyBKParams {
        TFHENoisyBKParams(
            outputNoiseBound: 0,
            delta: rotationScale(polynomialDegree: n),
            lutCount: lutCount
        )
    }

    /// Conservative engineering floor: B_bk = σ-scale inject bound.
    package static func bounded(
        outputNoiseBound: UInt32,
        polynomialDegree n: Int,
        lutCount: Int
    ) -> TFHENoisyBKParams {
        TFHENoisyBKParams(
            outputNoiseBound: outputNoiseBound,
            delta: rotationScale(polynomialDegree: n),
            lutCount: lutCount
        )
    }
}

/// Depth / decodability certificate under noisy (or noiseless) BK.
package struct TFHENoisyBKCertificate: Sendable, Equatable {
    package var params: TFHENoisyBKParams
    package var hypotheses: [String]

    package var eachLUTDecodable: Bool {
        UInt64(params.outputNoiseBound) < UInt64(params.decodingHalfGap)
    }

    /// Under publicMS-per-LUT, circuit depth in LUTs is unlimited iff each BR is decodable.
    package var unboundedDepthUnderPublicMS: Bool { eachLUTDecodable }

    /// Max LUT count before a forced undecodable state (∞ if each LUT OK).
    package var maxSafeLUTCount: Int {
        eachLUTDecodable ? Int.max : 0
    }

    package var meetsHELUTNoiselessHypothesis: Bool {
        params.outputNoiseBound == 0
    }

    package init(params: TFHENoisyBKParams, hypotheses: [String]) {
        self.params = params
        self.hypotheses = hypotheses
    }

    package static func forNetlist(
        params: TFHENoisyBKParams,
        measurement: TFHENoisyBKMeasurement? = nil
    ) -> TFHENoisyBKCertificate {
        var hypotheses = [
            "After BR, extracted LWE noise |e| ≤ B_bk=\(params.outputNoiseBound)",
            "publicMS / decode requires |e| < δ/2 = \(params.decodingHalfGap)",
            "Each LUT is an independent BR → same floor (no cumulative BR noise under refresh)",
            "Does not replace TFHEAsymptoticSecurityCertificate Gaussian ingest analysis"
        ]
        if let measurement {
            hypotheses.insert(
                "B_bk measured from identity-LUT residual "
                    + "(trials=\(measurement.samples), inject B=\(measurement.injectBound), "
                    + String(format: "σ̂=%.1f", measurement.sigmaHat)
                    + ", decode_fail=\(measurement.decodeFailures))",
                at: 3
            )
        } else if params.outputNoiseBound == 0 {
            hypotheses.insert(
                "HELUT default BK encrypt is noiseless (e=0 gadget) — production stacks use noisy BK",
                at: 3
            )
        } else {
            hypotheses.insert(
                "Noisy BK floor is an engineering bound; prefer TFHENoisyBKMeasurement for production",
                at: 3
            )
        }
        return TFHENoisyBKCertificate(params: params, hypotheses: hypotheses)
    }

    package func assertDecodable(file: StaticString = #file, line: UInt = #line) {
        precondition(
            eachLUTDecodable,
            "TFHENoisyBKCertificate undecodable B_bk=\(params.outputNoiseBound) half=\(params.decodingHalfGap) at \(file):\(line)"
        )
    }
}

/// Gaussian BK output noise → per-LUT MS failure after BR (research-release).
package struct TFHENoisyBKGaussianCertificate: Sendable, Equatable {
    package var sigmaBK: Double
    package var delta: UInt32
    package var lutCount: Int
    package var perLUTFailureProbability: Double
    package var unionFailureProbability: Double
    package var targetFailureLog2: Int

    package var isSecure: Bool {
        unionFailureProbability <= pow(2, Double(targetFailureLog2))
    }

    package var failureLog2: Double {
        log2Probability(unionFailureProbability)
    }

    /// Union bound over `lutCount` independent post-BR MS events.
    package static func forDepth(
        sigmaBK: Double,
        polynomialDegree n: Int,
        lutCount: Int,
        targetFailureLog2: Int = -64
    ) -> TFHENoisyBKGaussianCertificate {
        precondition(sigmaBK >= 0)
        precondition(lutCount >= 0)
        let delta = rotationScale(polynomialDegree: n)
        let half = Double(delta) / 2
        let pOne: Double
        if sigmaBK == 0 {
            pOne = 0
        } else {
            pOne = gaussianTwoSidedTail(stddev: sigmaBK, threshold: half)
        }
        let pUnion = min(1, Double(max(lutCount, 1)) * pOne)
        return TFHENoisyBKGaussianCertificate(
            sigmaBK: sigmaBK,
            delta: delta,
            lutCount: lutCount,
            perLUTFailureProbability: pOne,
            unionFailureProbability: pUnion,
            targetFailureLog2: targetFailureLog2
        )
    }
}

/// Apply noisy-BK floor to a `TFHENoiseGrowth` tracker (one BR).
extension TFHENoiseGrowth {
    package mutating func afterBlindRotate(noisyBK params: TFHENoisyBKParams) {
        afterBlindRotate(outputNoiseBound: params.outputNoiseBound)
    }
}

/// Centered torus magnitude: `min(x, q−x)` on `UInt32`.
package func torusCenteredMagnitude(_ x: UInt32) -> UInt32 {
    x <= 0x8000_0000 ? x : UInt32(0) &- x
}

/// Empirical post-BR residual under a (possibly noisy) bootstrap key.
/// Identity LUT: encrypt bit `b`, PBS `[0,1]`, compare phase to `b·δ`.
package struct TFHENoisyBKMeasurement: Sendable, Equatable {
    package var maxAbsError: UInt32
    package var rms: Double
    package var samples: Int
    package var injectBound: UInt32
    package var delta: UInt32
    package var polynomialDegree: Int
    package var decodeFailures: Int

    package var sigmaHat: Double { rms }

    package var decodingHalfGap: UInt32 { delta / 2 }

    package var eachLUTDecodable: Bool {
        UInt64(maxAbsError) < UInt64(decodingHalfGap)
    }

    package init(
        maxAbsError: UInt32,
        rms: Double,
        samples: Int,
        injectBound: UInt32,
        delta: UInt32,
        polynomialDegree: Int,
        decodeFailures: Int
    ) {
        self.maxAbsError = maxAbsError
        self.rms = rms
        self.samples = samples
        self.injectBound = injectBound
        self.delta = delta
        self.polynomialDegree = polynomialDegree
        self.decodeFailures = decodeFailures
    }

    package func certificate(lutCount: Int) -> TFHENoisyBKCertificate {
        TFHENoisyBKCertificate.forNetlist(
            params: .bounded(
                outputNoiseBound: maxAbsError,
                polynomialDegree: polynomialDegree,
                lutCount: lutCount
            ),
            measurement: self
        )
    }

    package func gaussianCertificate(
        lutCount: Int,
        targetFailureLog2: Int = -64
    ) -> TFHENoisyBKGaussianCertificate {
        TFHENoisyBKGaussianCertificate.forDepth(
            sigmaBK: sigmaHat,
            polynomialDegree: polynomialDegree,
            lutCount: lutCount,
            targetFailureLog2: targetFailureLog2
        )
    }

    /// Identity-LUT BR residual. Uses `existing` BK when provided (no extra encrypt).
    package static func identity(
        secret: TFHESecretKey,
        params: GGSWParams,
        noise: TFHENoiseParams = .none,
        bootstrapKey existing: BootstrapKey? = nil,
        trials: Int = 16,
        seed: UInt32 = 0xB10C,
        publicRefreshCompatible: Bool = true
    ) -> TFHENoisyBKMeasurement {
        precondition(trials > 0)
        let n = params.tfhe.polynomialDegree
        let twoN = 2 * n
        let scale = rotationScale(polynomialDegree: n)
        var rng = LCG32(state: seed == 0 ? 1 : seed)
        let bk = existing ?? bootstrapKey(
            secret: secret,
            params: params,
            rng: &rng,
            publicRefreshCompatible: publicRefreshCompatible,
            noise: noise
        )
        var maxAbs: UInt32 = 0
        var sumSq: Double = 0
        var failures = 0
        let identity: [UInt32] = [0, 1]
        for _ in 0..<trials {
            let bit = rng.next() & 1
            let lwe = encryptLWERotationNative(
                message: bit,
                secret: secret.lweSecret,
                twoN: twoN,
                rng: &rng
            )
            let out = evaluateLUTBlindRotate(
                truthTable: identity,
                inputs: [lwe],
                bootstrapKey: bk,
                scale: scale
            )
            let phase = decryptLWE(out, secret: secret)
            let expected = bit &* scale
            let err = torusCenteredMagnitude(phase &- expected)
            if err > maxAbs { maxAbs = err }
            sumSq += Double(err) * Double(err)
            if decodeRotationBoolean(phase, scale: scale) != bit {
                failures += 1
            }
        }
        return TFHENoisyBKMeasurement(
            maxAbsError: maxAbs,
            rms: sqrt(sumSq / Double(trials)),
            samples: trials,
            injectBound: noise.bound,
            delta: scale,
            polynomialDegree: n,
            decodeFailures: failures
        )
    }

    package static func markdownTable(_ rows: [TFHENoisyBKMeasurement]) -> String {
        var lines = [
            "| gadget N | inject B | trials | max |e| | σ̂ | δ/2 | decode fail | decodable |",
            "|----------|----------|--------|---------|-----|-----|-------------|-----------|"
        ]
        for row in rows {
            let ok = row.eachLUTDecodable && row.decodeFailures == 0 ? "yes" : "no"
            lines.append(
                "| \(row.polynomialDegree) | \(row.injectBound) | \(row.samples) | \(row.maxAbsError) | "
                    + String(format: "%.1f", row.sigmaHat) + " | \(row.decodingHalfGap) | "
                    + "\(row.decodeFailures) | \(ok) |"
            )
        }
        return lines.joined(separator: "\n")
    }
}
