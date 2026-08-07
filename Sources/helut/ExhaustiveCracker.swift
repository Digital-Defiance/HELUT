import Foundation
import Metal
import HELUTCore

// MARK: - Exhaustive M4 shell sweep + plugboard hill-climb (Gillogly / Ostwald-Weierud shape)
//
// Why this exists: rotor settings have NO fitness gradient. Mutating a wheel order or a
// ring letter scrambles the decrypt completely, so a GA over the shell is a random walk
// with extra steps. The plugboard *does* have a gradient, which is why hill-climbing it
// works. So: enumerate the shell exhaustively on the GPU, hill-climb only the stecker.
//
// Two degeneracies collapse the space 676× (verified against EnigmaM4Machine.step):
//   * The Greek wheel never steps, so only (greekPos − greekRing) matters → pin greekRing = A.
//   * The left rotor's notch drives nothing, so only (posL − ringL) matters → pin ringL = A.
// Published naval keys showing "AA.." in the first two ring letters are consistent with this.
//
// Phase 1 scores with IC, not bigrams: with the true rotors but no plugs the text is
// plugboard-scrambled, so bigram structure is destroyed while IC stays elevated.

private let sweepLaneCount = 26 * 26 * 26 // 17_576 L/M/R starts
private let sweepGreekWindows = 26
private let sweepThreadCount = sweepGreekWindows * sweepLaneCount // 456_976

private let icSweepMetalSource = """
#include <metal_stdlib>
using namespace metal;

inline uchar wire(uchar ch, uchar pos, uchar ring, constant uchar *table) {
    int off = (int(pos) - int(ring) + 26) % 26;
    return uchar((int(table[(int(ch) + off) % 26]) - off + 26) % 26);
}

kernel void m4_ic_sweep(
    device uchar const *ct [[buffer(0)]],
    constant uint &ctLen [[buffer(1)]],
    constant uchar *rings [[buffer(2)]],
    constant uchar *refl [[buffer(3)]],
    constant uchar *gFwd [[buffer(4)]],
    constant uchar *gInv [[buffer(5)]],
    constant uchar *lFwd [[buffer(6)]],
    constant uchar *lInv [[buffer(7)]],
    constant uchar *mFwd [[buffer(8)]],
    constant uchar *mInv [[buffer(9)]],
    constant uchar *rFwd [[buffer(10)]],
    constant uchar *rInv [[buffer(11)]],
    constant uchar *notchM [[buffer(12)]],
    constant uchar *notchR [[buffer(13)]],
    device float *outIC [[buffer(14)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= 456976u) return;

    uint lane = gid % 17576u;
    uchar posG = uchar(gid / 17576u);
    uchar posR = uchar(lane % 26u);
    uchar posM = uchar((lane / 26u) % 26u);
    uchar posL = uchar(lane / 676u);

    uchar rg = rings[0], rl = rings[1], rm = rings[2], rr = rings[3];

    uchar freq[26];
    for (uint i = 0; i < 26u; ++i) freq[i] = 0;

    for (uint t = 0; t < ctLen; ++t) {
        bool midNotch = notchM[posM] != 0;
        bool rightNotch = notchR[posR] != 0;
        if (midNotch) posL = uchar((uint(posL) + 1u) % 26u);
        if (midNotch || rightNotch) posM = uchar((uint(posM) + 1u) % 26u);
        posR = uchar((uint(posR) + 1u) % 26u);

        uchar x = ct[t];
        x = wire(x, posR, rr, rFwd);
        x = wire(x, posM, rm, mFwd);
        x = wire(x, posL, rl, lFwd);
        x = wire(x, posG, rg, gFwd);
        x = refl[x];
        x = wire(x, posG, rg, gInv);
        x = wire(x, posL, rl, lInv);
        x = wire(x, posM, rm, mInv);
        x = wire(x, posR, rr, rInv);
        freq[x] += 1;
    }

    float n = float(ctLen);
    float num = 0.0f;
    for (uint i = 0; i < 26u; ++i) {
        float c = float(freq[i]);
        num += c * (c - 1.0f);
    }
    outIC[gid] = num / (n * (n - 1.0f));
}
"""

