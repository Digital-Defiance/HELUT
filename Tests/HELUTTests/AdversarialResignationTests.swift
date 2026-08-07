import Metal
import XCTest
@testable import HELUTCore

final class AdversarialResignationTests: XCTestCase {

    /// At λ midpoint, a still-fractional melt region must resign and reboot once.
    func testStreamResignsAndRebootsLineage() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device not available")
        }

        // Tiny Delay-XOR stream netlist (1 LUT + 1 DFF) — easy to keep fractional under λ.
        let netlist = TensorLUTNetlist(
            luts: [
                TensorLUT6Cell(cellID: 0, inputWires: [0, 1], outputWire: 2, rawTruthTable: "0110")
            ],
            dffs: [
                TensorDFFCell(dWire: 2, qWire: 1)
            ],
            totalWires: 3,
            executionLevels: [[0]]
        )
        let wiped = [Float](repeating: 0.5, count: 64)
        let target = AdversarialStreamTarget(
            inputWireIDs: [0],
            outputWireIDs: [2],
            inputSequence: [[[0]], [[1]], [[0]], [[1]]],
            expectedSequence: [[[0]], [[1]], [[1]], [[0]]],
            initialDFFStates: [1: 0]
        )

        let pipeline = try TensorLUTPipeline(device: device, netlist: netlist)
        let synth = try AdversarialSynthesizer(
            device: device,
            config: .init(
                mutationRate: 0.05,
                maxNoise: 0.05,
                lambdaMax: 10,
                lambdaDelayFraction: 0,
                discreteJumpRate: 0
            )
        )
        let harness = AdversarialHarness(
            device: device,
            pipeline: pipeline,
            synthesizer: synth,
            netlist: netlist
        )

        var resignEvents = 0
        var maxLineage = 0
        _ = harness.runStream(
            target: target,
            config: .init(
                populationSize: 4,
                generations: 40,
                eliteCount: 1,
                seedScatter: true,
                rngSeed: 0xAE51_601,
                seedInits: wiped,
                crossoverRate: 0.3,
                polishBinaryAtEnd: false,
                resignNonBinaryAbove: 0, // any fraction ⇒ resign at λ midpoint
                resignLambdaFraction: 0.5,
                maxLineageRestarts: 1
            ),
            progress: { stats in
                maxLineage = max(maxLineage, stats.lineageIndex)
                if stats.resigned { resignEvents += 1 }
            }
        )

        XCTAssertGreaterThanOrEqual(resignEvents, 1, "expected at least one RESIGN at λ midpoint")
        XCTAssertGreaterThanOrEqual(maxLineage, 1, "expected a fresh-seed reboot after resignation")
    }
}
