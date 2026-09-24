import CryptoKit
import Foundation
import XCTest
@testable import HELUTCore
@testable import HELUTToolKit

/// Fast-path adapter + escalator tests. These do **not** load the 628-Future operational JSON.
final class MuleinOstwaldEscalateAdapterTests: XCTestCase {

    func testPreHostDispositionKeepsIdentityRepairsOnly() {
        XCTAssertEqual(
            MuleinOstwaldAdapt.preHostDisposition(
                family: "identity", exact: false, droppedEmpty: false
            ),
            .identityRepair
        )
        XCTAssertEqual(
            MuleinOstwaldAdapt.preHostDisposition(
                family: "identity", exact: true, droppedEmpty: true
            ),
            .exactIdentityAlreadyScored
        )
        XCTAssertEqual(
            MuleinOstwaldAdapt.preHostDisposition(
                family: "post-gap-delta4", exact: true, droppedEmpty: true
            ),
            .exactPostGapAlreadyAdjudicated
        )
        XCTAssertEqual(
            MuleinOstwaldAdapt.preHostDisposition(
                family: "post-gap-delta4", exact: false, droppedEmpty: false
            ),
            .postGapDenseOstwaldIllegal
        )
        XCTAssertEqual(
            MuleinOstwaldAdapt.preHostDisposition(
                family: "post-gap-delta4", exact: false, droppedEmpty: false,
                gappedPostGap: true
            ),
            .postGapGappedRepair
        )
        XCTAssertEqual(
            MuleinOstwaldAdapt.preHostDisposition(
                family: "identity", exact: true, droppedEmpty: false
            ),
            .inconsistentExactDrop
        )
        XCTAssertEqual(
            MuleinOstwaldAdapt.preHostDisposition(
                family: "identity", exact: false, droppedEmpty: true
            ),
            .inconsistentExactDrop
        )
    }

    func testForcedPairTokensReadsSingletonLiveBits() {
        var live = [UInt32](repeating: 0, count: 26)
        live[0] = 1 << 1
        live[1] = 1 << 0
        live[4] = 1 << 5
        live[5] = 1 << 4
        live[8] = 1 << 8
        let tokens = MuleinOstwaldAdapt.forcedPairTokens(from: live)
        XCTAssertEqual(tokens, ["AB", "EF"])
    }

    func testForcedPairTokensRejectsAmbiguousRows() {
        var live = [UInt32](repeating: 0, count: 26)
        live[0] = (1 << 1) | (1 << 2)
        XCTAssertNil(MuleinOstwaldAdapt.forcedPairTokens(from: live))
    }

    func testMenuComponentsMatchesBombeEuler() {
        XCTAssertEqual(
            MuleinOstwaldAdapt.menuComponents(
                edgeCount: 2, loops: 0, endpointA: [0, 0], endpointB: [1, 2]
            ),
            1
        )
        XCTAssertEqual(
            MuleinOstwaldAdapt.menuComponents(
                edgeCount: 2, loops: 0, endpointA: [0, 2], endpointB: [1, 3]
            ),
            2
        )
    }

    func testShellLiveKeyCollapsesPostGapClones() {
        let identity = MuleinOstwaldAdapt.shellLiveKey(
            ukw: "B", greek: "beta", wheelOrder: "IV-III-VIII",
            rings: "AAAA", positions: "AAAA", liveHashHex: "0xabc"
        )
        let clone = MuleinOstwaldAdapt.shellLiveKey(
            ukw: "B", greek: "beta", wheelOrder: "IV-III-VIII",
            rings: "AAAA", positions: "AAAA", liveHashHex: "0xabc"
        )
        XCTAssertEqual(identity, clone)
        XCTAssertNotEqual(
            identity,
            MuleinOstwaldAdapt.shellLiveKey(
                ukw: "B", greek: "beta", wheelOrder: "IV-III-VIII",
                rings: "AAAA", positions: "AAAB", liveHashHex: "0xabc"
            )
        )
    }

    func testBombeCLIRoutesTheAdapterFlag() {
        XCTAssertTrue(HelutBombeCLI.handles(["--mulein-ostwald-adapt", "ledger.jsonl"]))
    }

    func testBombeCLIRoutesTheEscalateFlag() {
        XCTAssertTrue(HelutBombeCLI.handles(["--ostwald-escalate", "quarantine.json"]))
    }

    func testBombeCLIRoutesTheAllSettingsFlag() {
        XCTAssertTrue(HelutBombeCLI.handles(["--ostwald-all-settings", "--ostwald-control", "p1030684"]))
    }

