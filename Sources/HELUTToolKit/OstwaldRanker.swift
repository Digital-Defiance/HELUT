import Foundation
import HELUTCore

// MARK: - Leave-one-out linear Ostwald ranker
//
// The 2014 Ostwald/Weierud climb maximises IC, then bigrams, then trigrams. At 72 letters
// that discriminator loses: unseeded win rate ~20%, median margin negative, and extra
// compute raises the best *ghost* as well as the truth. NavalDiscriminator.swift sketched
// a composite LLR but was never wired, and it fitted against uniform random text — the
// wrong negative class. Decoys in this attack are *optimised* wrong-key decrypts.
//
// This ranker is that composite, fitted the way `--ostwald-curve` already grades a scorer:
//
//   positives  = 72-letter windows of held-in plaintext, plus true-setting decrypts with
//                0,2,4,6,8,10 correct plugs (so the climb path is in the training set)
//   negatives  = wrong-setting identity decrypts and random-board decrypts at the true
//                setting (the cheap stand-ins for ghosts). Optional staged climbs of
//                decoys, behind `--ostwald-ranker-decoy-climbs`, because those are slow.
//
// Features are smooth (IC, n-grams, entropy, a few naval-structure rates) so a hill-climb
// has a gradient. Lexicon surprise stays out of the climb score — Phase 50.8: a sparse
// hit-or-miss has nothing to follow from an empty board.
//
// Leave-one-out is not optional. The 48 published keys *are* the training set. Fitting on
// the control under test would score the model's memory of the answer. P1030680 is not in
// that set, so an operational fit withholds nothing — it still must greet `--ostwald-curve`
// at 72 letters before anyone points it at the target.
//
// This is not a language-model crib. It does not invent German. It reweights statistics
// the climb already computes.

