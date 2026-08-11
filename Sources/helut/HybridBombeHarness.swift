import Foundation
import HELUTCore

// MARK: - Hybrid GA: evolving daily shell × stecker × cleartext batch (P1030680)
//
// HELUTCore untouched. Fitness = boolean-faithful host M4 + cleartext Metal/CPU batch.
// Mock-PBS is never used for fitness.

/// Reciprocal Steckerbrett gene (≤ 10 pairs, no letter reused).
struct PlugboardChromosome: Sendable, Hashable {
    /// Unordered pairs with first < second.
    var pairs: [(Int, Int)]

    func descriptionPairs() -> String {
        if pairs.isEmpty { return "(none)" }
        return pairs
            .map { "\(EnigmaAlphabet.character($0.0))\(EnigmaAlphabet.character($0.1))" }
            .joined(separator: " ")
    }

    func plugboard() -> [Int] {
        EnigmaKey.plugboard(
            pairs: pairs.map { (EnigmaAlphabet.character($0.0), EnigmaAlphabet.character($0.1)) }
        )
    }

    static func random(maxPairs: Int, rng: inout some RandomNumberGenerator) -> PlugboardChromosome {
        var used = Set<Int>()
        var pairs: [(Int, Int)] = []
        let count = Int.random(in: 0...maxPairs, using: &rng)
        var pool = Array(0..<26)
        pool.shuffle(using: &rng)
        for letter in pool {
            if pairs.count >= count { break }
            if used.contains(letter) { continue }
            let partners = pool.filter { !used.contains($0) && $0 != letter }
            guard let other = partners.randomElement(using: &rng) else { break }
            let a = min(letter, other)
            let b = max(letter, other)
            pairs.append((a, b))
            used.insert(a)
            used.insert(b)
        }
        pairs.sort { $0.0 < $1.0 }
        return PlugboardChromosome(pairs: pairs)
    }

    func mutated(maxPairs: Int, rng: inout some RandomNumberGenerator) -> PlugboardChromosome {
        var next = pairs
        let roll = Int.random(in: 0..<5, using: &rng)
        switch roll {
        case 0 where !next.isEmpty:
            next.remove(at: Int.random(in: 0..<next.count, using: &rng))
        case 1 where next.count < maxPairs:
            let used = Set(next.flatMap { [$0.0, $0.1] })
            let free = (0..<26).filter { !used.contains($0) }
            if free.count >= 2 {
                let i = Int.random(in: 0..<free.count, using: &rng)
                var j = Int.random(in: 0..<free.count, using: &rng)
                while j == i { j = Int.random(in: 0..<free.count, using: &rng) }
                next.append((min(free[i], free[j]), max(free[i], free[j])))
            }
        case 2 where !next.isEmpty:
            let idx = Int.random(in: 0..<next.count, using: &rng)
            var used = Set(next.flatMap { [$0.0, $0.1] })
            used.remove(next[idx].0)
            used.remove(next[idx].1)
            let free = (0..<26).filter { !used.contains($0) }
            if let neu = free.randomElement(using: &rng) {
                let keep = Bool.random(using: &rng) ? next[idx].0 : next[idx].1
                let a = min(keep, neu)
                let b = max(keep, neu)
                if a != b { next[idx] = (a, b) }
            }
        default:
            if next.count >= 1 {
                let idx = Int.random(in: 0..<next.count, using: &rng)
                var used = Set(next.flatMap { [$0.0, $0.1] })
                used.remove(next[idx].0)
                used.remove(next[idx].1)
                let free = (0..<26).filter { !used.contains($0) }
                if free.count >= 2 {
                    let i = Int.random(in: 0..<free.count, using: &rng)
                    var j = Int.random(in: 0..<free.count, using: &rng)
                    while j == i { j = Int.random(in: 0..<free.count, using: &rng) }
                    next[idx] = (min(free[i], free[j]), max(free[i], free[j]))
                }
            }
        }
        next.sort { $0.0 < $1.0 }
        var seen = Set<Int>()
        var cleaned: [(Int, Int)] = []
        for pair in next {
            if seen.contains(pair.0) || seen.contains(pair.1) { continue }
            seen.insert(pair.0)
            seen.insert(pair.1)
            cleaned.append(pair)
            if cleaned.count >= maxPairs { break }
        }
        return PlugboardChromosome(pairs: cleaned)
    }

    static func crossover(
        _ a: PlugboardChromosome,
        _ b: PlugboardChromosome,
        maxPairs: Int,
        rng: inout some RandomNumberGenerator
    ) -> PlugboardChromosome {
        var pool = a.pairs + b.pairs
        pool.shuffle(using: &rng)
        var seen = Set<Int>()
        var out: [(Int, Int)] = []
        for pair in pool {
            if seen.contains(pair.0) || seen.contains(pair.1) { continue }
            seen.insert(pair.0)
            seen.insert(pair.1)
            out.append(pair)
            if out.count >= maxPairs { break }
        }
        out.sort { $0.0 < $1.0 }
        return PlugboardChromosome(pairs: out)
    }

    func hash(into hasher: inout Hasher) {
        for pair in pairs {
            hasher.combine(pair.0)
            hasher.combine(pair.1)
        }
    }

    static func == (lhs: PlugboardChromosome, rhs: PlugboardChromosome) -> Bool {
        lhs.pairs.count == rhs.pairs.count
            && zip(lhs.pairs, rhs.pairs).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
    }
}

/// Full searchable daily key: Walzenlage + Greek + UKW + rings + stecker.
/// Rings mutate freely (AACU can become AAAA); WO / Greek / UKW pick from the run subspace.
struct ShellChromosome: Sendable {
    var stecker: PlugboardChromosome
    var wheelOrderIndex: Int
    var greekIndex: Int // 0 = beta, 1 = gamma
    var ukwIndex: Int // 0 = thin B, 1 = thin C
    var rings: (Int, Int, Int, Int)

    func ringsString() -> String {
        EnigmaAlphabet.string(from: [rings.0, rings.1, rings.2, rings.3])
    }

    func describe(wheelOrders: [(EnigmaRotorSpec, EnigmaRotorSpec, EnigmaRotorSpec)]) -> String {
        guard wheelOrderIndex >= 0, wheelOrderIndex < wheelOrders.count else {
            return "UKW\(ukwIndex == 0 ? "B" : "C") \(greekIndex == 0 ? "beta" : "gamma") "
                + "WO#\(wheelOrderIndex)(?/\(wheelOrders.count)) "
                + "rings=\(EnigmaAlphabet.string(from: [rings.0, rings.1, rings.2, rings.3])) "
                + "stecker=\(stecker.descriptionPairs())"
        }
        let wo = wheelOrders[wheelOrderIndex]
        let greek = greekIndex == 0 ? "beta" : "gamma"
        let ukw = ukwIndex == 0 ? "B" : "C"
        return "UKW\(ukw) \(greek) \(wo.0.name)-\(wo.1.name)-\(wo.2.name) rings=\(ringsString()) stecker=\(stecker.descriptionPairs())"
    }

    static func random(
        maxPairs: Int,
        wheelOrderCount: Int,
        ringSeeds: [(Int, Int, Int, Int)],
        freeRings: Bool,
        rng: inout some RandomNumberGenerator
    ) -> ShellChromosome {
        let rings: (Int, Int, Int, Int)
        if freeRings, Bool.random(using: &rng) {
            rings = (
                Int.random(in: 0..<26, using: &rng),
                Int.random(in: 0..<26, using: &rng),
                Int.random(in: 0..<26, using: &rng),
                Int.random(in: 0..<26, using: &rng)
            )
        } else if let seed = ringSeeds.randomElement(using: &rng) {
            rings = seed
        } else {
            rings = (0, 0, 0, 0)
        }
        return ShellChromosome(
            stecker: .random(maxPairs: maxPairs, rng: &rng),
            wheelOrderIndex: Int.random(in: 0..<max(1, wheelOrderCount), using: &rng),
            greekIndex: Int.random(in: 0...1, using: &rng),
            ukwIndex: Int.random(in: 0...1, using: &rng),
            rings: rings
        )
    }

    func mutated(
        maxPairs: Int,
        evolveShell: Bool,
        wheelOrderCount: Int,
        ringSeeds: [(Int, Int, Int, Int)],
        freeRings: Bool,
        rng: inout some RandomNumberGenerator
    ) -> ShellChromosome {
        var next = self
        if !evolveShell {
            next.stecker = stecker.mutated(maxPairs: maxPairs, rng: &rng)
            return next
        }
        // ~55% stecker, ~45% shell genes (rings / WO / Greek / UKW).
        let roll = Double.random(in: 0..<1, using: &rng)
        if roll < 0.55 {
            next.stecker = stecker.mutated(maxPairs: maxPairs, rng: &rng)
        } else if roll < 0.80 {
            // Mutate one ring position — path from AACU → AAAA etc.
            if freeRings {
                let which = Int.random(in: 0..<4, using: &rng)
                let neu = Int.random(in: 0..<26, using: &rng)
                switch which {
                case 0: next.rings.0 = neu
                case 1: next.rings.1 = neu
                case 2: next.rings.2 = neu
                default: next.rings.3 = neu
                }
            } else if let seed = ringSeeds.randomElement(using: &rng) {
                next.rings = seed
            }
        } else if roll < 0.90 {
            next.wheelOrderIndex = Int.random(in: 0..<max(1, wheelOrderCount), using: &rng)
        } else if roll < 0.95 {
            next.greekIndex = 1 - next.greekIndex
        } else {
            next.ukwIndex = 1 - next.ukwIndex
        }
        return next
    }

