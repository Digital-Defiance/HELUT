import Foundation
import Darwin
import HELUTCore
import HELUTCLI

// MARK: - Durable P1030680 Verilog → TensorLUT campaign

private let p1030680MuleinCampaignProtocolVersion = 3
private let p1030680MuleinChunkSchemaVersion = 3
private let p1030680MuleinRunScope = "Bounded cleartext Float TensorLUT campaign; complete receipts and host-replayed positives; not FHE and no implied decrypt."
private let p1030680MuleinChunkScope = "Complete checked TensorLUT receipts; positives host-replayed; no implied decrypt."

private struct P1030680MuleinShell {
    let index: Int
    let ukwName: String
    let greekName: String
    let greek: EnigmaRotorSpec
    let left: EnigmaRotorSpec
    let middle: EnigmaRotorSpec
    let right: EnigmaRotorSpec
    let reflector: [Int]
    let rings: (Int, Int, Int, Int)

    var wheelOrder: String { "\(left.name)-\(middle.name)-\(right.name)" }
    var ringString: String {
        EnigmaAlphabet.string(from: [rings.0, rings.1, rings.2, rings.3])
    }
    var identity: String {
        "\(index):\(ukwName)/\(greekName)/\(wheelOrder)/\(ringString)"
    }
    var bombe: WelchmanBombe {
        WelchmanBombe(
            greek: greek,
            left: left,
            middle: middle,
            right: right,
            reflector: reflector,
            rings: rings,
            maxPlugs: 10
        )
    }
}

private struct P1030680MuleinRunIdentity: Codable, Equatable {
    let schemaVersion: Int
    let campaignProtocolVersion: Int
    let runID: String
    let targetID: String
    let manifestPath: String
    let manifestSHA256: String
    let manifestFingerprint: String
    let manifestEntries: Int
    let netlistPath: String
    let netlistSHA256: String
    let netlistBytes: Int
    let bankLanes: Int
    let lutCount: Int
    let dffCount: Int
    let totalWires: Int
    let levelCount: Int
    let deviceName: String
    let subspace: String
    let selectedShells: [String]
    let settingFrom: Int
    let settingCount: Int
    let futureFrom: Int
    let futureCount: Int
    let chunkSettings: Int
    let tensorBatch: Int
    let tickLimit: Int
    let scope: String
}

private struct P1030680MuleinRunIdentityPayload: Codable {
    let schemaVersion: Int
    let campaignProtocolVersion: Int
    let targetID: String
    let manifestPath: String
    let manifestSHA256: String
    let manifestFingerprint: String
    let manifestEntries: Int
    let netlistPath: String
    let netlistSHA256: String
    let netlistBytes: Int
    let bankLanes: Int
    let lutCount: Int
    let dffCount: Int
    let totalWires: Int
    let levelCount: Int
    let deviceName: String
    let subspace: String
    let selectedShells: [String]
    let settingFrom: Int
    let settingCount: Int
    let futureFrom: Int
    let futureCount: Int
    let chunkSettings: Int
    let tensorBatch: Int
    let tickLimit: Int
    let scope: String
}

private struct P1030680MuleinReceiptRecord: Codable, Equatable {
    let settingLane: Int
    let seed: Int
    let tag: UInt32
    let hit: Bool
    let exact: Bool
    let droppedEdgeMaskHex: String
    let erasedEdge: Int
    let pairCount: Int
    let determinedCount: Int
    let liveHashHex: String
    let cycleCount: UInt32
    let closureCount: UInt32
    let dropTrialCount: UInt32
}

private struct P1030680MuleinCandidateRecord: Codable, Equatable {
    let tag: UInt32
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
    let hostReplayVerified: Bool
    let breakEligibility: String
    let scoringStatus: String
    let cribExact: Bool?
    let indexOfCoincidence: Double?
    let tailScore: Double?
    let effectiveTailScore: Double?
    let plaintext: String?
    let steckerPairs: String?
    let breakGatePassed: Bool
}

private struct P1030680MuleinChunkRecord: Codable {
    let schemaVersion: Int
    let kind: String
    let run: P1030680MuleinRunIdentity
    let chunkID: String
    let completedAt: String
    let shellIndex: Int
    let ukw: String
    let greek: String
    let wheelOrder: String
    let rings: String
    let futureOrdinal: Int
    let futureID: String
    let futureFamily: String
    let settingFrom: Int
    let settingCount: Int
    let attemptedReceipts: Int
    let receipts: [P1030680MuleinReceiptRecord]
    let completeReceiptDigest: String
    let graphBatches: Int
    let submittedTicks: [Int]
    let tensorWallSeconds: Double
    let positiveCount: Int
    let candidates: [P1030680MuleinCandidateRecord]
    let breakGatePassed: Bool
    let scope: String
}

private struct P1030680MuleinExpectedChunk {
    let ordinal: Int
    let chunkID: String
    let shell: P1030680MuleinShell
    let futureOrdinal: Int
    let entry: MuleinFutureManifestEntry
    let work: MuleinFutureMetalWork
    let settingFrom: Int
    let settingCount: Int
    let attemptedReceipts: Int
    let graphBatches: Int
}

private final class P1030680MuleinJSONLLedger {
    let completedChunkIDs: Set<String>
    let priorRecords: [P1030680MuleinChunkRecord]
    let priorPositiveCount: Int
    let priorBreakGatePassed: Bool

    private let identity: P1030680MuleinRunIdentity
    private let expectedPlan: [P1030680MuleinExpectedChunk]
    private let ciphertext: [Int]
    private let encoder: JSONEncoder
    private let handle: FileHandle
    private var mutableCompleted: Set<String>
    private var nextPlanIndex: Int
    private var mutableBreakGatePassed: Bool

