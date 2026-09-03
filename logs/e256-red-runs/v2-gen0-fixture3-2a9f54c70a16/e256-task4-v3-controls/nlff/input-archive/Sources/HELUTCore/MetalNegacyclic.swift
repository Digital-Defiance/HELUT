import Foundation
import Metal

// MARK: - Phase 1 tiled BR + Phase 2 ring kernels
//
// Fused schoolbook-in-MPSGraph at N=1024 never reached GPU (11.6 h encode, SIGTERM).
// Phase 1 control plane: CMUX tiles + host gadget/rotate.
// Phase 2.1: cached uint32 schoolbook poly-mul PSO (`negacyclicPolyMulMetal`).
// Phase 2.2: one `helut_ggsw_external_product` launch per CMUX (all gadget levels).
// Phase 2.3: GPU-resident ACC + BK; one `helut_blind_rotate_tile` launch per CMUX tile.
// Phase 2 NTT: `helut_blind_rotate_ntt_tile` inlines 3-prime twisted NTT EP (schoolbook fallback).

/// Wall split for Metal blind-rotate (claim-sheet H3 / compiler telemetry).
package struct MetalBRTelemetry: Sendable, Equatable {
    package var lowering: String
    package var tileWidth: Int
    package var tileCount: Int
    package var encodeSeconds: Double
    package var gpuRunSeconds: Double
    package var hostRepackSeconds: Double
    /// Ring kernel inside the tile: `schoolbook`, `ntt`, or `mlir`.
    package var ring: String

    package var totalSeconds: Double { encodeSeconds + gpuRunSeconds + hostRepackSeconds }

    package static let empty = MetalBRTelemetry(
        lowering: "none",
        tileWidth: 0,
        tileCount: 0,
        encodeSeconds: 0,
        gpuRunSeconds: 0,
        hostRepackSeconds: 0,
        ring: "none"
    )
}

/// How `MetalGGSW.blindRotate` lowers the CMUX chain.
package enum MetalBRLowering: String, Sendable {
    /// One MPSGraph for all CMUX levels (schoolbook poly-mul expanded to MLIR).
    case fused
    /// CMUX windows; poly-mul is a cached Metal kernel.
    case tiledKernel = "tiled-kernel"

    /// Fused is safe at N≤64 (measured). Larger N uses tiles + kernel.
    package static func automatic(degree: Int) -> MetalBRLowering {
        degree <= 64 ? .fused : .tiledKernel
    }
}

package enum MetalBRControl {
    /// Optional progress line (microbench / SING). Invoked on the caller thread.
    nonisolated(unsafe) package static var progress: ((String) -> Void)?
    nonisolated(unsafe) package static var lastTelemetry = MetalBRTelemetry.empty
    nonisolated(unsafe) package static var defaultTileWidth = 64
    nonisolated(unsafe) package static var overrideLowering: MetalBRLowering?
}

package enum MetalPolyMulError: Error, CustomStringConvertible {
    case shaderCompile(String)
    case noCommandBuffer
    case noEncoder

    package var description: String {
        switch self {
        case .shaderCompile(let s): return "Metal poly-mul shader: \(s)"
        case .noCommandBuffer: return "Metal poly-mul: no command buffer"
        case .noEncoder: return "Metal poly-mul: no compute encoder"
        }
    }
}

/// Cached `helut_negacyclic_poly_mul` PSO + scratch buffers (Phase 1.3).
final class MetalPolyMulEngine: @unchecked Sendable {
    let device: MTLDevice
    let pipeline: MTLComputePipelineState
    let n: Int
    private let aBuf: MTLBuffer
    private let bBuf: MTLBuffer
    private let outBuf: MTLBuffer
    private let nBuf: MTLBuffer
    private let lock = NSLock()
    private var encodeSeconds: Double = 0
    private var gpuSeconds: Double = 0
    private var copySeconds: Double = 0

