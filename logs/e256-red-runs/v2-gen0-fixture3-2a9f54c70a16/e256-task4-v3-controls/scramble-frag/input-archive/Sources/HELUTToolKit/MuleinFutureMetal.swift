import Foundation
import Metal
import HELUTCore
import HELUTCLI

// MARK: - Mulein Future Bank (cleartext Metal prototype)
//
// This is deliberately separate from `WelchmanMetalEngine`. The production campaign kernel
// remains unchanged until this path has passed the blind host and P1030684 grades. The Future
// Bank is ordinary cleartext Metal board evaluation: it is neither encrypted execution nor FHE.
//
// One threadgroup owns one rotor setting. Its workers build the complete unsteckered scrambler
// trail S_0...S_n once in threadgroup memory, then divide `future × 26 seed` closure jobs among
// themselves. Futures therefore replicate only their compact menu state; they do not replicate
// Enigma trails. Survivors enter a sparse queue with the local erased-edge mask intact so the
// host can map each bit back to a stable `MuleinEdgeID`.

private let muleinFutureMaxEdges = 40
private let muleinFutureMaxSteps = 80
private let muleinFutureDescriptorWords = 6
private let muleinFutureHitWords = 8
private let muleinFutureHitBytes = muleinFutureHitWords * MemoryLayout<UInt32>.stride

package struct MuleinFutureMetalWork: Sendable {
    package let future: MuleinFuture
    /// Prototype cap is one erased edge. Higher tolerances remain on the existing, separately
    /// graded Mulein board until the Future Bank's exact-first repair path is certified.
    package let tolerance: Int
    package let maxPlugs: Int
    package let exactPlugs: Int

    package init(
        future: MuleinFuture,
        tolerance: Int = 0,
        maxPlugs: Int = 0,
        exactPlugs: Int = 0
    ) {
        self.future = future
        self.tolerance = tolerance
        self.maxPlugs = maxPlugs
        self.exactPlugs = exactPlugs
    }
}

package struct MuleinFutureMetalHit: Sendable, Hashable {
    package let settingLane: Int
    package let futureIndex: Int
    package let futureID: MuleinHypothesisID
    package let seed: Int
    package let droppedEdgeMask: UInt64
    package let repair: MuleinBoardRepairReceipt
    package let pairCount: Int
    package let determinedCount: Int
    package let exact: Bool
    package let liveHash: UInt32

    package var positions: (Int, Int, Int, Int) {
        WelchmanMetalEngine.position(forLane: settingLane)
    }
}

package struct MuleinFutureMetalStatistics: Sendable {
    package let deviceName: String
    package let compileSeconds: Double
    package let wallSeconds: Double
    package let gpuSeconds: Double
    package let threadExecutionWidth: Int
    package let threadsPerThreadgroup: Int
    package let staticThreadgroupBytes: Int
    package let settingCount: Int
    package let futureCount: Int
    package let trailLength: Int
    package let attemptedHits: Int
    package let writtenHits: Int
    package let overflowHits: Int

    package var futureSettings: Int { settingCount * futureCount }
    package var seedClosures: Int { futureSettings * 26 }
    package var queueBytesWritten: Int { writtenHits * muleinFutureHitBytes }
}

package struct MuleinFutureMetalBatchResult: Sendable {
    package let hits: [MuleinFutureMetalHit]
    package let statistics: MuleinFutureMetalStatistics

    package var isComplete: Bool { statistics.overflowHits == 0 }
}

package enum MuleinFutureMetalError: Error, CustomStringConvertible {
    case noMetalDevice
    case commandQueueUnavailable
    case pipelineCompilation(String)
    case invalidBatch(String)
    case allocationFailed(String)
    case commandEncodingFailed
    case commandFailed(String)
    case queueOverflow(attempted: Int, written: Int, capacity: Int)
    case benchmarkMismatch(String)

    package var description: String {
        switch self {
        case .noMetalDevice:
            return "no Metal device is available"
        case .commandQueueUnavailable:
            return "Metal command queue creation failed"
        case let .pipelineCompilation(message):
            return "Mulein Future Bank kernel compilation failed: \(message)"
        case let .invalidBatch(message):
            return "invalid Mulein Future Bank batch: \(message)"
        case let .allocationFailed(label):
            return "Metal buffer allocation failed for \(label)"
        case .commandEncodingFailed:
            return "Metal command buffer/encoder creation failed"
        case let .commandFailed(message):
            return "Mulein Future Bank command failed: \(message)"
        case let .queueOverflow(attempted, written, capacity):
            return "Mulein Future Bank sparse queue overflow: attempted \(attempted), "
                + "wrote \(written), capacity \(capacity); result is incomplete"
        case let .benchmarkMismatch(message):
            return "Mulein Future Bank benchmark mismatch: \(message)"
        }
    }
}

private struct MuleinFutureHitKey: Hashable {
    let settingLane: Int
    let futureIndex: Int
    let seed: Int
}

@discardableResult
package func validateMuleinFutureWork(_ work: [MuleinFutureMetalWork]) throws -> Int {
    guard !work.isEmpty else {
        throw MuleinFutureMetalError.invalidBatch("at least one future is required")
    }

    var maximumStep = -1
    for (futureIndex, item) in work.enumerated() {
        let menu = item.future.menu
        let boardEdges = item.future.boardEdges
        guard menu.ends.count == menu.steps.count else {
            throw MuleinFutureMetalError.invalidBatch(
                "future \(futureIndex) menu endpoint/step counts disagree"
            )
        }
        guard menu.edgeCount > 0, menu.edgeCount <= muleinFutureMaxEdges else {
            throw MuleinFutureMetalError.invalidBatch(
                "future \(futureIndex) has \(menu.edgeCount) edges; cap is "
                    + "\(muleinFutureMaxEdges)"
            )
        }
        guard boardEdges.count == menu.edgeCount else {
            throw MuleinFutureMetalError.invalidBatch(
                "future \(futureIndex) lost board-edge provenance while packing"
            )
        }
        guard (0...1).contains(item.tolerance) else {
            throw MuleinFutureMetalError.invalidBatch(
                "future \(futureIndex) requests tolerance \(item.tolerance); prototype cap is 1"
            )
        }
        guard (0...13).contains(item.maxPlugs), (0...13).contains(item.exactPlugs) else {
            throw MuleinFutureMetalError.invalidBatch(
                "future \(futureIndex) plug budgets must lie in 0...13"
            )
        }
        guard item.maxPlugs == 0 || item.exactPlugs == 0
                || item.exactPlugs <= item.maxPlugs else {
            throw MuleinFutureMetalError.invalidBatch(
                "future \(futureIndex) exact-plug budget exceeds its maximum"
            )
        }
        guard (0..<26).contains(menu.central),
              menu.ends.allSatisfy({
                  (0..<26).contains($0.0) && (0..<26).contains($0.1)
              }) else {
            throw MuleinFutureMetalError.invalidBatch(
                "future \(futureIndex) contains an out-of-range Enigma letter"
            )
        }
        guard menu.steps.allSatisfy({ (0..<muleinFutureMaxSteps).contains($0) }) else {
            throw MuleinFutureMetalError.invalidBatch(
                "future \(futureIndex) has a step outside 0..<\(muleinFutureMaxSteps)"
            )
        }

        for edgeIndex in menu.ends.indices {
            let provenance = boardEdges[edgeIndex]
            let endpoints = menu.ends[edgeIndex]
            let step = menu.steps[edgeIndex]
            guard provenance.isBoardConstraint,
                  provenance.plaintext == endpoints.0,
                  provenance.effectiveCiphertext == endpoints.1,
                  provenance.id.transmittedStep == step else {
                throw MuleinFutureMetalError.invalidBatch(
                    "future \(futureIndex) edge \(edgeIndex) provenance disagrees with packed work"
                )
            }
            maximumStep = max(maximumStep, step)
        }
    }
    return maximumStep
}