    init(
        path: String,
        identity: P1030680MuleinRunIdentity,
        expectedPlan: [P1030680MuleinExpectedChunk],
        ciphertext: [Int]
    ) throws {
        guard identity.schemaVersion == p1030680MuleinCampaignProtocolVersion,
              identity.campaignProtocolVersion == p1030680MuleinCampaignProtocolVersion,
              !expectedPlan.isEmpty,
              Set(expectedPlan.map(\.chunkID)).count == expectedPlan.count else {
            throw MuleinFutureMetalError.commandFailed(
                "campaign identity or expected chunk plan is invalid"
            )
        }
        self.identity = identity
        self.expectedPlan = expectedPlan
        self.ciphertext = ciphertext
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let descriptor = path.withCString {
            Darwin.open($0, O_RDWR | O_CREAT, mode_t(0o644))
        }
        guard descriptor >= 0 else {
            let openError = errno
            throw MuleinFutureMetalError.commandFailed(
                "could not atomically open campaign ledger at \(path): "
                    + String(cString: strerror(openError))
            )
        }
        let lockedHandle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        guard Darwin.lockf(lockedHandle.fileDescriptor, F_TLOCK, 0) == 0 else {
            let lockError = errno
            try? lockedHandle.close()
            throw MuleinFutureMetalError.commandFailed(
                "campaign ledger is already owned by another writer: "
                    + String(cString: strerror(lockError))
            )
        }
        var transferredLockedHandle = false
        defer {
            if !transferredLockedHandle {
                _ = Darwin.lockf(lockedHandle.fileDescriptor, F_ULOCK, 0)
                try? lockedHandle.close()
            }
        }

        let decoder = JSONDecoder()
        try lockedHandle.seek(toOffset: 0)
        var data = try lockedHandle.readToEnd() ?? Data()
        var segments = data.split(separator: 0x0a, omittingEmptySubsequences: false)
        let endedWithNewline = data.last == 0x0a
        if endedWithNewline, segments.last?.isEmpty == true { segments.removeLast() }

        var rows: [P1030680MuleinChunkRecord] = []
        var decodedTail: P1030680MuleinChunkRecord?
        var validTailWithoutNewline = false
        if !endedWithNewline, let tail = segments.popLast() {
            if tail.isEmpty {
                validTailWithoutNewline = true
            } else if let row = try? decoder.decode(
                P1030680MuleinChunkRecord.self, from: Data(tail)
            ) {
                decodedTail = row
                validTailWithoutNewline = true
            } else {
                let truncateOffset = UInt64(data.count - tail.count)
                try lockedHandle.truncate(atOffset: truncateOffset)
                try lockedHandle.synchronize()
                data = data.prefix(Int(truncateOffset))
                print("ledger recovery    : discarded torn final JSONL record")
            }
        }

        for (lineIndex, segment) in segments.enumerated() {
            guard !segment.isEmpty else {
                throw MuleinFutureMetalError.commandFailed(
                    "campaign ledger has an empty interior line at \(lineIndex + 1)"
                )
            }
            do {
                rows.append(try decoder.decode(
                    P1030680MuleinChunkRecord.self, from: Data(segment)
                ))
            } catch {
                throw MuleinFutureMetalError.commandFailed(
                    "campaign ledger has malformed interior line \(lineIndex + 1): \(error)"
                )
            }
        }
        if let decodedTail { rows.append(decodedTail) }

        guard rows.count <= expectedPlan.count else {
            throw MuleinFutureMetalError.commandFailed(
                "campaign ledger is longer than the deterministic chunk plan"
            )
        }
        var completed = Set<String>()
        var sawBreakGate = false
        var positiveCount = 0
        for (rowIndex, row) in rows.enumerated() {
            guard !sawBreakGate else {
                throw MuleinFutureMetalError.commandFailed(
                    "campaign ledger contains a record after a BREAK-gate row"
                )
            }
            try p1030680ValidateChunkRecord(
                row,
                expected: expectedPlan[rowIndex],
                identity: identity,
                ciphertext: ciphertext
            )
            guard completed.insert(row.chunkID).inserted else {
                throw MuleinFutureMetalError.commandFailed(
                    "campaign ledger contains duplicate chunk \(row.chunkID)"
                )
            }
            positiveCount += row.positiveCount
            sawBreakGate = row.breakGatePassed
        }

        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys]
        self.handle = lockedHandle
        try self.handle.seekToEnd()
        if validTailWithoutNewline && !data.isEmpty {
            try self.handle.write(contentsOf: Data([0x0a]))
            try self.handle.synchronize()
        }
        self.priorRecords = rows
        self.completedChunkIDs = completed
        self.priorPositiveCount = positiveCount
        self.priorBreakGatePassed = sawBreakGate
        self.mutableCompleted = completed
        self.nextPlanIndex = rows.count
        self.mutableBreakGatePassed = sawBreakGate
        transferredLockedHandle = true
    }

    deinit {
        _ = Darwin.lockf(handle.fileDescriptor, F_ULOCK, 0)
        try? handle.close()
    }

    func append(_ record: P1030680MuleinChunkRecord) throws {
        guard !mutableBreakGatePassed else {
            throw MuleinFutureMetalError.commandFailed(
                "refusing to append a campaign chunk after a BREAK-gate row"
            )
        }
        guard nextPlanIndex < expectedPlan.count else {
            throw MuleinFutureMetalError.commandFailed(
                "refusing to append beyond the deterministic campaign plan"
            )
        }
        try p1030680ValidateChunkRecord(
            record,
            expected: expectedPlan[nextPlanIndex],
            identity: identity,
            ciphertext: ciphertext
        )
        guard mutableCompleted.insert(record.chunkID).inserted else {
            throw MuleinFutureMetalError.commandFailed(
                "refusing to append a duplicate campaign chunk"
            )
        }
        var data = try encoder.encode(record)
        data.append(0x0a)
        try handle.write(contentsOf: data)
        try handle.synchronize()
        nextPlanIndex += 1
        mutableBreakGatePassed = record.breakGatePassed
    }
}

private struct P1030680MuleinDigest {
    private var hash: UInt64 = 0xcbf2_9ce4_8422_2325

    mutating func mix(_ raw: UInt64) {
        var value = raw
        for _ in 0..<8 {
            hash ^= value & 0xff
            hash &*= 0x0000_0100_0000_01b3
            value >>= 8
        }
    }

