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
                rngSeed: 0xC0FFEE,
                polishBinaryAtEnd: true
            ),
            progress: { lastStats = $0 }
        )

        XCTAssertNotNil(lastStats)
        XCTAssertEqual(lastStats?.generation, 23)
        XCTAssertGreaterThan(lastStats?.lambda ?? -1, 5)

        // Soft crypto across 4 corners should be near-perfect (sum of −MSE ≈ 0).
        XCTAssertGreaterThan(lastStats?.bestCrypto ?? -100, -0.05)

        // Snap (polishBinaryAtEnd): π=0 and INIT bits are the XOR interpolant.
        let penalty = TensorLUTFrictionEngine.hostSumDiscretenessPenalty(best.inits)
        XCTAssertLessThan(penalty, 1e-5, "snap must land on the Boolean cube")
        XCTAssertEqual(best.inits[0], 0, accuracy: 1e-5)
        XCTAssertEqual(best.inits[1], 1, accuracy: 1e-5)
        XCTAssertEqual(best.inits[2], 1, accuracy: 1e-5)
        XCTAssertEqual(best.inits[3], 0, accuracy: 1e-5)
        let emitted = TensorLUTFormal.emitBinary(Array(best.inits.prefix(4)))
        XCTAssertEqual(emitted, [0, 1, 1, 0])
    }

    /// Two-LUT cascade: y = (a ∧ b) ⊕ c. Melt, snap, emit Verilog INIT ≡ spec on 8 corners.
    func testTwoLUTCascadeMeltFreezeSnapEmit() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device not available")
        }
        let andLUT = TensorLUT6Cell(
            cellID: 0,
            inputWires: [0, 1],
            outputWire: 2,
            rawTruthTable: "1000"
        )
        let xorLUT = TensorLUT6Cell(
            cellID: 1,
            inputWires: [2, 3],
            outputWire: 4,
            rawTruthTable: "0110"
        )
        let netlist = TensorLUTNetlist(
            luts: [andLUT, xorLUT],
            dffs: [],
            totalWires: 5,
            executionLevels: [[0], [1]]
        )
        var inputVectors: [[Float]] = []
        var expected: [[Float]] = []
        for a in 0...1 {
            for b in 0...1 {
                for c in 0...1 {
                    inputVectors.append([Float(a), Float(b), Float(c)])
                    expected.append([Float((a & b) ^ c)])
                }
            }
        }
        let target = AdversarialTarget(
            inputWireIDs: [0, 1, 3],
            outputWireIDs: [4],
            inputVectors: inputVectors,
            expectedOutputs: expected,
            clockTicks: 0
        )
        let pipeline = try TensorLUTPipeline(device: device, netlist: netlist)
        let synthesizer = try AdversarialSynthesizer(
            device: device,
            config: .init(mutationRate: 0.2, maxNoise: 0.4, lambdaMax: 10)
        )
        let harness = AdversarialHarness(
            device: device,
            pipeline: pipeline,
            synthesizer: synthesizer,
            netlist: netlist
        )
        let seed = [Float](repeating: 0.5, count: 128)
        let best = harness.run(
            target: target,
            config: .init(
                populationSize: 20,
                generations: 40,
                eliteCount: 2,
                seedScatter: true,
                rngSeed: 0xCA5C,
                seedInits: seed,
                polishBinaryAtEnd: true
            )
        )
        XCTAssertLessThan(TensorLUTFrictionEngine.hostSumDiscretenessPenalty(best.inits), 1e-4)
        for a in 0...1 {
            for b in 0...1 {
                for c in 0...1 {
                    let x = best.inits[a | (b << 1)] >= 0.5 ? 1 : 0
                    let y = best.inits[64 + (x | (c << 1))] >= 0.5 ? 1 : 0
                    XCTAssertEqual(y, (a & b) ^ c, "corner a=\(a) b=\(b) c=\(c)")
                }
            }
        }
        let verilog = TensorLUTEmitter.emitVerilog(
            moduleName: "and_xor_cascade",
            netlist: netlist,
            chromosome: best,
            inputWires: [0, 1, 3],
            outputWires: [4]
        )
        XCTAssertTrue(verilog.contains("module and_xor_cascade"))
        XCTAssertEqual(verilog.components(separatedBy: "LUT6 #(").count - 1, 2)
        let hex0 = TensorLUTEmitter.initHex(entries: best.inits[0..<64])
        let hex1 = TensorLUTEmitter.initHex(entries: best.inits[64..<128])
        XCTAssertTrue(verilog.contains("64'h\(hex0)"))
        XCTAssertTrue(verilog.contains("64'h\(hex1)"))
    }
}
