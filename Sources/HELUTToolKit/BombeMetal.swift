import Foundation
import Metal
import HELUTCore
import HELUTCLI

// MARK: - Welchman diagonal board on the GPU
//
// One thread per rotor setting; the grid is the whole 26⁴ window space. Each thread
// builds its own scramblers, then runs seed hypotheses through the menu and the
// diagonal board and writes back a 26-bit survivor mask.
//
// On the exact board (tolerance 0) a seed is propagated only when it is a fixed point
// of every closed walk through the test letter. That is Turing's loop test. It is a
// necessary filter, so the stops match the unfiltered board. Walks are packed on the
// host (`TuringMenuWalks`). The kernel follows four seeds along each walk at once.
// Tolerance above 0 skips the filter, because a dropped edge can remove the walk that
// would have rejected the seed.
//
// The step pattern of a lane depends only on the middle and right window positions.
// `WelchmanStepTable` can fill that 676-entry table once per shell. On this GPU it
// did not beat the notch walk, so the sweep leaves it off. There is no cache of the
// loop test: that cache pays when one thread loops the rings, and this kernel is one
// thread per window position.
//
// Pipelining: `depth` shared output buffers. Encode/commit into a free slot without
// waiting; the sweep loop keeps that many shells on the GPU while the host drains
// completed slots. Synchronous `sweep` is enqueue + wait for the rehearsal path.

let welchmanMaxEdges = 40
/// Distinct slow-wheel `(l, m)` states a lane may need across its menu span. A 72-letter
/// span advances the middle wheel at most three times, so four sufficed while the middle
/// ring was pinned. It is raised here because overflow used to be reported as
/// *eliminated* (see `WELCHMAN_UNDECIDED`), and a middle-ring sweep widens the reachable
/// state count.
private let welchmanMaxUpper = 8

/// All 26 seed hypotheses marked live: the kernel's "I could not decide this lane" code.
/// A lane that overflows `MAX_UPPER` writes this instead of 0, so the host re-tests it
/// on an engine that has no such cap. Reporting 0 there would silently discard a key.
let welchmanUndecidedMask: UInt32 = 0x03FF_FFFF

enum WelchmanMenuPackingError: Error, Equatable {
    case invalidEdgeCount(Int)
    case parallelArrayMismatch(steps: Int, ends: Int)
    case endpointOutOfRange(edge: Int, a: Int, b: Int)
    case stepOutOfRange(edge: Int, step: Int)
    case centralOutOfRange(Int)
}

struct PackedWelchmanMenu: Equatable {
    let edgeA: [UInt8]
    let edgeB: [UInt8]
    let edgeStep: [UInt8]
    let central: UInt32
}

/// Fail-closed host packing shared by legacy, splice, and constellation menus.
/// No integer is narrowed until every value has been proved representable.
func packWelchmanMenu(_ menu: BombeMenu) throws -> PackedWelchmanMenu {
    guard (1...welchmanMaxEdges).contains(menu.edgeCount) else {
        throw WelchmanMenuPackingError.invalidEdgeCount(menu.edgeCount)
    }
    guard menu.steps.count == menu.ends.count else {
        throw WelchmanMenuPackingError.parallelArrayMismatch(
            steps: menu.steps.count, ends: menu.ends.count
        )
    }
    guard (0..<26).contains(menu.central) else {
        throw WelchmanMenuPackingError.centralOutOfRange(menu.central)
    }
    var a: [UInt8] = [], b: [UInt8] = [], steps: [UInt8] = []
    a.reserveCapacity(menu.edgeCount); b.reserveCapacity(menu.edgeCount)
    steps.reserveCapacity(menu.edgeCount)
    for index in menu.ends.indices {
        let edge = menu.ends[index], step = menu.steps[index]
        guard (0..<26).contains(edge.0), (0..<26).contains(edge.1) else {
            throw WelchmanMenuPackingError.endpointOutOfRange(
                edge: index, a: edge.0, b: edge.1
            )
        }
        guard (0...255).contains(step) else {
            throw WelchmanMenuPackingError.stepOutOfRange(edge: index, step: step)
        }
        a.append(UInt8(edge.0)); b.append(UInt8(edge.1)); steps.append(UInt8(step))
    }
    return PackedWelchmanMenu(
        edgeA: a, edgeB: b, edgeStep: steps, central: UInt32(menu.central)
    )
}