private let muleinFutureMetalSource = """
#include <metal_stdlib>
using namespace metal;

#define MAX_EDGES \(muleinFutureMaxEdges)
#define MAX_STEPS \(muleinFutureMaxSteps)
#define DESC_WORDS \(muleinFutureDescriptorWords)
#define HIT_WORDS \(muleinFutureHitWords)

inline uchar future_rot_fwd(uchar ch, int offset, constant uchar *wiring) {
    int shifted = (int(ch) + offset) % 26;
    return uchar((int(wiring[shifted]) - offset + 26) % 26);
}

inline uchar future_rot_inv(uchar ch, int offset, constant uchar *inverse) {
    int shifted = (int(ch) + offset) % 26;
    return uchar((int(inverse[shifted]) - offset + 26) % 26);
}

inline uint future_edge_a(uint packed) { return packed & 31u; }
inline uint future_edge_b(uint packed) { return (packed >> 5u) & 31u; }
inline uint future_edge_step(uint packed) { return (packed >> 10u) & 127u; }

/// Exact diagonal-board closure over one explicit pre-propagation drop mask.
/// `activeOut` records only menu edges that changed the partial involution. If an edge did not
/// change the exact closure, deleting it cannot change either that closure or its plug budget,
/// so active-edge repair remains complete for both contradiction and over-budget failures.
inline bool future_closure(
    threadgroup const uchar *trail,
    device const uint *edges,
    uint edgeOffset,
    uint edgeCount,
    ulong dropMask,
    uint central,
    uint seed,
    thread uint *outLive,
    thread ulong *activeOut
) {
    uint live[26];
    for (uint i = 0u; i < 26u; ++i) { live[i] = 0u; }
    live[central] = 1u << seed;
    ulong active = 0ul;

    bool changed = true;
    while (changed) {
        changed = false;
        for (uint e = 0u; e < edgeCount; ++e) {
            if (((dropMask >> e) & 1ul) != 0ul) { continue; }
            uint packed = edges[edgeOffset + e];
            uint a = future_edge_a(packed);
            uint b = future_edge_b(packed);
            uint table = future_edge_step(packed) * 26u;

            uint mask = live[a];
            uint image = 0u;
            while (mask != 0u) {
                uint bit = uint(ctz(mask));
                mask &= mask - 1u;
                image |= 1u << uint(trail[table + bit]);
            }
            if ((image & ~live[b]) != 0u) {
                live[b] |= image;
                active |= 1ul << e;
                if (popcount(live[b]) > 1) { *activeOut = active; return false; }
                changed = true;
            }

            mask = live[b];
            image = 0u;
            while (mask != 0u) {
                uint bit = uint(ctz(mask));
                mask &= mask - 1u;
                image |= 1u << uint(trail[table + bit]);
            }
            if ((image & ~live[a]) != 0u) {
                live[a] |= image;
                active |= 1ul << e;
                if (popcount(live[a]) > 1) { *activeOut = active; return false; }
                changed = true;
            }
        }

        for (uint x = 0u; x < 26u; ++x) {
            uint mask = live[x];
            while (mask != 0u) {
                uint y = uint(ctz(mask));
                mask &= mask - 1u;
                uint bit = 1u << x;
                if ((live[y] & bit) == 0u) {
                    live[y] |= bit;
                    if (popcount(live[y]) > 1) { *activeOut = active; return false; }
                    changed = true;
                }
            }
        }
    }

    for (uint i = 0u; i < 26u; ++i) { outLive[i] = live[i]; }
    *activeOut = active;
    return true;
}

inline bool future_seed_attached(
    device const uint *edges,
    uint edgeOffset,
    uint edgeCount,
    ulong dropMask,
    uint central
) {
    for (uint e = 0u; e < edgeCount; ++e) {
        if (((dropMask >> e) & 1ul) != 0ul) { continue; }
        uint packed = edges[edgeOffset + e];
        if (future_edge_a(packed) == central || future_edge_b(packed) == central) {
            return true;
        }
    }
    return false;
}

inline bool future_budget(
    thread const uint *live,
    uint maxPlugs,
    uint exactPlugs,
    thread uint *pairCount,
    thread uint *determinedCount
) {
    uint determined = 0u;
    uint halfPairs = 0u;
    for (uint x = 0u; x < 26u; ++x) {
        if (live[x] == 0u) { continue; }
        determined += 1u;
        if (uint(ctz(live[x])) != x) { halfPairs += 1u; }
    }
    uint pairs = halfPairs / 2u;
    *pairCount = pairs;
    *determinedCount = determined;
    if (maxPlugs > 0u && pairs > maxPlugs) { return false; }
    if (exactPlugs > 0u) {
        if (pairs > exactPlugs) { return false; }
        if ((26u - determined) < 2u * (exactPlugs - pairs)) { return false; }
    }
    return true;
}

/// Exact first, then one active-edge erasure. Crucially, budget failure is a failed exact
/// candidate rather than an early return: a dropped edge may reduce the forced plug count.
inline bool future_find_repair(
    threadgroup const uchar *trail,
    device const uint *edges,
    uint edgeOffset,
    uint edgeCount,
    uint tolerance,
    uint central,
    uint seed,
    uint maxPlugs,
    uint exactPlugs,
    thread uint *outLive,
    thread ulong *outDropMask,
    thread uint *outPairs,
    thread uint *outDetermined
) {
    ulong active0 = 0ul;
    bool exactClosed = future_closure(
        trail, edges, edgeOffset, edgeCount, 0ul, central, seed, outLive, &active0
    );
    if (exactClosed && future_budget(
            outLive, maxPlugs, exactPlugs, outPairs, outDetermined)) {
        *outDropMask = 0ul;
        return true;
    }
    if (tolerance == 0u) { return false; }

    ulong candidates = active0;
    while (candidates != 0ul) {
        uint edge = uint(ctz(candidates));
        candidates &= candidates - 1ul;
        ulong mask = 1ul << edge;
        if (!future_seed_attached(edges, edgeOffset, edgeCount, mask, central)) { continue; }
        ulong active1 = 0ul;
        if (!future_closure(
                trail, edges, edgeOffset, edgeCount, mask,
                central, seed, outLive, &active1)) { continue; }
        if (!future_budget(outLive, maxPlugs, exactPlugs, outPairs, outDetermined)) {
            continue;
        }
        *outDropMask = mask;
        return true;
    }
    return false;
}

inline uint future_live_hash(thread const uint *live) {
    uint hash = 2166136261u;
    for (uint x = 0u; x < 26u; ++x) {
        hash = (hash ^ live[x]) * 16777619u;
    }
    return hash;
}

/// One threadgroup per rotor setting. Workers first materialize the shared scrambler trail,
/// then consume independent future×seed jobs. Output is sparse: one 32-byte record per hit.
kernel void mulein_future_batch(
    device const uint *descriptors       [[buffer(0)]],
    device const uint *edges             [[buffer(1)]],
    constant uint &futureCount           [[buffer(2)]],
    constant uint &settingBase           [[buffer(3)]],
    constant uint &settingCount          [[buffer(4)]],
    constant uint &trailLength           [[buffer(5)]],
    constant uchar *gFwd                 [[buffer(6)]],
    constant uchar *gInv                 [[buffer(7)]],
    constant uchar *lFwd                 [[buffer(8)]],
    constant uchar *lInv                 [[buffer(9)]],
    constant uchar *mFwd                 [[buffer(10)]],
    constant uchar *mInv                 [[buffer(11)]],
    constant uchar *rFwd                 [[buffer(12)]],
    constant uchar *rInv                 [[buffer(13)]],
    constant uchar *refl                 [[buffer(14)]],
    constant uchar *notchM               [[buffer(15)]],
    constant uchar *notchR               [[buffer(16)]],
    constant uchar *rings                [[buffer(17)]],
    device atomic_uint *counters         [[buffer(18)]],
    device uint *hitRecords              [[buffer(19)]],
    constant uint &hitCapacity           [[buffer(20)]],
    uint tid                              [[thread_index_in_threadgroup]],
    uint3 group                           [[threadgroup_position_in_grid]],
    uint3 groupSize                       [[threads_per_threadgroup]]
) {
    if (group.x >= settingCount) { return; }
    uint setting = settingBase + group.x;

    uchar posG = uchar(setting / 17576u);
    uchar posL = uchar((setting / 676u) % 26u);
    uchar posM = uchar((setting / 26u) % 26u);
    uchar posR = uchar(setting % 26u);

    threadgroup uint steppedPositions[MAX_STEPS];
    threadgroup uchar trail[MAX_STEPS * 26];

    if (tid == 0u) {
        uchar l = posL, m = posM, r = posR;
        for (uint step = 0u; step < trailLength; ++step) {
            bool middleAtNotch = notchM[m] != 0;
            bool rightAtNotch = notchR[r] != 0;
            if (middleAtNotch) { l = uchar((uint(l) + 1u) % 26u); }
            if (middleAtNotch || rightAtNotch) {
                m = uchar((uint(m) + 1u) % 26u);
            }
            r = uchar((uint(r) + 1u) % 26u);
            steppedPositions[step] = uint(l) | (uint(m) << 8u) | (uint(r) << 16u);
        }
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    uint cells = trailLength * 26u;
    int offsetG = (int(posG) - int(rings[0]) + 26) % 26;
    for (uint cell = tid; cell < cells; cell += groupSize.x) {
        uint step = cell / 26u;
        uchar input = uchar(cell % 26u);
        uint packedPosition = steppedPositions[step];
        int offsetL = (int((packedPosition >> 0u) & 255u) - int(rings[1]) + 26) % 26;
        int offsetM = (int((packedPosition >> 8u) & 255u) - int(rings[2]) + 26) % 26;
        int offsetR = (int((packedPosition >> 16u) & 255u) - int(rings[3]) + 26) % 26;

        uchar value = future_rot_fwd(input, offsetR, rFwd);
        value = future_rot_fwd(value, offsetM, mFwd);
        value = future_rot_fwd(value, offsetL, lFwd);
        value = future_rot_fwd(value, offsetG, gFwd);
        value = refl[value];
        value = future_rot_inv(value, offsetG, gInv);
        value = future_rot_inv(value, offsetL, lInv);
        value = future_rot_inv(value, offsetM, mInv);
        value = future_rot_inv(value, offsetR, rInv);
        trail[cell] = value;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    uint itemCount = futureCount * 26u;
    for (uint item = tid; item < itemCount; item += groupSize.x) {
        uint future = item / 26u;
        uint seed = item % 26u;
        uint descriptor = future * DESC_WORDS;
        uint edgeOffset = descriptors[descriptor + 0u];
        uint edgeCount = descriptors[descriptor + 1u];
        uint central = descriptors[descriptor + 2u];
        uint tolerance = descriptors[descriptor + 3u];
        uint maxPlugs = descriptors[descriptor + 4u];
        uint exactPlugs = descriptors[descriptor + 5u];

        uint live[26];
        ulong dropMask = 0ul;
        uint pairs = 0u;
        uint determined = 0u;
        if (!future_find_repair(
                trail, edges, edgeOffset, edgeCount, tolerance, central, seed,
                maxPlugs, exactPlugs, live, &dropMask, &pairs, &determined)) {
            continue;
        }

        uint slot = atomic_fetch_add_explicit(&counters[0], 1u, memory_order_relaxed);
        if (slot >= hitCapacity) {
            atomic_fetch_add_explicit(&counters[1], 1u, memory_order_relaxed);
            continue;
        }
        uint record = slot * HIT_WORDS;
        hitRecords[record + 0u] = setting;
        hitRecords[record + 1u] = future;
        hitRecords[record + 2u] = seed;
        hitRecords[record + 3u] = uint(dropMask & 0xFFFFFFFFul);
        hitRecords[record + 4u] = uint(dropMask >> 32u);
        hitRecords[record + 5u] = pairs;
        hitRecords[record + 6u] = determined;
        // Exactness is derivable from the zero drop mask; keep all 32 checksum bits.
        hitRecords[record + 7u] = future_live_hash(live);
    }
}
"""

