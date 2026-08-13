import Foundation
import Metal
import HELUTCore

// MARK: - Cleartext batch datapath (ASIC-esque, boolean-faithful)
//
// Hard macros: rotor/reflector/bigram/crib tables in constant buffers.
// Soft I/O: stecker + rings rebound per chromosome (µs — not a Yosys resynth).
// Parallel lanes: B = 26³ = 17_576. On-device fitness ≈ HostM4Bombe.attackScore
// (mean bigram − IC penalty + multi-letter crib bonuses).
//
// NOT the HELUT mock-PBS graph for fitness. Scoring LUTs live in this cleartext
// Metal kernel (compile once per process); shell genes only reload 26-byte tables.

let cleartextBatchLaneCount = 26 * 26 * 26 // 17_576

private let germanICTarget: Float = 0.0749
private let icPenaltyScale: Float = 8.0
private let cribBonus: Float = 0.05

/// Same multi-letter cribs as `HostM4Bombe.attackScore` (packed for Metal/CPU).
private let attackScoreCribs: [String] = [
    "EINS", "ZWO", "DREI", "NULL", "VIER", "FUENF", "SECHS", "ACHT", "NEUN",
    "WETTER", "CHEF", "UBOOT", "MELDUNG", "MARINE", "QUADRAT", "KURS", "FEIND",
    "BOOT", "STANDORT", "ANGRIFF", "VONVON"
]