    static func crossover(
        _ a: ShellChromosome,
        _ b: ShellChromosome,
        maxPairs: Int,
        evolveShell: Bool,
        rng: inout some RandomNumberGenerator
    ) -> ShellChromosome {
        let stecker = PlugboardChromosome.crossover(a.stecker, b.stecker, maxPairs: maxPairs, rng: &rng)
        guard evolveShell else {
            return ShellChromosome(
                stecker: stecker,
                wheelOrderIndex: a.wheelOrderIndex,
                greekIndex: a.greekIndex,
                ukwIndex: a.ukwIndex,
                rings: a.rings
            )
        }
        let rings: (Int, Int, Int, Int) = (
            Bool.random(using: &rng) ? a.rings.0 : b.rings.0,
            Bool.random(using: &rng) ? a.rings.1 : b.rings.1,
            Bool.random(using: &rng) ? a.rings.2 : b.rings.2,
            Bool.random(using: &rng) ? a.rings.3 : b.rings.3
        )
        return ShellChromosome(
            stecker: stecker,
            wheelOrderIndex: Bool.random(using: &rng) ? a.wheelOrderIndex : b.wheelOrderIndex,
            greekIndex: Bool.random(using: &rng) ? a.greekIndex : b.greekIndex,
            ukwIndex: Bool.random(using: &rng) ? a.ukwIndex : b.ukwIndex,
            rings: rings
        )
    }
}

struct HybridLaneHit: Sendable {
    let partition: String // "3-rotor" (Greek locked A) or "4-rotor" or "kpa-…"
    let positions: String
    let score: Double
    let ic: Double
    let plaintext: String
    var templateName: String = ""
}

struct HybridFitness: Sendable {
    let chromosome: ShellChromosome
    let fitness: Double
    let bestHit: HybridLaneHit
}

/// Masked plaintext template for Stochastic Bombe (`.` / values ≥26 = don't-care).
struct StochasticTemplate: Sendable {
    let name: String
    /// Per-position: 0…25 required letter, −1 don't-care.
    let pattern: [Int]
    var constrainedCount: Int { pattern.filter { $0 >= 0 && $0 < 26 }.count }

    static func parse(name: String, pattern: String) -> StochasticTemplate {
        let chars = Array(pattern.uppercased())
        let mapped: [Int] = chars.map { ch in
            if ch == "." || ch == "?" || ch == "X" || ch == "*" { return -1 }
            guard ch >= "A", ch <= "Z" else { return -1 }
            return EnigmaAlphabet.index(ch)
        }
        return StochasticTemplate(name: name, pattern: mapped)
    }
}

/// Outer GA (shell + stecker) × inner cleartext batch (Greek-A vs Block-B Greeks).
enum HybridBombeHarness {
    struct Config: Sendable {
        var population: Int = 24
        var generations: Int = 40
        var maxPlugs: Int = 10
        var eliteCount: Int = 4
        var mutationRate: Double = 0.55
        var blockBGreekSamples: Int = 5
        var fullGreekSweep: Bool = false
        var topLanesPerGreek: Int = 1
        /// When false, only stecker evolves (legacy lock-shell).
        var evolveShell: Bool = true
        /// When true, ring letters mutate freely across A…Z (AACU can become AAAA).
        var freeRingMutation: Bool = true
        var wheelOrders: [(EnigmaRotorSpec, EnigmaRotorSpec, EnigmaRotorSpec)] = [
            (EnigmaWarehouse.rotorIV, EnigmaWarehouse.rotorIII, EnigmaWarehouse.rotorVIII)
        ]
        var ringSeeds: [(Int, Int, Int, Int)] = [
            (0, 0, 0, 0),
            EnigmaM4Key.rings(fromLetters: "AACU"),
            EnigmaM4Key.rings(fromLetters: "VCCH")
        ]
        var subspaceName: String = "potsdam"
        /// When set, fitness is known-plaintext letter matches (0…N) instead of bigram/IC.
        /// Grades the evolutionary loop on a sharp landscape — the n-gram path is flat at 72 letters.
        var knownPlaintext: [Int]? = nil
        /// Stochastic Bombe template bank (masked). When non-empty, fitness = best letter-match
        /// across templates (don't-care positions ignored). Overrides bigram mode.
        var templates: [StochasticTemplate] = []
        /// When true, GA ranks by match/constrained (×1000 + absolute). Halt still needs exact.
        var kpaRatioFitness: Bool = false
        /// When set, inject this stecker as population[1] (control smoke / landscape check).
        var seedStecker: PlugboardChromosome? = nil
        /// Welchman soft-band near-misses injected as elite seeds (full shell + stecker).
        var seedChromosomes: [ShellChromosome] = []
        /// Local stecker hill-climb steps per elite after each KPA generation (0 = off).
        var kpaHillSteps: Int = 0
        /// Random shells sampled to estimate per-template noise floor (0 = skip).
        var noiseFloorSamples: Int = 0
        /// Option A RIGA: each generation = elites + mutants-from-elites + fresh random immigrants.
        /// Keeps the inner \(26^4\) message-key sweep per chromosome (not Option B full-key grid).
        var rigaMode: Bool = false
        /// Fraction of next population drawn uniform-random (default 0.19 ≈ user's 19% immigrants).
        var immigrantFraction: Double = 0.19
        /// Fraction retained untouched as elites (default 0.01). Absolute floor = `eliteCount`.
        var eliteFraction: Double = 0.01

        var usesKPA: Bool { knownPlaintext != nil || !templates.isEmpty }
    }

    private static let greeks: [EnigmaRotorSpec] = [
        EnigmaM4Warehouse.beta,
        EnigmaM4Warehouse.gamma
    ]
    private static let ukws: [[Int]] = [
        EnigmaM4Warehouse.thinB,
        EnigmaM4Warehouse.thinC
    ]

    static func run(
        ciphertext: [Int],
        config: Config,
        progress: ((String) -> Void)? = nil
    ) -> HybridFitness {
        let batch = CleartextM4BatchEngine.make(
            ciphertext: ciphertext,
            knownPlaintext: config.knownPlaintext ?? config.templates.first.map {
                $0.pattern.map { $0 < 0 ? 255 : $0 }
            }
        )
        progress?("ASIC datapath backend: \(batch.backendName) (B=\(cleartextBatchLaneCount) cleartext lanes/Greek)")
        if !config.templates.isEmpty {
            progress?(
                "Stochastic templates: \(config.templates.count) "
                    + "(constrained \(config.templates.map(\.constrainedCount).min() ?? 0)…"
                    + "\(config.templates.map(\.constrainedCount).max() ?? 0))"
            )
        }
        progress?(
            "Shell evolution: \(config.evolveShell ? "ON" : "OFF") "
                + "freeRings=\(config.freeRingMutation) "
                + "WO=\(config.wheelOrders.count) ringSeeds=\(config.ringSeeds.count) "
                + "subspace=\(config.subspaceName)"
        )
        if config.rigaMode {
            progress?(
                String(
                    format: "RIGA Option A: elite≈%.0f%% immigrants≈%.0f%% mutants=remainder "
                        + "(inner 26^4 message-key sweep per chromosome; scores on host)",
                    config.eliteFraction * 100,
                    config.immigrantFraction * 100
                )
            )
        }

        var rng = SystemRandomNumberGenerator()
        var population: [ShellChromosome] = (0..<config.population).map { _ in
            if config.evolveShell {
                return ShellChromosome.random(
                    maxPairs: config.maxPlugs,
                    wheelOrderCount: config.wheelOrders.count,
                    ringSeeds: config.ringSeeds,
                    freeRings: config.freeRingMutation,
                    rng: &rng
                )
            }
            // Locked shell: only stecker varies.
            return ShellChromosome(
                stecker: .random(maxPairs: config.maxPlugs, rng: &rng),
                wheelOrderIndex: 0,
                greekIndex: 1,
                ukwIndex: 0,
                rings: config.ringSeeds.first ?? (0, 0, 0, 0)
            )
        }
        // Seed individual 0: empty stecker on first seed rings + first WO (Potsdam-ish baseline).
        population[0] = ShellChromosome(
            stecker: PlugboardChromosome(pairs: []),
            wheelOrderIndex: 0,
            greekIndex: 1, // gamma
            ukwIndex: 0, // B
            rings: config.ringSeeds.first ?? (0, 0, 0, 0)
        )
        // Optional oracle stecker seed (control landscape smoke): proves KPA halt path.
        if let seedStecker = config.seedStecker, population.count > 1 {
            population[1] = ShellChromosome(
                stecker: seedStecker,
                wheelOrderIndex: 0,
                greekIndex: 1,
                ukwIndex: 0,
                rings: config.ringSeeds.first ?? (0, 0, 0, 0)
            )
            progress?("Seeded population[1] with oracle stecker (\(seedStecker.descriptionPairs()))")
        }
        // Welchman quarantine seeds: overwrite the front of the population with full shells.
        if !config.seedChromosomes.isEmpty {
            let n = min(config.seedChromosomes.count, population.count)
            for i in 0..<n {
                population[i] = config.seedChromosomes[i]
            }
            progress?(
                "Seeded population[0..<\(n)] from Welchman quarantine "
                    + "(\(config.seedChromosomes.count) candidate(s))"
            )
            for (i, seed) in config.seedChromosomes.prefix(n).enumerated() {
                progress?("  seed[\(i)] \(seed.describe(wheelOrders: config.wheelOrders))")
            }
        }

        let blockBGreeks: [Int]
        if config.fullGreekSweep {
            blockBGreeks = Array(1..<26)
        } else {
            blockBGreeks = sampleGreeks(count: config.blockBGreekSamples, excluding: 0, rng: &rng)
        }
        progress?(
            "Block B Greeks (fixed): "
                + (blockBGreeks.isEmpty
                    ? "(none)"
                    : EnigmaAlphabet.string(from: blockBGreeks))
                + " — fitness higher=better ("
                + (config.usesKPA ? "KPA letter-match" : "bigram")
                + ")"
        )

        var globalBest: HybridFitness?

        for generation in 0..<config.generations {
            progress?(
                "Hybrid gen \(generation + 1)/\(config.generations) "
                    + "pop=\(population.count) blockB_greeks=\(blockBGreeks.count)"
            )

            let evaluated = evaluatePopulation(
                population: population,
                ciphertext: ciphertext,
                config: config,
                blockBGreeks: blockBGreeks,
                batch: batch
            )
            let ranked = evaluated.sorted { $0.fitness > $1.fitness }
            if let top = ranked.first {
                if globalBest == nil || top.fitness > globalBest!.fitness {
                    globalBest = top
                }
                if config.usesKPA {
                    let denom: Int = {
                        if let t = config.templates.first(where: { $0.name == top.bestHit.templateName }) {
                            return t.constrainedCount
                        }
                        return config.knownPlaintext?.count ?? 0
                    }()
                    let hits = Int(top.bestHit.score + 0.5)
                    let pct = denom > 0 ? 100.0 * Double(hits) / Double(denom) : 0
                    progress?(
                        "  gen-best  \(hits)/\(denom) (\(String(format: "%.0f", pct))%) "
                            + "tmpl=\(top.bestHit.templateName) "
                            + String(format: "IC=%.4f pos=%@", top.bestHit.ic, top.bestHit.positions)
                            + " | \(top.chromosome.describe(wheelOrders: config.wheelOrders))"
                    )
                    if let gb = globalBest {
                        let gh = Int(gb.bestHit.score + 0.5)
                        progress?(
                            "  all-time  \(gh)/\(denom) "
                                + "tmpl=\(gb.bestHit.templateName) pos=\(gb.bestHit.positions) "
                                + "| \(gb.chromosome.describe(wheelOrders: config.wheelOrders))"
                        )
                    }
                    if kpaExactMatch(top, config: config) {
                        progress?("*** Hybrid halt — template exact match (\(top.bestHit.templateName)) ***")
                        return top
                    }
                } else {
                    progress?(
                        String(
                            format: "  gen-best  fitness=%.4f IC=%.4f pos=%@ | %@",
                            top.fitness,
                            top.bestHit.ic,
                            top.bestHit.positions,
                            top.chromosome.describe(wheelOrders: config.wheelOrders)
                        )
                    )
                    if let gb = globalBest {
                        progress?(
                            String(
                                format: "  all-time  fitness=%.4f IC=%.4f pos=%@ | %@",
                                gb.fitness,
                                gb.bestHit.ic,
                                gb.bestHit.positions,
                                gb.chromosome.describe(wheelOrders: config.wheelOrders)
                            )
                        )
                    }
                    let verdict = HostM4Bombe.evaluateBreak(
                        plaintext: EnigmaAlphabet.normalize(top.bestHit.plaintext)
                    )
                    if verdict.isPossibleBreak {
                        progress?("*** Hybrid halt — strong-crib break ***")
                        progress?(verdict.reason)
                        return top
                    }
                }
            }

            var next: [ShellChromosome] = Array(ranked.prefix(config.eliteCount).map(\.chromosome))
            // KPA: polish elites with local stecker hill-climb (letter-match is sharp enough).
            if config.usesKPA, config.kpaHillSteps > 0 {
                for i in 0..<next.count {
                    next[i] = kpaHillClimbStecker(
                        next[i],
                        ciphertext: ciphertext,
                        config: config,
                        batch: batch,
                        steps: config.kpaHillSteps,
                        rng: &rng
                    )
                }
                // Re-score polished elites; may halt mid-generation.
                let polished = next.map { chrom in
                    evaluateChromosome(
                        chrom,
                        ciphertext: ciphertext,
                        config: config,
                        blockBGreeks: blockBGreeks,
                        batch: batch
                    )
                }.sorted { $0.fitness > $1.fitness }
                if let top = polished.first {
                    if globalBest == nil || top.fitness > globalBest!.fitness {
                        globalBest = top
                    }
                    if kpaExactMatch(top, config: config) {
                        progress?(
                            String(
                                format: "  hill-climb recovered fitness=%.0f tmpl=%@ pos=%@ | %@",
                                top.fitness,
                                top.bestHit.templateName,
                                top.bestHit.positions,
                                top.chromosome.describe(wheelOrders: config.wheelOrders)
                            )
                        )
                        progress?("*** Hybrid halt — template exact match (hill-climb) ***")
                        return top
                    }
                }
            }
            if config.rigaMode {
                next = rigaNextGeneration(
                    ranked: ranked,
                    eliteSeed: next,
                    config: config,
                    rng: &rng
                )
            } else {
                while next.count < config.population {
                    let parentA = ranked[Int.random(in: 0..<min(ranked.count, config.population / 2), using: &rng)]
                        .chromosome
                    let parentB = ranked[Int.random(in: 0..<min(ranked.count, config.population / 2), using: &rng)]
                        .chromosome
                    var child = ShellChromosome.crossover(
                        parentA,
                        parentB,
                        maxPairs: config.maxPlugs,
                        evolveShell: config.evolveShell,
                        rng: &rng
                    )
                    if Double.random(in: 0..<1, using: &rng) < config.mutationRate {
                        child = child.mutated(
                            maxPairs: config.maxPlugs,
                            evolveShell: config.evolveShell,
                            wheelOrderCount: config.wheelOrders.count,
                            ringSeeds: config.ringSeeds,
                            freeRings: config.freeRingMutation,
                            rng: &rng
                        )
                    }
                    next.append(child)
                }
            }
            population = next
        }

        return globalBest ?? HybridFitness(
            chromosome: ShellChromosome(
                stecker: PlugboardChromosome(pairs: []),
                wheelOrderIndex: 0,
                greekIndex: 1,
                ukwIndex: 0,
                rings: (0, 0, 0, 0)
            ),
            fitness: -1e9,
            bestHit: HybridLaneHit(
                partition: "none",
                positions: "????",
                score: -1e9,
                ic: 0,
                plaintext: ""
            )
        )
    }

