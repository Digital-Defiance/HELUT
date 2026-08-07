import Foundation

/// Restricted structural changes that preserve the compiled fixed-DAG wiring.
///
/// `.constant0`, `.constant1`, and `.bypass` are materialized as ordinary
/// binary LUT6 INIT blocks, so the Metal ABI and execution levels do not change.
/// A downstream logic optimizer can then remove the degenerate LUTs.
package enum TensorLUTStructuralMode: Hashable, Sendable {
    case table
    case constant0
    case constant1
    case bypass(pin: Int)
}

/// One structural mode per LUT in array/index order.
package struct TensorLUTStructuralGenome: Hashable, Sendable {
    package var modes: [TensorLUTStructuralMode]

    package init(lutCount: Int) {
        precondition(lutCount >= 0)
        self.modes = Array(repeating: .table, count: lutCount)
    }

    package init(modes: [TensorLUTStructuralMode]) {
        self.modes = modes
    }

    package var changedModeCount: Int {
        modes.reduce(0) { $0 + ($1 == .table ? 0 : 1) }
    }
}

package enum TensorLUTStructuralError: Error, Equatable, Sendable {
    case sequentialNetlist(dffCount: Int)
    case chromosomeLUTCount(expected: Int, actual: Int)
    case genomeLUTCount(expected: Int, actual: Int)
    case invalidCellID(index: Int, cellID: Int)
    case invalidOutputWire(lut: Int, wire: Int32)
    case invalidInputWire(lut: Int, pin: Int, wire: Int32)
    case duplicateDriver(wire: Int32, firstLUT: Int, secondLUT: Int)
    case selfEdge(lut: Int, wire: Int32)
    case invalidLevelIndex(level: Int, index: Int32)
    case duplicateLevelEntry(lut: Int)
    case missingLevelEntry(lut: Int)
    case dependencyNotEarlier(producer: Int, consumer: Int)
    case invalidConstOneWire(Int32)
    case constOneDriven(wire: Int32, lut: Int)
    case noOutputWires
    case invalidOutputObservationWire(Int32)
    case frozenModeChange(lut: Int, mode: TensorLUTStructuralMode)
    case invalidBypassPin(lut: Int, pin: Int)
    case bypassOfPadding(lut: Int, pin: Int)
    case nonBinaryINIT(lut: Int, address: Int, value: Float)
    case baselineMismatch(count: Int)
    case negativeMismatchCount(Int)
}

/// Cheap, technology-independent implementation proxies after exact constant and
/// bypass propagation through the reachable output cone.
package struct TensorLUTStructuralMetrics: Equatable, Sendable {
    package let activeReachableLUTs: Int
    package let outputConeDepth: Int
    package let supportEdges: Int

    package init(activeReachableLUTs: Int, outputConeDepth: Int, supportEdges: Int) {
        self.activeReachableLUTs = activeReachableLUTs
        self.outputConeDepth = outputConeDepth
        self.supportEdges = supportEdges
    }
}

/// Strict correctness-first rank. A candidate with fewer mismatches always wins,
/// regardless of its structural cost. The remaining fields are considered only
/// when every earlier field ties.
package struct TensorLUTStructuralScore: Comparable, Sendable {
    package let mismatchCount: Int
    package let activeReachableLUTs: Int
    package let outputConeDepth: Int
    package let supportEdges: Int
    package let changedModeCount: Int

    package init(
        mismatchCount: Int,
        activeReachableLUTs: Int,
        outputConeDepth: Int,
        supportEdges: Int,
        changedModeCount: Int
    ) {
        precondition(mismatchCount >= 0)
        precondition(activeReachableLUTs >= 0)
        precondition(outputConeDepth >= 0)
        precondition(supportEdges >= 0)
        precondition(changedModeCount >= 0)
        self.mismatchCount = mismatchCount
        self.activeReachableLUTs = activeReachableLUTs
        self.outputConeDepth = outputConeDepth
        self.supportEdges = supportEdges
        self.changedModeCount = changedModeCount
    }

    package static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.mismatchCount != rhs.mismatchCount {
            return lhs.mismatchCount < rhs.mismatchCount
        }
        if lhs.activeReachableLUTs != rhs.activeReachableLUTs {
            return lhs.activeReachableLUTs < rhs.activeReachableLUTs
        }
        if lhs.outputConeDepth != rhs.outputConeDepth {
            return lhs.outputConeDepth < rhs.outputConeDepth
        }
        if lhs.supportEdges != rhs.supportEdges {
            return lhs.supportEdges < rhs.supportEdges
        }
        return lhs.changedModeCount < rhs.changedModeCount
    }
}

