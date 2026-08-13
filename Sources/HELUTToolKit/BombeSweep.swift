import Foundation
import HELUTCore
import HELUTCLI

// MARK: - Welchman bombe driver
//
// Rehearsal first, sweep second. The rehearsal runs the bombe against P1030684,
// whose key is known, and reports three numbers that decide whether the sweep is
// worth starting at all: does the true setting survive, is the deduced stecker
// correct, and what fraction of wrong settings does the menu actually kill.

// MARK: Menu set

struct CribMenuSet {
    let ciphertext: [Int]
    let menus: [BombeMenu]
    let source: String
}

private struct MenuFile: Decodable {
    struct Crib: Decodable {
        let text: String
        let messages: Int
        let offsets: [Int]
    }
    let target: String
    let ciphertext: String
    let cribs: [Crib]
}

private struct CorpusFile: Decodable {
    struct Message: Decodable {
        let id: String
        let plaintext: String?
        let ciphertext: String?
    }
    let messages: [Message]
}

func loadCribMenus(path: String) -> CribMenuSet? {
    guard let data = FileManager.default.contents(atPath: path),
          let file = try? JSONDecoder().decode(MenuFile.self, from: data) else {
        return nil
    }
    let ciphertext = EnigmaAlphabet.normalize(file.ciphertext)
    var menus: [BombeMenu] = []
    for crib in file.cribs {
        for offset in crib.offsets {
            if let menu = BombeMenuBuilder.menu(
                crib: crib.text, offset: offset, ciphertext: ciphertext
            ) {
                menus.append(menu)
            }
        }
    }
    // Shortcut #2: rank by deduction power on *this* ciphertext, not by corpus popularity.
    menus.sort(by: byLoopPower)
    return CribMenuSet(ciphertext: ciphertext, menus: menus, source: path)
}

/// Offset-0 openings mined from broken U-534 decrypts (shortcut #1).
/// Shared openings (≥2 messages) first; unique 24-letter openings fill out the set.
func loadOpeningMenus(
    corpusPath: String,
    ciphertext: [Int],
    minLength: Int,
    maxLength: Int = 24
) -> [BombeMenu] {
    guard let data = FileManager.default.contents(atPath: corpusPath),
          let file = try? JSONDecoder().decode(CorpusFile.self, from: data) else {
        return []
    }
    let upper = min(maxLength, ciphertext.count)
    guard minLength <= upper else { return [] }

    var carriers: [String: Set<String>] = [:]
    for message in file.messages {
        guard let plaintext = message.plaintext, plaintext.count >= minLength else { continue }
        for length in minLength...min(plaintext.count, upper) {
            carriers[String(plaintext.prefix(length)), default: []].insert(message.id)
        }
    }

    func build(_ texts: [String]) -> [BombeMenu] {
        var menus: [BombeMenu] = []
        for text in texts {
            if let menu = BombeMenuBuilder.menu(crib: text, offset: 0, ciphertext: ciphertext) {
                menus.append(menu)
            }
        }
        return maximalMenus(menus).sorted(by: byLoopPower)
    }

    let shared = carriers.filter { $0.value.count >= 2 }.map(\.key)
    let uniqueLong = carriers.filter { $0.value.count == 1 && $0.key.count == upper }.map(\.key)
    // Shared register first (the actual shortcut), then unique long openings.
    let sharedMenus = build(shared)
    let uniqueMenus = build(uniqueLong).filter { candidate in
        sharedMenus.allSatisfy { menusAreIndependent($0, candidate) }
    }
    // A handful of unique long openings; confirmation partners supply the rest.
    return sharedMenus + Array(uniqueMenus.prefix(4))
}

/// Drop menus whose crib is a proper substring of another menu's crib at the same offset.
func maximalMenus(_ menus: [BombeMenu]) -> [BombeMenu] {
    let ordered = menus.sorted { $0.crib.count > $1.crib.count }
    var kept: [BombeMenu] = []
    for menu in ordered {
        let dominated = kept.contains {
            $0.offset == menu.offset && $0.crib.contains(menu.crib)
        }
        if !dominated { kept.append(menu) }
    }
    return kept
}

func menusAreIndependent(_ a: BombeMenu, _ b: BombeMenu) -> Bool {
    if a.offset != b.offset { return true }
    return !a.crib.contains(b.crib) && !b.crib.contains(a.crib)
}

/// Select menus for a run: openings (± loop-ranked partners) or pure loop ranking.
func selectMenus(config: BombeSweepConfig, full: CribMenuSet) -> (menus: [BombeMenu], openingCount: Int) {
    if !config.menuFilter.isEmpty {
        let opening = loadOpeningMenus(
            corpusPath: resolveCorpusPath(),
            ciphertext: full.ciphertext,
            minLength: config.minOpeningLength
        )
        // "CRIB" matches any placement; "CRIB@12" pins one.
        let parts = config.menuFilter.split(separator: "@", maxSplits: 1)
        let text = String(parts[0])
        let wanted = parts.count > 1 ? Int(parts[1]) : nil
        let matched = (opening + full.menus).filter { menu in
            menu.crib.contains(text) && (wanted == nil || menu.offset == wanted!)
        }
        return (Array(matched.sorted(by: byLoopPower).prefix(max(config.menuCount, 1))), matched.count)
    }
    if config.openingsOnly {
        let openings = loadOpeningMenus(
            corpusPath: resolveCorpusPath(),
            ciphertext: full.ciphertext,
            minLength: config.minOpeningLength
        )
        let partners = full.menus.filter { candidate in
            openings.allSatisfy { menusAreIndependent($0, candidate) }
        }
        // Never drop openings when capping — trim partners first.
        let partnerBudget: Int
        if config.menuCount > 0 && config.menuCount > openings.count {
            partnerBudget = min(config.confirmPartners, config.menuCount - openings.count)
        } else if config.menuCount > 0 {
            partnerBudget = 0
        } else {
            partnerBudget = config.confirmPartners
        }
        let chosenPartners = Array(partners.prefix(max(partnerBudget, config.confirmMenus > 1 ? config.confirmPartners : 0)))
        // Run highest-loop first, but keep every opening in the set.
        let chosen = (openings + chosenPartners).sorted(by: byLoopPower)
        return (chosen, openings.count)
    }
    return (Array(full.menus.prefix(config.menuCount > 0 ? config.menuCount : full.menus.count)), 0)
}

