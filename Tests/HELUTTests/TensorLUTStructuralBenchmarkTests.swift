import Foundation
import XCTest
@testable import HELUTCore

/// Apples-to-apples structural-search evidence.
///
/// Every baseline and every unique seed winner is emitted through the production
/// TensorLUT emitter, mapped by the same `abc -lut 6` script, measured from that
/// mapped JSON, and SAT-proven against independent behavioral RTL. The reported
/// cell count and cone depth are deliberately called LUT6 area/timing *proxies*;
/// there is no target library, placement, routing, STA, or power model here.
final class TensorLUTStructuralBenchmarkTests: XCTestCase {
    private static let seeds: [UInt64] = [
        0x0000_0000_0000_5EED,
        0x0000_0000_00C0_FFEE,
        0x0000_0000_51A7_E123,
    ]

    private static let lut6Model = """
    // Behavioral LUT6 used identically for every baseline and finalist.
    module LUT6 (output O, input I0, I1, I2, I3, I4, I5);
        parameter [63:0] INIT = 64'h0000000000000000;
        wire [5:0] addr = {I5, I4, I3, I2, I1, I0};
        assign O = INIT[addr];
    endmodule
    """

    private struct BenchmarkCase {
        let id: String
        let netlist: TensorLUTNetlist
        let baseline: TensorChromosome
        let inputWires: [Int32]
        let outputWires: [Int32]
        let inputSpace: Int
        let searchPatterns: [Int]
        let oracle: (Int) -> [UInt8]
        let referenceVerilog: String
    }

    private enum ProofVerdict: String {
        case proved = "PROVED"
        case refuted = "REFUTED"
        case inconclusive = "INCONCLUSIVE"
    }

    private struct FlowResult {
        let mappedLUTs: Int
        let mappedConeLUTs: Int
        let mappedDepth: Int
        let proof: ProofVerdict
        let artifactDirectory: String
    }

    private struct AggregatedCandidate {
        var candidate: TensorLUTStructuralCandidate
        var seeds: [UInt64]
    }

    private struct NetlistBuilder {
        let inputCount: Int
        var nextWire: Int32
        var luts: [TensorLUT6Cell] = []
        var levels: [[Int32]] = []
        var producerLevel: [Int32: Int] = [:]

        init(inputCount: Int) {
            self.inputCount = inputCount
            self.nextWire = Int32(inputCount)
        }

        var lutCount: Int { luts.count }

        mutating func addLUT(
            inputs: [Int32],
            _ function: ([Int]) -> Int
        ) -> Int32 {
            precondition((1...6).contains(inputs.count))
            let output = nextWire
            nextWire += 1
            let index = luts.count
            let raw = Self.truthTable(inputCount: inputs.count, function)
            luts.append(TensorLUT6Cell(
                cellID: index,
                inputWires: inputs,
                outputWire: output,
                rawTruthTable: raw
            ))
            let level = 1 + (inputs.compactMap { producerLevel[$0] }.max() ?? -1)
            while levels.count <= level { levels.append([]) }
            levels[level].append(Int32(index))
            producerLevel[output] = level
            return output
        }

        func build() -> TensorLUTNetlist {
            TensorLUTNetlist(
                luts: luts,
                totalWires: Int(nextWire),
                executionLevels: levels
            )
        }

        private static func truthTable(
            inputCount: Int,
            _ function: ([Int]) -> Int
        ) -> String {
            var result = ""
            for address in stride(from: (1 << inputCount) - 1, through: 0, by: -1) {
                let pins = (0..<inputCount).map { (address >> $0) & 1 }
                result.append(function(pins) == 0 ? "0" : "1")
            }
            return result
        }
    }