    func testSubsetMaterializeCompilesOnlyRequestedOrdinals() throws {
        let source = try writeTinyP1030680Source(
            crib: "BEFEHLERHALTENREGENBOGEN", offsets: [1]
        )
        let manifest = try MuleinFutureManifestBuilder.build(
            sourcePath: source.path, minimumEdges: 12, delta: 4
        )
        XCTAssertGreaterThanOrEqual(manifest.identityCount, 1)
        XCTAssertGreaterThanOrEqual(manifest.postGapDeltaCount, 1)

        let identityOnly = try MuleinFutureManifestBuilder.materialize(
            manifest, ordinals: [0]
        )
        XCTAssertEqual(Set(identityOnly.keys), [0])
        XCTAssertEqual(identityOnly[0]?.future.menu.crib.isEmpty, false)
        XCTAssertEqual(manifest.entries[0].family, MuleinOstwaldAdapt.identityFamily)

        let postGapOrdinal = manifest.identityCount
        XCTAssertEqual(manifest.entries[postGapOrdinal].family.hasPrefix("post-gap"), true)
        let postGapOnly = try MuleinFutureManifestBuilder.materialize(
            manifest, ordinals: [postGapOrdinal]
        )
        XCTAssertEqual(Set(postGapOnly.keys), [postGapOrdinal])
        XCTAssertNotEqual(
            identityOnly[0]?.future.id.rawValue,
            postGapOnly[postGapOrdinal]?.future.id.rawValue
        )
    }

    func testAdaptSkipOnlyDoesNotCompileFuturesAndWritesReasons() throws {
        let fixture = try TinyManifestFixture.make()
        let rows = [
            fixture.row(
                chunkID: "exact-identity",
                ordinal: 0,
                family: "identity",
                candidate: fixture.dummyCandidate(
                    family: "identity", ordinal: 0, exact: true, dropped: false
                )
            ),
            fixture.row(
                chunkID: "exact-post-gap",
                ordinal: fixture.manifest.identityCount,
                family: fixture.postGapFamily,
                candidate: fixture.dummyCandidate(
                    family: fixture.postGapFamily,
                    ordinal: fixture.manifest.identityCount,
                    exact: true,
                    dropped: false
                )
            ),
            fixture.row(
                chunkID: "post-gap-repair",
                ordinal: fixture.manifest.identityCount,
                family: fixture.postGapFamily,
                candidate: fixture.dummyCandidate(
                    family: fixture.postGapFamily,
                    ordinal: fixture.manifest.identityCount,
                    exact: false,
                    dropped: true
                )
            )
        ]
        let ledger = try writeJSONL(rows, in: fixture.dir, name: "skip-only.jsonl")
        let out = fixture.dir.appendingPathComponent("quarantine.json").path
        let skip = fixture.dir.appendingPathComponent("skips.jsonl").path

        let result = try MuleinOstwaldAdapt.run(
            ledgerPath: ledger, outputPath: out, skipPath: skip
        )
        XCTAssertEqual(result.totalCandidates, 3)
        XCTAssertEqual(result.queuedIdentityRepairs, 0)
        XCTAssertEqual(result.compiledOrdinals, 0)
        XCTAssertEqual(result.emitted, 0)
        XCTAssertEqual(result.skipCounts[.exactIdentityAlreadyScored], 1)
        XCTAssertEqual(result.skipCounts[.exactPostGapAlreadyAdjudicated], 1)
        XCTAssertEqual(result.skipCounts[.postGapDenseOstwaldIllegal], 1)

        let skips = try loadSkipRecords(skip)
        XCTAssertEqual(
            Set(skips.map(\.reason)),
            [
                MuleinOstwaldAdaptSkipReason.exactIdentityAlreadyScored.rawValue,
                MuleinOstwaldAdaptSkipReason.exactPostGapAlreadyAdjudicated.rawValue,
                MuleinOstwaldAdaptSkipReason.postGapDenseOstwaldIllegal.rawValue
            ]
        )
        let decoded = try JSONDecoder().decode(
            OstwaldEscalateManifest.self,
            from: Data(contentsOf: URL(fileURLWithPath: out))
        )
        XCTAssertEqual(decoded.candidates.count, 0)
        XCTAssertEqual(decoded.target, "P1030680")
    }

    func testAdaptFailClosedOnMixedRunIdentities() throws {
        let fixture = try TinyManifestFixture.make()
        let other = MuleinOstwaldAdaptRunIdentity(
            runID: "other-run",
            targetID: fixture.runIdentity.targetID,
            manifestPath: fixture.runIdentity.manifestPath,
            manifestSHA256: fixture.runIdentity.manifestSHA256,
            manifestFingerprint: fixture.runIdentity.manifestFingerprint,
            manifestEntries: fixture.runIdentity.manifestEntries
        )
        let rows = [
            fixture.row(
                chunkID: "a",
                ordinal: 0,
                family: "identity",
                candidate: fixture.dummyCandidate(
                    family: "identity", ordinal: 0, exact: true, dropped: false
                )
            ),
            MuleinOstwaldAdaptRow(
                run: other,
                chunkID: "b",
                ukw: "B",
                greek: "gamma",
                wheelOrder: "IV-III-VIII",
                rings: "AACU",
                futureOrdinal: 0,
                futureID: fixture.manifest.entries[0].receipts[0].id.rawValue,
                futureFamily: "identity",
                candidates: [
                    fixture.dummyCandidate(
                        family: "identity", ordinal: 0, exact: true, dropped: false
                    )
                ]
            )
        ]
        let ledger = try writeJSONL(rows, in: fixture.dir, name: "mixed.jsonl")
        assertAdaptError(containing: "mixes run identities") {
            try MuleinOstwaldAdapt.run(
                ledgerPath: ledger,
                outputPath: fixture.dir.appendingPathComponent("out.json").path,
                skipPath: fixture.dir.appendingPathComponent("skip.jsonl").path
            )
        }
    }