/// One surviving rotor hypothesis from the IC sieve (plugboard still unknown).
struct ShellCandidate: Sendable {
    var ukwIndex: Int
    var greekIndex: Int
    var woIndex: Int
    var ringM: Int
    var ringR: Int
    var greekPos: Int
    var posL: Int
    var posM: Int
    var posR: Int
    var ic: Float
}

/// Fully-solved candidate after stecker hill-climb.
struct SolvedCandidate: Sendable {
    var shell: ShellCandidate
    var pairs: [[Int]]
    var bigram: Double
    var attackScore: Double
    var ic: Double
    var plaintext: String
}

final class M4ShellSweepEngine: @unchecked Sendable {
    private let device: MTLDevice?
    private let queue: MTLCommandQueue?
    private let pipeline: MTLComputePipelineState?
    private let ctBuffer: MTLBuffer?
    private let outBuffer: MTLBuffer?
    private let ciphertext: [Int]
    private let ctLen: Int
    let backendName: String

    private init(
        ciphertext: [Int],
        device: MTLDevice?,
        queue: MTLCommandQueue?,
        pipeline: MTLComputePipelineState?,
        backendName: String
    ) {
        self.ciphertext = ciphertext
        self.ctLen = ciphertext.count
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
        self.backendName = backendName
        if let device, pipeline != nil {
            var ctBytes = ciphertext.map { UInt8($0) }
            while ctBytes.count < 256 { ctBytes.append(0) }
            self.ctBuffer = device.makeBuffer(
                bytes: &ctBytes,
                length: ctBytes.count,
                options: .storageModeShared
            )
            self.outBuffer = device.makeBuffer(
                length: sweepThreadCount * MemoryLayout<Float>.stride,
                options: .storageModeShared
            )
        } else {
            self.ctBuffer = nil
            self.outBuffer = nil
        }
    }

    static func make(ciphertext: [Int]) -> M4ShellSweepEngine {
        if let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() {
            do {
                let library = try device.makeLibrary(source: icSweepMetalSource, options: nil)
                if let fn = library.makeFunction(name: "m4_ic_sweep") {
                    let pipeline = try device.makeComputePipelineState(function: fn)
                    return M4ShellSweepEngine(
                        ciphertext: ciphertext,
                        device: device,
                        queue: queue,
                        pipeline: pipeline,
                        backendName: "Metal-ic-sweep"
                    )
                }
            } catch {
                fputs("IC sweep Metal compile failed (\(error)); CPU sweep.\n", stderr)
            }
        }
        return M4ShellSweepEngine(
            ciphertext: ciphertext,
            device: nil,
            queue: nil,
            pipeline: nil,
            backendName: "CPU-ic-sweep"
        )
    }

    /// IC for all 26 Greek windows × 26³ L/M/R starts, zero plugs. Returns 456_976 floats.
    func sweep(key: EnigmaM4Key) -> UnsafeBufferPointer<Float> {
        if let out = metalSweep(key: key) {
            return out
        }
        return cpuSweep(key: key)
    }

    private var cpuScratch = [Float](repeating: 0, count: sweepThreadCount)

    private func metalSweep(key: EnigmaM4Key) -> UnsafeBufferPointer<Float>? {
        guard let device, let queue, let pipeline, let ctBuffer, let outBuffer else { return nil }
        let tables = SweepTables(key: key)
        var lenU = UInt32(ctLen)
        var rings: [UInt8] = [
            UInt8(key.rings.0), UInt8(key.rings.1), UInt8(key.rings.2), UInt8(key.rings.3)
        ]

        guard let command = queue.makeCommandBuffer(),
              let encoder = command.makeComputeCommandEncoder() else { return nil }

        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(ctBuffer, offset: 0, index: 0)
        encoder.setBytes(&lenU, length: 4, index: 1)
        encoder.setBytes(&rings, length: 4, index: 2)
        // setBytes (not makeBuffer) — these are 26-byte constants rebound every dispatch.
        tables.bind(encoder: encoder, firstIndex: 3)
        encoder.setBuffer(outBuffer, offset: 0, index: 14)

        let width = pipeline.maxTotalThreadsPerThreadgroup
        encoder.dispatchThreads(
            MTLSize(width: sweepThreadCount, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1)
        )
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()

        let ptr = outBuffer.contents().bindMemory(to: Float.self, capacity: sweepThreadCount)
        return UnsafeBufferPointer(start: ptr, count: sweepThreadCount)
    }