    mutating func mix(_ receipt: MuleinFutureTensorLUTEvaluatedReceipt) {
        mix(UInt64(receipt.settingLane))
        mix(UInt64(receipt.job.seed))
        mix(UInt64(receipt.receipt.tag))
        mix(receipt.receipt.valid ? 1 : 0)
        mix(receipt.receipt.configError ? 1 : 0)
        mix(receipt.receipt.hit ? 1 : 0)
        mix(receipt.receipt.exact ? 1 : 0)
        mix(receipt.receipt.droppedEdgeMask)
        mix(UInt64(receipt.receipt.erasedEdge))
        mix(UInt64(receipt.receipt.pairCount))
        mix(UInt64(receipt.receipt.determinedCount))
        mix(UInt64(receipt.receipt.liveHash))
        mix(UInt64(receipt.receipt.cycleCount))
        mix(UInt64(receipt.receipt.closureCount))
        mix(UInt64(receipt.receipt.dropTrialCount))
    }

    var description: String { String(format: "fnv1a64-%016llx", hash) }
}

private func p1030680CampaignInt(
    _ name: String,
    default defaultValue: Int,
    minimum: Int
) throws -> Int {
    guard CommandLine.arguments.contains(name) else { return defaultValue }
    guard let raw = stringFlag(name), let value = Int(raw), value >= minimum else {
        throw MuleinFutureMetalError.invalidBatch(
            "\(name) requires an integer ≥ \(minimum)"
        )
    }
    return value
}

private func p1030680CampaignSubspace(_ name: String) throws -> M4ThetisAttack.Subspace {
    switch name.lowercased() {
    case "potsdam", "potsdam-neighbourhood": return M4ThetisAttack.potsdamNeighbourhood()
    case "two-notch", "naval-two-notch", "naval-two-notch-right":
        return M4ThetisAttack.navalTwoNotchPrior()
    case "rings-right", "right-ring": return M4ThetisAttack.rightRingSweep()
    case "full-potsdam-rings", "potsdam-rings": return M4ThetisAttack.fullWithPotsdamRings()
    case "full", "all": return M4ThetisAttack.fullSpace()
    default:
        throw MuleinFutureMetalError.invalidBatch(
            "unknown subspace \(name); use potsdam-neighbourhood, naval-two-notch-right, "
                + "rings-right, full-potsdam-rings, or full"
        )
    }
}

private func p1030680CampaignRings(
    override: String?, subspace: M4ThetisAttack.Subspace
) throws -> [(Int, Int, Int, Int)] {
    guard let override else { return subspace.ringVariants }
    var rings: [(Int, Int, Int, Int)] = []
    var seen = Set<String>()
    for token in override.split(separator: ",") {
        let text = token.trimmingCharacters(in: .whitespaces).uppercased()
        let normalized = EnigmaAlphabet.normalize(text)
        guard normalized.count == 4,
              EnigmaAlphabet.string(from: normalized) == text else {
            throw MuleinFutureMetalError.invalidBatch(
                "--rings entries must be exactly four A...Z letters"
            )
        }
        if seen.insert(text).inserted {
            rings.append((normalized[0], normalized[1], normalized[2], normalized[3]))
        }
    }
    guard !rings.isEmpty else {
        throw MuleinFutureMetalError.invalidBatch("--rings did not contain a ring setting")
    }
    return rings
}

private func p1030680CampaignShells(
    subspace: M4ThetisAttack.Subspace,
    rings: [(Int, Int, Int, Int)]
) -> [P1030680MuleinShell] {
    let ukws: [(String, [Int])] = [
        ("B", EnigmaM4Warehouse.thinB), ("C", EnigmaM4Warehouse.thinC)
    ]
    let greeks: [(String, EnigmaRotorSpec)] = [
        ("beta", EnigmaM4Warehouse.beta), ("gamma", EnigmaM4Warehouse.gamma)
    ]
    var shells: [P1030680MuleinShell] = []
    for (ukwName, reflector) in ukws {
        for (greekName, greek) in greeks {
            for ring in rings {
                for order in subspace.wheelOrders {
                    shells.append(P1030680MuleinShell(
                        index: shells.count,
                        ukwName: ukwName,
                        greekName: greekName,
                        greek: greek,
                        left: order.0,
                        middle: order.1,
                        right: order.2,
                        reflector: reflector,
                        rings: ring
                    ))
                }
            }
        }
    }
    return shells
}

private func p1030680SteckerPairs(_ table: [Int]) -> String {
    var seen = Set<Int>()
    var pairs: [String] = []
    for letter in 0..<26 where table[letter] != letter && !seen.contains(letter) {
        let mate = table[letter]
        seen.insert(letter)
        seen.insert(mate)
        pairs.append("\(EnigmaAlphabet.character(letter))\(EnigmaAlphabet.character(mate))")
    }
    return pairs.isEmpty ? "(none)" : pairs.sorted().joined(separator: " ")
}