    func testMultiSeedSuiteMapsMeasuresAndFormallyProvesEveryFinalist() throws {
        guard let yosys = yosysPath() else {
            throw XCTSkip("yosys not found — install it to run the structural benchmark")
        }

        let cases = makeCases()
        XCTAssertEqual(
            cases.map(\.id),
            ["parity12", "decision6", "mux8", "popcount6", "multiplier3x3", "adder8"]
        )

        let artifactEnvironment = ProcessInfo.processInfo.environment[
            "HELUT_STRUCTURAL_BENCH_ARTIFACT_DIR"
        ]
        let artifactRoot: URL
        let shouldDeleteArtifacts: Bool
        if let artifactEnvironment, !artifactEnvironment.isEmpty {
            artifactRoot = URL(fileURLWithPath: artifactEnvironment)
            shouldDeleteArtifacts = false
        } else {
            artifactRoot = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("helut-structural-benchmark-\(UUID().uuidString)")
            shouldDeleteArtifacts = true
        }
        try FileManager.default.createDirectory(
            at: artifactRoot,
            withIntermediateDirectories: true
        )
        defer {
            if shouldDeleteArtifacts { try? FileManager.default.removeItem(at: artifactRoot) }
        }

        let configTemplate = TensorLUTStructuralEvolutionConfig(
            populationSize: 96,
            generations: 16,
            eliteCount: 12,
            tournamentSize: 4,
            mutationRate: 0.15,
            crossoverRate: 0.85,
            seed: Self.seeds[0]
        )

        var lutWins = 0
        var lutTies = 0
        var lutLosses = 0
        var depthWins = 0
        var depthTies = 0
        var depthLosses = 0
        var retainedSeedResults = 0
        var circuitReports: [[String: Any]] = []

        for benchmark in cases {
            let baselineMetrics = try TensorLUTStructuralAnalyzer.analyze(
                netlist: benchmark.netlist,
                chromosome: benchmark.baseline,
                outputWires: benchmark.outputWires
            )
            XCTAssertEqual(
                mismatchCount(benchmark, chromosome: benchmark.baseline),
                0,
                "\(benchmark.id) baseline does not match its independent oracle"
            )
            let baselineFlow = try mapMeasureAndProve(
                yosys: yosys,
                benchmark: benchmark,
                chromosome: benchmark.baseline,
                artifactRoot: artifactRoot,
                tag: "baseline"
            )
            XCTAssertEqual(
                baselineFlow.proof,
                .proved,
                "\(benchmark.id) baseline was not formally proven"
            )

            var grouped: [TensorLUTStructuralGenome: AggregatedCandidate] = [:]
            var seedSearchRows: [[String: Any]] = []
            for seed in Self.seeds {
                var config = configTemplate
                config.seed = seed
                let result = try TensorLUTStructuralEvolution.evolve(
                    netlist: benchmark.netlist,
                    baseline: benchmark.baseline,
                    outputWires: benchmark.outputWires,
                    config: config
                ) { chromosome in
                    self.mismatchCount(benchmark, chromosome: chromosome)
                }
                XCTAssertEqual(result.best.score.mismatchCount, 0)
                XCTAssertLessThan(
                    result.best.metrics.activeReachableLUTs,
                    result.baseline.metrics.activeReachableLUTs,
                    "\(benchmark.id) seed \(seedHex(seed)) found no structural simplification"
                )

                if var aggregate = grouped[result.best.genome] {
                    aggregate.seeds.append(seed)
                    grouped[result.best.genome] = aggregate
                } else {
                    grouped[result.best.genome] = AggregatedCandidate(
                        candidate: result.best,
                        seeds: [seed]
                    )
                }
                seedSearchRows.append([
                    "seed": seedHex(seed),
                    "mode_vector": modeVector(result.best.genome),
                    "search_mismatches": result.best.score.mismatchCount,
                    "pre_active_luts": result.best.metrics.activeReachableLUTs,
                    "pre_depth": result.best.metrics.outputConeDepth,
                    "pre_support_edges": result.best.metrics.supportEdges,
                    "changed_modes": result.best.genome.changedModeCount,
                    "unique_candidates_evaluated": result.uniqueCandidatesEvaluated,
                ])
            }

            var finalistReports: [[String: Any]] = []
            let aggregates = grouped.values.sorted {
                modeVector($0.candidate.genome) < modeVector($1.candidate.genome)
            }
            for (index, aggregate) in aggregates.enumerated() {
                let flow = try mapMeasureAndProve(
                    yosys: yosys,
                    benchmark: benchmark,
                    chromosome: aggregate.candidate.chromosome,
                    artifactRoot: artifactRoot,
                    tag: "finalist-\(index)"
                )
                XCTAssertEqual(
                    flow.proof,
                    .proved,
                    "\(benchmark.id) finalist \(index) was not formally proven"
                )

                let lutDelta = flow.mappedLUTs - baselineFlow.mappedLUTs
                let depthDelta = flow.mappedDepth - baselineFlow.mappedDepth
                if lutDelta < 0 {
                    lutWins += aggregate.seeds.count
                } else if lutDelta == 0 {
                    lutTies += aggregate.seeds.count
                } else {
                    lutLosses += aggregate.seeds.count
                }
                if depthDelta < 0 {
                    depthWins += aggregate.seeds.count
                } else if depthDelta == 0 {
                    depthTies += aggregate.seeds.count
                } else {
                    depthLosses += aggregate.seeds.count
                }
                retainedSeedResults += aggregate.seeds.count

                for seed in aggregate.seeds {
                    print(
                        "STRUCTURAL_ABC circuit=\(benchmark.id) seed=\(seedHex(seed)) "
                            + "search_rows=\(benchmark.searchPatterns.count)/\(benchmark.inputSpace) "
                            + "pre_luts=\(aggregate.candidate.metrics.activeReachableLUTs) "
                            + "pre_depth=\(aggregate.candidate.metrics.outputConeDepth) "
                            + "mapped_luts=\(flow.mappedLUTs) "
                            + "mapped_cone_luts=\(flow.mappedConeLUTs) "
                            + "mapped_depth=\(flow.mappedDepth) "
                            + "delta_luts=\(lutDelta) delta_depth=\(depthDelta) "
                            + "proof=\(flow.proof.rawValue) retained=true"
                    )
                }

                finalistReports.append([
                    "seeds": aggregate.seeds.map(seedHex),
                    "mode_vector": modeVector(aggregate.candidate.genome),
                    "search_mismatches": aggregate.candidate.score.mismatchCount,
                    "pre_active_luts": aggregate.candidate.metrics.activeReachableLUTs,
                    "pre_depth": aggregate.candidate.metrics.outputConeDepth,
                    "pre_support_edges": aggregate.candidate.metrics.supportEdges,
                    "changed_modes": aggregate.candidate.genome.changedModeCount,
                    "mapped_luts": flow.mappedLUTs,
                    "mapped_cone_luts": flow.mappedConeLUTs,
                    "mapped_depth": flow.mappedDepth,
                    "delta_mapped_luts": lutDelta,
                    "delta_mapped_depth": depthDelta,
                    "proof": flow.proof.rawValue,
                    "retained": flow.proof == .proved,
                    "artifact_directory": flow.artifactDirectory,
                ])
            }

            circuitReports.append([
                "id": benchmark.id,
                "input_space": benchmark.inputSpace,
                "search_rows": benchmark.searchPatterns.count,
                "input_wires": benchmark.inputWires.map(Int.init),
                "output_wires": benchmark.outputWires.map(Int.init),
                "seeds": seedSearchRows,
                "baseline": [
                    "pre_active_luts": baselineMetrics.activeReachableLUTs,
                    "pre_depth": baselineMetrics.outputConeDepth,
                    "pre_support_edges": baselineMetrics.supportEdges,
                    "mapped_luts": baselineFlow.mappedLUTs,
                    "mapped_cone_luts": baselineFlow.mappedConeLUTs,
                    "mapped_depth": baselineFlow.mappedDepth,
                    "proof": baselineFlow.proof.rawValue,
                    "artifact_directory": baselineFlow.artifactDirectory,
                ],
                "unique_finalists": finalistReports,
            ])
        }

        let expectedSeedResults = cases.count * Self.seeds.count
        XCTAssertEqual(retainedSeedResults, expectedSeedResults)
        XCTAssertEqual(lutWins + lutTies + lutLosses, expectedSeedResults)
        XCTAssertEqual(depthWins + depthTies + depthLosses, expectedSeedResults)

        let version = try run(yosys, ["-V"], cwd: artifactRoot).1
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let report: [String: Any] = [
            "schema": "helut.tensorlut.structural-abc-benchmark.v1",
            "timestamp_utc": ISO8601DateFormatter().string(from: Date()),
            "status": "PASS",
            "yosys_version": version,
            "flow": [
                "lut_size": 6,
                "synthesis": "read LUT6 model + emitted candidate; hierarchy -check; proc; flatten; opt; techmap; opt; abc -lut 6; opt_clean; check -assert; write_json",
                "proof": "read mapped JSON + independent behavioral RTL; miter -equiv -flatten; sat -prove trigger 0",
                "area_proxy": "post-ABC $lut cell count",
                "timing_proxy": "maximum post-ABC output-cone LUT levels",
            ],
            "evolution": [
                "population": configTemplate.populationSize,
                "generations": configTemplate.generations,
                "elite_count": configTemplate.eliteCount,
                "tournament_size": configTemplate.tournamentSize,
                "mutation_rate": configTemplate.mutationRate,
                "crossover_rate": configTemplate.crossoverRate,
                "seeds": Self.seeds.map(seedHex),
                "rank": ["mismatches", "active_luts", "depth", "support_edges", "changed_modes"],
            ],
            "summary": [
                "circuits": cases.count,
                "seed_results": expectedSeedResults,
                "retained_and_proved": retainedSeedResults,
                "mapped_lut_wins": lutWins,
                "mapped_lut_ties": lutTies,
                "mapped_lut_losses": lutLosses,
                "mapped_depth_wins": depthWins,
                "mapped_depth_ties": depthTies,
                "mapped_depth_losses": depthLosses,
            ],
            "claim_boundary": "LUT6 count and LUT-level depth under this one ABC flow are implementation proxies, not physical area, delay, frequency, power, or a general synthesis result.",
            "circuits": circuitReports,
        ]
        let reportData = try JSONSerialization.data(
            withJSONObject: report,
            options: [.prettyPrinted, .sortedKeys]
        )
        try reportData.write(to: artifactRoot.appendingPathComponent("report.json"))

        print(
            "STRUCTURAL_ABC_SUMMARY circuits=\(cases.count) seeds=\(expectedSeedResults) "
                + "retained_proved=\(retainedSeedResults) "
                + "lut_wins=\(lutWins) lut_ties=\(lutTies) lut_losses=\(lutLosses) "
                + "depth_wins=\(depthWins) depth_ties=\(depthTies) depth_losses=\(depthLosses) "
                + "proxy_only=true result=PASS"
        )
        print("STRUCTURAL_ABC_REPORT \(artifactRoot.appendingPathComponent("report.json").path)")
    }

