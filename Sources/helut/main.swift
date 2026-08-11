import Foundation
import Metal
import MetalPerformanceShadersGraph
import HELUTCore

// MARK: - HELUT-Bombe: massively parallel Enigma cryptanalysis

/// P1030680 / M-Thetis tensor path: M4 netlist, B = 26³, in-graph linguistic score.
let p1030680Bombe = CommandLine.arguments.contains("--p1030680-bombe")

/// Parse `--name N` from argv; nil if absent or not an int.
/// By default requires a positive value. Pass `allowZero: true` when 0 is meaningful
/// (e.g. `--bombe-menus 0` means "all placements").
func intFlag(_ name: String, allowZero: Bool = false) -> Int? {
    guard let idx = CommandLine.arguments.firstIndex(of: name),
          idx + 1 < CommandLine.arguments.count,
          let value = Int(CommandLine.arguments[idx + 1]) else {
        return nil
    }
    if allowZero {
        return value >= 0 ? value : nil
    }
    return value > 0 ? value : nil
}

/// Parse `--name VALUE` from argv.
func stringFlag(_ name: String) -> String? {
    guard let idx = CommandLine.arguments.firstIndex(of: name),
          idx + 1 < CommandLine.arguments.count else {
        return nil
    }
    let value = CommandLine.arguments[idx + 1]
    return value.hasPrefix("--") ? nil : value
}

/// Batch dimension. Override with `--batch N`.
/// Defaults: P1030680 → 17,576 (26³); demo bombe → 10,000.
/// On 64 GB unified memory, M4 @ N=1024 is comfortable near B≈30–35k; ≥40k is tight.
let bombeBatch: Int = {
    if let batch = intFlag("--batch") {
        return batch
    }
    return p1030680Bombe ? 17_576 : 10_000
}()

let positionalArgs: [String] = {
    let args = Array(CommandLine.arguments.dropFirst())
    var out: [String] = []
    var index = 0
    let valueFlags: Set<String> = [
        "--ticks", "--batch", "--rings", "--subspace", "--msg-keys", "--skip", "--from",
        "--hybrid-pop", "--hybrid-gens", "--hybrid-greek-samples",
        "--exhaust-top", "--exhaust-plugs", "--selftest-len",
        "--bombe-menus", "--bombe-plugs", "--bombe-report", "--bombe-pipeline",
        "--bombe-from", "--bombe-min-crib", "--bombe-fixture",
        "--bombe-confirm", "--bombe-partners", "--bombe-opening-len",
        "--enigma256-out", "--enigma256-plain",
        "--enigma256-in", "--enigma256-ikm", "--enigma256-salt", "--enigma256-nonce",
        "--enigma256-mode", "--enigma256-plain-file",
        "--enigma256-host", "--enigma256-port",
        "--enigma256-passphrase", "--enigma256-pbkdf2-iters",
        "--enigma256-netlist", "--enigma256-emit-out", "--enigma256-tensorlut-log",
        "--enigma256-tensorlut-gens", "--enigma256-tensorlut-pop"
    ]
    while index < args.count {
        let arg = args[index]
        if valueFlags.contains(arg) {
            index += 2 // skip flag + value
            continue
        }
        if arg.hasPrefix("--") {
            index += 1
            continue
        }
        out.append(arg)
        index += 1
    }
    return out
}()

if CommandLine.arguments.contains("--enigma256-golden") {
    runEnigma256Golden()
    exit(0)
}

if CommandLine.arguments.contains("--enigma256-crypt") {
    runEnigma256Crypt()
    exit(0)
}

if CommandLine.arguments.contains("--enigma256-ecdh-demo") {
    runEnigma256ECDHDemo()
    exit(0)
}

if CommandLine.arguments.contains("--enigma256-wire-demo") {
    runEnigma256WireDemo()
    exit(0)
}

if CommandLine.arguments.contains("--enigma256-listen") {
    runEnigma256TCPListen()
    exit(0)
}

if CommandLine.arguments.contains("--enigma256-connect") {
    runEnigma256TCPConnect()
    exit(0)
}

if CommandLine.arguments.contains("--enigma256-tensorlut") {
    runEnigma256TensorLUT()
    exit(0)
}

let netlistPath = resolveEnigmaNetlistPath(
    argument: positionalArgs.first,
    preferredName: p1030680Bombe ? "enigma_m4_netlist.json" : "enigma_netlist.json"
)

if CommandLine.arguments.contains("--validate") {
    runThreeTierValidation(netlistPath: netlistPath)
    exit(0)
}

if CommandLine.arguments.contains("--welchman-rehearsal") {
    runWelchmanRehearsal()
    exit(0)
}

if CommandLine.arguments.contains("--debug-survivor") {
    DebugSurvivor.run()
    exit(0)
}

if let spec = stringFlag("--bombe-inspect") {
    PostBombeDiscriminator.inspect(spec: spec)
    exit(0)
}

if CommandLine.arguments.contains("--welchman") {
    var config = BombeSweepConfig()
    config.openingsOnly = CommandLine.arguments.contains("--bombe-openings")
    config.menuCount = intFlag("--bombe-menus", allowZero: true)
        ?? (config.openingsOnly ? 9 : config.menuCount)
    config.maxPlugs = intFlag("--bombe-plugs") ?? config.maxPlugs
    config.reportLimit = intFlag("--bombe-report") ?? config.reportLimit
    config.pipelineDepth = intFlag("--bombe-pipeline") ?? config.pipelineDepth
    config.confirmMenus = intFlag("--bombe-confirm")
        ?? (config.openingsOnly ? 2 : 1)
    config.confirmPartners = intFlag("--bombe-partners") ?? config.confirmPartners
    config.minOpeningLength = intFlag("--bombe-opening-len") ?? config.minOpeningLength
    config.menuFilter = stringFlag("--bombe-only") ?? config.menuFilter
    config.minCribLength = intFlag("--bombe-min-crib") ?? config.minCribLength
    config.resumeFrom = intFlag("--bombe-from") ?? config.resumeFrom
    config.sweepRightRing = CommandLine.arguments.contains("--bombe-ring-sweep")
    config.fixturePath = stringFlag("--bombe-fixture") ?? config.fixturePath
    if let subspace = stringFlag("--subspace") {
        config.wheelOrders = M4ThetisAttack.subspace(named: subspace).wheelOrders
    }
    runWelchmanBombe(config: config)
    exit(0)
}

if CommandLine.arguments.contains("--exhaust-selftest") {
    runExhaustiveSelfTest()
    exit(0)
}

if CommandLine.arguments.contains("--exhaust") {
    runExhaustiveCracker()
    exit(0)
}

if CommandLine.arguments.contains("--hybrid")
    || CommandLine.arguments.contains("--hybrid-bombe") {
    runHybridBombe()
    exit(0)
}