    private func cpuSweep(key: EnigmaM4Key) -> UnsafeBufferPointer<Float> {
        let ct = ciphertext
        cpuScratch.withUnsafeMutableBufferPointer { buf in
            let base = buf.baseAddress!
            DispatchQueue.concurrentPerform(iterations: sweepThreadCount) { gid in
                let lane = gid % sweepLaneCount
                var k = key
                k.positions = (gid / sweepLaneCount, lane / 676, (lane / 26) % 26, lane % 26)
                var machine = EnigmaM4Machine(key: k)
                var freq = [Int](repeating: 0, count: 26)
                for cipher in ct { freq[machine.process(cipher)] += 1 }
                let n = Double(ct.count)
                var num = 0.0
                for c in freq { num += Double(c * (c - 1)) }
                base[gid] = Float(num / (n * (n - 1)))
            }
        }
        return cpuScratch.withUnsafeBufferPointer { $0 }
    }
}

private struct SweepTables {
    let refl: [UInt8]
    let gFwd: [UInt8], gInv: [UInt8]
    let lFwd: [UInt8], lInv: [UInt8]
    let mFwd: [UInt8], mInv: [UInt8]
    let rFwd: [UInt8], rInv: [UInt8]
    let notchM: [UInt8], notchR: [UInt8]

    init(key: EnigmaM4Key) {
        refl = key.reflector.map { UInt8($0) }
        gFwd = key.greek.wiring.map { UInt8($0) }
        gInv = key.greek.inverse.map { UInt8($0) }
        lFwd = key.rotors.0.wiring.map { UInt8($0) }
        lInv = key.rotors.0.inverse.map { UInt8($0) }
        mFwd = key.rotors.1.wiring.map { UInt8($0) }
        mInv = key.rotors.1.inverse.map { UInt8($0) }
        rFwd = key.rotors.2.wiring.map { UInt8($0) }
        rInv = key.rotors.2.inverse.map { UInt8($0) }
        notchM = Self.mask(key.rotors.1)
        notchR = Self.mask(key.rotors.2)
    }

    func bind(encoder: MTLComputeCommandEncoder, firstIndex: Int) {
        let all = [refl, gFwd, gInv, lFwd, lInv, mFwd, mInv, rFwd, rInv, notchM, notchR]
        for (offset, table) in all.enumerated() {
            var copy = table
            encoder.setBytes(&copy, length: copy.count, index: firstIndex + offset)
        }
    }

    private static func mask(_ rotor: EnigmaRotorSpec) -> [UInt8] {
        var mask = [UInt8](repeating: 0, count: 26)
        for n in rotor.notches { mask[n] = 1 }
        return mask
    }
}

// MARK: - Bounded top-N collector

private struct TopN {
    private(set) var items: [ShellCandidate] = []
    private let limit: Int
    private(set) var cutoff: Float = -1

    init(limit: Int) {
        self.limit = limit
        items.reserveCapacity(limit * 2)
    }

    mutating func insert(_ candidate: ShellCandidate) {
        items.append(candidate)
        if items.count >= limit * 2 { compact() }
    }

    mutating func compact() {
        items.sort { $0.ic > $1.ic }
        if items.count > limit { items.removeLast(items.count - limit) }
        cutoff = items.last?.ic ?? -1
    }

    mutating func finish() -> [ShellCandidate] {
        compact()
        return items
    }
}

// MARK: - Cracker

enum ExhaustiveCracker {
    struct Config {
        var wheelOrders: [(EnigmaRotorSpec, EnigmaRotorSpec, EnigmaRotorSpec)] =
            M4ThetisAttack.allWheelOrders()
        var subspaceName = "full"
        /// Sweep the two rings that actually matter (middle, right). 676× the work.
        var sweepRings = false
        var survivors = 20_000
        var maxPlugs = 10
        var reportTop = 10
    }

    static let greeks: [EnigmaRotorSpec] = [EnigmaM4Warehouse.beta, EnigmaM4Warehouse.gamma]
    static let ukws: [[Int]] = [EnigmaM4Warehouse.thinB, EnigmaM4Warehouse.thinC]

