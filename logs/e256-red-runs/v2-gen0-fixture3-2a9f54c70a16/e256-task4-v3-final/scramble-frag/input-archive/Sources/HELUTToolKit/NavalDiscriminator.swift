import Foundation
import HELUTCore

// ⚠️ NOT WIRED. No CLI flag reaches this file, no campaign arm uses it, and no claim in
// `BREAK_P1030680.md` or `writeup.tex` rests on it. It compiles and is committed so the design
// is not lost, but its weights are **unvalidated**: the log-likelihood ratios below have never
// been fitted against the 48 known-key controls, and the independence assumption has never been
// tested. Treat every number in here as a hypothesis.
//
// Before it may be used for anything: fit the per-feature LLRs on controls *excluding* the one
// under test (the same leave-one-out discipline the naval trigram model needed in Phase 50.8,
// which measured null), then grade the composite the way `--ostwald-curve` grades a scorer —
// margin at the true setting minus the best margin over wrong settings. A discriminator that
// has not been shown to separate truth from decoys on known keys is decoration.

// MARK: - Composite naval discriminator: lexicon + structure, as a log-likelihood ratio
//
// Two single-statistic levers measured null in this phase (a naval trigram mix, and a stronger
// plugboard neighborhood), and the reason both failed is the same: the margin is a difference
// of two maxima, so anything a hill-climb can nudge upward it nudges upward at the decoys too.
// The way out is features a ten-plug board *cannot* manufacture.
//
// That is the design principle here. Each feature is scored as a log-likelihood ratio in bits,
//
//     llr(f) = log2 P(f | naval German) - log2 P(f | wrong-key decrypt)
//
// so the weights are measured rather than invented, and the total is additive under an
// independence assumption that is admittedly optimistic but at least explicit.
//
// Features are deliberately split by how *gameable* they are, because that turned out to
// matter more than raw separation:
//
//   Sparse, multi-position (hard to fake with 10 plugs — a digit word needs 3-5 specific
//   letters in order, a triple needs three identical, a lexicon token up to twelve):
//       lexicon surprise, digit words, triple runs, XX separators
//
//   Global rates (cheap to fake — the plugboard is an involution on the output, so plugging Q
//   to anything erases every Q):
//       Q rate, X/Y punctuation rate
//
// Measured against raw random text the global rates look strongest (Q rate 2.2 sigma), which
// is exactly the trap: raw random is the wrong baseline. The decoys are *optimised* wrong-key
// decrypts. So the global rates are down-weighted on principle and, more importantly, the
// runner reports per-feature ablation so the guess is checked rather than trusted.
//
// Leave-one-out throughout: the controls under attack are in the corpus this is calibrated on.

struct NavalDiscriminator: Sendable {

    enum Feature: String, CaseIterable, Sendable {
        case lexicon      // surprise bits from recurring naval tokens
        case digitWords   // NUL EINS ZWO DREI VIR FUNF SECHS SIBEN ACHT NEUN
        case triples      // VVV UUU FFF TTT KKK MMM ...
        case separators   // XX doubling
        case qRate        // German barely uses Q; naval traffic essentially never
        case punctuation  // X and Y as period/comma

        /// Sparse multi-position features resist plugboard overfitting; global rates do not.
        var gameable: Bool {
            switch self {
            case .lexicon, .digitWords, .triples, .separators: return false
            case .qRate, .punctuation: return true
            }
        }
    }

    private let lexicon: NavalLexicon
    private let enabled: Set<Feature>
    /// Measured means and deviations per feature, under naval plaintext.
    private let navalMean: [Feature: Double]
    private let navalDeviation: [Feature: Double]
    /// Same under uniform-random text — the stand-in for an unoptimised wrong-key decrypt.
    private let randomMean: [Feature: Double]
    private let randomDeviation: [Feature: Double]

    var sourceDescription: String {
        let names = Feature.allCases.filter { enabled.contains($0) }.map(\.rawValue)
        return "naval composite [\(names.joined(separator: "+"))], "
            + "\(lexicon.tokenCount) lexicon tokens"
    }

    private static let digitWords: [[Int]] = [
        "NUL", "EINS", "ZWO", "DREI", "VIR", "FUNF", "SECHS", "SIBEN", "ACHT", "NEUN",
    ].map { EnigmaAlphabet.normalize($0) }

    // MARK: Raw feature values

