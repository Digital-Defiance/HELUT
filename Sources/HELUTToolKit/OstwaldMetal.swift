import Foundation
import Metal
import HELUTCore
import HELUTCLI

// MARK: - Metal Ostwald plugboard scoring
//
// Welchman enumerates *settings* (456,976 lanes × shells). Ostwald enumerates *plugboards*
// on a locked shell: each greedy round is C(unused, 2) 72-letter decrypts. Those trials are
// independent, so they belong in one dispatch — and with 64 GB unified memory the cap is
// the GPU grid, not RAM.
//
// Default budget is 48 GB of 32-byte trial records (~1.61×10⁹ plugboards / dispatch) on
// Turing's 64 GB unified pool, leaving ~16 GB for the rest of HELUT. `--ostwald-memory-gb`
// overrides it. That cap is not the 4-plug limiter: a streamed climb is host-capped at
// `OstwaldExhaust.fourPlugWaveJobsCap` (524,288 jobs, ~2.6 GB in round 1) because packing
// tens of millions of Swift trial objects was slower than the kernel, and polishing every
// ghost on CPU after an 8,192-job wave was the live 2.0M/s wall. Greedy still has sequential
// rounds, but every live climb in the wave shares the round. Replacement polish runs only
// on the top scores in the wave.

package enum OstwaldScoreMode: UInt32, Sendable {
    case ic = 0
    case bigram = 1
    case trigram = 2
}

/// Packed trial: 4 position bytes, 26-byte plugboard, 1 hole count, 1 pad = 32 bytes.
package struct OstwaldTrial {
    package var posG: UInt8
    package var posL: UInt8
    package var posM: UInt8
    package var posR: UInt8
    package var plug: [UInt8]
    package var leadingHoles: UInt8

    package static let stride = 32

    package init(
        positions: (Int, Int, Int, Int),
        plugboard: [Int],
        leadingHoles: Int
    ) {
        posG = UInt8(positions.0)
        posL = UInt8(positions.1)
        posM = UInt8(positions.2)
        posR = UInt8(positions.3)
        var packed = [UInt8](repeating: 0, count: 26)
        for index in 0..<26 {
            packed[index] = UInt8(plugboard[index])
        }
        plug = packed
        self.leadingHoles = UInt8(min(max(leadingHoles, 0), 255))
    }

    fileprivate static func pack(
        to bytes: UnsafeMutablePointer<UInt8>,
        at trial: Int,
        posG: UInt8,
        posL: UInt8,
        posM: UInt8,
        posR: UInt8,
        plug: UnsafePointer<UInt8>,
        leadingHoles: UInt8
    ) {
        let base = trial * stride
        bytes[base] = posG
        bytes[base + 1] = posL
        bytes[base + 2] = posM
        bytes[base + 3] = posR
        (bytes + base + 4).update(from: plug, count: 26)
        bytes[base + 30] = leadingHoles
        bytes[base + 31] = 0
    }

    fileprivate func write(to bytes: UnsafeMutablePointer<UInt8>, at trial: Int) {
        plug.withUnsafeBufferPointer { buffer in
            guard let plugBytes = buffer.baseAddress else { return }
            OstwaldTrial.pack(
                to: bytes, at: trial,
                posG: posG, posL: posL, posM: posM, posR: posR,
                plug: plugBytes, leadingHoles: leadingHoles
            )
        }
    }
}