    static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    kernel void helut_negacyclic_poly_mul(
        device const uint *a [[buffer(0)]],
        device const uint *b [[buffer(1)]],
        device uint *out [[buffer(2)]],
        constant uint &n [[buffer(3)]],
        uint k [[thread_position_in_grid]]
    ) {
        if (k >= n) return;
        uint acc = 0u;
        for (uint j = 0u; j < n; ++j) {
            uint idx = (k >= j) ? (k - j) : (k + n - j);
            uint term = a[idx] * b[j];
            acc = (k >= j) ? (acc + term) : (acc - term);
        }
        out[k] = acc;
    }
    """

    init(device: MTLDevice, n: Int) throws {
        self.device = device
        self.n = n
        let t0 = CFAbsoluteTimeGetCurrent()
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: Self.shaderSource, options: nil)
        } catch {
            throw MetalPolyMulError.shaderCompile(String(describing: error))
        }
        guard let fn = library.makeFunction(name: "helut_negacyclic_poly_mul") else {
            throw MetalPolyMulError.shaderCompile("missing helut_negacyclic_poly_mul")
        }
        self.pipeline = try device.makeComputePipelineState(function: fn)
        encodeSeconds = CFAbsoluteTimeGetCurrent() - t0
        let bytes = n * MemoryLayout<UInt32>.stride
        guard
            let aBuf = device.makeBuffer(length: bytes, options: .storageModeShared),
            let bBuf = device.makeBuffer(length: bytes, options: .storageModeShared),
            let outBuf = device.makeBuffer(length: bytes, options: .storageModeShared),
            let nBuf = device.makeBuffer(length: MemoryLayout<UInt32>.stride, options: .storageModeShared)
        else {
            throw MetalPolyMulError.shaderCompile("buffer alloc failed")
        }
        self.aBuf = aBuf
        self.bBuf = bBuf
        self.outBuf = outBuf
        self.nBuf = nBuf
        nBuf.contents().bindMemory(to: UInt32.self, capacity: 1).pointee = UInt32(n)
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

    func multiply(_ a: [UInt32], _ b: [UInt32], queue: MTLCommandQueue) throws -> [UInt32] {
        precondition(a.count == n && b.count == n)
        lock.lock()
        defer { lock.unlock() }
        let c0 = CFAbsoluteTimeGetCurrent()
        a.withUnsafeBytes { raw in
            aBuf.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
        }
        b.withUnsafeBytes { raw in
            bBuf.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
        }
        copySeconds += CFAbsoluteTimeGetCurrent() - c0

        guard let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeComputeCommandEncoder() else {
            throw MetalPolyMulError.noCommandBuffer
        }
        enc.setComputePipelineState(pipeline)
        enc.setBuffer(aBuf, offset: 0, index: 0)
        enc.setBuffer(bBuf, offset: 0, index: 1)
        enc.setBuffer(outBuf, offset: 0, index: 2)
        enc.setBuffer(nBuf, offset: 0, index: 3)
        let width = min(pipeline.maxTotalThreadsPerThreadgroup, n)
        let tg = MTLSize(width: max(width, 1), height: 1, depth: 1)
        let grid = MTLSize(width: n, height: 1, depth: 1)
        enc.dispatchThreads(grid, threadsPerThreadgroup: tg)
        enc.endEncoding()
        let g0 = CFAbsoluteTimeGetCurrent()
        cmd.commit()
        cmd.waitUntilCompleted()
        gpuSeconds += CFAbsoluteTimeGetCurrent() - g0

        let c1 = CFAbsoluteTimeGetCurrent()
        let ptr = outBuf.contents().bindMemory(to: UInt32.self, capacity: n)
        let out = Array(UnsafeBufferPointer(start: ptr, count: n))
        copySeconds += CFAbsoluteTimeGetCurrent() - c1
        return out
    }
}

enum MetalPolyMulCache {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var engines: [String: MetalPolyMulEngine] = [:]

    static func engine(device: MTLDevice, n: Int) throws -> MetalPolyMulEngine {
        let key = "\(ObjectIdentifier(device))-\(n)"
        lock.lock()
        defer { lock.unlock() }
        if let existing = engines[key] { return existing }
        let created = try MetalPolyMulEngine(device: device, n: n)
        engines[key] = created
        return created
    }
}

/// Cached fused GGSW ⋉ GLWE (Phase 2.2): one launch for all gadget levels.
private final class MetalEPEngine: @unchecked Sendable {
    let device: MTLDevice
    let pipeline: MTLComputePipelineState
    let n: Int
    let levelCount: Int
    private let dmaskBuf: MTLBuffer
    private let dbodyBuf: MTLBuffer
    private let ggswBuf: MTLBuffer
    private let outMaskBuf: MTLBuffer
    private let outBodyBuf: MTLBuffer
    private let nBuf: MTLBuffer
    private let levelBuf: MTLBuffer
    private let lock = NSLock()
    private var encodeSeconds: Double = 0
    private var gpuSeconds: Double = 0
    private var copySeconds: Double = 0

    static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    kernel void helut_ggsw_external_product(
        device const uint *dmask [[buffer(0)]],
        device const uint *dbody [[buffer(1)]],
        device const uint *ggsw [[buffer(2)]],
        device uint *outMask [[buffer(3)]],
        device uint *outBody [[buffer(4)]],
        constant uint &n [[buffer(5)]],
        constant uint &levelCount [[buffer(6)]],
        uint k [[thread_position_in_grid]]
    ) {
        if (k >= n) return;
        uint accM = 0u;
        uint accB = 0u;
        for (uint lv = 0u; lv < levelCount; ++lv) {
            device const uint *dm = dmask + lv * n;
            device const uint *db = dbody + lv * n;
            device const uint *g0m = ggsw + (lv * 4u) * n;
            device const uint *g0b = g0m + n;
            device const uint *g1m = g0b + n;
            device const uint *g1b = g1m + n;
            for (uint j = 0u; j < n; ++j) {
                uint idx = (k >= j) ? (k - j) : (k + n - j);
                uint dmj = dm[j];
                uint dbj = db[j];
                uint termM = g0m[idx] * dmj + g1m[idx] * dbj;
                uint termB = g0b[idx] * dmj + g1b[idx] * dbj;
                if (k >= j) {
                    accM += termM;
                    accB += termB;
                } else {
                    accM -= termM;
                    accB -= termB;
                }
            }
        }
        outMask[k] = accM;
        outBody[k] = accB;
    }
    """

