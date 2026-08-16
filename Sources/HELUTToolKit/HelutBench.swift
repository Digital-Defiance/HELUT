import Foundation
import Darwin
import Metal
import MetalPerformanceShadersGraph
import HELUTCore
import HELUTCLI
import HELUTCLI

// MARK: - Boolean-path HELUT bench (FHE/PBS datapath)

/// Release harness for trivial-encoding boolean-safe HELUT:
/// compile wall time, steady-state tick latency, optional Enigma Metal≡cleartext.
func runHelutBench() {
    if CommandLine.arguments.contains("--bench-encrypted") {
        runEncryptedNetlistBench()
        return
    }

    let path = resolveBenchNetlistPath()
    let degree = intFlag("--degree") ?? polynomialDegree
    let batch = intFlag("--batch") ?? 1
    let ticks = intFlag("--ticks", allowZero: true) ?? 10
    let warmup = intFlag("--warmup", allowZero: true) ?? 1
    let resetHold = intFlag("--reset-hold", allowZero: true) ?? 3
    let equiv = CommandLine.arguments.contains("--bench-equiv")
    let compileOnly = CommandLine.arguments.contains("--compile-only")
    let encodingKind = parseEncodingKindFlag()
    let lutBackend = parseLUTBackendFlag()

    if lutBackend.usesEncryptedNetlist {
        runEncryptedNetlistBench()
        return
    }

    let config = HELUTDatapathConfig(
        encodingDegree: degree,
        encodingKind: encodingKind,
        lutBackend: lutBackend
    )
    // Fail closed early for --lut-backend pbs
    config.assertRunnable()

    guard let device = MTLCreateSystemDefaultDevice() else {
        fputs("No Metal device\n", stderr)
        exit(1)
    }
    guard let commandQueue = device.makeCommandQueue() else {
        fputs("No MTLCommandQueue\n", stderr)
        exit(1)
    }

    print("HELUT boolean-path bench")
    print("  netlist: \(path)")
    print("  N=\(degree)  B=\(batch)  ticks=\(ticks)  warmup=\(warmup)  reset_hold=\(resetHold)")
    print("  encoding: \(encodingKind.rawValue) (trivial, noise-free)")
    print("  LUT backend: \(lutBackend.rawValue)")
    if encodingKind.isPackedGLWE {
        print("  wire width: \(encodingKind.wireWidth(polynomialDegree: degree)) (packed k=1)")
    }
    print("")

    let netlist = loadYosysNetlist(from: path)
    guard let (moduleName, module) = netlist.modules.first else {
        fatalError("Empty netlist")
    }

    let rssBefore = taskResidentMemoryBytes()
    let compiler = YosysGraphCompiler(
        degree: degree,
        batch: batch,
        encodingKind: encodingKind,
        lutBackend: lutBackend
    )
    let compileStarted = CFAbsoluteTimeGetCurrent()
    compiler.compile(moduleName: moduleName, module: module)
    let compileSeconds = CFAbsoluteTimeGetCurrent() - compileStarted
    let rssAfterCompile = taskResidentMemoryBytes()

    print(String(format: "COMPILE"))
    print(String(format: "  total            %.4f s", compileSeconds))
    print(String(format: "  LUT lower        %.4f s", compiler.lastToeplitzExpandSeconds))
    print(String(format: "  graph build      %.4f s", compiler.lastGraphBuildSeconds))
    print(
        "  cells            \(compiler.lutNodes.count) LUTs, "
            + "\(compiler.dffNodes.count) DFFs, "
            + "\(compiler.inputNodes.count) inputs, "
            + "\(compiler.outputTensors.count) outputs"
    )
    print(
        String(
            format: "  RSS delta        %+.1f MiB (after=%.1f MiB)",
            Double(Int64(rssAfterCompile) &- Int64(rssBefore)) / (1024 * 1024),
            Double(rssAfterCompile) / (1024 * 1024)
        )
    )
    print("")

    if compileOnly {
        print("Stopping after compile (--compile-only).")
        return
    }

    if compiler.dffNodes.isEmpty {
        print("Combinational netlist — no clock loop.")
        if equiv {
            runCombinationalEquivGate(
                compiler: compiler,
                moduleName: moduleName,
                module: module,
                device: device,
                commandQueue: commandQueue
            )
        }
    } else if ticks > 0 {
        let tickTimes = runScriptedClock(
            compiler: compiler,
            module: module,
            device: device,
            commandQueue: commandQueue,
            ticks: ticks,
            warmup: warmup,
            resetHold: resetHold
        )

        let steady = Array(tickTimes.dropFirst(max(0, warmup)))
        let steadySum = steady.reduce(0, +)
        let steadyAvg = steady.isEmpty ? 0 : steadySum / Double(steady.count)
        let allSum = tickTimes.reduce(0, +)

        print("CLOCK")
        print(String(format: "  ticks total      %.4f s (%d ticks)", allSum, tickTimes.count))
        if let first = tickTimes.first {
            print(String(format: "  tick 1 (JIT)     %.4f s", first))
        }
        print(String(format: "  steady avg       %.4f s/tick (n=%d, skip warmup=%d)", steadyAvg, steady.count, warmup))
        if steadyAvg > 0 {
            print(String(format: "  steady Hz        %.2f", 1.0 / steadyAvg))
        }
        print("")
    }

    if equiv {
        if compiler.dffNodes.isEmpty {
            // Already handled above when combinational.
        } else {
            runEnigmaEquivGate(
                path: path,
                degree: degree,
                encodingKind: encodingKind,
                lutBackend: lutBackend,
                device: device,
                commandQueue: commandQueue
            )
        }
    }

    let rssFinal = taskResidentMemoryBytes()
    print(
        String(
            format: "RSS final %.1f MiB (delta from start %+.1f MiB)",
            Double(rssFinal) / (1024 * 1024),
            Double(Int64(rssFinal) &- Int64(rssBefore)) / (1024 * 1024)
        )
    )
}

