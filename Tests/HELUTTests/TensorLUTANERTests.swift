import Metal
import XCTest
@testable import HELUTCore

final class TensorLUTANERTests: XCTestCase {

    func testWideNetlistStaysOffTheEngine() {
        let netlist = TensorLUTNetlist(luts: [], totalWires: 600, executionLevels: [])
        XCTAssertNil(TensorLUTANERBooster(netlist: netlist))
    }

    func testLargeLookupCountStaysOffTheEngine() {
        let luts = (0..<TensorLUTANERBooster.maxBoostLUTs + 1).map { index in
            TensorLUT6Cell(cellID: index, inputWires: [0], outputWire: 1, rawTruthTable: "10")
        }
        let netlist = TensorLUTNetlist(
            luts: luts,
            totalWires: 2,
            executionLevels: [luts.indices.map { Int32($0) }]
        )
        XCTAssertNil(TensorLUTANERBooster(netlist: netlist))
    }

    func testPipelineXORRunsOnTheNeuralEngine() throws {
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
            totalWires: 3,
            executionLevels: [[0]]
        )
        let pipeline = try TensorLUTPipeline(device: device, netlist: netlist)
        let initData = netlist.packedINITBuffer()
        guard let initsBuffer = device.makeBuffer(
            bytes: initData,
            length: initData.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ), let wireBuffer = device.makeBuffer(
            bytes: [Float](arrayLiteral:
                0, 0, 0,
                1, 0, 0,
                0, 1, 0,
                1, 1, 0
            ),
            length: 12 * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else {
            return XCTFail("Failed to allocate TensorLUT buffers")
        }

        pipeline.evaluateForward(
            totalWires: netlist.totalWires,
            initsBuffer: initsBuffer,
            wireBuffer: wireBuffer,
            batchSize: 4
        )

        XCTAssertTrue(pipeline.forwardUsedNeuralEngine)
        let output = wireBuffer.contents().bindMemory(to: Float.self, capacity: 12)
        XCTAssertEqual(output[2], 0, accuracy: 1e-4)
        XCTAssertEqual(output[5], 1, accuracy: 1e-4)
        XCTAssertEqual(output[8], 1, accuracy: 1e-4)
        XCTAssertEqual(output[11], 0, accuracy: 1e-4)
    }

    func testBatchPastOneTileStaysOnMetal() throws {
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
            totalWires: 3,
            executionLevels: [[0]]
        )
        let pipeline = try TensorLUTPipeline(device: device, netlist: netlist)
        let batch = TensorLUTANERBooster.maxBoostBatch + 1
        let initData = netlist.packedINITBuffer()
        var wires = [Float](repeating: 0, count: batch * 3)
        for sample in 0..<batch {
            wires[sample * 3] = (sample & 1) == 0 ? 0 : 1
            wires[sample * 3 + 1] = (sample & 2) == 0 ? 0 : 1
        }
        guard let initsBuffer = device.makeBuffer(
            bytes: initData,
            length: initData.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ), let wireBuffer = device.makeBuffer(
            bytes: wires,
            length: wires.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else {
            return XCTFail("Failed to allocate TensorLUT buffers")
        }

        pipeline.evaluateForward(
            totalWires: netlist.totalWires,
            initsBuffer: initsBuffer,
            wireBuffer: wireBuffer,
            batchSize: batch
        )

        XCTAssertFalse(pipeline.forwardUsedNeuralEngine)
        let output = wireBuffer.contents().bindMemory(to: Float.self, capacity: wires.count)
        for sample in stride(from: 0, to: batch, by: 16) {
            let a = (sample & 1) == 0 ? Float(0) : 1
            let b = (sample & 2) == 0 ? Float(0) : 1
            XCTAssertEqual(output[sample * 3 + 2], a == b ? 0 : 1, accuracy: 1e-4)
        }
    }
}