if CommandLine.arguments.contains("--break-p1030680")
    || CommandLine.arguments.contains("--campaign") {
    runP1030680Break()
    exit(0)
}

/// Intercepted ciphertext stream (A=0 … Z=25). Same bytes broadcast to every batch lane.
let ciphertextStream: [UInt8] = {
    let raw: String
    if p1030680Bombe {
        raw = U534MessageP1030680.ciphertext
    } else {
        raw = "HELUTBOMBE"
    }
    return Array(raw.utf8).map { byte in
        let letter: UInt8
        if byte >= 65 && byte <= 90 {
            letter = byte - 65
        } else if byte >= 97 && byte <= 122 {
            letter = byte - 97
        } else {
            letter = 0
        }
        return UInt8(letter % 26)
    }
}()

/// Clock ticks = ciphertext length (full P1030680 = 72). Override with `--ticks N`.
let bombeTicks: Int = {
    if let ticks = intFlag("--ticks") {
        return min(ticks, ciphertextStream.count)
    }
    if p1030680Bombe {
        return ciphertextStream.count
    }
    return min(10, ciphertextStream.count)
}()

struct BombeTickResult {
    let tick: Int
    let ciphertextByte: UInt8
    let elapsedSeconds: Double
}

guard let device = MTLCreateSystemDefaultDevice() else {
    fatalError("No Metal device available")
}
guard let commandQueue = device.makeCommandQueue() else {
    fatalError("Failed to create MTLCommandQueue")
}

let netlist = loadYosysNetlist(from: netlistPath)

guard let (moduleName, module) = netlist.modules.first else {
    fatalError("Yosys netlist contains no modules")
}

if p1030680Bombe {
    print("HELUT-Bombe — P1030680 M-Thetis (M4 tensor path)")
    print("Target: \(U534MessageP1030680.sourceURL)")
    print("Indicators: \(U534MessageP1030680.indicators.0) \(U534MessageP1030680.indicators.1)")
    print("Partition: B=\(bombeBatch) lanes (lane i ↔ L/M/R via i mod 26³); Greek/UKW/WO fixed in netlist")
    if bombeBatch > 38_000 {
        print("WARNING: B=\(bombeBatch) may exceed ~64 GB unified memory for M4 @ N=1024 — expect jetsam.")
    } else if bombeBatch > 30_000 {
        print("NOTE: B=\(bombeBatch) is a wide run — leave headroom; prefer --compile-only then --ticks 1 first.")
    }
} else {
    print("HELUT-Bombe — Massively Parallel Enigma Cryptanalysis")
}
print("Batch=\(bombeBatch), N=\(polynomialDegree), clockCycles=\(bombeTicks)")
print("Netlist: \(netlistPath)")
print("Creator: \(netlist.creator ?? "unknown")")
print("Module:  \(moduleName)")
print("Ciphertext stream (\(ciphertextStream.count) chars): \(ciphertextStream.map { String(UnicodeScalar(65 + Int($0))!) }.joined())")
print("retainHistory=false (double-buffered ping-pong)")
print("State / port tensor shape: [\(bombeBatch), \(polynomialDegree)]")
print("")

let compiler = YosysGraphCompiler(degree: polynomialDegree, batch: bombeBatch)
let compileStarted = CFAbsoluteTimeGetCurrent()
compiler.compile(moduleName: moduleName, module: module)
let compileSeconds = CFAbsoluteTimeGetCurrent() - compileStarted

print(String(format: "Graph compilation (setup): %.4f s", compileSeconds))
print(
    String(
        format: "  of which Toeplitz expand %.4f s, MPSGraph build %.4f s",
        compiler.lastToeplitzExpandSeconds,
        compiler.lastGraphBuildSeconds
    )
)
print("")

if CommandLine.arguments.contains("--compile-only") {
    print("Stopping after compile (--compile-only).")
    exit(0)
}

let rotorMap = mapRotorDFFIndices(module: module, dffNodes: compiler.dffNodes)
print(
    "Grundstellung mapping: rotor_r bits=\(rotorMap.rBits.count), "
        + "rotor_m bits=\(rotorMap.mBits.count), rotor_l bits=\(rotorMap.lBits.count)"
)

let bombeRun = runEnigmaBombe(
    compiler: compiler,
    device: device,
    commandQueue: commandQueue,
    ticks: bombeTicks,
    ciphertext: ciphertextStream,
    rotorMap: rotorMap
)
let tickResults = bombeRun.ticks

var totalElapsed = 0.0
for result in tickResults {
    totalElapsed += result.elapsedSeconds
    let letter = String(UnicodeScalar(65 + Int(result.ciphertextByte))!)
    print(
        String(
            format: "Tick %d — CT='%@' — graph.run %.4f s — %d SDFFs / %d LUTs",
            result.tick,
            letter as NSString,
            result.elapsedSeconds,
            compiler.dffNodes.count,
            compiler.lutNodes.count
        )
    )
}

let averagePerTick = totalElapsed / Double(bombeTicks)
print("")
print(String(format: "Graph compilation time:     %.4f s", compileSeconds))
print(String(format: "Total execution (%d ticks): %.4f s", bombeTicks, totalElapsed))
print(String(format: "Average execution / tick:   %.4f s", averagePerTick))

if let last = tickResults.last {
    if p1030680Bombe {
        let ranked = rankLinguisticScoreLanes(
            compiler: compiler,
            outputBuffers: bombeRun.outputBuffers,
            topK: 16
        )
        print("")
        print("In-graph linguistic_score ranking (top \(ranked.count) of \(bombeBatch) lanes):")
        for (rank, row) in ranked.enumerated() {
            print(
                String(
                    format: "  #%02d lane %5d  Grund L=%2d M=%2d R=%2d  linguistic_score=%u",
                    rank + 1,
                    row.lane,
                    row.grundL,
                    row.grundM,
                    row.grundR,
                    row.score
                )
            )
        }
        if let best = ranked.first {
            print(
                "Score spike leader: lane \(best.lane) "
                    + "L=\(best.grundL) M=\(best.grundM) R=\(best.grundR) score=\(best.score)"
            )
        }
        print(
            "Note: mock-PBS tensors are not boolean-faithful; host `--break-p1030680` is the cryptanalytic oracle."
        )
    } else {
        let candidates = scorePlaintextCandidates(
            compiler: compiler,
            outputBuffers: bombeRun.outputBuffers,
            tickOutputs: last,
            sampleLanes: min(8, bombeBatch)
        )
        print("")
        print("Plaintext tensor evaluation (mock-encrypted crib scan, first \(candidates.count) lanes):")
        for row in candidates {
            print(
                "  lane \(String(format: "%5d", row.lane))  "
                    + "Grundstellung R=\(String(format: "%2d", row.grundR)) "
                    + "M=\(String(format: "%2d", row.grundM)) "
                    + "L=\(String(format: "%2d", row.grundL))  "
                    + "score=\(row.score)  "
                    + "plaintext_bits[4:0]=0b\(String(row.plainLow5, radix: 2).leftPad(to: 5, with: "0"))"
            )
        }
        if let best = candidates.max(by: { $0.score < $1.score }) {
            print(
                "Top sampled candidate: lane \(best.lane) "
                    + "(R=\(best.grundR) M=\(best.grundM) L=\(best.grundL)) score=\(best.score)"
            )
        }
    }
}