    private static func evaluatePopulation(
        population: [ShellChromosome],
        ciphertext: [Int],
        config: Config,
        blockBGreeks: [Int],
        batch: CleartextM4BatchEngine
    ) -> [HybridFitness] {
        let count = population.count
        // KPA path saturates the GPU inside each chromosome (26 × 17_576 lanes);
        // evaluate sequentially so Metal command buffers do not queue-thrash.
        // Bigram path is lighter per chromosome — parallelize across the population.
        if config.usesKPA {
            return population.map { chromosome in
                evaluateChromosome(
                    chromosome,
                    ciphertext: ciphertext,
                    config: config,
                    blockBGreeks: blockBGreeks,
                    batch: batch
                )
            }
        }
        return Array(unsafeUninitializedCapacity: count) { buffer, initializedCount in
            DispatchQueue.concurrentPerform(iterations: count) { index in
                buffer[index] = evaluateChromosome(
                    population[index],
                    ciphertext: ciphertext,
                    config: config,
                    blockBGreeks: blockBGreeks,
                    batch: batch
                )
            }
            initializedCount = count
        }
    }

    private static func evaluateChromosome(
        _ chromosome: ShellChromosome,
        ciphertext: [Int],
        config: Config,
        blockBGreeks: [Int],
        batch: CleartextM4BatchEngine
    ) -> HybridFitness {
        precondition(
            chromosome.wheelOrderIndex >= 0
                && chromosome.wheelOrderIndex < config.wheelOrders.count,
            "wheelOrderIndex \(chromosome.wheelOrderIndex) out of range for "
                + "\(config.wheelOrders.count) wheel orders (quarantine/subspace mismatch?)"
        )
        let wo = config.wheelOrders[chromosome.wheelOrderIndex]
        let base = EnigmaM4Key(
            greek: greeks[chromosome.greekIndex],
            rotors: wo,
            rings: chromosome.rings,
            positions: (0, 0, 0, 0),
            plugboard: chromosome.stecker.plugboard(),
            reflector: ukws[chromosome.ukwIndex]
        )

        // KPA / template-match mode: Metal/CPU cleartext batch × letter match.
        if config.usesKPA {
            let hit = bestKPAOverTemplates(
                dailyKey: base,
                ciphertext: ciphertext,
                config: config,
                batch: batch
            )
            let denom: Int = {
                if let t = config.templates.first(where: { $0.name == hit.templateName }) {
                    return t.constrainedCount
                }
                return config.knownPlaintext?.count ?? 0
            }()
            let matches = hit.score
            let fitness: Double
            if config.kpaRatioFitness, denom > 0 {
                // Rank by fraction; absolute matches break ties. Halt still uses hit.score.
                fitness = (matches / Double(denom)) * 1000.0 + matches
            } else {
                fitness = matches
            }
            return HybridFitness(chromosome: chromosome, fitness: fitness, bestHit: hit)
        }

        let blockA = bestOverLMR(
            dailyKey: base,
            ciphertext: ciphertext,
            greek: 0,
            partition: "3-rotor",
            batch: batch,
            topK: config.topLanesPerGreek
        )

        var best = blockA
        for greek in blockBGreeks {
            let hit = bestOverLMR(
                dailyKey: base,
                ciphertext: ciphertext,
                greek: greek,
                partition: "4-rotor",
                batch: batch,
                topK: config.topLanesPerGreek
            )
            if hit.score > best.score {
                best = hit
            }
        }

        return HybridFitness(chromosome: chromosome, fitness: best.score, bestHit: best)
    }

    /// Option A RIGA refill: keep polished elites, fill ~immigrantFraction with fresh random
    /// shells, and breed the rest from the top half (crossover + mutation). Message keys stay
    /// an exhaustive inner \(26^4\) sweep inside `evaluateChromosome` — not mutated here.
    private static func rigaNextGeneration(
        ranked: [HybridFitness],
        eliteSeed: [ShellChromosome],
        config: Config,
        rng: inout some RandomNumberGenerator
    ) -> [ShellChromosome] {
        let pop = max(config.population, 1)
        let eliteTarget = max(
            config.eliteCount,
            Int((config.eliteFraction * Double(pop)).rounded(.up))
        )
        var next = Array(eliteSeed.prefix(min(eliteTarget, pop)))
        if next.isEmpty, let best = ranked.first {
            next = [best.chromosome]
        }

        let immigrantTarget = min(
            pop - next.count,
            max(0, Int((config.immigrantFraction * Double(pop)).rounded()))
        )
        for _ in 0..<immigrantTarget {
            if config.evolveShell {
                next.append(
                    ShellChromosome.random(
                        maxPairs: config.maxPlugs,
                        wheelOrderCount: config.wheelOrders.count,
                        ringSeeds: config.ringSeeds,
                        freeRings: config.freeRingMutation,
                        rng: &rng
                    )
                )
            } else {
                next.append(
                    ShellChromosome(
                        stecker: .random(maxPairs: config.maxPlugs, rng: &rng),
                        wheelOrderIndex: next.first?.wheelOrderIndex ?? 0,
                        greekIndex: next.first?.greekIndex ?? 1,
                        ukwIndex: next.first?.ukwIndex ?? 0,
                        rings: next.first?.rings ?? (config.ringSeeds.first ?? (0, 0, 0, 0))
                    )
                )
            }
        }

        let parentPool = max(1, min(ranked.count, max(pop / 2, eliteTarget)))
        while next.count < pop {
            let parentA = ranked[Int.random(in: 0..<parentPool, using: &rng)].chromosome
            let parentB = ranked[Int.random(in: 0..<parentPool, using: &rng)].chromosome
            var child = ShellChromosome.crossover(
                parentA,
                parentB,
                maxPairs: config.maxPlugs,
                evolveShell: config.evolveShell,
                rng: &rng
            )
            // RIGA mutants always take at least one mutation (immigration already covers novelty).
            child = child.mutated(
                maxPairs: config.maxPlugs,
                evolveShell: config.evolveShell,
                wheelOrderCount: config.wheelOrders.count,
                ringSeeds: config.ringSeeds,
                freeRings: config.freeRingMutation,
                rng: &rng
            )
            if Double.random(in: 0..<1, using: &rng) < config.mutationRate {
                child = child.mutated(
                    maxPairs: config.maxPlugs,
                    evolveShell: config.evolveShell,
                    wheelOrderCount: config.wheelOrders.count,
                    ringSeeds: config.ringSeeds,
                    freeRings: config.freeRingMutation,
                    rng: &rng
                )
            }
            next.append(child)
        }
        return Array(next.prefix(pop))
    }

