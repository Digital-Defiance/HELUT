import Foundation
import Metal

/// Flattened TensorLUT INIT genome (`num_luts * 64` floats in `[0, 1]`).
package struct TensorChromosome: Sendable {
    package var inits: [Float]
    package var fitness: Float
    /// Per-LUT freeze flags (`true` = no mutation / no binary penalty). Length = `lutCount`.
    package var freezeMask: [Bool]

    package var lutCount: Int { inits.count / 64 }

    package var meltLUTCount: Int {
        freezeMask.reduce(0) { $0 + ($1 ? 0 : 1) }
    }

    package init(
        inits: [Float],
        fitness: Float = -Float.greatestFiniteMagnitude,
        freezeMask: [Bool]? = nil
    ) {
        precondition(inits.count % 64 == 0, "INIT genome must be num_luts×64")
        let lutCount = inits.count / 64
        self.inits = inits
        self.fitness = fitness
        if let freezeMask {
            precondition(freezeMask.count == lutCount, "freezeMask length must equal lutCount")
            self.freezeMask = freezeMask
        } else {
            self.freezeMask = Array(repeating: false, count: lutCount)
        }
    }

    package static func from(netlist: TensorLUTNetlist) -> TensorChromosome {
        TensorChromosome(inits: netlist.packedINITBuffer())
    }

    /// Freeze every LUT except `meltIndices` (targeted melt).
    package mutating func freezeAllExcept(meltIndices: Set<Int>) {
        let n = lutCount
        freezeMask = (0..<n).map { !meltIndices.contains($0) }
    }

    /// Freeze LUTs matching `predicate` (`true` ⇒ freeze).
    package mutating func applyFreezeMask(where shouldFreeze: (Int) -> Bool) {
        freezeMask = (0..<lutCount).map(shouldFreeze)
    }

    /// Wipe only melt-region INIT floats (frozen LUTs keep their binary tables).
    package mutating func wipeMeltRegion(to value: Float = 0.5) {
        for lut in 0..<lutCount where !freezeMask[lut] {
            let base = lut * 64
            for j in 0..<64 {
                inits[base + j] = value
            }
        }
    }

    package func isFrozen(lutIndex: Int) -> Bool {
        guard freezeMask.indices.contains(lutIndex) else { return false }
        return freezeMask[lutIndex]
    }
}

/// Helpers for building targeted-melt freeze masks over a TensorLUT netlist.
package enum TensorFreezeMask {
    /// All LUTs frozen except the given indices.
    package static func meltOnly(lutCount: Int, indices: Set<Int>) -> [Bool] {
        precondition(lutCount > 0)
        for i in indices {
            precondition((0..<lutCount).contains(i), "melt index \(i) out of range")
        }
        return (0..<lutCount).map { !indices.contains($0) }
    }

    /// Freeze nothing (full cold-start).
    package static func meltAll(lutCount: Int) -> [Bool] {
        Array(repeating: false, count: lutCount)
    }

    /// Freeze everything (degenerate — useful in tests).
    package static func freezeAll(lutCount: Int) -> [Bool] {
        Array(repeating: true, count: lutCount)
    }
}

