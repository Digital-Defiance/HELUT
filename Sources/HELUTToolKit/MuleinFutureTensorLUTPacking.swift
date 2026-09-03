import HELUTCore

// MARK: - Verilog/TensorLUT Future Bank packing

/// One independently scheduled hardware slot. `tag` is only a compact ordinal into this host
/// table; the complete future and stable edge identities remain attached to `work`.
package struct MuleinFutureTensorLUTJob: Sendable {
    package let work: MuleinFutureMetalWork
    package let seed: Int
    package let tag: UInt32

    package init(work: MuleinFutureMetalWork, seed: Int, tag: UInt32) {
        self.work = work
        self.seed = seed
        self.tag = tag
    }
}

/// Full held receipt decoded from one slot of `mulein_future_tensorlut_top`.
package struct MuleinFutureTensorLUTCircuitReceipt: Sendable, Equatable {
    package let slot: Int
    package let valid: Bool
    package let configError: Bool
    package let hit: Bool
    package let tag: UInt32
    package let seed: Int
    package let exact: Bool
    package let droppedEdgeMask: UInt64
    package let erasedEdge: Int
    package let pairCount: Int
    package let determinedCount: Int
    package let liveHash: UInt32
    package let cycleCount: UInt32
    package let closureCount: UInt32
    package let dropTrialCount: UInt32
}

/// Slot-major, LSB-first primary-input image for one setting. The packed M4 trail is shared by
/// every slot in the Verilog bank; unused rows and slots are zero-filled and never addressed.
package struct MuleinFutureTensorLUTPackedBatch: Sendable {
    package let jobs: [MuleinFutureTensorLUTJob]
    package let bankLanes: Int
    package let maxEdges: Int
    package let maxSteps: Int
    package let edgeBits: Int
    package let stepBits: Int
    package let tagBits: Int
    package let stableInputs: [String: [UInt8]]

    package func portInputs(
        resetn: Bool,
        start: Bool,
        resultReadyMask: UInt64 = 0
    ) -> [String: [UInt8]] {
        var values = stableInputs
        values["clk"] = [0]
        values["resetn"] = [resetn ? 1 : 0]
        values["start"] = [start ? 1 : 0]
        values["result_ready"] = Self.bits(resultReadyMask, width: bankLanes)
        return values
    }

    package func decode(
        outputs: [String: [UInt8]],
        slot: Int
    ) throws -> MuleinFutureTensorLUTCircuitReceipt {
        guard (0..<bankLanes).contains(slot) else {
            throw MuleinFutureMetalError.invalidBatch("TensorLUT receipt slot is out of range")
        }

        func field(_ name: String, width: Int, base: Int) throws -> UInt64 {
            guard width <= 64, let source = outputs[name],
                  base >= 0, base + width <= source.count else {
                throw MuleinFutureMetalError.commandFailed(
                    "TensorLUT output \(name)[\(base)..<\(base + width)] is absent"
                )
            }
            var value: UInt64 = 0
            for bit in 0..<width where source[base + bit] != 0 {
                value |= UInt64(1) << UInt64(bit)
            }
            return value
        }

        return try MuleinFutureTensorLUTCircuitReceipt(
            slot: slot,
            valid: field("result_valid", width: 1, base: slot) != 0,
            configError: field("result_config_error", width: 1, base: slot) != 0,
            hit: field("result_hit", width: 1, base: slot) != 0,
            tag: UInt32(field("result_tags", width: tagBits, base: slot * tagBits)),
            seed: Int(field("result_seeds", width: 5, base: slot * 5)),
            exact: field("result_exact", width: 1, base: slot) != 0,
            droppedEdgeMask: field(
                "result_drop_masks", width: maxEdges, base: slot * maxEdges
            ),
            erasedEdge: Int(field(
                "result_erased_edges", width: edgeBits, base: slot * edgeBits
            )),
            pairCount: Int(field("result_pair_counts", width: 4, base: slot * 4)),
            determinedCount: Int(field(
                "result_determined_counts", width: 5, base: slot * 5
            )),
            liveHash: UInt32(field(
                "result_live_hashes", width: 32, base: slot * 32
            )),
            cycleCount: UInt32(field(
                "result_cycle_counts", width: 32, base: slot * 32
            )),
            closureCount: UInt32(field(
                "result_closure_counts", width: 32, base: slot * 32
            )),
            dropTrialCount: UInt32(field(
                "result_drop_trial_counts", width: 32, base: slot * 32
            ))
        )
    }

    /// Resolve a hardware mask back to stable evidence identities. A bit indexes the filtered
    /// ordered `future.boardEdges`, never a crib index.
    package func droppedEdgeIDs(
        for receipt: MuleinFutureTensorLUTCircuitReceipt
    ) throws -> [MuleinEdgeID] {
        guard jobs.indices.contains(receipt.slot) else {
            throw MuleinFutureMetalError.commandFailed("receipt has no host job metadata")
        }
        let edges = jobs[receipt.slot].work.future.boardEdges
        let validMask: UInt64 = edges.count == 64
            ? UInt64.max
            : ((UInt64(1) << UInt64(edges.count)) - 1)
        guard receipt.droppedEdgeMask & ~validMask == 0 else {
            throw MuleinFutureMetalError.commandFailed(
                "hardware receipt has a drop bit outside stable board-edge provenance"
            )
        }
        return edges.indices.compactMap { edge in
            (receipt.droppedEdgeMask & (UInt64(1) << UInt64(edge))) != 0
                ? edges[edge].id : nil
        }
    }

    fileprivate static func bits(_ value: UInt64, width: Int) -> [UInt8] {
        (0..<width).map { UInt8((value >> UInt64($0)) & 1) }
    }
}

