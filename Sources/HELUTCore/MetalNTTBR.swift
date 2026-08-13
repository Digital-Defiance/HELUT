import Foundation
import Metal

// MARK: - Phase 2 NTT persist BR tile
//
// Same CMUX control plane as `helut_blind_rotate_tile`, but external product is
// 3-prime twisted NTT (bit-identical to schoolbook). BK is uploaded in NTT
// domain; digits are NTT'd in-tile. One threadgroup of N.

private struct BRNTTUniforms {
    var n: UInt32
    var twoN: UInt32
    var bitLo: UInt32
    var bitHi: UInt32
    var levelCount: UInt32
    var baseLog: UInt32
    var shift: UInt32
    var logN: UInt32
    var p0: UInt32
    var p1: UInt32
    var p2: UInt32
    var nInv0: UInt32
    var nInv1: UInt32
    var nInv2: UInt32
    var invP0ModP1: UInt32
    var invP01ModP2: UInt32
    var p01Lo: UInt32
    var p01Hi: UInt32
    var pLoLo: UInt32
    var pLoHi: UInt32
    var pHiLo: UInt32
    var pHiHi: UInt32
    var pad0: UInt32
    var pad1: UInt32
}

func nttDomainBootstrapKey(
    _ coeff: [UInt32],
    n: Int,
    levelCount: Int,
    bitCount: Int
) -> [UInt32] {
    let polysPerBit = levelCount * 4
    precondition(coeff.count == bitCount * polysPerBit * n)
    var out = [UInt32](repeating: 0, count: bitCount * NegacyclicNTT.primeCount * polysPerBit * n)
    var src = [UInt32](repeating: 0, count: n)
    for bit in 0..<bitCount {
        for poly in 0..<polysPerBit {
            let srcOff = (bit * polysPerBit + poly) * n
            src.replaceSubrange(0..<n, with: coeff[srcOff..<(srcOff + n)])
            for pi in 0..<NegacyclicNTT.primeCount {
                let m = NegacyclicNTT.modulus(primeIndex: pi, n: n)
                let hat = NegacyclicNTT.forwardTwisted(src, m)
                let destOff = ((bit * NegacyclicNTT.primeCount + pi) * polysPerBit + poly) * n
                out.replaceSubrange(destOff..<(destOff + n), with: hat)
            }
        }
    }
    return out
}

final class MetalBRNTTEngine: @unchecked Sendable {
    let device: MTLDevice
    let pipeline: MTLComputePipelineState
    let n: Int
    let levelCount: Int
    let bitCount: Int
    let canFuseThreadgroup: Bool
    private let accMaskBuf: MTLBuffer
    private let accBodyBuf: MTLBuffer
    private let nttBkBuf: MTLBuffer
    private let lweABuf: MTLBuffer
    private let twiddleBuf: MTLBuffer
    private let scratchBuf: MTLBuffer
    private let uniBuf: MTLBuffer
    private let lock = NSLock()
    private var encodeSeconds: Double = 0
    private var gpuSeconds: Double = 0
    private var copySeconds: Double = 0
    private var bkFingerprint: UInt64 = 0

    static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct BRNTTUniforms {
        uint n;
        uint twoN;
        uint bitLo;
        uint bitHi;
        uint levelCount;
        uint baseLog;
        uint shift;
        uint logN;
        uint p0;
        uint p1;
        uint p2;
        uint nInv0;
        uint nInv1;
        uint nInv2;
        uint invP0ModP1;
        uint invP01ModP2;
        uint p01Lo;
        uint p01Hi;
        uint pLoLo;
        uint pLoHi;
        uint pHiLo;
        uint pHiHi;
        uint pad0;
        uint pad1;
    };

    uint mod_mul(uint a, uint b, uint p) {
        return uint((ulong)a * (ulong)b % (ulong)p);
    }
    uint mod_add(uint a, uint b, uint p) {
        uint s = a + b;
        return s >= p ? s - p : s;
    }
    uint mod_sub(uint a, uint b, uint p) {
        return a >= b ? a - b : (p - (b - a));
    }
    uint bitrev(uint x, uint logn) {
        uint r = 0u;
        for (uint i = 0u; i < logn; ++i) {
            r = (r << 1) | (x & 1u);
            x >>= 1;
        }
        return r;
    }