/// Largest garble tolerance the kernel enumerates — owned by `MuleinBoard`, which explains
/// why the bound is structural (Metal has no recursion, so drop-set loops are unrolled) and
/// carries the cost model in `MuleinBoard.closuresPerSeed`. Above this, the host board in
/// `MuleinBoard.propagate` is the fallback.
let welchmanMaxTolerance = MuleinBoard.maxTolerance

/// The 676 stepping patterns of one middle/right notch pair.
///
/// Duif's V5 kernel computes this once per workgroup. Here the host computes it once
/// per shell, because a shell already fixes the two wheels. Each pattern stores the
/// first step index at which the left wheel has stepped 1…6 times, then the same for
/// the middle wheel up to 12. That covers a 72-letter message: past it, a double-notch
/// pair can step more often, and `pack` returns nil so the kernel walks the notches
/// itself. Index 255 means "not within the horizon".
enum WelchmanStepTable {
    static let patterns = 26 * 26
    static let leftSlots = 6
    static let middleSlots = 12
    static let stride = leftSlots + middleSlots
    static let byteCount = patterns * stride
    static let never: UInt8 = 255

    /// `horizon` is the number of step-before-edge iterations, `menu.stepHorizon`.
    static func pack(notchM: [Int], notchR: [Int], horizon: Int) -> [UInt8]? {
        let middleNotch = Set(notchM)
        let rightNotch = Set(notchR)
        var packed = [UInt8](repeating: never, count: byteCount)
        let steps = max(0, horizon)
        for startM in 0..<26 {
            for startR in 0..<26 {
                var windowM = startM
                var windowR = startR
                var steppedLeft = 0
                var steppedMiddle = 0
                let base = (startM * 26 + startR) * stride
                for t in 0..<steps {
                    if t > Int(never) - 1 { return nil }
                    let middleHits = middleNotch.contains(windowM)
                    let rightHits = rightNotch.contains(windowR)
                    if middleHits {
                        steppedLeft += 1
                        steppedMiddle += 1
                    } else if rightHits {
                        steppedMiddle += 1
                    }
                    if steppedLeft > leftSlots || steppedMiddle > middleSlots {
                        return nil
                    }
                    if middleHits {
                        packed[base + steppedLeft - 1] = UInt8(t)
                    }
                    if middleHits || rightHits {
                        packed[base + leftSlots + steppedMiddle - 1] = UInt8(t)
                        windowM = (windowM + 1) % 26
                    }
                    windowR = (windowR + 1) % 26
                }
            }
        }
        return packed
    }
}