    static func run(
        ciphertext: [Int],
        config: Config,
        progress: (String) -> Void
    ) -> [SolvedCandidate] {
        let engine = M4ShellSweepEngine.make(ciphertext: ciphertext)
        let ringPairs: [(Int, Int)] = config.sweepRings
            ? (0..<26).flatMap { m in (0..<26).map { r in (m, r) } }
            : [(0, 0)]

        let dispatches = ukws.count * greeks.count * config.wheelOrders.count * ringPairs.count
        let lanes = Double(dispatches) * Double(sweepThreadCount)
        progress("Phase 1 — exhaustive IC sieve (zero plugs)")
        progress("  backend=\(engine.backendName) subspace=\(config.subspaceName)")
        progress(
            "  shells=\(dispatches) × \(sweepThreadCount) lanes = "
                + String(format: "%.3g", lanes) + " decrypts"
        )
        progress("  greekRing/leftRing pinned to A (676× degeneracy removed)")

        var top = TopN(limit: config.survivors)
        let started = CFAbsoluteTimeGetCurrent()
        var done = 0

        for ukwIndex in ukws.indices {
            for greekIndex in greeks.indices {
                for woIndex in config.wheelOrders.indices {
                    for (ringM, ringR) in ringPairs {
                        let key = EnigmaM4Key(
                            greek: greeks[greekIndex],
                            rotors: config.wheelOrders[woIndex],
                            rings: (0, 0, ringM, ringR),
                            positions: (0, 0, 0, 0),
                            plugboard: Array(0..<26),
                            reflector: ukws[ukwIndex]
                        )
                        let out = engine.sweep(key: key)
                        let cutoff = top.cutoff
                        for gid in 0..<sweepThreadCount {
                            let ic = out[gid]
                            if ic <= cutoff { continue }
                            let lane = gid % sweepLaneCount
                            top.insert(
                                ShellCandidate(
                                    ukwIndex: ukwIndex,
                                    greekIndex: greekIndex,
                                    woIndex: woIndex,
                                    ringM: ringM,
                                    ringR: ringR,
                                    greekPos: gid / sweepLaneCount,
                                    posL: lane / 676,
                                    posM: (lane / 26) % 26,
                                    posR: lane % 26,
                                    ic: ic
                                )
                            )
                        }
                        done += 1
                        if done % 200 == 0 || done == dispatches {
                            let elapsed = CFAbsoluteTimeGetCurrent() - started
                            let rate = Double(done) * Double(sweepThreadCount) / max(elapsed, 1e-6)
                            let eta = (Double(dispatches - done) * Double(sweepThreadCount)) / max(rate, 1)
                            progress(
                                String(
                                    format: "  %d/%d shells  %.1fM decrypts/s  elapsed %.0fs  eta %.0fs  cutoffIC=%.4f",
                                    done, dispatches, rate / 1e6, elapsed, eta, max(top.cutoff, 0)
                                )
                            )
                        }
                    }
                }
            }
        }

        let survivors = top.finish()
        let sieveSeconds = CFAbsoluteTimeGetCurrent() - started
        progress(String(format: "Phase 1 done in %.1fs — %d survivors", sieveSeconds, survivors.count))
        if let best = survivors.first {
            progress(String(format: "  best sieve IC=%.4f", best.ic))
        }

        progress("Phase 2 — stecker hill-climb (bigram) on survivors")
        let solved = hillClimbAll(
            survivors: survivors,
            ciphertext: ciphertext,
            wheelOrders: config.wheelOrders,
            maxPlugs: config.maxPlugs
        )
        progress(String(format: "Phase 2 done — %d scored", solved.count))
        return Array(solved.prefix(max(config.reportTop, 1)))
    }

    private static func hillClimbAll(
        survivors: [ShellCandidate],
        ciphertext: [Int],
        wheelOrders: [(EnigmaRotorSpec, EnigmaRotorSpec, EnigmaRotorSpec)],
        maxPlugs: Int
    ) -> [SolvedCandidate] {
        guard !survivors.isEmpty else { return [] }
        let box = SolvedBox(count: survivors.count)
        DispatchQueue.concurrentPerform(iterations: survivors.count) { index in
            let shell = survivors[index]
            let key = EnigmaM4Key(
                greek: greeks[shell.greekIndex],
                rotors: wheelOrders[shell.woIndex],
                rings: (0, 0, shell.ringM, shell.ringR),
                positions: (shell.greekPos, shell.posL, shell.posM, shell.posR),
                plugboard: Array(0..<26),
                reflector: ukws[shell.ukwIndex]
            )
            let climbed = hillClimb(key: key, ciphertext: ciphertext, maxPlugs: maxPlugs)
            box.store(
                SolvedCandidate(
                    shell: shell,
                    pairs: climbed.pairs.map { [$0.0, $0.1] },
                    bigram: climbed.score,
                    attackScore: HostM4Bombe.attackScore(
                        plaintext: climbed.plain,
                        scorer: .germanMilitary()
                    ),
                    ic: LanguageScorer.indexOfCoincidence(climbed.plain),
                    plaintext: EnigmaAlphabet.string(from: climbed.plain)
                ),
                at: index
            )
        }
        return box.snapshot().sorted { $0.attackScore > $1.attackScore }
    }