    func testAdaptFailClosedOnInconsistentExactDrop() throws {
        let fixture = try TinyManifestFixture.make()
        let rows = [
            fixture.row(
                chunkID: "bad",
                ordinal: 0,
                family: "identity",
                candidate: fixture.dummyCandidate(
                    family: "identity", ordinal: 0, exact: true, dropped: true
                )
            )
        ]
        let ledger = try writeJSONL(rows, in: fixture.dir, name: "inconsistent.jsonl")
        assertAdaptError(containing: "exact/drop provenance is inconsistent") {
            try MuleinOstwaldAdapt.run(
                ledgerPath: ledger,
                outputPath: fixture.dir.appendingPathComponent("out.json").path,
                skipPath: fixture.dir.appendingPathComponent("skip.jsonl").path
            )
        }
    }

    func testAdaptFailClosedOnMalformedJSONL() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mulein-ostwald-malformed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ledger = dir.appendingPathComponent("bad.jsonl")
        try Data("{not-json\n".utf8).write(to: ledger)
        assertAdaptError(containing: "malformed ledger row") {
            try MuleinOstwaldAdapt.run(
                ledgerPath: ledger.path,
                outputPath: dir.appendingPathComponent("out.json").path,
                skipPath: dir.appendingPathComponent("skip.jsonl").path
            )
        }
    }

    func testAdaptFailClosedOnEmptyLedger() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mulein-ostwald-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ledger = dir.appendingPathComponent("empty.jsonl")
        try Data().write(to: ledger)
        assertAdaptError(containing: "campaign ledger is empty") {
            try MuleinOstwaldAdapt.run(
                ledgerPath: ledger.path,
                outputPath: dir.appendingPathComponent("out.json").path,
                skipPath: dir.appendingPathComponent("skip.jsonl").path
            )
        }
    }

    func testAdaptFailClosedOnManifestSHAMismatch() throws {
        let fixture = try TinyManifestFixture.make()
        let bad = MuleinOstwaldAdaptRunIdentity(
            runID: fixture.runIdentity.runID,
            targetID: fixture.runIdentity.targetID,
            manifestPath: fixture.runIdentity.manifestPath,
            manifestSHA256: String(repeating: "ab", count: 32),
            manifestFingerprint: fixture.runIdentity.manifestFingerprint,
            manifestEntries: fixture.runIdentity.manifestEntries
        )
        let row = MuleinOstwaldAdaptRow(
            run: bad,
            chunkID: "sha",
            ukw: "B",
            greek: "gamma",
            wheelOrder: "IV-III-VIII",
            rings: "AACU",
            futureOrdinal: 0,
            futureID: fixture.manifest.entries[0].receipts[0].id.rawValue,
            futureFamily: "identity",
            candidates: [
                fixture.dummyCandidate(
                    family: "identity", ordinal: 0, exact: true, dropped: false
                )
            ]
        )
        let ledger = try writeJSONL([row], in: fixture.dir, name: "sha.jsonl")
        assertAdaptError(containing: "manifest has changed since the run") {
            try MuleinOstwaldAdapt.run(
                ledgerPath: ledger,
                outputPath: fixture.dir.appendingPathComponent("out.json").path,
                skipPath: fixture.dir.appendingPathComponent("skip.jsonl").path
            )
        }
    }

    func testAdaptFailClosedOnFingerprintMismatch() throws {
        let fixture = try TinyManifestFixture.make()
        let bad = MuleinOstwaldAdaptRunIdentity(
            runID: fixture.runIdentity.runID,
            targetID: fixture.runIdentity.targetID,
            manifestPath: fixture.runIdentity.manifestPath,
            manifestSHA256: fixture.runIdentity.manifestSHA256,
            manifestFingerprint: "fnv1a64-deadbeefdeadbeef",
            manifestEntries: fixture.runIdentity.manifestEntries
        )
        let row = MuleinOstwaldAdaptRow(
            run: bad,
            chunkID: "fp",
            ukw: "B",
            greek: "gamma",
            wheelOrder: "IV-III-VIII",
            rings: "AACU",
            futureOrdinal: 0,
            futureID: fixture.manifest.entries[0].receipts[0].id.rawValue,
            futureFamily: "identity",
            candidates: [
                fixture.dummyCandidate(
                    family: "identity", ordinal: 0, exact: true, dropped: false
                )
            ]
        )
        let ledger = try writeJSONL([row], in: fixture.dir, name: "fp.jsonl")
        assertAdaptError(containing: "fingerprint/entry count disagrees") {
            try MuleinOstwaldAdapt.run(
                ledgerPath: ledger,
                outputPath: fixture.dir.appendingPathComponent("out.json").path,
                skipPath: fixture.dir.appendingPathComponent("skip.jsonl").path
            )
        }
    }

    func testAdaptFailClosedOnFamilyDisagreement() throws {
        let fixture = try TinyManifestFixture.make()
        let row = fixture.row(
            chunkID: "fam",
            ordinal: 0,
            family: "identity",
            candidate: fixture.dummyCandidate(
                family: fixture.postGapFamily, ordinal: 0, exact: false, dropped: true
            )
        )
        let ledger = try writeJSONL([row], in: fixture.dir, name: "fam.jsonl")
        assertAdaptError(containing: "candidate family disagrees") {
            try MuleinOstwaldAdapt.run(
                ledgerPath: ledger,
                outputPath: fixture.dir.appendingPathComponent("out.json").path,
                skipPath: fixture.dir.appendingPathComponent("skip.jsonl").path
            )
        }
    }

    func testAdaptEmitsKnownKeyIdentityRepairAndSkipsDuplicateAndFloor() throws {
        let repair = try KnownKeyIdentityRepairFixture.make()
        XCTAssertEqual(repair.row.greek, "gamma")
        XCTAssertEqual(repair.host.pairCount >= MuleinOstwaldAdapt.defaultMinPairs, true)
        XCTAssertEqual(repair.work.future.menu.components, 1)

        let duplicate = repair.row
        let ledger = try writeJSONL(
            [repair.row, duplicate], in: repair.dir, name: "repair.jsonl"
        )
        let out = repair.dir.appendingPathComponent("quarantine.json").path
        let skip = repair.dir.appendingPathComponent("skips.jsonl").path

        let emitted = try MuleinOstwaldAdapt.run(
            ledgerPath: ledger, outputPath: out, skipPath: skip, minPairs: 4
        )
        XCTAssertEqual(emitted.queuedIdentityRepairs, 2)
        XCTAssertEqual(emitted.compiledOrdinals, 1)
        XCTAssertEqual(emitted.emitted, 1)
        XCTAssertEqual(emitted.skipCounts[.duplicateShellLiveHash], 1)

        let manifest = try JSONDecoder().decode(
            OstwaldEscalateManifest.self,
            from: Data(contentsOf: URL(fileURLWithPath: out))
        )
        XCTAssertEqual(manifest.candidates.count, 1)
        XCTAssertEqual(manifest.candidates[0].greek, "gamma")
        XCTAssertEqual(manifest.candidates[0].ukw, "B")
        XCTAssertEqual(manifest.candidates[0].wheelOrder, "IV-III-VIII")
        XCTAssertEqual(manifest.candidates[0].rings, "AACU")
        XCTAssertEqual(manifest.candidates[0].positions, "VYAA")
        XCTAssertFalse(manifest.candidates[0].steckerPairs.isEmpty)
        XCTAssertEqual(
            OstwaldEscalate.greekLookupName(manifest.candidates[0].greek),
            "C"
        )

        let floor = try MuleinOstwaldAdapt.run(
            ledgerPath: ledger,
            outputPath: repair.dir.appendingPathComponent("floor.json").path,
            skipPath: repair.dir.appendingPathComponent("floor-skips.jsonl").path,
            minPairs: 13
        )
        XCTAssertEqual(floor.emitted, 0)
        XCTAssertEqual(floor.skipCounts[.pairCountBelowFloor], 2)

        let scrambled = MuleinOstwaldAdaptCandidate(
            settingLane: repair.candidate.settingLane,
            positions: repair.candidate.positions,
            futureOrdinal: repair.candidate.futureOrdinal,
            futureID: repair.candidate.futureID,
            family: repair.candidate.family,
            seed: repair.candidate.seed,
            exact: repair.candidate.exact,
            droppedEdgeMaskHex: repair.candidate.droppedEdgeMaskHex,
            droppedEdgeIDs: repair.candidate.droppedEdgeIDs,
            pairCount: repair.candidate.pairCount,
            determinedCount: repair.candidate.determinedCount,
            liveHashHex: "0xdeadbeef"
        )
        let badRow = MuleinOstwaldAdaptRow(
            run: repair.row.run,
            chunkID: "host-mismatch",
            ukw: repair.row.ukw,
            greek: repair.row.greek,
            wheelOrder: repair.row.wheelOrder,
            rings: repair.row.rings,
            futureOrdinal: repair.row.futureOrdinal,
            futureID: repair.row.futureID,
            futureFamily: repair.row.futureFamily,
            candidates: [scrambled]
        )
        let badLedger = try writeJSONL([badRow], in: repair.dir, name: "mismatch.jsonl")
        assertAdaptError(containing: "disagrees with its persisted host state") {
            try MuleinOstwaldAdapt.run(
                ledgerPath: badLedger,
                outputPath: repair.dir.appendingPathComponent("bad-out.json").path,
                skipPath: repair.dir.appendingPathComponent("bad-skip.jsonl").path
            )
        }
    }

    func testAdaptQuarantineDecodesAsEscalateInputAndDoesNotBreakOnGarble() throws {
        XCTAssertTrue(GermanTrigrams.isLoaded)
        let repair = try KnownKeyIdentityRepairFixture.make()
        let ledger = try writeJSONL([repair.row], in: repair.dir, name: "compose.jsonl")
        let out = repair.dir.appendingPathComponent("compose.json").path
        let skip = repair.dir.appendingPathComponent("compose-skips.jsonl").path
        let adapted = try MuleinOstwaldAdapt.run(
            ledgerPath: ledger, outputPath: out, skipPath: skip
        )
        XCTAssertEqual(adapted.emitted, 1)

        let climbed = try OstwaldEscalate.run(
            manifestPath: out,
            scorer: .staged,
            exhaustLetters: 0,
            noiseSamples: 0,
            printProgress: false
        )
        XCTAssertEqual(climbed.candidateCount, 1)
        XCTAssertEqual(climbed.noiseSampleCount, 0)
        XCTAssertEqual(climbed.breakCount, 0)
        // One crib letter was garbled on purpose; crib-exact on a dropped letter is not a break.
        XCTAssertFalse(climbed.ranked[0].cribExact)
        XCTAssertFalse(climbed.ranked[0].clearsBreakBar)
    }

    private func writeTinyP1030680Source(crib: String, offsets: [Int]) throws -> URL {
        try TinyManifestFixture.writeSource(
            ciphertext: U534MessageP1030680.ciphertext,
            crib: crib,
            offsets: offsets
        )
    }

    private func writeJSONL(
        _ rows: [MuleinOstwaldAdaptRow],
        in dir: URL,
        name: String
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = Data()
        for row in rows {
            var line = try encoder.encode(row)
            line.append(0x0a)
            data.append(line)
        }
        let url = dir.appendingPathComponent(name)
        try data.write(to: url)
        return url.path
    }

    private func loadSkipRecords(_ path: String) throws -> [MuleinOstwaldAdaptSkipRecord] {
        let text = try String(contentsOfFile: path, encoding: .utf8)
        let decoder = JSONDecoder()
        return try text.split(separator: "\n", omittingEmptySubsequences: true).map {
            try decoder.decode(MuleinOstwaldAdaptSkipRecord.self, from: Data($0.utf8))
        }
    }

    private func assertAdaptError(
        containing needle: String,
        _ body: () throws -> MuleinOstwaldAdaptResult
    ) {
        XCTAssertThrowsError(try body()) { error in
            let text = String(describing: error)
            XCTAssertTrue(
                text.contains(needle),
                "error '\(text)' did not contain '\(needle)'"
            )
        }
    }
}