private let welchmanMetalSource = """
#include <metal_stdlib>
using namespace metal;

#define MAX_EDGES \(welchmanMaxEdges)
#define MAX_UPPER \(welchmanMaxUpper)
#define MAX_TOL \(welchmanMaxTolerance)
#define WELCHMAN_UNDECIDED \(welchmanUndecidedMask)u

inline uchar rot_fwd(uchar ch, int offset, constant uchar *wiring) {
    int shifted = (int(ch) + offset) % 26;
    return uchar((int(wiring[shifted]) - offset + 26) % 26);
}

inline uchar rot_inv(uchar ch, int offset, constant uchar *inverse) {
    int shifted = (int(ch) + offset) % 26;
    return uchar((int(inverse[shifted]) - offset + 26) % 26);
}

inline uint step_count(constant uchar *first, uint slots, uint t) {
    uint count = 0u;
    for (uint i = 0u; i < slots; ++i) {
        if (uint(first[i]) <= t) { count += 1u; }
        else { break; }
    }
    return count;
}

/// Record the slow-wheel state of one edge. False means `MAX_UPPER` overflowed.
inline bool note_upper(
    uchar l, uchar m,
    thread uchar *upperL, thread uchar *upperM, thread uint *upperCount,
    thread uchar *edgeUpper, uint e
) {
    uint slot = *upperCount;
    for (uint u = 0u; u < *upperCount; ++u) {
        if (upperL[u] == l && upperM[u] == m) { slot = u; break; }
    }
    if (slot == *upperCount) {
        if (*upperCount >= uint(MAX_UPPER)) { return false; }
        upperL[*upperCount] = l;
        upperM[*upperCount] = m;
        *upperCount += 1u;
    }
    edgeUpper[e] = uchar(slot);
    return true;
}

\(MuleinBoard.metalClosureSource(maxEdges: welchmanMaxEdges, tolerance: welchmanMaxTolerance))

kernel void welchman_sweep(
    constant uchar *edgeA        [[buffer(0)]],
    constant uchar *edgeB        [[buffer(1)]],
    constant uchar *edgeStep     [[buffer(2)]],
    constant uint  &edgeCount    [[buffer(3)]],
    constant uint  &central      [[buffer(4)]],
    constant uchar *gFwd         [[buffer(5)]],
    constant uchar *gInv         [[buffer(6)]],
    constant uchar *lFwd         [[buffer(7)]],
    constant uchar *lInv         [[buffer(8)]],
    constant uchar *mFwd         [[buffer(9)]],
    constant uchar *mInv         [[buffer(10)]],
    constant uchar *rFwd         [[buffer(11)]],
    constant uchar *rInv         [[buffer(12)]],
    constant uchar *refl         [[buffer(13)]],
    constant uchar *notchM       [[buffer(14)]],
    constant uchar *notchR       [[buffer(15)]],
    constant uchar *rings        [[buffer(16)]],
    device   uint  *outSurvivors [[buffer(17)]],
    constant uint  &maxPlugs     [[buffer(18)]],
    constant uint  &exactPlugs   [[buffer(19)]],
    constant uint  &skipCovered  [[buffer(20)]],
    constant uint  &tolerance    [[buffer(21)]],
    constant uchar *walkEdges    [[buffer(22)]],
    constant ushort *walkOffset  [[buffer(23)]],
    constant uint  &walkCount    [[buffer(24)]],
    constant uchar *stepFirst    [[buffer(25)]],
    constant uint  &useStep      [[buffer(26)]],
    constant uint  &wideLoop     [[buffer(27)]],
    uint lane [[thread_position_in_grid]]
) {
    if (lane >= 456976u) return;

    uchar posG = uchar(lane / 17576u);
    uchar posL = uchar((lane / 676u) % 26u);
    uchar posM = uchar((lane / 26u) % 26u);
    uchar posR = uchar(lane % 26u);

    uint maxStep = 0u;
    for (uint e = 0u; e < edgeCount; ++e) {
        maxStep = max(maxStep, uint(edgeStep[e]));
    }

    // Middle-ring coverage skip. `skipCovered` is set only for rings[2] != 0, and it
    // drops exactly the lanes a rings-AAAA pass already decided. The equivalence: the
    // trail depends on *window* positions (notch tests are ring-free), so as long as
    // neither this lane's middle wheel nor the middle wheel of its ring-A partner
    // (start m - rings[2]) reaches its own notch across [0, maxStep], the middle wheel
    // steps only on right-wheel notches — identical times in both trails — the left
    // wheel never moves, and offsetM = m - rings[2] is literally the ring-A partner's
    // window. Same scramblers, same verdict. Any middle-notch hit breaks that
    // invariant, so those lanes are the ones a middle-ring sweep must actually test.
    if (skipCovered != 0u) {
        uchar mA = posM;
        uchar mB = uchar((uint(posM) + 26u - uint(rings[2])) % 26u);
        uchar rr = posR;
        bool hit = false;
        for (uint t = 0u; t <= maxStep && !hit; ++t) {
            bool notchA = notchM[mA] != 0;
            bool notchB = notchM[mB] != 0;
            if (notchA || notchB) { hit = true; break; }
            if (notchR[rr] != 0) {
                mA = uchar((uint(mA) + 1u) % 26u);
                mB = uchar((uint(mB) + 1u) % 26u);
            }
            rr = uchar((uint(rr) + 1u) % 26u);
        }
        if (!hit) { outSurvivors[lane] = 0u; return; }
    }

    uchar edgeUpper[MAX_EDGES];
    uchar edgeOffR[MAX_EDGES];
    uchar upperL[MAX_UPPER];
    uchar upperM[MAX_UPPER];
    uint  upperCount = 0u;

    if (useStep != 0u) {
        constant uchar *pat = stepFirst + (uint(posM) * 26u + uint(posR)) * 18u;
        for (uint e = 0u; e < edgeCount; ++e) {
            uint t = uint(edgeStep[e]);
            uint dL = step_count(pat, 6u, t);
            uint dM = step_count(pat + 6u, 12u, t);
            uchar l = uchar((uint(posL) + dL) % 26u);
            uchar m = uchar((uint(posM) + dM) % 26u);
            uchar r = uchar((uint(posR) + t + 1u) % 26u);
            if (!note_upper(l, m, upperL, upperM, &upperCount, edgeUpper, e)) {
                outSurvivors[lane] = WELCHMAN_UNDECIDED;
                return;
            }
            edgeOffR[e] = uchar((int(r) - int(rings[3]) + 26) % 26);
        }
    } else {
        uchar l = posL, m = posM, r = posR;
        for (uint t = 0u; t <= maxStep; ++t) {
            bool midNotch = notchM[m] != 0;
            bool rightNotch = notchR[r] != 0;
            if (midNotch) { l = uchar((uint(l) + 1u) % 26u); }
            if (midNotch || rightNotch) { m = uchar((uint(m) + 1u) % 26u); }
            r = uchar((uint(r) + 1u) % 26u);

            for (uint e = 0u; e < edgeCount; ++e) {
                if (uint(edgeStep[e]) != t) { continue; }
                if (!note_upper(l, m, upperL, upperM, &upperCount, edgeUpper, e)) {
                    // Undecided, not eliminated. The host engine has no slow-state cap,
                    // so hand it every seed rather than reporting a clean negative we
                    // did not earn.
                    outSurvivors[lane] = WELCHMAN_UNDECIDED;
                    return;
                }
                edgeOffR[e] = uchar((int(r) - int(rings[3]) + 26) % 26);
            }
        }
    }

    uchar upper[MAX_UPPER][26];
    int offsetG = (int(posG) - int(rings[0]) + 26) % 26;
    for (uint u = 0u; u < upperCount; ++u) {
        int offsetL = (int(upperL[u]) - int(rings[1]) + 26) % 26;
        int offsetM = (int(upperM[u]) - int(rings[2]) + 26) % 26;
        for (uint x = 0u; x < 26u; ++x) {
            uchar v = uchar(x);
            v = rot_fwd(v, offsetM, mFwd);
            v = rot_fwd(v, offsetL, lFwd);
            v = rot_fwd(v, offsetG, gFwd);
            v = refl[v];
            v = rot_inv(v, offsetG, gInv);
            v = rot_inv(v, offsetL, lInv);
            v = rot_inv(v, offsetM, mInv);
            upper[u][x] = v;
        }
    }

    uchar scram[MAX_EDGES * 26];
    for (uint e = 0u; e < edgeCount; ++e) {
        int off = int(edgeOffR[e]);
        uint u = uint(edgeUpper[e]);
        for (uint x = 0u; x < 26u; ++x) {
            uchar v = rot_fwd(uchar(x), off, rFwd);
            v = upper[u][v];
            scram[e * 26u + x] = rot_inv(v, off, rInv);
        }
    }

    uint effectiveTol = min(tolerance, uint(MAX_TOL));

    uint survivors = 0u;
    // Four seeds share one walk so the scrambler lookups are independent. One seed
    // at a time is the same test; `wideLoop` only changes how they are issued.
    uint seedStride = wideLoop != 0u ? 4u : 1u;
    for (uint base = 0u; base < 26u; base += seedStride) {
        uint group = min(seedStride, 26u - base);
        bool keep0 = true;
        bool keep1 = group > 1u;
        bool keep2 = group > 2u;
        bool keep3 = group > 3u;
        uchar h0 = uchar(base);
        uchar h1 = uchar(base + (group > 1u ? 1u : 0u));
        uchar h2 = uchar(base + (group > 2u ? 2u : 0u));
        uchar h3 = uchar(base + (group > 3u ? 3u : 0u));
        // Exact board only. The product around a walk is a consequence of the full
        // menu; once an edge may be deleted the same seed can close without it.
        if (effectiveTol == 0u && walkCount > 0u) {
            for (uint w = 0u; w < walkCount && (keep0 || keep1 || keep2 || keep3); ++w) {
                uchar v0 = h0, v1 = h1, v2 = h2, v3 = h3;
                uint end = uint(walkOffset[w + 1u]);
                for (uint i = uint(walkOffset[w]); i < end; ++i) {
                    uint col = uint(walkEdges[i]) * 26u;
                    if (keep0) { v0 = scram[col + uint(v0)]; }
                    if (keep1) { v1 = scram[col + uint(v1)]; }
                    if (keep2) { v2 = scram[col + uint(v2)]; }
                    if (keep3) { v3 = scram[col + uint(v3)]; }
                }
                keep0 = keep0 && (v0 == h0);
                keep1 = keep1 && (v1 == h1);
                keep2 = keep2 && (v2 == h2);
                keep3 = keep3 && (v3 == h3);
            }
        }
        for (uint s = 0u; s < group; ++s) {
        bool keep = s == 0u ? keep0 : (s == 1u ? keep1 : (s == 2u ? keep2 : keep3));
        if (!keep) { continue; }
        uint seed = base + s;

        uint live[26];
        if (!mulein_tolerant_closure(scram, edgeA, edgeB, edgeCount,
                              effectiveTol, central, seed, live)) { continue; }

        // Plugboard sieve, on the GPU where the stop is born rather than on the host
        // after it has been shipped back. `maxPlugs` reproduces the host rule exactly
        // (WelchmanBombe.test), so it changes throughput and not verdicts.
        if (maxPlugs > 0u || exactPlugs > 0u) {
            uint determined = 0u;
            uint halfPairs = 0u;
            for (uint x = 0u; x < 26u; ++x) {
                if (live[x] == 0u) { continue; }
                determined += 1u;
                if (uint(ctz(live[x])) != x) { halfPairs += 1u; }
            }
            uint pairs = halfPairs / 2u;
            if (maxPlugs > 0u && pairs > maxPlugs) { continue; }
            // Kriegsmarine boards carried *exactly* ten leads — all three recovered
            // U-534 daily keys and the P1030684 control have ten pairs. So the plugs the
            // menu has not yet forced still have to fit: each needs two letters, and a
            // letter this menu has already pinned (paired or self-steckered) cannot take
            // one. A board that runs out of free letters is not a machine anyone built.
            if (exactPlugs > 0u) {
                if (pairs > exactPlugs) { continue; }
                if ((26u - determined) < 2u * (exactPlugs - pairs)) { continue; }
            }
        }

        survivors |= 1u << seed;
        }
    }

    outSurvivors[lane] = survivors;
}
"""

