import Metal
import XCTest
@testable import HELUTCore

final class AdversarialHarnessTests: XCTestCase {

    /// XOR TensorLUT: evolve under λ cooling; elite should recover near-binary INITs and perfect crypto.
    func testXORLambdaCoolingSnapsTowardBinary() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device not available")
        }

        let xorLUT = TensorLUT6Cell(
            cellID: 0,
            inputWires: [0, 1],
            outputWire: 2,
            rawTruthTable: "0110"
        )
        let netlist = TensorLUTNetlist(
            luts: [xorLUT],
            dffs: [],
            totalWires: 3,
            executionLevels: [[0]]
        )

        let target = AdversarialTarget(
            inputWireIDs: [0, 1],
            outputWireIDs: [2],
            inputVectors: [
                [0, 0],
                [1, 0],
                [0, 1],
                [1, 1]
            ],
            expectedOutputs: [
                [0],
                [1],
                [1],
                [0]
            ],
            clockTicks: 0
        )

        let pipeline = try TensorLUTPipeline(device: device, netlist: netlist)
        let synthesizer = try AdversarialSynthesizer(
            device: device,
            config: .init(mutationRate: 0.15, maxNoise: 0.35, lambdaMax: 8)
        )
        let harness = AdversarialHarness(
            device: device,
            pipeline: pipeline,
            synthesizer: synthesizer,
            netlist: netlist
        )

        var lastStats: AdversarialHarness.GenerationStats?
        let best = harness.run(
            target: target,
            config: .init(
                populationSize: 12,
                generations: 24,
                eliteCount: 2,
                seedScatter: true,
                rngSeed: 0xC0FFEE
            ),
            progress: { lastStats = $0 }
        )

        XCTAssertNotNil(lastStats)
        XCTAssertEqual(lastStats?.generation, 23)
        XCTAssertGreaterThan(lastStats?.lambda ?? -1, 5)

        // Soft crypto across 4 corners should be near-perfect (sum of −MSE ≈ 0).
        XCTAssertGreaterThan(lastStats?.bestCrypto ?? -100, -0.05)

        // Physical penalty should be squeezed down late in the schedule.
        let penalty = TensorLUTFrictionEngine.hostSumDiscretenessPenalty(best.inits)
        XCTAssertLessThan(penalty, 1.0, "λ cooling should push INIT floats toward binary")

        // Active XOR corners (indices 0…3 after pad) near {0,1,1,0}.
        XCTAssertEqual(best.inits[0], 0, accuracy: 0.15)
        XCTAssertEqual(best.inits[1], 1, accuracy: 0.15)
        XCTAssertEqual(best.inits[2], 1, accuracy: 0.15)
        XCTAssertEqual(best.inits[3], 0, accuracy: 0.15)
    }
}
