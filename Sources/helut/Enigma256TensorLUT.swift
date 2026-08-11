import Foundation
import Metal
import HELUTCore

// MARK: - Enigma 256 TensorLUT Red Team (`--enigma256-tensorlut`)

func enigma256PortNets(_ module: YosysModule, _ name: String) -> [Int32] {
    guard let port = module.ports[name] else {
        fatalError("missing port \(name)")
    }
    return port.bits.compactMap { bit -> Int32? in
        if case .net(let id) = bit { return Int32(id) }
        return nil
    }
}

/// Exhaustive coverage of each NLFF's live taps (others held at a base pattern).
func enigma256NLFFTrainingBatch(
    generation: Enigma256Generation = .current
) -> (inputs: [[Float]], expected: [[Float]]) {
    let tapSets: [[Int]] = generation.folds.map { $0.taps(for: generation.formula) }
    var seeds: [UInt64] = []
    // Base patterns so unused bits aren't all-zero lockup.
    let bases: [UInt64] = [1, 0xA5A5_A5A5_A5A5_A5A5, 0x0123_4567_89AB_CDEF]
    for base in bases {
        for taps in tapSets {
            let space = 1 << taps.count
            for mask in 0 ..< space {
                var s = base
                var clear: UInt64 = 0
                for t in taps { clear |= UInt64(1) << t }
                s &= ~clear
                for (i, t) in taps.enumerated() where (mask & (1 << i)) != 0 {
                    s |= UInt64(1) << t
                }
                if s == 0 { s = 1 }
                seeds.append(s)
            }
        }
    }
    // Extra random-ish anchors (golden LFSR included).
    seeds.append(contentsOf: [
        0xE842_0155_1FDB_C83A,
        0x8000_0000_0000_0001,
        0xFFFF_FFFF_FFFF_FFFF,
        0x7FFF_FFFF_FFFF_FFFF
    ])

    var inputs: [[Float]] = []
    var expected: [[Float]] = []
    var seen = Set<UInt64>()
    for seed in seeds where seen.insert(seed).inserted {
        let s = seed == 0 ? 1 : seed
        var row = [Float]()
        row.reserveCapacity(64)
        for bit in 0 ..< 64 {
            row.append(Float((s >> bit) & 1))
        }
        inputs.append(row)
        let mask = Enigma256LFSR(seed: s).stepMask(using: generation)
        expected.append([
            mask.0 ? 1 : 0,
            mask.1 ? 1 : 0,
            mask.2 ? 1 : 0,
            mask.3 ? 1 : 0
        ])
    }
    return (inputs, expected)
}