/// One shell still on the GPU (or waiting to be drained by the host).
struct WelchmanInFlight {
    let slot: Int
    let commandBuffer: MTLCommandBuffer
    let shell: WelchmanShell
}

/// Sieves the kernel applies before a lane is shipped back to the host.
///
/// `maxPlugs` mirrors `WelchmanBombe.test` exactly, so enabling it cannot change a
/// verdict — it only stops the host from re-deriving stops it would have thrown away.
/// `exactPlugs` is a *stronger* claim about the target (a ten-lead Kriegsmarine board)
/// and is therefore opt-in. `skipMiddleRingCovered` drops lanes a rings-AAAA pass has
/// already decided, and is only ever set for shells whose middle ring is not A.
///
/// `garbleTolerance` is not a sieve but its opposite — it *widens* what survives, by letting a
/// lane drop up to that many menu edges on the hypothesis that a dropped edge is a
/// mis-transcribed ciphertext letter. It is listed here because it rides the same plumbing.
/// Zero is the historical board and the default; anything above it changes verdicts by design
/// and costs `1 + E + C(E,2) + C(E,3)` closures per seed, so it is always explicit.
struct WelchmanSieve {
    var maxPlugs: Int = 0
    var exactPlugs: Int = 0
    var skipMiddleRingCovered: Bool = false
    var garbleTolerance: Int = 0