private let m4AttackBatchMetalSource = """
#include <metal_stdlib>
using namespace metal;

inline uchar rot_fwd(uchar ch, uchar pos, uchar ring, constant uchar *fwd) {
    int offset = (int(pos) - int(ring) + 26) % 26;
    int shifted = (int(ch) + offset) % 26;
    int wired = int(fwd[shifted]);
    return uchar((wired - offset + 26) % 26);
}

inline uchar rot_inv(uchar ch, uchar pos, uchar ring, constant uchar *inv) {
    int offset = (int(pos) - int(ring) + 26) % 26;
    int shifted = (int(ch) + offset) % 26;
    int wired = int(inv[shifted]);
    return uchar((wired - offset + 26) % 26);
}

kernel void m4_attack_batch(
    device uchar const *ciphertext [[buffer(0)]],
    constant uint &ctLen [[buffer(1)]],
    constant uint &greekPos [[buffer(2)]],
    constant uchar *rings [[buffer(3)]],
    constant uchar *plug [[buffer(4)]],
    constant uchar *refl [[buffer(5)]],
    constant uchar *gFwd [[buffer(6)]],
    constant uchar *gInv [[buffer(7)]],
    constant uchar *lFwd [[buffer(8)]],
    constant uchar *lInv [[buffer(9)]],
    constant uchar *mFwd [[buffer(10)]],
    constant uchar *mInv [[buffer(11)]],
    constant uchar *rFwd [[buffer(12)]],
    constant uchar *rInv [[buffer(13)]],
    constant uchar *notchL [[buffer(14)]],
    constant uchar *notchM [[buffer(15)]],
    constant uchar *notchR [[buffer(16)]],
    constant float *bigrams [[buffer(17)]],
    constant uchar *cribs [[buffer(18)]],
    device float *outScore [[buffer(19)]],
    uint lane [[thread_position_in_grid]]
) {
    if (lane >= 17576u) return;
    (void)notchL[0];

    uchar posR = uchar(lane % 26u);
    uchar posM = uchar((lane / 26u) % 26u);
    uchar posL = uchar(lane / 676u);
    uchar posG = uchar(greekPos);

    uchar rg = rings[0], rl = rings[1], rm = rings[2], rr = rings[3];

    uchar plain[128];
    uint freq[26];
    for (uint i = 0; i < 26u; ++i) freq[i] = 0u;

    uchar prev = 0;
    float bigramSum = 0.0f;

    for (uint t = 0; t < ctLen; ++t) {
        bool midNotch = notchM[posM] != 0;
        bool rightNotch = notchR[posR] != 0;
        if (midNotch) {
            posL = uchar((uint(posL) + 1u) % 26u);
        }
        if (midNotch || rightNotch) {
            posM = uchar((uint(posM) + 1u) % 26u);
        }
        posR = uchar((uint(posR) + 1u) % 26u);

        uchar x = plug[ciphertext[t]];
        x = rot_fwd(x, posR, rr, rFwd);
        x = rot_fwd(x, posM, rm, mFwd);
        x = rot_fwd(x, posL, rl, lFwd);
        x = rot_fwd(x, posG, rg, gFwd);
        x = refl[x];
        x = rot_inv(x, posG, rg, gInv);
        x = rot_inv(x, posL, rl, lInv);
        x = rot_inv(x, posM, rm, mInv);
        x = rot_inv(x, posR, rr, rInv);
        x = plug[x];

        plain[t] = x;
        freq[x] += 1u;
        if (t > 0u) {
            bigramSum += bigrams[uint(prev) * 26u + uint(x)];
        }
        prev = x;
    }

    float n = float(ctLen);
    float icNum = 0.0f;
    for (uint i = 0; i < 26u; ++i) {
        float c = float(freq[i]);
        icNum += c * (c - 1.0f);
    }
    float ic = icNum / (n * (n - 1.0f));
    float bigram = (ctLen >= 2u) ? (bigramSum / float(ctLen - 1u)) : -10.0f;
    float score = bigram - fabs(ic - 0.0749f) * 8.0f;

    // Packed cribs: [nCribs][len][letters…]…
    uint nCribs = uint(cribs[0]);
    uint cursor = 1u;
    for (uint c = 0; c < nCribs; ++c) {
        uint len = uint(cribs[cursor]);
        cursor += 1u;
        bool hit = false;
        if (len > 0u && ctLen >= len) {
            uint last = ctLen - len;
            for (uint off = 0u; off <= last; ++off) {
                bool ok = true;
                for (uint i = 0u; i < len; ++i) {
                    if (plain[off + i] != cribs[cursor + i]) {
                        ok = false;
                        break;
                    }
                }
                if (ok) {
                    hit = true;
                    break;
                }
            }
        }
        if (hit) {
            score += 0.05f;
        }
        cursor += len;
    }

    outScore[lane] = score;
}

/// Known-plaintext / template match: score = letter hits (0…ctLen). Used by the
/// Stochastic Bombe — German n-grams are irrelevant for Thetis template search.
kernel void m4_kpa_batch(
    device uchar const *ciphertext [[buffer(0)]],
    constant uint &ctLen [[buffer(1)]],
    constant uint &greekPos [[buffer(2)]],
    constant uchar *rings [[buffer(3)]],
    constant uchar *plug [[buffer(4)]],
    constant uchar *refl [[buffer(5)]],
    constant uchar *gFwd [[buffer(6)]],
    constant uchar *gInv [[buffer(7)]],
    constant uchar *lFwd [[buffer(8)]],
    constant uchar *lInv [[buffer(9)]],
    constant uchar *mFwd [[buffer(10)]],
    constant uchar *mInv [[buffer(11)]],
    constant uchar *rFwd [[buffer(12)]],
    constant uchar *rInv [[buffer(13)]],
    constant uchar *notchL [[buffer(14)]],
    constant uchar *notchM [[buffer(15)]],
    constant uchar *notchR [[buffer(16)]],
    constant uchar *known [[buffer(17)]],
    device float *outScore [[buffer(18)]],
    uint lane [[thread_position_in_grid]]
) {
    if (lane >= 17576u) return;
    (void)notchL[0];

    uchar posR = uchar(lane % 26u);
    uchar posM = uchar((lane / 26u) % 26u);
    uchar posL = uchar(lane / 676u);
    uchar posG = uchar(greekPos);

    uchar rg = rings[0], rl = rings[1], rm = rings[2], rr = rings[3];

    float matches = 0.0f;
    for (uint t = 0; t < ctLen; ++t) {
        bool midNotch = notchM[posM] != 0;
        bool rightNotch = notchR[posR] != 0;
        if (midNotch) {
            posL = uchar((uint(posL) + 1u) % 26u);
        }
        if (midNotch || rightNotch) {
            posM = uchar((uint(posM) + 1u) % 26u);
        }
        posR = uchar((uint(posR) + 1u) % 26u);

        uchar x = plug[ciphertext[t]];
        x = rot_fwd(x, posR, rr, rFwd);
        x = rot_fwd(x, posM, rm, mFwd);
        x = rot_fwd(x, posL, rl, lFwd);
        x = rot_fwd(x, posG, rg, gFwd);
        x = refl[x];
        x = rot_inv(x, posG, rg, gInv);
        x = rot_inv(x, posL, rl, lInv);
        x = rot_inv(x, posM, rm, mInv);
        x = rot_inv(x, posR, rr, rInv);
        x = plug[x];

        if (known[t] < 26u && x == known[t]) {
            matches += 1.0f;
        }
    }
    outScore[lane] = matches;
}
"""

