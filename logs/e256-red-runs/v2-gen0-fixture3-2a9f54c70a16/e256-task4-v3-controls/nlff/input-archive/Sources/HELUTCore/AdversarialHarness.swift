import Foundation
import Metal

/// Generational TensorLUT adversarial loop: population over INIT genomes, data-parallel batch eval.
package final class AdversarialHarness {
    package struct Config: Sendable {
        package var populationSize: Int
        package var generations: Int
        package var eliteCount: Int
        /// Apply sparse mutation to seeds at gen 0 for diversity.
        package var seedScatter: Bool
        package var rngSeed: UInt64?
        /// When set, replaces `netlist.packedINITBuffer()` (e.g. cold-start wipe to `0.5`).
        package var seedInits: [Float]?
        /// Probability of LUT-block crossover between two parents when breeding.
        package var crossoverRate: Float
        /// After the last generation, snap the elite INIT weights to `{0,1}` if crypto is preserved.
        package var polishBinaryAtEnd: Bool
        /// Per-LUT freeze mask (`true` = frozen). Applied to every chromosome in the population.
        package var freezeMask: [Bool]?
        /// When λ first reaches `resignLambdaFraction * λ_max`, resign if melt-region
        /// non-binary count is still strictly above this threshold. `nil` disables.
        package var resignNonBinaryAbove: Int?
        /// Fraction of `λ_max` that arms the resignation check (default: midpoint).
        package var resignLambdaFraction: Float
        /// How many fresh-seed reboots after a resignation (0 = resign ends the run).
        package var maxLineageRestarts: Int

        package init(
            populationSize: Int = 16,
            generations: Int = 32,
            eliteCount: Int = 2,
            seedScatter: Bool = true,
            rngSeed: UInt64? = nil,
            seedInits: [Float]? = nil,
            crossoverRate: Float = 0.5,
            polishBinaryAtEnd: Bool = false,
            freezeMask: [Bool]? = nil,
            resignNonBinaryAbove: Int? = nil,
            resignLambdaFraction: Float = 0.5,
            maxLineageRestarts: Int = 0
        ) {
            self.populationSize = populationSize
            self.generations = generations
            self.eliteCount = eliteCount
            self.seedScatter = seedScatter
            self.rngSeed = rngSeed
            self.seedInits = seedInits
            self.crossoverRate = min(1, max(0, crossoverRate))
            self.polishBinaryAtEnd = polishBinaryAtEnd
            self.freezeMask = freezeMask
            self.resignNonBinaryAbove = resignNonBinaryAbove
            self.resignLambdaFraction = min(1, max(0, resignLambdaFraction))
            self.maxLineageRestarts = max(0, maxLineageRestarts)
        }
    }

    package struct GenerationStats: Sendable {
        package let generation: Int
        package let bestFitness: Float
        package let bestCrypto: Float
        package let lambda: Float
        package let bestNonBinaryCount: Int
        /// Lineage index (0 = first seed; increments after each resignation reboot).
        package let lineageIndex: Int
        /// `true` on the generation that triggered certifiable loss / reboot.
        package let resigned: Bool

        package init(
            generation: Int,
            bestFitness: Float,
            bestCrypto: Float,
            lambda: Float,
            bestNonBinaryCount: Int = 0,
            lineageIndex: Int = 0,
            resigned: Bool = false
        ) {
            self.generation = generation
            self.bestFitness = bestFitness
            self.bestCrypto = bestCrypto
            self.lambda = lambda
            self.bestNonBinaryCount = bestNonBinaryCount
            self.lineageIndex = lineageIndex
            self.resigned = resigned
        }
    }

    private let device: MTLDevice
    private let pipeline: TensorLUTPipeline
    private let synthesizer: AdversarialSynthesizer
    private let netlist: TensorLUTNetlist

    package init(
        device: MTLDevice,
        pipeline: TensorLUTPipeline,
        synthesizer: AdversarialSynthesizer,
        netlist: TensorLUTNetlist
    ) {
        self.device = device
        self.pipeline = pipeline
        self.synthesizer = synthesizer
        self.netlist = netlist
    }

    /// Runs the continuous–discrete evolutionary loop; returns the best chromosome.
    @discardableResult
    package func run(
        target: AdversarialTarget,
        config: Config = Config(),
        progress: ((GenerationStats) -> Void)? = nil
    ) -> TensorChromosome {
        let populationSize = max(config.populationSize, 1)
        let generations = max(config.generations, 1)
        let eliteCount = min(max(config.eliteCount, 1), populationSize)
        let batchSize = target.batchSize
        let totalWires = netlist.totalWires
        let initFloatsCount = netlist.luts.count * 64
        precondition(initFloatsCount > 0, "TensorLUT netlist has no LUTs")

        guard
            let initsBuffer = device.makeBuffer(
                length: initFloatsCount * MemoryLayout<Float>.stride,
                options: .storageModeShared
            ),
            let wireBuffer = device.makeBuffer(
                length: batchSize * totalWires * MemoryLayout<Float>.stride,
                options: .storageModeShared
            )
        else {
            fatalError("Failed to allocate adversarial GPU buffers")
        }

        let seedInits = config.seedInits ?? netlist.packedINITBuffer()
        precondition(seedInits.count == initFloatsCount, "seedInits count must be num_luts×64")
        let freezeMask = config.freezeMask ?? Array(repeating: false, count: netlist.luts.count)
        precondition(freezeMask.count == netlist.luts.count, "freezeMask length must equal lutCount")

        var rng = SplitMix64(seed: config.rngSeed ?? UInt64.random(in: 1...UInt64.max))

        var population: [TensorChromosome] = (0..<populationSize).map { _ in
            TensorChromosome(inits: seedInits, freezeMask: freezeMask)
        }
        if config.seedScatter {
            // Cold-start (custom seedInits): scatter everyone. Warm start: keep one pristine elite.
            let scatterFrom = config.seedInits == nil ? 1 : 0
            for i in scatterFrom..<population.count {
                synthesizer.mutate(
                    chromosome: &population[i],
                    currentGen: 0,
                    totalGens: generations,
                    rng: &rng
                )
            }
        }

        for gen in 0..<generations {
            for i in 0..<populationSize {
                var chromo = population[i]
                uploadInits(chromo.inits, to: initsBuffer)
                injectWires(target: target, wireBuffer: wireBuffer)

                if target.clockTicks <= 0 {
                    pipeline.evaluateForward(
                        totalWires: totalWires,
                        initsBuffer: initsBuffer,
                        wireBuffer: wireBuffer,
                        batchSize: batchSize
                    )
                } else {
                    for _ in 0..<target.clockTicks {
                        pipeline.evaluateTick(
                            totalWires: totalWires,
                            initsBuffer: initsBuffer,
                            wireBuffer: wireBuffer,
                            batchSize: batchSize
                        )
                    }
                }

                let crypto = sampleCryptoFitness(target: target, wireBuffer: wireBuffer)
                synthesizer.computeTotalFitness(
                    chromosome: &chromo,
                    cryptoFitness: crypto,
                    currentGen: gen,
                    totalGens: generations,
                    initsBuffer: initsBuffer
                )
                population[i] = chromo
            }

            population.sort { $0.fitness > $1.fitness }
            let elites = Array(population.prefix(eliteCount))
            let bestCrypto = sampleBestCrypto(
                chromosome: elites[0],
                target: target,
                initsBuffer: initsBuffer,
                wireBuffer: wireBuffer
            )

            progress?(
                GenerationStats(
                    generation: gen,
                    bestFitness: elites[0].fitness,
                    bestCrypto: bestCrypto,
                    lambda: synthesizer.lambda(currentGen: gen, totalGens: generations),
                    bestNonBinaryCount: Self.nonBinaryCount(
                        elites[0].inits,
                        freezeMask: elites[0].freezeMask
                    )
                )
            )

            var next = elites
            let parentPool = max(populationSize / 2, 1)
            while next.count < populationSize {
                let parentA = population[Int.random(in: 0..<parentPool, using: &rng)]
                var child: TensorChromosome
                if config.crossoverRate > 0,
                   Float.random(in: 0..<1, using: &rng) < config.crossoverRate {
                    let parentB = population[Int.random(in: 0..<parentPool, using: &rng)]
                    child = synthesizer.crossover(parentA, parentB, rng: &rng)
                } else {
                    child = parentA
                }
                synthesizer.mutate(
                    chromosome: &child,
                    currentGen: gen,
                    totalGens: generations,
                    rng: &rng
                )
                next.append(child)
            }
            population = next
        }

        population.sort { $0.fitness > $1.fitness }
        var elite = population[0]
        if config.polishBinaryAtEnd {
            elite = polishEliteIfSafe(
                elite,
                target: target,
                initsBuffer: initsBuffer,
                wireBuffer: wireBuffer
            )
        }
        return elite
    }

    /// Evolutionary loop over a temporally unrolled stream (inject → combo → score → DFF).
    /// Supports early lineage resignation when non-binary count stays above threshold at λ midpoint.
    @discardableResult
    package func runStream(
        target: AdversarialStreamTarget,
        config: Config = Config(),
        progress: ((GenerationStats) -> Void)? = nil
    ) -> TensorChromosome {
        let populationSize = max(config.populationSize, 1)
        let generations = max(config.generations, 1)
        let eliteCount = min(max(config.eliteCount, 1), populationSize)
        let batchSize = target.batchSize
        let totalWires = netlist.totalWires
        let initFloatsCount = netlist.luts.count * 64
        precondition(initFloatsCount > 0, "TensorLUT netlist has no LUTs")
        precondition(!netlist.dffs.isEmpty || target.stepCount == 1, "multi-step stream needs DFFs")

        guard
            let initsBuffer = device.makeBuffer(
                length: initFloatsCount * MemoryLayout<Float>.stride,
                options: .storageModeShared
            ),
            let wireBuffer = device.makeBuffer(
                length: batchSize * totalWires * MemoryLayout<Float>.stride,
                options: .storageModeShared
            )
        else {
            fatalError("Failed to allocate streaming adversarial buffers")
        }

        let seedInits = config.seedInits ?? netlist.packedINITBuffer()
        precondition(seedInits.count == initFloatsCount, "seedInits count must be num_luts×64")
        let freezeMask = config.freezeMask ?? Array(repeating: false, count: netlist.luts.count)
        precondition(freezeMask.count == netlist.luts.count, "freezeMask length must equal lutCount")

        let lambdaMax = synthesizer.config.lambdaMax
        let resignArmed = config.resignNonBinaryAbove != nil && lambdaMax > 0
        let resignLambdaGate = lambdaMax * config.resignLambdaFraction

        var lineageIndex = 0
        var bestEver: TensorChromosome?
        let baseSeed = config.rngSeed ?? UInt64.random(in: 1...UInt64.max)

        while true {
            var rng = SplitMix64(seed: baseSeed &+ UInt64(lineageIndex) &* 0x9E37_79B9)
            // Fresh lineage: re-wipe melt floats to 0.5 so doomed fractional shortcuts
            // cannot poison the next seed (frozen LUTs stay binary).
            var lineageSeed = seedInits
            if lineageIndex > 0 {
                var chromo = TensorChromosome(inits: lineageSeed, freezeMask: freezeMask)
                chromo.wipeMeltRegion(to: 0.5)
                lineageSeed = chromo.inits
            }
            var population = bootstrapPopulation(
                seedInits: lineageSeed,
                freezeMask: freezeMask,
                populationSize: populationSize,
                generations: generations,
                seedScatter: config.seedScatter,
                customSeedInits: config.seedInits != nil,
                rng: &rng
            )
            var checkedResignGate = false
            var rebootLineage = false

            genLoop: for gen in 0..<generations {
                for i in 0..<populationSize {
                    var chromo = population[i]
                    uploadInits(chromo.inits, to: initsBuffer)
                    let crypto = evaluateStreamCrypto(
                        target: target,
                        initsBuffer: initsBuffer,
                        wireBuffer: wireBuffer
                    )
                    synthesizer.computeTotalFitness(
                        chromosome: &chromo,
                        cryptoFitness: crypto,
                        currentGen: gen,
                        totalGens: generations,
                        initsBuffer: initsBuffer
                    )
                    population[i] = chromo
                }

                population.sort { $0.fitness > $1.fitness }
                let elites = Array(population.prefix(eliteCount))
                let bestCrypto = evaluateStreamCrypto(
                    chromosome: elites[0],
                    target: target,
                    initsBuffer: initsBuffer,
                    wireBuffer: wireBuffer
                )
                let lam = synthesizer.lambda(currentGen: gen, totalGens: generations)
                let nonBinary = Self.nonBinaryCount(
                    elites[0].inits,
                    freezeMask: elites[0].freezeMask
                )

                var resigned = false
                if resignArmed,
                   !checkedResignGate,
                   lam + 1e-6 >= resignLambdaGate {
                    checkedResignGate = true
                    if let thresh = config.resignNonBinaryAbove, nonBinary > thresh {
                        resigned = true
                    }
                }

                progress?(
                    GenerationStats(
                        generation: gen,
                        bestFitness: elites[0].fitness,
                        bestCrypto: bestCrypto,
                        lambda: lam,
                        bestNonBinaryCount: nonBinary,
                        lineageIndex: lineageIndex,
                        resigned: resigned
                    )
                )

                if resigned {
                    if bestEver == nil || elites[0].fitness > bestEver!.fitness {
                        bestEver = elites[0]
                    }
                    if lineageIndex < config.maxLineageRestarts {
                        lineageIndex += 1
                        rebootLineage = true
                        break genLoop
                    }
                    // Out of restarts: return best effort.
                    var elite = elites[0]
                    if config.polishBinaryAtEnd {
                        elite = polishStreamEliteIfSafe(
                            elite,
                            target: target,
                            initsBuffer: initsBuffer,
                            wireBuffer: wireBuffer
                        )
                    }
                    if let prior = bestEver, prior.fitness > elite.fitness {
                        return prior
                    }
                    return elite
                }

                var next = elites
                let parentPool = max(populationSize / 2, 1)
                while next.count < populationSize {
                    let parentA = population[Int.random(in: 0..<parentPool, using: &rng)]
                    var child: TensorChromosome
                    if config.crossoverRate > 0,
                       Float.random(in: 0..<1, using: &rng) < config.crossoverRate {
                        let parentB = population[Int.random(in: 0..<parentPool, using: &rng)]
                        child = synthesizer.crossover(parentA, parentB, rng: &rng)
                    } else {
                        child = parentA
                    }
                    synthesizer.mutate(
                        chromosome: &child,
                        currentGen: gen,
                        totalGens: generations,
                        rng: &rng
                    )
                    next.append(child)
                }
                population = next
            }

            if rebootLineage {
                continue
            }

            population.sort { $0.fitness > $1.fitness }
            var elite = population[0]
            if config.polishBinaryAtEnd {
                elite = polishStreamEliteIfSafe(
                    elite,
                    target: target,
                    initsBuffer: initsBuffer,
                    wireBuffer: wireBuffer
                )
            }
            if let prior = bestEver, prior.fitness > elite.fitness {
                return prior
            }
            return elite
        }
    }

    private func bootstrapPopulation(
        seedInits: [Float],
        freezeMask: [Bool],
        populationSize: Int,
        generations: Int,
        seedScatter: Bool,
        customSeedInits: Bool,
        rng: inout SplitMix64
    ) -> [TensorChromosome] {
        var population: [TensorChromosome] = (0..<populationSize).map { _ in
            TensorChromosome(inits: seedInits, freezeMask: freezeMask)
        }
        if seedScatter {
            let scatterFrom = customSeedInits ? 0 : 1
            for i in scatterFrom..<population.count {
                synthesizer.mutate(
                    chromosome: &population[i],
                    currentGen: 0,
                    totalGens: generations,
                    rng: &rng
                )
            }
        }
        return population
    }

    private func polishStreamEliteIfSafe(
        _ elite: TensorChromosome,
        target: AdversarialStreamTarget,
        initsBuffer: MTLBuffer,
        wireBuffer: MTLBuffer
    ) -> TensorChromosome {
        let softCrypto = evaluateStreamCrypto(
            chromosome: elite,
            target: target,
            initsBuffer: initsBuffer,
            wireBuffer: wireBuffer
        )
        var polished = elite
        for lut in 0..<elite.lutCount {
            if elite.freezeMask[lut] { continue }
            let base = lut * 64
            for j in 0..<64 {
                polished.inits[base + j] = elite.inits[base + j] >= 0.5 ? 1 : 0
            }
        }
        let hardCrypto = evaluateStreamCrypto(
            chromosome: polished,
            target: target,
            initsBuffer: initsBuffer,
            wireBuffer: wireBuffer
        )
        if hardCrypto + 1e-3 >= softCrypto {
            polished.fitness = synthesizer.combineFitness(
                cryptoFitness: hardCrypto,
                sumPenalty: 0,
                currentGen: 1,
                totalGens: 1
            )
            return polished
        }
        return elite
    }

    /// Snap INIT floats to `{0,1}` when the discrete chromosome keeps crypto within tolerance.
    private func polishEliteIfSafe(
        _ elite: TensorChromosome,
        target: AdversarialTarget,
        initsBuffer: MTLBuffer,
        wireBuffer: MTLBuffer
    ) -> TensorChromosome {
        let softCrypto = sampleBestCrypto(
            chromosome: elite,
            target: target,
            initsBuffer: initsBuffer,
            wireBuffer: wireBuffer
        )
        var polished = elite
        for lut in 0..<elite.lutCount {
            if elite.freezeMask[lut] { continue }
            let base = lut * 64
            for j in 0..<64 {
                polished.inits[base + j] = elite.inits[base + j] >= 0.5 ? 1 : 0
            }
        }
        let hardCrypto = sampleBestCrypto(
            chromosome: polished,
            target: target,
            initsBuffer: initsBuffer,
            wireBuffer: wireBuffer
        )
        // Accept polish when discrete logic is at least as good (MSE not worse by > 1e-3).
        if hardCrypto + 1e-3 >= softCrypto {
            polished.fitness = synthesizer.combineFitness(
                cryptoFitness: hardCrypto,
                sumPenalty: 0,
                currentGen: 1,
                totalGens: 1
            )
            return polished
        }
        return elite
    }

    // MARK: - Stecker involution (reciprocity by construction)

    package struct SteckerSearchConfig: Sendable {
        package var populationSize: Int
        package var generations: Int
        package var eliteCount: Int
        package var maxPairs: Int
        package var crossoverRate: Float
        package var rngSeed: UInt64?
        /// Optional known-good stecker injected as population[0] (control).
        package var seedStecker: SteckerInvolution?
        /// Fraction of each generation replaced by fresh random immigrants (diversity).
        package var immigrantFraction: Float
        /// Prefer fewer pairs when \(F_{crypto}\) ties (kills unconstrained extras).
        package var parsimony: Bool
        /// Grow pair budget 1…`maxPairs` when fitness plateaus (sequential discovery).
        package var growPairs: Bool
        /// Generations without crypto improvement before raising the pair budget.
        package var growPlateauGens: Int
        /// When growing, keep the elite's pairs frozen and only search additive plugs.
        package var freezeElitePairs: Bool

        package init(
            populationSize: Int = 32,
            generations: Int = 64,
            eliteCount: Int = 4,
            maxPairs: Int = 10,
            crossoverRate: Float = 0.5,
            rngSeed: UInt64? = nil,
            seedStecker: SteckerInvolution? = nil,
            immigrantFraction: Float = 0.15,
            parsimony: Bool = true,
            growPairs: Bool = false,
            growPlateauGens: Int = 4,
            freezeElitePairs: Bool = true
        ) {
            self.populationSize = populationSize
            self.generations = generations
            self.eliteCount = eliteCount
            self.maxPairs = maxPairs
            self.crossoverRate = min(1, max(0, crossoverRate))
            self.rngSeed = rngSeed
            self.seedStecker = seedStecker
            self.immigrantFraction = min(1, max(0, immigrantFraction))
            self.parsimony = parsimony
            self.growPairs = growPairs
            self.growPlateauGens = max(1, growPlateauGens)
            self.freezeElitePairs = freezeElitePairs
        }
    }

    package struct SteckerGenerationStats: Sendable {
        package let generation: Int
        package let bestFitness: Float
        package let bestPairs: String
        package let bestPairCount: Int
        package let pairBudget: Int
    }

    /// Evolve a reciprocal stecker around a *frozen* identity-stecker TensorLUT core.
    ///
    /// For each step: inject `S(CT)` bit pattern; score soft PT bits against `S(PT)`.
    /// LUT INITs never mutate — reciprocity cannot shatter under λ.
    @discardableResult
    package func runSteckerInvolution(
        ciphertext: String,
        plaintext: String,
        left: Int,
        middle: Int,
        right: Int,
        config: SteckerSearchConfig = SteckerSearchConfig(),
        progress: ((SteckerGenerationStats) -> Void)? = nil
    ) -> SteckerInvolution {
        let ctLetters = EnigmaAlphabet.normalize(ciphertext)
        let ptLetters = EnigmaAlphabet.normalize(plaintext)
        precondition(ctLetters.count == ptLetters.count && !ctLetters.isEmpty)
        precondition((0...25).contains(left) && (0...25).contains(middle) && (0...25).contains(right))

        let populationSize = max(config.populationSize, 1)
        let generations = max(config.generations, 1)
        let eliteCount = min(max(config.eliteCount, 1), populationSize)
        let batchSize = 1
        let totalWires = netlist.totalWires
        let initFloatsCount = netlist.luts.count * 64
        let immigrantCount = min(
            populationSize - eliteCount,
            Int((config.immigrantFraction * Float(populationSize)).rounded())
        )

        // Frozen baseline INITs (identity plugboard in silicon).
        let frozenInits = netlist.packedINITBuffer()
        let initialDFFs = EnigmaStreamBuilder.buildTarget(
            ciphertext: EnigmaAlphabet.string(from: ctLetters),
            plaintext: EnigmaAlphabet.string(from: ptLetters),
            left: left,
            middle: middle,
            right: right
        ).initialDFFStates

        guard
            let initsBuffer = device.makeBuffer(
                bytes: frozenInits,
                length: initFloatsCount * MemoryLayout<Float>.stride,
                options: .storageModeShared
            ),
            let wireBuffer = device.makeBuffer(
                length: batchSize * totalWires * MemoryLayout<Float>.stride,
                options: .storageModeShared
            )
        else {
            fatalError("Failed to allocate stecker-involution buffers")
        }

        var rng = SplitMix64(seed: config.rngSeed ?? UInt64.random(in: 1...UInt64.max))
        var pairBudget = config.growPairs ? 1 : config.maxPairs
        var plateau = 0
        var bestCryptoSeen: Float = -.greatestFiniteMagnitude
        var frozenPairs: [(Int, Int)] = []
        var population: [SteckerInvolution] = (0..<populationSize).map { _ in
            SteckerInvolution.random(maxPairs: pairBudget, rng: &rng)
        }
        if let seed = config.seedStecker {
            population[0] = seed
        }

        for gen in 0..<generations {
            for i in 0..<populationSize {
                var chromo = population[i]
                chromo.fitness = evaluateSteckerSandwichCrypto(
                    stecker: chromo,
                    ctLetters: ctLetters,
                    ptLetters: ptLetters,
                    initialDFFs: initialDFFs,
                    initsBuffer: initsBuffer,
                    wireBuffer: wireBuffer
                )
                population[i] = chromo
            }

            population.sort { lhs, rhs in
                if abs(lhs.fitness - rhs.fitness) > 1e-5 {
                    return lhs.fitness > rhs.fitness
                }
                if config.parsimony {
                    return lhs.pairCount < rhs.pairCount
                }
                return false
            }
            let elites = Array(population.prefix(eliteCount))
            progress?(
                SteckerGenerationStats(
                    generation: gen,
                    bestFitness: elites[0].fitness,
                    bestPairs: elites[0].descriptionPairs(),
                    bestPairCount: elites[0].pairCount,
                    pairBudget: pairBudget
                )
            )

            if elites[0].fitness >= -1e-4 {
                let perfect = population.filter { $0.fitness >= -1e-4 }
                if config.parsimony {
                    return perfect.min(by: { $0.pairCount < $1.pairCount }) ?? elites[0]
                }
                return elites[0]
            }

            if elites[0].fitness > bestCryptoSeen + 1e-4 {
                bestCryptoSeen = elites[0].fitness
                plateau = 0
            } else {
                plateau += 1
            }
            if config.growPairs,
               plateau >= config.growPlateauGens,
               pairBudget < config.maxPairs {
                pairBudget += 1
                plateau = 0
                if config.freezeElitePairs {
                    frozenPairs = elites[0].pairs
                }
            } else if config.freezeElitePairs,
                      plateau >= config.growPlateauGens * 2,
                      pairBudget >= config.maxPairs,
                      !frozenPairs.isEmpty {
                // Deep plateau at full budget: thaw frozen plugs and reshuffle.
                frozenPairs = []
                plateau = 0
            }

            var next = elites
            let parentPool = max(populationSize / 2, 1)
            let bredTarget = populationSize - immigrantCount
            while next.count < bredTarget {
                let parentA = population[Int.random(in: 0..<parentPool, using: &rng)]
                var child: SteckerInvolution
                if config.crossoverRate > 0,
                   Float.random(in: 0..<1, using: &rng) < config.crossoverRate {
                    let parentB = population[Int.random(in: 0..<parentPool, using: &rng)]
                    child = SteckerInvolution.crossover(
                        parentA,
                        parentB,
                        maxPairs: pairBudget,
                        rng: &rng
                    )
                } else {
                    child = parentA
                }
                // Soft freeze: 75% preserve elite plugs; 25% free mutate (escape wrong locks).
                if config.freezeElitePairs,
                   !frozenPairs.isEmpty,
                   Float.random(in: 0..<1, using: &rng) < 0.75 {
                    child = child.mutatedPreserving(
                        frozen: frozenPairs,
                        maxPairs: pairBudget,
                        rng: &rng
                    )
                } else {
                    child = child.mutated(maxPairs: pairBudget, rng: &rng)
                }
                if child.pairCount > pairBudget {
                    child = SteckerInvolution(pairs: Array(child.pairs.prefix(pairBudget)))
                }
                next.append(child)
            }
            while next.count < populationSize {
                if config.freezeElitePairs,
                   !frozenPairs.isEmpty,
                   Float.random(in: 0..<1, using: &rng) < 0.5 {
                    next.append(
                        SteckerInvolution.randomPreserving(
                            frozen: frozenPairs,
                            maxPairs: pairBudget,
                            rng: &rng
                        )
                    )
                } else {
                    next.append(SteckerInvolution.random(maxPairs: pairBudget, rng: &rng))
                }
            }
            population = next
        }

        population.sort { lhs, rhs in
            if abs(lhs.fitness - rhs.fitness) > 1e-5 {
                return lhs.fitness > rhs.fitness
            }
            if config.parsimony {
                return lhs.pairCount < rhs.pairCount
            }
            return false
        }
        return population[0]
    }

    /// Soft \(F_{crypto}\) for stecker sandwich around frozen identity core.
    private func evaluateSteckerSandwichCrypto(
        stecker: SteckerInvolution,
        ctLetters: [Int],
        ptLetters: [Int],
        initialDFFs: [Int32: Float],
        initsBuffer: MTLBuffer,
        wireBuffer: MTLBuffer
    ) -> Float {
        let batchSize = 1
        let totalWires = netlist.totalWires
        let steps = ctLetters.count
        let wirePtr = wireBuffer.contents().bindMemory(to: Float.self, capacity: batchSize * totalWires)
        let map = stecker.mapTable()

        for w in 0..<totalWires { wirePtr[w] = 0 }
        if let constOne = netlist.constOneWire {
            wirePtr[Int(constOne)] = 1
        }
        for (qWire, stateVal) in initialDFFs {
            wirePtr[Int(qWire)] = stateVal
        }

        var cryptoSum: Float = 0
        for step in 0..<steps {
            let ctMapped = map[ctLetters[step]]
            let ptMapped = map[ptLetters[step]]
            // resetn = 1, then 8 CT bits
            wirePtr[Int(EnigmaStreamBuilder.wireResetN)] = 1
            let ctBits = SteckerIOProjection.ciphertextBits(ctMapped)
            for (i, wire) in EnigmaStreamBuilder.wireCT.enumerated() {
                wirePtr[Int(wire)] = ctBits[i]
            }

            pipeline.evaluateForward(
                totalWires: totalWires,
                initsBuffer: initsBuffer,
                wireBuffer: wireBuffer,
                batchSize: batchSize
            )
            pipeline.clockTick(
                totalWires: totalWires,
                wireBuffer: wireBuffer,
                batchSize: batchSize
            )

            let expected = SteckerIOProjection.plaintextBits(ptMapped)
            var extracted = [Float]()
            extracted.reserveCapacity(5)
            for wire in EnigmaStreamBuilder.wirePT {
                extracted.append(wirePtr[Int(wire)])
            }
            cryptoSum += synthesizer.computeCryptoFitness(
                tensorOutputWires: extracted,
                targetBits: expected
            )
        }
        return cryptoSum
    }

    // MARK: - Internals

    package static func nonBinaryCount(
        _ inits: [Float],
        freezeMask: [Bool]? = nil,
        lo: Float = 0.05,
        hi: Float = 0.95
    ) -> Int {
        if let freezeMask {
            precondition(inits.count % 64 == 0)
            let lutCount = inits.count / 64
            precondition(freezeMask.count == lutCount)
            var count = 0
            for lut in 0..<lutCount where !freezeMask[lut] {
                let base = lut * 64
                for j in 0..<64 {
                    let w = inits[base + j]
                    if w > lo && w < hi { count += 1 }
                }
            }
            return count
        }
        return inits.reduce(0) { $0 + (($1 > lo && $1 < hi) ? 1 : 0) }
    }

    private func uploadInits(_ inits: [Float], to buffer: MTLBuffer) {
        inits.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            buffer.contents().copyMemory(from: base, byteCount: raw.count)
        }
    }

    private func evaluateStreamCrypto(
        chromosome: TensorChromosome,
        target: AdversarialStreamTarget,
        initsBuffer: MTLBuffer,
        wireBuffer: MTLBuffer
    ) -> Float {
        uploadInits(chromosome.inits, to: initsBuffer)
        return evaluateStreamCrypto(
            target: target,
            initsBuffer: initsBuffer,
            wireBuffer: wireBuffer
        )
    }

    /// Wipe → seed DFFs → for each step: inject → forward → clockTick → sample MSE.
    private func evaluateStreamCrypto(
        target: AdversarialStreamTarget,
        initsBuffer: MTLBuffer,
        wireBuffer: MTLBuffer
    ) -> Float {
        let batchSize = target.batchSize
        let totalWires = netlist.totalWires
        let steps = target.stepCount
        let wirePtr = wireBuffer.contents().bindMemory(to: Float.self, capacity: batchSize * totalWires)

        for b in 0..<batchSize {
            let batchOffset = b * totalWires
            for w in 0..<totalWires {
                wirePtr[batchOffset + w] = 0
            }
            if let constOne = netlist.constOneWire {
                wirePtr[batchOffset + Int(constOne)] = 1
            }
            for (qWire, stateVal) in target.initialDFFStates {
                wirePtr[batchOffset + Int(qWire)] = stateVal
            }
        }

        var cryptoSum: Float = 0
        for step in 0..<steps {
            for b in 0..<batchSize {
                let batchOffset = b * totalWires
                for (idx, wireID) in target.inputWireIDs.enumerated() {
                    wirePtr[batchOffset + Int(wireID)] = target.inputSequence[step][b][idx]
                }
            }

            pipeline.evaluateForward(
                totalWires: totalWires,
                initsBuffer: initsBuffer,
                wireBuffer: wireBuffer,
                batchSize: batchSize
            )
            // Registered outputs (e.g. Enigma plaintext_char) update on the DFF edge —
            // match CleartextNetlistSim: combo → DFF → sample.
            pipeline.clockTick(
                totalWires: totalWires,
                wireBuffer: wireBuffer,
                batchSize: batchSize
            )

            for b in 0..<batchSize {
                let batchOffset = b * totalWires
                var extracted = [Float]()
                extracted.reserveCapacity(target.outputWireIDs.count)
                for wireID in target.outputWireIDs {
                    extracted.append(wirePtr[batchOffset + Int(wireID)])
                }
                cryptoSum += synthesizer.computeCryptoFitness(
                    tensorOutputWires: extracted,
                    targetBits: target.expectedSequence[step][b]
                )
            }
        }
        return cryptoSum
    }

    private func injectWires(target: AdversarialTarget, wireBuffer: MTLBuffer) {
        let batchSize = target.batchSize
        let totalWires = netlist.totalWires
        let wirePtr = wireBuffer.contents().bindMemory(to: Float.self, capacity: batchSize * totalWires)

        for b in 0..<batchSize {
            let batchOffset = b * totalWires
            for w in 0..<totalWires {
                wirePtr[batchOffset + w] = 0
            }
            if let constOne = netlist.constOneWire {
                wirePtr[batchOffset + Int(constOne)] = 1
            }
            for (idx, wireID) in target.inputWireIDs.enumerated() {
                wirePtr[batchOffset + Int(wireID)] = target.inputVectors[b][idx]
            }
        }
    }

    private func sampleCryptoFitness(target: AdversarialTarget, wireBuffer: MTLBuffer) -> Float {
        let batchSize = target.batchSize
        let totalWires = netlist.totalWires
        let wirePtr = wireBuffer.contents().bindMemory(to: Float.self, capacity: batchSize * totalWires)
        var cryptoSum: Float = 0
        for b in 0..<batchSize {
            let batchOffset = b * totalWires
            var extracted = [Float]()
            extracted.reserveCapacity(target.outputWireIDs.count)
            for wireID in target.outputWireIDs {
                extracted.append(wirePtr[batchOffset + Int(wireID)])
            }
            cryptoSum += synthesizer.computeCryptoFitness(
                tensorOutputWires: extracted,
                targetBits: target.expectedOutputs[b]
            )
        }
        return cryptoSum
    }

    private func sampleBestCrypto(
        chromosome: TensorChromosome,
        target: AdversarialTarget,
        initsBuffer: MTLBuffer,
        wireBuffer: MTLBuffer
    ) -> Float {
        uploadInits(chromosome.inits, to: initsBuffer)
        injectWires(target: target, wireBuffer: wireBuffer)
        let batchSize = target.batchSize
        let totalWires = netlist.totalWires
        if target.clockTicks <= 0 {
            pipeline.evaluateForward(
                totalWires: totalWires,
                initsBuffer: initsBuffer,
                wireBuffer: wireBuffer,
                batchSize: batchSize
            )
        } else {
            for _ in 0..<target.clockTicks {
                pipeline.evaluateTick(
                    totalWires: totalWires,
                    initsBuffer: initsBuffer,
                    wireBuffer: wireBuffer,
                    batchSize: batchSize
                )
            }
        }
        return sampleCryptoFitness(target: target, wireBuffer: wireBuffer)
    }
}

private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0xDEAD_BEEF : seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z &>> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z &>> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z &>> 31)
    }
}
