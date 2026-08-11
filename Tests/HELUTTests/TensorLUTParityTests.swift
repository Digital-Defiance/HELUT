import Metal
import XCTest
@testable import HELUTCore

final class TensorLUTParityTests: XCTestCase {

    func testBinaryParityWithXOR() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device not available")
        }

        // Yosys MSB-first string for 2-input XOR (table[00,01,10,11] = 0,1,1,0).
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
        ) else {
            return XCTFail("Failed to allocate INIT buffer")
        }

        // Batch of 4: [0,0], [1,0], [0,1], [1,1] on wires [A, B, OUT]
        let wiresData: [Float] = [
            0.0, 0.0, 0.0,
            1.0, 0.0, 0.0,
            0.0, 1.0, 0.0,
            1.0, 1.0, 0.0
        ]

        guard let wireBuffer = device.makeBuffer(
            bytes: wiresData,
            length: wiresData.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else {
            return XCTFail("Failed to allocate wire buffer")
        }

        pipeline.evaluateForward(
            totalWires: netlist.totalWires,
            initsBuffer: initsBuffer,
            wireBuffer: wireBuffer,
            batchSize: 4
        )

        let outputPtr = wireBuffer.contents().bindMemory(to: Float.self, capacity: 12)
        let accuracy: Float = 1e-5

        XCTAssertEqual(outputPtr[2], 0.0, accuracy: accuracy, "0 XOR 0")
        XCTAssertEqual(outputPtr[5], 1.0, accuracy: accuracy, "1 XOR 0")
        XCTAssertEqual(outputPtr[8], 1.0, accuracy: accuracy, "0 XOR 1")
        XCTAssertEqual(outputPtr[11], 0.0, accuracy: accuracy, "1 XOR 1")
    }

    func testPadBroadcastMatchesCleartextWidth2() {
        // WIDTH=2 AND: Yosys MSB-first leftmost = A=all-1s → "1000".
        let andLUT = TensorLUT6Cell(
            cellID: 1,
            inputWires: [0, 1],
            outputWire: 2,
            rawTruthTable: "1000"
        )
        XCTAssertEqual(andLUT.entries.count, 64)
        XCTAssertEqual(andLUT.entries[0], 0)
        XCTAssertEqual(andLUT.entries[1], 0)
        XCTAssertEqual(andLUT.entries[2], 0)
        XCTAssertEqual(andLUT.entries[3], 1)
        // Broadcast: entry 7 (111b) ≡ 7 % 4 = 3 → 1
        XCTAssertEqual(andLUT.entries[7], 1)
        XCTAssertEqual(andLUT.in2, -1)
        XCTAssertEqual(andLUT.in5, -1)
    }
}
