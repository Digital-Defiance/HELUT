import Metal
import XCTest
@testable import HELUTCore

final class AdversarialSynthesizerTests: XCTestCase {

    func testCryptoFitnessPerfectIsZero() {
        let synth = AdversarialSynthesizer()
        let wires: [Float] = [0, 1, 0.5, 1]
        let targets: [Float] = [0, 1, 0.5, 1]
        XCTAssertEqual(synth.computeCryptoFitness(tensorOutputWires: wires, targetBits: targets), 0, accuracy: 1e-6)
    }

    func testCryptoFitnessIsNegativeMSE() {
        let synth = AdversarialSynthesizer()
        // errors: 0.5^2 + 0.5^2 = 0.5 → fitness -0.5
        let fitness = synth.computeCryptoFitness(
            tensorOutputWires: [0.5, 0.5],
            targetBits: [0, 1]
        )
        XCTAssertEqual(fitness, -0.5, accuracy: 1e-6)
    }

    func testLambdaScheduleQuadratic() {
        let synth = AdversarialSynthesizer(config: .init(lambdaMax: 10))
        XCTAssertEqual(synth.lambda(currentGen: 0, totalGens: 100), 0, accuracy: 1e-6)
        XCTAssertEqual(synth.lambda(currentGen: 50, totalGens: 100), 2.5, accuracy: 1e-5)
        XCTAssertEqual(synth.lambda(currentGen: 100, totalGens: 100), 10, accuracy: 1e-5)
    }

    func testMutateClampsToUnitInterval() {
        var chrom = TensorChromosome(inits: [Float](repeating: 0.5, count: 128))
        let synth = AdversarialSynthesizer(config: .init(mutationRate: 1.0, maxNoise: 5.0))
        var rng = SplitMix64(seed: 42)
        for gen in 0..<20 {
            synth.mutate(chromosome: &chrom, currentGen: gen, totalGens: 20, rng: &rng)
        }
        XCTAssertTrue(chrom.inits.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    func testCombineFitnessAppliesLambdaPenalty() {
        let synth = AdversarialSynthesizer(config: .init(lambdaMax: 4))
        // gen=total → λ=4; crypto=-1; penalty=2 → -1 - 8 = -9
        let total = synth.combineFitness(cryptoFitness: -1, sumPenalty: 2, currentGen: 10, totalGens: 10)
        XCTAssertEqual(total, -9, accuracy: 1e-5)
    }

    func testMetalDiscretenessPenaltyMatchesHost() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device not available")
        }
        let friction = try TensorLUTFrictionEngine(device: device)
        let inits: [Float] = [0, 0.25, 0.5, 0.75, 1, 0.1, 0.9]
        let expected = TensorLUTFrictionEngine.hostSumDiscretenessPenalty(inits)
        // 0 + 0.1875 + 0.25 + 0.1875 + 0 + 0.09 + 0.09 = 0.805
        XCTAssertEqual(expected, 0.805, accuracy: 1e-5)

        guard let buffer = device.makeBuffer(
            bytes: inits,
            length: inits.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else {
            return XCTFail("buffer")
        }
        let got = friction.sumDiscretenessPenalty(initsBuffer: buffer, count: inits.count)
        XCTAssertEqual(got, expected, accuracy: 1e-4)
    }

    func testComputeTotalFitnessBinaryInitZeroPenaltyAtGenEnd() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device not available")
        }
        let synth = try AdversarialSynthesizer(
            device: device,
            config: .init(lambdaMax: 10)
        )
        var chrom = TensorChromosome(inits: [0, 1, 0, 1, 0, 1] + [Float](repeating: 0, count: 58))
        let crypto: Float = -0.25
        let total = synth.computeTotalFitness(
            chromosome: &chrom,
            cryptoFitness: crypto,
            currentGen: 100,
            totalGens: 100,
            device: device
        )
        // Binary INITs ⇒ penalty 0 ⇒ fitness == crypto even at λ_max
        XCTAssertEqual(total, crypto, accuracy: 1e-4)
        XCTAssertEqual(chrom.fitness, crypto, accuracy: 1e-4)
    }
}

/// Tiny deterministic RNG for mutation tests.
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