/// Encrypted packed/GLWE netlist: GGSW PBS / blind-rotate per `$lut`.
private func runEncryptedNetlistBench() {
    setbuf(stdout, nil)
    let path = resolveBenchNetlistPath()
    let degree = intFlag("--degree") ?? 8
    let sing = CommandLine.arguments.contains("--sing")
        || CommandLine.arguments.contains("--bench-encrypted-metrics")
    let cpuOnly = CommandLine.arguments.contains("--cpu-only")
        || CommandLine.arguments.contains("--skip-metal")
    let metalNetlistOnly = CommandLine.arguments.contains("--metal-netlist-only")
    let maxVectors = intFlag("--vectors") ?? 256
    let encryptedTicks = intFlag("--ticks")
    let resetHold = intFlag("--reset-hold", allowZero: true)
    let encryptedMem = stringFlag("--encrypted-mem")
    let booleanScaleMul = intFlag("--boolean-scale-mul") ?? 1
    let lweDimension = intFlag("--lwe-dimension")
    let pathFilter = stringFlag("--paths") // comma list substring match; nil = all
    let bkNoise: TFHENoiseParams = {
        if let sigma = doubleFlag("--bk-noise-sigma"), sigma > 0 {
            return .gaussian(sigma: sigma)
        }
        let bound = intFlag("--bk-noise", allowZero: true) ?? 0
        return TFHENoiseParams(bound: UInt32(bound))
    }()
    let netlist = loadYosysNetlist(from: path)
    guard let (moduleName, module) = netlist.modules.first else {
        fatalError("Empty netlist")
    }
    let clear = CleartextNetlistSimulator(moduleName: moduleName, module: module)
    let sequential = !clear.dffs.isEmpty
    if sequential && metalNetlistOnly {
        fatalError("--metal-netlist-only is combinational-only; sequential netlists use per-LUT BR")
    }

    let bootTicks = sequential ? encryptedTicks : nil
    let memKind = encryptedMem
    let hostMemActive = memKind == "nop" || memKind == "prog"
    if hostMemActive {
        precondition(sequential && clear.inputPorts["resetn"] != nil, "--encrypted-mem needs sequential resetn")
        precondition(clear.inputPorts["mem_ready"] != nil && clear.inputPorts["mem_rdata"] != nil, "--encrypted-mem needs mem_ready/mem_rdata")
        precondition(clear.outputPorts["mem_valid"] != nil && clear.outputPorts["mem_addr"] != nil, "--encrypted-mem needs mem_valid/mem_addr")
        if memKind == "prog" {
            precondition(clear.outputPorts["mem_wstrb"] != nil && clear.outputPorts["mem_wdata"] != nil, "--encrypted-mem prog needs mem_wstrb/mem_wdata")
        }
    }
    if let memKind, memKind != "nop", memKind != "prog" {
        fatalError("--encrypted-mem must be nop or prog")
    }
    let stimuli: [[String: [UInt8]]]
    if hostMemActive {
        // Reactive ROM fills rows inside runAll; placeholder length = tick count.
        let ticks = bootTicks ?? (memKind == "prog" ? 48 : 24)
        stimuli = Array(repeating: [:], count: ticks)
    } else if let bootTicks, bootTicks > 0, clear.inputPorts["resetn"] != nil {
        let hold = resetHold ?? 3
        stimuli = makeEncryptedResetHoldStimuli(clear: clear, ticks: bootTicks, resetHold: hold)
    } else {
        stimuli = makeEncryptedStimuli(clear: clear, maxVectors: maxVectors, seed: 0x51A1)
    }
    precondition(!stimuli.isEmpty, "no encrypted stimuli")

    let twoN = 2 * degree
    let muxCost = MetalGGSW.DynamicRotateCost.muxRotates(twoN: twoN, lweDimension: degree)
    let binCost: Int
    if twoN > 1 && twoN.nonzeroBitCount == 1 {
        binCost = MetalGGSW.DynamicRotateCost.binaryRotates(twoN: twoN, lweDimension: degree)
    } else {
        binCost = -1
    }

    print("HELUT encrypted-netlist bench\(sing ? " · SING" : "")")
    print("  netlist: \(path)  module=\(moduleName)")
    print("  poly N=\(degree)  LUTs=\(clear.luts.count)  DFFs=\(clear.dffs.count)\(sequential ? "  sequential" : "")  2N=\(twoN)")
    print("  stimuli=\(stimuli.count) (max --vectors \(maxVectors))  cpu-only=\(cpuOnly)  metal-netlist-only=\(metalNetlistOnly)")
    if memKind == "nop" {
        print("  encrypted mem: nop ROM (addi x0,x0,0 = 0x00000013)  ticks=\(stimuli.count)  reset-hold=\(resetHold ?? 3)")
    } else if memKind == "prog" {
        print("  encrypted mem: tiny ROM addi; sw; lw x2,0(x0)  ticks=\(stimuli.count)  reset-hold=\(resetHold ?? 3)")
    } else if encryptedTicks != nil, sequential, clear.inputPorts["resetn"] != nil {
        print("  scripted boot: ticks=\(stimuli.count)  reset-hold=\(resetHold ?? 3) (resetn=0 then 1; other inputs 0 including clk)")
    }
    if let pathFilter {
        print("  paths filter: \(pathFilter)")
    }
    print("  paths: public-ms@boolean + public-ms@crypto + secret@crypto\(cpuOnly || metalNetlistOnly ? "" : " (+ Metal)")")
    if bkNoise.usesGaussian {
        print("  BK noise inject Gaussian σ=\(bkNoise.gaussianSigma) (torus; measured identity residual → B_bk)")
    } else if bkNoise.bound > 0 {
        print("  BK noise inject B=\(bkNoise.bound) (measured identity residual → B_bk)")
    }
    if booleanScaleMul > 1 {
        print("  boolean scale kδ  k=\(booleanScaleMul)  (test-poly stride \(booleanScaleMul); public-MS native δ)")
    }
    if let lweDimension {
        print("  LWE n=\(lweDimension)  (CMUX count; extract→KS when n<kN=\(degree))")
    }
    if binCost >= 0 {
        print("  DynamicRotateCost mux=\(muxCost) binary=\(binCost) speedup≈\(String(format: "%.1f", Double(muxCost) / Double(max(binCost, 1))))×")
    }
    print("")

    let tileWidthFlag = intFlag("--metal-br-tile")
    let tileWidth = tileWidthFlag ?? MetalBRControl.defaultTileWidth
    MetalBRControl.defaultTileWidth = tileWidth
    if CommandLine.arguments.contains("--metal-br-fused") {
        MetalBRControl.overrideLowering = .fused
    } else if tileWidthFlag != nil {
        MetalBRControl.overrideLowering = .tiledKernel
    } else {
        MetalBRControl.overrideLowering = nil
    }
    MetalBRControl.progress = { line in
        print(line)
        fflush(stdout)
    }

    struct EncryptedMetric {
        var label: String
        var rows: Int
        var seconds: Double
        var msPerRow: Double
        var classicalBits: Double
        var failureLog2: Double
        var noisyBKBound: UInt32
        var meets128: Bool
    }
    var metrics: [EncryptedMetric] = []

    func wantPath(_ label: String) -> Bool {
        if sequential && (label.contains("cpu-ggsw") || label.contains("metal-netlist")) {
            return false
        }
        if metalNetlistOnly {
            return label.contains("metal-netlist")
        }
        guard let pathFilter else {
            // Fused whole-netlist graph hangs at N≳256 unless tiled-kernel lowering
            // (evaluateTopoNetlistTiledKernel). Still opt-in via --metal-netlist-only.
            return !label.contains("metal-netlist")
        }
        return pathFilter.split(separator: ",").contains { raw in
            let token = raw.trimmingCharacters(in: .whitespaces)
            if token.isEmpty { return false }
            if token == "blind-rotate-metal" || label.contains("metal-netlist") {
                // Do not let "blind-rotate-metal" substring-match the netlist path.
                if token == "blind-rotate-metal" {
                    return label.contains("blind-rotate-metal") && !label.contains("netlist")
                }
            }
            return label.contains(token)
        }
    }

    func runAll(
        label: String,
        params raw: GGSWParams,
        backend: EncryptedLUTBackend,
        wireRefresh: EncryptedWireRefresh,
        seed: UInt32,
        device: MTLDevice?,
        queue: MTLCommandQueue?
    ) throws {
        guard wantPath(label) else { return }
        let params = lweDimension.map { raw.withLWEDimension($0) } ?? raw
        print("  starting \(label)\(lweDimension.map { "  n=\($0)" } ?? "")")
        fflush(stdout)
        clear.resetState()
        let secret = TFHESecretKey.random(params: params.tfhe, seed: seed)
        let enc = EncryptedNetlistSimulator(
            moduleName: moduleName,
            module: module,
            secret: secret,
            params: params,
            backend: backend,
            wireRefresh: wireRefresh,
            bkNoise: bkNoise,
            seed: seed &+ 0x100,
            device: device,
            commandQueue: queue,
            booleanScaleMul: booleanScaleMul
        )
        var rows = 0
        var lastOutputs: [String: [UInt8]]?
        var hostMem = PicoRVHostMem()
        let hold = resetHold ?? 3
        let started = CFAbsoluteTimeGetCurrent()
        for tickIndex in 0..<stimuli.count {
            let inputs: [String: [UInt8]]
            if let memKind, hostMemActive {
                inputs = makePicoRVHostMemInputs(
                    clear: clear,
                    tick: tickIndex + 1,
                    resetHold: hold,
                    lastOutputs: lastOutputs,
                    kind: memKind,
                    host: &hostMem
                )
            } else {
                inputs = stimuli[tickIndex]
            }
            let want = clear.tick(inputs: inputs)
            let got = try enc.tick(inputs: inputs)
            for (port, bits) in want {
                guard let gotBits = got[port], gotBits == bits else {
                    fatalError(
                        "\(port) mismatch \(label) tick \(rows + 1): want=\(bits) got=\(got[port] ?? [])"
                    )
                }
            }
            if sequential {
                let encQ = enc.decryptedRegisterBits()
                for dff in clear.dffs {
                    let wantQ = clear.state[dff.qWire] ?? 0
                    let gotQ = encQ[dff.qWire] ?? 255
                    if wantQ != gotQ {
                        fatalError(
                            "DFF \(dff.name) \(dff.type) mismatch \(label) tick \(rows + 1): want=\(wantQ) got=\(gotQ)"
                        )
                    }
                }
            }
            if hostMemActive {
                let valid = (want["mem_valid"] ?? [0]).first ?? 0
                let ready = (inputs["mem_ready"] ?? [0]).first ?? 0
                let addr = unpackHostLE(want["mem_addr"] ?? [])
                let instr = (want["mem_instr"] ?? [0]).first ?? 0
                let wstrb = unpackHostLE(want["mem_wstrb"] ?? [])
                let wdata = unpackHostLE(want["mem_wdata"] ?? [])
                if valid == 1 && ready == 1 {
                    if instr == 1 {
                        hostMem.noteFetch(tick: rows + 1, addr: addr)
                        print(String(format: "  FETCH tick %2d  addr=0x%08x  instr=1", rows + 1, addr))
                    } else if wstrb == 0 {
                        let rdata = unpackHostLE(inputs["mem_rdata"] ?? [])
                        hostMem.noteLoad(tick: rows + 1, addr: addr, rdata: rdata)
                        print(String(format: "  LOAD  tick %2d  addr=0x%08x  rdata=0x%08x", rows + 1, addr, rdata))
                    }
                    if wstrb != 0 {
                        hostMem.noteStore(tick: rows + 1, addr: addr, wstrb: UInt8(wstrb & 0xf), wdata: wdata)
                        print(String(format: "  STORE tick %2d  addr=0x%08x  wstrb=0x%x  wdata=0x%08x", rows + 1, addr, wstrb, wdata))
                    }
                } else if rows < 12 || valid == 1 {
                    print(String(format: "  mem tick %2d  valid=%d ready=%d addr=0x%08x instr=%d wstrb=0x%x", rows + 1, valid, ready, addr, instr, wstrb))
                }
                hostMem.afterTick(valid: valid, ready: ready, instr: instr, addr: addr)
            }
            lastOutputs = want
            rows += 1
        }
        if hostMemActive {
            let addrs = hostMem.fetches.map { $0.addr }
            let unique = Set(addrs)
            let addrList = addrs.map { String(format: "0x%x", $0) }.joined(separator: ",")
            print("  FETCH summary  served=\(hostMem.fetches.count)  unique_addr=\(unique.count)  addrs=\(addrList)")
            if hostMem.fetches.count < 2 || unique.count < 2 {
                fatalError("fetch did not advance PC (served=\(hostMem.fetches.count) unique=\(unique.count)) \(label)")
            }
            if memKind == "prog" {
                let wdata1 = hostMem.stores.contains { $0.wstrb != 0 && ($0.wdata & 0xff) == 1 }
                print("  STORE summary  count=\(hostMem.stores.count)  wdata1=\(wdata1)  ram0=\(hostMem.ram[0] ?? 0)")
                if !wdata1 {
                    fatalError("tiny program did not store 1 (stores=\(hostMem.stores.count)) \(label)")
                }
                let load1 = hostMem.loadXfers.contains { $0.rdata == 1 }
                print("  LOAD  summary  count=\(hostMem.loads.count)  xfers=\(hostMem.loadXfers.count)  rdata1=\(load1)")
                if !load1 {
                    fatalError("tiny program did not load 1 (xfers=\(hostMem.loadXfers)) \(label)")
                }
            }
        }
        let seconds = CFAbsoluteTimeGetCurrent() - started
        let hard = enc.hardnessCertificate ?? enc.issueHardnessCertificate()
        let asym = enc.asymptoticCertificate ?? enc.issueAsymptoticCertificate()
        let bk = enc.noisyBKCertificate ?? enc.issueNoisyBKCertificate()
        let msPer = seconds * 1000.0 / Double(max(rows, 1))
        metrics.append(
            EncryptedMetric(
                label: label,
                rows: rows,
                seconds: seconds,
                msPerRow: msPer,
                classicalBits: hard.estimatedClassicalBits,
                failureLog2: asym.failureLog2,
                noisyBKBound: bk.params.outputNoiseBound,
                meets128: hard.meetsTarget
            )
        )
        let epsLabel: String
        if asym.failureLog2.isInfinite && asym.failureLog2 < 0 {
            epsLabel = "-inf"
        } else {
            epsLabel = String(format: "%.1f", asym.failureLog2)
        }
        print("ENCRYPTED EQUIV (\(label))")
        print("  rows            \(rows)")
        print(String(format: "  wall            %.4f s  (%.2f ms/row)", seconds, msPer))
        print(String(format: "  classical bits  %.1f  (≥128? %@)", hard.estimatedClassicalBits, hard.meetsTarget ? "yes" : "no"))
        print("  ingest ε log2   \(epsLabel)  (target \(asym.params.targetFailureLog2))")
        print("  noisy BK B_bk   \(bk.params.outputNoiseBound)  (decodable \(bk.eachLUTDecodable))")
        print("  result          PASS")
        print("")
    }

    do {
        try runAll(
            label: "blind-rotate public-ms boolean",
            params: .booleanPublicMS(degree: degree),
            backend: .blindRotate,
            wireRefresh: .publicMS,
            seed: 0xE11C,
            device: nil,
            queue: nil
        )
        try runAll(
            label: "blind-rotate public-ms crypto",
            params: .cryptoPublicMS(degree: degree),
            backend: .blindRotate,
            wireRefresh: .publicMS,
            seed: 0xE120,
            device: nil,
            queue: nil
        )
        try runAll(
            label: "blind-rotate secret crypto",
            params: .crypto(degree: degree),
            backend: .blindRotate,
            wireRefresh: .secret,
            seed: 0xE11D,
            device: nil,
            queue: nil
        )
        try runAll(
            label: "cpu-ggsw secret crypto",
            params: .crypto(degree: degree),
            backend: .cpuGGSW,
            wireRefresh: .secret,
            seed: 0xE11E,
            device: nil,
            queue: nil
        )
        if cpuOnly {
            // Covering gadgets were Metal-only; CPU path is the E2 1k-barrier lever.
            try runAll(
                label: "blind-rotate secret covering-b4",
                params: .covering(degree: degree, baseLog: 4),
                backend: .blindRotate,
                wireRefresh: .secret,
                seed: 0xE142,
                device: nil,
                queue: nil
            )
            try runAll(
                label: "blind-rotate public-ms covering-b4",
                params: .covering(degree: degree, baseLog: 4),
                backend: .blindRotate,
                wireRefresh: .publicMS,
                seed: 0xE143,
                device: nil,
                queue: nil
            )
            try runAll(
                label: "blind-rotate secret covering-b2",
                params: .covering(degree: degree, baseLog: 2),
                backend: .blindRotate,
                wireRefresh: .secret,
                seed: 0xE144,
                device: nil,
                queue: nil
            )
            try runAll(
                label: "blind-rotate public-ms covering-b2",
                params: .covering(degree: degree, baseLog: 2),
                backend: .blindRotate,
                wireRefresh: .publicMS,
                seed: 0xE145,
                device: nil,
                queue: nil
            )
            try runAll(
                label: "blind-rotate secret covering-b1",
                params: .covering(degree: degree, baseLog: 1),
                backend: .blindRotate,
                wireRefresh: .secret,
                seed: 0xE146,
                device: nil,
                queue: nil
            )
            try runAll(
                label: "blind-rotate public-ms covering-b1",
                params: .covering(degree: degree, baseLog: 1),
                backend: .blindRotate,
                wireRefresh: .publicMS,
                seed: 0xE147,
                device: nil,
                queue: nil
            )
            print("ENCRYPTED EQUIV (metal)")
            print("  result          SKIP (--cpu-only)")
            print("")
        } else if let device = MTLCreateSystemDefaultDevice(),
                  let queue = device.makeCommandQueue() {
            if !metalNetlistOnly {
                try runAll(
                    label: "blind-rotate-metal public-ms boolean",
                    params: .booleanPublicMS(degree: degree),
                    backend: .blindRotateMetal,
                    wireRefresh: .publicMS,
                    seed: 0xE122,
                    device: device,
                    queue: queue
                )
                try runAll(
                    label: "blind-rotate-metal public-ms crypto",
                    params: .cryptoPublicMS(degree: degree),
                    backend: .blindRotateMetal,
                    wireRefresh: .publicMS,
                    seed: 0xE11F,
                    device: device,
                    queue: queue
                )
                // Track A approx candidate (**C31**/**C32**): covering `.crypto` (g₀≠δ).
                // Distinct from public-ms cryptoPublicMS so C21 reproduce filters stay stable.
                try runAll(
                    label: "blind-rotate-metal secret crypto",
                    params: .crypto(degree: degree),
                    backend: .blindRotateMetal,
                    wireRefresh: .secret,
                    seed: 0xE130,
                    device: device,
                    queue: queue
                )
                try runAll(
                    label: "blind-rotate-metal public-ms covering-crypto",
                    params: .crypto(degree: degree),
                    backend: .blindRotateMetal,
                    wireRefresh: .publicMS,
                    seed: 0xE131,
                    device: device,
                    queue: queue
                )
                // Finer covering (baseLog=4/2): EP β↓ ⇒ BK-noise amp↓ (H4 toward ε≤2^{-64}).
                try runAll(
                    label: "blind-rotate-metal secret covering-b4",
                    params: .covering(degree: degree, baseLog: 4),
                    backend: .blindRotateMetal,
                    wireRefresh: .secret,
                    seed: 0xE132,
                    device: device,
                    queue: queue
                )
                try runAll(
                    label: "blind-rotate-metal public-ms covering-b4",
                    params: .covering(degree: degree, baseLog: 4),
                    backend: .blindRotateMetal,
                    wireRefresh: .publicMS,
                    seed: 0xE133,
                    device: device,
                    queue: queue
                )
                try runAll(
                    label: "blind-rotate-metal secret covering-b2",
                    params: .covering(degree: degree, baseLog: 2),
                    backend: .blindRotateMetal,
                    wireRefresh: .secret,
                    seed: 0xE134,
                    device: device,
                    queue: queue
                )
                try runAll(
                    label: "blind-rotate-metal public-ms covering-b2",
                    params: .covering(degree: degree, baseLog: 2),
                    backend: .blindRotateMetal,
                    wireRefresh: .publicMS,
                    seed: 0xE135,
                    device: device,
                    queue: queue
                )
                // Finest covering (baseLog=1): EP β=2 — H4 push toward torus-scale B~128.
                try runAll(
                    label: "blind-rotate-metal secret covering-b1",
                    params: .covering(degree: degree, baseLog: 1),
                    backend: .blindRotateMetal,
                    wireRefresh: .secret,
                    seed: 0xE136,
                    device: device,
                    queue: queue
                )
                try runAll(
                    label: "blind-rotate-metal public-ms covering-b1",
                    params: .covering(degree: degree, baseLog: 1),
                    backend: .blindRotateMetal,
                    wireRefresh: .publicMS,
                    seed: 0xE137,
                    device: device,
                    queue: queue
                )
            }
            if metalNetlistOnly {
                try runAll(
                    label: "blind-rotate-metal-netlist public-ms boolean",
                    params: .booleanPublicMS(degree: degree),
                    backend: .blindRotateMetalNetlist,
                    wireRefresh: .publicMS,
                    seed: 0xE121,
                    device: device,
                    queue: queue
                )
            }
        } else {
            print("ENCRYPTED EQUIV (blind-rotate-metal)")
            print("  result          SKIP (no Metal)")
            print("")
        }
    } catch {
        fputs("encrypted bench failed: \(error)\n", stderr)
        exit(1)
    }

    if sing && !metrics.isEmpty {
        print("════════ SING METRICS SUMMARY ════════")
        print("path                                             ms/row       bits    εlog2     B_bk")
        for m in metrics {
            let eps: String
            if m.failureLog2.isInfinite && m.failureLog2 < 0 {
                eps = "-inf"
            } else {
                eps = String(format: "%.1f", m.failureLog2)
            }
            let pathPad = m.label.padding(toLength: 48, withPad: " ", startingAt: 0)
            let ms = String(format: "%8.2f", m.msPerRow)
            let bits = String(format: "%10.1f", m.classicalBits)
            let epsPad = eps.padding(toLength: 8, withPad: " ", startingAt: 0)
            let bk = String(format: "%8d", m.noisyBKBound)
            print("\(pathPad) \(ms) \(bits) \(epsPad) \(bk)")
        }
        print("calibration:\n\(TFHELWECalibration.markdownTable())")
        print("core-SVP model (sage-free):\n\(TFHELWECoreSVPModel.markdownTable())")
        print("estimator protocol:\n\(TFHELWEEstimatorProtocol.markdownTable(TFHELWEEstimatorProtocol.mergedFromResultsFile()))")
        print("══════════════════════════════════════")
    }
}

