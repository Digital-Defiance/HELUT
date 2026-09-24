import CryptoKit
import Foundation
import HELUTCLI
import HELUTCore

// MARK: - `--mulein-ostwald-adapt`
//
// Hands identity-family one-edge repairs to the existing dense `--ostwald-escalate` climber.
// Three layers the campaign already paid to keep apart:
//
//  1. **Future lattice** — a compiled transcript hypothesis. The operational inventory is
//     628 Futures (314 identity + 314 post-gap δ=4). Replacement/transposition exist in the
//     type and are not in that inventory.
//  2. **Mulein board repair** — delete a constraint so the diagonal board closes. Edge erasure
//     never masquerades as geometry. A repair is not a `.replacement` Future.
//  3. **Ostwald climb** — walks the 72 recorded letters. Legal for identity Futures. Illegal
//     for post-gap: after a hole every later symbol would be enciphered at a rotor position
//     δ too low. That is the bug `MuleinSparseTranscriptBuilder` exists to stop, and 82% of
//     post-gap hits in the stripe are identity closures translated by four lanes.
//
// Fast mode, on purpose. This does **not** rematerialize the 628-Future TensorLUT campaign.
// It streams the durable JSONL, rebounds the inventory by SHA-256 + fingerprint, and compiles
// only the identity-repair ordinals that actually appear. Host replay on the Swift board
// rebuilds forced plugs from `live` (repairs persist `steckerPairs` as nil). Split menus and
// post-gap repairs are counted with an explicit skip reason, not dropped on the floor.
//
// Not a decrypt. Emitting a quarantine JSON is not a climb, and a climb that fails crib-exact
// on a dropped letter is not a break. The climber's job is margin versus the random-setting
// floor, on identity-family forced plugs only.

private let muleinOstwaldAdaptSchemaVersion = 1
private let muleinOstwaldAdaptScope =
    "Read-only identity-family Mulein-repair → Ostwald escalate adapter. "
        + "Fast rebound: SHA-256 + fingerprint, compile only requested identity-repair "
        + "ordinals, Swift host board. Post-gap dense climb is illegal. Not a decrypt."

package enum MuleinOstwaldAdaptDisposition: String, Equatable, Sendable {
    case exactIdentityAlreadyScored = "exact-identity-already-scored"
    case exactPostGapAlreadyAdjudicated = "exact-post-gap-already-adjudicated"
    case postGapDenseOstwaldIllegal = "post-gap-dense-ostwald-illegal"
    case postGapGappedRepair = "post-gap-gapped-repair"
    case inconsistentExactDrop = "inconsistent-exact-drop"
    case identityRepair = "identity-repair"
}

package enum MuleinOstwaldAdaptSkipReason: String, Equatable, Hashable, Sendable {
    case exactIdentityAlreadyScored = "exact-identity-already-scored"
    case exactPostGapAlreadyAdjudicated = "exact-post-gap-already-adjudicated"
    case postGapDenseOstwaldIllegal = "post-gap-dense-ostwald-illegal"
    case inconsistentExactDrop = "inconsistent-exact-drop"
    case splitMenu = "split-menu"
    case pairCountBelowFloor = "pair-count-below-floor"
    case duplicateShellLiveHash = "duplicate-shell-live-hash"
    case familyNotRequested = "family-not-requested"
    case emptyForcedPlugs = "empty-forced-plugs"
}