    // MARK: - Identical map, measure, and proof path

    private func mapMeasureAndProve(
        yosys: String,
        benchmark: BenchmarkCase,
        chromosome: TensorChromosome,
        artifactRoot: URL,
        tag: String
    ) throws -> FlowResult {
        let top = "\(benchmark.id)_dut"
        let reference = "\(benchmark.id)_ref"
        let directory = artifactRoot
            .appendingPathComponent(benchmark.id)
            .appendingPathComponent(tag)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let emitted = TensorLUTEmitter.emitVerilog(
            moduleName: top,
            netlist: benchmark.netlist,
            chromosome: chromosome,
            inputWires: benchmark.inputWires,
            outputWires: benchmark.outputWires
        )
        let flowScript = """
        read_verilog lut6.v
        read_verilog emitted.v
        hierarchy -check -top \(top)
        proc
        flatten
        opt
        techmap
        opt
        abc -lut 6
        opt_clean
        check -assert
        stat
        write_json resynth.json
        """
        let proofScript = """
        read_json resynth.json
        read_verilog reference.v
        proc
        opt
        miter -equiv -flatten \(reference) \(top) miter
        flatten miter
        opt
        sat -prove trigger 0 -show-inputs -show-outputs miter
        """

        try emitted.write(
            to: directory.appendingPathComponent("emitted.v"),
            atomically: true,
            encoding: .utf8
        )
        try Self.lut6Model.write(
            to: directory.appendingPathComponent("lut6.v"),
            atomically: true,
            encoding: .utf8
        )
        try benchmark.referenceVerilog.write(
            to: directory.appendingPathComponent("reference.v"),
            atomically: true,
            encoding: .utf8
        )
        try flowScript.write(
            to: directory.appendingPathComponent("flow.ys"),
            atomically: true,
            encoding: .utf8
        )
        try proofScript.write(
            to: directory.appendingPathComponent("prove.ys"),
            atomically: true,
            encoding: .utf8
        )

        let (synthStatus, synthLog) = try run(yosys, ["flow.ys"], cwd: directory)
        try synthLog.write(
            to: directory.appendingPathComponent("synthesis.log"),
            atomically: true,
            encoding: .utf8
        )
        let mappedPath = directory.appendingPathComponent("resynth.json")
        guard synthStatus == 0, FileManager.default.fileExists(atPath: mappedPath.path) else {
            throw benchmarkFailure(
                "\(benchmark.id)/\(tag) synthesis failed (status \(synthStatus)): \(synthLog.suffix(2000))"
            )
        }

        let mapped = loadYosysNetlist(from: mappedPath.path)
        guard let mappedModule = mapped.modules[top] else {
            throw benchmarkFailure("\(benchmark.id)/\(tag) mapped top \(top) is missing")
        }
        // Current Yosys releases may retain `$scopeinfo` cells in JSON after
        // flattening. They carry source hierarchy metadata only; the production
        // intentionally ignores them. Any other non-LUT cell is a metric gap and
        // remains fail-closed.
        let unsupported = Set(
            mappedModule.cells.values.map(\.type).filter {
                $0 != "$lut" && $0 != "$scopeinfo"
            }
        )
        guard unsupported.isEmpty else {
            throw benchmarkFailure(
                "\(benchmark.id)/\(tag) contains unsupported mapped cells: \(unsupported.sorted())"
            )
        }

        let mappedLUTs = mappedModule.cells.values.filter { $0.type == "$lut" }.count
        let mappedNetlist = TensorLUTCompiler.compile(module: mappedModule)
        let mappedOutputBits = mappedModule.ports
            .filter { $0.value.direction == "output" && $0.key.hasPrefix("out_") }
            .sorted { $0.key < $1.key }
            .flatMap { $0.value.bits }
        let mappedOutputWires = mappedOutputBits.compactMap { bit -> Int32? in
            guard case .net(let wire) = bit else { return nil }
            return Int32(wire)
        }
        let mappedMetrics: TensorLUTStructuralMetrics
        if mappedOutputWires.isEmpty {
            mappedMetrics = TensorLUTStructuralMetrics(
                activeReachableLUTs: 0,
                outputConeDepth: 0,
                supportEdges: 0
            )
        } else {
            mappedMetrics = try TensorLUTStructuralAnalyzer.analyze(
                netlist: mappedNetlist,
                chromosome: TensorChromosome.from(netlist: mappedNetlist),
                outputWires: mappedOutputWires
            )
        }

        let (proofStatus, proofLog) = try run(yosys, ["prove.ys"], cwd: directory)
        try proofLog.write(
            to: directory.appendingPathComponent("proof.log"),
            atomically: true,
            encoding: .utf8
        )
        let proof: ProofVerdict
        if proofStatus != 0 {
            proof = .inconclusive
        } else if proofLog.contains("no model found: SUCCESS") {
            proof = .proved
        } else if proofLog.contains("model found: FAIL") {
            proof = .refuted
        } else {
            proof = .inconclusive
        }

        return FlowResult(
            mappedLUTs: mappedLUTs,
            mappedConeLUTs: mappedMetrics.activeReachableLUTs,
            mappedDepth: mappedMetrics.outputConeDepth,
            proof: proof,
            artifactDirectory: directory.path
        )
    }

