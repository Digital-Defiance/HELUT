import XCTest
@testable import HELUTCore

final class TensorLUTStructuralEvolutionTests: XCTestCase {
    func testConstantsAndEveryValidBypassMaterializeAsBinaryLUT6Tables() throws {
        let lut = TensorLUT6Cell(
            cellID: 0,
            inputWires: [0, 1, 2],
            outputWire: 3,
            rawTruthTable: truthTable(inputCount: 3) { ($0[0] ^ $0[1]) | $0[2] }
        )
        let netlist = TensorLUTNetlist(
            luts: [lut],
            totalWires: 4,
            executionLevels: [[0]]
        )
        let baseline = TensorChromosome.from(netlist: netlist)

        for (mode, expected) in [
            (TensorLUTStructuralMode.constant0, Float(0)),
            (.constant1, Float(1)),
        ] {
            let materialized = try TensorLUTStructuralMaterializer.materialize(
                genome: TensorLUTStructuralGenome(modes: [mode]),
                baseline: baseline,
                netlist: netlist
            )
            XCTAssertEqual(materialized.inits, Array(repeating: expected, count: 64))
        }

        for pin in 0..<3 {
            let materialized = try TensorLUTStructuralMaterializer.materialize(
                genome: TensorLUTStructuralGenome(modes: [.bypass(pin: pin)]),
                baseline: baseline,
                netlist: netlist
            )
            for address in 0..<64 {
                XCTAssertEqual(
                    materialized.inits[address],
                    Float((address >> pin) & 1),
                    "pin=\(pin), address=\(address)"
                )
            }
        }
    }

    func testFrozenLUTRejectsMaterializedChangeAndMutationPreservesTableMode() throws {
        let fixture = makeRedundantXOR()
        let baseline = TensorChromosome(
            inits: fixture.netlist.packedINITBuffer(),
            freezeMask: [true, false, false]
        )
        let changedFrozen = TensorLUTStructuralGenome(
            modes: [.constant0, .table, .table]
        )

        XCTAssertThrowsError(
            try TensorLUTStructuralMaterializer.materialize(
                genome: changedFrozen,
                baseline: baseline,
                netlist: fixture.netlist
            )
        ) { error in
            XCTAssertEqual(
                error as? TensorLUTStructuralError,
                .frozenModeChange(lut: 0, mode: .constant0)
            )
        }

        var rng = TestSplitMix64(seed: 17)
        let mutated = TensorLUTStructuralEvolution.mutate(
            genome: TensorLUTStructuralGenome(lutCount: 3),
            netlist: fixture.netlist,
            freezeMask: baseline.freezeMask,
            rate: 1,
            forceAtLeastOne: true,
            rng: &rng
        )
        XCTAssertEqual(mutated.modes[0], .table)
        XCTAssertNotEqual(mutated.modes[1], .table)
        XCTAssertNotEqual(mutated.modes[2], .table)
    }

    func testCorrectLargerCircuitAlwaysOutranksWrongZeroLUTCircuit() throws {
        let fixture = makeRedundantXOR()
        let baseline = TensorChromosome.from(netlist: fixture.netlist)
        let correctMetrics = try TensorLUTStructuralAnalyzer.analyze(
            netlist: fixture.netlist,
            chromosome: baseline,
            outputWires: [fixture.outputWire]
        )
        let wrongGenome = TensorLUTStructuralGenome(
            modes: [.table, .table, .constant0]
        )
        let wrong = try TensorLUTStructuralMaterializer.materialize(
            genome: wrongGenome,
            baseline: baseline,
            netlist: fixture.netlist
        )
        let wrongMetrics = try TensorLUTStructuralAnalyzer.analyze(
            netlist: fixture.netlist,
            chromosome: wrong,
            outputWires: [fixture.outputWire]
        )
        let wrongMismatches = xorMismatchCount(
            chromosome: wrong,
            netlist: fixture.netlist,
            outputWire: fixture.outputWire
        )

        XCTAssertEqual(correctMetrics.activeReachableLUTs, 3)
        XCTAssertEqual(wrongMetrics.activeReachableLUTs, 0)
        XCTAssertEqual(wrongMismatches, 2)

        let correctScore = TensorLUTStructuralScore(
            mismatchCount: 0,
            activeReachableLUTs: correctMetrics.activeReachableLUTs,
            outputConeDepth: correctMetrics.outputConeDepth,
            supportEdges: correctMetrics.supportEdges,
            changedModeCount: 0
        )
        let wrongScore = TensorLUTStructuralScore(
            mismatchCount: wrongMismatches,
            activeReachableLUTs: wrongMetrics.activeReachableLUTs,
            outputConeDepth: wrongMetrics.outputConeDepth,
            supportEdges: wrongMetrics.supportEdges,
            changedModeCount: 1
        )
        XCTAssertLessThan(correctScore, wrongScore)
    }

