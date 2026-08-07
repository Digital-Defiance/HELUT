import XCTest
import Metal
@testable import HELUTCore

/// End-to-end bounded conformance for the canonical Mulein Closure Core.
///
/// The grade has four independent surfaces:
/// 1. canonical source RTL under Icarus;
/// 2. the same unchanged core behind a packed shared-store adapter, LUT6-mapped by Yosys and
///    written back to RTL;
/// 3. the Yosys JSON in `CleartextNetlistSimulator`;
/// 4. all fixtures in one lane-major TensorLUT Metal batch.
///
/// Fixtures include every one-edge future of a four-edge contradictory board. Every core job
/// evaluates all 26 central-letter seeds. A one-row mutation is the test-of-the-test: it must
/// change the exact receipt. This is cleartext bounded circuit conformance, not encrypted
/// execution and not a campaign claim.
final class MuleinClosureTensorLUTTests: XCTestCase {
    private let edgeBits = 3
    private let maxEdges = 4
    private let maxSteps = 4
    private let stepBits = 3

    private struct Edge {
        let a: Int
        let b: Int
        let step: Int
    }

    private struct Fixture {
        let name: String
        let edges: [Edge]
        let rows: [[UInt8]]
        let maxPlugs: Int
        let tolerance: Int
    }

    private struct SemanticReceipt: Equatable {
        let survivorMask: UInt32
        let erasedMask: UInt32
        let erasedEdges: [Int]
    }

    private struct CircuitReceipt: Equatable, CustomStringConvertible {
        let name: String
        let survivorMask: UInt32
        let erasedMask: UInt32
        let erasedEdges: [Int]
        let cycles: UInt32
        let closures: UInt32
        let drops: UInt32
        let configError: UInt8

        var description: String {
            "\(name): survivor=\(String(survivorMask, radix: 16)) "
                + "erased=\(String(erasedMask, radix: 16)) cycles=\(cycles) "
                + "closures=\(closures) drops=\(drops) error=\(configError)"
        }
    }

    private func identityRow() -> [UInt8] {
        (0..<26).map(UInt8.init)
    }

    private func zeroRows() -> [[UInt8]] {
        Array(repeating: [UInt8](repeating: 0, count: 26), count: maxSteps)
    }

    private func swapRow(_ x: Int, _ y: Int) -> [UInt8] {
        var row = identityRow()
        row[x] = UInt8(y)
        row[y] = UInt8(x)
        return row
    }

    private func overplugFixture(name: String, maxPlugs: Int, tolerance: Int) -> Fixture {
        var rows = zeroRows()
        rows[0] = swapRow(1, 3)
        rows[1] = swapRow(0, 1)
        return Fixture(
            name: name,
            edges: [Edge(a: 0, b: 2, step: 0), Edge(a: 0, b: 1, step: 1)],
            rows: rows,
            maxPlugs: maxPlugs,
            tolerance: tolerance
        )
    }

    private func contradictionFixture(
        name: String,
        tolerance: Int,
        dropping dropped: Int? = nil,
        mutateBadRow: Bool = false
    ) -> Fixture {
        var rows = zeroRows()
        rows[0] = swapRow(0, 1)
        rows[1] = mutateBadRow ? swapRow(0, 1) : swapRow(0, 2)
        rows[2] = swapRow(4, 5)
        let all = [
            Edge(a: 0, b: 1, step: 0),
            Edge(a: 0, b: 1, step: 0),
            Edge(a: 0, b: 1, step: 1),
            Edge(a: 4, b: 5, step: 2)
        ]
        let edges = all.enumerated().compactMap { index, edge in
            index == dropped ? nil : edge
        }
        return Fixture(name: name, edges: edges, rows: rows, maxPlugs: 10, tolerance: tolerance)
    }

