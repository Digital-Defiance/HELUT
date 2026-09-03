import Foundation
import HELUTCore
import HELUTCLI

// MARK: - Ciphertext-only length threshold, measured on 48 known-key M4 controls
//
// Ostwald and Weierud's ciphertext-only attack uses no crib: for each candidate rotor
// setting it hill-climbs the plugboard and ranks the setting by the score the climb
// reaches. Their published reach is messages down to about 100 letters, with 78 the
// shortest they have broken — on three-rotor Heer traffic. P1030680 is 72 letters on
// four-rotor naval M4, i.e. shorter than the record on a harder machine.
//
// The wall is not compute. 72 letters of naval German carries ~223 bits of redundancy; a
// ten-plug board is ~47 bits of nuisance parameter *fitted per candidate*; and the shell x
// position space is ~10^11 candidates. Taking the maximum of an overfitted score over that
// many candidates is a multiple-comparisons problem, and adding compute makes it worse by
// raising the maximum of the noise. So the quantity that decides everything is not a rate.
// It is the **margin**:
//
//     margin = climbedScore(true setting) - max climbedScore(wrong settings)
//
// If the margin is positive at a given message length, a full sweep can in principle find
// the key. If it is negative, no amount of hardware will, because the search is ranking
// noise above signal. This harness measures that margin directly, at a ladder of lengths,
// on the 48 published 1 May 1945 U-534 keys — same net, same signals office, same German
// dialect as the target. Two of those controls are 60 and 68 letters, i.e. shorter than
// P1030680 itself.

/// Which statistic the plugboard climb optimises.
///
/// `enigma-cuda` (the reference implementation of this attack, which also carries Ostwald's
/// partial exhaustion) defaults to scoring sequence `023` = IC, bigrams, trigrams. HELUT's
/// existing climb is bigram-only, so `staged` is the first thing worth measuring against it.
enum ClimbScorer: String, CaseIterable {
    /// What `ExhaustiveCracker.hillClimb` does today.
    case bigram
    /// Trigrams throughout. 14,947 grams over 28.5M letters of German.
    case trigram
    /// IC while the board is nearly empty, then bigrams, then trigrams — `enigma-cuda` 023.
    ///
    /// The staging exists because the measures fail at different times. With no plugs the
    /// text is letter-substituted, so bigram and trigram structure is destroyed while IC
    /// survives; once a few plugs are right the n-grams become far more discriminating.
    case staged

    /// Statistic to optimise when `placed` plugs are already on the board.
    ///
    /// `trigramTable`, when supplied, replaces the generic German trigram model at every
    /// stage that uses trigrams. Passing it is the whole A/B: same scorer, same staging,
    /// different language model.
    func measure(placed: Int, trigramTable: [Double]? = nil) -> (([Int]) -> Double) {
        let trigram: ([Int]) -> Double = { letters in
            if let trigramTable { return NavalGrams.score(letters, table: trigramTable) }
            return GermanTrigrams.score(letters)
        }
        switch self {
        case .bigram: return LanguageScorer.bigramScore
        case .trigram: return trigram
        case .staged:
            if placed < 2 { return LanguageScorer.indexOfCoincidence }
            if placed < 5 { return LanguageScorer.bigramScore }
            return trigram
        }
    }
}

/// One published U-534 key, ready to be truncated and attacked.
struct KnownControl {
    let id: String
    let ciphertext: [Int]
    let plaintext: [Int]
    let key: EnigmaM4Key
    let truePairs: [(Int, Int)]

    var length: Int { ciphertext.count }
}

enum OstwaldCurve {

    // MARK: Corpus

    private struct CorpusFile: Decodable {
        struct Message: Decodable {
            let id: String
            let ciphertext: String?
            let plaintext: String?
            let reflector: String?
            let greek: String?
            let wheels: String?
            let rings: String?
            let wheel_positions: String?
            let plugs: String?
            let broken: Bool?
        }
        let messages: [Message]
    }

    private static func plugTable(_ text: String) -> ([Int], [(Int, Int)]) {
        var table = Array(0..<26)
        var pairs: [(Int, Int)] = []
        for token in text.split(separator: " ") where token.count == 2 {
            let letters = Array(token)
            let a = EnigmaAlphabet.index(letters[0])
            let b = EnigmaAlphabet.index(letters[1])
            guard a >= 0, a < 26, b >= 0, b < 26 else { continue }
            table[a] = b
            table[b] = a
            pairs.append((min(a, b), max(a, b)))
        }
        return (table, pairs)
    }