package struct OstwaldRanker: Sendable {
    package static let featureCount = 8
    package static let featureNames = [
        "ic", "bigram", "trigram", "naval", "entropy", "digits", "triples", "xx",
    ]

    private static let digitWords: [[Int]] = [
        "NUL", "EINS", "ZWO", "DREI", "VIR", "FUNF", "SECHS", "SIBEN", "ACHT", "NEUN",
    ].map { EnigmaAlphabet.normalize($0) }

    package struct Model: Sendable {
        package let weights: [Double]
        package let center: [Double]
        package let scale: [Double]
        package let excluding: String?
        package let navalTable: [Double]?
        package let positiveCount: Int
        package let negativeCount: Int

        package var sourceDescription: String {
            "leave-one-out LDA ranker (\(positiveCount)+/\(negativeCount)−"
                + (excluding.map { ", withheld \($0)" } ?? ", operational fit")
                + ")"
        }

        package func features(_ letters: [Int]) -> [Double] {
            OstwaldRanker.features(letters, navalTable: navalTable)
        }

        package func score(_ letters: [Int]) -> Double {
            let raw = features(letters)
            var total = 0.0
            for index in 0..<OstwaldRanker.featureCount {
                let z = (raw[index] - center[index]) / scale[index]
                total += weights[index] * z
            }
            return total
        }
    }

    // MARK: Features

    package static func features(_ letters: [Int], navalTable: [Double]?) -> [Double] {
        let n = max(letters.count, 1)
        let ic = LanguageScorer.indexOfCoincidence(letters)
        let bigram = LanguageScorer.bigramScore(letters)
        let trigram = GermanTrigrams.scoreIfLoaded(letters) ?? -10
        let naval: Double
        if let navalTable {
            naval = NavalGrams.score(letters, table: navalTable)
        } else {
            naval = 0
        }
        return [
            ic,
            bigram,
            trigram,
            naval,
            unigramEntropy(letters),
            digitDensity(letters, n: n),
            tripleDensity(letters, n: n),
            xxDensity(letters, n: n),
        ]
    }

    private static func unigramEntropy(_ letters: [Int]) -> Double {
        var freq = [Int](repeating: 0, count: 26)
        var counted = 0
        for letter in letters where (0..<26).contains(letter) {
            freq[letter] += 1
            counted += 1
        }
        let n = Double(max(counted, 1))
        var entropy = 0.0
        for count in freq where count > 0 {
            let p = Double(count) / n
            entropy -= p * log2(p)
        }
        return entropy
    }

    private static func digitDensity(_ letters: [Int], n: Int) -> Double {
        var hits = 0
        for word in digitWords where letters.count >= word.count {
            for start in 0...(letters.count - word.count)
            where Array(letters[start..<(start + word.count)]) == word {
                hits += 1
            }
        }
        return Double(hits) / Double(n)
    }

    private static func tripleDensity(_ letters: [Int], n: Int) -> Double {
        var hits = 0
        var index = 0
        while index + 2 < letters.count {
            if letters[index] == letters[index + 1] && letters[index] == letters[index + 2] {
                hits += 1
            }
            index += 1
        }
        return Double(hits) / Double(n)
    }

    private static func xxDensity(_ letters: [Int], n: Int) -> Double {
        let x = EnigmaAlphabet.index("X")
        var hits = 0
        for index in 0..<max(letters.count - 1, 0)
        where letters[index] == x && letters[index + 1] == x {
            hits += 1
        }
        return Double(hits) / Double(n)
    }

    // MARK: Fit

    static func fit(
        controls: [KnownControl],
        excluding: String?,
        window: Int = 72,
        decoyClimbs: Int = 0,
        seed: UInt64 = 0xA11CE,
        navalCorpus: NavalGramCorpus? = nil
    ) -> Model? {
        let train = controls.filter { $0.id != excluding }
        guard train.count >= 4 else { return nil }
        let trigramTable = navalCorpus?.table(excluding: excluding)
        var positives: [[Double]] = []
        var negatives: [[Double]] = []
        var generator = SplitMix64(seed: seed)

        for control in train {
            let length = min(window, control.ciphertext.count, control.plaintext.count)
            guard length >= 60 else { continue }
            let ct = Array(control.ciphertext.prefix(length))
            let pt = Array(control.plaintext.prefix(length))
            let step = max(1, (pt.count - length) == 0 ? length : 17)
            if pt.count == length {
                positives.append(features(pt, navalTable: trigramTable))
            } else {
                for start in stride(from: 0, through: pt.count - length, by: step) {
                    positives.append(
                        features(Array(pt[start..<(start + length)]), navalTable: trigramTable)
                    )
                }
            }

            let stripped = EnigmaM4Key(
                greek: control.key.greek, rotors: control.key.rotors, rings: control.key.rings,
                positions: control.key.positions, plugboard: Array(0..<26),
                reflector: control.key.reflector
            )
            for plugCount in [0, 2, 4, 6, 8, 10] {
                let pairs = Array(control.truePairs.prefix(plugCount))
                let plain = OstwaldCurve.decrypt(key: stripped, ciphertext: ct, pairs: pairs)
                positives.append(features(plain, navalTable: trigramTable))
            }

            for _ in 0..<4 {
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
                let decoy = OstwaldCurve.decrypt(key: wrong, ciphertext: ct, pairs: [])
                negatives.append(features(decoy, navalTable: trigramTable))
            }
            for _ in 0..<2 {
                let randomBoard = randomPairs(10, generator: &generator)
                let decoy = OstwaldCurve.decrypt(
                    key: stripped, ciphertext: ct, pairs: randomBoard
                )
                negatives.append(features(decoy, navalTable: trigramTable))
            }
            for _ in 0..<max(0, decoyClimbs) {
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
                let climbed = OstwaldCurve.climb(
                    key: wrong, ciphertext: ct, scorer: .staged, maxPlugs: 10
                )
                negatives.append(features(climbed.plain, navalTable: trigramTable))
            }
        }

        guard positives.count >= 8, negatives.count >= 8 else { return nil }
        return lda(
            positives: positives, negatives: negatives,
            excluding: excluding, navalTable: trigramTable
        )
    }

    private static func randomPairs(_ count: Int, generator: inout SplitMix64) -> [(Int, Int)] {
        var pool = Array(0..<26)
        for index in stride(from: 25, to: 0, by: -1) {
            let swap = Int(generator.next() % UInt64(index + 1))
            pool.swapAt(index, swap)
        }
        var pairs: [(Int, Int)] = []
        var cursor = 0
        while pairs.count < count && cursor + 1 < pool.count {
            pairs.append((min(pool[cursor], pool[cursor + 1]), max(pool[cursor], pool[cursor + 1])))
            cursor += 2
        }
        return pairs
    }

    private static func lda(
        positives: [[Double]],
        negatives: [[Double]],
        excluding: String?,
        navalTable: [Double]?
    ) -> Model? {
        let dim = featureCount
        let pooled = positives + negatives
        var center = [Double](repeating: 0, count: dim)
        for row in pooled {
            for index in 0..<dim { center[index] += row[index] }
        }
        let n = Double(pooled.count)
        for index in 0..<dim { center[index] /= n }
        var scale = [Double](repeating: 0, count: dim)
        for row in pooled {
            for index in 0..<dim {
                let d = row[index] - center[index]
                scale[index] += d * d
            }
        }
        for index in 0..<dim {
            scale[index] = max(sqrt(scale[index] / Double(max(pooled.count - 1, 1))), 1e-6)
        }

        func zscore(_ row: [Double]) -> [Double] {
            (0..<dim).map { (row[$0] - center[$0]) / scale[$0] }
        }
        let zp = positives.map(zscore)
        let zn = negatives.map(zscore)

        var muP = [Double](repeating: 0, count: dim)
        var muN = [Double](repeating: 0, count: dim)
        for row in zp { for index in 0..<dim { muP[index] += row[index] } }
        for row in zn { for index in 0..<dim { muN[index] += row[index] } }
        let np = Double(zp.count), nn = Double(zn.count)
        for index in 0..<dim {
            muP[index] /= np
            muN[index] /= nn
        }

        var sigma = Array(repeating: Array(repeating: 0.0, count: dim), count: dim)
        func accumulate(_ rows: [[Double]], _ mean: [Double]) {
            for row in rows {
                for i in 0..<dim {
                    let di = row[i] - mean[i]
                    for j in 0..<dim {
                        sigma[i][j] += di * (row[j] - mean[j])
                    }
                }
            }
        }
        accumulate(zp, muP)
        accumulate(zn, muN)
        let denom = Double(max(zp.count + zn.count - 2, 1))
        for i in 0..<dim {
            for j in 0..<dim {
                sigma[i][j] /= denom
            }
            sigma[i][i] += 1e-4
        }
        let delta = (0..<dim).map { muP[$0] - muN[$0] }
        let weights = solve(sigma, delta) ?? delta
        return Model(
            weights: weights, center: center, scale: scale,
            excluding: excluding, navalTable: navalTable,
            positiveCount: positives.count, negativeCount: negatives.count
        )
    }

    /// Gaussian elimination with partial pivoting. Returns nil if the matrix is singular.
    package static func solve(_ matrix: [[Double]], _ vector: [Double]) -> [Double]? {
        let n = vector.count
        guard matrix.count == n, matrix.allSatisfy({ $0.count == n }) else { return nil }
        var a = matrix
        var b = vector
        for k in 0..<n {
            var pivot = k
            var best = abs(a[k][k])
            for i in (k + 1)..<n where abs(a[i][k]) > best {
                best = abs(a[i][k])
                pivot = i
            }
            if best < 1e-12 { return nil }
            if pivot != k {
                a.swapAt(k, pivot)
                b.swapAt(k, pivot)
            }
            let diag = a[k][k]
            for i in (k + 1)..<n {
                let factor = a[i][k] / diag
                for j in k..<n { a[i][j] -= factor * a[k][j] }
                b[i] -= factor * b[k]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for i in stride(from: n - 1, through: 0, by: -1) {
            var sum = b[i]
            for j in (i + 1)..<n { sum -= a[i][j] * x[j] }
            x[i] = sum / a[i][i]
        }
        return x
    }
}