private func packAttackCribs(_ cribs: [String]) -> [UInt8] {
    var bytes: [UInt8] = [UInt8(cribs.count)]
    for crib in cribs {
        let letters = EnigmaAlphabet.normalize(crib)
        precondition(letters.count <= 255)
        bytes.append(UInt8(letters.count))
        bytes.append(contentsOf: letters.map { UInt8($0) })
    }
    return bytes
}

private func floatBigramTable() -> [Float] {
    LanguageScorer.germanBigramLogProbs.map { Float($0) }
}

/// ASIC-style cleartext batch: one Greek window × all 26³ L/M/R starts.
final class CleartextM4BatchEngine: @unchecked Sendable {
    private let lock = NSLock()
    private let device: MTLDevice?
    private let queue: MTLCommandQueue?
    private let pipeline: MTLComputePipelineState?
    private let kpaPipeline: MTLComputePipelineState?
    private let ctBuffer: MTLBuffer?
    private let outBuffer: MTLBuffer?
    private let bigramBuffer: MTLBuffer?
    private let cribBuffer: MTLBuffer?
    private let knownBuffer: MTLBuffer?
    private let ciphertext: [Int]
    private let knownPlaintext: [Int]?
    /// 0…25 = required letter; values ≥26 (e.g. 255) are don't-care for masked templates.
    private var activeKnown: [UInt8]
    private let ctLen: Int
    private let bigrams: [Float]
    private let cribBytes: [UInt8]
    let backendName: String

    private init(
        ciphertext: [Int],
        knownPlaintext: [Int]?,
        device: MTLDevice?,
        queue: MTLCommandQueue?,
        pipeline: MTLComputePipelineState?,
        kpaPipeline: MTLComputePipelineState?,
        backendName: String
    ) {
        self.ciphertext = ciphertext
        self.knownPlaintext = knownPlaintext
        self.ctLen = ciphertext.count
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
        self.kpaPipeline = kpaPipeline
        self.backendName = backendName
        self.bigrams = floatBigramTable()
        self.cribBytes = packAttackCribs(attackScoreCribs)
        if let known = knownPlaintext {
            self.activeKnown = known.map { UInt8(clamping: $0 > 25 ? 255 : $0) }
        } else {
            self.activeKnown = [UInt8](repeating: 255, count: ciphertext.count)
        }
        while self.activeKnown.count < 128 { self.activeKnown.append(255) }

        if let device, pipeline != nil || kpaPipeline != nil {
            var ctBytes = ciphertext.map { UInt8($0) }
            while ctBytes.count < 128 { ctBytes.append(0) }
            self.ctBuffer = device.makeBuffer(bytes: &ctBytes, length: ctBytes.count, options: .storageModeShared)
            self.outBuffer = device.makeBuffer(
                length: cleartextBatchLaneCount * MemoryLayout<Float>.stride,
                options: .storageModeShared
            )
            var bigCopy = bigrams
            self.bigramBuffer = device.makeBuffer(
                bytes: &bigCopy,
                length: bigCopy.count * MemoryLayout<Float>.stride,
                options: .storageModeShared
            )
            var cribCopy = cribBytes
            self.cribBuffer = device.makeBuffer(
                bytes: &cribCopy,
                length: cribCopy.count,
                options: .storageModeShared
            )
            var knownBytes = activeKnown
            self.knownBuffer = device.makeBuffer(
                bytes: &knownBytes,
                length: knownBytes.count,
                options: .storageModeShared
            )
        } else {
            self.ctBuffer = nil
            self.outBuffer = nil
            self.bigramBuffer = nil
            self.cribBuffer = nil
            self.knownBuffer = nil
        }
    }

