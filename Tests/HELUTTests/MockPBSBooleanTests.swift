import XCTest
import Metal
import MetalPerformanceShadersGraph
@testable import HELUTCore

final class MockPBSBooleanTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testYosysTruthTableEndianMatchesCleartextSim() {
        // LUT "0110" is XOR: entries[0]=0, [1]=1, [2]=1, [3]=0
        XCTAssertEqual(parseYosysLUTTruthTable("0110"), [0, 1, 1, 0])
        XCTAssertEqual(parseYosysLUTTruthTable("11101000"), [0, 0, 0, 1, 0, 1, 1, 1])
        XCTAssertEqual(
            evaluateMultilinearLUT(truthTable: [0, 1, 1, 0], inputs: [1, 1]),
            0
        )
        XCTAssertEqual(
            evaluateMultilinearLUT(truthTable: [0, 1, 1, 0], inputs: [1, 0]),
            1
        )
    }

    func testMockTorusEncodeDecodeRoundTrip() {
        for bit: UInt32 in [0, 1] {
            let poly = MockTorusEncoding.encodeBit(bit, degree: 16)
            XCTAssertEqual(MockTorusEncoding.decodeBit(poly), bit)
        }
    }

    /// Metal mock-PBS full adder matches clear boolean for all 8 input rows.
    func testBooleanSafeFullAdderMatchesCleartext() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device")
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw XCTSkip("No MTLCommandQueue")
        }
        guard let path = resolveRepoFile("netlist.json") else {
            return XCTFail("netlist.json not found")
        }

        let netlist = loadYosysNetlist(from: path)
        guard let (moduleName, module) = netlist.modules.first else {
            return XCTFail("Empty netlist")
        }

        let degree = 32
        let batch = 1
        let compiler = YosysGraphCompiler(degree: degree, batch: batch)
        compiler.compile(moduleName: moduleName, module: module)
        XCTAssertTrue(compiler.dffNodes.isEmpty, "full_adder should be combinational")

        let clear = CleartextNetlistSimulator(moduleName: moduleName, module: module)

        for a in 0...1 {
            for b in 0...1 {
                for cin in 0...1 {
                    let clearOut = clear.tick(inputs: [
                        "a": [UInt8(a)],
                        "b": [UInt8(b)],
                        "cin": [UInt8(cin)]
                    ])
                    let wantSum = Int(clearOut["sum"]?[0] ?? 255)
                    let wantCout = Int(clearOut["cout"]?[0] ?? 255)

                    let metal = try evaluateCombinational(
                        compiler: compiler,
                        device: device,
                        commandQueue: commandQueue,
                        inputs: [
                            "a": [UInt32(a)],
                            "b": [UInt32(b)],
                            "cin": [UInt32(cin)]
                        ]
                    )
                    XCTAssertEqual(
                        metal["sum"],
                        [UInt32(wantSum)],
                        "sum mismatch for a=\(a) b=\(b) cin=\(cin)"
                    )
                    XCTAssertEqual(
                        metal["cout"],
                        [UInt32(wantCout)],
                        "cout mismatch for a=\(a) b=\(b) cin=\(cin)"
                    )
                }
            }
        }
    }

    /// Stateful counter under mock PBS matches cleartext for 16 enable ticks.
    func testBooleanSafeCounterMatchesCleartext() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device")
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw XCTSkip("No MTLCommandQueue")
        }
        guard let path = resolveRepoFile("core_netlist.json") else {
            return XCTFail("core_netlist.json not found")
        }

        let netlist = loadYosysNetlist(from: path)
        guard let (moduleName, module) = netlist.modules.first else {
            return XCTFail("Empty netlist")
        }

        let degree = 64
        let batch = 1
        let compiler = YosysGraphCompiler(degree: degree, batch: batch)
        compiler.compile(moduleName: moduleName, module: module)
        XCTAssertFalse(compiler.dffNodes.isEmpty)

        let clear = CleartextNetlistSimulator(moduleName: moduleName, module: module)
        clear.resetState()

        let vectorShape: [NSNumber] = [NSNumber(value: batch), NSNumber(value: degree)]
        let elementCount = batch * degree
        let zeroHost = [UInt32](repeating: 0, count: elementCount)
        let oneHost = [UInt32](repeating: 1, count: elementCount)

        var primaryFeeds: [MPSGraphTensor: MPSGraphTensorData] = [:]
        var enBuffer: MTLBuffer?
        for entry in compiler.inputNodes {
            guard let placeholder = entry.node.placeholder else {
                return XCTFail("Missing placeholder")
            }
            let values = entry.port == "en" ? oneHost : zeroHost
            let buffer = makeSharedUInt32Buffer(device: device, values: values)
            if entry.port == "en" { enBuffer = buffer }
            primaryFeeds[placeholder] = MPSGraphTensorData(buffer, shape: vectorShape, dataType: .uInt32)
        }
        XCTAssertNotNil(enBuffer)

        var stateFeeds: [MPSGraphTensorData] = compiler.dffNodes.map { _ in
            let buffer = makeSharedUInt32Buffer(device: device, values: zeroHost)
            return MPSGraphTensorData(buffer, shape: vectorShape, dataType: .uInt32)
        }
        let stateWriteBuffers: [[MTLBuffer]] = [
            compiler.dffNodes.map { _ in makeSharedUInt32Buffer(device: device, count: elementCount) },
            compiler.dffNodes.map { _ in makeSharedUInt32Buffer(device: device, count: elementCount) }
        ]
        var writeSlot = 0

        // count[i] is a registered Q — sample Q_next from stateWrites (cleartext returns post-update).
        var qWireToDFF: [Int: Int] = [:]
        for (index, dff) in compiler.dffNodes.enumerated() {
            guard let cell = module.cells[dff.cell],
                  let qBit = cell.connections["Q"]?.first,
                  case .net(let qWire) = qBit else { continue }
            qWireToDFF[qWire] = index
        }
        let countDFFIndices: [Int] = (module.ports["count"]?.bits ?? []).compactMap { bit in
            guard case .net(let wire) = bit else { return nil }
            return qWireToDFF[wire]
        }
        XCTAssertEqual(countDFFIndices.count, 4)

        for tick in 1...16 {
            let clearOut = clear.tick(inputs: ["clk": [0], "en": [1]])
            let want = clearOut["count"] ?? []
            XCTAssertEqual(want.count, 4)

            let writeBuffers = stateWriteBuffers[writeSlot]
            var feeds = primaryFeeds
            for (index, dff) in compiler.dffNodes.enumerated() {
                guard let placeholder = dff.stateInput.placeholder else {
                    return XCTFail("Missing state placeholder")
                }
                feeds[placeholder] = stateFeeds[index]
            }

            var results: [MPSGraphTensor: MPSGraphTensorData] = [:]
            var nextState: [MPSGraphTensorData] = []
            for (index, dff) in compiler.dffNodes.enumerated() {
                guard let stateOutput = dff.stateOutput else {
                    return XCTFail("Missing state output")
                }
                let data = MPSGraphTensorData(
                    writeBuffers[index], shape: vectorShape, dataType: .uInt32
                )
                results[stateOutput] = data
                nextState.append(data)
            }
            for entry in compiler.outputTensors {
                let buffer = makeSharedUInt32Buffer(device: device, count: elementCount)
                results[entry.tensor] = MPSGraphTensorData(
                    buffer, shape: vectorShape, dataType: .uInt32
                )
            }

            compiler.graph.run(
                with: commandQueue,
                feeds: feeds,
                targetOperations: nil,
                resultsDictionary: results
            )

            var got: [UInt8] = []
            for dffIndex in countDFFIndices {
                let ptr = writeBuffers[dffIndex].contents().bindMemory(
                    to: UInt32.self, capacity: elementCount
                )
                let decoded = MockTorusEncoding.decodeBit(buffer: ptr, lane: 0, degree: degree)
                got.append(UInt8(decoded))
            }
            XCTAssertEqual(got, want, "counter mismatch at tick \(tick)")
            stateFeeds = nextState
            writeSlot ^= 1
        }
    }

    /// Short Enigma M3 netlist stream: Metal mock PBS == cleartext simulator == host oracle.
    func testBooleanSafeEnigmaNetlistMatchesOracle() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device")
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw XCTSkip("No MTLCommandQueue")
        }
        guard let path = resolveEnigmaNetlistPathForCore() ?? resolveRepoFile("enigma_netlist.json") else {
            throw XCTSkip("enigma_netlist.json not found")
        }

        let plaintext = "TEST"
        let harness = EnigmaNetlistHarness(netlistPath: path)
        harness.seedGrundstellung(left: 0, middle: 1, right: 2) // ABC
        let ct = harness.process(ciphertext: EnigmaAlphabet.normalize(plaintext))
        // Round-trip through the same clear harness after reseeding.
        harness.seedGrundstellung(left: 0, middle: 1, right: 2)
        let clearPT = harness.process(ciphertext: ct)
        XCTAssertEqual(EnigmaAlphabet.string(from: clearPT), plaintext)

        let netlist = loadYosysNetlist(from: path)
        guard let (moduleName, module) = netlist.modules.first else {
            return XCTFail("Empty enigma netlist")
        }

        // Small degree keeps the test fast; boolean-safe LUTs do not need N=1024.
        let degree = 8
        let batch = 1
        let compiler = YosysGraphCompiler(degree: degree, batch: batch)
        compiler.compile(moduleName: moduleName, module: module)

        let metalPT = try runEnigmaMetalMockPBS(
            compiler: compiler,
            module: module,
            device: device,
            commandQueue: commandQueue,
            ciphertext: ct,
            left: 0,
            middle: 1,
            right: 2
        )
        XCTAssertEqual(EnigmaAlphabet.string(from: metalPT), plaintext)
    }
}