    /// Every message in the scrape whose key is published, as an attackable control.
    static func loadControls(path: String) -> [KnownControl] {
        guard let data = FileManager.default.contents(atPath: path),
              let file = try? JSONDecoder().decode(CorpusFile.self, from: data) else {
            return []
        }
        var controls: [KnownControl] = []
        for message in file.messages {
            guard message.broken == true,
                  let ct = message.ciphertext, let pt = message.plaintext,
                  let reflector = message.reflector, let greek = message.greek,
                  let wheels = message.wheels, let rings = message.rings,
                  let positions = message.wheel_positions, let plugs = message.plugs,
                  wheels.count == 3, rings.count == 4, positions.count == 4
            else { continue }
            let rotors = Array(wheels).map { EnigmaWarehouse.rotor(named: String($0)) }
            let (table, pairs) = plugTable(plugs)
            guard pairs.count == 10 else { continue }
            let key = EnigmaM4Key(
                greek: EnigmaM4Warehouse.greek(named: greek),
                rotors: (rotors[0], rotors[1], rotors[2]),
                rings: EnigmaM4Key.rings(fromLetters: rings),
                positions: EnigmaM4Key.positions(fromLetters: positions),
                plugboard: table,
                reflector: EnigmaM4Warehouse.thinReflector(named: reflector)
            )
            controls.append(
                KnownControl(
                    id: message.id,
                    ciphertext: EnigmaAlphabet.normalize(ct),
                    plaintext: EnigmaAlphabet.normalize(pt),
                    key: key,
                    truePairs: pairs
                )
            )
        }
        return controls.sorted { $0.length < $1.length }
    }

    // MARK: Climb