    // MARK: - Benchmark corpus

    private func makeCases() -> [BenchmarkCase] {
        [
            makeParity12(),
            makeDecision6(),
            makeMux8(),
            makePopcount6(),
            makeMultiplier3x3(),
            makeAdder8(),
        ]
    }

    private func makeParity12() -> BenchmarkCase {
        var builder = NetlistBuilder(inputCount: 12)
        func parityNetwork(_ builder: inout NetlistBuilder) -> Int32 {
            let low = builder.addLUT(inputs: (0..<6).map(Int32.init)) { $0.reduce(0, ^) }
            let high = builder.addLUT(inputs: (6..<12).map(Int32.init)) { $0.reduce(0, ^) }
            return builder.addLUT(inputs: [low, high]) { $0[0] ^ $0[1] }
        }
        let left = parityNetwork(&builder)
        let right = parityNetwork(&builder)
        let output = builder.addLUT(inputs: [left, right]) { $0[0] & $0[1] }
        let inputs = (0..<12).map(Int32.init)
        let oracle: (Int) -> [UInt8] = { pattern in
            [UInt8(pattern.nonzeroBitCount & 1)]
        }
        return makeCase(
            id: "parity12",
            builder: builder,
            inputWires: inputs,
            outputWires: [output],
            searchPatterns: Array(0..<(1 << 12)),
            oracle: oracle,
            referenceBody: "assign out_\(output) = "
                + inputs.map { "in_\($0)" }.joined(separator: " ^ ") + ";"
        )
    }

