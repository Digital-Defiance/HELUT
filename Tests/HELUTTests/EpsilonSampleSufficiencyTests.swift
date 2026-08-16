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
