import Foundation
import HELUTCore

// MARK: - Near-miss quarantine (Welchman → Stochastic handoff)
//
// Exact BREAK bars drop keys when the intercept is garbled (cf. Hörenberg /
// Girard degarbling of P1030681: U↔N, Q↔G, missing groups, dual transcriptions).
// Physical Welchman stops that clear a *soft* linguistic band but fail the
// strict bar are written to JSON and ingested as Hybrid `ShellChromosome` seeds.

struct QuarantineSoftBar: Codable, Sendable {
    /// Soft tail floor: `breakThreshold - softTailMargin` (default −4.000).
    var softTailFloor: Double
    /// Soft IC floor (default 0.048).
    var softICFloor: Double
    var strictTailFloor: Double
    var strictICFloor: Double
}

struct QuarantineCandidate: Codable, Sendable, Hashable {
    var ukw: String
    var greek: String
    var wheelOrder: String
    var rings: String
    var positions: String
    var steckerPairs: [String]
    var pairCount: Int

    var menuCrib: String
    var menuOffset: Int
    var menuLoops: Int
    var menuEdges: Int

    var ic: Double
    var tailScore: Double
    var fullScore: Double
    var effectiveTailScore: Double
    var cribExact: Bool
    var prefixEnd: Int?
    var prefixIC: Double?
    var prefixTailScore: Double?
    var plaintextPrefix: String

    var softBand: String
    var source: String
}

struct QuarantineManifest: Codable, Sendable {
    var target: String
    var ciphertext: String
    var generatedAt: String
    var sourceFixture: String
    var softBar: QuarantineSoftBar
    var candidates: [QuarantineCandidate]
}

enum NearMissQuarantine {
    static let defaultPath = "logs/quarantine_candidates.json"
    static let softTailMargin = 0.400
    static let softICFloor = 0.048

    static func defaultSoftBar() -> QuarantineSoftBar {
        QuarantineSoftBar(
            softTailFloor: PostBombeDiscriminator.breakThreshold - softTailMargin,
            softICFloor: softICFloor,
            strictTailFloor: PostBombeDiscriminator.breakThreshold,
            strictICFloor: PostBombeDiscriminator.icFloor
        )
    }

    /// Physical, crib-exact, below BREAK, but inside the soft linguistic band.
    static func shouldQuarantine(
        _ candidate: DiscriminatedCandidate,
        softBar: QuarantineSoftBar = defaultSoftBar()
    ) -> Bool {
        guard candidate.cribExact else { return false }
        if PostBombeDiscriminator.isBreak(candidate) { return false }

        let wholeSoft =
            candidate.ic >= softBar.softICFloor
            && candidate.tailScore > softBar.softTailFloor
        let prefixSoft: Bool
        if let prefix = candidate.prefix {
            prefixSoft = prefix.ic >= softBar.softICFloor
                && prefix.tailScore > softBar.softTailFloor
        } else {
            prefixSoft = false
        }
        return wholeSoft || prefixSoft
    }

    static func softBandReason(
        _ candidate: DiscriminatedCandidate,
        softBar: QuarantineSoftBar = defaultSoftBar()
    ) -> String {
        var reasons: [String] = []
        if candidate.ic >= softBar.softICFloor
            && candidate.tailScore > softBar.softTailFloor {
            reasons.append(
                String(
                    format: "whole IC=%.3f≥%.3f tail=%.3f>%.3f",
                    candidate.ic,
                    softBar.softICFloor,
                    candidate.tailScore,
                    softBar.softTailFloor
                )
            )
        }
        if let prefix = candidate.prefix,
           prefix.ic >= softBar.softICFloor,
           prefix.tailScore > softBar.softTailFloor {
            reasons.append(
                String(
                    format: "prefix@%d IC=%.3f tail=%.3f",
                    prefix.end,
                    prefix.ic,
                    prefix.tailScore
                )
            )
        }
        return reasons.isEmpty ? "soft-band" : reasons.joined(separator: "; ")
    }