    /// Prefer Metal; always returns a usable engine (CPU fallback).
    static func make(ciphertext: [Int], knownPlaintext: [Int]? = nil) -> CleartextM4BatchEngine {
        if let device = MTLCreateSystemDefaultDevice(),
           let queue = device.makeCommandQueue() {
            do {
                let library = try device.makeLibrary(source: m4AttackBatchMetalSource, options: nil)
                let attackFn = library.makeFunction(name: "m4_attack_batch")
                let kpaFn = library.makeFunction(name: "m4_kpa_batch")
                let attackPipe = try attackFn.map { try device.makeComputePipelineState(function: $0) }
                let kpaPipe = try kpaFn.map { try device.makeComputePipelineState(function: $0) }
                if attackPipe != nil || kpaPipe != nil {
                    let mode: String
                    if knownPlaintext != nil, kpaPipe != nil {
                        mode = "Metal-cleartext-KPA"
                    } else if attackPipe != nil {
                        mode = "Metal-cleartext-attack"
                    } else {
                        mode = "Metal-cleartext-KPA-only"
                    }
                    return CleartextM4BatchEngine(
                        ciphertext: ciphertext,
                        knownPlaintext: knownPlaintext,
                        device: device,
                        queue: queue,
                        pipeline: attackPipe,
                        kpaPipeline: kpaPipe,
                        backendName: mode
                    )
                }
            } catch {
                fputs("Cleartext Metal batch compile failed (\(error)); CPU batch.\n", stderr)
            }
        }
        return CleartextM4BatchEngine(
            ciphertext: ciphertext,
            knownPlaintext: knownPlaintext,
            device: nil,
            queue: nil,
            pipeline: nil,
            kpaPipeline: nil,
            backendName: knownPlaintext == nil ? "CPU-cleartext-attack" : "CPU-cleartext-KPA"
        )
    }

    /// Top-K lanes by on-device attack score (bigram − IC penalty + crib bonuses).
    func topLanes(key: EnigmaM4Key, greek: Int, topK: Int) -> [(lane: Int, score: Float)] {
        lock.lock()
        defer { lock.unlock() }
        let scores: [Float]
        if pipeline != nil {
            scores = metalAttackBatch(key: key, greek: greek)
        } else {
            scores = cpuAttackBatch(key: key, greek: greek)
        }
        return Self.pickTop(scores: scores, topK: topK)
    }

    /// Best message-key lane under letter-match to `known` (0…25 required; ≥26 don't-care).
    /// Full 26⁴ scan. Updates the on-device known buffer under the engine lock.
    func bestKPAMatch(key: EnigmaM4Key, known: [Int]) -> (greek: Int, lane: Int, score: Float) {
        lock.lock()
        defer { lock.unlock() }

        activeKnown = known.map { UInt8(clamping: $0 > 25 ? 255 : $0) }
        while activeKnown.count < 128 { activeKnown.append(255) }
        if let knownBuffer {
            let ptr = knownBuffer.contents().bindMemory(to: UInt8.self, capacity: activeKnown.count)
            for i in 0..<activeKnown.count { ptr[i] = activeKnown[i] }
        }

        var bestGreek = 0
        var bestLane = 0
        var bestScore: Float = -1
        for greek in 0..<26 {
            let scores: [Float]
            if kpaPipeline != nil, knownBuffer != nil {
                scores = metalKPABatch(key: key, greek: greek)
            } else {
                scores = cpuKPABatch(key: key, greek: greek)
            }
            for lane in 0..<scores.count {
                let score = scores[lane]
                if score > bestScore {
                    bestScore = score
                    bestLane = lane
                    bestGreek = greek
                }
            }
        }
        return (bestGreek, bestLane, bestScore)
    }