    private static func sampleGreeks(
        count: Int,
        excluding: Int,
        rng: inout some RandomNumberGenerator
    ) -> [Int] {
        var pool = Array(0..<26).filter { $0 != excluding }
        pool.shuffle(using: &rng)
        return Array(pool.prefix(max(0, count)))
    }

    private static func kpaExactMatch(_ fitness: HybridFitness, config: Config) -> Bool {
        let constrained: Int
        if !config.templates.isEmpty {
            constrained = config.templates.first(where: { $0.name == fitness.bestHit.templateName })?
                .constrainedCount
                ?? 0
        } else {
            constrained = config.knownPlaintext?.count ?? 0
        }
        // Always gate on raw letter hits in bestHit.score (not the ratio-scaled fitness).
        return constrained > 0 && Int(fitness.bestHit.score + 0.5) >= constrained
    }

    /// Empirical noise floor: max match ratio over random shells (no evolution).
    static func empiricalNoiseFloor(
        ciphertext: [Int],
        config: Config,
        samples: Int
    ) -> (ratio: Double, hits: Int, denom: Int) {
        guard samples > 0, let template = config.templates.first else {
            return (0, 0, 0)
        }
        let batch = CleartextM4BatchEngine.make(
            ciphertext: ciphertext,
            knownPlaintext: template.pattern.map { $0 < 0 ? 255 : $0 }
        )
        var rng = SystemRandomNumberGenerator()
        var bestHits = 0
        let denom = template.constrainedCount
        for _ in 0..<samples {
            let chrom: ShellChromosome
            if config.evolveShell {
                chrom = ShellChromosome.random(
                    maxPairs: config.maxPlugs,
                    wheelOrderCount: config.wheelOrders.count,
                    ringSeeds: config.ringSeeds,
                    freeRings: config.freeRingMutation,
                    rng: &rng
                )
            } else {
                chrom = ShellChromosome(
                    stecker: .random(maxPairs: config.maxPlugs, rng: &rng),
                    wheelOrderIndex: 0,
                    greekIndex: Int.random(in: 0...1, using: &rng),
                    ukwIndex: Int.random(in: 0...1, using: &rng),
                    rings: config.ringSeeds.randomElement(using: &rng) ?? (0, 0, 0, 0)
                )
            }
            let fit = evaluateChromosome(
                chrom,
                ciphertext: ciphertext,
                config: config,
                blockBGreeks: [],
                batch: batch
            )
            let hits = Int(fit.bestHit.score + 0.5)
            if hits > bestHits { bestHits = hits }
        }
        let ratio = denom > 0 ? Double(bestHits) / Double(denom) : 0
        return (ratio, bestHits, denom)
    }

    /// Best letter-match over the template bank (or single knownPlaintext).
    private static func bestKPAOverTemplates(
        dailyKey: EnigmaM4Key,
        ciphertext: [Int],
        config: Config,
        batch: CleartextM4BatchEngine
    ) -> HybridLaneHit {
        if config.templates.isEmpty, let known = config.knownPlaintext {
            return bestKPAMatch(
                dailyKey: dailyKey,
                ciphertext: ciphertext,
                known: known,
                templateName: "known-PT",
                batch: batch
            )
        }
        var best: HybridLaneHit?
        for template in config.templates {
            let known = template.pattern.map { $0 < 0 ? 255 : $0 }
            let hit = bestKPAMatch(
                dailyKey: dailyKey,
                ciphertext: ciphertext,
                known: known,
                templateName: template.name,
                batch: batch
            )
            if best == nil || hit.score > best!.score {
                best = hit
            }
            // Early exit if this template is fully satisfied.
            if Int(hit.score + 0.5) >= template.constrainedCount, template.constrainedCount > 0 {
                return hit
            }
        }
        return best!
    }

    /// Exhaustive 26⁴ message-key scan under a fixed daily shell, scored by letter match.
    private static func bestKPAMatch(
        dailyKey: EnigmaM4Key,
        ciphertext: [Int],
        known: [Int],
        templateName: String,
        batch: CleartextM4BatchEngine
    ) -> HybridLaneHit {
        let hit = batch.bestKPAMatch(key: dailyKey, known: known)
        let pos = positionsFromBatchLane(hit.lane, greek: hit.greek)
        var key = dailyKey
        key.positions = pos
        var machine = EnigmaM4Machine(key: key)
        let plain = machine.processText(ciphertext)
        return HybridLaneHit(
            partition: "kpa-26^4",
            positions: EnigmaAlphabet.string(from: [pos.0, pos.1, pos.2, pos.3]),
            score: Double(hit.score),
            ic: LanguageScorer.indexOfCoincidence(plain),
            plaintext: EnigmaAlphabet.string(from: plain),
            templateName: templateName
        )
    }

    /// Greedy stecker mutations under KPA fitness (locked shell).
    private static func kpaHillClimbStecker(
        _ chromosome: ShellChromosome,
        ciphertext: [Int],
        config: Config,
        batch: CleartextM4BatchEngine,
        steps: Int,
        rng: inout some RandomNumberGenerator
    ) -> ShellChromosome {
        var best = chromosome
        var bestScore = evaluateChromosome(
            best,
            ciphertext: ciphertext,
            config: config,
            blockBGreeks: [],
            batch: batch
        ).fitness
        for _ in 0..<steps {
            let trial = best.mutated(
                maxPairs: config.maxPlugs,
                evolveShell: false,
                wheelOrderCount: config.wheelOrders.count,
                ringSeeds: config.ringSeeds,
                freeRings: false,
                rng: &rng
            )
            let score = evaluateChromosome(
                trial,
                ciphertext: ciphertext,
                config: config,
                blockBGreeks: [],
                batch: batch
            ).fitness
            if score > bestScore {
                best = trial
                bestScore = score
            }
        }
        return best
    }

    /// On-device attack-score sieve → host decrypt only the winning lane (plaintext / break).
    private static func bestOverLMR(
        dailyKey: EnigmaM4Key,
        ciphertext: [Int],
        greek: Int,
        partition: String,
        batch: CleartextM4BatchEngine,
        topK: Int
    ) -> HybridLaneHit {
        let tops = batch.topLanes(key: dailyKey, greek: greek, topK: max(1, topK))
        guard let winner = tops.first else {
            return HybridLaneHit(
                partition: partition,
                positions: "????",
                score: -1e9,
                ic: 0,
                plaintext: ""
            )
        }

        let pos = positionsFromBatchLane(winner.lane, greek: greek)
        var key = dailyKey
        key.positions = pos
        var machine = EnigmaM4Machine(key: key)
        let plain = machine.processText(ciphertext)
        let ic = LanguageScorer.indexOfCoincidence(plain)
        let hostScore = HostM4Bombe.attackScore(plaintext: plain, scorer: .germanMilitary())
        let deviceScore = Double(winner.score)
        let finalScore = abs(hostScore - deviceScore) < 0.15 ? deviceScore : hostScore

        return HybridLaneHit(
            partition: partition,
            positions: EnigmaAlphabet.string(from: [pos.0, pos.1, pos.2, pos.3]),
            score: finalScore,
            ic: ic,
            plaintext: EnigmaAlphabet.string(from: plain)
        )
    }
}

// MARK: - CLI entry

/// Option A RIGA knobs. Call after other pop/gens defaults; explicit `--hybrid-pop` wins.
private func applyHybridRigaConfig(_ config: inout HybridBombeHarness.Config, quick: Bool) {
    guard CommandLine.arguments.contains("--hybrid-riga") else { return }
    config.rigaMode = true
    if intFlag("--hybrid-pop") == nil {
        config.population = quick ? 32 : 256
    }
    if intFlag("--hybrid-gens") == nil {
        config.generations = quick ? 12 : 48
    }
    if let raw = stringFlag("--hybrid-immigrants") {
        config.immigrantFraction = Double(raw) ?? config.immigrantFraction
    }
    if let raw = stringFlag("--hybrid-elites") {
        config.eliteFraction = Double(raw) ?? config.eliteFraction
    }
    config.eliteCount = max(
        config.eliteCount,
        Int((config.eliteFraction * Double(config.population)).rounded(.up))
    )
    // Unbind rings only when the shell itself may evolve.
    if config.evolveShell,
       !CommandLine.arguments.contains("--hybrid-pool-rings"),
       !CommandLine.arguments.contains("--hybrid-lock-shell") {
        config.freeRingMutation = true
    }
}

