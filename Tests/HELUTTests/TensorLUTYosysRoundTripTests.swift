import Metal
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

    // MARK: - Searched elite → synthesis → independent proof

    /// The melt fixture from `TensorFreezeMaskTests.testTwoBitAdderTargetedMeltDiscovers`:
    /// a two-bit adder whose carry stage has been erased to all-zero tables.
    ///
    /// LUT0 (low sum, XOR) and LUT1 (low carry, AND) are the frozen known-good
    /// half. LUT2/LUT3 are declared all-zero, so there is no correct answer
    /// hiding underneath the wipe — the search has to discover the carry logic,
    /// not remember it.
    private func meltedAdderNetlist() -> TensorLUTNetlist {
        TensorLUTNetlist(
            luts: [
                TensorLUT6Cell(cellID: 0, inputWires: [0, 2], outputWire: 5, rawTruthTable: "0110"),
                TensorLUT6Cell(cellID: 1, inputWires: [0, 2], outputWire: 4, rawTruthTable: "1000"),
                TensorLUT6Cell(
                    cellID: 2, inputWires: [1, 3, 4], outputWire: 6,
                    rawTruthTable: String(repeating: "0", count: 8)
                ),
                TensorLUT6Cell(
                    cellID: 3, inputWires: [1, 3, 4], outputWire: 7,
                    rawTruthTable: String(repeating: "0", count: 8)
                )
            ],
            dffs: [],
            totalWires: 8,
            executionLevels: [[0, 1], [2, 3]]
        )
    }

    /// Exhaustive two-bit addition: all 16 operand pairs, three output bits.
    /// Same construction as the freeze-mask suite so both talk about one function.
    private func adderTarget() -> AdversarialTarget {
        var inputs = [[Float]]()
        var expected = [[Float]]()
        for a in 0..<4 {
            for b in 0..<4 {
                inputs.append([
                    Float(a & 1), Float((a >> 1) & 1), Float(b & 1), Float((b >> 1) & 1)
                ])
                let sum = a + b
                expected.append([
                    Float(sum & 1), Float((sum >> 1) & 1), Float((sum >> 2) & 1)
                ])
            }
        }
        return AdversarialTarget(
            inputWireIDs: [0, 1, 2, 3],
            outputWireIDs: [5, 6, 7],
            inputVectors: inputs,
            expectedOutputs: expected,
            clockTicks: 0
        )
    }

    /// Runs the same deterministic targeted melt the freeze-mask suite runs, then
    /// hands the elite back so it can be pushed through synthesis. Configuration
    /// is copied verbatim from `testTwoBitAdderTargetedMeltDiscovers` so a change
    /// on either side shows up as a divergence rather than as two unrelated runs.
    private func searchMeltedCarry(
        device: MTLDevice,
        netlist: TensorLUTNetlist,
        target: AdversarialTarget,
        seed: [Float],
        freeze: [Bool]
    ) throws -> TensorChromosome {
        let pipeline = try TensorLUTPipeline(device: device, netlist: netlist)
        let synth = try AdversarialSynthesizer(
            device: device,
            config: .init(
                mutationRate: 0.2,
                maxNoise: 0.4,
                lambdaMax: 12,
                liveWidths: [2, 2, 3, 3],
                lambdaDelayFraction: 0.1,
                discreteJumpRate: 0.4
            )
        )
        let harness = AdversarialHarness(
            device: device,
            pipeline: pipeline,
            synthesizer: synth,
            netlist: netlist
        )
        return harness.run(
            target: target,
            config: .init(
                populationSize: 48,
                generations: 120,
                eliteCount: 6,
                seedScatter: true,
                rngSeed: 0x7A6E17,
                seedInits: seed,
                crossoverRate: 0.55,
                polishBinaryAtEnd: true,
                freezeMask: freeze
            )
        )
    }

    /// emit → yosys → `abc -lut 6` → reload → compare against the **target truth
    /// table**, exhaustively.
    ///
    /// The reference is the target rather than the source netlist, and that is the
    /// whole point of this path. The source netlist's carry tables are erased, so
    /// it computes the wrong function by construction; comparing against it would
    /// assert that the search failed. Comparing against the target asserts the
    /// stronger claim: the re-synthesized circuit *is* a two-bit adder.
    ///
    /// Returns counts instead of asserting so the positive result and the negative
    /// control share one code path and cannot drift apart.
    private func resynthesizeAgainstTarget(
        yosys: String,
        netlist: TensorLUTNetlist,
        chromosome: TensorChromosome,
        target: AdversarialTarget,
        tag: String
    ) throws -> (compared: Int, mismatches: Int) {
        let verilog = TensorLUTEmitter.emitVerilog(
            moduleName: "two_bit_adder",
            netlist: netlist,
            chromosome: chromosome,
            inputWires: target.inputWireIDs,
            outputWires: target.outputWireIDs
        )

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("helut-tensorlut-\(tag)-\(UUID().uuidString)")
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
        guard status == 0 else {
            XCTFail("yosys rejected the emitted design (\(tag)):\n\(log.suffix(3000))")
            return (0, 0)
        }

        let jsonPath = dir.appendingPathComponent("resynth.json").path
        guard FileManager.default.fileExists(atPath: jsonPath) else {
            XCTFail("yosys wrote no resynth.json (\(tag)). Log:\n\(log.suffix(2000))")
            return (0, 0)
        }

        let reloaded = loadYosysNetlist(from: jsonPath)
        guard let (moduleName, module) = reloaded.modules
            .first(where: { !$0.value.cells.isEmpty })
            .map({ ($0.key, $0.value) })
        else {
            XCTFail("re-synthesized netlist has no module with cells (\(tag))")
            return (0, 0)
        }

        let sim = CleartextNetlistSimulator(moduleName: moduleName, module: module)
        var compared = 0
        var mismatches = 0
        for row in 0..<target.batchSize {
            var simInputs = [String: [UInt8]]()
            for (i, wire) in target.inputWireIDs.enumerated() {
                simInputs["in_\(wire)"] = [UInt8(target.inputVectors[row][i] >= 0.5 ? 1 : 0)]
            }
            let got = sim.tick(inputs: simInputs)
            for (j, wire) in target.outputWireIDs.enumerated() {
                guard let actual = got["out_\(wire)"]?.first else {
                    XCTFail(
                        "re-synthesized module lacks out_\(wire) (\(tag)); ports: "
                            + "\(got.keys.sorted())"
                    )
                    return (compared, mismatches)
                }
                let expected = UInt8(target.expectedOutputs[row][j] >= 0.5 ? 1 : 0)
                if actual != expected { mismatches += 1 }
                compared += 1
            }
        }
        return (compared, mismatches)
    }

    /// The join Episode 15 admits is missing: a *searched* elite emitted as
    /// Verilog, re-synthesized by Yosys, reloaded, and proven against the target
    /// function by a checker that had no part in the search.
    ///
    /// Three gates, in order, because the middle one alone would be weak:
    ///
    ///  1. The erased starting design must **fail** the target. Without this a
    ///     skeptic can say the adder was already correct and the search did
    ///     nothing.
    ///  2. The searched elite must pass on all 16 assignments × 3 outputs after
    ///     an independent synthesis round trip.
    ///  3. Frozen tables must be byte-identical and the genome fully binary, so
    ///     the artifact under test is the elite itself and not a thresholded
    ///     reinterpretation of it.
    ///
    /// What this does not establish: topology change, area or depth improvement
    /// over Yosys/ABC, or anything about designs larger than this fixture.
    func testSearchedEliteResynthesizesToTargetFunction() throws {
        guard let yosys = yosysPath() else {
            throw XCTSkip(
                "yosys not found — install it (brew install yosys) to exercise the "
                    + "search → emit → synthesize → reload → prove loop. See REPRODUCE.md."
            )
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device not available")
        }

        let netlist = meltedAdderNetlist()
        let target = adderTarget()
        var seed = netlist.packedINITBuffer()
        for i in (2 * 64)..<(4 * 64) { seed[i] = 0.5 }
        let freeze = TensorFreezeMask.meltOnly(lutCount: 4, indices: [2, 3])

        // Gate 1: the erased design must not already compute the target.
        let erased = try resynthesizeAgainstTarget(
            yosys: yosys,
            netlist: netlist,
            chromosome: TensorChromosome.from(netlist: netlist),
            target: target,
            tag: "erased"
        )
        XCTAssertGreaterThan(
            erased.mismatches, 0,
            """
            the erased starting design already satisfies the target after \
            synthesis, so the fixture is not actually melted and a later pass \
            would prove nothing about the search.
            """
        )

        let best = try searchMeltedCarry(
            device: device, netlist: netlist, target: target, seed: seed, freeze: freeze
        )

        // Gate 3a: the freeze mask has to have held all the way through.
        XCTAssertEqual(
            Array(best.inits[0..<128]), Array(seed[0..<128]),
            "frozen XOR/AND tables were modified; the freeze mask leaked"
        )

        // Gate 3b: `initHex` snaps at 0.5 silently, so a fractional genome would
        // be reinterpreted on the way out and the round trip would prove
        // something about the snapped design rather than about the elite.
        let fractional = AdversarialHarness.nonBinaryCount(best.inits)
        XCTAssertEqual(
            fractional, 0,
            """
            \(fractional) genome entries are still fractional, so emission would \
            silently threshold them. Re-prove only fully frozen chromosomes.
            """
        )

        // Gate 2: the searched circuit, independently re-synthesized.
        let result = try resynthesizeAgainstTarget(
            yosys: yosys,
            netlist: netlist,
            chromosome: best,
            target: target,
            tag: "searched"
        )
        XCTAssertEqual(result.compared, target.batchSize * target.outputWireIDs.count)
        XCTAssertEqual(
            result.mismatches, 0,
            """
            the searched elite does not compute the target after emit → yosys → \
            reload. Either the search result is wrong, or emission/synthesis does \
            not preserve it.
            """
        )
        print(
            "TENSORLUT_SEARCHED_ROUNDTRIP ok: erased design failed \(erased.mismatches) "
                + "of \(erased.compared) bits; searched elite agrees on "
                + "\(result.compared)/\(result.compared) output bits over "
                + "\(target.batchSize) input assignments, yosys-resynthesized vs target"
        )
    }

    /// Teeth for the joined path. The searched elite is corrupted in the region
    /// the search itself discovered, and the round trip must notice.
    ///
    /// Separate from the identity negative control on purpose: that one proves the
    /// checker catches damage to a hand-written table, this one proves it catches
    /// damage to a *discovered* one.
    func testSearchedEliteRoundTripDetectsCorruption() throws {
        guard let yosys = yosysPath() else {
            throw XCTSkip("yosys not found — see REPRODUCE.md")
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device not available")
        }

        let netlist = meltedAdderNetlist()
        let target = adderTarget()
        var seed = netlist.packedINITBuffer()
        for i in (2 * 64)..<(4 * 64) { seed[i] = 0.5 }
        let freeze = TensorFreezeMask.meltOnly(lutCount: 4, indices: [2, 3])

        var best = try searchMeltedCarry(
            device: device, netlist: netlist, target: target, seed: seed, freeze: freeze
        )

        // Flip one discovered entry: LUT2, address 0. Reachable whenever the high
        // operand bits and the incoming carry are all zero, so it must surface.
        let corrupt = 2 * 64
        let before = best.inits[corrupt]
        best.inits[corrupt] = before >= 0.5 ? 0.0 : 1.0
        XCTAssertNotEqual(best.inits[corrupt], before)

        let result = try resynthesizeAgainstTarget(
            yosys: yosys,
            netlist: netlist,
            chromosome: best,
            target: target,
            tag: "searched-negctl"
        )
        XCTAssertGreaterThan(
            result.mismatches, 0,
            """
            corrupting a discovered INIT entry produced no observable difference \
            after emit → yosys → reload, so the joined equivalence check has no \
            teeth and its positive result cannot be trusted either.
            """
        )
        print(
            "TENSORLUT_SEARCHED_ROUNDTRIP negative control: \(result.mismatches) "
                + "mismatch(es) of \(result.compared) detected after one flipped "
                + "discovered entry"
        )
    }

    // MARK: - Formal equivalence (SAT), not enumeration

    /// Behavioural golden model. Uses Verilog `+` and knows nothing about lookup
    /// tables, so agreement with it is a statement about the *function*, not about
    /// a shared implementation.
    ///
    /// Port names must match the emitter's (`clk`, `in_<wire>`, `out_<wire>`)
    /// because `miter -equiv` pairs signals by name. Wire numbering follows
    /// `adderTarget()`: 0/1 are operand A low/high, 2/3 are operand B low/high,
    /// 5/6/7 are sum bits 0/1/2.
    private static let adderReference = """
    module two_bit_adder_ref (
        input clk,
        input in_0, in_1, in_2, in_3,
        output out_5, out_6, out_7
    );
        wire [1:0] a = {in_1, in_0};
        wire [1:0] b = {in_3, in_2};
        wire [2:0] s = a + b;
        assign out_5 = s[0];
        assign out_6 = s[1];
        assign out_7 = s[2];
    endmodule
    """

    /// Second Yosys pass: prove the re-synthesized `$lut` design equals the
    /// behavioural reference for **every** input, by SAT.
    ///
    /// Reads `resynth.json` rather than the emitted Verilog, so what gets proven
    /// is the post-`abc -lut 6` artifact — the same form the repo's own loader
    /// consumes. `miter -equiv` builds a comparator whose `trigger` output is 1
    /// exactly when the two disagree; proving `trigger` is unsatisfiable is the
    /// equivalence proof.
    ///
    /// Deliberately no `-verify`: that turns a failed proof into a Yosys error,
    /// which would make "the proof was refuted" indistinguishable from "Yosys
    /// broke". Without it, exit status reports infrastructure health and the log
    /// carries the verdict.
    private static let satEquivScript = """
    read_json resynth.json
    read_verilog reference.v
    proc
    opt
    miter -equiv -flatten two_bit_adder_ref two_bit_adder miter
    sat -prove trigger 0 -show-inputs -show-outputs miter
    """

    private enum ProofOutcome {
        /// SAT could not satisfy `trigger`: the designs agree on all inputs.
        case proved
        /// SAT found an input assignment where they differ.
        case refuted(log: String)
        /// Yosys did not get far enough to answer.
        case inconclusive(log: String)
    }

    /// Full chain: emit → synthesize → `abc -lut 6` → SAT-prove against the
    /// behavioural reference. Returns the verdict rather than asserting, so the
    /// positive test and the negative control share one path.
    private func proveAgainstReference(
        yosys: String,
        netlist: TensorLUTNetlist,
        chromosome: TensorChromosome,
        target: AdversarialTarget,
        tag: String
    ) throws -> ProofOutcome {
        let verilog = TensorLUTEmitter.emitVerilog(
            moduleName: "two_bit_adder",
            netlist: netlist,
            chromosome: chromosome,
            inputWires: target.inputWireIDs,
            outputWires: target.outputWireIDs
        )

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("helut-tensorlut-sat-\(tag)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try verilog.write(
            to: dir.appendingPathComponent("emitted.v"), atomically: true, encoding: .utf8
        )
        try Self.lut6Model.write(
            to: dir.appendingPathComponent("lut6.v"), atomically: true, encoding: .utf8
        )
        try Self.adderReference.write(
            to: dir.appendingPathComponent("reference.v"), atomically: true, encoding: .utf8
        )
        try Self.yosysScript.write(
            to: dir.appendingPathComponent("flow.ys"), atomically: true, encoding: .utf8
        )
        try Self.satEquivScript.write(
            to: dir.appendingPathComponent("prove.ys"), atomically: true, encoding: .utf8
        )

        let (synthStatus, synthLog) = try run(yosys, ["-q", "flow.ys"], cwd: dir)
        guard synthStatus == 0,
              FileManager.default.fileExists(atPath: dir.appendingPathComponent("resynth.json").path)
        else {
            return .inconclusive(log: "synthesis pass failed:\n\(synthLog.suffix(2000))")
        }

        let (proveStatus, proveLog) = try run(yosys, ["prove.ys"], cwd: dir)
        guard proveStatus == 0 else {
            return .inconclusive(log: "sat pass exited \(proveStatus):\n\(proveLog.suffix(2000))")
        }
        if proveLog.contains("no model found: SUCCESS") { return .proved }
        if proveLog.contains("model found: FAIL") { return .refuted(log: proveLog) }
        return .inconclusive(log: "no SAT verdict in log:\n\(proveLog.suffix(2000))")
    }

    /// The strongest form of the melt/freeze claim available today: the searched
    /// circuit is **formally** equivalent to behavioural two-bit addition, proven
    /// by SAT over the entire input space rather than by enumerating 16 rows.
    ///
    /// This matters beyond elegance. Enumeration is only tractable while the input
    /// space is small; at 24 inputs it is already 16.7 million rows. A SAT proof
    /// is the mechanism that lets the same claim scale to circuits where
    /// exhaustive checking is impossible, so validating it here — against a
    /// fixture whose answer is independently known — is the groundwork for that.
    func testSearchedEliteIsFormallyEquivalentToBehavioralAdder() throws {
        guard let yosys = yosysPath() else {
            throw XCTSkip("yosys not found — see REPRODUCE.md")
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device not available")
        }

        let netlist = meltedAdderNetlist()
        let target = adderTarget()
        var seed = netlist.packedINITBuffer()
        for i in (2 * 64)..<(4 * 64) { seed[i] = 0.5 }
        let freeze = TensorFreezeMask.meltOnly(lutCount: 4, indices: [2, 3])

        // The erased design must be formally *refutable*, or the fixture is not
        // actually broken and a later proof would be vacuous.
        switch try proveAgainstReference(
            yosys: yosys,
            netlist: netlist,
            chromosome: TensorChromosome.from(netlist: netlist),
            target: target,
            tag: "erased"
        ) {
        case .refuted:
            break
        case .proved:
            return XCTFail(
                "the erased design is already formally equivalent to the adder; "
                    + "the melt fixture is not melted"
            )
        case .inconclusive(let log):
            return XCTFail("could not evaluate the erased design: \(log)")
        }

        let best = try searchMeltedCarry(
            device: device, netlist: netlist, target: target, seed: seed, freeze: freeze
        )
        XCTAssertEqual(
            Array(best.inits[0..<128]), Array(seed[0..<128]),
            "frozen tables were modified; the freeze mask leaked"
        )
        XCTAssertEqual(
            AdversarialHarness.nonBinaryCount(best.inits), 0,
            "genome still fractional, so emission would silently threshold it"
        )

        switch try proveAgainstReference(
            yosys: yosys,
            netlist: netlist,
            chromosome: best,
            target: target,
            tag: "searched"
        ) {
        case .proved:
            print(
                "TENSORLUT_SAT_EQUIV ok: searched elite proven equivalent to "
                    + "behavioural two-bit addition over the entire input space "
                    + "(yosys miter + minisat, post abc -lut 6)"
            )
        case .refuted(let log):
            let counterexample = log
                .split(separator: "\n")
                .filter { $0.contains("in_") || $0.contains("out_") }
                .prefix(12)
                .joined(separator: "\n")
            XCTFail(
                """
                the searched elite is NOT equivalent to behavioural addition. \
                SAT counterexample:
                \(counterexample)
                """
            )
        case .inconclusive(let log):
            XCTFail("SAT proof did not reach a verdict: \(log)")
        }
    }

    /// Teeth for the formal path. A proof that cannot be refuted proves nothing,
    /// so corrupt one discovered entry and require SAT to produce a
    /// counterexample.
    func testFormalProofRefutesCorruptedSearchedElite() throws {
        guard let yosys = yosysPath() else {
            throw XCTSkip("yosys not found — see REPRODUCE.md")
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device not available")
        }

        let netlist = meltedAdderNetlist()
        let target = adderTarget()
        var seed = netlist.packedINITBuffer()
        for i in (2 * 64)..<(4 * 64) { seed[i] = 0.5 }
        let freeze = TensorFreezeMask.meltOnly(lutCount: 4, indices: [2, 3])

        var best = try searchMeltedCarry(
            device: device, netlist: netlist, target: target, seed: seed, freeze: freeze
        )
        let corrupt = 2 * 64
        best.inits[corrupt] = best.inits[corrupt] >= 0.5 ? 0.0 : 1.0

        switch try proveAgainstReference(
            yosys: yosys, netlist: netlist, chromosome: best, target: target, tag: "negctl"
        ) {
        case .refuted:
            print(
                "TENSORLUT_SAT_EQUIV negative control: SAT refuted the corrupted "
                    + "elite and produced a counterexample"
            )
        case .proved:
            XCTFail(
                """
                SAT proved a corrupted elite equivalent to the adder. The formal \
                check has no teeth, so its positive result cannot be trusted.
                """
            )
        case .inconclusive(let log):
            XCTFail("SAT proof did not reach a verdict on the corrupted elite: \(log)")
        }
    }

    // MARK: - Sequential melt → freeze → emit → prove

    /// One frozen identity LUT feeds one erased transition LUT. The DFF stores
    /// `q_next = q XOR x`, with active-high enable and active-low synchronous
    /// reset. Search sees a five-step stream that visits every live XOR address;
    /// formal proof then quantifies over both current-state values and every
    /// input/control combination.
    private func sequentialMeltFixture() -> (
        netlist: TensorLUTNetlist,
        target: AdversarialStreamTarget,
        seed: [Float],
        freeze: [Bool]
    ) {
        let netlist = TensorLUTNetlist(
            luts: [
                TensorLUT6Cell(
                    cellID: 0, inputWires: [0], outputWire: 2, rawTruthTable: "10"
                ),
                TensorLUT6Cell(
                    cellID: 1, inputWires: [2, 1], outputWire: 3, rawTruthTable: "0000"
                )
            ],
            dffs: [
                TensorDFFCell(
                    dWire: 3,
                    qWire: 1,
                    enableWire: 4,
                    resetWire: 5,
                    enableActiveHigh: 1,
                    resetActiveHigh: 0,
                    resetValue: 0
                )
            ],
            totalWires: 6,
            executionLevels: [[0], [1]]
        )
        let target = AdversarialStreamTarget(
            inputWireIDs: [0, 4, 5],
            outputWireIDs: [3],
            inputSequence: [
                [[0, 1, 1]],
                [[1, 1, 1]],
                [[0, 1, 1]],
                [[1, 1, 1]],
                [[0, 1, 1]]
            ],
            expectedSequence: [[[0]], [[1]], [[1]], [[0]], [[0]]],
            initialDFFStates: [1: 0]
        )
        var seed = netlist.packedINITBuffer()
        for i in 64..<128 { seed[i] = 0.5 }
        return (
            netlist,
            target,
            seed,
            TensorFreezeMask.meltOnly(lutCount: 2, indices: [1])
        )
    }

    private func searchSequentialTransition(
        device: MTLDevice,
        fixture: (
            netlist: TensorLUTNetlist,
            target: AdversarialStreamTarget,
            seed: [Float],
            freeze: [Bool]
        )
    ) throws -> TensorChromosome {
        let pipeline = try TensorLUTPipeline(device: device, netlist: fixture.netlist)
        let explore = try AdversarialSynthesizer(
            device: device,
            config: .init(
                mutationRate: 0.25,
                maxNoise: 0.5,
                lambdaMax: 0,
                liveWidths: [1, 2],
                discreteJumpRate: 0.4
            )
        )
        let explored = AdversarialHarness(
            device: device,
            pipeline: pipeline,
            synthesizer: explore,
            netlist: fixture.netlist
        ).runStream(
            target: fixture.target,
            config: .init(
                populationSize: 40,
                generations: 80,
                eliteCount: 5,
                seedScatter: true,
                rngSeed: 0xDFF0_0001,
                seedInits: fixture.seed,
                crossoverRate: 0.6,
                freezeMask: fixture.freeze
            )
        )

        let squeeze = try AdversarialSynthesizer(
            device: device,
            config: .init(
                mutationRate: 0.12,
                maxNoise: 0.25,
                lambdaMax: 14,
                liveWidths: [1, 2],
                lambdaDelayFraction: 0.1,
                discreteJumpRate: 0.5
            )
        )
        return AdversarialHarness(
            device: device,
            pipeline: pipeline,
            synthesizer: squeeze,
            netlist: fixture.netlist
        ).runStream(
            target: fixture.target,
            config: .init(
                populationSize: 32,
                generations: 100,
                eliteCount: 4,
                seedScatter: true,
                rngSeed: 0xDFF0_0002,
                seedInits: explored.inits,
                crossoverRate: 0.5,
                polishBinaryAtEnd: true,
                freezeMask: fixture.freeze
            )
        )
    }

    /// Independent behavioral state machine. It shares only the emitter's port
    /// contract; it does not instantiate LUTs or copy the candidate equation.
    private static let sequentialReference = """
    module sequential_toggle_ref (
        input clk,
        input in_0, in_4, in_5,
        output out_1
    );
        reg q;
        always @(posedge clk) begin
            if (!in_5)
                q <= 1'b0;
            else if (in_4)
                q <= q ^ in_0;
        end
        assign out_1 = q;
    endmodule
    """

    private static let sequentialSynthScript = """
    read_verilog lut6.v
    read_verilog emitted.v
    hierarchy -top sequential_toggle
    proc
    flatten
    opt
    techmap
    opt
    abc -lut 6
    opt_clean
    check -assert
    write_json resynth.json
    """

    /// With Q exposed as the sole output, the one-cycle induction hypothesis is
    /// exactly `q_gold == q_gate`. Proving the next cycle therefore proves the
    /// transition relation for every matched Boolean state and all inputs.
    private static let sequentialInductScript = """
    read_json resynth.json
    read_verilog reference.v
    proc
    opt
    equiv_make sequential_toggle_ref sequential_toggle sequential_equiv
    hierarchy -top sequential_equiv
    flatten
    opt_clean
    equiv_induct -seq 1
    equiv_status
    """

    private enum SequentialInductionOutcome {
        case proved
        case unproved(log: String)
        case inconclusive(log: String)
    }

    private struct SequentialProofResult {
        let induction: SequentialInductionOutcome
        let boundedResetTrace: ProofOutcome
    }

    /// A concrete three-step trace: synchronously reset both machines, apply one
    /// enabled data bit from known q=0, then inspect Q. `-prove-skip 2` avoids
    /// treating the deliberately unconstrained pre-reset state as a mismatch.
    private func sequentialResetTraceScript(x: Int) -> String {
        """
        read_json resynth.json
        read_verilog reference.v
        proc
        opt
        miter -equiv -flatten sequential_toggle_ref sequential_toggle sequential_miter
        hierarchy -top sequential_miter
        dffunmap
        opt_clean
        sat -seq 3 -set-at 1 in_in_0 0 -set-at 1 in_in_4 0 -set-at 1 in_in_5 0 -set-at 2 in_in_0 \(x) -set-at 2 in_in_4 1 -set-at 2 in_in_5 1 -prove trigger 0 -prove-skip 2 -show-inputs -show-outputs sequential_miter
        """
    }

    private func proveSequentialTransition(
        yosys: String,
        netlist: TensorLUTNetlist,
        chromosome: TensorChromosome,
        witnessX: Int,
        tag: String
    ) throws -> SequentialProofResult {
        let verilog = TensorLUTEmitter.emitVerilog(
            moduleName: "sequential_toggle",
            netlist: netlist,
            chromosome: chromosome,
            inputWires: [0, 4, 5],
            outputWires: [1]
        )
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("helut-tensorlut-sequential-\(tag)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try verilog.write(
            to: dir.appendingPathComponent("emitted.v"), atomically: true, encoding: .utf8
        )
        try Self.lut6Model.write(
            to: dir.appendingPathComponent("lut6.v"), atomically: true, encoding: .utf8
        )
        try Self.sequentialReference.write(
            to: dir.appendingPathComponent("reference.v"), atomically: true, encoding: .utf8
        )
        try Self.sequentialSynthScript.write(
            to: dir.appendingPathComponent("flow.ys"), atomically: true, encoding: .utf8
        )
        try Self.sequentialInductScript.write(
            to: dir.appendingPathComponent("induct.ys"), atomically: true, encoding: .utf8
        )
        try sequentialResetTraceScript(x: witnessX).write(
            to: dir.appendingPathComponent("trace.ys"), atomically: true, encoding: .utf8
        )

        let (synthStatus, synthLog) = try run(yosys, ["-q", "flow.ys"], cwd: dir)
        guard synthStatus == 0,
              FileManager.default.fileExists(atPath: dir.appendingPathComponent("resynth.json").path)
        else {
            let log = "sequential synthesis failed:\n\(synthLog.suffix(3000))"
            return SequentialProofResult(
                induction: .inconclusive(log: log),
                boundedResetTrace: .inconclusive(log: log)
            )
        }

        let (inductStatus, inductLog) = try run(yosys, ["induct.ys"], cwd: dir)
        let induction: SequentialInductionOutcome
        if inductStatus != 0 {
            induction = .inconclusive(
                log: "equiv_induct exited \(inductStatus):\n\(inductLog.suffix(3000))"
            )
        } else if inductLog.contains("Equivalence successfully proven") {
            induction = .proved
        } else if inductLog.contains("unproven $equiv") {
            induction = .unproved(log: inductLog)
        } else {
            induction = .inconclusive(
                log: "no induction verdict in log:\n\(inductLog.suffix(3000))"
            )
        }

        let (traceStatus, traceLog) = try run(yosys, ["trace.ys"], cwd: dir)
        let bounded: ProofOutcome
        if traceStatus != 0 {
            bounded = .inconclusive(
                log: "bounded trace exited \(traceStatus):\n\(traceLog.suffix(3000))"
            )
        } else if traceLog.contains("no model found: SUCCESS") {
            bounded = .proved
        } else if traceLog.contains("model found: FAIL") {
            bounded = .refuted(log: traceLog)
        } else {
            bounded = .inconclusive(
                log: "no bounded-trace verdict in log:\n\(traceLog.suffix(3000))"
            )
        }
        return SequentialProofResult(induction: induction, boundedResetTrace: bounded)
    }

    /// Erase a state-transition LUT, rediscover it from a short temporal stream,
    /// re-synthesize it through ABC, then prove its transition relation against
    /// independent behavioral RTL for every matched current state and control.
    /// Finally flip one reachable discovered bit and require a concrete reset →
    /// stimulus → divergence trace.
    func testMeltedSequentialTransitionIsRediscoveredAndFormallyProven() throws {
        guard let yosys = yosysPath() else {
            throw XCTSkip("yosys not found — see REPRODUCE.md")
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device not available")
        }

        let fixture = sequentialMeltFixture()
        let erased = TensorChromosome.from(netlist: fixture.netlist)
        let erasedProof = try proveSequentialTransition(
            yosys: yosys,
            netlist: fixture.netlist,
            chromosome: erased,
            witnessX: 1,
            tag: "erased"
        )
        guard case .unproved = erasedProof.induction,
              case .refuted = erasedProof.boundedResetTrace
        else {
            return XCTFail(
                "the erased transition was not concretely refuted; fixture is vacuous: "
                    + "\(erasedProof)"
            )
        }

        var best = try searchSequentialTransition(device: device, fixture: fixture)
        XCTAssertEqual(
            Array(best.inits[0..<64]),
            Array(fixture.seed[0..<64]),
            "frozen identity LUT changed during sequential search"
        )
        XCTAssertEqual(
            AdversarialHarness.nonBinaryCount(best.inits), 0,
            "sequential elite remains fractional and would be thresholded during emission"
        )
        for (address, expected) in [Float(0), 1, 1, 0].enumerated() {
            XCTAssertEqual(
                best.inits[64 + address],
                expected,
                accuracy: 0.01,
                "search did not recover XOR at live address \(address)"
            )
        }

        let searchedProof = try proveSequentialTransition(
            yosys: yosys,
            netlist: fixture.netlist,
            chromosome: best,
            witnessX: 0,
            tag: "searched"
        )
        switch searchedProof.induction {
        case .proved:
            break
        case .unproved(let log), .inconclusive(let log):
            return XCTFail("sequential transition proof failed:\n\(log.suffix(3000))")
        }
        guard case .proved = searchedProof.boundedResetTrace else {
            return XCTFail(
                "proven transition failed its concrete reset trace: \(searchedProof)"
            )
        }
        print(
            "TENSORLUT_SEQUENTIAL_EQUIV ok: erased transition refuted; search recovered "
                + "q_next=q XOR x behind 1 DFF; post-ABC equiv_induct proved every "
                + "matched Boolean state and all enable/reset/input combinations"
        )

        let corrupt = 64
        best.inits[corrupt] = best.inits[corrupt] >= 0.5 ? 0.0 : 1.0
        let corruptProof = try proveSequentialTransition(
            yosys: yosys,
            netlist: fixture.netlist,
            chromosome: best,
            witnessX: 0,
            tag: "corrupt"
        )
        guard case .unproved = corruptProof.induction else {
            return XCTFail("induction did not reject corrupted transition: \(corruptProof)")
        }
        switch corruptProof.boundedResetTrace {
        case .refuted(let log):
            XCTAssertTrue(
                log.contains("in_0") && log.contains("out_1"),
                "counterexample omitted the concrete stimulus/output trace"
            )
            print(
                "TENSORLUT_SEQUENTIAL_EQUIV negative control: one discovered INIT bit "
                    + "flipped; induction left Q unproved and bounded SAT produced the "
                    + "reset → x=0 → divergent-Q counterexample"
            )
        case .proved:
            XCTFail("bounded SAT missed the reachable corrupted transition")
        case .inconclusive(let log):
            XCTFail("bounded SAT did not reach a verdict:\n\(log)")
        }
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
        let netlistPath = try XCTUnwrap(
            repoFile("Generated/Netlists/Enigma/enigma_m4_netlist.json"),
            "checked-in canonical M4 netlist is missing"
        )
        let committedPath = try XCTUnwrap(
            repoFile("Generated/TensorLUT/EnigmaM4/enigma_m4_tensorlut_baseline.v"),
            "checked-in canonical M4 TensorLUT baseline is missing"
        )

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