    /// Convenience: use the known plaintext supplied at `make` time.
    func bestKPAMatch(key: EnigmaM4Key) -> (greek: Int, lane: Int, score: Float) {
        guard let known = knownPlaintext else {
            return (0, 0, -1)
        }
        return bestKPAMatch(key: key, known: known)
    }

    private static func pickTop(scores: [Float], topK: Int) -> [(lane: Int, score: Float)] {
        var best = [(Int, Float)]()
        best.reserveCapacity(topK)
        for lane in 0..<scores.count {
            let score = scores[lane]
            if best.count < topK {
                best.append((lane, score))
                if best.count == topK { best.sort { $0.1 > $1.1 } }
            } else if score > best[topK - 1].1 {
                best[topK - 1] = (lane, score)
                best.sort { $0.1 > $1.1 }
            }
        }
        return best.map { (lane: $0.0, score: $0.1) }
    }

    private func metalAttackBatch(key: EnigmaM4Key, greek: Int) -> [Float] {
        guard let device, let queue, let pipeline,
              let ctBuffer, let outBuffer, let bigramBuffer, let cribBuffer else {
            return cpuAttackBatch(key: key, greek: greek)
        }
        let tables = KeyTables(key: key)
        var greekU = UInt32(greek)
        var lenU = UInt32(ctLen)
        var rings: [UInt8] = [
            UInt8(key.rings.0), UInt8(key.rings.1), UInt8(key.rings.2), UInt8(key.rings.3)
        ]

        func buf(_ bytes: [UInt8]) -> MTLBuffer {
            var copy = bytes
            return device.makeBuffer(bytes: &copy, length: copy.count, options: .storageModeShared)!
        }

        guard let command = queue.makeCommandBuffer(),
              let encoder = command.makeComputeCommandEncoder() else {
            return cpuAttackBatch(key: key, greek: greek)
        }

        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(ctBuffer, offset: 0, index: 0)
        encoder.setBytes(&lenU, length: 4, index: 1)
        encoder.setBytes(&greekU, length: 4, index: 2)
        encoder.setBytes(&rings, length: 4, index: 3)
        encoder.setBuffer(buf(tables.plug), offset: 0, index: 4)
        encoder.setBuffer(buf(tables.refl), offset: 0, index: 5)
        encoder.setBuffer(buf(tables.gFwd), offset: 0, index: 6)
        encoder.setBuffer(buf(tables.gInv), offset: 0, index: 7)
        encoder.setBuffer(buf(tables.lFwd), offset: 0, index: 8)
        encoder.setBuffer(buf(tables.lInv), offset: 0, index: 9)
        encoder.setBuffer(buf(tables.mFwd), offset: 0, index: 10)
        encoder.setBuffer(buf(tables.mInv), offset: 0, index: 11)
        encoder.setBuffer(buf(tables.rFwd), offset: 0, index: 12)
        encoder.setBuffer(buf(tables.rInv), offset: 0, index: 13)
        encoder.setBuffer(buf(tables.notchL), offset: 0, index: 14)
        encoder.setBuffer(buf(tables.notchM), offset: 0, index: 15)
        encoder.setBuffer(buf(tables.notchR), offset: 0, index: 16)
        encoder.setBuffer(bigramBuffer, offset: 0, index: 17)
        encoder.setBuffer(cribBuffer, offset: 0, index: 18)
        encoder.setBuffer(outBuffer, offset: 0, index: 19)

        let w = pipeline.threadExecutionWidth
        let groups = MTLSize(width: (cleartextBatchLaneCount + w - 1) / w, height: 1, depth: 1)
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: MTLSize(width: w, height: 1, depth: 1))
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()

