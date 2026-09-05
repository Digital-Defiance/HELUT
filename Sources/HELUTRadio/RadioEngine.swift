import Foundation
import HELUTCore

/// Opaque engine behind the C ABI. Keeps package HELUTCore types out of the header.
final class RadioEngine {
    enum Mode: String {
        case clear
        case encryptedDemo = "encrypted-demo"
    }

    private struct LiteralMatcherDescriptor {
        /// For each input port in packed/lexicographic order, the byte-window index to use.
        let inputWindowIndices: [Int]
        let matchBitOffset: Int
    }

    let mode: Mode
    let moduleName: String
    let inputPorts: [(name: String, width: Int)]
    let outputPorts: [(name: String, width: Int)]
    private let clear: CleartextNetlistSimulator
    private var encrypted: EncryptedNetlistSimulator?
    private var regexWindow: [UInt8] = []
    private lazy var literalMatcherDescriptor: LiteralMatcherDescriptor? = Self.makeLiteralMatcherDescriptor(
        inputPorts: inputPorts,
        outputPorts: outputPorts
    )

    var inputBitCount: Int { inputPorts.reduce(0) { $0 + $1.width } }
    var outputBitCount: Int { outputPorts.reduce(0) { $0 + $1.width } }

    init(netlistPath: String, mode: Mode) throws {
        let netlist = loadYosysNetlist(from: netlistPath)
        guard let (moduleName, module) = netlist.modules.sorted(by: { $0.key < $1.key }).first else {
            throw RadioError.netlist("empty Yosys modules")
        }
        self.moduleName = moduleName
        self.mode = mode
        let clear = CleartextNetlistSimulator(moduleName: moduleName, module: module)
        self.clear = clear
        self.inputPorts = clear.inputPorts.keys.sorted().map { name in
            (name, clear.inputPorts[name]!.count)
        }
        self.outputPorts = clear.outputPorts.keys.sorted().map { name in
            (name, clear.outputPorts[name]!.count)
        }

        switch mode {
        case .clear:
            self.encrypted = nil
        case .encryptedDemo:
            // Demo N=8 only — production N=1024 encrypted SING is not claimed here.
            let degree = 8
            let params = GGSWParams.booleanTrivial(degree: degree)
            let secret = TFHESecretKey.random(params: params.tfhe, seed: 0xE4D10)
            self.encrypted = EncryptedNetlistSimulator(
                moduleName: moduleName,
                module: module,
                secret: secret,
                params: params,
                backend: .blindRotate,
                wireRefresh: .publicMS,
                seed: 0xE4D11
            )
        }
    }

    func reset() {
        clear.resetState()
        regexWindow.removeAll(keepingCapacity: true)
        // Encrypted sequential Q reset is not exposed on EncryptedNetlistSimulator;
        // combinational demos (regex / tree) do not need it.
    }

    func tick(inBits: [UInt8]) throws -> [UInt8] {
        precondition(inBits.count == inputBitCount, "input bit count mismatch")
        let inputs = unpackInputs(inBits)
        let outputs: [String: [UInt8]]
        switch mode {
        case .clear:
            outputs = clear.tick(inputs: inputs)
        case .encryptedDemo:
            guard let encrypted else { throw RadioError.internal("missing encrypted sim") }
            outputs = try encrypted.tick(inputs: inputs)
        }
        return packOutputs(outputs)
    }

    /// Literal-matcher convenience: sliding byte window → the one-bit `match` output.
    ///
    /// The netlist contract is contiguous 8-bit ports `char0...charN` plus a one-bit
    /// output named `match`. Window width is therefore derived from the circuit.
    func regexFeed(_ byte: UInt8) throws -> UInt8 {
        guard let descriptor = literalMatcherDescriptor else {
            throw RadioError.mode(
                "regex feed requires contiguous 8-bit ports char0...charN and a one-bit match output"
            )
        }

        let windowWidth = descriptor.inputWindowIndices.count
        regexWindow.append(byte)
        if regexWindow.count > windowWidth {
            regexWindow.removeFirst(regexWindow.count - windowWidth)
        }
        guard regexWindow.count == windowWidth else { return 0 }

        var bits: [UInt8] = []
        bits.reserveCapacity(inputBitCount)
        // Pack in the engine's lexicographic port order, but map each charN by its
        // numeric suffix so char10 cannot be mistaken for the byte after char1.
        for windowIndex in descriptor.inputWindowIndices {
            let value = regexWindow[windowIndex]
            for bitIndex in 0..<8 {
                bits.append((value >> bitIndex) & 1)
            }
        }

        let out = try tick(inBits: bits)
        guard descriptor.matchBitOffset < out.count else {
            throw RadioError.internal("match output offset exceeds packed output width")
        }
        return out[descriptor.matchBitOffset]
    }

    private static func makeLiteralMatcherDescriptor(
        inputPorts: [(name: String, width: Int)],
        outputPorts: [(name: String, width: Int)]
    ) -> LiteralMatcherDescriptor? {
        guard !inputPorts.isEmpty else { return nil }

        var windowIndices: [Int] = []
        windowIndices.reserveCapacity(inputPorts.count)
        for port in inputPorts {
            guard port.width == 8, port.name.hasPrefix("char") else { return nil }
            let suffix = String(port.name.dropFirst(4))
            guard let index = Int(suffix), index >= 0, suffix == String(index) else { return nil }
            windowIndices.append(index)
        }
        guard Set(windowIndices) == Set(0..<inputPorts.count) else { return nil }

        var packedOffset = 0
        var matchBitOffset: Int?
        for port in outputPorts {
            if port.name == "match" {
                guard port.width == 1, matchBitOffset == nil else { return nil }
                matchBitOffset = packedOffset
            }
            packedOffset += port.width
        }
        guard let matchBitOffset else { return nil }
        return LiteralMatcherDescriptor(
            inputWindowIndices: windowIndices,
            matchBitOffset: matchBitOffset
        )
    }

    private func unpackInputs(_ inBits: [UInt8]) -> [String: [UInt8]] {
        var offset = 0
        var inputs: [String: [UInt8]] = [:]
        for port in inputPorts {
            let slice = Array(inBits[offset..<(offset + port.width)])
            inputs[port.name] = slice
            offset += port.width
        }
        return inputs
    }

    private func packOutputs(_ outputs: [String: [UInt8]]) -> [UInt8] {
        var packed: [UInt8] = []
        packed.reserveCapacity(outputBitCount)
        for port in outputPorts {
            let bits = outputs[port.name] ?? Array(repeating: 0, count: port.width)
            precondition(bits.count == port.width)
            packed.append(contentsOf: bits)
        }
        return packed
    }
}

enum RadioError: Error, CustomStringConvertible {
    case netlist(String)
    case mode(String)
    case `internal`(String)

    var description: String {
        switch self {
        case .netlist(let s): return s
        case .mode(let s): return s
        case .internal(let s): return s
        }
    }
}