/// Host-clocked sequential boot: `resetn=0` for `resetHold` ticks, then `1`.
/// Other ports zero; `clk` is the host tick, not a torus wire.
private func makeEncryptedResetHoldStimuli(
    clear: CleartextNetlistSimulator,
    ticks: Int,
    resetHold: Int
) -> [[String: [UInt8]]] {
    precondition(ticks > 0)
    let hold = max(0, resetHold)
    let ports = clear.inputPorts.keys.sorted()
    return (1...ticks).map { tick in
        var row: [String: [UInt8]] = [:]
        for p in ports {
            let width = clear.inputPorts[p]!.count
            var bits = [UInt8](repeating: 0, count: width)
            if p == "clk" {
                bits = [UInt8](repeating: 0, count: width)
            } else if p == "resetn" {
                let live: UInt8 = tick <= hold ? 0 : 1
                bits = [UInt8](repeating: live, count: width)
            }
            row[p] = bits
        }
        return row
    }
}

private func makeEncryptedStimuli(
    clear: CleartextNetlistSimulator,
    maxVectors: Int,
    seed: UInt32
) -> [[String: [UInt8]]] {
    let ports = clear.inputPorts.keys.sorted()
    precondition(!ports.isEmpty)
    var widths: [String: Int] = [:]
    var totalBits = 0
    for p in ports {
        let w = clear.inputPorts[p]!.count
        widths[p] = w
        totalBits += w
    }
    func decode(_ mask: UInt64) -> [String: [UInt8]] {
        var remaining = mask
        var out: [String: [UInt8]] = [:]
        for p in ports {
            let w = widths[p]!
            var bits = [UInt8](repeating: 0, count: w)
            for i in 0..<w {
                bits[i] = UInt8(remaining & 1)
                remaining >>= 1
            }
            out[p] = bits
        }
        return out
    }
    let space = totalBits >= 63 ? UInt64.max : (UInt64(1) << UInt64(totalBits))
    if totalBits <= 12 && space <= UInt64(maxVectors) {
        return (0..<Int(space)).map { decode(UInt64($0)) }
    }
    var rng = LCG32(state: seed == 0 ? 1 : seed)
    var seen = Set<UInt64>()
    var rows: [[String: [UInt8]]] = []
    rows.reserveCapacity(maxVectors)
    // Always include all-zero; include all-one when room remains.
    let onesMask = totalBits >= 63 ? UInt64.max : (space &- 1)
    for fixed in [UInt64(0), onesMask] where rows.count < maxVectors {
        if seen.insert(fixed).inserted {
            rows.append(decode(fixed))
        }
    }
    while rows.count < maxVectors {
        let raw = (UInt64(rng.next()) << 32) | UInt64(rng.next())
        let mask = totalBits >= 63 ? raw : (raw & onesMask)
        if seen.insert(mask).inserted {
            rows.append(decode(mask))
        }
    }
    return rows
}