private func p1030680ReplayCandidate(
    evaluated: MuleinFutureTensorLUTEvaluatedReceipt,
    futureOrdinal: Int,
    entry: MuleinFutureManifestEntry,
    work: MuleinFutureMetalWork,
    shell: P1030680MuleinShell,
    ciphertext: [Int]
) throws -> P1030680MuleinCandidateRecord {
    let receipt = evaluated.receipt
    let positions = WelchmanMetalEngine.position(forLane: evaluated.settingLane)
    let rows = shell.bombe.scramblers(menu: work.future.menu, start: positions)
    guard let host = MuleinBoard.propagate(
        menu: work.future.menu,
        scramblers: rows,
        seedLetter: work.future.menu.central,
        seedValue: evaluated.job.seed,
        tolerance: work.tolerance,
        maxPlugs: work.maxPlugs,
        exactPlugs: work.exactPlugs
    ) else {
        throw MuleinFutureMetalError.commandFailed(
            "TensorLUT positive failed independent host replay"
        )
    }

    var hostMask: UInt64 = 0
    var droppedIDs: [MuleinEdgeID] = []
    for edge in host.droppedEdges {
        guard work.future.boardEdges.indices.contains(edge) else {
            throw MuleinFutureMetalError.commandFailed(
                "host replay emitted out-of-range repair provenance"
            )
        }
        hostMask |= UInt64(1) << UInt64(edge)
        droppedIDs.append(work.future.boardEdges[edge].id)
    }
    guard receipt.hit,
          receipt.droppedEdgeMask == hostMask,
          receipt.exact == host.exact,
          receipt.pairCount == host.pairCount,
          receipt.determinedCount == host.determinedCount,
          receipt.liveHash == host.liveHash else {
        throw MuleinFutureMetalError.commandFailed(
            "TensorLUT positive disagrees with independent host replay"
        )
    }

    var eligibility: String
    var scoringStatus: String
    var cribExact: Bool?
    var ic: Double?
    var tail: Double?
    var effectiveTail: Double?
    var plaintext: String?
    var steckerPairs: String?
    var breakGatePassed = false

    if entry.hypothesis == .exact && host.exact && droppedIDs.isEmpty {
        let seedMask = UInt32(1) << UInt32(evaluated.job.seed)
        guard let stop = shell.bombe.test(
            menu: work.future.menu,
            start: positions,
            seedMask: seedMask
        ).first(where: { $0.seedValue == evaluated.job.seed }),
              stop.pairCount == host.pairCount else {
            throw MuleinFutureMetalError.commandFailed(
                "exact identity positive failed the historical-board stop replay"
            )
        }
        let sweepStop = SweepStop(
            ukw: shell.ukwName,
            greek: shell.greekName,
            wheelOrder: shell.wheelOrder,
            menu: work.future.menu,
            rings: shell.rings,
            stop: stop,
            ciphertext: ciphertext
        )
        let verdict = PostBombeDiscriminator.rank(
            stops: [sweepStop], ciphertext: ciphertext, maxPlugs: work.maxPlugs
        )
        if let candidate = verdict.candidates.first {
            scoringStatus = "exact-identity-completed-and-scored"
            cribExact = candidate.cribExact
            ic = candidate.ic
            tail = candidate.tailScore
            effectiveTail = candidate.effectiveTailScore
            plaintext = candidate.plaintext
            steckerPairs = p1030680SteckerPairs(candidate.stecker)
            breakGatePassed = PostBombeDiscriminator.isBreak(candidate)
            eligibility = breakGatePassed
                ? "exact-identity-break-gate-passed-awaiting-ledger-sync"
                : "exact-identity-scored-below-break-gate"
        } else {
            scoringStatus = verdict.killedByCompletion > 0
                ? "exact-identity-killed-by-completion"
                : "exact-identity-killed-by-ic"
            eligibility = "exact-identity-not-scorable"
        }
    } else if entry.hypothesis != .exact {
        eligibility = "post-gap-non-break-eligible-without-geometry-aware-full-decrypt"
        scoringStatus = "host-replayed-physical-candidate-only"
    } else {
        eligibility = "repaired-non-break-eligible-without-explicit-correction-replay"
        scoringStatus = "host-replayed-physical-candidate-only"
    }

    return P1030680MuleinCandidateRecord(
        tag: receipt.tag,
        settingLane: evaluated.settingLane,
        positions: EnigmaAlphabet.string(
            from: [positions.0, positions.1, positions.2, positions.3]
        ),
        futureOrdinal: futureOrdinal,
        futureID: work.future.id.rawValue,
        family: entry.family,
        seed: evaluated.job.seed,
        exact: receipt.exact,
        droppedEdgeMaskHex: String(format: "0x%016llx", receipt.droppedEdgeMask),
        droppedEdgeIDs: droppedIDs,
        pairCount: receipt.pairCount,
        determinedCount: receipt.determinedCount,
        liveHashHex: String(format: "0x%08x", receipt.liveHash),
        hostReplayVerified: true,
        breakEligibility: eligibility,
        scoringStatus: scoringStatus,
        cribExact: cribExact,
        indexOfCoincidence: ic,
        tailScore: tail,
        effectiveTailScore: effectiveTail,
        plaintext: plaintext,
        steckerPairs: steckerPairs,
        breakGatePassed: breakGatePassed
    )
}

private func p1030680CanonicalHex(
    _ text: String,
    digits: Int
) -> UInt64? {
    guard text.count == digits + 2,
          text.hasPrefix("0x"),
          text == text.lowercased() else { return nil }
    let payload = text.dropFirst(2)
    guard payload.allSatisfy({ $0.isNumber || ("a"..."f").contains(String($0)) }) else {
        return nil
    }
    return UInt64(payload, radix: 16)
}

private func p1030680ValidDigest(_ digest: String) -> Bool {
    let prefix = "fnv1a64-"
    guard digest.hasPrefix(prefix), digest.count == prefix.count + 16 else { return false }
    return digest.dropFirst(prefix.count).allSatisfy {
        $0.isNumber || ("a"..."f").contains(String($0))
    }
}

private func p1030680ReceiptRecord(
    _ evaluated: MuleinFutureTensorLUTEvaluatedReceipt
) -> P1030680MuleinReceiptRecord {
    let receipt = evaluated.receipt
    return P1030680MuleinReceiptRecord(
        settingLane: evaluated.settingLane,
        seed: evaluated.job.seed,
        tag: receipt.tag,
        hit: receipt.hit,
        exact: receipt.exact,
        droppedEdgeMaskHex: String(format: "0x%016llx", receipt.droppedEdgeMask),
        erasedEdge: receipt.erasedEdge,
        pairCount: receipt.pairCount,
        determinedCount: receipt.determinedCount,
        liveHashHex: String(format: "0x%08x", receipt.liveHash),
        cycleCount: receipt.cycleCount,
        closureCount: receipt.closureCount,
        dropTrialCount: receipt.dropTrialCount
    )
}

private func p1030680ReceiptKey(settingLane: Int, seed: Int, tag: UInt32) -> String {
    "\(settingLane):\(seed):\(tag)"
}

