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
    let partition: String // "3-rotor" (Greek locked A) or "4-rotor"
    let positions: String
    let score: Double
    let ic: Double
    let plaintext: String
}

struct HybridFitness: Sendable {
    let chromosome: ShellChromosome
    let fitness: Double
    let bestHit: HybridLaneHit
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
        let batch = CleartextM4BatchEngine.make(ciphertext: ciphertext)
        progress?("ASIC datapath backend: \(batch.backendName) (B=\(cleartextBatchLaneCount) cleartext lanes/Greek)")
        progress?(
            "Shell evolution: \(config.evolveShell ? "ON" : "OFF") "
                + "freeRings=\(config.freeRingMutation) "
                + "WO=\(config.wheelOrders.count) ringSeeds=\(config.ringSeeds.count) "
                + "subspace=\(config.subspaceName)"
        )

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
                + " — fitness higher=better (bigram)"
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

            var next: [ShellChromosome] = Array(ranked.prefix(config.eliteCount).map(\.chromosome))
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
        population.map { chromosome in
            evaluateChromosome(
                chromosome,
                ciphertext: ciphertext,
                config: config,
                blockBGreeks: blockBGreeks,
                batch: batch
            )
        }
    }

    private static func evaluateChromosome(
        _ chromosome: ShellChromosome,
        ciphertext: [Int],
        config: Config,
        blockBGreeks: [Int],
        batch: CleartextM4BatchEngine
    ) -> HybridFitness {
        let wo = config.wheelOrders[chromosome.wheelOrderIndex]
        let base = EnigmaM4Key(
            greek: greeks[chromosome.greekIndex],
            rotors: wo,
            rings: chromosome.rings,
            positions: (0, 0, 0, 0),
            plugboard: chromosome.stecker.plugboard(),
            reflector: ukws[chromosome.ukwIndex]
        )

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

    private static func sampleGreeks(
        count: Int,
        excluding: Int,
        rng: inout some RandomNumberGenerator
    ) -> [Int] {
        var pool = Array(0..<26).filter { $0 != excluding }
        pool.shuffle(using: &rng)
        return Array(pool.prefix(max(0, count)))
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
        // Metal float vs Double; trust host if they diverge meaningfully.
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

func runHybridBombe() {
    print("HELUT — ASIC-esque self-evolving cracker (P1030680)")
    print("Ciphertext: \(U534MessageP1030680.ciphertext)")
    print("Architecture: evolving shell+stecker (host) × cleartext batch datapath — NOT mock PBS.")
    print("Genes: WO / Greek / thin UKW / rings / stecker. Block A Greek=A; Block B more Greeks.")
    print("")

    let ct = EnigmaAlphabet.normalize(U534MessageP1030680.ciphertext)
    let quick = CommandLine.arguments.contains("--quick")
    var config = HybridBombeHarness.Config()

    let subspaceName = stringFlag("--subspace") ?? "potsdam"
    let subspace = M4ThetisAttack.subspace(named: subspaceName)
    config.subspaceName = subspace.name
    config.wheelOrders = subspace.wheelOrders
    config.ringSeeds = subspace.ringVariants

    if quick {
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
            // Seed pool includes CLI rings; with free mutation the GA can still leave them.
            config.ringSeeds = list + config.ringSeeds.filter { seed in
                !list.contains { $0 == seed }
            }
            // When shell is locked, also pin rings on every individual via seeds-only path:
            // lock-shell keeps rings from parent A in crossover — seed pop[0] via run().
            if !config.evolveShell, let first = list.first {
                config.ringSeeds = [first]
            }
        }
    }

    let bDesc = config.fullGreekSweep ? "full 1…25" : "\(config.blockBGreekSamples) samples"
    let ringDesc = config.ringSeeds
        .prefix(6)
        .map { EnigmaAlphabet.string(from: [$0.0, $0.1, $0.2, $0.3]) }
        .joined(separator: ",")
    print(
        "Config: pop=\(config.population) gens=\(config.generations) "
            + "maxPlugs=\(config.maxPlugs) blockB_greeks=\(bDesc) "
            + "subspace=\(config.subspaceName) WO=\(config.wheelOrders.count) "
            + "evolveShell=\(config.evolveShell) freeRings=\(config.freeRingMutation) "
            + "ringSeeds=\(ringDesc)"
    )
    print("")

    let started = CFAbsoluteTimeGetCurrent()
    let best = HybridBombeHarness.run(ciphertext: ct, config: config) { message in
        fputs(message + "\n", stderr)
    }
    let elapsed = CFAbsoluteTimeGetCurrent() - started

    print("")
    print(String(format: "Elapsed: %.1f s", elapsed))
    print("Best shell: \(best.chromosome.describe(wheelOrders: config.wheelOrders))")
    print(
        String(
            format: "Best hit: partition=%@ pos=%@ score=%.4f IC=%.4f",
            best.bestHit.partition,
            best.bestHit.positions,
            best.bestHit.score,
            best.bestHit.ic
        )
    )
    print("Plain: \(best.bestHit.plaintext)")
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
    print("See ASIC_CRACKER.md / evolution-hybridization.md")
}