print("")
print(
    "BOMBE COMPLETE: \(bombeBatch) parallel Enigma hypotheses stepped for \(bombeTicks) ticks; "
        + "\(compiler.dffNodes.count) encrypted state bits retained with ping-pong buffers."
)

// MARK: - Rotor DFF → bit mapping (from Yosys netnames)

struct RotorDFFMap {
    /// Indices into `compiler.dffNodes` for rotor_r[0…].
    let rBits: [Int]
    let mBits: [Int]
    let lBits: [Int]
}

func mapRotorDFFIndices(module: YosysModule, dffNodes: [CompiledDFF]) -> RotorDFFMap {
    var qWireToDFFIndex: [Int: Int] = [:]
    for (index, dff) in dffNodes.enumerated() {
        guard let cell = module.cells[dff.cell],
              let qBits = cell.connections["Q"],
              let qBit = qBits.first,
              case .net(let qWire) = qBit else {
            continue
        }
        qWireToDFFIndex[qWire] = index
    }

    func bits(named name: String) -> [Int] {
        guard let net = module.netnames?[name] else {
            fatalError("Missing netname '\(name)' in Enigma netlist")
        }
        var indices: [Int] = []
        for (bitIndex, bit) in net.bits.enumerated() {
            guard case .net(let wire) = bit else { continue } // constant-tied bits
            guard let dffIndex = qWireToDFFIndex[wire] else {
                fatalError("No DFF drives \(name)[\(bitIndex)] wire \(wire)")
            }
            indices.append(dffIndex)
        }
        return indices
    }

    return RotorDFFMap(rBits: bits(named: "rotor_r"), mBits: bits(named: "rotor_m"), lBits: bits(named: "rotor_l"))
}

struct Grundstellung {
    let rotorR: Int
    let rotorM: Int
    let rotorL: Int
}

func grundstellung(forLane lane: Int) -> Grundstellung {
    // Exact 26³ partition: lane ↔ (R, M, L). With B=17,576 every start is unique.
    let rotorR = lane % 26
    let rotorM = (lane / 26) % 26
    let rotorL = (lane / (26 * 26)) % 26
    return Grundstellung(rotorR: rotorR, rotorM: rotorM, rotorL: rotorL)
}

// MARK: - Clock loop (retainHistory = false, scripted ciphertext + Grundstellung)

struct BombeRunResult {
    let ticks: [BombeTickResult]
    let outputBuffers: [MTLBuffer]
}

func runEnigmaBombe(
    compiler: YosysGraphCompiler,
    device: MTLDevice,
    commandQueue: MTLCommandQueue,
    ticks: Int,
    ciphertext: [UInt8],
    rotorMap: RotorDFFMap
) -> BombeRunResult {
    precondition(ticks > 0)
    precondition(ciphertext.count >= ticks, "Ciphertext stream shorter than tick count")
    precondition(!compiler.dffNodes.isEmpty, "Expected sequential SDFF cells for clocked evaluation")
    for dff in compiler.dffNodes {
        precondition(dff.stateOutput != nil, "DFF '\(dff.cell)' missing state output (Q_next)")
        precondition(dff.stateInput.placeholder != nil, "DFF '\(dff.cell)' missing state input (Q)")
    }

    let vectorShape: [NSNumber] = [NSNumber(value: compiler.batch), NSNumber(value: compiler.degree)]
    let matrixShape: [NSNumber] = [NSNumber(value: compiler.degree), NSNumber(value: compiler.degree)]
    let elementCount = compiler.batch * compiler.degree
    let zeroHost = [UInt32](repeating: 0, count: elementCount)
    let oneHost = [UInt32](repeating: 1, count: elementCount)

    let primary = makeBombePrimaryFeeds(
        compiler: compiler,
        device: device,
        shape: vectorShape,
        zeroHost: zeroHost,
        oneHost: oneHost
    )
    let matrixFeeds = makeBombeLUTMatrixFeeds(compiler: compiler, device: device, shape: matrixShape)
    let buffers = makeBombeBufferPool(
        compiler: compiler,
        device: device,
        shape: vectorShape,
        elementCount: elementCount,
        zeroHost: zeroHost
    )

    // Seed state set A with per-lane Grundstellung hypotheses (rotor DFFs only).
    seedGrundstellung(
        stateBuffers: buffers.stateBuffersA,
        rotorMap: rotorMap,
        degree: compiler.degree,
        batch: compiler.batch
    )

    var stateFeeds = buffers.stateSetA
    var writeToB = true
    var tickResults: [BombeTickResult] = []
    tickResults.reserveCapacity(ticks)

    for tick in 1...ticks {
        let tickResult: BombeTickResult = autoreleasepool {
            let cipherByte = ciphertext[tick - 1]
            writeCiphertextByte(
                cipherByte,
                into: primary.ciphertextBuffers,
                degree: compiler.degree,
                batch: compiler.batch,
                zeroHost: zeroHost,
                oneHost: oneHost
            )
            // resetn stays encrypted-1 so seeded Grundstellung is not cleared.
            primary.resetnValues.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                primary.resetnBuffer.contents().copyMemory(from: base, byteCount: raw.count)
            }

            let stateWrites = writeToB ? buffers.stateSetB : buffers.stateSetA
            var feeds = primary.feeds
            feeds.merge(matrixFeeds) { _, new in new }
            for (index, dff) in compiler.dffNodes.enumerated() {
                guard let placeholder = dff.stateInput.placeholder else {
                    fatalError("Missing state-input placeholder for '\(dff.cell)'")
                }
                feeds[placeholder] = stateFeeds[index]
            }

            var resultsDictionary: [MPSGraphTensor: MPSGraphTensorData] = [:]
            for (outIndex, entry) in compiler.outputTensors.enumerated() {
                resultsDictionary[entry.tensor] = buffers.outputScratch[outIndex]
            }
            for (index, dff) in compiler.dffNodes.enumerated() {
                guard let stateOutput = dff.stateOutput else {
                    fatalError("Missing state output for '\(dff.cell)'")
                }
                resultsDictionary[stateOutput] = stateWrites[index]
            }

            let started = CFAbsoluteTimeGetCurrent()
            compiler.graph.run(
                with: commandQueue,
                feeds: feeds,
                targetOperations: nil,
                resultsDictionary: resultsDictionary
            )
            let elapsed = CFAbsoluteTimeGetCurrent() - started

            stateFeeds = stateWrites
            writeToB.toggle()
            return BombeTickResult(tick: tick, ciphertextByte: cipherByte, elapsedSeconds: elapsed)
        }
        tickResults.append(tickResult)
    }

    return BombeRunResult(ticks: tickResults, outputBuffers: buffers.outputBuffers)
}