    init(device: MTLDevice, n: Int, levelCount: Int) throws {
        self.device = device
        self.n = n
        self.levelCount = levelCount
        let t0 = CFAbsoluteTimeGetCurrent()
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: Self.shaderSource, options: nil)
        } catch {
            throw MetalPolyMulError.shaderCompile(String(describing: error))
        }
        guard let fn = library.makeFunction(name: "helut_ggsw_external_product") else {
            throw MetalPolyMulError.shaderCompile("missing helut_ggsw_external_product")
        }
        self.pipeline = try device.makeComputePipelineState(function: fn)
        encodeSeconds = CFAbsoluteTimeGetCurrent() - t0
        let polyBytes = n * MemoryLayout<UInt32>.stride
        let digitBytes = levelCount * polyBytes
        let ggswBytes = levelCount * 4 * polyBytes
        guard
            let dmaskBuf = device.makeBuffer(length: digitBytes, options: .storageModeShared),
            let dbodyBuf = device.makeBuffer(length: digitBytes, options: .storageModeShared),
            let ggswBuf = device.makeBuffer(length: ggswBytes, options: .storageModeShared),
            let outMaskBuf = device.makeBuffer(length: polyBytes, options: .storageModeShared),
            let outBodyBuf = device.makeBuffer(length: polyBytes, options: .storageModeShared),
            let nBuf = device.makeBuffer(length: MemoryLayout<UInt32>.stride, options: .storageModeShared),
            let levelBuf = device.makeBuffer(length: MemoryLayout<UInt32>.stride, options: .storageModeShared)
        else {
            throw MetalPolyMulError.shaderCompile("EP buffer alloc failed")
        }
        self.dmaskBuf = dmaskBuf
        self.dbodyBuf = dbodyBuf
        self.ggswBuf = ggswBuf
        self.outMaskBuf = outMaskBuf
        self.outBodyBuf = outBodyBuf
        self.nBuf = nBuf
        self.levelBuf = levelBuf
        nBuf.contents().bindMemory(to: UInt32.self, capacity: 1).pointee = UInt32(n)
        levelBuf.contents().bindMemory(to: UInt32.self, capacity: 1).pointee = UInt32(levelCount)
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

    func externalProduct(
        maskDigits: [[UInt32]],
        bodyDigits: [[UInt32]],
        ggswPacked: [UInt32],
        queue: MTLCommandQueue
    ) throws -> (mask: [UInt32], body: [UInt32]) {
        precondition(maskDigits.count == levelCount && bodyDigits.count == levelCount)
        precondition(ggswPacked.count == levelCount * 4 * n)
        lock.lock()
        defer { lock.unlock() }
        let c0 = CFAbsoluteTimeGetCurrent()
        var flatM: [UInt32] = []
        var flatB: [UInt32] = []
        flatM.reserveCapacity(levelCount * n)
        flatB.reserveCapacity(levelCount * n)
        for lv in 0..<levelCount {
            precondition(maskDigits[lv].count == n && bodyDigits[lv].count == n)
            flatM.append(contentsOf: maskDigits[lv])
            flatB.append(contentsOf: bodyDigits[lv])
        }
        flatM.withUnsafeBytes { raw in
            dmaskBuf.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
        }
        flatB.withUnsafeBytes { raw in
            dbodyBuf.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
        }
        ggswPacked.withUnsafeBytes { raw in
            ggswBuf.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
        }
        copySeconds += CFAbsoluteTimeGetCurrent() - c0

        guard let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeComputeCommandEncoder() else {
            throw MetalPolyMulError.noCommandBuffer
        }
        enc.setComputePipelineState(pipeline)
        enc.setBuffer(dmaskBuf, offset: 0, index: 0)
        enc.setBuffer(dbodyBuf, offset: 0, index: 1)
        enc.setBuffer(ggswBuf, offset: 0, index: 2)
        enc.setBuffer(outMaskBuf, offset: 0, index: 3)
        enc.setBuffer(outBodyBuf, offset: 0, index: 4)
        enc.setBuffer(nBuf, offset: 0, index: 5)
        enc.setBuffer(levelBuf, offset: 0, index: 6)
        let width = min(pipeline.maxTotalThreadsPerThreadgroup, n)
        let tg = MTLSize(width: max(width, 1), height: 1, depth: 1)
        let grid = MTLSize(width: n, height: 1, depth: 1)
        enc.dispatchThreads(grid, threadsPerThreadgroup: tg)
        enc.endEncoding()
        let g0 = CFAbsoluteTimeGetCurrent()
        cmd.commit()
        cmd.waitUntilCompleted()
        gpuSeconds += CFAbsoluteTimeGetCurrent() - g0

        let c1 = CFAbsoluteTimeGetCurrent()
        let mPtr = outMaskBuf.contents().bindMemory(to: UInt32.self, capacity: n)
        let bPtr = outBodyBuf.contents().bindMemory(to: UInt32.self, capacity: n)
        let mask = Array(UnsafeBufferPointer(start: mPtr, count: n))
        let body = Array(UnsafeBufferPointer(start: bPtr, count: n))
        copySeconds += CFAbsoluteTimeGetCurrent() - c1
        return (mask, body)
    }
}

