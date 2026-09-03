import XCTest
@testable import HELUTCore

/// Does sampling every accumulator coefficient measure the same noise the
/// single-residual estimator measures?
///
/// The single-residual estimator keeps one scalar per bootstrap, so pinning ε
/// down at N=1024 needs ~8 450 bootstraps — about eight days. The GLWE
/// accumulator carries N coefficients whose noise comes from the same
/// distribution, so measuring all of them is ~1000× cheaper for identical
/// cryptographic work. That is only legitimate if the two estimators agree on
/// the quantity being measured, which is what these tests check.
///
/// Kept cheap on purpose: small degrees, single-digit-to-hundreds trial counts.
final class TFHENoisyBKAccumulatorTests: XCTestCase {

    /// Covering gadget (baseLog·ℓ = 32, g₀ = δ) — the configuration the ε
    /// claims are actually quoted at.
    private func rig(degree: Int) -> (TFHESecretKey, GGSWParams) {
        let params = GGSWParams.cryptoPublicMS(degree: degree)
        let secret = TFHESecretKey.random(params: params.tfhe, seed: 0xB401)
        return (secret, params)
    }

    /// The reference must be *exact*. Sample-extract lifts coefficient 0
    /// (`b: ciphertext.body[0]`), so if the rotation power were recomputed even
    /// slightly wrong, coefficient 0 would disagree with the residual the old
    /// estimator sees.
    ///
    /// This is the correctness gate for the whole approach. Same seed and same
    /// parameters mean the RNG streams coincide trial for trial, so the
    /// comparison is exact rather than statistical.
    func testCoefficientZeroReproducesExtractedResidual() {
        for degree in [8, 16] {
            let (secret, params) = rig(degree: degree)
            let noise = TFHENoiseParams(bound: 4)

            let old = TFHENoisyBKMeasurement.identity(
                secret: secret, params: params, noise: noise,
                trials: 6, seed: 0xA11CE
            )
            let new = TFHENoisyBKMeasurement.identityAllCoefficients(
                secret: secret, params: params, noise: noise,
                trials: 6, seed: 0xA11CE
            )

            XCTAssertEqual(
                new.maxAbsError, old.maxAbsError,
                """
                N=\(degree): extracted max |e| disagrees — accumulator \
                coefficient 0 gave \(new.maxAbsError), sample-extract gave \
                \(old.maxAbsError). Either the exact reference is wrong or the \
                RNG streams diverged.
                """
            )
            XCTAssertEqual(new.decodeFailures, old.decodeFailures)
        }
    }

    /// Sample provenance has to be visible on the measurement. A caller holding
    /// one must be able to tell N-coefficient residuals from independent
    /// bootstraps, because the χ² confidence bound assumes independence.
    func testSampleProvenanceIsRecorded() {
        let degree = 16
        let (secret, params) = rig(degree: degree)
        let trials = 5

        let acc = TFHENoisyBKMeasurement.identityAllCoefficients(
            secret: secret, params: params, noise: TFHENoiseParams(bound: 4),
            trials: trials, seed: 0xBEE5
        )
        XCTAssertEqual(acc.bootstraps, trials)
        XCTAssertEqual(acc.samples, trials * degree)
        XCTAssertTrue(acc.isAccumulatorSampled)
        XCTAssertNotNil(acc.accumulatorMaxAbsError)
        // Whole-accumulator worst case cannot be smaller than coefficient 0's.
        XCTAssertGreaterThanOrEqual(acc.accumulatorMaxAbsError!, acc.maxAbsError)

        let single = TFHENoisyBKMeasurement.identity(
            secret: secret, params: params, noise: TFHENoiseParams(bound: 4),
            trials: trials, seed: 0xBEE5
        )
        XCTAssertFalse(single.isAccumulatorSampled)
        XCTAssertEqual(single.bootstraps, single.samples)
        XCTAssertNil(single.accumulatorMaxAbsError)
    }

