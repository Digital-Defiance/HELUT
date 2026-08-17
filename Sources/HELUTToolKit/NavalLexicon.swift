import Foundation
import HELUTCore

// MARK: - Lexicon score: fit naval *words*, not character statistics
//
// The naval trigram experiment (Phase 50.8) measured null, and the reason is instructive: it
// smoothed naval counts into the *same statistic* the generic model already covers. 7,500
// trigram observations over 17,576 cells adds almost nothing.
//
// A lexicon is a different feature class, and its shape is the interesting part. Matching
// `KOMXADMXUUUB` is a single event worth 12 x log2(26) ~ 56 bits of surprise. A trigram model
// smears that across ten grams *and* hands partial credit to near-misses. That smoothness is
// exactly what a wrong rotor setting climbs: the measured lesson of this phase is that better
// plugboard optimisation makes the margin worse, because a smooth score can be nudged upward
// from anywhere. A lexicon score is nearly discrete — you hit `FLOTTX` or you do not — so
// there is far less for a decoy to climb.
//
// **Which forces a design constraint.** A sparse score gives the climb no gradient either. It
// cannot be the climbing objective; used that way it would sit at zero until the board was
// nearly solved and the hill-climb would never start. So it is applied as a *discriminator*
// after the climb: climb with staged IC -> bigram -> trigram (which demonstrably works), then
// re-score the resulting plaintext with the lexicon and take the margin on that. Finding a
// good plugboard and deciding whether a setting is real are different jobs, and overfitting
// bites on the second one.
//
// Leave-one-out again: the controls under attack are in the corpus the lexicon is mined from.

struct NavalLexicon: Sendable {
    /// Token (as letter indices) -> set of message IDs carrying it.
    private let tokens: [[Int]: Set<String>]
    /// Longest token, so the matcher knows how far to look ahead.
    private let maxLength: Int
    /// Minimum distinct *other* messages a token must appear in to count.
    private let minReach: Int

    var tokenCount: Int { tokens.count }

    var sourceDescription: String {
        "U-534 naval lexicon (\(tokens.count) tokens, len ≤ \(maxLength), "
            + "reach ≥ \(minReach) excluding the message under test)"
    }

    private struct CorpusFile: Decodable {
        struct Message: Decodable {
            let id: String
            let plaintext: String?
            let broken: Bool?
        }
        let messages: [Message]
    }

    static func load(
        corpusPath: String, minLength: Int = 5, maxLength: Int = 12, minReach: Int = 2
    ) -> NavalLexicon? {
        guard let data = FileManager.default.contents(atPath: corpusPath),
              let file = try? JSONDecoder().decode(CorpusFile.self, from: data) else { return nil }
        var carriers: [[Int]: Set<String>] = [:]
        for message in file.messages {
            guard message.broken == true, let text = message.plaintext else { continue }
            let letters = EnigmaAlphabet.normalize(text)
            for length in minLength...maxLength where letters.count >= length {
                for start in 0...(letters.count - length) {
                    carriers[Array(letters[start..<(start + length)]), default: []]
                        .insert(message.id)
                }
            }
        }
        // A token only earns its place if more than one message carries it; single-message
        // content is the relay hypothesis, not shared register, and would self-fit.
        let kept = carriers.filter { $0.value.count >= minReach }
        guard !kept.isEmpty else { return nil }
        return NavalLexicon(tokens: kept, maxLength: maxLength, minReach: minReach)
    }

    /// Surprise bits per letter, from greedy longest non-overlapping matches.
    ///
    /// `excluding` withholds one message from every token's reach, so a control cannot be
    /// scored against a lexicon that remembers it. A token carried only by the excluded
    /// message drops out entirely.
    func score(_ letters: [Int], excluding messageID: String?) -> Double {
        guard !letters.isEmpty else { return 0 }
        let bitsPerLetter = log2(26.0)
        var total = 0.0
        var index = 0
        while index < letters.count {
            var matched = 0
            var length = min(maxLength, letters.count - index)
            while length >= 1 {
                let candidate = Array(letters[index..<(index + length)])
                if let reach = tokens[candidate] {
                    var effective = reach.count
                    if let messageID, reach.contains(messageID) { effective -= 1 }
                    if effective >= minReach {
                        matched = length
                        break
                    }
                }
                length -= 1
            }
            if matched > 0 {
                // Surprise of finding this run by chance in random text.
                total += Double(matched) * bitsPerLetter
                index += matched
            } else {
                index += 1
            }
        }
        return total / Double(letters.count)
    }
}
