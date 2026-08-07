import Metal
import XCTest
@testable import HELUTCore

/// How far does melt → freeze → prove actually go?
///
/// The joined receipt in `TensorLUTYosysRoundTripTests` runs on a two-bit adder:
/// four LUTs, sixteen input assignments. That is small enough to be honest about
/// but too small to answer the obvious question, and the one archived large
/// attempt (925 LUTs, 16 mutable) *failed* to freeze — 118 entries stayed
/// fractional. So there is a boundary somewhere between four and 925, and nothing
/// in the repository locates it.
///
/// This sweeps a parameterised ripple-carry adder along two independent axes and
/// records where the chain stops working:
///
///  - **surrounding size**: grow the circuit, keep the melted region fixed
///  - **melt region**: fix the circuit, grow the number of melted tables
///
/// Verdicts come from SAT over the whole input space, not enumeration, so a
/// "pass" means formally equivalent to behavioural addition rather than
/// "agreed on the rows we happened to try".
///
/// A boundary is a result. These tests assert only that the known-good baseline
/// still proves; everything past it is reported as data.
final class TensorLUTMeltScalingTests: XCTestCase {

    // MARK: - Parameterised ripple-carry adder

    /// Wire layout for an `n`-bit adder, chosen so every wire id is derivable
    /// without a lookup table:
    ///
    /// ```
    ///  a_i        = i              i ∈ 0..<n
    ///  b_i        = n + i
    ///  c_(i+1)    = 2n + i         c_n is the carry out
    ///  s_i        = 3n + i
    /// ```
    ///
    /// There is no carry *in*, so bit 0 uses two-input XOR/AND and every higher
    /// bit uses three-input XOR/majority.
    private struct AdderLayout {
        let bits: Int
        var aWire: (Int) -> Int32 { { Int32($0) } }
        var bWire: (Int) -> Int32 { { Int32(self.bits + $0) } }
        /// Carry *out* of bit `i`.
        var cWire: (Int) -> Int32 { { Int32(2 * self.bits + $0) } }
        var sWire: (Int) -> Int32 { { Int32(3 * self.bits + $0) } }
        var totalWires: Int { 4 * bits }
        var inputWires: [Int32] { (0..<(2 * bits)).map(Int32.init) }
        /// Sum bits low-to-high, then the final carry as the top output.
        var outputWires: [Int32] { (0..<bits).map { sWire($0) } + [cWire(bits - 1)] }
    }

    /// Yosys stores truth tables MSB-first, so entry `2^k - 1` comes first.
    private func truthTable(inputCount: Int, _ f: ([Int]) -> Int) -> String {
        let rows = 1 << inputCount
        var out = ""
        for address in stride(from: rows - 1, through: 0, by: -1) {
            let pins = (0..<inputCount).map { (address >> $0) & 1 }
            out.append(f(pins) == 0 ? "0" : "1")
        }
        return out
    }

