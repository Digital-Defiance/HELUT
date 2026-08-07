import Foundation
import HELUTCLI
import HELUTCore

/// Generic per-netlist TensorLUT Verilog emit.
///
/// Restores the path that `enigma_m4_tensorlut_baseline.v` was produced by. Its
/// header records the loss:
///
///     swift run -c release helut -- enigma_m4_netlist.json \
///       --emit-tensorlut-verilog --emit-out <file>
///
/// Those flags were dropped in the packaging split, leaving `TensorLUTEmitter`
/// reachable only from library code and the surviving `--enigma256-emit-out`
/// path, which hardcodes the port layout of the `enigma_256_*` modules. That made
/// C8's 925-LUT artifact impossible to regenerate end-to-end, and the claim sheet
/// carried it as an open gap rather than a receipt.
///
/// Port derivation is the only thing the E256 path did by hand. It names each
/// port group explicitly because it also builds an adversarial target and needs
/// a specific stimulus order. A plain emit does not, so ports are taken straight
/// off `module.ports` by direction, in the same net-id order the compiler's bit
/// map uses.
///
/// Deliberately not a synthesis or mutation entry point: no fitness, no
/// chromosome polish. It emits the *unmutated* Yosys INIT tables, which is what
/// "baseline" means for C8. `TensorChromosome.from(netlist:)` is the identity
/// lift.
enum TensorLUTGenericEmit {

    /// Clock ports, which are *not* data inputs here.
    ///
    /// `TensorLUTEmitter.emitVerilog` declares `clk` itself as the first port and
    /// drives the DFF block from it. Passing the clock net through `inputWires`
    /// as well declares it twice and shifts every other port, which is exactly
    /// how the first regeneration attempt produced 10 inputs where the committed
    /// artifact has 9.
    static let clockPortNames: Set<String> = ["clk", "clock", "clk_i", "i_clk"]

    /// Bits of every port with the given direction, as net ids.
    ///
    /// Sorted ascending by net id rather than grouped by port name. Both are
    /// deterministic, but net-id order is what the original emit used and what
    /// `enigma_m4_tensorlut_baseline.v` records (`in_3 … in_11`), so this keeps
    /// regeneration comparable against the committed artifact. Multi-bit ports
    /// are allocated consecutive ids by Yosys, so bit order survives.
    static func portWires(_ module: YosysModule, direction: String) -> [Int32] {
        var wires: Set<Int32> = []
        for (name, port) in module.ports {
            guard port.direction == direction else { continue }
            if direction == "input", clockPortNames.contains(name.lowercased()) { continue }
            for bit in port.bits {
                if case .net(let id) = bit { wires.insert(Int32(id)) }
            }
        }
        return wires.sorted()
    }

    /// Behavioural `LUT6` matching the Xilinx Unisim port map, so the emitted
    /// file can be read straight back by Yosys or a simulator without pointing
    /// at a vendor library. Same model the round-trip test uses.
    static let lut6Model = """
    // Behavioral LUT6 (Xilinx Unisim-compatible port map) for Yosys / sim.
    // INIT[k] is the output for address {I5,I4,I3,I2,I1,I0} == k (I0 = LSB).
    module LUT6 #(parameter [63:0] INIT = 64'h0) (
        input  I0, I1, I2, I3, I4, I5,
        output O
    );
        wire [5:0] addr = {I5, I4, I3, I2, I1, I0};
        assign O = INIT[addr];
    endmodule
    """

    static func header(
        source: String,
        moduleName: String,
        netlist: TensorLUTNetlist,
        chromosome: TensorChromosome
    ) -> String {
        """
        // Auto-generated TensorLUT baseline (unmutated Yosys INIT tables).
        // Source: \(source)
        // LUTs: \(netlist.luts.count)  DFFs: \(netlist.dffs.count)  \
        wires: \(netlist.totalWires)
        // INIT floats: \(chromosome.inits.count)
        // Do not hand-edit.
        //
        // Regenerate with:
        //   .build/release/helut-bench --emit-tensorlut-verilog \(source) \\
        //     --emit-out <file>
        //
        // Emits the unmutated Yosys INIT tables -- no mutation, no fitness, no
        // chromosome polish. Verified end-to-end by
        //   swift test -c release --filter TensorLUTYosysRoundTripTests
        // which re-synthesizes emitted Verilog through Yosys and checks it is
        // functionally equivalent to the source netlist (claim C8).
        """
    }

    /// `--emit-tensorlut-verilog <netlist.json> [--emit-out <file>]`
    static func run() {
        let args = CommandLine.arguments
        guard let flagIndex = args.firstIndex(of: "--emit-tensorlut-verilog") else { return }

        // Path may follow the flag, or be given as the first non-flag argument.
        var source: String?
        if flagIndex + 1 < args.count, !args[flagIndex + 1].hasPrefix("--") {
            source = args[flagIndex + 1]
        } else {
            source = args.dropFirst().first { !$0.hasPrefix("--") && $0.hasSuffix(".json") }
        }
        guard let netlistPath = source else {
            fputs("""
            --emit-tensorlut-verilog needs a Yosys JSON netlist.
            Usage: helut-bench --emit-tensorlut-verilog <netlist.json> [--emit-out <file>]

            """, stderr)
            exit(2)
        }
        guard FileManager.default.fileExists(atPath: netlistPath) else {
            fputs("netlist not found: \(netlistPath)\n", stderr)
            exit(2)
        }

        let yosys = loadYosysNetlist(from: netlistPath)
        // Prefer a module that actually has cells; a netlist can carry stubs.
        guard let (moduleName, module) = yosys.modules
            .first(where: { !$0.value.cells.isEmpty }) ?? yosys.modules.first
        else {
            fputs("empty Yosys netlist: \(netlistPath)\n", stderr)
            exit(2)
        }

        let netlist = TensorLUTCompiler.compile(module: module)
        let chromosome = TensorChromosome.from(netlist: netlist)
        let inputWires = portWires(module, direction: "input")
        let outputWires = portWires(module, direction: "output")

        let emitModuleName = stringFlag("--emit-module-name") ?? moduleName
        let body = TensorLUTEmitter.emitVerilog(
            moduleName: emitModuleName,
            netlist: netlist,
            chromosome: chromosome,
            inputWires: inputWires,
            outputWires: outputWires
        )
        let text = header(
            source: netlistPath,
            moduleName: emitModuleName,
            netlist: netlist,
            chromosome: chromosome
        ) + "\n" + lut6Model + "\n" + body + "\n"

        let outPath = stringFlag("--emit-out")
        if let outPath {
            do {
                try text.write(toFile: outPath, atomically: true, encoding: .utf8)
            } catch {
                fputs("could not write \(outPath): \(error)\n", stderr)
                exit(2)
            }
            print(
                "emitted \(emitModuleName): \(netlist.luts.count) LUTs, "
                    + "\(netlist.dffs.count) DFFs, \(chromosome.inits.count) INIT floats, "
                    + "\(inputWires.count) inputs, \(outputWires.count) outputs -> \(outPath)"
            )
        } else {
            print(text)
        }
        exit(0)
    }
}