package struct TensorLUTStructuralCandidate: Sendable {
    package let genome: TensorLUTStructuralGenome
    package let chromosome: TensorChromosome
    package let metrics: TensorLUTStructuralMetrics
    package let score: TensorLUTStructuralScore
}

package struct TensorLUTStructuralEvolutionResult: Sendable {
    package let baseline: TensorLUTStructuralCandidate
    package let best: TensorLUTStructuralCandidate
    package let generationsCompleted: Int
    package let uniqueCandidatesEvaluated: Int
}

package struct TensorLUTStructuralEvolutionConfig: Sendable {
    package var populationSize: Int
    package var generations: Int
    package var eliteCount: Int
    package var tournamentSize: Int
    package var mutationRate: Double
    package var crossoverRate: Double
    package var seed: UInt64

    package init(
        populationSize: Int = 64,
        generations: Int = 40,
        eliteCount: Int = 8,
        tournamentSize: Int = 3,
        mutationRate: Double = 0.15,
        crossoverRate: Double = 0.8,
        seed: UInt64 = 0x4845_4C55_5453_5452
    ) {
        precondition(populationSize >= 2)
        precondition(generations >= 0)
        precondition((1..<populationSize).contains(eliteCount))
        precondition(tournamentSize >= 1)
        precondition((0...1).contains(mutationRate))
        precondition((0...1).contains(crossoverRate))
        self.populationSize = populationSize
        self.generations = generations
        self.eliteCount = eliteCount
        self.tournamentSize = tournamentSize
        self.mutationRate = mutationRate
        self.crossoverRate = crossoverRate
        self.seed = seed
    }
}

/// Validation for the deliberately narrow structural search domain. This is
/// stricter than the historical compiler path: indices must be dense, every LUT
/// must appear exactly once in the supplied levels, drivers must be unique, and
/// all dependencies must point to an earlier level.
package enum TensorLUTStructuralValidation {
    package static func validate(
        netlist: TensorLUTNetlist,
        chromosome: TensorChromosome,
        outputWires: [Int32]
    ) throws {
        guard netlist.dffs.isEmpty else {
            throw TensorLUTStructuralError.sequentialNetlist(dffCount: netlist.dffs.count)
        }
        guard chromosome.lutCount == netlist.luts.count else {
            throw TensorLUTStructuralError.chromosomeLUTCount(
                expected: netlist.luts.count,
                actual: chromosome.lutCount
            )
        }
        guard !outputWires.isEmpty else {
            throw TensorLUTStructuralError.noOutputWires
        }
        for wire in outputWires where wire < 0 || Int(wire) >= netlist.totalWires {
            throw TensorLUTStructuralError.invalidOutputObservationWire(wire)
        }

        if let constOne = netlist.constOneWire,
           constOne < 0 || Int(constOne) >= netlist.totalWires {
            throw TensorLUTStructuralError.invalidConstOneWire(constOne)
        }

        var producerByWire: [Int32: Int] = [:]
        for (index, lut) in netlist.luts.enumerated() {
            guard lut.cellID == index else {
                throw TensorLUTStructuralError.invalidCellID(index: index, cellID: lut.cellID)
            }
            guard lut.outWire >= 0, Int(lut.outWire) < netlist.totalWires else {
                throw TensorLUTStructuralError.invalidOutputWire(lut: index, wire: lut.outWire)
            }
            if lut.outWire == netlist.constOneWire {
                throw TensorLUTStructuralError.constOneDriven(wire: lut.outWire, lut: index)
            }
            if let first = producerByWire.updateValue(index, forKey: lut.outWire) {
                throw TensorLUTStructuralError.duplicateDriver(
                    wire: lut.outWire,
                    firstLUT: first,
                    secondLUT: index
                )
            }
            for (pin, wire) in inputWires(of: lut).enumerated() {
                guard wire == -1 || (wire >= 0 && Int(wire) < netlist.totalWires) else {
                    throw TensorLUTStructuralError.invalidInputWire(lut: index, pin: pin, wire: wire)
                }
                if wire == lut.outWire {
                    throw TensorLUTStructuralError.selfEdge(lut: index, wire: wire)
                }
            }
        }

        var levelForLUT = [Int](repeating: -1, count: netlist.luts.count)
        for (level, indices) in netlist.executionLevels.enumerated() {
            for rawIndex in indices {
                guard rawIndex >= 0, Int(rawIndex) < netlist.luts.count else {
                    throw TensorLUTStructuralError.invalidLevelIndex(level: level, index: rawIndex)
                }
                let index = Int(rawIndex)
                guard levelForLUT[index] == -1 else {
                    throw TensorLUTStructuralError.duplicateLevelEntry(lut: index)
                }
                levelForLUT[index] = level
            }
        }
        for index in netlist.luts.indices where levelForLUT[index] == -1 {
            throw TensorLUTStructuralError.missingLevelEntry(lut: index)
        }

        for (consumer, lut) in netlist.luts.enumerated() {
            for wire in inputWires(of: lut) where wire >= 0 {
                guard let producer = producerByWire[wire] else { continue }
                guard levelForLUT[producer] < levelForLUT[consumer] else {
                    throw TensorLUTStructuralError.dependencyNotEarlier(
                        producer: producer,
                        consumer: consumer
                    )
                }
            }
        }
    }

    fileprivate static func inputWires(of lut: TensorLUT6Cell) -> [Int32] {
        [lut.in0, lut.in1, lut.in2, lut.in3, lut.in4, lut.in5]
    }
}