    private func makeDecision6() -> BenchmarkCase {
        var builder = NetlistBuilder(inputCount: 6)
        let decision: ([Int]) -> Int = { p in
            p[0] == 1 ? (p[1] == 1 ? p[2] : p[3]) : (p[4] == 1 ? p[5] : p[2])
        }
        let inputs = (0..<6).map(Int32.init)
        let left = builder.addLUT(inputs: inputs, decision)
        let right = builder.addLUT(inputs: inputs, decision)
        let output = builder.addLUT(inputs: [left, right]) { $0[0] & $0[1] }
        let oracle: (Int) -> [UInt8] = { pattern in
            let bit: (Int) -> Int = { (pattern >> $0) & 1 }
            let value = bit(0) == 1
                ? (bit(1) == 1 ? bit(2) : bit(3))
                : (bit(4) == 1 ? bit(5) : bit(2))
            return [UInt8(value)]
        }
        return makeCase(
            id: "decision6",
            builder: builder,
            inputWires: inputs,
            outputWires: [output],
            searchPatterns: Array(0..<(1 << 6)),
            oracle: oracle,
            referenceBody: "assign out_\(output) = in_0 ? (in_1 ? in_2 : in_3) : (in_4 ? in_5 : in_2);"
        )
    }

    private func makeMux8() -> BenchmarkCase {
        var builder = NetlistBuilder(inputCount: 11)
        func mux(_ builder: inout NetlistBuilder, _ low: Int32, _ high: Int32, _ select: Int32) -> Int32 {
            builder.addLUT(inputs: [low, high, select]) { $0[2] == 0 ? $0[0] : $0[1] }
        }
        func muxNetwork(_ builder: inout NetlistBuilder) -> Int32 {
            let first = stride(from: 0, to: 8, by: 2).map {
                mux(&builder, Int32($0), Int32($0 + 1), 8)
            }
            let second = [
                mux(&builder, first[0], first[1], 9),
                mux(&builder, first[2], first[3], 9),
            ]
            return mux(&builder, second[0], second[1], 10)
        }
        let left = muxNetwork(&builder)
        let right = muxNetwork(&builder)
        let output = builder.addLUT(inputs: [left, right]) { $0[0] & $0[1] }
        let oracle: (Int) -> [UInt8] = { pattern in
            let select = (pattern >> 8) & 0b111
            return [UInt8((pattern >> select) & 1)]
        }
        return makeCase(
            id: "mux8",
            builder: builder,
            inputWires: (0..<11).map(Int32.init),
            outputWires: [output],
            searchPatterns: Array(0..<(1 << 11)),
            oracle: oracle,
            referenceBody: """
                wire [7:0] data = {in_7, in_6, in_5, in_4, in_3, in_2, in_1, in_0};
                wire [2:0] select = {in_10, in_9, in_8};
                assign out_\(output) = data[select];
            """
        )
    }

