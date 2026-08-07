import Foundation
import Metal
import MetalPerformanceShadersGraph

// MARK: - Constants

package let polynomialDegree = 1024
/// Application #1: single ciphertext stream so temporal DFF routing stays easy to verify.
package let batchSize = 1
/// Host-emulated clock: each iteration is one posedge.
package let clockCycles = 5

// MARK: - Deterministic UInt32 PRNG (no floating-point)

package struct LCG32 {
    package var state: UInt32

    package mutating func next() -> UInt32 {
        // Numerical Recipes LCG; wraps naturally in UInt32.
        state = state &* 1_664_525 &+ 1_013_904_223
        return state
    }
}

package func randomPolynomial(count: Int, seed: UInt32) -> [UInt32] {
    var rng = LCG32(state: seed)
    return (0..<count).map { _ in rng.next() }
}

/// Deterministic test polynomial keyed by a Yosys LUT truth-table string.
package func polynomialFromLUTTruthTable(_ lut: String, degree: Int) -> [UInt32] {
    var seed: UInt32 = 0x4C55_5401 // "LUT\x01"
    for byte in lut.utf8 {
        seed = seed &* 167_776_19 &+ UInt32(byte)
    }
    return randomPolynomial(count: degree, seed: seed | 1)
}

// MARK: - Host: Negacyclic Toeplitz expansion (Phase 1)

/// Builds `M_A` where the first column is `A`, and each next column is the previous
/// shifted down by one with the wrapped element negated (`0 &- v` in UInt32).
package func expandNegacyclicToeplitz(_ polynomial: [UInt32]) -> [UInt32] {
    let degree = polynomial.count
    var matrix = [UInt32](repeating: 0, count: degree * degree)

    for row in 0..<degree {
        matrix[row * degree] = polynomial[row]
    }

    for col in 1..<degree {
        for row in 0..<degree {
            if row == 0 {
                matrix[col] = 0 &- matrix[(degree - 1) * degree + (col - 1)]
            } else {
                matrix[row * degree + col] = matrix[(row - 1) * degree + (col - 1)]
            }
        }
    }
    return matrix
}

// MARK: - MTLBuffer helpers

package func makeSharedUInt32Buffer(device: MTLDevice, values: [UInt32]) -> MTLBuffer {
    let byteCount = values.count * MemoryLayout<UInt32>.stride
    guard let buffer = device.makeBuffer(
        bytes: values,
        length: byteCount,
        options: .storageModeShared
    ) else {
        fatalError("Failed to allocate MTLBuffer (\(byteCount) bytes)")
    }
    return buffer
}

package func makeSharedUInt32Buffer(device: MTLDevice, count: Int) -> MTLBuffer {
    let byteCount = count * MemoryLayout<UInt32>.stride
    guard let buffer = device.makeBuffer(length: byteCount, options: .storageModeShared) else {
        fatalError("Failed to allocate MTLBuffer (\(byteCount) bytes)")
    }
    return buffer
}

// MARK: - Yosys JSON (write_json) Codable model

package struct YosysNetlist: Codable {
    package let creator: String?
    package let modules: [String: YosysModule]
}

package struct YosysModule: Codable {
    package let ports: [String: YosysPort]
    package let cells: [String: YosysCell]
    package let netnames: [String: YosysNetname]?
}

package struct YosysPort: Codable {
    package let direction: String
    package let bits: [YosysBit]
}

package struct YosysCell: Codable {
    package let type: String
    package let parameters: YosysCellParameters
    package let connections: [String: [YosysBit]]
    package let portDirections: [String: String]?

    package enum CodingKeys: String, CodingKey {
        case type, parameters, connections
        case portDirections = "port_directions"
    }
}

package struct YosysCellParameters: Codable {
    package let LUT: String?
    package let WIDTH: String?
}

package struct YosysNetname: Codable {
    package let bits: [YosysBit]
}

/// Yosys connection bit: net ID (Int) or constant `"0"` / `"1"`.
package enum YosysBit: Codable, Equatable {
    case net(Int)
    case constant(UInt32)

    package init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .net(value)
            return
        }
        let raw = try container.decode(String.self)
        switch raw {
        case "0":
            self = .constant(0)
        case "1":
            self = .constant(1)
        case "x", "X", "z", "Z":
            // Yosys undriven / high-Z — treat as encrypted 0 for HELUT feeds.
            self = .constant(0)
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported Yosys bit value '\(raw)'"
            )
        }
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .net(let id): try container.encode(id)
        case .constant(let value): try container.encode(value == 0 ? "0" : "1")
        }
    }

    package var netID: Int? {
        if case .net(let id) = self { return id }
        return nil
    }
}