    static let none = WelchmanSieve()
}

/// Everything the host needs to re-derive steckers once the GPU reports survivors.
struct WelchmanShell {
    let menu: BombeMenu
    let greek: EnigmaRotorSpec
    let left: EnigmaRotorSpec
    let middle: EnigmaRotorSpec
    let right: EnigmaRotorSpec
    let reflector: [Int]
    let rings: (Int, Int, Int, Int)
    let ukwName: String
    let greekName: String
    let wheelOrder: String
}

/// GPU sweep of the full 26⁴ window space, with a pool of output buffers so shells
/// can be committed without waiting for the previous one to finish.
final class WelchmanMetalEngine {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState
    private let buffers: [MTLBuffer]
    private let stepBuffers: [MTLBuffer]
    private var freeSlots: [Int]
    private let lock = NSLock()
    private let slotsAvailable: DispatchSemaphore

    /// How many shells may be in flight at once.
    let depth: Int

    /// Sieves applied inside the kernel. Default is none, so the rehearsal cross-check
    /// keeps comparing raw board logic against the host engine.
    var sieve: WelchmanSieve = .none

    /// Turing's loop test. Off propagates every seed. Same stops on the exact board.
    var loopTest = true

    /// Host step table. Measured on the M4 Max it was slower than the notch walk
    /// on a 26-letter window and about 3% faster on a 67-step span, so it stays off.
    var adoptStepTable = false

