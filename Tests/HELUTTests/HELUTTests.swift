import XCTest
import Metal
import MetalPerformanceShadersGraph
import Darwin
@testable import HELUTCore

// MARK: - CPU reference (exact ℤ/2³²ℤ schoolbook)

/// Row-major matvec with wrapping `UInt32` multiply-add: `out[i] = Σ_j M[i,j] * v[j] (mod 2^32)`.
func cpuSchoolbookMatvec(matrix: [UInt32], vector: [UInt32], degree: Int) -> [UInt32] {
    precondition(matrix.count == degree * degree)
    precondition(vector.count == degree)
    var out = [UInt32](repeating: 0, count: degree)
    for row in 0..<degree {
        var acc: UInt32 = 0
        let rowBase = row * degree
        for col in 0..<degree {
            acc = acc &+ (matrix[rowBase + col] &* vector[col])
        }
        out[row] = acc
    }
    return out
}

func readUInt32Buffer(_ buffer: MTLBuffer, count: Int) -> [UInt32] {
    let pointer = buffer.contents().bindMemory(to: UInt32.self, capacity: count)
    return Array(UnsafeBufferPointer(start: pointer, count: count))
}

func taskResidentMemoryBytes() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(
        MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
    )
    let result = withUnsafeMutablePointer(to: &info) { infoPtr in
        infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { raw in
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), raw, &count)
        }
    }
    precondition(result == KERN_SUCCESS, "task_info failed: \(result)")
    return info.resident_size
}

func resolveCoreNetlistPath() -> String? {
    let fileManager = FileManager.default
    let cwd = fileManager.currentDirectoryPath
    let candidates = [
        "core_netlist.json",
        "../core_netlist.json",
        "../../core_netlist.json",
        "../../../core_netlist.json"
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
        let candidate = url.appendingPathComponent("core_netlist.json").path
        if fileManager.fileExists(atPath: candidate) {
            return candidate
        }
    }
    return nil
}

func extremePattern(base: UInt32, degree: Int, offsets: [(Int, Int)]) -> [UInt32] {
    let extremes: [UInt32] = [0x0000_0000, 0x0000_0001, 0x8000_0000, 0xFFFF_FFFF]
    var values = [UInt32](repeating: base, count: degree)
    guard let baseIndex = extremes.firstIndex(of: base) else { return values }
    for (position, offset) in offsets where position < degree {
        values[position] = extremes[(baseIndex + offset) % extremes.count]
    }
    return values
}

func firstMismatch(got: [UInt32], expected: [UInt32]) -> (index: Int, got: UInt32, expected: UInt32)? {
    for index in 0..<min(got.count, expected.count) where got[index] != expected[index] {
        return (index, got[index], expected[index])
    }
    if got.count != expected.count {
        return (got.count, 0, 0)
    }
    return nil
}

func makeEnableZeroPrimaryFeeds(
    compiler: YosysGraphCompiler,
    device: MTLDevice,
    shape: [NSNumber]
) -> [MPSGraphTensor: MPSGraphTensorData]? {
    var feeds: [MPSGraphTensor: MPSGraphTensorData] = [:]
    let count = compiler.batch * compiler.degree
    for entry in compiler.inputNodes {
        guard let placeholder = entry.node.placeholder else { return nil }
        let values: [UInt32]
        switch entry.port {
        case "en", "clk":
            values = [UInt32](repeating: 0, count: count)
        default:
            values = randomPolynomial(count: count, seed: 0xDEAD_0001 &+ UInt32(entry.bitIndex))
        }
        let buffer = makeSharedUInt32Buffer(device: device, values: values)
        feeds[placeholder] = MPSGraphTensorData(buffer, shape: shape, dataType: .uInt32)
    }
    return feeds
}

func makeMatrixFeeds(
    compiler: YosysGraphCompiler,
    device: MTLDevice,
    shape: [NSNumber]
) -> [MPSGraphTensor: MPSGraphTensorData]? {
    var feeds: [MPSGraphTensor: MPSGraphTensorData] = [:]
    for entry in compiler.lutNodes {
        guard let matrixPlaceholder = entry.node.matrixPlaceholder else { return nil }
        let buffer = makeSharedUInt32Buffer(device: device, values: entry.node.matrix)
        feeds[matrixPlaceholder] = MPSGraphTensorData(buffer, shape: shape, dataType: .uInt32)
    }
    return feeds
}