/// Welchman-shaped ETA: an a-priori floor at a named rate, then live elapsed/rate/ETA.
package enum OstwaldProgress {
    /// Optimistic CPU decrypt floor. Phase 62 cleared ~50 seeded climbs in <1 s.
    package static let cpuDecryptFloorPerSecond = 40_000.0
    /// Optimistic fat-dispatch Metal floor. Live lines replace this with the measured rate.
    package static let metalDecryptFloorPerSecond = 10_000_000.0

    package static func unusedPairCount(placed: Int) -> Int {
        let unused = 26 - 2 * max(0, placed)
        guard unused >= 2 else { return 0 }
        return unused * (unused - 1) / 2
    }

    /// Metal greedy insertion only (no CPU replacement). Seeded 4 → 503 decrypts.
    package static func greedyInsertDecrypts(seeded: Int, maxPlugs: Int = 10) -> Int {
        var total = 0
        var placed = max(0, seeded)
        while placed < maxPlugs {
            let extras = unusedPairCount(placed: placed)
            guard extras > 0 else { break }
            total += extras
            placed += 1
        }
        return total
    }

    package static func greedyDecrypts(seeded: Int, maxPlugs: Int = 10, beamWidth: Int = 1) -> Int {
        var total = greedyInsertDecrypts(seeded: seeded, maxPlugs: maxPlugs)
        let nonSeeded = max(0, maxPlugs - max(0, seeded))
        let unusedDuringReplace = 26 - 2 * maxPlugs + 2
        if unusedDuringReplace >= 2 {
            total += nonSeeded * unusedDuringReplace * (unusedDuringReplace - 1) / 2
        }
        return total * max(1, beamWidth)
    }

    package static func rateLabel(_ perSecond: Double) -> String {
        if perSecond >= 1_000_000 {
            return String(format: "%.0fM decrypts/s", perSecond / 1_000_000)
        }
        if perSecond >= 1_000 {
            return String(format: "%.0fk decrypts/s", perSecond / 1_000)
        }
        return String(format: "%.0f decrypts/s", perSecond)
    }

    /// Same shape as Welchman's `ETA floor (~50M/s): 69.2 min`.
    package static func floorLine(decrypts: Int, perSecond: Double) -> String {
        let eta = Double(max(decrypts, 0)) / max(perSecond, 1)
        return String(format: "ETA floor (~%@): %.1f min", rateLabel(perSecond), eta / 60)
    }

    /// Same shape as Welchman's live `1227s  42.3M/s ETA  61.3 min`.
    package static func liveLine(
        elapsed: TimeInterval,
        decryptsDone: Int,
        decryptsTotal: Int
    ) -> String {
        let rate = elapsed > 0 ? Double(decryptsDone) / elapsed : 0
        let remaining = max(0, decryptsTotal - decryptsDone)
        let eta = rate > 0 ? Double(remaining) / rate : 0
        let rateText: String
        if rate >= 1_000_000 {
            rateText = String(format: "%5.1fM/s", rate / 1_000_000)
        } else {
            rateText = String(format: "%5.1fk/s", rate / 1_000)
        }
        return String(format: "%6.0fs %@ ETA %5.1f min", elapsed, rateText, eta / 60)
    }

    /// Round banner. Do not use `String(format: "%d")` for `decryptsDone` —
    /// `%d` is Int32 and wraps negative past 2,147,483,647. Interpolation keeps Int64.
    package static func roundLine(round: Int, active: Int, decryptsDone: Int, live: String) -> String {
        "  [round \(round) · \(active) climbs live · \(decryptsDone) decrypts] \(live)"
    }
}

package enum OstwaldMemory {
    /// Default slice of Turing's 64 GB unified pool for trial + score buffers.
    package static let defaultBudgetGigabytes = 48
    package static let defaultBudgetBytes = defaultBudgetGigabytes * 1024 * 1024 * 1024

    package static func maxTrials(budgetBytes: Int) -> Int {
        max(1, budgetBytes / OstwaldTrial.stride)
    }
}

