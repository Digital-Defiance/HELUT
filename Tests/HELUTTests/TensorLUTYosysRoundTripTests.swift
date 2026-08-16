import XCTest
@testable import HELUTCore

/// Does the emitted Verilog actually mean what we say it means?
///
/// `testEmitVerilogTwoBitAdderStructure` checks the emitter's *string* output:
/// that a module header appears, that four `LUT6 #(` blocks appear, that an INIT
/// hex digit lands where expected. That is a formatting test. It cannot tell you
/// whether a synthesis tool accepts the file, and it cannot tell you whether the
/// synthesized result computes the same function as the netlist it came from.
/// C8's honest gap.
///
/// This closes the loop: emit Verilog, hand it back to Yosys, re-synthesize to
/// `$lut` cells, reload through the repo's own Yosys loader, and require the
/// re-synthesized netlist to agree with direct evaluation of the source netlist
/// on **every** input assignment. Exhaustive over 4 inputs, so agreement is proof
/// rather than sampling.
final class TensorLUTYosysRoundTripTests: XCTestCase {

    /// Behavioural `LUT6` so the round-trip does not depend on where a given
    /// Yosys install keeps its Xilinx simulation library.
    private static let lut6Model = """
    // Behavioural LUT6, sufficient for re-reading emitted TensorLUT Verilog.
    // INIT is LSB-first: bit k is the output for address k.
    module LUT6 (output O, input I0, I1, I2, I3, I4, I5);
        parameter [63:0] INIT = 64'h0000000000000000;
        wire [5:0] addr = {I5, I4, I3, I2, I1, I0};
        assign O = INIT[addr];
    endmodule
    """

    /// The same four-LUT design the string-level emitter test uses, so the two
    /// tests are talking about the same artifact.
    private func sourceNetlist() -> TensorLUTNetlist {
        TensorLUTNetlist(
            luts: [
                TensorLUT6Cell(cellID: 0, inputWires: [0, 2], outputWire: 5, rawTruthTable: "0110"),
                TensorLUT6Cell(cellID: 1, inputWires: [0, 2], outputWire: 4, rawTruthTable: "1000"),
                TensorLUT6Cell(
                    cellID: 2, inputWires: [1, 3, 4], outputWire: 6, rawTruthTable: "10010110"
                ),
                TensorLUT6Cell(
                    cellID: 3, inputWires: [1, 3, 4], outputWire: 7, rawTruthTable: "11101000"
                )
            ],
            dffs: [],
            totalWires: 8,
            executionLevels: [[0, 1], [2, 3]]
        )
    }

    /// Reference evaluation straight off the TensorLUT cells, level by level.
    /// Deliberately independent of the emitter and of Yosys.
    ///
    /// Reads `entries` rather than re-deriving from `rawTruthTable`: `entries` is
    /// the 64-float INIT indexed directly by address (bit k = output at address
    /// k), which is exactly what `initHex` serialises, whereas `rawTruthTable` is
    /// stored MSB-first and would need reversing. Unused LUT inputs are −1 and
    /// contribute 0, matching the emitter's `wireRef` mapping them to `1'b0`.
    private func evaluateSource(
        _ netlist: TensorLUTNetlist,
        inputs: [Int32: UInt8]
    ) -> [Int32: UInt8] {
        var wires = [Int32: UInt8]()
        for (w, v) in inputs { wires[w] = v }
        for level in netlist.executionLevels {
            for cellID in level {
                guard let cell = netlist.luts.first(where: { $0.cellID == cellID }) else { continue }
                let pins = [cell.in0, cell.in1, cell.in2, cell.in3, cell.in4, cell.in5]
                var address = 0
                for (bit, w) in pins.enumerated() where w >= 0 {
                    if (wires[w] ?? 0) != 0 { address |= (1 << bit) }
                }
                wires[cell.outWire] = cell.entries[address] >= 0.5 ? 1 : 0
            }
        }
        return wires
    }