final class OstwaldEscalateTests: XCTestCase {

    func testGreekLookupPreservesCampaignBetaGammaStrings() {
        XCTAssertEqual(OstwaldEscalate.greekLookupName("beta"), "B")
        XCTAssertEqual(OstwaldEscalate.greekLookupName("gamma"), "C")
        // Adapter must emit "beta", not "B": a stored "B" is sent to gamma.
        XCTAssertEqual(OstwaldEscalate.greekLookupName("B"), "C")
    }

    func testParseSteckerPairsDropsMalformedTokens() {
        let pairs = OstwaldEscalate.parseSteckerPairs(["CH", "E", "EJ", "AA", "TY"])
        XCTAssertEqual(pairs.map { ($0.0, $0.1) }.count, 3)
        XCTAssertEqual(pairs[0].0, EnigmaAlphabet.index("C"))
        XCTAssertEqual(pairs[0].1, EnigmaAlphabet.index("H"))
    }

    func testKnownKeyEightPlugsClearsCribExactAt72Letters() throws {
        XCTAssertTrue(GermanTrigrams.isLoaded)
        let path = try writeEscalateManifest(
            greek: "gamma",
            positions: "VYAA",
            plugs: Array(ControlMessageP1030684.plugPairs.prefix(8))
        )
        let result = try OstwaldEscalate.run(
            manifestPath: path,
            scorer: .staged,
            exhaustLetters: 0,
            noiseSamples: 0,
            printProgress: false
        )
        XCTAssertEqual(result.candidateCount, 1)
        XCTAssertEqual(result.breakCount, 1)
        let best = try XCTUnwrap(result.ranked.first)
        XCTAssertTrue(best.cribExact)
        XCTAssertTrue(best.clearsBreakBar)
        XCTAssertLessThanOrEqual(best.pairCount, 10)
        XCTAssertTrue(best.plaintext.hasPrefix("VVVUUUVIRSOBENNU"))
    }