    /// Two LUTs per bit position: one sum, one carry. Cell ids are array indices,
    /// which is what the emitter uses to slice the chromosome.
    ///
    /// LUTs listed in `erase` are declared as all-zero tables rather than their
    /// correct logic, following the established melt fixture: there must be no
    /// correct answer hiding underneath the wipe, so the search has to discover
    /// the function instead of remembering it. This also makes
    /// `TensorChromosome.from(netlist:)` a genuine "before" state that the formal
    /// check should refute.
    private func makeRippleAdder(bits: Int, erase: Set<Int> = []) -> (
        netlist: TensorLUTNetlist, layout: AdderLayout, liveWidths: [Int]
    ) {
        let L = AdderLayout(bits: bits)
        var luts: [TensorLUT6Cell] = []
        var liveWidths: [Int] = []
        var levels: [[Int32]] = []

        let xor2 = truthTable(inputCount: 2) { ($0[0] ^ $0[1]) }
        let and2 = truthTable(inputCount: 2) { ($0[0] & $0[1]) }
        let xor3 = truthTable(inputCount: 3) { ($0[0] ^ $0[1] ^ $0[2]) }
        let maj3 = truthTable(inputCount: 3) { p in (p[0] + p[1] + p[2]) >= 2 ? 1 : 0 }

        for i in 0..<bits {
            let sumID = luts.count
            let carryID = luts.count + 1
            let zero2 = String(repeating: "0", count: 4)
            let zero3 = String(repeating: "0", count: 8)
            if i == 0 {
                luts.append(TensorLUT6Cell(
                    cellID: sumID, inputWires: [L.aWire(0), L.bWire(0)],
                    outputWire: L.sWire(0),
                    rawTruthTable: erase.contains(sumID) ? zero2 : xor2
                ))
                luts.append(TensorLUT6Cell(
                    cellID: carryID, inputWires: [L.aWire(0), L.bWire(0)],
                    outputWire: L.cWire(0),
                    rawTruthTable: erase.contains(carryID) ? zero2 : and2
                ))
                liveWidths.append(2)
                liveWidths.append(2)
            } else {
                let pins = [L.aWire(i), L.bWire(i), L.cWire(i - 1)]
                luts.append(TensorLUT6Cell(
                    cellID: sumID, inputWires: pins,
                    outputWire: L.sWire(i),
                    rawTruthTable: erase.contains(sumID) ? zero3 : xor3
                ))
                luts.append(TensorLUT6Cell(
                    cellID: carryID, inputWires: pins,
                    outputWire: L.cWire(i),
                    rawTruthTable: erase.contains(carryID) ? zero3 : maj3
                ))
                liveWidths.append(3)
                liveWidths.append(3)
            }
            // Both LUTs of bit i depend only on c_(i-1), so they share a level.
            levels.append([Int32(sumID), Int32(carryID)])
        }

        let netlist = TensorLUTNetlist(
            luts: luts,
            dffs: [],
            totalWires: L.totalWires,
            executionLevels: levels
        )
        return (netlist, L, liveWidths)
    }

    /// Stimulus for the search. Exhaustive by default; pass `sampleRows` to train
    /// on a deterministic subset instead.
    ///
    /// The distinction is what decides whether any of this scales. Exhaustive
    /// stimulus costs 2^(2n) rows, so it dies long before SAT does — at 16 operand
    /// bits it is already 65,536 rows, and the proof would happily handle far more.
    /// If the search converges from a sample and the *proof* still covers the whole
    /// space, then search cost decouples from input-space size entirely.
    private func adderTarget(
        layout L: AdderLayout, sampleRows: Int? = nil, sampleSeed: UInt64 = 0x5EED_1234
    ) -> AdversarialTarget {
        let n = L.bits
        let total = 1 << (2 * n)

        func row(_ index: Int) -> ([Float], [Float]) {
            let a = index & ((1 << n) - 1)
            let b = index >> n
            var inputs = [Float]()
            for i in 0..<n { inputs.append(Float((a >> i) & 1)) }
            for i in 0..<n { inputs.append(Float((b >> i) & 1)) }
            let sum = a + b
            var outputs = [Float]()
            for i in 0..<n { outputs.append(Float((sum >> i) & 1)) }
            outputs.append(Float((sum >> n) & 1))
            return (inputs, outputs)
        }

        var indices: [Int]
        if let sampleRows, sampleRows < total {
            // Deterministic LCG sample without replacement, so the trial is
            // reproducible and the sample is not aligned to the carry structure
            // the way a fixed stride would be.
            var state = sampleSeed
            var picked = Set<Int>()
            indices = []
            while picked.count < sampleRows {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                let candidate = Int((state >> 16) % UInt64(total))
                if picked.insert(candidate).inserted { indices.append(candidate) }
            }
        } else {
            indices = Array(0..<total)
        }

        var inputVectors = [[Float]]()
        var expectedOutputs = [[Float]]()
        for index in indices {
            let (inputs, outputs) = row(index)
            inputVectors.append(inputs)
            expectedOutputs.append(outputs)
        }
        return AdversarialTarget(
            inputWireIDs: L.inputWires,
            outputWireIDs: L.outputWires,
            inputVectors: inputVectors,
            expectedOutputs: expectedOutputs,
            clockTicks: 0
        )
    }

