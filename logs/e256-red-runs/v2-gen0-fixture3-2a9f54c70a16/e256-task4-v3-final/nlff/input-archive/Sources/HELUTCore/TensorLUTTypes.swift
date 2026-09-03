import Foundation

/// A 64-wide continuous LUT6 representation (WIDTH 1…6 padded).
package struct TensorLUT6Cell: Codable {
    package let cellID: Int
    /// Flattened so Codable synthesizes cleanly without tuple issues.
    package let in0, in1, in2, in3, in4, in5, outWire: Int32
    /// Strictly 64-wide continuous INIT activations in `[0, 1]` (binary at corners).
    package var entries: [Float]

    package init(cellID: Int, inputWires: [Int32], outputWire: Int32, rawTruthTable: String) {
        precondition(inputWires.count <= 6, "TensorLUT6Cell supports at most 6 inputs")
        self.cellID = cellID
        self.outWire = outputWire

        var pads = inputWires
        while pads.count < 6 { pads.append(-1) }
        self.in0 = pads[0]
        self.in1 = pads[1]
        self.in2 = pads[2]
        self.in3 = pads[3]
        self.in4 = pads[4]
        self.in5 = pads[5]

        let width = inputWires.count
        let rawCount = 1 << width
        precondition(
            rawTruthTable.count == rawCount,
            "LUT truth table length \(rawTruthTable.count) != 2^\(width)"
        )
        var initFloats = [Float](repeating: 0.0, count: 64)

        for mask in 0..<rawCount {
            let charIndex = rawTruthTable.count - 1 - mask
            let idx = rawTruthTable.index(rawTruthTable.startIndex, offsetBy: charIndex)
            initFloats[mask] = (rawTruthTable[idx] == "1") ? 1.0 : 0.0
        }

        if width < 6 {
            for i in rawCount..<64 {
                initFloats[i] = initFloats[i % rawCount]
            }
        }
        self.entries = initFloats
    }
}

/// GPU-aligned sequential cell (must match Metal `DFFInputs`).
///
/// Extends the PRD’s plain D→Q with sync-reset / enable so Yosys `$_SDFF*` /
/// `$_DFFE*` cells (e.g. `enigma_m4_netlist.json`) tick correctly.
package struct TensorDFFCell: Codable {
    package let dWire: Int32
    package let qWire: Int32
    /// `-1` ⇒ always enabled.
    package let enableWire: Int32
    /// `-1` ⇒ no sync reset.
    package let resetWire: Int32
    package let enableActiveHigh: Int32
    package let resetActiveHigh: Int32
    /// Loaded when reset is asserted (`0` or `1`).
    package let resetValue: Int32

    package init(
        dWire: Int32,
        qWire: Int32,
        enableWire: Int32 = -1,
        resetWire: Int32 = -1,
        enableActiveHigh: Int32 = 1,
        resetActiveHigh: Int32 = 1,
        resetValue: Int32 = 0
    ) {
        self.dWire = dWire
        self.qWire = qWire
        self.enableWire = enableWire
        self.resetWire = resetWire
        self.enableActiveHigh = enableActiveHigh
        self.resetActiveHigh = resetActiveHigh
        self.resetValue = resetValue
    }
}

/// Flat, uniform netlist representation mapped to GPU-aligned buffers.
package final class TensorLUTNetlist {
    package let luts: [TensorLUT6Cell]
    package let dffs: [TensorDFFCell]
    package let totalWires: Int
    /// Topologically sorted LUT indices per combinational level.
    package let executionLevels: [[Int32]]
    /// Reserved wire held at `1.0` for Yosys constant-1 LUT/DFF pins (`nil` if unused).
    package let constOneWire: Int32?

    package init(
        luts: [TensorLUT6Cell],
        dffs: [TensorDFFCell] = [],
        totalWires: Int,
        executionLevels: [[Int32]],
        constOneWire: Int32? = nil
    ) {
        self.luts = luts
        self.dffs = dffs
        self.totalWires = totalWires
        self.executionLevels = executionLevels
        self.constOneWire = constOneWire
    }

    /// Packs all 64-entry LUT INITs into a single contiguous `[num_luts * 64]` Float32 array.
    package func packedINITBuffer() -> [Float] {
        var buffer = [Float]()
        buffer.reserveCapacity(luts.count * 64)
        for lut in luts {
            precondition(lut.entries.count == 64)
            buffer.append(contentsOf: lut.entries)
        }
        return buffer
    }

    /// Per-LUT live WIDTH (non-pad inputs) for cold-start mutation focus.
    package var liveWidths: [Int] {
        luts.map { lut in
            let w = [lut.in0, lut.in1, lut.in2, lut.in3, lut.in4, lut.in5]
                .filter { $0 >= 0 }
                .count
            return min(6, max(1, w))
        }
    }

    /// Writes `1.0` into `constOneWire` for every batch lane (no-op if unused).
    package func seedConstOne(into wires: inout [Float], batchSize: Int) {
        guard let wire = constOneWire else { return }
        let w = Int(wire)
        for b in 0..<batchSize {
            wires[b * totalWires + w] = 1.0
        }
    }
}