    private static func value(
        _ feature: Feature, _ letters: [Int], lexicon: NavalLexicon, excluding: String?
    ) -> Double {
        let n = Double(max(letters.count, 1))
        switch feature {
        case .lexicon:
            return lexicon.score(letters, excluding: excluding)
        case .digitWords:
            var hits = 0
            for word in digitWords where letters.count >= word.count {
                for start in 0...(letters.count - word.count)
                where Array(letters[start..<(start + word.count)]) == word {
                    hits += 1
                }
            }
            return Double(hits)
        case .triples:
            var hits = 0
            var index = 0
            while index + 2 < letters.count {
                if letters[index] == letters[index + 1] && letters[index] == letters[index + 2] {
                    hits += 1
                }
                index += 1
            }
            return Double(hits)
        case .separators:
            let x = EnigmaAlphabet.index("X")
            var hits = 0
            for index in 0..<max(letters.count - 1, 0)
            where letters[index] == x && letters[index + 1] == x { hits += 1 }
            return Double(hits)
        case .qRate:
            let q = EnigmaAlphabet.index("Q")
            return Double(letters.filter { $0 == q }.count) / n
        case .punctuation:
            let x = EnigmaAlphabet.index("X"), y = EnigmaAlphabet.index("Y")
            return Double(letters.filter { $0 == x || $0 == y }.count) / n
        }
    }

    // MARK: Calibration

    private struct CorpusFile: Decodable {
        struct Message: Decodable {
            let id: String
            let plaintext: String?
            let broken: Bool?
        }
        let messages: [Message]
    }

    static func load(
        corpusPath: String,
        window: Int = 72,
        features: Set<Feature> = Set(Feature.allCases)
    ) -> NavalDiscriminator? {
        guard let lexicon = NavalLexicon.load(corpusPath: corpusPath),
              let data = FileManager.default.contents(atPath: corpusPath),
              let file = try? JSONDecoder().decode(CorpusFile.self, from: data) else { return nil }

        // Naval side: sliding windows of real plaintext at the length we will actually score.
        var navalWindows: [[Int]] = []
        for message in file.messages {
            guard message.broken == true, let text = message.plaintext else { continue }
            let letters = EnigmaAlphabet.normalize(text)
            guard letters.count >= window else { continue }
            for start in stride(from: 0, through: letters.count - window, by: 17) {
                navalWindows.append(Array(letters[start..<(start + window)]))
            }
        }
        guard navalWindows.count > 8 else { return nil }

        // Random side: the stand-in for a wrong-key decrypt before any plug optimisation.
        var generator = SplitMix64(seed: 0x9E37_79B9)
        var randomWindows: [[Int]] = []
        for _ in 0..<navalWindows.count {
            randomWindows.append((0..<window).map { _ in Int(generator.next() % 26) })
        }

        func stats(_ windows: [[Int]], _ feature: Feature) -> (Double, Double) {
            let values = windows.map {
                value(feature, $0, lexicon: lexicon, excluding: nil)
            }
            let mean = values.reduce(0, +) / Double(values.count)
            let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
                / Double(max(values.count - 1, 1))
            return (mean, max(variance.squareRoot(), 1e-9))
        }

        var nm: [Feature: Double] = [:], nd: [Feature: Double] = [:]
        var rm: [Feature: Double] = [:], rd: [Feature: Double] = [:]
        for feature in Feature.allCases {
            (nm[feature], nd[feature]) = stats(navalWindows, feature)
            (rm[feature], rd[feature]) = stats(randomWindows, feature)
        }
        return NavalDiscriminator(
            lexicon: lexicon, enabled: features,
            navalMean: nm, navalDeviation: nd, randomMean: rm, randomDeviation: rd
        )
    }

    // MARK: Scoring

    /// Per-feature log-likelihood ratio in bits, under Gaussian models for each class.
    func featureBits(_ letters: [Int], excluding: String?) -> [Feature: Double] {
        var out: [Feature: Double] = [:]
        for feature in Feature.allCases where enabled.contains(feature) {
            let x = Self.value(feature, letters, lexicon: lexicon, excluding: excluding)
            guard let nm = navalMean[feature], let nd = navalDeviation[feature],
                  let rm = randomMean[feature], let rd = randomDeviation[feature]
            else { continue }
            // log2 of the ratio of two Gaussian densities.
            let underNaval = -((x - nm) * (x - nm)) / (2 * nd * nd) - log(nd)
            let underRandom = -((x - rm) * (x - rm)) / (2 * rd * rd) - log(rd)
            var bits = (underNaval - underRandom) / log(2.0)
            // Global rates are cheap for a ten-plug board to fake, so they are allowed to
            // contribute but not to dominate.
            if feature.gameable { bits *= 0.25 }
            out[feature] = bits
        }
        return out
    }

    func score(_ letters: [Int], excluding: String?) -> Double {
        featureBits(letters, excluding: excluding).values.reduce(0, +)
    }
}
