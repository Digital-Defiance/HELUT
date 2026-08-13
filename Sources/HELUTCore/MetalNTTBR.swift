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

private struct NTTScratch {
    let accMaskBuf: MTLBuffer
    let accBodyBuf: MTLBuffer
    let lweABuf: MTLBuffer
    let scratchBuf: MTLBuffer
    let uniBuf: MTLBuffer
}

final class MetalBRNTTEngine: @unchecked Sendable {
    let device: MTLDevice
    let pipeline: MTLComputePipelineState
    let n: Int
    let levelCount: Int
    let bitCount: Int
    let canFuseThreadgroup: Bool
    private let nttBkBuf: MTLBuffer
    private let twiddleBuf: MTLBuffer
    private let lock = NSLock()
    private var scratchPool: [NTTScratch] = []
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

    void bitrev_plane(threadgroup uint *a, threadgroup uint *tmp, uint logn, uint k) {
        tmp[bitrev(k, logn)] = a[k];
        threadgroup_barrier(mem_flags::mem_threadgroup);
        a[k] = tmp[k];
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }

    void ntt_inplace_3p(
        threadgroup uint *a0,
        threadgroup uint *a1,
        threadgroup uint *a2,
        uint n,
        device const uint *w0,
        device const uint *w1,
        device const uint *w2,
        uint pA,
        uint pB,
        uint pC,
        uint k
    ) {
        for (uint len = 2u; len <= n; len <<= 1) {
            uint halfLen = len >> 1;
            if (k < (n >> 1)) {
                uint block = k / halfLen;
                uint j = k % halfLen;
                uint i0 = block * len + j;
                uint i1 = i0 + halfLen;
                uint widx = (n / len) * j;
                uint u0 = a0[i0];
                uint v0 = mod_mul(a0[i1], w0[widx], pA);
                a0[i0] = mod_add(u0, v0, pA);
                a0[i1] = mod_sub(u0, v0, pA);
                uint u1 = a1[i0];
                uint v1 = mod_mul(a1[i1], w1[widx], pB);
                a1[i0] = mod_add(u1, v1, pB);
                a1[i1] = mod_sub(u1, v1, pB);
                uint u2 = a2[i0];
                uint v2 = mod_mul(a2[i1], w2[widx], pC);
                a2[i0] = mod_add(u2, v2, pC);
                a2[i1] = mod_sub(u2, v2, pC);
            }
            threadgroup_barrier(mem_flags::mem_threadgroup);
        }
    }

    void ntt_from_device_3p(
        threadgroup uint *pl0,
        threadgroup uint *pl1,
        threadgroup uint *pl2,
        threadgroup uint *tmp,
        device const uint *in,
        device const uint *tw,
        uint n,
        uint logn,
        uint pA,
        uint pB,
        uint pC,
        uint k
    ) {
        device const uint *psi0 = tw;
        device const uint *psi1 = tw + 4u * n;
        device const uint *psi2 = tw + 8u * n;
        pl0[k] = mod_mul(in[k] % pA, psi0[k], pA);
        pl1[k] = mod_mul(in[k] % pB, psi1[k], pB);
        pl2[k] = mod_mul(in[k] % pC, psi2[k], pC);
        threadgroup_barrier(mem_flags::mem_threadgroup);
        bitrev_plane(pl0, tmp, logn, k);
        bitrev_plane(pl1, tmp, logn, k);
        bitrev_plane(pl2, tmp, logn, k);
        ntt_inplace_3p(
            pl0, pl1, pl2, n,
            tw + 2u * n, tw + 6u * n, tw + 10u * n,
            pA, pB, pC, k
        );
    }