package func packMuleinFutureTensorLUTBatch(
    jobs: [MuleinFutureTensorLUTJob],
    bombe: WelchmanBombe,
    setting: (Int, Int, Int, Int),
    bankLanes: Int,
    maxEdges: Int = 40,
    maxSteps: Int = 80,
    edgeBits: Int = 6,
    stepBits: Int = 7,
    tagBits: Int = 32
) throws -> MuleinFutureTensorLUTPackedBatch {
    guard !jobs.isEmpty, jobs.count <= bankLanes, bankLanes > 0, bankLanes <= 64 else {
        throw MuleinFutureMetalError.invalidBatch(
            "TensorLUT jobs must fit a positive bank of at most 64 lanes"
        )
    }
    guard maxEdges > 0, maxEdges <= 64,
          maxSteps > 0,
          edgeBits > 0, edgeBits < 64,
          stepBits > 0, stepBits < 64,
          tagBits == 32,
          (UInt64(1) << UInt64(edgeBits)) - 1 >= UInt64(maxEdges),
          (UInt64(1) << UInt64(stepBits)) >= UInt64(maxSteps) else {
        throw MuleinFutureMetalError.invalidBatch(
            "TensorLUT bank bounds or index widths are not representable"
        )
    }
    guard (0..<26).contains(setting.0), (0..<26).contains(setting.1),
          (0..<26).contains(setting.2), (0..<26).contains(setting.3) else {
        throw MuleinFutureMetalError.invalidBatch("TensorLUT setting is outside A...Z")
    }
    guard jobs.allSatisfy({ (0..<26).contains($0.seed) }),
          Set(jobs.map(\.tag)).count == jobs.count else {
        throw MuleinFutureMetalError.invalidBatch(
            "TensorLUT seeds must be letters and active tags must be unique"
        )
    }

    let maximumStep = try validateMuleinFutureWork(jobs.map(\.work))
    guard jobs.allSatisfy({ $0.work.future.menu.edgeCount <= maxEdges }),
          maximumStep < maxSteps else {
        throw MuleinFutureMetalError.invalidBatch(
            "TensorLUT work exceeds the selected edge/step bounds"
        )
    }

    func write(_ value: UInt64, width: Int, into target: inout [UInt8], at base: Int) {
        for bit in 0..<width {
            target[base + bit] = UInt8((value >> UInt64(bit)) & 1)
        }
    }

    var laneMask = [UInt8](repeating: 0, count: bankLanes)
    var edgeCounts = [UInt8](repeating: 0, count: bankLanes * edgeBits)
    var centrals = [UInt8](repeating: 0, count: bankLanes * 5)
    var seeds = [UInt8](repeating: 0, count: bankLanes * 5)
    var maxPlugs = [UInt8](repeating: 0, count: bankLanes * 5)
    var exactPlugs = [UInt8](repeating: 0, count: bankLanes * 5)
    var tolerances = [UInt8](repeating: 0, count: bankLanes * 2)
    var tags = [UInt8](repeating: 0, count: bankLanes * tagBits)
    var edgeA = [UInt8](repeating: 0, count: bankLanes * maxEdges * 5)
    var edgeB = [UInt8](repeating: 0, count: bankLanes * maxEdges * 5)
    var edgeSteps = [UInt8](repeating: 0, count: bankLanes * maxEdges * stepBits)

    var denseRows = Array(
        repeating: [UInt8](repeating: 0, count: 26), count: maxSteps
    )
    var populated = Set<Int>()

    for (slot, job) in jobs.enumerated() {
        let item = job.work
        let menu = item.future.menu
        laneMask[slot] = 1
        write(UInt64(menu.edgeCount), width: edgeBits, into: &edgeCounts, at: slot * edgeBits)
        write(UInt64(menu.central), width: 5, into: &centrals, at: slot * 5)
        write(UInt64(job.seed), width: 5, into: &seeds, at: slot * 5)
        write(UInt64(item.maxPlugs), width: 5, into: &maxPlugs, at: slot * 5)
        write(UInt64(item.exactPlugs), width: 5, into: &exactPlugs, at: slot * 5)
        write(UInt64(item.tolerance), width: 2, into: &tolerances, at: slot * 2)
        write(UInt64(job.tag), width: tagBits, into: &tags, at: slot * tagBits)

        let rows = bombe.scramblers(menu: menu, start: setting)
        guard rows.count == menu.edgeCount else {
            throw MuleinFutureMetalError.commandFailed(
                "scrambler row count disagrees with Future-Lattice geometry"
            )
        }
        for edge in menu.ends.indices {
            let a = menu.ends[edge].0
            let b = menu.ends[edge].1
            let step = menu.steps[edge]
            let edgeBase = slot * maxEdges + edge
            write(UInt64(a), width: 5, into: &edgeA, at: edgeBase * 5)
            write(UInt64(b), width: 5, into: &edgeB, at: edgeBase * 5)
            write(UInt64(step), width: stepBits, into: &edgeSteps, at: edgeBase * stepBits)

            let row = rows[edge]
            guard row.count == 26,
                  row.allSatisfy({ $0 < 26 }),
                  Set(row).count == 26 else {
                throw MuleinFutureMetalError.commandFailed(
                    "scrambler step \(step) is not a 26-letter permutation"
                )
            }
            if populated.contains(step) {
                guard denseRows[step] == row else {
                    throw MuleinFutureMetalError.commandFailed(
                        "shared scrambler step \(step) disagrees across futures"
                    )
                }
            } else {
                denseRows[step] = row
                populated.insert(step)
            }
        }
    }

    var stepRows = [UInt8](repeating: 0, count: maxSteps * 26 * 5)
    for step in populated {
        for letter in 0..<26 {
            write(
                UInt64(denseRows[step][letter]), width: 5,
                into: &stepRows, at: (step * 26 + letter) * 5
            )
        }
    }

    return MuleinFutureTensorLUTPackedBatch(
        jobs: jobs,
        bankLanes: bankLanes,
        maxEdges: maxEdges,
        maxSteps: maxSteps,
        edgeBits: edgeBits,
        stepBits: stepBits,
        tagBits: tagBits,
        stableInputs: [
            "start_lane_mask": laneMask,
            "start_edge_counts": edgeCounts,
            "start_centrals": centrals,
            "start_seeds": seeds,
            "start_max_plugs": maxPlugs,
            "start_exact_plugs": exactPlugs,
            "start_tolerances": tolerances,
            "start_tags": tags,
            "edge_a_tables": edgeA,
            "edge_b_tables": edgeB,
            "edge_step_tables": edgeSteps,
            "step_rows": stepRows
        ]
    )
}
