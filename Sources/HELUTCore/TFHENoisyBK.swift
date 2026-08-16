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
//
// Measurement (`TFHENoisyBKMeasurement`) requires a covering gadget
// (baseLog·ℓ = 32). ℓ=1 booleanPublicMS is a noiseless δ-lattice vehicle:
// BK noise leaves the lattice and later CMUXes mis-decompose.

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
            let provenance = measurement.isAccumulatorSampled
                ? "\(measurement.bootstraps) PBS × \(measurement.polynomialDegree) "
                    + "accumulator coeffs = \(measurement.samples) residuals, "
                    + "credited \(measurement.effectiveSamples) independent"
                : "trials=\(measurement.samples)"
            hypotheses.insert(
                "B_bk measured from identity-LUT residual "
                    + "(\(provenance), inject B=\(measurement.injectBound), "
                    + String(format: "σ̂=%.1f", measurement.sigmaHat)
                    + ", decode_fail=\(measurement.decodeFailures))",
                at: 3
            )
            // σ̂ is an RMS over the residuals and log₂ε ∝ −1/σ̂², so the sample
            // size, not the arithmetic, sets how much of ε is real. The count
            // quoted here is the *effective* one: accumulator coefficients are
            // correlated, and crediting all of them would tighten the bound
            // beyond what the data supports.
            hypotheses.insert(
                String(
                    format:
                        "ε sampling uncertainty: σ̂ from %d effective samples ⇒ log₂ε "
                        + "unresolved to ±%.0f orders; point %.1f, 95%% upper bound %.1f; "
                        + "±1 order would need ~%d effective samples",
                    measurement.effectiveSamples,
                    measurement.epsilonUnresolvedOrders,
                    measurement.failureLog2Point,
                    measurement.failureLog2Upper95,
                    measurement.samplesForOneOrder
                ),
                at: 4
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
        if sigmaBK == 0 {
            return -Double.infinity
        }
        let half = Double(delta) / 2
        let log2One = log2GaussianTwoSidedTail(stddev: sigmaBK, threshold: half)
        // Union bound: P_union ≤ lutCount · P_one ⇒ log2 ≤ log2(lutCount) + log2(P_one)
        let n = max(lutCount, 1)
        if log2One.isInfinite && log2One < 0 {
            return log2One
        }
        let log2Union = log2(Double(n)) + log2One
        return min(0, log2Union)
    }

    /// Union bound over `lutCount` independent post-BR MS events.
    package static func forDepth(
        sigmaBK: Double,
        polynomialDegree n: Int,
        lutCount: Int,
        targetFailureLog2: Int = -64
    ) -> TFHENoisyBKGaussianCertificate {
        forDepth(
            sigmaBK: sigmaBK,
            delta: rotationScale(polynomialDegree: n),
            lutCount: lutCount,
            targetFailureLog2: targetFailureLog2
        )
    }

    package static func forDepth(
        sigmaBK: Double,
        delta: UInt32,
        lutCount: Int,
        targetFailureLog2: Int = -64
    ) -> TFHENoisyBKGaussianCertificate {
        precondition(sigmaBK >= 0)
        precondition(delta >= 2)
        precondition(lutCount >= 0)
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

    // MARK: Sample provenance
    //
    // `samples` is a count of *residuals*, which is not the same thing as a
    // count of bootstraps. The single-residual estimator (`identity`) draws one
    // residual per PBS, so the two agree. The accumulator estimator
    // (`identityAllCoefficients`) draws N residuals per PBS, so `samples` is
    // ~N× `bootstraps`. The χ² confidence bound assumes independent samples, so
    // any caller quoting a bound from the accumulator estimator has to know
    // which of the two it is holding. Hence this field rather than a comment.

    /// Number of PBS evaluations behind `samples`. Equals `samples` for the
    /// single-residual estimator.
    package var bootstraps: Int

    /// Effective *independent* sample count backing `rms`, which is what a
    /// confidence bound may divide by.
    ///
    /// For the single-residual estimator this is `samples`: one residual per
    /// bootstrap, genuinely independent. For the accumulator estimator it is
    /// **not** `samples`. The N residuals from one bootstrap share the same
    /// GGSW external-product error, so they are identically distributed but
    /// correlated, and the measured effective count per bootstrap is a flat
    /// 7.7–11.7 across N ∈ {32,64,128,256} rather than N
    /// (`TFHENoisyBKEffectiveSampleTests`). Quoting `samples` here would make
    /// `sigmaUpper95` too tight, i.e. ε too good — the dangerous direction.
    package var effectiveSamples: Int

    /// Max |residual| over *all* accumulator coefficients, when measured.
    /// `nil` for the single-residual estimator, which only ever sees
    /// coefficient 0. Kept distinct from `maxAbsError` because decodability is
    /// a property of the extracted coefficient, not of the whole accumulator.
    package var accumulatorMaxAbsError: UInt32?

    /// Whether `samples` counts accumulator coefficients rather than bootstraps.
    package var isAccumulatorSampled: Bool { bootstraps != samples }

    package var sigmaHat: Double { rms }

    package var decodingHalfGap: UInt32 { delta / 2 }

    // MARK: Sampling uncertainty
    //
    // `rms` is an RMS over exactly `samples` observations (one residual per
    // trial), and ε is an analytic tail evaluated at it. Because log₂ε ∝ −1/σ̂²,
    // small-sample error in σ̂ dominates ε. These accessors exist so no caller
    // can quote ε against a bar without also seeing what the sample size can
    // actually resolve. See the 2026-08-15 re-validation of C35.

    /// One-sided 95% upper confidence bound on σ from this sample.
    ///
    /// Divides by `effectiveSamples`, not `samples`. The two differ only for the
    /// accumulator estimator, where correlated coefficients make the raw
    /// residual count an overstatement of independence.
    package var sigmaUpper95: Double {
        sigmaUpperConfidenceBound(sigmaHat: sigmaHat, samples: effectiveSamples)
    }

    /// `log₂ε` recomputed at `sigmaUpper95` — the conservative figure, and the
    /// only one that should be compared against a target such as 2⁻⁶⁴.
    package var failureLog2Upper95: Double {
        guard sigmaUpper95.isFinite, sigmaUpper95 > 0 else { return 0 }
        return log2GaussianTwoSidedTail(
            stddev: sigmaUpper95,
            threshold: Double(decodingHalfGap)
        )
    }

    /// `log₂ε` at the point estimate of σ̂ (what the tool historically printed).
    package var failureLog2Point: Double {
        guard sigmaHat > 0 else { return -Double.infinity }
        return log2GaussianTwoSidedTail(
            stddev: sigmaHat,
            threshold: Double(decodingHalfGap)
        )
    }

    /// Orders of `log₂ε` this sample size cannot resolve. Uses the effective
    /// count for the same reason `sigmaUpper95` does.
    package var epsilonUnresolvedOrders: Double {
        epsilonResolutionOrders(failureLog2: failureLog2Point, samples: effectiveSamples)
    }

    /// Whether the target bar is met at the 95% upper bound, not merely at the
    /// point estimate.
    package func meetsTargetWithConfidence(targetLog2: Double) -> Bool {
        failureLog2Upper95 <= targetLog2
    }

    /// Samples needed to resolve ε to ±1 order at this magnitude.
    ///
    /// Usually *not* the number you want — see `samplesToMeetTarget`. Resolving
    /// to ±1 order is far stricter than clearing a bar, and conflating the two
    /// led to declaring C35 undecidable when it was only under-sampled
    /// (AUDIT §13 vs §14).
    package var samplesForOneOrder: Int {
        samplesForEpsilonResolution(failureLog2: failureLog2Point)
    }

    /// Smallest sample count whose 95% bound would clear `targetLog2`, or `nil`
    /// if no sample count can because the point estimate already fails.
    ///
    /// Lets a caller distinguish the two ways a bar goes unmet, which need
    /// opposite responses:
    ///
    ///  - **under-sampled** — point estimate clears, bound does not. Buy more
    ///    trials. C35 and C36 are this.
    ///  - **genuinely unmet** — point estimate itself fails. More trials are
    ///    wasted compute; the claim has to be weakened. C55 and C56 are this,
    ///    and both already say so.
    package func samplesToMeetTarget(targetLog2: Double = -64) -> Int? {
        samplesToClearFailureTarget(
            sigmaHat: sigmaHat,
            threshold: Double(decodingHalfGap),
            targetLog2: targetLog2
        )
    }

    /// Whether this measurement's *sample size* is what stands between it and
    /// the bar. True means more trials would settle it.
    package func isUnderSampledForTarget(targetLog2: Double = -64) -> Bool {
        guard !meetsTargetWithConfidence(targetLog2: targetLog2) else { return false }
        return samplesToMeetTarget(targetLog2: targetLog2) != nil
    }

    package var eachLUTDecodable: Bool {
        UInt64(maxAbsError) < UInt64(decodingHalfGap)
    }

    /// Independent samples one bootstrap is credited with under accumulator
    /// sampling.
    ///
    /// Measured gain is 7.7–11.7 across N ∈ {32,64,128,256}, flat in N rather
    /// than proportional to it, and mildly *decreasing* with N
    /// (`TFHENoisyBKEffectiveSampleTests`). This constant sits below the lowest
    /// measured value on purpose: the estimate feeds a confidence bound, and
    /// crediting too many independent samples makes that bound too tight. Under
    /// -crediting only costs sample size. It is not extrapolated to N=1024,
    /// where no measurement has been taken.
    package static let accumulatorSampleGain = 4

    package init(
        maxAbsError: UInt32,
        rms: Double,
        samples: Int,
        injectBound: UInt32,
        delta: UInt32,
        polynomialDegree: Int,
        decodeFailures: Int,
        bootstraps: Int? = nil,
        accumulatorMaxAbsError: UInt32? = nil,
        effectiveSamples: Int? = nil
    ) {
        self.maxAbsError = maxAbsError
        self.rms = rms
        self.samples = samples
        self.injectBound = injectBound
        self.delta = delta
        self.polynomialDegree = polynomialDegree
        self.decodeFailures = decodeFailures
        let pbs = bootstraps ?? samples
        self.bootstraps = pbs
        self.accumulatorMaxAbsError = accumulatorMaxAbsError
        if let effectiveSamples {
            self.effectiveSamples = effectiveSamples
        } else if pbs == samples {
            // Single-residual estimator: one independent draw per bootstrap.
            self.effectiveSamples = samples
        } else {
            // Accumulator estimator: credit the conservative measured gain, and
            // never more than the residuals actually collected.
            self.effectiveSamples = min(
                samples,
                max(1, pbs * TFHENoisyBKMeasurement.accumulatorSampleGain)
            )
        }
    }

    package func certificate(lutCount: Int) -> TFHENoisyBKCertificate {
        TFHENoisyBKCertificate.forNetlist(
            params: TFHENoisyBKParams(
                outputNoiseBound: maxAbsError,
                delta: delta,
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
            delta: delta,
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
        publicRefreshCompatible: Bool = true,
        booleanScaleMul: Int = 1
    ) -> TFHENoisyBKMeasurement {
        precondition(trials > 0)
        let n = params.tfhe.polynomialDegree
        let twoN = 2 * n
        let scale = rotationBooleanScale(polynomialDegree: n, mul: booleanScaleMul)
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
                message: encodeRotationNativeBit(bit, k: booleanScaleMul),
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

    /// Identity-LUT BR residual measured across **every** accumulator
    /// coefficient instead of only the extracted one.
    ///
    /// Why this exists: `identity` above runs a full PBS and then keeps a single
    /// scalar residual, discarding the other N−1 coefficients of the GLWE
    /// accumulator. Since log₂ε ∝ −1/σ̂², the sample size needed to pin ε down
    /// grows fast, and at N=1024 the single-residual estimator needs ~8 450
    /// bootstraps to resolve ε to ±1 order — about eight days. The discarded
    /// coefficients carry noise from the same distribution, so measuring all of
    /// them yields ~N residuals per bootstrap at no extra cryptographic cost.
    ///
    /// How the reference is obtained: blind rotate leaves
    /// `ACC = X^{−p}·v` where `p = b − Σ_j a_j s_j` is the LWE phase in `Z_2N`.
    /// This is a self-test, so `s` is in hand and `p` is computable exactly —
    /// no decryption of a noisy quantity is involved in forming the reference.
    /// Rotating the test polynomial by that exact power gives the noiseless
    /// accumulator, and the residual is the difference. An approximate
    /// reference would contaminate the estimate, which is why the power is
    /// recomputed from the secret rather than inferred from the output.
    ///
    /// Independence caveat, stated because it bears on the confidence bound:
    /// the per-coefficient residuals are identically distributed but only
    /// *approximately* independent — the CMUX ladder mixes external-product
    /// error across coefficients. `bootstraps` is therefore recorded alongside
    /// `samples` so a caller can compare the two estimators and see whether the
    /// effective sample size is really N per PBS.
    /// `TFHENoisyBKAccumulatorAgreement` does exactly that.
    package static func identityAllCoefficients(
        secret: TFHESecretKey,
        params: GGSWParams,
        noise: TFHENoiseParams = .none,
        bootstrapKey existing: BootstrapKey? = nil,
        trials: Int = 16,
        seed: UInt32 = 0xB10C,
        publicRefreshCompatible: Bool = true,
        booleanScaleMul: Int = 1
    ) -> TFHENoisyBKMeasurement {
        precondition(trials > 0)
        let n = params.tfhe.polynomialDegree
        let twoN = 2 * n
        let scale = rotationBooleanScale(polynomialDegree: n, mul: booleanScaleMul)
        var rng = LCG32(state: seed == 0 ? 1 : seed)
        let bk = existing ?? bootstrapKey(
            secret: secret,
            params: params,
            rng: &rng,
            publicRefreshCompatible: publicRefreshCompatible,
            noise: noise
        )
        let identity: [UInt32] = [0, 1]
        let testPoly = TFHETestPolyCache.shared.testPolynomial(
            truthTable: identity,
            degree: n,
            scale: scale
        )
        let s = secret.lweSecret

        var extractedMaxAbs: UInt32 = 0
        var accMaxAbs: UInt32 = 0
        var sumSq: Double = 0
        var sampleCount = 0
        var failures = 0

        for _ in 0..<trials {
            let bit = rng.next() & 1
            let lwe = encryptLWERotationNative(
                message: encodeRotationNativeBit(bit, k: booleanScaleMul),
                secret: s,
                twoN: twoN,
                rng: &rng
            )
            let packed = packLWEBits([lwe], twoN: twoN)
            let acc = blindRotate(
                testPolynomial: testPoly,
                lwe: packed,
                bootstrapKey: bk
            )

            // Exact noiseless accumulator: X^{−p}·v, p the LWE phase in Z_2N.
            var rotation = -rotationPower(packed.b, twoN: twoN)
            for j in 0..<packed.lweDimension where s[j] == 1 {
                rotation += rotationPower(packed.a[j], twoN: twoN)
            }
            let reference = negacyclicMultiplyByXPower(testPoly, power: rotation)

            let phases = decryptGLWE(acc, secret: secret)
            precondition(phases.count == n && reference.count == n)
            for i in 0..<n {
                let err = torusCenteredMagnitude(phases[i] &- reference[i])
                if err > accMaxAbs { accMaxAbs = err }
                sumSq += Double(err) * Double(err)
            }
            sampleCount += n

            // Coefficient 0 is what `sampleExtractLWE` lifts, so decodability
            // and the extracted-residual max stay defined on it alone — same
            // semantics as `identity` above.
            let err0 = torusCenteredMagnitude(phases[0] &- reference[0])
            if err0 > extractedMaxAbs { extractedMaxAbs = err0 }
            if decodeRotationBoolean(phases[0], scale: scale) != bit {
                failures += 1
            }
        }

        return TFHENoisyBKMeasurement(
            maxAbsError: extractedMaxAbs,
            rms: sqrt(sumSq / Double(sampleCount)),
            samples: sampleCount,
            injectBound: noise.bound,
            delta: scale,
            polynomialDegree: n,
            decodeFailures: failures,
            bootstraps: trials,
            accumulatorMaxAbsError: accMaxAbs
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