    func testGhostPlugsAtWrongSettingDoNotClearCribExact() throws {
        XCTAssertTrue(GermanTrigrams.isLoaded)
        let path = try writeEscalateManifest(
            greek: "gamma",
            positions: "VYAB",
            plugs: Array(ControlMessageP1030684.plugPairs.prefix(8))
        )
        let result = try OstwaldEscalate.run(
            manifestPath: path,
            scorer: .staged,
            exhaustLetters: 0,
            noiseSamples: 0,
            printProgress: false
        )
        XCTAssertEqual(result.breakCount, 0)
        let best = try XCTUnwrap(result.ranked.first)
        XCTAssertFalse(best.cribExact)
        XCTAssertFalse(best.clearsBreakBar)
    }

    func testEmptyCandidatesFailClosed() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ostwald-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ciphertext = String(
            EnigmaAlphabet.string(
                from: Array(EnigmaAlphabet.normalize(ControlMessageP1030684.ciphertext).prefix(72))
            )
        )
        let body: [String: Any] = [
            "target": "P1030684-control",
            "ciphertext": ciphertext,
            "candidates": [Any]()
        ]
        let url = dir.appendingPathComponent("empty.json")
        try JSONSerialization.data(withJSONObject: body).write(to: url)
        XCTAssertThrowsError(
            try OstwaldEscalate.run(
                manifestPath: url.path, noiseSamples: 0, printProgress: false
            )
        ) { error in
            XCTAssertTrue(String(describing: error).contains("no candidates"))
        }
    }

    func testFourPlugBruteAtExhaustSixFailsClosed() throws {
        let path = try writeEscalateManifest(
            greek: "gamma",
            positions: "VYAA",
            plugs: Array(ControlMessageP1030684.plugPairs.prefix(2))
        )
        XCTAssertThrowsError(
            try OstwaldEscalate.run(
                manifestPath: path,
                exhaustLetters: 6,
                noiseSamples: 0,
                brutePlugs: 4
            )
        ) { error in
            let text = String(describing: error)
            XCTAssertTrue(
                text.contains("exhaust ≥ 8") || text.contains("four pairs"),
                "error '\(text)' did not name the exhaust-6 / 4-plug refusal"
            )
        }
    }

    func testKnownKeyEightPlugsClearsOnMetalWhenAvailable() throws {
        XCTAssertTrue(GermanTrigrams.isLoaded)
        let path = try writeEscalateManifest(
            greek: "gamma",
            positions: "VYAA",
            plugs: Array(ControlMessageP1030684.plugPairs.prefix(8))
        )
        let result = try OstwaldEscalate.run(
            manifestPath: path,
            scorer: .staged,
            exhaustLetters: 0,
            noiseSamples: 0,
            printProgress: false,
            useMetal: true
        )
        XCTAssertEqual(result.breakCount, 1)
        let best = try XCTUnwrap(result.ranked.first)
        XCTAssertTrue(best.cribExact)
        XCTAssertTrue(best.plaintext.hasPrefix("VVVUUUVIRSOBENNU"))
    }

    func testKeepZeroUnlocksForcedPlugs() throws {
        XCTAssertTrue(GermanTrigrams.isLoaded)
        let path = try writeEscalateManifest(
            greek: "gamma",
            positions: "VYAA",
            plugs: Array(ControlMessageP1030684.plugPairs.prefix(8))
        )
        let locked = try OstwaldEscalate.run(
            manifestPath: path,
            scorer: .staged,
            exhaustLetters: 0,
            noiseSamples: 0,
            printProgress: false
        )
        let unlocked = try OstwaldEscalate.run(
            manifestPath: path,
            scorer: .staged,
            exhaustLetters: 0,
            keepSeeded: 0,
            noiseSamples: 0,
            printProgress: false
        )
        XCTAssertEqual(locked.breakCount, 1)
        // Unseeded 72-letter climb is the known-negative cell: unlocking eight correct
        // plugs must not silently keep them.
        XCTAssertEqual(unlocked.breakCount, 0)
        XCTAssertNotEqual(locked.ranked[0].plaintext, unlocked.ranked[0].plaintext)
    }

    func testAllSettingsSliceEnumeratesTrueMessageKey() throws {
        let truth = EnigmaM4Key.positions(fromLetters: ControlMessageP1030684.positions)
        let idx = OstwaldAllSettings.index(truth)
        XCTAssertEqual(OstwaldAllSettings.letters(OstwaldAllSettings.positions(index: idx)), "VYAA")
        let control = OstwaldAllSettings.p1030684Control()
        XCTAssertEqual(control.shell.rings, "AACU")
        XCTAssertEqual(control.ciphertext.count, 72)
    }

    private func writeEscalateManifest(
        greek: String,
        positions: String,
        plugs: [String]
    ) throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ostwald-escalate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ciphertext = EnigmaAlphabet.string(
            from: Array(EnigmaAlphabet.normalize(ControlMessageP1030684.ciphertext).prefix(72))
        )
        let crib = String(
            EnigmaAlphabet.string(
                from: Array(EnigmaAlphabet.normalize(ControlMessageP1030684.plaintext).prefix(16))
            )
        )
        let candidate: [String: Any] = [
            "ukw": "B",
            "greek": greek,
            "wheelOrder": "IV-III-VIII",
            "rings": "AACU",
            "positions": positions,
            "steckerPairs": plugs,
            "menuCrib": crib,
            "menuOffset": 0,
            "ic": 0,
            "tailScore": 0,
            "source": "known-key-control"
        ]
        let body: [String: Any] = [
            "target": "P1030684-control",
            "ciphertext": ciphertext,
            "candidates": [candidate]
        ]
        let url = dir.appendingPathComponent("manifest.json")
        try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]).write(to: url)
        return url.path
    }
}

