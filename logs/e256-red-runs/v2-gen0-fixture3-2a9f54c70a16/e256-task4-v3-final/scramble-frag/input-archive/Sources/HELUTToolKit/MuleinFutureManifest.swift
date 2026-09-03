import Foundation
import HELUTCore
import HELUTCLI

// MARK: - Finite target Future-Lattice manifest

package struct MuleinFutureManifestEntry: Codable, Sendable {
    package let ordinal: Int
    package let family: String
    package let sourceCribOrdinal: Int
    package let sourceMessages: Int
    package let evidence: MuleinFutureEvidence
    package let hypothesis: MuleinFutureHypothesis
    package let receipts: [MuleinHypothesisReceipt]
    package let geometry: MuleinTranscriptGeometry
    package let boardEdgeIDs: [MuleinEdgeID]
    package let steps: [Int]
    package let endpointA: [Int]
    package let endpointB: [Int]
    package let central: Int
    package let edgeCount: Int
    package let loops: Int
    package let tolerance: Int
    package let maxPlugs: Int
    package let exactPlugs: Int
}

package struct MuleinFutureManifest: Codable, Sendable {
    package let schemaVersion: Int
    package let targetID: String
    package let sourceFixture: String
    package let ciphertext: String
    package let minimumEdges: Int
    package let transmissionGroup: Int
    package let delta: Int
    package let inventoryFingerprint: String
    package let identityCount: Int
    package let postGapDeltaCount: Int
    package let scope: String
    package let entries: [MuleinFutureManifestEntry]
}