private func p1030680MaterializeReceipt(
    _ persisted: P1030680MuleinReceiptRecord,
    expected: P1030680MuleinExpectedChunk
) throws -> MuleinFutureTensorLUTEvaluatedReceipt {
    let expectedTag = ((persisted.settingLane - expected.settingFrom) * 26)
        + persisted.seed + 1
    guard (expected.settingFrom..<(expected.settingFrom + expected.settingCount))
            .contains(persisted.settingLane),
          (0..<26).contains(persisted.seed),
          expectedTag > 0,
          persisted.tag == UInt32(expectedTag),
          let droppedMask = p1030680CanonicalHex(
              persisted.droppedEdgeMaskHex, digits: 16
          ),
          let liveHash = p1030680CanonicalHex(persisted.liveHashHex, digits: 8),
          (0..<64).contains(persisted.erasedEdge),
          (0...15).contains(persisted.pairCount),
          (0...63).contains(persisted.determinedCount),
          persisted.cycleCount > 0,
          persisted.closureCount > 0 else {
        throw MuleinFutureMetalError.commandFailed(
            "campaign ledger contains an invalid complete-receipt projection"
        )
    }

    return MuleinFutureTensorLUTEvaluatedReceipt(
        settingLane: persisted.settingLane,
        job: MuleinFutureTensorLUTJob(
            work: expected.work,
            seed: persisted.seed,
            tag: persisted.tag
        ),
        receipt: MuleinFutureTensorLUTCircuitReceipt(
            slot: 0,
            valid: true,
            configError: false,
            hit: persisted.hit,
            tag: persisted.tag,
            seed: persisted.seed,
            exact: persisted.exact,
            droppedEdgeMask: droppedMask,
            erasedEdge: persisted.erasedEdge,
            pairCount: persisted.pairCount,
            determinedCount: persisted.determinedCount,
            liveHash: UInt32(liveHash),
            cycleCount: persisted.cycleCount,
            closureCount: persisted.closureCount,
            dropTrialCount: persisted.dropTrialCount
        )
    )
}

private func p1030680ValidateChunkRecord(
    _ record: P1030680MuleinChunkRecord,
    expected: P1030680MuleinExpectedChunk,
    identity: P1030680MuleinRunIdentity,
    ciphertext: [Int]
) throws {
    guard record.schemaVersion == p1030680MuleinChunkSchemaVersion,
          record.kind == "complete-chunk",
          record.run == identity,
          record.chunkID == expected.chunkID,
          record.shellIndex == expected.shell.index,
          record.ukw == expected.shell.ukwName,
          record.greek == expected.shell.greekName,
          record.wheelOrder == expected.shell.wheelOrder,
          record.rings == expected.shell.ringString,
          record.futureOrdinal == expected.futureOrdinal,
          record.futureID == expected.work.future.id.rawValue,
          record.futureFamily == expected.entry.family,
          record.settingFrom == expected.settingFrom,
          record.settingCount == expected.settingCount,
          record.attemptedReceipts == expected.attemptedReceipts,
          record.receipts.count == expected.attemptedReceipts,
          p1030680ValidDigest(record.completeReceiptDigest),
          record.graphBatches == expected.graphBatches,
          record.submittedTicks.count == expected.graphBatches,
          record.submittedTicks.allSatisfy({ (2...identity.tickLimit).contains($0) }),
          record.tensorWallSeconds.isFinite,
          record.tensorWallSeconds >= 0,
          record.scope == p1030680MuleinChunkScope,
          ISO8601DateFormatter().date(from: record.completedAt) != nil else {
        throw MuleinFutureMetalError.commandFailed(
            "campaign ledger row does not match deterministic chunk \(expected.ordinal)"
        )
    }

    var evaluated: [MuleinFutureTensorLUTEvaluatedReceipt] = []
    evaluated.reserveCapacity(record.receipts.count)
    var receiptKeys = Set<String>()
    var previousOrder: (setting: Int, seed: Int)?
    for persisted in record.receipts {
        let order = (setting: persisted.settingLane, seed: persisted.seed)
        if let previousOrder {
            guard (previousOrder.setting, previousOrder.seed) < (order.setting, order.seed) else {
                throw MuleinFutureMetalError.commandFailed(
                    "campaign ledger complete receipts are not in canonical order"
                )
            }
        }
        previousOrder = order
        let item = try p1030680MaterializeReceipt(persisted, expected: expected)
        let key = p1030680ReceiptKey(
            settingLane: persisted.settingLane, seed: persisted.seed, tag: persisted.tag
        )
        guard receiptKeys.insert(key).inserted else {
            throw MuleinFutureMetalError.commandFailed(
                "campaign ledger contains a duplicate complete receipt"
            )
        }
        evaluated.append(item)
    }

    var candidatesByKey: [String: P1030680MuleinCandidateRecord] = [:]
    for candidate in record.candidates {
        let key = p1030680ReceiptKey(
            settingLane: candidate.settingLane, seed: candidate.seed, tag: candidate.tag
        )
        guard candidatesByKey.updateValue(candidate, forKey: key) == nil else {
            throw MuleinFutureMetalError.commandFailed(
                "campaign ledger chunk contains a duplicate candidate"
            )
        }
    }

    var digest = P1030680MuleinDigest()
    var hitCount = 0
    var breakGatePassed = false
    for item in evaluated {
        digest.mix(item)
        let key = p1030680ReceiptKey(
            settingLane: item.settingLane, seed: item.job.seed, tag: item.receipt.tag
        )
        if item.receipt.hit {
            hitCount += 1
            guard let candidate = candidatesByKey.removeValue(forKey: key) else {
                throw MuleinFutureMetalError.commandFailed(
                    "campaign ledger deleted a candidate committed by a hit receipt"
                )
            }
            let replayed = try p1030680ReplayCandidate(
                evaluated: item,
                futureOrdinal: expected.futureOrdinal,
                entry: expected.entry,
                work: expected.work,
                shell: expected.shell,
                ciphertext: ciphertext
            )
            guard replayed == candidate else {
                throw MuleinFutureMetalError.commandFailed(
                    "campaign ledger candidate failed deterministic host/scoring replay"
                )
            }
            breakGatePassed = breakGatePassed || replayed.breakGatePassed
        } else if candidatesByKey[key] != nil {
            throw MuleinFutureMetalError.commandFailed(
                "campaign ledger candidate is not backed by a hit receipt"
            )
        }
    }

    guard candidatesByKey.isEmpty,
          digest.description == record.completeReceiptDigest,
          record.positiveCount == hitCount,
          record.candidates.count == hitCount,
          record.breakGatePassed == breakGatePassed else {
        throw MuleinFutureMetalError.commandFailed(
            "campaign ledger receipt digest/hit/gate commitment is inconsistent"
        )
    }
}

