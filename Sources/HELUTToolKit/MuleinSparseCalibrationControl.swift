import Foundation
import HELUTCore

/// Grades the sparse scoring path on a **known key** before it is ever pointed at P1030680.
///
/// This is Phase 11 doctrine applied to a scorer rather than a search: the thing that will decide
/// whether a candidate is German must first be shown to separate a true key from wrong keys, on a
/// message whose answer is already known, under exactly the geometries the target candidates use.
///
/// Three questions, in increasing sharpness:
///
/// 1. **Does the sparse path reproduce the dense result on ordinary geometry?** If it cannot, the
///    plumbing is wrong before any hole is involved.
/// 2. **Does hole-burning actually work?** Delete a real four-letter group from the control
///    ciphertext and attack the damage with post-gap geometry. The machine must be stepped through
///    the hole so that every symbol *after* the gap still decrypts. This is the decisive test,
///    and the assertion is exact plaintext equality rather than a score — a score can be fudged,
///    a 116-letter exact match cannot.
/// 3. **Do the dense thresholds transfer?** This was expected to be the hard part and turned out
///    not to be, which is worth stating plainly because the opposite was assumed first.
///    `GermanTrigrams.scoreIfLoaded` returns `total / (n - 2)` — a mean log-probability per
///    trigram window — and the sparse path's `meanLogProbability` is the same quantity over the
///    windows geometry actually permits. They are therefore the **same statistic in the same
///    units**, and arm A reproduces `PostBombeDiscriminator.germanReference` to within float
///    noise on hole-free geometry. The control asserts that equivalence rather than assuming it.
///
///    What does *not* transfer is the dense `tailScore` **sample**: it excises crib positions and
///    concatenates the remainder, which invents adjacency across the excision. The sparse path
///    refuses that bridge by construction. So a sparse score is comparable to the dense bar in
///    scale, while a sparse "tail" is a different sample of the same statistic — and at reduced
///    window count the estimate is simply noisier.
enum MuleinSparseCalibrationControl {
    /// Where the synthetic gap is cut, and how wide. Four letters is the group size Girard
    /// documented missing from the plain-paper copy of the sister message P1030681.
    private static let gapRecordedStart = 12
    private static let gapLength = 4
    /// Crib length used to compile the control Future. 27 letters is the blind-control menu size.
    private static let cribLength = 27

    private struct ArmScore {
        let label: String
        let ic: Double
        let bigramMean: Double?
        let trigramMean: Double?
        let eligibleCount: Int
        let runCount: Int
        let barrierCount: Int
        let plaintextExact: Bool?
    }

