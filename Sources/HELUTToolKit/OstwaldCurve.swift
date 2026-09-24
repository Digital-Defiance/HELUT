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

/// Recorded-letter decrypt walk. Dense Ostwald treats the 72-letter intercept as consecutive
/// machine steps. A leading-gap walk dummy-steps `leadingHoles` times first so later letters
/// sit at the transmitted rotor positions; scoring still sees only the recorded plaintext.
package struct OstwaldWalk: Equatable, Sendable {
    package let leadingHoles: Int

    package static let dense = OstwaldWalk(leadingHoles: 0)

    package static func leadingGap(_ holes: Int) -> OstwaldWalk {
        OstwaldWalk(leadingHoles: max(0, holes))
    }
}

/// Partial-exhaustion / top-up start sets. Two knobs stay distinct:
/// `exhaustLetters` is Ostwald `-e` (hot ciphertext endpoints); plug *count* is how many
/// disjoint pairs those letters are asked to supply.
package enum OstwaldExhaust {
    /// Phase 54.4 measured cell: depth 2 × exhaust 6. Four *correct* plugs are a board
    /// seed / top-up target, not this hot-letter width.
    package static let measuredLetters = 6
    package static let measuredDepth = 2
    package static let measuredTopUpTo = 4
    /// Four disjoint pairs need eight letters. Exhaust 6 cannot host a 4-plug brute.
    package static let fourPlugMinLetters = 8
    /// Depth-1 receipts saturate by ~10 hot letters; do not widen a 4-plug brute past 12
    /// without an explicit `--ostwald-brute-all`.
    package static let fourPlugMaxLetters = 12
    /// Full alphabet. C(26,8)×105 = 164,038,875 four-plug boards.
    package static let fourPlugAlphabetLetters = 26
    /// 7!! = number of perfect matchings on eight letters.
    package static let fourPlugMatchingsOnEight = 105
    /// Do not materialize more starts than this as a Swift array. Full-alphabet brute
    /// streams in chunks instead (Phase 67).
    package static let fourPlugMaterializeCap = 50_000
    /// Floor for a streamed 4-plug chunk. The live wave is `fourPlugWaveJobs(trialCap:)`.
    package static let fourPlugChunkSize = 8_192
    /// Host-side 4-plug jobs in one Metal greedy wave. Round 1 is 154 trials/job, so
    /// 524,288 jobs ≈ 2.6 GB of 32-byte records — well under the 48–56 GB unified
    /// budget. The 64 GB machine is not the limiter; 8,192-job waves plus a CPU polish
    /// of every ghost were.
    package static let fourPlugWaveJobsCap = 524_288

    /// Jobs per streamed 4-plug Metal wave. Sized from the trial budget, then capped
    /// so host packing stays a couple of gigabytes rather than tens.
    package static func fourPlugWaveJobs(trialCap: Int) -> Int {
        let round1 = 1 + OstwaldProgress.unusedPairCount(placed: 4)
        let fromBudget = trialCap / max(1, round1)
        return min(fourPlugWaveJobsCap, max(fourPlugChunkSize, fromBudget))
    }
    /// ~2 settings × 164M × 671 decrypts at the 10M floor is already a workday.
    /// More than this needs `--ostwald-brute-settings-ok`.
    package static let fourPlugDecryptCapWithoutOverride = 200_000_000_000

    package enum Error: Swift.Error, CustomStringConvertible, Equatable {
        case fourPlugNeedsEightHotLetters(exhaustLetters: Int)
        case fourPlugSaturationTrap(exhaustLetters: Int)
        case fourPlugWouldMaterialize(count: Int)

        package var description: String {
            switch self {
            case let .fourPlugNeedsEightHotLetters(n):
                return "4-plug hot-letter brute needs --ostwald-exhaust ≥ 8 (got \(n)); "
                    + "four pairs use eight letters. Exhaust 6 is the depth-2 cell, not a 4-plug cell."
            case let .fourPlugSaturationTrap(n):
                return "4-plug hot-letter brute at exhaust \(n) is the Phase 54.4 saturation trap. "
                    + "Pass --ostwald-brute-all to force it."
            case let .fourPlugWouldMaterialize(count):
                return "4-plug brute has \(count) starts; that is streamed, not allocated. "
                    + "Lock one setting: --ostwald-all-settings --ostwald-control p1030684 "
                    + "--ostwald-setting-count 1 --ostwald-brute-plugs 4 --ostwald-brute-all "
                    + "--ostwald-exhaust 26."
            }
        }
    }

    /// C(n,8) × 105. Zero if n < 8.
    package static func fourPlugStartCount(letterCount: Int) -> Int {
        guard letterCount >= fourPlugMinLetters else { return 0 }
        var choose = 1
        for i in 0..<fourPlugMinLetters {
            choose = choose * (letterCount - i) / (i + 1)
        }
        return choose * fourPlugMatchingsOnEight
    }

    /// Index-pair patterns for the 105 matchings on eight ordered letters.
    package static let fourPlugIndexPatterns: [[(Int, Int)]] = perfectMatchings(Array(0..<8))

    package static func fourPlugPool(
        ciphertext: [Int],
        exhaustLetters: Int,
        locked: Set<Int>
    ) -> [Int] {
        hotLetters(ciphertext: ciphertext, count: exhaustLetters)
            .filter { !locked.contains($0) }
    }

    /// Perfect matchings on `2k` letters: `(2k-1)!!` pairings.
    package static func perfectMatchings(_ letters: [Int]) -> [[(Int, Int)]] {
        let sorted = letters.sorted()
        guard sorted.count % 2 == 0 else { return [] }
        if sorted.isEmpty { return [[]] }

        func rec(_ remaining: [Int]) -> [[(Int, Int)]] {
            if remaining.isEmpty { return [[]] }
            let first = remaining[0]
            var out: [[(Int, Int)]] = []
            for index in 1..<remaining.count {
                let mate = remaining[index]
                var rest: [Int] = []
                rest.reserveCapacity(remaining.count - 2)
                for (j, letter) in remaining.enumerated() where j != 0 && j != index {
                    rest.append(letter)
                }
                for tail in rec(rest) {
                    out.append([(first, mate)] + tail)
                }
            }
            return out
        }
        return rec(sorted)
    }

    package static func hotLetters(ciphertext: [Int], count: Int) -> [Int] {
        var frequency = [Int](repeating: 0, count: 26)
        for letter in ciphertext where (0..<26).contains(letter) {
            frequency[letter] += 1
        }
        return Array((0..<26).sorted { frequency[$0] > frequency[$1] }.prefix(max(0, count)))
    }

    /// Depth-1/2 start sets from the published `-e` construction: each hot letter against
    /// every unused partner, then disjoint combinations at depth 2.
    package static func hotPartnerStarts(
        ciphertext: [Int],
        exhaustLetters: Int,
        exhaustDepth: Int,
        locked: Set<Int>
    ) -> [[(Int, Int)]] {
        let depth = max(1, exhaustDepth)
        let hot = hotLetters(ciphertext: ciphertext, count: exhaustLetters)
        var seeds: Set<[Int]> = []
        for a in hot where !locked.contains(a) {
            for b in 0..<26 where b != a && !locked.contains(b) {
                seeds.insert([min(a, b), max(a, b)])
            }
        }
        let ordered = seeds.sorted { ($0[0], $0[1]) < ($1[0], $1[1]) }
        if depth == 1 {
            return ordered.map { [($0[0], $0[1])] }
        }
        var startSets: [[(Int, Int)]] = []
        for i in ordered.indices {
            for j in ordered.indices where j > i {
                let left = ordered[i], right = ordered[j]
                if left[0] == right[0] || left[0] == right[1]
                    || left[1] == right[0] || left[1] == right[1] { continue }
                startSets.append([(left[0], left[1]), (right[0], right[1])])
            }
        }
        return startSets
    }

    /// Yield every 4-plug perfect matching on eight-letter subsets of `pool`.
    /// Patterns are computed once; the 164M full-alphabet board is not stored.
    package static func visitFourPlugStarts(
        pool: [Int],
        body: ([(Int, Int)]) throws -> Void
    ) rethrows {
        let n = pool.count
        guard n >= fourPlugMinLetters else { return }
        var choose = [Int](0..<fourPlugMinLetters)
        let patterns = fourPlugIndexPatterns
        while true {
            let letters = choose.map { pool[$0] }.sorted()
            for pattern in patterns {
                try body(pattern.map { (letters[$0.0], letters[$0.1]) })
            }
            var i = fourPlugMinLetters - 1
            while i >= 0 && choose[i] == n - fourPlugMinLetters + i { i -= 1 }
            if i < 0 { return }
            choose[i] += 1
            var j = i + 1
            while j < fourPlugMinLetters {
                choose[j] = choose[j - 1] + 1
                j += 1
            }
        }
    }

    package static func fourPlugStarts(
        ciphertext: [Int],
        exhaustLetters: Int,
        locked: Set<Int>,
        bruteAll: Bool
    ) throws -> [[(Int, Int)]] {
        if exhaustLetters < fourPlugMinLetters {
            throw Error.fourPlugNeedsEightHotLetters(exhaustLetters: exhaustLetters)
        }
        if exhaustLetters > fourPlugMaxLetters && !bruteAll {
            throw Error.fourPlugSaturationTrap(exhaustLetters: exhaustLetters)
        }
        let pool = fourPlugPool(
            ciphertext: ciphertext, exhaustLetters: exhaustLetters, locked: locked
        )
        let count = fourPlugStartCount(letterCount: pool.count)
        if count > fourPlugMaterializeCap {
            throw Error.fourPlugWouldMaterialize(count: count)
        }
        guard pool.count >= fourPlugMinLetters else { return [] }
        var starts: [[(Int, Int)]] = []
        starts.reserveCapacity(count)
        try visitFourPlugStarts(pool: pool) { starts.append($0) }
        return starts
    }

    /// How many true plugs have both ends in the hot-letter pool. Four such plugs on eight
    /// letters is a perfect matching, so one `--ostwald-brute-plugs 4` start is fully correct.
    package static func truePlugsInsideHotSet(
        ciphertext: [Int],
        truePairs: [(Int, Int)],
        exhaustLetters: Int
    ) -> Int {
        let hot = Set(hotLetters(ciphertext: ciphertext, count: exhaustLetters))
        return truePairs.filter { hot.contains($0.0) && hot.contains($0.1) }.count
    }

    /// Board seeds held fixed. If they already supply `topUpTo` plugs, return a single empty
    /// extra start (just climb). If there are no seeds, use the measured depth-2 × exhaust-6
    /// cell — not a 4-plug brute. Otherwise add `min(needed, exhaustDepth)` hot-letter plugs.
    package static func startSets(
        ciphertext: [Int],
        exhaustLetters: Int,
        exhaustDepth: Int,
        alsoSeeded: [(Int, Int)],
        topUpTo: Int = 0,
        brutePlugs: Int = 0,
        bruteAll: Bool = false
    ) throws -> [[(Int, Int)]] {
        let locked = Set(alsoSeeded.flatMap { [$0.0, $0.1] })
        // Literal 4-plug brute is an empty-board attack. Partial board seeds fall
        // through to top-up (or just climb) instead of adding four *extra* pairs.
        if brutePlugs >= 4, alsoSeeded.isEmpty {
            return try fourPlugStarts(
                ciphertext: ciphertext,
                exhaustLetters: exhaustLetters,
                locked: locked,
                bruteAll: bruteAll
            )
        }
        if brutePlugs >= 4, alsoSeeded.count >= brutePlugs {
            return [[]]
        }
        if topUpTo > 0, alsoSeeded.count >= topUpTo {
            return [[]]
        }
        let needed = topUpTo > 0 ? max(0, topUpTo - alsoSeeded.count) : exhaustDepth
        let depth: Int
        if alsoSeeded.isEmpty {
            depth = max(1, exhaustDepth)
        } else {
            depth = max(1, min(needed, max(exhaustDepth, 1)))
        }
        let starts = hotPartnerStarts(
            ciphertext: ciphertext,
            exhaustLetters: exhaustLetters,
            exhaustDepth: depth,
            locked: locked
        )
        return starts.isEmpty ? [[]] : starts
    }
}