    private func makePopcount6() -> BenchmarkCase {
        var builder = NetlistBuilder(inputCount: 6)
        let inputs = (0..<6).map(Int32.init)
        var outputs: [Int32] = []
        for bit in 0..<3 {
            let function: ([Int]) -> Int = { pins in
                (pins.reduce(0, +) >> bit) & 1
            }
            let left = builder.addLUT(inputs: inputs, function)
            let right = builder.addLUT(inputs: inputs, function)
            outputs.append(builder.addLUT(inputs: [left, right]) { $0[0] & $0[1] })
        }
        let oracle: (Int) -> [UInt8] = { pattern in
            let count = (pattern & 0b11_1111).nonzeroBitCount
            return (0..<3).map { UInt8((count >> $0) & 1) }
        }
        return makeCase(
            id: "popcount6",
            builder: builder,
            inputWires: inputs,
            outputWires: outputs,
            searchPatterns: Array(0..<(1 << 6)),
            oracle: oracle,
            referenceBody: """
                wire [2:0] count = {2'b00, in_0} + {2'b00, in_1} + {2'b00, in_2}
                    + {2'b00, in_3} + {2'b00, in_4} + {2'b00, in_5};
                assign out_\(outputs[0]) = count[0];
                assign out_\(outputs[1]) = count[1];
                assign out_\(outputs[2]) = count[2];
            """
        )
    }

