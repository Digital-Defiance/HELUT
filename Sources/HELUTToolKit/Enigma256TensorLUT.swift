import Foundation
import Metal
import HELUTCore
import HELUTCLI

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
/// Optional Galois next-state byte densifies the Red cone past NLFF-only.
enum Enigma256NLFFExtraOut: Sendable {
    case none
    case nextLo // lfsr_next[7:0] — trivial shift on this poly; prefer nextHi
    case nextHi // lfsr_next[63:56] — includes feedback taps
}

func enigma256NLFFSeedPatterns(
    generation: Enigma256Generation = .current
) -> [UInt64] {
    let tapSets: [[Int]] = generation.folds.map { $0.taps(for: generation.formula) }
    var seeds: [UInt64] = []
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
    seeds.append(contentsOf: [
        0xE842_0155_1FDB_C83A,
        0x8000_0000_0000_0001,
        0xFFFF_FFFF_FFFF_FFFF,
        0x7FFF_FFFF_FFFF_FFFF
    ])
    var seen = Set<UInt64>()
    return seeds.filter { seen.insert($0).inserted }.map { $0 == 0 ? 1 : $0 }
}

func enigma256AppendByteBits(_ out: inout [Float], _ value: UInt8) {
    for bit in 0 ..< 8 {
        out.append(Float((value >> bit) & 1))
    }
}

func enigma256AppendExtraOut(
    _ out: inout [Float],
    seed: UInt64,
    extra: Enigma256NLFFExtraOut
) {
    switch extra {
    case .none:
        break
    case .nextLo:
        let next = Enigma256LFSR(seed: seed).next
        for bit in 0 ..< 8 {
            out.append(Float((next >> bit) & 1))
        }
    case .nextHi:
        let next = Enigma256LFSR(seed: seed).next
        for bit in 0 ..< 8 {
            out.append(Float((next >> (56 + bit)) & 1))
        }
    }
}

func enigma256NLFFTrainingBatch(
    generation: Enigma256Generation = .current,
    extra: Enigma256NLFFExtraOut = .none
) -> (inputs: [[Float]], expected: [[Float]]) {
    var inputs: [[Float]] = []
    var expected: [[Float]] = []
    for s in enigma256NLFFSeedPatterns(generation: generation) {
        var row = [Float]()
        row.reserveCapacity(64)
        for bit in 0 ..< 64 {
            row.append(Float((s >> bit) & 1))
        }
        inputs.append(row)
        let mask = Enigma256LFSR(seed: s).stepMask(using: generation)
        var out: [Float] = [
            mask.0 ? 1 : 0,
            mask.1 ? 1 : 0,
            mask.2 ? 1 : 0,
            mask.3 ? 1 : 0
        ]
        enigma256AppendExtraOut(&out, seed: s, extra: extra)
        expected.append(out)
    }
    return (inputs, expected)
}

/// Past-NLFF cone: LFSR + four 8-bit offsets → steps + next offsets (+ optional lfsr_next_hi).
func enigma256NLFFOffsetTrainingBatch(
    generation: Enigma256Generation = .current,
    extra: Enigma256NLFFExtraOut = .none
) -> (inputs: [[Float]], expected: [[Float]]) {
    let offsetPatterns: [(UInt8, UInt8, UInt8, UInt8)] = [
        (0x00, 0x00, 0x00, 0x00),
        (0xFF, 0xFF, 0xFF, 0xFF),
        (0x01, 0x02, 0x03, 0x04),
        (0xA5, 0x5A, 0x3C, 0xC3),
        (0x7F, 0x80, 0x00, 0xFF)
    ]
    var inputs: [[Float]] = []
    var expected: [[Float]] = []
    for s in enigma256NLFFSeedPatterns(generation: generation) {
        let mask = Enigma256LFSR(seed: s).stepMask(using: generation)
        let steps: [Bool] = [mask.0, mask.1, mask.2, mask.3]
        for offsets in offsetPatterns {
            var row = [Float]()
            row.reserveCapacity(96)
            for bit in 0 ..< 64 {
                row.append(Float((s >> bit) & 1))
            }
            let offs = [offsets.0, offsets.1, offsets.2, offsets.3]
            for o in offs {
                enigma256AppendByteBits(&row, o)
            }
            inputs.append(row)

            var out: [Float] = steps.map { $0 ? 1 : 0 }
            for (o, stepped) in zip(offs, steps) {
                let next = o &+ (stepped ? 1 : 0)
                enigma256AppendByteBits(&out, next)
            }
            enigma256AppendExtraOut(&out, seed: s, extra: extra)
            expected.append(out)
        }
    }
    return (inputs, expected)
}

