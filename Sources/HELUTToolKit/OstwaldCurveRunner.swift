import Foundation
import HELUTCore
import HELUTCLI

// MARK: - `--ostwald-curve` driver
//
// Prints the measured length threshold of the crib-free attack on the 48 published U-534
// keys. The number that matters per row is the **margin**: climbed score at the true rotor
// setting minus the best climbed score over sampled wrong settings. Positive means signal
// still outranks noise at that message length, so a sweep could work. Negative means the
// search would rank a wrong key above the right one, and no amount of GPU changes that.

func runOstwaldCurve() {
    let corpusPath = resolveCorpusPath()
    let controls = OstwaldCurve.loadControls(path: corpusPath)
    guard !controls.isEmpty else {
        print("no known-key controls loaded from \(corpusPath)")
        return
    }

    let wrongSamples = intFlag("--ostwald-wrong") ?? 16
    let ladder = (stringFlag("--ostwald-lengths")?
        .split(separator: ",").compactMap { Int($0) })
        ?? [60, 68, 72, 80, 90, 100, 120, 160]
    let scorers: [ClimbScorer]
    if let only = stringFlag("--ostwald-scorer"),
       let picked = ClimbScorer(rawValue: only) {
        scorers = [picked]
    } else {
        scorers = ClimbScorer.languageScorers
    }
    let maxControls = intFlag("--ostwald-controls") ?? controls.count
    // Ostwald partial exhaustion: number of high-frequency letters to fix a plug on.
    // 6 letters == 141 fixed plugs, matching enigma-cuda's documented -e behaviour.
    let brutePlugs = intFlag("--ostwald-brute-plugs", allowZero: true) ?? 0
    let bruteAll = CommandLine.arguments.contains("--ostwald-brute-all")
    var exhaustLetters = intFlag("--ostwald-exhaust", allowZero: true) ?? 0
    if brutePlugs >= 4, exhaustLetters == 0 {
        exhaustLetters = OstwaldExhaust.fourPlugMinLetters
    }
    if brutePlugs >= 4, exhaustLetters < OstwaldExhaust.fourPlugMinLetters {
        print("ABORT — 4-plug hot-letter brute needs --ostwald-exhaust ≥ 8 "
            + "(got \(exhaustLetters)); four pairs use eight letters. "
            + "Exhaust 6 is the depth-2 cell, not a 4-plug cell.")
        return
    }
    if brutePlugs >= 4, exhaustLetters > OstwaldExhaust.fourPlugMaxLetters, !bruteAll {
        print("ABORT — 4-plug hot-letter brute at exhaust \(exhaustLetters) is the "
            + "Phase 54.4 saturation trap. Pass --ostwald-brute-all to force it.")
        return
    }
    if brutePlugs >= 4 {
        let pool = min(max(exhaustLetters, OstwaldExhaust.fourPlugMinLetters), 26)
        let starts = OstwaldExhaust.fourPlugStartCount(letterCount: pool)
        if starts > OstwaldExhaust.fourPlugMaterializeCap {
            let trueIndex = OstwaldAllSettings.index(
                EnigmaM4Key.positions(fromLetters: ControlMessageP1030684.positions)
            )
            print("ABORT — 4-plug alphabet brute is \(starts) starts per control, "
                + "not a 30-control curve. Lock one setting:")
            print("  ./.build/release/helut --ostwald-all-settings --ostwald-control p1030684 "
                + "--ostwald-setting-from \(trueIndex) --ostwald-setting-count 1 "
                + "--ostwald-brute-plugs 4 --ostwald-brute-all --ostwald-exhaust 26")
            print("Wrong-setting control: --ostwald-setting-from 0 --ostwald-setting-count 1 "
                + "with the same 4-plug flags.")
            return
        }
    }
    // Depth 1 is Ostwald's published single-plug scheme and saturates: 141 fixed plugs up to
    // 325 buys no further margin, because exhaustion is symmetric and lifts the decoys' best
    // start too. Depth 2 fixes two disjoint plugs, trading a far larger decoy maximum against
    // a discretely better true basin. Never previously run; Phase 50 named it as open.
    let exhaustDepth = max(1, intFlag("--ostwald-exhaust-depth") ?? 1)
    // Bombe coupling model: k correct plugs at the true setting (a true stop's forced
    // board) against k random plugs at every decoy (a ghost stop's forced board).
    let seededPlugs = intFlag("--ostwald-seed", allowZero: true) ?? 0
    // Naval-dialect trigram model, leave-one-out, Dirichlet-mixed with the generic German.
    // Break-and-reconnect passes in the stecker climb (0 = old insertion-only behaviour).
    let reconnectPasses = intFlag("--ostwald-reconnect", allowZero: true) ?? 0
    let beamWidth = intFlag("--ostwald-beam") ?? 1
    let decoyClimbs = intFlag("--ostwald-ranker-decoy-climbs", allowZero: true) ?? 0
    let lexicon = CommandLine.arguments.contains("--ostwald-lexicon")
        ? NavalLexicon.load(corpusPath: corpusPath)
        : nil
    let navalRequested = CommandLine.arguments.contains("--ostwald-naval")
        || scorers.contains(.ranker)
    let navalCorpus = navalRequested ? NavalGrams.load(corpusPath: corpusPath) : nil
    if navalRequested, navalCorpus == nil, !scorers.contains(.ranker) {
        print("ABORT — leave-one-out naval trigram model unavailable; no curve evaluated.")
        return
    }
    let needsGenericTrigram = navalCorpus == nil && scorers.contains { scorer in
        switch scorer {
        case .bigram: return false
        case .trigram, .staged, .ranker: return true
        }
    }
    if needsGenericTrigram, !GermanTrigrams.isLoaded {
        print("ABORT — attested trigram model unavailable; no trigram/staged curve evaluated.")
        return
    }

    print("=== Ciphertext-only length threshold — crib-free climb on known M4 keys ===")
    print("corpus        : \(corpusPath)")
    print("controls      : \(controls.count) published 1 May 1945 U-534 keys "
        + "(lengths \(controls.first!.length)…\(controls.last!.length)), using "
        + "\(min(maxControls, controls.count))")
    if let navalCorpus {
        print("trigram model : \(navalCorpus.sourceDescription)")
        print("                leave-one-out: each control's own plaintext is withheld")
    } else {
        print("trigram model : \(GermanTrigrams.sourceDescription)")
    }
    print("scorers       : \(scorers.map(\.rawValue).joined(separator: ", "))")
    if let lexicon {
        print("margin stat   : \(lexicon.sourceDescription)")
        print("                applied AFTER the climb as a discriminator; the climb still")
        print("                optimises the staged statistic (a sparse score has no gradient)")
    }
    print("climb         : " + (reconnectPasses > 0
        ? "greedy insertion + \(reconnectPasses) break-and-reconnect pass(es), "
            + "frequency-ordered"
        : "greedy insertion + one replacement pass (insertion-only neighborhood)"))
    if beamWidth > 1 {
        print("beam          : \(beamWidth) partial boards kept per plug-insertion round")
    }
    if scorers.contains(.ranker) {
        print("ranker        : leave-one-out LDA on IC/n-grams/entropy/naval-structure, "
            + "fitted against wrong-setting decrypts (not uniform random)")
        if decoyClimbs > 0 {
            print("                plus \(decoyClimbs) staged decoy climb(s) per training control")
        }
    }
    if brutePlugs >= 4 {
        print("exhaustion    : 4-plug hot-letter brute on \(exhaustLetters) most "
            + "frequent ciphertext letters"
            + (bruteAll ? " (--ostwald-brute-all)" : ""))
        print("                (applied symmetrically to true *and* wrong settings)")
    } else if exhaustLetters > 0 {
        print("exhaustion    : Ostwald partial exhaustion over the \(exhaustLetters) most "
            + "frequent ciphertext letters, depth \(exhaustDepth)"
            + (exhaustDepth > 1 ? " (disjoint plug \(exhaustDepth)-sets)" : ""))
        print("                (applied symmetrically to true *and* wrong settings)")
    } else {
        print("exhaustion    : none — climbing from an empty board (--ostwald-exhaust N)")
    }
    if seededPlugs > 0 {
        print("bombe seed    : \(seededPlugs) plug(s) held fixed — CORRECT at the true "
            + "setting, RANDOM at every decoy")
        print("                (models a Welchman stop's forced stecker; oracle-seeded, so")
        print("                 this is an upper bound on the real coupling)")
    }
    print("wrong samples : \(wrongSamples) random message keys per cell, same shell "
        + "(the hardest negative control — a real sweep also enumerates wrong wheel")
    print("                orders and rings, which are easier to reject, so margins here")
    print("                are conservative)")
    print("target        : P1030680 is 72 letters. Published record for this attack class")
    print("                is 78 letters on three-rotor Heer; this is four-rotor naval M4.")
    print()
    // Preflight. A harness that cannot reproduce the published plaintext from the
    // published key is measuring its own bugs, so it does not get to print a curve.
    var roundTripped: [KnownControl] = []
    var failures: [(String, Int, Int)] = []
    for control in controls {
        var machine = EnigmaM4Machine(key: control.key)
        let decrypt = machine.processText(control.ciphertext)
        let matched = zip(decrypt, control.plaintext).reduce(0) { $0 + ($1.0 == $1.1 ? 1 : 0) }
        if matched == min(decrypt.count, control.plaintext.count), !decrypt.isEmpty {
            roundTripped.append(control)
        } else {
            failures.append((control.id, matched, min(decrypt.count, control.plaintext.count)))
        }
    }
    print("preflight     : \(roundTripped.count)/\(controls.count) controls decrypt to their "
        + "published plaintext under their published key")
    if !failures.isEmpty {
        print("  FAILED to round-trip (key mapping is wrong for these):")
        for (id, matched, total) in failures.prefix(12) {
            print(String(format: "    %@  %d/%d letters", id, matched, total))
        }
        if failures.count > 12 { print("    … \(failures.count - 12) more") }
    }
    guard !roundTripped.isEmpty else {
        print()
        print("ABORT — no control reproduces its own plaintext, so any curve printed here")
        print("would be measuring a key-construction bug rather than the attack. Fix the")
        print("corpus mapping first.")
        return
    }
    print()

    print("A cell is decided by MARGIN = trueScore − best wrongScore.")
    print("  margin > 0 : signal outranks sampled noise; a sweep can work at this length")
    print("  margin < 0 : the search would rank a wrong key first; compute cannot fix it")
    print()

    let used = Array(roundTripped.prefix(maxControls))
    if brutePlugs >= 4, let sample = used.first(where: { $0.length >= 72 }) ?? used.first {
        let window = Array(sample.ciphertext.prefix(min(72, sample.ciphertext.count)))
        if let starts = try? OstwaldExhaust.fourPlugStarts(
            ciphertext: window,
            exhaustLetters: exhaustLetters,
            locked: [],
            bruteAll: bruteAll
        ) {
            print("4-plug starts : \(starts.count) perfect matchings on \(exhaustLetters) hot letters "
                + "(sample \(sample.id))")
        }
        let covered = used.filter {
            OstwaldExhaust.truePlugsInsideHotSet(
                ciphertext: Array($0.ciphertext.prefix(min(72, $0.ciphertext.count))),
                truePairs: $0.truePairs,
                exhaustLetters: exhaustLetters
            ) >= 4
        }.count
        print("oracle cover  : \(covered)/\(used.count) round-tripped controls have ≥4 true "
            + "plugs inside the \(exhaustLetters) hottest ciphertext letters")
        print("                (if this is ~0, Metal cannot invent those four plugs from "
            + "frequency; a 164M all-pair 4-plug score is a different job)")
        print()
    }

    for scorer in scorers {
        print(String(repeating: "─", count: 96))
        print("scorer: \(scorer.rawValue)")
        // Swift's String(format:) cannot take %s with a Swift String — pad manually.
        func column(_ text: String, _ width: Int) -> String {
            String(repeating: " ", count: max(0, width - text.count)) + text
        }
        print(column("len", 6) + column("ctrls", 6) + column("win", 5)
            + column("win%", 8) + column("medMargin", 11) + column("medZ", 8)
            + column("plugs", 7) + column("corr", 7))
        print(String(repeating: "─", count: 96))

        for length in ladder {
            let eligible = used.filter { $0.length >= length && $0.plaintext.count >= length }
            guard !eligible.isEmpty else { continue }

            let box = CurveBox(count: eligible.count)
            DispatchQueue.concurrentPerform(iterations: eligible.count) { index in
                let ranker: OstwaldRanker.Model?
                if scorer == .ranker {
                    ranker = OstwaldRanker.fit(
                        controls: used, excluding: eligible[index].id,
                        window: length, decoyClimbs: decoyClimbs,
                        seed: UInt64(0xA11CE &+ index &* 7919),
                        navalCorpus: navalCorpus
                    )
                    if ranker == nil { return }
                } else {
                    ranker = nil
                }
                let point = OstwaldCurve.measure(
                    control: eligible[index], length: length, scorer: scorer,
                    wrongSamples: wrongSamples,
                    seed: UInt64(0x5EED &+ index &* 7919 &+ length &* 104_729),
                    exhaustLetters: exhaustLetters,
                    exhaustDepth: exhaustDepth,
                    seededPlugs: seededPlugs,
                    navalCorpus: navalCorpus,
                    reconnectPasses: reconnectPasses,
                    lexicon: lexicon,
                    beamWidth: beamWidth,
                    ranker: ranker,
                    brutePlugs: brutePlugs,
                    bruteAll: bruteAll
                )
                if let point { box.store(point, at: index) }
            }
            let points = box.snapshot()
            guard !points.isEmpty else { continue }

            let wins = points.filter { $0.margin > 0 }.count
            let margins = points.map(\.margin).sorted()
            let zs = points.map(\.z).filter { $0.isFinite }.sorted()
            let medMargin = margins[margins.count / 2]
            let medZ = zs.isEmpty ? 0 : zs[zs.count / 2]
            let medPlugs = points.map(\.plugsRecovered).sorted()[points.count / 2]
            let medCorrect = points.map { Double($0.lettersCorrect) / Double(length) }
                .sorted()[points.count / 2]

            print(column("\(length)", 6) + column("\(points.count)", 6)
                + column("\(wins)", 5)
                + column(String(format: "%.0f%%",
                                Double(wins) / Double(points.count) * 100), 8)
                + column(String(format: "%+.4f", medMargin), 11)
                + column(String(format: "%.2f", medZ), 8)
                + column("\(medPlugs)/10", 7)
                + column(String(format: "%.0f%%", medCorrect * 100), 7))
            fflush(stdout)
        }
        print()
    }

    print(String(repeating: "─", count: 96))
    print("Columns: win = controls whose true setting beat every sampled wrong setting.")
    print("         medMargin / medZ = median margin and median z-score of the truth.")
    print("         plugs = median true plugs recovered of 10. corr = median letters right.")
    print()
    print("This is a measurement, not a break. It bounds what the crib-free path can reach")
    print("on this traffic class before any of it is pointed at P1030680.")
}