    void intt_3p(
        threadgroup uint *pl0,
        threadgroup uint *pl1,
        threadgroup uint *pl2,
        threadgroup uint *tmp,
        device const uint *tw,
        uint n,
        uint logn,
        uint nInv0,
        uint nInv1,
        uint nInv2,
        uint pA,
        uint pB,
        uint pC,
        uint k
    ) {
        bitrev_plane(pl0, tmp, logn, k);
        bitrev_plane(pl1, tmp, logn, k);
        bitrev_plane(pl2, tmp, logn, k);
        ntt_inplace_3p(
            pl0, pl1, pl2, n,
            tw + 3u * n, tw + 7u * n, tw + 11u * n,
            pA, pB, pC, k
        );
        device const uint *psiI0 = tw + n;
        device const uint *psiI1 = tw + 5u * n;
        device const uint *psiI2 = tw + 9u * n;
        pl0[k] = mod_mul(mod_mul(pl0[k], nInv0, pA), psiI0[k], pA);
        pl1[k] = mod_mul(mod_mul(pl1[k], nInv1, pB), psiI1[k], pB);
        pl2[k] = mod_mul(mod_mul(pl2[k], nInv2, pC), psiI2[k], pC);
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
        uint pA = U.p0;
        uint pB = U.p1;
        uint pC = U.p2;
        threadgroup uint *shAccM = mem;
        threadgroup uint *shAccB = mem + n;
        threadgroup uint *pl0 = mem + 2u * n;
        threadgroup uint *pl1 = mem + 3u * n;
        threadgroup uint *pl2 = mem + 4u * n;
        threadgroup uint *tmp = mem + 5u * n;
        shAccM[k] = accM[k];
        shAccB[k] = accB[k];
        threadgroup_barrier(mem_flags::mem_threadgroup);

        uint polysPerBit = 4u * levels;
        uint bitStride = 3u * polysPerBit * n;
        uint primeStride = polysPerBit * n;

        for (uint bit = U.bitLo; bit < U.bitHi; ++bit) {
            uint pwr = rotation_power(lweA[bit], U.twoN, U.shift);
            uint rotOff = pwr % n;
            uint wrapExtra = pwr / n;
            uint i = (k >= rotOff) ? (k - rotOff) : (k + n - rotOff);
            uint wraps = wrapExtra + ((k < rotOff) ? 1u : 0u);
            uint rotM = shAccM[i];
            uint rotB = shAccB[i];
            if (wraps & 1u) {
                rotM = 0u - rotM;
                rotB = 0u - rotB;
            }
            pl0[k] = rotM - shAccM[k];
            pl1[k] = rotB - shAccB[k];
            threadgroup_barrier(mem_flags::mem_threadgroup);

            uint remM = pl0[k];
            uint remB = pl1[k];
            for (uint lv = 0u; lv < levels; ++lv) {
                scratch[lv * n + k] = take_digit(&remM, U.baseLog, lv);
                scratch[(levels + lv) * n + k] = take_digit(&remB, U.baseLog, lv);
            }
            threadgroup_barrier(mem_flags::mem_threadgroup);

            uint resMOff = 2u * levels * n;
            uint resBOff = resMOff + 3u * n;
            device const uint *bkBit = nttBk + bit * bitStride;

            uint accHatM0 = 0u, accHatM1 = 0u, accHatM2 = 0u;
            uint accHatB0 = 0u, accHatB1 = 0u, accHatB2 = 0u;
            for (uint lv = 0u; lv < levels; ++lv) {
                ntt_from_device_3p(
                    pl0, pl1, pl2, tmp, scratch + lv * n, tw,
                    n, logn, pA, pB, pC, k
                );
                uint hDm0 = pl0[k], hDm1 = pl1[k], hDm2 = pl2[k];
                ntt_from_device_3p(
                    pl0, pl1, pl2, tmp, scratch + (levels + lv) * n, tw,
                    n, logn, pA, pB, pC, k
                );
                uint hDb0 = pl0[k], hDb1 = pl1[k], hDb2 = pl2[k];
                device const uint *g0m0 = bkBit + (lv * 4u) * n;
                device const uint *g0m1 = bkBit + primeStride + (lv * 4u) * n;
                device const uint *g0m2 = bkBit + 2u * primeStride + (lv * 4u) * n;
                accHatM0 = mod_add(
                    accHatM0,
                    mod_add(mod_mul(g0m0[k], hDm0, pA), mod_mul(g0m0[k + 2u * n], hDb0, pA), pA),
                    pA
                );
                accHatB0 = mod_add(
                    accHatB0,
                    mod_add(mod_mul(g0m0[k + n], hDm0, pA), mod_mul(g0m0[k + 3u * n], hDb0, pA), pA),
                    pA
                );
                accHatM1 = mod_add(
                    accHatM1,
                    mod_add(mod_mul(g0m1[k], hDm1, pB), mod_mul(g0m1[k + 2u * n], hDb1, pB), pB),
                    pB
                );
                accHatB1 = mod_add(
                    accHatB1,
                    mod_add(mod_mul(g0m1[k + n], hDm1, pB), mod_mul(g0m1[k + 3u * n], hDb1, pB), pB),
                    pB
                );
                accHatM2 = mod_add(
                    accHatM2,
                    mod_add(mod_mul(g0m2[k], hDm2, pC), mod_mul(g0m2[k + 2u * n], hDb2, pC), pC),
                    pC
                );
                accHatB2 = mod_add(
                    accHatB2,
                    mod_add(mod_mul(g0m2[k + n], hDm2, pC), mod_mul(g0m2[k + 3u * n], hDb2, pC), pC),
                    pC
                );
                threadgroup_barrier(mem_flags::mem_threadgroup);
            }

            pl0[k] = accHatM0;
            pl1[k] = accHatM1;
            pl2[k] = accHatM2;
            threadgroup_barrier(mem_flags::mem_threadgroup);
            intt_3p(
                pl0, pl1, pl2, tmp, tw, n, logn,
                U.nInv0, U.nInv1, U.nInv2, pA, pB, pC, k
            );
            scratch[resMOff + k] = pl0[k];
            scratch[resMOff + n + k] = pl1[k];
            scratch[resMOff + 2u * n + k] = pl2[k];
            threadgroup_barrier(mem_flags::mem_threadgroup);

            pl0[k] = accHatB0;
            pl1[k] = accHatB1;
            pl2[k] = accHatB2;
            threadgroup_barrier(mem_flags::mem_threadgroup);
            intt_3p(
                pl0, pl1, pl2, tmp, tw, n, logn,
                U.nInv0, U.nInv1, U.nInv2, pA, pB, pC, k
            );
            scratch[resBOff + k] = pl0[k];
            scratch[resBOff + n + k] = pl1[k];
            scratch[resBOff + 2u * n + k] = pl2[k];
            threadgroup_barrier(mem_flags::mem_threadgroup);

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
        let tgNeed = 6 * n * MemoryLayout<UInt32>.stride
        self.canFuseThreadgroup = pipeline.maxTotalThreadsPerThreadgroup >= n
            && n.nonzeroBitCount == 1 && n >= 8
            && device.maxThreadgroupMemoryLength >= tgNeed
        let polyBytes = n * MemoryLayout<UInt32>.stride
        let nttBkBytes = bitCount * 3 * levelCount * 4 * polyBytes
        let tw = NegacyclicNTT.twiddleTable(n: n)
        guard
            let nttBkBuf = device.makeBuffer(length: max(nttBkBytes, 16), options: .storageModeShared),
            let twiddleBuf = device.makeBuffer(
                bytes: tw, length: tw.count * 4, options: .storageModeShared
            )
        else {
            throw MetalPolyMulError.shaderCompile("NTT BR buffer alloc failed")
        }
        self.nttBkBuf = nttBkBuf
        self.twiddleBuf = twiddleBuf
        scratchPool.append(try makeScratch())
    }

    private func makeScratch() throws -> NTTScratch {
        let polyBytes = n * MemoryLayout<UInt32>.stride
        let scratchUints = (2 * levelCount + 6) * n
        guard
            let accMaskBuf = device.makeBuffer(length: polyBytes, options: .storageModeShared),
            let accBodyBuf = device.makeBuffer(length: polyBytes, options: .storageModeShared),
            let lweABuf = device.makeBuffer(
                length: bitCount * MemoryLayout<UInt32>.stride, options: .storageModeShared
            ),
            let scratchBuf = device.makeBuffer(
                length: max(scratchUints * 4, 16), options: .storageModeShared
            ),
            let uniBuf = device.makeBuffer(
                length: MemoryLayout<BRNTTUniforms>.stride, options: .storageModeShared
            )
        else {
            throw MetalPolyMulError.shaderCompile("NTT BR scratch alloc failed")
        }
        return NTTScratch(
            accMaskBuf: accMaskBuf,
            accBodyBuf: accBodyBuf,
            lweABuf: lweABuf,
            scratchBuf: scratchBuf,
            uniBuf: uniBuf
        )
    }

    private func checkoutScratch() throws -> NTTScratch {
        lock.lock()
        if let hit = scratchPool.popLast() {
            lock.unlock()
            return hit
        }
        lock.unlock()
        return try makeScratch()
    }

    private func checkinScratch(_ scratch: NTTScratch) {
        lock.lock()
        scratchPool.append(scratch)
        lock.unlock()
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
        let slot = try checkoutScratch()
        defer { checkinScratch(slot) }

        lock.lock()
        let fp = Self.fingerprint(packedCoeffBK)
        if fp != bkFingerprint {
            let tNTT = CFAbsoluteTimeGetCurrent()
            let nttPacked = nttDomainBootstrapKey(
                packedCoeffBK, n: n, levelCount: levelCount, bitCount: bitCount
            )
            encodeSeconds += CFAbsoluteTimeGetCurrent() - tNTT
            nttPacked.withUnsafeBytes { raw in
                nttBkBuf.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }
            bkFingerprint = fp
        }
        lock.unlock()

        let c0 = CFAbsoluteTimeGetCurrent()
        accMask.withUnsafeBytes { raw in
            slot.accMaskBuf.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
        }
        accBody.withUnsafeBytes { raw in
            slot.accBodyBuf.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
        }
        lweA.withUnsafeBytes { raw in
            slot.lweABuf.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
        }
        lock.lock()
        copySeconds += CFAbsoluteTimeGetCurrent() - c0
        lock.unlock()

        let w = max(1, tileWidth)
        let tileCount = (bitCount + w - 1) / w
        let twoN = 2 * n
        let shift = 32 - twoN.trailingZeroBitCount
        let tgBytes = 6 * n * MemoryLayout<UInt32>.stride
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
                slot.uniBuf.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }
            guard let cmd = queue.makeCommandBuffer(),
                  let enc = cmd.makeComputeCommandEncoder() else {
                throw MetalPolyMulError.noCommandBuffer
            }
            enc.setComputePipelineState(pipeline)
            enc.setBuffer(slot.accMaskBuf, offset: 0, index: 0)
            enc.setBuffer(slot.accBodyBuf, offset: 0, index: 1)
            enc.setBuffer(nttBkBuf, offset: 0, index: 2)
            enc.setBuffer(slot.lweABuf, offset: 0, index: 3)
            enc.setBuffer(slot.uniBuf, offset: 0, index: 4)
            enc.setBuffer(twiddleBuf, offset: 0, index: 5)
            enc.setBuffer(slot.scratchBuf, offset: 0, index: 6)
            enc.setThreadgroupMemoryLength(tgBytes, index: 0)
            enc.dispatchThreadgroups(groups, threadsPerThreadgroup: tg)
            enc.endEncoding()
            let g0 = CFAbsoluteTimeGetCurrent()
            cmd.commit()
            cmd.waitUntilCompleted()
            lock.lock()
            gpuSeconds += CFAbsoluteTimeGetCurrent() - g0
            lock.unlock()
            if let err = cmd.error {
                throw MetalPolyMulError.shaderCompile("NTT BR tile GPU: \(err)")
            }
        }

        let c1 = CFAbsoluteTimeGetCurrent()
        let mPtr = slot.accMaskBuf.contents().bindMemory(to: UInt32.self, capacity: n)
        let bPtr = slot.accBodyBuf.contents().bindMemory(to: UInt32.self, capacity: n)
        let mask = Array(UnsafeBufferPointer(start: mPtr, count: n))
        let body = Array(UnsafeBufferPointer(start: bPtr, count: n))
        lock.lock()
        copySeconds += CFAbsoluteTimeGetCurrent() - c1
        lock.unlock()
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