private func parseEncodingKindFlag() -> TrivialBitEncodingKind {
    guard let raw = stringFlag("--encoding") else { return .constantFill }
    guard let kind = TrivialBitEncodingKind(rawValue: raw) else {
        fputs("Unknown --encoding \(raw) (use constant-fill|phase|glwe-trivial|glwe-packed)\n", stderr)
        exit(1)
    }
    return kind
}

private func parseLUTBackendFlag() -> LUTEvaluationBackend {
    guard let raw = stringFlag("--lut-backend") else { return .multilinear }
    if raw == "pbs" || raw == "programmableBootstrap" {
        return .programmableBootstrap
    }
    if raw == "encrypted" || raw == "blind-rotate" {
        return .encryptedBlindRotate
    }
    guard let backend = LUTEvaluationBackend(rawValue: raw) else {
        fputs("Unknown --lut-backend \(raw) (use multilinear|pbs|pbs-ggsw|encrypted)\n", stderr)
        exit(1)
    }
    return backend
}

private func packEncodedBits(bit: UInt32, encoding: any TorusBitEncoding, batch: Int) -> [UInt32] {
    let lane = encoding.encodeBit(bit)
    var values: [UInt32] = []
    values.reserveCapacity(batch * encoding.degree)
    for _ in 0..<batch {
        values.append(contentsOf: lane)
    }
    return values
}