package func parseYosysBinaryInt(_ binary: String) -> Int {
    Int(binary, radix: 2) ?? Int(binary) ?? 0
}

// MARK: - Netlist nodes

/// Compiles a circuit node into tensors on a shared `MPSGraph`.
protocol CircuitNode: AnyObject {
    var name: String { get }
    /// Builds this node's output tensor from already-compiled upstream tensors.
    func compile(graph: MPSGraph, inputs: [MPSGraphTensor]) -> MPSGraphTensor
}

/// Dynamic ciphertext placeholder. Shape `[B, N]` for tensor-batch evaluation.
package final class InputNode: CircuitNode {
    package let name: String
    package let degree: Int
    package let batch: Int
    package private(set) var placeholder: MPSGraphTensor?

    package init(name: String, degree: Int = polynomialDegree, batch: Int = batchSize) {
        self.name = name
        self.degree = degree
        self.batch = batch
    }

    package func compile(graph: MPSGraph, inputs: [MPSGraphTensor]) -> MPSGraphTensor {
        precondition(inputs.isEmpty, "InputNode '\(name)' takes no upstream wires")
        let shape: [NSNumber] = [NSNumber(value: batch), NSNumber(value: degree)]
        let tensor = graph.placeholder(shape: shape, dataType: .uInt32, name: name)
        placeholder = tensor
        return tensor
    }
}

/// Homomorphic XOR via free torus addition (`A + B` with UInt32 wraparound).
package final class AddNode: CircuitNode {
    package let name: String

    package init(name: String) {
        self.name = name
    }

    package func compile(graph: MPSGraph, inputs: [MPSGraphTensor]) -> MPSGraphTensor {
        precondition(inputs.count == 2, "AddNode '\(name)' requires exactly two inputs")
        return graph.addition(inputs[0], inputs[1], name: name)
    }
}

/// Programmable bootstrapping / LUT evaluation via dense negacyclic matvec.
///
/// `MPSGraph.matrixMultiplication` rejects `UInt32`, so this reuses the Phase 1
/// workaround with a batch axis: reshape `[B, N]` → `[B, 1, N]`, broadcast-multiply
/// against the static `[N, N]` matrix (→ `[B, N, N]`), then `reductionSum` on axis 2
/// and reshape back to `[B, N]` for cascading.
package final class LUTNode: CircuitNode {
    package let name: String
    package let degree: Int
    package let batch: Int
    /// Host-side Negacyclic Toeplitz matrix (`N×N` row-major `UInt32`).
    package let matrix: [UInt32]
    package private(set) var matrixPlaceholder: MPSGraphTensor?

    package init(
        name: String,
        matrix: [UInt32],
        degree: Int = polynomialDegree,
        batch: Int = batchSize
    ) {
        precondition(matrix.count == degree * degree)
        self.name = name
        self.degree = degree
        self.batch = batch
        self.matrix = matrix
    }

    package func compile(graph: MPSGraph, inputs: [MPSGraphTensor]) -> MPSGraphTensor {
        precondition(!inputs.isEmpty, "LUTNode '\(name)' requires at least one vector input")

        // Pack multi-input LUT wires via free torus addition, then PBS.
        var packed = inputs[0]
        for index in 1..<inputs.count {
            packed = graph.addition(
                packed,
                inputs[index],
                name: "\(name)_pack_\(index)"
            )
        }

        let matrixShape: [NSNumber] = [NSNumber(value: degree), NSNumber(value: degree)]
        let matrixTensor = graph.placeholder(
            shape: matrixShape,
            dataType: .uInt32,
            name: "\(name)_M"
        )
        matrixPlaceholder = matrixTensor

        // [B, N] → [B, 1, N] so Hadamard against [N, N] broadcasts to [B, N, N].
        let batchVecShape: [NSNumber] = [
            NSNumber(value: batch),
            NSNumber(value: 1),
            NSNumber(value: degree)
        ]
        let packed3D = graph.reshape(packed, shape: batchVecShape, name: "\(name)_batch_vec")

        let products = graph.multiplication(
            matrixTensor,
            packed3D,
            name: "\(name)_Hadamard"
        )
        let reduced = graph.reductionSum(
            with: products,
            axis: 2,
            name: "\(name)_reduce"
        )
        // Collapse back to [B, N] for the next LUT / output port.
        let outShape: [NSNumber] = [NSNumber(value: batch), NSNumber(value: degree)]
        return graph.reshape(reduced, shape: outShape, name: name)
    }
}