    /// Follow four loop-test seeds at once. Off tests one seed at a time. Same stops.
    /// On the M4 Max this was the faster of the two, on both bench cribs.
    var wideLoopTest = true

    static let laneCount = 26 * 26 * 26 * 26 // 456,976
    static let defaultDepth = 4

    init?(depth: Int = WelchmanMetalEngine.defaultDepth) {
        let depth = max(1, depth)
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        guard let library = try? device.makeLibrary(source: welchmanMetalSource, options: nil),
              let function = library.makeFunction(name: "welchman_sweep"),
              let pipeline = try? device.makeComputePipelineState(function: function)
        else { return nil }

        let bytes = Self.laneCount * MemoryLayout<UInt32>.stride
        var buffers: [MTLBuffer] = []
        var stepBuffers: [MTLBuffer] = []
        buffers.reserveCapacity(depth)
        stepBuffers.reserveCapacity(depth)
        for _ in 0..<depth {
            guard let buffer = device.makeBuffer(length: bytes, options: .storageModeShared),
                  let steps = device.makeBuffer(
                    length: WelchmanStepTable.byteCount, options: .storageModeShared
                  )
            else { return nil }
            buffers.append(buffer)
            stepBuffers.append(steps)
        }

        self.device = device
        self.queue = queue
        self.pipeline = pipeline
        self.buffers = buffers
        self.stepBuffers = stepBuffers
        self.freeSlots = Array(0..<depth)
        self.slotsAvailable = DispatchSemaphore(value: depth)
        self.depth = depth
    }