    /// Greedy plug insertion then a replacement pass — the classic Enigma stecker climb.
    static func hillClimb(
        key: EnigmaM4Key,
        ciphertext: [Int],
        maxPlugs: Int
    ) -> (pairs: [(Int, Int)], score: Double, plain: [Int]) {
        var plain = [Int](repeating: 0, count: ciphertext.count)
        var pairs: [(Int, Int)] = []
        var used = [Bool](repeating: false, count: 26)

        func evaluate(_ candidate: [(Int, Int)]) -> Double {
            var table = Array(0..<26)
            for pair in candidate {
                table[pair.0] = pair.1
                table[pair.1] = pair.0
            }
            let working = EnigmaM4Key(
                greek: key.greek,
                rotors: key.rotors,
                rings: key.rings,
                positions: key.positions,
                plugboard: table,
                reflector: key.reflector
            )
            var machine = EnigmaM4Machine(key: working)
            for index in ciphertext.indices { plain[index] = machine.process(ciphertext[index]) }
            return LanguageScorer.bigramScore(plain)
        }

        var best = evaluate(pairs)

        while pairs.count < maxPlugs {
            var bestPair: (Int, Int)?
            var bestScore = best
            for a in 0..<26 where !used[a] {
                for b in (a + 1)..<26 where !used[b] {
                    let score = evaluate(pairs + [(a, b)])
                    if score > bestScore {
                        bestScore = score
                        bestPair = (a, b)
                    }
                }
            }
            guard let pair = bestPair else { break }
            pairs.append(pair)
            used[pair.0] = true
            used[pair.1] = true
            best = bestScore
        }

        // Replacement pass: pull each plug and see if a different partner scores better.
        for index in pairs.indices {
            let original = pairs[index]
            used[original.0] = false
            used[original.1] = false
            var rest = pairs
            rest.remove(at: index)
            var bestPair = original
            var bestScore = best
            for a in 0..<26 where !used[a] {
                for b in (a + 1)..<26 where !used[b] {
                    let score = evaluate(rest + [(a, b)])
                    if score > bestScore {
                        bestScore = score
                        bestPair = (a, b)
                    }
                }
            }
            pairs[index] = bestPair
            used[bestPair.0] = true
            used[bestPair.1] = true
            best = bestScore
        }

        _ = evaluate(pairs)
        return (pairs, best, plain)
    }
}

private final class SolvedBox: @unchecked Sendable {
    private let lock = NSLock()
    private var slots: [SolvedCandidate?]

    init(count: Int) { slots = [SolvedCandidate?](repeating: nil, count: count) }

    func store(_ value: SolvedCandidate, at index: Int) {
        lock.lock()
        slots[index] = value
        lock.unlock()
    }

    func snapshot() -> [SolvedCandidate] {
        lock.lock()
        defer { lock.unlock() }
        return slots.compactMap { $0 }
    }
}

// MARK: - Self-test against a message whose key is known