func resolveMenuPath() -> String {
    firstExisting([
        "Fixtures/p1030680_menus.json",
        FileManager.default.currentDirectoryPath + "/Fixtures/p1030680_menus.json"
    ]) ?? "Fixtures/p1030680_menus.json"
}

func resolveCorpusPath() -> String {
    firstExisting([
        "Fixtures/u534_corpus.json",
        FileManager.default.currentDirectoryPath + "/Fixtures/u534_corpus.json"
    ]) ?? "Fixtures/u534_corpus.json"
}

private func firstExisting(_ paths: [String]) -> String? {
    paths.first { FileManager.default.fileExists(atPath: $0) }
}

private func byLoopPower(_ a: BombeMenu, _ b: BombeMenu) -> Bool {
    (a.loops, a.edgeCount, a.crib.count) > (b.loops, b.edgeCount, b.crib.count)
}

// MARK: Known-key control

/// P1030684 — Potsdam, 1 May 1945. Key recovered, so the bombe can be graded.
enum ControlMessageP1030684 {
    static let ciphertext =
        "RFBYWKIKELDCHBSXUNFJFSNRRVFWASXYLQCQFADYJXNTBMVLRDCGULOWHTBGWUSSOQHGAY"
        + "EDKMJDNGVZNZFOXFKMIBKQNXFDWFIVGCYMJVQCKYQFBHYKZSCJ"
    static let plaintext =
        "VVVUUUVIRSOBENNULEINSXXMITUUUVIRSIBENNULZWOYVIRSIBENNULDREIYZWODREISEC"
        + "HSEINSYZWODREIDREIACHTEINSDREIOITNACHWZSTENPASSIRT"
    static let rings = "AACU"
    static let positions = "VYAA"
    static let plugPairs = ["CH", "EJ", "NV", "OU", "TY", "LG", "SZ", "PK", "DI", "QB"]

    static func bombe(maxPlugs: Int = 10) -> WelchmanBombe {
        WelchmanBombe(
            greek: EnigmaM4Warehouse.gamma,
            left: EnigmaWarehouse.rotorIV,
            middle: EnigmaWarehouse.rotorIII,
            right: EnigmaWarehouse.rotorVIII,
            reflector: EnigmaM4Warehouse.thinB,
            rings: EnigmaM4Key.rings(fromLetters: rings),
            maxPlugs: maxPlugs
        )
    }

    static var trueStecker: [Int] {
        var table = Array(0..<26)
        for pair in plugPairs {
            let letters = Array(pair)
            let a = EnigmaAlphabet.index(letters[0])
            let b = EnigmaAlphabet.index(letters[1])
            table[a] = b
            table[b] = a
        }
        return table
    }
}

// MARK: Rehearsal

func runWelchmanRehearsal() {
    let cipher = EnigmaAlphabet.normalize(ControlMessageP1030684.ciphertext)
    let plain = EnigmaAlphabet.normalize(ControlMessageP1030684.plaintext)
    let bombe = ControlMessageP1030684.bombe()
    let truth = EnigmaM4Key.positions(fromLetters: ControlMessageP1030684.positions)
    let trueStecker = ControlMessageP1030684.trueStecker

    print("=== Welchman diagonal board — known-key rehearsal (P1030684) ===")
    print("wheel order IV-III-VIII, Greek γ, UKW B, rings \(ControlMessageP1030684.rings)")
    print("true message key \(ControlMessageP1030684.positions), "
        + "10 plugs \(ControlMessageP1030684.plugPairs.joined(separator: " "))")
    print()

    // Crib lengths spanning what we actually mined for P1030680 (6–10 letters) up to
    // the long menus a bombe operator would have preferred.
    let lengths = [6, 8, 9, 10, 12, 16, 20, 25]
    print("Each row sweeps the full 26⁴ position space for the true wheel order.")
    print("'survivors' counts settings the menu could not kill — the sweep's output volume.")
    print()
    print("crib                       len edges loops | truth | stecker        | "
        + "survivors/26⁴ | proj. full space")
    print(String(repeating: "-", count: 118))

    for length in lengths where length <= plain.count {
        let cribText = EnigmaAlphabet.string(from: Array(plain[0..<length]))
        guard let menu = BombeMenuBuilder.menu(crib: cribText, offset: 0, ciphertext: cipher)
        else { continue }

        // 1. Does the true setting survive, and is the forced stecker right?
        let stops = bombe.test(menu: menu, start: truth)
        var graded = "no stop"
        var verdict = "KILLED"
        if let stop = stops.first(where: { candidate in
            (0..<26).allSatisfy {
                !candidate.determined[$0] || candidate.stecker[$0] == trueStecker[$0]
            }
        }) {
            verdict = "kept  "
            graded = "\((0..<26).filter { stop.determined[$0] }.count)/26 correct"
        } else if !stops.isEmpty {
            graded = "\(stops.count) stops, wrong"
        }

        // 2. Exhaustive survivor count over every position for this shell.
        let survivors = LockedCounter()
        DispatchQueue.concurrentPerform(iterations: 26) { g in
            var local = 0
            for l in 0..<26 {
                for m in 0..<26 {
                    for r in 0..<26 where !bombe.isDead(menu: menu, start: (g, l, m, r)) {
                        local += 1
                    }
                }
            }
            survivors.add(local)
        }
        let kept = survivors.value
        // 336 wheel orders × 2 Greek × 2 UKW share this per-shell survivor rate.
        let projected = Double(kept) * 1344.0

        let padded = cribText.padding(toLength: 26, withPad: " ", startingAt: 0)
        print(String(format: "%@ %3d %5d %5d | %@ | %-14@ | %13d | %.3g",
                     padded, length, menu.edgeCount, menu.loops, verdict,
                     graded as NSString, kept, projected))
    }

    print()
    print("Projection assumes the per-shell survivor rate holds across all 1344 shells.")
    print("A survivor is a stop, not a break: each still needs its plaintext read.")
    print()

    verifyMetalAgainstHost(cipher: cipher, plain: plain, bombe: bombe, truth: truth)
    validateDiscriminator(cipher: cipher, plain: plain, bombe: bombe, truth: truth)
}