    /// Encode and commit; blocks only if every pipeline slot is already in flight.
    func enqueue(shell: WelchmanShell) -> WelchmanInFlight? {
        guard let packed = try? packWelchmanMenu(shell.menu) else { return nil }
        slotsAvailable.wait()

        lock.lock()
        guard let slot = freeSlots.popLast() else {
            lock.unlock()
            slotsAvailable.signal()
            return nil
        }
        lock.unlock()

        guard let commands = queue.makeCommandBuffer(),
              let encoder = commands.makeComputeCommandEncoder() else {
            releaseSlot(slot)
            return nil
        }

        let menu = shell.menu
        let edgeA = packed.edgeA
        let edgeB = packed.edgeB
        let edgeStep = packed.edgeStep
        var edgeCount = UInt32(menu.edgeCount)
        var central = packed.central

        encoder.setComputePipelineState(pipeline)
        encoder.setBytes(edgeA, length: edgeA.count, index: 0)
        encoder.setBytes(edgeB, length: edgeB.count, index: 1)
        encoder.setBytes(edgeStep, length: edgeStep.count, index: 2)
        encoder.setBytes(&edgeCount, length: MemoryLayout<UInt32>.size, index: 3)
        encoder.setBytes(&central, length: MemoryLayout<UInt32>.size, index: 4)

        let tables: [[UInt8]] = [
            bytes(shell.greek.wiring), bytes(shell.greek.inverse),
            bytes(shell.left.wiring), bytes(shell.left.inverse),
            bytes(shell.middle.wiring), bytes(shell.middle.inverse),
            bytes(shell.right.wiring), bytes(shell.right.inverse),
            bytes(shell.reflector),
            notchTable(shell.middle), notchTable(shell.right),
            [UInt8(shell.rings.0), UInt8(shell.rings.1),
             UInt8(shell.rings.2), UInt8(shell.rings.3)]
        ]
        for (offset, table) in tables.enumerated() {
            encoder.setBytes(table, length: table.count, index: 5 + offset)
        }
        encoder.setBuffer(buffers[slot], offset: 0, index: 17)

        var maxPlugs = UInt32(max(0, sieve.maxPlugs))
        var exactPlugs = UInt32(max(0, sieve.exactPlugs))
        // Never skip at ring A: that pass is the one every other ring defers to.
        var skipCovered = UInt32(
            sieve.skipMiddleRingCovered && shell.rings.2 != 0 ? 1 : 0
        )
        var tolerance = UInt32(max(0, min(sieve.garbleTolerance, welchmanMaxTolerance)))
        let loops = Self.loopBuffers(ends: menu.ends, central: menu.central)
        encoder.setBytes(&maxPlugs, length: MemoryLayout<UInt32>.size, index: 18)
        encoder.setBytes(&exactPlugs, length: MemoryLayout<UInt32>.size, index: 19)
        encoder.setBytes(&skipCovered, length: MemoryLayout<UInt32>.size, index: 20)
        encoder.setBytes(&tolerance, length: MemoryLayout<UInt32>.size, index: 21)
        encoder.setBytes(loops.edges, length: loops.edges.count, index: 22)
        encoder.setBytes(loops.offsets, length: loops.offsets.count * MemoryLayout<UInt16>.size, index: 23)
        var walkCount = loops.count
        if !loopTest { walkCount = 0 }
        encoder.setBytes(&walkCount, length: MemoryLayout<UInt32>.size, index: 24)

        let packedSteps = adoptStepTable
            ? WelchmanStepTable.pack(
                notchM: shell.middle.notches,
                notchR: shell.right.notches,
                horizon: shell.menu.stepHorizon
            )
            : nil
        var useStep = UInt32(packedSteps == nil ? 0 : 1)
        if let packedSteps {
            packedSteps.withUnsafeBytes { raw in
                stepBuffers[slot].contents().copyMemory(
                    from: raw.baseAddress!, byteCount: raw.count
                )
            }
        }
        encoder.setBuffer(stepBuffers[slot], offset: 0, index: 25)
        encoder.setBytes(&useStep, length: MemoryLayout<UInt32>.size, index: 26)
        var wideLoop = UInt32(wideLoopTest ? 1 : 0)
        encoder.setBytes(&wideLoop, length: MemoryLayout<UInt32>.size, index: 27)

        let width = min(pipeline.maxTotalThreadsPerThreadgroup, 256)
        encoder.dispatchThreads(
            MTLSize(width: Self.laneCount, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1)
        )
        encoder.endEncoding()
        commands.commit()

        return WelchmanInFlight(slot: slot, commandBuffer: commands, shell: shell)
    }