// MARK: - Clock

private func runScriptedClock(
    compiler: YosysGraphCompiler,
    module: YosysModule,
    device: MTLDevice,
    commandQueue: MTLCommandQueue,
    ticks: Int,
    warmup: Int,
    resetHold: Int
) -> [Double] {
    _ = module
    _ = warmup
    let degree = compiler.degree
    let batch = compiler.batch
    let encoding = compiler.bitEncoding
    let elementCount = batch * degree
    let vectorShape: [NSNumber] = [NSNumber(value: batch), NSNumber(value: degree)]
    let zeroHost = packEncodedBits(bit: 0, encoding: encoding, batch: batch)
    let oneHost = packEncodedBits(bit: 1, encoding: encoding, batch: batch)

    var primaryFeeds: [MPSGraphTensor: MPSGraphTensorData] = [:]
    var resetnBuffer: MTLBuffer?
    for entry in compiler.inputNodes {
        guard let placeholder = entry.node.placeholder else {
            fatalError("Missing placeholder \(entry.port)")
        }
        let values: [UInt32]
        switch entry.port {
        case "en":
            values = oneHost
        case "resetn":
            values = zeroHost // start in reset; raised after resetHold
        default:
            values = zeroHost
        }
        let buffer = makeSharedUInt32Buffer(device: device, values: values)
        if entry.port == "resetn" {
            resetnBuffer = buffer
        }
        primaryFeeds[placeholder] = MPSGraphTensorData(buffer, shape: vectorShape, dataType: .uInt32)
    }

    let stateBuffersA: [MTLBuffer] = compiler.dffNodes.map { _ in
        makeSharedUInt32Buffer(device: device, values: zeroHost)
    }
    let stateSetA: [MPSGraphTensorData] = stateBuffersA.map {
        MPSGraphTensorData($0, shape: vectorShape, dataType: .uInt32)
    }
    let stateBuffersB: [MTLBuffer] = compiler.dffNodes.map { _ in
        makeSharedUInt32Buffer(device: device, count: elementCount)
    }
    let stateSetB: [MPSGraphTensorData] = stateBuffersB.map {
        MPSGraphTensorData($0, shape: vectorShape, dataType: .uInt32)
    }
    let outputScratch: [MPSGraphTensorData] = compiler.outputTensors.map { _ in
        let buffer = makeSharedUInt32Buffer(device: device, count: elementCount)
        return MPSGraphTensorData(buffer, shape: vectorShape, dataType: .uInt32)
    }

    var stateFeeds = stateSetA
    var writeToB = true
    var times: [Double] = []
    times.reserveCapacity(ticks)

    for tick in 1...ticks {
        let elapsed: Double = autoreleasepool {
            if let resetnBuffer {
                let host = tick <= resetHold ? zeroHost : oneHost
                host.withUnsafeBytes { raw in
                    guard let base = raw.baseAddress else { return }
                    resetnBuffer.contents().copyMemory(from: base, byteCount: raw.count)
                }
            }

            let stateWrites = writeToB ? stateSetB : stateSetA
            var feeds = primaryFeeds
            for (index, dff) in compiler.dffNodes.enumerated() {
                guard let placeholder = dff.stateInput.placeholder else {
                    fatalError("Missing state placeholder")
                }
                feeds[placeholder] = stateFeeds[index]
            }

            var results: [MPSGraphTensor: MPSGraphTensorData] = [:]
            for (outIndex, entry) in compiler.outputTensors.enumerated() {
                _ = entry
                results[compiler.outputTensors[outIndex].tensor] = outputScratch[outIndex]
            }
            for (index, dff) in compiler.dffNodes.enumerated() {
                guard let stateOutput = dff.stateOutput else {
                    fatalError("Missing state output")
                }
                results[stateOutput] = stateWrites[index]
            }

            let started = CFAbsoluteTimeGetCurrent()
            compiler.graph.run(
                with: commandQueue,
                feeds: feeds,
                targetOperations: nil,
                resultsDictionary: results
            )
            let dt = CFAbsoluteTimeGetCurrent() - started
            stateFeeds = stateWrites
            writeToB.toggle()
            return dt
        }
        times.append(elapsed)
        print(String(format: "  tick %2d  %.4f s  resetn=%d", tick, elapsed, tick <= resetHold ? 0 : 1))
    }
    return times
}

// MARK: - Enigma Metal ≡ cleartext

private func runCombinationalEquivGate(
    compiler: YosysGraphCompiler,
    moduleName: String,
    module: YosysModule,
    device: MTLDevice,
    commandQueue: MTLCommandQueue
) {
    print("EQUIV (Metal PBS/multilinear ≡ CleartextNetlistSim, combinational)")
    print("  encoding: \(compiler.encodingKind.rawValue)")
    print("  LUT backend: \(compiler.lutBackend.rawValue)")
    let clear = CleartextNetlistSimulator(moduleName: moduleName, module: module)
    let encoding = compiler.bitEncoding
    let degree = compiler.degree
    let batch = compiler.batch
    let elementCount = batch * degree
    let vectorShape: [NSNumber] = [NSNumber(value: batch), NSNumber(value: degree)]

    // Enumerate primary inputs as single-bit ports (full_adder style).
    var portWidths: [(String, Int)] = []
    for (name, port) in module.ports.sorted(by: { $0.key < $1.key }) where port.direction == "input" {
        portWidths.append((name, port.bits.count))
    }
    let totalBits = portWidths.reduce(0) { $0 + $1.1 }
    precondition(totalBits <= 12, "Combinational equiv only for small input spaces")

    var failures = 0
    for mask in 0..<(1 << totalBits) {
        var clearInputs: [String: [UInt8]] = [:]
        var metalBits: [String: [UInt32]] = [:]
        var bitCursor = 0
        for (name, width) in portWidths {
            var cBits: [UInt8] = []
            var mBits: [UInt32] = []
            for _ in 0..<width {
                let v = UInt32((mask >> bitCursor) & 1)
                bitCursor += 1
                cBits.append(UInt8(v))
                mBits.append(v)
            }
            clearInputs[name] = cBits
            metalBits[name] = mBits
        }
        let clearOut = clear.tick(inputs: clearInputs)

        var feeds: [MPSGraphTensor: MPSGraphTensorData] = [:]
        for entry in compiler.inputNodes {
            guard let placeholder = entry.node.placeholder else { fatalError("missing placeholder") }
            let bits = metalBits[entry.port] ?? [0]
            let lane = encoding.encodeBit(bits[entry.bitIndex])
            let buffer = device.makeBuffer(
                bytes: lane,
                length: lane.count * MemoryLayout<UInt32>.stride,
                options: .storageModeShared
            )!
            feeds[placeholder] = MPSGraphTensorData(buffer, shape: vectorShape, dataType: .uInt32)
        }
        var results: [MPSGraphTensor: MPSGraphTensorData] = [:]
        var outputBuffers: [(port: String, bit: Int, buffer: MTLBuffer)] = []
        for entry in compiler.outputTensors {
            let buffer = device.makeBuffer(
                length: elementCount * MemoryLayout<UInt32>.stride,
                options: .storageModeShared
            )!
            results[entry.tensor] = MPSGraphTensorData(buffer, shape: vectorShape, dataType: .uInt32)
            outputBuffers.append((entry.port, entry.bitIndex, buffer))
        }
        compiler.graph.run(
            with: commandQueue,
            feeds: feeds,
            targetOperations: nil,
            resultsDictionary: results
        )
        for (port, bit, buffer) in outputBuffers {
            let ptr = buffer.contents().bindMemory(to: UInt32.self, capacity: elementCount)
            let lane = Array(UnsafeBufferPointer(start: ptr, count: degree))
            let got = encoding.decodeBit(lane)
            let want = UInt32(clearOut[port]?[bit] ?? 255)
            if got != want {
                failures += 1
                print("  FAIL mask=\(mask) \(port)[\(bit)] got=\(got) want=\(want)")
            }
        }
    }
    if failures == 0 {
        print("  rows            \(1 << totalBits)")
        print("  result          PASS")
    } else {
        print("  result          FAIL (\(failures) mismatches)")
        fputs("Combinational Metal≡cleartext FAIL\n", stderr)
        exit(1)
    }
    print("")
}