private enum MetalEPCache {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var engines: [String: MetalEPEngine] = [:]

    static func engine(device: MTLDevice, n: Int, levelCount: Int) throws -> MetalEPEngine {
        let key = "\(ObjectIdentifier(device))-\(n)-\(levelCount)"
        lock.lock()
        defer { lock.unlock() }
        if let existing = engines[key] { return existing }
        let created = try MetalEPEngine(device: device, n: n, levelCount: levelCount)
        engines[key] = created
        return created
    }
}

func packGGSWForMetalEP(_ ggsw: GGSWCiphertext) -> [UInt32] {
    let n = ggsw.params.tfhe.polynomialDegree
    let levels = ggsw.params.levelCount
    var packed = [UInt32](repeating: 0, count: levels * 4 * n)
    for lv in 0..<levels {
        let g0 = ggsw.row(glweRow: 0, level: lv)
        let g1 = ggsw.row(glweRow: 1, level: lv)
        let base = lv * 4 * n
        packed.replaceSubrange(base..<(base + n), with: g0.mask[0])
        packed.replaceSubrange((base + n)..<(base + 2 * n), with: g0.body)
        packed.replaceSubrange((base + 2 * n)..<(base + 3 * n), with: g1.mask[0])
        packed.replaceSubrange((base + 3 * n)..<(base + 4 * n), with: g1.body)
    }
    return packed
}

enum MetalBKPackCache {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cachedStamp: UInt64 = 0
    nonisolated(unsafe) private static var coeff: [UInt32] = []

    static func stamp(_ bk: BootstrapKey) -> UInt64 {
        var h: UInt64 = UInt64(bk.bitKeys.count) &* 0x9E3779B97F4A7C15
        h ^= UInt64(bk.params.baseLog) &<< 32
        h ^= UInt64(bk.params.levelCount) &<< 16
        h ^= UInt64(bk.params.tfhe.polynomialDegree)
        guard !bk.bitKeys.isEmpty else { return h }
        let n = bk.params.tfhe.polynomialDegree
        let step = max(1, bk.bitKeys.count / 8)
        var i = 0
        while i < bk.bitKeys.count {
            let g0 = bk.bitKeys[i].row(glweRow: 0, level: 0)
            h ^= UInt64(g0.body[0])
            h ^= UInt64(g0.body[n - 1]) &* 0x100000001b3
            h ^= UInt64(g0.mask[0][0])
            h = h &* 0x100000001b3
            i += step
        }
        let last = bk.bitKeys[bk.bitKeys.count - 1].row(glweRow: 1, level: 0)
        h ^= UInt64(last.body[n / 2])
        return h
    }