package enum MuleinFutureManifestBuilder {
    private struct SourceFile: Decodable {
        struct Crib: Decodable {
            let text: String
            let messages: Int
            let offsets: [Int]
        }
        let target: String
        let ciphertext: String
        let cribs: [Crib]
    }

    package static func build(
        sourcePath: String,
        minimumEdges: Int = 16,
        delta: Int = 4,
        maxPlugs: Int = 10,
        exactPlugs: Int = 10,
        tolerance: Int = 1
    ) throws -> MuleinFutureManifest {
        guard minimumEdges > 0, delta > 0,
              (0...1).contains(tolerance),
              (0...13).contains(maxPlugs), (0...13).contains(exactPlugs),
              maxPlugs == 0 || exactPlugs == 0 || exactPlugs <= maxPlugs else {
            throw MuleinFutureMetalError.invalidBatch("invalid target manifest policy")
        }
        let sourceURL = URL(fileURLWithPath: sourcePath)
        let source = try JSONDecoder().decode(SourceFile.self, from: Data(contentsOf: sourceURL))
        guard source.target == "P1030680" else {
            throw MuleinFutureMetalError.invalidBatch(
                "target manifest source is \(source.target), expected P1030680"
            )
        }
        let ciphertext = EnigmaAlphabet.normalize(source.ciphertext)
        guard !ciphertext.isEmpty,
              EnigmaAlphabet.string(from: ciphertext) == source.ciphertext else {
            throw MuleinFutureMetalError.invalidBatch(
                "target manifest ciphertext is empty or not normalized A...Z"
            )
        }

        let sourceID = sourcePath
        var entries: [MuleinFutureManifestEntry] = []
        var receiptIDs = Set<MuleinHypothesisID>()

        func sameGeometry(_ future: MuleinFuture, _ menu: BombeMenu) -> Bool {
            future.menu.steps == menu.steps
                && future.menu.ends.map(\.0) == menu.ends.map(\.0)
                && future.menu.ends.map(\.1) == menu.ends.map(\.1)
        }

        func append(
            family: String,
            sourceCribOrdinal: Int,
            sourceMessages: Int,
            evidence: MuleinFutureEvidence,
            hypothesis: MuleinFutureHypothesis,
            expectedMenu: BombeMenu
        ) throws {
            let future = try MuleinFutureLattice.compile(
                evidence: evidence,
                hypothesis: hypothesis,
                minimumEdges: minimumEdges
            )
            guard sameGeometry(future, expectedMenu) else {
                throw MuleinFutureMetalError.commandFailed(
                    "Future-Lattice geometry drifted from \(family) splice/menu builder"
                )
            }
            guard future.receipts.allSatisfy({ receiptIDs.insert($0.id).inserted }) else {
                throw MuleinFutureMetalError.commandFailed(
                    "target manifest generated a duplicate hypothesis receipt ID"
                )
            }
            entries.append(MuleinFutureManifestEntry(
                ordinal: entries.count,
                family: family,
                sourceCribOrdinal: sourceCribOrdinal,
                sourceMessages: sourceMessages,
                evidence: evidence,
                hypothesis: hypothesis,
                receipts: future.receipts,
                geometry: future.geometry,
                boardEdgeIDs: future.boardEdges.map(\.id),
                steps: future.executionKey.steps,
                endpointA: future.executionKey.endpointA,
                endpointB: future.executionKey.endpointB,
                central: future.menu.central,
                edgeCount: future.menu.edgeCount,
                loops: future.menu.loops,
                tolerance: tolerance,
                maxPlugs: maxPlugs,
                exactPlugs: exactPlugs
            ))
        }

        // Identity family: exactly the placements pinned by the strongest-menu fixture.
        for (cribOrdinal, crib) in source.cribs.enumerated() {
            for offset in crib.offsets.sorted() {
                guard let menu = BombeMenuBuilder.menu(
                    crib: crib.text, offset: offset, ciphertext: ciphertext
                ), menu.edgeCount >= minimumEdges else {
                    throw MuleinFutureMetalError.invalidBatch(
                        "identity source crib \(cribOrdinal)@\(offset) is illegal or too short"
                    )
                }
                let evidence = MuleinFutureEvidence(
                    targetID: source.target,
                    sourceID: sourceID,
                    cribID: "strongest-\(cribOrdinal)-identity-T\(offset)",
                    crib: crib.text,
                    transmittedOffset: offset,
                    ciphertext: ciphertext
                )
                try append(
                    family: "identity",
                    sourceCribOrdinal: cribOrdinal,
                    sourceMessages: crib.messages,
                    evidence: evidence,
                    hypothesis: .exact,
                    expectedMenu: menu
                )
            }
        }
        let identityCount = entries.count

        // Post-gap δ family: one representative for each execution-distinct menu whose crib is
        // wholly after a missing group. `splice=0` is an equivalence representative only; the
        // manifest does not claim where (or whether) a physical gap occurred.
        var seenTexts = Set<String>()
        for (cribOrdinal, crib) in source.cribs.enumerated()
        where seenTexts.insert(crib.text).inserted {
            let family = SpliceMenuBuilder.indelMenus(
                crib: crib.text,
                ciphertext: ciphertext,
                deltas: [delta],
                groupSize: SpliceMenuBuilder.transmissionGroup,
                minimumEdges: minimumEdges
            ).filter { !$0.straddlesGap && $0.delta == delta }
                .sorted {
                    let left = $0.menu.steps.map(String.init).joined(separator: ",")
                        + "|" + $0.menu.ends.map { "\($0.0)-\($0.1)" }.joined(separator: ",")
                    let right = $1.menu.steps.map(String.init).joined(separator: ",")
                        + "|" + $1.menu.ends.map { "\($0.0)-\($0.1)" }.joined(separator: ",")
                    return left < right
                }

            for spliced in family {
                guard spliced.splice == 0, spliced.transmittedOffset >= delta else {
                    throw MuleinFutureMetalError.commandFailed(
                        "post-gap δ\(delta) builder emitted a non-equivalence representative"
                    )
                }
                let evidence = MuleinFutureEvidence(
                    targetID: source.target,
                    sourceID: sourceID,
                    cribID: "strongest-\(cribOrdinal)-postgap-delta\(delta)-T\(spliced.transmittedOffset)",
                    crib: crib.text,
                    transmittedOffset: spliced.transmittedOffset,
                    ciphertext: ciphertext
                )
                let hypothesis = MuleinFutureHypothesis(
                    label: "post-gap-delta\(delta)-equivalence",
                    edits: [.missingFromRecording(
                        transmitted: MuleinSpan(start: 0, length: delta),
                        recordedBoundary: 0
                    )]
                )
                try append(
                    family: "post-gap-delta\(delta)",
                    sourceCribOrdinal: cribOrdinal,
                    sourceMessages: crib.messages,
                    evidence: evidence,
                    hypothesis: hypothesis,
                    expectedMenu: spliced.menu
                )
            }
        }

        let postGapCount = entries.count - identityCount
        guard identityCount > 0, postGapCount > 0 else {
            throw MuleinFutureMetalError.invalidBatch(
                "target manifest did not generate both identity and post-gap families"
            )
        }
        let fingerprint = inventoryFingerprint(for: entries)

        return MuleinFutureManifest(
            schemaVersion: 1,
            targetID: source.target,
            sourceFixture: sourcePath,
            ciphertext: source.ciphertext,
            minimumEdges: minimumEdges,
            transmissionGroup: SpliceMenuBuilder.transmissionGroup,
            delta: delta,
            inventoryFingerprint: fingerprint,
            identityCount: identityCount,
            postGapDeltaCount: postGapCount,
            scope: "Finite identity + post-gap delta-\(delta) hypothesis inventory; no settings evaluated and no decrypt implied.",
            entries: entries
        )
    }

    package static func load(path: String) throws -> MuleinFutureManifest {
        try load(data: Data(contentsOf: URL(fileURLWithPath: path)))
    }

    package static func load(data: Data) throws -> MuleinFutureManifest {
        let manifest = try JSONDecoder().decode(MuleinFutureManifest.self, from: data)
        let ciphertext = EnigmaAlphabet.normalize(manifest.ciphertext)
        guard manifest.schemaVersion == 1,
              manifest.targetID == "P1030680",
              !manifest.sourceFixture.isEmpty,
              !ciphertext.isEmpty,
              EnigmaAlphabet.string(from: ciphertext) == manifest.ciphertext,
              manifest.minimumEdges > 0,
              manifest.transmissionGroup == SpliceMenuBuilder.transmissionGroup,
              manifest.delta > 0,
              manifest.identityCount > 0,
              manifest.postGapDeltaCount > 0,
              manifest.entries.count == manifest.identityCount + manifest.postGapDeltaCount,
              manifest.entries.indices.allSatisfy({ manifest.entries[$0].ordinal == $0 }) else {
            throw MuleinFutureMetalError.invalidBatch("target manifest header/counts are invalid")
        }

        let expectedPostGapFamily = "post-gap-delta\(manifest.delta)"
        let expectedPostGapLabel = "post-gap-delta\(manifest.delta)-equivalence"
        var receiptIDs = Set<MuleinHypothesisID>()
        var policy: (tolerance: Int, maxPlugs: Int, exactPlugs: Int)?

        for entry in manifest.entries {
            guard entry.sourceCribOrdinal >= 0,
                  entry.sourceMessages >= 0,
                  entry.evidence.targetID == manifest.targetID,
                  entry.evidence.sourceID == manifest.sourceFixture,
                  entry.evidence.ciphertext == ciphertext,
                  entry.edgeCount >= manifest.minimumEdges,
                  entry.boardEdgeIDs.count == entry.edgeCount,
                  entry.steps.count == entry.edgeCount,
                  entry.endpointA.count == entry.edgeCount,
                  entry.endpointB.count == entry.edgeCount,
                  (0..<26).contains(entry.central),
                  entry.loops >= 0,
                  (0...1).contains(entry.tolerance),
                  (0...13).contains(entry.maxPlugs),
                  (0...13).contains(entry.exactPlugs),
                  entry.maxPlugs == 0 || entry.exactPlugs == 0
                    || entry.exactPlugs <= entry.maxPlugs,
                  !entry.receipts.isEmpty else {
                throw MuleinFutureMetalError.invalidBatch(
                    "target manifest entry \(entry.ordinal) has invalid evidence, geometry, or policy"
                )
            }

            let entryPolicy = (
                tolerance: entry.tolerance,
                maxPlugs: entry.maxPlugs,
                exactPlugs: entry.exactPlugs
            )
            if let policy {
                guard policy == entryPolicy else {
                    throw MuleinFutureMetalError.invalidBatch(
                        "target manifest entry \(entry.ordinal) changes the campaign policy"
                    )
                }
            } else {
                policy = entryPolicy
            }

            if entry.ordinal < manifest.identityCount {
                guard entry.family == "identity", entry.hypothesis == .exact else {
                    throw MuleinFutureMetalError.invalidBatch(
                        "target manifest identity prefix has invalid hypothesis semantics"
                    )
                }
            } else {
                guard entry.family == expectedPostGapFamily,
                      entry.evidence.transmittedOffset >= manifest.delta,
                      entry.hypothesis.label == expectedPostGapLabel,
                      entry.hypothesis.edits.count == 1,
                      case let .missingFromRecording(span, boundary) = entry.hypothesis.edits[0],
                      span == MuleinSpan(start: 0, length: manifest.delta),
                      boundary == 0 else {
                    throw MuleinFutureMetalError.invalidBatch(
                        "target manifest post-gap suffix has invalid hypothesis semantics"
                    )
                }
            }

            for receipt in entry.receipts {
                guard receipt.targetID == entry.evidence.targetID,
                      receipt.sourceID == entry.evidence.sourceID,
                      receipt.cribID == entry.evidence.cribID,
                      receipt.label == entry.hypothesis.label,
                      receipt.edits == entry.hypothesis.edits,
                      receiptIDs.insert(receipt.id).inserted else {
                    throw MuleinFutureMetalError.invalidBatch(
                        "target manifest entry \(entry.ordinal) has invalid or duplicate receipts"
                    )
                }
            }
        }

        guard manifest.inventoryFingerprint == inventoryFingerprint(for: manifest.entries) else {
            throw MuleinFutureMetalError.invalidBatch(
                "target manifest inventory fingerprint does not match its entries"
            )
        }
        return manifest
    }

    /// Recompile every evidence path and prove the serialized geometry/provenance before use.
    package static func materialize(
        _ manifest: MuleinFutureManifest
    ) throws -> [MuleinFutureMetalWork] {
        try manifest.entries.map { entry in
            let future = try MuleinFutureLattice.compile(
                evidence: entry.evidence,
                hypothesis: entry.hypothesis,
                minimumEdges: manifest.minimumEdges
            )
            guard future.receipts == entry.receipts,
                  future.geometry == entry.geometry,
                  future.boardEdges.map(\.id) == entry.boardEdgeIDs,
                  future.executionKey.steps == entry.steps,
                  future.executionKey.endpointA == entry.endpointA,
                  future.executionKey.endpointB == entry.endpointB,
                  future.menu.central == entry.central,
                  future.menu.edgeCount == entry.edgeCount,
                  future.menu.loops == entry.loops else {
                throw MuleinFutureMetalError.commandFailed(
                    "manifest entry \(entry.ordinal) failed provenance/geometry replay"
                )
            }
            return MuleinFutureMetalWork(
                future: future,
                tolerance: entry.tolerance,
                maxPlugs: entry.maxPlugs,
                exactPlugs: entry.exactPlugs
            )
        }
    }

    package static func write(_ manifest: MuleinFutureManifest, to path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(manifest)
        data.append(0x0A)
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    private static func inventoryFingerprint(
        for entries: [MuleinFutureManifestEntry]
    ) -> String {
        let canonical = entries.map { entry in
            let ids = entry.receipts.map { $0.id.rawValue }.joined(separator: ",")
            let steps = entry.steps.map(String.init).joined(separator: ",")
            let ends = zip(entry.endpointA, entry.endpointB)
                .map { "\($0)-\($1)" }.joined(separator: ",")
            return "\(entry.ordinal)|\(entry.family)|\(ids)|\(steps)|\(ends)"
        }.joined(separator: "\n")
        return stableFingerprint(canonical)
    }

    private static func stableFingerprint(_ text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return String(format: "fnv1a64-%016llx", hash)
    }
}

func runMuleinFutureManifestEmit() {
    let source = stringFlag("--mulein-future-manifest-source")
        ?? "Fixtures/p1030680_maxupper_strongest_menus.json"
    let deltaFlag = "--mulein-future-manifest-delta"
    do {
        let delta: Int
        if CommandLine.arguments.contains(deltaFlag) {
            guard let raw = stringFlag(deltaFlag), let parsed = Int(raw), parsed > 0 else {
                throw MuleinFutureMetalError.invalidBatch(
                    "\(deltaFlag) requires a positive integer"
                )
            }
            delta = parsed
        } else {
            delta = 4
        }
        let output = stringFlag("--mulein-future-manifest-out")
            ?? "Fixtures/p1030680_mulein_identity_postgap_delta\(delta).json"
        let manifest = try MuleinFutureManifestBuilder.build(
            sourcePath: source, delta: delta
        )
        let work = try MuleinFutureManifestBuilder.materialize(manifest)
        let transmittedLength = EnigmaAlphabet.normalize(manifest.ciphertext).count
            + manifest.delta
        guard transmittedLength <= 80 else {
            throw MuleinFutureMetalError.invalidBatch(
                "delta \(manifest.delta) requires \(transmittedLength) transmitted steps; "
                    + "the Future Bank envelope is 80"
            )
        }
        _ = try validateMuleinFutureWork(work)
        try MuleinFutureManifestBuilder.write(manifest, to: output)
        print("MULEIN FUTURE MANIFEST emitted: \(output)")
        print("  source       : \(source)")
        print("  target       : \(manifest.targetID)")
        print("  transmitted  : \(transmittedLength)")
        print("  identity     : \(manifest.identityCount)")
        print("  post-gap δ\(manifest.delta) : \(manifest.postGapDeltaCount)")
        print("  total        : \(manifest.entries.count)")
        print("  fingerprint  : \(manifest.inventoryFingerprint)")
        print("  scope        : \(manifest.scope)")
    } catch {
        fputs("Mulein manifest emit failed: \(error)\n", stderr)
        exit(1)
    }
}