private func runEnigmaEquivGate(
    path: String,
    degree: Int,
    encodingKind: TrivialBitEncodingKind,
    lutBackend: LUTEvaluationBackend,
    device: MTLDevice,
    commandQueue: MTLCommandQueue
) {
    print("EQUIV (Metal boolean-path ≡ CleartextNetlistSim)")
    print("  encoding: \(encodingKind.rawValue)")
    print("  LUT backend: \(lutBackend.rawValue)")
    let plaintext = "KEINEBESONDERENEREIGNISSE"
    let left = 0, middle = 1, right = 2 // ABC

    let clear = EnigmaNetlistHarness(netlistPath: path)
    clear.seedGrundstellung(left: left, middle: middle, right: right)
    let ct = clear.process(ciphertext: EnigmaAlphabet.normalize(plaintext))
    clear.seedGrundstellung(left: left, middle: middle, right: right)
    let clearPT = clear.process(ciphertext: ct)
    let clearStr = EnigmaAlphabet.string(from: clearPT)
    precondition(clearStr == plaintext, "Clear harness round-trip failed: \(clearStr)")

    let netlist = loadYosysNetlist(from: path)
    guard let (moduleName, module) = netlist.modules.first else {
        fatalError("Empty netlist for equiv")
    }
    let compiler = YosysGraphCompiler(
        degree: degree,
        batch: 1,
        encodingKind: encodingKind,
        lutBackend: lutBackend
    )
    let compileStarted = CFAbsoluteTimeGetCurrent()
    compiler.compile(moduleName: moduleName, module: module)
    let compileSeconds = CFAbsoluteTimeGetCurrent() - compileStarted

    let metalStarted = CFAbsoluteTimeGetCurrent()
    let metalPT = runEnigmaMetalStream(
        compiler: compiler,
        module: module,
        device: device,
        commandQueue: commandQueue,
        ciphertext: ct,
        left: left,
        middle: middle,
        right: right
    )
    let metalSeconds = CFAbsoluteTimeGetCurrent() - metalStarted
    let metalStr = EnigmaAlphabet.string(from: metalPT)

    print(String(format: "  plaintext      %@", plaintext))
    print(String(format: "  clear          %@", clearStr))
    print(String(format: "  metal          %@", metalStr))
    print(String(format: "  compile        %.4f s (N=%d B=1)", compileSeconds, degree))
    print(
        String(
            format: "  stream         %.4f s (%d letters, %.4f s/letter)",
            metalSeconds,
            metalPT.count,
            metalSeconds / Double(max(1, metalPT.count))
        )
    )
    if metalStr == plaintext {
        print("  result          PASS")
    } else {
        print("  result          FAIL")
        fputs("Metal≡cleartext FAIL\n", stderr)
        exit(1)
    }
    print("")
}

private func runEnigmaMetalStream(
    compiler: YosysGraphCompiler,
    module: YosysModule,
    device: MTLDevice,
    commandQueue: MTLCommandQueue,
    ciphertext: [Int],
    left: Int,
    middle: Int,
    right: Int
) -> [Int] {
    let degree = compiler.degree
    let batch = compiler.batch
    let encoding = compiler.bitEncoding
    let elementCount = batch * degree
    let vectorShape: [NSNumber] = [NSNumber(value: batch), NSNumber(value: degree)]
    let zeroHost = packEncodedBits(bit: 0, encoding: encoding, batch: batch)
    let oneHost = packEncodedBits(bit: 1, encoding: encoding, batch: batch)

    var qWireToDFF: [Int: Int] = [:]
    for (index, dff) in compiler.dffNodes.enumerated() {
        guard let cell = module.cells[dff.cell],
              let qBit = cell.connections["Q"]?.first,
              case .net(let qWire) = qBit else { continue }
        qWireToDFF[qWire] = index
    }

    func dffBits(named name: String) -> [Int] {
        guard let net = module.netnames?[name] else { return [] }
        return net.bits.compactMap { bit -> Int? in
            guard case .net(let wire) = bit else { return nil }
            return qWireToDFF[wire]
        }
    }
    let rBits = dffBits(named: "rotor_r")
    let mBits = dffBits(named: "rotor_m")
    let lBits = dffBits(named: "rotor_l")

    var primaryFeeds: [MPSGraphTensor: MPSGraphTensorData] = [:]
    var ctBuffers: [MTLBuffer?] = Array(repeating: nil, count: 8)
    for entry in compiler.inputNodes {
        guard let placeholder = entry.node.placeholder else {
            fatalError("Missing placeholder")
        }
        let values = entry.port == "resetn" ? oneHost : zeroHost
        let buffer = makeSharedUInt32Buffer(device: device, values: values)
        if entry.port == "ciphertext_char", entry.bitIndex < 8 {
            ctBuffers[entry.bitIndex] = buffer
        }
        primaryFeeds[placeholder] = MPSGraphTensorData(buffer, shape: vectorShape, dataType: .uInt32)
    }

    let stateBuffersA: [MTLBuffer] = compiler.dffNodes.map { _ in
        makeSharedUInt32Buffer(device: device, values: zeroHost)
    }
    let stateSetA: [MPSGraphTensorData] = stateBuffersA.map {
        MPSGraphTensorData($0, shape: vectorShape, dataType: .uInt32)
    }
    let stateBuffersB: [MTLBuffer] = compiler.dffNodes.map { _ in
        makeSharedUInt32Buffer(device: device, count: elementCount)
    }
    let stateSetB: [MPSGraphTensorData] = stateBuffersB.map {
        MPSGraphTensorData($0, shape: vectorShape, dataType: .uInt32)
    }

    func writeStateBit(buffers: [MTLBuffer], dffIndex: Int, bit: UInt32) {
        let fill = encoding.encodeBit(bit)
        fill.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            buffers[dffIndex].contents().copyMemory(from: base, byteCount: raw.count)
        }
    }
    for (i, dffIndex) in rBits.enumerated() {
        writeStateBit(buffers: stateBuffersA, dffIndex: dffIndex, bit: UInt32((right >> i) & 1))
    }
    for (i, dffIndex) in mBits.enumerated() {
        writeStateBit(buffers: stateBuffersA, dffIndex: dffIndex, bit: UInt32((middle >> i) & 1))
    }
    for (i, dffIndex) in lBits.enumerated() {
        writeStateBit(buffers: stateBuffersA, dffIndex: dffIndex, bit: UInt32((left >> i) & 1))
    }

    var ptDFFIndices: [Int: Int] = [:]
    if let ptBits = module.ports["plaintext_char"]?.bits {
        for (bitIndex, bit) in ptBits.enumerated() {
            guard case .net(let wire) = bit, let dffIndex = qWireToDFF[wire] else { continue }
            ptDFFIndices[bitIndex] = dffIndex
        }
    }

    var stateFeeds = stateSetA
    var writeToB = true
    var plaintext: [Int] = []

    for letter in ciphertext {
        for bitIndex in 0..<8 {
            guard let buffer = ctBuffers[bitIndex] else { continue }
            let bit: UInt32 = ((letter >> bitIndex) & 1) == 0 ? 0 : 1
            let host = bit == 0 ? zeroHost : oneHost
            host.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                buffer.contents().copyMemory(from: base, byteCount: raw.count)
            }
        }

        let stateWrites = writeToB ? stateSetB : stateSetA
        let writeBuffers = writeToB ? stateBuffersB : stateBuffersA
        var feeds = primaryFeeds
        for (index, dff) in compiler.dffNodes.enumerated() {
            guard let placeholder = dff.stateInput.placeholder else {
                fatalError("Missing state placeholder")
            }
            feeds[placeholder] = stateFeeds[index]
        }

        var results: [MPSGraphTensor: MPSGraphTensorData] = [:]
        for entry in compiler.outputTensors {
            let buffer = makeSharedUInt32Buffer(device: device, count: elementCount)
            results[entry.tensor] = MPSGraphTensorData(
                buffer, shape: vectorShape, dataType: .uInt32
            )
        }
        for (index, dff) in compiler.dffNodes.enumerated() {
            guard let stateOutput = dff.stateOutput else {
                fatalError("Missing state output")
            }
            results[stateOutput] = stateWrites[index]
        }

        compiler.graph.run(
            with: commandQueue,
            feeds: feeds,
            targetOperations: nil,
            resultsDictionary: results
        )

        var value = 0
        for bit in 0..<5 {
            guard let dffIndex = ptDFFIndices[bit] else { continue }
            let ptr = writeBuffers[dffIndex].contents().bindMemory(
                to: UInt32.self, capacity: elementCount
            )
            let lane = Array(UnsafeBufferPointer(start: ptr, count: degree))
            if encoding.decodeBit(lane) != 0 {
                value |= (1 << bit)
            }
        }
        plaintext.append(value)
        stateFeeds = stateWrites
        writeToB.toggle()
    }
    return plaintext
}