    /// The payoff, asserted so it cannot rot: the accumulator estimator reaches
    /// N× the sample count for the same number of bootstraps.
    func testSampleEfficiencyGain() {
        let degree = 16
        let (secret, params) = rig(degree: degree)
        let noise = TFHENoiseParams(bound: 4)

        let acc = TFHENoisyBKMeasurement.identityAllCoefficients(
            secret: secret, params: params, noise: noise,
            trials: 4, seed: 0xF00D
        )
        let single = TFHENoisyBKMeasurement.identity(
            secret: secret, params: params, noise: noise,
            trials: 4, seed: 0xF00D
        )
        XCTAssertEqual(acc.samples, single.samples * degree)
        XCTAssertEqual(acc.bootstraps, single.bootstraps)
    }

    /// A noiseless bootstrap key must give an exactly zero residual across the
    /// *whole* accumulator, not just at coefficient 0. This is what proves the
    /// reference is the true noiseless accumulator: with no noise injected there
    /// is nothing for a wrong reference to hide behind.
    func testNoiselessKeyGivesZeroResidualEverywhere() {
        let degree = 16
        let (secret, params) = rig(degree: degree)

        let quiet = TFHENoisyBKMeasurement.identityAllCoefficients(
            secret: secret, params: params, noise: .none,
            trials: 4, seed: 0xC0FFEE
        )
        XCTAssertEqual(
            quiet.accumulatorMaxAbsError, 0,
            """
            noiseless BK left a residual of \
            \(quiet.accumulatorMaxAbsError ?? .max) somewhere in the \
            accumulator, so the exact reference X^{-p}·v is not exact.
            """
        )
        XCTAssertEqual(quiet.maxAbsError, 0)
        XCTAssertEqual(quiet.sigmaHat, 0)
        XCTAssertEqual(quiet.decodeFailures, 0)
    }

    /// σ̂ from the two estimators must describe the same distribution. This is
    /// the substantive claim and the one that could actually fail: if the CMUX
    /// ladder concentrated noise into the extracted coefficient, the accumulator
    /// σ̂ would read low and every ε bound built on it would be optimistic —
    /// the dangerous direction.
    ///
    /// Tolerance is deliberately loose. The point is to catch systematic bias,
    /// not to assert agreement to three digits at these trial counts.
    func testSigmaAgreesBetweenEstimators() {
        let degree = 16
        let (secret, params) = rig(degree: degree)
        let noise = TFHENoiseParams(bound: 8)

        let acc = TFHENoisyBKMeasurement.identityAllCoefficients(
            secret: secret, params: params, noise: noise,
            trials: 32, seed: 0x1234
        )
        // Many bootstraps for the single-residual estimator so its own σ̂ is not
        // dominated by small-sample error.
        let single = TFHENoisyBKMeasurement.identity(
            secret: secret, params: params, noise: noise,
            trials: 600, seed: 0x1234
        )

        XCTAssertGreaterThan(acc.sigmaHat, 0)
        XCTAssertGreaterThan(single.sigmaHat, 0)
        let ratio = acc.sigmaHat / single.sigmaHat
        XCTAssertTrue(
            ratio > 0.5 && ratio < 2.0,
            """
            σ̂ ratio \(ratio) outside [0.5, 2.0]. accumulator σ̂=\(acc.sigmaHat) \
            over \(acc.samples) residuals (\(acc.bootstraps) PBS); \
            single-residual σ̂=\(single.sigmaHat) over \(single.samples) PBS. \
            A ratio below 1 means the accumulator estimator reads low, which \
            makes any ε bound derived from it optimistic.
            """
        )
    }
}

/// Safety properties of the confidence bound under accumulator sampling.
///
/// The accumulator estimator collects ~N residuals per bootstrap but they are
/// correlated, so `samples` overstates independence. If a bound divided by
/// `samples`, switching estimators would appear to buy confidence that was never
/// measured — ε would look better for free. These tests pin that shut.
final class TFHENoisyBKAccumulatorBoundSafetyTests: XCTestCase {

    private func rig(degree: Int) -> (TFHESecretKey, GGSWParams) {
        let params = GGSWParams.cryptoPublicMS(degree: degree)
        let secret = TFHESecretKey.random(params: params.tfhe, seed: 0xB401)
        return (secret, params)
    }