/// Grade the discriminator where the answer is known: an 18-letter menu (the same
/// length as the only P1030680 crib that stops) on P1030684. The true key must not
/// merely survive — it must come out ranked first, ahead of its ghosts.
private func validateDiscriminator(
    cipher: [Int],
    plain: [Int],
    bombe: WelchmanBombe,
    truth: (Int, Int, Int, Int)
) {
    print()
    print("=== Discriminator rehearsal (18-letter menu, known key) ===")
    let cribText = EnigmaAlphabet.string(from: Array(plain[0..<18]))
    guard let menu = BombeMenuBuilder.menu(crib: cribText, offset: 0, ciphertext: cipher) else {
        print("  could not build an 18-letter control menu")
        return
    }
    print("  menu \(menu.description)")

    // Collect every survivor over the 26⁴ window space at the true shell.
    var stops: [SweepStop] = []
    for g in 0..<26 {
        for l in 0..<26 {
            for m in 0..<26 {
                for r in 0..<26 {
                    let start = (g, l, m, r)
                    for stop in bombe.test(menu: menu, start: start) {
                        stops.append(
                            SweepStop(
                                ukw: "B", greek: "gamma", wheelOrder: "IV-III-VIII",
                                menu: menu,
                                rings: EnigmaM4Key.rings(
                                    fromLetters: ControlMessageP1030684.rings
                                ),
                                stop: stop,
                                ciphertext: cipher
                            )
                        )
                    }
                }
            }
        }
    }
    print("  survivors at the true shell: \(stops.count)")
    guard !stops.isEmpty else { return }

    let ranked = PostBombeDiscriminator.rank(stops: stops, ciphertext: cipher).candidates
    guard let winner = ranked.first else { return }

    let truthString = EnigmaAlphabet.string(from: [truth.0, truth.1, truth.2, truth.3])
    let rankOfTruth = ranked.firstIndex { $0.messageKey == truthString }.map { $0 + 1 }
    let exactCount = ranked.filter(\.cribExact).count

    print(String(format: "  crib reproduced exactly by %d/%d after completion",
                 exactCount, ranked.count))
    print(String(format: "  German %.3f / noise %.3f / threshold %.3f / IC floor %.3f",
                 PostBombeDiscriminator.germanReference,
                 PostBombeDiscriminator.noiseReference,
                 PostBombeDiscriminator.breakThreshold,
                 PostBombeDiscriminator.icFloor))
    for (index, candidate) in ranked.prefix(5).enumerated() {
        let mark = candidate.messageKey == truthString ? " <-- TRUE KEY" : ""
        print(String(format: "  %2d. %@ IC %.3f tail %8.3f  crib %@  %@%@",
                     index + 1, candidate.messageKey, candidate.ic, candidate.tailScore,
                     candidate.cribExact ? "ok " : "BAD",
                     String(candidate.plaintext.prefix(40)), mark))
    }

    if let rankOfTruth {
        print("  true key ranked #\(rankOfTruth) of \(ranked.count)")
        if rankOfTruth == 1 && PostBombeDiscriminator.isBreak(winner) {
            print("  PASS — the discriminator picks the real message out of its ghosts")
            // Fire the real banner on a known message, so the path that matters most
            // is exercised on every rehearsal rather than first run in anger.
            PostBombeDiscriminator.announceBreak(winner)
        } else if rankOfTruth == 1 {
            print("  WEAK — correct order, but the winner fails the break gate "
                + "(IC / tail)")
        } else {
            print("  FAIL — a ghost outranks the true key at this crib length")
        }
    } else {
        print("  FAIL — the true key is not among the survivors")
    }
}

/// The GPU bombe is only useful if it decides identically to the validated host one.
/// This sweeps the same 26⁴ space both ways and demands an exact match, lane for lane.
private func verifyMetalAgainstHost(
    cipher: [Int],
    plain: [Int],
    bombe: WelchmanBombe,
    truth: (Int, Int, Int, Int)
) {
    print("=== GPU cross-check (must agree with the host engine exactly) ===")
    guard let engine = WelchmanMetalEngine() else {
        print("  no Metal device — host engine only")
        return
    }

    let cribText = EnigmaAlphabet.string(from: Array(plain[0..<12]))
    guard let menu = BombeMenuBuilder.menu(crib: cribText, offset: 0, ciphertext: cipher) else {
        print("  could not build the cross-check menu")
        return
    }

    let started = Date()
    guard let survivors = engine.sweep(
        menu: menu,
        greek: EnigmaM4Warehouse.gamma,
        left: EnigmaWarehouse.rotorIV,
        middle: EnigmaWarehouse.rotorIII,
        right: EnigmaWarehouse.rotorVIII,
        reflector: EnigmaM4Warehouse.thinB,
        rings: EnigmaM4Key.rings(fromLetters: ControlMessageP1030684.rings)
    ) else {
        print("  GPU sweep failed")
        return
    }
    let gpuElapsed = Date().timeIntervalSince(started)

    var gpuAlive = 0
    for mask in survivors where mask != 0 { gpuAlive += 1 }

    let hostStarted = Date()
    let hostCounter = LockedCounter()
    let mismatches = LockedCounter()
    DispatchQueue.concurrentPerform(iterations: 26) { g in
        var alive = 0
        var bad = 0
        for l in 0..<26 {
            for m in 0..<26 {
                for r in 0..<26 {
                    let lane = g * 17576 + l * 676 + m * 26 + r
                    let hostStops = bombe.test(menu: menu, start: (g, l, m, r))
                    // Host applies the ten-plug rule; compare the raw logic instead.
                    let hostAlive = !bombe.isDead(menu: menu, start: (g, l, m, r))
                    if hostAlive { alive += 1 }
                    if hostAlive != (survivors[lane] != 0) { bad += 1 }
                    _ = hostStops
                }
            }
        }
        hostCounter.add(alive)
        mismatches.add(bad)
    }
    let hostElapsed = Date().timeIntervalSince(hostStarted)

    let trueLane = truth.0 * 17576 + truth.1 * 676 + truth.2 * 26 + truth.3
    print("  menu       \(menu.description)")
    print(String(format: "  GPU  %7d survivors in %.2fs (%.2fM settings/s)",
                 gpuAlive, gpuElapsed, Double(WelchmanMetalEngine.laneCount) / gpuElapsed / 1e6))
    print(String(format: "  host %7d survivors in %.2fs (%.2fM settings/s)",
                 hostCounter.value, hostElapsed,
                 Double(WelchmanMetalEngine.laneCount) / hostElapsed / 1e6))
    print("  lane mismatches: \(mismatches.value)")
    print("  true setting \(EnigmaAlphabet.string(from: [truth.0, truth.1, truth.2, truth.3])) "
        + "survives on GPU: \(survivors[trueLane] != 0)")
    if mismatches.value == 0 {
        print(String(format: "  AGREEMENT EXACT — GPU is %.0fx the host sweep rate",
                     hostElapsed / gpuElapsed))
    } else {
        print("  DISAGREEMENT — do not trust the GPU path until this is zero")
    }
}

