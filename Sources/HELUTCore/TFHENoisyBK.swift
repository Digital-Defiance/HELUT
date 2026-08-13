import Foundation

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
        params: TFHENoisyBKParams
    ) -> TFHENoisyBKCertificate {
        TFHENoisyBKCertificate(
            params: params,
            hypotheses: [
                "After BR, extracted LWE noise |e| ≤ B_bk=\(params.outputNoiseBound)",
                "publicMS / decode requires |e| < δ/2 = \(params.decodingHalfGap)",
                "Each LUT is an independent BR → same floor (no cumulative BR noise under refresh)",
                params.outputNoiseBound == 0
                    ? "HELUT current BK encrypt is noiseless (e=0 gadget) — production stacks use noisy BK"
                    : "Noisy BK floor is an engineering bound; replace with measured/σ model for production",
                "Does not replace TFHEAsymptoticSecurityCertificate Gaussian ingest analysis"
            ]
        )
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
