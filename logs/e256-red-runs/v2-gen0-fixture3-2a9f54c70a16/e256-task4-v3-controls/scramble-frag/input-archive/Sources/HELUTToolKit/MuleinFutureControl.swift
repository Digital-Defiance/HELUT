import Foundation
import HELUTCore

// MARK: - Blind Future Bank control grade
//
// P1030684 is used only as a published known-key control. The Swift oracle itself receives no
// truth key: it reconstructs scrambler rows from each candidate setting and blindly enumerates
// every permitted edge erasure. This file never reads P1030680 campaign data.

private struct MuleinFutureControlFixtures {
    let clean: MuleinFuture
    let garbled: MuleinFuture
    let restored: MuleinFuture
    let missingGapAndGarble: MuleinFuture
    let offset79: MuleinFuture
    let delta6Envelope: MuleinFuture
    let delta8Envelope: MuleinFuture
    let wrongDelta6OnDelta8Recording: MuleinFuture
    let delta6EnvelopeAndGarble: MuleinFuture
    let delta8EnvelopeAndGarble: MuleinFuture
    let weakOneEdge: MuleinFuture
    let garbleCribIndex: Int
    let postGapGarbleCribIndex: Int
    let envelopeGarbleCribIndex: Int
    let missingCribIndices: Set<Int>