private struct BombePrimaryFeeds {
    let feeds: [MPSGraphTensor: MPSGraphTensorData]
    let resetnBuffer: MTLBuffer
    let resetnValues: [UInt32]
    /// Bit 0 … 7 of `ciphertext_char`, each an MTLBuffer of shape [B, N].
    let ciphertextBuffers: [MTLBuffer]
}

private struct BombeBufferPool {
    let stateSetA: [MPSGraphTensorData]
    let stateSetB: [MPSGraphTensorData]
    let stateBuffersA: [MTLBuffer]
    let outputScratch: [MPSGraphTensorData]
    let outputBuffers: [MTLBuffer]
}

private func makeBombePrimaryFeeds(
    compiler: YosysGraphCompiler,
    device: MTLDevice,
    shape: [NSNumber],
    zeroHost: [UInt32],
    oneHost: [UInt32]
) -> BombePrimaryFeeds {
    var feeds: [MPSGraphTensor: MPSGraphTensorData] = [:]
    var resetnBuffer: MTLBuffer?
    var ciphertextBuffers = [MTLBuffer?](repeating: nil, count: 8)

    for entry in compiler.inputNodes {
        guard let placeholder = entry.node.placeholder else {
            fatalError("Missing placeholder for input '\(entry.port)'")
        }
        let initial: [UInt32]
        if entry.port == "resetn" {
            initial = oneHost
        } else if entry.port == "ciphertext_char" {
            initial = zeroHost
        } else {
            // clk and any other ports: host loop is the clock.
            initial = zeroHost
        }
        let buffer = makeSharedUInt32Buffer(device: device, values: initial)
        if entry.port == "resetn" {
            resetnBuffer = buffer
        }
        if entry.port == "ciphertext_char", entry.bitIndex < 8 {
            ciphertextBuffers[entry.bitIndex] = buffer
        }
        feeds[placeholder] = MPSGraphTensorData(buffer, shape: shape, dataType: .uInt32)
    }

    guard let resetnBuffer else {
        fatalError("Failed to allocate resetn feed buffer")
    }
    let ctBuffers = ciphertextBuffers.map { buffer -> MTLBuffer in
        guard let buffer else {
            fatalError("Missing ciphertext_char bit buffer")
        }
        return buffer
    }
    return BombePrimaryFeeds(
        feeds: feeds,
        resetnBuffer: resetnBuffer,
        resetnValues: oneHost,
        ciphertextBuffers: ctBuffers
    )
}

private func makeBombeLUTMatrixFeeds(
    compiler: YosysGraphCompiler,
    device: MTLDevice,
    shape: [NSNumber]
) -> [MPSGraphTensor: MPSGraphTensorData] {
    var feeds: [MPSGraphTensor: MPSGraphTensorData] = [:]
    for entry in compiler.lutNodes {
        guard let matrixPlaceholder = entry.node.matrixPlaceholder else {
            fatalError("Missing matrix placeholder for LUT '\(entry.cell)'")
        }
        let buffer = makeSharedUInt32Buffer(device: device, values: entry.node.matrix)
        feeds[matrixPlaceholder] = MPSGraphTensorData(buffer, shape: shape, dataType: .uInt32)
    }
    return feeds
}

private func makeBombeBufferPool(
    compiler: YosysGraphCompiler,
    device: MTLDevice,
    shape: [NSNumber],
    elementCount: Int,
    zeroHost: [UInt32]
) -> BombeBufferPool {
    var stateBuffersA: [MTLBuffer] = []
    stateBuffersA.reserveCapacity(compiler.dffNodes.count)
    let stateSetA: [MPSGraphTensorData] = compiler.dffNodes.map { _ in
        let buffer = makeSharedUInt32Buffer(device: device, values: zeroHost)
        stateBuffersA.append(buffer)
        return MPSGraphTensorData(buffer, shape: shape, dataType: .uInt32)
    }
    let stateSetB: [MPSGraphTensorData] = compiler.dffNodes.map { _ in
        let buffer = makeSharedUInt32Buffer(device: device, count: elementCount)
        return MPSGraphTensorData(buffer, shape: shape, dataType: .uInt32)
    }
    var outputBuffers: [MTLBuffer] = []
    outputBuffers.reserveCapacity(compiler.outputTensors.count)
    let outputScratch: [MPSGraphTensorData] = compiler.outputTensors.map { _ in
        let buffer = makeSharedUInt32Buffer(device: device, count: elementCount)
        outputBuffers.append(buffer)
        return MPSGraphTensorData(buffer, shape: shape, dataType: .uInt32)
    }
    return BombeBufferPool(
        stateSetA: stateSetA,
        stateSetB: stateSetB,
        stateBuffersA: stateBuffersA,
        outputScratch: outputScratch,
        outputBuffers: outputBuffers
    )
}

private func seedGrundstellung(
    stateBuffers: [MTLBuffer],
    rotorMap: RotorDFFMap,
    degree: Int,
    batch: Int
) {
    func writeBit(dffIndex: Int, lane: Int, bit: UInt32) {
        let buffer = stateBuffers[dffIndex]
        let offset = (lane * degree) * MemoryLayout<UInt32>.stride
        // Mock-encrypted bit: fill the whole degree-N polynomial with 0 or 1.
        let fill = [UInt32](repeating: bit, count: degree)
        fill.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            buffer.contents().advanced(by: offset).copyMemory(from: base, byteCount: raw.count)
        }
    }

    for lane in 0..<batch {
        let start = grundstellung(forLane: lane)
        for (bitIndex, dffIndex) in rotorMap.rBits.enumerated() {
            let bit: UInt32 = ((start.rotorR >> bitIndex) & 1) == 0 ? 0 : 1
            writeBit(dffIndex: dffIndex, lane: lane, bit: bit)
        }
        for (bitIndex, dffIndex) in rotorMap.mBits.enumerated() {
            let bit: UInt32 = ((start.rotorM >> bitIndex) & 1) == 0 ? 0 : 1
            writeBit(dffIndex: dffIndex, lane: lane, bit: bit)
        }
        for (bitIndex, dffIndex) in rotorMap.lBits.enumerated() {
            let bit: UInt32 = ((start.rotorL >> bitIndex) & 1) == 0 ? 0 : 1
            writeBit(dffIndex: dffIndex, lane: lane, bit: bit)
        }
    }
}