    uint take_digit(thread uint *remaining, uint baseLog, uint level) {
        if (baseLog == 32u) {
            uint d = *remaining;
            *remaining = 0u;
            return d;
        }
        uint baseMask = (1u << baseLog) - 1u;
        uint used = (level + 1u) * baseLog;
        if (used <= 32u) {
            uint sh = 32u - used;
            uint d = (*remaining >> sh) & baseMask;
            *remaining -= d << sh;
            return d;
        }
        uint d = *remaining & baseMask;
        *remaining = 0u;
        return d;
    }

    uint rotation_power(uint coeff, uint twoN, uint shift) {
        uint scale = 1u << shift;
        if (coeff < twoN) return coeff;
        if (scale > 1u && (coeff % scale) == 0u) return (coeff / scale) % twoN;
        if (scale > 1u && coeff < scale) return coeff % twoN;
        return coeff >> shift;
    }

    void ntt_inplace(
        threadgroup uint *a,
        uint n,
        device const uint *omegaPow,
        uint p,
        uint k
    ) {
        for (uint len = 2u; len <= n; len <<= 1) {
            uint halfLen = len >> 1;
            if (k < (n >> 1)) {
                uint block = k / halfLen;
                uint j = k % halfLen;
                uint i0 = block * len + j;
                uint i1 = i0 + halfLen;
                uint w = omegaPow[(n / len) * j];
                uint u = a[i0];
                uint v = mod_mul(a[i1], w, p);
                a[i0] = mod_add(u, v, p);
                a[i1] = mod_sub(u, v, p);
            }
            threadgroup_barrier(mem_flags::mem_threadgroup);
        }
    }

    void ntt_from_device(
        threadgroup uint *sh,
        threadgroup uint *tmp,
        device const uint *in,
        device const uint *psiPow,
        device const uint *omegaPow,
        uint n,
        uint logn,
        uint p,
        uint k
    ) {
        sh[k] = mod_mul(in[k] % p, psiPow[k], p);
        threadgroup_barrier(mem_flags::mem_threadgroup);
        tmp[bitrev(k, logn)] = sh[k];
        threadgroup_barrier(mem_flags::mem_threadgroup);
        sh[k] = tmp[k];
        threadgroup_barrier(mem_flags::mem_threadgroup);
        ntt_inplace(sh, n, omegaPow, p, k);
    }

    void intt_sh(
        threadgroup uint *sh,
        threadgroup uint *tmp,
        device const uint *psiInvPow,
        device const uint *omegaInvPow,
        uint nInv,
        uint n,
        uint logn,
        uint p,
        uint k
    ) {
        tmp[bitrev(k, logn)] = sh[k];
        threadgroup_barrier(mem_flags::mem_threadgroup);
        sh[k] = tmp[k];
        threadgroup_barrier(mem_flags::mem_threadgroup);
        ntt_inplace(sh, n, omegaInvPow, p, k);
        sh[k] = mod_mul(mod_mul(sh[k], nInv, p), psiInvPow[k], p);
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }

    void umul64(ulong a, ulong b, thread ulong *hi, thread ulong *lo) {
        ulong a0 = a & 0xfffffffful;
        ulong a1 = a >> 32;
        ulong b0 = b & 0xfffffffful;
        ulong b1 = b >> 32;
        ulong p00 = a0 * b0;
        ulong p01 = a0 * b1;
        ulong p10 = a1 * b0;
        ulong p11 = a1 * b1;
        ulong mid = (p00 >> 32) + (p01 & 0xfffffffful) + (p10 & 0xfffffffful);
        *lo = (p00 & 0xfffffffful) | (mid << 32);
        mid >>= 32;
        *hi = p11 + (p01 >> 32) + (p10 >> 32) + mid;
    }

