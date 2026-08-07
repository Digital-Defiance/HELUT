import XCTest
@testable import HELUTCore

/// Is a given trial count enough to support an ε bar?
///
/// The answer is not a constant. It depends only on how far the point estimate
/// sits from the bar: the 95% bound is `σ̂·√(m/χ²₀.₀₅(m))`, and since
/// `log₂ε ∝ −1/σ²`, the bound clears iff `|point| ≥ (m/χ²₀.₀₅(m))·|target|`.
/// That factor falls monotonically in `m`, so each sample count buys a fixed
/// amount of slack and anything with more slack than that is fine at that count.
///
/// This matters because trial counts in the claim rows were chosen by hand. Four
/// is generous for some rows and hopeless for others, and nothing in the tooling
/// used to say which was which.
final class EpsilonSampleSufficiencyTests: XCTestCase {

    /// δ/2 at N=1024, the scale most ε rows are quoted at.
    private let halfGap = 1_048_576.0

    /// σ̂ that yields a given log₂ε at this decoding gap, so tests can be written
    /// in terms of the quantity that matters.
    private func sigmaFor(pointLog2 target: Double) -> Double {
        var lo = 1.0
        var hi = halfGap
        for _ in 0..<200 {
            let mid = (lo + hi) / 2
            if log2GaussianTwoSidedTail(stddev: mid, threshold: halfGap) > target {
                hi = mid
            } else {
                lo = mid
            }
        }
        return (lo + hi) / 2
    }

    /// The headline table. Prints the slack each sample count buys, which is the
    /// direct answer to "is n=4 enough".
    func testSlackPurchasedBySampleCount() {
        var out = "\n=== what each sample count buys against a −64 bar ===\n"
        out += "   n   |point| needed to clear −64\n"
        out += "-----   ---------------------------\n"
        var previous = Double.infinity
        for n in [2, 3, 4, 6, 8, 12, 16, 24, 32, 64, 128, 256, 1024] {
            // Find the smallest |point| whose bound at n still clears −64.
            var lo = 64.0
            var hi = 1e7
            for _ in 0..<200 {
                let mid = (lo + hi) / 2
                let sigma = sigmaFor(pointLog2: -mid)
                let upper = sigmaUpperConfidenceBound(sigmaHat: sigma, samples: n)
                let bound = log2GaussianTwoSidedTail(stddev: upper, threshold: halfGap)
                if bound <= -64 { hi = mid } else { lo = mid }
            }
            out += String(format: "%5d   %26.0f\n", n, hi)
            // More samples must never require *more* slack.
            XCTAssertLessThanOrEqual(
                hi, previous + 1e-6,
                "slack requirement rose from \(previous) to \(hi) going to n=\(n)"
            )
            previous = hi
        }
        print(out)
    }

    /// A measurement far below the bar is fine at tiny n. This is why "n=4 is
    /// insufficient" is not a general truth: C30's B=1 row sits near −24 000 and
    /// n=3 settles it.
    func testGenerousMarginNeedsVeryFewSamples() {
        let sigma = sigmaFor(pointLog2: -23744)
        let need = samplesToClearFailureTarget(
            sigmaHat: sigma, threshold: halfGap, targetLog2: -64
        )
        XCTAssertNotNil(need)
        XCTAssertLessThanOrEqual(
            need!, 4,
            "a point estimate of −23744 should clear −64 at a handful of samples, needed \(need!)"
        )
    }

    /// A measurement just past the bar needs a lot. C41's N=512 row sits at
    /// −76.6 against −64, and that thin margin is expensive.
    func testThinMarginNeedsManySamples() {
        let sigma = sigmaFor(pointLog2: -76.6)
        let need = samplesToClearFailureTarget(
            sigmaHat: sigma, threshold: halfGap, targetLog2: -64
        )
        XCTAssertNotNil(need, "−76.6 is past −64, so some sample count must clear it")
        XCTAssertGreaterThan(
            need!, 32,
            "a margin this thin cannot be settled by a few dozen samples"
        )
        print("thin margin −76.6 vs −64 needs n≈\(need!)")
    }