    private func fixtures() -> [Fixture] {
        [
            overplugFixture(name: "overplug_exact", maxPlugs: 2, tolerance: 0),
            overplugFixture(name: "overplug_repair", maxPlugs: 1, tolerance: 1),
            contradictionFixture(name: "contradiction_exact", tolerance: 0),
            contradictionFixture(name: "contradiction_repair", tolerance: 1),
            contradictionFixture(name: "contradiction_drop_0", tolerance: 0, dropping: 0),
            contradictionFixture(name: "contradiction_drop_1", tolerance: 0, dropping: 1),
            contradictionFixture(name: "contradiction_drop_2", tolerance: 0, dropping: 2),
            contradictionFixture(name: "contradiction_drop_3", tolerance: 0, dropping: 3),
            contradictionFixture(
                name: "row_mutation_control", tolerance: 0, mutateBadRow: true
            )
        ]
    }

    /// Blind reference: exact first, then every one-edge future in lexical order. It uses the
    /// historical row-based closure, not the RTL compact-involution implementation or its
    /// active-edge prune.
    private func blindReceipt(_ fixture: Fixture) -> SemanticReceipt {
        func closure(seed: Int, dropping dropped: Int?) -> [UInt32]? {
            let kept = fixture.edges.indices.filter { $0 != dropped }
            guard kept.contains(where: {
                fixture.edges[$0].a == 0 || fixture.edges[$0].b == 0
            }) else { return nil }
            return WelchmanBombe.propagateCore(
                ends: kept.map { (fixture.edges[$0].a, fixture.edges[$0].b) },
                scramblers: kept.map { fixture.rows[fixture.edges[$0].step] },
                seedLetter: 0,
                seedValue: seed
            )
        }

        func withinBudget(_ live: [UInt32]?) -> Bool {
            guard let live else { return false }
            var halfPairs = 0
            for x in 0..<26 where live[x] != 0 {
                if live[x].trailingZeroBitCount != x { halfPairs += 1 }
            }
            return fixture.maxPlugs == 0 || halfPairs / 2 <= fixture.maxPlugs
        }

        var survivorMask: UInt32 = 0
        var erasedMask: UInt32 = 0
        var erasedEdges = [Int](repeating: (1 << edgeBits) - 1, count: 26)

        for seed in 0..<26 {
            if withinBudget(closure(seed: seed, dropping: nil)) {
                survivorMask |= UInt32(1) << UInt32(seed)
                continue
            }
            guard fixture.tolerance == 1 else { continue }

            // Deliberately evaluate every one-edge future even after finding the first repair.
            // This keeps the oracle blind to the RTL's conflict-directed candidate ordering.
            var firstRepair: Int?
            for dropped in fixture.edges.indices {
                if withinBudget(closure(seed: seed, dropping: dropped)), firstRepair == nil {
                    firstRepair = dropped
                }
            }
            if let firstRepair {
                survivorMask |= UInt32(1) << UInt32(seed)
                erasedMask |= UInt32(1) << UInt32(seed)
                erasedEdges[seed] = firstRepair
            }
        }
        return SemanticReceipt(
            survivorMask: survivorMask,
            erasedMask: erasedMask,
            erasedEdges: erasedEdges
        )
    }