// MARK: Sweep

struct BombeSweepConfig {
    var menuCount = 1
    var wheelOrders: [(EnigmaRotorSpec, EnigmaRotorSpec, EnigmaRotorSpec)] =
        M4ThetisAttack.allWheelOrders()
    var maxPlugs = 10
    var reportLimit = 20
    /// Sweep the fast-wheel Ringstellung as well. The middle and greek rings are
    /// absorbed into their window positions, and the left ring never gates a
    /// turnover, but the right ring sets *when* the middle wheel steps — so a menu
    /// long enough to span a turnover needs all 26 phases to be complete.
    var sweepRightRing = false
    /// How many GPU shells to keep in flight. 4 is usually enough to hide host drain.
    var pipelineDepth = WelchmanMetalEngine.defaultDepth
    /// Prefer offset-0 message openings (≥ minOpeningLength) from the U-534 corpus,
    /// then fill remaining slots with highest-loop independent menus.
    var openingsOnly = false
    /// Run only menus whose crib contains this text — for re-testing one stop-producing crib.
    var menuFilter = ""
    var minOpeningLength = 16
    /// Drop menus shorter than this. 14-letter cribs sit under unicity and produced
    /// the −4.070 false positive; 16 is the rehearsal length that isolates a true key.
    var minCribLength = 16
    /// 1-based index into the selected list to resume from (`--bombe-from 628`
    /// skips menus 1…627). Applied before the length filter so log indices match.
    var resumeFrom = 1
    /// A shell is only reported when this many *independent* menus stop on it.
    /// Nested cribs (one a prefix of another at the same offset) count as one.
    var confirmMenus = 1
    /// Extra high-loop menus to pull in as confirmation partners under openings mode.
    var confirmPartners = 8
    /// Menu fixture to attack. Empty means the P1030680 catalog. Pointing this at a
    /// known-key control fixture grades the sweep itself instead of swapping files.
    var fixturePath = ""
    /// When non-nil, physical soft-band near-misses are appended to this quarantine JSON
    /// for Stochastic Bombe seeding (`--hybrid-quarantine`). Empty string disables.
    var quarantinePath: String? = NearMissQuarantine.defaultPath
    /// Soft tail margin below the strict break threshold (default 0.4 → floor −4.0).
    var quarantineSoftTailMargin = NearMissQuarantine.softTailMargin
    /// Soft IC floor for quarantine (default 0.048).
    var quarantineSoftICFloor = NearMissQuarantine.softICFloor
}