func runHoldTick(
    compiler: YosysGraphCompiler,
    device: MTLDevice,
    commandQueue: MTLCommandQueue,
    primaryFeeds: [MPSGraphTensor: MPSGraphTensorData],
    matrixFeeds: [MPSGraphTensor: MPSGraphTensorData],
    stateFeeds: [MPSGraphTensorData],
    vectorShape: [NSNumber]
) -> (nextState: [MPSGraphTensorData], nextBuffers: [MTLBuffer])? {
    var feeds = primaryFeeds
    feeds.merge(matrixFeeds) { _, new in new }
    for (index, dff) in compiler.dffNodes.enumerated() {
        guard let placeholder = dff.stateInput.placeholder else { return nil }
        feeds[placeholder] = stateFeeds[index]
    }

    var resultsDictionary: [MPSGraphTensor: MPSGraphTensorData] = [:]
    var nextBuffers: [MTLBuffer] = []
    var nextState: [MPSGraphTensorData] = []
    let elementCount = compiler.batch * compiler.degree
    for dff in compiler.dffNodes {
        guard let stateOutput = dff.stateOutput else { return nil }
        let buffer = makeSharedUInt32Buffer(device: device, count: elementCount)
        let data = MPSGraphTensorData(buffer, shape: vectorShape, dataType: .uInt32)
        resultsDictionary[stateOutput] = data
        nextBuffers.append(buffer)
        nextState.append(data)
    }
    for entry in compiler.outputTensors {
        let buffer = makeSharedUInt32Buffer(device: device, count: elementCount)
        resultsDictionary[entry.tensor] = MPSGraphTensorData(
            buffer, shape: vectorShape, dataType: .uInt32
        )
    }

    compiler.graph.run(
        with: commandQueue,
        feeds: feeds,
        targetOperations: nil,
        resultsDictionary: resultsDictionary
    )
    return (nextState, nextBuffers)
}

// MARK: - Adversarial suite