package final class MuleinFutureMetalEngine {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState

    package let compileSeconds: Double
    package let deviceName: String
    package let threadExecutionWidth: Int
    package let threadsPerThreadgroup: Int
    package let staticThreadgroupBytes: Int

    package init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw MuleinFutureMetalError.noMetalDevice
        }
        guard let queue = device.makeCommandQueue() else {
            throw MuleinFutureMetalError.commandQueueUnavailable
        }

        let started = CFAbsoluteTimeGetCurrent()
        let pipeline: MTLComputePipelineState
        do {
            let library = try device.makeLibrary(source: muleinFutureMetalSource, options: nil)
            guard let function = library.makeFunction(name: "mulein_future_batch") else {
                throw MuleinFutureMetalError.pipelineCompilation("kernel function is absent")
            }
            pipeline = try device.makeComputePipelineState(function: function)
        } catch let error as MuleinFutureMetalError {
            throw error
        } catch {
            throw MuleinFutureMetalError.pipelineCompilation(String(describing: error))
        }
        let compileSeconds = CFAbsoluteTimeGetCurrent() - started

        let width = pipeline.threadExecutionWidth
        let desired = min(128, pipeline.maxTotalThreadsPerThreadgroup)
        let rounded = (desired / width) * width
        let threads = max(width, rounded)
        guard pipeline.staticThreadgroupMemoryLength <= device.maxThreadgroupMemoryLength else {
            throw MuleinFutureMetalError.pipelineCompilation(
                "kernel needs \(pipeline.staticThreadgroupMemoryLength) threadgroup bytes, "
                    + "device allows \(device.maxThreadgroupMemoryLength)"
            )
        }

        self.device = device
        self.queue = queue
        self.pipeline = pipeline
        self.compileSeconds = compileSeconds
        self.deviceName = device.name
        self.threadExecutionWidth = width
        self.threadsPerThreadgroup = threads
        self.staticThreadgroupBytes = pipeline.staticThreadgroupMemoryLength
    }

    /// Evaluate a bounded setting subrange. `failOnOverflow` defaults true because an
    /// overflowing sparse queue is an incomplete observation, never a clean negative.
    package func evaluate(
        work: [MuleinFutureMetalWork],
        bombe: WelchmanBombe,
        settingRange: Range<Int> = 0..<WelchmanMetalEngine.laneCount,
        hitCapacity: Int,
        failOnOverflow: Bool = true
    ) throws -> MuleinFutureMetalBatchResult {
        _ = try validateMuleinFutureWork(work)
        guard !work.isEmpty else {
            throw MuleinFutureMetalError.invalidBatch("at least one future is required")
        }
        guard settingRange.lowerBound >= 0,
              settingRange.upperBound <= WelchmanMetalEngine.laneCount,
              !settingRange.isEmpty else {
            throw MuleinFutureMetalError.invalidBatch(
                "setting range must be a non-empty subset of 0..<\(WelchmanMetalEngine.laneCount)"
            )
        }
        guard hitCapacity > 0, hitCapacity <= Int(UInt32.max) else {
            throw MuleinFutureMetalError.invalidBatch("hit capacity must fit a positive UInt32")
        }
        let maximumItems = UInt64(settingRange.count) * UInt64(work.count) * 26
        guard maximumItems <= UInt64(UInt32.max) else {
            throw MuleinFutureMetalError.invalidBatch(
                "setting×future×seed space exceeds the UInt32 sparse-queue counter"
            )
        }

        var descriptors: [UInt32] = []
        var packedEdges: [UInt32] = []
        descriptors.reserveCapacity(work.count * muleinFutureDescriptorWords)
        packedEdges.reserveCapacity(work.reduce(0) { $0 + $1.future.menu.edgeCount })
        var maximumStep = -1

        for (futureIndex, item) in work.enumerated() {
            let menu = item.future.menu
            guard menu.edgeCount > 0, menu.edgeCount <= muleinFutureMaxEdges else {
                throw MuleinFutureMetalError.invalidBatch(
                    "future \(futureIndex) has \(menu.edgeCount) edges; cap is "
                        + "\(muleinFutureMaxEdges)"
                )
            }
            guard item.future.boardEdges.count == menu.edgeCount else {
                throw MuleinFutureMetalError.invalidBatch(
                    "future \(futureIndex) lost board-edge provenance while packing"
                )
            }
            guard (0...1).contains(item.tolerance) else {
                throw MuleinFutureMetalError.invalidBatch(
                    "future \(futureIndex) requests tolerance \(item.tolerance); prototype cap is 1"
                )
            }
            guard item.maxPlugs >= 0, item.maxPlugs <= 13,
                  item.exactPlugs >= 0, item.exactPlugs <= 13 else {
                throw MuleinFutureMetalError.invalidBatch(
                    "future \(futureIndex) plug budgets must lie in 0...13"
                )
            }
            guard menu.central >= 0, menu.central < 26,
                  menu.ends.allSatisfy({ (0..<26).contains($0.0) && (0..<26).contains($0.1) })
            else {
                throw MuleinFutureMetalError.invalidBatch(
                    "future \(futureIndex) contains an out-of-range Enigma letter"
                )
            }
            guard menu.steps.allSatisfy({ (0..<muleinFutureMaxSteps).contains($0) }) else {
                throw MuleinFutureMetalError.invalidBatch(
                    "future \(futureIndex) has a step outside 0..<\(muleinFutureMaxSteps)"
                )
            }

            descriptors.append(UInt32(packedEdges.count))
            descriptors.append(UInt32(menu.edgeCount))
            descriptors.append(UInt32(menu.central))
            descriptors.append(UInt32(item.tolerance))
            descriptors.append(UInt32(item.maxPlugs))
            descriptors.append(UInt32(item.exactPlugs))

            for edge in menu.ends.indices {
                let a = UInt32(menu.ends[edge].0)
                let b = UInt32(menu.ends[edge].1)
                let step = UInt32(menu.steps[edge])
                packedEdges.append(a | (b << 5) | (step << 10))
                maximumStep = max(maximumStep, menu.steps[edge])
            }
        }

        let trailLengthValue = maximumStep + 1
        guard trailLengthValue > 0, trailLengthValue <= muleinFutureMaxSteps else {
            throw MuleinFutureMetalError.invalidBatch("computed trail length is invalid")
        }

        let descriptorBuffer = try makeBuffer(descriptors, label: "future descriptors")
        let edgeBuffer = try makeBuffer(packedEdges, label: "packed future edges")
        guard let counterBuffer = device.makeBuffer(
            length: 2 * MemoryLayout<UInt32>.stride, options: .storageModeShared
        ) else {
            throw MuleinFutureMetalError.allocationFailed("sparse queue counters")
        }
        guard let hitBuffer = device.makeBuffer(
            length: hitCapacity * muleinFutureHitBytes, options: .storageModeShared
        ) else {
            throw MuleinFutureMetalError.allocationFailed("sparse hit records")
        }
        counterBuffer.label = "Mulein Future Bank counters"
        hitBuffer.label = "Mulein Future Bank sparse hits"
        let counters = counterBuffer.contents().bindMemory(to: UInt32.self, capacity: 2)
        counters[0] = 0
        counters[1] = 0

        guard let commands = queue.makeCommandBuffer(),
              let encoder = commands.makeComputeCommandEncoder() else {
            throw MuleinFutureMetalError.commandEncodingFailed
        }
        commands.label = "Mulein Future Bank \(work.count) futures × \(settingRange.count) settings"
        encoder.label = "Shared-trail future×seed closure"
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(descriptorBuffer, offset: 0, index: 0)
        encoder.setBuffer(edgeBuffer, offset: 0, index: 1)

        var futureCount = UInt32(work.count)
        var settingBase = UInt32(settingRange.lowerBound)
        var settingCount = UInt32(settingRange.count)
        var trailLength = UInt32(trailLengthValue)
        encoder.setBytes(&futureCount, length: MemoryLayout<UInt32>.stride, index: 2)
        encoder.setBytes(&settingBase, length: MemoryLayout<UInt32>.stride, index: 3)
        encoder.setBytes(&settingCount, length: MemoryLayout<UInt32>.stride, index: 4)
        encoder.setBytes(&trailLength, length: MemoryLayout<UInt32>.stride, index: 5)

        let tables: [[UInt8]] = [
            byteTable(bombe.greek.wiring), byteTable(bombe.greek.inverse),
            byteTable(bombe.left.wiring), byteTable(bombe.left.inverse),
            byteTable(bombe.middle.wiring), byteTable(bombe.middle.inverse),
            byteTable(bombe.right.wiring), byteTable(bombe.right.inverse),
            byteTable(bombe.reflector), notchTable(bombe.middle), notchTable(bombe.right),
            [UInt8(bombe.rings.0), UInt8(bombe.rings.1),
             UInt8(bombe.rings.2), UInt8(bombe.rings.3)]
        ]
        for (offset, table) in tables.enumerated() {
            table.withUnsafeBytes { raw in
                encoder.setBytes(raw.baseAddress!, length: raw.count, index: 6 + offset)
            }
        }
        encoder.setBuffer(counterBuffer, offset: 0, index: 18)
        encoder.setBuffer(hitBuffer, offset: 0, index: 19)
        var capacity = UInt32(hitCapacity)
        encoder.setBytes(&capacity, length: MemoryLayout<UInt32>.stride, index: 20)

        encoder.dispatchThreadgroups(
            MTLSize(width: settingRange.count, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: threadsPerThreadgroup, height: 1, depth: 1)
        )
        encoder.endEncoding()

        let wallStarted = CFAbsoluteTimeGetCurrent()
        commands.commit()
        commands.waitUntilCompleted()
        let wallSeconds = CFAbsoluteTimeGetCurrent() - wallStarted
        guard commands.status == .completed else {
            let detail = commands.error.map(String.init(describing:)) ?? "status \(commands.status.rawValue)"
            throw MuleinFutureMetalError.commandFailed(detail)
        }

        let attempted = Int(counters[0])
        let overflow = Int(counters[1])
        let written = min(attempted, hitCapacity)
        guard UInt64(attempted) <= maximumItems else {
            throw MuleinFutureMetalError.commandFailed(
                "GPU sparse counter exceeds the submitted setting×future×seed space"
            )
        }
        guard overflow == attempted - written else {
            throw MuleinFutureMetalError.commandFailed(
                "GPU sparse counter invariant failed: overflow \(overflow), "
                    + "attempted \(attempted), written \(written)"
            )
        }

        let rawHits = hitBuffer.contents().bindMemory(
            to: UInt32.self, capacity: hitCapacity * muleinFutureHitWords
        )
        var hits: [MuleinFutureMetalHit] = []
        var seenKeys = Set<MuleinFutureHitKey>()
        hits.reserveCapacity(written)
        seenKeys.reserveCapacity(written)
        for slot in 0..<written {
            let base = slot * muleinFutureHitWords
            let settingLane = Int(rawHits[base])
            let futureIndex = Int(rawHits[base + 1])
            let seed = Int(rawHits[base + 2])
            guard work.indices.contains(futureIndex), (0..<26).contains(seed),
                  settingRange.contains(settingLane) else {
                throw MuleinFutureMetalError.commandFailed(
                    "GPU emitted an out-of-range sparse record at slot \(slot)"
                )
            }

            let key = MuleinFutureHitKey(
                settingLane: settingLane, futureIndex: futureIndex, seed: seed
            )
            guard seenKeys.insert(key).inserted else {
                throw MuleinFutureMetalError.commandFailed(
                    "GPU emitted duplicate sparse key at setting \(settingLane), "
                        + "future \(futureIndex), seed \(seed)"
                )
            }

            let dropMask = UInt64(rawHits[base + 3]) | (UInt64(rawHits[base + 4]) << 32)
            let item = work[futureIndex]
            let future = item.future
            let validDropMask = (UInt64(1) << UInt64(future.boardEdges.count)) - 1
            let dropCount = dropMask.nonzeroBitCount
            guard dropMask & ~validDropMask == 0,
                  dropCount <= item.tolerance,
                  dropCount <= 1 else {
                throw MuleinFutureMetalError.commandFailed(
                    "GPU emitted an invalid drop mask at slot \(slot)"
                )
            }

            var droppedIDs: [MuleinEdgeID] = []
            for edge in future.boardEdges.indices
            where dropMask & (UInt64(1) << UInt64(edge)) != 0 {
                droppedIDs.append(future.boardEdges[edge].id)
            }
            guard droppedIDs.count == dropCount,
                  Set(droppedIDs).count == droppedIDs.count else {
                throw MuleinFutureMetalError.commandFailed(
                    "GPU drop-mask provenance count failed at slot \(slot)"
                )
            }

            let pairCount = Int(rawHits[base + 5])
            let determinedCount = Int(rawHits[base + 6])
            guard (0...13).contains(pairCount),
                  (1...26).contains(determinedCount),
                  2 * pairCount <= determinedCount else {
                throw MuleinFutureMetalError.commandFailed(
                    "GPU emitted invalid plug counts at slot \(slot)"
                )
            }
            guard item.maxPlugs == 0 || pairCount <= item.maxPlugs else {
                throw MuleinFutureMetalError.commandFailed(
                    "GPU emitted a hit over its maximum plug budget at slot \(slot)"
                )
            }
            if item.exactPlugs > 0 {
                let enoughFreeLetters = 26 - determinedCount
                    >= 2 * (item.exactPlugs - pairCount)
                guard pairCount <= item.exactPlugs, enoughFreeLetters else {
                    throw MuleinFutureMetalError.commandFailed(
                        "GPU emitted a hit outside its exact plug budget at slot \(slot)"
                    )
                }
            }

            hits.append(
                MuleinFutureMetalHit(
                    settingLane: settingLane,
                    futureIndex: futureIndex,
                    futureID: future.id,
                    seed: seed,
                    droppedEdgeMask: dropMask,
                    repair: MuleinBoardRepairReceipt(droppedEdgeIDs: droppedIDs),
                    pairCount: pairCount,
                    determinedCount: determinedCount,
                    exact: dropMask == 0,
                    liveHash: rawHits[base + 7]
                )
            )
        }
        hits.sort {
            ($0.settingLane, $0.futureIndex, $0.seed)
                < ($1.settingLane, $1.futureIndex, $1.seed)
        }

        let gpuSeconds: Double = {
            let start = commands.gpuStartTime
            let end = commands.gpuEndTime
            return end >= start ? end - start : 0
        }()
        let statistics = MuleinFutureMetalStatistics(
            deviceName: deviceName,
            compileSeconds: compileSeconds,
            wallSeconds: wallSeconds,
            gpuSeconds: gpuSeconds,
            threadExecutionWidth: threadExecutionWidth,
            threadsPerThreadgroup: threadsPerThreadgroup,
            staticThreadgroupBytes: staticThreadgroupBytes,
            settingCount: settingRange.count,
            futureCount: work.count,
            trailLength: trailLengthValue,
            attemptedHits: attempted,
            writtenHits: written,
            overflowHits: overflow
        )
        if overflow > 0 && failOnOverflow {
            throw MuleinFutureMetalError.queueOverflow(
                attempted: attempted, written: written, capacity: hitCapacity
            )
        }
        return MuleinFutureMetalBatchResult(hits: hits, statistics: statistics)
    }

    /// Return a complete sparse result or fail. An overflowing prefix is never merged: the
    /// exact attempted count sizes a clean rerun, or the setting range is bisected recursively.
    package func evaluateComplete(
        work: [MuleinFutureMetalWork],
        bombe: WelchmanBombe,
        settingRange: Range<Int> = 0..<WelchmanMetalEngine.laneCount,
        initialHitCapacity: Int = 65_536,
        maximumRetryHitCapacity: Int = 1_000_000
    ) throws -> MuleinFutureMetalBatchResult {
        guard initialHitCapacity > 0, maximumRetryHitCapacity > 0 else {
            throw MuleinFutureMetalError.invalidBatch(
                "complete-drain capacities must be positive"
            )
        }

        func retimed(
            _ complete: MuleinFutureMetalBatchResult,
            adding discarded: MuleinFutureMetalStatistics
        ) -> MuleinFutureMetalBatchResult {
            MuleinFutureMetalBatchResult(
                hits: complete.hits,
                statistics: MuleinFutureMetalStatistics(
                    deviceName: deviceName,
                    compileSeconds: compileSeconds,
                    wallSeconds: discarded.wallSeconds + complete.statistics.wallSeconds,
                    gpuSeconds: discarded.gpuSeconds + complete.statistics.gpuSeconds,
                    threadExecutionWidth: threadExecutionWidth,
                    threadsPerThreadgroup: threadsPerThreadgroup,
                    staticThreadgroupBytes: staticThreadgroupBytes,
                    settingCount: complete.statistics.settingCount,
                    futureCount: work.count,
                    trailLength: complete.statistics.trailLength,
                    attemptedHits: complete.statistics.attemptedHits,
                    writtenHits: complete.statistics.writtenHits,
                    overflowHits: 0
                )
            )
        }

        func complete(_ range: Range<Int>) throws -> MuleinFutureMetalBatchResult {
            let maximumItems = UInt64(range.count) * UInt64(work.count) * 26
            let capacity = max(1, min(initialHitCapacity, Int(maximumItems)))
            let first = try evaluate(
                work: work,
                bombe: bombe,
                settingRange: range,
                hitCapacity: capacity,
                failOnOverflow: false
            )
            if first.isComplete { return first }

            // The incomplete prefix is intentionally discarded. Atomic queue arrival order is
            // not a pagination cursor, so unioning it with any retry would be unsound.
            let attempted = first.statistics.attemptedHits
            if attempted <= maximumRetryHitCapacity || range.count == 1 {
                let retry = try evaluate(
                    work: work,
                    bombe: bombe,
                    settingRange: range,
                    hitCapacity: attempted,
                    failOnOverflow: true
                )
                guard retry.statistics.attemptedHits == attempted,
                      retry.statistics.writtenHits == attempted,
                      retry.isComplete else {
                    throw MuleinFutureMetalError.commandFailed(
                        "complete-drain retry changed its deterministic hit count"
                    )
                }
                return retimed(retry, adding: first.statistics)
            }

            let midpoint = range.lowerBound + range.count / 2
            guard midpoint > range.lowerBound, midpoint < range.upperBound else {
                throw MuleinFutureMetalError.queueOverflow(
                    attempted: attempted,
                    written: first.statistics.writtenHits,
                    capacity: capacity
                )
            }
            let leftRange = range.lowerBound..<midpoint
            let rightRange = midpoint..<range.upperBound
            let left = try complete(leftRange)
            let right = try complete(rightRange)
            guard left.statistics.settingCount == leftRange.count,
                  right.statistics.settingCount == rightRange.count,
                  leftRange.upperBound == rightRange.lowerBound else {
                throw MuleinFutureMetalError.commandFailed(
                    "complete-drain range coverage is not contiguous"
                )
            }

            var hits = left.hits + right.hits
            var keys = Set<MuleinFutureHitKey>()
            keys.reserveCapacity(hits.count)
            for hit in hits {
                let key = MuleinFutureHitKey(
                    settingLane: hit.settingLane,
                    futureIndex: hit.futureIndex,
                    seed: hit.seed
                )
                guard keys.insert(key).inserted else {
                    throw MuleinFutureMetalError.commandFailed(
                        "complete-drain produced a duplicate sparse key"
                    )
                }
            }
            hits.sort {
                ($0.settingLane, $0.futureIndex, $0.seed)
                    < ($1.settingLane, $1.futureIndex, $1.seed)
            }
            let finalHitCount = left.statistics.attemptedHits
                + right.statistics.attemptedHits
            guard finalHitCount == hits.count else {
                throw MuleinFutureMetalError.commandFailed(
                    "complete-drain hit count disagrees with its complete chunks"
                )
            }

            return MuleinFutureMetalBatchResult(
                hits: hits,
                statistics: MuleinFutureMetalStatistics(
                    deviceName: deviceName,
                    compileSeconds: compileSeconds,
                    wallSeconds: first.statistics.wallSeconds
                        + left.statistics.wallSeconds + right.statistics.wallSeconds,
                    gpuSeconds: first.statistics.gpuSeconds
                        + left.statistics.gpuSeconds + right.statistics.gpuSeconds,
                    threadExecutionWidth: threadExecutionWidth,
                    threadsPerThreadgroup: threadsPerThreadgroup,
                    staticThreadgroupBytes: staticThreadgroupBytes,
                    settingCount: range.count,
                    futureCount: work.count,
                    trailLength: max(
                        first.statistics.trailLength,
                        max(left.statistics.trailLength, right.statistics.trailLength)
                    ),
                    attemptedHits: finalHitCount,
                    writtenHits: finalHitCount,
                    overflowHits: 0
                )
            )
        }

        return try complete(settingRange)
    }

    private func makeBuffer(_ values: [UInt32], label: String) throws -> MTLBuffer {
        guard !values.isEmpty else {
            throw MuleinFutureMetalError.invalidBatch("\(label) is empty")
        }
        let buffer: MTLBuffer? = values.withUnsafeBufferPointer { pointer in
            guard let base = pointer.baseAddress else { return nil }
            return device.makeBuffer(
                bytes: base,
                length: pointer.count * MemoryLayout<UInt32>.stride,
                options: .storageModeShared
            )
        }
        guard let buffer else { throw MuleinFutureMetalError.allocationFailed(label) }
        buffer.label = "Mulein \(label)"
        return buffer
    }

    private func byteTable(_ values: [Int]) -> [UInt8] {
        values.map { UInt8($0) }
    }

    private func notchTable(_ rotor: EnigmaRotorSpec) -> [UInt8] {
        var table = [UInt8](repeating: 0, count: 26)
        for notch in rotor.notches { table[notch] = 1 }
        return table
    }
}