// MARK: - Helpers

private func resolveRepoFile(_ name: String) -> String? {
    let fileManager = FileManager.default
    let cwd = fileManager.currentDirectoryPath
    let candidates = [
        name,
        "../\(name)",
        "../../\(name)",
        "../../../\(name)"
    ]
    for relative in candidates {
        let path = URL(fileURLWithPath: cwd).appendingPathComponent(relative).path
        if fileManager.fileExists(atPath: path) {
            return path
        }
    }
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 {
        url.deleteLastPathComponent()
        let candidate = url.appendingPathComponent(name).path
        if fileManager.fileExists(atPath: candidate) {
            return candidate
        }
    }
    return nil
}

private enum MockPBSTestError: Error {
    case missingPlaceholder
}

private func evaluateCombinational(
    compiler: YosysGraphCompiler,
    device: MTLDevice,
    commandQueue: MTLCommandQueue,
    inputs: [String: [UInt32]]
) throws -> [String: [UInt32]] {
    let degree = compiler.degree
    let batch = compiler.batch
    let elementCount = batch * degree
    let vectorShape: [NSNumber] = [NSNumber(value: batch), NSNumber(value: degree)]

    var feeds: [MPSGraphTensor: MPSGraphTensorData] = [:]
    for entry in compiler.inputNodes {
        guard let placeholder = entry.node.placeholder else {
            throw MockPBSTestError.missingPlaceholder
        }
        let bits = inputs[entry.port] ?? [0]
        precondition(entry.bitIndex < bits.count)
        let values = MockTorusEncoding.encodeBit(bits[entry.bitIndex], degree: degree)
        let buffer = makeSharedUInt32Buffer(device: device, values: values)
        feeds[placeholder] = MPSGraphTensorData(buffer, shape: vectorShape, dataType: .uInt32)
    }

    var results: [MPSGraphTensor: MPSGraphTensorData] = [:]
    var outputBuffers: [(port: String, bit: Int, buffer: MTLBuffer)] = []
    for entry in compiler.outputTensors {
        let buffer = makeSharedUInt32Buffer(device: device, count: elementCount)
        results[entry.tensor] = MPSGraphTensorData(buffer, shape: vectorShape, dataType: .uInt32)
        outputBuffers.append((entry.port, entry.bitIndex, buffer))
    }

    compiler.graph.run(
        with: commandQueue,
        feeds: feeds,
        targetOperations: nil,
        resultsDictionary: results
    )

    var decoded: [String: [UInt32]] = [:]
    for (port, bit, buffer) in outputBuffers {
        let ptr = buffer.contents().bindMemory(to: UInt32.self, capacity: elementCount)
        let value = MockTorusEncoding.decodeBit(buffer: ptr, lane: 0, degree: degree)
        var row = decoded[port] ?? [UInt32](repeating: 0, count: bit + 1)
        if row.count <= bit {
            row.append(contentsOf: repeatElement(0, count: bit + 1 - row.count))
        }
        row[bit] = value
        decoded[port] = row
    }
    return decoded
}