// MARK: - Yosys → MPSGraph compiler

package struct CompiledInput {
    package let port: String
    package let bitIndex: Int
    package let node: InputNode
}

package struct CompiledLUT {
    package let cell: String
    package let node: LUTNode
}

package struct CompiledOutput {
    package let port: String
    package let bitIndex: Int
    package let tensor: MPSGraphTensor
}

/// One D-flip-flop: `Q` is a state placeholder; `stateOutput` is next-state (`Q_next`) after each tick.
package struct CompiledDFF {
    package let cell: String
    package let type: String
    package let stateInput: InputNode
    /// Next-state tensor (`Q_next`), filled after combinational LUTs (+ optional DFFE mux) resolve.
    package private(set) var stateOutput: MPSGraphTensor?

    package mutating func bindStateOutput(_ tensor: MPSGraphTensor) {
        stateOutput = tensor
    }
}

package struct EvaluatedOutput {
    package let port: String
    package let bitIndex: Int
    package let data: MPSGraphTensorData

    package var label: String {
        bitIndex == 0 ? port : "\(port)[\(bitIndex)]"
    }
}

package struct ClockTickResult {
    package let tick: Int
    package let outputs: [EvaluatedOutput]
    package let stateOutputs: [MPSGraphTensorData]
    package let elapsedSeconds: Double
}

/// Yosys sequential cell types treated as host-clocked state (posedge).
/// Matches `$_DFF*`, `$_DFFE*`, `$_SDFF*`, `$_SDFFE*`, `$_SDFFCE*`, …
package func isYosysDFFType(_ type: String) -> Bool {
    guard type.hasPrefix("$_"), type.hasSuffix("_") else { return false }
    let kind = type.dropFirst(2).split(separator: "_").first.map(String.init) ?? ""
    return kind.contains("DFF")
}

/// Polarity / reset-value fields encoded in Yosys gate type names (e.g. `$_SDFFE_PN0P_`).
package struct YosysDFFPolarity {
    /// `nil` when the cell type has no enable pin.
    package let enableActiveHigh: Bool?
    /// Sync-reset pin polarity and constant value when reset is asserted (`nil` if no `R`).
    package let syncReset: (activeHigh: Bool, value: UInt32)?
}

/// Parses enable / sync-reset polarity from a Yosys DFF type string.
package func parseYosysDFFPolarity(_ type: String) -> YosysDFFPolarity {
    guard type.hasPrefix("$_"), type.hasSuffix("_") else {
        return YosysDFFPolarity(enableActiveHigh: nil, syncReset: nil)
    }
    let parts = type.dropFirst(2).dropLast().split(separator: "_")
    guard parts.count >= 2 else {
        return YosysDFFPolarity(enableActiveHigh: nil, syncReset: nil)
    }
    let kind = String(parts[0])
    let code = String(parts[1])
    let chars = Array(code)

    var enableActiveHigh: Bool?
    if kind.contains("DFFE") || kind.contains("DFFCE") || kind.hasSuffix("CE") {
        if let last = chars.last, last == "P" || last == "N" {
            enableActiveHigh = (last == "P")
        }
    }

    var syncReset: (activeHigh: Bool, value: UInt32)?
    if kind.contains("SDFF"), chars.count >= 3 {
        let resetPol = chars[1]
        let resetVal = chars[2]
        if resetPol == "P" || resetPol == "N", resetVal == "0" || resetVal == "1" {
            syncReset = (resetPol == "P", resetVal == "1" ? 1 : 0)
        }
    }

    return YosysDFFPolarity(enableActiveHigh: enableActiveHigh, syncReset: syncReset)
}

