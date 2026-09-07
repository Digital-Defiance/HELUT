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

    /// German bigram counts from `Fixtures/german_bigrams.txt` (28,508,834 letters, IC 0.0747).
    /// 674 of 676 cells observed; JX and QY fall to the row-specific add-k floor.
    /// Row = first letter, column = second letter.
    /// Regenerate with `Scripts/build_bigrams.py --source bigrams`.
    package static let germanBigramCounts: [UInt32] = [
        13994, 89457, 81562, 33753, 156632, 35399, 78350, 60608, 23149, 1200, 24644, 165996, 84894, 288384, 1485, 17779, 407, 152419, 154912, 126482, 221667, 8009, 4894, 3182, 6913, 8714,  // A
        52292, 3120, 742, 5323, 295550, 1678, 6442, 2581, 45269, 1204, 1471, 25252, 2063, 3563, 20755, 700, 31, 29631, 20006, 15297, 30202, 1677, 3571, 62, 1759, 2387,  // B
        8582, 1367, 1324, 1782, 10755, 451, 420, 666112, 3842, 62, 48159, 3616, 684, 417, 12834, 512, 119, 3709, 2135, 2275, 2716, 530, 414, 32, 566, 522,  // C
        168666, 11775, 2787, 36138, 569603, 9280, 11274, 8274, 254951, 2634, 7778, 14155, 11454, 10374, 33244, 7485, 245, 30287, 30617, 12162, 44200, 9288, 14481, 174, 1856, 7011,  // D
        83125, 129143, 79838, 134430, 64904, 78747, 130055, 155518, 551121, 7865, 55283, 215318, 156421, 1095297, 16190, 35191, 2400, 1109878, 370213, 165975, 115916, 40511, 61452, 12437, 3168, 35710,  // E
        60695, 4420, 2686, 23751, 80659, 33858, 8324, 2778, 32155, 1400, 2678, 22626, 4506, 5314, 36966, 3151, 75, 41606, 11791, 50250, 75468, 2180, 3374, 482, 429, 2925,  // F
        59897, 8595, 757, 25433, 397443, 6627, 9601, 7580, 46103, 1294, 6934, 29427, 7780, 12093, 10164, 2349, 112, 50124, 44282, 42268, 33064, 9508, 7700, 237, 861, 7792,  // G
        175432, 12266, 1171, 39959, 250960, 8020, 10487, 7624, 65921, 2281, 9396, 59367, 34207, 52205, 51150, 3123, 190, 120830, 33808, 138868, 32727, 8387, 27596, 77, 1655, 8444,  // H
        25102, 22571, 234049, 44261, 468363, 18757, 106122, 30308, 4497, 2180, 29139, 78376, 81284, 488114, 53886, 10462, 647, 59690, 200234, 223888, 6906, 21872, 4309, 2058, 286, 17792,  // I
        32801, 71, 35, 67, 21103, 71, 24, 45, 616, 25, 91, 90, 85, 59, 5326, 114, 2, 89, 184, 75, 10252, 40, 35, 0, 14, 13,  // J
        60533, 2857, 625, 4819, 76249, 3290, 3384, 2674, 17982, 329, 2969, 28254, 2530, 5091, 74719, 1638, 90, 25000, 12212, 53518, 34707, 2048, 3232, 15, 1041, 2763,  // K
        137267, 21115, 6885, 45990, 209454, 15413, 17660, 5033, 174030, 1164, 10286, 138119, 11058, 13160, 37694, 5023, 199, 3916, 58724, 79464, 48716, 7958, 7394, 254, 4178, 8149,  // L
        122297, 20876, 2633, 21671, 155918, 13133, 12487, 7438, 129675, 5986, 9341, 8870, 65258, 9243, 38139, 24582, 443, 6411, 33441, 22528, 38065, 10204, 10440, 131, 819, 6839,  // M
        190842, 64456, 16903, 502506, 346145, 63629, 245111, 43277, 161164, 15008, 80025, 36660, 60633, 125077, 54189, 28035, 1686, 24704, 209239, 177229, 101665, 45969, 76141, 676, 2118, 72092,  // N
        7795, 26545, 44804, 30704, 79785, 24080, 20122, 22563, 5637, 3093, 11167, 80121, 52969, 177978, 9968, 22289, 128, 133631, 49522, 31655, 12814, 8023, 14457, 1779, 1135, 13223,  // O
        45507, 771, 1401, 3647, 36388, 16546, 900, 8327, 31083, 155, 1044, 19977, 1029, 715, 30608, 16425, 40, 63109, 5740, 10473, 12538, 739, 628, 18, 359, 1096,  // P
        147, 36, 22, 26, 86, 14, 23, 26, 145, 3, 5, 43, 38, 55, 14, 19, 6, 21, 72, 111, 8597, 34, 23, 1, 0, 19,  // Q
        211207, 67185, 24394, 174515, 321175, 53455, 73375, 45675, 155909, 10517, 64393, 45777, 59848, 86905, 104032, 22868, 1031, 35249, 148989, 149906, 116796, 32938, 49174, 504, 2803, 41637,  // R
        99235, 33802, 210184, 51621, 257099, 21271, 37323, 26265, 180519, 6771, 26839, 26036, 29701, 18998, 84806, 73956, 891, 14841, 195468, 332326, 41619, 22497, 30733, 479, 8033, 20973,  // S
        164527, 25501, 4994, 102338, 536414, 20321, 27891, 37808, 165791, 6644, 14241, 38359, 33000, 26810, 54459, 11251, 548, 84004, 122350, 70148, 84384, 23556, 63603, 555, 3748, 80225,  // T
        13322, 18595, 53640, 17625, 225923, 85775, 24161, 12009, 5310, 657, 11800, 22912, 69064, 320409, 1438, 13854, 65, 106239, 129690, 70228, 3291, 6820, 4474, 956, 320, 4479,  // U
        9529, 873, 163, 947, 109578, 904, 643, 277, 31909, 76, 597, 340, 649, 252, 104187, 1010, 9, 702, 1343, 381, 751, 423, 1241, 50, 105, 349,  // V
        83059, 491, 295, 1021, 141999, 656, 389, 1011, 109559, 379, 574, 838, 1765, 1031, 39330, 397, 9, 612, 4321, 479, 24732, 326, 1125, 37, 812, 253,  // W
        1759, 859, 370, 1011, 2239, 634, 353, 386, 3428, 54, 841, 344, 575, 415, 666, 3546, 62, 210, 988, 2742, 1283, 531, 352, 1029, 388, 330,  // X
        2525, 1532, 1246, 1592, 4870, 593, 777, 567, 1448, 150, 802, 2479, 2972, 1707, 2384, 2404, 103, 2657, 8535, 1497, 915, 641, 951, 39, 126, 544,  // Y
        14748, 4349, 427, 5263, 86812, 1945, 2327, 1387, 33940, 196, 2072, 4951, 2401, 1513, 7354, 1100, 48, 688, 3470, 23245, 119064, 2579, 23706, 132, 564, 2537,  // Z
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

    /// Reproducible reference points for the dense counted-bigram model.
    /// Independently reproduced by Python and Ruby over the first 72 symbols of
    /// P1030684 plus 400 deterministic uniform 72-symbol controls; see
    /// `logs/dense-bigram-independent-audit-20260906T220123Z`.
    package enum Calibration {
        /// Bigram score of the frozen 72-symbol German reference.
        package static let germanMean = -3.378690
        /// Mean over the 400 deterministic uniform controls.
        package static let randomMean = -4.652828
        /// Population standard deviation of those 400 controls.
        package static let randomDeviation = 0.231568
        /// Index of coincidence recorded by the 28,508,834-letter source fixture.
        package static let germanIC = 0.0747
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
