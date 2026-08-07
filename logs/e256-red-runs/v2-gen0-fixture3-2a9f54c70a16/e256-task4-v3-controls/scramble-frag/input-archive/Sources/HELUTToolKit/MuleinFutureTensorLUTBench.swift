import Foundation
import Darwin
import Metal
import HELUTCore
import HELUTCLI

// MARK: - Unified Verilog → Yosys → Float TensorLUT width grade

private let muleinTensorLUTModuleName = "mulein_future_tensorlut_top"
private let muleinTensorLUTLogicalJobsPerSetting = 16
private let muleinTensorLUTMaxEdges = 40
private let muleinTensorLUTMaxSteps = 80
private let muleinTensorLUTEdgeBits = 6
private let muleinTensorLUTStepBits = 7
private let muleinTensorLUTTagBits = 32
private let muleinTensorLUTOutputNames = [
    "result_valid", "result_config_error", "result_hit", "result_tags",
    "result_seeds", "result_exact", "result_drop_masks", "result_erased_edges",
    "result_pair_counts", "result_determined_counts", "result_live_hashes",
    "result_cycle_counts", "result_closure_counts", "result_drop_trial_counts"
]

private struct MuleinTensorLUTExpectedKey: Hashable {
    let settingLane: Int
    let futureIndex: Int
    let seed: Int
}

private struct MuleinTensorLUTJobDescriptor: Equatable {
    let logicalJob: Int
    let futureIndex: Int
    let tag: UInt32
}

private struct MuleinTensorLUTLanePlan {
    let settingLane: Int
    let packed: MuleinFutureTensorLUTPackedBatch
    let jobs: [MuleinTensorLUTJobDescriptor]
}

private struct MuleinTensorLUTReceiptRecord: Equatable {
    let settingLane: Int
    let logicalJob: Int
    let receipt: MuleinFutureTensorLUTCircuitReceipt
}

private struct MuleinTensorLUTCompletedRun {
    let submittedTicks: Int
    let wallSeconds: Double
    let records: [MuleinTensorLUTReceiptRecord]
    let digest: String
}

private struct MuleinTensorLUTFNV1a64 {
    private(set) var value: UInt64 = 0xcbf2_9ce4_8422_2325

    mutating func mix(_ raw: UInt64) {
        var value = raw
        for _ in 0..<8 {
            self.value ^= value & 0xff
            self.value &*= 0x0000_0100_0000_01b3
            value >>= 8
        }
    }
}

private func requireMuleinTensorLUT(
    _ condition: @autoclosure () -> Bool,
    _ message: @autoclosure () -> String
) throws {
    guard condition() else {
        throw MuleinFutureMetalError.benchmarkMismatch(message())
    }
}

private func muleinTensorLUTPercentile(_ values: [Double], _ quantile: Double) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let index = max(0, min(sorted.count - 1, Int(ceil(quantile * Double(sorted.count))) - 1))
    return sorted[index]
}

private func muleinTensorLUTMiB(_ bytes: UInt64) -> String {
    String(format: "%.3f MiB", Double(bytes) / (1024.0 * 1024.0))
}

private func muleinTensorLUTDigest(_ records: [MuleinTensorLUTReceiptRecord]) -> String {
    var hash = MuleinTensorLUTFNV1a64()
    let ordered = records.sorted {
        ($0.settingLane, $0.logicalJob) < ($1.settingLane, $1.logicalJob)
    }
    hash.mix(UInt64(ordered.count))
    for record in ordered {
        let receipt = record.receipt
        hash.mix(UInt64(record.settingLane))
        hash.mix(UInt64(record.logicalJob))
        hash.mix(receipt.valid ? 1 : 0)
        hash.mix(receipt.configError ? 1 : 0)
        hash.mix(receipt.hit ? 1 : 0)
        hash.mix(UInt64(receipt.tag))
        hash.mix(UInt64(receipt.seed))
        hash.mix(receipt.exact ? 1 : 0)
        hash.mix(receipt.droppedEdgeMask)
        hash.mix(UInt64(receipt.erasedEdge))
        hash.mix(UInt64(receipt.pairCount))
        hash.mix(UInt64(receipt.determinedCount))
        hash.mix(UInt64(receipt.liveHash))
        hash.mix(UInt64(receipt.cycleCount))
        hash.mix(UInt64(receipt.closureCount))
        hash.mix(UInt64(receipt.dropTrialCount))
    }
    return String(format: "fnv1a64-%016llx", hash.value)
}