    static func coeffPack(_ bk: BootstrapKey) -> [UInt32] {
        let s = stamp(bk)
        lock.lock()
        defer { lock.unlock() }
        if s == cachedStamp, !coeff.isEmpty { return coeff }
        let packed = packBootstrapKeyForMetalEP(bk)
        cachedStamp = s
        coeff = packed
        return packed
    }
}

func packBootstrapKeyForMetalEP(_ bk: BootstrapKey) -> [UInt32] {
    var packed: [UInt32] = []
    packed.reserveCapacity(bk.bitKeys.count * bk.params.levelCount * 4 * bk.params.tfhe.polynomialDegree)
    for ggsw in bk.bitKeys {
        packed.append(contentsOf: packGGSWForMetalEP(ggsw))
    }
    return packed
}

/// Phase 2.3: ACC + BK live on GPU; one threadgroup of N runs a CMUX tile.
private final class MetalBRPersistEngine: @unchecked Sendable {
    let device: MTLDevice
    let pipeline: MTLComputePipelineState
    let n: Int
    let levelCount: Int
    let bitCount: Int
    let canFuseThreadgroup: Bool
    private let accMaskBuf: MTLBuffer
    private let accBodyBuf: MTLBuffer
    private let bkBuf: MTLBuffer
    private let lweABuf: MTLBuffer
    private let lock = NSLock()
    private var encodeSeconds: Double = 0
    private var gpuSeconds: Double = 0
    private var copySeconds: Double = 0
    private var bkFingerprint: UInt64 = 0

    static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct BRTileUniforms {
        uint n;
        uint twoN;
        uint bitLo;
        uint bitHi;
        uint levelCount;
        uint baseLog;
        uint shift;
        uint pad;
    };

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