/// U534 P1030684 (Potsdam, 1 May 1945) — broken, published key. Truncated to P1030680's
/// length it is an exact-difficulty rehearsal: if the pipeline cannot recover a *known*
/// key from 72 ciphertext-only letters, it cannot break Thetis either.
func runExhaustiveSelfTest() {
    let fullCiphertext = EnigmaAlphabet.normalize(
        "RFBYWKIKELDCHBSXUNFJFSNRRVFWASXYLQCQFADYJXNTBMVLRDCGULOWHTBGWUSSOQHGAYED"
            + "KMJDNGVZNZFOXFKMIBKQNXFDWFIVGCYMJVQCKYQFBHYKZSCJ"
    )
    let length = intFlag("--selftest-len") ?? EnigmaAlphabet.normalize(
        U534MessageP1030680.ciphertext
    ).count
    let ct = Array(fullCiphertext.prefix(length))

    let truth = EnigmaM4Key.positions(fromLetters: "VYAA")
    let trueGid = truth.0 * sweepLaneCount + truth.1 * 676 + truth.2 * 26 + truth.3

    print("HELUT — exhaustive cracker self-test (known key)")
    print("Control message: U534 P1030684, Potsdam 1 May 1945 (published key)")
    print("Truth: UKW B, gamma, IV-III-VIII, rings AACU, message key VYAA, 10 plugs")
    print("Using first \(ct.count) letters — same length as P1030680\n")

    var withPlugs = EnigmaM4Machine(key: EnigmaM4Key.potsdam1May1945(positions: truth))
    let reference = withPlugs.processText(ct)
    print("Reference plaintext (true key, true plugs):")
    print("  \(EnigmaAlphabet.string(from: reference))")
    print(String(format: "  bigram=%.4f IC=%.4f\n",
                 LanguageScorer.bigramScore(reference),
                 LanguageScorer.indexOfCoincidence(reference)))

    let engine = M4ShellSweepEngine.make(ciphertext: ct)
    print("Backend: \(engine.backendName)\n")

    // Level 1 — correct daily key, zero plugs: can IC alone find the message key?
    let dailyNoPlugs = EnigmaM4Key(
        greek: EnigmaM4Warehouse.gamma,
        rotors: (EnigmaWarehouse.rotorIV, EnigmaWarehouse.rotorIII, EnigmaWarehouse.rotorVIII),
        rings: EnigmaM4Key.rings(fromLetters: "AACU"),
        positions: (0, 0, 0, 0),
        plugboard: Array(0..<26),
        reflector: EnigmaM4Warehouse.thinB
    )
    let level1 = engine.sweep(key: dailyNoPlugs)
    let trueIC = level1[trueGid]
    var better = 0
    for gid in 0..<sweepThreadCount where level1[gid] > trueIC { better += 1 }
    print("Level 1 — correct wheels/rings, plugs unknown, sieve = IC over 26^4 message keys")
    print(String(format: "  true key IC = %.4f", trueIC))
    print("  rank = \(better + 1) of \(sweepThreadCount)")
    print(String(format: "  percentile = top %.3f%%\n",
                 100.0 * Double(better + 1) / Double(sweepThreadCount)))

    // Level 2 — can the stecker climb recover German once the rotors are right?
    let climbed = ExhaustiveCracker.hillClimb(
        key: EnigmaM4Key(
            greek: EnigmaM4Warehouse.gamma,
            rotors: (EnigmaWarehouse.rotorIV, EnigmaWarehouse.rotorIII, EnigmaWarehouse.rotorVIII),
            rings: EnigmaM4Key.rings(fromLetters: "AACU"),
            positions: truth,
            plugboard: Array(0..<26),
            reflector: EnigmaM4Warehouse.thinB
        ),
        ciphertext: ct,
        maxPlugs: intFlag("--exhaust-plugs") ?? 10
    )
    let recovered = EnigmaAlphabet.string(from: climbed.plain)
    let expected = EnigmaAlphabet.string(from: reference)
    var matches = 0
    for (a, b) in zip(recovered, expected) where a == b { matches += 1 }
    print("Level 2 — stecker hill-climb from the TRUE rotor setting")
    print("  recovered: \(recovered)")
    print(String(format: "  letters correct: %d/%d (%.0f%%)",
                 matches, expected.count, 100.0 * Double(matches) / Double(expected.count)))
    print(String(format: "  bigram=%.4f (true plugs: %.4f)",
                 climbed.score, LanguageScorer.bigramScore(reference)))
    let foundPlugs = Set(climbed.pairs.map { Set([$0.0, $0.1]) })
    let truePlugs: Set<Set<Int>> = Set(
        [("C", "H"), ("E", "J"), ("N", "V"), ("O", "U"), ("T", "Y"),
         ("L", "G"), ("S", "Z"), ("P", "K"), ("D", "I"), ("Q", "B")]
            .map { Set([EnigmaAlphabet.index(Character($0.0)), EnigmaAlphabet.index(Character($0.1))]) }
    )
    print("  plugs recovered: \(foundPlugs.intersection(truePlugs).count)/10 correct, "
        + "\(climbed.pairs.count) proposed\n")

    // Level 3 — null distribution: what does the machine claim on the true rotors' rivals?
    print("Level 3 — verdict on the recovered text")
    let verdict = HostM4Bombe.evaluateBreak(plaintext: climbed.plain)
    print(String(format: "  likeness=%.2f IC=%.4f cribs=%@",
                 verdict.likeness,
                 verdict.indexOfCoincidence,
                 (verdict.strongCribHits.isEmpty
                    ? "(none)" : verdict.strongCribHits.joined(separator: ", ")) as NSString))
    print("  \(verdict.reason)")
    print("")
    print("Read this as the ceiling: P1030680 cannot do better than this rehearsal.")
}