/// Production-N Metal microbench: BK gen + 1-bit identity LUT blind-rotate.
/// Default N=1024. Use before full_adder×8 at production degree.
func runEncryptedMicrobench() {
    // Line-buffer stdout so long N=1024 runs show KEYGEN/TRIAL progress under tee.
    setbuf(stdout, nil)
    let degree = intFlag("--degree") ?? 1024
    let trials = intFlag("--trials") ?? 3
    let warmup = intFlag("--warmup", allowZero: true) ?? 1
    let tileWidthFlag = intFlag("--metal-br-tile")
    let tileWidth = tileWidthFlag ?? MetalBRControl.defaultTileWidth
    let forceFused = CommandLine.arguments.contains("--metal-br-fused")
    precondition(degree >= 2 && (2 * degree).nonzeroBitCount == 1, "2N must be power of two")
    precondition((2 * degree) <= 4096, "2N ≤ 4096 for binary X^p")

    MetalBRControl.defaultTileWidth = tileWidth
    if forceFused {
        MetalBRControl.overrideLowering = .fused
    } else if tileWidthFlag != nil {
        MetalBRControl.overrideLowering = .tiledKernel
    } else {
        MetalBRControl.overrideLowering = nil
    }
    MetalBRControl.progress = { line in
        print(line)
        fflush(stdout)
    }

    guard let device = MTLCreateSystemDefaultDevice(),
          let queue = device.makeCommandQueue() else {
        fputs("No Metal device\n", stderr)
        exit(1)
    }

    let twoN = 2 * degree
    let mux = MetalGGSW.DynamicRotateCost.muxRotates(twoN: twoN, lweDimension: degree)
    let bin = MetalGGSW.DynamicRotateCost.binaryRotates(twoN: twoN, lweDimension: degree)
    let rss0 = taskResidentMemoryBytes()

    print("HELUT encrypted Metal MICROBENCH")
    print("  N=\(degree)  2N=\(twoN)  trials=\(trials)  warmup=\(warmup)")
    let autoLower = MetalBRLowering.automatic(degree: degree)
    let lowering = MetalBRControl.overrideLowering ?? autoLower
    print("  lowering=\(lowering.rawValue)  tileWidth=\(tileWidth)")
    print("  DynamicRotateCost mux=\(mux) binary=\(bin) speedup≈\(String(format: "%.1f", Double(mux)/Double(bin)))×")
    print("")

    let params = GGSWParams.booleanTrivial(degree: degree)
    let keyStarted = CFAbsoluteTimeGetCurrent()
    let secret = TFHESecretKey.random(params: params.tfhe, seed: 0x1024)
    var rng = LCG32(state: 0x1025)
    let bk = bootstrapKey(
        secret: secret,
        params: params,
        rng: &rng,
        publicRefreshCompatible: true
    )
    let keySeconds = CFAbsoluteTimeGetCurrent() - keyStarted
    let rss1 = taskResidentMemoryBytes()
    print(String(format: "KEYGEN+BK         %.3f s  RSS %+0.1f MiB (after=%.1f MiB)",
                 keySeconds,
                 Double(Int64(rss1) &- Int64(rss0)) / (1024 * 1024),
                 Double(rss1) / (1024 * 1024)))

    let scale = rotationScale(polynomialDegree: degree)
    let hard = TFHELWEHardnessCertificate.forHELUTEncrypt(
        gaussian: degree >= 1024
            ? .productionBoolean64(polynomialDegree: degree)
            : .demoBoolean64(polynomialDegree: degree)
    )
    print(String(format: "HARDNESS          %.1f classical bits  (≥128? %@)",
                 hard.estimatedClassicalBits, hard.meetsTarget ? "yes" : "no"))

    // Identity LUT on 1 bit: table [0,1] → extract should match input bit.
    let truth: [UInt32] = [0, 1]
    TFHETestPolyCache.shared.clear()

    func oneBR(bit: UInt32) throws -> (UInt32, Double) {
        let ct = encryptLWERotationNative(
            message: bit,
            secret: secret.lweSecret,
            twoN: twoN,
            rng: &rng
        )
        print(String(format: "BR start bit=%d  RSS=%.1f MiB …", bit, Double(taskResidentMemoryBytes()) / (1024 * 1024)))
        fflush(stdout)
        let t0 = CFAbsoluteTimeGetCurrent()
        let out = try MetalGGSW.evaluateLUTBlindRotate(
            truthTable: truth,
            inputs: [ct],
            bootstrapKey: bk,
            scale: scale,
            device: device,
            commandQueue: queue
        )
        let dt = CFAbsoluteTimeGetCurrent() - t0
        let phase = decryptLWE(out, secret: secret)
        let got = decodeRotationBoolean(phase, scale: scale)
        return (got, dt)
    }

    do {
        for i in 0..<warmup {
            let (got, dt) = try oneBR(bit: UInt32(i & 1))
            precondition(got == UInt32(i & 1), "warmup mismatch")
            print(String(format: "WARMUP %d          %.3f s  ok", i, dt))
        }
        var times: [Double] = []
        for i in 0..<trials {
            let bit = UInt32(i & 1)
            let (got, dt) = try oneBR(bit: bit)
            precondition(got == bit, "trial mismatch")
            times.append(dt)
            let tel = MetalBRControl.lastTelemetry
            print(String(format: "TRIAL  %d          %.3f s  bit=%d PASS", i, dt, bit))
            print(String(
                format: "  telemetry       lowering=%@ ring=%@ tiles=%d encode=%.3fs gpu=%.3fs copy=%.3fs",
                tel.lowering, tel.ring, tel.tileCount, tel.encodeSeconds, tel.gpuRunSeconds, tel.hostRepackSeconds
            ))
        }
        let mean = times.reduce(0, +) / Double(max(times.count, 1))
        let (hits, misses, entries) = TFHETestPolyCache.shared.stats
        print("")
        print(String(format: "STEADY mean       %.3f s/BR (1-LUT identity @ N=%d)", mean, degree))
        print("INIT cache        hits=\(hits) misses=\(misses) entries=\(entries)")
        print(String(format: "RSS final         %.1f MiB", Double(taskResidentMemoryBytes()) / (1024 * 1024)))
        print("result            PASS")
    } catch {
        fputs("microbench failed: \(error)\n", stderr)
        exit(1)
    }
}

// MARK: - Helpers