    static func makeCandidate(
        from ranked: DiscriminatedCandidate,
        source: String,
        softBar: QuarantineSoftBar = defaultSoftBar()
    ) -> QuarantineCandidate {
        let stop = ranked.stop
        let rings = EnigmaAlphabet.string(from: [
            stop.rings.0, stop.rings.1, stop.rings.2, stop.rings.3
        ])
        let prefixLen = min(48, ranked.plaintext.count)
        return QuarantineCandidate(
            ukw: stop.ukw,
            greek: stop.greek,
            wheelOrder: stop.wheelOrder,
            rings: rings,
            positions: ranked.messageKey,
            steckerPairs: steckerPairTokens(ranked.stecker),
            pairCount: ranked.pairCount,
            menuCrib: stop.menu.crib,
            menuOffset: stop.menu.offset,
            menuLoops: stop.menu.loops,
            menuEdges: stop.menu.edgeCount,
            ic: ranked.ic,
            tailScore: ranked.tailScore,
            fullScore: ranked.score,
            effectiveTailScore: ranked.effectiveTailScore,
            cribExact: ranked.cribExact,
            prefixEnd: ranked.prefix?.end,
            prefixIC: ranked.prefix?.ic,
            prefixTailScore: ranked.prefix?.tailScore,
            plaintextPrefix: String(ranked.plaintext.prefix(prefixLen)),
            softBand: softBandReason(ranked, softBar: softBar),
            source: source
        )
    }

    static func steckerPairTokens(_ table: [Int]) -> [String] {
        var pairs: [String] = []
        for a in 0..<26 where table[a] > a {
            pairs.append(
                "\(EnigmaAlphabet.character(a))\(EnigmaAlphabet.character(table[a]))"
            )
        }
        return pairs
    }

    static func writeManifest(
        _ manifest: QuarantineManifest,
        to path: String
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    static func loadManifest(from path: String) -> QuarantineManifest? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONDecoder().decode(QuarantineManifest.self, from: data)
    }

    /// Convert a quarantine row into a Hybrid shell gene. Appends missing WO to `wheelOrders`.
    static func toShellChromosome(
        _ candidate: QuarantineCandidate,
        wheelOrders: inout [(EnigmaRotorSpec, EnigmaRotorSpec, EnigmaRotorSpec)]
    ) -> ShellChromosome? {
        let names = candidate.wheelOrder.split(separator: "-").map(String.init)
        guard names.count == 3 else { return nil }
        let lookup = M4ThetisAttack.navalRotors
        func rotor(_ name: String) -> EnigmaRotorSpec? {
            lookup.first { $0.name == name }
        }
        guard
            let left = rotor(names[0]),
            let middle = rotor(names[1]),
            let right = rotor(names[2])
        else { return nil }

        let triple = (left, middle, right)
        let woIndex: Int
        if let existing = wheelOrders.firstIndex(where: {
            $0.0.name == left.name && $0.1.name == middle.name && $0.2.name == right.name
        }) {
            woIndex = existing
        } else {
            wheelOrders.append(triple)
            woIndex = wheelOrders.count - 1
        }

        var pairs: [(Int, Int)] = []
        for token in candidate.steckerPairs {
            let chars = Array(token.uppercased())
            guard chars.count == 2 else { continue }
            let a = EnigmaAlphabet.index(chars[0])
            let b = EnigmaAlphabet.index(chars[1])
            pairs.append((min(a, b), max(a, b)))
        }
        pairs.sort { $0.0 < $1.0 }

        let greekIndex = candidate.greek.lowercased().hasPrefix("beta") ? 0 : 1
        let ukwIndex = candidate.ukw.uppercased() == "C" ? 1 : 0
        let rings = EnigmaM4Key.rings(fromLetters: candidate.rings)

        return ShellChromosome(
            stecker: PlugboardChromosome(pairs: pairs),
            wheelOrderIndex: woIndex,
            greekIndex: greekIndex,
            ukwIndex: ukwIndex,
            rings: rings
        )
    }