    static func build() throws -> MuleinFutureControlFixtures {
        let ciphertext = EnigmaAlphabet.normalize(ControlMessageP1030684.ciphertext)
        let plaintext = EnigmaAlphabet.normalize(ControlMessageP1030684.plaintext)

        func crib(offset: Int, length: Int) -> String {
            EnigmaAlphabet.string(from: Array(plaintext[offset..<(offset + length)]))
        }

        func changedSymbol(original: Int, avoiding plaintext: Int) -> Int {
            for delta in 1..<26 {
                let candidate = (original + delta) % 26
                if candidate != plaintext { return candidate }
            }
            preconditionFailure("alphabet has no legal replacement")
        }

        func leadingMissingFuture(
            recordingStart: Int,
            recordingEnd: Int,
            claimedDelta: Int,
            cribOffset: Int,
            cribLength: Int,
            garbleTransmittedIndex: Int? = nil,
            label: String
        ) throws -> MuleinFuture {
            precondition(recordingStart >= 0 && recordingStart < recordingEnd)
            precondition(recordingEnd <= ciphertext.count)
            var recording = Array(ciphertext[recordingStart..<recordingEnd])
            if let garbleTransmittedIndex {
                precondition((recordingStart..<recordingEnd).contains(garbleTransmittedIndex))
                precondition((cribOffset..<(cribOffset + cribLength)).contains(
                    garbleTransmittedIndex
                ))
                let recordedIndex = garbleTransmittedIndex - recordingStart
                recording[recordedIndex] = changedSymbol(
                    original: ciphertext[garbleTransmittedIndex],
                    avoiding: plaintext[garbleTransmittedIndex]
                )
            }
            let evidence = MuleinFutureEvidence(
                targetID: "P1030684-control",
                sourceID: garbleTransmittedIndex == nil
                    ? "synthetic-leading-indel-envelope"
                    : "synthetic-leading-indel-plus-garble",
                cribID: label,
                crib: crib(offset: cribOffset, length: cribLength),
                transmittedOffset: cribOffset,
                ciphertext: recording
            )
            return try MuleinFutureLattice.compile(
                evidence: evidence,
                hypothesis: MuleinFutureHypothesis(
                    label: label,
                    edits: [.missingFromRecording(
                        transmitted: MuleinSpan(start: 0, length: claimedDelta),
                        recordedBoundary: 0
                    )]
                ),
                minimumEdges: cribLength
            )
        }

        let cleanEvidence = MuleinFutureEvidence(
            targetID: "P1030684-control",
            sourceID: "published-known-key",
            cribID: "clean-27-at-0",
            crib: crib(offset: 0, length: 27),
            transmittedOffset: 0,
            ciphertext: ciphertext
        )
        let clean = try MuleinFutureLattice.compile(
            evidence: cleanEvidence, hypothesis: .exact, minimumEdges: 27
        )

        let garbleIndex = 13
        var garbledCiphertext = ciphertext
        garbledCiphertext[garbleIndex] = changedSymbol(
            original: ciphertext[garbleIndex], avoiding: plaintext[garbleIndex]
        )
        let garbledEvidence = MuleinFutureEvidence(
            targetID: "P1030684-control",
            sourceID: "synthetic-one-garble",
            cribID: "garble-13",
            crib: crib(offset: 0, length: 27),
            transmittedOffset: 0,
            ciphertext: garbledCiphertext
        )
        let garbled = try MuleinFutureLattice.compile(
            evidence: garbledEvidence, hypothesis: .exact, minimumEdges: 27
        )
        let restored = try MuleinFutureLattice.compile(
            evidence: garbledEvidence,
            hypothesis: MuleinFutureHypothesis(
                label: "restore-published-symbol",
                edits: [.replacement(
                    recordedIndex: garbleIndex,
                    observed: garbledCiphertext[garbleIndex],
                    hypothesized: ciphertext[garbleIndex]
                )]
            ),
            minimumEdges: 27
        )

        let gapStart = 10
        let gapLength = 4
        var gapRecording = ciphertext
        gapRecording.removeSubrange(gapStart..<(gapStart + gapLength))
        let postGapTransmittedIndex = 18
        let postGapRecordedIndex = postGapTransmittedIndex - gapLength
        gapRecording[postGapRecordedIndex] = changedSymbol(
            original: ciphertext[postGapTransmittedIndex],
            avoiding: plaintext[postGapTransmittedIndex]
        )
        let gapEvidence = MuleinFutureEvidence(
            targetID: "P1030684-control",
            sourceID: "synthetic-missing-group-plus-garble",
            cribID: "gap-10-13-garble-18",
            crib: crib(offset: 0, length: 27),
            transmittedOffset: 0,
            ciphertext: gapRecording
        )
        let missingGapAndGarble = try MuleinFutureLattice.compile(
            evidence: gapEvidence,
            hypothesis: MuleinFutureHypothesis(
                label: "missing-four-recorded-symbols",
                edits: [.missingFromRecording(
                    transmitted: MuleinSpan(start: gapStart, length: gapLength),
                    recordedBoundary: gapStart
                )]
            ),
            minimumEdges: 23
        )

        let offset79Evidence = MuleinFutureEvidence(
            targetID: "P1030684-control",
            sourceID: "published-known-key",
            cribID: "clean-20-at-60",
            crib: crib(offset: 60, length: 20),
            transmittedOffset: 60,
            ciphertext: ciphertext
        )
        let offset79 = try MuleinFutureLattice.compile(
            evidence: offset79Evidence, hypothesis: .exact, minimumEdges: 20
        )

        // Target-shaped 72-symbol recordings exercise the staged 78/80-step envelope. The
        // wrong-delta control deliberately interprets a true delta-8 recording as delta 6.
        let delta6Envelope = try leadingMissingFuture(
            recordingStart: 6,
            recordingEnd: 78,
            claimedDelta: 6,
            cribOffset: 38,
            cribLength: 40,
            label: "leading-delta-6"
        )
        let delta8Envelope = try leadingMissingFuture(
            recordingStart: 8,
            recordingEnd: 80,
            claimedDelta: 8,
            cribOffset: 40,
            cribLength: 40,
            label: "leading-delta-8"
        )
        let wrongDelta6OnDelta8Recording = try leadingMissingFuture(
            recordingStart: 8,
            recordingEnd: 80,
            claimedDelta: 6,
            cribOffset: 12,
            cribLength: 32,
            label: "wrong-delta-6-on-delta-8-recording"
        )

        // Corrupt crib edge 20 after each leading gap. Both controls use recorded index 52,
        // while retaining their distinct transmitted steps (58 for delta 6, 60 for delta 8).
        let envelopeGarbleCribIndex = 20
        let delta6EnvelopeAndGarble = try leadingMissingFuture(
            recordingStart: 6,
            recordingEnd: 78,
            claimedDelta: 6,
            cribOffset: 38,
            cribLength: 40,
            garbleTransmittedIndex: 38 + envelopeGarbleCribIndex,
            label: "leading-delta-6-plus-garble"
        )
        let delta8EnvelopeAndGarble = try leadingMissingFuture(
            recordingStart: 8,
            recordingEnd: 80,
            claimedDelta: 8,
            cribOffset: 40,
            cribLength: 40,
            garbleTransmittedIndex: 40 + envelopeGarbleCribIndex,
            label: "leading-delta-8-plus-garble"
        )

        let weakEvidence = MuleinFutureEvidence(
            targetID: "P1030684-control",
            sourceID: "published-known-key",
            cribID: "weak-one-edge",
            crib: crib(offset: 0, length: 1),
            transmittedOffset: 0,
            ciphertext: ciphertext
        )
        let weakOneEdge = try MuleinFutureLattice.compile(
            evidence: weakEvidence, hypothesis: .exact, minimumEdges: 1
        )

        return MuleinFutureControlFixtures(
            clean: clean,
            garbled: garbled,
            restored: restored,
            missingGapAndGarble: missingGapAndGarble,
            offset79: offset79,
            delta6Envelope: delta6Envelope,
            delta8Envelope: delta8Envelope,
            wrongDelta6OnDelta8Recording: wrongDelta6OnDelta8Recording,
            delta6EnvelopeAndGarble: delta6EnvelopeAndGarble,
            delta8EnvelopeAndGarble: delta8EnvelopeAndGarble,
            weakOneEdge: weakOneEdge,
            garbleCribIndex: garbleIndex,
            postGapGarbleCribIndex: postGapTransmittedIndex,
            envelopeGarbleCribIndex: envelopeGarbleCribIndex,
            missingCribIndices: Set(gapStart..<(gapStart + gapLength))
        )
    }
}

