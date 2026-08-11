import Foundation

/// Phase 3 reverse emitter: polished TensorChromosome → gate-level `LUT6` Verilog.
package enum TensorLUTEmitter {

    /// Formats 64 INIT floats (`[0,1]`, LSB = address 0) as a Xilinx-style `64'h…` hex body.
    ///
    /// Bit `k` of the INIT word is `1` iff `entries[k] >= 0.5`, matching TensorLUT /
    /// `CleartextNetlistSim` LSB-first tables. The hex string is MSB-nibble-first
    /// (leftmost digit = bits 63…60).
    package static func initHex(entries: ArraySlice<Float>) -> String {
        precondition(entries.count == 64, "INIT block must be 64 floats")
        var hex = ""
        hex.reserveCapacity(16)
        for nibble in (0..<16).reversed() {
            var val = 0
            for bit in 0..<4 {
                let floatIdx = entries.startIndex + (nibble * 4) + bit
                if entries[floatIdx] >= 0.5 {
                    val |= (1 << bit)
                }
            }
            hex.append(String(format: "%X", val))
        }
        return hex
    }

    /// Inverse of `initHex` for round-trip tests (MSB-nibble-first hex → 64 LSB-first bits).
    package static func entriesFromInitHex(_ hex: String) -> [Float] {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        precondition(cleaned.count == 16, "expected 16 hex digits, got \(cleaned.count)")
        var entries = [Float](repeating: 0, count: 64)
        for (ni, ch) in cleaned.enumerated() {
            guard let digit = Int(String(ch), radix: 16) else {
                fatalError("invalid hex digit \(ch)")
            }
            // Leftmost character is nibble 15 (bits 63…60).
            let nibble = 15 - ni
            for bit in 0..<4 {
                if (digit & (1 << bit)) != 0 {
                    entries[nibble * 4 + bit] = 1
                }
            }
        }
        return entries
    }

    /// Generates gate-level, synthesizable Verilog from an optimized TensorChromosome.
    package static func emitVerilog(
        moduleName: String,
        netlist: TensorLUTNetlist,
        chromosome: TensorChromosome,
        inputWires: [Int32],
        outputWires: [Int32]
    ) -> String {
        precondition(chromosome.inits.count == netlist.luts.count * 64)
        // Yosys may alias output bits onto primary inputs (pure wires / shifts).
        // That is fine: `assign n[w] = in_w` then `assign out_w = n[w]` is a passthrough.

        var v: [String] = []

        // 1. Module Declaration & Ports
        var ports = ["clk"]
        ports.append(contentsOf: inputWires.map { "in_\($0)" })
        ports.append(contentsOf: outputWires.map { "out_\($0)" })

        v.append("module \(moduleName) (")
        v.append("    " + ports.joined(separator: ", "))
        v.append(");")
        v.append("")

        // 2. Port Definitions
        v.append("    input wire clk;")
        for iw in inputWires {
            v.append("    input wire in_\(iw);")
        }
        for ow in outputWires {
            v.append("    output wire out_\(ow);")
        }
        v.append("")

        // 3. Internal Wire Array
        let top = max(netlist.totalWires - 1, 0)
        v.append("    // Internal Netlist Wires")
        v.append("    wire [\(top):0] n;")
        if !netlist.dffs.isEmpty {
            v.append("    reg [\(top):0] n_reg;")
        }
        v.append("")

        // 4. Bind Primary Inputs and Outputs
        v.append("    // Primary I/O Bindings")
        for iw in inputWires {
            v.append("    assign n[\(iw)] = in_\(iw);")
        }
        if let constOne = netlist.constOneWire {
            v.append("    assign n[\(constOne)] = 1'b1;")
        }
        let qWires = Set(netlist.dffs.map(\.qWire))
        for ow in outputWires {
            if qWires.contains(ow) {
                v.append("    assign out_\(ow) = n_reg[\(ow)];")
            } else {
                v.append("    assign out_\(ow) = n[\(ow)];")
            }
        }
        v.append("")

        func wireRef(_ w: Int32) -> String {
            w >= 0 ? "n[\(w)]" : "1'b0"
        }

        // 5. Emit LUT6 Instantiations
        v.append("    // Adversarially Synthesized Combinational Logic")
        for (idx, lut) in netlist.luts.enumerated() {
            let offset = idx * 64
            let hexInit = initHex(entries: chromosome.inits[offset..<(offset + 64)])

            v.append("    LUT6 #(")
            v.append("        .INIT(64'h\(hexInit))")
            v.append("    ) lut_\(lut.cellID) (")
            v.append(
                "        .I0(\(wireRef(lut.in0))), .I1(\(wireRef(lut.in1))), .I2(\(wireRef(lut.in2))), "
                    + ".I3(\(wireRef(lut.in3))), .I4(\(wireRef(lut.in4))), .I5(\(wireRef(lut.in5))),"
            )
            v.append("        .O(\(wireRef(lut.outWire)))")
            v.append("    );")
        }
        v.append("")

        // 6. Emit Sequential Elements (DFFs)
        if !netlist.dffs.isEmpty {
            v.append("    // Sequential State Updates")
            v.append("    always @(posedge clk) begin")
            for dff in netlist.dffs {
                let dExpr = dff.dWire >= 0 ? "n[\(dff.dWire)]" : "1'b0"
                var next = dExpr
                if dff.enableWire >= 0 {
                    let eRef = "n[\(dff.enableWire)]"
                    let enabled = dff.enableActiveHigh != 0 ? eRef : "!\(eRef)"
                    next = "(\(enabled) ? \(dExpr) : n_reg[\(dff.qWire)])"
                }
                if dff.resetWire >= 0 {
                    let rRef = "n[\(dff.resetWire)]"
                    let asserted = dff.resetActiveHigh != 0 ? rRef : "!\(rRef)"
                    next = "(\(asserted) ? 1'b\(dff.resetValue) : \(next))"
                }
                v.append("        n_reg[\(dff.qWire)] <= \(next);")
            }
            v.append("    end")
            v.append("")
            v.append("    // DFF to Wire bindings")
            for dff in netlist.dffs {
                v.append("    assign n[\(dff.qWire)] = n_reg[\(dff.qWire)];")
            }
        }

        v.append("endmodule")
        v.append("")
        return v.joined(separator: "\n")
    }
}