package enum MuleinOstwaldAdapt {
    package static let identityFamily = "identity"
    package static let defaultMinPairs = 4

    package enum Family: String, Equatable, Sendable {
        case identity
        case postGap = "post-gap"
        case both
    }

    /// Classify a ledger candidate before any Future is compiled.
    package static func preHostDisposition(
        family: String,
        exact: Bool,
        droppedEmpty: Bool,
        gappedPostGap: Bool = false
    ) -> MuleinOstwaldAdaptDisposition {
        let identity = family == identityFamily
        switch (exact, droppedEmpty) {
        case (true, true):
            return identity
                ? .exactIdentityAlreadyScored
                : .exactPostGapAlreadyAdjudicated
        case (false, false):
            if identity { return .identityRepair }
            return gappedPostGap ? .postGapGappedRepair : .postGapDenseOstwaldIllegal
        default:
            return .inconsistentExactDrop
        }
    }

    /// Euler characteristic, same formula as `BombeMenu.components`.
    package static func menuComponents(
        edgeCount: Int,
        loops: Int,
        endpointA: [Int],
        endpointB: [Int]
    ) -> Int {
        var letters = Set<Int>()
        for letter in endpointA { letters.insert(letter) }
        for letter in endpointB { letters.insert(letter) }
        return loops - edgeCount + letters.count
    }

    /// Dedup key: shell + message positions + live-state hash.
    /// Post-gap clones of an identity closure share this key at `lane − 4`; dropping them
    /// here is belt-and-suspenders once post-gap is already skipped by disposition.
    package static func shellLiveKey(
        ukw: String,
        greek: String,
        wheelOrder: String,
        rings: String,
        positions: String,
        liveHashHex: String
    ) -> String {
        [ukw, greek, wheelOrder, rings, positions, liveHashHex].joined(separator: "|")
    }

    /// Forced non-identity plugs from a Mulein `live` bitmask.
    /// `nil` means the involution is not a well-formed singleton-bit board.
    package static func forcedPairTokens(from live: [UInt32]) -> [String]? {
        guard live.count == 26 else { return nil }
        var table = Array(0..<26)
        var determined = [Bool](repeating: false, count: 26)
        for letter in 0..<26 {
            let mask = live[letter]
            if mask == 0 { continue }
            guard mask.nonzeroBitCount == 1 else { return nil }
            let mate = Int(mask.trailingZeroBitCount)
            guard (0..<26).contains(mate) else { return nil }
            table[letter] = mate
            determined[letter] = true
        }
        for letter in 0..<26 where determined[letter] {
            let mate = table[letter]
            guard determined[mate], table[mate] == letter else { return nil }
        }
        var tokens: [String] = []
        for letter in 0..<26 where determined[letter] && table[letter] > letter {
            tokens.append(
                "\(EnigmaAlphabet.character(letter))\(EnigmaAlphabet.character(table[letter]))"
            )
        }
        return tokens
    }

    /// Callable core. Does not read argv or `exit`. Tests pass temp paths; the CLI wrapper
    /// prints and fails closed. Never rematerializes the 628-Future operational inventory.
    package static func run(
        ledgerPath: String,
        outputPath: String,
        skipPath: String,
        minPairs: Int = defaultMinPairs,
        limit: Int = 0,
        printProgress: Bool = false,
        includeSplitMenu: Bool = false,
        family: Family = .identity
    ) throws -> MuleinOstwaldAdaptResult {
        try muleinOstwaldAdaptRun(
            ledgerPath: ledgerPath,
            outputPath: outputPath,
            skipPath: skipPath,
            minPairs: minPairs,
            limit: limit,
            printProgress: printProgress,
            includeSplitMenu: includeSplitMenu,
            family: family
        )
    }
}

package struct MuleinOstwaldAdaptResult: Equatable, Sendable {
    package let ledgerSHA256: String
    package let compiledOrdinals: Int
    package let totalCandidates: Int
    package let queuedIdentityRepairs: Int
    package let queuedGappedRepairs: Int
    package let emitted: Int
    package let skipCounts: [MuleinOstwaldAdaptSkipReason: Int]
    package let outputPath: String
    package let skipPath: String
}

package struct MuleinOstwaldAdaptRunIdentity: Codable, Equatable, Sendable {
    package let runID: String
    package let targetID: String
    package let manifestPath: String
    package let manifestSHA256: String
    package let manifestFingerprint: String
    package let manifestEntries: Int

    package init(
        runID: String,
        targetID: String,
        manifestPath: String,
        manifestSHA256: String,
        manifestFingerprint: String,
        manifestEntries: Int
    ) {
        self.runID = runID
        self.targetID = targetID
        self.manifestPath = manifestPath
        self.manifestSHA256 = manifestSHA256
        self.manifestFingerprint = manifestFingerprint
        self.manifestEntries = manifestEntries
    }
}