/// Materializes structural modes into the existing 64-entry LUT blocks.
package enum TensorLUTStructuralMaterializer {
    package static func materialize(
        genome: TensorLUTStructuralGenome,
        baseline: TensorChromosome,
        netlist: TensorLUTNetlist
    ) throws -> TensorChromosome {
        guard genome.modes.count == netlist.luts.count else {
            throw TensorLUTStructuralError.genomeLUTCount(
                expected: netlist.luts.count,
                actual: genome.modes.count
            )
        }
        guard baseline.lutCount == netlist.luts.count else {
            throw TensorLUTStructuralError.chromosomeLUTCount(
                expected: netlist.luts.count,
                actual: baseline.lutCount
            )
        }

        var inits = baseline.inits
        for index in netlist.luts.indices {
            let mode = genome.modes[index]
            if baseline.isFrozen(lutIndex: index), mode != .table {
                throw TensorLUTStructuralError.frozenModeChange(lut: index, mode: mode)
            }
            let base = index * 64
            switch mode {
            case .table:
                continue
            case .constant0:
                inits.replaceSubrange(base..<(base + 64), with: repeatElement(Float(0), count: 64))
            case .constant1:
                inits.replaceSubrange(base..<(base + 64), with: repeatElement(Float(1), count: 64))
            case .bypass(let pin):
                guard (0..<6).contains(pin) else {
                    throw TensorLUTStructuralError.invalidBypassPin(lut: index, pin: pin)
                }
                let wires = TensorLUTStructuralValidation.inputWires(of: netlist.luts[index])
                guard wires[pin] >= 0 else {
                    throw TensorLUTStructuralError.bypassOfPadding(lut: index, pin: pin)
                }
                for address in 0..<64 {
                    inits[base + address] = Float((address >> pin) & 1)
                }
            }
        }
        return TensorChromosome(inits: inits, freezeMask: baseline.freezeMask)
    }
}