/// Frozen Red stand-in bijections — must match `enigma_256_scramble_frag_combo.v`.
func enigma256FragRotL(_ x: UInt8, _ n: UInt8) -> UInt8 {
    let k = n % 8
    return (x &<< k) | (x &>> (8 - k))
}

func enigma256FragRotR(_ x: UInt8, _ n: UInt8) -> UInt8 {
    let k = n % 8
    return (x &>> k) | (x &<< (8 - k))
}

func enigma256FragSbox1(_ x: UInt8) -> UInt8 {
    let a = enigma256FragRotL(x, 3)
    let b = a &+ 0x3D
    return enigma256FragRotL(b, 1)
}

func enigma256FragSbox1Inv(_ x: UInt8) -> UInt8 {
    let a = enigma256FragRotR(x, 1)
    let b = a &- 0x3D
    return enigma256FragRotR(b, 3)
}

func enigma256FragSbox2(_ x: UInt8) -> UInt8 {
    let a = enigma256FragRotL(x, 5)
    let b = a ^ 0xA5
    return b &+ 0x11
}

func enigma256FragSbox2Inv(_ x: UInt8) -> UInt8 {
    let a = x &- 0x11
    let b = a ^ 0xA5
    return enigma256FragRotR(b, 5)
}

func enigma256FragSbox3(_ x: UInt8) -> UInt8 {
    let a = enigma256FragRotL(x, 2)
    let b = a ^ 0xC3
    return b &+ 0x27
}

func enigma256FragSbox3Inv(_ x: UInt8) -> UInt8 {
    let a = x &- 0x27
    let b = a ^ 0xC3
    return enigma256FragRotR(b, 2)
}

func enigma256FragSbox4(_ x: UInt8) -> UInt8 {
    let a = enigma256FragRotL(x, 7)
    let b = a &+ 0x6E
    return b ^ 0x39
}

func enigma256FragSbox4Inv(_ x: UInt8) -> UInt8 {
    let a = x ^ 0x39
    let b = a &- 0x6E
    return enigma256FragRotR(b, 7)
}

func enigma256FragUkw(_ x: UInt8) -> UInt8 {
    let swapped = (x &<< 4) | (x &>> 4)
    return swapped ^ 0x55
}

func enigma256FragStage(_ x: UInt8, offset: UInt8, sbox: (UInt8) -> UInt8) -> UInt8 {
    sbox(x &+ offset) &- offset
}

/// Full frozen reciprocal fragment (identity plug sandwich).
func enigma256ScrambleFrag(
    dataIn: UInt8,
    offsetR1: UInt8,
    offsetR2: UInt8,
    offsetR3: UInt8,
    offsetR4: UInt8
) -> UInt8 {
    let r1 = enigma256FragStage(dataIn, offset: offsetR1, sbox: enigma256FragSbox1)
    let r2 = enigma256FragStage(r1, offset: offsetR2, sbox: enigma256FragSbox2)
    let r3 = enigma256FragStage(r2, offset: offsetR3, sbox: enigma256FragSbox3)
    let r4 = enigma256FragStage(r3, offset: offsetR4, sbox: enigma256FragSbox4)
    let ref = enigma256FragUkw(r4)
    let r4r = enigma256FragStage(ref, offset: offsetR4, sbox: enigma256FragSbox4Inv)
    let r3r = enigma256FragStage(r4r, offset: offsetR3, sbox: enigma256FragSbox3Inv)
    let r2r = enigma256FragStage(r3r, offset: offsetR2, sbox: enigma256FragSbox2Inv)
    return enigma256FragStage(r2r, offset: offsetR1, sbox: enigma256FragSbox1Inv)
}