// Narrow fixture surface for the production Verilog/TensorLUT conformance grade.  The broad
// control inventory above remains private; this exposes only auditable work items and truth
// metadata for a published known-key message.  The blind oracle still evaluates without using
// these true seeds.
package struct MuleinFutureTensorLUTControlFixture {
    package let work: [MuleinFutureMetalWork]
    package let labels: [String]
    package let envelopeWork: [MuleinFutureMetalWork]
    package let envelopeLabels: [String]
    package let composedWork: [MuleinFutureMetalWork]
    package let composedLabels: [String]
    package let bombe: WelchmanBombe
    package let setting: (Int, Int, Int, Int)
    package let settingLane: Int
    package let trueSeeds: [Int]
    package let envelopeTrueSeeds: [Int]
    package let composedTrueSeeds: [Int]
    package let postGapGarbleCribIndex: Int
    package let envelopeGarbleCribIndex: Int
    package let missingCribIndices: Set<Int>
}

package func makeMuleinFutureTensorLUTControlFixture()
    throws -> MuleinFutureTensorLUTControlFixture
{
    let fixtures = try MuleinFutureControlFixtures.build()
    // Keep this benchmark inventory exactly four jobs; its normalized digest is published.
    let work = [
        MuleinFutureMetalWork(
            future: fixtures.clean, tolerance: 0, maxPlugs: 10, exactPlugs: 10
        ),
        MuleinFutureMetalWork(
            future: fixtures.missingGapAndGarble,
            tolerance: 0,
            maxPlugs: 10,
            exactPlugs: 10
        ),
        MuleinFutureMetalWork(
            future: fixtures.missingGapAndGarble,
            tolerance: 1,
            maxPlugs: 10,
            exactPlugs: 10
        ),
        MuleinFutureMetalWork(
            future: fixtures.offset79, tolerance: 0, maxPlugs: 10, exactPlugs: 10
        )
    ]
    let labels = ["clean-exact", "gap-garble-exact", "gap-garble-repair", "step-79"]
    let envelopeWork = [
        MuleinFutureMetalWork(
            future: fixtures.delta6Envelope, tolerance: 0, maxPlugs: 10, exactPlugs: 10
        ),
        MuleinFutureMetalWork(
            future: fixtures.delta8Envelope, tolerance: 0, maxPlugs: 10, exactPlugs: 10
        ),
        MuleinFutureMetalWork(
            future: fixtures.wrongDelta6OnDelta8Recording,
            tolerance: 0,
            maxPlugs: 10,
            exactPlugs: 10
        )
    ]
    let envelopeLabels = ["delta-6-exact", "delta-8-exact", "wrong-delta-6-on-delta-8"]
    let composedWork = [
        MuleinFutureMetalWork(
            future: fixtures.delta6EnvelopeAndGarble,
            tolerance: 0,
            maxPlugs: 10,
            exactPlugs: 10
        ),
        MuleinFutureMetalWork(
            future: fixtures.delta6EnvelopeAndGarble,
            tolerance: 1,
            maxPlugs: 10,
            exactPlugs: 10
        ),
        MuleinFutureMetalWork(
            future: fixtures.delta8EnvelopeAndGarble,
            tolerance: 0,
            maxPlugs: 10,
            exactPlugs: 10
        ),
        MuleinFutureMetalWork(
            future: fixtures.delta8EnvelopeAndGarble,
            tolerance: 1,
            maxPlugs: 10,
            exactPlugs: 10
        )
    ]
    let composedLabels = [
        "delta-6-garble-exact",
        "delta-6-garble-repair",
        "delta-8-garble-exact",
        "delta-8-garble-repair"
    ]
    let setting = EnigmaM4Key.positions(fromLetters: ControlMessageP1030684.positions)
    let settingLane = setting.0 * 17_576 + setting.1 * 676 + setting.2 * 26 + setting.3
    let stecker = ControlMessageP1030684.trueStecker
    let trueSeeds = work.map { stecker[$0.future.menu.central] }
    let envelopeTrueSeeds = envelopeWork.map { stecker[$0.future.menu.central] }
    let composedTrueSeeds = composedWork.map { stecker[$0.future.menu.central] }
    return MuleinFutureTensorLUTControlFixture(
        work: work,
        labels: labels,
        envelopeWork: envelopeWork,
        envelopeLabels: envelopeLabels,
        composedWork: composedWork,
        composedLabels: composedLabels,
        bombe: ControlMessageP1030684.bombe(maxPlugs: 10),
        setting: setting,
        settingLane: settingLane,
        trueSeeds: trueSeeds,
        envelopeTrueSeeds: envelopeTrueSeeds,
        composedTrueSeeds: composedTrueSeeds,
        postGapGarbleCribIndex: fixtures.postGapGarbleCribIndex,
        envelopeGarbleCribIndex: fixtures.envelopeGarbleCribIndex,
        missingCribIndices: fixtures.missingCribIndices
    )
}