private func resolveBenchNetlistPath() -> String {
    if let arg = positionalArgs.first {
        return resolveNetlistPath(argument: arg)
    }
    // Default suite order is chosen by the driver script; CLI default = PicoRV capstone.
    return resolveNetlistPath(argument: "picorv32_netlist.json")
}

private func taskResidentMemoryBytes() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(
        MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
    )
    let result = withUnsafeMutablePointer(to: &info) { infoPtr in
        infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { raw in
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), raw, &count)
        }
    }
    precondition(result == KERN_SUCCESS, "task_info failed: \(result)")
    return info.resident_size
}

/// Identity-LUT residual under noiseless vs injected BK noise (H4).
func runNoisyBKMeasure() {
    setbuf(stdout, nil)
    let degree = intFlag("--degree") ?? 8
    let trials = intFlag("--trials") ?? 16
    let injectNoise: TFHENoiseParams = {
        if let sigma = doubleFlag("--bk-noise-sigma"), sigma > 0 {
            return .gaussian(sigma: sigma)
        }
        return TFHENoiseParams(bound: UInt32(intFlag("--bk-noise", allowZero: true) ?? 64))
    }()
    let coveringSweep = CommandLine.arguments.contains("--covering-sweep")
    let booleanScaleMul = intFlag("--boolean-scale-mul") ?? 1
    let lweDimension = intFlag("--lwe-dimension")
    let injectLabel: String
    if injectNoise.usesGaussian {
        injectLabel = String(format: "σ=%.1f", injectNoise.gaussianSigma)
    } else {
        injectLabel = "B=\(injectNoise.bound)"
    }
    print("HELUT noisy-BK identity residual (H4)")
    print("  N=\(degree)  trials=\(trials)  inject ∈ {0, \(injectLabel)}"
        + (coveringSweep ? "  covering-sweep=yes" : "")
        + (booleanScaleMul > 1 ? "  kδ=\(booleanScaleMul)" : "")
        + (lweDimension.map { "  n=\($0)" } ?? ""))
    print("")
    var rows: [TFHENoisyBKMeasurement] = []
    var gadgets: [(String, GGSWParams)] = [
        ("cryptoPublicMS", .cryptoPublicMS(degree: degree)),
        ("crypto", .crypto(degree: degree))
    ]
    if let baseLogOnly = intFlag("--covering-base-log"), 32 % baseLogOnly == 0 {
        gadgets = [("covering-b\(baseLogOnly)", .covering(degree: degree, baseLog: baseLogOnly))]
    } else if coveringSweep {
        // Smaller baseLog ⇒ smaller EP β ⇒ less BK-noise amp (Track A push toward ε≤2^{-64}).
        for baseLog in [16, 8, 4, 2, 1] where 32 % baseLog == 0 {
            gadgets.append(("covering-b\(baseLog)", .covering(degree: degree, baseLog: baseLog)))
        }
    }
    if degree <= 16 {
        print("  note: booleanPublicMS (ℓ=1) omitted — incomplete gadget; BK noise mis-decomposes")
    }
    for (label, raw) in gadgets {
        let params = lweDimension.map { raw.withLWEDimension($0) } ?? raw
        let secret = TFHESecretKey.random(params: params.tfhe, seed: 0xB10C)
        let modes: [TFHENoiseParams] = [.none, injectNoise]
        for noise in modes {
            let measured = TFHENoisyBKMeasurement.identity(
                secret: secret,
                params: params,
                noise: noise,
                trials: trials,
                seed: 0xB10D &+ (noise.usesGaussian
                    ? UInt32(noise.gaussianSigma.rounded())
                    : noise.bound),
                booleanScaleMul: booleanScaleMul
            )
            let cert = measured.certificate(lutCount: 8)
            let gauss = measured.gaussianCertificate(lutCount: 8)
            let eps: String
            if gauss.failureLog2.isInfinite && gauss.failureLog2 < 0 {
                eps = "-inf"
            } else {
                eps = String(format: "%.1f", gauss.failureLog2)
            }
            let modeTag: String
            if noise.usesGaussian {
                modeTag = String(format: "σ=%.1f", noise.gaussianSigma)
            } else {
                modeTag = "B=\(noise.bound)"
            }
            print(
                "\(label) \(modeTag): max|e|=\(measured.maxAbsError) "
                    + String(format: "σ̂=%.1f", measured.sigmaHat)
                    + " δ/2=\(measured.decodingHalfGap) "
                    + "decode_fail=\(measured.decodeFailures) "
                    + "decodable=\(cert.eachLUTDecodable) εlog2=\(eps)"
                    // The bar is decided by the confidence bound, not the point
                    // estimate: log2(eps) is proportional to -1/sigma^2, so a
                    // sigma-hat from a handful of samples leaves orders
                    // unresolved. Only worth printing when it could change the
                    // verdict -- at tiny N the point estimate is astronomically
                    // below any bar and the uncertainty is moot.
                    // NOTE %ld, not %d: Int is 64-bit here and %d truncates.
                    + epsilonConfidenceNote(measured, lutCount: 8)
                    + "  (baseLog=\(params.baseLog) ℓ=\(params.levelCount))"
            )
            rows.append(measured)
            if noise.bound == 0 && !noise.usesGaussian {
                precondition(measured.maxAbsError == 0, "noiseless BK must measure B_bk=0")
                cert.assertDecodable()
            }
        }
    }
    print("")
    print(TFHENoisyBKMeasurement.markdownTable(rows))
}

/// Human-readable sampling-uncertainty note for a measured epsilon.
///
/// `log2(eps)` is proportional to `-1/sigma^2`, so a relative error r in
/// sigma-hat moves it by about `2*|log2 eps|*r`, and sigma-hat from m samples
/// carries a standard error near `1/sqrt(2m)`. The consequence found on
/// 2026-08-15: C35's "-65.4, still <= -64" at 4 samples carried +/-46 orders and
/// could not decide the bar at all.
///
/// Printed only when it is decision-relevant. When the 95% upper bound already
/// clears the target by a wide margin the note is noise, and at small N the
/// point estimate is so far below any bar that "orders unresolved" is a
/// meaningless-looking huge number.
func epsilonConfidenceNote(
    _ m: TFHENoisyBKMeasurement,
    lutCount: Int,
    targetLog2: Double = -64
) -> String {
    guard m.sigmaHat > 0, m.failureLog2Point.isFinite else { return "" }
    // The printed epsilon is the UNION over `lutCount` LUTs, so the bound must be
    // too, or the comparison is apples to oranges. Getting this wrong made the
    // bound look *better* than the point estimate, which is impossible for an
    // upper bound on sigma: at n=512 the single-LUT bound (-19.1) appeared to
    // beat the union point estimate (-18.0). Union adds log2(lutCount).
    let unionPenalty = log2(Double(max(lutCount, 1)))
    let upper = m.failureLog2Upper95 + unionPenalty
    let clearsAtBound = upper <= targetLog2
    // Comfortable: bound clears the bar with an order of magnitude to spare.
    if clearsAtBound && upper <= targetLog2 * 2 {
        return String(format: " [n=%ld, 95%%up=%.1f — clears %.0f]", m.samples, upper, targetLog2)
    }
    // What to do about a bar that is not met depends entirely on *why*, and the
    // two cases need opposite responses. Printing "±1 needs n≈40489" invited the
    // wrong one: that is the cost of resolving ε to ±1 order, a far stricter
    // standard than clearing a bar, and quoting it made under-sampled rows look
    // hopeless. AUDIT §14. So report the sample size that would actually settle
    // the bar, and say plainly when no sample size will.
    //
    // The requirement is stated against the union target, since the printed ε is
    // a union over `lutCount` LUTs.
    let unionTarget = targetLog2 - unionPenalty
    let needStr: String
    if clearsAtBound {
        needStr = ""
    } else if let need = m.samplesToMeetTarget(targetLog2: unionTarget) {
        needStr = String(format: ", under-sampled: n≈%ld would clear", need)
    } else {
        needStr = ", point estimate itself fails — no n clears this"
    }
    return String(
        format: " [n=%ld, 95%%up=%.1f %@ %.0f%@]",
        m.samples,
        upper,
        clearsAtBound ? "clears" : "DOES NOT CLEAR",
        targetLog2,
        needStr
    )
}