/// Independent blind receipt oracle. It constructs rows from the public rotor shell and blindly
/// enumerates every one-edge reduction through `MuleinBoard`; it does not share Metal's active-
/// edge candidate prune and never consults a known key or plaintext truth while evaluating.
package func evaluateMuleinFutureSwiftOracle(
    work: [MuleinFutureMetalWork],
    bombe: WelchmanBombe,
    settingRange: Range<Int>
) throws -> [MuleinFutureMetalHit] {
    _ = try validateMuleinFutureWork(work)
    guard settingRange.lowerBound >= 0,
          settingRange.upperBound <= WelchmanMetalEngine.laneCount,
          !settingRange.isEmpty else {
        throw MuleinFutureMetalError.invalidBatch(
            "oracle setting range must be a non-empty position-space subset"
        )
    }

    var hits: [MuleinFutureMetalHit] = []
    var keys = Set<MuleinFutureHitKey>()
    for settingLane in settingRange {
        let positions = WelchmanMetalEngine.position(forLane: settingLane)
        for (futureIndex, item) in work.enumerated() {
            let future = item.future
            let scramblers = bombe.scramblers(menu: future.menu, start: positions)
            for seed in 0..<26 {
                guard let result = MuleinBoard.propagate(
                    menu: future.menu,
                    scramblers: scramblers,
                    seedLetter: future.menu.central,
                    seedValue: seed,
                    tolerance: item.tolerance,
                    maxPlugs: item.maxPlugs,
                    exactPlugs: item.exactPlugs
                ) else { continue }

                var dropMask: UInt64 = 0
                var droppedIDs: [MuleinEdgeID] = []
                for edgeIndex in result.droppedEdges {
                    guard future.boardEdges.indices.contains(edgeIndex) else {
                        throw MuleinFutureMetalError.commandFailed(
                            "Swift oracle emitted an out-of-range repair edge"
                        )
                    }
                    dropMask |= UInt64(1) << UInt64(edgeIndex)
                    droppedIDs.append(future.boardEdges[edgeIndex].id)
                }
                guard dropMask.nonzeroBitCount == droppedIDs.count else {
                    throw MuleinFutureMetalError.commandFailed(
                        "Swift oracle repair provenance is not one-to-one"
                    )
                }

                let key = MuleinFutureHitKey(
                    settingLane: settingLane, futureIndex: futureIndex, seed: seed
                )
                guard keys.insert(key).inserted else {
                    throw MuleinFutureMetalError.commandFailed(
                        "Swift oracle emitted a duplicate sparse key"
                    )
                }
                hits.append(
                    MuleinFutureMetalHit(
                        settingLane: settingLane,
                        futureIndex: futureIndex,
                        futureID: future.id,
                        seed: seed,
                        droppedEdgeMask: dropMask,
                        repair: MuleinBoardRepairReceipt(droppedEdgeIDs: droppedIDs),
                        pairCount: result.pairCount,
                        determinedCount: result.determinedCount,
                        exact: result.exact,
                        liveHash: result.liveHash
                    )
                )
            }
        }
    }
    return hits
}