private func p1030680ExpectedChunkPlan(
    shells: [P1030680MuleinShell],
    manifest: MuleinFutureManifest,
    work: [MuleinFutureMetalWork],
    futureFrom: Int,
    futureCount: Int,
    settingFrom: Int,
    settingCount: Int,
    chunkSettings: Int,
    bankLanes: Int,
    tensorBatch: Int
) -> [P1030680MuleinExpectedChunk] {
    let executionLanesPerSetting = (26 + bankLanes - 1) / bankLanes
    var plan: [P1030680MuleinExpectedChunk] = []
    for shell in shells {
        for futureOrdinal in futureFrom..<(futureFrom + futureCount) {
            var lower = settingFrom
            while lower < settingFrom + settingCount {
                let upper = min(lower + chunkSettings, settingFrom + settingCount)
                let attemptedReceipts = (upper - lower) * 26
                let executionLanes = (upper - lower) * executionLanesPerSetting
                plan.append(P1030680MuleinExpectedChunk(
                    ordinal: plan.count,
                    chunkID: String(
                        format: "shell-%06d-future-%04d-settings-%06d-%06d",
                        shell.index, futureOrdinal, lower, upper
                    ),
                    shell: shell,
                    futureOrdinal: futureOrdinal,
                    entry: manifest.entries[futureOrdinal],
                    work: work[futureOrdinal],
                    settingFrom: lower,
                    settingCount: upper - lower,
                    attemptedReceipts: attemptedReceipts,
                    graphBatches: (executionLanes + tensorBatch - 1) / tensorBatch
                ))
                lower = upper
            }
        }
    }
    return plan
}