    private func yosysPath() -> String? {
        for candidate in ["/opt/homebrew/bin/yosys", "/usr/local/bin/yosys", "/usr/bin/yosys"] {
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    @discardableResult
    private func run(_ launch: String, _ args: [String], cwd: URL) throws -> (Int32, String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launch)
        proc.arguments = args
        proc.currentDirectoryURL = cwd
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        try proc.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return (proc.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    func testEmittedVerilogResynthesizesToEquivalentNetlist() throws {
        guard let yosys = yosysPath() else {
            throw XCTSkip(
                "yosys not found — install it (brew install yosys) to exercise the "
                    + "emit → synthesize → reload → compare loop. See REPRODUCE.md."
            )
        }

        let netlist = sourceNetlist()
        let chromosome = TensorChromosome.from(netlist: netlist)
        let inputWires: [Int32] = [0, 1, 2, 3]
        let outputWires: [Int32] = [5, 6, 7]
        let verilog = TensorLUTEmitter.emitVerilog(
            moduleName: "two_bit_adder",
            netlist: netlist,
            chromosome: chromosome,
            inputWires: inputWires,
            outputWires: outputWires
        )

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("helut-tensorlut-roundtrip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try verilog.write(
            to: dir.appendingPathComponent("emitted.v"), atomically: true, encoding: .utf8
        )
        try Self.lut6Model.write(
            to: dir.appendingPathComponent("lut6.v"), atomically: true, encoding: .utf8
        )

        // Re-synthesize back down to $lut cells. Shared with the negative control
        // so the two cannot drift apart.
        try Self.yosysScript.write(
            to: dir.appendingPathComponent("flow.ys"), atomically: true, encoding: .utf8
        )

        let (status, log) = try run(yosys, ["-q", "flow.ys"], cwd: dir)
        XCTAssertEqual(
            status, 0,
            """
            yosys rejected the emitted Verilog — the emitter produces text that \
            does not synthesize. Log:
            \(log.suffix(3000))
            """
        )

        let jsonPath = dir.appendingPathComponent("resynth.json").path
        guard FileManager.default.fileExists(atPath: jsonPath) else {
            return XCTFail("yosys wrote no resynth.json. Log:\n\(log.suffix(2000))")
        }

        let reloaded = loadYosysNetlist(from: jsonPath)
        guard let (moduleName, module) = reloaded.modules
            .first(where: { !$0.value.cells.isEmpty })
            .map({ ($0.key, $0.value) })
        else {
            return XCTFail("re-synthesized netlist has no module with cells")
        }

        // Exhaustive over the 4 primary inputs: agreement here is proof, not
        // sampling.
        var sim = CleartextNetlistSimulator(moduleName: moduleName, module: module)
        var compared = 0
        for pattern in 0..<16 {
            var sourceInputs = [Int32: UInt8]()
            var simInputs = [String: [UInt8]]()
            for (bit, wire) in inputWires.enumerated() {
                let value = UInt8((pattern >> bit) & 1)
                sourceInputs[wire] = value
                simInputs["in_\(wire)"] = [value]
            }

            let expectedWires = evaluateSource(netlist, inputs: sourceInputs)
            let got = try sim.tick(inputs: simInputs)

            for wire in outputWires {
                guard let actual = got["out_\(wire)"]?.first else {
                    return XCTFail(
                        "re-synthesized module lacks out_\(wire); ports: "
                            + "\(got.keys.sorted())"
                    )
                }
                let expected = expectedWires[wire] ?? 0
                XCTAssertEqual(
                    actual, expected,
                    """
                    round-trip mismatch at inputs \(String(pattern, radix: 2)) \
                    on out_\(wire): emitted+resynthesized gave \(actual), source \
                    netlist gives \(expected). The emitted Verilog does not mean \
                    what the TensorLUT netlist means.
                    """
                )
                compared += 1
            }
        }
        XCTAssertEqual(compared, 16 * outputWires.count)
        print(
            "TENSORLUT_ROUNDTRIP ok: \(compared) output bits over 16 input "
                + "assignments, yosys-resynthesized vs source netlist"
        )
    }

    /// Test of the test. An equivalence check that cannot fail proves nothing, so
    /// corrupt one INIT bit and require the round-trip to *notice*.
    ///
    /// The corruption is deliberately minimal — a single entry in a single LUT —
    /// because that is the weakest signal the harness must still catch. If Yosys
    /// optimised the emitted design down to something that ignored INIT, or if
    /// the comparison were reading the wrong ports, this test would pass
    /// silently and the positive result above would be worthless.
    func testRoundTripDetectsACorruptedInitBit() throws {
        guard let yosys = yosysPath() else {
            throw XCTSkip("yosys not found — see REPRODUCE.md")
        }

        let netlist = sourceNetlist()
        var chromosome = TensorChromosome.from(netlist: netlist)
        let inputWires: [Int32] = [0, 1, 2, 3]
        let outputWires: [Int32] = [5, 6, 7]

        // Flip one address of LUT 0 (drives out_5 directly).
        let target = 0
        let before = chromosome.inits[target]
        chromosome.inits[target] = before >= 0.5 ? 0.0 : 1.0
        XCTAssertNotEqual(chromosome.inits[target], before)

        let verilog = TensorLUTEmitter.emitVerilog(
            moduleName: "two_bit_adder",
            netlist: netlist,
            chromosome: chromosome,
            inputWires: inputWires,
            outputWires: outputWires
        )

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("helut-tensorlut-negctl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try verilog.write(
            to: dir.appendingPathComponent("emitted.v"), atomically: true, encoding: .utf8
        )
        try Self.lut6Model.write(
            to: dir.appendingPathComponent("lut6.v"), atomically: true, encoding: .utf8
        )
        try Self.yosysScript.write(
            to: dir.appendingPathComponent("flow.ys"), atomically: true, encoding: .utf8
        )

        let (status, log) = try run(yosys, ["-q", "flow.ys"], cwd: dir)
        XCTAssertEqual(status, 0, "yosys failed on the corrupted design:\n\(log.suffix(2000))")

        let reloaded = loadYosysNetlist(from: dir.appendingPathComponent("resynth.json").path)
        guard let (moduleName, module) = reloaded.modules
            .first(where: { !$0.value.cells.isEmpty })
            .map({ ($0.key, $0.value) })
        else {
            return XCTFail("re-synthesized corrupted netlist has no module with cells")
        }

        var sim = CleartextNetlistSimulator(moduleName: moduleName, module: module)
        var mismatches = 0
        for pattern in 0..<16 {
            var sourceInputs = [Int32: UInt8]()
            var simInputs = [String: [UInt8]]()
            for (bit, wire) in inputWires.enumerated() {
                let value = UInt8((pattern >> bit) & 1)
                sourceInputs[wire] = value
                simInputs["in_\(wire)"] = [value]
            }
            // Compare against the *uncorrupted* source netlist.
            let expectedWires = evaluateSource(netlist, inputs: sourceInputs)
            let got = try sim.tick(inputs: simInputs)
            for wire in outputWires {
                if got["out_\(wire)"]?.first != (expectedWires[wire] ?? 0) { mismatches += 1 }
            }
        }

        XCTAssertGreaterThan(
            mismatches, 0,
            """
            flipping one INIT bit produced no observable difference after \
            emit → yosys → reload. The equivalence check has no teeth, so the \
            positive round-trip result cannot be trusted either.
            """
        )
        print("TENSORLUT_ROUNDTRIP negative control: \(mismatches) mismatch(es) detected")
    }

    /// Shared Yosys flow. `abc -lut 6` lands on `$lut` cells, which is the form
    /// the repo's own loader consumes and the same mapping used for the PicoRV
    /// work.
    private static let yosysScript = """
    read_verilog lut6.v
    read_verilog emitted.v
    hierarchy -top two_bit_adder
    proc
    flatten
    opt
    techmap
    opt
    abc -lut 6
    opt_clean
    write_json resynth.json
    """
}
