import Foundation
import HELUTCore

// MARK: - Additional transcript controls
//
// Historical P1030681/P1030714 data is a source-attributed regression, not an independently
// archived scan. Synthetic controls provide the mechanism ground truth by encrypting a fixed
// message locally and then applying each supported edit class.

private func controlLane(_ positions: (Int, Int, Int, Int)) -> Int {
    positions.0 * 17_576 + positions.1 * 676 + positions.2 * 26 + positions.3
}

private func controlHit(
    _ result: MuleinFutureMetalBatchResult,
    futureIndex: Int,
    lane: Int,
    seed: Int
) -> MuleinFutureMetalHit? {
    result.hits.first {
        $0.futureIndex == futureIndex && $0.settingLane == lane && $0.seed == seed
    }
}

private func menusMatch(_ lhs: MuleinFuture, _ rhs: MuleinFuture) -> Bool {
    lhs.executionKey == rhs.executionKey
}

private func exactTrueSeedSurvives(
    future: MuleinFuture,
    bombe: WelchmanBombe,
    positions: (Int, Int, Int, Int),
    stecker: [Int]
) -> Bool {
    let rows = bombe.scramblers(menu: future.menu, start: positions)
    let seed = stecker[future.menu.central]
    return MuleinBoard.propagate(
        menu: future.menu,
        scramblers: rows,
        seedLetter: future.menu.central,
        seedValue: seed,
        tolerance: 0,
        maxPlugs: 10,
        exactPlugs: 10
    ) != nil
}

private func centeredControlRange(lane: Int, count: Int = 64) -> Range<Int> {
    let lower = max(0, min(lane - count / 2, WelchmanMetalEngine.laneCount - count))
    return lower..<(lower + count)
}

// MARK: Girard/Hörenberg P1030681 + P1030714

private struct P1030681HistoricalFixtures {
    let earlyClean: MuleinFuture
    let earlySchluesselzettel: MuleinFuture
    let earlySchluesselzettelCorrected: MuleinFuture
    let earlyPlainPaper: MuleinFuture
    let earlyPlainPaperCorrected: MuleinFuture
    let lateClean: MuleinFuture
    let lateSchluesselzettelRejectedReason: String
    let lateSchluesselzettelCorrected: MuleinFuture
    let latePlainPaperGapOnly: MuleinFuture
    let latePlainPaperCorrected: MuleinFuture
    let latePositions: (Int, Int, Int, Int)
    let blankLocalRange: Range<Int>