package struct MuleinOstwaldAdaptCandidate: Codable, Equatable, Sendable {
    package let settingLane: Int
    package let positions: String
    package let futureOrdinal: Int
    package let futureID: String
    package let family: String
    package let seed: Int
    package let exact: Bool
    package let droppedEdgeMaskHex: String
    package let droppedEdgeIDs: [MuleinEdgeID]
    package let pairCount: Int
    package let determinedCount: Int
    package let liveHashHex: String

    package init(
        settingLane: Int,
        positions: String,
        futureOrdinal: Int,
        futureID: String,
        family: String,
        seed: Int,
        exact: Bool,
        droppedEdgeMaskHex: String,
        droppedEdgeIDs: [MuleinEdgeID],
        pairCount: Int,
        determinedCount: Int,
        liveHashHex: String
    ) {
        self.settingLane = settingLane
        self.positions = positions
        self.futureOrdinal = futureOrdinal
        self.futureID = futureID
        self.family = family
        self.seed = seed
        self.exact = exact
        self.droppedEdgeMaskHex = droppedEdgeMaskHex
        self.droppedEdgeIDs = droppedEdgeIDs
        self.pairCount = pairCount
        self.determinedCount = determinedCount
        self.liveHashHex = liveHashHex
    }
}

package struct MuleinOstwaldAdaptRow: Codable, Equatable, Sendable {
    package let run: MuleinOstwaldAdaptRunIdentity
    package let chunkID: String
    package let ukw: String
    package let greek: String
    package let wheelOrder: String
    package let rings: String
    package let futureOrdinal: Int
    package let futureID: String
    package let futureFamily: String
    package let candidates: [MuleinOstwaldAdaptCandidate]

    package init(
        run: MuleinOstwaldAdaptRunIdentity,
        chunkID: String,
        ukw: String,
        greek: String,
        wheelOrder: String,
        rings: String,
        futureOrdinal: Int,
        futureID: String,
        futureFamily: String,
        candidates: [MuleinOstwaldAdaptCandidate]
    ) {
        self.run = run
        self.chunkID = chunkID
        self.ukw = ukw
        self.greek = greek
        self.wheelOrder = wheelOrder
        self.rings = rings
        self.futureOrdinal = futureOrdinal
        self.futureID = futureID
        self.futureFamily = futureFamily
        self.candidates = candidates
    }
}

package struct MuleinOstwaldAdaptSkipRecord: Codable, Equatable, Sendable {
    package let schemaVersion: Int
    package let kind: String
    package let reason: String
    package let chunkID: String
    package let shell: String
    package let futureOrdinal: Int
    package let futureID: String
    package let family: String
    package let settingLane: Int
    package let positions: String
    package let seed: Int
    package let exact: Bool
    package let pairCount: Int
    package let liveHashHex: String
    package let scope: String
}

private struct OstwaldAdaptRepairRef {
    let row: MuleinOstwaldAdaptRow
    let candidate: MuleinOstwaldAdaptCandidate
}

func runMuleinOstwaldAdapt() {
    guard let ledgerPath = stringFlag("--mulein-ostwald-adapt") else {
        fputs(
            "usage: --mulein-ostwald-adapt <campaign-ledger.jsonl> "
                + "[--mulein-ostwald-adapt-out quarantine.json] "
                + "[--mulein-ostwald-adapt-skip-out skips.jsonl] "
                + "[--mulein-ostwald-min-pairs 4] "
                + "[--mulein-ostwald-adapt-limit N] "
                + "[--mulein-ostwald-split-menu] "
                + "[--mulein-ostwald-family identity|post-gap|both]\n",
            stderr
        )
        exit(2)
    }
    let outputPath = stringFlag("--mulein-ostwald-adapt-out")
        ?? "logs/p1030680-mulein-identity-repair-ostwald.json"
    let skipPath = stringFlag("--mulein-ostwald-adapt-skip-out")
        ?? "logs/p1030680-mulein-identity-repair-ostwald-skips.jsonl"
    let minPairs = intFlag("--mulein-ostwald-min-pairs", allowZero: true)
        ?? MuleinOstwaldAdapt.defaultMinPairs
    let limit = intFlag("--mulein-ostwald-adapt-limit", allowZero: true) ?? 0
    let includeSplitMenu = CommandLine.arguments.contains("--mulein-ostwald-split-menu")
    let family = MuleinOstwaldAdapt.Family(
        rawValue: stringFlag("--mulein-ostwald-family") ?? "identity"
    ) ?? .identity
    do {
        _ = try MuleinOstwaldAdapt.run(
            ledgerPath: ledgerPath,
            outputPath: outputPath,
            skipPath: skipPath,
            minPairs: minPairs,
            limit: limit,
            printProgress: true,
            includeSplitMenu: includeSplitMenu,
            family: family
        )
    } catch {
        fputs("\(error)\n", stderr)
        exit(1)
    }
}