    uint crt_u32(uint a0, uint a1, uint a2, constant BRNTTUniforms &U) {
        uint v1 = mod_mul(mod_sub(a1, a0 % U.p1, U.p1), U.invP0ModP1, U.p1);
        ulong x01 = (ulong)a0 + (ulong)U.p0 * (ulong)v1;
        ulong p01 = ((ulong)U.p01Hi << 32) | (ulong)U.p01Lo;
        uint x01modp2 = uint(x01 % (ulong)U.p2);
        uint v2 = mod_mul(mod_sub(a2, x01modp2, U.p2), U.invP01ModP2, U.p2);
        ulong xhi, xlo;
        umul64(p01, (ulong)v2, &xhi, &xlo);
        ulong slo = xlo + x01;
        if (slo < xlo) xhi += 1ul;
        xlo = slo;
        ulong Phi = ((ulong)U.pHiHi << 32) | (ulong)U.pHiLo;
        ulong Plo = ((ulong)U.pLoHi << 32) | (ulong)U.pLoLo;
        ulong halfHi = Phi >> 1;
        ulong halfLo = (Plo >> 1) | (Phi << 63);
        bool ge = (xhi != halfHi) ? (xhi > halfHi) : (xlo >= halfLo);
        if (ge) {
            ulong blo = xlo - Plo;
            ulong bhi = xhi - Phi;
            if (xlo < Plo) bhi -= 1ul;
            xlo = blo;
            xhi = bhi;
        }
        return uint(xlo);
    }

