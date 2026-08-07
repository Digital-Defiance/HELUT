import Foundation

/// Yosys JSON → TensorLUT: pad LUT6 cells, extract DFFs, Kahn topo levels.
package enum TensorLUTCompiler {

    /// Compiles a Yosys AST module into a topologically sorted TensorLUTNetlist.
    package static func compile(module: YosysModule) -> TensorLUTNetlist {
        // Pass 1: discover max net ID and whether constant-1 pins appear.
        var maxWire: Int32 = -1
        var needsConstOne = false

        func noteBit(_ bit: YosysBit) {
            switch bit {
            case .net(let id):
                maxWire = max(maxWire, Int32(id))
            case .constant(let value):
                if value != 0 { needsConstOne = true }
            }
        }

        for port in module.ports.values {
            for bit in port.bits { noteBit(bit) }
        }
        if let netnames = module.netnames {
            for net in netnames.values {
                for bit in net.bits { noteBit(bit) }
            }
        }
        for (_, cell) in module.cells {
            for bits in cell.connections.values {
                for bit in bits { noteBit(bit) }
            }
        }

        let constOneWire: Int32? = needsConstOne ? (maxWire + 1) : nil
        if let constOneWire {
            maxWire = constOneWire
        }
        let totalWires = Int(max(maxWire + 1, 0))

        func mapBit(_ bit: YosysBit) -> Int32 {
            switch bit {
            case .net(let id):
                return Int32(id)
            case .constant(let value):
                return value == 0 ? -1 : (constOneWire ?? -1)
            }
        }

        // Pass 2: extract cells (stable order).
        var luts: [TensorLUT6Cell] = []
        var dffs: [TensorDFFCell] = []

        for (_, cell) in module.cells.sorted(by: { $0.key < $1.key }) {
            if cell.type == "$lut" {
                guard let aBits = cell.connections["A"],
                      let yBits = cell.connections["Y"],
                      yBits.count == 1,
                      let rawTruth = cell.parameters.LUT,
                      case .net(let outW) = yBits[0]
                else {
                    fatalError("Malformed $lut cell in TensorLUTCompiler")
                }
                precondition(aBits.count <= 6, "TensorLUT requires WIDTH ≤ 6 (got \(aBits.count))")

                let inWires = aBits.map(mapBit)
                luts.append(
                    TensorLUT6Cell(
                        cellID: luts.count,
                        inputWires: inWires,
                        outputWire: Int32(outW),
                        rawTruthTable: rawTruth
                    )
                )
            } else if isYosysDFFType(cell.type) {
                guard let dBits = cell.connections["D"], dBits.count == 1,
                      let qBits = cell.connections["Q"], qBits.count == 1
                else {
                    fatalError("Malformed DFF cell in TensorLUTCompiler")
                }
                let polarity = parseYosysDFFPolarity(cell.type)
                let enableBit = cell.connections["E"]?.first
                let resetBit = cell.connections["R"]?.first

                var enableActiveHigh: Int32 = 1
                var enableWire: Int32 = -1
                if let enableBit {
                    enableWire = mapBit(enableBit)
                    enableActiveHigh = (polarity.enableActiveHigh ?? true) ? 1 : 0
                }

                var resetActiveHigh: Int32 = 1
                var resetValue: Int32 = 0
                var resetWire: Int32 = -1
                if let resetBit {
                    resetWire = mapBit(resetBit)
                    if let sync = polarity.syncReset {
                        resetActiveHigh = sync.activeHigh ? 1 : 0
                        resetValue = Int32(sync.value)
                    }
                }

                dffs.append(
                    TensorDFFCell(
                        dWire: mapBit(dBits[0]),
                        qWire: mapBit(qBits[0]),
                        enableWire: enableWire,
                        resetWire: resetWire,
                        enableActiveHigh: enableActiveHigh,
                        resetActiveHigh: resetActiveHigh,
                        resetValue: resetValue
                    )
                )
            }
        }

        let executionLevels = topologicalLevels(luts: luts)
        return TensorLUTNetlist(
            luts: luts,
            dffs: dffs,
            totalWires: totalWires,
            executionLevels: executionLevels,
            constOneWire: constOneWire
        )
    }

    /// Kahn levels: edge LUT→LUT when a consumer input is another LUT’s `outWire`.
    /// DFF Q / primary inputs are not producers in this graph (break sequential cycles).
    private static func topologicalLevels(luts: [TensorLUT6Cell]) -> [[Int32]] {
        var producerLUT: [Int32: Int] = [:]
        for (idx, lut) in luts.enumerated() {
            producerLUT[lut.outWire] = idx
        }

        var inDegree = [Int](repeating: 0, count: luts.count)
        var dependents: [Int: [Int]] = [:]

        for (idx, lut) in luts.enumerated() {
            let inputs = [lut.in0, lut.in1, lut.in2, lut.in3, lut.in4, lut.in5].filter { $0 >= 0 }
            var seenProducers = Set<Int>()
            for inWire in inputs {
                guard let prodIdx = producerLUT[inWire], prodIdx != idx else { continue }
                // Multi-fan-in from same producer counts once for Kahn.
                if seenProducers.insert(prodIdx).inserted {
                    dependents[prodIdx, default: []].append(idx)
                    inDegree[idx] += 1
                }
            }
        }

        var executionLevels: [[Int32]] = []
        var currentQueue: [Int] = []
        for i in 0..<luts.count where inDegree[i] == 0 {
            currentQueue.append(i)
        }

        while !currentQueue.isEmpty {
            executionLevels.append(currentQueue.map { Int32($0) })
            var nextQueue: [Int] = []
            for lutIdx in currentQueue {
                for depIdx in dependents[lutIdx] ?? [] {
                    inDegree[depIdx] -= 1
                    if inDegree[depIdx] == 0 {
                        nextQueue.append(depIdx)
                    }
                }
            }
            currentQueue = nextQueue
        }

        let sortedCount = executionLevels.reduce(0) { $0 + $1.count }
        precondition(
            sortedCount == luts.count,
            "Combinational loop detected in Yosys AST. Sorted \(sortedCount)/\(luts.count) LUTs."
        )
        return executionLevels
    }
}