    /// Behavioural golden model with the emitter's port names. Knows nothing about
    /// lookup tables — it uses Verilog `+`.
    private func referenceVerilog(layout L: AdderLayout) -> String {
        let n = L.bits
        let inputList = (0..<(2 * n)).map { "in_\($0)" }.joined(separator: ", ")
        let outputList = L.outputWires.map { "out_\($0)" }.joined(separator: ", ")
        let aBits = (0..<n).reversed().map { "in_\(L.aWire($0))" }.joined(separator: ", ")
        let bBits = (0..<n).reversed().map { "in_\(L.bWire($0))" }.joined(separator: ", ")
        var assigns = (0..<n)
            .map { "    assign out_\(L.sWire($0)) = s[\($0)];" }
            .joined(separator: "\n")
        assigns += "\n    assign out_\(L.cWire(n - 1)) = s[\(n)];"
        return """
        module ripple_adder_ref (
            input clk,
            input \(inputList),
            output \(outputList)
        );
            wire [\(n - 1):0] a = {\(aBits)};
            wire [\(n - 1):0] b = {\(bBits)};
            wire [\(n):0] s = a + b;
        \(assigns)
        endmodule
        """
    }

    // MARK: - Yosys / SAT plumbing

    private static let lut6Model = """
    module LUT6 (output O, input I0, I1, I2, I3, I4, I5);
        parameter [63:0] INIT = 64'h0000000000000000;
        wire [5:0] addr = {I5, I4, I3, I2, I1, I0};
        assign O = INIT[addr];
    endmodule
    """

