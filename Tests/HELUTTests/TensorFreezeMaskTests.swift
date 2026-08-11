import Metal
import XCTest
@testable import HELUTCore

final class TensorFreezeMaskTests: XCTestCase {

    func testMutateSkipsFrozenLUTs() {
        var chrom = TensorChromosome(
            inits: [Float](repeating: 0.25, count: 128),
            freezeMask: [true, false]
        )
        let frozenSlice = Array(chrom.inits[0..<64])
        let synth = AdversarialSynthesizer(config: .init(mutationRate: 1.0, maxNoise: 0.9))
        var rng = SplitMix64(seed: 7)
        for gen in 0..<40 {
            synth.mutate(chromosome: &chrom, currentGen: gen, totalGens: 40, rng: &rng)
        }
        XCTAssertEqual(Array(chrom.inits[0..<64]), frozenSlice)
        XCTAssertNotEqual(Array(chrom.inits[64..<128]), [Float](repeating: 0.25, count: 64))
    }

    func testCrossoverKeepsFrozenParentA() {
        var aInits = [Float](repeating: 0, count: 128)
        var bInits = [Float](repeating: 1, count: 128)
        for i in 0..<64 { aInits[i] = 0.11; bInits[i] = 0.99 }
        let a = TensorChromosome(inits: aInits, freezeMask: [true, false])
        let b = TensorChromosome(inits: bInits, freezeMask: [true, false])
        let synth = AdversarialSynthesizer()
        var rng = SplitMix64(seed: 99)
        var sawMeltSwap = false
        for _ in 0..<32 {
            let child = synth.crossover(a, b, rng: &rng)
            XCTAssertEqual(Array(child.inits[0..<64]), Array(aInits[0..<64]))
            if child.inits[64] == 1 { sawMeltSwap = true }
        }
        XCTAssertTrue(sawMeltSwap, "expected at least one melt-block swap from parent B")
    }

    func testHostPenaltyIgnoresFrozenLUTs() {
        var inits = [Float](repeating: 0.5, count: 128)
        // Frozen LUT0 at binary — would be 0 penalty anyway; make frozen fractional.
        for i in 0..<64 { inits[i] = 0.5 }
        for i in 64..<128 { inits[i] = 0 } // melt region binary

        let full = TensorLUTFrictionEngine.hostSumDiscretenessPenalty(inits)
        XCTAssertEqual(full, 64 * 0.25, accuracy: 1e-5)

        let masked = TensorLUTFrictionEngine.hostSumDiscretenessPenalty(
            inits,
            freezeMask: [true, false]
        )
        XCTAssertEqual(masked, 0, accuracy: 1e-5)
    }