    /// Greedy plug insertion then a replacement pass, with a pluggable statistic and
    /// optional pre-seeded plugs (Ostwald's partial exhaustion / a bombe's forced board).
    ///
    /// Seeded pairs are held fixed: they are not removed by the replacement pass. That is
    /// the point of seeding — it removes their freedom from the fit, which is what shifts
    /// the length threshold.
    static func climb(
        key: EnigmaM4Key,
        ciphertext: [Int],
        scorer: ClimbScorer,
        maxPlugs: Int = 10,
        seeded: [(Int, Int)] = [],
        trigramTable: [Double]? = nil,
        reconnectPasses: Int = 0
    ) -> (pairs: [(Int, Int)], score: Double, plain: [Int]) {
        var plain = [Int](repeating: 0, count: ciphertext.count)
        var pairs = seeded
        var used = [Bool](repeating: false, count: 26)
        for pair in seeded { used[pair.0] = true; used[pair.1] = true }

        func decrypt(_ candidate: [(Int, Int)]) -> [Int] {
            var table = Array(0..<26)
            for pair in candidate {
                table[pair.0] = pair.1
                table[pair.1] = pair.0
            }
            let working = EnigmaM4Key(
                greek: key.greek, rotors: key.rotors, rings: key.rings,
                positions: key.positions, plugboard: table, reflector: key.reflector
            )
            var machine = EnigmaM4Machine(key: working)
            var out = [Int](repeating: 0, count: ciphertext.count)
            for index in ciphertext.indices { out[index] = machine.process(ciphertext[index]) }
            return out
        }

        // Greedy insertion. The statistic can change as the board fills (staged scoring),
        // so `best` is re-baselined whenever the measure does.
        var measure = scorer.measure(placed: pairs.count, trigramTable: trigramTable)
        var best = measure(decrypt(pairs))
        while pairs.count < maxPlugs {
            let next = scorer.measure(placed: pairs.count, trigramTable: trigramTable)
            // A new stage is a different scale; re-baseline before comparing against it.
            if scorer == .staged { best = next(decrypt(pairs)) }
            measure = next
            var bestPair: (Int, Int)?
            var bestScore = best
            for a in 0..<26 where !used[a] {
                for b in (a + 1)..<26 where !used[b] {
                    let score = measure(decrypt(pairs + [(a, b)]))
                    if score > bestScore {
                        bestScore = score
                        bestPair = (a, b)
                    }
                }
            }
            guard let pair = bestPair else { break }
            pairs.append(pair)
            used[pair.0] = true
            used[pair.1] = true
            best = bestScore
        }

        let final = scorer.measure(placed: maxPlugs, trigramTable: trigramTable)

        // Break-and-reconnect passes: the neighborhood the classic stecker climb uses and
        // greedy insertion cannot reach.
        //
        // Greedy insertion only ever considers pairs whose *both* letters are currently
        // unplugged, so it can add plugs but never re-pair. If it commits to A-B early on
        // thin evidence, no later move can propose "break A-B and C-D, make A-C and B-D",
        // and one bad first choice poisons the rest of the board. That is exactly the trap
        // Ostwald's partial exhaustion works around from the outside — and the same trap is
        // worth removing from the inside.
        //
        // For each letter pair (i, j) with current partners a = σ(i), b = σ(j), the
        // candidate boards are: plug i-j and orphan the displaced letters; or, when both
        // were already plugged, the two ways of re-pairing the four letters {i, a, j, b}
        // that keep the plug count — i-j with a-b, and i-b with a-j. Passes repeat until one
        // makes no improvement. Seeded plugs are immovable throughout.
        if reconnectPasses > 0 {
            var table = Array(0..<26)
            for pair in pairs { table[pair.0] = pair.1; table[pair.1] = pair.0 }
            let locked = Set(seeded.flatMap { [$0.0, $0.1] })

            func pairList(_ board: [Int]) -> [(Int, Int)] {
                var out: [(Int, Int)] = []
                for x in 0..<26 where board[x] != x && x < board[x] { out.append((x, board[x])) }
                return out
            }
            // enigma-cuda orders its swaps by ciphertext letter frequency by default; the
            // most frequent letters are the ones most likely to be steckered.
            var frequency = [Int](repeating: 0, count: 26)
            for letter in ciphertext { frequency[letter] += 1 }
            let order = (0..<26).sorted { frequency[$0] > frequency[$1] }

            for _ in 0..<reconnectPasses {
                var improvedThisPass = false
                for oi in 0..<26 {
                    for oj in (oi + 1)..<26 {
                        let i = order[oi], j = order[oj]
                        if locked.contains(i) || locked.contains(j) { continue }
                        let a = table[i], b = table[j]
                        if locked.contains(a) || locked.contains(b) { continue }

                        var candidates: [[Int]] = []
                        if a == j {
                            // Already plugged to each other — try removing the lead.
                            var next = table
                            next[i] = i; next[j] = j
                            candidates.append(next)
                        } else {
                            // Plug i-j, orphaning whatever i and j were connected to.
                            var next = table
                            if a != i { next[a] = a }
                            if b != j { next[b] = b }
                            next[i] = j; next[j] = i
                            candidates.append(next)
                            // Both were plugged: the two count-preserving re-pairings.
                            if a != i && b != j {
                                var cross = table
                                cross[i] = j; cross[j] = i
                                cross[a] = b; cross[b] = a
                                candidates.append(cross)
                                var other = table
                                other[i] = b; other[b] = i
                                other[a] = j; other[j] = a
                                candidates.append(other)
                            }
                        }

                        let current = pairList(table)
                        let measureNow = scorer.measure(
                            placed: current.count, trigramTable: trigramTable
                        )
                        var bestBoard = table
                        var bestLocal = measureNow(decrypt(current))
                        for candidate in candidates {
                            let asPairs = pairList(candidate)
                            if maxPlugs > 0 && asPairs.count > maxPlugs { continue }
                            let score = measureNow(decrypt(asPairs))
                            if score > bestLocal {
                                bestLocal = score
                                bestBoard = candidate
                            }
                        }
                        if bestBoard != table {
                            table = bestBoard
                            improvedThisPass = true
                        }
                    }
                }
                if !improvedThisPass { break }
            }
            pairs = pairList(table)
            plain = decrypt(pairs)
            return (pairs, final(plain), plain)
        }

        // Replacement pass under the final statistic. Seeded plugs are immovable.
        best = final(decrypt(pairs))
        for index in pairs.indices where index >= seeded.count {
            let original = pairs[index]
            used[original.0] = false
            used[original.1] = false
            var rest = pairs
            rest.remove(at: index)
            var bestPair = original
            var bestScore = best
            for a in 0..<26 where !used[a] {
                for b in (a + 1)..<26 where !used[b] {
                    let score = final(decrypt(rest + [(a, b)]))
                    if score > bestScore {
                        bestScore = score
                        bestPair = (a, b)
                    }
                }
            }
            pairs[index] = bestPair
            used[bestPair.0] = true
            used[bestPair.1] = true
            best = bestScore
        }

        plain = decrypt(pairs)
        return (pairs, final(plain), plain)
    }

