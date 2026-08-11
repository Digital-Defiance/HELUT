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

func runEnigma256TensorLUT() {
    // Default attack surface: pure NLFF combo (TensorLUT-friendly, no DFFs).
    // Sequential step cone remains available via --enigma256-netlist.
    let netlistPath = stringFlag("--enigma256-netlist")
        ?? "build/enigma_256_nlff_combo_netlist.json"
    let emitOut = stringFlag("--enigma256-emit-out")
        ?? "enigma_256_tensorlut_baseline.v"
    let logPath = stringFlag("--enigma256-tensorlut-log")
        ?? "logs/tensorlut-enigma256-nlff.log"
    let smoke = !CommandLine.arguments.contains("--enigma256-tensorlut-emit-only")
    let gens = intFlag("--enigma256-tensorlut-gens") ?? 40
    let pop = intFlag("--enigma256-tensorlut-pop") ?? 24

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
        // Sequential step cone — emit only recommended; smoke uses NLFF combo by default.
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

        let seeds: [UInt64] = [
            1,
            0xE842_0155_1FDB_C83A,
            0x8000_0000_0000_0001,
            0x0123_4567_89AB_CDEF,
            0xFFFF_FFFF_FFFF_FFFF,
            0x00FF_00FF_00FF_00FF,
            0x0F0F_0F0F_0F0F_0F0F,
            0xA5A5_A5A5_A5A5_A5A5,
            0x1111_2222_3333_4444,
            0xDEAD_BEEF_CAFE_BABE,
            0x0123_4567_89AB_0000,
            0x7FFF_FFFF_FFFF_FFFF,
            0x0000_0000_0000_0002,
            0x5555_5555_5555_5555,
            0xAAAA_AAAA_AAAA_AAAA,
            0x0
        ]
        var inputs: [[Float]] = []
        var expected: [[Float]] = []
        for seed in seeds {
            let s = seed == 0 ? 1 : seed
            var row = [Float]()
            for b in 0..<64 {
                row.append(Float((s >> b) & 1))
            }
            inputs.append(row)
            let mask = Enigma256LFSR(seed: s).stepMask
            expected.append([
                mask.0 ? 1 : 0,
                mask.1 ? 1 : 0,
                mask.2 ? 1 : 0,
                mask.3 ? 1 : 0
            ])
        }
        target = AdversarialTarget(
            inputWireIDs: inputWires,
            outputWireIDs: outputWires,
            inputVectors: inputs,
            expectedOutputs: expected,
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

    let wiped = [Float](repeating: 0.5, count: soft.luts.count * 64)
    let liveWidths = soft.liveWidths
    let exploreSynth = try! AdversarialSynthesizer(
        device: device,
        config: .init(
            mutationRate: 0.25,
            maxNoise: 0.5,
            lambdaMax: 0,
            liveWidths: liveWidths,
            discreteJumpRate: 0.4
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
            eliteCount: max(2, pop / 8),
            seedScatter: true,
            rngSeed: 0xE256_01,
            seedInits: wiped,
            crossoverRate: 0.6
        ),
        progress: { exploreLast = $0 }
    )

    let squeezeSynth = try! AdversarialSynthesizer(
        device: device,
        config: .init(
            mutationRate: 0.12,
            maxNoise: 0.25,
            lambdaMax: 12,
            liveWidths: liveWidths,
            lambdaDelayFraction: 0.1,
            discreteJumpRate: 0.5
        )
    )
    var squeezeLast: AdversarialHarness.GenerationStats?
    let squeezed = AdversarialHarness(
        device: device,
        pipeline: pipeline,
        synthesizer: squeezeSynth,
        netlist: soft
    ).run(
        target: target,
        config: .init(
            populationSize: pop,
            generations: gens,
            eliteCount: max(2, pop / 8),
            seedScatter: true,
            rngSeed: 0xE256_02,
            seedInits: explored.inits,
            crossoverRate: 0.5,
            polishBinaryAtEnd: true
        ),
        progress: { squeezeLast = $0 }
    )

    let report = """
    # TensorLUT Red Team — \(moduleName)
    netlist: \(netlistPath)
    luts: \(soft.luts.count)
    dffs: \(soft.dffs.count)
    batch: \(target.batchSize)
    baseline_crypto: \(baselineStats.map { String(format: "%.6f", $0.bestCrypto) } ?? "n/a")
    explore_best_crypto: \(exploreLast.map { String(format: "%.6f", $0.bestCrypto) } ?? "n/a")
    explore_nonbinary: \(exploreLast.map { String($0.bestNonBinaryCount) } ?? "n/a")
    squeeze_best_crypto: \(squeezeLast.map { String(format: "%.6f", $0.bestCrypto) } ?? "n/a")
    squeeze_best_fitness: \(squeezeLast.map { String(format: "%.6f", $0.bestFitness) } ?? "n/a")
    squeeze_nonbinary: \(squeezeLast.map { String($0.bestNonBinaryCount) } ?? "n/a")
    elite_fitness: \(String(format: "%.6f", squeezed.fitness))
    note: NLFF combo is the deliberate first Red Team target; full core BRAM flatten deferred.
    """

    try! FileManager.default.createDirectory(
        at: URL(fileURLWithPath: logPath).deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try! report.write(toFile: logPath, atomically: true, encoding: .utf8)
    print(report)
    print("  log → \(logPath)")
}