private func writeCiphertextByte(
    _ byte: UInt8,
    into buffers: [MTLBuffer],
    degree: Int,
    batch: Int,
    zeroHost: [UInt32],
    oneHost: [UInt32]
) {
    for bitIndex in 0..<8 {
        let bitIsOne = ((Int(byte) >> bitIndex) & 1) != 0
        let host = bitIsOne ? oneHost : zeroHost
        host.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            buffers[bitIndex].contents().copyMemory(from: base, byteCount: raw.count)
        }
    }
    _ = degree
    _ = batch
}

// MARK: - Crib / candidate scoring on plaintext_char tensors

struct CandidateRow {
    let lane: Int
    let grundR: Int
    let grundM: Int
    let grundL: Int
    let score: UInt32
    let plainLow5: Int
}

private func scorePlaintextCandidates(
    compiler: YosysGraphCompiler,
    outputBuffers: [MTLBuffer],
    tickOutputs: BombeTickResult,
    sampleLanes: Int
) -> [CandidateRow] {
    _ = tickOutputs
    let degree = compiler.degree
    let batch = compiler.batch
    var plainBitBuffers: [Int: MTLBuffer] = [:]
    for (index, entry) in compiler.outputTensors.enumerated() where entry.port == "plaintext_char" {
        guard index < outputBuffers.count else { continue }
        plainBitBuffers[entry.bitIndex] = outputBuffers[index]
    }

    var rows: [CandidateRow] = []
    rows.reserveCapacity(sampleLanes)
    for lane in 0..<sampleLanes {
        let start = grundstellung(forLane: lane)
        var score: UInt32 = 0
        var plainLow5 = 0
        for bit in 0..<5 {
            guard let buffer = plainBitBuffers[bit] else { continue }
            let ptr = buffer.contents().bindMemory(to: UInt32.self, capacity: batch * degree)
            let coeff0 = ptr[lane * degree]
            score &+= coeff0
            if coeff0 != 0 {
                plainLow5 |= (1 << bit)
            }
        }
        rows.append(
            CandidateRow(
                lane: lane,
                grundR: start.rotorR,
                grundM: start.rotorM,
                grundL: start.rotorL,
                score: score,
                plainLow5: plainLow5
            )
        )
    }
    return rows
}

/// Read the Verilog `linguistic_score` port across all batch lanes and keep top-K spikes.
private func rankLinguisticScoreLanes(
    compiler: YosysGraphCompiler,
    outputBuffers: [MTLBuffer],
    topK: Int
) -> [CandidateRow] {
    let degree = compiler.degree
    let batch = compiler.batch
    var scoreBitBuffers: [Int: MTLBuffer] = [:]
    for (index, entry) in compiler.outputTensors.enumerated() where entry.port == "linguistic_score" {
        guard index < outputBuffers.count else { continue }
        scoreBitBuffers[entry.bitIndex] = outputBuffers[index]
    }
    precondition(!scoreBitBuffers.isEmpty, "Netlist missing linguistic_score output (need enigma_m4_core)")

    var heap: [CandidateRow] = []
    heap.reserveCapacity(topK)

    for lane in 0..<batch {
        var value: UInt32 = 0
        for bit in 0..<16 {
            guard let buffer = scoreBitBuffers[bit] else { continue }
            let ptr = buffer.contents().bindMemory(to: UInt32.self, capacity: batch * degree)
            if ptr[lane * degree] != 0 {
                value |= (1 << bit)
            }
        }
        let start = grundstellung(forLane: lane)
        let row = CandidateRow(
            lane: lane,
            grundR: start.rotorR,
            grundM: start.rotorM,
            grundL: start.rotorL,
            score: value,
            plainLow5: 0
        )
        if heap.count < topK {
            heap.append(row)
            if heap.count == topK {
                heap.sort { $0.score > $1.score }
            }
        } else if let worst = heap.last, value > worst.score {
            heap[topK - 1] = row
            heap.sort { $0.score > $1.score }
        }
    }
    return heap.sorted { $0.score > $1.score }
}

func resolveEnigmaNetlistPath(argument: String?, preferredName: String = "enigma_netlist.json") -> String {
    if let argument {
        return argument
    }
    let candidates = [
        preferredName,
        "../\(preferredName)",
        "../../\(preferredName)",
        "enigma_netlist.json",
        "../enigma_netlist.json"
    ]
    let cwd = FileManager.default.currentDirectoryPath
    for relative in candidates {
        let path = URL(fileURLWithPath: cwd).appendingPathComponent(relative).path
        if FileManager.default.fileExists(atPath: path) {
            return path
        }
    }
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 {
        url.deleteLastPathComponent()
        let candidate = url.appendingPathComponent(preferredName).path
        if FileManager.default.fileExists(atPath: candidate) {
            return candidate
        }
        let fallback = url.appendingPathComponent("enigma_netlist.json").path
        if FileManager.default.fileExists(atPath: fallback) {
            return fallback
        }
    }
    fatalError("\(preferredName) not found (cwd=\(cwd)). Pass an explicit path as argv[1].")
}

// MARK: - Three-tier validation pipeline (`--validate`)