private let ostwaldMetalSource = """
#include <metal_stdlib>
using namespace metal;

inline uchar wire(uchar ch, uchar pos, uchar ring, constant uchar *table) {
    int off = (int(pos) - int(ring) + 26) % 26;
    return uchar((int(table[(int(ch) + off) % 26]) - off + 26) % 26);
}

inline void step(thread uchar &posL, thread uchar &posM, thread uchar &posR,
                 constant uchar *notchM, constant uchar *notchR) {
    bool midNotch = notchM[posM] != 0;
    bool rightNotch = notchR[posR] != 0;
    if (midNotch) posL = uchar((uint(posL) + 1u) % 26u);
    if (midNotch || rightNotch) posM = uchar((uint(posM) + 1u) % 26u);
    posR = uchar((uint(posR) + 1u) % 26u);
}

kernel void m4_ostwald_score(
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
    device uchar const *trials [[buffer(14)]],
    constant uint &trialCount [[buffer(15)]],
    constant uint &scoreMode [[buffer(16)]],
    device float const *bigram [[buffer(17)]],
    device float const *trigram [[buffer(18)]],
    device float *out [[buffer(19)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= trialCount) return;
    uint base = gid * 32u;
    uchar posG = trials[base + 0];
    uchar posL = trials[base + 1];
    uchar posM = trials[base + 2];
    uchar posR = trials[base + 3];
    uchar plug[26];
    for (uint i = 0; i < 26u; ++i) plug[i] = trials[base + 4u + i];
    uint holes = uint(trials[base + 30]);
    uchar rg = rings[0], rl = rings[1], rm = rings[2], rr = rings[3];

    for (uint t = 0; t < holes; ++t) {
        step(posL, posM, posR, notchM, notchR);
    }

    uint freq[26];
    for (uint i = 0; i < 26u; ++i) freq[i] = 0;
    float ngram = 0.0f;
    uchar prev1 = 0, prev2 = 0;

    for (uint t = 0; t < ctLen; ++t) {
        step(posL, posM, posR, notchM, notchR);
        uchar x = plug[ct[t]];
        x = wire(x, posR, rr, rFwd);
        x = wire(x, posM, rm, mFwd);
        x = wire(x, posL, rl, lFwd);
        x = wire(x, posG, rg, gFwd);
        x = refl[x];
        x = wire(x, posG, rg, gInv);
        x = wire(x, posL, rl, lInv);
        x = wire(x, posM, rm, mInv);
        x = wire(x, posR, rr, rInv);
        x = plug[x];
        freq[x] += 1u;
        if (scoreMode == 1u && t >= 1u) {
            ngram += bigram[uint(prev1) * 26u + uint(x)];
        } else if (scoreMode == 2u && t >= 2u) {
            ngram += trigram[uint(prev2) * 676u + uint(prev1) * 26u + uint(x)];
        }
        prev2 = prev1;
        prev1 = x;
    }

    if (scoreMode == 0u) {
        float n = float(ctLen);
        float num = 0.0f;
        for (uint i = 0; i < 26u; ++i) {
            float c = float(freq[i]);
            num += c * (c - 1.0f);
        }
        out[gid] = n > 1.0f ? num / (n * (n - 1.0f)) : 0.0f;
    } else if (scoreMode == 1u) {
        out[gid] = ctLen > 1u ? ngram / float(ctLen - 1u) : -10.0f;
    } else {
        out[gid] = ctLen > 2u ? ngram / float(ctLen - 2u) : -10.0f;
    }
}
"""