    private func toolPath(_ name: String) -> String? {
        for candidate in [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)"
        ] where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return nil
    }

    private func repositoryRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<8 {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(
                atPath: url.appendingPathComponent("Package.swift").path
            ), FileManager.default.fileExists(
                atPath: url.appendingPathComponent("Apps/Mulein/rtl/mulein_closure_core.sv").path
            ) {
                return url
            }
        }
        throw NSError(
            domain: "MuleinClosureTensorLUTTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "repository root not found from #filePath"]
        )
    }

    @discardableResult
    private func run(_ executable: String, _ arguments: [String], cwd: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = cwd
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "MuleinClosureTensorLUTTests", code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey:
                    "\(executable) \(arguments.joined(separator: " ")) failed:\n"
                        + String(output.suffix(8_000))]
            )
        }
        return output
    }

    private func bits(fromHex raw: String, width: Int) -> [UInt8] {
        let chars = Array(raw.lowercased().reversed())
        var bits = [UInt8](repeating: 0, count: width)
        for bit in 0..<width {
            let nibble = bit / 4
            guard nibble < chars.count,
                  let value = Int(String(chars[nibble]), radix: 16) else { continue }
            bits[bit] = UInt8((value >> (bit % 4)) & 1)
        }
        return bits
    }

    private func erasedEdges(fromBits bits: [UInt8]) -> [Int] {
        (0..<26).map { seed in
            var value = 0
            for bit in 0..<edgeBits where bits[seed * edgeBits + bit] != 0 {
                value |= 1 << bit
            }
            return value
        }
    }

    private func parseReceipts(_ output: String) throws -> [CircuitReceipt] {
        try output.split(separator: "\n").compactMap { raw -> CircuitReceipt? in
            let line = String(raw)
            guard line.hasPrefix("RECEIPT ") else { return nil }
            let tokens = line.split(separator: " ").map(String.init)
            guard tokens.count == 9 else {
                throw NSError(
                    domain: "MuleinClosureTensorLUTTests", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "malformed receipt: \(line)"]
                )
            }
            var fields: [String: String] = [:]
            for token in tokens.dropFirst(2) {
                let pair = token.split(separator: "=", maxSplits: 1).map(String.init)
                if pair.count == 2 { fields[pair[0]] = pair[1] }
            }
            func hex32(_ key: String) throws -> UInt32 {
                guard let text = fields[key], let value = UInt32(text, radix: 16) else {
                    throw NSError(
                        domain: "MuleinClosureTensorLUTTests", code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "missing \(key) in \(line)"]
                    )
                }
                return value
            }
            guard let provenance = fields["provenance"] else {
                throw NSError(
                    domain: "MuleinClosureTensorLUTTests", code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "missing provenance in \(line)"]
                )
            }
            return CircuitReceipt(
                name: tokens[1],
                survivorMask: try hex32("survivor"),
                erasedMask: try hex32("erased"),
                erasedEdges: erasedEdges(fromBits: bits(fromHex: provenance, width: 26 * edgeBits)),
                cycles: try hex32("cycles"),
                closures: try hex32("closures"),
                drops: try hex32("drops"),
                configError: UInt8(try hex32("error"))
            )
        }
    }

    private func integerBits(_ value: Int, width: Int) -> [UInt8] {
        (0..<width).map { UInt8((value >> $0) & 1) }
    }

    private func packedFixtureInputs(
        _ fixture: Fixture,
        module: YosysModule,
        resetn: UInt8,
        start: UInt8
    ) -> [String: [UInt8]] {
        var inputs: [String: [UInt8]] = [:]
        for (name, port) in module.ports where port.direction == "input" {
            inputs[name] = [UInt8](repeating: 0, count: port.bits.count)
        }
        inputs["resetn"] = [resetn]
        inputs["start"] = [start]
        inputs["start_edge_count"] = integerBits(fixture.edges.count, width: edgeBits)
        inputs["start_central"] = integerBits(0, width: 5)
        inputs["start_max_plugs"] = integerBits(fixture.maxPlugs, width: 5)
        inputs["start_tolerance"] = integerBits(fixture.tolerance, width: 2)

        var edgeA = [UInt8](repeating: 0, count: maxEdges * 5)
        var edgeB = [UInt8](repeating: 0, count: maxEdges * 5)
        var edgeSteps = [UInt8](repeating: 0, count: maxEdges * stepBits)
        for (index, edge) in fixture.edges.enumerated() {
            let a = integerBits(edge.a, width: 5)
            let b = integerBits(edge.b, width: 5)
            let step = integerBits(edge.step, width: stepBits)
            edgeA.replaceSubrange(index * 5..<(index * 5 + 5), with: a)
            edgeB.replaceSubrange(index * 5..<(index * 5 + 5), with: b)
            edgeSteps.replaceSubrange(
                index * stepBits..<(index * stepBits + stepBits), with: step
            )
        }
        inputs["edge_a_table"] = edgeA
        inputs["edge_b_table"] = edgeB
        inputs["edge_step_table"] = edgeSteps

        var rows = [UInt8](repeating: 0, count: maxSteps * 26 * 5)
        for step in 0..<maxSteps {
            for letter in 0..<26 {
                let value = integerBits(Int(fixture.rows[step][letter]), width: 5)
                let base = (step * 26 + letter) * 5
                rows.replaceSubrange(base..<(base + 5), with: value)
            }
        }
        inputs["step_rows"] = rows
        return inputs
    }

    private func integer(_ bits: [UInt8]) -> UInt32 {
        var value: UInt32 = 0
        for (index, bit) in bits.enumerated() where bit != 0 {
            value |= UInt32(1) << UInt32(index)
        }
        return value
    }

    private func receipt(
        name: String,
        outputs: [String: [UInt8]]
    ) -> CircuitReceipt {
        CircuitReceipt(
            name: name,
            survivorMask: integer(outputs["survivor_mask"] ?? []),
            erasedMask: integer(outputs["erased_seed_mask"] ?? []),
            erasedEdges: erasedEdges(fromBits: outputs["erased_edge_by_seed"] ?? []),
            cycles: integer(outputs["cycle_count"] ?? []),
            closures: integer(outputs["closure_count"] ?? []),
            drops: integer(outputs["drop_trial_count"] ?? []),
            configError: outputs["config_error"]?.first ?? 1
        )
    }

    private func runCleartext(
        moduleName: String,
        module: YosysModule,
        fixtures: [Fixture]
    ) throws -> [CircuitReceipt] {
        try fixtures.map { fixture in
            let simulator = CleartextNetlistSimulator(moduleName: moduleName, module: module)
            simulator.resetState()
            _ = simulator.tick(inputs: packedFixtureInputs(
                fixture, module: module, resetn: 0, start: 0
            ))
            var outputs = simulator.tick(inputs: packedFixtureInputs(
                fixture, module: module, resetn: 1, start: 1
            ))
            for _ in 0..<2_000 {
                if outputs["done"]?.first == 1 {
                    return receipt(name: fixture.name, outputs: outputs)
                }
                outputs = simulator.tick(inputs: packedFixtureInputs(
                    fixture, module: module, resetn: 1, start: 0
                ))
            }
            throw NSError(
                domain: "MuleinClosureTensorLUTTests", code: 5,
                userInfo: [NSLocalizedDescriptionKey: "clear simulator timed out on \(fixture.name)"]
            )
        }
    }

    private func readPort(
        _ name: String,
        lane: Int,
        module: YosysModule,
        wires: UnsafePointer<Float>,
        totalWires: Int
    ) -> [UInt8] {
        guard let port = module.ports[name] else { return [] }
        return port.bits.map { bit in
            switch bit {
            case .constant(let value): return UInt8(value)
            case .net(let wire): return wires[lane * totalWires + wire] >= 0.5 ? 1 : 0
            }
        }
    }

    private func runTensorLUT(
        device: MTLDevice,
        module: YosysModule,
        netlist: TensorLUTNetlist,
        fixtures: [Fixture]
    ) throws -> [CircuitReceipt] {
        let batchSize = fixtures.count
        let pipeline = try TensorLUTPipeline(device: device, netlist: netlist)
        let inits = netlist.packedINITBuffer()
        guard let initsBuffer = device.makeBuffer(
            bytes: inits,
            length: inits.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else { throw NSError(domain: "MuleinClosureTensorLUTTests", code: 6) }

        var initial = [Float](repeating: 0, count: batchSize * netlist.totalWires)
        netlist.seedConstOne(into: &initial, batchSize: batchSize)
        guard let wireBuffer = device.makeBuffer(
            bytes: initial,
            length: initial.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else { throw NSError(domain: "MuleinClosureTensorLUTTests", code: 7) }
        let pointer = wireBuffer.contents().bindMemory(
            to: Float.self, capacity: batchSize * netlist.totalWires
        )

        func writeInputs(resetn: UInt8, start: UInt8) {
            for (lane, fixture) in fixtures.enumerated() {
                let values = packedFixtureInputs(
                    fixture, module: module, resetn: resetn, start: start
                )
                for (portName, portValues) in values {
                    guard let port = module.ports[portName] else { continue }
                    for (index, bit) in port.bits.enumerated() {
                        if case .net(let wire) = bit {
                            pointer[lane * netlist.totalWires + wire] = Float(portValues[index])
                        }
                    }
                }
            }
        }

        func tick(resetn: UInt8, start: UInt8) {
            writeInputs(resetn: resetn, start: start)
            pipeline.evaluateTick(
                totalWires: netlist.totalWires,
                initsBuffer: initsBuffer,
                wireBuffer: wireBuffer,
                batchSize: batchSize
            )
        }

        tick(resetn: 0, start: 0)
        tick(resetn: 1, start: 1)
        var completed = [CircuitReceipt?](repeating: nil, count: batchSize)
        for _ in 0..<2_000 {
            for lane in fixtures.indices where completed[lane] == nil {
                let done = readPort(
                    "done", lane: lane, module: module,
                    wires: UnsafePointer(pointer), totalWires: netlist.totalWires
                ).first ?? 0
                if done == 1 {
                    var outputs: [String: [UInt8]] = [:]
                    for name in [
                        "survivor_mask", "erased_seed_mask", "erased_edge_by_seed",
                        "cycle_count", "closure_count", "drop_trial_count", "config_error"
                    ] {
                        outputs[name] = readPort(
                            name, lane: lane, module: module,
                            wires: UnsafePointer(pointer), totalWires: netlist.totalWires
                        )
                    }
                    completed[lane] = receipt(name: fixtures[lane].name, outputs: outputs)
                }
            }
            if completed.allSatisfy({ $0 != nil }) { break }
            tick(resetn: 1, start: 0)
        }
        guard completed.allSatisfy({ $0 != nil }) else {
            let missing = fixtures.indices.filter { completed[$0] == nil }.map { fixtures[$0].name }
            throw NSError(
                domain: "MuleinClosureTensorLUTTests", code: 8,
                userInfo: [NSLocalizedDescriptionKey: "TensorLUT timed out: \(missing)"]
            )
        }
        return completed.map { $0! }
    }

    func testSourcePostYosysClearAndTensorLUTBatchAgree() throws {
        guard let yosys = toolPath("yosys"),
              let iverilog = toolPath("iverilog"),
              let vvp = toolPath("vvp") else {
            throw XCTSkip("yosys/iverilog/vvp are required for the Mulein circuit grade")
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device is required for the TensorLUT batch grade")
        }
        let root = try repositoryRoot()
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("helut-mulein-tensorlut-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let core = root.appendingPathComponent("Apps/Mulein/rtl/mulein_closure_core.sv").path
        let wrapper = root.appendingPathComponent("Apps/Mulein/rtl/mulein_closure_bounded.sv").path
        let testbench = root.appendingPathComponent(
            "Apps/Mulein/tests/rtl/mulein_closure_bounded_tb.sv"
        ).path
        let flow = """
        read_verilog -sv \(core) \(wrapper)
        hierarchy -check -top mulein_closure_bounded
        proc
        flatten
        memory
        opt
        techmap
        opt
        dffunmap
        zinit -all
        abc -lut 6
        opt_clean
        check -assert
        write_json bounded.json
        write_verilog -noattr bounded.v
        """
        try flow.write(to: dir.appendingPathComponent("flow.ys"), atomically: true, encoding: .utf8)
        _ = try run(yosys, ["-Q", "-q", "flow.ys"], cwd: dir)

        _ = try run(
            iverilog,
            ["-g2012", "-Wall", "-s", "mulein_closure_bounded_tb", "-o", "source.vvp",
             core, wrapper, testbench],
            cwd: dir
        )
        let sourceOutput = try run(vvp, ["source.vvp"], cwd: dir)
        XCTAssertTrue(sourceOutput.contains("PASS: bounded source/post-Yosys receipt fixtures"))

        _ = try run(
            iverilog,
            ["-g2012", "-Wall", "-s", "mulein_closure_bounded_tb", "-o", "post.vvp",
             "bounded.v", testbench],
            cwd: dir
        )
        let postOutput = try run(vvp, ["post.vvp"], cwd: dir)
        XCTAssertTrue(postOutput.contains("PASS: bounded source/post-Yosys receipt fixtures"))

        let sourceReceipts = try parseReceipts(sourceOutput)
        let postReceipts = try parseReceipts(postOutput)
        XCTAssertEqual(sourceReceipts.count, fixtures().count)
        XCTAssertEqual(postReceipts, sourceReceipts, "post-Yosys RTL receipts drifted from source")

        let loaded = loadYosysNetlist(from: dir.appendingPathComponent("bounded.json").path)
        guard let (moduleName, module) = loaded.modules["mulein_closure_bounded"]
            .map({ ("mulein_closure_bounded", $0) }) else {
            return XCTFail("bounded.json lacks mulein_closure_bounded")
        }
        let executableCells = module.cells.values.filter { $0.type != "$scopeinfo" }
        let unsupported = Set(executableCells.map(\.type).filter {
            $0 != "$lut" && $0 != "$_DFF_P_"
        })
        XCTAssertTrue(
            unsupported.isEmpty,
            "TensorLUT JSON contains unsupported/reset-priority cells: \(unsupported.sorted())"
        )
        XCTAssertTrue(executableCells.contains { $0.type == "$lut" })
        XCTAssertTrue(executableCells.contains { $0.type == "$_DFF_P_" })

        let batchFixtures = fixtures()
        let semantic = batchFixtures.map(blindReceipt)
        for index in batchFixtures.indices {
            XCTAssertEqual(sourceReceipts[index].name, batchFixtures[index].name)
            XCTAssertEqual(sourceReceipts[index].survivorMask, semantic[index].survivorMask)
            XCTAssertEqual(sourceReceipts[index].erasedMask, semantic[index].erasedMask)
            XCTAssertEqual(sourceReceipts[index].erasedEdges, semantic[index].erasedEdges)
        }
        XCTAssertNotEqual(
            semantic[2].survivorMask, semantic[8].survivorMask,
            "negative control has no observable effect; the grade would have no teeth"
        )

        let clearReceipts = try runCleartext(
            moduleName: moduleName, module: module, fixtures: batchFixtures
        )
        XCTAssertEqual(clearReceipts, sourceReceipts, "Yosys JSON clear simulation drifted")

        let tensor = TensorLUTCompiler.compile(module: module)
        XCTAssertEqual(tensor.luts.count, executableCells.filter { $0.type == "$lut" }.count)
        XCTAssertEqual(tensor.dffs.count, executableCells.filter { $0.type == "$_DFF_P_" }.count)
        XCTAssertEqual(
            tensor.executionLevels.reduce(0) { $0 + $1.count }, tensor.luts.count,
            "not every LUT entered a topological execution level"
        )
        let tensorReceipts = try runTensorLUT(
            device: device, module: module, netlist: tensor, fixtures: batchFixtures
        )
        XCTAssertEqual(tensorReceipts, sourceReceipts, "batched TensorLUT Metal receipts drifted")

        let oneEdgeFutures = batchFixtures.filter { $0.name.hasPrefix("contradiction_drop_") }
        XCTAssertEqual(oneEdgeFutures.count, 4)
        print(
            "MULEIN_TENSORLUT PASS: source == post-Yosys == clear JSON == "
                + "TensorLUT Metal; \(batchFixtures.count) lanes, all 26 seeds/lane, "
                + "4/4 one-edge futures, \(tensor.luts.count) LUT6, \(tensor.dffs.count) DFF"
        )
        print("MULEIN_TENSORLUT scope: cleartext bounded circuit conformance; not FHE")
    }
}