    /// Block until this shell finishes; returns the survivor mask buffer for its slot.
    func wait(_ flight: WelchmanInFlight) -> UnsafeBufferPointer<UInt32> {
        flight.commandBuffer.waitUntilCompleted()
        let pointer = buffers[flight.slot].contents()
            .bindMemory(to: UInt32.self, capacity: Self.laneCount)
        return UnsafeBufferPointer(start: pointer, count: Self.laneCount)
    }

    /// Return the slot to the free pool so another shell can reuse it.
    func release(_ flight: WelchmanInFlight) {
        releaseSlot(flight.slot)
    }

    /// Synchronous path for the rehearsal / GPU↔host cross-check.
    func sweep(
        menu: BombeMenu,
        greek: EnigmaRotorSpec,
        left: EnigmaRotorSpec,
        middle: EnigmaRotorSpec,
        right: EnigmaRotorSpec,
        reflector: [Int],
        rings: (Int, Int, Int, Int)
    ) -> UnsafeBufferPointer<UInt32>? {
        let shell = WelchmanShell(
            menu: menu, greek: greek, left: left, middle: middle, right: right,
            reflector: reflector, rings: rings,
            ukwName: "", greekName: "", wheelOrder: ""
        )
        guard let flight = enqueue(shell: shell) else { return nil }
        let survivors = wait(flight)
        // Copy before release — the slot may be reused by the next enqueue.
        let copy = Array(survivors)
        release(flight)
        return stash(copy)
    }

    private var syncStash: UnsafeMutablePointer<UInt32>?
    private func stash(_ values: [UInt32]) -> UnsafeBufferPointer<UInt32> {
        if syncStash == nil {
            syncStash = .allocate(capacity: Self.laneCount)
        }
        for (index, value) in values.enumerated() { syncStash![index] = value }
        return UnsafeBufferPointer(start: syncStash, count: Self.laneCount)
    }

    deinit {
        syncStash?.deallocate()
    }

    private func releaseSlot(_ slot: Int) {
        lock.lock()
        freeSlots.append(slot)
        lock.unlock()
        slotsAvailable.signal()
    }

    private func notchTable(_ rotor: EnigmaRotorSpec) -> [UInt8] {
        var table = [UInt8](repeating: 0, count: 26)
        for notch in rotor.notches { table[notch] = 1 }
        return table
    }

    private func bytes(_ values: [Int]) -> [UInt8] { values.map { UInt8($0) } }

    static func position(forLane lane: Int) -> (Int, Int, Int, Int) {
        (lane / 17576, (lane / 676) % 26, (lane / 26) % 26, lane % 26)
    }

    /// Walks for the kernel. `offsets[w]` is the first edge of walk `w`, and
    /// `offsets[count]` is the end. A menu with no loop ships a one-byte dummy so
    /// `setBytes` still has a buffer, and `count` stays 0.
    private static func loopBuffers(
        ends: [(Int, Int)],
        central: Int
    ) -> (edges: [UInt8], offsets: [UInt16], count: UInt32) {
        let walks = TuringMenuWalks.walks(ends: ends, central: central)
        var edges: [UInt8] = []
        var offsets: [UInt16] = [0]
        for walk in walks {
            for edge in walk {
                edges.append(UInt8(edge))
            }
            offsets.append(UInt16(edges.count))
        }
        if edges.isEmpty { edges = [0] }
        return (edges, offsets, UInt32(walks.count))
    }
}