        let ptr = outBuffer.contents().bindMemory(to: Float.self, capacity: cleartextBatchLaneCount)
        return Array(UnsafeBufferPointer(start: ptr, count: cleartextBatchLaneCount))
    }

    private func metalKPABatch(key: EnigmaM4Key, greek: Int) -> [Float] {
        guard let device, let queue, let kpaPipeline,
              let ctBuffer, let outBuffer, let knownBuffer else {
            return cpuKPABatch(key: key, greek: greek)
        }
        let tables = KeyTables(key: key)
        var greekU = UInt32(greek)
        var lenU = UInt32(ctLen)
        var rings: [UInt8] = [
            UInt8(key.rings.0), UInt8(key.rings.1), UInt8(key.rings.2), UInt8(key.rings.3)
        ]

        func buf(_ bytes: [UInt8]) -> MTLBuffer {
            var copy = bytes
            return device.makeBuffer(bytes: &copy, length: copy.count, options: .storageModeShared)!
        }

        guard let command = queue.makeCommandBuffer(),
              let encoder = command.makeComputeCommandEncoder() else {
            return cpuKPABatch(key: key, greek: greek)
        }

        encoder.setComputePipelineState(kpaPipeline)
        encoder.setBuffer(ctBuffer, offset: 0, index: 0)
        encoder.setBytes(&lenU, length: 4, index: 1)
        encoder.setBytes(&greekU, length: 4, index: 2)
        encoder.setBytes(&rings, length: 4, index: 3)
        encoder.setBuffer(buf(tables.plug), offset: 0, index: 4)
        encoder.setBuffer(buf(tables.refl), offset: 0, index: 5)
        encoder.setBuffer(buf(tables.gFwd), offset: 0, index: 6)
        encoder.setBuffer(buf(tables.gInv), offset: 0, index: 7)
        encoder.setBuffer(buf(tables.lFwd), offset: 0, index: 8)
        encoder.setBuffer(buf(tables.lInv), offset: 0, index: 9)
        encoder.setBuffer(buf(tables.mFwd), offset: 0, index: 10)
        encoder.setBuffer(buf(tables.mInv), offset: 0, index: 11)
        encoder.setBuffer(buf(tables.rFwd), offset: 0, index: 12)
        encoder.setBuffer(buf(tables.rInv), offset: 0, index: 13)
        encoder.setBuffer(buf(tables.notchL), offset: 0, index: 14)
        encoder.setBuffer(buf(tables.notchM), offset: 0, index: 15)
        encoder.setBuffer(buf(tables.notchR), offset: 0, index: 16)
        encoder.setBuffer(knownBuffer, offset: 0, index: 17)
        encoder.setBuffer(outBuffer, offset: 0, index: 18)

        let w = kpaPipeline.threadExecutionWidth
        let groups = MTLSize(width: (cleartextBatchLaneCount + w - 1) / w, height: 1, depth: 1)
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: MTLSize(width: w, height: 1, depth: 1))
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()

        let ptr = outBuffer.contents().bindMemory(to: Float.self, capacity: cleartextBatchLaneCount)
        return Array(UnsafeBufferPointer(start: ptr, count: cleartextBatchLaneCount))
    }

    private func cpuAttackBatch(key: EnigmaM4Key, greek: Int) -> [Float] {
        var out = [Float](repeating: 0, count: cleartextBatchLaneCount)
        let ct = ciphertext
        let bigramTable = self.bigrams
        let cribPacked = self.cribBytes
        out.withUnsafeMutableBufferPointer { buf in
            let base = buf.baseAddress!
            DispatchQueue.concurrentPerform(iterations: cleartextBatchLaneCount) { lane in
                let r = lane % 26
                let m = (lane / 26) % 26
                let l = lane / 676
                var k = key
                k.positions = (greek, l, m, r)
                var machine = EnigmaM4Machine(key: k)
                var plain = [UInt8](repeating: 0, count: ct.count)
                var freq = [Int](repeating: 0, count: 26)
                for (t, cipher) in ct.enumerated() {
                    let p = machine.process(cipher)
                    plain[t] = UInt8(p)
                    freq[p] += 1
                }
                let n = Double(ct.count)
                var icNum = 0.0
                for c in freq { icNum += Double(c * (c - 1)) }
                let ic = Float(icNum / (n * (n - 1)))
                var bigramSum: Float = 0
                if plain.count >= 2 {
                    for i in 0..<(plain.count - 1) {
                        bigramSum += bigramTable[Int(plain[i]) * 26 + Int(plain[i + 1])]
                    }
                }
                let bigram: Float = plain.count >= 2
                    ? bigramSum / Float(plain.count - 1)
                    : -10
                var score = bigram - abs(ic - germanICTarget) * icPenaltyScale

                var cursor = 1
                let nCribs = Int(cribPacked[0])
                for _ in 0..<nCribs {
                    let len = Int(cribPacked[cursor])
                    cursor += 1
                    let crib = Array(cribPacked[cursor..<(cursor + len)])
                    cursor += len
                    if len > 0, plain.count >= len {
                        let last = plain.count - len
                        var hit = false
                        for off in 0...last {
                            if Array(plain[off..<(off + len)]) == crib {
                                hit = true
                                break
                            }
                        }
                        if hit { score += cribBonus }
                    }
                }
                base[lane] = score
            }
        }
        return out
    }

    private func cpuKPABatch(key: EnigmaM4Key, greek: Int) -> [Float] {
        let known = activeKnown
        var out = [Float](repeating: 0, count: cleartextBatchLaneCount)
        let ct = ciphertext
        let n = ctLen
        out.withUnsafeMutableBufferPointer { buf in
            let base = buf.baseAddress!
            DispatchQueue.concurrentPerform(iterations: cleartextBatchLaneCount) { lane in
                let r = lane % 26
                let m = (lane / 26) % 26
                let l = lane / 676
                var k = key
                k.positions = (greek, l, m, r)
                var machine = EnigmaM4Machine(key: k)
                var hits: Float = 0
                for t in 0..<n {
                    let p = machine.process(ct[t])
                    let expect = known[t]
                    if expect < 26, p == Int(expect) { hits += 1 }
                }
                base[lane] = hits
            }
        }
        return out
    }
}