private struct MuleinControlKey: Hashable {
    let settingLane: Int
    let futureIndex: Int
    let seed: Int
}

private struct MuleinNormalizedReceipt: Hashable {
    let settingLane: Int
    let futureID: MuleinHypothesisID
    let seed: Int
    let droppedEdgeMask: UInt64
    let repair: MuleinBoardRepairReceipt
    let pairCount: Int
    let determinedCount: Int
    let exact: Bool
    let liveHash: UInt32

    init(_ hit: MuleinFutureMetalHit) {
        settingLane = hit.settingLane
        futureID = hit.futureID
        seed = hit.seed
        droppedEdgeMask = hit.droppedEdgeMask
        repair = hit.repair
        pairCount = hit.pairCount
        determinedCount = hit.determinedCount
        exact = hit.exact
        liveHash = hit.liveHash
    }
}

func muleinControlRequire(
    _ condition: @autoclosure () -> Bool,
    _ message: @autoclosure () -> String
) throws {
    guard condition() else {
        throw MuleinFutureMetalError.benchmarkMismatch(message())
    }
}

private func muleinReceiptDescription(_ hit: MuleinFutureMetalHit) -> String {
    let repairs = hit.repair.droppedEdgeIDs.map {
        "\($0.cribIndex)@T\($0.transmittedStep)"
    }.joined(separator: ",")
    return "lane=\(hit.settingLane) future=\(hit.futureIndex):\(hit.futureID.rawValue) "
        + "seed=\(hit.seed) drop=0x\(String(hit.droppedEdgeMask, radix: 16)) "
        + "repair=[\(repairs)] pairs=\(hit.pairCount) determined=\(hit.determinedCount) "
        + "exact=\(hit.exact) hash=0x\(String(hit.liveHash, radix: 16))"
}

@discardableResult
func gradeMuleinParity(
    label: String,
    engine: MuleinFutureMetalEngine,
    work: [MuleinFutureMetalWork],
    bombe: WelchmanBombe,
    settingRange: Range<Int>,
    initialCapacity: Int = 4_096
) throws -> MuleinFutureMetalBatchResult {
    let swift = try evaluateMuleinFutureSwiftOracle(
        work: work, bombe: bombe, settingRange: settingRange
    )
    let metal = try engine.evaluateComplete(
        work: work,
        bombe: bombe,
        settingRange: settingRange,
        initialHitCapacity: initialCapacity
    )
    try muleinControlRequire(metal.isComplete, "\(label): Metal result is incomplete")
    try muleinControlRequire(
        Set(metal.hits).count == metal.hits.count,
        "\(label): Metal result contains duplicate full receipts"
    )
    guard metal.hits == swift else {
        let metalOnly = Set(metal.hits).subtracting(swift).first
        let swiftOnly = Set(swift).subtracting(metal.hits).first
        let detail = "\(label): full receipt mismatch; Metal-only="
            + (metalOnly.map(muleinReceiptDescription) ?? "none")
            + "; Swift-only="
            + (swiftOnly.map(muleinReceiptDescription) ?? "none")
        throw MuleinFutureMetalError.benchmarkMismatch(detail)
    }
    print("PASS parity   : \(label) — \(settingRange.count) settings, "
        + "\(work.count) futures, \(metal.hits.count) full receipts")
    return metal
}

