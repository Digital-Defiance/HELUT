import Metal
import XCTest
@testable import HELUTCore

final class AdversarialStreamTests: XCTestCase {

    /// Known XOR INIT + 4-step stream must accumulate perfect crypto (state carry-forward proof).
    func testStreamingDelayXORKnownINIT() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device not available")
        }
        let (netlist, target) = makeDelayXORFixture()
        let pipeline = try TensorLUTPipeline(device: device, netlist: netlist)
        let synthesizer = try AdversarialSynthesizer(device: device)
        let harness = AdversarialHarness(
            device: device,
            pipeline: pipeline,
            synthesizer: synthesizer,
            netlist: netlist
        )

        // Single "generation" with pristine XOR genome — no mutation.
        let best = harness.runStream(
            target: target,
            config: .init(
                populationSize: 1,
                generations: 1,
                eliteCount: 1,
                seedScatter: false,
                rngSeed: 1,
                polishBinaryAtEnd: false
            )
        )
        XCTAssertEqual(best.fitness, 0, accuracy: 1e-4)
        XCTAssertEqual(
            TensorLUTFrictionEngine.hostSumDiscretenessPenalty(best.inits),
            0,
            accuracy: 1e-5
        )
    }

    /// Cold-start from 0.5 discovers Delay-XOR under streaming MSE + λ squeeze.
    func testStreamingDelayXORColdStart() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device not available")
        }
        let (netlist, target) = makeDelayXORFixture(placeholderTruth: true)
        let pipeline = try TensorLUTPipeline(device: device, netlist: netlist)
        let wiped = [Float](repeating: 0.5, count: 64)

        let exploreSynth = try AdversarialSynthesizer(
            device: device,
            config: .init(
                mutationRate: 0.25,
                maxNoise: 0.5,
                lambdaMax: 0,
                liveWidths: [2],
                discreteJumpRate: 0.4
            )
        )
        let explored = AdversarialHarness(
            device: device,
            pipeline: pipeline,
            synthesizer: exploreSynth,
            netlist: netlist
        ).runStream(
            target: target,
            config: .init(
                populationSize: 40,
                generations: 80,
                eliteCount: 5,
                seedScatter: true,
                rngSeed: 0xD31A41,
                seedInits: wiped,
                crossoverRate: 0.6
            )
        )

        let squeezeSynth = try AdversarialSynthesizer(
            device: device,
            config: .init(
                mutationRate: 0.12,
                maxNoise: 0.25,
                lambdaMax: 14,
                liveWidths: [2],
                lambdaDelayFraction: 0.1,
                discreteJumpRate: 0.5
            )
        )
        var lastStats: AdversarialHarness.GenerationStats?
        let best = AdversarialHarness(
            device: device,
            pipeline: pipeline,
            synthesizer: squeezeSynth,
            netlist: netlist
        ).runStream(
            target: target,
            config: .init(
                populationSize: 32,
                generations: 100,
                eliteCount: 4,
                seedScatter: true,
                rngSeed: 0xD31A42,
                seedInits: explored.inits,
                crossoverRate: 0.5,
                polishBinaryAtEnd: true
            ),
            progress: { lastStats = $0 }
        )

        XCTAssertGreaterThan(lastStats?.bestCrypto ?? -100, -0.05)
        let nonBinary = best.inits.reduce(0) { $0 + (($1 > 0.05 && $1 < 0.95) ? 1 : 0) }
        XCTAssertEqual(nonBinary, 0, "λ/polish left \(nonBinary) fractional weights")
        // Constrained XOR corners (stream hits 00,01,10,11).
        XCTAssertEqual(best.inits[0], 0, accuracy: 0.01)
        XCTAssertEqual(best.inits[1], 1, accuracy: 0.01)
        XCTAssertEqual(best.inits[2], 1, accuracy: 0.01)
        XCTAssertEqual(best.inits[3], 0, accuracy: 0.01)
        XCTAssertGreaterThan(best.fitness, -0.05)
    }

    /// Output = CurrentInput XOR PreviousInput (DFF holds previous).
    /// Stream starts Q=0: 0,1,0,1,1 → expected 0,1,1,1,0 (hits all four address corners).
    private func makeDelayXORFixture(placeholderTruth: Bool = false) -> (TensorLUTNetlist, AdversarialStreamTarget) {
        let lut = TensorLUT6Cell(
            cellID: 0,
            inputWires: [0, 1],
            outputWire: 2,
            rawTruthTable: placeholderTruth ? "0000" : "0110"
        )
        let dff = TensorDFFCell(dWire: 0, qWire: 1)
        let netlist = TensorLUTNetlist(
            luts: [lut],
            dffs: [dff],
            totalWires: 3,
            executionLevels: [[0]]
        )
        let target = AdversarialStreamTarget(
            inputWireIDs: [0],
            outputWireIDs: [2],
            inputSequence: [[[0]], [[1]], [[0]], [[1]], [[1]]],
            expectedSequence: [[[0]], [[1]], [[1]], [[1]], [[0]]],
            initialDFFStates: [1: 0]
        )
        return (netlist, target)
    }
}