func runHybridBombe() {
    let control = CommandLine.arguments.contains("--hybrid-control")
    let stochastic = CommandLine.arguments.contains("--hybrid-stochastic")
    let quick = CommandLine.arguments.contains("--quick")
    var config = HybridBombeHarness.Config()

    let ciphertext: [Int]
    if control {
        // Stochastic Bombe control grade: first 72 letters of P1030684.
        // Fitness is exact letter match — not German trigrams. Training traffic
        // need not look like Potsdam register; it only has to decrypt to the target.
        let fullCT = EnigmaAlphabet.normalize(ControlMessageP1030684.ciphertext)
        let fullPT = EnigmaAlphabet.normalize(ControlMessageP1030684.plaintext)
        let n = min(72, fullCT.count, fullPT.count)
        ciphertext = Array(fullCT.prefix(n))
        config.knownPlaintext = Array(fullPT.prefix(n))
        config.subspaceName = "potsdam"
        config.wheelOrders = [
            (EnigmaWarehouse.rotorIV, EnigmaWarehouse.rotorIII, EnigmaWarehouse.rotorVIII)
        ]
        config.ringSeeds = [EnigmaM4Key.rings(fromLetters: ControlMessageP1030684.rings)]
        config.freeRingMutation = false
        // First control: lock the published shell, evolve stecker under KPA fitness.
        config.evolveShell = false
        config.population = quick ? 8 : 32
        config.generations = quick ? 6 : 80
        config.eliteCount = 4
        config.blockBGreekSamples = 0 // message key lives in the 26⁴ KPA scan
        config.kpaHillSteps = quick ? 8 : 24
        // Default: seed true stecker so gen-1 proves Metal KPA + halt. Blind with --hybrid-blind.
        // --hybrid-seed-drop N removes N true pairs (near-miss recovery grade).
        let blind = CommandLine.arguments.contains("--hybrid-blind")
        let drop = intFlag("--hybrid-seed-drop") ?? 0
        if !blind {
            var pairs = ControlMessageP1030684.plugPairs.map { pair -> (Int, Int) in
                let letters = Array(pair)
                let a = EnigmaAlphabet.index(letters[0])
                let b = EnigmaAlphabet.index(letters[1])
                return (min(a, b), max(a, b))
            }.sorted { $0.0 < $1.0 }
            if drop > 0, drop < pairs.count {
                pairs.removeLast(drop)
                print("Near-miss seed: dropped \(drop) true plug pair(s); \(pairs.count) remain")
            }
            config.seedStecker = PlugboardChromosome(pairs: pairs)
        }
        applyHybridRigaConfig(&config, quick: quick)
        // Control grade keeps the published shell locked; immigrants = fresh steckers only.
        config.evolveShell = false
        config.freeRingMutation = false
        print("HELUT — Stochastic Bombe KPA control (P1030684, \(n) letters)")
        print("Fitness: exact decrypt match against known plaintext (German-ness ignored)")
        print("Shell locked: UKW B / γ / IV-III-VIII / rings \(ControlMessageP1030684.rings)")
        if config.rigaMode {
            print(
                String(
                    format: "RIGA Option A ON — pop=%d gens=%d immigrants=%.0f%% (stecker-only)",
                    config.population, config.generations, config.immigrantFraction * 100
                )
            )
        }
        print(
            "Stecker seed: "
                + (config.seedStecker == nil
                    ? "BLIND (no oracle)"
                    : "oracle \(config.seedStecker!.descriptionPairs())")
        )
        print("KPA hill-climb steps/elite: \(config.kpaHillSteps)")
        print("Ciphertext: \(EnigmaAlphabet.string(from: ciphertext))")
        print("Target PT:  \(EnigmaAlphabet.string(from: config.knownPlaintext!))")
        print("")
    } else if stochastic {
        if CommandLine.arguments.contains("--hybrid-meta-evolve") {
            runMetaEvolveCampaign(quick: quick)
            return
        }
        ciphertext = EnigmaAlphabet.normalize(U534MessageP1030680.ciphertext)
        let rigor = CommandLine.arguments.contains("--hybrid-rigor")
        let path = stringFlag("--hybrid-templates")
            ?? (rigor
                ? "Fixtures/p1030680_stochastic_structural.json"
                : "Fixtures/p1030680_stochastic_templates.json")
        var bank = loadStochasticTemplates(path: path, messageLength: ciphertext.count)
        let minC = intFlag("--hybrid-min-constrained") ?? 16
        let maxC = intFlag("--hybrid-max-constrained") ?? (rigor ? 24 : 28)
        bank = bank.filter { $0.constrainedCount >= minC && $0.constrainedCount <= maxC }
        if !rigor, !CommandLine.arguments.contains("--hybrid-include-tiles") {
            bank = bank.filter {
                $0.name.hasPrefix("head:") || $0.name.hasPrefix("body:") || $0.name.hasPrefix("struct:")
            }
        }
        let cap = intFlag("--hybrid-template-cap") ?? (rigor ? 21 : (quick ? 8 : 16))
        bank = Array(
            bank.sorted { a, b in
                if a.constrainedCount != b.constrainedCount {
                    return a.constrainedCount > b.constrainedCount
                }
                return a.name < b.name
            }.prefix(cap)
        )
        precondition(!bank.isEmpty, "No stochastic templates after filters — check fixture / flags")

        let survivorBar = Double(stringFlag("--hybrid-survivor-ratio") ?? (rigor ? "0.80" : "0.80")) ?? 0.80
        let noiseMargin = Double(stringFlag("--hybrid-noise-margin") ?? "0.10") ?? 0.10
        let noiseSamples = intFlag("--hybrid-noise-samples") ?? (rigor ? (quick ? 6 : 12) : 0)

        let subspaceList: [String]
        if let raw = stringFlag("--hybrid-subspaces") {
            subspaceList = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        } else if rigor {
            subspaceList = ["potsdam", "two-notch"]
        } else {
            subspaceList = [stringFlag("--subspace") ?? "potsdam"]
        }

        config.blockBGreekSamples = 0
        config.kpaHillSteps = quick ? 4 : (rigor ? 16 : 12)
        config.population = quick ? 8 : (rigor ? 16 : 12)
        config.generations = quick ? 4 : (rigor ? 16 : 12)
        config.eliteCount = 4
        config.kpaRatioFitness = true
        config.evolveShell = !CommandLine.arguments.contains("--hybrid-lock-shell")
        if CommandLine.arguments.contains("--hybrid-pool-rings") || rigor {
            config.freeRingMutation = false
        }
        if let pop = intFlag("--hybrid-pop") { config.population = pop }
        if let gens = intFlag("--hybrid-gens") { config.generations = gens }
        if let ringsText = stringFlag("--rings") {
            let list = M4ThetisAttack.parseRingsList(ringsText)
            if !list.isEmpty {
                config.ringSeeds = list
            }
        } else if rigor {
            config.ringSeeds = [
                (0, 0, 0, 0),
                EnigmaM4Key.rings(fromLetters: "AACU"),
                EnigmaM4Key.rings(fromLetters: "VCCH")
            ]
        }
        applyHybridRigaConfig(&config, quick: quick)
        // Re-apply explicit pop/gens after RIGA defaults.
        if let pop = intFlag("--hybrid-pop") { config.population = pop }
        if let gens = intFlag("--hybrid-gens") { config.generations = gens }

        if let qPath = stringFlag("--hybrid-quarantine") {
            applyQuarantineSeeds(path: qPath, config: &config)
        }

        print("HELUT — Stochastic Bombe vs P1030680\(rigor ? " [RIGOR]" : "")")
        print("Ciphertext: \(U534MessageP1030680.ciphertext)")
        print("Fitness: match RATIO (×1000 + absolute); halt on exact constrained match")
        print(
            String(
                format: "Survivor bar: ratio ≥ %.0f%% AND ≥ noiseFloor + %.0f%%",
                survivorBar * 100, noiseMargin * 100
            )
        )
        print("Templates: \(path) → \(bank.count) masks (constrained \(minC)…\(maxC))")
        for t in bank {
            print("  [\(t.constrainedCount)] \(t.name)")
        }
        print("Subspaces: \(subspaceList.joined(separator: ", "))")
        print(
            "GA: pop=\(config.population) gens=\(config.generations) "
                + "hill=\(config.kpaHillSteps) noiseSamples=\(noiseSamples) "
                + "evolveShell=\(config.evolveShell) freeRings=\(config.freeRingMutation)"
                + (config.rigaMode
                    ? String(
                        format: " RIGA(imm=%.0f%%,elite=%.0f%%)",
                        config.immigrantFraction * 100, config.eliteFraction * 100
                    )
                    : "")
        )
        print("")

        struct Row: Sendable {
            var subspace: String
            var name: String
            var hit: Int
            var denom: Int
            var ratio: Double
            var noise: Double
            var delta: Double
            var survivor: Bool
            var exact: Bool
            var positions: String
            var ic: Double
            var shell: String
            var plain: String
        }

        let started = CFAbsoluteTimeGetCurrent()
        var rows: [Row] = []
        var survivors: [Row] = []

        for subspaceName in subspaceList {
            let space = M4ThetisAttack.subspace(named: subspaceName)
            print("════════ subspace \(space.name) (WO=\(space.wheelOrders.count)) ════════")
            for (index, template) in bank.enumerated() {
                var cfg = config
                cfg.subspaceName = space.name
                // Quarantine seeds carry wheelOrderIndex into config.wheelOrders. Replacing
                // that table with the subspace WO list remaps / OOB-traps those indices.
                if config.seedChromosomes.isEmpty || config.evolveShell {
                    cfg.wheelOrders = space.wheelOrders
                } else {
                    cfg.wheelOrders = config.wheelOrders
                    print(
                        "  quarantine WO table retained "
                            + "(\(cfg.wheelOrders.count) orders; subspace \(space.name) not applied)"
                    )
                }
                if stringFlag("--rings") == nil {
                    // Merge rigor ring seeds with subspace variants (dedup).
                    var rings = config.ringSeeds
                    for seed in space.ringVariants where !rings.contains(where: { $0 == seed }) {
                        rings.append(seed)
                    }
                    cfg.ringSeeds = rings
                }
                cfg.templates = [template]
                cfg.kpaRatioFitness = true

                print(
                    "——— [\(space.name)] \(index + 1)/\(bank.count) \(template.name) "
                        + "(\(template.constrainedCount)) ———"
                )

                let noise = HybridBombeHarness.empiricalNoiseFloor(
                    ciphertext: ciphertext,
                    config: cfg,
                    samples: noiseSamples
                )
                if noiseSamples > 0 {
                    print(
                        String(
                            format: "  noiseFloor: %d/%d (%.0f%%) over %d random shells",
                            noise.hits, noise.denom, noise.ratio * 100, noiseSamples
                        )
                    )
                }

                let best = HybridBombeHarness.run(ciphertext: ciphertext, config: cfg) { message in
                    fputs(message + "\n", stderr)
                }
                let denom = template.constrainedCount
                let hit = Int(best.bestHit.score + 0.5)
                let ratio = denom > 0 ? Double(hit) / Double(denom) : 0
                let delta = ratio - noise.ratio
                let exact = hit >= denom && denom > 0
                let survivor = exact
                    || (ratio + 1e-12 >= survivorBar && delta + 1e-12 >= noiseMargin)
                let row = Row(
                    subspace: space.name,
                    name: template.name,
                    hit: hit,
                    denom: denom,
                    ratio: ratio,
                    noise: noise.ratio,
                    delta: delta,
                    survivor: survivor,
                    exact: exact,
                    positions: best.bestHit.positions,
                    ic: best.bestHit.ic,
                    shell: best.chromosome.describe(wheelOrders: cfg.wheelOrders),
                    plain: best.bestHit.plaintext
                )
                rows.append(row)
                print(
                    String(
                        format: "  → %d/%d (%.0f%%) noise=%.0f%% Δ=%+.0f%% %@ pos=%@ IC=%.4f",
                        hit, denom, ratio * 100, noise.ratio * 100, delta * 100,
                        survivor ? "SURVIVOR" : "reject",
                        best.bestHit.positions,
                        best.bestHit.ic
                    )
                )
                print("    \(row.shell)")
                if survivor {
                    survivors.append(row)
                    print("  *** SURVIVOR — candidate for Welchman crib export ***")
                }
                if exact {
                    print("*** EXACT TEMPLATE MATCH — \(template.name) @ \(space.name) ***")
                }
            }
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - started
        print("")
        print("——— RIGOR SUMMARY (by ratio) ———")
        for row in rows.sorted(by: { $0.ratio > $1.ratio }) {
            print(
                String(
                    format: "  %5.1f%%  %2d/%-2d  noise=%4.0f%% Δ=%+5.1f%%  %-8@  %@%@  | %@",
                    row.ratio * 100, row.hit, row.denom, row.noise * 100, row.delta * 100,
                    row.subspace as NSString,
                    row.name as NSString,
                    row.survivor ? " ★" : "",
                    row.shell as NSString
                )
            )
        }
        print("")
        print(String(format: "Elapsed: %.1f s", elapsed))
        print("Survivors (≥\(Int(survivorBar * 100))% and ≥noise+\(Int(noiseMargin * 100))%): \(survivors.count)")
        if survivors.isEmpty {
            print("*** CLEAN NEGATIVE under rigor bar — templates/prior not near-true ***")
            print("Next: invent new structural hypotheses; do not burn catalog rings yet.")
        } else {
            print("Welchman handoff cribs (export manually into a menu fixture):")
            for s in survivors {
                let letters = Array(s.plain)
                // Reconstruct constrained crib letters from template pattern via name lookup.
                if let tmpl = bank.first(where: { $0.name == s.name }) {
                    var cribChars: [Character] = []
                    for (i, code) in tmpl.pattern.enumerated() where code >= 0 && code < 26 {
                        if i < letters.count {
                            cribChars.append(letters[i])
                        }
                    }
                    // Better: emit the hypothesized template letters (known), not decrypt.
                    let hypothesized = tmpl.pattern.compactMap { code -> Character? in
                        guard code >= 0, code < 26 else { return nil }
                        return EnigmaAlphabet.character(code)
                    }
                    print(
                        "  [\(s.subspace)] \(s.name)  hypothesized=\(String(hypothesized))  "
                            + "key=\(s.shell)  pos=\(s.positions)"
                    )
                }
            }
        }

        // Machine-readable campaign ledger
        let logPath = stringFlag("--hybrid-ledger")
            ?? "logs/stochastic-bombe-p1030680-rigor.json"
        let payload: [String: Any] = [
            "target": "P1030680",
            "elapsed_s": elapsed,
            "survivor_bar": survivorBar,
            "noise_margin": noiseMargin,
            "noise_samples": noiseSamples,
            "templates_path": path,
            "subspaces": subspaceList,
            "survivor_count": survivors.count,
            "rows": rows.map { r -> [String: Any] in
                [
                    "subspace": r.subspace,
                    "template": r.name,
                    "hits": r.hit,
                    "constrained": r.denom,
                    "ratio": r.ratio,
                    "noise_floor": r.noise,
                    "delta": r.delta,
                    "survivor": r.survivor,
                    "exact": r.exact,
                    "positions": r.positions,
                    "ic": r.ic,
                    "shell": r.shell,
                    "plaintext": r.plain
                ]
            }
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: logPath))
            print("Wrote \(logPath)")
        }
        print("See stochastic-bombe.md / BREAK_P1030680.md Phase 18")
        return
    } else {
        print("HELUT — ASIC-esque self-evolving cracker (P1030680)")
        print("Ciphertext: \(U534MessageP1030680.ciphertext)")
        print("Architecture: evolving shell+stecker (host) × cleartext batch datapath — NOT mock PBS.")
        print("Genes: WO / Greek / thin UKW / rings / stecker. Block A Greek=A; Block B more Greeks.")
        print("")
        ciphertext = EnigmaAlphabet.normalize(U534MessageP1030680.ciphertext)
        let subspaceName = stringFlag("--subspace") ?? "potsdam"
        let subspace = M4ThetisAttack.subspace(named: subspaceName)
        config.subspaceName = subspace.name
        config.wheelOrders = subspace.wheelOrders
        config.ringSeeds = subspace.ringVariants
    }

    if quick && !control && !stochastic {
        config.population = 8
        config.generations = 4
        config.blockBGreekSamples = 2
        config.eliteCount = 2
    }
    if CommandLine.arguments.contains("--hybrid-full-greek") {
        config.fullGreekSweep = true
    }
    if CommandLine.arguments.contains("--hybrid-lock-shell") {
        config.evolveShell = false
    }
    if CommandLine.arguments.contains("--hybrid-pool-rings") {
        config.freeRingMutation = false
    }
    if let pop = intFlag("--hybrid-pop") { config.population = pop }
    if let gens = intFlag("--hybrid-gens") { config.generations = gens }
    if let samples = intFlag("--hybrid-greek-samples") { config.blockBGreekSamples = samples }
    if let ringsText = stringFlag("--rings") {
        let list = M4ThetisAttack.parseRingsList(ringsText)
        if !list.isEmpty {
            config.ringSeeds = list + config.ringSeeds.filter { seed in
                !list.contains { $0 == seed }
            }
            if !config.evolveShell, let first = list.first {
                config.ringSeeds = [first]
            }
        }
    }
    applyHybridRigaConfig(&config, quick: quick)
    if let pop = intFlag("--hybrid-pop") { config.population = pop }
    if let gens = intFlag("--hybrid-gens") { config.generations = gens }

    let bDesc = config.fullGreekSweep ? "full 1…25" : "\(config.blockBGreekSamples) samples"
    let ringDesc = config.ringSeeds
        .prefix(6)
        .map { EnigmaAlphabet.string(from: [$0.0, $0.1, $0.2, $0.3]) }
        .joined(separator: ",")
    let fitDesc: String
    if !config.templates.isEmpty {
        fitDesc = "KPA templates×\(config.templates.count)"
    } else if let known = config.knownPlaintext {
        fitDesc = "KPA letter-match / \(known.count)"
    } else {
        fitDesc = "bigram"
    }
    print(
        "Config: pop=\(config.population) gens=\(config.generations) "
            + "maxPlugs=\(config.maxPlugs) blockB_greeks=\(bDesc) "
            + "subspace=\(config.subspaceName) WO=\(config.wheelOrders.count) "
            + "evolveShell=\(config.evolveShell) freeRings=\(config.freeRingMutation) "
            + "ringSeeds=\(ringDesc) fitness=\(fitDesc) "
            + "kpaHill=\(config.kpaHillSteps)"
            + (config.rigaMode
                ? String(
                    format: " RIGA(imm=%.0f%%,elite=%.0f%%)",
                    config.immigrantFraction * 100, config.eliteFraction * 100
                )
                : "")
    )
    print("")

    let started = CFAbsoluteTimeGetCurrent()
    let best = HybridBombeHarness.run(ciphertext: ciphertext, config: config) { message in
        fputs(message + "\n", stderr)
    }
    let elapsed = CFAbsoluteTimeGetCurrent() - started

    print("")
    print(String(format: "Elapsed: %.1f s", elapsed))
    print("Best shell: \(best.chromosome.describe(wheelOrders: config.wheelOrders))")
    print(
        String(
            format: "Best hit: partition=%@ tmpl=%@ pos=%@ score=%.4f IC=%.4f",
            best.bestHit.partition,
            best.bestHit.templateName,
            best.bestHit.positions,
            best.bestHit.score,
            best.bestHit.ic
        )
    )
    print("Plain: \(best.bestHit.plaintext)")
    if !config.templates.isEmpty {
        let denom = config.templates.first(where: { $0.name == best.bestHit.templateName })?
            .constrainedCount ?? 0
        print("Template match: \(Int(best.fitness))/\(denom) on \(best.bestHit.templateName)")
        if denom > 0, Int(best.fitness + 0.5) >= denom {
            print("*** TEMPLATE SATISFIED — inspect plaintext / stecker ***")
        } else {
            print("*** No template fully satisfied — continue bank / operators ***")
        }
    } else if let known = config.knownPlaintext {
        let got = EnigmaAlphabet.normalize(best.bestHit.plaintext)
        let matches = zip(got, known).filter { $0 == $1 }.count
        print("KPA match: \(matches)/\(known.count)")
        if got == known {
            print("*** CONTROL PASS — exact plaintext recovered ***")
        } else {
            print("*** CONTROL FAIL — decrypt does not match known plaintext ***")
        }
    } else {
        let verdict = HostM4Bombe.evaluateBreak(
            plaintext: EnigmaAlphabet.normalize(best.bestHit.plaintext)
        )
        print(
            String(
                format: "Verdict likeness=%.2f cribs=%@",
                verdict.likeness,
                (verdict.strongCribHits.isEmpty ? "(none)" : verdict.strongCribHits.joined(separator: ", "))
                    as NSString
            )
        )
        print(verdict.reason)
    }
    print("See ASIC_CRACKER.md / evolution-hybridization.md / stochastic-bombe.md")
}