/// Phase 2 adversarial loop: sparse Gaussian INIT drift + soft \(F_{crypto}\) + λ-weighted physical penalty.
package final class AdversarialSynthesizer: @unchecked Sendable {
    package struct Config: Sendable {
        /// Fraction of INIT floats mutated per child.
        package var mutationRate: Float
        /// Gaussian σ at generation 0.
        package var maxNoise: Float
        /// Terminal physical-penalty weight.
        package var lambdaMax: Float
        /// Late-generation noise floor as a fraction of `maxNoise` (PRD: cool to 20%).
        package var noiseFloorFraction: Float
        /// Optional per-LUT WIDTH; when set, mutate the first `2^width` entries at full rate
        /// and the padded tail at a reduced rate (cold-start discovery).
        package var liveWidths: [Int]?
        /// Fraction of the run with \(\lambda = 0\) before the quadratic ramp (crypto-first).
        package var lambdaDelayFraction: Float
        /// When mutating, probability of snapping a weight to exact `0` or `1` instead of Gaussian drift.
        package var discreteJumpRate: Float

        package init(
            mutationRate: Float = 0.05,
            maxNoise: Float = 0.3,
            lambdaMax: Float = 10.0,
            noiseFloorFraction: Float = 0.2,
            liveWidths: [Int]? = nil,
            lambdaDelayFraction: Float = 0,
            discreteJumpRate: Float = 0
        ) {
            self.mutationRate = mutationRate
            self.maxNoise = maxNoise
            self.lambdaMax = lambdaMax
            self.noiseFloorFraction = noiseFloorFraction
            self.liveWidths = liveWidths
            self.lambdaDelayFraction = min(1, max(0, lambdaDelayFraction))
            self.discreteJumpRate = min(1, max(0, discreteJumpRate))
        }
    }

    package let config: Config
    private let friction: TensorLUTFrictionEngine?

    package init(config: Config = Config(), friction: TensorLUTFrictionEngine? = nil) {
        self.config = config
        self.friction = friction
    }

    package convenience init(device: MTLDevice, config: Config = Config()) throws {
        self.init(config: config, friction: try TensorLUTFrictionEngine(device: device))
    }

    // MARK: - Mutation

    /// Sparse continuous mutation with clamping to `[0, 1]`. Noise σ cools with generation progress.
    /// Frozen LUTs (`chromosome.freezeMask[lut] == true`) are never drifted.
    package func mutate(
        chromosome: inout TensorChromosome,
        currentGen: Int,
        totalGens: Int,
        rng: inout some RandomNumberGenerator
    ) {
        let progress = generationProgress(currentGen: currentGen, totalGens: totalGens)
        let cool = 1.0 - progress * (1.0 - config.noiseFloorFraction)
        let currentNoise = config.maxNoise * cool
        let lutCount = chromosome.lutCount
        precondition(chromosome.freezeMask.count == lutCount, "freezeMask/lutCount mismatch")

        func mutateIndex(_ idx: Int, rate: Float, chromosome: inout TensorChromosome, rng: inout some RandomNumberGenerator) {
            if Float.random(in: 0..<1, using: &rng) >= rate { return }
            if config.discreteJumpRate > 0,
               Float.random(in: 0..<1, using: &rng) < config.discreteJumpRate {
                chromosome.inits[idx] = Float.random(in: 0..<1, using: &rng) < 0.5 ? 0 : 1
                return
            }
            let drift = boxMullerGaussian(rng: &rng) * currentNoise
            chromosome.inits[idx] = min(1.0, max(0.0, chromosome.inits[idx] + drift))
        }

        if let widths = config.liveWidths {
            precondition(widths.count * 64 == chromosome.inits.count, "liveWidths×64 must match genome")
            for (lutIdx, width) in widths.enumerated() {
                if chromosome.freezeMask[lutIdx] { continue }
                precondition((1...6).contains(width), "live width must be 1…6")
                let base = lutIdx * 64
                let live = 1 << width
                for j in 0..<64 {
                    let rate = j < live ? config.mutationRate : config.mutationRate * 0.35
                    mutateIndex(base + j, rate: rate, chromosome: &chromosome, rng: &rng)
                }
            }
        } else {
            for lutIdx in 0..<lutCount {
                if chromosome.freezeMask[lutIdx] { continue }
                let base = lutIdx * 64
                for j in 0..<64 {
                    mutateIndex(base + j, rate: config.mutationRate, chromosome: &chromosome, rng: &rng)
                }
            }
        }
        chromosome.fitness = -Float.greatestFiniteMagnitude
    }

    /// Uniform crossover of 64-wide LUT blocks between two parents.
    /// Frozen blocks always keep parent A's tables (both parents should share the same freeze mask).
    package func crossover(
        _ a: TensorChromosome,
        _ b: TensorChromosome,
        rng: inout some RandomNumberGenerator
    ) -> TensorChromosome {
        precondition(a.inits.count == b.inits.count)
        precondition(a.inits.count % 64 == 0)
        precondition(a.freezeMask.count == a.lutCount)
        var child = a.inits
        let lutCount = a.lutCount
        for lut in 0..<lutCount {
            if a.freezeMask[lut] { continue }
            if Bool.random(using: &rng) { continue }
            let base = lut * 64
            for j in 0..<64 {
                child[base + j] = b.inits[base + j]
            }
        }
        return TensorChromosome(inits: child, freezeMask: a.freezeMask)
    }

    // MARK: - Fitness

    /// Soft \(ct \times pt\): negative sum of squared errors vs target output bits.
    /// Perfect match ⇒ `0.0`; errors are increasingly negative.
    package func computeCryptoFitness(tensorOutputWires: [Float], targetBits: [Float]) -> Float {
        precondition(tensorOutputWires.count == targetBits.count)
        var errorSum: Float = 0
        for i in tensorOutputWires.indices {
            let diff = tensorOutputWires[i] - targetBits[i]
            errorSum += diff * diff
        }
        return -errorSum
    }

    /// \(\lambda_g = \lambda_{max} (p')^2\) with optional delay before the quadratic ramp starts.
    package func lambda(currentGen: Int, totalGens: Int) -> Float {
        let progress = generationProgress(currentGen: currentGen, totalGens: totalGens)
        let delay = config.lambdaDelayFraction
        let delayed: Float
        if delay >= 1 {
            delayed = 0
        } else if progress <= delay {
            delayed = 0
        } else {
            delayed = (progress - delay) / (1 - delay)
        }
        return config.lambdaMax * delayed * delayed
    }

    /// \(F = F_{crypto} - \lambda \sum w(1-w)\).
    package func combineFitness(
        cryptoFitness: Float,
        sumPenalty: Float,
        currentGen: Int,
        totalGens: Int
    ) -> Float {
        cryptoFitness - lambda(currentGen: currentGen, totalGens: totalGens) * sumPenalty
    }

    /// Metal friction + λ schedule. Updates `chromosome.fitness`.
    /// Frozen LUTs contribute `0` to \(\sum w(1-w)\).
    ///
    /// - Parameter initsBuffer: Shared buffer already holding `chromosome.inits` (caller may
    ///   write via `contents()` before calling).
    @discardableResult
    package func computeTotalFitness(
        chromosome: inout TensorChromosome,
        cryptoFitness: Float,
        currentGen: Int,
        totalGens: Int,
        initsBuffer: MTLBuffer
    ) -> Float {
        let sumPenalty: Float
        let activeFreeze: [Bool]? =
            chromosome.meltLUTCount == chromosome.lutCount ? nil : chromosome.freezeMask
        if let friction {
            sumPenalty = friction.sumDiscretenessPenalty(
                initsBuffer: initsBuffer,
                count: chromosome.inits.count,
                freezeMask: activeFreeze
            )
        } else {
            sumPenalty = TensorLUTFrictionEngine.hostSumDiscretenessPenalty(
                chromosome.inits,
                freezeMask: activeFreeze
            )
        }
        let total = combineFitness(
            cryptoFitness: cryptoFitness,
            sumPenalty: sumPenalty,
            currentGen: currentGen,
            totalGens: totalGens
        )
        chromosome.fitness = total
        return total
    }

    /// Convenience: copy chromosome into `initsBuffer`, then score.
    @discardableResult
    package func computeTotalFitness(
        chromosome: inout TensorChromosome,
        cryptoFitness: Float,
        currentGen: Int,
        totalGens: Int,
        device: MTLDevice
    ) -> Float {
        let bytes = chromosome.inits.count * MemoryLayout<Float>.stride
        guard let initsBuffer = device.makeBuffer(
            bytes: chromosome.inits,
            length: bytes,
            options: .storageModeShared
        ) else {
            fatalError("Failed to allocate INIT buffer for fitness")
        }
        return computeTotalFitness(
            chromosome: &chromosome,
            cryptoFitness: cryptoFitness,
            currentGen: currentGen,
            totalGens: totalGens,
            initsBuffer: initsBuffer
        )
    }

    // MARK: - Helpers

    private func generationProgress(currentGen: Int, totalGens: Int) -> Float {
        let g = max(totalGens, 1)
        return min(1.0, max(0.0, Float(currentGen) / Float(g)))
    }

    /// Standard normal via Box–Muller (`u1` avoids `log(0)`).
    private func boxMullerGaussian(rng: inout some RandomNumberGenerator) -> Float {
        let u1 = Float.random(in: Float.leastNormalMagnitude..<1, using: &rng)
        let u2 = Float.random(in: 0..<1, using: &rng)
        return sqrt(-2.0 * log(u1)) * cos(2.0 * Float.pi * u2)
    }
}
