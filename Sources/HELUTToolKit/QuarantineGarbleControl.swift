import Foundation
import HELUTCore
import HELUTCLI

// MARK: - Quarantine garble control

private struct GarbleControlCase {
    let name: String
    let cleanCT: [Int]
    let garbledCT: [Int]
    let plain: [Int]
    let edits: [String]
    let rings: String
    let positions: String
    let ukw: String
    let greek: String
    let wheelOrder: String
    let bombe: WelchmanBombe
    let wheelOrders: [(EnigmaRotorSpec, EnigmaRotorSpec, EnigmaRotorSpec)]
    let sourceLabel: String
    let garbleNote: String
}

/// Grade the near-miss pipeline on a known key with CT garbles.
///
/// Default: synthetic block-wipe on P1030684.
/// `--garble-source donitz`: historical Schlüsselzettel re-check vs proofed CT
/// `--garble-source donitz-first`: first draft (aligned: `.`→X, insert HMHY)
/// from Girard's [P1030681 degarbling](https://enigma.hoerenberg.com/index.php?cat=The%20U534%20messages&page=Degarbling%20the%20D%C3%B6nitz%20Message%20P1030681).
func runQuarantineGarbleControl() {
    let source = (stringFlag("--garble-source") ?? "synthetic").lowercased()
    let cribLen = intFlag("--garble-crib-len") ?? 18
    let escalate = !CommandLine.arguments.contains("--garble-no-escalate")
    let softBar = NearMissQuarantine.defaultSoftBar()

    let control: GarbleControlCase
    switch source {
    case "donitz", "p1030681", "schluesselzettel", "schlüsselzettel",
         "donitz-first", "first-draft", "p1030681-first":
        let useFirst = source.contains("first") || source.contains("draft")
        let clean = EnigmaAlphabet.normalize(ControlMessageP1030681.ciphertextProofed)
        let garbled = EnigmaAlphabet.normalize(
            useFirst
                ? ControlMessageP1030681.ciphertextFirstDraftAligned
                : ControlMessageP1030681.ciphertextSchluesselzettel
        )
        let plain = EnigmaAlphabet.normalize(ControlMessageP1030681.plaintext)
        precondition(clean.count == garbled.count && clean.count == plain.count)
        let edits = useFirst
            ? ControlMessageP1030681.firstDraftEdits()
            : ControlMessageP1030681.schluesselzettelEdits()
        // Crib must sit in the shared head (both historical drafts ≡ proofed for first 56).
        let sharedHead = zip(clean, garbled).prefix { $0 == $1 }.count
        precondition(
            cribLen <= sharedHead,
            "cribLen \(cribLen) exceeds shared CT head \(sharedHead)"
        )
        control = GarbleControlCase(
            name: useFirst
                ? "P1030681 Dönitz (first-draft aligned)"
                : "P1030681 Dönitz (Schlüsselzettel near-miss)",
            cleanCT: clean,
            garbledCT: garbled,
            plain: plain,
            edits: edits,
            rings: ControlMessageP1030681.rings,
            positions: ControlMessageP1030681.positions,
            ukw: "C",
            greek: "beta",
            wheelOrder: "V-VI-VIII",
            bombe: ControlMessageP1030681.bombe(),
            wheelOrders: [
                (EnigmaWarehouse.rotorV, EnigmaWarehouse.rotorVI, EnigmaWarehouse.rotorVIII)
            ],
            sourceLabel: useFirst
                ? "Girard/Hörenberg first draft (aligned)"
                : "Girard/Hörenberg Schlüsselzettel re-check",
            garbleNote: useFirst
                ? "historical first draft: .→X + insert HMHY; \(edits.count) CT diffs; shared head \(sharedHead)"
                : "historical 12-letter CT diffs vs proofed; crib head identical"
        )
    default:
        let flips = intFlag("--garble-flips") ?? 20
        let seed = UInt64(intFlag("--garble-seed") ?? 0x6A48_1E01)
        let blockWipe = !CommandLine.arguments.contains("--garble-scatter")
        let clean = EnigmaAlphabet.normalize(ControlMessageP1030684.ciphertext)
        let plain = EnigmaAlphabet.normalize(ControlMessageP1030684.plaintext)
        precondition(cribLen >= 16 && cribLen < plain.count)
        let (garbled, edits) = NearMissQuarantine.garbleCiphertext(
            clean,
            cribStart: 0,
            cribEnd: cribLen,
            flipCount: flips,
            seed: seed,
            blockWipe: blockWipe
        )
        control = GarbleControlCase(
            name: "P1030684 synthetic garble",
            cleanCT: clean,
            garbledCT: garbled,
            plain: plain,
            edits: edits,
            rings: ControlMessageP1030684.rings,
            positions: ControlMessageP1030684.positions,
            ukw: "B",
            greek: "gamma",
            wheelOrder: "IV-III-VIII",
            bombe: ControlMessageP1030684.bombe(),
            wheelOrders: [
                (EnigmaWarehouse.rotorIV, EnigmaWarehouse.rotorIII, EnigmaWarehouse.rotorVIII)
            ],
            sourceLabel: "synthetic \(blockWipe ? "block-wipe" : "scatter")",
            garbleNote: "flips=\(edits.count) seed=\(seed)"
        )
    }

    let qPath = stringFlag("--bombe-quarantine")
        ?? {
            if source.contains("first") || source.contains("draft") {
                return "logs/quarantine_p1030681_first_draft.json"
            }
            if source.hasPrefix("don") || source.contains("1030681") || source.contains("schl") {
                return "logs/quarantine_p1030681_schluesselzettel.json"
            }
            return "logs/quarantine_p1030684_garbled.json"
        }()

    let cribText = EnigmaAlphabet.string(from: Array(control.plain[0..<cribLen]))
    let truth = EnigmaM4Key.positions(fromLetters: control.positions)

    print("=== Quarantine garble control — \(control.name) ===")
    print(
        "shell: UKW \(control.ukw) / \(control.greek) / \(control.wheelOrder) "
            + "/ rings \(control.rings) / key \(control.positions)"
    )
    print("crib@0 len=\(cribLen): \(cribText)")
    print("garble: \(control.sourceLabel) — \(control.garbleNote)")
    print(
        "edits (\(control.edits.count)): "
            + control.edits.prefix(12).joined(separator: " ")
            + (control.edits.count > 12 ? " …" : "")
    )
    print(String(
        format: "soft band: IC≥%.3f tail>%.3f | strict: IC≥%.3f tail>%.3f",
        softBar.softICFloor,
        softBar.softTailFloor,
        softBar.strictICFloor,
        softBar.strictTailFloor
    ))
    print()

    func stopAtTruth(ciphertext: [Int]) -> SweepStop {
        guard let menu = BombeMenuBuilder.menu(
            crib: cribText, offset: 0, ciphertext: ciphertext
        ) else {
            fatalError("could not build control menu on this ciphertext")
        }
        let hits = control.bombe.test(menu: menu, start: truth)
        guard let stop = hits.first else {
            fatalError("true message key killed by menu — crib/CT inconsistent")
        }
        return SweepStop(
            ukw: control.ukw,
            greek: control.greek,
            wheelOrder: control.wheelOrder,
            menu: menu,
            rings: EnigmaM4Key.rings(fromLetters: control.rings),
            stop: stop,
            ciphertext: ciphertext
        )
    }

    // --- Phase A: clean must BREAK ---
    print("--- Phase A: clean / proofed ciphertext ---")
    let cleanStop = stopAtTruth(ciphertext: control.cleanCT)
    let cleanRanked = PostBombeDiscriminator.rank(
        stops: [cleanStop], ciphertext: control.cleanCT
    ).candidates
    guard let cleanBest = cleanRanked.first else {
        fatalError("FAIL Phase A: no ranked candidates on clean CT")
    }
    print(String(
        format: "  best %@ IC=%.3f tail=%.3f cribExact=%@ break=%@",
        cleanBest.messageKey,
        cleanBest.ic,
        cleanBest.effectiveTailScore,
        cleanBest.cribExact ? "yes" : "no",
        PostBombeDiscriminator.isBreak(cleanBest) ? "yes" : "no"
    ))
    guard cleanBest.messageKey == control.positions,
          PostBombeDiscriminator.isBreak(cleanBest) else {
        fatalError("FAIL Phase A: true key must BREAK on clean/proofed CT")
    }
    print("  PASS — true key BREAKs on clean/proofed CT")
    print()

    // --- Phase B: garbled transcript ---
    print("--- Phase B: garbled / Schlüsselzettel ciphertext ---")
    let garbledStop = stopAtTruth(ciphertext: control.garbledCT)
    let garbledRanked = PostBombeDiscriminator.rank(
        stops: [garbledStop],
        ciphertext: control.garbledCT,
        provisionalICFloor: softBar.softICFloor
    ).candidates
    guard let garbledTruth = garbledRanked.first else {
        fatalError("FAIL Phase B: true key unscored after garble")
    }
    let isBreak = PostBombeDiscriminator.isBreak(garbledTruth)
    let soft = NearMissQuarantine.shouldQuarantine(garbledTruth, softBar: softBar)
    print(String(
        format: "  true key IC=%.3f tail=%.3f cribExact=%@ break=%@ soft=%@",
        garbledTruth.ic,
        garbledTruth.effectiveTailScore,
        garbledTruth.cribExact ? "yes" : "no",
        isBreak ? "yes" : "no",
        soft ? "yes" : "no"
    ))
    print("  decrypt head: \(String(garbledTruth.plaintext.prefix(48)))")

    if isBreak {
        print("  WEAK — garbled CT still BREAKs (historical near-miss may be too mild)")
    }
    guard garbledTruth.cribExact else {
        fatalError("FAIL Phase B: crib must stay exact (shared CT head required)")
    }
    guard soft || isBreak else {
        fatalError("FAIL Phase B: true key fell below soft band")
    }
    if soft && !isBreak {
        print("  PASS — true key is a soft-band near-miss (quarantine trap)")
    } else if isBreak {
        print("  PASS (partial) — still scores; quarantine written for escalate grade")
    }

    let candidate = NearMissQuarantine.makeCandidate(
        from: garbledTruth,
        source: control.name,
        softBar: softBar
    )
    let manifest = QuarantineManifest(
        target: control.name,
        ciphertext: EnigmaAlphabet.string(from: control.garbledCT),
        generatedAt: ISO8601DateFormatter().string(from: Date()),
        sourceFixture: control.sourceLabel,
        softBar: softBar,
        candidates: [candidate]
    )
    do {
        try NearMissQuarantine.writeManifest(manifest, to: qPath)
        print("  wrote \(qPath)")
    } catch {
        fatalError("FAIL Phase B: could not write quarantine: \(error)")
    }

    let fixturePath = stringFlag("--garble-fixture-out")
        ?? {
            if control.name.contains("first-draft") {
                return "Fixtures/p1030681_first_draft_menus.json"
            }
            if control.name.contains("0681") {
                return "Fixtures/p1030681_schluesselzettel_menus.json"
            }
            return "Fixtures/p1030684_garbled_control_menus.json"
        }()
    let fixture: [String: Any] = [
        "target": control.name,
        "note": control.garbleNote,
        "ciphertext": EnigmaAlphabet.string(from: control.garbledCT),
        "clean_ciphertext": EnigmaAlphabet.string(from: control.cleanCT),
        "garble_edits": control.edits,
        "cribs": [["text": cribText, "messages": 1, "offsets": [0]]]
    ]
    if let data = try? JSONSerialization.data(
        withJSONObject: fixture, options: [.prettyPrinted, .sortedKeys]
    ) {
        try? data.write(to: URL(fileURLWithPath: fixturePath))
        print("  wrote \(fixturePath)")
    }
    print()

    guard escalate else {
        print("Skipping Hybrid escalate (--garble-no-escalate).")
        return
    }

    print("--- Phase C: Hybrid escalate from quarantine ---")
    var config = HybridBombeHarness.Config()
    config.population = intFlag("--hybrid-pop") ?? 12
    config.generations = intFlag("--hybrid-gens") ?? 8
    config.eliteCount = 4
    config.knownPlaintext = control.plain
    config.kpaRatioFitness = true
    config.kpaHillSteps = intFlag("--hybrid-kpa-hill") ?? 24
    config.evolveShell = false
    config.freeRingMutation = false
    config.blockBGreekSamples = 0
    config.ringSeeds = [EnigmaM4Key.rings(fromLetters: control.rings)]
    config.wheelOrders = control.wheelOrders
    applyQuarantineSeeds(path: qPath, config: &config)

    // Ceiling: proofed PT vs decrypt(garbled CT) with true key ≈ len − editCount
    // for substitution-only garbles. Dönitz Schlüsselzettel is that case.
    let expectedHits = control.plain.count - control.edits.count
    let expectedRatio = Double(expectedHits) / Double(control.plain.count)
    print(String(
        format: "  expected ceiling ≈ %.1f%% (%d/%d) if shell+stecker correct",
        expectedRatio * 100,
        expectedHits,
        control.plain.count
    ))

    let best = HybridBombeHarness.run(
        ciphertext: control.garbledCT,
        config: config,
        progress: { print("  \($0)") }
    )
    let hits = Int(best.bestHit.score + 0.5)
    let denom = control.plain.count
    let ratio = Double(hits) / Double(denom)
    print(String(
        format: "  result: %d/%d (%.1f%%) shell=%@",
        hits,
        denom,
        ratio * 100,
        best.chromosome.describe(wheelOrders: config.wheelOrders)
    ))

    let survivorBar = 0.80
    if ratio + 1e-9 >= survivorBar {
        print("  PASS — quarantine seed clears ≥80% on garbled CT")
        if abs(ratio - expectedRatio) <= 0.05 + 1e-9 {
            print("  PASS — match near historical edit ceiling")
        }
    } else {
        print(String(format: "  FAIL — ratio %.1f%% below 80%%", ratio * 100))
        exit(1)
    }
}
