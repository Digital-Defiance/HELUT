import Foundation
import Metal

// MARK: - Metal 3-prime twisted NTT poly-mul (Phase 2 NTT)
//
// Same math as `NegacyclicNTT.multiply`. One threadgroup of N. Bit-identical
// to CPU schoolbook (certified by MetalCompilerPhase1Tests + NegacyclicNTTTests).

private struct NTTMulUniforms {
    var n: UInt32
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
}

final class MetalNTTMulEngine: @unchecked Sendable {
    let device: MTLDevice
    let pipeline: MTLComputePipelineState
    let n: Int
    let canFuse: Bool
    private let aBuf: MTLBuffer
    private let bBuf: MTLBuffer
    private let outBuf: MTLBuffer
    private let twiddleBuf: MTLBuffer
    private let resBuf: MTLBuffer
    private let uniBuf: MTLBuffer
    private let lock = NSLock()

    static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct NTTMulUniforms {
        uint n;
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

    [[max_total_threads_per_threadgroup(1024)]]
    kernel void helut_negacyclic_ntt_mul(
        device const uint *inA [[buffer(0)]],
        device const uint *inB [[buffer(1)]],
        device uint *out [[buffer(2)]],
        device const uint *tw [[buffer(3)]],
        device uint *res [[buffer(4)]],
        constant NTTMulUniforms &U [[buffer(5)]],
        threadgroup uint *mem [[threadgroup(0)]],
        uint k [[thread_index_in_threadgroup]]
    ) {
        uint n = U.n;
        uint logn = U.logN;
        threadgroup uint *sh = mem;
        threadgroup uint *tmp = mem + n;
        uint ps[3] = {U.p0, U.p1, U.p2};
        uint nInvs[3] = {U.nInv0, U.nInv1, U.nInv2};

        for (uint pi = 0u; pi < 3u; ++pi) {
            uint p = ps[pi];
            device const uint *psiPow = tw + pi * 4u * n;
            device const uint *psiInvPow = psiPow + n;
            device const uint *omegaPow = psiInvPow + n;
            device const uint *omegaInvPow = omegaPow + n;

            sh[k] = mod_mul(inA[k] % p, psiPow[k], p);
            threadgroup_barrier(mem_flags::mem_threadgroup);
            tmp[bitrev(k, logn)] = sh[k];
            threadgroup_barrier(mem_flags::mem_threadgroup);
            sh[k] = tmp[k];
            threadgroup_barrier(mem_flags::mem_threadgroup);
            ntt_inplace(sh, n, omegaPow, p, k);
            res[pi * n + k] = sh[k];
            threadgroup_barrier(mem_flags::mem_threadgroup);

            sh[k] = mod_mul(inB[k] % p, psiPow[k], p);
            threadgroup_barrier(mem_flags::mem_threadgroup);
            tmp[bitrev(k, logn)] = sh[k];
            threadgroup_barrier(mem_flags::mem_threadgroup);
            sh[k] = tmp[k];
            threadgroup_barrier(mem_flags::mem_threadgroup);
            ntt_inplace(sh, n, omegaPow, p, k);
            sh[k] = mod_mul(sh[k], res[pi * n + k], p);
            threadgroup_barrier(mem_flags::mem_threadgroup);

            tmp[bitrev(k, logn)] = sh[k];
            threadgroup_barrier(mem_flags::mem_threadgroup);
            sh[k] = tmp[k];
            threadgroup_barrier(mem_flags::mem_threadgroup);
            ntt_inplace(sh, n, omegaInvPow, p, k);
            res[pi * n + k] = mod_mul(mod_mul(sh[k], nInvs[pi], p), psiInvPow[k], p);
            threadgroup_barrier(mem_flags::mem_threadgroup);
        }

        uint a0 = res[k];
        uint a1 = res[n + k];
        uint a2 = res[2u * n + k];
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
        out[k] = uint(xlo);
    }
    """

    init(device: MTLDevice, n: Int) throws {
        self.device = device
        self.n = n
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: Self.shaderSource, options: nil)
        } catch {
            throw MetalPolyMulError.shaderCompile(String(describing: error))
        }
        guard let fn = library.makeFunction(name: "helut_negacyclic_ntt_mul") else {
            throw MetalPolyMulError.shaderCompile("missing helut_negacyclic_ntt_mul")
        }
        self.pipeline = try device.makeComputePipelineState(function: fn)
        self.canFuse = pipeline.maxTotalThreadsPerThreadgroup >= n && n.nonzeroBitCount == 1 && n >= 8
        let polyBytes = n * MemoryLayout<UInt32>.stride
        let tw = NegacyclicNTT.twiddleTable(n: n)
        guard
            let aBuf = device.makeBuffer(length: polyBytes, options: .storageModeShared),
            let bBuf = device.makeBuffer(length: polyBytes, options: .storageModeShared),
            let outBuf = device.makeBuffer(length: polyBytes, options: .storageModeShared),
            let twiddleBuf = device.makeBuffer(bytes: tw, length: tw.count * 4, options: .storageModeShared),
            let resBuf = device.makeBuffer(length: 3 * polyBytes, options: .storageModeShared),
            let uniBuf = device.makeBuffer(length: MemoryLayout<NTTMulUniforms>.stride, options: .storageModeShared)
        else {
            throw MetalPolyMulError.shaderCompile("NTT buffer alloc failed")
        }
        self.aBuf = aBuf
        self.bBuf = bBuf
        self.outBuf = outBuf
        self.twiddleBuf = twiddleBuf
        self.resBuf = resBuf
        self.uniBuf = uniBuf
        let p01 = UInt64(NegacyclicNTT.primes[0]) * UInt64(NegacyclicNTT.primes[1])
        let P = NegacyclicNTT.crtModulusProduct
        var u = NTTMulUniforms(
            n: UInt32(n),
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
            pHiHi: UInt32(truncatingIfNeeded: P.hi >> 32)
        )
        withUnsafeBytes(of: &u) { raw in
            uniBuf.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
        }
    }

    func multiply(_ a: [UInt32], _ b: [UInt32], queue: MTLCommandQueue) throws -> [UInt32] {
        precondition(canFuse)
        lock.lock()
        defer { lock.unlock() }
        a.withUnsafeBytes { aBuf.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        b.withUnsafeBytes { bBuf.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        guard let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeComputeCommandEncoder() else {
            throw MetalPolyMulError.noCommandBuffer
        }
        enc.setComputePipelineState(pipeline)
        enc.setBuffer(aBuf, offset: 0, index: 0)
        enc.setBuffer(bBuf, offset: 0, index: 1)
        enc.setBuffer(outBuf, offset: 0, index: 2)
        enc.setBuffer(twiddleBuf, offset: 0, index: 3)
        enc.setBuffer(resBuf, offset: 0, index: 4)
        enc.setBuffer(uniBuf, offset: 0, index: 5)
        enc.setThreadgroupMemoryLength(2 * n * 4, index: 0)
        enc.dispatchThreadgroups(MTLSize(width: 1, height: 1, depth: 1),
                                 threadsPerThreadgroup: MTLSize(width: n, height: 1, depth: 1))
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        if let err = cmd.error {
            throw MetalPolyMulError.shaderCompile("NTT GPU: \(err)")
        }
        let ptr = outBuf.contents().bindMemory(to: UInt32.self, capacity: n)
        return Array(UnsafeBufferPointer(start: ptr, count: n))
    }
}

enum MetalNTTMulCache {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var engines: [String: MetalNTTMulEngine] = [:]

    static func engine(device: MTLDevice, n: Int) throws -> MetalNTTMulEngine {
        let key = "\(ObjectIdentifier(device))-\(n)"
        lock.lock()
        defer { lock.unlock() }
        if let existing = engines[key] { return existing }
        let created = try MetalNTTMulEngine(device: device, n: n)
        engines[key] = created
        return created
    }
}

extension MetalGGSW {
    /// Prefer 3-prime NTT; fall back to schoolbook if the device cannot fuse N threads.
    package static func negacyclicPolyMulMetal(
        _ a: [UInt32],
        _ b: [UInt32],
        device: MTLDevice,
        commandQueue: MTLCommandQueue
    ) throws -> [UInt32] {
        precondition(a.count == b.count)
        let n = a.count
        if n >= 8 && n.nonzeroBitCount == 1 {
            let ntt = try MetalNTTMulCache.engine(device: device, n: n)
            if ntt.canFuse {
                return try ntt.multiply(a, b, queue: commandQueue)
            }
        }
        let engine = try MetalPolyMulCache.engine(device: device, n: n)
        return try engine.multiply(a, b, queue: commandQueue)
    }
}