private func discoverP1030684BudgetRepair(
    ciphertext: [Int],
    plaintext: [Int],
    bombe: WelchmanBombe,
    truth: (Int, Int, Int, Int),
    trueStecker: [Int]
) throws -> (work: MuleinFutureMetalWork, result: MuleinBoardResult, label: String) {
    for length in stride(from: 27, through: 8, by: -1) {
        let maximumOffset = min(40, plaintext.count - length)
        for offset in 0...maximumOffset {
            let evidence = MuleinFutureEvidence(
                targetID: "P1030684-control",
                sourceID: "published-known-key-budget-search",
                cribID: "budget-\(length)-at-\(offset)",
                crib: EnigmaAlphabet.string(
                    from: Array(plaintext[offset..<(offset + length)])
                ),
                transmittedOffset: offset,
                ciphertext: ciphertext
            )
            let future = try MuleinFutureLattice.compile(
                evidence: evidence, hypothesis: .exact, minimumEdges: length
            )
            let seed = trueStecker[future.menu.central]
            let rows = bombe.scramblers(menu: future.menu, start: truth)
            guard let exact = MuleinBoard.propagate(
                menu: future.menu,
                scramblers: rows,
                seedLetter: future.menu.central,
                seedValue: seed,
                tolerance: 0
            ), exact.pairCount >= 2 else { continue }

            for budget in stride(from: exact.pairCount - 1, through: 1, by: -1) {
                guard let repaired = MuleinBoard.propagate(
                    menu: future.menu,
                    scramblers: rows,
                    seedLetter: future.menu.central,
                    seedValue: seed,
                    tolerance: 1,
                    maxPlugs: budget
                ), !repaired.exact else { continue }
                return (
                    MuleinFutureMetalWork(
                        future: future, tolerance: 1, maxPlugs: budget
                    ),
                    repaired,
                    "length \(length) at offset \(offset), maxPlugs=\(budget)"
                )
            }
        }
    }
    throw MuleinFutureMetalError.benchmarkMismatch(
        "P1030684 fixture search found no one-edge plug-budget repair"
    )
}

private func hit(
    _ result: MuleinFutureMetalBatchResult,
    futureIndex: Int,
    settingLane: Int,
    seed: Int
) -> MuleinFutureMetalHit? {
    result.hits.first {
        $0.futureIndex == futureIndex && $0.settingLane == settingLane && $0.seed == seed
    }
}

