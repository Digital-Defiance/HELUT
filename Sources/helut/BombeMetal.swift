import Foundation
import Metal
import HELUTCore

// MARK: - Welchman diagonal board on the GPU
//
// One thread per rotor setting; the grid is the whole 26⁴ window space. Each thread
// builds its own scramblers, then runs all 26 seed hypotheses through the menu and
// the diagonal board and writes back a 26-bit survivor mask.
//
// Pipelining: `depth` shared output buffers. Encode/commit into a free slot without
// waiting; the sweep loop keeps that many shells on the GPU while the host drains
// completed slots. Synchronous `sweep` is enqueue + wait for the rehearsal path.

let welchmanMaxEdges = 40
private let welchmanMaxUpper = 4

private let welchmanMetalSource = """
#include <metal_stdlib>
using namespace metal;

#define MAX_EDGES \(welchmanMaxEdges)
#define MAX_UPPER \(welchmanMaxUpper)

inline uchar rot_fwd(uchar ch, int offset, constant uchar *wiring) {
    int shifted = (int(ch) + offset) % 26;
    return uchar((int(wiring[shifted]) - offset + 26) % 26);
}

inline uchar rot_inv(uchar ch, int offset, constant uchar *inverse) {
    int shifted = (int(ch) + offset) % 26;
    return uchar((int(inverse[shifted]) - offset + 26) % 26);
}

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

    uchar edgeUpper[MAX_EDGES];
    uchar edgeOffR[MAX_EDGES];
    uchar upperL[MAX_UPPER];
    uchar upperM[MAX_UPPER];
    uint  upperCount = 0u;

    uchar l = posL, m = posM, r = posR;
    for (uint t = 0u; t <= maxStep; ++t) {
        bool midNotch = notchM[m] != 0;
        bool rightNotch = notchR[r] != 0;
        if (midNotch) { l = uchar((uint(l) + 1u) % 26u); }
        if (midNotch || rightNotch) { m = uchar((uint(m) + 1u) % 26u); }
        r = uchar((uint(r) + 1u) % 26u);

        for (uint e = 0u; e < edgeCount; ++e) {
            if (uint(edgeStep[e]) != t) { continue; }
            uint slot = upperCount;
            for (uint u = 0u; u < upperCount; ++u) {
                if (upperL[u] == l && upperM[u] == m) { slot = u; break; }
            }
            if (slot == upperCount) {
                if (upperCount >= MAX_UPPER) {
                    outSurvivors[lane] = 0u;
                    return;
                }
                upperL[upperCount] = l;
                upperM[upperCount] = m;
                upperCount += 1u;
            }
            edgeUpper[e] = uchar(slot);
            edgeOffR[e] = uchar((int(r) - int(rings[3]) + 26) % 26);
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

    uchar scram[MAX_EDGES][26];
    for (uint e = 0u; e < edgeCount; ++e) {
        int off = int(edgeOffR[e]);
        uint u = uint(edgeUpper[e]);
        for (uint x = 0u; x < 26u; ++x) {
            uchar v = rot_fwd(uchar(x), off, rFwd);
            v = upper[u][v];
            scram[e][x] = rot_inv(v, off, rInv);
        }
    }

    uint survivors = 0u;
    for (uint seed = 0u; seed < 26u; ++seed) {
        uint live[26];
        for (uint i = 0u; i < 26u; ++i) { live[i] = 0u; }
        live[central] = 1u << seed;

        bool dead = false;
        bool changed = true;
        while (changed && !dead) {
            changed = false;

            for (uint e = 0u; e < edgeCount && !dead; ++e) {
                uint a = uint(edgeA[e]);
                uint b = uint(edgeB[e]);

                uint mask = live[a];
                uint image = 0u;
                while (mask != 0u) {
                    uint bit = uint(ctz(mask));
                    mask &= mask - 1u;
                    image |= 1u << uint(scram[e][bit]);
                }
                if ((image & ~live[b]) != 0u) {
                    live[b] |= image;
                    if (popcount(live[b]) > 1) { dead = true; break; }
                    changed = true;
                }

                mask = live[b];
                image = 0u;
                while (mask != 0u) {
                    uint bit = uint(ctz(mask));
                    mask &= mask - 1u;
                    image |= 1u << uint(scram[e][bit]);
                }
                if ((image & ~live[a]) != 0u) {
                    live[a] |= image;
                    if (popcount(live[a]) > 1) { dead = true; break; }
                    changed = true;
                }
            }
            if (dead) { break; }

            for (uint x = 0u; x < 26u && !dead; ++x) {
                uint mask = live[x];
                while (mask != 0u) {
                    uint y = uint(ctz(mask));
                    mask &= mask - 1u;
                    uint bit = 1u << x;
                    if ((live[y] & bit) == 0u) {
                        live[y] |= bit;
                        if (popcount(live[y]) > 1) { dead = true; break; }
                        changed = true;
                    }
                }
            }
        }

        if (!dead) { survivors |= 1u << seed; }
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
    private var freeSlots: [Int]
    private let lock = NSLock()
    private let slotsAvailable: DispatchSemaphore

    /// How many shells may be in flight at once.
    let depth: Int

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
        buffers.reserveCapacity(depth)
        for _ in 0..<depth {
            guard let buffer = device.makeBuffer(length: bytes, options: .storageModeShared)
            else { return nil }
            buffers.append(buffer)
        }

        self.device = device
        self.queue = queue
        self.pipeline = pipeline
        self.buffers = buffers
        self.freeSlots = Array(0..<depth)
        self.slotsAvailable = DispatchSemaphore(value: depth)
        self.depth = depth
    }

    /// Encode and commit; blocks only if every pipeline slot is already in flight.
    func enqueue(shell: WelchmanShell) -> WelchmanInFlight? {
        guard shell.menu.edgeCount <= welchmanMaxEdges else { return nil }
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
        let edgeA = menu.ends.map { UInt8($0.0) }
        let edgeB = menu.ends.map { UInt8($0.1) }
        let edgeStep = menu.steps.map { UInt8($0) }
        var edgeCount = UInt32(menu.edgeCount)
        var central = UInt32(menu.central)

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
}