/// Exact binary support over the states reachable after local constant and alias
/// propagation. This catches tied input pins and downstream simplifications such
/// as `AND(x, 0)` without invoking ABC for every genome.
package enum TensorLUTStructuralAnalyzer {
    private enum Source: Hashable {
        case constant(Bool)
        case wire(Int32)
    }

    private enum CellSemantics {
        case constant(Bool)
        case bypass(Source)
        case table(supportWires: [Int32])
    }

    package static func analyze(
        netlist: TensorLUTNetlist,
        chromosome: TensorChromosome,
        outputWires: [Int32]
    ) throws -> TensorLUTStructuralMetrics {
        try TensorLUTStructuralValidation.validate(
            netlist: netlist,
            chromosome: chromosome,
            outputWires: outputWires
        )

        for lut in netlist.luts.indices {
            let base = lut * 64
            for address in 0..<64 {
                let value = chromosome.inits[base + address]
                if value != 0 && value != 1 {
                    throw TensorLUTStructuralError.nonBinaryINIT(
                        lut: lut,
                        address: address,
                        value: value
                    )
                }
            }
        }

        var producerByWire: [Int32: Int] = [:]
        for (index, lut) in netlist.luts.enumerated() {
            producerByWire[lut.outWire] = index
        }

        var resolvedByWire: [Int32: Source] = [:]
        var semantics = [CellSemantics?](repeating: nil, count: netlist.luts.count)

        func resolve(_ wire: Int32) -> Source {
            if wire < 0 { return .constant(false) }
            if wire == netlist.constOneWire { return .constant(true) }
            return resolvedByWire[wire] ?? .wire(wire)
        }

        for level in netlist.executionLevels {
            for rawIndex in level {
                let index = Int(rawIndex)
                let lut = netlist.luts[index]
                let pinSources = TensorLUTStructuralValidation.inputWires(of: lut).map(resolve)
                let base = index * 64
                let entries = Array(chromosome.inits[base..<(base + 64)])
                let cell = classify(entries: entries, pinSources: pinSources)
                semantics[index] = cell
                switch cell {
                case .constant(let value):
                    resolvedByWire[lut.outWire] = .constant(value)
                case .bypass(let source):
                    resolvedByWire[lut.outWire] = source
                case .table:
                    resolvedByWire[lut.outWire] = .wire(lut.outWire)
                }
            }
        }

        var active = Set<Int>()
        func visit(_ wire: Int32) {
            switch resolve(wire) {
            case .constant:
                return
            case .wire(let resolvedWire):
                guard let index = producerByWire[resolvedWire],
                      let cell = semantics[index]
                else { return }
                switch cell {
                case .constant:
                    return
                case .bypass(let source):
                    if case .wire(let sourceWire) = source { visit(sourceWire) }
                case .table(let supportWires):
                    guard active.insert(index).inserted else { return }
                    for sourceWire in supportWires { visit(sourceWire) }
                }
            }
        }
        for output in outputWires { visit(output) }

        var depthMemo: [Int32: Int] = [:]
        func depth(of wire: Int32) -> Int {
            switch resolve(wire) {
            case .constant:
                return 0
            case .wire(let resolvedWire):
                if let cached = depthMemo[resolvedWire] { return cached }
                guard let index = producerByWire[resolvedWire],
                      let cell = semantics[index]
                else {
                    depthMemo[resolvedWire] = 0
                    return 0
                }
                let value: Int
                switch cell {
                case .constant:
                    value = 0
                case .bypass(let source):
                    if case .wire(let sourceWire) = source {
                        value = depth(of: sourceWire)
                    } else {
                        value = 0
                    }
                case .table(let supportWires):
                    value = 1 + (supportWires.map(depth).max() ?? 0)
                }
                depthMemo[resolvedWire] = value
                return value
            }
        }

        let outputDepth = outputWires.map(depth).max() ?? 0
        let supportEdges = active.reduce(0) { partial, index in
            guard case .table(let supportWires)? = semantics[index] else { return partial }
            return partial + supportWires.count
        }
        return TensorLUTStructuralMetrics(
            activeReachableLUTs: active.count,
            outputConeDepth: outputDepth,
            supportEdges: supportEdges
        )
    }

    private static func classify(entries: [Float], pinSources: [Source]) -> CellSemantics {
        precondition(entries.count == 64)
        precondition(pinSources.count == 6)

        var variables: [Int32] = []
        for source in pinSources {
            guard case .wire(let wire) = source else { continue }
            if !variables.contains(wire) { variables.append(wire) }
        }
        let variableIndex = Dictionary(uniqueKeysWithValues: variables.enumerated().map { ($0.element, $0.offset) })
        let rowCount = 1 << variables.count
        var outputs = [Bool](repeating: false, count: rowCount)

        for row in 0..<rowCount {
            var address = 0
            for (pin, source) in pinSources.enumerated() {
                let bit: Bool
                switch source {
                case .constant(let value):
                    bit = value
                case .wire(let wire):
                    bit = ((row >> variableIndex[wire]!) & 1) == 1
                }
                if bit { address |= 1 << pin }
            }
            outputs[row] = entries[address] == 1
        }

        if outputs.allSatisfy({ $0 == outputs[0] }) {
            return .constant(outputs[0])
        }

        for (variable, wire) in variables.enumerated() {
            var isProjection = true
            for row in 0..<rowCount {
                let expected = ((row >> variable) & 1) == 1
                if outputs[row] != expected {
                    isProjection = false
                    break
                }
            }
            if isProjection { return .bypass(.wire(wire)) }
        }

        var support: [Int32] = []
        for (variable, wire) in variables.enumerated() {
            var depends = false
            for row in 0..<rowCount where ((row >> variable) & 1) == 0 {
                if outputs[row] != outputs[row | (1 << variable)] {
                    depends = true
                    break
                }
            }
            if depends { support.append(wire) }
        }
        return .table(supportWires: support)
    }
}