    [[max_total_threads_per_threadgroup(1024)]]
    kernel void helut_blind_rotate_tile(
        device uint *accM [[buffer(0)]],
        device uint *accB [[buffer(1)]],
        device const uint *bk [[buffer(2)]],
        device const uint *lweA [[buffer(3)]],
        constant BRTileUniforms &U [[buffer(4)]],
        threadgroup uint *mem [[threadgroup(0)]],
        uint k [[thread_index_in_threadgroup]]
    ) {
        uint n = U.n;
        threadgroup uint *shAccM = mem;
        threadgroup uint *shAccB = mem + n;
        threadgroup uint *shDiffM = mem + 2u * n;
        threadgroup uint *shDiffB = mem + 3u * n;
        shAccM[k] = accM[k];
        shAccB[k] = accB[k];
        threadgroup_barrier(mem_flags::mem_threadgroup);

        uint stride = 4u * U.levelCount * n;
        for (uint bit = U.bitLo; bit < U.bitHi; ++bit) {
            uint p = rotation_power(lweA[bit], U.twoN, U.shift);
            uint p0 = p % n;
            uint wrapExtra = p / n;
            uint i = (k >= p0) ? (k - p0) : (k + n - p0);
            uint wraps = wrapExtra + ((k < p0) ? 1u : 0u);
            uint rotM = shAccM[i];
            uint rotB = shAccB[i];
            if (wraps & 1u) {
                rotM = 0u - rotM;
                rotB = 0u - rotB;
            }
            shDiffM[k] = rotM - shAccM[k];
            shDiffB[k] = rotB - shAccB[k];
            threadgroup_barrier(mem_flags::mem_threadgroup);

            device const uint *ggsw = bk + bit * stride;
            uint gatedM = 0u;
            uint gatedB = 0u;
            for (uint j = 0u; j < n; ++j) {
                uint remM = shDiffM[j];
                uint remB = shDiffB[j];
                uint idx = (k >= j) ? (k - j) : (k + n - j);
                for (uint lv = 0u; lv < U.levelCount; ++lv) {
                    uint dmj = take_digit(&remM, U.baseLog, lv);
                    uint dbj = take_digit(&remB, U.baseLog, lv);
                    device const uint *g0m = ggsw + (lv * 4u) * n;
                    device const uint *g0b = g0m + n;
                    device const uint *g1m = g0b + n;
                    device const uint *g1b = g1m + n;
                    uint termM = g0m[idx] * dmj + g1m[idx] * dbj;
                    uint termB = g0b[idx] * dmj + g1b[idx] * dbj;
                    if (k >= j) {
                        gatedM += termM;
                        gatedB += termB;
                    } else {
                        gatedM -= termM;
                        gatedB -= termB;
                    }
                }
            }
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
        guard let fn = library.makeFunction(name: "helut_blind_rotate_tile") else {
            throw MetalPolyMulError.shaderCompile("missing helut_blind_rotate_tile")
        }
        self.pipeline = try device.makeComputePipelineState(function: fn)
        encodeSeconds = CFAbsoluteTimeGetCurrent() - t0
        self.canFuseThreadgroup = pipeline.maxTotalThreadsPerThreadgroup >= n
        let polyBytes = n * MemoryLayout<UInt32>.stride
        let bkBytes = bitCount * levelCount * 4 * polyBytes
        guard
            let accMaskBuf = device.makeBuffer(length: polyBytes, options: .storageModeShared),
            let accBodyBuf = device.makeBuffer(length: polyBytes, options: .storageModeShared),
            let bkBuf = device.makeBuffer(length: max(bkBytes, 16), options: .storageModeShared),
            let lweABuf = device.makeBuffer(length: bitCount * MemoryLayout<UInt32>.stride, options: .storageModeShared)
        else {
            throw MetalPolyMulError.shaderCompile("BR persist buffer alloc failed")
        }
        self.accMaskBuf = accMaskBuf
        self.accBodyBuf = accBodyBuf
        self.bkBuf = bkBuf
        self.lweABuf = lweABuf
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
        packedBK: [UInt32],
        lweA: [UInt32],
        baseLog: Int,
        tileWidth: Int,
        queue: MTLCommandQueue,
        progress: ((String) -> Void)?
    ) throws -> (mask: [UInt32], body: [UInt32]) {
        precondition(accMask.count == n && accBody.count == n)
        precondition(lweA.count == bitCount)
        precondition(packedBK.count == bitCount * levelCount * 4 * n)
        precondition(canFuseThreadgroup, "threadgroup too small for N=\(n)")
        lock.lock()
        defer { lock.unlock() }

        let c0 = CFAbsoluteTimeGetCurrent()
        accMask.withUnsafeBytes { raw in
            accMaskBuf.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
        }
        accBody.withUnsafeBytes { raw in
            accBodyBuf.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
        }
        let fp = Self.fingerprint(packedBK)
        if fp != bkFingerprint {
            packedBK.withUnsafeBytes { raw in
                bkBuf.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }
            bkFingerprint = fp
        }
        lweA.withUnsafeBytes { raw in
            lweABuf.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
        }
        copySeconds += CFAbsoluteTimeGetCurrent() - c0

        let w = max(1, tileWidth)
        let tileCount = (bitCount + w - 1) / w
        let twoN = 2 * n
        let shift = 32 - twoN.trailingZeroBitCount
        let tgBytes = 4 * n * MemoryLayout<UInt32>.stride
        let tg = MTLSize(width: n, height: 1, depth: 1)
        let groups = MTLSize(width: 1, height: 1, depth: 1)

        for tile in 0..<tileCount {
            let lo = tile * w
            let hi = min(lo + w, bitCount)
            progress?("BR tile=\(tile + 1)/\(tileCount) bits=\(lo)..<\(hi)")
            var uniforms = BRTileUniforms(
                n: UInt32(n),
                twoN: UInt32(twoN),
                bitLo: UInt32(lo),
                bitHi: UInt32(hi),
                levelCount: UInt32(levelCount),
                baseLog: UInt32(baseLog),
                shift: UInt32(shift),
                pad: 0
            )
            guard let cmd = queue.makeCommandBuffer(),
                  let enc = cmd.makeComputeCommandEncoder() else {
                throw MetalPolyMulError.noCommandBuffer
            }
            enc.setComputePipelineState(pipeline)
            enc.setBuffer(accMaskBuf, offset: 0, index: 0)
            enc.setBuffer(accBodyBuf, offset: 0, index: 1)
            enc.setBuffer(bkBuf, offset: 0, index: 2)
            enc.setBuffer(lweABuf, offset: 0, index: 3)
            enc.setBytes(&uniforms, length: MemoryLayout<BRTileUniforms>.stride, index: 4)
            enc.setThreadgroupMemoryLength(tgBytes, index: 0)
            enc.dispatchThreadgroups(groups, threadsPerThreadgroup: tg)
            enc.endEncoding()
            let g0 = CFAbsoluteTimeGetCurrent()
            cmd.commit()
            cmd.waitUntilCompleted()
            gpuSeconds += CFAbsoluteTimeGetCurrent() - g0
            if let err = cmd.error {
                throw MetalPolyMulError.shaderCompile("BR tile GPU: \(err)")
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

private struct BRTileUniforms {
    var n: UInt32
    var twoN: UInt32
    var bitLo: UInt32
    var bitHi: UInt32
    var levelCount: UInt32
    var baseLog: UInt32
    var shift: UInt32
    var pad: UInt32
}

private enum MetalBRPersistCache {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var engines: [String: MetalBRPersistEngine] = [:]

    static func engine(
        device: MTLDevice, n: Int, levelCount: Int, bitCount: Int
    ) throws -> MetalBRPersistEngine {
        let key = "\(ObjectIdentifier(device))-\(n)-\(levelCount)-\(bitCount)"
        lock.lock()
        defer { lock.unlock() }
        if let existing = engines[key] { return existing }
        let created = try MetalBRPersistEngine(
            device: device, n: n, levelCount: levelCount, bitCount: bitCount
        )
        engines[key] = created
        return created
    }
}

extension MetalGGSW {
    package static func externalProductKernel(
        ggsw: GGSWCiphertext,
        ciphertext: GLWECiphertext,
        device: MTLDevice,
        commandQueue: MTLCommandQueue
    ) throws -> GLWECiphertext {
        try externalProductKernelPacked(
            packedGGSW: packGGSWForMetalEP(ggsw),
            ciphertext: ciphertext,
            params: ggsw.params,
            device: device,
            commandQueue: commandQueue
        )
    }

    fileprivate static func externalProductKernelPacked(
        packedGGSW: [UInt32],
        ciphertext: GLWECiphertext,
        params: GGSWParams,
        device: MTLDevice,
        commandQueue: MTLCommandQueue
    ) throws -> GLWECiphertext {
        precondition(ciphertext.glweDimension == 1 && params.tfhe.glweDimension == 1)
        let maskDigits = gadgetDecompose(
            ciphertext.mask[0],
            baseLog: params.baseLog,
            levelCount: params.levelCount
        )
        let bodyDigits = gadgetDecompose(
            ciphertext.body,
            baseLog: params.baseLog,
            levelCount: params.levelCount
        )
        let engine = try MetalEPCache.engine(
            device: device,
            n: params.tfhe.polynomialDegree,
            levelCount: params.levelCount
        )
        let (mask, body) = try engine.externalProduct(
            maskDigits: maskDigits,
            bodyDigits: bodyDigits,
            ggswPacked: packedGGSW,
            queue: commandQueue
        )
        return GLWECiphertext(mask: [mask], body: body)
    }

    /// Phase 1.1 tiles + Phase 2.3 GPU-resident ACC/BK (one launch per tile).
    /// Falls back to per-CMUX EP if the device cannot fit N threads in one threadgroup.
    package static func blindRotateTiledKernel(
        testPolynomial: [UInt32],
        lwe: LWECiphertext,
        bootstrapKey: BootstrapKey,
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        tileWidth: Int
    ) throws -> GLWECiphertext {
        let params = bootstrapKey.params
        precondition(params.tfhe.glweDimension == 1, "Metal BR is k=1 only")
        let n = params.tfhe.polynomialDegree
        let twoN = 2 * n
        let w = max(1, tileWidth)
        precondition(testPolynomial.count == n)
        let dim = lwe.lweDimension
        precondition(dim == bootstrapKey.bitKeys.count)

        let bPow = rotationPower(lwe.b, twoN: twoN)
        let acc0 = encryptGLWETrivialMask(
            message: negacyclicMultiplyByXPower(testPolynomial, power: -bPow),
            secret: .zero(params: params.tfhe)
        )
        let tileCount = (dim + w - 1) / w
        if n >= 8 && n.nonzeroBitCount == 1 {
            let ntt = try MetalBRNTTCache.engine(
                device: device, n: n, levelCount: params.levelCount, bitCount: dim
            )
            if ntt.canFuseThreadgroup {
                let packedBK = MetalBKPackCache.coeffPack(bootstrapKey)
                let (mask, body) = try ntt.blindRotate(
                    accMask: acc0.mask[0],
                    accBody: acc0.body,
                    packedCoeffBK: packedBK,
                    lweA: lwe.a,
                    baseLog: params.baseLog,
                    tileWidth: w,
                    queue: commandQueue,
                    progress: MetalBRControl.progress
                )
                let (enc, gpu, copy) = ntt.takeTimings()
                MetalBRControl.lastTelemetry = MetalBRTelemetry(
                    lowering: MetalBRLowering.tiledKernel.rawValue,
                    tileWidth: w,
                    tileCount: tileCount,
                    encodeSeconds: enc,
                    gpuRunSeconds: gpu,
                    hostRepackSeconds: copy,
                    ring: "ntt"
                )
                return GLWECiphertext(mask: [mask], body: body)
            }
        }
        let persist = try MetalBRPersistCache.engine(
            device: device, n: n, levelCount: params.levelCount, bitCount: dim
        )
        if persist.canFuseThreadgroup {
            let packedBK = MetalBKPackCache.coeffPack(bootstrapKey)
            let (mask, body) = try persist.blindRotate(
                accMask: acc0.mask[0],
                accBody: acc0.body,
                packedBK: packedBK,
                lweA: lwe.a,
                baseLog: params.baseLog,
                tileWidth: w,
                queue: commandQueue,
                progress: MetalBRControl.progress
            )
            let (enc, gpu, copy) = persist.takeTimings()
            MetalBRControl.lastTelemetry = MetalBRTelemetry(
                lowering: MetalBRLowering.tiledKernel.rawValue,
                tileWidth: w,
                tileCount: tileCount,
                encodeSeconds: enc,
                gpuRunSeconds: gpu,
                hostRepackSeconds: copy,
                ring: "schoolbook"
            )
            return GLWECiphertext(mask: [mask], body: body)
        }
        return try blindRotateTiledKernelHostEP(
            acc0: acc0, lwe: lwe, bootstrapKey: bootstrapKey,
            device: device, commandQueue: commandQueue, tileWidth: w
        )
    }

    /// Host rotate + Phase 2.2 EP when a fused threadgroup of size N is unavailable.
    fileprivate static func blindRotateTiledKernelHostEP(
        acc0: GLWECiphertext,
        lwe: LWECiphertext,
        bootstrapKey: BootstrapKey,
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        tileWidth: Int
    ) throws -> GLWECiphertext {
        let params = bootstrapKey.params
        let n = params.tfhe.polynomialDegree
        let twoN = 2 * n
        let w = max(1, tileWidth)
        var acc = acc0
        let dim = lwe.lweDimension
        let tileCount = (dim + w - 1) / w
        let packedBK = bootstrapKey.bitKeys.map(packGGSWForMetalEP)
        _ = try MetalEPCache.engine(device: device, n: n, levelCount: params.levelCount)

        for tile in 0..<tileCount {
            let lo = tile * w
            let hi = min(lo + w, dim)
            MetalBRControl.progress?(
                "BR tile=\(tile + 1)/\(tileCount) bits=\(lo)..<\(hi)"
            )
            for j in lo..<hi {
                let aPow = rotationPower(lwe.a[j], twoN: twoN)
                let rotated = GLWECiphertext(
                    mask: acc.mask.map { negacyclicMultiplyByXPower($0, power: aPow) },
                    body: negacyclicMultiplyByXPower(acc.body, power: aPow)
                )
                let diff = subGLWE(rotated, acc)
                let gated = try externalProductKernelPacked(
                    packedGGSW: packedBK[j],
                    ciphertext: diff,
                    params: params,
                    device: device,
                    commandQueue: commandQueue
                )
                acc = addGLWE(acc, gated)
            }
        }

        let engine = try MetalEPCache.engine(
            device: device, n: n, levelCount: params.levelCount
        )
        let (enc, gpu, copy) = engine.takeTimings()
        MetalBRControl.lastTelemetry = MetalBRTelemetry(
            lowering: MetalBRLowering.tiledKernel.rawValue,
            tileWidth: w,
            tileCount: tileCount,
            encodeSeconds: enc,
            gpuRunSeconds: gpu,
            hostRepackSeconds: copy,
            ring: "schoolbook"
        )
        return acc
    }
}