    /// Deduplicate by shell identity (UKW/Greek/WO/rings/positions/stecker).
    /// Prefer whole-message soft-band hits, then stronger IC / less-negative tail.
    static func prioritize(_ candidates: [QuarantineCandidate]) -> [QuarantineCandidate] {
        candidates.sorted { a, b in
            let aWhole = a.softBand.contains("whole")
            let bWhole = b.softBand.contains("whole")
            if aWhole != bWhole { return aWhole && !bWhole }
            if a.ic != b.ic { return a.ic > b.ic }
            return a.tailScore > b.tailScore
        }
    }

    static func dedupe(_ candidates: [QuarantineCandidate]) -> [QuarantineCandidate] {
        var seen = Set<String>()
        var out: [QuarantineCandidate] = []
        for c in candidates {
            let key = [
                c.ukw, c.greek, c.wheelOrder, c.rings, c.positions,
                c.steckerPairs.joined(separator: ",")
            ].joined(separator: "|")
            if seen.insert(key).inserted {
                out.append(c)
            }
        }
        return out.sorted { $0.effectiveTailScore > $1.effectiveTailScore }
    }

    // MARK: Wartime-style ciphertext garble (control)

    /// Confusable hand/radio letter pairs (Girard/Hörenberg P1030681 notes).
    static let confusionPairs: [(Character, Character)] = [
        ("U", "N"), ("Q", "G"), ("H", "F"), ("O", "D"), ("R", "K"), ("M", "W"),
        ("B", "R"), ("S", "G"), ("A", "R"), ("V", "U")
    ]

    /// Flip `flipCount` ciphertext letters strictly outside `[cribStart, cribEnd)`.
    /// When `blockWipe` is true, replace a contiguous post-crib block (missing-group /
    /// disarranged Schlüsselzettel style) instead of scattered confusions — needed to
    /// push a true key below the strict BREAK bar while staying cribExact.
    static func garbleCiphertext(
        _ ciphertext: [Int],
        cribStart: Int,
        cribEnd: Int,
        flipCount: Int,
        seed: UInt64,
        blockWipe: Bool = true
    ) -> (garbled: [Int], edits: [String]) {
        precondition(cribStart >= 0 && cribEnd <= ciphertext.count && cribStart < cribEnd)
        var rng = SplitMix64Public(seed: seed)
        var garbled = ciphertext
        var edits: [String] = []

        if blockWipe {
            let available = ciphertext.count - cribEnd
            let block = min(max(flipCount, 1), available)
            for pos in cribEnd..<(cribEnd + block) {
                let from = garbled[pos]
                var to = Int.random(in: 0..<26, using: &rng)
                if to == from { to = (from + 7) % 26 }
                garbled[pos] = to
                edits.append(
                    "\(pos):\(EnigmaAlphabet.character(from))→\(EnigmaAlphabet.character(to))"
                )
            }
            return (garbled, edits)
        }

        var near = Array(cribEnd..<min(ciphertext.count, cribEnd + max(flipCount * 2, 32)))
        var far = Array(0..<ciphertext.count).filter {
            ($0 < cribStart || $0 >= cribEnd) && !near.contains($0)
        }
        near.shuffle(using: &rng)
        far.shuffle(using: &rng)
        let pool = near + far
        let confusions: [Int: Int] = {
            var map: [Int: Int] = [:]
            for (a, b) in confusionPairs {
                let ia = EnigmaAlphabet.index(a)
                let ib = EnigmaAlphabet.index(b)
                map[ia] = ib
                map[ib] = ia
            }
            return map
        }()
        for pos in pool {
            if edits.count >= flipCount { break }
            let from = garbled[pos]
            let to = confusions[from] ?? ((from + 1) % 26)
            if to == from { continue }
            garbled[pos] = to
            edits.append(
                "\(pos):\(EnigmaAlphabet.character(from))→\(EnigmaAlphabet.character(to))"
            )
        }
        return (garbled, edits)
    }
}

/// Tiny SplitMix64 for garble control (helut target; avoids depending on harness private RNG).
private struct SplitMix64Public: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0xDEAD_BEEF : seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