private func muleinOstwaldAdaptRun(
    ledgerPath: String,
    outputPath: String,
    skipPath: String,
    minPairs: Int,
    limit: Int,
    printProgress: Bool,
    includeSplitMenu: Bool,
    family: MuleinOstwaldAdapt.Family
) throws -> MuleinOstwaldAdaptResult {
    func note(_ line: String) {
        if printProgress { print(line) }
    }

    let includeGappedPostGap = family != .identity
    let includeIdentity = family != .postGap
    note("=== P1030680 Mulein-repair → Ostwald escalate adapter ===")
    note("source ledger : \(ledgerPath)")
    note("quarantine    : \(outputPath)")
    note("skip ledger   : \(skipPath)")
    note("min pairs     : \(minPairs)"
        + (minPairs == 0
            ? "  (empty boards emitted; Phase 50.6 still wants 4 correct plugs to finish)"
            : "  (Phase 50.6: four correct plugs flip the 72-letter sign)"))
    note("family        : \(family.rawValue)"
        + (includeSplitMenu ? "  split-menu: emit" : "  split-menu: skip"))
    note("rebound       : fast — SHA-256 + fingerprint, compile requested repair ordinals")
    note("scope         : "
        + (includeGappedPostGap
            ? "identity plus leading-gap post-gap (δ dummy-steps); dense post-gap still illegal"
            : "identity-family repairs; post-gap dense climb is illegal"))
    note("")
    if printProgress { fflush(stdout) }

    let decoder = JSONDecoder()
    var identity: MuleinOstwaldAdaptRunIdentity?
    var totalCandidates = 0
    var repairRefs: [OstwaldAdaptRepairRef] = []
    var skipCounts: [MuleinOstwaldAdaptSkipReason: Int] = [:]
    var skipRecords: [MuleinOstwaldAdaptSkipRecord] = []
    let ledgerDigest = try muleinOstwaldHashAndScan(
        path: ledgerPath,
        decoder: decoder,
        identity: &identity,
        totalCandidates: &totalCandidates,
        repairRefs: &repairRefs,
        skipCounts: &skipCounts,
        skipRecords: &skipRecords,
        includeIdentity: includeIdentity,
        includeGappedPostGap: includeGappedPostGap
    )

    guard let identity else {
        throw MuleinFutureMetalError.commandFailed("campaign ledger is empty")
    }
    note("ledger SHA-256: \(ledgerDigest)")
    note("rows scanned  : streamed (not loaded as one blob)")
    note("run           : \(identity.runID)")
    note("candidates    : \(totalCandidates) total")
    note("  identity-repair queued : \(repairRefs.count)")
    for reason in [
        MuleinOstwaldAdaptSkipReason.exactIdentityAlreadyScored,
        .exactPostGapAlreadyAdjudicated,
        .postGapDenseOstwaldIllegal
    ] {
        if let count = skipCounts[reason], count > 0 {
            note("  skipped \(reason.rawValue): \(count)")
        }
    }
    note("")
    if printProgress { fflush(stdout) }

    // ---- rebound the 628-Future inventory by content, then compile a subset ---------------
    guard let manifestData = FileManager.default.contents(atPath: identity.manifestPath) else {
        throw MuleinFutureMetalError.commandFailed(
            "could not read manifest \(identity.manifestPath)"
        )
    }
    let manifestDigest = SHA256.hash(data: manifestData)
        .map { String(format: "%02x", $0) }.joined()
    guard manifestDigest == identity.manifestSHA256 else {
        throw MuleinFutureMetalError.commandFailed(
            "manifest has changed since the run: \(manifestDigest) != "
                + "\(identity.manifestSHA256). Refusing to escalate against a different inventory."
        )
    }
    guard let manifest = try? MuleinFutureManifestBuilder.load(data: manifestData) else {
        throw MuleinFutureMetalError.commandFailed("manifest failed semantic validation")
    }
    guard manifest.inventoryFingerprint == identity.manifestFingerprint,
          manifest.entries.count == identity.manifestEntries else {
        throw MuleinFutureMetalError.commandFailed(
            "manifest fingerprint/entry count disagrees with the ledger identity"
        )
    }
    note("manifest      : \(manifest.entries.count) Futures, "
        + "fingerprint \(manifest.inventoryFingerprint) — rebound by content")
    note("  identity    : \(manifest.identityCount)")
    note("  post-gap    : \(manifest.postGapDeltaCount) (not compiled)")

    let neededOrdinals = Set(repairRefs.map(\.candidate.futureOrdinal))
    let workByOrdinal: [Int: MuleinFutureMetalWork]
    do {
        workByOrdinal = try MuleinFutureManifestBuilder.materialize(
            manifest, ordinals: neededOrdinals
        )
    } catch {
        throw MuleinFutureMetalError.commandFailed("fast materialize failed: \(error)")
    }
    note("  compiled    : \(workByOrdinal.count) repair ordinals "
        + "(fast mode; not \(manifest.entries.count))")
    note("")
    if printProgress { fflush(stdout) }

    // ---- host replay, split-menu dump, pair floor, dedup ----------------------------------
    var emitted: [QuarantineCandidate] = []
    var seenLive = Set<String>()
    for item in repairRefs {
        let row = item.row
        let candidate = item.candidate
        let skipBase = { (reason: MuleinOstwaldAdaptSkipReason) -> MuleinOstwaldAdaptSkipRecord in
            MuleinOstwaldAdaptSkipRecord(
                schemaVersion: muleinOstwaldAdaptSchemaVersion,
                kind: "mulein-ostwald-adapt-skip",
                reason: reason.rawValue,
                chunkID: row.chunkID,
                shell: "\(row.ukw)/\(row.greek)/\(row.wheelOrder)/\(row.rings)",
                futureOrdinal: candidate.futureOrdinal,
                futureID: candidate.futureID,
                family: candidate.family,
                settingLane: candidate.settingLane,
                positions: candidate.positions,
                seed: candidate.seed,
                exact: candidate.exact,
                pairCount: candidate.pairCount,
                liveHashHex: candidate.liveHashHex,
                scope: muleinOstwaldAdaptScope
            )
        }

        guard let work = workByOrdinal[candidate.futureOrdinal] else {
            throw MuleinFutureMetalError.commandFailed(
                "identity-repair names Future \(candidate.futureOrdinal) that was not compiled"
            )
        }
        let future = work.future
        let isIdentity = candidate.family == MuleinOstwaldAdapt.identityFamily
        let entry = manifest.entries[candidate.futureOrdinal]
        if isIdentity {
            guard future.id.rawValue == candidate.futureID,
                  entry.family == MuleinOstwaldAdapt.identityFamily,
                  entry.hypothesis == .exact else {
                throw MuleinFutureMetalError.commandFailed(
                    "Future content ID / identity hypothesis disagrees with the ledger row"
                )
            }
        } else {
            guard future.id.rawValue == candidate.futureID,
                  entry.family.hasPrefix("post-gap") else {
                throw MuleinFutureMetalError.commandFailed(
                    "Future content ID / post-gap family disagrees with the ledger row"
                )
            }
        }

        let serializedComponents = MuleinOstwaldAdapt.menuComponents(
            edgeCount: entry.edgeCount,
            loops: entry.loops,
            endpointA: entry.endpointA,
            endpointB: entry.endpointB
        )
        guard future.menu.components == serializedComponents else {
            throw MuleinFutureMetalError.commandFailed(
                "compiled menu components disagree with serialized Euler characteristic"
            )
        }
        if !includeSplitMenu, future.menu.components != 1 {
            skipCounts[.splitMenu, default: 0] += 1
            skipRecords.append(skipBase(.splitMenu))
            continue
        }

        let rotorNames = row.wheelOrder.split(separator: "-").map(String.init)
        guard rotorNames.count == 3 else {
            throw MuleinFutureMetalError.commandFailed(
                "unparseable wheel order '\(row.wheelOrder)'"
            )
        }
        let bombe = WelchmanBombe(
            greek: EnigmaM4Warehouse.greek(named: row.greek),
            left: EnigmaWarehouse.rotor(named: rotorNames[0]),
            middle: EnigmaWarehouse.rotor(named: rotorNames[1]),
            right: EnigmaWarehouse.rotor(named: rotorNames[2]),
            reflector: EnigmaM4Warehouse.thinReflector(named: row.ukw),
            rings: EnigmaM4Key.rings(fromLetters: row.rings),
            maxPlugs: work.maxPlugs
        )
        let positions = WelchmanMetalEngine.position(forLane: candidate.settingLane)
        let scramblers = bombe.scramblers(menu: future.menu, start: positions)
        guard let host = MuleinBoard.propagate(
            menu: future.menu,
            scramblers: scramblers,
            seedLetter: future.menu.central,
            seedValue: candidate.seed,
            tolerance: work.tolerance,
            maxPlugs: work.maxPlugs,
            exactPlugs: work.exactPlugs
        ) else {
            throw MuleinFutureMetalError.commandFailed(
                "candidate \(row.chunkID) lane \(candidate.settingLane) "
                    + "failed independent host replay"
            )
        }

        var hostMask: UInt64 = 0
        var droppedIDs: [MuleinEdgeID] = []
        for edge in host.droppedEdges {
            guard future.boardEdges.indices.contains(edge) else {
                throw MuleinFutureMetalError.commandFailed(
                    "host replay emitted out-of-range repair provenance"
                )
            }
            hostMask |= UInt64(1) << UInt64(edge)
            droppedIDs.append(future.boardEdges[edge].id)
        }
        guard !host.exact,
              host.pairCount == candidate.pairCount,
              host.determinedCount == candidate.determinedCount,
              String(format: "0x%08x", host.liveHash) == candidate.liveHashHex,
              String(format: "0x%016llx", hostMask) == candidate.droppedEdgeMaskHex,
              Set(droppedIDs) == Set(candidate.droppedEdgeIDs) else {
            throw MuleinFutureMetalError.commandFailed(
                "candidate \(row.chunkID) lane \(candidate.settingLane) "
                    + "disagrees with its persisted host state"
            )
        }

        if host.pairCount < minPairs {
            skipCounts[.pairCountBelowFloor, default: 0] += 1
            skipRecords.append(skipBase(.pairCountBelowFloor))
            continue
        }
        guard let tokens = MuleinOstwaldAdapt.forcedPairTokens(from: host.live),
              tokens.count == host.pairCount else {
            throw MuleinFutureMetalError.commandFailed(
                "live bitmask did not yield a well-formed involution"
            )
        }
        if tokens.isEmpty, minPairs > 0 {
            skipCounts[.emptyForcedPlugs, default: 0] += 1
            skipRecords.append(skipBase(.emptyForcedPlugs))
            continue
        }

        let liveKey = MuleinOstwaldAdapt.shellLiveKey(
            ukw: row.ukw,
            greek: row.greek,
            wheelOrder: row.wheelOrder,
            rings: row.rings,
            positions: candidate.positions,
            liveHashHex: candidate.liveHashHex
        )
        if !seenLive.insert(liveKey).inserted {
            skipCounts[.duplicateShellLiveHash, default: 0] += 1
            skipRecords.append(skipBase(.duplicateShellLiveHash))
            continue
        }

        let leadingHoles = isIdentity ? 0 : manifest.delta
        emitted.append(
            QuarantineCandidate(
                ukw: row.ukw,
                greek: row.greek,
                wheelOrder: row.wheelOrder,
                rings: row.rings,
                positions: candidate.positions,
                steckerPairs: tokens,
                pairCount: host.pairCount,
                menuCrib: future.menu.crib,
                menuOffset: future.menu.offset,
                menuAnchors: future.menu.anchors.count > 1 ? future.menu.anchors : nil,
                menuLoops: future.menu.loops,
                menuEdges: future.menu.edgeCount,
                ic: 0,
                tailScore: 0,
                fullScore: 0,
                effectiveTailScore: 0,
                cribExact: false,
                prefixEnd: nil,
                prefixIC: nil,
                prefixTailScore: nil,
                plaintextPrefix: "",
                softBand: isIdentity
                    ? "identity-repair-forced-plugs-not-soft-band"
                    : "post-gap-gapped-repair-forced-plugs-not-soft-band",
                source: isIdentity
                    ? "mulein-identity-repair-future-\(candidate.futureOrdinal)-host-replay"
                    : "mulein-post-gap-gapped-repair-future-\(candidate.futureOrdinal)-host-replay",
                leadingHoles: leadingHoles
            )
        )
    }

    emitted.sort { lhs, rhs in
        if lhs.pairCount != rhs.pairCount { return lhs.pairCount > rhs.pairCount }
        return lhs.positions < rhs.positions
    }
    if limit > 0 && emitted.count > limit {
        note("limited to \(limit) candidate(s) by --mulein-ostwald-adapt-limit")
        emitted = Array(emitted.prefix(limit))
    }

    let formatter = ISO8601DateFormatter()
    let manifestOut = QuarantineManifest(
        target: manifest.targetID,
        ciphertext: manifest.ciphertext,
        generatedAt: formatter.string(from: Date()),
        sourceFixture: ledgerPath,
        softBar: NearMissQuarantine.defaultSoftBar(),
        candidates: emitted
    )
    do {
        try NearMissQuarantine.writeManifest(manifestOut, to: outputPath)
    } catch {
        throw MuleinFutureMetalError.commandFailed(
            "could not write quarantine manifest: \(error)"
        )
    }

    let skipEncoder = JSONEncoder()
    skipEncoder.outputFormatting = [.sortedKeys]
    var skipPayload = Data()
    for record in skipRecords {
        guard var line = try? skipEncoder.encode(record) else { continue }
        line.append(0x0a)
        skipPayload.append(line)
    }
    do {
        let skipURL = URL(fileURLWithPath: skipPath)
        try FileManager.default.createDirectory(
            at: skipURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try skipPayload.write(to: skipURL, options: .atomic)
    } catch {
        throw MuleinFutureMetalError.commandFailed("could not write skip ledger: \(error)")
    }

    note("=== Adapter summary ===")
    note("queued identity-repair : \(repairRefs.count)")
    note("emitted to escalate    : \(emitted.count)")
    for reason in [
        MuleinOstwaldAdaptSkipReason.splitMenu,
        .pairCountBelowFloor,
        .duplicateShellLiveHash,
        .emptyForcedPlugs
    ] {
        if let count = skipCounts[reason], count > 0 {
            note("skipped \(reason.rawValue): \(count)")
        }
    }
    note("wrote quarantine       : \(outputPath)")
    note("wrote skips            : \(skipPath)")
    note("")
    note("This is not a climb and not a decrypt. Feed the quarantine to")
    note("  --ostwald-escalate \(outputPath)")
    if includeGappedPostGap {
        note("Identity rows use the dense walker; post-gap rows carry leadingHoles = δ.")
    } else {
        note("if you want the dense 72-letter walker to grade these forced plugs.")
        note("Do not point that walker at post-gap repairs.")
    }
    if printProgress { fflush(stdout) }

    let queuedIdentity = repairRefs.filter {
        $0.candidate.family == MuleinOstwaldAdapt.identityFamily
    }.count
    let queuedGapped = repairRefs.count - queuedIdentity
    return MuleinOstwaldAdaptResult(
        ledgerSHA256: ledgerDigest,
        compiledOrdinals: workByOrdinal.count,
        totalCandidates: totalCandidates,
        queuedIdentityRepairs: queuedIdentity,
        queuedGappedRepairs: queuedGapped,
        emitted: emitted.count,
        skipCounts: skipCounts,
        outputPath: outputPath,
        skipPath: skipPath
    )
}

private func muleinOstwaldHashAndScan(
    path: String,
    decoder: JSONDecoder,
    identity: inout MuleinOstwaldAdaptRunIdentity?,
    totalCandidates: inout Int,
    repairRefs: inout [OstwaldAdaptRepairRef],
    skipCounts: inout [MuleinOstwaldAdaptSkipReason: Int],
    skipRecords: inout [MuleinOstwaldAdaptSkipRecord],
    includeIdentity: Bool,
    includeGappedPostGap: Bool
) throws -> String {
    guard let handle = FileHandle(forReadingAtPath: path) else {
        throw MuleinFutureMetalError.commandFailed("could not read campaign ledger at \(path)")
    }
    defer { try? handle.close() }

    var hasher = SHA256()
    var buffer = Data()
    var lineNumber = 0

    func consumeCompleteLines(final: Bool) throws {
        while true {
            guard let newline = buffer.firstIndex(of: 0x0a) else {
                if final, !buffer.isEmpty {
                    try acceptLine(buffer, number: lineNumber + 1)
                    buffer.removeAll(keepingCapacity: true)
                }
                return
            }
            let line = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            if line.isEmpty { continue }
            try acceptLine(line, number: lineNumber + 1)
        }
    }

    func acceptLine(_ line: Data, number: Int) throws {
        lineNumber = number
        guard let row = try? decoder.decode(MuleinOstwaldAdaptRow.self, from: line) else {
            throw MuleinFutureMetalError.commandFailed(
                "malformed ledger row at line \(number)"
            )
        }
        if let existing = identity {
            guard row.run == existing else {
                throw MuleinFutureMetalError.commandFailed(
                    "campaign ledger mixes run identities — refusing to adapt"
                )
            }
        } else {
            identity = row.run
        }
        for candidate in row.candidates {
            totalCandidates += 1
            if candidate.family != row.futureFamily {
                throw MuleinFutureMetalError.commandFailed(
                    "candidate family disagrees with row futureFamily at line \(number)"
                )
            }
            let droppedEmpty = candidate.droppedEdgeIDs.isEmpty
            let disposition = MuleinOstwaldAdapt.preHostDisposition(
                family: candidate.family,
                exact: candidate.exact,
                droppedEmpty: droppedEmpty,
                gappedPostGap: includeGappedPostGap
            )
            switch disposition {
            case .identityRepair:
                if includeIdentity {
                    repairRefs.append(OstwaldAdaptRepairRef(row: row, candidate: candidate))
                } else {
                    skipCounts[.familyNotRequested, default: 0] += 1
                    skipRecords.append(
                        muleinOstwaldSkip(row: row, candidate: candidate,
                                          reason: .familyNotRequested)
                    )
                }
            case .postGapGappedRepair:
                repairRefs.append(OstwaldAdaptRepairRef(row: row, candidate: candidate))
            case .exactIdentityAlreadyScored:
                skipCounts[.exactIdentityAlreadyScored, default: 0] += 1
                skipRecords.append(
                    muleinOstwaldSkip(row: row, candidate: candidate,
                                      reason: .exactIdentityAlreadyScored)
                )
            case .exactPostGapAlreadyAdjudicated:
                skipCounts[.exactPostGapAlreadyAdjudicated, default: 0] += 1
                skipRecords.append(
                    muleinOstwaldSkip(row: row, candidate: candidate,
                                      reason: .exactPostGapAlreadyAdjudicated)
                )
            case .postGapDenseOstwaldIllegal:
                skipCounts[.postGapDenseOstwaldIllegal, default: 0] += 1
                skipRecords.append(
                    muleinOstwaldSkip(row: row, candidate: candidate,
                                      reason: .postGapDenseOstwaldIllegal)
                )
            case .inconsistentExactDrop:
                throw MuleinFutureMetalError.commandFailed(
                    "candidate exact/drop provenance is inconsistent at line \(number)"
                )
            }
        }
    }

    while true {
        let chunk = try handle.read(upToCount: 1 << 20)
        guard let chunk, !chunk.isEmpty else { break }
        hasher.update(data: chunk)
        buffer.append(chunk)
        try consumeCompleteLines(final: false)
    }
    try consumeCompleteLines(final: true)
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

private func muleinOstwaldSkip(
    row: MuleinOstwaldAdaptRow,
    candidate: MuleinOstwaldAdaptCandidate,
    reason: MuleinOstwaldAdaptSkipReason
) -> MuleinOstwaldAdaptSkipRecord {
    MuleinOstwaldAdaptSkipRecord(
        schemaVersion: muleinOstwaldAdaptSchemaVersion,
        kind: "mulein-ostwald-adapt-skip",
        reason: reason.rawValue,
        chunkID: row.chunkID,
        shell: "\(row.ukw)/\(row.greek)/\(row.wheelOrder)/\(row.rings)",
        futureOrdinal: candidate.futureOrdinal,
        futureID: candidate.futureID,
        family: candidate.family,
        settingLane: candidate.settingLane,
        positions: candidate.positions,
        seed: candidate.seed,
        exact: candidate.exact,
        pairCount: candidate.pairCount,
        liveHashHex: candidate.liveHashHex,
        scope: muleinOstwaldAdaptScope
    )
}