func runWelchmanBombe(config: BombeSweepConfig = BombeSweepConfig()) {
    let path = config.fixturePath.isEmpty ? resolveMenuPath() : config.fixturePath
    guard let set = loadCribMenus(path: path) else {
        print("could not load menus from \(path)")
        print("run: python3 Scripts/crib_mine.py Fixtures/u534_corpus.json "
            + "--emit Fixtures/p1030680_menus.json")
        return
    }

    guard let engine = WelchmanMetalEngine(depth: config.pipelineDepth) else {
        print("no Metal device available — the host engine is 100x slower; "
            + "use --welchman-rehearsal to measure it")
        return
    }

    let selection = selectMenus(config: config, full: set)
    let catalog = selection.menus
    guard !catalog.isEmpty else {
        print("no menus selected — check --bombe-openings / corpus / menu fixture")
        return
    }

    // Resume uses the catalog's original 1-based indices (matching prior log lines),
    // then the length filter drops short cribs from whatever remains.
    let resumeFrom = max(config.resumeFrom, 1)
    let afterResume = catalog.enumerated().compactMap { index, menu -> (Int, BombeMenu)? in
        let original = index + 1
        guard original >= resumeFrom else { return nil }
        return (original, menu)
    }
    let chosen = afterResume.filter { $0.1.crib.count >= config.minCribLength }
    let droppedShort = afterResume.count - chosen.count
    guard !chosen.isEmpty else {
        print("no menus left after --bombe-from \(resumeFrom) / min crib \(config.minCribLength)")
        return
    }

    print("=== Welchman diagonal board — P1030680 ===")
    print("fixture: \(set.source) (\(set.menus.count) loop-ranked placements)")
    if config.openingsOnly {
        print("mode: openings (≥\(config.minOpeningLength)…24 @0) + \(config.confirmPartners) "
            + "loop-ranked confirmation partners")
        print("selected \(catalog.count) menus "
            + "(\(selection.openingCount) openings, confirm≥\(config.confirmMenus) independent)")
    } else {
        print("mode: loop-ranked (loops, edges); confirm≥\(config.confirmMenus) independent")
        print("selected \(catalog.count) of \(set.menus.count)")
    }
    print("min crib length: \(config.minCribLength)"
        + (droppedShort > 0 ? " (dropped \(droppedShort) shorter from the remaining set)" : ""))
    if resumeFrom > 1 {
        print("resuming from menu \(resumeFrom) of \(catalog.count) "
            + "(skipping \(resumeFrom - 1) already done)")
    }
    print("running \(chosen.count) menus, highest deduction power first:")
    for item in chosen.prefix(12) {
        print("  [\(item.0)] \(item.1.description)")
    }
    if chosen.count > 12 { print("  … \(chosen.count - 12) more") }

    let ringVariants: [(Int, Int, Int, Int)] = config.sweepRightRing
        ? (0..<26).map { (0, 0, 0, $0) }
        : [(0, 0, 0, 0)]
    let shellsPerMenu = config.wheelOrders.count * 4 * ringVariants.count
    let settingsPerMenu = Double(shellsPerMenu) * Double(WelchmanMetalEngine.laneCount)
    print(String(format: "shells/menu: %d (%d WO × 2 Greek × 2 UKW × %d ring) → %.3g settings",
                 shellsPerMenu, config.wheelOrders.count, ringVariants.count, settingsPerMenu))
    print("GPU pipeline depth: \(engine.depth) shells in flight")
    print(String(format: "break threshold: %.3f  IC floor: %.3f  (German %.3f / noise %.3f)",
                 PostBombeDiscriminator.breakThreshold,
                 PostBombeDiscriminator.icFloor,
                 PostBombeDiscriminator.germanReference,
                 PostBombeDiscriminator.noiseReference))
    if config.sweepRightRing {
        // Sweeping the right ring covers every phase of the right-wheel turnover, so
        // middle-wheel stepping is correct for all 26. The middle ring stays pinned at
        // A, which is only exact while the middle wheel itself does not turn over in
        // span — so a key that steps the left wheel mid-crib is still out of reach.
        let longest = chosen.map { $0.1.edgeCount }.max() ?? 0
        let steps = longest / 26 + 1
        print("right ring swept: every right-wheel turnover phase covered")
        print(String(format: "residual gap: middle ring pinned A, so keys whose middle "
                     + "wheel turns over inside a %d-letter span (~%.0f%% for 1 notch, "
                     + "~%.0f%% for 2) are not covered",
                     longest, Double(steps) / 26.0 * 100, Double(2 * steps) / 26.0 * 100))
    } else {
        let longest = chosen.map { $0.1.edgeCount }.max() ?? 0
        let free = max(0, 26 - longest)
        print(String(format: "rings AAAA: exhaustive over turnover-free spans, which is "
                     + "%d/26 (%.0f%%) of keys at %d letters. --bombe-ring-sweep covers "
                     + "the rest at 26x cost.",
                     free, Double(free) / 26.0 * 100, longest))
    }
    let etaSeconds = settingsPerMenu * Double(chosen.count) / 50e6
    print(String(format: "ETA floor (~50M/s): %.1f min", etaSeconds / 60))
    print()
    fflush(stdout)

    let greeks: [(String, EnigmaRotorSpec)] = [
        ("beta", EnigmaM4Warehouse.beta), ("gamma", EnigmaM4Warehouse.gamma)
    ]
    let reflectors: [(String, [Int])] = [
        ("B", EnigmaM4Warehouse.thinB), ("C", EnigmaM4Warehouse.thinC)
    ]

    // Shortcut #3: accumulate stops by shell; report only multi-menu agreements.
    let agreements = LockedShellAgreements()
    /// Physical shells admitted by a unicity-safe (≥16) menu. Short challengers under
    /// confirm≥2 never GPU-sweep: they only re-test these shells on the host. A true
    /// key still survives — its ≥16 body locks the shell, then the short header
    /// confirms it. What dies is the 10M–40M ghost-completion flood that stalled arm 2.
    var lockedAnchors: [ShellID: LockedAnchorShell] = [:]
    let anchorMinLength = 16
    var totalStops = 0
    var totalCompletions = 0
    var settingsDone = 0
    var shellsDone = 0
    let started = Date()
    var bestSoFar: DiscriminatedCandidate?
    var breakFound: DiscriminatedCandidate?
    var quarantineBag: [QuarantineCandidate] = []
    let softBar = QuarantineSoftBar(
        softTailFloor: PostBombeDiscriminator.breakThreshold - config.quarantineSoftTailMargin,
        softICFloor: config.quarantineSoftICFloor,
        strictTailFloor: PostBombeDiscriminator.breakThreshold,
        strictICFloor: PostBombeDiscriminator.icFloor
    )
    let quarantineSource = path
    if let qPath = config.quarantinePath, !qPath.isEmpty {
        print(String(
            format: "quarantine: soft IC≥%.3f / tail>%.3f (strict IC≥%.3f / tail>%.3f) → %@",
            softBar.softICFloor,
            softBar.softTailFloor,
            softBar.strictICFloor,
            softBar.strictTailFloor,
            qPath
        ))
        fflush(stdout)
    }
    /// Physically valid stops retained per menu. A guard, not a filter: a legitimate
    /// menu produces a handful, so hitting this cap means the menu was too weak to
    /// be worth reading anyway.
    let physicalCap = 5_000
    let overlong = chosen.filter { $0.1.edgeCount > welchmanMaxEdges }
    let runnableRaw = chosen.filter { $0.1.edgeCount <= welchmanMaxEdges }
    // Confirm mode: every unicity-safe menu before any short challenger, so the
    // locked-anchor set is complete before challengers run.
    let runnable: [(Int, BombeMenu)]
    if config.confirmMenus > 1 {
        let anchors = runnableRaw.filter { $0.1.crib.count >= anchorMinLength }
        let challengers = runnableRaw.filter { $0.1.crib.count < anchorMinLength }
        runnable = anchors + challengers
        print("confirm mode: \(anchors.count) anchor menus (≥\(anchorMinLength)), "
            + "\(challengers.count) short challengers (host re-test of locked shells only)")
    } else {
        runnable = runnableRaw
    }
    if !overlong.isEmpty {
        print("WARNING: \(overlong.count) menu(s) exceed Metal edge cap "
            + "(\(welchmanMaxEdges)) and will not be tested:")
        for (originalIndex, menu) in overlong.prefix(12) {
            print(String(format: "  [%d] %@ — %d edges",
                         originalIndex, menu.description as NSString, menu.edgeCount))
        }
        if overlong.count > 12 { print("  … \(overlong.count - 12) more") }
        print()
    }
    // ETA covers GPU anchor work only; challengers are O(|locked shells|) on host.
    let anchorRunnable = runnable.filter { $0.1.crib.count >= anchorMinLength || config.confirmMenus <= 1 }
    let runnableShells = shellsPerMenu * anchorRunnable.count
    let etaSecondsRunnable = settingsPerMenu * Double(anchorRunnable.count) / 50e6
    if runnable.count != chosen.count || config.confirmMenus > 1 {
        print(String(format: "runnable: %d menus (%d GPU) → ETA floor %.1f min",
                     runnable.count, anchorRunnable.count, etaSecondsRunnable / 60))
        print()
    }

    for (runIndex, item) in runnable.enumerated() {
        let originalIndex = item.0
        let menu = item.1
        let label = String(format: "[%d/%d·%d]", originalIndex, catalog.count, runIndex + 1)
        let isChallenger = config.confirmMenus > 1 && menu.crib.count < anchorMinLength

        var physical: [SweepStop] = []
        var rawStops = 0

        if isChallenger {
            if lockedAnchors.isEmpty {
                print(String(format: "  %@ %-44@ skipped — no locked anchor shells",
                             label, menu.description as NSString))
                fflush(stdout)
                continue
            }
            // Host-only: re-test each locked shell against this short menu.
            for anchor in lockedAnchors.values {
                let bombe = WelchmanBombe(
                    greek: anchor.greek, left: anchor.left,
                    middle: anchor.middle, right: anchor.right,
                    reflector: anchor.reflector, rings: anchor.rings,
                    maxPlugs: config.maxPlugs
                )
                let stops = bombe.test(menu: menu, start: anchor.positions)
                rawStops += stops.count
                for stop in stops {
                    let sweepStop = SweepStop(
                        ukw: anchor.ukwName, greek: anchor.greekName,
                        wheelOrder: anchor.wheelOrder,
                        menu: menu,
                        rings: anchor.rings,
                        stop: stop,
                        ciphertext: set.ciphertext
                    )
                    guard !PostBombeDiscriminator.completions(
                        for: sweepStop, maxPlugs: config.maxPlugs
                    ).isEmpty else { continue }
                    if physical.count < physicalCap { physical.append(sweepStop) }
                    agreements.insert(sweepStop)
                }
            }
            settingsDone += lockedAnchors.count
        } else {
            // Full GPU sweep for unicity-safe anchors (and for confirm=1 runs).
            var inFlight: [WelchmanInFlight] = []

            func drainOldest() {
                guard let flight = inFlight.first else { return }
                inFlight.removeFirst()
                let survivors = engine.wait(flight)
                let shell = flight.shell
                let bombe = WelchmanBombe(
                    greek: shell.greek, left: shell.left, middle: shell.middle, right: shell.right,
                    reflector: shell.reflector, rings: shell.rings, maxPlugs: config.maxPlugs
                )
                for lane in 0..<WelchmanMetalEngine.laneCount where survivors[lane] != 0 {
                    let start = WelchmanMetalEngine.position(forLane: lane)
                    let stops = bombe.test(menu: shell.menu, start: start)
                    rawStops += stops.count
                    for stop in stops {
                        let sweepStop = SweepStop(
                            ukw: shell.ukwName, greek: shell.greekName,
                            wheelOrder: shell.wheelOrder,
                            menu: shell.menu,
                            rings: shell.rings,
                            stop: stop,
                            ciphertext: set.ciphertext
                        )
                        guard !PostBombeDiscriminator.completions(
                            for: sweepStop, maxPlugs: config.maxPlugs
                        ).isEmpty else { continue }
                        if physical.count < physicalCap { physical.append(sweepStop) }
                        lockedAnchors[sweepStop.shellID] = LockedAnchorShell(
                            ukwName: shell.ukwName, greekName: shell.greekName,
                            wheelOrder: shell.wheelOrder,
                            greek: shell.greek, left: shell.left,
                            middle: shell.middle, right: shell.right,
                            reflector: shell.reflector, rings: shell.rings,
                            positions: stop.positions
                        )
                        if config.confirmMenus > 1 { agreements.insert(sweepStop) }
                    }
                }
                engine.release(flight)
                settingsDone += WelchmanMetalEngine.laneCount
                shellsDone += 1
            }

            for (ukwName, reflector) in reflectors {
                for (greekName, greek) in greeks {
                    for rings in ringVariants {
                        for order in config.wheelOrders {
                            while inFlight.count >= engine.depth {
                                drainOldest()
                            }
                            let shell = WelchmanShell(
                                menu: menu,
                                greek: greek, left: order.0, middle: order.1, right: order.2,
                                reflector: reflector, rings: rings,
                                ukwName: ukwName, greekName: greekName,
                                wheelOrder: "\(order.0.name)-\(order.1.name)-\(order.2.name)"
                            )
                            if let flight = engine.enqueue(shell: shell) {
                                inFlight.append(flight)
                            }
                        }
                    }
                }
            }
            while !inFlight.isEmpty {
                drainOldest()
            }
        }

        totalStops += rawStops
        let elapsed = Date().timeIntervalSince(started)
        let rate = elapsed > 0 ? Double(settingsDone) / elapsed / 1e6 : 0
        let remaining = max(0, runnableShells - shellsDone)
        let eta = rate > 0
            ? Double(remaining) * Double(WelchmanMetalEngine.laneCount) / (rate * 1e6)
            : 0
        let progress = String(format: "%6.0fs %5.1fM/s ETA %5.1f min", elapsed, rate, eta / 60)

        // Stage 1 — the bombe. Nothing survived, so there is nothing to sieve.
        if rawStops == 0 {
            print(String(format: "  %@ %-44@ dead at the board                    %@",
                         label, menu.description as NSString, progress))
            fflush(stdout)
            continue
        }

        // Stage 2 — the physical sieve, already applied as the stops drained. A survivor
        // needing more than 10 plugs, or contradicting the plugs already deduced, is not
        // a machine the Kriegsmarine could have built.
        if physical.isEmpty {
            print(String(format: "  %@ %-44@ %7d stops → 0 valid 10-plug completions  %@",
                         label, menu.description as NSString, rawStops, progress))
            fflush(stdout)
            continue
        }

        // Stage 3 — the discriminator. Physically possible is not the same as true.
        let verdict = PostBombeDiscriminator.rank(
            stops: physical,
            ciphertext: set.ciphertext,
            maxPlugs: config.maxPlugs,
            provisionalICFloor: config.quarantinePath != nil ? softBar.softICFloor : nil
        )
        totalCompletions += verdict.candidates.count
        guard let best = verdict.candidates.first else {
            print(String(format: "  %@ %-44@ %7d stops → 0 scorable completions  %@",
                         label, menu.description as NSString, rawStops, progress))
            fflush(stdout)
            continue
        }
        if bestSoFar == nil || best.tailScore > bestSoFar!.tailScore { bestSoFar = best }
        if config.quarantinePath != nil {
            for candidate in verdict.candidates.prefix(8)
            where NearMissQuarantine.shouldQuarantine(candidate, softBar: softBar) {
                quarantineBag.append(
                    NearMissQuarantine.makeCandidate(
                        from: candidate,
                        source: quarantineSource,
                        softBar: softBar
                    )
                )
            }
        }
        print(String(format: "  %@ %-44@ %7d stops → %d physical, best IC %.3f tail %.3f  %@",
                     label, menu.description as NSString,
                     rawStops, verdict.candidates.count, best.ic, best.tailScore, progress))
        fflush(stdout)

        // Solo BREAK is allowed only for cribs that clear the unicity floor (16).
        // Shorter menus under --bombe-confirm ≥2 may clear the linguistic bar by chance
        // (menu 627); they must wait for an independent partner on the same shell.
        if PostBombeDiscriminator.isBreak(best) {
            if menu.crib.count >= 16 {
                breakFound = best
                break
            }
            if config.confirmMenus > 1 {
                print(String(format: "  %@ clears the bar at %d letters — holding for "
                             + "≥%d-menu agreement before claiming a break",
                             label, menu.crib.count, config.confirmMenus))
                fflush(stdout)
            } else {
                print(String(format: "  %@ clears the bar at %d letters but is under "
                             + "unicity — not claiming a break (use --bombe-confirm 2)",
                             label, menu.crib.count))
                fflush(stdout)
            }
        }
    }

    let elapsedTotal = Date().timeIntervalSince(started)
    print()
    print("total raw stops: \(totalStops) over \(settingsDone) settings "
        + String(format: "(%.1fM/s mean)",
                 elapsedTotal > 0 ? Double(settingsDone) / elapsedTotal / 1e6 : 0))

    print("survived the 10-plug sieve: \(totalCompletions)")
    if config.confirmMenus > 1 {
        print("locked anchor shells (≥\(anchorMinLength)): \(lockedAnchors.count)")
    }
    if !overlong.isEmpty {
        print("skipped (edges > \(welchmanMaxEdges) Metal cap): \(overlong.count) — not tested")
    }

    func flushQuarantine(note: String) {
        guard let qPath = config.quarantinePath, !qPath.isEmpty else { return }
        // Also quarantine the campaign best if it sits in the soft band.
        if let best = bestSoFar,
           NearMissQuarantine.shouldQuarantine(best, softBar: softBar) {
            quarantineBag.append(
                NearMissQuarantine.makeCandidate(
                    from: best,
                    source: quarantineSource + "#bestSoFar",
                    softBar: softBar
                )
            )
        }
        let deduped = NearMissQuarantine.prioritize(NearMissQuarantine.dedupe(quarantineBag))
        guard !deduped.isEmpty else {
            print("quarantine: 0 soft-band near-misses (\(note))")
            return
        }
        let ct = EnigmaAlphabet.string(from: set.ciphertext)
        let manifest = QuarantineManifest(
            target: "P1030680",
            ciphertext: ct,
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            sourceFixture: quarantineSource,
            softBar: softBar,
            candidates: deduped
        )
        do {
            try NearMissQuarantine.writeManifest(manifest, to: qPath)
            print("quarantine: wrote \(deduped.count) near-miss(es) → \(qPath) (\(note))")
            print("  escalate: --hybrid --hybrid-stochastic --hybrid-quarantine \(qPath)")
        } catch {
            print("quarantine: failed to write \(qPath): \(error)")
        }
    }

    if let winner = breakFound {
        flushQuarantine(note: "break claimed; soft-band peers retained")
        PostBombeDiscriminator.announceBreak(winner)
        return
    }

    if runnable.isEmpty {
        print("nothing runnable — every selected menu exceeded the Metal edge cap")
    } else if totalStops == 0 {
        print("no setting survived — every runnable menu contradicted everywhere it was tried")
    } else if totalCompletions == 0 {
        print("every stop was a ghost: no menu admits a physically buildable "
            + "\(config.maxPlugs)-plug board.")
        print("The cribs tried are not in this message at the offsets tried.")
    } else if let best = bestSoFar {
        print(String(format: "best physical candidate: IC %.3f tail %.3f "
                     + "(IC floor %.3f / threshold %.3f) — below the bar, so no break claimed",
                     best.ic, best.tailScore,
                     PostBombeDiscriminator.icFloor,
                     PostBombeDiscriminator.breakThreshold))
        print("  \(best.stop.menu.description)")
        print("  UKW \(best.stop.ukw) Greek \(best.stop.greek) WO \(best.stop.wheelOrder) "
            + "pos \(best.messageKey)")
        print("  \(best.plaintext)")
    }

    guard config.confirmMenus > 1 else {
        flushQuarantine(note: "solo pass complete")
        return
    }
    let confirmed = agreements.confirmed(minIndependentMenus: config.confirmMenus)
    print("confirmed shells (≥\(config.confirmMenus) independent menus): \(confirmed.count)")
    for hit in confirmed.prefix(config.reportLimit) { print(hit.report()) }

    // Agreement is the only path a short crib has to a claimed break. Re-score each
    // confirmed shell; the representative stop comes from the strongest independent menu.
    for hit in confirmed {
        let verdict = PostBombeDiscriminator.rank(
            stops: [hit.representative],
            ciphertext: set.ciphertext,
            maxPlugs: config.maxPlugs,
            provisionalICFloor: config.quarantinePath != nil ? softBar.softICFloor : nil
        )
        guard let best = verdict.candidates.first else { continue }
        if NearMissQuarantine.shouldQuarantine(best, softBar: softBar) {
            quarantineBag.append(
                NearMissQuarantine.makeCandidate(
                    from: best,
                    source: quarantineSource + "#confirmed",
                    softBar: softBar
                )
            )
        }
        guard PostBombeDiscriminator.isBreak(best) else { continue }
        print()
        print("confirmed shell also clears the linguistic bar "
            + "(\(hit.independentCount) independent menus)")
        flushQuarantine(note: "confirmed break")
        PostBombeDiscriminator.announceBreak(best)
        return
    }
    flushQuarantine(note: "confirm pass complete")
}