func runEnigma256TensorLUT() {
    _ = Enigma256Generation.bootstrapFromFixture()
    let netlistPath = stringFlag("--enigma256-netlist")
        ?? "build/enigma_256_nlff_combo_netlist.json"
    let emitOut = stringFlag("--enigma256-emit-out")
        ?? "enigma_256_tensorlut_baseline.v"
    let logPath = stringFlag("--enigma256-tensorlut-log")
        ?? "logs/tensorlut-enigma256-nlff.log"
    let smoke = !CommandLine.arguments.contains("--enigma256-tensorlut-emit-only")
    let gens = intFlag("--enigma256-tensorlut-gens") ?? 80
    let pop = intFlag("--enigma256-tensorlut-pop") ?? 32
    let polishGens = intFlag("--enigma256-tensorlut-polish") ?? max(40, gens / 2)

    guard FileManager.default.fileExists(atPath: netlistPath) else {
        fputs("""
        Missing \(netlistPath)
        Run: ./Scripts/enigma256_tensorlut_synth.sh

        """, stderr)
        exit(2)
    }

    let yosys = loadYosysNetlist(from: netlistPath)
    guard let (moduleName, module) = yosys.modules.first else {
        fatalError("empty Yosys netlist")
    }
    let soft = TensorLUTCompiler.compile(module: module)
    let chromo = TensorChromosome.from(netlist: soft)

    let inputWires: [Int32]
    let outputWires: [Int32]
    let target: AdversarialTarget

    if module.ports["init_lfsr"] != nil {
        let rstNets = enigma256PortNets(module, "rst_n")
        let loadNets = enigma256PortNets(module, "load_state")
        let initNets = enigma256PortNets(module, "init_lfsr")
        let stepNets = enigma256PortNets(module, "step")
        inputWires = rstNets + loadNets + initNets + stepNets
        outputWires = enigma256PortNets(module, "step_r1")
            + enigma256PortNets(module, "step_r2")
            + enigma256PortNets(module, "step_r3")
            + enigma256PortNets(module, "step_r4")
        target = AdversarialTarget(
            inputWireIDs: inputWires,
            outputWireIDs: outputWires,
            inputVectors: [[Float](repeating: 0, count: inputWires.count)],
            expectedOutputs: [[0, 0, 0, 0]],
            clockTicks: 1
        )
    } else {
        let lfsrNets = enigma256PortNets(module, "lfsr")
        precondition(lfsrNets.count == 64)
        inputWires = lfsrNets
        outputWires = enigma256PortNets(module, "step_r1")
            + enigma256PortNets(module, "step_r2")
            + enigma256PortNets(module, "step_r3")
            + enigma256PortNets(module, "step_r4")
        let batch = enigma256NLFFTrainingBatch()
        target = AdversarialTarget(
            inputWireIDs: inputWires,
            outputWireIDs: outputWires,
            inputVectors: batch.inputs,
            expectedOutputs: batch.expected,
            clockTicks: 0
        )
    }

    let verilog = TensorLUTEmitter.emitVerilog(
        moduleName: moduleName == "enigma_256_nlff_combo"
            ? "enigma_256_tensorlut_baseline"
            : "enigma_256_step_cone_tensorlut",
        netlist: soft,
        chromosome: chromo,
        inputWires: inputWires,
        outputWires: outputWires
    )
    do {
        try verilog.write(toFile: emitOut, atomically: true, encoding: .utf8)
    } catch {
        fatalError("emit failed: \(error)")
    }

    print("Enigma 256 TensorLUT")
    print("  module: \(moduleName)")
    print("  LUTs: \(soft.luts.count)  DFFs: \(soft.dffs.count)  wires: \(soft.totalWires)")
    print("  baseline → \(emitOut)")

    guard smoke else { return }
    guard module.ports["lfsr"] != nil else {
        print("  smoke skipped for sequential cone — use NLFF combo netlist")
        return
    }
    guard let device = MTLCreateSystemDefaultDevice() else {
        fputs("Metal unavailable — emit-only\n", stderr)
        exit(0)
    }

    let pipeline = try! TensorLUTPipeline(device: device, netlist: soft)
    let liveWidths = soft.liveWidths

    var baselineStats: AdversarialHarness.GenerationStats?
    _ = AdversarialHarness(
        device: device,
        pipeline: pipeline,
        synthesizer: try! AdversarialSynthesizer(device: device),
        netlist: soft
    ).run(
        target: target,
        config: .init(
            populationSize: 1,
            generations: 1,
            eliteCount: 1,
            seedScatter: false,
            rngSeed: 2,
            seedInits: chromo.inits
        ),
        progress: { baselineStats = $0 }
    )

    // Phase A — crypto-only explore (λ=0).
    let wiped = [Float](repeating: 0.5, count: soft.luts.count * 64)
    let exploreSynth = try! AdversarialSynthesizer(
        device: device,
        config: .init(
            mutationRate: 0.28,
            maxNoise: 0.5,
            lambdaMax: 0,
            liveWidths: liveWidths,
            discreteJumpRate: 0.5
        )
    )
    var exploreLast: AdversarialHarness.GenerationStats?
    let explored = AdversarialHarness(
        device: device,
        pipeline: pipeline,
        synthesizer: exploreSynth,
        netlist: soft
    ).run(
        target: target,
        config: .init(
            populationSize: pop,
            generations: gens,
            eliteCount: max(4, pop / 6),
            seedScatter: true,
            rngSeed: 0xE256_21,
            seedInits: wiped,
            crossoverRate: 0.7
        ),
        progress: { exploreLast = $0 }
    )

    // Phase B — binary polish with λ=0 (pad snap only). Avoid λ-crush on WIDTH<6 pads.
    let polishSynth = try! AdversarialSynthesizer(
        device: device,
        config: .init(
            mutationRate: 0.1,
            maxNoise: 0.15,
            lambdaMax: 0,
            liveWidths: liveWidths,
            discreteJumpRate: 0.7
        )
    )
    var polishLast: AdversarialHarness.GenerationStats?
    let polished = AdversarialHarness(
        device: device,
        pipeline: pipeline,
        synthesizer: polishSynth,
        netlist: soft
    ).run(
        target: target,
        config: .init(
            populationSize: pop,
            generations: polishGens,
            eliteCount: max(4, pop / 6),
            seedScatter: false,
            rngSeed: 0xE256_22,
            seedInits: explored.inits,
            crossoverRate: 0.35,
            polishBinaryAtEnd: true
        ),
        progress: { polishLast = $0 }
    )

    // Re-score the polished elite (post snap-to-binary).
    var finalStats: AdversarialHarness.GenerationStats?
    _ = AdversarialHarness(
        device: device,
        pipeline: pipeline,
        synthesizer: try! AdversarialSynthesizer(device: device, config: .init(lambdaMax: 0)),
        netlist: soft
    ).run(
        target: target,
        config: .init(
            populationSize: 1,
            generations: 1,
            eliteCount: 1,
            seedScatter: false,
            rngSeed: 3,
            seedInits: polished.inits
        ),
        progress: { finalStats = $0 }
    )

    let finalCrypto = finalStats?.bestCrypto ?? -999
    let finalNonBinary = polished.inits.reduce(0) { $0 + (($1 > 0.05 && $1 < 0.95) ? 1 : 0) }
    let survived = finalCrypto > -0.05 && finalNonBinary == 0
    let generation = Enigma256Generation.current
    // squeeze_survived=true  → Red recovered a binary elite (Blue must mutate).
    // squeeze_survived=false → Red failed the squeeze (Blue holds this generation).
    let verdict = survived ? "red_pressure" : "blue_hold"
    let report = """
    # TensorLUT Red Team — \(moduleName)
    generation: \(generation.id)
    formula: \(generation.formula.rawValue)
    netlist: \(netlistPath)
    luts: \(soft.luts.count)
    dffs: \(soft.dffs.count)
    batch: \(target.batchSize)
    explore_gens: \(gens)
    polish_gens: \(polishGens)
    pop: \(pop)
    baseline_crypto: \(baselineStats.map { String(format: "%.6f", $0.bestCrypto) } ?? "n/a")
    explore_best_crypto: \(exploreLast.map { String(format: "%.6f", $0.bestCrypto) } ?? "n/a")
    explore_nonbinary: \(exploreLast.map { String($0.bestNonBinaryCount) } ?? "n/a")
    polish_gen_crypto: \(polishLast.map { String(format: "%.6f", $0.bestCrypto) } ?? "n/a")
    final_crypto: \(String(format: "%.6f", finalCrypto))
    final_nonbinary: \(finalNonBinary)
    elite_fitness: \(String(format: "%.6f", polished.fitness))
    squeeze_survived: \(survived)
    verdict: \(verdict)
    note: λ=0 explore + λ=0 discrete polish (no λ-crush on LUT6 pads); exhaustive NLFF corners. squeeze_survived=false is a Blue hold.
    """

    try! FileManager.default.createDirectory(
        at: URL(fileURLWithPath: logPath).deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try! report.write(toFile: logPath, atomically: true, encoding: .utf8)
    print(report)
    print("  log → \(logPath)")
    if !survived {
        fputs("WARNING: final crypto/nonbinary did not meet bar (crypto \(finalCrypto), nb \(finalNonBinary))\n", stderr)
        exit(1)
    }
}