/// Deterministic genetic search over the restricted structural mode vector.
/// The all-table, proven-correct baseline remains in every generation.
package enum TensorLUTStructuralEvolution {
    package static func mutate(
        genome: TensorLUTStructuralGenome,
        netlist: TensorLUTNetlist,
        freezeMask: [Bool],
        rate: Double,
        forceAtLeastOne: Bool = false,
        rng: inout some RandomNumberGenerator
    ) -> TensorLUTStructuralGenome {
        precondition(genome.modes.count == netlist.luts.count)
        precondition(freezeMask.count == netlist.luts.count)
        precondition((0...1).contains(rate))

        var child = genome
        var changed = false
        for index in netlist.luts.indices {
            if freezeMask[index] {
                child.modes[index] = .table
                continue
            }
            if Double.random(in: 0..<1, using: &rng) < rate {
                let options = modeOptions(for: netlist.luts[index]).filter { $0 != child.modes[index] }
                if let chosen = options.randomElement(using: &rng) {
                    child.modes[index] = chosen
                    changed = true
                }
            }
        }

        if forceAtLeastOne, !changed {
            let mutable = netlist.luts.indices.filter { !freezeMask[$0] }
            if let index = mutable.randomElement(using: &rng) {
                let options = modeOptions(for: netlist.luts[index]).filter { $0 != child.modes[index] }
                if let chosen = options.randomElement(using: &rng) {
                    child.modes[index] = chosen
                }
            }
        }
        return child
    }

    package static func crossover(
        _ lhs: TensorLUTStructuralGenome,
        _ rhs: TensorLUTStructuralGenome,
        freezeMask: [Bool],
        rng: inout some RandomNumberGenerator
    ) -> TensorLUTStructuralGenome {
        precondition(lhs.modes.count == rhs.modes.count)
        precondition(lhs.modes.count == freezeMask.count)
        var modes = lhs.modes
        for index in modes.indices {
            if freezeMask[index] {
                modes[index] = .table
            } else if Bool.random(using: &rng) {
                modes[index] = rhs.modes[index]
            }
        }
        return TensorLUTStructuralGenome(modes: modes)
    }

    package static func evolve(
        netlist: TensorLUTNetlist,
        baseline: TensorChromosome,
        outputWires: [Int32],
        config: TensorLUTStructuralEvolutionConfig = .init(),
        mismatchCount: (TensorChromosome) throws -> Int
    ) throws -> TensorLUTStructuralEvolutionResult {
        try TensorLUTStructuralValidation.validate(
            netlist: netlist,
            chromosome: baseline,
            outputWires: outputWires
        )

        let baselineGenome = TensorLUTStructuralGenome(lutCount: netlist.luts.count)
        var cache: [TensorLUTStructuralGenome: TensorLUTStructuralCandidate] = [:]

        func evaluate(_ genome: TensorLUTStructuralGenome) throws -> TensorLUTStructuralCandidate {
            if let cached = cache[genome] { return cached }
            let chromosome = try TensorLUTStructuralMaterializer.materialize(
                genome: genome,
                baseline: baseline,
                netlist: netlist
            )
            let mismatches = try mismatchCount(chromosome)
            guard mismatches >= 0 else {
                throw TensorLUTStructuralError.negativeMismatchCount(mismatches)
            }
            let metrics = try TensorLUTStructuralAnalyzer.analyze(
                netlist: netlist,
                chromosome: chromosome,
                outputWires: outputWires
            )
            let score = TensorLUTStructuralScore(
                mismatchCount: mismatches,
                activeReachableLUTs: metrics.activeReachableLUTs,
                outputConeDepth: metrics.outputConeDepth,
                supportEdges: metrics.supportEdges,
                changedModeCount: genome.changedModeCount
            )
            let candidate = TensorLUTStructuralCandidate(
                genome: genome,
                chromosome: chromosome,
                metrics: metrics,
                score: score
            )
            cache[genome] = candidate
            return candidate
        }

        let baselineCandidate = try evaluate(baselineGenome)
        guard baselineCandidate.score.mismatchCount == 0 else {
            throw TensorLUTStructuralError.baselineMismatch(count: baselineCandidate.score.mismatchCount)
        }

        var rng = StructuralSplitMix64(seed: config.seed)
        var seedGenomes = [baselineGenome]
        // With a bounded population, mutations nearest the observed outputs are
        // the most likely to prune an entire upstream cone. Reverse topological
        // order also avoids an arbitrary preference for low cell IDs.
        let seedOrder = netlist.executionLevels.reversed().flatMap { $0.reversed() }.map(Int.init)
        for index in seedOrder where !baseline.freezeMask[index] {
            for mode in modeOptions(for: netlist.luts[index]) where mode != .table {
                var genome = baselineGenome
                genome.modes[index] = mode
                seedGenomes.append(genome)
            }
        }
        while seedGenomes.count < config.populationSize {
            seedGenomes.append(mutate(
                genome: baselineGenome,
                netlist: netlist,
                freezeMask: baseline.freezeMask,
                rate: config.mutationRate,
                forceAtLeastOne: true,
                rng: &rng
            ))
        }
        var population = try seedGenomes.prefix(config.populationSize).map(evaluate)
        var best = population.min(by: candidateLess) ?? baselineCandidate

        for _ in 0..<config.generations {
            population.sort(by: candidateLess)
            if let generationBest = population.first, candidateLess(generationBest, best) {
                best = generationBest
            }

            var nextGenomes: [TensorLUTStructuralGenome] = [baselineGenome]
            for candidate in population where candidate.genome != baselineGenome {
                if nextGenomes.count >= config.eliteCount + 1 { break }
                nextGenomes.append(candidate.genome)
            }

            while nextGenomes.count < config.populationSize {
                let parentA = tournament(population, size: config.tournamentSize, rng: &rng)
                var child = parentA.genome
                if Double.random(in: 0..<1, using: &rng) < config.crossoverRate {
                    let parentB = tournament(population, size: config.tournamentSize, rng: &rng)
                    child = crossover(
                        parentA.genome,
                        parentB.genome,
                        freezeMask: baseline.freezeMask,
                        rng: &rng
                    )
                }
                child = mutate(
                    genome: child,
                    netlist: netlist,
                    freezeMask: baseline.freezeMask,
                    rate: config.mutationRate,
                    forceAtLeastOne: false,
                    rng: &rng
                )
                nextGenomes.append(child)
            }
            population = try nextGenomes.map(evaluate)
        }

        if let finalBest = population.min(by: candidateLess), candidateLess(finalBest, best) {
            best = finalBest
        }
        // The retained all-table elite makes this a hard invariant rather than a
        // probabilistic expectation.
        precondition(best.score.mismatchCount == 0)

        return TensorLUTStructuralEvolutionResult(
            baseline: baselineCandidate,
            best: best,
            generationsCompleted: config.generations,
            uniqueCandidatesEvaluated: cache.count
        )
    }

    private static func modeOptions(for lut: TensorLUT6Cell) -> [TensorLUTStructuralMode] {
        var modes: [TensorLUTStructuralMode] = [.table, .constant0, .constant1]
        for (pin, wire) in TensorLUTStructuralValidation.inputWires(of: lut).enumerated() where wire >= 0 {
            modes.append(.bypass(pin: pin))
        }
        return modes
    }

    private static func tournament(
        _ population: [TensorLUTStructuralCandidate],
        size: Int,
        rng: inout some RandomNumberGenerator
    ) -> TensorLUTStructuralCandidate {
        precondition(!population.isEmpty)
        var best = population[Int.random(in: population.indices, using: &rng)]
        for _ in 1..<size {
            let contender = population[Int.random(in: population.indices, using: &rng)]
            if candidateLess(contender, best) { best = contender }
        }
        return best
    }

    private static func candidateLess(
        _ lhs: TensorLUTStructuralCandidate,
        _ rhs: TensorLUTStructuralCandidate
    ) -> Bool {
        if lhs.score != rhs.score { return lhs.score < rhs.score }
        let lhsCodes = lhs.genome.modes.map(modeCode)
        let rhsCodes = rhs.genome.modes.map(modeCode)
        return lhsCodes.lexicographicallyPrecedes(rhsCodes)
    }

    private static func modeCode(_ mode: TensorLUTStructuralMode) -> Int {
        switch mode {
        case .table: return 0
        case .constant0: return 1
        case .constant1: return 2
        case .bypass(let pin): return 3 + pin
        }
    }
}

private struct StructuralSplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x4845_4C55_54 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
