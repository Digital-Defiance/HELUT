import Metal
import XCTest
@testable import HELUTCore

final class TensorLUTCompilerTests: XCTestCase {

    func testCompileEnigmaM4Topology() throws {
        guard let path = resolveNetlistPath("enigma_m4_netlist.json") else {
            throw XCTSkip("enigma_m4_netlist.json not found")
        }
        let yosys = loadYosysNetlist(from: path)
        guard let (_, module) = yosys.modules.first else {
            return XCTFail("empty netlist")
        }

        let soft = TensorLUTCompiler.compile(module: module)

        XCTAssertEqual(soft.luts.count, 925)
        XCTAssertEqual(soft.dffs.count, 49) // 47 SDFF + 2 SDFFE
        XCTAssertFalse(soft.executionLevels.isEmpty)
        let leveled = soft.executionLevels.reduce(0) { $0 + $1.count }
        XCTAssertEqual(leveled, soft.luts.count)
        XCTAssertGreaterThan(soft.totalWires, 2000)
        // All LUT inputs WIDTH ≤ 3 in this netlist — padded to 6 with -1.
        XCTAssertTrue(soft.luts.allSatisfy { $0.in5 == -1 || $0.entries.count == 64 })
        XCTAssertTrue(soft.luts.allSatisfy { $0.entries.count == 64 })
    }

    func testCompileCoreNetlistHasEnableDFFs() throws {
        guard let path = resolveNetlistPath("core_netlist.json") else {
            throw XCTSkip("core_netlist.json not found")
        }
        let yosys = loadYosysNetlist(from: path)
        guard let (_, module) = yosys.modules.first else {
            return XCTFail("empty netlist")
        }

        let soft = TensorLUTCompiler.compile(module: module)
        XCTAssertEqual(soft.luts.count, 6)
        XCTAssertEqual(soft.dffs.count, 4)
        XCTAssertTrue(soft.dffs.contains { $0.enableWire >= 0 })
        XCTAssertEqual(soft.executionLevels.reduce(0) { $0 + $1.count }, soft.luts.count)
    }

    func testCoreNetlistBinaryTickParityVsCleartext() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device not available")
        }
        guard let path = resolveNetlistPath("core_netlist.json") else {
            throw XCTSkip("core_netlist.json not found")
        }

        let yosys = loadYosysNetlist(from: path)
        guard let (moduleName, module) = yosys.modules.first else {
            return XCTFail("empty netlist")
        }

        let clear = CleartextNetlistSimulator(moduleName: moduleName, module: module)
        clear.resetState()

        // Drive a simple pattern on every input port bit.
        var clearInputs: [String: [UInt8]] = [:]
        for (name, bits) in clear.inputPorts {
            clearInputs[name] = bits.indices.map { UInt8(($0 + 1) % 2) }
        }
        let clearOut = clear.tick(inputs: clearInputs)

        let soft = TensorLUTCompiler.compile(module: module)
        let pipeline = try TensorLUTPipeline(device: device, netlist: soft)
        let initData = soft.packedINITBuffer()
        guard let initsBuffer = device.makeBuffer(
            bytes: initData,
            length: initData.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else {
            return XCTFail("INIT buffer")
        }

        var wires = [Float](repeating: 0, count: soft.totalWires)
        soft.seedConstOne(into: &wires, batchSize: 1)
        // Q starts at 0 (matches clear.resetState).
        for (name, bits) in clear.inputPorts {
            let values = clearInputs[name]!
            for (i, bit) in bits.enumerated() {
                if case .net(let wire) = bit {
                    wires[wire] = Float(values[i])
                }
            }
        }

        guard let wireBuffer = device.makeBuffer(
            bytes: wires,
            length: wires.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else {
            return XCTFail("wire buffer")
        }

        pipeline.evaluateTick(
            totalWires: soft.totalWires,
            initsBuffer: initsBuffer,
            wireBuffer: wireBuffer,
            batchSize: 1
        )

        let ptr = wireBuffer.contents().bindMemory(to: Float.self, capacity: soft.totalWires)
        let accuracy: Float = 1e-4

        for (name, bits) in clear.outputPorts {
            let expected = clearOut[name]!
            for (i, bit) in bits.enumerated() {
                guard case .net(let wire) = bit else { continue }
                XCTAssertEqual(
                    ptr[wire],
                    Float(expected[i]),
                    accuracy: accuracy,
                    "port \(name)[\(i)] wire \(wire)"
                )
            }
        }

        // Registered Q bits in clear state should match TensorLUT Q wires.
        for dff in soft.dffs {
            let q = Int(dff.qWire)
            let expected = clear.state[q] ?? 0
            XCTAssertEqual(ptr[q], Float(expected), accuracy: accuracy, "Q wire \(q)")
        }
    }
}

private func resolveNetlistPath(_ filename: String) -> String? {
    let fileManager = FileManager.default
    let cwd = fileManager.currentDirectoryPath
    let candidates = [
        filename,
        "../\(filename)",
        "../../\(filename)",
        "../../../\(filename)"
    ]
    for relative in candidates {
        let path = (cwd as NSString).appendingPathComponent(relative)
        if fileManager.fileExists(atPath: path) { return path }
    }
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 {
        url.deleteLastPathComponent()
        let candidate = url.appendingPathComponent(filename).path
        if fileManager.fileExists(atPath: candidate) { return candidate }
    }
    return nil
}