private struct TinyManifestFixture {
    let dir: URL
    let manifest: MuleinFutureManifest
    let runIdentity: MuleinOstwaldAdaptRunIdentity

    var postGapFamily: String { "post-gap-delta\(manifest.delta)" }

    static func make() throws -> TinyManifestFixture {
        let source = try writeSource(
            ciphertext: U534MessageP1030680.ciphertext,
            crib: "BEFEHLERHALTENREGENBOGEN",
            offsets: [1]
        )
        let manifest = try MuleinFutureManifestBuilder.build(
            sourcePath: source.path, minimumEdges: 12, delta: 4
        )
        let manifestURL = source.deletingLastPathComponent()
            .appendingPathComponent("tiny-manifest.json")
        try MuleinFutureManifestBuilder.write(manifest, to: manifestURL.path)
        let digest = sha256(of: manifestURL)
        let identity = MuleinOstwaldAdaptRunIdentity(
            runID: "tiny-test-run",
            targetID: "P1030680",
            manifestPath: manifestURL.path,
            manifestSHA256: digest,
            manifestFingerprint: manifest.inventoryFingerprint,
            manifestEntries: manifest.entries.count
        )
        return TinyManifestFixture(
            dir: source.deletingLastPathComponent(),
            manifest: manifest,
            runIdentity: identity
        )
    }