private struct KeyTables {
    let plug: [UInt8]
    let refl: [UInt8]
    let gFwd: [UInt8]
    let gInv: [UInt8]
    let lFwd: [UInt8]
    let lInv: [UInt8]
    let mFwd: [UInt8]
    let mInv: [UInt8]
    let rFwd: [UInt8]
    let rInv: [UInt8]
    let notchL: [UInt8]
    let notchM: [UInt8]
    let notchR: [UInt8]

    init(key: EnigmaM4Key) {
        plug = key.plugboard.map { UInt8($0) }
        refl = key.reflector.map { UInt8($0) }
        gFwd = key.greek.wiring.map { UInt8($0) }
        gInv = key.greek.inverse.map { UInt8($0) }
        lFwd = key.rotors.0.wiring.map { UInt8($0) }
        lInv = key.rotors.0.inverse.map { UInt8($0) }
        mFwd = key.rotors.1.wiring.map { UInt8($0) }
        mInv = key.rotors.1.inverse.map { UInt8($0) }
        rFwd = key.rotors.2.wiring.map { UInt8($0) }
        rInv = key.rotors.2.inverse.map { UInt8($0) }
        notchL = Self.notchMask(key.rotors.0)
        notchM = Self.notchMask(key.rotors.1)
        notchR = Self.notchMask(key.rotors.2)
    }

    private static func notchMask(_ rotor: EnigmaRotorSpec) -> [UInt8] {
        var mask = [UInt8](repeating: 0, count: 26)
        for n in rotor.notches { mask[n] = 1 }
        return mask
    }
}

func positionsFromBatchLane(_ lane: Int, greek: Int) -> (Int, Int, Int, Int) {
    let r = lane % 26
    let m = (lane / 26) % 26
    let l = lane / 676
    return (greek, l, m, r)
}