    func testEvolutionSimplifiesRedundantSupergraphAndCorruptionIsDetected() throws {
        let fixture = makeRedundantXOR()
        let baseline = TensorChromosome.from(netlist: fixture.netlist)
        let config = TensorLUTStructuralEvolutionConfig(
            populationSize: 32,
            generations: 8,
            eliteCount: 6,
            tournamentSize: 3,
            mutationRate: 0.2,
            crossoverRate: 0.8,
            seed: 0x5354_5255_4354
        )

        let result = try TensorLUTStructuralEvolution.evolve(
            netlist: fixture.netlist,
            baseline: baseline,
            outputWires: [fixture.outputWire],
            config: config
        ) { chromosome in
            self.xorMismatchCount(
                chromosome: chromosome,
                netlist: fixture.netlist,
                outputWire: fixture.outputWire
            )
        }

        XCTAssertEqual(result.baseline.score.mismatchCount, 0)
        XCTAssertEqual(result.baseline.metrics.activeReachableLUTs, 3)
        XCTAssertEqual(result.baseline.metrics.outputConeDepth, 2)
        XCTAssertEqual(result.best.score.mismatchCount, 0)
        XCTAssertEqual(result.best.metrics.activeReachableLUTs, 1)
        XCTAssertEqual(result.best.metrics.outputConeDepth, 1)
        XCTAssertEqual(result.best.metrics.supportEdges, 2)
        XCTAssertEqual(result.best.genome.changedModeCount, 1)
        XCTAssertEqual(result.best.genome.modes[2], .bypass(pin: 0))
        XCTAssertGreaterThan(result.uniqueCandidatesEvaluated, 1)

        let repeated = try TensorLUTStructuralEvolution.evolve(
            netlist: fixture.netlist,
            baseline: baseline,
            outputWires: [fixture.outputWire],
            config: config
        ) { chromosome in
            self.xorMismatchCount(
                chromosome: chromosome,
                netlist: fixture.netlist,
                outputWire: fixture.outputWire
            )
        }
        XCTAssertEqual(repeated.best.genome, result.best.genome)
        XCTAssertEqual(repeated.best.score, result.best.score)

        var corrupted = result.best.chromosome
        corrupted.inits[0] = corrupted.inits[0] == 0 ? 1 : 0
        XCTAssertEqual(
            xorMismatchCount(
                chromosome: corrupted,
                netlist: fixture.netlist,
                outputWire: fixture.outputWire
            ),
            1
        )
    }

    func testAnalyzerPropagatesConstantsAndAliasesBeforeCountingSupport() throws {
        // t0 = 0; t1 = a AND t0; y = t1 OR b. The effective cone is just b.
        let luts = [
            TensorLUT6Cell(
                cellID: 0,
                inputWires: [0],
                outputWire: 2,
                rawTruthTable: "00"
            ),
            TensorLUT6Cell(
                cellID: 1,
                inputWires: [0, 2],
                outputWire: 3,
                rawTruthTable: truthTable(inputCount: 2) { $0[0] & $0[1] }
            ),
            TensorLUT6Cell(
                cellID: 2,
                inputWires: [3, 1],
                outputWire: 4,
                rawTruthTable: truthTable(inputCount: 2) { $0[0] | $0[1] }
            ),
        ]
        let netlist = TensorLUTNetlist(
            luts: luts,
            totalWires: 5,
            executionLevels: [[0], [1], [2]]
        )
        let metrics = try TensorLUTStructuralAnalyzer.analyze(
            netlist: netlist,
            chromosome: TensorChromosome.from(netlist: netlist),
            outputWires: [4]
        )
        XCTAssertEqual(metrics.activeReachableLUTs, 0)
        XCTAssertEqual(metrics.outputConeDepth, 0)
        XCTAssertEqual(metrics.supportEdges, 0)
    }

    // MARK: - Fixtures and clear oracle

    private func makeRedundantXOR() -> (netlist: TensorLUTNetlist, outputWire: Int32) {
        let xor2 = truthTable(inputCount: 2) { $0[0] ^ $0[1] }
        let and2 = truthTable(inputCount: 2) { $0[0] & $0[1] }
        let luts = [
            TensorLUT6Cell(
                cellID: 0,
                inputWires: [0, 1],
                outputWire: 2,
                rawTruthTable: xor2
            ),
            TensorLUT6Cell(
                cellID: 1,
                inputWires: [0, 1],
                outputWire: 3,
                rawTruthTable: xor2
            ),
            TensorLUT6Cell(
                cellID: 2,
                inputWires: [2, 3],
                outputWire: 4,
                rawTruthTable: and2
            ),
        ]
        return (
            TensorLUTNetlist(
                luts: luts,
                totalWires: 5,
                executionLevels: [[0, 1], [2]]
            ),
            4
        )
    }

    private func xorMismatchCount(
        chromosome: TensorChromosome,
        netlist: TensorLUTNetlist,
        outputWire: Int32
    ) -> Int {
        var mismatches = 0
        for row in 0..<4 {
            var wires = [Float](repeating: 0, count: netlist.totalWires)
            wires[0] = Float(row & 1)
            wires[1] = Float((row >> 1) & 1)
            for level in netlist.executionLevels {
                for rawIndex in level {
                    let index = Int(rawIndex)
                    let lut = netlist.luts[index]
                    let inputWires = [lut.in0, lut.in1, lut.in2, lut.in3, lut.in4, lut.in5]
                    var address = 0
                    for (pin, wire) in inputWires.enumerated() where wire >= 0 {
                        if wires[Int(wire)] == 1 { address |= 1 << pin }
                    }
                    wires[Int(lut.outWire)] = chromosome.inits[index * 64 + address]
                }
            }
            let expected = Float((row & 1) ^ ((row >> 1) & 1))
            if wires[Int(outputWire)] != expected { mismatches += 1 }
        }
        return mismatches
    }

    private func truthTable(inputCount: Int, _ body: ([Int]) -> Int) -> String {
        var result = ""
        for address in stride(from: (1 << inputCount) - 1, through: 0, by: -1) {
            let pins = (0..<inputCount).map { (address >> $0) & 1 }
            result.append(body(pins) == 0 ? "0" : "1")
        }
        return result
    }
}

private struct TestSplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