    static func run() {
        print("=== Mulein sparse-path calibration control (P1030684, known key) ===")
        print("Grades the SCORER, not a search. Establishes whether the sparse statistic")
        print("separates a true key from wrong keys under exact and post-gap geometry.")
        print()

        let recorded = EnigmaAlphabet.normalize(ControlMessageP1030684.ciphertext)
        let truePlain = EnigmaAlphabet.normalize(ControlMessageP1030684.plaintext)
        let stecker = ControlMessageP1030684.trueStecker
        let crib = String(
            EnigmaAlphabet.string(from: truePlain).prefix(cribLength)
        )

        func key(positions: (Int, Int, Int, Int)) -> EnigmaM4Key {
            EnigmaM4Key(
                greek: EnigmaM4Warehouse.gamma,
                rotors: (
                    EnigmaWarehouse.rotorIV, EnigmaWarehouse.rotorIII, EnigmaWarehouse.rotorVIII
                ),
                rings: EnigmaM4Key.rings(fromLetters: ControlMessageP1030684.rings),
                positions: positions,
                plugboard: stecker,
                reflector: EnigmaM4Warehouse.thinB
            )
        }
        let truePositions = EnigmaM4Key.rings(
            fromLetters: ControlMessageP1030684.positions
        )

        // ---- Arm A: ordinary geometry, true key -------------------------------------------
        guard let exactFuture = try? MuleinFutureLattice.compile(
            evidence: MuleinFutureEvidence(
                targetID: "P1030684",
                sourceID: "sparse-calibration",
                cribID: "exact-head",
                crib: crib,
                transmittedOffset: 0,
                ciphertext: recorded
            ),
            hypothesis: .exact,
            minimumEdges: 1
        ) else {
            fatalError("sparse calibration: exact control Future failed to compile")
        }

        guard let armA = score(
            label: "A  exact geometry, TRUE key",
            future: exactFuture,
            key: key(positions: truePositions),
            recorded: recorded,
            expectedPlaintextByTransmittedStep: truePlain
        ) else { fatalError("sparse calibration: arm A failed to build") }

        // ---- Arm B: ordinary geometry, wrong keys -----------------------------------------
        var wrongExact: [ArmScore] = []
        for offset in [1, 2, 3, 5, 7, 11, 13, 17] {
            let wrong = (
                truePositions.0,
                truePositions.1,
                truePositions.2,
                (truePositions.3 + offset) % 26
            )
            if let s = score(
                label: "B  exact geometry, wrong key +\(offset)",
                future: exactFuture,
                key: key(positions: wrong),
                recorded: recorded,
                expectedPlaintextByTransmittedStep: nil
            ) { wrongExact.append(s) }
        }

        // ---- Arm C: post-gap geometry, true key — THE decisive test ------------------------
        // Manufacture the transcript a copyist would have left: a real four-letter group is
        // simply absent from the recording. The transmitted stream is unchanged.
        var damaged = recorded
        let removed = Array(damaged[gapRecordedStart..<(gapRecordedStart + gapLength)])
        damaged.removeSubrange(gapRecordedStart..<(gapRecordedStart + gapLength))

        let postGapHypothesis = MuleinFutureHypothesis(
            label: "sparse-calibration-post-gap-delta\(gapLength)",
            edits: [
                .missingFromRecording(
                    transmitted: MuleinSpan(start: gapRecordedStart, length: gapLength),
                    recordedBoundary: gapRecordedStart
                ),
            ]
        )
        guard let postGapFuture = try? MuleinFutureLattice.compile(
            evidence: MuleinFutureEvidence(
                targetID: "P1030684",
                sourceID: "sparse-calibration",
                cribID: "post-gap-head",
                crib: crib,
                transmittedOffset: 0,
                ciphertext: damaged
            ),
            hypothesis: postGapHypothesis,
            minimumEdges: 1
        ) else {
            fatalError("sparse calibration: post-gap control Future failed to compile")
        }

        print("synthetic damage : removed recorded[\(gapRecordedStart)..<"
            + "\(gapRecordedStart + gapLength)] = \(EnigmaAlphabet.string(from: removed))")
        print("                   recorded \(recorded.count) → \(damaged.count) letters; "
            + "transmitted timeline \(postGapFuture.geometry.transmittedLength)")
        print()

        guard let armC = score(
            label: "C  post-gap δ\(gapLength), TRUE key",
            future: postGapFuture,
            key: key(positions: truePositions),
            recorded: damaged,
            expectedPlaintextByTransmittedStep: truePlain
        ) else { fatalError("sparse calibration: arm C failed to build") }

        // ---- Arm D: post-gap geometry, wrong keys -----------------------------------------
        var wrongPostGap: [ArmScore] = []
        for offset in [1, 2, 3, 5, 7, 11, 13, 17] {
            let wrong = (
                truePositions.0,
                truePositions.1,
                truePositions.2,
                (truePositions.3 + offset) % 26
            )
            if let s = score(
                label: "D  post-gap δ\(gapLength), wrong key +\(offset)",
                future: postGapFuture,
                key: key(positions: wrong),
                recorded: damaged,
                expectedPlaintextByTransmittedStep: nil
            ) { wrongPostGap.append(s) }
        }

        // ---- Arm E: one-edge repair, structural check --------------------------------------
        let firstBoardEdge = exactFuture.boardEdges.first
        let armE = firstBoardEdge.flatMap { edge in
            score(
                label: "E  exact geometry, TRUE key, 1 edge excluded",
                future: exactFuture,
                key: key(positions: truePositions),
                recorded: recorded,
                expectedPlaintextByTransmittedStep: nil,
                droppedEdgeIDs: [edge.id]
            )
        }

        // ---- Report ------------------------------------------------------------------------
        report(armA, wrongExact, armC, wrongPostGap, armE)
    }