/// Fair complete-receipt benchmark for one synthesized bank width.
///
/// Each process grades exactly 16 logical P1030684 jobs per setting. Wider RTL banks reduce
/// the outer TensorLUT batch by the same factor, so every width performs identical semantic
/// work. Netlist loading, compilation, packing, the Swift oracle, and one full warm-up run are
/// outside the reported steady-state timing window.
func runMuleinFutureTensorLUTGrade() {
    setbuf(stdout, nil)

    do {
        let bankLanes = intFlag("--mulein-future-bank-lanes") ?? 1
        let settingCount = intFlag("--mulein-future-settings") ?? 16
        let repetitions = intFlag("--mulein-future-repetitions") ?? 5
        let tickLimit = intFlag("--mulein-future-tick-limit") ?? 100_000
        let artifactPath = stringFlag("--mulein-future-tensorlut-json")
            ?? "build/mulein/mulein_future_bank\(bankLanes)_lut6.json"

        try requireMuleinTensorLUT(
            [1, 2, 4, 8, 16].contains(bankLanes)
                && muleinTensorLUTLogicalJobsPerSetting % bankLanes == 0,
            "bank width must be one of 1, 2, 4, 8, or 16"
        )
        try requireMuleinTensorLUT(settingCount > 0, "setting count must be positive")
        try requireMuleinTensorLUT(repetitions > 0, "repetition count must be positive")
        try requireMuleinTensorLUT(tickLimit >= 3, "tick limit must be at least three")

        guard let device = MTLCreateSystemDefaultDevice() else {
            throw MuleinFutureMetalError.noMetalDevice
        }

        print("=== Mulein Future Verilog→Yosys→Float TensorLUT width grade ===")
        print("scope              : P1030684 cleartext known-key controls; not FHE")
        print("target data        : none; no P1030680 verdict or decrypt is implied")
        print("device             : \(device.name)")
        print("bank_lanes         : \(bankLanes)")
        print("settings           : \(settingCount)")
        print("logical_jobs       : \(muleinTensorLUTLogicalJobsPerSetting) per setting")
        print("repetitions        : \(repetitions)")
        print("tick_limit         : \(tickLimit)")
        print("artifact           : \(artifactPath)")
        print("timing_window      : reset/start through all held-valid receipts")

        let rssStart = taskResidentMemoryBytes()
        let artifactURL = URL(fileURLWithPath: artifactPath)
        let artifactData = try Data(contentsOf: artifactURL, options: .mappedIfSafe)
        let loaded = try JSONDecoder().decode(YosysNetlist.self, from: artifactData)
        guard let module = loaded.modules[muleinTensorLUTModuleName] else {
            throw MuleinFutureMetalError.invalidBatch(
                "artifact lacks module \(muleinTensorLUTModuleName)"
            )
        }

        let executableCells = module.cells.values.filter { $0.type != "$scopeinfo" }
        let unsupported = Set(executableCells.map(\.type).filter {
            $0 != "$lut" && $0 != "$_DFF_P_"
        })
        try requireMuleinTensorLUT(
            unsupported.isEmpty,
            "unsupported executable cells: \(unsupported.sorted())"
        )
        try requireMuleinTensorLUT(
            module.ports["start_lane_mask"]?.bits.count == bankLanes,
            "artifact start_lane_mask width does not match --mulein-future-bank-lanes"
        )
        try requireMuleinTensorLUT(
            module.ports["result_valid"]?.bits.count == bankLanes,
            "artifact result_valid width does not match --mulein-future-bank-lanes"
        )

        let tensor = TensorLUTCompiler.compile(module: module)
        let lutCount = executableCells.filter { $0.type == "$lut" }.count
        let dffCount = executableCells.filter { $0.type == "$_DFF_P_" }.count
        try requireMuleinTensorLUT(lutCount > 0 && dffCount > 0, "artifact is not sequential LUT RTL")
        try requireMuleinTensorLUT(tensor.luts.count == lutCount, "TensorLUT lost LUT cells")
        try requireMuleinTensorLUT(tensor.dffs.count == dffCount, "TensorLUT lost DFF cells")
        try requireMuleinTensorLUT(
            tensor.executionLevels.reduce(0) { $0 + $1.count } == tensor.luts.count,
            "not every LUT was assigned to an execution level"
        )
        let rssAfterCompile = taskResidentMemoryBytes()

        let control = try makeMuleinFutureTensorLUTControlFixture()
        try requireMuleinTensorLUT(control.work.count == 4, "control fixture must contain four jobs")
        try requireMuleinTensorLUT(
            control.trueSeeds.count == control.work.count,
            "control truth-seed inventory is incomplete"
        )
        let settingUpper = control.settingLane + settingCount
        try requireMuleinTensorLUT(
            settingUpper <= WelchmanMetalEngine.laneCount,
            "requested settings run past the 26^4 setting space from the control lane"
        )
        let settingRange = control.settingLane..<settingUpper

        // Blind receipt oracle: truth seeds select submitted jobs only after the complete
        // setting/future/seed result set has been enumerated.
        let oracle = try evaluateMuleinFutureSwiftOracle(
            work: control.work,
            bombe: control.bombe,
            settingRange: settingRange
        )
        var expectedByKey: [MuleinTensorLUTExpectedKey: MuleinFutureMetalHit] = [:]
        for hit in oracle {
            let key = MuleinTensorLUTExpectedKey(
                settingLane: hit.settingLane,
                futureIndex: hit.futureIndex,
                seed: hit.seed
            )
            try requireMuleinTensorLUT(
                expectedByKey.updateValue(hit, forKey: key) == nil,
                "Swift oracle emitted a duplicate full receipt"
            )
        }

        let chunksPerSetting = muleinTensorLUTLogicalJobsPerSetting / bankLanes
        var plans: [MuleinTensorLUTLanePlan] = []
        plans.reserveCapacity(settingCount * chunksPerSetting)
        for (settingOrdinal, settingLane) in settingRange.enumerated() {
            let setting = WelchmanMetalEngine.position(forLane: settingLane)
            for chunk in 0..<chunksPerSetting {
                let lower = chunk * bankLanes
                var jobs: [MuleinFutureTensorLUTJob] = []
                var descriptors: [MuleinTensorLUTJobDescriptor] = []
                jobs.reserveCapacity(bankLanes)
                descriptors.reserveCapacity(bankLanes)
                for slot in 0..<bankLanes {
                    let logicalJob = lower + slot
                    let futureIndex = logicalJob % control.work.count
                    let ordinal = settingOrdinal * muleinTensorLUTLogicalJobsPerSetting + logicalJob
                    let tag = UInt32(0x4d00_0000) + UInt32(ordinal)
                    jobs.append(MuleinFutureTensorLUTJob(
                        work: control.work[futureIndex],
                        seed: control.trueSeeds[futureIndex],
                        tag: tag
                    ))
                    descriptors.append(MuleinTensorLUTJobDescriptor(
                        logicalJob: logicalJob,
                        futureIndex: futureIndex,
                        tag: tag
                    ))
                }
                let packed = try packMuleinFutureTensorLUTBatch(
                    jobs: jobs,
                    bombe: control.bombe,
                    setting: setting,
                    bankLanes: bankLanes,
                    maxEdges: muleinTensorLUTMaxEdges,
                    maxSteps: muleinTensorLUTMaxSteps,
                    edgeBits: muleinTensorLUTEdgeBits,
                    stepBits: muleinTensorLUTStepBits,
                    tagBits: muleinTensorLUTTagBits
                )
                plans.append(MuleinTensorLUTLanePlan(
                    settingLane: settingLane,
                    packed: packed,
                    jobs: descriptors
                ))
            }
        }

        let outerBatch = plans.count
        let logicalReceiptCount = settingCount * muleinTensorLUTLogicalJobsPerSetting
        try requireMuleinTensorLUT(
            outerBatch == settingCount * chunksPerSetting,
            "outer TensorLUT batch shape is inconsistent"
        )

        let pipeline = try TensorLUTPipeline(device: device, netlist: tensor)
        var initValues = tensor.packedINITBuffer()
        guard let initsBuffer = device.makeBuffer(
            bytes: initValues,
            length: initValues.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else {
            throw MuleinFutureMetalError.allocationFailed("TensorLUT INIT buffer")
        }
        initValues.removeAll(keepingCapacity: false)

        var initialWires = [Float](repeating: 0, count: outerBatch * tensor.totalWires)
        tensor.seedConstOne(into: &initialWires, batchSize: outerBatch)
        guard let wireBuffer = device.makeBuffer(
            bytes: initialWires,
            length: initialWires.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else {
            throw MuleinFutureMetalError.allocationFailed("TensorLUT dynamic wire buffer")
        }
        initialWires.removeAll(keepingCapacity: false)
        let wireCapacity = outerBatch * tensor.totalWires
        let wires = wireBuffer.contents().bindMemory(to: Float.self, capacity: wireCapacity)

        func writePort(_ name: String, bits: [UInt8], lane: Int) throws {
            guard let port = module.ports[name], port.direction == "input" else {
                throw MuleinFutureMetalError.invalidBatch("missing input port \(name)")
            }
            try requireMuleinTensorLUT(
                bits.count == port.bits.count,
                "input \(name) has \(bits.count) bits; artifact expects \(port.bits.count)"
            )
            for (index, bit) in port.bits.enumerated() {
                switch bit {
                case .net(let wire):
                    wires[lane * tensor.totalWires + wire] = Float(bits[index])
                case .constant(let value):
                    try requireMuleinTensorLUT(
                        value == UInt32(bits[index]),
                        "input \(name)[\(index)] disagrees with a constant artifact bit"
                    )
                }
            }
        }

        for (lane, plan) in plans.enumerated() {
            for (name, bits) in plan.packed.stableInputs {
                try writePort(name, bits: bits, lane: lane)
            }
            try writePort("clk", bits: [0], lane: lane)
        }

        let fullReadyMask = (UInt64(1) << UInt64(bankLanes)) - 1
        func writeControls(resetn: Bool, start: Bool, ready: UInt64) throws {
            let readyBits = (0..<bankLanes).map {
                UInt8((ready >> UInt64($0)) & 1)
            }
            for lane in plans.indices {
                try writePort("resetn", bits: [resetn ? 1 : 0], lane: lane)
                try writePort("start", bits: [start ? 1 : 0], lane: lane)
                try writePort("result_ready", bits: readyBits, lane: lane)
            }
        }

        func tick(resetn: Bool, start: Bool, ready: UInt64 = 0) throws {
            try writeControls(resetn: resetn, start: start, ready: ready)
            try pipeline.evaluateTickChecked(
                totalWires: tensor.totalWires,
                initsBuffer: initsBuffer,
                wireBuffer: wireBuffer,
                batchSize: outerBatch
            )
        }

        func readPort(_ name: String, lane: Int) throws -> [UInt8] {
            guard let port = module.ports[name], port.direction == "output" else {
                throw MuleinFutureMetalError.invalidBatch("missing output port \(name)")
            }
            return port.bits.map { bit in
                switch bit {
                case .constant(let value): return value == 0 ? 0 : 1
                case .net(let wire):
                    return wires[lane * tensor.totalWires + wire] >= 0.5 ? 1 : 0
                }
            }
        }

        func integer(_ bits: [UInt8]) -> UInt64 {
            var value: UInt64 = 0
            for bit in 0..<min(bits.count, 64) where bits[bit] != 0 {
                value |= UInt64(1) << UInt64(bit)
            }
            return value
        }

        func validMask(lane: Int) throws -> UInt64 {
            integer(try readPort("result_valid", lane: lane))
        }

        func allReceiptsValid() throws -> Bool {
            for lane in plans.indices {
                if try validMask(lane: lane) != fullReadyMask {
                    return false
                }
            }
            return true
        }

        func outputs(lane: Int) throws -> [String: [UInt8]] {
            var result: [String: [UInt8]] = [:]
            result.reserveCapacity(muleinTensorLUTOutputNames.count)
            for name in muleinTensorLUTOutputNames {
                result[name] = try readPort(name, lane: lane)
            }
            return result
        }

        func validateReceipt(
            _ receipt: MuleinFutureTensorLUTCircuitReceipt,
            plan: MuleinTensorLUTLanePlan,
            descriptor: MuleinTensorLUTJobDescriptor
        ) throws {
            let packedJob = plan.packed.jobs[receipt.slot]
            try requireMuleinTensorLUT(receipt.valid, "tag \(descriptor.tag) is not held valid")
            try requireMuleinTensorLUT(!receipt.configError, "tag \(descriptor.tag) has config_error")
            try requireMuleinTensorLUT(receipt.tag == descriptor.tag, "receipt tag mismatch")
            try requireMuleinTensorLUT(receipt.tag == packedJob.tag, "receipt lost packed job identity")
            try requireMuleinTensorLUT(receipt.seed == packedJob.seed, "receipt seed mismatch")
            try requireMuleinTensorLUT(receipt.cycleCount > 0, "receipt cycle count is zero")
            try requireMuleinTensorLUT(receipt.closureCount > 0, "receipt closure count is zero")

            let key = MuleinTensorLUTExpectedKey(
                settingLane: plan.settingLane,
                futureIndex: descriptor.futureIndex,
                seed: packedJob.seed
            )
            guard let expected = expectedByKey[key] else {
                try requireMuleinTensorLUT(!receipt.hit, "hardware emitted a false survivor")
                try requireMuleinTensorLUT(!receipt.exact, "negative receipt is marked exact")
                try requireMuleinTensorLUT(receipt.droppedEdgeMask == 0, "negative receipt has a drop mask")
                try requireMuleinTensorLUT(receipt.pairCount == 0, "negative receipt has plug pairs")
                try requireMuleinTensorLUT(receipt.determinedCount == 0, "negative receipt has determined rows")
                try requireMuleinTensorLUT(receipt.liveHash == 0, "negative receipt has a live hash")
                let droppedEdgeIDs = try plan.packed.droppedEdgeIDs(for: receipt)
                try requireMuleinTensorLUT(
                    droppedEdgeIDs.isEmpty,
                    "negative receipt has stable repair provenance"
                )
                return
            }

            try requireMuleinTensorLUT(receipt.hit, "Swift survivor was lost by TensorLUT")
            try requireMuleinTensorLUT(receipt.exact == expected.exact, "exact/repaired status mismatch")
            try requireMuleinTensorLUT(
                receipt.droppedEdgeMask == expected.droppedEdgeMask,
                "dropped-edge mask mismatch"
            )
            try requireMuleinTensorLUT(receipt.pairCount == expected.pairCount, "pair count mismatch")
            try requireMuleinTensorLUT(
                receipt.determinedCount == expected.determinedCount,
                "determined count mismatch"
            )
            try requireMuleinTensorLUT(receipt.liveHash == expected.liveHash, "live hash mismatch")
            let expectedErased = expected.droppedEdgeMask == 0
                ? (1 << muleinTensorLUTEdgeBits) - 1
                : expected.droppedEdgeMask.trailingZeroBitCount
            try requireMuleinTensorLUT(receipt.erasedEdge == expectedErased, "erased-edge index mismatch")
            let droppedEdgeIDs = try plan.packed.droppedEdgeIDs(for: receipt)
            try requireMuleinTensorLUT(
                droppedEdgeIDs == expected.repair.droppedEdgeIDs,
                "stable repair provenance mismatch"
            )
        }

        func decodeAndValidate() throws -> [MuleinTensorLUTReceiptRecord] {
            var records: [MuleinTensorLUTReceiptRecord] = []
            records.reserveCapacity(logicalReceiptCount)
            var tags = Set<UInt32>()
            for (lane, plan) in plans.enumerated() {
                let laneOutputs = try outputs(lane: lane)
                for slot in plan.jobs.indices {
                    let descriptor = plan.jobs[slot]
                    let receipt = try plan.packed.decode(outputs: laneOutputs, slot: slot)
                    try validateReceipt(receipt, plan: plan, descriptor: descriptor)
                    try requireMuleinTensorLUT(
                        tags.insert(receipt.tag).inserted,
                        "duplicate receipt tag \(receipt.tag)"
                    )
                    records.append(MuleinTensorLUTReceiptRecord(
                        settingLane: plan.settingLane,
                        logicalJob: descriptor.logicalJob,
                        receipt: receipt
                    ))
                }
            }
            try requireMuleinTensorLUT(
                records.count == logicalReceiptCount,
                "missing complete receipts: got \(records.count), expected \(logicalReceiptCount)"
            )
            return records
        }

        func executeComplete() throws -> MuleinTensorLUTCompletedRun {
            let started = CFAbsoluteTimeGetCurrent()
            try tick(resetn: false, start: false)
            var submittedTicks = 1
            try tick(resetn: true, start: true)
            submittedTicks += 1

            while !(try allReceiptsValid()) {
                guard submittedTicks < tickLimit else {
                    let missing = try plans.indices.filter {
                        try validMask(lane: $0) != fullReadyMask
                    }
                    throw MuleinFutureMetalError.commandFailed(
                        "TensorLUT timed out after \(submittedTicks) ticks; "
                            + "\(missing.count) outer lanes incomplete"
                    )
                }
                try tick(resetn: true, start: false)
                submittedTicks += 1
            }
            let wallSeconds = CFAbsoluteTimeGetCurrent() - started
            let records = try decodeAndValidate()
            let digest = muleinTensorLUTDigest(records)

            // Held receipt/backpressure is part of the grade, but intentionally outside the
            // throughput timing window.
            for _ in 0..<2 {
                try tick(resetn: true, start: false)
                let heldRecords = try decodeAndValidate()
                try requireMuleinTensorLUT(
                    heldRecords == records,
                    "held TensorLUT receipt changed under backpressure"
                )
            }

            try tick(resetn: true, start: false, ready: fullReadyMask)
            for lane in plans.indices {
                let consumedValidMask = try validMask(lane: lane)
                try requireMuleinTensorLUT(
                    consumedValidMask == 0,
                    "result_valid remained asserted after consume"
                )
            }
            // Bank-ready is combinational from the just-updated Q state and settles on the
            // next forward phase. This also proves that the next repetition is rearmed.
            try tick(resetn: true, start: false)
            for lane in plans.indices {
                let settledValidMask = try validMask(lane: lane)
                try requireMuleinTensorLUT(
                    settledValidMask == 0,
                    "stale receipt reappeared after consume"
                )
                let readyValue = integer(try readPort("bank_ready", lane: lane))
                try requireMuleinTensorLUT(
                    readyValue == 1,
                    "bank failed to rearm after consume"
                )
            }

            return MuleinTensorLUTCompletedRun(
                submittedTicks: submittedTicks,
                wallSeconds: wallSeconds,
                records: records,
                digest: digest
            )
        }

        let rssAfterBuffers = taskResidentMemoryBytes()
        print("artifact_bytes      : \(artifactData.count)")
        print("lut6                : \(tensor.luts.count)")
        print("dff                 : \(tensor.dffs.count)")
        print("wires               : \(tensor.totalWires)")
        print("levels              : \(tensor.executionLevels.count)")
        print("outer_batch_shape   : \(settingCount) × \(chunksPerSetting) = \(outerBatch)")
        let staticBytes = UInt64(tensor.luts.count) * 288 + UInt64(tensor.dffs.count) * 28
        let dynamicWireBytes = UInt64(outerBatch) * UInt64(tensor.totalWires)
            * UInt64(MemoryLayout<Float>.stride)
        print("accounted_static    : \(staticBytes) bytes (\(muleinTensorLUTMiB(staticBytes)))")
        print("dynamic_wire_bytes  : \(dynamicWireBytes) bytes (\(muleinTensorLUTMiB(dynamicWireBytes)))")
        print("rss_start           : \(rssStart) bytes (\(muleinTensorLUTMiB(rssStart)))")
        print("rss_after_compile   : \(rssAfterCompile) bytes (\(muleinTensorLUTMiB(rssAfterCompile)))")
        print("rss_after_buffers   : \(rssAfterBuffers) bytes (\(muleinTensorLUTMiB(rssAfterBuffers)))")
        print("oracle_hits         : \(oracle.count) complete blind Swift survivors")
        print()

        let warmup = try executeComplete()
        let rssAfterWarmup = taskResidentMemoryBytes()
        print(String(
            format: "warmup             : ticks=%d wall_s=%.6f digest=%@",
            warmup.submittedTicks, warmup.wallSeconds, warmup.digest
        ))
        print("rss_after_warmup    : \(rssAfterWarmup) bytes (\(muleinTensorLUTMiB(rssAfterWarmup)))")

        var runs: [MuleinTensorLUTCompletedRun] = []
        runs.reserveCapacity(repetitions)
        for repetition in 1...repetitions {
            let run = try executeComplete()
            try requireMuleinTensorLUT(
                run.digest == warmup.digest,
                "semantic receipt digest drifted on repetition \(repetition)"
            )
            runs.append(run)
            print(String(
                format: "rep %-2d              : ticks=%d wall_s=%.6f receipts_per_s=%.6f settings_per_s=%.6f",
                repetition,
                run.submittedTicks,
                run.wallSeconds,
                Double(logicalReceiptCount) / max(run.wallSeconds, 1e-12),
                Double(settingCount) / max(run.wallSeconds, 1e-12)
            ))
        }

        let receiptRates = runs.map {
            Double(logicalReceiptCount) / max($0.wallSeconds, 1e-12)
        }
        let settingRates = runs.map {
            Double(settingCount) / max($0.wallSeconds, 1e-12)
        }
        let receiptMedian = muleinTensorLUTPercentile(receiptRates, 0.50)
        let receiptP95 = muleinTensorLUTPercentile(receiptRates, 0.95)
        let settingMedian = muleinTensorLUTPercentile(settingRates, 0.50)
        let settingP95 = muleinTensorLUTPercentile(settingRates, 0.95)
        let rssFinal = taskResidentMemoryBytes()

        print()
        print("complete_receipts   : \(logicalReceiptCount) per repetition")
        print("receipt_digest      : \(warmup.digest)")
        print(String(format: "median_receipts_per_s: %.9f", receiptMedian))
        print(String(format: "p95_receipts_per_s  : %.9f", receiptP95))
        print(String(format: "median_settings_per_s: %.9f", settingMedian))
        print(String(format: "p95_settings_per_s  : %.9f", settingP95))
        print("rss_final           : \(rssFinal) bytes (\(muleinTensorLUTMiB(rssFinal)))")
        print("result              : PASS")
        print("scope               : cleartext Float TensorLUT/Metal, not FHE; no P1030680 verdict")
    } catch {
        fputs("MULEIN_FUTURE_TENSORLUT FAIL: \(error)\n", stderr)
        fflush(stderr)
        exit(1)
    }
}