final class HELUTTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Bit-exact equality: CPU `UInt32` schoolbook matvec vs MPSGraph Hadamard + `reductionSum`.
    func testNegacyclicModuloFidelity() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device")
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw XCTSkip("No MTLCommandQueue")
        }

        let degree = 64
        let batch = 1
        let extremes: [UInt32] = [0x0000_0000, 0x0000_0001, 0x8000_0000, 0xFFFF_FFFF]

        for polySeed in extremes {
            for vecSeed in extremes {
                let polynomial = extremePattern(
                    base: polySeed,
                    degree: degree,
                    offsets: [(1, 1), (degree / 2, 2)]
                )
                let vector = extremePattern(
                    base: vecSeed,
                    degree: degree,
                    offsets: [(0, 1), (degree - 1, 3)]
                )
                let matrix = expandNegacyclicToeplitz(polynomial)
                let expected = cpuSchoolbookMatvec(matrix: matrix, vector: vector, degree: degree)

                let graph = MPSGraph()
                let lut = LUTNode(name: "fidelity_lut", matrix: matrix, degree: degree, batch: batch)
                let input = InputNode(name: "fidelity_in", degree: degree, batch: batch)
                let inputTensor = input.compile(graph: graph, inputs: [])
                let outputTensor = lut.compile(graph: graph, inputs: [inputTensor])

                guard let matrixPlaceholder = lut.matrixPlaceholder,
                      let inputPlaceholder = input.placeholder else {
                    return XCTFail("Missing placeholders")
                }

                let vectorShape: [NSNumber] = [NSNumber(value: batch), NSNumber(value: degree)]
                let matrixShape: [NSNumber] = [NSNumber(value: degree), NSNumber(value: degree)]
                let vectorBuffer = makeSharedUInt32Buffer(device: device, values: vector)
                let matrixBuffer = makeSharedUInt32Buffer(device: device, values: matrix)
                let resultBuffer = makeSharedUInt32Buffer(device: device, count: batch * degree)

                graph.run(
                    with: commandQueue,
                    feeds: [
                        inputPlaceholder: MPSGraphTensorData(
                            vectorBuffer, shape: vectorShape, dataType: .uInt32
                        ),
                        matrixPlaceholder: MPSGraphTensorData(
                            matrixBuffer, shape: matrixShape, dataType: .uInt32
                        )
                    ],
                    targetOperations: nil,
                    resultsDictionary: [
                        outputTensor: MPSGraphTensorData(
                            resultBuffer, shape: vectorShape, dataType: .uInt32
                        )
                    ]
                )

                XCTAssertEqual(outputTensor.dataType, .uInt32)
                let got = readUInt32Buffer(resultBuffer, count: degree)
                if let mismatch = firstMismatch(got: got, expected: expected) {
                    XCTFail(
                        "poly=0x\(String(polySeed, radix: 16)) vec=0x\(String(vecSeed, radix: 16)): "
                            + "MPSGraph ≠ CPU at coeff[\(mismatch.index)] "
                            + "(got=\(mismatch.got) expected=\(mismatch.expected))"
                    )
                }
            }
        }
    }

    /// When E=0, register Q must remain identical to the T₀ state across multiple ticks.
    ///
    /// Engine under test ignores the DFFE `E` pin and always commits `D` → next `Q`.
    /// This test feeds `en = 0` via the primary port without modifying engine code.
    func testDFFEnableHoldSemantics() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device")
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw XCTSkip("No MTLCommandQueue")
        }
        guard let path = resolveCoreNetlistPath() else {
            return XCTFail("core_netlist.json not found")
        }

        let netlist = loadYosysNetlist(from: path)
        guard let (moduleName, module) = netlist.modules.first else {
            return XCTFail("Empty netlist")
        }

        let compiler = YosysGraphCompiler(degree: polynomialDegree, batch: batchSize)
        compiler.compile(moduleName: moduleName, module: module)
        XCTAssertFalse(compiler.dffNodes.isEmpty)
        XCTAssertTrue(
            compiler.dffNodes.contains { $0.type.contains("DFFE") },
            "Expected enable-capable DFF cells in core_netlist"
        )

        let vectorShape: [NSNumber] = [NSNumber(value: batchSize), NSNumber(value: polynomialDegree)]
        let matrixShape: [NSNumber] = [NSNumber(value: polynomialDegree), NSNumber(value: polynomialDegree)]
        let elementCount = batchSize * polynomialDegree

        let t0State: [[UInt32]] = compiler.dffNodes.indices.map { bit in
            (0..<elementCount).map { offset in
                (0xA5A5_0000 &+ UInt32(bit)) &+ UInt32(offset &* 0x1001)
            }
        }
        var stateFeeds: [MPSGraphTensorData] = t0State.map { values in
            let buffer = makeSharedUInt32Buffer(device: device, values: values)
            return MPSGraphTensorData(buffer, shape: vectorShape, dataType: .uInt32)
        }

        guard let primaryFeeds = makeEnableZeroPrimaryFeeds(
            compiler: compiler, device: device, shape: vectorShape
        ), let matrixFeeds = makeMatrixFeeds(
            compiler: compiler, device: device, shape: matrixShape
        ) else {
            return XCTFail("Failed to build feeds")
        }

        for tick in 1...4 {
            guard let tickResult = runHoldTick(
                compiler: compiler,
                device: device,
                commandQueue: commandQueue,
                primaryFeeds: primaryFeeds,
                matrixFeeds: matrixFeeds,
                stateFeeds: stateFeeds,
                vectorShape: vectorShape
            ) else {
                return XCTFail("Hold tick \(tick) failed to build graph I/O")
            }

            for (bit, buffer) in tickResult.nextBuffers.enumerated() {
                let got = readUInt32Buffer(buffer, count: elementCount)
                if let mismatch = firstMismatch(got: got, expected: t0State[bit]) {
                    let dff = compiler.dffNodes[bit]
                    XCTFail(
                        "E=0 hold violated at tick \(tick), DFF bit \(bit) "
                            + "(\(dff.cell) type=\(dff.type)): Q left T₀ at coeff[\(mismatch.index)] "
                            + "(got=0x\(String(mismatch.got, radix: 16)), "
                            + "T₀=0x\(String(mismatch.expected, radix: 16))). "
                            + "Root cause: compileDFFStateOutputs binds D only; E pin is ignored."
                    )
                }
            }
            stateFeeds = tickResult.nextState
        }
    }

    /// 1,000 clock ticks; resident memory must stay flat after graph compilation / warmup.
    func testLongClockMemoryStability() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device")
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw XCTSkip("No MTLCommandQueue")
        }
        guard let path = resolveCoreNetlistPath() else {
            return XCTFail("core_netlist.json not found")
        }

        let netlist = loadYosysNetlist(from: path)
        guard let (moduleName, module) = netlist.modules.first else {
            return XCTFail("Empty netlist")
        }

        let compiler = YosysGraphCompiler(degree: polynomialDegree, batch: batchSize)
        compiler.compile(moduleName: moduleName, module: module)

        _ = compiler.runClockCycles(device: device, commandQueue: commandQueue, ticks: 5)

        let baseline = taskResidentMemoryBytes()
        let totalTicks = 1_000
        let results = compiler.runClockCycles(
            device: device,
            commandQueue: commandQueue,
            ticks: totalTicks
        )
        XCTAssertEqual(results.count, totalTicks)

        let finalRSS = taskResidentMemoryBytes()
        let growth = finalRSS &- min(finalRSS, baseline)
        let maxGrowthBytes: UInt64 = 8 * 1024 * 1024
        XCTAssertLessThanOrEqual(
            growth,
            maxGrowthBytes,
            """
            Resident memory grew by \(growth) bytes over \(totalTicks) ticks \
            (baseline=\(baseline), final=\(finalRSS)). \
            Expected flat RSS after compilation; growth implicates retained tick buffers / MTLBuffer leak.
            """
        )
    }
}