    static func build() throws -> P1030681HistoricalFixtures {
        let theoretical = EnigmaAlphabet.normalize(ControlMessageP1030681.ciphertextTheoretical)
        let theoreticalPlain = EnigmaAlphabet.normalize(ControlMessageP1030681.plaintextTheoretical)
        let schluesselzettel = EnigmaAlphabet.normalize(
            ControlMessageP1030681.ciphertextSchluesselzettel
        )
        let proofed = EnigmaAlphabet.normalize(ControlMessageP1030681.ciphertextProofed)
        let finalPlain = EnigmaAlphabet.normalize(ControlMessageP1030681.plaintext)
        let plainPaperCharacters = Array(ControlMessageP1030681.ciphertextPlainPaperRaw)

        try muleinControlRequire(theoretical.count == 372,
                                 "P1030681 theoretical ciphertext length changed")
        try muleinControlRequire(schluesselzettel.count == theoretical.count,
                                 "P1030681 Schlüsselzettel length changed")
        try muleinControlRequire(proofed.count == theoretical.count,
                                 "P1030681 final proof length changed")
        try muleinControlRequire(plainPaperCharacters.count == theoretical.count,
                                 "P1030714 plain-paper layout length changed")
        try muleinControlRequire(theoreticalPlain.count == theoretical.count,
                                 "P1030681 reconstructed plaintext length changed")

        var finalMachine = EnigmaM4Machine(key: ControlMessageP1030681.key)
        try muleinControlRequire(
            finalMachine.processText(proofed) == finalPlain,
            "published P1030681 key does not reproduce the final proof decryption"
        )
        var theoreticalMachine = EnigmaM4Machine(key: ControlMessageP1030681.key)
        try muleinControlRequire(
            theoreticalMachine.processText(theoreticalPlain) == theoretical,
            "published P1030681 key does not round-trip the theoretical reconstruction"
        )

        func evidence(
            sourceID: String,
            cribID: String,
            crib: String,
            offset: Int,
            ciphertext: [Int]
        ) -> MuleinFutureEvidence {
            MuleinFutureEvidence(
                targetID: "P1030681-P1030714-historical-control",
                sourceID: sourceID,
                cribID: cribID,
                crib: crib,
                transmittedOffset: offset,
                ciphertext: ciphertext
            )
        }

        func replacementEdits(
            observed: [Int],
            truth: [Int],
            transmittedRange: Range<Int>,
            recordedIndex: (Int) -> Int
        ) -> [MuleinTranscriptEdit] {
            transmittedRange.compactMap { transmitted in
                let recorded = recordedIndex(transmitted)
                guard observed[recorded] != truth[transmitted] else { return nil }
                return .replacement(
                    recordedIndex: recorded,
                    observed: observed[recorded],
                    hypothesized: truth[transmitted]
                )
            }
        }

        // An early window fits the native 0..<80 trail and contains errors in both copies while
        // stopping immediately before P1030714's first illegible dot.
        let earlyStart = 48
        let earlyLength = 31
        let earlyRange = earlyStart..<(earlyStart + earlyLength)
        let earlyCrib = EnigmaAlphabet.string(from: Array(theoreticalPlain[earlyRange]))
        let plainPaperPrefixText = String(plainPaperCharacters[0..<earlyRange.upperBound])
        let plainPaperPrefix = EnigmaAlphabet.normalize(plainPaperPrefixText)
        try muleinControlRequire(plainPaperPrefix.count == earlyRange.upperBound,
                                 "P1030714 early control unexpectedly contains an illegible")

        let earlyCleanEvidence = evidence(
            sourceID: "girard-theoretical",
            cribID: "early-48-78",
            crib: earlyCrib,
            offset: earlyStart,
            ciphertext: theoretical
        )
        let earlySZEvidence = evidence(
            sourceID: "P1030681-schluesselzettel",
            cribID: "early-48-78",
            crib: earlyCrib,
            offset: earlyStart,
            ciphertext: schluesselzettel
        )
        let earlyPPEvidence = evidence(
            sourceID: "P1030714-plain-paper",
            cribID: "early-48-78",
            crib: earlyCrib,
            offset: earlyStart,
            ciphertext: plainPaperPrefix
        )
        let earlyClean = try MuleinFutureLattice.compile(
            evidence: earlyCleanEvidence, hypothesis: .exact, minimumEdges: earlyLength
        )
        let earlySchluesselzettel = try MuleinFutureLattice.compile(
            evidence: earlySZEvidence, hypothesis: .exact, minimumEdges: earlyLength
        )
        let earlySchluesselzettelCorrected = try MuleinFutureLattice.compile(
            evidence: earlySZEvidence,
            hypothesis: MuleinFutureHypothesis(
                label: "correct-from-theoretical-reencipherment",
                edits: replacementEdits(
                    observed: schluesselzettel,
                    truth: theoretical,
                    transmittedRange: earlyRange,
                    recordedIndex: { $0 }
                )
            ),
            minimumEdges: earlyLength
        )
        let earlyPlainPaper = try MuleinFutureLattice.compile(
            evidence: earlyPPEvidence, hypothesis: .exact, minimumEdges: earlyLength
        )
        let earlyPlainPaperCorrected = try MuleinFutureLattice.compile(
            evidence: earlyPPEvidence,
            hypothesis: MuleinFutureHypothesis(
                label: "correct-from-theoretical-reencipherment",
                edits: replacementEdits(
                    observed: plainPaperPrefix,
                    truth: theoretical,
                    transmittedRange: earlyRange,
                    recordedIndex: { $0 }
                )
            ),
            minimumEdges: earlyLength
        )

        // Rebase the late HMHY window so its local transmitted steps fit the Future Bank's
        // bounded 0..<80 trail. Advancing the known machine changes only the starting windows.
        let lateStart = 340
        let lateEnd = 372
        let lateRange = lateStart..<lateEnd
        let latePlain = Array(theoreticalPlain[lateRange])
        let lateTruth = Array(theoretical[lateRange])
        var advance = EnigmaM4Machine(key: ControlMessageP1030681.key)
        _ = advance.processText(Array(theoreticalPlain[0..<lateStart]))
        let latePositions = advance.key.positions
        var rebasedKey = ControlMessageP1030681.key
        rebasedKey.positions = latePositions
        var rebasedMachine = EnigmaM4Machine(key: rebasedKey)
        try muleinControlRequire(
            rebasedMachine.processText(latePlain) == lateTruth,
            "rebased P1030681 HMHY window does not reproduce the theoretical ciphertext"
        )

        let lateSZ = Array(schluesselzettel[lateRange])
        let latePPCharacters = Array(plainPaperCharacters[lateRange])
        let blank = 16..<20
        try muleinControlRequire(String(latePPCharacters[blank]) == "....",
                                 "P1030714 HMHY blank is not at the expected late-window span")
        try muleinControlRequire(
            EnigmaAlphabet.string(from: Array(lateTruth[blank])) == "HMHY",
            "the theoretical HMHY group is not aligned with the P1030714 blank"
        )
        var latePPRecordedCharacters = latePPCharacters
        latePPRecordedCharacters.removeSubrange(blank)
        let latePPRecordedText = String(latePPRecordedCharacters)
        let latePPRecorded = EnigmaAlphabet.normalize(latePPRecordedText)
        try muleinControlRequire(latePPRecorded.count == latePPRecordedCharacters.count,
                                 "late P1030714 control contains another illegible cell")

        let lateCrib = EnigmaAlphabet.string(from: latePlain)
        let lateCleanEvidence = evidence(
            sourceID: "girard-theoretical-rebased",
            cribID: "late-340-371-hmhy",
            crib: lateCrib,
            offset: 0,
            ciphertext: lateTruth
        )
        let lateSZEvidence = evidence(
            sourceID: "P1030681-schluesselzettel-rebased",
            cribID: "late-340-371-hmhy",
            crib: lateCrib,
            offset: 0,
            ciphertext: lateSZ
        )
        let latePPEvidence = evidence(
            sourceID: "P1030714-plain-paper-rebased",
            cribID: "late-340-371-hmhy-blank",
            crib: lateCrib,
            offset: 0,
            ciphertext: latePPRecorded
        )

        let lateClean = try MuleinFutureLattice.compile(
            evidence: lateCleanEvidence, hypothesis: .exact, minimumEdges: 32
        )
        let rejectedLateSZ = MuleinFutureLattice.build(
            evidence: lateSZEvidence, hypotheses: [.exact], minimumEdges: 32
        )
        try muleinControlRequire(
            rejectedLateSZ.futures.isEmpty && rejectedLateSZ.rejected.count == 1,
            "uncorrected late Schlüsselzettel should fail the Enigma self-encipher prefilter"
        )
        let lateSchluesselzettelRejectedReason = rejectedLateSZ.rejected[0].reason
        try muleinControlRequire(
            lateSchluesselzettelRejectedReason.contains("self-enciphers"),
            "late Schlüsselzettel was rejected for an unexpected reason"
        )
        let lateSchluesselzettelCorrected = try MuleinFutureLattice.compile(
            evidence: lateSZEvidence,
            hypothesis: MuleinFutureHypothesis(
                label: "correct-late-schluesselzettel",
                edits: replacementEdits(
                    observed: lateSZ,
                    truth: lateTruth,
                    transmittedRange: 0..<32,
                    recordedIndex: { $0 }
                )
            ),
            minimumEdges: 32
        )

        let missing = MuleinTranscriptEdit.missingFromRecording(
            transmitted: MuleinSpan(start: blank.lowerBound, length: blank.count),
            recordedBoundary: blank.lowerBound
        )
        let latePlainPaperGapOnly = try MuleinFutureLattice.compile(
            evidence: latePPEvidence,
            hypothesis: MuleinFutureHypothesis(
                label: "P1030714-HMHY-blank-only",
                edits: [missing]
            ),
            minimumEdges: 28
        )
        var ppCorrections: [MuleinTranscriptEdit] = [missing]
        for transmitted in 0..<32 where !blank.contains(transmitted) {
            let recorded = transmitted < blank.lowerBound ? transmitted : transmitted - blank.count
            if latePPRecorded[recorded] != lateTruth[transmitted] {
                ppCorrections.append(.replacement(
                    recordedIndex: recorded,
                    observed: latePPRecorded[recorded],
                    hypothesized: lateTruth[transmitted]
                ))
            }
        }
        let latePlainPaperCorrected = try MuleinFutureLattice.compile(
            evidence: latePPEvidence,
            hypothesis: MuleinFutureHypothesis(
                label: "P1030714-HMHY-blank-plus-source-corrections",
                edits: ppCorrections
            ),
            minimumEdges: 28
        )

        return P1030681HistoricalFixtures(
            earlyClean: earlyClean,
            earlySchluesselzettel: earlySchluesselzettel,
            earlySchluesselzettelCorrected: earlySchluesselzettelCorrected,
            earlyPlainPaper: earlyPlainPaper,
            earlyPlainPaperCorrected: earlyPlainPaperCorrected,
            lateClean: lateClean,
            lateSchluesselzettelRejectedReason: lateSchluesselzettelRejectedReason,
            lateSchluesselzettelCorrected: lateSchluesselzettelCorrected,
            latePlainPaperGapOnly: latePlainPaperGapOnly,
            latePlainPaperCorrected: latePlainPaperCorrected,
            latePositions: latePositions,
            blankLocalRange: blank
        )
    }
}