    static func writeSource(ciphertext: String, crib: String, offsets: [Int]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mulein-ostwald-adapt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("source.json")
        let payload: [String: Any] = [
            "target": "P1030680",
            "ciphertext": ciphertext,
            "cribs": [
                [
                    "text": crib,
                    "messages": 1,
                    "offsets": offsets
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        try data.write(to: url)
        return url
    }

    func dummyCandidate(
        family: String,
        ordinal: Int,
        exact: Bool,
        dropped: Bool
    ) -> MuleinOstwaldAdaptCandidate {
        let futureID = manifest.entries[ordinal].receipts[0].id.rawValue
        return MuleinOstwaldAdaptCandidate(
            settingLane: 0,
            positions: "AAAA",
            futureOrdinal: ordinal,
            futureID: futureID,
            family: family,
            seed: 0,
            exact: exact,
            droppedEdgeMaskHex: dropped ? "0x0000000000000001" : "0x0000000000000000",
            droppedEdgeIDs: dropped
                ? [
                    MuleinEdgeID(
                        sourceID: "test",
                        cribID: "test",
                        cribIndex: 0,
                        transmittedStep: 0,
                        recordedIndex: 0
                    )
                ]
                : [],
            pairCount: exact ? 10 : 6,
            determinedCount: exact ? 20 : 12,
            liveHashHex: "0x00000000"
        )
    }

    func row(
        chunkID: String,
        ordinal: Int,
        family: String,
        candidate: MuleinOstwaldAdaptCandidate
    ) -> MuleinOstwaldAdaptRow {
        MuleinOstwaldAdaptRow(
            run: runIdentity,
            chunkID: chunkID,
            ukw: "B",
            greek: "gamma",
            wheelOrder: "IV-III-VIII",
            rings: "AACU",
            futureOrdinal: ordinal,
            futureID: candidate.futureID,
            futureFamily: family,
            candidates: [candidate]
        )
    }
}

private struct KnownKeyIdentityRepairFixture {
    let dir: URL
    let row: MuleinOstwaldAdaptRow
    let candidate: MuleinOstwaldAdaptCandidate
    let work: MuleinFutureMetalWork
    let host: MuleinBoardResult

    static func make() throws -> KnownKeyIdentityRepairFixture {
        let plaintext = Array(
            EnigmaAlphabet.normalize(ControlMessageP1030684.plaintext).prefix(72)
        )
        let positions = EnigmaM4Key.positions(fromLetters: "VYAA")
        var machine = EnigmaM4Machine(
            key: EnigmaM4Key.potsdam1May1945(positions: positions)
        )
        let clean = machine.processText(plaintext)
        let cribLength = 16
        let crib = EnigmaAlphabet.string(from: Array(plaintext.prefix(cribLength)))
        let bombe = ControlMessageP1030684.bombe(maxPlugs: 10)
        let trueStecker = ControlMessageP1030684.trueStecker
        let lane = positions.0 * 17_576 + positions.1 * 676 + positions.2 * 26 + positions.3
        XCTAssertEqual(
            WelchmanMetalEngine.position(forLane: lane).0, positions.0
        )

        var chosenCT: [Int]?
        for garbleIndex in 0..<cribLength {
            var ct = clean
            var replacement = (ct[garbleIndex] + 1) % 26
            if replacement == plaintext[garbleIndex] {
                replacement = (ct[garbleIndex] + 2) % 26
            }
            ct[garbleIndex] = replacement
            let evidence = MuleinFutureEvidence(
                targetID: "P1030680",
                sourceID: "probe",
                cribID: "garble-\(garbleIndex)",
                crib: crib,
                transmittedOffset: 0,
                ciphertext: ct
            )
            let future = try MuleinFutureLattice.compile(
                evidence: evidence, hypothesis: .exact, minimumEdges: 8
            )
            guard future.menu.components == 1 else { continue }
            let seed = trueStecker[future.menu.central]
            let scramblers = bombe.scramblers(menu: future.menu, start: positions)
            guard let host = MuleinBoard.propagate(
                menu: future.menu,
                scramblers: scramblers,
                seedLetter: future.menu.central,
                seedValue: seed,
                tolerance: 1,
                maxPlugs: 10,
                exactPlugs: 0
            ), !host.exact, host.droppedEdges.count == 1, host.pairCount >= 4 else {
                continue
            }
            chosenCT = ct
            break
        }
        guard let chosenCT else {
            throw NSError(
                domain: "KnownKeyIdentityRepairFixture",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "no t=1 identity repair at VYAA on a 16-letter known-key crib"
                ]
            )
        }

        let source = try TinyManifestFixture.writeSource(
            ciphertext: EnigmaAlphabet.string(from: chosenCT),
            crib: crib,
            offsets: [0]
        )
        let manifest = try MuleinFutureManifestBuilder.build(
            sourcePath: source.path,
            minimumEdges: 8,
            delta: 4,
            maxPlugs: 10,
            exactPlugs: 0,
            tolerance: 1
        )
        let manifestURL = source.deletingLastPathComponent()
            .appendingPathComponent("known-key-manifest.json")
        try MuleinFutureManifestBuilder.write(manifest, to: manifestURL.path)
        let work = try XCTUnwrap(
            MuleinFutureManifestBuilder.materialize(manifest, ordinals: [0])[0]
        )
        XCTAssertEqual(work.future.menu.components, 1)
        let seed = trueStecker[work.future.menu.central]
        let scramblers = bombe.scramblers(menu: work.future.menu, start: positions)
        let host = try XCTUnwrap(
            MuleinBoard.propagate(
                menu: work.future.menu,
                scramblers: scramblers,
                seedLetter: work.future.menu.central,
                seedValue: seed,
                tolerance: work.tolerance,
                maxPlugs: work.maxPlugs,
                exactPlugs: work.exactPlugs
            )
        )
        XCTAssertFalse(host.exact)
        XCTAssertEqual(host.droppedEdges.count, 1)

        var hostMask: UInt64 = 0
        var droppedIDs: [MuleinEdgeID] = []
        for edge in host.droppedEdges {
            hostMask |= UInt64(1) << UInt64(edge)
            droppedIDs.append(work.future.boardEdges[edge].id)
        }
        let candidate = MuleinOstwaldAdaptCandidate(
            settingLane: lane,
            positions: "VYAA",
            futureOrdinal: 0,
            futureID: work.future.id.rawValue,
            family: "identity",
            seed: seed,
            exact: false,
            droppedEdgeMaskHex: String(format: "0x%016llx", hostMask),
            droppedEdgeIDs: droppedIDs,
            pairCount: host.pairCount,
            determinedCount: host.determinedCount,
            liveHashHex: String(format: "0x%08x", host.liveHash)
        )
        let identity = MuleinOstwaldAdaptRunIdentity(
            runID: "known-key-garble",
            targetID: "P1030680",
            manifestPath: manifestURL.path,
            manifestSHA256: sha256(of: manifestURL),
            manifestFingerprint: manifest.inventoryFingerprint,
            manifestEntries: manifest.entries.count
        )
        let row = MuleinOstwaldAdaptRow(
            run: identity,
            chunkID: "known-key-identity-repair",
            ukw: "B",
            greek: "gamma",
            wheelOrder: "IV-III-VIII",
            rings: "AACU",
            futureOrdinal: 0,
            futureID: work.future.id.rawValue,
            futureFamily: "identity",
            candidates: [candidate]
        )
        return KnownKeyIdentityRepairFixture(
            dir: source.deletingLastPathComponent(),
            row: row,
            candidate: candidate,
            work: work,
            host: host
        )
    }
}

private func sha256(of url: URL) -> String {
    let data = (try? Data(contentsOf: url)) ?? Data()
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
