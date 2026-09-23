import CryptoKit
import Foundation
import HELUTCLI
import HELUTCore

// MARK: - `--sparse-adjudicate`
//
// Grades campaign candidates the running campaign could not grade, **without evaluating a single
// rotor setting**. Everything needed already sits in the durable ledger.
//
// Three design constraints, each forced rather than chosen:
//
//  1. **Read-only, separate ledger.** `p1030680ValidateChunkRecord` re-derives every candidate and
//     compares it with struct equality, so adding score fields to existing rows would fail all
//     4,184 checks and the campaign ledger would refuse to open. The input is opened without a
//     write lock so a resumed campaign is never blocked, and results go to a new file.
//  2. **Decode-only schema.** The campaign's row types are `private` and their two validation
//     functions must not be touched. This file declares its own decode structs for the subset it
//     reads. Drift cannot produce a silent wrong answer, because every candidate is re-verified
//     against rebuilt state (manifest digest, host board replay, live-state hash, pair and
//     determined counts, dropped-edge mask) before it is scored.
//  3. **Only the exact/no-drop post-gap family.** A repaired candidate is crib-exact-minus-k by
//     definition, and `PostBombeDiscriminator.isBreak` opens on `cribExact`. There is no bar for
//     them to be graded against, so they are counted and skipped rather than scored against an
//     invented threshold.

private struct SparseAdjudicatorRunIdentity: Codable, Equatable {
    let runID: String
    let targetID: String
    let manifestPath: String
    let manifestSHA256: String
    let manifestFingerprint: String
    let manifestEntries: Int
}

private struct SparseAdjudicatorCandidate: Codable {
    let settingLane: Int
    let positions: String
    let futureOrdinal: Int
    let futureID: String
    let family: String
    let seed: Int
    let exact: Bool
    let droppedEdgeMaskHex: String
    let droppedEdgeIDs: [MuleinEdgeID]
    let pairCount: Int
    let determinedCount: Int
    let liveHashHex: String
    let breakEligibility: String
}

private struct SparseAdjudicatorRow: Codable {
    let run: SparseAdjudicatorRunIdentity
    let chunkID: String
    let shellIndex: Int
    let ukw: String
    let greek: String
    let wheelOrder: String
    let rings: String
    let futureOrdinal: Int
    let futureID: String
    let futureFamily: String
    let candidates: [SparseAdjudicatorCandidate]
    let breakGatePassed: Bool
}

/// One adjudicated candidate, emitted whether or not it clears the bar.
private struct SparseAdjudicationRecord: Codable {
    let schemaVersion: Int
    let kind: String
    let sourceLedger: String
    let sourceLedgerSHA256: String
    let runID: String
    let chunkID: String
    let shell: String
    let futureOrdinal: Int
    let futureID: String
    let family: String
    let settingLane: Int
    let positions: String
    let seed: Int
    let hypothesisLabel: String
    let transmittedLength: Int
    let recordedLength: Int
    let holeCount: Int
    let crib: String
    let transmittedOffset: Int
    let completionsExamined: Int
    let steckerPairs: String
    let cribExact: Bool
    let sparseIC: Double
    let sparseBigramMean: Double?
    let sparseTrigramMean: Double?
    let eligibleSymbolCount: Int
    let contiguousRunCount: Int
    let barrierCount: Int
    let trigramWindowCount: Int
    let recordedPlaintextRendering: String
    let clearsDenseBar: Bool
    let assessment: String
    let scope: String
}

private let sparseAdjudicationSchemaVersion = 1
private let sparseAdjudicationScope =
    "Read-only geometry-aware adjudication of exact/no-drop post-gap candidates. "
        + "No rotor setting evaluated; no repaired candidate graded; not a decrypt."