    private static func score(
        label: String,
        future: MuleinFuture,
        key: EnigmaM4Key,
        recorded: [Int],
        expectedPlaintextByTransmittedStep: [Int]?,
        droppedEdgeIDs: [MuleinEdgeID] = []
    ) -> ArmScore? {
        guard let transcript = try? MuleinSparseTranscriptBuilder.build(
            future: future,
            key: key,
            recordedCiphertext: recorded,
            droppedEdgeIDs: droppedEdgeIDs
        ), let validated = try? MuleinSparseReferenceEvaluator.validate(transcript) else {
            return nil
        }

        let icTrace = MuleinSparseReferenceEvaluator.accumulateIC(validated)
        let adjacency = MuleinSparseReferenceEvaluator.traceAdjacency(
            validated, orders: [2, 3]
        )
        let ngrams = try? MuleinSparseReferenceEvaluator.evaluateNGrams(
            adjacency,
            using: [MuleinGermanBigramModel(), MuleinGermanTrigramModel()]
        )
        let ic = icTrace.possiblePairCount > 0
            ? Double(icTrace.coincidencePairCount) / Double(icTrace.possiblePairCount)
            : 0

        // Exact plaintext equality is a stronger claim than any score: the machine must have been
        // stepped correctly at every transmitted position, including across the hole.
        var exactMatch: Bool?
        if let expected = expectedPlaintextByTransmittedStep {
            var allMatch = true
            for cell in transcript.cells {
                guard case let .eligible(symbol) = cell.plaintext else { continue }
                guard expected.indices.contains(cell.transmittedStep) else { continue }
                if symbol.rawValue != expected[cell.transmittedStep] { allMatch = false; break }
            }
            exactMatch = allMatch
        }

        return ArmScore(
            label: label,
            ic: ic,
            bigramMean: ngrams?.first(where: { $0.order == 2 })?.meanLogProbability,
            trigramMean: ngrams?.first(where: { $0.order == 3 })?.meanLogProbability,
            eligibleCount: adjacency.eligiblePlaintext.count,
            runCount: adjacency.runs.count,
            barrierCount: adjacency.barriers.count,
            plaintextExact: exactMatch
        )
    }

