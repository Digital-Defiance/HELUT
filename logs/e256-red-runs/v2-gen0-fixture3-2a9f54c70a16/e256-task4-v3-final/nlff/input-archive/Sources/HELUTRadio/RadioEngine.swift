import Foundation
import HELUTCore

/// Opaque engine behind the C ABI. Keeps package HELUTCore types out of the header.
final class RadioEngine {
    enum Mode: String {
        case clear
        case encryptedDemo = "encrypted-demo"
    }

    let mode: Mode
    let moduleName: String
    let inputPorts: [(name: String, width: Int)]
    let outputPorts: [(name: String, width: Int)]
    private let clear: CleartextNetlistSimulator
    private var encrypted: EncryptedNetlistSimulator?
    private var regexWindow: [UInt8] = []

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

    /// regex_matcher convenience: sliding 3-byte window → match bit.
    func regexFeed(_ byte: UInt8) throws -> UInt8 {
        let names = Set(inputPorts.map(\.name))
        guard names == Set(["char0", "char1", "char2"]),
              outputPorts.contains(where: { $0.name == "match" && $0.width == 1 }) else {
            throw RadioError.mode("regex feed requires ports char0/char1/char2 → match")
        }
        regexWindow.append(byte)
        if regexWindow.count > 3 {
            regexWindow.removeFirst(regexWindow.count - 3)
        }
        guard regexWindow.count == 3 else { return 0 }
        var bits: [UInt8] = []
        bits.reserveCapacity(24)
        for idx in 0..<3 {
            let value = regexWindow[idx]
            for i in 0..<8 {
                bits.append((value >> i) & 1)
            }
        }
        // Pack in lexicographic port order: char0, char1, char2 (matches inputPorts sort).
        let out = try tick(inBits: bits)
        return out.first ?? 0
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