package final class OstwaldMetalEngine: @unchecked Sendable {
    package let backendName: String
    package let maxTrials: Int
    private let device: MTLDevice?
    private let queue: MTLCommandQueue?
    private let pipeline: MTLComputePipelineState?
    private let key: EnigmaM4Key
    private let ciphertext: [Int]
    private let ctBuffer: MTLBuffer?
    private let bigramBuffer: MTLBuffer?
    private let trigramBuffer: MTLBuffer?
    private var trialBuffer: MTLBuffer?
    private var outBuffer: MTLBuffer?
    private let tables: OstwaldMetalTables

    private init(
        key: EnigmaM4Key,
        ciphertext: [Int],
        device: MTLDevice?,
        queue: MTLCommandQueue?,
        pipeline: MTLComputePipelineState?,
        backendName: String,
        maxTrials: Int
    ) {
        self.key = key
        self.ciphertext = ciphertext
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
        self.backendName = backendName
        self.maxTrials = max(1, maxTrials)
        self.tables = OstwaldMetalTables(key: key)
        if let device, pipeline != nil {
            var ctBytes = ciphertext.map { UInt8(clamping: $0) }
            if ctBytes.isEmpty { ctBytes = [0] }
            self.ctBuffer = device.makeBuffer(
                bytes: &ctBytes, length: ctBytes.count, options: .storageModeShared
            )
            var bigram = LanguageScorer.germanBigramLogProbs.map { Float($0) }
            self.bigramBuffer = device.makeBuffer(
                bytes: &bigram, length: bigram.count * MemoryLayout<Float>.stride,
                options: .storageModeShared
            )
            var trigram = (GermanTrigrams.logProbs ?? [Double](repeating: 0, count: 17_576))
                .map { Float($0) }
            self.trigramBuffer = device.makeBuffer(
                bytes: &trigram, length: trigram.count * MemoryLayout<Float>.stride,
                options: .storageModeShared
            )
        } else {
            self.ctBuffer = nil
            self.bigramBuffer = nil
            self.trigramBuffer = nil
        }
    }

    package static func make(
        key: EnigmaM4Key,
        ciphertext: [Int],
        budgetBytes: Int = OstwaldMemory.defaultBudgetBytes
    ) -> OstwaldMetalEngine? {
        let maxTrials = OstwaldMemory.maxTrials(budgetBytes: budgetBytes)
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            return nil
        }
        do {
            let library = try device.makeLibrary(source: ostwaldMetalSource, options: nil)
            guard let fn = library.makeFunction(name: "m4_ostwald_score") else { return nil }
            let pipeline = try device.makeComputePipelineState(function: fn)
            return OstwaldMetalEngine(
                key: key, ciphertext: ciphertext, device: device, queue: queue,
                pipeline: pipeline, backendName: "Metal-ostwald-score", maxTrials: maxTrials
            )
        } catch {
            fputs("Ostwald Metal compile failed (\(error)); CPU climb.\n", stderr)
            return nil
        }
    }

    package func scores(
        plugTables: [[Int]],
        mode: OstwaldScoreMode,
        walk: OstwaldWalk
    ) -> [Float] {
        let trials = plugTables.map {
            OstwaldTrial(positions: key.positions, plugboard: $0, leadingHoles: walk.leadingHoles)
        }
        return scores(trials: trials, mode: mode)
    }

    package func scores(trials: [OstwaldTrial], mode: OstwaldScoreMode) -> [Float] {
        if trials.isEmpty { return [] }
        return scoresPacked(count: trials.count, mode: mode) { bytes in
            for (index, trial) in trials.enumerated() { trial.write(to: bytes, at: index) }
        }
    }

    /// Fill `count` 32-byte trial records in place, then score. Avoids a Swift
    /// `[OstwaldTrial]` (each of which heap-allocates a 26-byte plugboard).
    package func scoresPacked(
        count: Int,
        mode: OstwaldScoreMode,
        fill: (UnsafeMutablePointer<UInt8>) -> Void
    ) -> [Float] {
        if count <= 0 { return [] }
        let stride = OstwaldTrial.stride
        if pipeline == nil || device == nil || queue == nil {
            let host = UnsafeMutablePointer<UInt8>.allocate(capacity: count * stride)
            defer { host.deallocate() }
            fill(host)
            return cpuScoresPacked(bytes: UnsafePointer(host), count: count, mode: mode)
        }
        if count <= maxTrials {
            ensureCapacity(count)
            guard let trialBuffer else {
                let host = UnsafeMutablePointer<UInt8>.allocate(capacity: count * stride)
                defer { host.deallocate() }
                fill(host)
                return cpuScoresPacked(bytes: UnsafePointer(host), count: count, mode: mode)
            }
            let dest = trialBuffer.contents().bindMemory(to: UInt8.self, capacity: count * stride)
            fill(dest)
            return metalDispatch(count: count, mode: mode)
                ?? cpuScoresPacked(bytes: UnsafePointer(dest), count: count, mode: mode)
        }
        let host = UnsafeMutablePointer<UInt8>.allocate(capacity: count * stride)
        defer { host.deallocate() }
        fill(host)
        var out = [Float](repeating: 0, count: count)
        var offset = 0
        while offset < count {
            let chunk = min(maxTrials, count - offset)
            ensureCapacity(chunk)
            guard let trialBuffer else {
                let slice = cpuScoresPacked(
                    bytes: UnsafePointer(host + offset * stride), count: chunk, mode: mode
                )
                for index in slice.indices { out[offset + index] = slice[index] }
                offset += chunk
                continue
            }
            let dest = trialBuffer.contents().bindMemory(to: UInt8.self, capacity: chunk * stride)
            dest.update(from: host + offset * stride, count: chunk * stride)
            let scored = metalDispatch(count: chunk, mode: mode)
                ?? cpuScoresPacked(bytes: UnsafePointer(dest), count: chunk, mode: mode)
            for index in scored.indices { out[offset + index] = scored[index] }
            offset += chunk
        }
        return out
    }

    package func cpuScores(trials: [OstwaldTrial], mode: OstwaldScoreMode) -> [Float] {
        trials.map { trial in
            let plug = trial.plug.map { Int($0) }
            let walk = OstwaldWalk.leadingGap(Int(trial.leadingHoles))
            let positions = (Int(trial.posG), Int(trial.posL), Int(trial.posM), Int(trial.posR))
            let working = EnigmaM4Key(
                greek: key.greek, rotors: key.rotors, rings: key.rings,
                positions: positions, plugboard: plug, reflector: key.reflector
            )
            let plain = OstwaldCurve.decrypt(
                key: working, ciphertext: ciphertext, plugboard: plug, walk: walk
            )
            switch mode {
            case .ic: return Float(LanguageScorer.indexOfCoincidence(plain))
            case .bigram: return Float(LanguageScorer.bigramScore(plain))
            case .trigram: return Float(GermanTrigrams.score(plain))
            }
        }
    }

    private func cpuScoresPacked(
        bytes: UnsafePointer<UInt8>,
        count: Int,
        mode: OstwaldScoreMode
    ) -> [Float] {
        (0..<count).map { index in
            let base = index * OstwaldTrial.stride
            let plug = (0..<26).map { Int(bytes[base + 4 + $0]) }
            let walk = OstwaldWalk.leadingGap(Int(bytes[base + 30]))
            let positions = (
                Int(bytes[base]), Int(bytes[base + 1]),
                Int(bytes[base + 2]), Int(bytes[base + 3])
            )
            let working = EnigmaM4Key(
                greek: key.greek, rotors: key.rotors, rings: key.rings,
                positions: positions, plugboard: plug, reflector: key.reflector
            )
            let plain = OstwaldCurve.decrypt(
                key: working, ciphertext: ciphertext, plugboard: plug, walk: walk
            )
            switch mode {
            case .ic: return Float(LanguageScorer.indexOfCoincidence(plain))
            case .bigram: return Float(LanguageScorer.bigramScore(plain))
            case .trigram: return Float(GermanTrigrams.score(plain))
            }
        }
    }

    /// Trial buffer must already hold `count` packed records.
    private func metalDispatch(count: Int, mode: OstwaldScoreMode) -> [Float]? {
        guard device != nil, let queue, let pipeline,
              let ctBuffer, let bigramBuffer, let trigramBuffer,
              let trialBuffer, let outBuffer,
              let command = queue.makeCommandBuffer(),
              let encoder = command.makeComputeCommandEncoder() else { return nil }

        var ctLen = UInt32(ciphertext.count)
        var trialCount = UInt32(count)
        var scoreMode = mode.rawValue
        var rings: [UInt8] = [
            UInt8(key.rings.0), UInt8(key.rings.1),
            UInt8(key.rings.2), UInt8(key.rings.3)
        ]

        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(ctBuffer, offset: 0, index: 0)
        encoder.setBytes(&ctLen, length: MemoryLayout<UInt32>.stride, index: 1)
        encoder.setBytes(&rings, length: 4, index: 2)
        tables.bind(encoder: encoder, firstIndex: 3)
        encoder.setBuffer(trialBuffer, offset: 0, index: 14)
        encoder.setBytes(&trialCount, length: MemoryLayout<UInt32>.stride, index: 15)
        encoder.setBytes(&scoreMode, length: MemoryLayout<UInt32>.stride, index: 16)
        encoder.setBuffer(bigramBuffer, offset: 0, index: 17)
        encoder.setBuffer(trigramBuffer, offset: 0, index: 18)
        encoder.setBuffer(outBuffer, offset: 0, index: 19)

        let width = max(1, pipeline.threadExecutionWidth)
        let threads = MTLSize(width: count, height: 1, depth: 1)
        let group = MTLSize(width: width, height: 1, depth: 1)
        encoder.dispatchThreads(threads, threadsPerThreadgroup: group)
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()

        let raw = outBuffer.contents().bindMemory(to: Float.self, capacity: count)
        return Array(UnsafeBufferPointer(start: raw, count: count))
    }

    private func ensureCapacity(_ count: Int) {
        guard let device else { return }
        let bytes = count * OstwaldTrial.stride
        if trialBuffer == nil || (trialBuffer?.length ?? 0) < bytes {
            trialBuffer = device.makeBuffer(length: bytes, options: .storageModeShared)
            outBuffer = device.makeBuffer(
                length: count * MemoryLayout<Float>.stride, options: .storageModeShared
            )
        }
    }
}