    [[max_total_threads_per_threadgroup(1024)]]
    kernel void helut_blind_rotate_ntt_tile(
        device uint *accM [[buffer(0)]],
        device uint *accB [[buffer(1)]],
        device const uint *nttBk [[buffer(2)]],
        device const uint *lweA [[buffer(3)]],
        constant BRNTTUniforms &U [[buffer(4)]],
        device const uint *tw [[buffer(5)]],
        device uint *scratch [[buffer(6)]],
        threadgroup uint *mem [[threadgroup(0)]],
        uint k [[thread_index_in_threadgroup]]
    ) {
        uint n = U.n;
        uint logn = U.logN;
        uint levels = U.levelCount;
        threadgroup uint *shAccM = mem;
        threadgroup uint *shAccB = mem + n;
        threadgroup uint *sh = mem + 2u * n;
        threadgroup uint *tmp = mem + 3u * n;
        shAccM[k] = accM[k];
        shAccB[k] = accB[k];
        threadgroup_barrier(mem_flags::mem_threadgroup);

        uint polysPerBit = 4u * levels;
        uint bitStride = 3u * polysPerBit * n;
        uint primeStride = polysPerBit * n;
        uint ps[3] = {U.p0, U.p1, U.p2};
        uint nInvs[3] = {U.nInv0, U.nInv1, U.nInv2};

        for (uint bit = U.bitLo; bit < U.bitHi; ++bit) {
            uint pwr = rotation_power(lweA[bit], U.twoN, U.shift);
            uint p0 = pwr % n;
            uint wrapExtra = pwr / n;
            uint i = (k >= p0) ? (k - p0) : (k + n - p0);
            uint wraps = wrapExtra + ((k < p0) ? 1u : 0u);
            uint rotM = shAccM[i];
            uint rotB = shAccB[i];
            if (wraps & 1u) {
                rotM = 0u - rotM;
                rotB = 0u - rotB;
            }
            sh[k] = rotM - shAccM[k];
            tmp[k] = rotB - shAccB[k];
            threadgroup_barrier(mem_flags::mem_threadgroup);

            uint remM = sh[k];
            uint remB = tmp[k];
            for (uint lv = 0u; lv < levels; ++lv) {
                scratch[lv * n + k] = take_digit(&remM, U.baseLog, lv);
                scratch[(levels + lv) * n + k] = take_digit(&remB, U.baseLog, lv);
            }
            threadgroup_barrier(mem_flags::mem_threadgroup);

            uint resMOff = 2u * levels * n;
            uint resBOff = resMOff + 3u * n;
            device const uint *bkBit = nttBk + bit * bitStride;

            for (uint pi = 0u; pi < 3u; ++pi) {
                uint p = ps[pi];
                device const uint *psiPow = tw + pi * 4u * n;
                device const uint *psiInvPow = psiPow + n;
                device const uint *omegaPow = psiInvPow + n;
                device const uint *omegaInvPow = omegaPow + n;
                device const uint *bkP = bkBit + pi * primeStride;

                uint accHatM = 0u;
                uint accHatB = 0u;
                for (uint lv = 0u; lv < levels; ++lv) {
                    ntt_from_device(
                        sh, tmp, scratch + lv * n,
                        psiPow, omegaPow, n, logn, p, k
                    );
                    uint hatDm = sh[k];
                    ntt_from_device(
                        sh, tmp, scratch + (levels + lv) * n,
                        psiPow, omegaPow, n, logn, p, k
                    );
                    uint hatDb = sh[k];
                    device const uint *g0m = bkP + (lv * 4u) * n;
                    device const uint *g0b = g0m + n;
                    device const uint *g1m = g0b + n;
                    device const uint *g1b = g1m + n;
                    accHatM = mod_add(
                        accHatM,
                        mod_add(mod_mul(g0m[k], hatDm, p), mod_mul(g1m[k], hatDb, p), p),
                        p
                    );
                    accHatB = mod_add(
                        accHatB,
                        mod_add(mod_mul(g0b[k], hatDm, p), mod_mul(g1b[k], hatDb, p), p),
                        p
                    );
                    threadgroup_barrier(mem_flags::mem_threadgroup);
                }

                sh[k] = accHatM;
                threadgroup_barrier(mem_flags::mem_threadgroup);
                intt_sh(sh, tmp, psiInvPow, omegaInvPow, nInvs[pi], n, logn, p, k);
                scratch[resMOff + pi * n + k] = sh[k];
                threadgroup_barrier(mem_flags::mem_threadgroup);

                sh[k] = accHatB;
                threadgroup_barrier(mem_flags::mem_threadgroup);
                intt_sh(sh, tmp, psiInvPow, omegaInvPow, nInvs[pi], n, logn, p, k);
                scratch[resBOff + pi * n + k] = sh[k];
                threadgroup_barrier(mem_flags::mem_threadgroup);
            }

            uint gatedM = crt_u32(
                scratch[resMOff + k],
                scratch[resMOff + n + k],
                scratch[resMOff + 2u * n + k],
                U
            );
            uint gatedB = crt_u32(
                scratch[resBOff + k],
                scratch[resBOff + n + k],
                scratch[resBOff + 2u * n + k],
                U
            );
            shAccM[k] += gatedM;
            shAccB[k] += gatedB;
            threadgroup_barrier(mem_flags::mem_threadgroup);
        }
        accM[k] = shAccM[k];
        accB[k] = shAccB[k];
    }
    """

    init(device: MTLDevice, n: Int, levelCount: Int, bitCount: Int) throws {
        self.device = device
        self.n = n
        self.levelCount = levelCount
        self.bitCount = bitCount
        let t0 = CFAbsoluteTimeGetCurrent()
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: Self.shaderSource, options: nil)
        } catch {
            throw MetalPolyMulError.shaderCompile(String(describing: error))
        }
        guard let fn = library.makeFunction(name: "helut_blind_rotate_ntt_tile") else {
            throw MetalPolyMulError.shaderCompile("missing helut_blind_rotate_ntt_tile")
        }
        self.pipeline = try device.makeComputePipelineState(function: fn)
        encodeSeconds = CFAbsoluteTimeGetCurrent() - t0
        self.canFuseThreadgroup = pipeline.maxTotalThreadsPerThreadgroup >= n
            && n.nonzeroBitCount == 1 && n >= 8
        let polyBytes = n * MemoryLayout<UInt32>.stride
        let nttBkBytes = bitCount * 3 * levelCount * 4 * polyBytes
        let scratchUints = (2 * levelCount + 6) * n
        let tw = NegacyclicNTT.twiddleTable(n: n)
        guard
            let accMaskBuf = device.makeBuffer(length: polyBytes, options: .storageModeShared),
            let accBodyBuf = device.makeBuffer(length: polyBytes, options: .storageModeShared),
            let nttBkBuf = device.makeBuffer(length: max(nttBkBytes, 16), options: .storageModeShared),
            let lweABuf = device.makeBuffer(
                length: bitCount * MemoryLayout<UInt32>.stride, options: .storageModeShared
            ),
            let twiddleBuf = device.makeBuffer(
                bytes: tw, length: tw.count * 4, options: .storageModeShared
            ),
            let scratchBuf = device.makeBuffer(
                length: max(scratchUints * 4, 16), options: .storageModeShared
            ),
            let uniBuf = device.makeBuffer(
                length: MemoryLayout<BRNTTUniforms>.stride, options: .storageModeShared
            )
        else {
            throw MetalPolyMulError.shaderCompile("NTT BR buffer alloc failed")
        }
        self.accMaskBuf = accMaskBuf
        self.accBodyBuf = accBodyBuf
        self.nttBkBuf = nttBkBuf
        self.lweABuf = lweABuf
        self.twiddleBuf = twiddleBuf
        self.scratchBuf = scratchBuf
        self.uniBuf = uniBuf
    }

    func takeTimings() -> (encode: Double, gpu: Double, copy: Double) {
        lock.lock()
        defer { lock.unlock() }
        let t = (encodeSeconds, gpuSeconds, copySeconds)
        encodeSeconds = 0
        gpuSeconds = 0
        copySeconds = 0
        return t
    }

    private static func fingerprint(_ words: [UInt32]) -> UInt64 {
        var h: UInt64 = UInt64(words.count) &* 0x9E3779B97F4A7C15
        if words.isEmpty { return h }
        h ^= UInt64(words[0])
        h ^= UInt64(words[words.count - 1]) &* 0x100000001b3
        let stride = max(1, words.count / 32)
        var i = 0
        while i < words.count {
            h ^= UInt64(words[i])
            h = h &* 0x100000001b3
            i += stride
        }
        return h
    }

    func blindRotate(
        accMask: [UInt32],
        accBody: [UInt32],
        packedCoeffBK: [UInt32],
        lweA: [UInt32],
        baseLog: Int,
        tileWidth: Int,
        queue: MTLCommandQueue,
        progress: ((String) -> Void)?
    ) throws -> (mask: [UInt32], body: [UInt32]) {
        precondition(accMask.count == n && accBody.count == n)
        precondition(lweA.count == bitCount)
        precondition(packedCoeffBK.count == bitCount * levelCount * 4 * n)
        precondition(canFuseThreadgroup, "NTT BR threadgroup too small for N=\(n)")
        lock.lock()
        defer { lock.unlock() }

        let c0 = CFAbsoluteTimeGetCurrent()
        accMask.withUnsafeBytes { raw in
            accMaskBuf.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
        }
        accBody.withUnsafeBytes { raw in
            accBodyBuf.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
        }
        lweA.withUnsafeBytes { raw in
            lweABuf.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
        }
        copySeconds += CFAbsoluteTimeGetCurrent() - c0
        let fp = Self.fingerprint(packedCoeffBK)
        if fp != bkFingerprint {
            let tNTT = CFAbsoluteTimeGetCurrent()
            let nttPacked = nttDomainBootstrapKey(
                packedCoeffBK, n: n, levelCount: levelCount, bitCount: bitCount
            )
            encodeSeconds += CFAbsoluteTimeGetCurrent() - tNTT
            let tUp = CFAbsoluteTimeGetCurrent()
            nttPacked.withUnsafeBytes { raw in
                nttBkBuf.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }
            copySeconds += CFAbsoluteTimeGetCurrent() - tUp
            bkFingerprint = fp
        }

        let w = max(1, tileWidth)
        let tileCount = (bitCount + w - 1) / w
        let twoN = 2 * n
        let shift = 32 - twoN.trailingZeroBitCount
        let tgBytes = 4 * n * MemoryLayout<UInt32>.stride
        let tg = MTLSize(width: n, height: 1, depth: 1)
        let groups = MTLSize(width: 1, height: 1, depth: 1)
        let p01 = UInt64(NegacyclicNTT.primes[0]) * UInt64(NegacyclicNTT.primes[1])
        let P = NegacyclicNTT.crtModulusProduct

        for tile in 0..<tileCount {
            let lo = tile * w
            let hi = min(lo + w, bitCount)
            progress?("BR tile=\(tile + 1)/\(tileCount) bits=\(lo)..<\(hi)")
            var uniforms = BRNTTUniforms(
                n: UInt32(n),
                twoN: UInt32(twoN),
                bitLo: UInt32(lo),
                bitHi: UInt32(hi),
                levelCount: UInt32(levelCount),
                baseLog: UInt32(baseLog),
                shift: UInt32(shift),
                logN: UInt32(n.trailingZeroBitCount),
                p0: NegacyclicNTT.primes[0],
                p1: NegacyclicNTT.primes[1],
                p2: NegacyclicNTT.primes[2],
                nInv0: NegacyclicNTT.modulus(primeIndex: 0, n: n).nInv,
                nInv1: NegacyclicNTT.modulus(primeIndex: 1, n: n).nInv,
                nInv2: NegacyclicNTT.modulus(primeIndex: 2, n: n).nInv,
                invP0ModP1: NegacyclicNTT.crtInvP0ModP1,
                invP01ModP2: NegacyclicNTT.crtInvP01ModP2,
                p01Lo: UInt32(truncatingIfNeeded: p01),
                p01Hi: UInt32(truncatingIfNeeded: p01 >> 32),
                pLoLo: UInt32(truncatingIfNeeded: P.lo),
                pLoHi: UInt32(truncatingIfNeeded: P.lo >> 32),
                pHiLo: UInt32(truncatingIfNeeded: P.hi),
                pHiHi: UInt32(truncatingIfNeeded: P.hi >> 32),
                pad0: 0,
                pad1: 0
            )
            withUnsafeBytes(of: &uniforms) { raw in
                uniBuf.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }
            guard let cmd = queue.makeCommandBuffer(),
                  let enc = cmd.makeComputeCommandEncoder() else {
                throw MetalPolyMulError.noCommandBuffer
            }
            enc.setComputePipelineState(pipeline)
            enc.setBuffer(accMaskBuf, offset: 0, index: 0)
            enc.setBuffer(accBodyBuf, offset: 0, index: 1)
            enc.setBuffer(nttBkBuf, offset: 0, index: 2)
            enc.setBuffer(lweABuf, offset: 0, index: 3)
            enc.setBuffer(uniBuf, offset: 0, index: 4)
            enc.setBuffer(twiddleBuf, offset: 0, index: 5)
            enc.setBuffer(scratchBuf, offset: 0, index: 6)
            enc.setThreadgroupMemoryLength(tgBytes, index: 0)
            enc.dispatchThreadgroups(groups, threadsPerThreadgroup: tg)
            enc.endEncoding()
            let g0 = CFAbsoluteTimeGetCurrent()
            cmd.commit()
            cmd.waitUntilCompleted()
            gpuSeconds += CFAbsoluteTimeGetCurrent() - g0
            if let err = cmd.error {
                throw MetalPolyMulError.shaderCompile("NTT BR tile GPU: \(err)")
            }
        }

        let c1 = CFAbsoluteTimeGetCurrent()
        let mPtr = accMaskBuf.contents().bindMemory(to: UInt32.self, capacity: n)
        let bPtr = accBodyBuf.contents().bindMemory(to: UInt32.self, capacity: n)
        let mask = Array(UnsafeBufferPointer(start: mPtr, count: n))
        let body = Array(UnsafeBufferPointer(start: bPtr, count: n))
        copySeconds += CFAbsoluteTimeGetCurrent() - c1
        return (mask, body)
    }
}

enum MetalBRNTTCache {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var engines: [String: MetalBRNTTEngine] = [:]

    static func engine(
        device: MTLDevice, n: Int, levelCount: Int, bitCount: Int
    ) throws -> MetalBRNTTEngine {
        let key = "\(ObjectIdentifier(device))-\(n)-\(levelCount)-\(bitCount)"
        lock.lock()
        defer { lock.unlock() }
        if let existing = engines[key] { return existing }
        let created = try MetalBRNTTEngine(
            device: device, n: n, levelCount: levelCount, bitCount: bitCount
        )
        engines[key] = created
        return created
    }
}