    func testMetalPenaltyMatchesHostWithFreeze() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device not available")
        }
        let friction = try TensorLUTFrictionEngine(device: device)
        var inits = [Float](repeating: 0.5, count: 128)
        for i in 64..<128 { inits[i] = 0.25 }
        let mask = [true, false]
        let expected = TensorLUTFrictionEngine.hostSumDiscretenessPenalty(inits, freezeMask: mask)
        guard let buffer = device.makeBuffer(
            bytes: inits,
            length: inits.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else {
            return XCTFail("buffer")
        }
        let got = friction.sumDiscretenessPenalty(
            initsBuffer: buffer,
            count: inits.count,
            freezeMask: mask
        )
        XCTAssertEqual(got, expected, accuracy: 1e-4)
        // Melt LUT only: 64 × 0.25×0.75 = 12
        XCTAssertEqual(got, 12, accuracy: 1e-3)
    }

    func testWipeMeltRegionPreservesFrozen() {
        var chrom = TensorChromosome.from(
            netlist: TensorLUTNetlist(
                luts: [
                    TensorLUT6Cell(cellID: 0, inputWires: [0, 1], outputWire: 2, rawTruthTable: "0110"),
                    TensorLUT6Cell(cellID: 1, inputWires: [0, 1], outputWire: 3, rawTruthTable: "1001")
                ],
                dffs: [],
                totalWires: 4,
                executionLevels: [[0, 1]]
            )
        )
        chrom.freezeAllExcept(meltIndices: [1])
        let frozen = Array(chrom.inits[0..<64])
        chrom.wipeMeltRegion(to: 0.5)
        XCTAssertEqual(Array(chrom.inits[0..<64]), frozen)
        XCTAssertTrue(chrom.inits[64..<128].allSatisfy { $0 == 0.5 })
        XCTAssertEqual(chrom.meltLUTCount, 1)
    }

    func testTwoBitAdderTargetedMeltDiscovers() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device not available")
        }

        // Same topology as cold-start adder; freeze first two LUTs, melt the carry pair.
        let netlist = TensorLUTNetlist(
            luts: [
                TensorLUT6Cell(cellID: 0, inputWires: [0, 2], outputWire: 5, rawTruthTable: "0110"),
                TensorLUT6Cell(cellID: 1, inputWires: [0, 2], outputWire: 4, rawTruthTable: "1000"),
                TensorLUT6Cell(cellID: 2, inputWires: [1, 3, 4], outputWire: 6, rawTruthTable: String(repeating: "0", count: 8)),
                TensorLUT6Cell(cellID: 3, inputWires: [1, 3, 4], outputWire: 7, rawTruthTable: String(repeating: "0", count: 8))
            ],
            dffs: [],
            totalWires: 8,
            executionLevels: [[0, 1], [2, 3]]
        )
        // Known-good sum/carry for LUT0/1 (XOR + AND of low bits); melt LUT2/3 from 0.5.
        var seed = netlist.packedINITBuffer()
        for i in (2 * 64)..<(4 * 64) { seed[i] = 0.5 }
        let freeze = TensorFreezeMask.meltOnly(lutCount: 4, indices: [2, 3])

        var inputs = [[Float]]()
        var expected = [[Float]]()
        for a in 0..<4 {
            for b in 0..<4 {
                inputs.append([Float(a & 1), Float((a >> 1) & 1), Float(b & 1), Float((b >> 1) & 1)])
                let sum = a + b
                expected.append([Float(sum & 1), Float((sum >> 1) & 1), Float((sum >> 2) & 1)])
            }
        }
        let target = AdversarialTarget(
            inputWireIDs: [0, 1, 2, 3],
            outputWireIDs: [5, 6, 7],
            inputVectors: inputs,
            expectedOutputs: expected,
            clockTicks: 0
        )

        let pipeline = try TensorLUTPipeline(device: device, netlist: netlist)
        let synth = try AdversarialSynthesizer(
            device: device,
            config: .init(
                mutationRate: 0.2,
                maxNoise: 0.4,
                lambdaMax: 12,
                liveWidths: [2, 2, 3, 3],
                lambdaDelayFraction: 0.1,
                discreteJumpRate: 0.4
            )
        )
        let harness = AdversarialHarness(
            device: device,
            pipeline: pipeline,
            synthesizer: synth,
            netlist: netlist
        )
        let best = harness.run(
            target: target,
            config: .init(
                populationSize: 48,
                generations: 120,
                eliteCount: 6,
                seedScatter: true,
                rngSeed: 0x7A6E17,
                seedInits: seed,
                crossoverRate: 0.55,
                polishBinaryAtEnd: true,
                freezeMask: freeze
            )
        )

        // Frozen XOR/AND tables untouched.
        XCTAssertEqual(Array(best.inits[0..<64]), Array(seed[0..<64]))
        XCTAssertEqual(Array(best.inits[64..<128]), Array(seed[64..<128]))
        let meltNonBinary = AdversarialHarness.nonBinaryCount(best.inits, freezeMask: freeze)
        XCTAssertEqual(meltNonBinary, 0, "melt region still fractional (\(meltNonBinary))")
        XCTAssertGreaterThan(best.fitness, -0.05)
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