func applyQuarantineSeeds(path: String, config: inout HybridBombeHarness.Config) {
    guard let manifest = NearMissQuarantine.loadManifest(from: path) else {
        fatalError("Could not load quarantine manifest from \(path)")
    }
    var wheelOrders = config.wheelOrders
    var seeds: [ShellChromosome] = []
    var ringSeeds = config.ringSeeds
    let ordered = NearMissQuarantine.prioritize(manifest.candidates)
    for candidate in ordered {
        guard let chrom = NearMissQuarantine.toShellChromosome(
            candidate,
            wheelOrders: &wheelOrders
        ) else {
            print("quarantine: skipped unreadable shell \(candidate.wheelOrder) / \(candidate.rings)")
            continue
        }
        seeds.append(chrom)
        if !ringSeeds.contains(where: { $0 == chrom.rings }) {
            ringSeeds.append(chrom.rings)
        }
    }
    precondition(!seeds.isEmpty, "quarantine \(path) produced 0 shell seeds")
    config.wheelOrders = wheelOrders
    config.ringSeeds = ringSeeds
    config.seedChromosomes = seeds
    // Local neighborhood: hold WO/Greek/UKW/rings; drift stecker (unless free-shell).
    if !CommandLine.arguments.contains("--hybrid-quarantine-free-shell") {
        config.evolveShell = false
        config.freeRingMutation = false
    }
    config.kpaHillSteps = max(config.kpaHillSteps, intFlag("--hybrid-kpa-hill") ?? 24)
    print(
        "Quarantine ingest: \(seeds.count) seed(s) from \(path) "
            + "(soft IC≥\(String(format: "%.3f", manifest.softBar.softICFloor)) "
            + "tail>\(String(format: "%.3f", manifest.softBar.softTailFloor)); "
            + "evolveShell=\(config.evolveShell) hill=\(config.kpaHillSteps))"
    )
    for (i, c) in ordered.prefix(seeds.count).enumerated() {
        print(
            String(
                format: "  [%d] %@ %@ %@ rings=%@ pos=%@ plugs=%d soft=%@ IC=%.3f tail=%.3f",
                i,
                c.ukw,
                c.greek,
                c.wheelOrder,
                c.rings,
                c.positions,
                c.pairCount,
                c.softBand,
                c.ic,
                c.effectiveTailScore
            )
        )
    }
}