    private static func report(
        _ armA: ArmScore,
        _ wrongExact: [ArmScore],
        _ armC: ArmScore,
        _ wrongPostGap: [ArmScore],
        _ armE: ArmScore?
    ) {
        func line(_ s: ArmScore) {
            let bigram = s.bigramMean.map { String(format: "%8.4f", $0) } ?? "      --"
            let trigram = s.trigramMean.map { String(format: "%8.4f", $0) } ?? "      --"
            let exact = s.plaintextExact.map { $0 ? "  EXACT" : "  WRONG" } ?? "      -"
            print(String(format: "  %-44@ IC %6.4f  bi %@  tri %@  n=%3d runs=%d barr=%d%@",
                         s.label as NSString, s.ic, bigram as NSString, trigram as NSString,
                         s.eligibleCount, s.runCount, s.barrierCount, exact as NSString))
        }

        print("  " + String(repeating: "-", count: 104))
        line(armA)
        for s in wrongExact.prefix(3) { line(s) }
        print("  " + String(repeating: "-", count: 104))
        line(armC)
        for s in wrongPostGap.prefix(3) { line(s) }
        if let armE {
            print("  " + String(repeating: "-", count: 104))
            line(armE)
        }
        print()

        // --- The decisive assertions ---
        var failures: [String] = []

        if armA.plaintextExact != true {
            failures.append("arm A did not reproduce the control plaintext on exact geometry")
        }
        if armC.plaintextExact != true {
            failures.append(
                "arm C did not reproduce the control plaintext through a δ\(gapLength) hole — "
                    + "hole-burning is WRONG"
            )
        }
        if armC.runCount < 2 || armC.barrierCount != gapLength {
            failures.append(
                "arm C geometry is not sparse: expected \(gapLength) barriers and ≥2 runs, "
                    + "saw \(armC.barrierCount) and \(armC.runCount)"
            )
        }
        if let armE, armE.barrierCount < 1 {
            failures.append("arm E excluded an edge but produced no barrier")
        }

        let worstTrueTrigram = min(
            armA.trigramMean ?? -.infinity, armC.trigramMean ?? -.infinity
        )
        let bestWrongTrigram = (wrongExact + wrongPostGap)
            .compactMap(\.trigramMean).max() ?? -.infinity
        let margin = worstTrueTrigram - bestWrongTrigram

        print(String(format: "sparse trigram separation: worst TRUE %.4f  vs  best WRONG %.4f",
                     worstTrueTrigram, bestWrongTrigram))
        print(String(format: "  margin %+.4f  (%@)", margin,
                     (margin > 0 ? "separates" : "DOES NOT separate") as NSString))
        if margin <= 0 {
            failures.append(
                "sparse trigram statistic does not separate the true key from wrong keys"
            )
        }
        print()

        // --- Dense/sparse equivalence, asserted rather than assumed ---
        // `GermanTrigrams.scoreIfLoaded` divides by (n - 2), so it is a mean log-probability per
        // trigram window. The sparse path reports the same quantity. On hole-free geometry the two
        // must therefore agree, and if they do not the plumbing is wrong somewhere.
        let densePlain = EnigmaAlphabet.normalize(ControlMessageP1030684.plaintext)
        let denseGerman = GermanTrigrams.score(densePlain)
        let sparseGerman = armA.trigramMean ?? .nan
        let equivalenceDelta = abs(denseGerman - sparseGerman)
        let denseIC = LanguageScorer.indexOfCoincidence(densePlain)

        print("dense / sparse equivalence on hole-free geometry (arm A):")
        print(String(format: "  dense  GermanTrigrams.score(plaintext) : %.6f", denseGerman))
        print(String(format: "  sparse meanLogProbability(order 3)     : %.6f", sparseGerman))
        print(String(format: "  |delta| %.2e  →  %@", equivalenceDelta,
                     (equivalenceDelta < 1e-9 ? "IDENTICAL statistic" : "DIVERGENT") as NSString))
        print(String(format: "  dense IC %.6f vs sparse IC %.6f", denseIC, armA.ic))
        if equivalenceDelta >= 1e-9 {
            failures.append(
                "sparse order-3 mean does not reproduce the dense trigram score on hole-free "
                    + "geometry (|delta| \(equivalenceDelta))"
            )
        }
        print()

        print("threshold transfer:")
        print(String(format: "  dense break bar        : %.3f", PostBombeDiscriminator.breakThreshold))
        print(String(format: "  dense German reference : %.3f", PostBombeDiscriminator.germanReference))
        print(String(format: "  dense noise reference  : %.3f", PostBombeDiscriminator.noiseReference))
        print(String(format: "  sparse TRUE            : %.4f exact / %.4f post-gap",
                     armA.trigramMean ?? .nan, armC.trigramMean ?? .nan))
        print(String(format: "  sparse WRONG (best)    : %.4f", bestWrongTrigram))
        print("  Same statistic and same units, so the -3.600 bar is comparable in SCALE.")
        print("  Two caveats that are not scale problems:")
        print("   * the dense `tailScore` excises crib positions and concatenates, inventing")
        print("     adjacency the sparse path refuses — a sparse tail is a different SAMPLE;")
        print("   * fewer eligible windows means a noisier estimate, so a barrier-heavy")
        print("     candidate deserves less confidence at the same mean.")
        print()

        if failures.isEmpty {
            print("*** SPARSE CALIBRATION PASS ***")
            print("The sparse path reproduces the control plaintext on both geometries, keeps the")
            print("hole as a scoring barrier, separates the true key, and reproduces the dense")
            print("trigram statistic exactly on hole-free geometry. It is fit to adjudicate")
            print("exact/no-drop post-gap candidates against the existing bar, with window count")
            print("reported alongside every score. It sets no bar for REPAIRED candidates:")
            print("crib-exactness is undefined for them by construction.")
        } else {
            print("*** SPARSE CALIBRATION FAIL ***")
            for failure in failures { print("  - \(failure)") }
            print("Do not adjudicate any candidate until these are resolved.")
        }
        fflush(stdout)
    }
}