/// Unclimbed 4-plug score probe: do any 4 true plugs already outrank random 4-plug boards
/// at 72 letters? If not, enumerating all 164 million 4-plug boards with Metal still
/// cannot surface the Phase 50.6 basin without climbing the remaining six.
func runOstwaldFourPlugProbe() {
    let corpusPath = resolveCorpusPath()
    let controls = OstwaldCurve.loadControls(path: corpusPath)
    let randomCount = intFlag("--ostwald-wrong") ?? 2048
    print("=== Unclimbed 4-plug score probe (Metal 164M filter question) ===")
    print("window        : 72 letters")
    print("true subsets  : C(10,4) = 210 disjoint 4-plug boards from the published stecker")
    print("random boards : \(randomCount) random 4-plug boards, same rotor setting")
    print("score         : trigram (the Metal kernel's last stage; unclimbed 4-plug is not yet staged-to-trigram)")
    print()
    func column(_ text: String, _ width: Int) -> String {
        String(repeating: " ", count: max(0, width - text.count)) + text
    }
    print(
        column("id", 10) + column("trueMax", 9) + column("rndMax", 9)
            + column("rndMean", 9) + column("z", 8) + column("beat", 12)
    )
    var wins = 0
    var n = 0
    for control in controls where control.length >= 72 {
        var machine = EnigmaM4Machine(key: control.key)
        let decrypt = machine.processText(control.ciphertext)
        let matched = zip(decrypt, control.plaintext).reduce(0) { $0 + ($1.0 == $1.1 ? 1 : 0) }
        guard matched == min(decrypt.count, control.plaintext.count), !decrypt.isEmpty else {
            continue
        }
        let ct = Array(control.ciphertext.prefix(72))
        let stripped = EnigmaM4Key(
            greek: control.key.greek, rotors: control.key.rotors, rings: control.key.rings,
            positions: control.key.positions, plugboard: Array(0..<26),
            reflector: control.key.reflector
        )
        let trueMax = fourPlugSubsetMax(key: stripped, ciphertext: ct, pairs: control.truePairs)
        var rng = SplitMix64(seed: 0x4B00_0000 &+ UInt64(n &* 7919))
        var randomScores: [Double] = []
        randomScores.reserveCapacity(randomCount)
        for _ in 0..<randomCount {
            randomScores.append(
                GermanTrigrams.score(
                    OstwaldCurve.decrypt(
                        key: stripped, ciphertext: ct, pairs: randomFourPlug(&rng)
                    )
                )
            )
        }
        let rndMax = randomScores.max() ?? -.infinity
        let rndMean = randomScores.reduce(0, +) / Double(randomCount)
        let variance = randomScores.reduce(0) { $0 + ($1 - rndMean) * ($1 - rndMean) }
            / Double(max(randomCount - 1, 1))
        let z = variance > 0 ? (trueMax - rndMean) / variance.squareRoot() : 0
        let beat = randomScores.filter { $0 >= trueMax }.count
        if trueMax > rndMax { wins += 1 }
        n += 1
        print(
            column(control.id, 10)
                + column(String(format: "%.3f", trueMax), 9)
                + column(String(format: "%.3f", rndMax), 9)
                + column(String(format: "%.3f", rndMean), 9)
                + column(String(format: "%.2f", z), 8)
                + column("\(beat)/\(randomCount)", 12)
        )
        if n >= 12 { break }
    }
    print()
    print("trueMax > rndMax on \(wins)/\(n) controls (unclimbed).")
    print("If this is not a clean majority, a 164M Metal 4-plug *score* does not find the")
    print("Phase 50.6 board. Climbing all 164,038,875 remaining-six boards is")
    print("\(OstwaldExhaust.fourPlugStartCount(letterCount: 26)) starts × "
        + "\(OstwaldProgress.greedyDecrypts(seeded: 4)) decrypts "
        + "≈ \(OstwaldExhaust.fourPlugStartCount(letterCount: 26) * OstwaldProgress.greedyDecrypts(seeded: 4)) "
        + "decrypts (~3.1 h/setting at the 10M floor, ~6.7 h at 4.6M measured).")
    print("That climb is streamed (--ostwald-brute-all --ostwald-exhaust 26) on one")
    print("locked setting; it is still symmetric on decoys.")
}

