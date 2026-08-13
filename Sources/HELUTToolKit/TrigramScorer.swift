import Foundation
import HELUTCore
import HELUTCLI

// MARK: - German trigram scorer (harness-local; HELUTCore stays untouched)
//
// Ostwald & Weierud (2017) found n=3 the best trade-off for authentic Enigma traffic:
// quadgrams are more selective but brittle against the garbles real intercepts contain.
//
// Loaded at runtime from Fixtures/german_trigrams.txt ("GRAM COUNT" lines) so corpora can
// be swapped and re-measured against --exhaust-selftest without a rebuild.

enum GermanTrigrams {
    private struct Model: Sendable {
        let table: [Double]
        let description: String
    }

    private static let model: Model? = load()

    static var sourceDescription: String { model?.description ?? "none (bigram fallback)" }

    /// log P(third | first, second), indexed first*676 + second*26 + third. Nil if no fixture.
    static var logProbs: [Double]? { model?.table }

    private static func fixtureURL() -> URL? {
        let fileManager = FileManager.default
        var roots: [URL] = []
        if let override = ProcessInfo.processInfo.environment["HELUT_FIXTURES"] {
            roots.append(URL(fileURLWithPath: override))
        }
        var cursor = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        for _ in 0..<6 {
            roots.append(cursor.appendingPathComponent("Fixtures"))
            cursor = cursor.deletingLastPathComponent()
        }
        var source = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            source = source.deletingLastPathComponent()
            roots.append(source.appendingPathComponent("Fixtures"))
        }
        for root in roots {
            let candidate = root.appendingPathComponent("german_trigrams.txt")
            if fileManager.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    private static func load() -> Model? {
        guard let url = fixtureURL(),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        var counts = [Double](repeating: 0, count: 17_576)
        var header = ""
        var loaded = 0

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("#") {
                header = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                continue
            }
            let parts = line.split(separator: " ")
            guard parts.count == 2, parts[0].count == 3, let count = Double(parts[1]) else { continue }
            let letters = Array(parts[0].utf8).map { Int($0) - 65 }
            guard letters.allSatisfy({ $0 >= 0 && $0 < 26 }) else { continue }
            counts[letters[0] * 676 + letters[1] * 26 + letters[2]] = count
            loaded += 1
        }
        guard loaded > 1_000 else { return nil }

        // Add-k smoothing per (first, second) context so unseen trigrams get a finite floor.
        let smoothing = 0.5
        var table = [Double](repeating: 0, count: 17_576)
        for context in 0..<676 {
            var total = 0.0
            for third in 0..<26 { total += counts[context * 26 + third] }
            let denominator = total + smoothing * 26.0
            for third in 0..<26 {
                table[context * 26 + third] = log((counts[context * 26 + third] + smoothing) / denominator)
            }
        }

        return Model(
            table: table,
            description: "Fixtures/german_trigrams.txt (\(loaded) grams; \(header))"
        )
    }

    /// Mean trigram log-probability; falls back to the embedded bigram model when absent.
    static func score(_ letters: [Int]) -> Double {
        guard let table = logProbs, letters.count >= 3 else {
            return LanguageScorer.bigramScore(letters)
        }
        var total = 0.0
        for index in 0..<(letters.count - 2) {
            total += table[letters[index] * 676 + letters[index + 1] * 26 + letters[index + 2]]
        }
        return total / Double(letters.count - 2)
    }

    static var isLoaded: Bool { logProbs != nil }
}