private func loadStochasticTemplates(path: String, messageLength: Int) -> [StochasticTemplate] {
    let url = URL(fileURLWithPath: path)
    guard let data = try? Data(contentsOf: url),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let rows = root["templates"] as? [[String: Any]] else {
        fputs("Failed to load stochastic templates from \(path)\n", stderr)
        return []
    }
    var out: [StochasticTemplate] = []
    for row in rows {
        guard let name = row["name"] as? String,
              let pattern = row["pattern"] as? String else { continue }
        var tmpl = StochasticTemplate.parse(name: name, pattern: pattern)
        if tmpl.pattern.count < messageLength {
            tmpl = StochasticTemplate(
                name: name,
                pattern: tmpl.pattern + Array(repeating: -1, count: messageLength - tmpl.pattern.count)
            )
        } else if tmpl.pattern.count > messageLength {
            tmpl = StochasticTemplate(name: name, pattern: Array(tmpl.pattern.prefix(messageLength)))
        }
        out.append(tmpl)
    }
    return out
}

// MARK: - Meta-evolve: invent → cheap probe → deepen winners → mutate neighbors

private struct MetaProbeRow {
    var phase: String
    var subspace: String
    var template: StochasticTemplate
    var hits: Int
    var denom: Int
    var ratio: Double
    var noise: Double
    var delta: Double
    var positions: String
    var ic: Double
    var shell: String
    var plain: String
    var deepened: Bool
    var selected: Bool
}

/// Self-stecker legality: hypothesized plain letter must not equal ciphertext at that index.
private func templateSelfSteckerLegal(_ pattern: [Int], ciphertext: [Int]) -> Bool {
    for i in 0..<min(pattern.count, ciphertext.count) {
        let p = pattern[i]
        if p >= 0, p < 26, p == ciphertext[i] { return false }
    }
    let c = pattern.filter { $0 >= 0 && $0 < 26 }.count
    return c >= 16 && c <= 24
}

private func mutateStochasticTemplate(
    _ parent: StochasticTemplate,
    ciphertext: [Int],
    generation: Int,
    index: Int,
    rng: inout some RandomNumberGenerator
) -> StochasticTemplate? {
    var pattern = parent.pattern
    let constrainedIdx = pattern.indices.filter { pattern[$0] >= 0 && pattern[$0] < 26 }
    guard !constrainedIdx.isEmpty else { return nil }
    let roll = Int.random(in: 0..<4, using: &rng)
    switch roll {
    case 0:
        // Shift constrained block ±1 (slide hypothesis along the message).
        let dir = Bool.random(using: &rng) ? 1 : -1
        var next = [Int](repeating: -1, count: pattern.count)
        for i in constrainedIdx {
            let j = i + dir
            if j >= 0, j < pattern.count {
                next[j] = pattern[i]
            }
        }
        pattern = next
    case 1:
        // Replace one hypothesized letter.
        let i = constrainedIdx.randomElement(using: &rng)!
        var neu = Int.random(in: 0..<26, using: &rng)
        while neu == pattern[i] { neu = Int.random(in: 0..<26, using: &rng) }
        pattern[i] = neu
    case 2:
        // Swap two constrained letters.
        if constrainedIdx.count >= 2 {
            let a = constrainedIdx.randomElement(using: &rng)!
            var b = constrainedIdx.randomElement(using: &rng)!
            while b == a { b = constrainedIdx.randomElement(using: &rng)! }
            pattern.swapAt(a, b)
        }
    default:
        // Extend or shrink the rightmost constrained run by one.
        if let last = constrainedIdx.max() {
            if last + 1 < pattern.count, Bool.random(using: &rng) {
                var neu = Int.random(in: 0..<26, using: &rng)
                while neu == ciphertext[last + 1] { neu = Int.random(in: 0..<26, using: &rng) }
                pattern[last + 1] = neu
            } else if constrainedIdx.count > 16 {
                pattern[last] = -1
            }
        }
    }
    guard templateSelfSteckerLegal(pattern, ciphertext: ciphertext) else { return nil }
    return StochasticTemplate(
        name: "mut:\(parent.name)#g\(generation).\(index)",
        pattern: pattern
    )
}

private func probeTemplateOnce(
    template: StochasticTemplate,
    ciphertext: [Int],
    baseConfig: HybridBombeHarness.Config,
    subspace: M4ThetisAttack.Subspace,
    noiseSamples: Int,
    population: Int,
    generations: Int,
    hillSteps: Int,
    phase: String
) -> MetaProbeRow {
    var cfg = baseConfig
    cfg.subspaceName = subspace.name
    cfg.wheelOrders = subspace.wheelOrders
    var rings = baseConfig.ringSeeds
    for seed in subspace.ringVariants where !rings.contains(where: { $0 == seed }) {
        rings.append(seed)
    }
    cfg.ringSeeds = rings
    cfg.templates = [template]
    cfg.kpaRatioFitness = true
    cfg.population = population
    cfg.generations = generations
    cfg.kpaHillSteps = hillSteps
    cfg.eliteCount = min(4, max(2, population / 3))
    cfg.blockBGreekSamples = 0

    let noise = HybridBombeHarness.empiricalNoiseFloor(
        ciphertext: ciphertext,
        config: cfg,
        samples: noiseSamples
    )
    let best = HybridBombeHarness.run(ciphertext: ciphertext, config: cfg) { message in
        fputs("    \(message)\n", stderr)
    }
    let denom = template.constrainedCount
    let hits = Int(best.bestHit.score + 0.5)
    let ratio = denom > 0 ? Double(hits) / Double(denom) : 0
    return MetaProbeRow(
        phase: phase,
        subspace: subspace.name,
        template: template,
        hits: hits,
        denom: denom,
        ratio: ratio,
        noise: noise.ratio,
        delta: ratio - noise.ratio,
        positions: best.bestHit.positions,
        ic: best.bestHit.ic,
        shell: best.chromosome.describe(wheelOrders: cfg.wheelOrders),
        plain: best.bestHit.plaintext,
        deepened: false,
        selected: false
    )
}