func runThreeTierValidation(netlistPath: String) {
    print("HELUT-Bombe — Three-Tier Validation Pipeline")
    print("Netlist: \(netlistPath)")
    print("")

    // Tier 1: synthetic control phrase + injected correct lane among 10,000.
    let plaintext = "KEINEBESONDERENEREIGNISSE"
    let plugs: [(Character, Character)] = [
        ("A", "M"), ("B", "C"), ("D", "F"), ("G", "H"), ("I", "J"),
        ("K", "L"), ("N", "O"), ("P", "Q"), ("R", "S"), ("T", "U")
    ]
    let correctPositions = (
        EnigmaAlphabet.index("A"),
        EnigmaAlphabet.index("B"),
        EnigmaAlphabet.index("C")
    )
    let steckeredKey = EnigmaKey(
        rotors: (EnigmaWarehouse.rotorI, EnigmaWarehouse.rotorII, EnigmaWarehouse.rotorIII),
        rings: (0, 0, 0),
        positions: correctPositions,
        plugboard: EnigmaKey.plugboard(pairs: plugs)
    )
    var enc = EnigmaMachine(key: steckeredKey)
    let ciphertext = EnigmaAlphabet.normalize(enc.processString(plaintext))
    print("Tier 1 — Synthetic ground truth")
    print("  Plaintext:   \(plaintext)")
    print("  Ciphertext:  \(EnigmaAlphabet.string(from: ciphertext))")
    print("  Key: I-II-III rings AAA start ABC, 10 steckers")

    let correctLane = 42
    let positions: [(Int, Int, Int)] = (0..<bombeBatch).map { lane in
        if lane == correctLane { return correctPositions }
        let left = (lane * 7 + 3) % 26
        let middle = (lane * 11 + 5) % 26
        let right = (lane * 13 + 9) % 26
        let candidate = (left, middle, right)
        return candidate == correctPositions ? ((left + 1) % 26, middle, right) : candidate
    }
    let tier1 = HostEnigmaBombe.run(
        ciphertext: ciphertext,
        baseKey: steckeredKey,
        positionsPerLane: positions
    )
    let falsePositives = tier1.filter { $0.lane != correctLane && $0.plaintextString == plaintext }
    precondition(tier1[correctLane].plaintextString == plaintext, "Tier 1 correct lane failed to decrypt")
    precondition(falsePositives.isEmpty, "Tier 1 false positives: \(falsePositives.map(\.lane))")
    let spike1 = LanguageScorer.detectSpikes(results: tier1, margin: 0.8)
    print("  Assert: lane \(correctLane) exclusive plaintext recovery — PASS")
    print(
        String(
            format: "  Scoreboard winner lane %d score=%.3f noiseFloor=%.3f",
            spike1.winner?.lane ?? -1,
            spike1.winner?.score ?? 0,
            spike1.noiseFloor
        )
    )

    // Cleartext netlist ≡ oracle (HELUT Verilog baseline, empty stecker).
    var baselineEnc = EnigmaMachine(key: .helutBaseline(positions: correctPositions))
    let baselineCT = EnigmaAlphabet.normalize(baselineEnc.processString(plaintext))
    let harness = EnigmaNetlistHarness(netlistPath: netlistPath)
    harness.seedGrundstellung(
        left: correctPositions.0,
        middle: correctPositions.1,
        right: correctPositions.2
    )
    let netlistPT = EnigmaAlphabet.string(from: harness.process(ciphertext: baselineCT))
    precondition(netlistPT == plaintext, "Cleartext netlist diverged from oracle: \(netlistPT)")
    print("  Cleartext netlist ≡ oracle for HELUT baseline — PASS")
    print("")

    // Tier 2: historical FHPQX.
    print("Tier 2 — Historical vector FHPQX (Ostwald/Weierud 1941-07-13)")
    let historical = EnigmaKey(
        rotors: (EnigmaWarehouse.rotorIV, EnigmaWarehouse.rotorII, EnigmaWarehouse.rotorIII),
        rings: (
            EnigmaAlphabet.index("G"),
            EnigmaAlphabet.index("T"),
            EnigmaAlphabet.index("O")
        ),
        positions: (
            EnigmaAlphabet.index("S"),
            EnigmaAlphabet.index("D"),
            EnigmaAlphabet.index("V")
        ),
        plugboard: EnigmaKey.plugboard(pairs: [
            ("A", "D"), ("E", "H"), ("G", "Y"), ("I", "M"), ("K", "N"),
            ("L", "R"), ("O", "Z"), ("Q", "V"), ("T", "X"), ("U", "W")
        ])
    )
    let histCT = EnigmaAlphabet.normalize("FDZCJJDKVWPYFDWPOQZGTJQYYXAFRHSQESE")
    var histMachine = EnigmaMachine(key: historical)
    let histPlain = EnigmaAlphabet.string(from: histMachine.processText(histCT))
    precondition(histPlain.hasPrefix("ANXPANZXGRUPPEXVIERX"), "Historical decrypt failed: \(histPlain)")
    print("  Decrypt prefix: \(String(histPlain.prefix(24)))")
    print("  Crib window contains SIEGFR: \(histPlain.contains("SIEGFR") ? "PASS" : "FAIL")")
    print("")

    // Tier 3: scoreboard ranks correct historical key above 199 decoys.
    print("Tier 3 — IC / n-gram scoreboard spike detection")
    var histPositions: [(Int, Int, Int)] = [historical.positions]
    for lane in 1..<200 {
        histPositions.append(HostEnigmaBombe.helutGrundstellung(lane: lane + 50))
    }
    let histLongCT = EnigmaAlphabet.normalize(
        "FDZCJJDKVWPYFDWPOQZGTJQYYXAFRHSQESERKGJBWBYPEOOKFMMPOMK"
    )
    let tier3 = HostEnigmaBombe.run(
        ciphertext: histLongCT,
        baseKey: historical,
        positionsPerLane: histPositions
    )
    let spike3 = LanguageScorer.detectSpikes(results: tier3, margin: 0.5)
    guard let winner3 = spike3.winner else {
        fatalError("Tier 3 produced no winner")
    }
    precondition(
        winner3.positions == historical.positions,
        "Tier 3 failed to rank correct key"
    )
    print(
        String(
            format: "  Winner IC=%.4f score=%.3f plaintext=%@",
            winner3.indexOfCoincidence,
            winner3.score,
            String(winner3.plaintextString.prefix(28)) as NSString
        )
    )
    print("  Spike isolation of SDV among 200 hypotheses — PASS")
    print("")
    print("VALIDATION COMPLETE — tiers 1–3 green.")
    print(
        "Note: Metal mock-PBS tensors do not carry boolean plaintext; "
            + "letter-level assertions use EnigmaOracle + cleartext netlist simulation."
    )
}

// MARK: - P1030680 M-Thetis attack entrypoint

func runP1030680Break() {
    print("HELUT — Breaking P1030680 (U534, 1 May 1945, suspected M-Thetis)")
    print("Source: \(U534MessageP1030680.sourceURL)")
    print("Indicators: \(U534MessageP1030680.indicators.0) \(U534MessageP1030680.indicators.1)")
    print("Ciphertext (\(U534MessageP1030680.ciphertext.count) letters): \(U534MessageP1030680.ciphertext)")
    print("")

    let ct = EnigmaAlphabet.normalize(U534MessageP1030680.ciphertext)
    let campaign = CommandLine.arguments.contains("--campaign")

    printCribDragReport(ciphertext: ct)
    printPotsdamNegativeControl(ciphertext: ct)

    if campaign {
        runP1030680Campaign(ciphertext: ct)
    } else {
        let phase = resolveSingleAttackPhase()
        let broken = runAttackPhase(phase, ciphertext: ct)
        if !broken {
            print("See BREAK_P1030680.md — or re-run with --campaign to ladder all phases.")
        }
    }
}

private struct AttackPhase {
    let name: String
    let rationale: String
    let wheelOrders: [(EnigmaRotorSpec, EnigmaRotorSpec, EnigmaRotorSpec)]
    let ringVariants: [(Int, Int, Int, Int)]
    let msgKeyTopK: Int
    let candidateTopK: Int
}