private func runEnigmaMetalMockPBS(
    compiler: YosysGraphCompiler,
    module: YosysModule,
    device: MTLDevice,
    commandQueue: MTLCommandQueue,
    ciphertext: [Int],
    left: Int,
    middle: Int,
    right: Int
) throws -> [Int] {
    let degree = compiler.degree
    let batch = compiler.batch
    let elementCount = batch * degree
    let vectorShape: [NSNumber] = [NSNumber(value: batch), NSNumber(value: degree)]
    let zeroHost = [UInt32](repeating: 0, count: elementCount)
    let oneHost = [UInt32](repeating: 1, count: elementCount)

    var qWireToDFF: [Int: Int] = [:]
    for (index, dff) in compiler.dffNodes.enumerated() {
        guard let cell = module.cells[dff.cell],
              let qBit = cell.connections["Q"]?.first,
              case .net(let qWire) = qBit else { continue }
        qWireToDFF[qWire] = index
    }

    func dffBits(named name: String) -> [Int] {
        guard let net = module.netnames?[name] else { return [] }
        return net.bits.compactMap { bit -> Int? in
            guard case .net(let wire) = bit else { return nil }
            return qWireToDFF[wire]
        }
    }
    let rBits = dffBits(named: "rotor_r")
    let mBits = dffBits(named: "rotor_m")
    let lBits = dffBits(named: "rotor_l")
    XCTAssertFalse(rBits.isEmpty && mBits.isEmpty && lBits.isEmpty)

    var primaryFeeds: [MPSGraphTensor: MPSGraphTensorData] = [:]
    var resetnBuffer: MTLBuffer?
    var ctBuffers: [MTLBuffer?] = Array(repeating: nil, count: 8)
    for entry in compiler.inputNodes {
        guard let placeholder = entry.node.placeholder else {
            throw MockPBSTestError.missingPlaceholder
        }
        let values: [UInt32]
        if entry.port == "resetn" {
            values = oneHost
        } else if entry.port == "ciphertext_char" {
            values = zeroHost
        } else {
            values = zeroHost
        }
        let buffer = makeSharedUInt32Buffer(device: device, values: values)
        if entry.port == "resetn" { resetnBuffer = buffer }
        if entry.port == "ciphertext_char", entry.bitIndex < 8 {
            ctBuffers[entry.bitIndex] = buffer
        }
        primaryFeeds[placeholder] = MPSGraphTensorData(buffer, shape: vectorShape, dataType: .uInt32)
    }
    _ = resetnBuffer

    let stateBuffersA: [MTLBuffer] = compiler.dffNodes.map { _ in
        makeSharedUInt32Buffer(device: device, values: zeroHost)
    }
    let stateSetA: [MPSGraphTensorData] = stateBuffersA.map {
        MPSGraphTensorData($0, shape: vectorShape, dataType: .uInt32)
    }
    let stateBuffersB: [MTLBuffer] = compiler.dffNodes.map { _ in
        makeSharedUInt32Buffer(device: device, count: elementCount)
    }
    let stateSetB: [MPSGraphTensorData] = stateBuffersB.map {
        MPSGraphTensorData($0, shape: vectorShape, dataType: .uInt32)
    }

    func writeStateBit(dffIndex: Int, bit: UInt32) {
        let fill = MockTorusEncoding.encodeBit(bit, degree: degree)
        fill.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            stateBuffersA[dffIndex].contents().copyMemory(from: base, byteCount: raw.count)
        }
    }
    for (i, dffIndex) in rBits.enumerated() {
        writeStateBit(dffIndex: dffIndex, bit: UInt32((right >> i) & 1))
    }
    for (i, dffIndex) in mBits.enumerated() {
        writeStateBit(dffIndex: dffIndex, bit: UInt32((middle >> i) & 1))
    }
    for (i, dffIndex) in lBits.enumerated() {
        writeStateBit(dffIndex: dffIndex, bit: UInt32((left >> i) & 1))
    }

    var stateFeeds = stateSetA
    var writeToB = true
    var plaintext: [Int] = []

    for letter in ciphertext {
        for bitIndex in 0..<8 {
            guard let buffer = ctBuffers[bitIndex] else { continue }
            let bit: UInt32 = ((letter >> bitIndex) & 1) == 0 ? 0 : 1
            let host = bit == 0 ? zeroHost : oneHost
            host.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                buffer.contents().copyMemory(from: base, byteCount: raw.count)
            }
        }

        let stateWrites = writeToB ? stateSetB : stateSetA
        var feeds = primaryFeeds
        for (index, dff) in compiler.dffNodes.enumerated() {
            guard let placeholder = dff.stateInput.placeholder else {
                throw MockPBSTestError.missingPlaceholder
            }
            feeds[placeholder] = stateFeeds[index]
        }

        var results: [MPSGraphTensor: MPSGraphTensorData] = [:]
        // plaintext_char is registered — sample Q_next from stateWrites (cleartext post-update).
        var ptDFFIndices: [Int: Int] = [:]
        if let ptBits = module.ports["plaintext_char"]?.bits {
            for (bitIndex, bit) in ptBits.enumerated() {
                guard case .net(let wire) = bit, let dffIndex = qWireToDFF[wire] else { continue }
                ptDFFIndices[bitIndex] = dffIndex
            }
        }
        for entry in compiler.outputTensors {
            let buffer = makeSharedUInt32Buffer(device: device, count: elementCount)
            results[entry.tensor] = MPSGraphTensorData(
                buffer, shape: vectorShape, dataType: .uInt32
            )
        }
        for (index, dff) in compiler.dffNodes.enumerated() {
            guard let stateOutput = dff.stateOutput else {
                throw MockPBSTestError.missingPlaceholder
            }
            results[stateOutput] = stateWrites[index]
        }

        compiler.graph.run(
            with: commandQueue,
            feeds: feeds,
            targetOperations: nil,
            resultsDictionary: results
        )

        let writeBuffers = writeToB ? stateBuffersB : stateBuffersA
        var value = 0
        for bit in 0..<5 {
            guard let dffIndex = ptDFFIndices[bit] else { continue }
            let ptr = writeBuffers[dffIndex].contents().bindMemory(
                to: UInt32.self, capacity: elementCount
            )
            if MockTorusEncoding.decodeBit(buffer: ptr, lane: 0, degree: degree) != 0 {
                value |= (1 << bit)
            }
        }
        plaintext.append(value)
        stateFeeds = stateWrites
        writeToB.toggle()
    }
    return plaintext
}