/// Invent → cheap-score → allocate deep evolution to high-Δ texts → mutate neighbors → iterate.
func runMetaEvolveCampaign(quick: Bool) {
    let ciphertext = EnigmaAlphabet.normalize(U534MessageP1030680.ciphertext)
    let inventPath = stringFlag("--hybrid-templates")
        ?? "Fixtures/p1030680_stochastic_invented.json"
    let structuralPath = "Fixtures/p1030680_stochastic_structural.json"
    var bank = loadStochasticTemplates(path: inventPath, messageLength: ciphertext.count)
    // Only mix in the training structural seeds when using the default invent library.
    // Explicit --hybrid-templates (e.g. collapse bank) stays a pure prior.
    let mixStructural = stringFlag("--hybrid-templates") == nil
        || CommandLine.arguments.contains("--hybrid-mix-structural")
    if mixStructural {
        let structural = loadStochasticTemplates(path: structuralPath, messageLength: ciphertext.count)
        var seen = Set(bank.map(\.pattern))
        for t in structural where !seen.contains(t.pattern) {
            bank.append(t)
            seen.insert(t.pattern)
        }
    }
    let minC = intFlag("--hybrid-min-constrained") ?? 16
    let maxC = intFlag("--hybrid-max-constrained") ?? 24
    bank = bank.filter { $0.constrainedCount >= minC && $0.constrainedCount <= maxC }
    let inventCap = intFlag("--hybrid-invent-cap") ?? (quick ? 24 : 64)
    bank = Array(bank.shuffled().prefix(inventCap))
    if mixStructural {
        let structural = loadStochasticTemplates(path: structuralPath, messageLength: ciphertext.count)
        for t in structural where t.constrainedCount >= minC && t.constrainedCount <= maxC {
            if !bank.contains(where: { $0.pattern == t.pattern }) {
                bank.append(t)
            }
        }
    }
    precondition(!bank.isEmpty, "Empty invent bank")

    let survivorBar = Double(stringFlag("--hybrid-survivor-ratio") ?? "0.80") ?? 0.80
    let noiseMargin = Double(stringFlag("--hybrid-noise-margin") ?? "0.10") ?? 0.10
    let deepenKeep = intFlag("--hybrid-deepen-keep") ?? (quick ? 3 : 6)
    let neighborCount = intFlag("--hybrid-neighbors") ?? (quick ? 4 : 8)
    let metaRounds = intFlag("--hybrid-meta-rounds") ?? (quick ? 1 : 2)

    let subspaceList: [String]
    if let raw = stringFlag("--hybrid-subspaces") {
        subspaceList = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    } else {
        // Meta-evolve defaults to potsdam first (fast); pass two-notch explicitly to dual.
        subspaceList = [stringFlag("--subspace") ?? "potsdam"]
    }

    var base = HybridBombeHarness.Config()
    base.kpaRatioFitness = true
    base.evolveShell = !CommandLine.arguments.contains("--hybrid-lock-shell")
    base.freeRingMutation = false
    base.ringSeeds = [
        (0, 0, 0, 0),
        EnigmaM4Key.rings(fromLetters: "AACU"),
        EnigmaM4Key.rings(fromLetters: "VCCH")
    ]
    if let ringsText = stringFlag("--rings") {
        let list = M4ThetisAttack.parseRingsList(ringsText)
        if !list.isEmpty { base.ringSeeds = list }
    }
    applyHybridRigaConfig(&base, quick: quick)
    if CommandLine.arguments.contains("--hybrid-pool-rings") || !base.rigaMode {
        // Meta default keeps ring seeds unless RIGA unbound them.
        if !base.rigaMode { base.freeRingMutation = false }
    }

    let cheapNoise = quick ? 4 : 6
    let cheapPop = quick ? 6 : 8
    let cheapGens = quick ? 3 : 5
    let cheapHill = quick ? 2 : 4
    let deepNoise = quick ? 6 : 10
    let deepPop = intFlag("--hybrid-pop") ?? (quick ? 10 : 16)
    let deepGens = intFlag("--hybrid-gens") ?? (quick ? 8 : 24)
    let deepHill = quick ? 8 : 20

    print("HELUT — Stochastic Bombe META-EVOLVE vs P1030680")
    print("Ciphertext: \(U534MessageP1030680.ciphertext)")
    print("Loop: invent → cheap probe → deepen top-Δ → mutate neighbors → repeat")
    print("Invent bank: \(inventPath) (+ structural seeds) → \(bank.count) masks")
    print(
        String(
            format: "Bars: survivor ≥ %.0f%% and ≥ noise+%.0f%%; deepenKeep=%d neighbors=%d rounds=%d",
            survivorBar * 100, noiseMargin * 100, deepenKeep, neighborCount, metaRounds
        )
    )
    print("Cheap: pop=\(cheapPop) gens=\(cheapGens) hill=\(cheapHill) noise=\(cheapNoise)")
    print("Deep:  pop=\(deepPop) gens=\(deepGens) hill=\(deepHill) noise=\(deepNoise)")
    print("Subspaces: \(subspaceList.joined(separator: ", "))")
    print("")

    let started = CFAbsoluteTimeGetCurrent()
    var ledger: [MetaProbeRow] = []
    var survivors: [MetaProbeRow] = []
    var rng = SystemRandomNumberGenerator()
    var workingBank = bank

    for round in 0..<metaRounds {
        print("════════ META ROUND \(round + 1)/\(metaRounds) — invent pool \(workingBank.count) ════════")
        var cheapRows: [MetaProbeRow] = []
        for subspaceName in subspaceList {
            let space = M4ThetisAttack.subspace(named: subspaceName)
            print("—— cheap probe @ \(space.name) ——")
            for (i, template) in workingBank.enumerated() {
                print("  [\(i + 1)/\(workingBank.count)] \(template.name) (\(template.constrainedCount))")
                let row = probeTemplateOnce(
                    template: template,
                    ciphertext: ciphertext,
                    baseConfig: base,
                    subspace: space,
                    noiseSamples: cheapNoise,
                    population: cheapPop,
                    generations: cheapGens,
                    hillSteps: cheapHill,
                    phase: "cheap-r\(round + 1)"
                )
                print(
                    String(
                        format: "    cheap %d/%d (%.0f%%) noise=%.0f%% Δ=%+.0f%%",
                        row.hits, row.denom, row.ratio * 100, row.noise * 100, row.delta * 100
                    )
                )
                cheapRows.append(row)
                ledger.append(row)
            }
        }

        // Select by Δ over noise (then ratio). This is the self-evolution allocation step.
        let ranked = cheapRows.sorted {
            if abs($0.delta - $1.delta) > 1e-9 { return $0.delta > $1.delta }
            return $0.ratio > $1.ratio
        }
        let selected = Array(ranked.prefix(deepenKeep))
        print("—— SELECT for deep evolution (top \(selected.count) by Δ) ——")
        for s in selected {
            print(
                String(
                    format: "  ★ Δ=%+.0f%%  %.0f%%  %@  %@",
                    s.delta * 100, s.ratio * 100, s.subspace, s.template.name
                )
            )
        }

        var deepParents: [MetaProbeRow] = []
        for sel in selected {
            let resolved = M4ThetisAttack.subspace(named: {
                if sel.subspace.contains("two-notch") { return "two-notch" }
                if sel.subspace.contains("potsdam") { return "potsdam" }
                return subspaceList[0]
            }())
            print("—— DEEPEN \(sel.template.name) @ \(resolved.name) ——")
            var deep = probeTemplateOnce(
                template: sel.template,
                ciphertext: ciphertext,
                baseConfig: base,
                subspace: resolved,
                noiseSamples: deepNoise,
                population: deepPop,
                generations: deepGens,
                hillSteps: deepHill,
                phase: "deep-r\(round + 1)"
            )
            deep.deepened = true
            deep.selected = true
            print(
                String(
                    format: "    deep %d/%d (%.0f%%) noise=%.0f%% Δ=%+.0f%% pos=%@",
                    deep.hits, deep.denom, deep.ratio * 100, deep.noise * 100, deep.delta * 100,
                    deep.positions
                )
            )
            ledger.append(deep)
            deepParents.append(deep)
            let exact = deep.hits >= deep.denom && deep.denom > 0
            let survivor = exact
                || (deep.ratio + 1e-12 >= survivorBar && deep.delta + 1e-12 >= noiseMargin)
            if survivor {
                survivors.append(deep)
                print("    *** SURVIVOR ***")
            }
            if exact {
                print("*** EXACT TEMPLATE MATCH — \(deep.template.name) ***")
            }
        }

        // Invent neighbors of deep parents by mutating hypothesized plaintext.
        var neighbors: [StochasticTemplate] = []
        var n = 0
        while neighbors.count < neighborCount, n < neighborCount * 8 {
            n += 1
            guard let parent = deepParents.randomElement(using: &rng) else { break }
            if let mut = mutateStochasticTemplate(
                parent.template,
                ciphertext: ciphertext,
                generation: round + 1,
                index: neighbors.count,
                rng: &rng
            ) {
                if !workingBank.contains(where: { $0.pattern == mut.pattern }),
                   !neighbors.contains(where: { $0.pattern == mut.pattern }) {
                    neighbors.append(mut)
                }
            }
        }
        print("—— INVENT \(neighbors.count) neighbor texts from deep parents ——")
        for mut in neighbors {
            print("  + \(mut.name) (\(mut.constrainedCount))")
        }
        workingBank = neighbors
        if workingBank.isEmpty {
            print("No legal neighbors invented; stopping meta rounds.")
            break
        }
        if !survivors.isEmpty {
            print("Survivor(s) found — stopping further meta rounds.")
            break
        }
    }

    let elapsed = CFAbsoluteTimeGetCurrent() - started
    print("")
    print("——— META-EVOLVE SUMMARY ———")
    let deepOnly = ledger.filter(\.deepened).sorted { $0.delta > $1.delta }
    print("Deepened cells: \(deepOnly.count)")
    for row in deepOnly.prefix(12) {
        print(
            String(
                format: "  Δ=%+5.1f%%  %5.1f%%  %2d/%-2d  %@  %@",
                row.delta * 100, row.ratio * 100, row.hits, row.denom,
                row.phase, row.template.name
            )
        )
    }
    print(String(format: "Elapsed: %.1f s", elapsed))
    print("Survivors: \(survivors.count)")
    if survivors.isEmpty {
        print("*** No meta-evolve survivor — continue inventing qualitatively new texts ***")
    } else {
        for s in survivors {
            let hyp = s.template.pattern.compactMap { code -> Character? in
                guard code >= 0, code < 26 else { return nil }
                return EnigmaAlphabet.character(code)
            }
            print("  SURVIVOR \(s.template.name) hyp=\(String(hyp)) shell=\(s.shell) pos=\(s.positions)")
        }
    }

    let logPath = "logs/stochastic-bombe-p1030680-meta-evolve.json"
    let payload: [String: Any] = [
        "target": "P1030680",
        "mode": "meta-evolve",
        "elapsed_s": elapsed,
        "invent_path": inventPath,
        "invent_cap": inventCap,
        "deepen_keep": deepenKeep,
        "neighbors": neighborCount,
        "meta_rounds": metaRounds,
        "survivor_bar": survivorBar,
        "noise_margin": noiseMargin,
        "survivor_count": survivors.count,
        "rows": ledger.map { r -> [String: Any] in
            [
                "phase": r.phase,
                "subspace": r.subspace,
                "template": r.template.name,
                "hits": r.hits,
                "constrained": r.denom,
                "ratio": r.ratio,
                "noise_floor": r.noise,
                "delta": r.delta,
                "deepened": r.deepened,
                "selected": r.selected,
                "positions": r.positions,
                "ic": r.ic,
                "shell": r.shell,
                "plaintext": r.plain,
                "pattern": r.template.pattern.map { $0 < 0 ? "." : String(EnigmaAlphabet.character($0)) }.joined()
            ]
        }
    ]
    if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
        try? data.write(to: URL(fileURLWithPath: logPath))
        print("Wrote \(logPath)")
    }
    print("See stochastic-bombe.md — meta-evolve allocates self-evolution by Δ over noise")
}