/// Compiles a Yosys module into one `MPSGraph`, routing wires by Yosys net ID.
package final class YosysGraphCompiler {
    package let degree: Int
    package let batch: Int
    package let graph = MPSGraph()

    /// Yosys wire ID → live tensor (inputs, LUT outputs, DFF Q, constants).
    package private(set) var wires: [Int: MPSGraphTensor] = [:]
    package private(set) var inputNodes: [CompiledInput] = []
    package private(set) var lutNodes: [CompiledLUT] = []
    package private(set) var dffNodes: [CompiledDFF] = []
    package private(set) var outputTensors: [CompiledOutput] = []

    /// Reused across `runClockCycles` so repeated calls do not re-allocate N×N LUT matrices.
    private var cachedPrimaryFeeds: [MPSGraphTensor: MPSGraphTensorData]?
    private var cachedMatrixFeeds: [MPSGraphTensor: MPSGraphTensorData]?
    private var cachedOutputScratch: [MPSGraphTensorData]?
    private var cachedStateSetA: [MPSGraphTensorData]?
    private var cachedStateSetB: [MPSGraphTensorData]?

    /// Host wall time spent inside `expandNegacyclicToeplitz` during the last `compile`.
    package private(set) var lastToeplitzExpandSeconds: Double = 0
    /// Host wall time for the remainder of `compile` (placeholders, wiring, DFF muxes).
    package private(set) var lastGraphBuildSeconds: Double = 0

    package init(degree: Int = polynomialDegree, batch: Int = batchSize) {
        self.degree = degree
        self.batch = batch
    }

    package func compile(moduleName: String, module: YosysModule) {
        lastToeplitzExpandSeconds = 0
        let compileStarted = CFAbsoluteTimeGetCurrent()
        compileInputPorts(module.ports)
        // Register Q placeholders before LUTs so sequential feedback nets resolve.
        compileDFFStateInputs(module.cells)
        compileLUTCells(module.cells)
        compileDFFStateOutputs(module.cells)
        compileOutputPorts(module.ports)
        let total = CFAbsoluteTimeGetCurrent() - compileStarted
        lastGraphBuildSeconds = max(0, total - lastToeplitzExpandSeconds)
        print(
            "Compiled module '\(moduleName)': "
                + "\(inputNodes.count) inputs, \(lutNodes.count) LUTs, "
                + "\(dffNodes.count) DFFs, \(outputTensors.count) outputs"
        )
        print(
            String(
                format: "Compile breakdown: Toeplitz expand %.2f s, graph build %.2f s (total %.2f s)",
                lastToeplitzExpandSeconds,
                lastGraphBuildSeconds,
                total
            )
        )
    }

    private func compileInputPorts(_ ports: [String: YosysPort]) {
        for (portName, port) in ports.sorted(by: { $0.key < $1.key }) where port.direction == "input" {
            for (bitIndex, bit) in port.bits.enumerated() {
                guard case .net(let wireID) = bit else {
                    fatalError("Input port '\(portName)[\(bitIndex)]' is not a net")
                }
                let node = InputNode(name: "\(portName)_\(bitIndex)", degree: degree, batch: batch)
                wires[wireID] = node.compile(graph: graph, inputs: [])
                inputNodes.append(CompiledInput(port: portName, bitIndex: bitIndex, node: node))
            }
        }
    }

    /// Phase A: each DFF `Q` becomes a `StateInputNode` placeholder (current register value).
    private func compileDFFStateInputs(_ cells: [String: YosysCell]) {
        for (cellName, cell) in cells.sorted(by: { $0.key < $1.key }) where isYosysDFFType(cell.type) {
            guard let qBits = cell.connections["Q"],
                  let qBit = qBits.first,
                  case .net(let qWire) = qBit else {
                fatalError("DFF '\(cellName)' missing Q net")
            }
            precondition(wires[qWire] == nil, "DFF '\(cellName)' Q wire \(qWire) already driven")
            let node = InputNode(
                name: "state_in_\(sanitizeName(cellName))",
                degree: degree,
                batch: batch
            )
            wires[qWire] = node.compile(graph: graph, inputs: [])
            dffNodes.append(CompiledDFF(cell: cellName, type: cell.type, stateInput: node))
        }
    }

    /// Phase B: bind next-state. Plain DFF → `D`. DFFE with mapped `E` →
    /// `Q_next = (E * D) + ((1 - E) * Q)` (enable polarity from the Yosys type).
    /// Sync-reset (`R`) cells additionally mux in the typed reset constant.
    private func compileDFFStateOutputs(_ cells: [String: YosysCell]) {
        for index in dffNodes.indices {
            let cellName = dffNodes[index].cell
            let cellType = dffNodes[index].type
            guard let cell = cells[cellName],
                  let dBits = cell.connections["D"],
                  let dBit = dBits.first else {
                fatalError("DFF '\(cellName)' missing D connection")
            }
            let polarity = parseYosysDFFPolarity(cellType)
            let base = sanitizeName(cellName)
            let one = constantTensor(value: 1)
            let dTensor = resolveConnectionBit(dBit, label: "DFF '\(cellName)' D")
            var qNext: MPSGraphTensor = dTensor

            if let eBits = cell.connections["E"], let eBit = eBits.first {
                let rawE = resolveConnectionBit(eBit, label: "DFF '\(cellName)' E")
                guard let qTensor = dffNodes[index].stateInput.placeholder else {
                    fatalError("DFF '\(cellName)' missing Q placeholder")
                }
                let enableActiveHigh = polarity.enableActiveHigh ?? true
                let eTensor: MPSGraphTensor
                if enableActiveHigh {
                    eTensor = rawE
                } else {
                    eTensor = graph.subtraction(one, rawE, name: "\(base)_E_active")
                }
                let oneMinusE = graph.subtraction(one, eTensor, name: "\(base)_notE")
                let eTimesD = graph.multiplication(eTensor, dTensor, name: "\(base)_E_D")
                let holdQ = graph.multiplication(oneMinusE, qTensor, name: "\(base)_holdQ")
                qNext = graph.addition(eTimesD, holdQ, name: "\(base)_enabled")
            }

            if let rBits = cell.connections["R"], let rBit = rBits.first {
                let rawR = resolveConnectionBit(rBit, label: "DFF '\(cellName)' R")
                let reset = polarity.syncReset ?? (activeHigh: true, value: 0)
                let resetAsserted: MPSGraphTensor
                if reset.activeHigh {
                    resetAsserted = rawR
                } else {
                    resetAsserted = graph.subtraction(one, rawR, name: "\(base)_R_active")
                }
                let oneMinusReset = graph.subtraction(one, resetAsserted, name: "\(base)_notR")
                let resetValue = constantTensor(value: reset.value)
                let cleared = graph.multiplication(resetAsserted, resetValue, name: "\(base)_rstVal")
                let held = graph.multiplication(oneMinusReset, qNext, name: "\(base)_rstHold")
                qNext = graph.addition(cleared, held, name: "\(base)_Qnext")
            }

            dffNodes[index].bindStateOutput(qNext)
        }
    }

    private func resolveConnectionBit(_ bit: YosysBit, label: String) -> MPSGraphTensor {
        switch bit {
        case .net(let id):
            guard let tensor = wires[id] else {
                fatalError("\(label) wire \(id) has no driver")
            }
            return tensor
        case .constant(let value):
            return constantTensor(value: value)
        }
    }

    private func compileLUTCells(_ cells: [String: YosysCell]) {
        var pending = cells.filter { $0.value.type == "$lut" }
        var stepsLeft = pending.count * pending.count + 1
        while !pending.isEmpty {
            stepsLeft -= 1
            precondition(stepsLeft > 0, "Yosys netlist has a cycle or unresolved LUT inputs")

            var progressed = false
            var stillPending: [String: YosysCell] = [:]
            for (cellName, cell) in pending {
                if tryCompileLUT(cellName: cellName, cell: cell) {
                    progressed = true
                } else {
                    stillPending[cellName] = cell
                }
            }
            precondition(progressed, "Yosys compile stuck: no LUT cell could be resolved")
            pending = stillPending
        }
    }

    /// Returns `false` when an input wire is not yet in the dictionary.
    private func tryCompileLUT(cellName: String, cell: YosysCell) -> Bool {
        guard let aBits = cell.connections["A"],
              let yBits = cell.connections["Y"],
              let yBit = yBits.first,
              case .net(let outWire) = yBit else {
            fatalError("Cell '\(cellName)' missing A/Y connections")
        }

        let lutTruth = cell.parameters.LUT ?? ""
        validateLUT(cellName: cellName, aBits: aBits, lutTruth: lutTruth, widthField: cell.parameters.WIDTH)

        guard let inputTensors = resolveLUTInputs(aBits: aBits) else {
            return false
        }

        let poly = polynomialFromLUTTruthTable(lutTruth, degree: degree)
        let expandStarted = CFAbsoluteTimeGetCurrent()
        let matrix = expandNegacyclicToeplitz(poly)
        lastToeplitzExpandSeconds += CFAbsoluteTimeGetCurrent() - expandStarted
        let node = LUTNode(
            name: sanitizeName(cellName),
            matrix: matrix,
            degree: degree,
            batch: batch
        )
        wires[outWire] = node.compile(graph: graph, inputs: inputTensors)
        lutNodes.append(CompiledLUT(cell: cellName, node: node))
        return true
    }

    private func validateLUT(
        cellName: String,
        aBits: [YosysBit],
        lutTruth: String,
        widthField: String?
    ) {
        guard let widthField else { return }
        let width = parseYosysBinaryInt(widthField)
        precondition(
            aBits.count == width,
            "Cell '\(cellName)': A has \(aBits.count) bits but WIDTH=\(width)"
        )
        guard !lutTruth.isEmpty else { return }
        let expected = 1 << width
        precondition(
            lutTruth.count == expected,
            "Cell '\(cellName)': LUT length \(lutTruth.count) != 2^\(width)"
        )
    }

    private func resolveLUTInputs(aBits: [YosysBit]) -> [MPSGraphTensor]? {
        var inputTensors: [MPSGraphTensor] = []
        for bit in aBits {
            switch bit {
            case .net(let id):
                guard let tensor = wires[id] else { return nil }
                inputTensors.append(tensor)
            case .constant(let value):
                inputTensors.append(constantTensor(value: value))
            }
        }
        return inputTensors
    }

    private func compileOutputPorts(_ ports: [String: YosysPort]) {
        for (portName, port) in ports.sorted(by: { $0.key < $1.key }) where port.direction == "output" {
            for (bitIndex, bit) in port.bits.enumerated() {
                let tensor: MPSGraphTensor
                switch bit {
                case .net(let wireID):
                    guard let driven = wires[wireID] else {
                        fatalError("Output port '\(portName)[\(bitIndex)]' wire \(wireID) has no driver")
                    }
                    tensor = driven
                case .constant(let value):
                    // Undriven Yosys outputs (`"x"`) decode as constant 0.
                    tensor = constantTensor(value: value)
                }
                outputTensors.append(CompiledOutput(port: portName, bitIndex: bitIndex, tensor: tensor))
            }
        }
    }

    private func constantTensor(value: UInt32) -> MPSGraphTensor {
        let shape: [NSNumber] = [NSNumber(value: batch), NSNumber(value: degree)]
        let values = [UInt32](repeating: value, count: batch * degree)
        let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
        return graph.constant(data, shape: shape, dataType: .uInt32)
    }

    private func sanitizeName(_ raw: String) -> String {
        String(raw.map { character in
            character.isLetter || character.isNumber ? character : "_"
        })
    }

    /// Runs `ticks` host-emulated clock cycles. Tick *n*'s `stateOutputs` feed tick *n+1*'s `stateInputs`.
    ///
    /// - Parameter retainHistory: When `true`, keep every tick's output/`stateOutput` buffers.
    ///   When `false` (default), ping-pong two state buffer sets and return one `ClockTickResult`
    ///   per tick (elapsed stats always; tensors only on the final tick).
    package func runClockCycles(
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        ticks: Int = clockCycles,
        retainHistory: Bool = false
    ) -> [ClockTickResult] {
        precondition(ticks > 0)
        precondition(!dffNodes.isEmpty, "Expected sequential DFF cells for clocked evaluation")
        for dff in dffNodes {
            precondition(dff.stateOutput != nil, "DFF '\(dff.cell)' missing state output (Q_next)")
            precondition(dff.stateInput.placeholder != nil, "DFF '\(dff.cell)' missing state input (Q)")
        }

        let vectorShape: [NSNumber] = [NSNumber(value: batch), NSNumber(value: degree)]
        let matrixShape: [NSNumber] = [NSNumber(value: degree), NSNumber(value: degree)]
        let primaryFeeds = makePrimaryInputFeeds(device: device, shape: vectorShape)
        let matrixFeeds = makeMatrixFeeds(device: device, shape: matrixShape)
        let pool = prepareClockBufferPool(device: device, shape: vectorShape)

        var stateFeeds = pool.stateSetA
        var writeToB = true
        var tickResults: [ClockTickResult] = []
        tickResults.reserveCapacity(ticks)

        for tick in 1...ticks {
            let tickResult: ClockTickResult = autoreleasepool {
                executeClockTick(
                    tick: tick,
                    ticks: ticks,
                    retainHistory: retainHistory,
                    device: device,
                    commandQueue: commandQueue,
                    vectorShape: vectorShape,
                    primaryFeeds: primaryFeeds,
                    matrixFeeds: matrixFeeds,
                    pool: pool,
                    stateFeeds: &stateFeeds,
                    writeToB: &writeToB
                )
            }
            tickResults.append(tickResult)
        }
        return tickResults
    }

    private struct ClockBufferPool {
        let stateSetA: [MPSGraphTensorData]
        let stateSetB: [MPSGraphTensorData]
        let outputScratch: [MPSGraphTensorData]
        let elementCount: Int
    }

    private func prepareClockBufferPool(
        device: MTLDevice,
        shape: [NSNumber]
    ) -> ClockBufferPool {
        let elementCount = batch * degree
        let zeroHost = [UInt32](repeating: 0, count: elementCount)
        let stateSetA: [MPSGraphTensorData] = dffNodes.map { _ in
            let buffer = makeSharedUInt32Buffer(device: device, values: zeroHost)
            return MPSGraphTensorData(buffer, shape: shape, dataType: .uInt32)
        }
        let stateSetB: [MPSGraphTensorData]
        if let cachedB = cachedStateSetB, cachedB.count == dffNodes.count {
            stateSetB = cachedB
        } else {
            stateSetB = dffNodes.map { _ in
                let buffer = makeSharedUInt32Buffer(device: device, count: elementCount)
                return MPSGraphTensorData(buffer, shape: shape, dataType: .uInt32)
            }
            cachedStateSetB = stateSetB
        }
        cachedStateSetA = stateSetA

        let outputScratch: [MPSGraphTensorData]
        if let scratch = cachedOutputScratch, scratch.count == outputTensors.count {
            outputScratch = scratch
        } else {
            outputScratch = outputTensors.map { _ in
                let buffer = makeSharedUInt32Buffer(device: device, count: elementCount)
                return MPSGraphTensorData(buffer, shape: shape, dataType: .uInt32)
            }
            cachedOutputScratch = outputScratch
        }
        return ClockBufferPool(
            stateSetA: stateSetA,
            stateSetB: stateSetB,
            outputScratch: outputScratch,
            elementCount: elementCount
        )
    }

    private func executeClockTick(
        tick: Int,
        ticks: Int,
        retainHistory: Bool,
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        vectorShape: [NSNumber],
        primaryFeeds: [MPSGraphTensor: MPSGraphTensorData],
        matrixFeeds: [MPSGraphTensor: MPSGraphTensorData],
        pool: ClockBufferPool,
        stateFeeds: inout [MPSGraphTensorData],
        writeToB: inout Bool
    ) -> ClockTickResult {
        let stateWrites: [MPSGraphTensorData]
        if retainHistory {
            stateWrites = dffNodes.map { _ in
                let buffer = makeSharedUInt32Buffer(device: device, count: pool.elementCount)
                return MPSGraphTensorData(buffer, shape: vectorShape, dataType: .uInt32)
            }
        } else {
            stateWrites = writeToB ? pool.stateSetB : pool.stateSetA
        }

        var feeds = primaryFeeds
        feeds.merge(matrixFeeds) { _, new in new }
        for (index, dff) in dffNodes.enumerated() {
            guard let placeholder = dff.stateInput.placeholder else {
                fatalError("Missing state-input placeholder for '\(dff.cell)'")
            }
            feeds[placeholder] = stateFeeds[index]
        }

        var resultsDictionary: [MPSGraphTensor: MPSGraphTensorData] = [:]
        var orderedOutputs: [EvaluatedOutput] = []
        let keepTensors = retainHistory || tick == ticks
        bindTickResultBuffers(
            retainHistory: retainHistory,
            keepTensors: keepTensors,
            device: device,
            vectorShape: vectorShape,
            pool: pool,
            stateWrites: stateWrites,
            resultsDictionary: &resultsDictionary,
            orderedOutputs: &orderedOutputs
        )

        let started = CFAbsoluteTimeGetCurrent()
        graph.run(
            with: commandQueue,
            feeds: feeds,
            targetOperations: nil,
            resultsDictionary: resultsDictionary
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - started

        for (bit, data) in stateWrites.enumerated() {
            let shape = data.shape.map(\.intValue)
            precondition(
                shape == [batch, degree],
                "Tick \(tick) stateOutput[\(bit)] shape \(shape) != [\(batch), \(degree)]"
            )
        }

        let result = ClockTickResult(
            tick: tick,
            outputs: keepTensors ? orderedOutputs : [],
            stateOutputs: keepTensors ? stateWrites : [],
            elapsedSeconds: elapsed
        )
        stateFeeds = stateWrites
        if !retainHistory {
            writeToB.toggle()
        }
        return result
    }

    private func bindTickResultBuffers(
        retainHistory: Bool,
        keepTensors: Bool,
        device: MTLDevice,
        vectorShape: [NSNumber],
        pool: ClockBufferPool,
        stateWrites: [MPSGraphTensorData],
        resultsDictionary: inout [MPSGraphTensor: MPSGraphTensorData],
        orderedOutputs: inout [EvaluatedOutput]
    ) {
        for (outIndex, entry) in outputTensors.enumerated() {
            let data: MPSGraphTensorData
            if retainHistory {
                let buffer = makeSharedUInt32Buffer(device: device, count: pool.elementCount)
                data = MPSGraphTensorData(buffer, shape: vectorShape, dataType: .uInt32)
            } else {
                data = pool.outputScratch[outIndex]
            }
            resultsDictionary[entry.tensor] = data
            if keepTensors {
                orderedOutputs.append(
                    EvaluatedOutput(port: entry.port, bitIndex: entry.bitIndex, data: data)
                )
            }
        }
        for (index, dff) in dffNodes.enumerated() {
            guard let stateOutput = dff.stateOutput else {
                fatalError("Missing state output for '\(dff.cell)'")
            }
            resultsDictionary[stateOutput] = stateWrites[index]
        }
    }

    /// Primary ports only (`clk`, `en`, …). `en` is forced to an encrypted `1`.
    private func makePrimaryInputFeeds(
        device: MTLDevice,
        shape: [NSNumber]
    ) -> [MPSGraphTensor: MPSGraphTensorData] {
        if let cachedPrimaryFeeds {
            return cachedPrimaryFeeds
        }
        var feeds: [MPSGraphTensor: MPSGraphTensorData] = [:]
        for entry in inputNodes {
            guard let placeholder = entry.node.placeholder else {
                fatalError("Missing placeholder for input '\(entry.port)'")
            }
            let values: [UInt32]
            if entry.port == "en" {
                // Mock ciphertext for plaintext 1 (enable asserted every tick).
                values = [UInt32](repeating: 1, count: batch * degree)
            } else if entry.port == "clk" {
                // Host loop is the clock; feed zeros so the unused placeholder is satisfied.
                values = [UInt32](repeating: 0, count: batch * degree)
            } else {
                values = randomPolynomial(
                    count: batch * degree,
                    seed: 0xA11CE001 &+ UInt32(entry.bitIndex) &* 0x9E37
                )
            }
            let buffer = makeSharedUInt32Buffer(device: device, values: values)
            feeds[placeholder] = MPSGraphTensorData(buffer, shape: shape, dataType: .uInt32)
        }
        cachedPrimaryFeeds = feeds
        return feeds
    }

    private func makeMatrixFeeds(
        device: MTLDevice,
        shape: [NSNumber]
    ) -> [MPSGraphTensor: MPSGraphTensorData] {
        if let cachedMatrixFeeds {
            return cachedMatrixFeeds
        }
        var feeds: [MPSGraphTensor: MPSGraphTensorData] = [:]
        for entry in lutNodes {
            guard let matrixPlaceholder = entry.node.matrixPlaceholder else {
                fatalError("Missing matrix placeholder for LUT '\(entry.cell)'")
            }
            let buffer = makeSharedUInt32Buffer(device: device, values: entry.node.matrix)
            feeds[matrixPlaceholder] = MPSGraphTensorData(buffer, shape: shape, dataType: .uInt32)
        }
        cachedMatrixFeeds = feeds
        return feeds
    }

}

// MARK: - Netlist loading

package func loadYosysNetlist(from path: String) -> YosysNetlist {
    let url = URL(fileURLWithPath: path)
    let data: Data
    do {
        data = try Data(contentsOf: url)
    } catch {
        fatalError("Failed to read netlist at \(path): \(error)")
    }
    do {
        return try JSONDecoder().decode(YosysNetlist.self, from: data)
    } catch {
        fatalError("Failed to decode Yosys JSON: \(error)")
    }
}

package func resolveNetlistPath(argument: String?) -> String {
    if let argument {
        return argument
    }
    let candidates = [
        "core_netlist.json",
        "../core_netlist.json",
        "../../core_netlist.json",
        "netlist.json",
        "../netlist.json",
        "../../netlist.json"
    ]
    let cwd = FileManager.default.currentDirectoryPath
    for relative in candidates {
        let path = URL(fileURLWithPath: cwd).appendingPathComponent(relative).path
        if FileManager.default.fileExists(atPath: path) {
            return path
        }
    }
    fatalError("core_netlist.json not found (cwd=\(cwd)). Pass an explicit path as argv[1].")
}