private func resolveSingleAttackPhase() -> AttackPhase {
    let quick = CommandLine.arguments.contains("--quick")
    let msgKeys = intFlag("--msg-keys") ?? (quick ? 1 : 3)
    let candidateTopK = 40

    if let subspaceName = stringFlag("--subspace") {
        let space = M4ThetisAttack.subspace(named: subspaceName)
        var rings = space.ringVariants
        if let ringsText = stringFlag("--rings") {
            rings = M4ThetisAttack.parseRingsList(ringsText)
        } else if CommandLine.arguments.contains("--rings-right") {
            rings = (0..<26).map { (0, 0, 0, $0) }
        }
        return AttackPhase(
            name: space.name,
            rationale: space.rationale,
            wheelOrders: quick ? Array(space.wheelOrders.prefix(6)) : space.wheelOrders,
            ringVariants: rings,
            msgKeyTopK: msgKeys,
            candidateTopK: candidateTopK
        )
    }

    let orders: [(EnigmaRotorSpec, EnigmaRotorSpec, EnigmaRotorSpec)]
    if quick {
        orders = [
            (EnigmaWarehouse.rotorIV, EnigmaWarehouse.rotorIII, EnigmaWarehouse.rotorVIII),
            (EnigmaWarehouse.rotorV, EnigmaWarehouse.rotorVI, EnigmaWarehouse.rotorVIII),
            (EnigmaWarehouse.rotorI, EnigmaWarehouse.rotorII, EnigmaWarehouse.rotorIII),
            (EnigmaWarehouse.rotorVIII, EnigmaWarehouse.rotorVII, EnigmaWarehouse.rotorVI),
            (EnigmaWarehouse.rotorII, EnigmaWarehouse.rotorIV, EnigmaWarehouse.rotorV),
            (EnigmaWarehouse.rotorIII, EnigmaWarehouse.rotorVI, EnigmaWarehouse.rotorVIII)
        ]
    } else {
        orders = M4ThetisAttack.allWheelOrders()
    }

    let rings: [(Int, Int, Int, Int)]
    if let ringsText = stringFlag("--rings") {
        rings = M4ThetisAttack.parseRingsList(ringsText)
    } else if CommandLine.arguments.contains("--rings-right") {
        rings = (0..<26).map { (0, 0, 0, $0) }
    } else {
        rings = [(0, 0, 0, 0)]
    }

    return AttackPhase(
        name: quick ? "quick" : "custom",
        rationale: "CLI single-phase attack",
        wheelOrders: orders,
        ringVariants: rings,
        msgKeyTopK: msgKeys,
        candidateTopK: candidateTopK
    )
}

/// Ordered ladder: cheap same-day priors first, then wider coverage with top-K msg-keys.
/// Full rings-AAAA and AAA* (`--rings-right`) are **not** required repeats of your prior
/// msg-key=1 sweeps — use `--skip rings-right` / `--skip aaaa` as needed.
private func campaignPhases() -> [AttackPhase] {
    let potsdam = M4ThetisAttack.potsdamNeighbourhood()
    let twoNotch = M4ThetisAttack.navalTwoNotchPrior()
    let aaaa = (0, 0, 0, 0)
    let aacu = EnigmaM4Key.rings(fromLetters: "AACU")
    let vcch = EnigmaM4Key.rings(fromLetters: "VCCH")
    let includeAAAA = CommandLine.arguments.contains("--include-aaaa")
    // Default: skip full-space AAAA (already swept at msg-keys=1). Keep AAAA only on the
    // tiny potsdam-neighbourhood phase unless --include-aaaa widens later phases.
    let potsdamRingsWide: [(Int, Int, Int, Int)] = includeAAAA ? [aaaa, aacu, vcch] : [aacu, vcch]
    let allWO = M4ThetisAttack.allWheelOrders()

    return [
        AttackPhase(
            name: "1-potsdam-neighbourhood",
            rationale: potsdam.rationale,
            wheelOrders: potsdam.wheelOrders,
            ringVariants: potsdam.ringVariants, // AAAA/AACU/VCCH — cheap (6 WO)
            msgKeyTopK: 8,
            candidateTopK: 40
        ),
        AttackPhase(
            name: "2-two-notch-potsdam-rings",
            rationale: twoNotch.rationale + " × \(includeAAAA ? "AAAA/" : "")AACU/VCCH",
            wheelOrders: twoNotch.wheelOrders,
            ringVariants: potsdamRingsWide,
            msgKeyTopK: 5,
            candidateTopK: 40
        ),
        AttackPhase(
            name: "3-full-aacu-vcch",
            rationale: "All 336 WO × rings AACU/VCCH"
                + (includeAAAA ? "/AAAA" : " (AAAA omitted — already swept)")
                + ", top-5 msg-keys",
            wheelOrders: allWO,
            ringVariants: potsdamRingsWide,
            msgKeyTopK: 5,
            candidateTopK: 50
        ),
        AttackPhase(
            name: "4-full-rings-right",
            rationale: "All 336 WO × rings AAA* (right-ring sweep), top-3 msg-keys — skip if already done",
            wheelOrders: allWO,
            ringVariants: (0..<26).map { (0, 0, 0, $0) },
            msgKeyTopK: 3,
            candidateTopK: 50
        )
    ]
}

private func campaignSkipSet() -> Set<String> {
    guard let raw = stringFlag("--skip") else { return [] }
    return Set(
        raw.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }.filter { !$0.isEmpty }
    )
}

private func shouldSkipCampaignPhase(_ phase: AttackPhase, skip: Set<String>) -> Bool {
    guard !skip.isEmpty else { return false }
    let name = phase.name.lowercased()
    let bare = name.split(separator: "-").dropFirst().joined(separator: "-") // drop leading index
    let index = name.split(separator: "-").first.map(String.init) ?? ""
    for token in skip {
        if token == name || token == bare || token == index { return true }
        if token == "rings-right" && name.contains("rings-right") { return true }
        if token == "aaaa" && (name.contains("rings-right") || name.contains("aaaa")) { return true }
        if token == "potsdam" && name.contains("potsdam-neighbourhood") { return true }
        if token == "two-notch" && name.contains("two-notch") { return true }
        if (token == "aacu" || token == "vcch" || token == "potsdam-rings") && name.contains("aacu-vcch") {
            return true
        }
        if name.contains(token) { return true }
    }
    return false
}

private func campaignStartIndex(phases: [AttackPhase]) -> Int {
    guard let raw = stringFlag("--from") else { return 0 }
    let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if let n = Int(key), n >= 1, n <= phases.count {
        return n - 1
    }
    if let idx = phases.firstIndex(where: {
        let name = $0.name.lowercased()
        return name == key || name.contains(key) || name.split(separator: "-").dropFirst().joined(separator: "-") == key
    }) {
        return idx
    }
    fputs("WARNING: --from \(raw) did not match a phase; starting at phase 1\n", stderr)
    return 0
}