    /// The distinction that decides what to do next: a point estimate on the
    /// wrong side of the bar is not an under-sampling problem, and no amount of
    /// compute fixes it. C55 (−10.9) and C56 (−12.6) are this case, and both
    /// rows already record themselves as negatives.
    func testUnreachableWhenPointEstimateFails() {
        for point in [-10.9, -12.6, -24.1, -63.9] {
            let sigma = sigmaFor(pointLog2: point)
            let need = samplesToClearFailureTarget(
                sigmaHat: sigma, threshold: halfGap, targetLog2: -64
            )
            XCTAssertNil(
                need,
                """
                point estimate \(point) is worse than −64, so no sample count can \
                clear the bar, but the helper suggested n=\(need ?? -1). That would \
                send someone to buy compute for a claim that needs weakening.
                """
            )
        }
    }

    /// Monotonicity: the required sample count must not decrease as the margin
    /// gets thinner.
    func testRequiredSamplesGrowAsMarginNarrows() {
        var previous = 0
        for point in [-100_000.0, -10_000, -1_000, -500, -250, -150, -100, -80, -70] {
            let sigma = sigmaFor(pointLog2: point)
            guard let need = samplesToClearFailureTarget(
                sigmaHat: sigma, threshold: halfGap, targetLog2: -64
            ) else {
                return XCTFail("\(point) is past −64 and should be reachable")
            }
            XCTAssertGreaterThanOrEqual(
                need, previous,
                "required n fell from \(previous) to \(need) as the margin narrowed to \(point)"
            )
            previous = need
        }
    }

    /// `isUnderSampledForTarget` must separate the two failure modes on real
    /// measurement objects, not just on bare numbers.
    func testMeasurementReportsUnderSamplingCorrectly() {
        // Under-sampled: point clears, bound does not.
        let underSampled = TFHENoisyBKMeasurement(
            maxAbsError: 90_000,
            rms: sigmaFor(pointLog2: -139.3),
            samples: 4,
            injectBound: 32,
            delta: UInt32(halfGap * 2),
            polynomialDegree: 1024,
            decodeFailures: 0
        )
        XCTAssertFalse(underSampled.meetsTargetWithConfidence(targetLog2: -64))
        XCTAssertTrue(underSampled.isUnderSampledForTarget())
        XCTAssertNotNil(underSampled.samplesToMeetTarget())

        // Genuinely unmet: point estimate itself fails.
        let unmet = TFHENoisyBKMeasurement(
            maxAbsError: 900_000,
            rms: sigmaFor(pointLog2: -10.9),
            samples: 8,
            injectBound: 128,
            delta: UInt32(halfGap * 2),
            polynomialDegree: 1024,
            decodeFailures: 0
        )
        XCTAssertFalse(unmet.meetsTargetWithConfidence(targetLog2: -64))
        XCTAssertFalse(
            unmet.isUnderSampledForTarget(),
            "a point estimate of −10.9 is not an under-sampling problem"
        )
        XCTAssertNil(unmet.samplesToMeetTarget())
    }
}

/// The stride-*k* exchange rate: what widening the decode gap buys against ε.
///
/// Established empirically at *N*=512, σ=128, covering-b1 on 2026-08-16 while
/// recovering C41. Native *k*=1 misses 2⁻⁶⁴ (settled −50.6 at n=256), and no
/// sample size fixes a point estimate on the wrong side of a bar. The lever that
/// does fix it is the one C52 already used at *N*=1024: wires in `{0,k}`, decode
/// gap *k*δ.
///
/// σ̂ is independent of *k* — it is a property of the CMUX ladder, not of the
/// message scale — so the whole effect is the gap. The leading term of the
/// Gaussian tail is `−t²/(2σ²ln2)`, which would make the rate exactly *k*², but
/// the tail also carries `−log₂(t/σ)`, so growth is slightly **sub**-quadratic:
/// the measured exponent runs 1.94–1.97 over *k* ∈ [2,11].
///
/// Recording that because an earlier draft of this work claimed "*k*² to ~1%".
/// That was an artifact: σ̂ varied across the four measurements in a direction
/// that happened to cancel the correction. The tests below assert the real
/// relationship so the same mistake cannot be re-made silently.
final class EpsilonStrideExchangeRateTests: XCTestCase {