    private func yosysPath() -> String? {
        for candidate in ["/opt/homebrew/bin/yosys", "/usr/local/bin/yosys", "/usr/bin/yosys"] {
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    @discardableResult
    private func run(_ launch: String, _ args: [String], cwd: URL) throws -> (Int32, String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launch)
        proc.arguments = args
        proc.currentDirectoryURL = cwd
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        try proc.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return (proc.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private enum ProofOutcome: String {
        case proved = "PROVED"
        case refuted = "REFUTED"
        case inconclusive = "INCONCLUSIVE"
    }

    private struct SynthOutcome {
        let verdict: ProofOutcome
        /// `$lut` cells surviving `abc -lut 6` + `opt_clean`, or nil if synthesis
        /// never produced a netlist. This is the only resource number the
        /// repository can currently produce; there is no area or timing model
        /// anywhere, so it is a LUT-count proxy and nothing more.
        let resynthLUTs: Int?
    }

    /// emit → synthesize → `abc -lut 6` → SAT-prove against behavioural addition.
    ///
    /// No `-verify` on the `sat` call: that would turn a refutation into a Yosys
    /// error and make "the design is wrong" indistinguishable from "the tooling
    /// broke". Exit status reports tooling health; the log carries the verdict.
    private func proveAgainstReference(
        yosys: String,
        netlist: TensorLUTNetlist,
        layout: AdderLayout,
        chromosome: TensorChromosome,
        tag: String
    ) throws -> SynthOutcome {
        let verilog = TensorLUTEmitter.emitVerilog(
            moduleName: "ripple_adder",
            netlist: netlist,
            chromosome: chromosome,
            inputWires: layout.inputWires,
            outputWires: layout.outputWires
        )
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("helut-melt-scale-\(tag)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try verilog.write(
            to: dir.appendingPathComponent("emitted.v"), atomically: true, encoding: .utf8
        )
        try Self.lut6Model.write(
            to: dir.appendingPathComponent("lut6.v"), atomically: true, encoding: .utf8
        )
        try referenceVerilog(layout: layout).write(
            to: dir.appendingPathComponent("reference.v"), atomically: true, encoding: .utf8
        )
        try """
        read_verilog lut6.v
        read_verilog emitted.v
        hierarchy -top ripple_adder
        proc
        flatten
        opt
        techmap
        opt
        abc -lut 6
        opt_clean
        write_json resynth.json
        """.write(to: dir.appendingPathComponent("flow.ys"), atomically: true, encoding: .utf8)

        try """
        read_json resynth.json
        read_verilog reference.v
        proc
        opt
        miter -equiv -flatten ripple_adder_ref ripple_adder miter
        sat -prove trigger 0 miter
        """.write(to: dir.appendingPathComponent("prove.ys"), atomically: true, encoding: .utf8)

        let jsonPath = dir.appendingPathComponent("resynth.json").path
        let (synthStatus, synthLog) = try run(yosys, ["-q", "flow.ys"], cwd: dir)
        guard synthStatus == 0, FileManager.default.fileExists(atPath: jsonPath) else {
            print("  synthesis failed (\(tag)): \(synthLog.suffix(400))")
            return SynthOutcome(verdict: .inconclusive, resynthLUTs: nil)
        }

        // Count what ABC actually kept. Same pattern the production-cell tests use.
        var resynthLUTs: Int?
        let reloaded = loadYosysNetlist(from: jsonPath)
        if let (_, module) = reloaded.modules.first(where: { !$0.value.cells.isEmpty }) {
            resynthLUTs = module.cells.values.filter { $0.type == "$lut" }.count
        }

        let (proveStatus, proveLog) = try run(yosys, ["prove.ys"], cwd: dir)
        guard proveStatus == 0 else {
            print("  sat pass exited \(proveStatus) (\(tag)): \(proveLog.suffix(400))")
            return SynthOutcome(verdict: .inconclusive, resynthLUTs: resynthLUTs)
        }
        if proveLog.contains("no model found: SUCCESS") {
            return SynthOutcome(verdict: .proved, resynthLUTs: resynthLUTs)
        }
        if proveLog.contains("model found: FAIL") {
            return SynthOutcome(verdict: .refuted, resynthLUTs: resynthLUTs)
        }
        return SynthOutcome(verdict: .inconclusive, resynthLUTs: resynthLUTs)
    }

    // MARK: - One trial

    private struct Trial {
        let bits: Int
        let totalLUTs: Int
        let meltedLUTs: Int
        let targetRows: Int
        /// Size of the full input space, so a sampled trial can be told apart from
        /// an exhaustive one in the receipt.
        let inputSpace: Int
        let searchSeconds: Double
        let fitness: Float
        let fractionalEntries: Int
        let frozenIntact: Bool
        let erasedVerdict: ProofOutcome
        let searchedVerdict: ProofOutcome
        /// `$lut` cells ABC kept for the searched design, when it was synthesizable.
        let searchedResynthLUTs: Int?
    }

    /// Melts the given LUT indices, searches, and formally checks both the erased
    /// starting point and the searched result.
    private func runTrial(
        yosys: String,
        device: MTLDevice,
        bits: Int,
        meltIndices: [Int],
        generations: Int = 120,
        populationSize: Int = 48,
        sampleRows: Int? = nil
    ) throws -> Trial {
        let (netlist, layout, liveWidths) = makeRippleAdder(
            bits: bits, erase: Set(meltIndices)
        )
        let target = adderTarget(layout: layout, sampleRows: sampleRows)

        var seed = netlist.packedINITBuffer()
        for lut in meltIndices {
            for j in 0..<64 { seed[lut * 64 + j] = 0.5 }
        }
        let freeze = TensorFreezeMask.meltOnly(
            lutCount: netlist.luts.count, indices: Set(meltIndices)
        )

        // Is the erased design actually broken? If melting these tables does not
        // change the function, the trial proves nothing.
        let erased = try proveAgainstReference(
            yosys: yosys,
            netlist: netlist,
            layout: layout,
            chromosome: TensorChromosome.from(netlist: netlist),
            tag: "erased-\(bits)b-\(meltIndices.count)m"
        )

        let pipeline = try TensorLUTPipeline(device: device, netlist: netlist)
        let synth = try AdversarialSynthesizer(
            device: device,
            config: .init(
                mutationRate: 0.2,
                maxNoise: 0.4,
                lambdaMax: 12,
                liveWidths: liveWidths,
                lambdaDelayFraction: 0.1,
                discreteJumpRate: 0.4
            )
        )
        let harness = AdversarialHarness(
            device: device, pipeline: pipeline, synthesizer: synth, netlist: netlist
        )

        let started = Date()
        let best = harness.run(
            target: target,
            config: .init(
                populationSize: populationSize,
                generations: generations,
                eliteCount: 6,
                seedScatter: true,
                rngSeed: 0x7A6E17,
                seedInits: seed,
                crossoverRate: 0.55,
                polishBinaryAtEnd: true,
                freezeMask: freeze
            )
        )
        let searchSeconds = Date().timeIntervalSince(started)

        var frozenIntact = true
        for lut in 0..<netlist.luts.count where !meltIndices.contains(lut) {
            let lo = lut * 64
            if Array(best.inits[lo..<(lo + 64)]) != Array(seed[lo..<(lo + 64)]) {
                frozenIntact = false
                break
            }
        }
        let fractional = AdversarialHarness.nonBinaryCount(best.inits, freezeMask: freeze)

        // A fractional genome would be silently thresholded by the emitter, so the
        // proof would be about the snapped design rather than the elite. Report
        // the verdict as inconclusive instead of pretending it is about the elite.
        let searched: SynthOutcome
        if fractional > 0 {
            searched = SynthOutcome(verdict: .inconclusive, resynthLUTs: nil)
        } else {
            searched = try proveAgainstReference(
                yosys: yosys,
                netlist: netlist,
                layout: layout,
                chromosome: best,
                tag: "searched-\(bits)b-\(meltIndices.count)m"
            )
        }

        return Trial(
            bits: bits,
            totalLUTs: netlist.luts.count,
            meltedLUTs: meltIndices.count,
            targetRows: target.batchSize,
            inputSpace: 1 << (2 * bits),
            searchSeconds: searchSeconds,
            fitness: best.fitness,
            fractionalEntries: fractional,
            frozenIntact: frozenIntact,
            erasedVerdict: erased.verdict,
            searchedVerdict: searched.verdict,
            searchedResynthLUTs: searched.resynthLUTs
        )
    }

    private func report(_ label: String, _ trials: [Trial]) {
        print("")
        print("MELT_SCALING \(label)")
        print(
            "  bits  LUTs  melted  rows   space   search_s  fitness    frac  frozen"
                + "  erased        searched"
        )
        for t in trials {
            let bits = String(t.bits).leftPad(4)
            let luts = String(t.totalLUTs).leftPad(5)
            let melted = String(t.meltedLUTs).leftPad(6)
            let rows = String(t.targetRows).leftPad(6)
            let space = String(t.inputSpace).leftPad(7)
            let secs = String(format: "%.2f", t.searchSeconds).leftPad(9)
            let fit = String(format: "%.4f", t.fitness).leftPad(9)
            let frac = String(t.fractionalEntries).leftPad(5)
            let frozen = (t.frozenIntact ? "yes" : "LEAK").leftPad(7)
            let erased = t.erasedVerdict.rawValue.rightPad(13)
            print(
                "  \(bits) \(luts) \(melted) \(rows) \(space) \(secs) \(fit) \(frac) \(frozen)"
                    + "  \(erased) \(t.searchedVerdict.rawValue)"
            )
        }
    }

    // MARK: - Axis A: grow the circuit, keep the melted region fixed

    /// Does a bigger surrounding circuit make the same-sized repair harder?
    ///
    /// Each trial melts exactly the top bit position's two tables, so the search
    /// space is constant at 128 floats while the frozen context grows.
    func testMeltScalingBySurroundingCircuitSize() throws {
        guard let yosys = yosysPath() else { throw XCTSkip("yosys not found — see REPRODUCE.md") }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device not available")
        }

        var trials: [Trial] = []
        for bits in 2...8 {
            let top = [2 * bits - 2, 2 * bits - 1]
            let trial = try runTrial(
                yosys: yosys, device: device, bits: bits, meltIndices: top
            )
            trials.append(trial)
            if trial.searchedVerdict != .proved {
                print(
                    "MELT_SCALING axis-A boundary: \(bits)-bit adder "
                        + "(\(trial.totalLUTs) LUTs) did not prove — "
                        + "\(trial.searchedVerdict.rawValue), "
                        + "\(trial.fractionalEntries) fractional entries"
                )
                break
            }
        }
        report("axis-A (fixed 2-LUT melt, growing circuit)", trials)

        let baseline = try XCTUnwrap(trials.first, "no trials ran")
        XCTAssertEqual(baseline.bits, 2)
        XCTAssertEqual(
            baseline.erasedVerdict, .refuted,
            "the 2-bit erased fixture must be formally broken or the baseline is vacuous"
        )
        XCTAssertEqual(
            baseline.searchedVerdict, .proved,
            "the 2-bit baseline regressed; it is proven in TensorLUTYosysRoundTripTests"
        )
    }

    // MARK: - Axis B: fix the circuit, grow the melted region

    /// Where does the repair itself get too big? Fixes a four-bit adder (8 LUTs)
    /// and melts progressively more of it, ending with the whole circuit erased —
    /// which is cold-start synthesis from scratch, not repair.
    func testMeltScalingByMeltRegionSize() throws {
        guard let yosys = yosysPath() else { throw XCTSkip("yosys not found — see REPRODUCE.md") }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device not available")
        }

        let bits = 4
        var trials: [Trial] = []
        // Melt from the top down: the last k tables of an 8-LUT ripple adder.
        for melted in [2, 4, 6, 8] {
            let indices = Array((2 * bits - melted)..<(2 * bits))
            let trial = try runTrial(
                yosys: yosys, device: device, bits: bits, meltIndices: indices
            )
            trials.append(trial)
            if trial.searchedVerdict != .proved {
                print(
                    "MELT_SCALING axis-B boundary: melting \(melted) of "
                        + "\(trial.totalLUTs) LUTs did not prove — "
                        + "\(trial.searchedVerdict.rawValue), "
                        + "\(trial.fractionalEntries) fractional entries, "
                        + "fitness \(trial.fitness)"
                )
                break
            }
        }
        report("axis-B (fixed 4-bit adder, growing melt region)", trials)

        let baseline = try XCTUnwrap(trials.first, "no trials ran")
        XCTAssertEqual(baseline.meltedLUTs, 2)
        XCTAssertTrue(
            baseline.frozenIntact,
            "freeze mask leaked on the smallest melt region"
        )
    }

    // MARK: - Axis C: is the cold-start failure a budget lever or a boundary?

    /// Melting every table is not repair, it is synthesis from scratch: no frozen
    /// anchor, nothing to search *around*. Axis B shows it produces a fully binary
    /// but functionally wrong circuit. This asks whether that is a search-budget
    /// problem that more compute fixes, or a structural one that it does not.
    ///
    /// The distinction matters more than the outcome. A budget limit is a lever; a
    /// plateau across a 25× budget increase is evidence of something the current
    /// objective cannot reach, and would mean cold-start needs a different
    /// mechanism rather than a bigger number.
    ///
    /// This test deliberately asserts nothing about success. It records behaviour.
    func testColdStartMeltIsBudgetLeverOrBoundary() throws {
        guard let yosys = yosysPath() else { throw XCTSkip("yosys not found — see REPRODUCE.md") }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device not available")
        }

        let bits = 4
        let all = Array(0..<(2 * bits))
        var trials: [Trial] = []
        var budgets: [(generations: Int, population: Int)] = []
        for generations in [120, 500, 3000] {
            budgets.append((generations, 48))
        }
        // One wider-population run at the largest budget: more parallel search
        // rather than more sequential generations.
        budgets.append((3000, 192))

        for budget in budgets {
            let trial = try runTrial(
                yosys: yosys,
                device: device,
                bits: bits,
                meltIndices: all,
                generations: budget.generations,
                populationSize: budget.population
            )
            trials.append(trial)
            print(
                "MELT_SCALING cold-start gen=\(budget.generations) pop=\(budget.population) "
                    + "→ \(trial.searchedVerdict.rawValue) fitness=\(trial.fitness) "
                    + "frac=\(trial.fractionalEntries) search=\(String(format: "%.2f", trial.searchSeconds))s"
            )
            if trial.searchedVerdict == .proved {
                print(
                    "MELT_SCALING cold-start verdict: BUDGET LEVER — full-circuit melt "
                        + "proved at \(budget.generations) generations / population "
                        + "\(budget.population)"
                )
                break
            }
        }
        report("axis-C (4-bit cold start, escalating budget)", trials)

        if trials.allSatisfy({ $0.searchedVerdict != .proved }) {
            let best = trials.map(\.fitness).max() ?? -.infinity
            print(
                "MELT_SCALING cold-start verdict: NO BUDGET LEVER FOUND across "
                    + "\(trials.count) budgets up to \(trials.last?.searchSeconds.rounded() ?? 0)s; "
                    + "best fitness \(best). Full-circuit melt is not reachable by "
                    + "scaling this objective, and every run still froze to a fully "
                    + "binary but incorrect circuit."
            )
        }

        // The only hard requirement: the independent proof must never bless a
        // circuit the search got wrong. Freezing is not correctness.
        for trial in trials where trial.fitness < -0.05 {
            XCTAssertNotEqual(
                trial.searchedVerdict, .proved,
                """
                a run with fitness \(trial.fitness) was proven equivalent to the \
                adder. Either the fitness function or the formal check is wrong.
                """
            )
        }
    }

