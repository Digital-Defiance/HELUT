import XCTest
@testable import HELUTCore

final class TensorLUTEmitterTests: XCTestCase {

    /// INIT hex LSB/MSB must mirror TensorLUT / CleartextNetlistSim LSB-first tables.
    func testInitHexRoundTripMatchesCleartextDecode() {
        // Yosys MSB-first "0110" → table[0..3] = 0,1,1,0 (XOR)
        let xor = TensorLUT6Cell(
            cellID: 0,
            inputWires: [0, 1],
            outputWire: 2,
            rawTruthTable: "0110"
        )
        XCTAssertEqual(Array(xor.entries.prefix(4)), [0, 1, 1, 0])

        let hex = TensorLUTEmitter.initHex(entries: xor.entries[...])
        XCTAssertEqual(hex.count, 16)

        // Rightmost nibble encodes INIT[3:0] = {e3,e2,e1,e0} as bits 3..0 → 0b0110 = 6
        XCTAssertEqual(hex.last, "6")

        let recovered = TensorLUTEmitter.entriesFromInitHex(hex)
        for i in 0..<64 {
            XCTAssertEqual(recovered[i], xor.entries[i] >= 0.5 ? 1 : 0, accuracy: 0, "bit \(i)")
        }

        // CleartextNetlistSim-style address decode on recovered live bits
        for mask in 0..<4 {
            let expected: Float = [0, 1, 1, 0][mask]
            XCTAssertEqual(recovered[mask], expected)
        }
    }

    func testEmitVerilogTwoBitAdderStructure() {
        let luts = [
            TensorLUT6Cell(cellID: 0, inputWires: [0, 2], outputWire: 5, rawTruthTable: "0110"),
            TensorLUT6Cell(cellID: 1, inputWires: [0, 2], outputWire: 4, rawTruthTable: "1000"),
            TensorLUT6Cell(cellID: 2, inputWires: [1, 3, 4], outputWire: 6, rawTruthTable: "10010110"),
            TensorLUT6Cell(cellID: 3, inputWires: [1, 3, 4], outputWire: 7, rawTruthTable: "11101000")
        ]
        let netlist = TensorLUTNetlist(
            luts: luts,
            dffs: [],
            totalWires: 8,
            executionLevels: [[0, 1], [2, 3]]
        )
        let chromo = TensorChromosome.from(netlist: netlist)
        let verilog = TensorLUTEmitter.emitVerilog(
            moduleName: "two_bit_adder",
            netlist: netlist,
            chromosome: chromo,
            inputWires: [0, 1, 2, 3],
            outputWires: [5, 6, 7]
        )

        XCTAssertTrue(verilog.contains("module two_bit_adder ("))
        XCTAssertTrue(verilog.contains("input wire in_0;"))
        XCTAssertTrue(verilog.contains("output wire out_5;"))
        XCTAssertTrue(verilog.contains("wire [7:0] n;"))
        XCTAssertEqual(verilog.components(separatedBy: "LUT6 #(").count - 1, 4)
        XCTAssertTrue(verilog.contains(".INIT(64'h"))
        XCTAssertTrue(verilog.contains("endmodule"))

        // LUT0 XOR INIT must end with nibble 6 (bits 3:0 = 0110)
        let lut0Hex = TensorLUTEmitter.initHex(entries: chromo.inits[0..<64])
        XCTAssertEqual(lut0Hex.last, "6")
        XCTAssertTrue(verilog.contains("64'h\(lut0Hex)"))
    }
}