    /// Ostwald and Weierud's partial exhaustion: instead of climbing from an empty board,
    /// fix one plug and climb the rest, repeating over every candidate for that plug.
    ///
    /// Why it works is the overfitting argument. Climbing all ten plugs from empty means
    /// the greedy first choice is made on the weakest possible evidence, and a wrong first
    /// plug poisons everything after it. Fixing a plug removes it from the fit and gives
    /// the climb a basin to start in; one of the fixed candidates is the true plug, and
    /// that run climbs out of a far better starting point than any empty-board run.
    ///
    /// `enigma-cuda` exposes this as `-e <letters>`, trying each listed letter against all
    /// 25 partners; for six letters that is 141 distinct fixed plugs after removing the
    /// duplicates where both endpoints are listed. Letters are taken in ciphertext
    /// frequency order, which is also how that implementation orders its swaps by default.
    static func climbExhaustive(
        key: EnigmaM4Key,
        ciphertext: [Int],
        scorer: ClimbScorer,
        maxPlugs: Int = 10,
        exhaustLetters: Int,
        alsoSeeded: [(Int, Int)] = [],
        trigramTable: [Double]? = nil,
        reconnectPasses: Int = 0
    ) -> (pairs: [(Int, Int)], score: Double, plain: [Int]) {
        guard exhaustLetters > 0 else {
            return climb(key: key, ciphertext: ciphertext, scorer: scorer,
                         maxPlugs: maxPlugs, seeded: alsoSeeded,
                         trigramTable: trigramTable, reconnectPasses: reconnectPasses)
        }
        var frequency = [Int](repeating: 0, count: 26)
        for letter in ciphertext { frequency[letter] += 1 }
        let hot = (0..<26).sorted { frequency[$0] > frequency[$1] }.prefix(exhaustLetters)
        let locked = Set(alsoSeeded.flatMap { [$0.0, $0.1] })

        var seeds: Set<[Int]> = []
        for a in hot where !locked.contains(a) {
            for b in 0..<26 where b != a && !locked.contains(b) {
                seeds.insert([min(a, b), max(a, b)])
            }
        }

        var best: (pairs: [(Int, Int)], score: Double, plain: [Int])?
        for seed in seeds {
            let result = climb(
                key: key, ciphertext: ciphertext, scorer: scorer, maxPlugs: maxPlugs,
                seeded: alsoSeeded + [(seed[0], seed[1])], trigramTable: trigramTable,
                reconnectPasses: reconnectPasses
            )
            if best == nil || result.score > best!.score { best = result }
        }
        return best ?? climb(key: key, ciphertext: ciphertext, scorer: scorer,
                             maxPlugs: maxPlugs, seeded: alsoSeeded,
                             trigramTable: trigramTable,
                             reconnectPasses: reconnectPasses)
    }

    // MARK: Measurement

    struct CurvePoint {
        let id: String
        let length: Int
        let scorer: ClimbScorer
        /// Climbed score at the true rotor setting.
        let trueScore: Double
        /// Best climbed score over the sampled wrong rotor settings.
        let wrongBest: Double
        let wrongMean: Double
        let wrongDeviation: Double
        /// True plugs the climb actually recovered, of 10.
        let plugsRecovered: Int
        /// Letters matching the published plaintext.
        let lettersCorrect: Int
        /// Positive means signal outranks the sampled noise at this length.
        var margin: Double { trueScore - wrongBest }
        var z: Double {
            wrongDeviation > 0 ? (trueScore - wrongMean) / wrongDeviation : .infinity
        }
    }