    // MARK: - Axis D: train on a sample, prove on everything

    /// The axis that decides whether this scales at all.
    ///
    /// Every trial above drives the search with exhaustive stimulus, which costs
    /// 2^(2n) rows and is the real ceiling — not SAT, which barely notices these
    /// sizes. If the search converges from a small sample while the *proof* still
    /// covers the entire input space, then search cost stops tracking input-space
    /// size and the method is no longer confined to circuits you can enumerate.
    ///
    /// Sampling fractions here are deliberately brutal: 256 of 65,536 is 0.4%.
    func testSearchConvergesFromSampledStimulusAndStillProves() throws {
        guard let yosys = yosysPath() else { throw XCTSkip("yosys not found — see REPRODUCE.md") }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device not available")
        }

        let bits = 8
        let top = [2 * bits - 2, 2 * bits - 1]
        var trials: [Trial] = []

        for sample in [64, 256, 1024] {
            let trial = try runTrial(
                yosys: yosys,
                device: device,
                bits: bits,
                meltIndices: top,
                generations: 500,
                sampleRows: sample
            )
            trials.append(trial)
            let pct = Double(sample) / Double(trial.inputSpace) * 100
            print(
                "MELT_SCALING sampled gen=500 rows=\(sample)/\(trial.inputSpace) "
                    + "(\(String(format: "%.2f", pct))%) → \(trial.searchedVerdict.rawValue) "
                    + "fitness=\(trial.fitness) "
                    + "search=\(String(format: "%.2f", trial.searchSeconds))s"
            )
        }
        report("axis-D (8-bit adder, 2-LUT melt, sampled training stimulus)", trials)