/// Which statistic the plugboard climb optimises.
///
/// `enigma-cuda` (the reference implementation of this attack, which also carries Ostwald's
/// partial exhaustion) defaults to scoring sequence `023` = IC, bigrams, trigrams. HELUT's
/// existing climb is bigram-only, so `staged` is the first thing worth measuring against it.
package enum ClimbScorer: String, CaseIterable {
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
    /// Leave-one-out linear combination of IC, n-grams, entropy, and naval-structure rates,
    /// fitted on known-key windows against wrong-setting decrypts. Not a crib. Requires a
    /// fitted `OstwaldRanker.Model` or the climb falls back to staged.
    case ranker

    /// Scorers that `--ostwald-curve` runs when `--ostwald-scorer` is omitted. Ranker is
    /// opt-in: it needs a fitted model and would otherwise silently fall back to staged.
    static var languageScorers: [ClimbScorer] { [.bigram, .trigram, .staged] }

    /// Metal kernel scores IC/bigram/trigram, not the ranker features. Ranker climbs stay
    /// on the CPU (or Metal decrypt is unused).
    var usesMetalKernel: Bool {
        switch self {
        case .ranker: return false
        case .bigram, .trigram, .staged: return true
        }
    }

    /// Statistic to optimise when `placed` plugs are already on the board.
    ///
    /// `trigramTable`, when supplied, replaces the generic German trigram model at every
    /// stage that uses trigrams. Passing it is the whole A/B: same scorer, same staging,
    /// different language model.
    func measure(
        placed: Int,
        trigramTable: [Double]? = nil,
        ranker: OstwaldRanker.Model? = nil
    ) -> (([Int]) -> Double) {
        if self == .ranker, let ranker {
            return { ranker.score($0) }
        }
        let trigram: ([Int]) -> Double = { letters in
            if let trigramTable { return NavalGrams.score(letters, table: trigramTable) }
            return GermanTrigrams.score(letters)
        }
        switch self {
        case .bigram: return LanguageScorer.bigramScore
        case .trigram: return trigram
        case .staged, .ranker:
            if placed < 2 { return LanguageScorer.indexOfCoincidence }
            if placed < 5 { return LanguageScorer.bigramScore }
            return trigram
        }
    }

    /// Same staging as `measure`, as a Metal kernel discriminator.
    func scoreMode(placed: Int) -> OstwaldScoreMode {
        switch self {
        case .bigram: return .bigram
        case .trigram: return .trigram
        case .staged, .ranker:
            if placed < 2 { return .ic }
            if placed < 5 { return .bigram }
            return .trigram
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

    /// Recorded-letter decrypt. Dummy-steps `walk.leadingHoles` times first so a
    /// post-gap intercept is scored at the transmitted rotor positions.
    static func decrypt(
        key: EnigmaM4Key,
        ciphertext: [Int],
        pairs: [(Int, Int)],
        walk: OstwaldWalk = .dense
    ) -> [Int] {
        var table = Array(0..<26)
        for pair in pairs {
            table[pair.0] = pair.1
            table[pair.1] = pair.0
        }
        return decrypt(key: key, ciphertext: ciphertext, plugboard: table, walk: walk)
    }

    static func decrypt(
        key: EnigmaM4Key,
        ciphertext: [Int],
        plugboard: [Int],
        walk: OstwaldWalk = .dense
    ) -> [Int] {
        let working = EnigmaM4Key(
            greek: key.greek, rotors: key.rotors, rings: key.rings,
            positions: key.positions, plugboard: plugboard, reflector: key.reflector
        )
        var machine = EnigmaM4Machine(key: working)
        for _ in 0..<walk.leadingHoles { _ = machine.process(0) }
        var out = [Int](repeating: 0, count: ciphertext.count)
        for index in ciphertext.indices { out[index] = machine.process(ciphertext[index]) }
        return out
    }

    static func plugTable(_ pairs: [(Int, Int)]) -> [Int] {
        var table = Array(0..<26)
        for pair in pairs {
            table[pair.0] = pair.1
            table[pair.1] = pair.0
        }
        return table
    }

    static func climb(
        key: EnigmaM4Key,
        ciphertext: [Int],
        scorer: ClimbScorer,
        maxPlugs: Int = 10,
        seeded: [(Int, Int)] = [],
        trigramTable: [Double]? = nil,
        reconnectPasses: Int = 0,
        walk: OstwaldWalk = .dense,
        metal: OstwaldMetalEngine? = nil,
        resumeFrom: [(Int, Int)]? = nil,
        beamWidth: Int = 1,
        ranker: OstwaldRanker.Model? = nil
    ) -> (pairs: [(Int, Int)], score: Double, plain: [Int]) {
        var plain = [Int](repeating: 0, count: ciphertext.count)
        var pairs = resumeFrom ?? seeded
        var used = [Bool](repeating: false, count: 26)
        for pair in pairs { used[pair.0] = true; used[pair.1] = true }
        let beam = max(1, beamWidth)
        let metalOK = metal != nil && trigramTable == nil && ranker == nil && scorer.usesMetalKernel

        func decrypt(_ candidate: [(Int, Int)]) -> [Int] {
            OstwaldCurve.decrypt(key: key, ciphertext: ciphertext, pairs: candidate, walk: walk)
        }

        func scoreBatch(
            _ extras: [(Int, Int)],
            onto base: [(Int, Int)],
            placed: Int,
            measure: ([Int]) -> Double
        ) -> [Double] {
            if extras.isEmpty { return [] }
            if metalOK, let metal {
                let tables = extras.map { OstwaldCurve.plugTable(base + [$0]) }
                return metal.scores(
                    plugTables: tables,
                    mode: scorer.scoreMode(placed: placed),
                    walk: walk
                ).map(Double.init)
            }
            return extras.map { measure(decrypt(base + [$0])) }
        }

        func measureNow(_ placed: Int) -> ([Int]) -> Double {
            scorer.measure(placed: placed, trigramTable: trigramTable, ranker: ranker)
        }

        // Greedy insertion, or a beam of partial boards. The statistic can change as the
        // board fills (staged scoring), so `best` is re-baselined whenever the measure does.
        // Beam > 1 is how greedy first-plug poison is attacked from inside the climb
        // instead of only from Ostwald's outside exhaustion.
        struct BeamState {
            var pairs: [(Int, Int)]
            var used: [Bool]
            var score: Double
        }
        var beamStates = [
            BeamState(pairs: pairs, used: used, score: measureNow(pairs.count)(decrypt(pairs)))
        ]
        while beamStates.contains(where: { $0.pairs.count < maxPlugs }) {
            let placed = beamStates.map(\.pairs.count).min() ?? maxPlugs
            if placed >= maxPlugs { break }
            let nextMeasure = measureNow(placed)
            var expanded: [BeamState] = []
            expanded.reserveCapacity(beam == 1 ? 1 : beamStates.count * 8)
            var advanced = false
            for var state in beamStates {
                if state.pairs.count > placed || state.pairs.count >= maxPlugs {
                    expanded.append(state)
                    continue
                }
                if scorer == .staged || (scorer == .ranker && ranker == nil) {
                    state.score = nextMeasure(decrypt(state.pairs))
                }
                var extras: [(Int, Int)] = []
                extras.reserveCapacity(325)
                for a in 0..<26 where !state.used[a] {
                    for b in (a + 1)..<26 where !state.used[b] {
                        extras.append((a, b))
                    }
                }
                let scores = scoreBatch(
                    extras, onto: state.pairs, placed: state.pairs.count, measure: nextMeasure
                )
                if beam == 1 {
                    var bestPair: (Int, Int)?
                    var bestScore = state.score
                    for index in extras.indices where scores[index] > bestScore {
                        bestScore = scores[index]
                        bestPair = extras[index]
                    }
                    if let pair = bestPair {
                        var nextUsed = state.used
                        nextUsed[pair.0] = true
                        nextUsed[pair.1] = true
                        expanded.append(
                            BeamState(pairs: state.pairs + [pair], used: nextUsed, score: bestScore)
                        )
                        advanced = true
                    } else {
                        expanded.append(state)
                    }
                    continue
                }
                var improved = false
                for index in extras.indices where scores[index] > state.score {
                    var nextUsed = state.used
                    nextUsed[extras[index].0] = true
                    nextUsed[extras[index].1] = true
                    expanded.append(
                        BeamState(
                            pairs: state.pairs + [extras[index]],
                            used: nextUsed,
                            score: scores[index]
                        )
                    )
                    improved = true
                    advanced = true
                }
                if !improved { expanded.append(state) }
            }
            expanded.sort { $0.score > $1.score }
            beamStates = Array(expanded.prefix(beam))
            if !advanced { break }
        }
        let winner = beamStates.max(by: { $0.score < $1.score }) ?? beamStates[0]
        pairs = winner.pairs
        used = winner.used

        let final = measureNow(maxPlugs)

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
                            placed: current.count, trigramTable: trigramTable, ranker: ranker
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
        var best = final(decrypt(pairs))
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
    /// `exhaustDepth` fixes that many plugs simultaneously rather than one.
    ///
    /// Depth 1 is Ostwald's published scheme. Depth 2 is the lever Phase 50 named and never
    /// built, and the reason to expect anything from it is an asymmetry rather than more
    /// compute. Exhaustion is applied to the true *and* the wrong settings, so extra starts
    /// raise the decoys' maximum too — which is exactly why depth 1 saturates: sweeping 141
    /// fixed plugs up to 325 buys no further margin, because both sides gain equally.
    ///
    /// What does *not* transfer to a decoy is basin quality. Among depth-1 seeds the truth
    /// gets one start whose fixed plug is genuinely correct; among depth-2 seeds it gets one
    /// whose *pair* is correct, and the oracle ladder shows that quality pays steeply
    /// (2 correct plugs −0.10, 4 correct +0.33). So depth 2 trades a much larger decoy
    /// maximum against a discretely better true basin, and which dominates is an empirical
    /// question this parameter exists to answer.
    static func climbExhaustive(
        key: EnigmaM4Key,
        ciphertext: [Int],
        scorer: ClimbScorer,
        maxPlugs: Int = 10,
        exhaustLetters: Int,
        exhaustDepth: Int = 1,
        alsoSeeded: [(Int, Int)] = [],
        trigramTable: [Double]? = nil,
        reconnectPasses: Int = 0,
        topUpTo: Int = 0,
        brutePlugs: Int = 0,
        bruteAll: Bool = false,
        walk: OstwaldWalk = .dense,
        metal: OstwaldMetalEngine? = nil,
        beamWidth: Int = 1,
        ranker: OstwaldRanker.Model? = nil
    ) -> (pairs: [(Int, Int)], score: Double, plain: [Int]) {
        let startSets: [[(Int, Int)]]
        if exhaustLetters <= 0 && topUpTo <= 0 && brutePlugs <= 0 {
            return climb(
                key: key, ciphertext: ciphertext, scorer: scorer,
                maxPlugs: maxPlugs, seeded: alsoSeeded,
                trigramTable: trigramTable, reconnectPasses: reconnectPasses,
                walk: walk, metal: metal, beamWidth: beamWidth, ranker: ranker
            )
        }
        do {
            startSets = try OstwaldExhaust.startSets(
                ciphertext: ciphertext,
                exhaustLetters: exhaustLetters,
                exhaustDepth: exhaustDepth,
                alsoSeeded: alsoSeeded,
                topUpTo: topUpTo,
                brutePlugs: brutePlugs,
                bruteAll: bruteAll
            )
        } catch {
            return climb(
                key: key, ciphertext: ciphertext, scorer: scorer,
                maxPlugs: maxPlugs, seeded: alsoSeeded,
                trigramTable: trigramTable, reconnectPasses: reconnectPasses,
                walk: walk, metal: metal, beamWidth: beamWidth, ranker: ranker
            )
        }

        var best: (pairs: [(Int, Int)], score: Double, plain: [Int])?
        for start in startSets {
            let result = climb(
                key: key, ciphertext: ciphertext, scorer: scorer, maxPlugs: maxPlugs,
                seeded: alsoSeeded + start, trigramTable: trigramTable,
                reconnectPasses: reconnectPasses, walk: walk, metal: metal,
                beamWidth: beamWidth, ranker: ranker
            )
            if best == nil || result.score > best!.score { best = result }
        }
        return best ?? climb(
            key: key, ciphertext: ciphertext, scorer: scorer,
            maxPlugs: maxPlugs, seeded: alsoSeeded,
            trigramTable: trigramTable, reconnectPasses: reconnectPasses,
            walk: walk, metal: metal, beamWidth: beamWidth, ranker: ranker
        )
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
        exhaustDepth: Int = 1,
        seededPlugs: Int = 0,
        navalCorpus: NavalGramCorpus? = nil,
        reconnectPasses: Int = 0,
        lexicon: NavalLexicon? = nil,
        beamWidth: Int = 1,
        ranker: OstwaldRanker.Model? = nil,
        brutePlugs: Int = 0,
        bruteAll: Bool = false
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
            exhaustLetters: exhaustLetters, exhaustDepth: exhaustDepth,
            alsoSeeded: oracleSeed,
            trigramTable: trigramTable, reconnectPasses: reconnectPasses,
            brutePlugs: brutePlugs, bruteAll: bruteAll,
            beamWidth: beamWidth, ranker: ranker
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
                    exhaustLetters: exhaustLetters, exhaustDepth: exhaustDepth,
                    alsoSeeded: randomPairs(max(0, seededPlugs)),
                    trigramTable: trigramTable, reconnectPasses: reconnectPasses,
                    brutePlugs: brutePlugs, bruteAll: bruteAll,
                    beamWidth: beamWidth, ranker: ranker
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