    private func makeMultiplier3x3() -> BenchmarkCase {
        var builder = NetlistBuilder(inputCount: 6)
        let inputs = (0..<6).map(Int32.init)
        var outputs: [Int32] = []
        for bit in 0..<6 {
            let function: ([Int]) -> Int = { pins in
                let a = pins[0] | (pins[1] << 1) | (pins[2] << 2)
                let b = pins[3] | (pins[4] << 1) | (pins[5] << 2)
                return ((a * b) >> bit) & 1
            }
            let left = builder.addLUT(inputs: inputs, function)
            let right = builder.addLUT(inputs: inputs, function)
            outputs.append(builder.addLUT(inputs: [left, right]) { $0[0] & $0[1] })
        }
        let oracle: (Int) -> [UInt8] = { pattern in
            let product = (pattern & 0b111) * ((pattern >> 3) & 0b111)
            return (0..<6).map { UInt8((product >> $0) & 1) }
        }
        let outputAssignments = outputs.enumerated().map {
            "assign out_\($0.element) = product[\($0.offset)];"
        }.joined(separator: "\n")
        return makeCase(
            id: "multiplier3x3",
            builder: builder,
            inputWires: inputs,
            outputWires: outputs,
            searchPatterns: Array(0..<(1 << 6)),
            oracle: oracle,
            referenceBody: """
                wire [2:0] a = {in_2, in_1, in_0};
                wire [2:0] b = {in_5, in_4, in_3};
                wire [5:0] product = a * b;
                \(outputAssignments)
            """
        )
    }

    private func makeAdder8() -> BenchmarkCase {
        var builder = NetlistBuilder(inputCount: 16)
        func ripple(_ builder: inout NetlistBuilder) -> [Int32] {
            var sums: [Int32] = []
            var carry: Int32 = -1
            for bit in 0..<8 {
                let a = Int32(bit)
                let b = Int32(8 + bit)
                if bit == 0 {
                    sums.append(builder.addLUT(inputs: [a, b]) { $0[0] ^ $0[1] })
                    carry = builder.addLUT(inputs: [a, b]) { $0[0] & $0[1] }
                } else {
                    sums.append(builder.addLUT(inputs: [a, b, carry]) {
                        $0[0] ^ $0[1] ^ $0[2]
                    })
                    carry = builder.addLUT(inputs: [a, b, carry]) {
                        ($0[0] + $0[1] + $0[2]) >= 2 ? 1 : 0
                    }
                }
            }
            return sums + [carry]
        }
        let left = ripple(&builder)
        let right = ripple(&builder)
        let functionalLUTs = builder.lutCount
        var outputs: [Int32] = []
        for bit in 0..<9 {
            outputs.append(builder.addLUT(inputs: [left[bit], right[bit]]) { $0[0] & $0[1] })
        }
        let netlist = builder.build()
        let freezeMask = netlist.luts.indices.map { $0 < functionalLUTs }
        let baseline = TensorChromosome(
            inits: netlist.packedINITBuffer(),
            freezeMask: freezeMask
        )
        let oracle: (Int) -> [UInt8] = { pattern in
            let sum = (pattern & 0xFF) + ((pattern >> 8) & 0xFF)
            return (0..<9).map { UInt8((sum >> $0) & 1) }
        }
        var sampled = Set<Int>()
        for a in 0..<256 {
            sampled.insert(a)
            sampled.insert(a | (255 << 8))
        }
        let assignments = outputs.enumerated().map {
            "assign out_\($0.element) = sum[\($0.offset)];"
        }.joined(separator: "\n")
        return BenchmarkCase(
            id: "adder8",
            netlist: netlist,
            baseline: baseline,
            inputWires: (0..<16).map(Int32.init),
            outputWires: outputs,
            inputSpace: 1 << 16,
            searchPatterns: sampled.sorted(),
            oracle: oracle,
            referenceVerilog: referenceModule(
                name: "adder8_ref",
                inputWires: (0..<16).map(Int32.init),
                outputWires: outputs,
                body: """
                    wire [7:0] a = {in_7, in_6, in_5, in_4, in_3, in_2, in_1, in_0};
                    wire [7:0] b = {in_15, in_14, in_13, in_12, in_11, in_10, in_9, in_8};
                    wire [8:0] sum = {1'b0, a} + {1'b0, b};
                    \(assignments)
                """
            )
        )
    }

