import Foundation

/// Cleartext evaluator for Yosys `$lut` / `$_SDFF*` netlists (real boolean bits).
///
/// Oracle for Metal boolean-safe mock PBS (`LUTNode` multilinear path) and for
/// Enigma letter-level validation without batch tensor plumbing.
package final class CleartextNetlistSimulator {
    package struct DFFCell {
        package let name: String
        package let type: String
        package let qWire: Int
        package let dBit: YosysBit
        package let resetBit: YosysBit?
        package let enableBit: YosysBit?
        package let polarity: YosysDFFPolarity
    }

    package struct LUTCell {
        package let name: String
        package let aBits: [YosysBit]
        package let yWire: Int
        /// Truth table: `table[inputBits]` → output bit (LSB = A[0]).
        package let table: [UInt8]
    }

    package let moduleName: String
    package let inputPorts: [String: [YosysBit]]
    package let outputPorts: [String: [YosysBit]]
    package let luts: [LUTCell]
    package let dffs: [DFFCell]
    package private(set) var state: [Int: UInt8] // Q wire → bit

    package init(moduleName: String, module: YosysModule) {
        self.moduleName = moduleName
        var inputs: [String: [YosysBit]] = [:]
        var outputs: [String: [YosysBit]] = [:]
        for (name, port) in module.ports {
            if port.direction == "input" {
                inputs[name] = port.bits
            } else if port.direction == "output" {
                outputs[name] = port.bits
            }
        }
        self.inputPorts = inputs
        self.outputPorts = outputs

        var compiledLUTs: [LUTCell] = []
        var compiledDFFs: [DFFCell] = []
        for (cellName, cell) in module.cells.sorted(by: { $0.key < $1.key }) {
            if cell.type == "$lut" {
                guard let aBits = cell.connections["A"],
                      let yBits = cell.connections["Y"],
                      let yBit = yBits.first,
                      case .net(let yWire) = yBit,
                      let lutTruth = cell.parameters.LUT else {
                    fatalError("Malformed $lut \(cellName)")
                }
                let table: [UInt8] = lutTruth.reversed().map { $0 == "1" ? 1 : 0 }
                // Yosys LUT string is MSB-first for highest address; bit i of string is entry 2^width-1-i
                // Actually Yosys documents LUT as binary string where leftmost char is for A=all-1s.
                // So table[mask] = lutTruth[lutTruth.count - 1 - mask].
                let width = aBits.count
                precondition(lutTruth.count == (1 << width), "LUT width mismatch in \(cellName)")
                var entries = [UInt8](repeating: 0, count: 1 << width)
                for mask in 0..<(1 << width) {
                    let charIndex = lutTruth.count - 1 - mask
                    entries[mask] = lutTruth[lutTruth.index(lutTruth.startIndex, offsetBy: charIndex)] == "1" ? 1 : 0
                }
                _ = table
                compiledLUTs.append(LUTCell(name: cellName, aBits: aBits, yWire: yWire, table: entries))
            } else if isYosysDFFType(cell.type) {
                guard let qBits = cell.connections["Q"],
                      let qBit = qBits.first,
                      case .net(let qWire) = qBit,
                      let dBits = cell.connections["D"],
                      let dBit = dBits.first else {
                    fatalError("Malformed DFF \(cellName)")
                }
                let resetBit = cell.connections["R"]?.first
                let enableBit = cell.connections["E"]?.first
                compiledDFFs.append(
                    DFFCell(
                        name: cellName,
                        type: cell.type,
                        qWire: qWire,
                        dBit: dBit,
                        resetBit: resetBit,
                        enableBit: enableBit,
                        polarity: parseYosysDFFPolarity(cell.type)
                    )
                )
            }
        }
        self.luts = compiledLUTs
        self.dffs = compiledDFFs
        self.state = [:]
        for dff in compiledDFFs {
            state[dff.qWire] = 0
        }
    }

    package func resetState(to bits: [Int: UInt8] = [:]) {
        state = [:]
        for dff in dffs {
            state[dff.qWire] = bits[dff.qWire] ?? 0
        }
    }

    /// One posedge: evaluate combinational LUTs from current Q + inputs, then update DFFs.
    @discardableResult
    package func tick(inputs: [String: [UInt8]]) -> [String: [UInt8]] {
        var wires: [Int: UInt8] = state
        for (port, bits) in inputs {
            guard let portBits = inputPorts[port] else { continue }
            precondition(bits.count == portBits.count, "Width mismatch on \(port)")
            for (index, bit) in portBits.enumerated() {
                if case .net(let wire) = bit {
                    wires[wire] = bits[index]
                }
            }
        }

        // Iterate LUTs to fixpoint (DAG / topo via relaxation).
        var pending = luts
        var guardCount = pending.count * pending.count + 1
        while !pending.isEmpty {
            guardCount -= 1
            precondition(guardCount > 0, "Combinational loop in cleartext sim")
            var still: [LUTCell] = []
            var progressed = false
            for lut in pending {
                if let aValues = resolveBits(lut.aBits, wires: wires) {
                    var mask = 0
                    for (index, bit) in aValues.enumerated() {
                        if bit != 0 { mask |= (1 << index) }
                    }
                    wires[lut.yWire] = lut.table[mask]
                    progressed = true
                } else {
                    still.append(lut)
                }
            }
            precondition(progressed, "Stuck cleartext LUT resolve")
            pending = still
        }

        // Next-state for each DFF.
        var nextState: [Int: UInt8] = [:]
        for dff in dffs {
            let dValue = resolveBit(dff.dBit, wires: wires) ?? 0
            var qNext = dValue

            if let enableBit = dff.enableBit {
                let rawE = resolveBit(enableBit, wires: wires) ?? 0
                let enableActiveHigh = dff.polarity.enableActiveHigh ?? true
                let enabled: UInt8 = enableActiveHigh ? rawE : (1 - rawE)
                let qCurrent = state[dff.qWire] ?? 0
                qNext = enabled != 0 ? dValue : qCurrent
            }

            if let resetBit = dff.resetBit {
                let rawR = resolveBit(resetBit, wires: wires) ?? 0
                let reset = dff.polarity.syncReset ?? (activeHigh: true, value: 0)
                let asserted: UInt8 = reset.activeHigh ? rawR : (1 - rawR)
                if asserted != 0 {
                    qNext = UInt8(reset.value)
                }
            }
            nextState[dff.qWire] = qNext
        }
        state = nextState

        var outputs: [String: [UInt8]] = [:]
        for (port, bits) in outputPorts {
            outputs[port] = bits.map { bit in
                resolveBit(bit, wires: wires.merging(state) { _, new in new }) ?? 0
            }
        }
        // Outputs sampled from post-update state for registered ports.
        for (port, bits) in outputPorts {
            outputs[port] = bits.map { bit -> UInt8 in
                switch bit {
                case .net(let wire):
                    return state[wire] ?? wires[wire] ?? 0
                case .constant(let value):
                    return UInt8(value)
                }
            }
        }
        return outputs
    }

    private func resolveBits(_ bits: [YosysBit], wires: [Int: UInt8]) -> [UInt8]? {
        var values: [UInt8] = []
        for bit in bits {
            guard let value = resolveBit(bit, wires: wires) else { return nil }
            values.append(value)
        }
        return values
    }

    private func resolveBit(_ bit: YosysBit, wires: [Int: UInt8]) -> UInt8? {
        switch bit {
        case .constant(let value):
            return UInt8(value)
        case .net(let id):
            return wires[id]
        }
    }
}