private func fourPlugSubsetMax(
    key: EnigmaM4Key,
    ciphertext: [Int],
    pairs: [(Int, Int)]
) -> Double {
    let subsets = kSubsets(pairs, k: 4)
    var best = -Double.infinity
    for subset in subsets {
        let score = GermanTrigrams.score(
            OstwaldCurve.decrypt(key: key, ciphertext: ciphertext, pairs: subset)
        )
        if score > best { best = score }
    }
    return best
}

private func kSubsets<T>(_ items: [T], k: Int) -> [[T]] {
    guard k >= 0, items.count >= k else { return [] }
    if k == 0 { return [[]] }
    var out: [[T]] = []
    var choose = Array(0..<k)
    func emit() { out.append(choose.map { items[$0] }) }
    emit()
    while true {
        var i = k - 1
        while i >= 0 && choose[i] == items.count - k + i { i -= 1 }
        if i < 0 { break }
        choose[i] += 1
        var j = i + 1
        while j < k {
            choose[j] = choose[j - 1] + 1
            j += 1
        }
        emit()
    }
    return out
}

private func randomFourPlug(_ rng: inout SplitMix64) -> [(Int, Int)] {
    var pool = Array(0..<26)
    for index in stride(from: 25, to: 0, by: -1) {
        let swap = Int(rng.next() % UInt64(index + 1))
        pool.swapAt(index, swap)
    }
    return [
        (min(pool[0], pool[1]), max(pool[0], pool[1])),
        (min(pool[2], pool[3]), max(pool[2], pool[3])),
        (min(pool[4], pool[5]), max(pool[4], pool[5])),
        (min(pool[6], pool[7]), max(pool[6], pool[7])),
    ]
}

private final class CurveBox: @unchecked Sendable {
    private let lock = NSLock()
    private var slots: [OstwaldCurve.CurvePoint?]
    init(count: Int) { slots = .init(repeating: nil, count: count) }
    func store(_ value: OstwaldCurve.CurvePoint, at index: Int) {
        lock.lock(); slots[index] = value; lock.unlock()
    }
    func snapshot() -> [OstwaldCurve.CurvePoint] {
        lock.lock(); defer { lock.unlock() }
        return slots.compactMap { $0 }
    }
}