private func runP1030680Campaign(ciphertext: [Int]) {
    print("CAMPAIGN MODE — successive phases; stops only on strong-crib break verdict.")
    print("Hardware stays busy. Metal --p1030680-bombe is NOT part of this ladder.")
    let skip = campaignSkipSet()
    if !skip.isEmpty {
        print("Skip tokens: \(skip.sorted().joined(separator: ", "))")
    }
    if CommandLine.arguments.contains("--include-aaaa") {
        print("Including rings AAAA in wide phases (--include-aaaa).")
    } else {
        print("Wide phases omit rings AAAA by default (prior msg-keys=1 sweep). Pass --include-aaaa to force.")
    }
    print("")

    let allPhases = campaignPhases()
    let start = campaignStartIndex(phases: allPhases)
    var ran = 0
    for index in start..<allPhases.count {
        let phase = allPhases[index]
        if shouldSkipCampaignPhase(phase, skip: skip) {
            print("── SKIP phase \(phase.name) (--skip) ──")
            print("")
            continue
        }
        ran += 1
        print("════════════════════════════════════════════════════════════")
        print("CAMPAIGN PHASE \(index + 1)/\(allPhases.count): \(phase.name)")
        print("════════════════════════════════════════════════════════════")
        let broken = runAttackPhase(phase, ciphertext: ciphertext)
        if broken {
            print("")
            print("*** CAMPAIGN HALTED — possible break in phase \(phase.name) ***")
            print("Next: verify Kenngruppen/Grund for indicators VROL NMKA (Girard method).")
            print("See BREAK_P1030680.md")
            return
        }
        print("")
    }

    if ran == 0 {
        print("CAMPAIGN: nothing to run (all phases skipped). Relax --skip / --from.")
        return
    }
    print("CAMPAIGN COMPLETE — no strong-crib break across \(ran) executed phase(s).")
    print("Next engineering: richer stecker search (SA / random restarts), broader rings, crib menus.")
    print("See BREAK_P1030680.md")
}

/// Runs one CO phase. Returns true if evaluateBreak declares a possible break.
@discardableResult
private func runAttackPhase(_ phase: AttackPhase, ciphertext: [Int]) -> Bool {
    let configs = phase.wheelOrders.count * phase.ringVariants.count * 4
    let climbs = configs * phase.msgKeyTopK
    print("Phase: \(phase.name)")
    print("  \(phase.rationale)")
    print(
        "  \(phase.wheelOrders.count) WO × 2 Greek × 2 UKW × \(phase.ringVariants.count) rings "
            + "× top-\(phase.msgKeyTopK) msg-keys ≈ \(climbs) stecker climbs"
    )

    let started = CFAbsoluteTimeGetCurrent()
    let candidates = M4ThetisAttack.crack(
        ciphertext: ciphertext,
        wheelOrders: phase.wheelOrders,
        ringVariants: phase.ringVariants,
        topK: phase.candidateTopK,
        msgKeyTopK: phase.msgKeyTopK,
        maxPlugs: 10
    ) { message in
        fputs("  \(message)\n", stderr)
    }
    let elapsed = CFAbsoluteTimeGetCurrent() - started
    print(String(format: "  Elapsed: %.1f s", elapsed))
    print("")
    print("Top candidates:")
    for (rank, row) in candidates.prefix(15).enumerated() {
        print(
            String(
                format: "  #%02d  score=%.3f IC=%.4f  UKW=%@ γ=%@ WO=%@ rings=%@ pos=%@",
                rank + 1,
                row.score,
                row.indexOfCoincidence,
                row.thinReflector as NSString,
                row.greek as NSString,
                row.wheelOrder as NSString,
                row.rings as NSString,
                row.positions as NSString
            )
        )
        print("       stecker: \(row.steckerPairs)")
        print("       plain:   \(row.plaintext)")
        print("")
    }

    let germanReference = EnigmaAlphabet.normalize(
        "VVVUUUVIRSOBENNULEINSXXMITUUUVIRSIBENNULZWOYVIRSIBENNULDREIYZWODREISECHSEINS"
    )
    print(
        String(
            format: "Calibration — known German %.2f, ciphertext %.2f",
            HostM4Bombe.germanLikeness(plaintext: germanReference),
            HostM4Bombe.germanLikeness(plaintext: ciphertext)
        )
    )

    guard let winner = candidates.first else {
        print("NO BREAK. Phase produced no candidates.")
        return false
    }
    let verdict = HostM4Bombe.evaluateBreak(plaintext: EnigmaAlphabet.normalize(winner.plaintext))
    print(
        String(
            format: "Best — likeness %.2f IC %.4f strong cribs: %@",
            verdict.likeness,
            verdict.indexOfCoincidence,
            (verdict.strongCribHits.isEmpty ? "(none)" : verdict.strongCribHits.joined(separator: ", "))
                as NSString
        )
    )
    print(verdict.reason)
    return verdict.isPossibleBreak
}

private func printCribDragReport(ciphertext: [Int]) {
    print("Step 0 — Crib-drag (indicators VROL NMKA ignored entirely)")
    let placements = M4CribDrag.dragAll(ciphertext: ciphertext)
    for placement in placements.sorted(by: { $0.eliminationRate > $1.eliminationRate }) {
        if placement.isImpossible {
            print(
                String(
                    format: "  %-26@ IMPOSSIBLE — no legal offset in this message",
                    placement.crib as NSString
                )
            )
        } else {
            print(
                String(
                    format: "  %-26@ %3d/%3d offsets survive (%.0f%% eliminated)",
                    placement.crib as NSString,
                    placement.offsets.count,
                    placement.totalOffsets,
                    placement.eliminationRate * 100
                )
            )
        }
    }
    print("")
}

private func printPotsdamNegativeControl(ciphertext: [Int]) {
    print("Step 1 — Potsdam 1 May 1945 negative control")
    let potsdam = EnigmaM4Key.potsdam1May1945(positions: (0, 0, 0, 0))
    let potsdamTop = HostM4Bombe.exhaustMessageKeys(ciphertext: ciphertext, dailyKey: potsdam, topK: 3)
    for (rank, row) in potsdamTop.enumerated() {
        print(
            String(
                format: "  #%d  pos=%@  IC=%.4f  preview=%@",
                rank + 1,
                row.positionsString as NSString,
                row.indexOfCoincidence,
                String(row.plaintext.prefix(40)) as NSString
            )
        )
    }
    print("")
}

private extension String {
    func leftPad(to width: Int, with pad: Character) -> String {
        if count >= width { return self }
        return String(repeating: pad, count: width - count) + self
    }
}