        if let first = trials.first(where: { $0.searchedVerdict == .proved }) {
            let pct = Double(first.targetRows) / Double(first.inputSpace) * 100
            print(
                "MELT_SCALING sampling verdict: search cost DECOUPLES from input "
                    + "space — \(first.targetRows) of \(first.inputSpace) rows "
                    + "(\(String(format: "%.2f", pct))%) sufficed, and the result is "
                    + "formally proven over all \(first.inputSpace) assignments."
            )
        } else {
            print(
                "MELT_SCALING sampling verdict: no sampled budget generalised; "
                    + "exhaustive stimulus remains required at this melt size."
            )
        }

        // Whatever the outcome, a sampled run must never be blessed while wrong.
        for trial in trials where trial.fitness < -0.05 {
            XCTAssertNotEqual(
                trial.searchedVerdict, .proved,
                "a wrong sampled run was proven equivalent; the formal check is broken"
            )
        }
    }

    // MARK: - Resource cost: the ABC question, made measurable

    /// Does a discovered circuit cost more or less than the hand-designed one?
    ///
    /// Until now the repository could not answer this at all — there is no area
    /// model, no depth metric, and nothing parsed `stat`. Every "no simplification
    /// win" statement was therefore unmeasurable rather than merely unproven.
    ///
    /// This measures the one resource number that *is* available: `$lut` cells
    /// surviving `abc -lut 6` and `opt_clean`. Both designs are put through the
    /// identical mapping, and both are formally proven equivalent to the same
    /// behavioural reference first, so the comparison is between two circuits that
    /// provably compute the same function.
    ///
    /// Read the result narrowly. LUT count under one ABC recipe is not area, not
    /// depth, not power, and not timing. A tie means "no measurable difference on
    /// this proxy for this circuit", not "equivalent hardware".
    func testDiscoveredVersusHandDesignedResourceCost() throws {
        guard let yosys = yosysPath() else { throw XCTSkip("yosys not found — see REPRODUCE.md") }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device not available")
        }

        let bits = 4
        // The textbook design: nothing erased, nothing searched.
        let (pristine, pristineLayout, _) = makeRippleAdder(bits: bits)
        let handDesigned = try proveAgainstReference(
            yosys: yosys,
            netlist: pristine,
            layout: pristineLayout,
            chromosome: TensorChromosome.from(netlist: pristine),
            tag: "hand-designed"
        )
        XCTAssertEqual(
            handDesigned.verdict, .proved,
            "the hand-designed ripple adder must prove against behavioural addition, "
                + "otherwise the fixture or the reference is wrong"
        )

        print("")
        print("MELT_RESOURCE hand-designed \(bits)-bit ripple adder")
        print("  source TensorLUT cells : \(pristine.luts.count)")
        print("  post abc -lut 6        : \(handDesigned.resynthLUTs.map(String.init) ?? "n/a")")
        print("  combinational levels   : \(pristine.executionLevels.count)")

        // Discovered variants at several melt sizes, each independently proven.
        for melted in [2, 4, 6] {
            let indices = Array((2 * bits - melted)..<(2 * bits))
            let trial = try runTrial(
                yosys: yosys, device: device, bits: bits, meltIndices: indices,
                generations: 500
            )
            guard trial.searchedVerdict == .proved else {
                print(
                    "MELT_RESOURCE melt=\(melted): \(trial.searchedVerdict.rawValue), "
                        + "skipping resource comparison for an unproven circuit"
                )
                continue
            }
            let discovered = trial.searchedResynthLUTs
            let delta: String
            if let discovered, let baseline = handDesigned.resynthLUTs {
                let diff = discovered - baseline
                delta = diff == 0 ? "no difference" : (diff > 0 ? "+\(diff) LUTs" : "\(diff) LUTs")
            } else {
                delta = "unavailable"
            }
            print(
                "MELT_RESOURCE melt=\(melted)/\(trial.totalLUTs) proven; post abc -lut 6 = "
                    + "\(discovered.map(String.init) ?? "n/a") vs hand-designed "
                    + "\(handDesigned.resynthLUTs.map(String.init) ?? "n/a") → \(delta)"
            )
        }

        print("")
        print(
            "MELT_RESOURCE boundary: LUT count under one ABC recipe is the only "
                + "resource proxy this repository can produce. There is no area, "
                + "depth, power, or timing model, so no simplification claim "
                + "against Yosys/ABC follows from these numbers either way."
        )

        XCTAssertNotNil(
            handDesigned.resynthLUTs,
            "could not count $lut cells after synthesis; the metric is not working"
        )
    }
}

private extension String {
    func leftPad(_ width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }
    func rightPad(_ width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }
}