// MARK: - CLI entry

func runExhaustiveCracker() {
    print("HELUT — exhaustive M4 cracker (P1030680)")
    print("Ciphertext: \(U534MessageP1030680.ciphertext)")
    print("Shell enumerated on GPU (no gradient to evolve); stecker hill-climbed (gradient exists).")
    print("")

    let ct = EnigmaAlphabet.normalize(U534MessageP1030680.ciphertext)
    var config = ExhaustiveCracker.Config()

    if let name = stringFlag("--subspace") {
        let space = M4ThetisAttack.subspace(named: name)
        config.wheelOrders = space.wheelOrders
        config.subspaceName = space.name
    }
    if CommandLine.arguments.contains("--exhaust-rings") { config.sweepRings = true }
    if CommandLine.arguments.contains("--quick") {
        config.wheelOrders = Array(config.wheelOrders.prefix(12))
        config.subspaceName += "(quick-12)"
        config.survivors = 2_000
    }
    if let n = intFlag("--exhaust-top") { config.survivors = n }
    if let n = intFlag("--exhaust-plugs") { config.maxPlugs = n }

    let started = CFAbsoluteTimeGetCurrent()
    let results = ExhaustiveCracker.run(ciphertext: ct, config: config) { message in
        fputs(message + "\n", stderr)
    }
    let elapsed = CFAbsoluteTimeGetCurrent() - started

    print("")
    print(String(format: "Elapsed: %.1f s", elapsed))
    print("")

    for (rank, candidate) in results.enumerated() {
        let wo = config.wheelOrders[candidate.shell.woIndex]
        let ukw = candidate.shell.ukwIndex == 0 ? "B" : "C"
        let greek = candidate.shell.greekIndex == 0 ? "beta" : "gamma"
        let rings = EnigmaAlphabet.string(from: [0, 0, candidate.shell.ringM, candidate.shell.ringR])
        let positions = EnigmaAlphabet.string(from: [
            candidate.shell.greekPos, candidate.shell.posL, candidate.shell.posM, candidate.shell.posR
        ])
        let plugs = candidate.pairs.isEmpty
            ? "(none)"
            : candidate.pairs
                .map { "\(EnigmaAlphabet.character($0[0]))\(EnigmaAlphabet.character($0[1]))" }
                .joined(separator: " ")
        print(
            String(
                format: "#%02d score=%.4f bigram=%.4f IC=%.4f  UKW%@ %@ %@-%@-%@ rings=%@ pos=%@",
                rank + 1,
                candidate.attackScore,
                candidate.bigram,
                candidate.ic,
                ukw as NSString,
                greek as NSString,
                wo.0.name as NSString,
                wo.1.name as NSString,
                wo.2.name as NSString,
                rings as NSString,
                positions as NSString
            )
        )
        print("    stecker: \(plugs)")
        print("    plain:   \(candidate.plaintext)")
        let verdict = HostM4Bombe.evaluateBreak(
            plaintext: EnigmaAlphabet.normalize(candidate.plaintext)
        )
        print(
            String(
                format: "    verdict: likeness=%.2f cribs=%@",
                verdict.likeness,
                (verdict.strongCribHits.isEmpty
                    ? "(none)"
                    : verdict.strongCribHits.joined(separator: ", ")) as NSString
            )
        )
        if verdict.isPossibleBreak {
            print("    *** POSSIBLE BREAK *** \(verdict.reason)")
        }
    }
    print("")
    print("See ASIC_CRACKER.md")
}
