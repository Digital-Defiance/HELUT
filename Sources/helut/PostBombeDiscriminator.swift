import Foundation
import HELUTCore

// MARK: - Post-bombe discriminator
//
// The diagonal board answers a Boolean question: can this rotor setting be ruled out?
// It does not answer "is this the message". At 18 letters a menu sits just under the
// unicity distance, so a handful of ghosts survive alongside any true key.
//
// This is where statistics belong — after the deterministic sieve has cut 1.4x10^11
// settings down to a dozen, not before. Ranking twelve candidates on 72 letters is a
// completely different act from hill-climbing 2^47 plugboards on the same 72 letters.
//
// One correction the naive version needs. A bombe stop seeds ONE letter and propagates,
// so only the menu component containing that letter gets pinned. Letters in other
// components come back undetermined and default to self-steckered, which is why raw
// stop decrypts do not even reproduce their own crib (14/18 on the P1030680 stops).
// Scoring those tails would be scoring a broken plugboard, so the discriminator
// completes the board first: it re-seeds every component, keeps only combinations that
// are a consistent involution, and demands the crib decrypt back exactly.

/// A survivor after stecker completion and full-message scoring.
struct DiscriminatedCandidate {
    let stop: SweepStop
    let stecker: [Int]
    let plaintext: String
    /// Index of Coincidence over the full decrypt. German ≈ 0.07; noise ≈ 0.038.
    let ic: Double
    /// Mean trigram log-probability over all 72 letters.
    let score: Double
    /// Same, restricted to the letters the crib does *not* cover — the ghost test.
    let tailScore: Double
    let cribExact: Bool
    let pairCount: Int
    let determinedLetters: Int

    var messageKey: String { stop.stop.positionsString }
}

/// Outcome of discriminating one batch of stops.
struct DiscriminationResult {
    let candidates: [DiscriminatedCandidate]
    /// Stops that no ≤10-plug board can satisfy across the whole menu. The bombe kept
    /// these only because it seeds one letter, so it never tested the menu components
    /// that seed could not reach.
    let killedByCompletion: Int
    /// Completions whose full decrypt sits at the noise IC floor — rejected before
    /// trigrams run. Catches the menu-627 class of fluke.
    let killedByIC: Int
}

enum PostBombeDiscriminator {

    // MARK: Stecker completion

