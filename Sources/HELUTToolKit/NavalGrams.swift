import Foundation
import HELUTCore

// MARK: - Naval-dialect trigram model with leave-one-out and generic backoff
//
// Ostwald and Weierud name the hard part of the crib-free attack as finding a proper measure
// of a candidate's closeness to plaintext. The generic model already in the repo is fitted on
// 28.5M letters of German. That is a lot of German, but it is the *wrong* German: Kriegsmarine
// Enigma traffic is a dialect with `X` and `Y` as punctuation, digits spelled out (`NUL`,
// `EINS`, `ZWO`, `VIR`, `FUNF`, `SIBEN`, `ACHT`), `UUU` for U-boats, `VVV` and `FFFTTT` as
// procedure markers, and place names from one theatre.
//
// 64 GB of unified memory tempts one toward higher order — 5-grams are 11.9M entries, 6-grams
// 309M, and both fit. That temptation should be resisted: you cannot *estimate* a 6-gram model
// from 7,537 letters, which is all the naval plaintext that exists. The available win is
// domain match at low order, not order for its own sake.
//
// So: count trigrams on the 48 published U-534 decrypts and mix them into the generic model as
// a Dirichlet prior,
//
//     P(t) = (c_naval(t) + kappa * P_generic(t)) / (N_naval + kappa)
//
// which falls back smoothly to generic where the naval corpus has no evidence and takes over
// where it does. `kappa` is pseudo-count mass; larger means more trust in generic.
//
// **Leave-one-out is not optional.** The controls being attacked are *in* this corpus. Fitting
// on all 48 and then scoring one of them would be measuring the model's memory of the answer,
// which would look like a spectacular result and mean nothing. Every table is built with the
// control under test excluded.

/// Immutable once built, so it can cross the concurrent measurement loop safely.
struct NavalGramCorpus: Sendable {
    /// Per-message trigram counts, so a table can be rebuilt with any message withheld.
    let perMessage: [String: [Int: Int]]
    let totalCounts: [Int: Int]
    let letters: Int

    var sourceDescription: String {
        "U-534 naval dialect (\(perMessage.count) decrypts, \(letters) letters) "
            + "mixed into \(GermanTrigrams.sourceDescription)"
    }

    /// Log-probability table with `excluding` withheld from the naval counts.
    ///
    /// Returns nil when the generic model is unavailable, so callers fall back to generic
    /// scoring rather than silently scoring against a half-built table.
    func table(excluding messageID: String?, kappa: Double = 1200) -> [Double]? {
        guard let generic = GermanTrigrams.logProbs, generic.count == 17_576 else {
            return nil
        }
        var counts = totalCounts
        if let messageID, let own = perMessage[messageID] {
            for (gram, count) in own {
                let remaining = (counts[gram] ?? 0) - count
                if remaining > 0 { counts[gram] = remaining } else { counts[gram] = nil }
            }
        }
        let total = Double(counts.values.reduce(0, +))
        guard total > 0 else { return nil }

        var table = [Double](repeating: 0, count: 17_576)
        let denominator = total + kappa
        for gram in 0..<17_576 {
            let naval = Double(counts[gram] ?? 0)
            let prior = exp(generic[gram])
            let mixed = (naval + kappa * prior) / denominator
            // Floor matches the generic model's own treatment of unseen grams.
            table[gram] = mixed > 0 ? log(mixed) : generic[gram]
        }
        return table
    }

    /// How much of the naval corpus a single message represents — a sanity check that
    /// leave-one-out is actually withholding something.
    func shareOfCorpus(_ messageID: String) -> Double {
        guard let own = perMessage[messageID] else { return 0 }
        let mine = Double(own.values.reduce(0, +))
        let all = Double(totalCounts.values.reduce(0, +))
        return all > 0 ? mine / all : 0
    }
}

enum NavalGrams {

    private struct CorpusFile: Decodable {
        struct Message: Decodable {
            let id: String
            let plaintext: String?
            let broken: Bool?
        }
        let messages: [Message]
    }

    /// Mean trigram log-probability under an explicit table.
    static func score(_ letters: [Int], table: [Double]) -> Double {
        guard letters.count >= 3 else { return -10 }
        var total = 0.0
        for index in 0..<(letters.count - 2) {
            total += table[letters[index] * 676 + letters[index + 1] * 26 + letters[index + 2]]
        }
        return total / Double(letters.count - 2)
    }

    static func load(corpusPath: String) -> NavalGramCorpus? {
        guard let data = FileManager.default.contents(atPath: corpusPath),
              let file = try? JSONDecoder().decode(CorpusFile.self, from: data) else { return nil }
        var perMessage: [String: [Int: Int]] = [:]
        var totalCounts: [Int: Int] = [:]
        var letterCount = 0
        for message in file.messages {
            guard message.broken == true, let text = message.plaintext else { continue }
            let letters = EnigmaAlphabet.normalize(text)
            guard letters.count >= 3 else { continue }
            var counts: [Int: Int] = [:]
            for index in 0..<(letters.count - 2) {
                let gram = letters[index] * 676 + letters[index + 1] * 26 + letters[index + 2]
                counts[gram, default: 0] += 1
                totalCounts[gram, default: 0] += 1
            }
            perMessage[message.id] = counts
            letterCount += letters.count
        }
        guard !perMessage.isEmpty else { return nil }
        return NavalGramCorpus(
            perMessage: perMessage, totalCounts: totalCounts, letters: letterCount
        )
    }
}