    /// Effective samples must be far below the raw residual count, and must not
    /// exceed the conservative per-bootstrap credit.
    func testEffectiveSamplesAreDiscountedNotRaw() {
        let degree = 64
        let (secret, params) = rig(degree: degree)
        let trials = 8

        let acc = TFHENoisyBKMeasurement.identityAllCoefficients(
            secret: secret, params: params, noise: TFHENoiseParams(bound: 8),
            trials: trials, seed: 0x9001
        )
        XCTAssertEqual(acc.samples, trials * degree)
        XCTAssertEqual(
            acc.effectiveSamples,
            trials * TFHENoisyBKMeasurement.accumulatorSampleGain
        )
        XCTAssertLessThan(
            acc.effectiveSamples, acc.samples,
            "correlated residuals were credited in full — the bound will be too tight"
        )

        // The single-residual estimator is genuinely independent, so no discount.
        let single = TFHENoisyBKMeasurement.identity(
            secret: secret, params: params, noise: TFHENoiseParams(bound: 8),
            trials: trials, seed: 0x9001
        )
        XCTAssertEqual(single.effectiveSamples, single.samples)
    }

    /// The bound must be driven by effective samples, so an accumulator run and
    /// a single-residual run at the *same bootstrap count* cannot differ wildly
    /// in confidence. The accumulator run may be somewhat better — it does see
    /// more data — but not N× better.
    func testAccumulatorBoundIsNotArtificiallyTight() {
        let degree = 64
        let (secret, params) = rig(degree: degree)
        let noise = TFHENoiseParams(bound: 8)
        let trials = 16

        let acc = TFHENoisyBKMeasurement.identityAllCoefficients(
            secret: secret, params: params, noise: noise, trials: trials, seed: 0x9002
        )
        let single = TFHENoisyBKMeasurement.identity(
            secret: secret, params: params, noise: noise, trials: trials, seed: 0x9002
        )

        // Both bounds must remain worse than their own point estimate. An upper
        // bound on σ can only make ε worse; this ordering caught a real
        // reporting bug once already (AUDIT §13.5) and is cheap to keep.
        XCTAssertGreaterThanOrEqual(acc.failureLog2Upper95, acc.failureLog2Point)
        XCTAssertGreaterThanOrEqual(single.failureLog2Upper95, single.failureLog2Point)

        // σ̂ agrees, so the only thing separating the bounds is sample credit.
        let ratio = acc.sigmaHat / single.sigmaHat
        XCTAssertTrue(ratio > 0.5 && ratio < 2.0, "σ̂ ratio \(ratio) unexpected")

        // The accumulator bound is allowed to be tighter, but bounded by the
        // conservative credit rather than by N.
        XCTAssertLessThanOrEqual(
            acc.effectiveSamples,
            single.effectiveSamples * TFHENoisyBKMeasurement.accumulatorSampleGain,
            "accumulator credited more confidence than the measured gain allows"
        )
    }

    /// The certificate note has to disclose accumulator provenance. A reader
    /// seeing "trials=1024" would reasonably assume 1024 bootstraps.
    func testCertificateDisclosesAccumulatorProvenance() {
        let degree = 32
        let (secret, params) = rig(degree: degree)

        let acc = TFHENoisyBKMeasurement.identityAllCoefficients(
            secret: secret, params: params, noise: TFHENoiseParams(bound: 8),
            trials: 4, seed: 0x9003
        )
        let note = acc.observationReport(lutCount: 8).hypotheses.joined(separator: " | ")
        XCTAssertTrue(
            note.contains("accumulator coeffs"),
            "certificate hides that samples are accumulator coefficients: \(note)"
        )
        XCTAssertTrue(
            note.contains("credited"),
            "certificate does not disclose the independence discount: \(note)"
        )
        XCTAssertTrue(
            note.contains("effective samples"),
            "certificate quotes a raw sample count against ε: \(note)"
        )
    }
}