struct SweepStop {
    let ukw: String
    let greek: String
    let wheelOrder: String
    let menu: BombeMenu
    let rings: (Int, Int, Int, Int)
    let stop: BombeStop
    let ciphertext: [Int]

    var shellID: ShellID {
        ShellID(
            ukw: ukw, greek: greek, wheelOrder: wheelOrder,
            rings: rings, positions: stop.positions
        )
    }

    func report() -> String {
        let key = EnigmaM4Key(
            greek: EnigmaM4Warehouse.greek(named: greek == "beta" ? "B" : "C"),
            rotors: rotorTriple(),
            rings: rings,
            positions: stop.positions,
            plugboard: stop.stecker,
            reflector: EnigmaM4Warehouse.thinReflector(named: ukw)
        )
        var machine = EnigmaM4Machine(key: key)
        let plain = EnigmaAlphabet.string(from: machine.processText(ciphertext))
        let ringString = EnigmaAlphabet.string(from: [rings.0, rings.1, rings.2, rings.3])
        return """
          UKW \(ukw) Greek \(greek) WO \(wheelOrder) rings \(ringString) pos \(stop.positionsString)
            menu    \(menu.description)
            stecker \(stop.pairsString) (\(stop.pairCount) pairs)
            decrypt \(plain)
        """
    }

