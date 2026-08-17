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

/// Can the committed 925-LUT baseline artifact be regenerated?
///
/// C8 carried this as an open gap: `enigma_m4_tensorlut_baseline.v` was produced
/// by `--emit-tensorlut-verilog --emit-out`, those flags were dropped in the
/// packaging split, and afterwards `TensorLUTEmitter` was reachable only from
/// library code and an `enigma_256_*`-specific path. The artifact's own header
/// records the loss. So the file sat in the repo as an asserted result that
/// nothing could reproduce — the weakest kind of receipt.
///
/// The generic path is restored (`TensorLUTGenericEmit`). This test is the proof
/// it produces the same artifact rather than merely producing *something*: it
/// compares the emitted module body against the committed file line by line, and
/// separately compares all 925 INIT words, which are the actual logic content.
final class TensorLUTBaselineRegenerationTests: XCTestCase {

    private func repoFile(_ name: String) -> String? {
        let fm = FileManager.default
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            url.deleteLastPathComponent()
            let candidate = url.appendingPathComponent(name).path
            if fm.fileExists(atPath: candidate) { return candidate }
        }
        return nil
    }

    /// Emitting from the source netlist must reproduce the committed baseline.
    ///
    /// Two port details had to be right, and getting either wrong shifts every
    /// signal in the file:
    ///
    ///  - `clk` is declared by the emitter itself, so passing the clock net
    ///    through `inputWires` too declares it twice. The first attempt did that
    ///    and produced 9 inputs' worth of logic under 10 input declarations.
    ///  - ports are ordered by net id, not by port name. Both are deterministic;
    ///    only the former matches what the original emit recorded (`in_3 … in_11`).
    func testEmitReproducesCommittedM4Baseline() throws {
        guard let netlistPath = repoFile("enigma_m4_netlist.json"),
              let committedPath = repoFile("enigma_m4_tensorlut_baseline.v")
        else {
            throw XCTSkip("enigma_m4 netlist / baseline artifact not present")
        }

        let yosys = loadYosysNetlist(from: netlistPath)
        guard let (_, module) = yosys.modules.first(where: { !$0.value.cells.isEmpty })
        else {
            return XCTFail("no module with cells in enigma_m4_netlist.json")
        }

        let netlist = TensorLUTCompiler.compile(module: module)
        let chromosome = TensorChromosome.from(netlist: netlist)

        // Same derivation the CLI uses; kept in the test so a change to either
        // side shows up as a diff rather than as a silently different artifact.
        let clockNames: Set<String> = ["clk", "clock", "clk_i", "i_clk"]
        func wires(direction: String, dropClock: Bool) -> [Int32] {
            var out: Set<Int32> = []
            for (name, port) in module.ports where port.direction == direction {
                if dropClock, clockNames.contains(name.lowercased()) { continue }
                for bit in port.bits {
                    if case .net(let id) = bit { out.insert(Int32(id)) }
                }
            }
            return out.sorted()
        }

        XCTAssertEqual(netlist.luts.count, 925, "LUT count drifted from the artifact header")
        XCTAssertEqual(netlist.dffs.count, 49, "DFF count drifted from the artifact header")
        XCTAssertEqual(chromosome.inits.count, 59_200, "INIT float count drifted")

        let emitted = TensorLUTEmitter.emitVerilog(
            moduleName: "enigma_m4_tensorlut_baseline",
            netlist: netlist,
            chromosome: chromosome,
            inputWires: wires(direction: "input", dropClock: true),
            outputWires: wires(direction: "output", dropClock: false)
        )

        let committedFull = try String(contentsOfFile: committedPath, encoding: .utf8)
        let marker = "module enigma_m4_tensorlut_baseline"
        guard let cRange = committedFull.range(of: marker),
              let eRange = emitted.range(of: marker)
        else {
            return XCTFail("module header not found in one of the two files")
        }
        // Compare bodies only: the committed header carries provenance prose and
        // a behavioural LUT6 model that the emitter does not produce.
        let committedBody = String(committedFull[cRange.lowerBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let emittedBody = String(emitted[eRange.lowerBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if committedBody != emittedBody {
            let cl = committedBody.split(separator: "\n", omittingEmptySubsequences: false)
            let el = emittedBody.split(separator: "\n", omittingEmptySubsequences: false)
            let firstDiff = zip(cl, el).enumerated().first { $0.element.0 != $0.element.1 }
            XCTFail(
                """
                regenerated baseline differs from the committed artifact. \
                lines \(cl.count) vs \(el.count).
                first differing line \(firstDiff?.offset ?? -1):
                  committed: \(firstDiff?.element.0 ?? "-")
                  emitted:   \(firstDiff?.element.1 ?? "-")
                """
            )
        }

        // The logic content, checked independently of formatting.
        let initPattern = #"64'h([0-9A-F]{16})"#
        func initWords(_ s: String) -> [String] {
            let re = try! NSRegularExpression(pattern: initPattern)
            let ns = s as NSString
            return re.matches(in: s, range: NSRange(location: 0, length: ns.length))
                .map { ns.substring(with: $0.range(at: 1)) }
        }
        let committedInits = initWords(committedBody)
        let emittedInits = initWords(emittedBody)
        XCTAssertEqual(committedInits.count, 925)
        XCTAssertEqual(
            committedInits, emittedInits,
            "INIT tables differ — the emitted logic is not the committed logic"
        )
        print("TENSORLUT_BASELINE regenerated: 925 LUTs, 925/925 INIT words identical")
    }
}