func runP1030681FutureControls(engine: MuleinFutureMetalEngine) throws {
    let fixtures = try P1030681HistoricalFixtures.build()
    let bombe = ControlMessageP1030681.bombe(maxPlugs: 10)
    let positions = EnigmaM4Key.positions(fromLetters: ControlMessageP1030681.positions)
    let lane = controlLane(positions)
    let stecker = ControlMessageP1030681.trueStecker

    let earlyWork = [
        MuleinFutureMetalWork(
            future: fixtures.earlyClean, maxPlugs: 10, exactPlugs: 10
        ),
        MuleinFutureMetalWork(
            future: fixtures.earlySchluesselzettel, maxPlugs: 10, exactPlugs: 10
        ),
        MuleinFutureMetalWork(
            future: fixtures.earlySchluesselzettelCorrected, maxPlugs: 10, exactPlugs: 10
        ),
        MuleinFutureMetalWork(
            future: fixtures.earlyPlainPaper, maxPlugs: 10, exactPlugs: 10
        ),
        MuleinFutureMetalWork(
            future: fixtures.earlyPlainPaperCorrected, maxPlugs: 10, exactPlugs: 10
        )
    ]
    try muleinControlRequire(menusMatch(fixtures.earlyClean,
                                        fixtures.earlySchluesselzettelCorrected),
                             "early P1030681 correction does not restore the theoretical menu")
    try muleinControlRequire(menusMatch(fixtures.earlyClean,
                                        fixtures.earlyPlainPaperCorrected),
                             "early P1030714 correction does not restore the theoretical menu")
    let early = try gradeMuleinParity(
        label: "P1030681/P1030714 early source window",
        engine: engine,
        work: earlyWork,
        bombe: bombe,
        settingRange: centeredControlRange(lane: lane)
    )
    let cleanSeed = stecker[fixtures.earlyClean.menu.central]
    try muleinControlRequire(
        controlHit(early, futureIndex: 0, lane: lane, seed: cleanSeed)?.exact == true,
        "P1030681 theoretical early window lost its true candidate"
    )
    for index in [2, 4] {
        let future = earlyWork[index].future
        let seed = stecker[future.menu.central]
        try muleinControlRequire(
            controlHit(early, futureIndex: index, lane: lane, seed: seed)?.exact == true,
            "corrected historical early future \(index) lost the true candidate"
        )
    }
    try muleinControlRequire(
        controlHit(
            early,
            futureIndex: 1,
            lane: lane,
            seed: stecker[fixtures.earlySchluesselzettel.menu.central]
        ) == nil,
        "uncorrected P1030681 early copy unexpectedly retained the true candidate"
    )
    try muleinControlRequire(
        controlHit(
            early,
            futureIndex: 3,
            lane: lane,
            seed: stecker[fixtures.earlyPlainPaper.menu.central]
        ) == nil,
        "uncorrected P1030714 early copy unexpectedly retained the true candidate"
    )

    let lateLane = controlLane(fixtures.latePositions)
    let lateWork = [
        MuleinFutureMetalWork(future: fixtures.lateClean, maxPlugs: 10, exactPlugs: 10),
        MuleinFutureMetalWork(
            future: fixtures.lateSchluesselzettelCorrected, maxPlugs: 10, exactPlugs: 10
        ),
        MuleinFutureMetalWork(
            future: fixtures.latePlainPaperGapOnly, maxPlugs: 10, exactPlugs: 10
        ),
        MuleinFutureMetalWork(
            future: fixtures.latePlainPaperCorrected, maxPlugs: 10, exactPlugs: 10
        )
    ]
    try muleinControlRequire(menusMatch(fixtures.lateClean,
                                        fixtures.lateSchluesselzettelCorrected),
                             "late P1030681 corrections do not restore the theoretical menu")
    try muleinControlRequire(
        Set(fixtures.latePlainPaperCorrected.edges.filter { !$0.isBoardConstraint }
            .map(\.id.cribIndex)) == Set(fixtures.blankLocalRange),
        "P1030714 corrected future does not retain the four-cell HMHY blank receipt"
    )
    let late = try gradeMuleinParity(
        label: "P1030681/P1030714 rebased HMHY window",
        engine: engine,
        work: lateWork,
        bombe: bombe,
        settingRange: centeredControlRange(lane: lateLane)
    )
    try muleinControlRequire(
        fixtures.lateSchluesselzettelRejectedReason.contains("self-enciphers"),
        "late Schlüsselzettel pre-board rejection receipt was lost"
    )
    for index in [0, 1, 3] {
        let future = lateWork[index].future
        let seed = stecker[future.menu.central]
        try muleinControlRequire(
            controlHit(late, futureIndex: index, lane: lateLane, seed: seed)?.exact == true,
            "corrected historical late future \(index) lost the rebased true candidate"
        )
    }
    let gapOnly = lateWork[2].future
    try muleinControlRequire(
        controlHit(
            late,
            futureIndex: 2,
            lane: lateLane,
            seed: stecker[gapOnly.menu.central]
        ) == nil,
        "P1030714 gap-only future unexpectedly survived its retained substitutions"
    )

    print("PASS P1030681 : source-attributed two-copy correction and rebased HMHY blank")
    print("  provenance  : \(ControlMessageP1030681.sourceURL)")
    print("  scope       : historical regression from published transcriptions, not scan custody")
}

