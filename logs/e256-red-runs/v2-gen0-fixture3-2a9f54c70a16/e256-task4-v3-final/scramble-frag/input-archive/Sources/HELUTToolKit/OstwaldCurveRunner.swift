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
        scorers = ClimbScorer.allCases
    }
    let maxControls = intFlag("--ostwald-controls") ?? controls.count
    // Ostwald partial exhaustion: number of high-frequency letters to fix a plug on.
    // 6 letters == 141 fixed plugs, matching enigma-cuda's documented -e behaviour.
    let exhaustLetters = intFlag("--ostwald-exhaust", allowZero: true) ?? 0
    // Bombe coupling model: k correct plugs at the true setting (a true stop's forced
    // board) against k random plugs at every decoy (a ghost stop's forced board).
    let seededPlugs = intFlag("--ostwald-seed", allowZero: true) ?? 0
    // Naval-dialect trigram model, leave-one-out, Dirichlet-mixed with the generic German.
    // Break-and-reconnect passes in the stecker climb (0 = old insertion-only behaviour).
    let reconnectPasses = intFlag("--ostwald-reconnect", allowZero: true) ?? 0
    let lexicon = CommandLine.arguments.contains("--ostwald-lexicon")
        ? NavalLexicon.load(corpusPath: corpusPath)
        : nil
    let navalCorpus = CommandLine.arguments.contains("--ostwald-naval")
        ? NavalGrams.load(corpusPath: corpusPath)
        : nil

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
    if exhaustLetters > 0 {
        print("exhaustion    : Ostwald partial exhaustion over the \(exhaustLetters) most "
            + "frequent ciphertext letters")
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
                let point = OstwaldCurve.measure(
                    control: eligible[index], length: length, scorer: scorer,
                    wrongSamples: wrongSamples,
                    seed: UInt64(0x5EED &+ index &* 7919 &+ length &* 104_729),
                    exhaustLetters: exhaustLetters,
                    seededPlugs: seededPlugs,
                    navalCorpus: navalCorpus,
                    reconnectPasses: reconnectPasses,
                    lexicon: lexicon
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
