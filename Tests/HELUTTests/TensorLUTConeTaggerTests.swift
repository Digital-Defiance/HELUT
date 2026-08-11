import XCTest
@testable import HELUTCore

final class TensorLUTConeTaggerTests: XCTestCase {

    func testSteckerConesOnEnigmaM4AreEdgeSized() throws {
        guard let path = resolveNetlistPath("enigma_m4_netlist.json") else {
            throw XCTSkip("enigma_m4_netlist.json not found")
        }
        let yosys = loadYosysNetlist(from: path)
        guard let (_, module) = yosys.modules.first else {
            return XCTFail("empty module")
        }
        let netlist = TensorLUTCompiler.compile(module: module)
        XCTAssertEqual(netlist.luts.count, 925)

        let cones = TensorLUTConeTagger.tagStecker(netlist: netlist)
        // Edge stecker — not the rotor cloud.
        XCTAssertGreaterThanOrEqual(cones.forwardLUTIndices.count, 1)
        XCTAssertLessThan(cones.forwardLUTIndices.count, 50)
        XCTAssertGreaterThanOrEqual(cones.reverseLUTIndices.count, 1)
        XCTAssertLessThan(cones.reverseLUTIndices.count, 50)
        XCTAssertEqual(
            cones.meltLUTIndices,
            cones.forwardLUTIndices.union(cones.reverseLUTIndices)
        )
        XCTAssertLessThan(cones.meltLUTCount, 80)
        XCTAssertGreaterThan(cones.meltLUTCount, 5)

        // Rotor Q wires are sequential state, not melt.
        for q in EnigmaStreamBuilder.rotorR + EnigmaStreamBuilder.rotorM + EnigmaStreamBuilder.rotorL {
            XCTAssertTrue(cones.stateQWires.contains(q), "missing rotor Q \(q) in state set")
        }

        let mask = TensorLUTConeTagger.steckerFreezeMask(netlist: netlist)
        XCTAssertEqual(mask.count, 925)
        XCTAssertEqual(mask.filter { !$0 }.count, cones.meltLUTCount)
        XCTAssertFalse(cones.meltLUTCSV.isEmpty)
    }

    func testForwardConeDoesNotIncludeStateQReaders() throws {
        guard let path = resolveNetlistPath("enigma_m4_netlist.json") else {
            throw XCTSkip("enigma_m4_netlist.json not found")
        }
        let yosys = loadYosysNetlist(from: path)
        guard let (_, module) = yosys.modules.first else {
            return XCTFail("empty module")
        }
        let netlist = TensorLUTCompiler.compile(module: module)
        let cones = TensorLUTConeTagger.tagStecker(netlist: netlist)
        for idx in cones.forwardLUTIndices {
            let lut = netlist.luts[idx]
            let inputs = [lut.in0, lut.in1, lut.in2, lut.in3, lut.in4, lut.in5].filter { $0 >= 0 }
            XCTAssertFalse(
                inputs.contains(where: { cones.stateQWires.contains($0) }),
                "forward stecker LUT \(idx) reads state Q"
            )
        }
    }
}

private func resolveNetlistPath(_ filename: String) -> String? {
    let fileManager = FileManager.default
    let cwd = fileManager.currentDirectoryPath
    for relative in [filename, "../\(filename)", "../../\(filename)"] {
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