    func rotorTriple() -> (EnigmaRotorSpec, EnigmaRotorSpec, EnigmaRotorSpec) {
        let names = wheelOrder.split(separator: "-").map(String.init)
        let lookup = M4ThetisAttack.navalRotors
        func rotor(_ name: String) -> EnigmaRotorSpec {
            lookup.first { $0.name == name } ?? EnigmaWarehouse.rotorI
        }
        return (rotor(names[0]), rotor(names[1]), rotor(names[2]))
    }
}

struct ShellID: Hashable {
    let ukw: String
    let greek: String
    let wheelOrder: String
    let rings: (Int, Int, Int, Int)
    let positions: (Int, Int, Int, Int)

    static func == (lhs: ShellID, rhs: ShellID) -> Bool {
        lhs.ukw == rhs.ukw && lhs.greek == rhs.greek && lhs.wheelOrder == rhs.wheelOrder
            && lhs.rings == rhs.rings && lhs.positions == rhs.positions
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ukw)
        hasher.combine(greek)
        hasher.combine(wheelOrder)
        hasher.combine(rings.0); hasher.combine(rings.1)
        hasher.combine(rings.2); hasher.combine(rings.3)
        hasher.combine(positions.0); hasher.combine(positions.1)
        hasher.combine(positions.2); hasher.combine(positions.3)
    }
}

