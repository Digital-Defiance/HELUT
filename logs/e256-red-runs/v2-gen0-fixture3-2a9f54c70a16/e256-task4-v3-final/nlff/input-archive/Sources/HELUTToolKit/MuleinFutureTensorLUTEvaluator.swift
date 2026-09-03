import Foundation
import Darwin
import CryptoKit
import Metal
import HELUTCore

// MARK: - Checked production TensorLUT execution

package struct MuleinFutureTensorLUTExecutionLane {
    package let settingLane: Int
    package let packed: MuleinFutureTensorLUTPackedBatch

    package init(settingLane: Int, packed: MuleinFutureTensorLUTPackedBatch) {
        self.settingLane = settingLane
        self.packed = packed
    }
}

package struct MuleinFutureTensorLUTEvaluatedReceipt {
    package let settingLane: Int
    package let job: MuleinFutureTensorLUTJob
    package let receipt: MuleinFutureTensorLUTCircuitReceipt
}

package struct MuleinFutureTensorLUTEvaluationResult {
    package let receipts: [MuleinFutureTensorLUTEvaluatedReceipt]
    package let submittedTicks: Int
    package let wallSeconds: Double
}

package func muleinSHA256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

/// Reusable fail-closed executor for the production Mulein Future TensorLUT artifact.
///
/// The evaluator owns one compiled Metal pipeline and a fixed-capacity dynamic wire buffer.
/// Every call clears state, resets the graph, requires one complete held receipt per submitted
/// job, checks tags/seeds/configuration, grades two backpressured ticks, consumes every active
/// slot, and proves the bank rearmed. It never decides whether a receipt is a cryptanalytic
/// BREAK; campaign code must host-replay positives before assigning any meaning to them.
package final class MuleinFutureTensorLUTEvaluator {
    package let artifactPath: String
    package let artifactBytes: Int
    package let artifactSHA256: String
    package let bankLanes: Int
    package let maximumBatchSize: Int
    package let deviceName: String
    package let lutCount: Int
    package let dffCount: Int
    package let totalWires: Int
    package let levelCount: Int

    private static let moduleName = "mulein_future_tensorlut_top"
    private static let outputNames = [
        "result_valid", "result_config_error", "result_hit", "result_tags",
        "result_seeds", "result_exact", "result_drop_masks", "result_erased_edges",
        "result_pair_counts", "result_determined_counts", "result_live_hashes",
        "result_cycle_counts", "result_closure_counts", "result_drop_trial_counts"
    ]

    private let module: YosysModule
    private let netlist: TensorLUTNetlist
    private let pipeline: TensorLUTPipeline
    private let initsBuffer: MTLBuffer
    private let wireBuffer: MTLBuffer
    private let wires: UnsafeMutablePointer<Float>

    package init(artifactPath: String, bankLanes: Int, maximumBatchSize: Int) throws {
        guard [1, 2, 4, 8, 16].contains(bankLanes), maximumBatchSize > 0 else {
            throw MuleinFutureMetalError.invalidBatch(
                "TensorLUT bank width must be 1/2/4/8/16 and batch capacity must be positive"
            )
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw MuleinFutureMetalError.noMetalDevice
        }

        let data = try Data(
            contentsOf: URL(fileURLWithPath: artifactPath), options: .mappedIfSafe
        )
        let yosys = try JSONDecoder().decode(YosysNetlist.self, from: data)
        guard let module = yosys.modules[Self.moduleName] else {
            throw MuleinFutureMetalError.invalidBatch(
                "TensorLUT artifact lacks module \(Self.moduleName)"
            )
        }
        let executable = module.cells.values.filter { $0.type != "$scopeinfo" }
        let unsupported = Set(executable.map(\.type).filter {
            $0 != "$lut" && $0 != "$_DFF_P_"
        })
        guard unsupported.isEmpty else {
            throw MuleinFutureMetalError.invalidBatch(
                "TensorLUT artifact has unsupported cells: \(unsupported.sorted())"
            )
        }
        guard module.ports["start_lane_mask"]?.bits.count == bankLanes,
              module.ports["result_valid"]?.bits.count == bankLanes else {
            throw MuleinFutureMetalError.invalidBatch(
                "TensorLUT artifact port width does not match bank width \(bankLanes)"
            )
        }

        let netlist = TensorLUTCompiler.compile(module: module)
        let lutCount = executable.filter { $0.type == "$lut" }.count
        let dffCount = executable.filter { $0.type == "$_DFF_P_" }.count
        guard lutCount > 0, dffCount > 0,
              netlist.luts.count == lutCount,
              netlist.dffs.count == dffCount,
              netlist.executionLevels.reduce(0, { $0 + $1.count }) == lutCount else {
            throw MuleinFutureMetalError.invalidBatch(
                "TensorLUT artifact did not compile to a complete sequential LUT graph"
            )
        }

        let pipeline = try TensorLUTPipeline(device: device, netlist: netlist)
        var inits = netlist.packedINITBuffer()
        guard let initsBuffer = device.makeBuffer(
            bytes: inits,
            length: inits.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else {
            throw MuleinFutureMetalError.allocationFailed("TensorLUT INIT buffer")
        }
        inits.removeAll(keepingCapacity: false)

        let wireCount = maximumBatchSize * netlist.totalWires
        guard wireCount > 0,
              let wireBuffer = device.makeBuffer(
                length: wireCount * MemoryLayout<Float>.stride,
                options: .storageModeShared
              ) else {
            throw MuleinFutureMetalError.allocationFailed("TensorLUT dynamic wire buffer")
        }

        self.artifactPath = artifactPath
        self.artifactBytes = data.count
        self.artifactSHA256 = muleinSHA256Hex(data)
        self.bankLanes = bankLanes
        self.maximumBatchSize = maximumBatchSize
        self.deviceName = device.name
        self.lutCount = lutCount
        self.dffCount = dffCount
        self.totalWires = netlist.totalWires
        self.levelCount = netlist.executionLevels.count
        self.module = module
        self.netlist = netlist
        self.pipeline = pipeline
        self.initsBuffer = initsBuffer
        self.wireBuffer = wireBuffer
        self.wires = wireBuffer.contents().bindMemory(to: Float.self, capacity: wireCount)
    }

    package func evaluate(
        lanes: [MuleinFutureTensorLUTExecutionLane],
        tickLimit: Int = 100_000
    ) throws -> MuleinFutureTensorLUTEvaluationResult {
        guard !lanes.isEmpty, lanes.count <= maximumBatchSize, tickLimit >= 3 else {
            throw MuleinFutureMetalError.invalidBatch(
                "TensorLUT execution batch is empty, over capacity, or has an invalid tick limit"
            )
        }
        guard lanes.allSatisfy({
            !$0.packed.jobs.isEmpty
                && $0.packed.jobs.count <= bankLanes
                && $0.packed.bankLanes == bankLanes
        }) else {
            throw MuleinFutureMetalError.invalidBatch(
                "TensorLUT execution lane has no jobs or mismatched bank metadata"
            )
        }

        let usedWireCount = lanes.count * totalWires
        memset(wires, 0, usedWireCount * MemoryLayout<Float>.stride)
        if let constOne = netlist.constOneWire {
            for lane in lanes.indices {
                wires[lane * totalWires + Int(constOne)] = 1
            }
        }

        func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else {
                throw MuleinFutureMetalError.commandFailed(message)
            }
        }

        func writePort(_ name: String, bits: [UInt8], lane: Int) throws {
            guard let port = module.ports[name], port.direction == "input" else {
                throw MuleinFutureMetalError.invalidBatch("missing TensorLUT input \(name)")
            }
            try require(
                bits.count == port.bits.count,
                "TensorLUT input \(name) width mismatch"
            )
            for (index, bit) in port.bits.enumerated() {
                switch bit {
                case .net(let wire):
                    wires[lane * totalWires + wire] = Float(bits[index])
                case .constant(let value):
                    try require(
                        value == UInt32(bits[index]),
                        "TensorLUT input \(name)[\(index)] conflicts with a constant bit"
                    )
                }
            }
        }

        for (lane, execution) in lanes.enumerated() {
            for (name, bits) in execution.packed.stableInputs {
                try writePort(name, bits: bits, lane: lane)
            }
            try writePort("clk", bits: [0], lane: lane)
        }

        let activeMasks: [UInt64] = lanes.map { execution in
            (UInt64(1) << UInt64(execution.packed.jobs.count)) - 1
        }

        func writeControls(resetn: Bool, start: Bool, ready: [UInt64]) throws {
            try require(ready.count == lanes.count, "TensorLUT ready-mask count mismatch")
            for lane in lanes.indices {
                let bits = (0..<bankLanes).map {
                    UInt8((ready[lane] >> UInt64($0)) & 1)
                }
                try writePort("resetn", bits: [resetn ? 1 : 0], lane: lane)
                try writePort("start", bits: [start ? 1 : 0], lane: lane)
                try writePort("result_ready", bits: bits, lane: lane)
            }
        }

        let noReady = [UInt64](repeating: 0, count: lanes.count)
        func tick(resetn: Bool, start: Bool, ready: [UInt64]) throws {
            try writeControls(resetn: resetn, start: start, ready: ready)
            try pipeline.evaluateTickChecked(
                totalWires: totalWires,
                initsBuffer: initsBuffer,
                wireBuffer: wireBuffer,
                batchSize: lanes.count
            )
        }

        func readPort(_ name: String, lane: Int) throws -> [UInt8] {
            guard let port = module.ports[name], port.direction == "output" else {
                throw MuleinFutureMetalError.invalidBatch("missing TensorLUT output \(name)")
            }
            return port.bits.map { bit in
                switch bit {
                case .constant(let value): return value == 0 ? 0 : 1
                case .net(let wire):
                    return wires[lane * totalWires + wire] >= 0.5 ? 1 : 0
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

        func validMask(_ lane: Int) throws -> UInt64 {
            integer(try readPort("result_valid", lane: lane))
        }

        func allValid() throws -> Bool {
            for lane in lanes.indices {
                if try validMask(lane) != activeMasks[lane] { return false }
            }
            return true
        }

        func decode() throws -> [MuleinFutureTensorLUTEvaluatedReceipt] {
            var decoded: [MuleinFutureTensorLUTEvaluatedReceipt] = []
            decoded.reserveCapacity(lanes.reduce(0) { $0 + $1.packed.jobs.count })
            var tags = Set<UInt32>()
            for (lane, execution) in lanes.enumerated() {
                var outputs: [String: [UInt8]] = [:]
                for name in Self.outputNames {
                    outputs[name] = try readPort(name, lane: lane)
                }
                for slot in execution.packed.jobs.indices {
                    let job = execution.packed.jobs[slot]
                    let receipt = try execution.packed.decode(outputs: outputs, slot: slot)
                    try require(receipt.valid, "TensorLUT returned a non-valid receipt")
                    try require(!receipt.configError, "TensorLUT returned config_error")
                    try require(receipt.tag == job.tag, "TensorLUT receipt tag mismatch")
                    try require(receipt.seed == job.seed, "TensorLUT receipt seed mismatch")
                    try require(receipt.cycleCount > 0, "TensorLUT receipt has zero cycles")
                    try require(receipt.closureCount > 0, "TensorLUT receipt has zero closures")
                    try require(tags.insert(receipt.tag).inserted, "duplicate TensorLUT receipt tag")
                    decoded.append(MuleinFutureTensorLUTEvaluatedReceipt(
                        settingLane: execution.settingLane,
                        job: job,
                        receipt: receipt
                    ))
                }
            }
            return decoded
        }

        let started = CFAbsoluteTimeGetCurrent()
        try tick(resetn: false, start: false, ready: noReady)
        var submittedTicks = 1
        try tick(resetn: true, start: true, ready: noReady)
        submittedTicks += 1
        while !(try allValid()) {
            guard submittedTicks < tickLimit else {
                let incomplete = try lanes.indices.filter {
                    try validMask($0) != activeMasks[$0]
                }
                throw MuleinFutureMetalError.commandFailed(
                    "TensorLUT timed out after \(submittedTicks) ticks; "
                        + "\(incomplete.count) execution lanes incomplete"
                )
            }
            try tick(resetn: true, start: false, ready: noReady)
            submittedTicks += 1
        }
        let wallSeconds = CFAbsoluteTimeGetCurrent() - started
        let receipts = try decode()
        let expectedCount = lanes.reduce(0) { $0 + $1.packed.jobs.count }
        try require(receipts.count == expectedCount, "TensorLUT receipt count is incomplete")

        for _ in 0..<2 {
            try tick(resetn: true, start: false, ready: noReady)
            let held = try decode().map(\.receipt)
            try require(
                held == receipts.map(\.receipt),
                "TensorLUT held receipt changed under backpressure"
            )
        }

        try tick(resetn: true, start: false, ready: activeMasks)
        for lane in lanes.indices {
            let consumed = try validMask(lane)
            try require(consumed == 0, "TensorLUT result_valid remained high after consume")
        }
        try tick(resetn: true, start: false, ready: noReady)
        for lane in lanes.indices {
            let stale = try validMask(lane)
            let ready = integer(try readPort("bank_ready", lane: lane))
            try require(stale == 0, "TensorLUT stale receipt reappeared after consume")
            try require(ready == 1, "TensorLUT bank did not rearm after consume")
        }

        return MuleinFutureTensorLUTEvaluationResult(
            receipts: receipts,
            submittedTicks: submittedTicks,
            wallSeconds: wallSeconds
        )
    }
}
