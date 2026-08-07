import Foundation

/// Lightweight language scoreboard for Bombe spike detection (IC + German n-grams).
package struct LanguageScorer: Sendable {
    package let trigramLogProbs: [String: Double]
    package let floorLogProb: Double

    package static func germanMilitary() -> LanguageScorer {
        // Compact log-probability table for common Wehrmacht / German military fragments.
        // Scores are relative; only ranking / spike detection matters.
        let raw: [(String, Double)] = [
            ("EIN", -2.1), ("DER", -2.2), ("DIE", -2.3), ("UND", -2.4), ("DEN", -2.5),
            ("VON", -2.6), ("MIT", -2.7), ("DAS", -2.8), ("IST", -2.9), ("AUF", -3.0),
            ("NIC", -3.0), ("SCH", -2.8), ("CHT", -3.1), ("UNG", -3.0), ("GEN", -3.1),
            ("STE", -3.2), ("BER", -3.2), ("VER", -3.2), ("ZUR", -3.3), ("FUR", -3.4),
            ("DIV", -2.5), ("PAN", -2.6), ("ANZ", -2.7), ("GRP", -3.0), ("SIE", -2.8),
            ("FRI", -3.0), ("IED", -3.1), ("TON", -3.2), ("UHR", -2.9), ("MELD", -2.4),
            ("TAG", -3.0), ("ABEN", -2.8), ("NULL", -2.7), ("EINS", -2.6), ("ZWOX", -2.5),
            ("XDIV", -2.4), ("XPAN", -2.4), ("KEIN", -2.5), ("EINE", -2.6), ("BESO", -2.8),
            ("NDER", -2.7), ("EREN", -2.9), ("EREI", -3.0), ("IGNI", -3.1), ("SSEX", -3.2),
            ("WETT", -2.8), ("ERVO", -3.0), ("RHER", -3.1), ("SAGE", -3.0)
        ]
        var table: [String: Double] = [:]
        for (gram, value) in raw {
            table[gram] = value
        }
        return LanguageScorer(trigramLogProbs: table, floorLogProb: -6.0)
    }

    package func score(_ letters: [Int]) -> Double {
        guard letters.count >= 3 else { return floorLogProb * Double(max(letters.count, 1)) }
        var total = 0.0
        var count = 0
        // Prefer 4-grams when present in the table; otherwise fall back to trigrams.
        if letters.count >= 4 {
            for index in 0..<(letters.count - 3) {
                let tetra = String([
                    EnigmaAlphabet.character(letters[index]),
                    EnigmaAlphabet.character(letters[index + 1]),
                    EnigmaAlphabet.character(letters[index + 2]),
                    EnigmaAlphabet.character(letters[index + 3])
                ])
                if let value = trigramLogProbs[tetra] {
                    total += value
                    count += 1
                    continue
                }
                let tri = String(tetra.prefix(3))
                total += trigramLogProbs[tri] ?? floorLogProb
                count += 1
            }
        } else {
            for index in 0..<(letters.count - 2) {
                let tri = String([
                    EnigmaAlphabet.character(letters[index]),
                    EnigmaAlphabet.character(letters[index + 1]),
                    EnigmaAlphabet.character(letters[index + 2])
                ])
                total += trigramLogProbs[tri] ?? floorLogProb
                count += 1
            }
        }
        return count == 0 ? floorLogProb : total / Double(count)
    }

    package func score(string: String) -> Double {
        score(EnigmaAlphabet.normalize(string))
    }

    // MARK: - German bigram model

    /// German bigram counts from `Fixtures/german_corpus.txt` (10359 letters, IC 0.0749).
    /// Row = first letter, column = second letter. Regenerate with `Scripts/build_bigrams.py`.
    package static let germanBigramCounts: [UInt32] = [
        2, 39, 63, 13, 58, 11, 34, 19, 4, 0, 0, 26, 15, 109, 0, 0, 1, 31, 26, 45, 73, 0, 0, 4, 1, 0,  // A
        22, 0, 0, 1, 124, 0, 7, 1, 16, 0, 0, 5, 0, 0, 19, 0, 0, 13, 12, 4, 0, 0, 2, 1, 0, 0,  // B
        1, 0, 0, 0, 0, 0, 0, 233, 0, 0, 12, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  // C
        35, 6, 0, 22, 270, 5, 12, 2, 112, 1, 4, 14, 7, 5, 19, 0, 0, 29, 16, 5, 41, 4, 11, 0, 0, 6,  // D
        32, 67, 27, 46, 24, 50, 58, 79, 185, 1, 6, 93, 42, 366, 6, 7, 1, 411, 143, 85, 41, 24, 20, 6, 1, 9,  // E
        27, 1, 0, 5, 65, 40, 8, 0, 2, 1, 4, 12, 1, 3, 39, 1, 0, 16, 4, 19, 33, 1, 5, 2, 2, 2,  // F
        13, 6, 0, 26, 212, 6, 8, 3, 6, 0, 1, 5, 3, 8, 2, 0, 0, 30, 5, 21, 24, 2, 9, 5, 1, 11,  // G
        64, 7, 0, 21, 63, 9, 5, 0, 18, 1, 2, 28, 6, 23, 14, 1, 0, 51, 6, 68, 5, 0, 11, 1, 0, 2,  // H
        2, 4, 74, 10, 153, 26, 31, 1, 0, 0, 2, 14, 14, 137, 10, 0, 2, 44, 50, 71, 2, 7, 0, 6, 2, 0,  // I
        1, 0, 0, 0, 2, 1, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0,  // J
        4, 1, 0, 3, 25, 0, 3, 0, 3, 0, 1, 6, 2, 1, 13, 0, 0, 2, 3, 10, 14, 2, 0, 0, 0, 1,  // K
        43, 0, 0, 49, 56, 1, 12, 3, 35, 0, 2, 53, 1, 5, 7, 0, 0, 0, 5, 21, 33, 1, 1, 5, 2, 5,  // L
        40, 2, 0, 2, 74, 3, 4, 3, 26, 0, 1, 3, 28, 3, 12, 8, 1, 1, 6, 4, 3, 2, 2, 0, 0, 1,  // M
        84, 8, 0, 249, 92, 22, 141, 8, 37, 2, 20, 8, 20, 45, 31, 1, 1, 4, 52, 35, 48, 20, 34, 9, 4, 16,  // N
        1, 14, 8, 5, 21, 17, 1, 9, 1, 0, 1, 21, 21, 36, 16, 4, 0, 71, 23, 18, 0, 0, 4, 0, 2, 2,  // O
        5, 0, 0, 0, 11, 8, 0, 0, 1, 0, 0, 2, 0, 0, 5, 4, 0, 7, 1, 0, 4, 0, 0, 0, 0, 0,  // P
        0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0,  // Q
        74, 32, 11, 99, 105, 33, 30, 30, 51, 0, 24, 18, 23, 26, 19, 5, 0, 12, 57, 83, 49, 10, 8, 4, 1, 16,  // R
        16, 14, 49, 16, 76, 7, 15, 5, 57, 1, 2, 0, 5, 11, 21, 8, 0, 1, 45, 131, 15, 8, 19, 4, 1, 8,  // S
        62, 12, 1, 53, 169, 9, 14, 7, 36, 0, 5, 11, 17, 24, 18, 2, 3, 29, 31, 27, 50, 7, 33, 5, 6, 43,  // T
        9, 9, 12, 0, 85, 39, 21, 3, 0, 0, 0, 20, 21, 184, 0, 4, 0, 67, 37, 7, 8, 5, 1, 0, 0, 0,  // U
        0, 0, 0, 0, 54, 0, 0, 0, 15, 0, 0, 0, 0, 0, 28, 0, 0, 0, 0, 0, 1, 2, 0, 1, 0, 0,  // V
        25, 0, 0, 0, 58, 0, 0, 0, 53, 0, 2, 0, 0, 0, 13, 0, 0, 0, 0, 0, 31, 0, 0, 0, 0, 1,  // W
        7, 3, 1, 4, 2, 5, 2, 0, 0, 0, 3, 0, 3, 4, 2, 1, 1, 1, 6, 0, 3, 4, 2, 19, 0, 1,  // X
        2, 0, 0, 0, 1, 1, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 2, 0, 5, 3, 0, 2, 2, 0, 1, 3,  // Y
        3, 2, 0, 1, 29, 0, 1, 0, 4, 0, 0, 0, 0, 0, 1, 2, 0, 0, 2, 14, 46, 0, 19, 3, 0, 0   // Z
    ]

    /// Add-k smoothed log P(second | first), indexed `first * 26 + second`.
    package static let germanBigramLogProbs: [Double] = {
        let smoothing = 0.5
        var table = [Double](repeating: 0, count: 676)
        for first in 0..<26 {
            var rowTotal = 0.0
            for second in 0..<26 {
                rowTotal += Double(germanBigramCounts[first * 26 + second])
            }
            let denominator = rowTotal + smoothing * 26.0
            for second in 0..<26 {
                let numerator = Double(germanBigramCounts[first * 26 + second]) + smoothing
                table[first * 26 + second] = log(numerator / denominator)
            }
        }
        return table
    }()

    /// Mean bigram log-probability. This is the hill-climb objective: unlike IC it is
    /// *not* maximised by degenerate single-letter output, because repeating one letter
    /// lands on a rare self-pair (e.g. `UU`) every step.
    package static func bigramScore(_ letters: [Int]) -> Double {
        guard letters.count >= 2 else { return -10 }
        var total = 0.0
        for index in 0..<(letters.count - 1) {
            total += germanBigramLogProbs[letters[index] * 26 + letters[index + 1]]
        }
        return total / Double(letters.count - 1)
    }

    package static func bigramScore(string: String) -> Double {
        bigramScore(EnigmaAlphabet.normalize(string))
    }

    /// Measured reference points for calibrating a "is this German?" verdict.
    /// Produced by `Scripts/calibrate_scorer.py` over 400 random 72-letter samples.
    package enum Calibration {
        /// Mean bigram score of a held-out 72-letter German naval plaintext.
        package static let germanMean = -2.84
        /// Mean bigram score of uniform random letters (sd ≈ 0.17 at 72 letters).
        package static let randomMean = -4.29
        /// Standard deviation of the random baseline at message length ~72.
        package static let randomDeviation = 0.17
        /// Index of coincidence of German plaintext.
        package static let germanIC = 0.0749
    }

    /// Classic Index of Coincidence for A–Z text. German plaintext ≈ 0.07; random ≈ 0.0385.
    package static func indexOfCoincidence(_ letters: [Int]) -> Double {
        guard letters.count > 1 else { return 0 }
        var freq = [Int](repeating: 0, count: 26)
        for letter in letters where letter >= 0 && letter < 26 {
            freq[letter] += 1
        }
        let n = Double(letters.count)
        var numerator = 0.0
        for count in freq {
            numerator += Double(count * (count - 1))
        }
        return numerator / (n * (n - 1))
    }

    /// Rank lanes by score descending; flag spikes above `noiseFloor + margin`.
    package static func detectSpikes(
        results: [BombeLaneResult],
        margin: Double = 1.5
    ) -> (winner: BombeLaneResult?, spikes: [BombeLaneResult], noiseFloor: Double) {
        guard !results.isEmpty else { return (nil, [], 0) }
        let sorted = results.sorted { $0.score > $1.score }
        let noiseFloor: Double
        if sorted.count >= 20 {
            let tail = sorted.suffix(sorted.count / 2)
            noiseFloor = tail.reduce(0.0) { $0 + $1.score } / Double(tail.count)
        } else {
            noiseFloor = sorted.dropFirst().map(\.score).reduce(0.0, +)
                / Double(max(sorted.count - 1, 1))
        }
        let spikes = sorted.filter { $0.score >= noiseFloor + margin }
        return (sorted.first, spikes, noiseFloor)
    }
}