private struct OstwaldMetalTables {
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
        for notch in rotor.notches { mask[notch] = 1 }
        return mask
    }
}

// MARK: - Parallel wave climb (many Ostwalds, one greedy round)

package struct OstwaldClimbJob {
    package var candidateIndex: Int
    package var key: EnigmaM4Key
    package var pairs: [(Int, Int)]
    package var seededCount: Int
    package var walk: OstwaldWalk
    package var maxPlugs: Int
    package var stuck: Bool
    package var score: Double
    package var plain: [Int]

    package init(
        candidateIndex: Int,
        key: EnigmaM4Key,
        pairs: [(Int, Int)],
        seededCount: Int,
        walk: OstwaldWalk,
        maxPlugs: Int = 10
    ) {
        self.candidateIndex = candidateIndex
        self.key = key
        self.pairs = pairs
        self.seededCount = seededCount
        self.walk = walk
        self.maxPlugs = maxPlugs
        self.stuck = false
        self.score = -.infinity
        self.plain = []
    }
}

package enum OstwaldWave {
    /// Greedy-insert every job in lockstep. One Metal dispatch per (shell, placed-count)
    /// group. Trials are packed straight into the unified buffer — no `[OstwaldTrial]`
    /// of heap plugboards. Returns decrypts actually scored (for the live ETA).
    package static func greedyRound(
        jobs: inout [OstwaldClimbJob],
        ciphertext: [Int],
        scorer: ClimbScorer,
        engineFor: (OstwaldClimbJob) -> OstwaldMetalEngine?,
        decryptsDone: inout Int,
        ranker: OstwaldRanker.Model? = nil
    ) {
        var groups: [String: [Int]] = [:]
        for (index, job) in jobs.enumerated() {
            guard !job.stuck, job.pairs.count < job.maxPlugs else { continue }
            groups[shellKey(job), default: []].append(index)
        }
        let snapshot = jobs
        for indices in groups.values {
            guard let first = indices.first else { continue }
            let placed = snapshot[first].pairs.count
            let extrasPer = OstwaldProgress.unusedPairCount(placed: placed)
            let trialsPerJob = 1 + extrasPer
            let trialCount = indices.count * trialsPerJob
            guard trialCount > 0 else { continue }
            let mode = scorer.scoreMode(placed: placed)
            decryptsDone += trialCount
            let engine = engineFor(snapshot[first])
            let scores: [Float]
            if let engine, ranker == nil {
                scores = engine.scoresPacked(count: trialCount, mode: mode) { bytes in
                    packGreedyTrials(
                        jobs: snapshot, indices: indices, extrasPer: extrasPer, into: bytes
                    )
                }
            } else {
                scores = cpuGreedyScores(
                    jobs: snapshot, indices: indices, extrasPer: extrasPer,
                    ciphertext: ciphertext, scorer: scorer, placed: placed, ranker: ranker
                )
            }
            applyGreedyWinners(
                jobs: &jobs, indices: indices, extrasPer: extrasPer, scores: scores
            )
        }
    }

    /// Replacement polish is a CPU hill-climb. Doing it for every 4-plug ghost was the
    /// live 2.0M/s wall (~1.4M CPU decrypts per 8,192-job chunk). Keep Metal greedy on
    /// the whole wave; polish only the leaders, whose scores can still rise.
    package static let polishTopCount = 256

    package static func scoreFinal(
        jobs: inout [OstwaldClimbJob],
        ciphertext: [Int],
        scorer: ClimbScorer,
        engineFor: (OstwaldClimbJob) -> OstwaldMetalEngine?,
        ranker: OstwaldRanker.Model? = nil
    ) {
        guard !jobs.isEmpty else { return }
        var groups: [String: [Int]] = [:]
        for (index, job) in jobs.enumerated() {
            groups[shellKey(job), default: []].append(index)
        }
        let snapshot = jobs
        for indices in groups.values {
            guard let first = indices.first else { continue }
            let mode = scorer.scoreMode(placed: snapshot[first].maxPlugs)
            if let engine = engineFor(snapshot[first]), ranker == nil {
                let scores = engine.scoresPacked(count: indices.count, mode: mode) { bytes in
                    DispatchQueue.concurrentPerform(iterations: indices.count) { i in
                        packBoard(snapshot[indices[i]], at: i, into: bytes)
                    }
                }
                for i in indices.indices {
                    jobs[indices[i]].score = Double(scores[i])
                }
            } else {
                let measure = scorer.measure(placed: snapshot[first].maxPlugs, ranker: ranker)
                for jobIndex in indices {
                    let job = snapshot[jobIndex]
                    let plain = OstwaldCurve.decrypt(
                        key: job.key, ciphertext: ciphertext, pairs: job.pairs, walk: job.walk
                    )
                    jobs[jobIndex].score = measure(plain)
                    jobs[jobIndex].plain = plain
                }
            }
        }
    }

    package static func polishTop(
        jobs: inout [OstwaldClimbJob],
        ciphertext: [Int],
        scorer: ClimbScorer,
        beamWidth: Int = 1,
        ranker: OstwaldRanker.Model? = nil,
        keep: Int = polishTopCount
    ) {
        guard !jobs.isEmpty else { return }
        if jobs.count <= keep {
            polish(
                jobs: &jobs, ciphertext: ciphertext, scorer: scorer,
                beamWidth: beamWidth, ranker: ranker
            )
            return
        }
        let ranked = jobs.indices.sorted { jobs[$0].score > jobs[$1].score }
        var elite = ranked.prefix(keep).map { jobs[$0] }
        polish(
            jobs: &elite, ciphertext: ciphertext, scorer: scorer,
            beamWidth: beamWidth, ranker: ranker
        )
        for (offset, jobIndex) in ranked.prefix(keep).enumerated() {
            jobs[jobIndex] = elite[offset]
        }
    }

    package static func polish(
        jobs: inout [OstwaldClimbJob],
        ciphertext: [Int],
        scorer: ClimbScorer,
        beamWidth: Int = 1,
        ranker: OstwaldRanker.Model? = nil
    ) {
        final class Slot: @unchecked Sendable {
            var pairs: [(Int, Int)] = []
            var score = 0.0
            var plain: [Int] = []
        }
        let snapshot = jobs
        let slots = (0..<snapshot.count).map { _ in Slot() }
        DispatchQueue.concurrentPerform(iterations: snapshot.count) { index in
            let job = snapshot[index]
            let locked = Array(job.pairs.prefix(job.seededCount))
            let climbed = OstwaldCurve.climb(
                key: job.key,
                ciphertext: ciphertext,
                scorer: scorer,
                maxPlugs: job.maxPlugs,
                seeded: locked,
                walk: job.walk,
                resumeFrom: job.pairs,
                beamWidth: beamWidth,
                ranker: ranker
            )
            slots[index].pairs = climbed.pairs
            slots[index].score = climbed.score
            slots[index].plain = climbed.plain
        }
        for index in jobs.indices {
            jobs[index].pairs = slots[index].pairs
            jobs[index].score = slots[index].score
            jobs[index].plain = slots[index].plain
        }
    }

    private static func fillPlug(_ pairs: [(Int, Int)], into plug: UnsafeMutablePointer<UInt8>) {
        for letter in 0..<26 { plug[letter] = UInt8(letter) }
        for pair in pairs {
            plug[pair.0] = UInt8(pair.1)
            plug[pair.1] = UInt8(pair.0)
        }
    }

    private static func packBoard(
        _ job: OstwaldClimbJob,
        at trial: Int,
        into bytes: UnsafeMutablePointer<UInt8>
    ) {
        let plug = UnsafeMutablePointer<UInt8>.allocate(capacity: 26)
        defer { plug.deallocate() }
        fillPlug(job.pairs, into: plug)
        let pos = job.key.positions
        OstwaldTrial.pack(
            to: bytes, at: trial,
            posG: UInt8(pos.0), posL: UInt8(pos.1), posM: UInt8(pos.2), posR: UInt8(pos.3),
            plug: plug,
            leadingHoles: UInt8(min(max(job.walk.leadingHoles, 0), 255))
        )
    }

    private static func packGreedyTrials(
        jobs: [OstwaldClimbJob],
        indices: [Int],
        extrasPer: Int,
        into bytes: UnsafeMutablePointer<UInt8>
    ) {
        let trialsPerJob = 1 + extrasPer
        DispatchQueue.concurrentPerform(iterations: indices.count) { i in
            let job = jobs[indices[i]]
            let pos = job.key.positions
            let posG = UInt8(pos.0)
            let posL = UInt8(pos.1)
            let posM = UInt8(pos.2)
            let posR = UInt8(pos.3)
            let holes = UInt8(min(max(job.walk.leadingHoles, 0), 255))
            let plug = UnsafeMutablePointer<UInt8>.allocate(capacity: 26)
            let extra = UnsafeMutablePointer<UInt8>.allocate(capacity: 26)
            defer {
                plug.deallocate()
                extra.deallocate()
            }
            fillPlug(job.pairs, into: plug)
            let baseTrial = i * trialsPerJob
            OstwaldTrial.pack(
                to: bytes, at: baseTrial,
                posG: posG, posL: posL, posM: posM, posR: posR,
                plug: plug, leadingHoles: holes
            )
            var used: UInt32 = 0
            for pair in job.pairs {
                used |= UInt32(1) << pair.0
                used |= UInt32(1) << pair.1
            }
            var k = 0
            for a in 0..<26 where used & (UInt32(1) << a) == 0 {
                for b in (a + 1)..<26 where used & (UInt32(1) << b) == 0 {
                    extra.update(from: plug, count: 26)
                    extra[a] = UInt8(b)
                    extra[b] = UInt8(a)
                    OstwaldTrial.pack(
                        to: bytes, at: baseTrial + 1 + k,
                        posG: posG, posL: posL, posM: posM, posR: posR,
                        plug: extra, leadingHoles: holes
                    )
                    k += 1
                }
            }
        }
    }

    private static func applyGreedyWinners(
        jobs: inout [OstwaldClimbJob],
        indices: [Int],
        extrasPer: Int,
        scores: [Float]
    ) {
        let trialsPerJob = 1 + extrasPer
        for i in indices.indices {
            let jobIndex = indices[i]
            let baseIdx = i * trialsPerJob
            guard baseIdx < scores.count else {
                jobs[jobIndex].stuck = true
                continue
            }
            var used: UInt32 = 0
            for pair in jobs[jobIndex].pairs {
                used |= UInt32(1) << pair.0
                used |= UInt32(1) << pair.1
            }
            var bestScore = Double(scores[baseIdx])
            var bestPair: (Int, Int)?
            var k = 0
            for a in 0..<26 where used & (UInt32(1) << a) == 0 {
                for b in (a + 1)..<26 where used & (UInt32(1) << b) == 0 {
                    let trial = baseIdx + 1 + k
                    if trial < scores.count {
                        let value = Double(scores[trial])
                        if value > bestScore {
                            bestScore = value
                            bestPair = (a, b)
                        }
                    }
                    k += 1
                }
            }
            if let pair = bestPair {
                jobs[jobIndex].pairs.append(pair)
            } else {
                jobs[jobIndex].stuck = true
            }
        }
    }

    private static func cpuGreedyScores(
        jobs: [OstwaldClimbJob],
        indices: [Int],
        extrasPer: Int,
        ciphertext: [Int],
        scorer: ClimbScorer,
        placed: Int,
        ranker: OstwaldRanker.Model?
    ) -> [Float] {
        let trialsPerJob = 1 + extrasPer
        let count = indices.count * trialsPerJob
        let measure = scorer.measure(placed: placed, ranker: ranker)
        let raw = UnsafeMutablePointer<Float>.allocate(capacity: count)
        raw.initialize(repeating: 0, count: count)
        DispatchQueue.concurrentPerform(iterations: indices.count) { i in
            let job = jobs[indices[i]]
            let baseIdx = i * trialsPerJob
            raw[baseIdx] = Float(measure(OstwaldCurve.decrypt(
                key: job.key, ciphertext: ciphertext, pairs: job.pairs, walk: job.walk
            )))
            var used: UInt32 = 0
            for pair in job.pairs {
                used |= UInt32(1) << pair.0
                used |= UInt32(1) << pair.1
            }
            var k = 0
            for a in 0..<26 where used & (UInt32(1) << a) == 0 {
                for b in (a + 1)..<26 where used & (UInt32(1) << b) == 0 {
                    raw[baseIdx + 1 + k] = Float(measure(OstwaldCurve.decrypt(
                        key: job.key, ciphertext: ciphertext,
                        pairs: job.pairs + [(a, b)], walk: job.walk
                    )))
                    k += 1
                }
            }
        }
        let out = Array(UnsafeBufferPointer(start: raw, count: count))
        raw.deinitialize(count: count)
        raw.deallocate()
        return out
    }

    private static func shellKey(_ job: OstwaldClimbJob) -> String {
        "\(job.key.reflector.hashValue)|\(job.key.greek.name)|\(job.key.rotors.0.name)-\(job.key.rotors.1.name)-\(job.key.rotors.2.name)|\(job.key.rings.0)-\(job.key.rings.1)-\(job.key.rings.2)-\(job.key.rings.3)|\(job.pairs.count)"
    }
}