/// Past-offset cone: LFSR + data_in + offsets → frag_out + steps + next offsets + lfsr_next_hi.
func enigma256ScrambleFragTrainingBatch(
    generation: Enigma256Generation = .current,
    extra: Enigma256NLFFExtraOut = .none
) -> (inputs: [[Float]], expected: [[Float]]) {
    let offsetPatterns: [(UInt8, UInt8, UInt8, UInt8)] = [
        (0x00, 0x00, 0x00, 0x00),
        (0xFF, 0xFF, 0xFF, 0xFF),
        (0x01, 0x02, 0x03, 0x04),
        (0xA5, 0x5A, 0x3C, 0xC3)
    ]
    let dataPatterns: [UInt8] = [0x00, 0x01, 0x7F, 0x80, 0xA5, 0xFF]
    var inputs: [[Float]] = []
    var expected: [[Float]] = []
    let seeds = enigma256NLFFSeedPatterns(generation: generation)
    let step = max(1, seeds.count / 48)
    let thinSeeds = step == 1 ? seeds : Swift.stride(from: 0, to: seeds.count, by: step).map { seeds[$0] }
    for s in thinSeeds {
        let mask = Enigma256LFSR(seed: s).stepMask(using: generation)
        let steps: [Bool] = [mask.0, mask.1, mask.2, mask.3]
        for offsets in offsetPatterns {
            for dataIn in dataPatterns {
                var row = [Float]()
                row.reserveCapacity(104)
                for bit in 0 ..< 64 {
                    row.append(Float((s >> bit) & 1))
                }
                enigma256AppendByteBits(&row, dataIn)
                let offs = [offsets.0, offsets.1, offsets.2, offsets.3]
                for o in offs {
                    enigma256AppendByteBits(&row, o)
                }
                inputs.append(row)

                let frag = enigma256ScrambleFrag(
                    dataIn: dataIn,
                    offsetR1: offsets.0,
                    offsetR2: offsets.1,
                    offsetR3: offsets.2,
                    offsetR4: offsets.3
                )
                var out: [Float] = []
                enigma256AppendByteBits(&out, frag)
                out.append(contentsOf: steps.map { $0 ? Float(1) : 0 })
                for (o, stepped) in zip(offs, steps) {
                    enigma256AppendByteBits(&out, o &+ (stepped ? 1 : 0))
                }
                enigma256AppendExtraOut(&out, seed: s, extra: extra)
                expected.append(out)
            }
        }
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
    let polishLambda = Float(stringFlag("--enigma256-tensorlut-lambda").flatMap(Double.init) ?? 0)
    let exploreSeed = UInt64(intFlag("--enigma256-tensorlut-seed") ?? 0xE256_21)
    let expectHold = CommandLine.arguments.contains("--enigma256-tensorlut-expect-hold")
    let requireSqueeze = CommandLine.arguments.contains("--enigma256-tensorlut-require-squeeze")

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
        let hasScrambleFrag = module.ports["data_in"] != nil && module.ports["frag_out"] != nil
        let hasOffsetNext = module.ports["offset_r1"] != nil && module.ports["next_r1"] != nil
        if hasScrambleFrag {
            let dataNets = enigma256PortNets(module, "data_in")
            let offsetNets = enigma256PortNets(module, "offset_r1")
                + enigma256PortNets(module, "offset_r2")
                + enigma256PortNets(module, "offset_r3")
                + enigma256PortNets(module, "offset_r4")
            precondition(dataNets.count == 8 && offsetNets.count == 32)
            inputWires = lfsrNets + dataNets + offsetNets
            var outs = enigma256PortNets(module, "frag_out")
                + enigma256PortNets(module, "step_r1")
                + enigma256PortNets(module, "step_r2")
                + enigma256PortNets(module, "step_r3")
                + enigma256PortNets(module, "step_r4")
                + enigma256PortNets(module, "next_r1")
                + enigma256PortNets(module, "next_r2")
                + enigma256PortNets(module, "next_r3")
                + enigma256PortNets(module, "next_r4")
            let extra: Enigma256NLFFExtraOut
            if module.ports["lfsr_next_hi"] != nil {
                outs += enigma256PortNets(module, "lfsr_next_hi")
                extra = .nextHi
            } else {
                extra = .none
            }
            outputWires = outs
            let batch = enigma256ScrambleFragTrainingBatch(extra: extra)
            target = AdversarialTarget(
                inputWireIDs: inputWires,
                outputWireIDs: outputWires,
                inputVectors: batch.inputs,
                expectedOutputs: batch.expected,
                clockTicks: 0
            )
        } else if hasOffsetNext {
            let offsetNets = enigma256PortNets(module, "offset_r1")
                + enigma256PortNets(module, "offset_r2")
                + enigma256PortNets(module, "offset_r3")
                + enigma256PortNets(module, "offset_r4")
            precondition(offsetNets.count == 32)
            inputWires = lfsrNets + offsetNets
            var outs = enigma256PortNets(module, "step_r1")
                + enigma256PortNets(module, "step_r2")
                + enigma256PortNets(module, "step_r3")
                + enigma256PortNets(module, "step_r4")
                + enigma256PortNets(module, "next_r1")
                + enigma256PortNets(module, "next_r2")
                + enigma256PortNets(module, "next_r3")
                + enigma256PortNets(module, "next_r4")
            let extra: Enigma256NLFFExtraOut
            if module.ports["lfsr_next_hi"] != nil {
                outs += enigma256PortNets(module, "lfsr_next_hi")
                extra = .nextHi
            } else if module.ports["lfsr_next_lo"] != nil {
                outs += enigma256PortNets(module, "lfsr_next_lo")
                extra = .nextLo
            } else {
                extra = .none
            }
            outputWires = outs
            let batch = enigma256NLFFOffsetTrainingBatch(extra: extra)
            target = AdversarialTarget(
                inputWireIDs: inputWires,
                outputWireIDs: outputWires,
                inputVectors: batch.inputs,
                expectedOutputs: batch.expected,
                clockTicks: 0
            )
        } else {
            inputWires = lfsrNets
            var outs = enigma256PortNets(module, "step_r1")
                + enigma256PortNets(module, "step_r2")
                + enigma256PortNets(module, "step_r3")
                + enigma256PortNets(module, "step_r4")
            let extra: Enigma256NLFFExtraOut
            if module.ports["lfsr_next_hi"] != nil {
                outs += enigma256PortNets(module, "lfsr_next_hi")
                extra = .nextHi
            } else if module.ports["lfsr_next_lo"] != nil {
                outs += enigma256PortNets(module, "lfsr_next_lo")
                extra = .nextLo
            } else {
                extra = .none
            }
            outputWires = outs
            let batch = enigma256NLFFTrainingBatch(extra: extra)
            target = AdversarialTarget(
                inputWireIDs: inputWires,
                outputWireIDs: outputWires,
                inputVectors: batch.inputs,
                expectedOutputs: batch.expected,
                clockTicks: 0
            )
        }
    }

    let emitName: String
    switch moduleName {
    case "enigma_256_nlff_combo": emitName = "enigma_256_tensorlut_baseline"
    case "enigma_256_nlff_lfsr_combo": emitName = "enigma_256_nlff_lfsr_tensorlut"
    case "enigma_256_nlff_offset_combo": emitName = "enigma_256_nlff_offset_tensorlut"
    case "enigma_256_scramble_frag_combo": emitName = "enigma_256_scramble_frag_tensorlut"
    default: emitName = "enigma_256_step_cone_tensorlut"
    }
    let verilog = TensorLUTEmitter.emitVerilog(
        moduleName: emitName,
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
            rngSeed: exploreSeed,
            seedInits: wiped,
            crossoverRate: 0.7
        ),
        progress: { exploreLast = $0 }
    )

    // Phase B — binary polish. Default λ=0 (pad snap only). Optional λ via --enigma256-tensorlut-lambda.
    let polishSynth = try! AdversarialSynthesizer(
        device: device,
        config: .init(
            mutationRate: 0.1,
            maxNoise: 0.15,
            lambdaMax: polishLambda,
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
            rngSeed: exploreSeed &+ 1,
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
    polish_lambda: \(polishLambda)
    explore_seed: \(exploreSeed)
    baseline_crypto: \(baselineStats.map { String(format: "%.6f", $0.bestCrypto) } ?? "n/a")
    explore_best_crypto: \(exploreLast.map { String(format: "%.6f", $0.bestCrypto) } ?? "n/a")
    explore_nonbinary: \(exploreLast.map { String($0.bestNonBinaryCount) } ?? "n/a")
    polish_gen_crypto: \(polishLast.map { String(format: "%.6f", $0.bestCrypto) } ?? "n/a")
    final_crypto: \(String(format: "%.6f", finalCrypto))
    final_nonbinary: \(finalNonBinary)
    elite_fitness: \(String(format: "%.6f", polished.fitness))
    squeeze_survived: \(survived)
    verdict: \(verdict)
    note: explore λ=0; polish λ=\(polishLambda). squeeze_survived=false is a Blue hold.
    """

    try! FileManager.default.createDirectory(
        at: URL(fileURLWithPath: logPath).deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try! report.write(toFile: logPath, atomically: true, encoding: .utf8)
    print(report)
    print("  log → \(logPath)")
    if survived {
        fputs("RED pressure: squeeze recovered a binary elite\n", stderr)
        if expectHold { exit(2) }
        exit(0)
    } else {
        fputs("BLUE hold: squeeze failed (crypto \(finalCrypto), nb \(finalNonBinary))\n", stderr)
        if requireSqueeze { exit(1) }
        exit(0)
    }
}