    /// Connected components of the menu graph, as letter groups.
    private static func components(of menu: BombeMenu) -> [[Int]] {
        var parent = Array(0..<26)
        func find(_ x: Int) -> Int {
            var root = x
            while parent[root] != root { root = parent[root] }
            var walk = x
            while parent[walk] != root {
                let next = parent[walk]
                parent[walk] = root
                walk = next
            }
            return root
        }
        for (a, b) in menu.ends {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[ra] = rb }
        }
        var groups: [Int: [Int]] = [:]
        for letter in menu.letters {
            groups[find(letter), default: []].append(letter)
        }
        return Array(groups.values)
    }

    /// Merge two live maps; nil when they disagree on any letter.
    private static func merge(_ a: [UInt32], _ b: [UInt32]) -> [UInt32]? {
        var out = a
        for index in 0..<26 {
            let union = out[index] | b[index]
            if union.nonzeroBitCount > 1 { return nil }
            out[index] = union
        }
        return out
    }

    /// Every consistent full assignment the menu admits at this setting.
    ///
    /// Each component is seeded independently over all 26 values; surviving partial
    /// maps are then combined, with the diagonal board's involution rule rejecting any
    /// pair of components that would send two letters to the same stecker value.
    static func completedSteckers(
        menu: BombeMenu,
        scramblers: [[UInt8]],
        maxPlugs: Int,
        limit: Int = 4096
    ) -> [[Int]] {
        var perComponent: [[[UInt32]]] = []
        for group in components(of: menu) {
            guard let representative = group.first else { continue }
            var options: [[UInt32]] = []
            for value in 0..<26 {
                if let live = WelchmanBombe.propagate(
                    menu: menu, scramblers: scramblers,
                    seedLetter: representative, seedValue: value
                ) {
                    options.append(live)
                }
            }
            if options.isEmpty { return [] }
            perComponent.append(options)
        }
        guard !perComponent.isEmpty else { return [] }

        // Cartesian product across components, pruned as we go.
        var merged: [[UInt32]] = [[UInt32](repeating: 0, count: 26)]
        for options in perComponent {
            var next: [[UInt32]] = []
            for partial in merged {
                for option in options {
                    if let combined = merge(partial, option) {
                        next.append(combined)
                        if next.count >= limit { break }
                    }
                }
                if next.count >= limit { break }
            }
            if next.isEmpty { return [] }
            merged = next
        }

        var tables: [[Int]] = []
        for live in merged {
            var stecker = Array(0..<26)
            var pairs = 0
            var valid = true
            for x in 0..<26 where live[x] != 0 {
                let y = live[x].trailingZeroBitCount
                stecker[x] = y
                if y != x { pairs += 1 }
            }
            pairs /= 2
            if maxPlugs > 0 && pairs > maxPlugs { valid = false }
            // Must be a genuine involution.
            for x in 0..<26 where stecker[stecker[x]] != x { valid = false }
            if valid { tables.append(stecker) }
        }
        return tables
    }

    // MARK: Scoring

    private static func decrypt(
        ciphertext: [Int],
        stop: SweepStop,
        stecker: [Int]
    ) -> [Int] {
        let key = EnigmaM4Key(
            greek: EnigmaM4Warehouse.greek(named: stop.greek == "beta" ? "B" : "C"),
            rotors: stop.rotorTriple(),
            rings: stop.rings,
            positions: stop.stop.positions,
            plugboard: stecker,
            reflector: EnigmaM4Warehouse.thinReflector(named: stop.ukw)
        )
        var machine = EnigmaM4Machine(key: key)
        return machine.processText(ciphertext)
    }

    /// Score the stretch of plaintext the crib does not already guarantee.
    private static func tailScore(plain: [Int], menu: BombeMenu) -> Double {
        var tail: [Int] = []
        let cribRange = menu.offset..<(menu.offset + menu.edgeCount)
        for (index, letter) in plain.enumerated() where !cribRange.contains(index) {
            tail.append(letter)
        }
        return tail.count >= 3 ? GermanTrigrams.score(tail) : -10
    }

    /// Every ≤`maxPlugs` board that satisfies this stop's whole menu, not just the part
    /// its seed reached. Empty means the stop is physically impossible.
    ///
    /// Cheap enough to run on every stop as it drains off the GPU, which is what keeps
    /// a weak 12-letter menu from accumulating half a million dead survivors in memory.
    static func completions(for stop: SweepStop, maxPlugs: Int) -> [[Int]] {
        let triple = stop.rotorTriple()
        let bombe = WelchmanBombe(
            greek: EnigmaM4Warehouse.greek(named: stop.greek == "beta" ? "B" : "C"),
            left: triple.0, middle: triple.1, right: triple.2,
            reflector: EnigmaM4Warehouse.thinReflector(named: stop.ukw),
            rings: stop.rings,
            maxPlugs: maxPlugs
        )
        let scramblers = bombe.scramblers(menu: stop.menu, start: stop.stop.positions)
        return completedSteckers(menu: stop.menu, scramblers: scramblers, maxPlugs: maxPlugs)
    }

    /// Complete each stop's plugboard, decrypt all 72 letters, rank by trigram score.
    ///
    /// Completion is a second, stricter sieve before any statistics run. A stop whose
    /// menu admits no consistent ≤10-plug board is impossible, and is dropped rather
    /// than scored — scoring a decrypt made with a half-built plugboard is meaningless.
    ///
    /// Completions that clear the plug budget still face an IC gate before trigrams:
    /// a ghost can fluke a few naval trigrams, but it cannot fake a whole-string
    /// letter distribution (menu 627: IC 0.043 with a lucky tail of −4.070).
    static func rank(
        stops: [SweepStop],
        ciphertext: [Int],
        maxPlugs: Int = 10
    ) -> DiscriminationResult {
        var candidates: [DiscriminatedCandidate] = []
        var killed = 0
        var killedIC = 0

        for stop in stops {
            let tables = completions(for: stop, maxPlugs: maxPlugs)
            if tables.isEmpty {
                killed += 1
                continue
            }

            var best: DiscriminatedCandidate?
            var sawICFail = false
            for table in tables {
                let plain = decrypt(ciphertext: ciphertext, stop: stop, stecker: table)
                let ic = LanguageScorer.indexOfCoincidence(plain)
                // IC gate before trigrams — cheap, and decisive against noise.
                if ic < icFloor {
                    sawICFail = true
                    continue
                }
                let text = EnigmaAlphabet.string(from: plain)
                let cribLetters = EnigmaAlphabet.normalize(stop.menu.crib)
                let end = stop.menu.offset + cribLetters.count
                guard stop.menu.offset >= 0, end <= plain.count else { continue }
                let slice = Array(plain[stop.menu.offset..<end])
                let exact = slice == cribLetters
                let determined = (0..<26).filter { table[$0] != $0 }.count
                var pairs = 0
                for x in 0..<26 where table[x] != x { pairs += 1 }
                pairs /= 2

                let candidate = DiscriminatedCandidate(
                    stop: stop,
                    stecker: table,
                    plaintext: text,
                    ic: ic,
                    score: GermanTrigrams.score(plain),
                    tailScore: tailScore(plain: plain, menu: stop.menu),
                    cribExact: exact,
                    pairCount: pairs,
                    determinedLetters: determined
                )
                // A completion that reproduces the crib always beats one that does not.
                if best == nil
                    || (candidate.cribExact && !(best!.cribExact))
                    || (candidate.cribExact == best!.cribExact
                        && candidate.tailScore > best!.tailScore) {
                    best = candidate
                }
            }
            if let best {
                candidates.append(best)
            } else if sawICFail {
                killedIC += 1
            }
        }

        return DiscriminationResult(
            candidates: candidates.sorted {
                if $0.cribExact != $1.cribExact { return $0.cribExact }
                return $0.tailScore > $1.tailScore
            },
            killedByCompletion: killed,
            killedByIC: killedIC
        )
    }

    // MARK: Reporting

    /// Calibration, measured rather than assumed: real naval German from the P1030684
    /// decrypt, and the noise floor from the raw ciphertext (uniform by construction).
    static let germanReference: Double =
        GermanTrigrams.score(EnigmaAlphabet.normalize(ControlMessageP1030684.plaintext))
    static let noiseReference: Double =
        GermanTrigrams.score(EnigmaAlphabet.normalize(U534MessageP1030680.ciphertext))
    /// Stage 3 halt bar. Midway between German and noise (−4.114) admitted a
    /// 14-letter fluke at −4.070; −3.600 sits well clear of the noise floor and
    /// still well below real German (−2.85).
    static let breakThreshold: Double = -3.600
    /// Whole-string IC floor. Noise ≈ 0.038, German ≈ 0.07. The menu-627 ghost
    /// scored IC 0.043 — below this gate — while lucking a trigram tail past −4.114.
    static let icFloor: Double = 0.055

    static func report(_ result: DiscriminationResult, limit: Int) {
        let candidates = result.candidates
        print()
        print("=== Post-bombe discriminator ===")
        print("trigram model: \(GermanTrigrams.sourceDescription)")
        if result.killedByCompletion > 0 {
            print("stecker completion killed \(result.killedByCompletion) stop(s): no ≤10-plug "
                + "board satisfies the whole menu.")
            print("  Those stops survived the sweep only because the bombe seeds a single "
                + "letter, so it")
            print("  never tested the menu components that seed could not reach. "
                + "Completing every")
            print("  component is a strictly stronger sieve, and it is applied here.")
        }
        if result.killedByIC > 0 {
            print("IC gate (IC < \(icFloor)) killed \(result.killedByIC) completion(s) "
                + "before trigrams ran.")
        }
        guard !candidates.isEmpty else {
            print()
            if result.killedByIC > 0 && result.killedByCompletion == 0 {
                print("Every completion failed the IC gate (IC < \(icFloor)). "
                    + "Ghosts, not German.")
            } else {
                print("No stop admits a consistent plugboard that clears the IC gate. "
                    + "This crib is dead everywhere it was tried.")
            }
            return
        }
        print(String(format: "calibration: German %.3f, noise %.3f, break threshold %.3f, IC floor %.3f",
                     germanReference, noiseReference, breakThreshold, icFloor))
        print("ranking \(candidates.count) survivors on all 72 letters; "
            + "tail = the \(72 - candidates[0].stop.menu.edgeCount) letters the crib does not cover")
        print()
        print("  rank  crib  plugs     IC  tail-score  full-score  key   plaintext")
        print("  " + String(repeating: "-", count: 108))
        for (index, candidate) in candidates.prefix(limit).enumerated() {
            print(String(format: "  %4d  %@  %5d  %6.3f  %10.3f  %10.3f  %@  %@",
                         index + 1,
                         candidate.cribExact ? " ok " : "BAD ",
                         candidate.pairCount,
                         candidate.ic,
                         candidate.tailScore,
                         candidate.score,
                         candidate.messageKey,
                         String(candidate.plaintext.prefix(40))))
        }

        guard let winner = candidates.first else { return }
        let margin = candidates.count > 1
            ? winner.tailScore - candidates[1].tailScore
            : 0
        let looksGerman = isBreak(winner)

        print()
        if looksGerman {
            print("*** POTENTIAL BREAK ***")
        } else {
            print("=== Best candidate (NOT a break) ===")
        }
        print("  UKW \(winner.stop.ukw)  Greek \(winner.stop.greek)  "
            + "WO \(winner.stop.wheelOrder)  "
            + "rings \(EnigmaAlphabet.string(from: [winner.stop.rings.0, winner.stop.rings.1, winner.stop.rings.2, winner.stop.rings.3]))")
        print("  message key \(winner.messageKey)   (Grundstellung not recoverable — "
            + "the Grund table is lost, see BREAK_P1030680.md)")
        print("  stecker \(steckerString(winner.stecker)) (\(winner.pairCount) pairs)")
        print("  crib reproduced exactly: \(winner.cribExact)")
        print(String(format: "  IC %.3f (floor %.3f)  tail trigram %.3f vs German %.3f / noise %.3f, margin over #2 %.3f",
                     winner.ic, icFloor, winner.tailScore, germanReference, noiseReference, margin))
        print("  plaintext \(winner.plaintext)")
        if !looksGerman {
            print()
            print("  Failed the break gate (crib exact + IC ≥ \(icFloor) + tail > \(breakThreshold)).")
            print("  Ghosts that clear the board still die here.")
        }
    }

    /// Halt condition: crib exact, whole-string IC above the noise floor, and a
    /// trigram tail that clears the tightened bar.
    static func isBreak(_ candidate: DiscriminatedCandidate) -> Bool {
        candidate.cribExact
            && candidate.ic >= icFloor
            && candidate.tailScore > breakThreshold
    }

    /// The banner. Printed once, when a candidate clears every stage.
    static func announceBreak(_ winner: DiscriminatedCandidate) {
        let rule = String(repeating: "*", count: 78)
        print()
        print(rule)
        print("***  BREAK FOUND  ***")
        print(rule)
        print("  menu        \(winner.stop.menu.description)")
        print("  UKW         \(winner.stop.ukw)")
        print("  Greek       \(winner.stop.greek)")
        print("  wheel order \(winner.stop.wheelOrder)")
        print("  rings       \(EnigmaAlphabet.string(from: [winner.stop.rings.0, winner.stop.rings.1, winner.stop.rings.2, winner.stop.rings.3]))")
        print("  position    \(winner.messageKey)")
        print("  stecker     \(steckerString(winner.stecker)) (\(winner.pairCount) pairs)")
        print(String(format: "  IC          %.3f (floor %.3f)", winner.ic, icFloor))
        print(String(format: "  tail        %.3f vs German %.3f / noise %.3f",
                     winner.tailScore, germanReference, noiseReference))
        print()
        print("  \(winner.plaintext)")
        print(rule)
        fflush(stdout)
    }

    private static func steckerString(_ table: [Int]) -> String {
        var seen = Set<Int>()
        var pairs: [String] = []
        for x in 0..<26 where table[x] != x && !seen.contains(x) {
            seen.insert(x)
            seen.insert(table[x])
            pairs.append("\(EnigmaAlphabet.character(x))\(EnigmaAlphabet.character(table[x]))")
        }
        return pairs.isEmpty ? "(none)" : pairs.sorted().joined(separator: " ")
    }

    // MARK: Forensics

    /// Dissect one setting: "UKW:greek:WO:rings:pos:CRIB@offset".
    ///
    /// Exists because a stop is only as strong as the part of the menu that was
    /// actually tested. This prints the component structure so you can see how much
    /// of the menu the bombe's single seed ever reached.
    static func inspect(spec: String) {
        let field = spec.split(separator: ":").map(String.init)
        guard field.count == 6 else {
            print("usage: --bombe-inspect B:beta:III-IV-VII:AAAZ:TKIK:CRIB@0")
            return
        }
        let placement = field[5].split(separator: "@", maxSplits: 1)
        guard placement.count == 2, let offset = Int(placement[1]) else {
            print("crib must be written CRIB@offset")
            return
        }
        let cribText = String(placement[0])
        let cipher = EnigmaAlphabet.normalize(U534MessageP1030680.ciphertext)
        guard let menu = BombeMenuBuilder.menu(
            crib: cribText, offset: offset, ciphertext: cipher
        ) else {
            print("illegal placement (self-encipherment)")
            return
        }

        let rings = EnigmaM4Key.rings(fromLetters: field[3])
        let position = EnigmaAlphabet.normalize(field[4])
        let start = (position[0], position[1], position[2], position[3])
        let names = field[2].split(separator: "-").map(String.init)
        func rotor(_ name: String) -> EnigmaRotorSpec {
            M4ThetisAttack.navalRotors.first { $0.name == name } ?? EnigmaWarehouse.rotorI
        }
        let bombe = WelchmanBombe(
            greek: EnigmaM4Warehouse.greek(named: field[1] == "beta" ? "B" : "C"),
            left: rotor(names[0]), middle: rotor(names[1]), right: rotor(names[2]),
            reflector: EnigmaM4Warehouse.thinReflector(named: field[0]),
            rings: rings,
            maxPlugs: 10
        )
        let scramblers = bombe.scramblers(menu: menu, start: start)

        print("=== Setting forensics ===")
        print("  \(menu.description)")
        print("  UKW \(field[0]) Greek \(field[1]) WO \(field[2]) rings \(field[3]) pos \(field[4])")

        let groups = components(of: menu)
        print("  menu splits into \(groups.count) component(s):")
        for (index, group) in groups.enumerated() {
            let letters = group.sorted().map { String(EnigmaAlphabet.character($0)) }.joined()
            var survivors: [Int] = []
            for value in 0..<26 where WelchmanBombe.propagate(
                menu: menu, scramblers: scramblers,
                seedLetter: group[0], seedValue: value
            ) != nil {
                survivors.append(value)
            }
            print("    [\(index + 1)] \(group.count) letters {\(letters)} — "
                + "\(survivors.count)/26 seeds survive on their own")
        }

        let tables = completedSteckers(menu: menu, scramblers: scramblers, maxPlugs: 10)
        print("  joint completions consistent across all components at ≤10 plugs: \(tables.count)")
        if tables.isEmpty {
            print("  VERDICT: dead. The single-seed bombe kept this setting only because it")
            print("           never tested the components its seed could not reach.")
            return
        }
        for table in tables.prefix(6) {
            var pairs = 0
            for x in 0..<26 where table[x] != x { pairs += 1 }
            print("    \(steckerString(table)) (\(pairs / 2) pairs)")
        }
        print("  VERDICT: live — \(tables.count) plugboard(s) satisfy the whole menu.")
    }
}