/// Machine identity for a shell a ≥16 anchor already admitted — enough to re-test a
/// short challenger menu on the host without another full GPU sweep.
struct LockedAnchorShell {
    let ukwName: String
    let greekName: String
    let wheelOrder: String
    let greek: EnigmaRotorSpec
    let left: EnigmaRotorSpec
    let middle: EnigmaRotorSpec
    let right: EnigmaRotorSpec
    let reflector: [Int]
    let rings: (Int, Int, Int, Int)
    let positions: (Int, Int, Int, Int)
}

struct ConfirmedShell {
    let representative: SweepStop
    let menus: [BombeMenu]
    let independentCount: Int

    func report() -> String {
        let menuList = menus.map(\.description).joined(separator: "\n            ")
        return representative.report()
            + "\n            confirmed by \(independentCount) independent menus:\n            \(menuList)"
    }
}

// MARK: Thread-safe accumulators

final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() { add(1) }

    func add(_ amount: Int) {
        lock.lock()
        count += amount
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

/// Accumulates raw stops and returns only shells that multiple independent menus agree on.
final class LockedShellAgreements: @unchecked Sendable {
    private let lock = NSLock()
    private var byShell: [ShellID: [SweepStop]] = [:]

    func insert(_ stop: SweepStop) {
        lock.lock()
        byShell[stop.shellID, default: []].append(stop)
        lock.unlock()
    }

    func confirmed(minIndependentMenus: Int) -> [ConfirmedShell] {
        lock.lock()
        defer { lock.unlock() }
        var hits: [ConfirmedShell] = []
        for (_, stops) in byShell {
            let menus = maximalMenus(stops.map(\.menu))
            // Count pairwise-independent menus after dropping nested duplicates.
            var independent: [BombeMenu] = []
            for menu in menus.sorted(by: byLoopPower) {
                if independent.allSatisfy({ menusAreIndependent($0, menu) }) {
                    independent.append(menu)
                }
            }
            guard independent.count >= minIndependentMenus else { continue }
            // Prefer the stop from the strongest menu as the representative decrypt.
            let bestMenu = independent[0]
            let representative = stops.first { $0.menu.crib == bestMenu.crib
                && $0.menu.offset == bestMenu.offset } ?? stops[0]
            hits.append(
                ConfirmedShell(
                    representative: representative,
                    menus: independent,
                    independentCount: independent.count
                )
            )
        }
        return hits.sorted {
            ($0.independentCount, $0.representative.menu.loops)
                > ($1.independentCount, $1.representative.menu.loops)
        }
    }
}