    private func makeCase(
        id: String,
        builder: NetlistBuilder,
        inputWires: [Int32],
        outputWires: [Int32],
        searchPatterns: [Int],
        oracle: @escaping (Int) -> [UInt8],
        referenceBody: String
    ) -> BenchmarkCase {
        let netlist = builder.build()
        return BenchmarkCase(
            id: id,
            netlist: netlist,
            baseline: TensorChromosome.from(netlist: netlist),
            inputWires: inputWires,
            outputWires: outputWires,
            inputSpace: 1 << inputWires.count,
            searchPatterns: searchPatterns,
            oracle: oracle,
            referenceVerilog: referenceModule(
                name: "\(id)_ref",
                inputWires: inputWires,
                outputWires: outputWires,
                body: referenceBody
            )
        )
    }

    private func referenceModule(
        name: String,
        inputWires: [Int32],
        outputWires: [Int32],
        body: String
    ) -> String {
        let ports = ["clk"]
            + inputWires.map { "in_\($0)" }
            + outputWires.map { "out_\($0)" }
        let inputs = (["clk"] + inputWires.map { "in_\($0)" })
            .map { "    input \($0);" }
            .joined(separator: "\n")
        let outputs = outputWires
            .map { "    output out_\($0);" }
            .joined(separator: "\n")
        let indentedBody = body.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "    " + $0 }
            .joined(separator: "\n")
        return """
        module \(name)(\(ports.joined(separator: ", ")));
        \(inputs)
        \(outputs)
        \(indentedBody)
        endmodule
        """
    }

    // MARK: - Search oracle and utilities

    private func mismatchCount(
        _ benchmark: BenchmarkCase,
        chromosome: TensorChromosome
    ) -> Int {
        var mismatches = 0
        for pattern in benchmark.searchPatterns {
            var wires = [UInt8](repeating: 0, count: benchmark.netlist.totalWires)
            for (bit, wire) in benchmark.inputWires.enumerated() {
                wires[Int(wire)] = UInt8((pattern >> bit) & 1)
            }
            for level in benchmark.netlist.executionLevels {
                for rawIndex in level {
                    let index = Int(rawIndex)
                    let lut = benchmark.netlist.luts[index]
                    let pins = [lut.in0, lut.in1, lut.in2, lut.in3, lut.in4, lut.in5]
                    var address = 0
                    for (pin, wire) in pins.enumerated() where wire >= 0 {
                        if wires[Int(wire)] != 0 { address |= 1 << pin }
                    }
                    wires[Int(lut.outWire)] = chromosome.inits[index * 64 + address] == 1 ? 1 : 0
                }
            }
            let expected = benchmark.oracle(pattern)
            for (index, wire) in benchmark.outputWires.enumerated() {
                if wires[Int(wire)] != expected[index] { mismatches += 1 }
            }
        }
        return mismatches
    }

    private func modeVector(_ genome: TensorLUTStructuralGenome) -> String {
        genome.modes.map { mode in
            switch mode {
            case .table: return "T"
            case .constant0: return "C0"
            case .constant1: return "C1"
            case .bypass(let pin): return "B\(pin)"
            }
        }.joined(separator: ",")
    }

    private func seedHex(_ seed: UInt64) -> String {
        String(format: "0x%016llx", seed)
    }

    private func yosysPath() -> String? {
        for candidate in ["/opt/homebrew/bin/yosys", "/usr/local/bin/yosys", "/usr/bin/yosys"] {
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    private func run(
        _ executable: String,
        _ arguments: [String],
        cwd: URL
    ) throws -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = cwd
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private func benchmarkFailure(_ message: String) -> NSError {
        NSError(
            domain: "TensorLUTStructuralBenchmarkTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