// MARK: - Enigma netlist helpers

package struct EnigmaNetlistHarness {
    package let simulator: CleartextNetlistSimulator
    package let module: YosysModule
    package let rotorRQ: [Int] // Q wires for rotor_r[0…]
    package let rotorMQ: [Int]
    package let rotorLQ: [Int]

    package init(netlistPath: String) {
        let netlist = loadYosysNetlist(from: netlistPath)
        guard let (name, module) = netlist.modules.first else {
            fatalError("Empty netlist at \(netlistPath)")
        }
        self.module = module
        self.simulator = CleartextNetlistSimulator(moduleName: name, module: module)

        func qWires(named net: String) -> [Int] {
            guard let bits = module.netnames?[net]?.bits else {
                fatalError("Missing netname \(net)")
            }
            return bits.compactMap { bit in
                if case .net(let id) = bit { return id }
                return nil
            }
        }
        rotorRQ = qWires(named: "rotor_r")
        rotorMQ = qWires(named: "rotor_m")
        rotorLQ = qWires(named: "rotor_l")
    }

    package func seedGrundstellung(left: Int, middle: Int, right: Int) {
        var bits: [Int: UInt8] = [:]
        for (index, wire) in rotorRQ.enumerated() {
            bits[wire] = UInt8((right >> index) & 1)
        }
        for (index, wire) in rotorMQ.enumerated() {
            bits[wire] = UInt8((middle >> index) & 1)
        }
        for (index, wire) in rotorLQ.enumerated() {
            bits[wire] = UInt8((left >> index) & 1)
        }
        simulator.resetState(to: bits)
    }

    /// Decrypt/encrypt `ciphertext` bytes (0…25) with `resetn=1`. Returns plaintext letters 0…25.
    package func process(ciphertext: [Int], resetn: UInt8 = 1) -> [Int] {
        var plain: [Int] = []
        plain.reserveCapacity(ciphertext.count)
        for char in ciphertext {
            var ctBits = [UInt8](repeating: 0, count: 8)
            for bit in 0..<8 {
                ctBits[bit] = UInt8((char >> bit) & 1)
            }
            let outputs = simulator.tick(
                inputs: [
                    "clk": [0],
                    "resetn": [resetn],
                    "ciphertext_char": ctBits
                ]
            )
            let bits = outputs["plaintext_char"] ?? []
            var value = 0
            for (index, bit) in bits.enumerated() where index < 8 {
                if bit != 0 { value |= (1 << index) }
            }
            plain.append(value % 26)
        }
        return plain
    }
}

package func resolveEnigmaNetlistPathForCore() -> String? {
    let fileManager = FileManager.default
    let cwd = fileManager.currentDirectoryPath
    let candidates = [
        "enigma_netlist.json",
        "../enigma_netlist.json",
        "../../enigma_netlist.json",
        "../../../enigma_netlist.json"
    ]
    for relative in candidates {
        let path = URL(fileURLWithPath: cwd).appendingPathComponent(relative).path
        if fileManager.fileExists(atPath: path) {
            return path
        }
    }
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<6 {
        url.deleteLastPathComponent()
        let candidate = url.appendingPathComponent("enigma_netlist.json").path
        if fileManager.fileExists(atPath: candidate) {
            return candidate
        }
    }
    return nil
}