/// Exhaustive non-campaign certification for the cleartext Future Bank prototype.
func runMuleinFutureControlGrade() {
    setbuf(stdout, nil)
    let quick = CommandLine.arguments.contains("--mulein-future-control-quick")

    print("=== Mulein Future Bank — blind known-key control grade ===")
    print("controls      : self-generated M4, historical P1030681/P1030714, P1030684")
    print("scope         : cleartext Metal + independent Swift board; not FHE")
    print("target data   : none (P1030680 is not read or evaluated)")
    print("receipt       : setting/future/seed/drop IDs/counts/full 32-bit live hash")
    print("overflow      : fail closed; incomplete prefixes are discarded before retry")
    print("mode          : \(quick ? "quick (full-slice/full-range skipped)" : "full")")
    print()

    do {
        let fixtures = try MuleinFutureControlFixtures.build()
        let ciphertext = EnigmaAlphabet.normalize(ControlMessageP1030684.ciphertext)
        let plaintext = EnigmaAlphabet.normalize(ControlMessageP1030684.plaintext)
        let truth = EnigmaM4Key.positions(fromLetters: ControlMessageP1030684.positions)
        let trueLane = truth.0 * 17_576 + truth.1 * 676 + truth.2 * 26 + truth.3
        let trueStecker = ControlMessageP1030684.trueStecker
        let bombe = ControlMessageP1030684.bombe(maxPlugs: 10)
        let engine = try MuleinFutureMetalEngine()

        print("generated      : building fixed-key edit controls")
        try runSyntheticFutureControls(engine: engine)
        print("historical     : building P1030681/P1030714 controls")
        try runP1030681FutureControls(engine: engine)
        print()

        try muleinControlRequire(fixtures.clean.menu.edgeCount == 27,
                                 "clean fixture did not retain 27 edges")
        try muleinControlRequire(fixtures.garbled.menu.edgeCount == 27,
                                 "garbled fixture did not retain 27 edges")
        try muleinControlRequire(fixtures.restored.menu.steps == fixtures.clean.menu.steps,
                                 "replacement future changed transcript geometry")
        let restoredPairs = zip(fixtures.restored.menu.ends, fixtures.clean.menu.ends).allSatisfy {
            $0.0.0 == $0.1.0 && $0.0.1 == $0.1.1
        }
        try muleinControlRequire(restoredPairs,
                                 "replacement future did not restore the clean constraints")
        try muleinControlRequire(
            Set(fixtures.missingGapAndGarble.edges.filter { !$0.isBoardConstraint }
                .map(\.id.cribIndex)) == fixtures.missingCribIndices,
            "missing-recording future lost its four-edge evidence receipt"
        )
        try muleinControlRequire(fixtures.missingGapAndGarble.menu.edgeCount == 23,
                                 "missing-recording future did not omit exactly four constraints")
        try muleinControlRequire(fixtures.offset79.menu.steps.max() == 79,
                                 "offset-60 fixture did not exercise trail step 79")
        print("PASS lattice  : replacement, four-symbol recording gap, and step-79 geometry")

        let budget = try discoverP1030684BudgetRepair(
            ciphertext: ciphertext,
            plaintext: plaintext,
            bombe: bombe,
            truth: truth,
            trueStecker: trueStecker
        )
        print("PASS budget   : discovered deterministic one-edge repair (\(budget.label))")

        let work = [
            MuleinFutureMetalWork(
                future: fixtures.clean, tolerance: 0, maxPlugs: 10, exactPlugs: 10
            ),
            MuleinFutureMetalWork(
                future: fixtures.clean, tolerance: 1, maxPlugs: 10, exactPlugs: 10
            ),
            MuleinFutureMetalWork(
                future: fixtures.garbled, tolerance: 0, maxPlugs: 10, exactPlugs: 10
            ),
            MuleinFutureMetalWork(
                future: fixtures.garbled, tolerance: 1, maxPlugs: 10, exactPlugs: 10
            ),
            MuleinFutureMetalWork(
                future: fixtures.restored, tolerance: 0, maxPlugs: 10, exactPlugs: 10
            ),
            MuleinFutureMetalWork(
                future: fixtures.missingGapAndGarble,
                tolerance: 1,
                maxPlugs: 10,
                exactPlugs: 10
            ),
            MuleinFutureMetalWork(
                future: fixtures.offset79, tolerance: 0, maxPlugs: 10, exactPlugs: 10
            ),
            budget.work
        ]

        let ranges = [
            0..<64,
            385_288..<385_352,
            456_912..<456_976
        ]
        var trueWindow: MuleinFutureMetalBatchResult?
        for range in ranges {
            let result = try gradeMuleinParity(
                label: "detailed \(range.lowerBound)..<\(range.upperBound)",
                engine: engine,
                work: work,
                bombe: bombe,
                settingRange: range
            )
            if range.contains(trueLane) { trueWindow = result }

            let tolerance0 = Set(result.hits.filter { $0.futureIndex == 0 }
                .map(MuleinNormalizedReceipt.init))
            let tolerance1 = Set(result.hits.filter { $0.futureIndex == 1 }
                .map(MuleinNormalizedReceipt.init))
            try muleinControlRequire(
                tolerance0.allSatisfy { $0.droppedEdgeMask == 0 && $0.exact },
                "tolerance-0 emitted repair provenance in \(range)"
            )
            try muleinControlRequire(
                tolerance0.isSubset(of: tolerance1),
                "tolerance-0 receipts are not a zero-drop subset of tolerance-1 in \(range)"
            )
        }
        print("PASS monotone : every clean tolerance-0 receipt is unchanged at tolerance 1")

        let center = try muleinControlRequireUnwrap(
            trueWindow, "detailed ranges did not include the P1030684 true lane"
        )
        let cleanSeed = trueStecker[fixtures.clean.menu.central]
        let garbledSeed = trueStecker[fixtures.garbled.menu.central]
        let restoredSeed = trueStecker[fixtures.restored.menu.central]
        let gapSeed = trueStecker[fixtures.missingGapAndGarble.menu.central]
        let offsetSeed = trueStecker[fixtures.offset79.menu.central]
        let budgetSeed = trueStecker[budget.work.future.menu.central]

        let clean0 = try muleinControlRequireUnwrap(
            hit(center, futureIndex: 0, settingLane: trueLane, seed: cleanSeed),
            "clean tolerance-0 fixture lost the true lane/seed"
        )
        let clean1 = try muleinControlRequireUnwrap(
            hit(center, futureIndex: 1, settingLane: trueLane, seed: cleanSeed),
            "clean tolerance-1 fixture lost the true lane/seed"
        )
        try muleinControlRequire(clean0.exact && clean1.exact,
                                 "clean true candidate was mislabeled as repaired")
        try muleinControlRequire(clean0.liveHash == clean1.liveHash,
                                 "exact-first clean hash changed under tolerance 1")
        try muleinControlRequire(
            hit(center, futureIndex: 2, settingLane: trueLane, seed: garbledSeed) == nil,
            "one-garble exact control retained the true seed"
        )
        let repairedGarble = try muleinControlRequireUnwrap(
            hit(center, futureIndex: 3, settingLane: trueLane, seed: garbledSeed),
            "one-garble tolerance-1 control did not recover the true seed"
        )
        try muleinControlRequire(!repairedGarble.exact,
                                 "one-garble recovery lacks repair status")
        try muleinControlRequire(
            repairedGarble.repair.droppedEdgeIDs.count == 1
                && repairedGarble.repair.droppedEdgeIDs[0].cribIndex
                    == fixtures.garbleCribIndex,
            "one-garble recovery identified the wrong stable edge"
        )
        let restored = try muleinControlRequireUnwrap(
            hit(center, futureIndex: 4, settingLane: trueLane, seed: restoredSeed),
            "replacement future did not restore the true seed"
        )
        try muleinControlRequire(restored.exact,
                                 "replacement future still required an edge erasure")
        let repairedGap = try muleinControlRequireUnwrap(
            hit(center, futureIndex: 5, settingLane: trueLane, seed: gapSeed),
            "missing-gap plus post-gap-garble future lost the true seed"
        )
        try muleinControlRequire(
            repairedGap.repair.droppedEdgeIDs.count == 1
                && repairedGap.repair.droppedEdgeIDs[0].cribIndex
                    == fixtures.postGapGarbleCribIndex,
            "post-gap corruption did not retain stable repair provenance"
        )
        try muleinControlRequire(
            hit(center, futureIndex: 6, settingLane: trueLane, seed: offsetSeed)?.exact == true,
            "step-79 future lost the true exact seed"
        )
        let repairedBudget = try muleinControlRequireUnwrap(
            hit(center, futureIndex: 7, settingLane: trueLane, seed: budgetSeed),
            "plug-budget future lost the discovered true repair"
        )
        try muleinControlRequire(
            !repairedBudget.exact
                && repairedBudget.pairCount <= budget.work.maxPlugs
                && repairedBudget.repair.droppedEdgeIDs.count
                    == budget.result.droppedEdges.count,
            "plug-budget repair receipt is inconsistent"
        )
        print("PASS truth     : exact, garble repair, replacement, gap+garble, budget, step 79")

        print("overflow probe : capacity-1 prefix")
        let overflowWork = [MuleinFutureMetalWork(future: fixtures.weakOneEdge)]
        let overflowRange = 0..<64
        let incomplete = try engine.evaluate(
            work: overflowWork,
            bombe: bombe,
            settingRange: overflowRange,
            hitCapacity: 1,
            failOnOverflow: false
        )
        try muleinControlRequire(!incomplete.isComplete,
                                 "capacity-1 weak future unexpectedly completed")
        try muleinControlRequire(incomplete.hits.count == 1,
                                 "capacity-1 weak future did not return one explicit prefix hit")
        try muleinControlRequire(
            incomplete.statistics.overflowHits
                == incomplete.statistics.attemptedHits - incomplete.statistics.writtenHits,
            "overflow counters violate attempted = written + overflow"
        )
        print("overflow probe : attempted \(incomplete.statistics.attemptedHits), "
            + "written \(incomplete.statistics.writtenHits), "
            + "overflow \(incomplete.statistics.overflowHits)")
        do {
            _ = try engine.evaluate(
                work: overflowWork,
                bombe: bombe,
                settingRange: overflowRange,
                hitCapacity: 1
            )
            throw MuleinFutureMetalError.benchmarkMismatch(
                "default overflow policy did not throw"
            )
        } catch let error as MuleinFutureMetalError {
            guard case let .queueOverflow(attempted, written, capacity) = error else {
                throw error
            }
            try muleinControlRequire(
                attempted == incomplete.statistics.attemptedHits
                    && written == 1 && capacity == 1,
                "typed overflow receipt disagrees with incomplete statistics"
            )
        }
        print("overflow probe : typed throw passed; Swift full receipt")
        let overflowSwift = try evaluateMuleinFutureSwiftOracle(
            work: overflowWork, bombe: bombe, settingRange: overflowRange
        )
        print("overflow probe : Swift receipts \(overflowSwift.count); attempted-count rerun")
        let rerun = try engine.evaluateComplete(
            work: overflowWork,
            bombe: bombe,
            settingRange: overflowRange,
            initialHitCapacity: 1,
            maximumRetryHitCapacity: 100_000
        )
        print("overflow probe : rerun receipts \(rerun.hits.count); bisected drain")
        let bisected = try engine.evaluateComplete(
            work: overflowWork,
            bombe: bombe,
            settingRange: overflowRange,
            initialHitCapacity: 1,
            maximumRetryHitCapacity: 1
        )
        try muleinControlRequire(rerun.hits == overflowSwift,
                                 "attempted-count overflow rerun differs from Swift")
        try muleinControlRequire(bisected.hits == overflowSwift,
                                 "bisected overflow drain differs from Swift")
        print("PASS overflow  : typed throw, counter invariant, exact retry, and bisection drain")

        if !quick {
            let greekV = 369_096..<386_672
            _ = try gradeMuleinParity(
                label: "Greek-V slice",
                engine: engine,
                work: [work[0], work[6]],
                bombe: bombe,
                settingRange: greekV,
                initialCapacity: 8_192
            )

            print("full drain     : 0..<456976 in 32768-setting chunks")
            var fullHits: [MuleinFutureMetalHit] = []
            var fullKeys = Set<MuleinControlKey>()
            let chunkSize = 32_768
            var lower = 0
            while lower < WelchmanMetalEngine.laneCount {
                let upper = min(lower + chunkSize, WelchmanMetalEngine.laneCount)
                let chunk = try engine.evaluateComplete(
                    work: [work[0]],
                    bombe: bombe,
                    settingRange: lower..<upper,
                    initialHitCapacity: 4_096
                )
                try muleinControlRequire(chunk.isComplete,
                                         "full-range chunk \(lower)..<\(upper) is incomplete")
                for candidate in chunk.hits {
                    let key = MuleinControlKey(
                        settingLane: candidate.settingLane,
                        futureIndex: candidate.futureIndex,
                        seed: candidate.seed
                    )
                    try muleinControlRequire(fullKeys.insert(key).inserted,
                                             "full-range drain duplicated a sparse key")
                    fullHits.append(candidate)
                }
                print("  covered      : \(lower)..<\(upper), hits \(chunk.hits.count)")
                lower = upper
            }
            fullHits.sort {
                ($0.settingLane, $0.futureIndex, $0.seed)
                    < ($1.settingLane, $1.futureIndex, $1.seed)
            }
            try muleinControlRequire(
                fullHits.contains {
                    $0.settingLane == trueLane && $0.seed == cleanSeed && $0.exact
                },
                "full P1030684 exact drain lost true lane \(trueLane)/seed \(cleanSeed)"
            )
            print("PASS full      : 456976 settings complete, \(fullHits.count) exact receipts; "
                + "true lane \(trueLane)/seed \(cleanSeed) retained")
        }

        print()
        if quick {
            print("PASS: blind Swift and cleartext Metal Future Bank receipts agree on every")
            print("      generated, historical, and detailed P1030684 parity control run in quick mode.")
        } else {
            print("PASS: blind Swift and cleartext Metal Future Bank receipts agree on every")
            print("      generated, historical, detailed P1030684, and Greek-V parity control.")
            print("PASS: the separate full-range P1030684 gate is a complete, duplicate-checked")
            print("      Metal drain; it is not described as exhaustive Swift parity.")
        }
        print("No P1030680 target data was evaluated; this is not a decrypt and not FHE.")
    } catch {
        fputs("FAIL: \(error)\n", stderr)
        fflush(stderr)
        exit(1)
    }
}

func muleinControlRequireUnwrap<T>(
    _ value: T?, _ message: @autoclosure () -> String
) throws -> T {
    guard let value else {
        throw MuleinFutureMetalError.benchmarkMismatch(message())
    }
    return value
}