func runP1030680SparseAdjudication() {
    guard let ledgerPath = stringFlag("--sparse-adjudicate") else {
        fputs("--sparse-adjudicate requires a campaign ledger path\n", stderr)
        exit(2)
    }
    let outputPath = stringFlag("--sparse-adjudicate-out")
        ?? "logs/p1030680-sparse-adjudication.jsonl"
    let limit = intFlag("--sparse-adjudicate-limit", allowZero: true) ?? 0

    print("=== P1030680 sparse candidate adjudication (read-only) ===")
    print("source ledger : \(ledgerPath)")
    print("output        : \(outputPath)")
    print("bar           : crib-exact ∧ IC ≥ \(PostBombeDiscriminator.icFloor) ∧ "
        + "sparse trigram > \(PostBombeDiscriminator.breakThreshold)")
    print("scope         : exact/no-drop post-gap only. Repaired candidates are counted, not")
    print("                graded — `cribExact` is undefined when the board discarded a letter.")
    print()
    fflush(stdout)

    guard let ledgerData = FileManager.default.contents(atPath: ledgerPath) else {
        fputs("could not read campaign ledger at \(ledgerPath)\n", stderr)
        exit(1)
    }
    let ledgerDigest = SHA256.hash(data: ledgerData)
        .map { String(format: "%02x", $0) }.joined()
    print("ledger SHA-256: \(ledgerDigest)")

    // ---- decode ------------------------------------------------------------------------
    let decoder = JSONDecoder()
    var rows: [SparseAdjudicatorRow] = []
    for (index, segment) in ledgerData.split(
        separator: 0x0a, omittingEmptySubsequences: true
    ).enumerated() {
        guard let row = try? decoder.decode(
            SparseAdjudicatorRow.self, from: Data(segment)
        ) else {
            fputs("malformed ledger row at line \(index + 1)\n", stderr)
            exit(1)
        }
        rows.append(row)
    }
    guard let identity = rows.first?.run else {
        fputs("campaign ledger is empty\n", stderr)
        exit(1)
    }
    guard rows.allSatisfy({ $0.run == identity }) else {
        fputs("campaign ledger mixes run identities — refusing to adjudicate\n", stderr)
        exit(1)
    }
    print("rows          : \(rows.count)")
    print("run           : \(identity.runID)")

    // ---- rebind the manifest by content, not by path -----------------------------------
    guard let manifestData = FileManager.default.contents(atPath: identity.manifestPath) else {
        fputs("could not read manifest \(identity.manifestPath)\n", stderr)
        exit(1)
    }
    let manifestDigest = SHA256.hash(data: manifestData)
        .map { String(format: "%02x", $0) }.joined()
    guard manifestDigest == identity.manifestSHA256 else {
        fputs(
            "manifest has changed since the run: \(manifestDigest) != "
                + "\(identity.manifestSHA256). Refusing to score against a different inventory.\n",
            stderr
        )
        exit(1)
    }
    guard let manifest = try? MuleinFutureManifestBuilder.load(data: manifestData),
          let work = try? MuleinFutureManifestBuilder.materialize(manifest) else {
        fputs("manifest failed semantic validation or materialization\n", stderr)
        exit(1)
    }
    guard manifest.inventoryFingerprint == identity.manifestFingerprint,
          manifest.entries.count == identity.manifestEntries else {
        fputs("manifest fingerprint/entry count disagrees with the ledger identity\n", stderr)
        exit(1)
    }
    print("manifest      : \(manifest.entries.count) Futures, "
        + "fingerprint \(manifest.inventoryFingerprint) — rebound by content")
    let ciphertext = EnigmaAlphabet.normalize(manifest.ciphertext)
    print()

    // ---- select the adjudicable population ---------------------------------------------
    var totalCandidates = 0
    var skippedRepaired = 0
    var skippedExactIdentity = 0
    var selected: [(row: SparseAdjudicatorRow, candidate: SparseAdjudicatorCandidate)] = []
    for row in rows {
        for candidate in row.candidates {
            totalCandidates += 1
            let isPostGap = candidate.family != "identity"
            let isClean = candidate.exact && candidate.droppedEdgeIDs.isEmpty
            if isPostGap && isClean {
                selected.append((row, candidate))
            } else if isClean {
                skippedExactIdentity += 1
            } else {
                skippedRepaired += 1
            }
        }
    }
    print("candidates    : \(totalCandidates) total")
    print("  adjudicable : \(selected.count)  (exact, no drop, post-gap)")
    print("  already done: \(skippedExactIdentity)  (exact identity — scored by the campaign)")
    print("  deferred    : \(skippedRepaired)  (repaired — no declared bar)")
    print()
    if limit > 0 && selected.count > limit {
        selected = Array(selected.prefix(limit))
        print("limited to \(limit) candidate(s) by --sparse-adjudicate-limit")
        print()
    }
    guard !selected.isEmpty else {
        print("nothing to adjudicate.")
        return
    }

    // ---- adjudicate ---------------------------------------------------------------------
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    var emitted: [SparseAdjudicationRecord] = []
    var clearedBar = 0
    var cribExactCount = 0
    var bestTrigram = -Double.infinity
    var bestLine = ""

    print("  # shell/future                                    pairs cribX     IC "
        + "   sparse-tri  win  runs  assessment")
    print("  " + String(repeating: "-", count: 118))

    for (index, item) in selected.enumerated() {
        let row = item.row
        let candidate = item.candidate
        guard work.indices.contains(candidate.futureOrdinal) else {
            fputs("candidate names Future \(candidate.futureOrdinal) outside the manifest\n", stderr)
            exit(1)
        }
        let futureWork = work[candidate.futureOrdinal]
        let future = futureWork.future
        let entry = manifest.entries[candidate.futureOrdinal]
        guard future.id.rawValue == candidate.futureID else {
            fputs("Future content ID disagrees with the ledger row\n", stderr)
            exit(1)
        }

        // Rebuild the shell from what the row literally says, rather than re-deriving an index.
        let rotorNames = row.wheelOrder.split(separator: "-").map(String.init)
        guard rotorNames.count == 3 else {
            fputs("unparseable wheel order '\(row.wheelOrder)'\n", stderr)
            exit(1)
        }
        let bombe = WelchmanBombe(
            greek: EnigmaM4Warehouse.greek(named: row.greek),
            left: EnigmaWarehouse.rotor(named: rotorNames[0]),
            middle: EnigmaWarehouse.rotor(named: rotorNames[1]),
            right: EnigmaWarehouse.rotor(named: rotorNames[2]),
            reflector: EnigmaM4Warehouse.thinReflector(named: row.ukw),
            rings: EnigmaM4Key.rings(fromLetters: row.rings),
            maxPlugs: futureWork.maxPlugs
        )
        let positions = WelchmanMetalEngine.position(forLane: candidate.settingLane)
        let scramblers = bombe.scramblers(menu: future.menu, start: positions)

        // Independent host replay before anything is scored. This is the same check the campaign
        // performed, repeated here so adjudication cannot inherit a corrupted row.
        guard let host = MuleinBoard.propagate(
            menu: future.menu,
            scramblers: scramblers,
            seedLetter: future.menu.central,
            seedValue: candidate.seed,
            tolerance: futureWork.tolerance,
            maxPlugs: futureWork.maxPlugs,
            exactPlugs: futureWork.exactPlugs
        ) else {
            fputs("candidate \(index + 1) failed independent host replay\n", stderr)
            exit(1)
        }
        guard host.exact == candidate.exact,
              host.pairCount == candidate.pairCount,
              host.determinedCount == candidate.determinedCount,
              String(format: "0x%08x", host.liveHash) == candidate.liveHashHex,
              host.droppedEdges.isEmpty else {
            fputs("candidate \(index + 1) disagrees with its persisted host state\n", stderr)
            exit(1)
        }

        // Every ≤maxPlugs board satisfying the whole menu, not just the seeded component.
        let tables = PostBombeDiscriminator.completedSteckers(
            menu: future.menu, scramblers: scramblers, maxPlugs: futureWork.maxPlugs
        )

        let cribLetters = EnigmaAlphabet.normalize(entry.evidence.crib)
        let cribOffset = entry.evidence.transmittedOffset
        let holeCount = future.geometry.recordedIndexByTransmittedStep
            .filter { $0 == nil }.count

        var best: SparseAdjudicationRecord?
        for table in tables {
            let key = EnigmaM4Key(
                greek: EnigmaM4Warehouse.greek(named: row.greek),
                rotors: (
                    EnigmaWarehouse.rotor(named: rotorNames[0]),
                    EnigmaWarehouse.rotor(named: rotorNames[1]),
                    EnigmaWarehouse.rotor(named: rotorNames[2])
                ),
                rings: EnigmaM4Key.rings(fromLetters: row.rings),
                positions: positions,
                plugboard: table,
                reflector: EnigmaM4Warehouse.thinReflector(named: row.ukw)
            )
            guard let transcript = try? MuleinSparseTranscriptBuilder.build(
                future: future, key: key, recordedCiphertext: ciphertext
            ), let validated = try? MuleinSparseReferenceEvaluator.validate(transcript) else {
                continue
            }
            let icTrace = MuleinSparseReferenceEvaluator.accumulateIC(validated)
            let adjacency = MuleinSparseReferenceEvaluator.traceAdjacency(
                validated, orders: [2, 3]
            )
            let ngrams = try? MuleinSparseReferenceEvaluator.evaluateNGrams(
                adjacency, using: [MuleinGermanBigramModel(), MuleinGermanTrigramModel()]
            )
            let ic = icTrace.possiblePairCount > 0
                ? Double(icTrace.coincidencePairCount) / Double(icTrace.possiblePairCount)
                : 0
            let trigram = ngrams?.first(where: { $0.order == 3 })
            let bigram = ngrams?.first(where: { $0.order == 2 })

            // Crib exactness in TRANSMITTED coordinates. This is the whole point: under post-gap
            // geometry the crib sits at transmitted steps, and indexing a recorded array here is
            // precisely the bug that made these candidates ungradeable.
            var recovered: [Int: Int] = [:]
            for cell in transcript.cells {
                guard case let .eligible(symbol) = cell.plaintext else { continue }
                recovered[cell.transmittedStep] = symbol.rawValue
            }
            var cribExact = true
            for (cribIndex, letter) in cribLetters.enumerated() {
                guard recovered[cribOffset + cribIndex] == letter else {
                    cribExact = false
                    break
                }
            }

            let clears = cribExact
                && ic >= PostBombeDiscriminator.icFloor
                && (trigram?.meanLogProbability ?? -.infinity)
                    > PostBombeDiscriminator.breakThreshold
            let record = SparseAdjudicationRecord(
                schemaVersion: sparseAdjudicationSchemaVersion,
                kind: "sparse-adjudicated-candidate",
                sourceLedger: ledgerPath,
                sourceLedgerSHA256: ledgerDigest,
                runID: identity.runID,
                chunkID: row.chunkID,
                shell: "\(row.ukw)/\(row.greek)/\(row.wheelOrder)/\(row.rings)",
                futureOrdinal: candidate.futureOrdinal,
                futureID: candidate.futureID,
                family: candidate.family,
                settingLane: candidate.settingLane,
                positions: candidate.positions,
                seed: candidate.seed,
                hypothesisLabel: entry.hypothesis.label,
                transmittedLength: future.geometry.transmittedLength,
                recordedLength: future.geometry.recordedLength,
                holeCount: holeCount,
                crib: entry.evidence.crib,
                transmittedOffset: cribOffset,
                completionsExamined: tables.count,
                steckerPairs: p1030680SparseSteckerPairs(table),
                cribExact: cribExact,
                sparseIC: ic,
                sparseBigramMean: bigram?.meanLogProbability,
                sparseTrigramMean: trigram?.meanLogProbability,
                eligibleSymbolCount: adjacency.eligiblePlaintext.count,
                contiguousRunCount: adjacency.runs.count,
                barrierCount: adjacency.barriers.count,
                trigramWindowCount: trigram?.normalizationCount ?? 0,
                recordedPlaintextRendering:
                    MuleinSparseTranscriptBuilder.recordedPlaintextRendering(transcript),
                clearsDenseBar: clears,
                assessment: clears
                    ? "clears-dense-bar-awaiting-human-review"
                    : (cribExact
                        ? "crib-exact-below-bar"
                        : "scored-not-crib-exact"),
                scope: sparseAdjudicationScope
            )
            // Crib-reproducing completions always beat those that do not; then language.
            if best == nil
                || (record.cribExact && !(best!.cribExact))
                || (record.cribExact == best!.cribExact
                    && (record.sparseTrigramMean ?? -.infinity)
                        > (best!.sparseTrigramMean ?? -.infinity)) {
                best = record
            }
        }

        guard let winner = best else {
            print(String(format: "  %2d %-48@ %5d     -      -           -    -     - "
                         + "no-consistent-board",
                         index + 1,
                         "\(row.shellIndex)/\(candidate.futureOrdinal)" as NSString,
                         candidate.pairCount))
            continue
        }
        emitted.append(winner)
        if winner.clearsDenseBar { clearedBar += 1 }
        if winner.cribExact { cribExactCount += 1 }
        if let tri = winner.sparseTrigramMean, tri > bestTrigram {
            bestTrigram = tri
            bestLine = "\(winner.shell) lane \(winner.settingLane) "
                + "Future \(winner.futureOrdinal)"
        }

        print(String(format: "  %2d %-48@ %5d  %@ %6.4f  %11.4f %4d  %4d  %@",
                     index + 1,
                     "\(row.shellIndex)/\(candidate.futureOrdinal) \(winner.positions)" as NSString,
                     candidate.pairCount,
                     (winner.cribExact ? " ok " : "BAD ") as NSString,
                     winner.sparseIC,
                     winner.sparseTrigramMean ?? .nan,
                     winner.trigramWindowCount,
                     winner.contiguousRunCount,
                     winner.assessment as NSString))
        fflush(stdout)
    }

    // ---- emit + summarize ---------------------------------------------------------------
    let outputURL = URL(fileURLWithPath: outputPath)
    try? FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    var payload = Data()
    for record in emitted {
        guard var line = try? encoder.encode(record) else { continue }
        line.append(0x0a)
        payload.append(line)
    }
    do {
        try payload.write(to: outputURL, options: .atomic)
    } catch {
        fputs("could not write adjudication ledger: \(error)\n", stderr)
        exit(1)
    }

    print()
    print("=== Adjudication summary ===")
    print("adjudicated        : \(emitted.count) of \(selected.count) selected")
    print("crib-exact         : \(cribExactCount)")
    print("clears dense bar   : \(clearedBar)")
    if bestTrigram > -Double.infinity {
        print(String(format: "best sparse trigram: %.4f  (%@)", bestTrigram,
                     bestLine as NSString))
        print(String(format: "                     German %.3f / bar %.3f / noise %.3f",
                     PostBombeDiscriminator.germanReference,
                     PostBombeDiscriminator.breakThreshold,
                     PostBombeDiscriminator.noiseReference))
    }
    print("deferred repaired  : \(skippedRepaired) (no declared bar)")
    print("wrote              : \(outputPath)")
    print()
    if clearedBar == 0 {
        print("NO CANDIDATE CLEARS THE BAR. P1030680 remains unbroken. This adjudicates the")
        print("exact/no-drop post-gap family only; repaired candidates and every unrun setting,")
        print("shell, and ring remain open.")
    } else {
        print("*** \(clearedBar) CANDIDATE(S) CLEAR THE DENSE BAR — HUMAN REVIEW REQUIRED ***")
        print("This is NOT an automatic break. Before any claim: confirm crib exactness by hand,")
        print("check the plaintext reads as naval German, verify the ≤10-plug board, and record")
        print("the victory condition in BREAK_P1030680.md. No gate row is written automatically.")
    }
    fflush(stdout)
}

private func p1030680SparseSteckerPairs(_ table: [Int]) -> String {
    var seen = Set<Int>()
    var pairs: [String] = []
    for letter in 0..<26 where table[letter] != letter && !seen.contains(letter) {
        seen.insert(letter)
        seen.insert(table[letter])
        pairs.append("\(EnigmaAlphabet.character(letter))\(EnigmaAlphabet.character(table[letter]))")
    }
    return pairs.isEmpty ? "(none)" : pairs.sorted().joined(separator: " ")
}