// MARK: - Non-campaign benchmark / smoke grade

private struct MuleinFutureBenchmarkHit: Hashable {
    let setting: Int
    let futureID: String
    let seed: Int
    let dropMask: UInt64
    let repair: MuleinBoardRepairReceipt
    let pairCount: Int
    let determinedCount: Int
    let exact: Bool
    let liveHash: UInt32

    init(_ hit: MuleinFutureMetalHit) {
        setting = hit.settingLane
        futureID = hit.futureID.rawValue
        seed = hit.seed
        dropMask = hit.droppedEdgeMask
        repair = hit.repair
        pairCount = hit.pairCount
        determinedCount = hit.determinedCount
        exact = hit.exact
        liveHash = hit.liveHash
    }
}

private struct MuleinFutureBenchmarkMeasurement {
    let wall: Double
    let gpu: Double
    let hits: [MuleinFutureBenchmarkHit]
    let attempted: Int
    let overflow: Int
    let trailLength: Int
}

/// Benchmark the fused bank against repeated singleton dispatches over exactly the same futures
/// and setting range. This is a P1030684 known-key control only; it never reads P1030680 data.
func runMuleinFutureMetalGrade() {
    let requestedSettings = intFlag("--mulein-future-settings") ?? 2_048
    let settings = max(64, min(requestedSettings, WelchmanMetalEngine.laneCount))
    let repetitions = max(3, intFlag("--mulein-future-repetitions") ?? 5)
    let counts = [1, 2, 4, 8, 16]

    let ciphertext = EnigmaAlphabet.normalize(ControlMessageP1030684.ciphertext)
    let plaintext = EnigmaAlphabet.normalize(ControlMessageP1030684.plaintext)
    let truth = EnigmaM4Key.positions(fromLetters: ControlMessageP1030684.positions)
    let trueLane = truth.0 * 17576 + truth.1 * 676 + truth.2 * 26 + truth.3
    let lower = max(0, min(trueLane - settings / 2, WelchmanMetalEngine.laneCount - settings))
    let settingRange = lower..<(lower + settings)
    let bombe = ControlMessageP1030684.bombe(maxPlugs: 10)
    let trueStecker = ControlMessageP1030684.trueStecker

    var futures: [MuleinFutureMetalWork] = []
    let cribLength = 20
    for offset in 0..<16 {
        let crib = EnigmaAlphabet.string(from: Array(plaintext[offset..<(offset + cribLength)]))
        let evidence = MuleinFutureEvidence(
            targetID: "P1030684-control",
            sourceID: "published-known-key",
            cribID: "offset-\(offset)",
            crib: crib,
            transmittedOffset: offset,
            ciphertext: ciphertext
        )
        let lattice = MuleinFutureLattice.build(
            evidence: evidence, hypotheses: [.exact], minimumEdges: cribLength
        )
        guard let future = lattice.futures.first, lattice.rejected.isEmpty else {
            print("Mulein Future Bank fixture construction failed at offset \(offset)")
            exit(1)
        }
        futures.append(MuleinFutureMetalWork(
            future: future, tolerance: 0, maxPlugs: 10, exactPlugs: 10
        ))
    }

    print("=== Mulein Future Bank — fused cleartext Metal grade ===")
    print("control       : P1030684 published key only (no P1030680 target data)")
    print("engine        : one threadgroup/setting; one shared S_0...S_n trail")
    print("work          : future × 26 seeds; sparse 32-byte provenance records")
    print("settings      : \(settingRange.lowerBound)..<\(settingRange.upperBound) "
        + "(\(settings), includes true lane \(trueLane))")
    print("repetitions   : \(repetitions) per F; warm-up excluded")
    print("semantics     : exact closure; max 10 and exact-10 completion sieve; tolerance disabled")
    print("scope         : cleartext Metal board evaluation; not FHE, not a campaign run")
    print()

    do {
        let engine = try MuleinFutureMetalEngine()
        print("device        : \(engine.deviceName)")
        print(String(format: "pipeline      : compile %.3fs, SIMD %d, threads/TG %d, TG memory %d B",
                     engine.compileSeconds, engine.threadExecutionWidth,
                     engine.threadsPerThreadgroup, engine.staticThreadgroupBytes))

        let warmCount = min(128, settingRange.count)
        let warmLower = max(settingRange.lowerBound, trueLane - warmCount / 2)
        let warmUpper = min(settingRange.upperBound, warmLower + warmCount)
        _ = try engine.evaluate(
            work: [futures[0]], bombe: bombe,
            settingRange: warmLower..<warmUpper,
            hitCapacity: warmCount * 26
        )

        print()
        print("  F   fused wall med/p95   fused GPU med/p95    repeated med/p95   speedup  "
            + "future-settings/s   seed-closures/s   hits  queue")

        var allPassed = true
        for count in counts {
            let batch = Array(futures.prefix(count))
            let maximumHits = settings * count * 26
            let capacity = min(maximumHits, 1_000_000)
            var fused: [MuleinFutureBenchmarkMeasurement] = []
            var repeated: [MuleinFutureBenchmarkMeasurement] = []

            func receipts(
                _ result: MuleinFutureMetalBatchResult
            ) throws -> [MuleinFutureBenchmarkHit] {
                let values = result.hits.map(MuleinFutureBenchmarkHit.init)
                guard Set(values).count == values.count else {
                    throw MuleinFutureMetalError.benchmarkMismatch(
                        "sparse result contains duplicate full receipts"
                    )
                }
                return values.sorted {
                    ($0.setting, $0.futureID, $0.seed)
                        < ($1.setting, $1.futureID, $1.seed)
                }
            }

            func runFused() throws -> MuleinFutureBenchmarkMeasurement {
                // Match the repeated arm's end-to-end boundary: include host packing,
                // allocations, command creation/encoding, submission, and completion.
                let started = CFAbsoluteTimeGetCurrent()
                let result = try engine.evaluate(
                    work: batch, bombe: bombe, settingRange: settingRange,
                    hitCapacity: capacity
                )
                let normalizedHits = try receipts(result)
                let wall = CFAbsoluteTimeGetCurrent() - started
                return MuleinFutureBenchmarkMeasurement(
                    wall: wall,
                    gpu: result.statistics.gpuSeconds,
                    hits: normalizedHits, attempted: result.statistics.attemptedHits,
                    overflow: result.statistics.overflowHits,
                    trailLength: result.statistics.trailLength
                )
            }

            func runRepeated() throws -> MuleinFutureBenchmarkMeasurement {
                let started = CFAbsoluteTimeGetCurrent()
                var gpu = 0.0
                var hits: [MuleinFutureBenchmarkHit] = []
                var attempted = 0
                var overflow = 0
                var trailLength = 0
                for item in batch {
                    let result = try engine.evaluate(
                        work: [item], bombe: bombe, settingRange: settingRange,
                        hitCapacity: min(settings * 26, capacity)
                    )
                    gpu += result.statistics.gpuSeconds
                    hits.append(contentsOf: try receipts(result))
                    attempted += result.statistics.attemptedHits
                    overflow += result.statistics.overflowHits
                    trailLength = max(trailLength, result.statistics.trailLength)
                }
                guard Set(hits).count == hits.count else {
                    throw MuleinFutureMetalError.benchmarkMismatch(
                        "singleton union contains duplicate full receipts"
                    )
                }
                hits.sort {
                    ($0.setting, $0.futureID, $0.seed)
                        < ($1.setting, $1.futureID, $1.seed)
                }
                return MuleinFutureBenchmarkMeasurement(
                    wall: CFAbsoluteTimeGetCurrent() - started,
                    gpu: gpu, hits: hits, attempted: attempted,
                    overflow: overflow, trailLength: trailLength
                )
            }

            for repetition in 0..<repetitions {
                // Alternate order to avoid giving one arm every cold or thermally-favored run.
                if repetition.isMultiple(of: 2) {
                    fused.append(try runFused())
                    repeated.append(try runRepeated())
                } else {
                    repeated.append(try runRepeated())
                    fused.append(try runFused())
                }
            }

            for index in 0..<repetitions where fused[index].hits != repeated[index].hits {
                throw MuleinFutureMetalError.benchmarkMismatch(
                    "F=\(count), repetition \(index): fused sparse hits differ from singleton union"
                )
            }
            for (repetition, measurement) in fused.enumerated() {
                for item in batch {
                    let expectedID = item.future.id.rawValue
                    let expectedSeed = trueStecker[item.future.menu.central]
                    let retained = measurement.hits.contains {
                        $0.setting == trueLane
                            && $0.futureID == expectedID
                            && $0.seed == expectedSeed
                            && $0.dropMask == 0
                            && $0.repair.droppedEdgeIDs.isEmpty
                            && $0.pairCount <= 10
                            && 26 - $0.determinedCount >= 2 * (10 - $0.pairCount)
                            && $0.exact
                    }
                    if !retained {
                        allPassed = false
                        print("  F=\(count), repetition \(repetition): repair-free true "
                            + "lane/seed failed the 10-plug completion sieve for future "
                            + expectedID)
                    }
                }
            }
            if fused.contains(where: { $0.overflow != 0 })
                || repeated.contains(where: { $0.overflow != 0 }) {
                allPassed = false
                print("  F=\(count): sparse queue overflowed")
            }
            if fused.contains(where: { $0.attempted != $0.hits.count })
                || repeated.contains(where: { $0.attempted != $0.hits.count }) {
                allPassed = false
                print("  F=\(count): sparse queue accounting is incomplete")
            }

            let fusedWall = fused.map(\.wall)
            let fusedGPU = fused.map(\.gpu)
            let repeatedWall = repeated.map(\.wall)
            let wallMedian = percentile(fusedWall, 0.50)
            let wallP95 = percentile(fusedWall, 0.95)
            let gpuMedian = percentile(fusedGPU, 0.50)
            let gpuP95 = percentile(fusedGPU, 0.95)
            let repeatedMedian = percentile(repeatedWall, 0.50)
            let repeatedP95 = percentile(repeatedWall, 0.95)
            let speedup = repeatedMedian / max(wallMedian, 1e-12)
            let futureRate = Double(settings * count) / max(wallMedian, 1e-12)
            let closureRate = futureRate * 26
            let hits = fused[0].attempted
            let queueBytes = min(hits, capacity) * muleinFutureHitBytes

            print(String(
                format: "%3d   %7.4f/%7.4f     %7.4f/%7.4f       %7.4f/%7.4f    %6.2fx    %10.3gM       %10.3gM   %5d  %.1f KiB",
                count, wallMedian, wallP95, gpuMedian, gpuP95,
                repeatedMedian, repeatedP95, speedup,
                futureRate / 1e6, closureRate / 1e6,
                hits, Double(queueBytes) / 1024.0
            ))
            fflush(stdout)
        }

        print()
        if allPassed {
            print("PASS: duplicate-free fused full receipts equal repeated singleton receipts")
            print("      for F=1,2,4,8,16; every repetition retains each future's repair-free")
            print("      P1030684 true lane/central seed under the exact-10 completion sieve;")
            print("      sparse queues are complete.")
        } else {
            print("FAIL: the Future Bank did not satisfy all benchmark control invariants.")
            exit(1)
        }
        print("This benchmark establishes shared-trail execution mechanics and throughput only.")
        print("Companion --mulein-future-control-grade covers blind Swift parity, transcript")
        print("repairs, overflow recovery, Greek-V, and the chunked full P1030684 drain.")
        print("Both grades are cleartext controls; neither evaluates P1030680 or establishes FHE.")
    } catch {
        fputs("FAIL: \(error)\n", stderr)
        fflush(stderr)
        exit(1)
    }
}

private func percentile(_ values: [Double], _ quantile: Double) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let index = max(0, min(sorted.count - 1, Int(ceil(quantile * Double(sorted.count))) - 1))
    return sorted[index]
}