// MARK: Self-generated M4 edit controls

private struct SyntheticTranscriptCase {
    let label: String
    let naive: MuleinFuture
    let corrected: MuleinFuture
}

private struct SyntheticTranscriptFixtures {
    let key: EnigmaM4Key
    let bombe: WelchmanBombe
    let stecker: [Int]
    let plaintext: [Int]
    let ciphertext: [Int]
    let clean: MuleinFuture
    let cases: [SyntheticTranscriptCase]

    static func build() throws -> SyntheticTranscriptFixtures {
        let plugPairs: [(Character, Character)] = [
            ("A", "Z"), ("B", "Y"), ("C", "X"), ("D", "W"), ("E", "V"),
            ("F", "U"), ("G", "T"), ("H", "S"), ("I", "R"), ("J", "Q")
        ]
        let key = EnigmaM4Key(
            greek: EnigmaM4Warehouse.beta,
            rotors: (
                EnigmaWarehouse.rotorII,
                EnigmaWarehouse.rotorV,
                EnigmaWarehouse.rotorVII
            ),
            rings: EnigmaM4Key.rings(fromLetters: "BDFH"),
            positions: EnigmaM4Key.positions(fromLetters: "KQRM"),
            plugboard: EnigmaKey.plugboard(pairs: plugPairs),
            reflector: EnigmaM4Warehouse.thinC
        )
        let bombe = WelchmanBombe(
            greek: key.greek,
            left: key.rotors.0,
            middle: key.rotors.1,
            right: key.rotors.2,
            reflector: key.reflector,
            rings: key.rings,
            maxPlugs: 10
        )
        let plaintext = EnigmaAlphabet.normalize(
            "MULEINBOARDPRUEFTJEDEZUKUNFTXKLARTEXTMETALLBLEIBTMECHANIKX"
                + "DIESEKONTROLLEHATBEKANNTETRUTH"
        )
        try muleinControlRequire(plaintext.count >= 64,
                                 "synthetic control plaintext is too short")
        var encryptor = EnigmaM4Machine(key: key)
        let ciphertext = encryptor.processText(plaintext)
        var decryptor = EnigmaM4Machine(key: key)
        try muleinControlRequire(decryptor.processText(ciphertext) == plaintext,
                                 "synthetic M4 fixture failed its round trip")

        let cribLength = 40
        let crib = EnigmaAlphabet.string(from: Array(plaintext[0..<cribLength]))
        func evidence(source: String, recording: [Int]) -> MuleinFutureEvidence {
            MuleinFutureEvidence(
                targetID: "mulein-self-generated-control",
                sourceID: source,
                cribID: "fixed-key-40-edge-menu",
                crib: crib,
                transmittedOffset: 0,
                ciphertext: recording
            )
        }
        let cleanEvidence = evidence(source: "generated-clean", recording: ciphertext)
        let clean = try MuleinFutureLattice.compile(
            evidence: cleanEvidence, hypothesis: .exact, minimumEdges: cribLength
        )

        func compilePair(
            label: String,
            recording: [Int],
            correction: MuleinFutureHypothesis,
            correctedMinimum: Int = cribLength
        ) throws -> SyntheticTranscriptCase {
            let damagedEvidence = evidence(source: "generated-\(label)", recording: recording)
            let naive = try MuleinFutureLattice.compile(
                evidence: damagedEvidence, hypothesis: .exact, minimumEdges: cribLength
            )
            let corrected = try MuleinFutureLattice.compile(
                evidence: damagedEvidence,
                hypothesis: correction,
                minimumEdges: correctedMinimum
            )
            return SyntheticTranscriptCase(label: label, naive: naive, corrected: corrected)
        }

        let stecker = key.plugboard

        func selectCase(
            _ label: String,
            candidates: Range<Int>,
            build: (Int) throws -> SyntheticTranscriptCase
        ) throws -> SyntheticTranscriptCase {
            var lastReason = "no candidate compiled"
            for position in candidates {
                do {
                    let candidate = try build(position)
                    let naiveSurvives = exactTrueSeedSurvives(
                        future: candidate.naive,
                        bombe: bombe,
                        positions: key.positions,
                        stecker: stecker
                    )
                    let correctedSurvives = exactTrueSeedSurvives(
                        future: candidate.corrected,
                        bombe: bombe,
                        positions: key.positions,
                        stecker: stecker
                    )
                    if !naiveSurvives && correctedSurvives {
                        return SyntheticTranscriptCase(
                            label: label,
                            naive: candidate.naive,
                            corrected: candidate.corrected
                        )
                    }
                    lastReason = "candidate at \(position): naive=\(naiveSurvives), "
                        + "corrected=\(correctedSurvives)"
                } catch {
                    lastReason = "candidate at \(position): \(error)"
                }
            }
            throw MuleinFutureMetalError.benchmarkMismatch(
                "synthetic \(label) fixture selection failed (\(lastReason))"
            )
        }

        let candidatePositions = 8..<30
        let substitutionCase = try selectCase(
            "substitution", candidates: candidatePositions
        ) { substitutionIndex in
            var substituted = ciphertext
            var substitution = (ciphertext[substitutionIndex] + 1) % 26
            if substitution == plaintext[substitutionIndex] {
                substitution = (substitution + 1) % 26
            }
            substituted[substitutionIndex] = substitution
            return try compilePair(
                label: "substitution-\(substitutionIndex)",
                recording: substituted,
                correction: MuleinFutureHypothesis(
                    label: "restore-substitution",
                    edits: [.replacement(
                        recordedIndex: substitutionIndex,
                        observed: substitution,
                        hypothesized: ciphertext[substitutionIndex]
                    )]
                )
            )
        }

        let deletionLength = 4
        let deletionCase = try selectCase(
            "deletion", candidates: candidatePositions
        ) { deletionStart in
            var deleted = ciphertext
            deleted.removeSubrange(deletionStart..<(deletionStart + deletionLength))
            return try compilePair(
                label: "deletion-\(deletionStart)",
                recording: deleted,
                correction: MuleinFutureHypothesis(
                    label: "restore-missing-recording-geometry",
                    edits: [.missingFromRecording(
                        transmitted: MuleinSpan(
                            start: deletionStart, length: deletionLength
                        ),
                        recordedBoundary: deletionStart
                    )]
                ),
                correctedMinimum: cribLength - deletionLength
            )
        }

        let insertionLength = 3
        let insertionCase = try selectCase(
            "insertion", candidates: candidatePositions
        ) { insertionStart in
            var insertedSymbols = [25, 16, 9]
            for index in insertedSymbols.indices
            where insertedSymbols[index] == plaintext[insertionStart + index] {
                insertedSymbols[index] = (insertedSymbols[index] + 1) % 26
            }
            var inserted = ciphertext
            inserted.insert(contentsOf: insertedSymbols, at: insertionStart)
            return try compilePair(
                label: "insertion-\(insertionStart)",
                recording: inserted,
                correction: MuleinFutureHypothesis(
                    label: "remove-extra-recording-geometry",
                    edits: [.extraInRecording(
                        recorded: MuleinSpan(
                            start: insertionStart, length: insertionLength
                        ),
                        transmittedBoundary: insertionStart
                    )]
                )
            )
        }

        let transpositionCase = try selectCase(
            "transposition", candidates: candidatePositions
        ) { transposeStart in
            var transposed = ciphertext
            transposed.swapAt(transposeStart, transposeStart + 1)
            return try compilePair(
                label: "transposition-\(transposeStart)",
                recording: transposed,
                correction: MuleinFutureHypothesis(
                    label: "undo-adjacent-transposition",
                    edits: [.transposition(
                        recorded: MuleinSpan(start: transposeStart, length: 2),
                        permutation: [1, 0]
                    )]
                )
            )
        }

        let cases = [substitutionCase, deletionCase, insertionCase, transpositionCase]
        for item in cases {
            try muleinControlRequire(
                !exactTrueSeedSurvives(
                    future: item.naive,
                    bombe: bombe,
                    positions: key.positions,
                    stecker: stecker
                ),
                "synthetic \(item.label) naive future did not eliminate truth"
            )
            try muleinControlRequire(
                exactTrueSeedSurvives(
                    future: item.corrected,
                    bombe: bombe,
                    positions: key.positions,
                    stecker: stecker
                ),
                "synthetic \(item.label) correction did not restore truth"
            )
        }
        try muleinControlRequire(menusMatch(clean, substitutionCase.corrected),
                                 "synthetic substitution did not restore clean execution")
        try muleinControlRequire(menusMatch(clean, insertionCase.corrected),
                                 "synthetic insertion did not restore clean execution")
        try muleinControlRequire(menusMatch(clean, transpositionCase.corrected),
                                 "synthetic transposition did not restore clean execution")
        try muleinControlRequire(
            deletionCase.corrected.boardEdges.count == cribLength - deletionLength,
            "synthetic deletion did not retain a four-edge evidence gap"
        )

        return SyntheticTranscriptFixtures(
            key: key,
            bombe: bombe,
            stecker: stecker,
            plaintext: plaintext,
            ciphertext: ciphertext,
            clean: clean,
            cases: cases
        )
    }
}