private func p1030680RunIdentity(
    manifestPath: String,
    manifestData: Data,
    manifest: MuleinFutureManifest,
    evaluator: MuleinFutureTensorLUTEvaluator,
    subspace: String,
    shells: [P1030680MuleinShell],
    settingFrom: Int,
    settingCount: Int,
    futureFrom: Int,
    futureCount: Int,
    chunkSettings: Int,
    tensorBatch: Int,
    tickLimit: Int
) throws -> P1030680MuleinRunIdentity {
    let payload = P1030680MuleinRunIdentityPayload(
        schemaVersion: p1030680MuleinCampaignProtocolVersion,
        campaignProtocolVersion: p1030680MuleinCampaignProtocolVersion,
        targetID: manifest.targetID,
        manifestPath: manifestPath,
        manifestSHA256: muleinSHA256Hex(manifestData),
        manifestFingerprint: manifest.inventoryFingerprint,
        manifestEntries: manifest.entries.count,
        netlistPath: evaluator.artifactPath,
        netlistSHA256: evaluator.artifactSHA256,
        netlistBytes: evaluator.artifactBytes,
        bankLanes: evaluator.bankLanes,
        lutCount: evaluator.lutCount,
        dffCount: evaluator.dffCount,
        totalWires: evaluator.totalWires,
        levelCount: evaluator.levelCount,
        deviceName: evaluator.deviceName,
        subspace: subspace,
        selectedShells: shells.map(\.identity),
        settingFrom: settingFrom,
        settingCount: settingCount,
        futureFrom: futureFrom,
        futureCount: futureCount,
        chunkSettings: chunkSettings,
        tensorBatch: tensorBatch,
        tickLimit: tickLimit,
        scope: p1030680MuleinRunScope
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let runID = "sha256-" + muleinSHA256Hex(try encoder.encode(payload))
    return P1030680MuleinRunIdentity(
        schemaVersion: payload.schemaVersion,
        campaignProtocolVersion: payload.campaignProtocolVersion,
        runID: runID,
        targetID: payload.targetID,
        manifestPath: payload.manifestPath,
        manifestSHA256: payload.manifestSHA256,
        manifestFingerprint: payload.manifestFingerprint,
        manifestEntries: payload.manifestEntries,
        netlistPath: payload.netlistPath,
        netlistSHA256: payload.netlistSHA256,
        netlistBytes: payload.netlistBytes,
        bankLanes: payload.bankLanes,
        lutCount: payload.lutCount,
        dffCount: payload.dffCount,
        totalWires: payload.totalWires,
        levelCount: payload.levelCount,
        deviceName: payload.deviceName,
        subspace: payload.subspace,
        selectedShells: payload.selectedShells,
        settingFrom: payload.settingFrom,
        settingCount: payload.settingCount,
        futureFrom: payload.futureFrom,
        futureCount: payload.futureCount,
        chunkSettings: payload.chunkSettings,
        tensorBatch: payload.tensorBatch,
        tickLimit: payload.tickLimit,
        scope: payload.scope
    )
}

func runP1030680MuleinCampaign() {
    setbuf(stdout, nil)
    do {
        let manifestPath = stringFlag("--mulein-future-manifest")
            ?? "Fixtures/p1030680_mulein_identity_postgap_delta4.json"
        let netlistPath = stringFlag("--mulein-future-netlist")
            ?? "build/mulein/mulein_future_bank4_lut6.json"
        let ledgerPath = stringFlag("--campaign-ledger")
            ?? "logs/p1030680-mulein-unified.jsonl"
        let subspaceName = stringFlag("--subspace") ?? "potsdam-neighbourhood"
        let subspace = try p1030680CampaignSubspace(subspaceName)
        let rings = try p1030680CampaignRings(
            override: stringFlag("--rings"), subspace: subspace
        )
        let allShells = p1030680CampaignShells(subspace: subspace, rings: rings)

        let shellFrom = try p1030680CampaignInt("--shell-from", default: 0, minimum: 0)
        let defaultShellCount = max(0, allShells.count - shellFrom)
        let shellCount = try p1030680CampaignInt(
            "--shell-count", default: defaultShellCount, minimum: 1
        )
        guard shellFrom < allShells.count,
              shellFrom + shellCount <= allShells.count else {
            throw MuleinFutureMetalError.invalidBatch("selected shell range is out of bounds")
        }
        let shells = Array(allShells[shellFrom..<(shellFrom + shellCount)])

        let settingFrom = try p1030680CampaignInt("--setting-from", default: 0, minimum: 0)
        let settingCount = try p1030680CampaignInt(
            "--setting-count",
            default: WelchmanMetalEngine.laneCount - settingFrom,
            minimum: 1
        )
        guard settingFrom < WelchmanMetalEngine.laneCount,
              settingFrom + settingCount <= WelchmanMetalEngine.laneCount else {
            throw MuleinFutureMetalError.invalidBatch("selected setting range is out of bounds")
        }

        let manifestData = try Data(contentsOf: URL(fileURLWithPath: manifestPath))
        let manifest = try MuleinFutureManifestBuilder.load(data: manifestData)
        let work = try MuleinFutureManifestBuilder.materialize(manifest)
        let ciphertext = EnigmaAlphabet.normalize(manifest.ciphertext)
        guard ciphertext == EnigmaAlphabet.normalize(U534MessageP1030680.ciphertext) else {
            throw MuleinFutureMetalError.invalidBatch(
                "manifest ciphertext does not match the canonical P1030680 target"
            )
        }
        let futureFrom = try p1030680CampaignInt("--future-from", default: 0, minimum: 0)
        let futureCount = try p1030680CampaignInt(
            "--future-count", default: work.count - futureFrom, minimum: 1
        )
        guard futureFrom < work.count, futureFrom + futureCount <= work.count else {
            throw MuleinFutureMetalError.invalidBatch("selected future range is out of bounds")
        }

        let primaryBankLanes = try p1030680CampaignInt(
            "--mulein-bank-lanes", default: 4, minimum: 1
        )
        let alternateBankLanes: Int? = CommandLine.arguments.contains("--mulein-future-bank-lanes")
            ? try p1030680CampaignInt("--mulein-future-bank-lanes", default: 4, minimum: 1)
            : nil
        if let alternateBankLanes, alternateBankLanes != primaryBankLanes {
            throw MuleinFutureMetalError.invalidBatch(
                "--mulein-bank-lanes and --mulein-future-bank-lanes disagree"
            )
        }
        let bankLanes = alternateBankLanes ?? primaryBankLanes
        let chunkSettings = try p1030680CampaignInt(
            "--chunk-settings", default: 16, minimum: 1
        )
        let tensorBatch = try p1030680CampaignInt("--tensor-batch", default: 16, minimum: 1)
        let tickLimit = try p1030680CampaignInt(
            "--mulein-future-tick-limit", default: 100_000, minimum: 3
        )
        let evaluator = try MuleinFutureTensorLUTEvaluator(
            artifactPath: netlistPath,
            bankLanes: bankLanes,
            maximumBatchSize: tensorBatch
        )
        let identity = try p1030680RunIdentity(
            manifestPath: manifestPath,
            manifestData: manifestData,
            manifest: manifest,
            evaluator: evaluator,
            subspace: subspace.name,
            shells: shells,
            settingFrom: settingFrom,
            settingCount: settingCount,
            futureFrom: futureFrom,
            futureCount: futureCount,
            chunkSettings: chunkSettings,
            tensorBatch: tensorBatch,
            tickLimit: tickLimit
        )

        let expectedPlan = p1030680ExpectedChunkPlan(
            shells: shells,
            manifest: manifest,
            work: work,
            futureFrom: futureFrom,
            futureCount: futureCount,
            settingFrom: settingFrom,
            settingCount: settingCount,
            chunkSettings: chunkSettings,
            bankLanes: bankLanes,
            tensorBatch: tensorBatch
        )
        let totalChunks = expectedPlan.count
        let totalReceipts = expectedPlan.reduce(0) { $0 + $1.attemptedReceipts }
        print("=== Nazi Blaster 9000 — unified P1030680 Mulein TensorLUT campaign ===")
        print("protocol           : v\(identity.campaignProtocolVersion)")
        print("run_id             : \(identity.runID)")
        print("manifest           : \(manifestPath)")
        print("manifest_sha256    : \(identity.manifestSHA256)")
        print("manifest_inventory : \(manifest.inventoryFingerprint) (\(work.count) futures)")
        print("netlist            : \(netlistPath)")
        print("netlist_sha256     : \(evaluator.artifactSHA256)")
        print("device             : \(evaluator.deviceName)")
        print("graph              : W\(bankLanes), \(evaluator.lutCount) LUT6, "
            + "\(evaluator.dffCount) DFF, \(evaluator.totalWires) wires, "
            + "\(evaluator.levelCount) levels")
        print("shells             : \(shellFrom)..<\(shellFrom + shellCount) of \(allShells.count)")
        for shell in shells { print("  shell            : \(shell.identity)") }
        print("settings           : \(settingFrom)..<\(settingFrom + settingCount)")
        print("futures            : \(futureFrom)..<\(futureFrom + futureCount)")
        print("chunks             : \(totalChunks), \(chunkSettings) settings/chunk")
        print("complete receipts  : \(totalReceipts)")
        print("tensor batch       : \(tensorBatch) outer lanes")
        print("ledger             : \(ledgerPath)")
        print("scope              : \(identity.scope)")

        if CommandLine.arguments.contains("--mulein-future-plan-only") {
            print("PLAN ONLY: no P1030680 settings evaluated and no ledger written")
            return
        }

        let ledger = try P1030680MuleinJSONLLedger(
            path: ledgerPath,
            identity: identity,
            expectedPlan: expectedPlan,
            ciphertext: ciphertext
        )
        print("resume             : \(ledger.completedChunkIDs.count)/\(totalChunks) chunks present")
        print("prior verified hits: \(ledger.priorPositiveCount)")

        if ledger.priorBreakGatePassed {
            print()
            print("campaign result    : HALTED ON DURABLE PRIOR BREAK-GATE CANDIDATE")
            print("chunks new/skipped : 0/\(ledger.priorRecords.count)")
            print("host-verified hits : \(ledger.priorPositiveCount)")
            print("No evaluator work was submitted; automatic announcement remains withheld.")
            print("Sync BREAK ledger, journal, and report before any BREAK FOUND claim.")
            return
        }

        var completedNow = 0
        var skipped = 0
        var positives = ledger.priorPositiveCount
        var haltedForBreakGate = false

        campaign: for planned in expectedPlan {
            if ledger.completedChunkIDs.contains(planned.chunkID) {
                skipped += 1
                continue
            }

            let shell = planned.shell
            let item = planned.work
            let entry = planned.entry
            let lower = planned.settingFrom
            let upper = lower + planned.settingCount
            let expectedReceipts = planned.attemptedReceipts
            guard expectedReceipts <= Int(UInt32.max) else {
                throw MuleinFutureMetalError.invalidBatch(
                    "campaign chunk has too many jobs for 32-bit tags"
                )
            }
            var executionLanes: [MuleinFutureTensorLUTExecutionLane] = []
            executionLanes.reserveCapacity(
                (expectedReceipts + bankLanes - 1) / bankLanes
            )
            var ordinal = 0
            for settingLane in lower..<upper {
                let setting = WelchmanMetalEngine.position(forLane: settingLane)
                var seedFrom = 0
                while seedFrom < 26 {
                    let seedUpper = min(seedFrom + bankLanes, 26)
                    var jobs: [MuleinFutureTensorLUTJob] = []
                    for seed in seedFrom..<seedUpper {
                        ordinal += 1
                        jobs.append(MuleinFutureTensorLUTJob(
                            work: item, seed: seed, tag: UInt32(ordinal)
                        ))
                    }
                    let packed = try packMuleinFutureTensorLUTBatch(
                        jobs: jobs,
                        bombe: shell.bombe,
                        setting: setting,
                        bankLanes: bankLanes
                    )
                    executionLanes.append(MuleinFutureTensorLUTExecutionLane(
                        settingLane: settingLane, packed: packed
                    ))
                    seedFrom = seedUpper
                }
            }

            var evaluated: [MuleinFutureTensorLUTEvaluatedReceipt] = []
            evaluated.reserveCapacity(expectedReceipts)
            var submittedTicks: [Int] = []
            var tensorWall = 0.0
            var batchFrom = 0
            while batchFrom < executionLanes.count {
                let batchUpper = min(batchFrom + tensorBatch, executionLanes.count)
                let result = try evaluator.evaluate(
                    lanes: Array(executionLanes[batchFrom..<batchUpper]),
                    tickLimit: tickLimit
                )
                evaluated.append(contentsOf: result.receipts)
                submittedTicks.append(result.submittedTicks)
                tensorWall += result.wallSeconds
                batchFrom = batchUpper
            }

            guard evaluated.count == expectedReceipts,
                  Set(evaluated.map { $0.receipt.tag }).count == expectedReceipts,
                  Set(evaluated.map { ($0.settingLane * 26) + $0.job.seed }).count
                    == expectedReceipts,
                  submittedTicks.count == planned.graphBatches else {
                throw MuleinFutureMetalError.commandFailed(
                    "campaign chunk is missing or duplicating complete receipts/batches"
                )
            }
            let canonicalEvaluated = evaluated.sorted(by: {
                ($0.settingLane, $0.job.seed) < ($1.settingLane, $1.job.seed)
            })
            let receiptRecords = canonicalEvaluated.map(p1030680ReceiptRecord)
            var digest = P1030680MuleinDigest()
            for receipt in canonicalEvaluated {
                digest.mix(receipt)
            }

            var candidateRecords: [P1030680MuleinCandidateRecord] = []
            for receipt in canonicalEvaluated where receipt.receipt.hit {
                candidateRecords.append(try p1030680ReplayCandidate(
                    evaluated: receipt,
                    futureOrdinal: planned.futureOrdinal,
                    entry: entry,
                    work: item,
                    shell: shell,
                    ciphertext: ciphertext
                ))
            }
            let breakGatePassed = candidateRecords.contains(where: \.breakGatePassed)
            let record = P1030680MuleinChunkRecord(
                schemaVersion: p1030680MuleinChunkSchemaVersion,
                kind: "complete-chunk",
                run: identity,
                chunkID: planned.chunkID,
                completedAt: ISO8601DateFormatter().string(from: Date()),
                shellIndex: shell.index,
                ukw: shell.ukwName,
                greek: shell.greekName,
                wheelOrder: shell.wheelOrder,
                rings: shell.ringString,
                futureOrdinal: planned.futureOrdinal,
                futureID: item.future.id.rawValue,
                futureFamily: entry.family,
                settingFrom: lower,
                settingCount: planned.settingCount,
                attemptedReceipts: expectedReceipts,
                receipts: receiptRecords,
                completeReceiptDigest: digest.description,
                graphBatches: submittedTicks.count,
                submittedTicks: submittedTicks,
                tensorWallSeconds: tensorWall,
                positiveCount: candidateRecords.count,
                candidates: candidateRecords,
                breakGatePassed: breakGatePassed,
                scope: p1030680MuleinChunkScope
            )
            try ledger.append(record)
            completedNow += 1
            positives += candidateRecords.count
            print(String(
                format: "chunk %-53@ complete receipts=%d hits=%d batches=%d wall=%.3fs digest=%@",
                planned.chunkID as NSString,
                expectedReceipts,
                candidateRecords.count,
                submittedTicks.count,
                tensorWall,
                digest.description as NSString
            ))
            if breakGatePassed {
                haltedForBreakGate = true
                print("BREAK-GATE CANDIDATE durably recorded; automatic announcement withheld")
                print("Sync BREAK ledger, journal, and report before any BREAK FOUND claim")
                break campaign
            }
        }

        print()
        print("campaign result    : \(haltedForBreakGate ? "HALTED ON BREAK-GATE CANDIDATE" : "BOUNDED RUN COMPLETE")")
        print("chunks new/skipped : \(completedNow)/\(skipped)")
        print("host-verified hits : \(positives)")
        if !haltedForBreakGate {
            print("NO BREAK CLAIM: only the printed bounded shell/future/setting coverage moved")
        }
        print("P1030680 remains unbroken unless a durably recorded exact identity candidate")
        print("clears the existing crib/IC/tail/≤10-plug gate and the public surfaces are synced.")
    } catch {
        fputs("P1030680 Mulein campaign failed: \(error)\n", stderr)
        fflush(stderr)
        exit(1)
    }
}