    /// Wrong settings are drawn from the same *shell* as the truth, differing only in
    /// message key. That is deliberately the hardest possible negative control: a real
    /// sweep also enumerates wrong wheel orders and rings, which are easier to reject, so
    /// a margin measured this way is conservative.
    /// `exhaustLetters` applies to the true *and* the wrong settings. That symmetry is not
    /// optional: giving the truth 141 attempts at maximising its score while each decoy
    /// gets one would manufacture a margin out of nothing.
    ///
    /// `seededPlugs` models the bombe coupling, which is the lever only this repository can
    /// pull: a Welchman stop arrives with the stecker its menu forced, 15–24 of 26 letters
    /// of it. The model has to be fair about what that means at a *wrong* setting, so the
    /// true setting is seeded with `seededPlugs` genuinely correct plugs (what a true stop
    /// forces) while every decoy is seeded with the same number of *random* plugs (what a
    /// ghost stop forces). Seeded plugs are immovable in the climb, which is the whole
    /// point — they leave the fit, and the overfitting term shrinks with them.
    ///
    /// Note this is an *oracle-seeded* measurement and therefore an upper bound on the real
    /// coupling: it assumes the stop being seeded from is the true key. It answers "if a
    /// bombe hands us k correct plugs, does the margin go positive at this length" — which
    /// is exactly what decides whether the wiring is worth building.
    static func measure(
        control: KnownControl,
        length: Int,
        scorer: ClimbScorer,
        wrongSamples: Int,
        seed: UInt64,
        exhaustLetters: Int = 0,
        seededPlugs: Int = 0,
        navalCorpus: NavalGramCorpus? = nil,
        reconnectPasses: Int = 0,
        lexicon: NavalLexicon? = nil
    ) -> CurvePoint? {
        guard control.length >= length, control.plaintext.count >= length else { return nil }
        let ct = Array(control.ciphertext.prefix(length))
        let pt = Array(control.plaintext.prefix(length))

        let stripped = EnigmaM4Key(
            greek: control.key.greek, rotors: control.key.rotors, rings: control.key.rings,
            positions: control.key.positions, plugboard: Array(0..<26),
            reflector: control.key.reflector
        )
        // Leave-one-out: this control's own plaintext is withheld from the naval counts,
        // otherwise the model would be scoring its memory of the answer.
        let trigramTable = navalCorpus?.table(excluding: control.id)

        var generator = SplitMix64(seed: seed)

        // The true setting gets genuinely correct plugs, as a true bombe stop would force.
        let oracleSeed = Array(control.truePairs.prefix(max(0, seededPlugs)))
        let truth = climbExhaustive(
            key: stripped, ciphertext: ct, scorer: scorer,
            exhaustLetters: exhaustLetters, alsoSeeded: oracleSeed,
            trigramTable: trigramTable, reconnectPasses: reconnectPasses
        )
        // The lexicon is a *discriminator*, not a climbing objective: the climb above ran on
        // the staged statistic exactly as before, and only the number the margin is taken on
        // changes. A sparse score has no gradient for a hill-climb to follow.
        let trueScore = lexicon.map { $0.score(truth.plain, excluding: control.id) }
            ?? truth.score
        let trueSet = Set(truth.pairs.map { "\(min($0.0, $0.1))-\(max($0.0, $0.1))" })
        let wanted = Set(control.truePairs.map { "\($0.0)-\($0.1)" })
        let recovered = trueSet.intersection(wanted).count
        let correct = zip(truth.plain, pt).reduce(0) { $0 + ($1.0 == $1.1 ? 1 : 0) }

        /// A ghost stop's forced board: the right *number* of plugs, none of them right.
        func randomPairs(_ count: Int) -> [(Int, Int)] {
            var pool = Array(0..<26)
            for index in stride(from: 25, to: 0, by: -1) {
                let swap = Int(generator.next() % UInt64(index + 1))
                pool.swapAt(index, swap)
            }
            var pairs: [(Int, Int)] = []
            var cursor = 0
            while pairs.count < count && cursor + 1 < pool.count {
                let a = pool[cursor], b = pool[cursor + 1]
                pairs.append((min(a, b), max(a, b)))
                cursor += 2
            }
            return pairs
        }

        var scores: [Double] = []
        scores.reserveCapacity(wrongSamples)
        for _ in 0..<wrongSamples {
            var positions = (
                Int(generator.next() % 26), Int(generator.next() % 26),
                Int(generator.next() % 26), Int(generator.next() % 26)
            )
            if positions == control.key.positions { positions.3 = (positions.3 + 13) % 26 }
            let wrong = EnigmaM4Key(
                greek: control.key.greek, rotors: control.key.rotors, rings: control.key.rings,
                positions: positions, plugboard: Array(0..<26),
                reflector: control.key.reflector
            )
            let wrongResult = climbExhaustive(
                    key: wrong, ciphertext: ct, scorer: scorer,
                    exhaustLetters: exhaustLetters,
                    alsoSeeded: randomPairs(max(0, seededPlugs)),
                    trigramTable: trigramTable, reconnectPasses: reconnectPasses
            )
            scores.append(
                lexicon.map { $0.score(wrongResult.plain, excluding: control.id) }
                    ?? wrongResult.score
            )
        }
        let mean = scores.reduce(0, +) / Double(max(scores.count, 1))
        let variance = scores.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
            / Double(max(scores.count - 1, 1))

        return CurvePoint(
            id: control.id, length: length, scorer: scorer,
            trueScore: trueScore,
            wrongBest: scores.max() ?? -.infinity,
            wrongMean: mean, wrongDeviation: variance.squareRoot(),
            plugsRecovered: recovered, lettersCorrect: correct
        )
    }
}

/// Deterministic RNG so a curve is reproducible run to run.
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