func runSyntheticFutureControls(engine: MuleinFutureMetalEngine) throws {
    let fixtures = try SyntheticTranscriptFixtures.build()
    var work = [MuleinFutureMetalWork(
        future: fixtures.clean, maxPlugs: 10, exactPlugs: 10
    )]
    for item in fixtures.cases {
        work.append(MuleinFutureMetalWork(
            future: item.naive, maxPlugs: 10, exactPlugs: 10
        ))
        work.append(MuleinFutureMetalWork(
            future: item.corrected, maxPlugs: 10, exactPlugs: 10
        ))
    }

    let lane = controlLane(fixtures.key.positions)
    let result = try gradeMuleinParity(
        label: "self-generated deletion/insertion/substitution/transposition",
        engine: engine,
        work: work,
        bombe: fixtures.bombe,
        settingRange: centeredControlRange(lane: lane)
    )
    let cleanSeed = fixtures.stecker[fixtures.clean.menu.central]
    try muleinControlRequire(
        controlHit(result, futureIndex: 0, lane: lane, seed: cleanSeed)?.exact == true,
        "self-generated clean future lost truth"
    )
    for caseIndex in fixtures.cases.indices {
        let naiveIndex = 1 + caseIndex * 2
        let correctedIndex = naiveIndex + 1
        let naive = fixtures.cases[caseIndex].naive
        let corrected = fixtures.cases[caseIndex].corrected
        try muleinControlRequire(
            controlHit(
                result,
                futureIndex: naiveIndex,
                lane: lane,
                seed: fixtures.stecker[naive.menu.central]
            ) == nil,
            "self-generated \(fixtures.cases[caseIndex].label) naive Metal future retained truth"
        )
        try muleinControlRequire(
            controlHit(
                result,
                futureIndex: correctedIndex,
                lane: lane,
                seed: fixtures.stecker[corrected.menu.central]
            )?.exact == true,
            "self-generated \(fixtures.cases[caseIndex].label) corrected Metal future lost truth"
        )
    }

    print("PASS generated : fixed-key M4 round trip plus all four transcript edit classes")
    print("  shell       : thin C / beta / II-V-VII / rings BDFH / positions KQRM")
}