    /// δ at polynomial degree *N* is `q/2N`; stride *k* multiplies it.
    private func halfGap(degree: Int, stride: Int) -> Double {
        let delta = (4_294_967_296.0 / (2.0 * Double(degree))) * Double(stride)
        return delta / 2.0
    }

    /// Settled σ̂ at *N*=512, σ=128, covering-b1 (n=256).
    private let sigma = 251_262.4

    /// The exchange rate is sub-quadratic and tends toward 2 as *k* grows.
    func testStrideExchangeRateIsSlightlySubQuadratic() {
        let base = abs(
            log2GaussianTwoSidedTail(stddev: sigma, threshold: halfGap(degree: 512, stride: 1))
        )
        for k in [2, 3, 7, 11] {
            let got = abs(
                log2GaussianTwoSidedTail(
                    stddev: sigma, threshold: halfGap(degree: 512, stride: k)
                )
            )
            let exponent = log(got / base) / log(Double(k))
            XCTAssertTrue(
                exponent > 1.90 && exponent < 2.00,
                """
                stride k=\(k): implied exponent \(exponent) outside (1.90, 2.00). \
                |log₂ε| went \(base) -> \(got). The gap/ε exchange rate has moved, \
                so the C41 recovery arithmetic needs re-deriving.
                """
            )
            // Strictly below k², never above: the log term only ever costs.
            XCTAssertLessThan(got, base * Double(k * k))
        }
    }

    /// The concrete C41 case end to end: *k*=1 misses the bar and is beyond
    /// rescue by sampling; *k*=2 clears it at a modest sample count.
    func testC41StrideRecoversTheBar() {
        let gapK1 = halfGap(degree: 512, stride: 1)
        let gapK2 = halfGap(degree: 512, stride: 2)
        let pointK1 = log2GaussianTwoSidedTail(stddev: sigma, threshold: gapK1)
        let pointK2 = log2GaussianTwoSidedTail(stddev: sigma, threshold: gapK2)

        XCTAssertGreaterThan(pointK1, -64.0, "k=1 at N=512 should miss 2⁻⁶⁴; got \(pointK1)")
        XCTAssertNil(
            samplesToClearFailureTarget(sigmaHat: sigma, threshold: gapK1, targetLog2: -64),
            "k=1 misses the bar, so no sample count may be reported as sufficient"
        )

        XCTAssertLessThan(pointK2, -64.0, "k=2 at N=512 should clear 2⁻⁶⁴; got \(pointK2)")
        guard let need = samplesToClearFailureTarget(
            sigmaHat: sigma, threshold: gapK2, targetLog2: -64
        ) else {
            return XCTFail("k=2 clears the bar, so a sufficient sample count must exist")
        }
        XCTAssertLessThanOrEqual(
            need, 64, "k=2 was measured clearing at n=64; helper now demands n=\(need)"
        )

        // Single-LUT reference values. The CLI prints a union over lutCount, which
        // is ~3 orders kinder at lutCount=8 — that offset accounted for every one
        // of the four measured figures to within 0.1.
        XCTAssertEqual(pointK1, -53.7, accuracy: 1.0)
        XCTAssertEqual(pointK2, -205.4, accuracy: 4.0)
    }

    /// The union offset itself: the printed ε is worse than single-LUT by
    /// log₂(lutCount), and getting that backwards once made a bound look better
    /// than its own point estimate (AUDIT §13.5).
    func testUnionPenaltyMatchesMeasuredOffset() {
        let single = log2GaussianTwoSidedTail(
            stddev: sigma, threshold: halfGap(degree: 512, stride: 1)
        )
        let union = single + log2(8.0)
        XCTAssertGreaterThan(union, single, "a union over 8 LUTs must be worse, not better")
        XCTAssertEqual(union, -50.6, accuracy: 1.0)
    }
}
