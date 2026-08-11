import Metal
import XCTest
@testable import HELUTCore

final class AdversarialColdStartTests: XCTestCase {

    /// Wipe INIT tables to 0.5 and rediscover a 2-bit adder under \(F_{crypto}\) + delayed λ squeeze.
    func testTwoBitAdderColdStartDiscovery() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device not available")
        }

        let netlist = makeTwoBitAdderNetlist()
        let target = makeTwoBitAdderTarget()
        let pipeline = try TensorLUTPipeline(device: device, netlist: netlist)
        let wiped = [Float](repeating: 0.5, count: 4 * 64)

        // Phase A — crypto-only exploration from total ambiguity.
        let exploreSynth = try AdversarialSynthesizer(
            device: device,
            config: .init(
                mutationRate: 0.22,
                maxNoise: 0.55,
                lambdaMax: 0,
                liveWidths: [2, 2, 3, 3],
                discreteJumpRate: 0.35
            )
        )
        let exploreHarness = AdversarialHarness(
            device: device,
            pipeline: pipeline,
            synthesizer: exploreSynth,
            netlist: netlist
        )
        var exploreStats: AdversarialHarness.GenerationStats?
        let explored = exploreHarness.run(
            target: target,
            config: .init(
                populationSize: 64,
                generations: 160,
                eliteCount: 8,
                seedScatter: true,
                rngSeed: 0xADD12,
                seedInits: wiped,
                crossoverRate: 0.7
            ),
            progress: { exploreStats = $0 }
        )
        XCTAssertGreaterThan(
            exploreStats?.bestCrypto ?? -100,
            -0.2,
            "Explore phase failed (crypto=\(String(describing: exploreStats?.bestCrypto)))"
        )

        // Phase B — freeze toward binary under rising λ, seeded from the explorer elite.
        let squeezeSynth = try AdversarialSynthesizer(
            device: device,
            config: .init(
                mutationRate: 0.1,
                maxNoise: 0.25,
                lambdaMax: 18,
                liveWidths: [2, 2, 3, 3],
                lambdaDelayFraction: 0.15,
                discreteJumpRate: 0.45
            )
        )
        let squeezeHarness = AdversarialHarness(
            device: device,
            pipeline: pipeline,
            synthesizer: squeezeSynth,
            netlist: netlist
        )
        var squeezeStats: AdversarialHarness.GenerationStats?
        let best = squeezeHarness.run(
            target: target,
            config: .init(
                populationSize: 48,
                generations: 140,
                eliteCount: 6,
                seedScatter: true,
                rngSeed: 0xADD13,
                seedInits: explored.inits,
                crossoverRate: 0.5,
                polishBinaryAtEnd: true
            ),
            progress: { squeezeStats = $0 }
        )

        XCTAssertGreaterThan(squeezeStats?.lambda ?? 0, 5)
        XCTAssertGreaterThan(
            squeezeStats?.bestCrypto ?? -100,
            -0.05,
            "Squeeze phase lost crypto (crypto=\(String(describing: squeezeStats?.bestCrypto)))"
        )

        let nonBinaryCount = best.inits.reduce(0) { count, w in
            count + ((w > 0.05 && w < 0.95) ? 1 : 0)
        }
        XCTAssertEqual(
            nonBinaryCount,
            0,
            "Polished elite still has \(nonBinaryCount) fractional INIT weights"
        )

        let discreteCrypto = evaluateCrypto(
            inits: best.inits,
            device: device,
            pipeline: pipeline,
            synthesizer: squeezeSynth,
            netlist: netlist,
            target: target
        )
        XCTAssertEqual(discreteCrypto, 0, accuracy: 1e-4, "Binarized INITs must match expectedOutputs exactly")
        XCTAssertGreaterThan(best.fitness, -0.05)

        // Phase 3: freeze the discovered chromosome into gate-level Verilog.
        let verilog = TensorLUTEmitter.emitVerilog(
            moduleName: "two_bit_adder",
            netlist: netlist,
            chromosome: best,
            inputWires: [0, 1, 2, 3],
            outputWires: [5, 6, 7]
        )
        XCTAssertTrue(verilog.contains("module two_bit_adder ("))
        XCTAssertEqual(verilog.components(separatedBy: "LUT6 #(").count - 1, 4)
        XCTAssertTrue(verilog.contains("endmodule"))

        // INIT hex round-trip must preserve the polished TensorLUT tables.
        for lutIdx in 0..<4 {
            let slice = best.inits[(lutIdx * 64)..<((lutIdx + 1) * 64)]
            let hex = TensorLUTEmitter.initHex(entries: slice)
            let recovered = TensorLUTEmitter.entriesFromInitHex(hex)
            for j in 0..<64 {
                XCTAssertEqual(recovered[j], slice[slice.startIndex + j], accuracy: 0)
            }
            XCTAssertTrue(verilog.contains("64'h\(hex)"), "missing INIT for lut \(lutIdx)")
        }
    }

    private func makeTwoBitAdderNetlist() -> TensorLUTNetlist {
        let luts = [
            TensorLUT6Cell(cellID: 0, inputWires: [0, 2], outputWire: 5, rawTruthTable: "0000"),
            TensorLUT6Cell(cellID: 1, inputWires: [0, 2], outputWire: 4, rawTruthTable: "0000"),
            TensorLUT6Cell(cellID: 2, inputWires: [1, 3, 4], outputWire: 6, rawTruthTable: "00000000"),
            TensorLUT6Cell(cellID: 3, inputWires: [1, 3, 4], outputWire: 7, rawTruthTable: "00000000")
        ]
        return TensorLUTNetlist(
            luts: luts,
            dffs: [],
            totalWires: 8,
            executionLevels: [[0, 1], [2, 3]]
        )
    }

    private func makeTwoBitAdderTarget() -> AdversarialTarget {
        var inputs = [[Float]]()
        var expectedOutputs = [[Float]]()
        for a in 0..<4 {
            for b in 0..<4 {
                inputs.append([
                    Float(a & 1),
                    Float((a >> 1) & 1),
                    Float(b & 1),
                    Float((b >> 1) & 1)
                ])
                let sum = a + b
                expectedOutputs.append([
                    Float(sum & 1),
                    Float((sum >> 1) & 1),
                    Float((sum >> 2) & 1)
                ])
            }
        }
        return AdversarialTarget(
            inputWireIDs: [0, 1, 2, 3],
            outputWireIDs: [5, 6, 7],
            inputVectors: inputs,
            expectedOutputs: expectedOutputs,
            clockTicks: 0
        )
    }

    private func evaluateCrypto(
        inits: [Float],
        device: MTLDevice,
        pipeline: TensorLUTPipeline,
        synthesizer: AdversarialSynthesizer,
        netlist: TensorLUTNetlist,
        target: AdversarialTarget
    ) -> Float {
        let batchSize = target.batchSize
        let totalWires = netlist.totalWires
        guard
            let initsBuffer = device.makeBuffer(
                bytes: inits,
                length: inits.count * MemoryLayout<Float>.stride,
                options: .storageModeShared
            ),
            let wireBuffer = device.makeBuffer(
                length: batchSize * totalWires * MemoryLayout<Float>.stride,
                options: .storageModeShared
            )
        else {
            return -Float.greatestFiniteMagnitude
        }

        let wirePtr = wireBuffer.contents().bindMemory(to: Float.self, capacity: batchSize * totalWires)
        for b in 0..<batchSize {
            let off = b * totalWires
            for w in 0..<totalWires { wirePtr[off + w] = 0 }
            for (idx, wireID) in target.inputWireIDs.enumerated() {
                wirePtr[off + Int(wireID)] = target.inputVectors[b][idx]
            }
        }

        pipeline.evaluateForward(
            totalWires: totalWires,
            initsBuffer: initsBuffer,
            wireBuffer: wireBuffer,
            batchSize: batchSize
        )

        var crypto: Float = 0
        for b in 0..<batchSize {
            let off = b * totalWires
            let extracted = target.outputWireIDs.map { wirePtr[off + Int($0)] }
            crypto += synthesizer.computeCryptoFitness(
                tensorOutputWires: extracted,
                targetBits: target.expectedOutputs[b]
            )
        }
        return crypto
    }
}
