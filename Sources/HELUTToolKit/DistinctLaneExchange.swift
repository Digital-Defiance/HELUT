import CryptoKit
import Foundation
import HELUTCore

/// One port in the frozen lexicographic-port / ascending-bit interchange order.
package struct DistinctLanePortV1: Codable, Equatable, Sendable {
    package var name: String
    package var width: Int

    package init(name: String, width: Int) {
        self.name = name
        self.width = width
    }
}

/// A complete flattened bit row. `bits[0]` is bit zero of the first frozen port.
package struct DistinctLaneBitsV1: Codable, Equatable, Sendable {
    package var lane: Int
    package var bits: String

    package init(lane: Int, bits: String) {
        self.lane = lane
        self.bits = bits
    }
}

package struct DistinctLaneTimingV1: Codable, Equatable, Sendable {
    package var scope: String
    package var unit: String
    package var samples: [UInt64]
    package var warmup: Int

    package init(
        scope: String = DistinctLaneExchange.timingScope,
        unit: String = "nanoseconds",
        samples: [UInt64],
        warmup: Int
    ) {
        self.scope = scope
        self.unit = unit
        self.samples = samples
        self.warmup = warmup
    }
}

/// Backend/device fields are provenance, not trusted hardware attestation.
package struct DistinctLaneEnvironmentV1: Codable, Equatable, Sendable {
    package var executionBackend: String
    package var implementation: String
    package var implementationVersion: String?
    package var deviceName: String
    package var vendor: String?
    package var deviceIdentifier: String?
    package var driverVersion: String?
    package var operatingSystem: String?
    package var architecture: String?
    package var unifiedMemory: Bool?
    package var lowPower: Bool?
    package var removable: Bool?

    package init(
        executionBackend: String,
        implementation: String,
        implementationVersion: String? = nil,
        deviceName: String,
        vendor: String? = nil,
        deviceIdentifier: String? = nil,
        driverVersion: String? = nil,
        operatingSystem: String? = nil,
        architecture: String? = nil,
        unifiedMemory: Bool? = nil,
        lowPower: Bool? = nil,
        removable: Bool? = nil
    ) {
        self.executionBackend = executionBackend
        self.implementation = implementation
        self.implementationVersion = implementationVersion
        self.deviceName = deviceName
        self.vendor = vendor
        self.deviceIdentifier = deviceIdentifier
        self.driverVersion = driverVersion
        self.operatingSystem = operatingSystem
        self.architecture = architecture
        self.unifiedMemory = unifiedMemory
        self.lowPower = lowPower
        self.removable = removable
    }
}

/// Self-contained combinational distinct-lane workload. The exact source Yosys
/// JSON is embedded so a foreign backend does not need access to this repository.
package struct DistinctLaneWorkloadV1: Codable, Equatable, Sendable {
    package var schemaVersion: Int
    package var kind: String
    package var workloadID: String
    package var mode: String
    package var assignmentSchema: String
    package var encodingSchema: String
    package var lutSemantics: String
    package var outputDigestSchema: String
    package var timingScope: String
    package var netlistSHA256: String
    package var yosysJSONBase64: String
    package var moduleName: String
    package var degree: Int
    package var lanes: Int
    package var trials: Int
    package var warmup: Int
    package var inputPorts: [DistinctLanePortV1]
    package var outputPorts: [DistinctLanePortV1]
    package var laneInputs: [DistinctLaneBitsV1]
    package var expectedOutputDigest: String
}

package struct DistinctLaneResultV1: Codable, Equatable, Sendable {
    package var schemaVersion: Int
    package var kind: String
    package var workloadID: String
    package var outputRows: [DistinctLaneBitsV1]
    package var outputDigest: String
    package var timing: DistinctLaneTimingV1
    package var environment: DistinctLaneEnvironmentV1

    package init(
        schemaVersion: Int = 1,
        kind: String = DistinctLaneExchange.resultKind,
        workloadID: String,
        outputRows: [DistinctLaneBitsV1],
        outputDigest: String,
        timing: DistinctLaneTimingV1,
        environment: DistinctLaneEnvironmentV1
    ) {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.workloadID = workloadID
        self.outputRows = outputRows
        self.outputDigest = outputDigest
        self.timing = timing
        self.environment = environment
    }
}

package struct DistinctLaneReplayReceipt: Equatable, Sendable {
    package let workloadID: String
    package let lanes: Int
    package let inputBits: Int
    package let distinctInputAssignments: Int
    package let comparedBits: Int
    package let mismatches: Int
    package let distinctLaneOutputs: Int
    package let outputDigest: String
    package let firstNanoseconds: UInt64
    package let steadyMedianNanoseconds: Double
    package let steadyAverageNanoseconds: Double
    package let timingValid: Bool
}

package enum DistinctLaneExchangeError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalid(String)
    case missingModule(String)
    case ambiguousModules([String])
    case netlistIntegrity(expected: String, actual: String)
    case workloadIdentity(expected: String, actual: String)
    case resultWorkload(expected: String, actual: String)
    case outputDigest(expected: String, actual: String)

    package var description: String {
        switch self {
        case .invalid(let reason):
            return reason
        case .missingModule(let name):
            return "Yosys module '\(name)' is missing"
        case .ambiguousModules(let names):
            return "multiple executable Yosys modules; select one explicitly: \(names.joined(separator: ", "))"
        case .netlistIntegrity(let expected, let actual):
            return "embedded Yosys JSON SHA-256 mismatch: expected \(expected), got \(actual)"
        case .workloadIdentity(let expected, let actual):
            return "workload identity mismatch: expected \(expected), got \(actual)"
        case .resultWorkload(let expected, let actual):
            return "result targets workload \(actual), expected \(expected)"
        case .outputDigest(let expected, let actual):
            return "result output digest mismatch: declared \(expected), recomputed \(actual)"
        }
    }
}

/// Digest record shared with the shipped Metal distinct-lane verifier.
package struct DistinctBatchRecord: Equatable, Sendable {
    package let lane: Int
    package let port: String
    package let bit: Int
    package let value: UInt32

    package init(lane: Int, port: String, bit: Int, value: UInt32) {
        self.lane = lane
        self.port = port
        self.bit = bit
        self.value = value
    }
}

/// Compatibility checksum frozen by `fnv1a64-lane-port-bit-v1`.
package func distinctBatchChecksum(_ entries: [DistinctBatchRecord]) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    func mix(_ byte: UInt8) {
        hash ^= UInt64(byte)
        hash = hash &* 0x100_0000_01b3
    }
    for entry in entries.sorted(by: {
        ($0.lane, $0.port, $0.bit) < ($1.lane, $1.port, $1.bit)
    }) {
        withUnsafeBytes(of: UInt32(entry.lane).littleEndian) { $0.forEach(mix) }
        entry.port.utf8.forEach(mix)
        withUnsafeBytes(of: UInt32(entry.bit).littleEndian) { $0.forEach(mix) }
        withUnsafeBytes(of: entry.value.littleEndian) { $0.forEach(mix) }
    }
    return hash
}

package enum DistinctLaneExchange {
    package static let workloadKind = "helut.distinct-lane.workload.v1"
    package static let resultKind = "helut.distinct-lane.result.v1"
    package static let mode = "distinct-verified-v1"
    package static let assignmentSchema = "distinct-input-stride-v1"
    package static let encodingSchema = "constant-fill-u32-v1"
    package static let lutSemantics = "yosys-lut-lsb-address-v1"
    package static let outputDigestSchema = "fnv1a64-lane-port-bit-v1"
    package static let timingScope = "synchronized-graph-run-v1"

    package static func makeWorkload(
        netlistData: Data,
        moduleName requestedModule: String?,
        degree: Int,
        lanes: Int,
        trials: Int,
        warmup: Int
    ) throws -> DistinctLaneWorkloadV1 {
        let yosys = try decodeYosys(netlistData)
        let (moduleName, module) = try selectModule(yosys, requested: requestedModule)
        let (inputPorts, outputPorts) = try validateModule(
            moduleName: moduleName,
            module: module,
            degree: degree,
            lanes: lanes,
            trials: trials,
            warmup: warmup
        )
        let inputBits = inputPorts.reduce(0) { $0 + $1.width }
        let assignmentSpace = UInt64(1) << UInt64(inputBits)
        let stride = max(UInt64(1), assignmentSpace / UInt64(lanes))
        let laneInputs = (0..<lanes).map { lane in
            DistinctLaneBitsV1(
                lane: lane,
                bits: bitString(mask: UInt64(lane) * stride, width: inputBits)
            )
        }
        let expectedRows = try oracleRows(
            moduleName: moduleName,
            module: module,
            inputPorts: inputPorts,
            outputPorts: outputPorts,
            laneInputs: laneInputs
        )
        let expectedDigest = digestString(records(for: expectedRows, ports: outputPorts))
        let netlistSHA = sha256ID(netlistData)
        var workload = DistinctLaneWorkloadV1(
            schemaVersion: 1,
            kind: workloadKind,
            workloadID: "",
            mode: mode,
            assignmentSchema: assignmentSchema,
            encodingSchema: encodingSchema,
            lutSemantics: lutSemantics,
            outputDigestSchema: outputDigestSchema,
            timingScope: timingScope,
            netlistSHA256: netlistSHA,
            yosysJSONBase64: netlistData.base64EncodedString(),
            moduleName: moduleName,
            degree: degree,
            lanes: lanes,
            trials: trials,
            warmup: warmup,
            inputPorts: inputPorts,
            outputPorts: outputPorts,
            laneInputs: laneInputs,
            expectedOutputDigest: expectedDigest
        )
        workload.workloadID = workloadIdentity(workload)
        return workload
    }

    package static func makeResult(
        workload: DistinctLaneWorkloadV1,
        outputRows: [DistinctLaneBitsV1],
        timingSamplesNanoseconds: [UInt64],
        environment: DistinctLaneEnvironmentV1
    ) throws -> DistinctLaneResultV1 {
        _ = try validatedWorkload(workload)
        try validateRows(
            outputRows,
            lanes: workload.lanes,
            width: workload.outputPorts.reduce(0) { $0 + $1.width },
            label: "result output"
        )
        guard timingSamplesNanoseconds.count == workload.trials else {
            throw DistinctLaneExchangeError.invalid(
                "result has \(timingSamplesNanoseconds.count) timing samples; expected \(workload.trials)"
            )
        }
        try validateEnvironment(environment)
        let digest = digestString(records(for: outputRows, ports: workload.outputPorts))
        return DistinctLaneResultV1(
            workloadID: workload.workloadID,
            outputRows: outputRows.sorted { $0.lane < $1.lane },
            outputDigest: digest,
            timing: DistinctLaneTimingV1(
                samples: timingSamplesNanoseconds,
                warmup: workload.warmup
            ),
            environment: environment
        )
    }

    package static func replay(
        workload: DistinctLaneWorkloadV1,
        result: DistinctLaneResultV1
    ) throws -> DistinctLaneReplayReceipt {
        let validated = try validatedWorkload(workload)
        guard result.schemaVersion == 1, result.kind == resultKind else {
            throw DistinctLaneExchangeError.invalid(
                "unsupported result schema/kind: \(result.schemaVersion) / \(result.kind)"
            )
        }
        guard result.workloadID == workload.workloadID else {
            throw DistinctLaneExchangeError.resultWorkload(
                expected: workload.workloadID,
                actual: result.workloadID
            )
        }
        try validateEnvironment(result.environment)
        let outputWidth = workload.outputPorts.reduce(0) { $0 + $1.width }
        try validateRows(
            result.outputRows,
            lanes: workload.lanes,
            width: outputWidth,
            label: "result output"
        )
        guard result.timing.scope == timingScope,
              result.timing.unit == "nanoseconds",
              result.timing.samples.count == workload.trials,
              result.timing.warmup == workload.warmup else {
            throw DistinctLaneExchangeError.invalid("result timing contract does not match workload")
        }

        let actualDigest = digestString(
            records(for: result.outputRows, ports: workload.outputPorts)
        )
        guard result.outputDigest == actualDigest else {
            throw DistinctLaneExchangeError.outputDigest(
                expected: result.outputDigest,
                actual: actualDigest
            )
        }

        let expectedByLane = Dictionary(
            uniqueKeysWithValues: validated.expectedRows.map { ($0.lane, $0.bits) }
        )
        var mismatches = 0
        for row in result.outputRows {
            let expected = expectedByLane[row.lane]!
            mismatches += zip(row.bits, expected).reduce(0) { $0 + ($1.0 == $1.1 ? 0 : 1) }
        }
        let steady = Array(result.timing.samples.dropFirst(workload.warmup)).sorted()
        let median: Double
        if steady.count.isMultiple(of: 2) {
            median = (Double(steady[steady.count / 2 - 1]) + Double(steady[steady.count / 2])) / 2
        } else {
            median = Double(steady[steady.count / 2])
        }
        let average = steady.reduce(0) { $0 + Double($1) } / Double(steady.count)
        return DistinctLaneReplayReceipt(
            workloadID: workload.workloadID,
            lanes: workload.lanes,
            inputBits: workload.inputPorts.reduce(0) { $0 + $1.width },
            distinctInputAssignments: Set(workload.laneInputs.map(\.bits)).count,
            comparedBits: workload.lanes * outputWidth,
            mismatches: mismatches,
            distinctLaneOutputs: Set(result.outputRows.map(\.bits)).count,
            outputDigest: actualDigest,
            firstNanoseconds: result.timing.samples[0],
            steadyMedianNanoseconds: median,
            steadyAverageNanoseconds: average,
            timingValid: mismatches == 0
        )
    }

    /// Used by tests and reference runners; external accelerators should compute
    /// these rows themselves rather than copying the oracle output.
    package static func expectedOutputRows(
        workload: DistinctLaneWorkloadV1
    ) throws -> [DistinctLaneBitsV1] {
        try validatedWorkload(workload).expectedRows
    }

    package static func loadWorkload(from url: URL) throws -> DistinctLaneWorkloadV1 {
        let value = try JSONDecoder().decode(
            DistinctLaneWorkloadV1.self,
            from: Data(contentsOf: url)
        )
        _ = try validatedWorkload(value)
        return value
    }

    package static func loadResult(from url: URL) throws -> DistinctLaneResultV1 {
        try JSONDecoder().decode(DistinctLaneResultV1.self, from: Data(contentsOf: url))
    }

    package static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        if data.last != 0x0A { data.append(0x0A) }
        try data.write(to: url, options: .atomic)
    }

    private struct ValidatedWorkload {
        let module: YosysModule
        let expectedRows: [DistinctLaneBitsV1]
    }

    private static func validatedWorkload(
        _ workload: DistinctLaneWorkloadV1
    ) throws -> ValidatedWorkload {
        guard workload.schemaVersion == 1,
              workload.kind == workloadKind,
              workload.mode == mode,
              workload.assignmentSchema == assignmentSchema,
              workload.encodingSchema == encodingSchema,
              workload.lutSemantics == lutSemantics,
              workload.outputDigestSchema == outputDigestSchema,
              workload.timingScope == timingScope else {
            throw DistinctLaneExchangeError.invalid("unsupported workload schema or semantics")
        }
        guard let netlistData = Data(base64Encoded: workload.yosysJSONBase64) else {
            throw DistinctLaneExchangeError.invalid("workload Yosys JSON is not valid base64")
        }
        let netlistHash = sha256ID(netlistData)
        guard workload.netlistSHA256 == netlistHash else {
            throw DistinctLaneExchangeError.netlistIntegrity(
                expected: workload.netlistSHA256,
                actual: netlistHash
            )
        }
        let yosys = try decodeYosys(netlistData)
        guard let module = yosys.modules[workload.moduleName] else {
            throw DistinctLaneExchangeError.missingModule(workload.moduleName)
        }
        let (inputs, outputs) = try validateModule(
            moduleName: workload.moduleName,
            module: module,
            degree: workload.degree,
            lanes: workload.lanes,
            trials: workload.trials,
            warmup: workload.warmup
        )
        guard inputs == workload.inputPorts, outputs == workload.outputPorts else {
            throw DistinctLaneExchangeError.invalid("workload port descriptors do not match embedded netlist")
        }
        let inputWidth = inputs.reduce(0) { $0 + $1.width }
        try validateRows(
            workload.laneInputs,
            lanes: workload.lanes,
            width: inputWidth,
            label: "workload input"
        )
        let assignmentSpace = UInt64(1) << UInt64(inputWidth)
        let stride = max(UInt64(1), assignmentSpace / UInt64(workload.lanes))
        for row in workload.laneInputs {
            let expected = bitString(mask: UInt64(row.lane) * stride, width: inputWidth)
            guard row.bits == expected else {
                throw DistinctLaneExchangeError.invalid(
                    "lane \(row.lane) input does not match \(assignmentSchema)"
                )
            }
        }
        let expectedRows = try oracleRows(
            moduleName: workload.moduleName,
            module: module,
            inputPorts: inputs,
            outputPorts: outputs,
            laneInputs: workload.laneInputs
        )
        let oracleDigest = digestString(records(for: expectedRows, ports: outputs))
        guard workload.expectedOutputDigest == oracleDigest else {
            throw DistinctLaneExchangeError.invalid(
                "workload expected digest is \(workload.expectedOutputDigest), oracle recomputed \(oracleDigest)"
            )
        }
        let identity = workloadIdentity(workload)
        guard workload.workloadID == identity else {
            throw DistinctLaneExchangeError.workloadIdentity(
                expected: workload.workloadID,
                actual: identity
            )
        }
        return ValidatedWorkload(module: module, expectedRows: expectedRows)
    }

    private static func decodeYosys(_ data: Data) throws -> YosysNetlist {
        do {
            return try JSONDecoder().decode(YosysNetlist.self, from: data)
        } catch {
            throw DistinctLaneExchangeError.invalid("cannot decode embedded Yosys JSON: \(error)")
        }
    }

    private static func selectModule(
        _ yosys: YosysNetlist,
        requested: String?
    ) throws -> (String, YosysModule) {
        if let requested {
            guard let module = yosys.modules[requested] else {
                throw DistinctLaneExchangeError.missingModule(requested)
            }
            return (requested, module)
        }
        let candidates = yosys.modules.filter { _, module in
            module.cells.values.contains { $0.type != "$scopeinfo" }
        }.sorted { $0.key < $1.key }
        guard candidates.count == 1 else {
            throw DistinctLaneExchangeError.ambiguousModules(candidates.map(\.key))
        }
        return candidates[0]
    }

    private static func validateModule(
        moduleName: String,
        module: YosysModule,
        degree: Int,
        lanes: Int,
        trials: Int,
        warmup: Int
    ) throws -> ([DistinctLanePortV1], [DistinctLanePortV1]) {
        guard degree > 0, lanes > 0, trials > warmup, warmup >= 0 else {
            throw DistinctLaneExchangeError.invalid(
                "require degree > 0, lanes > 0, and trials > warmup >= 0"
            )
        }
        let inputs = module.ports.sorted { $0.key < $1.key }.compactMap { name, port in
            port.direction == "input" ? DistinctLanePortV1(name: name, width: port.bits.count) : nil
        }
        let outputs = module.ports.sorted { $0.key < $1.key }.compactMap { name, port in
            port.direction == "output" ? DistinctLanePortV1(name: name, width: port.bits.count) : nil
        }
        let inputWidth = inputs.reduce(0) { $0 + $1.width }
        let outputWidth = outputs.reduce(0) { $0 + $1.width }
        guard (1...62).contains(inputWidth), outputWidth > 0 else {
            throw DistinctLaneExchangeError.invalid(
                "module \(moduleName) requires 1...62 input bits and at least one output bit"
            )
        }
        let assignmentSpace = UInt64(1) << UInt64(inputWidth)
        guard UInt64(lanes) <= assignmentSpace else {
            throw DistinctLaneExchangeError.invalid(
                "requested \(lanes) lanes but only \(assignmentSpace) assignments exist"
            )
        }

        var driven = Set<Int>()
        for (name, port) in module.ports where port.direction == "input" {
            for (bit, value) in port.bits.enumerated() {
                guard case .net(let wire) = value else {
                    throw DistinctLaneExchangeError.invalid("input \(name)[\(bit)] is not a net")
                }
                driven.insert(wire)
            }
        }
        let executable = module.cells.filter { $0.value.type != "$scopeinfo" }
        if executable.values.contains(where: { isYosysDFFType($0.type) }) {
            throw DistinctLaneExchangeError.invalid("sequential cells are outside the v1 workload contract")
        }
        let unsupported = Set(executable.values.map(\.type).filter { $0 != "$lut" })
        guard unsupported.isEmpty else {
            throw DistinctLaneExchangeError.invalid(
                "unsupported cells in v1 workload: \(unsupported.sorted())"
            )
        }

        var cells: [(String, YosysCell, Int)] = []
        var outputDrivers: [Int: String] = [:]
        for (name, cell) in executable.sorted(by: { $0.key < $1.key }) {
            guard let a = cell.connections["A"], a.count <= 6,
                  let y = cell.connections["Y"], y.count == 1,
                  case .net(let output) = y[0],
                  let truth = cell.parameters.LUT,
                  truth.count == (1 << a.count),
                  truth.allSatisfy({ $0 == "0" || $0 == "1" }) else {
                throw DistinctLaneExchangeError.invalid("malformed LUT cell \(name)")
            }
            if let width = cell.parameters.WIDTH,
               Int(width, radix: 2) != a.count {
                throw DistinctLaneExchangeError.invalid("LUT WIDTH mismatch in \(name)")
            }
            if driven.contains(output) || outputDrivers.updateValue(name, forKey: output) != nil {
                throw DistinctLaneExchangeError.invalid("wire \(output) has multiple drivers")
            }
            cells.append((name, cell, output))
        }

        var pending = cells
        while !pending.isEmpty {
            var next: [(String, YosysCell, Int)] = []
            var progressed = false
            for item in pending {
                let inputsReady = item.1.connections["A"]!.allSatisfy { bit in
                    switch bit {
                    case .constant: return true
                    case .net(let wire): return driven.contains(wire)
                    }
                }
                if inputsReady {
                    driven.insert(item.2)
                    progressed = true
                } else {
                    next.append(item)
                }
            }
            guard progressed else {
                throw DistinctLaneExchangeError.invalid("unresolved input or combinational cycle in \(moduleName)")
            }
            pending = next
        }
        for (name, port) in module.ports where port.direction == "output" {
            for (bit, value) in port.bits.enumerated() {
                if case .net(let wire) = value, !driven.contains(wire) {
                    throw DistinctLaneExchangeError.invalid("output \(name)[\(bit)] is undriven")
                }
            }
        }
        return (inputs, outputs)
    }

    private static func oracleRows(
        moduleName: String,
        module: YosysModule,
        inputPorts: [DistinctLanePortV1],
        outputPorts: [DistinctLanePortV1],
        laneInputs: [DistinctLaneBitsV1]
    ) throws -> [DistinctLaneBitsV1] {
        let simulator = CleartextNetlistSimulator(moduleName: moduleName, module: module)
        return try laneInputs.sorted { $0.lane < $1.lane }.map { row in
            var cursor = row.bits.startIndex
            var inputs: [String: [UInt8]] = [:]
            for port in inputPorts {
                inputs[port.name] = (0..<port.width).map { _ in
                    defer { cursor = row.bits.index(after: cursor) }
                    return row.bits[cursor] == "1" ? 1 : 0
                }
            }
            let outputs = simulator.tick(inputs: inputs)
            var bits = ""
            for port in outputPorts {
                guard let values = outputs[port.name], values.count == port.width else {
                    throw DistinctLaneExchangeError.invalid(
                        "oracle omitted or resized output \(port.name)"
                    )
                }
                for value in values { bits.append(value == 0 ? "0" : "1") }
            }
            return DistinctLaneBitsV1(lane: row.lane, bits: bits)
        }
    }

    private static func validateRows(
        _ rows: [DistinctLaneBitsV1],
        lanes: Int,
        width: Int,
        label: String
    ) throws {
        guard rows.count == lanes else {
            throw DistinctLaneExchangeError.invalid(
                "\(label) has \(rows.count) rows; expected \(lanes)"
            )
        }
        let laneIDs = rows.map(\.lane)
        guard Set(laneIDs).count == lanes,
              laneIDs.allSatisfy({ (0..<lanes).contains($0) }) else {
            throw DistinctLaneExchangeError.invalid("\(label) lane IDs are missing, duplicated, or out of range")
        }
        for row in rows where row.bits.count != width
            || !row.bits.allSatisfy({ $0 == "0" || $0 == "1" }) {
            throw DistinctLaneExchangeError.invalid(
                "\(label) lane \(row.lane) must contain exactly \(width) binary characters"
            )
        }
    }

    private static func validateEnvironment(
        _ environment: DistinctLaneEnvironmentV1
    ) throws {
        guard !environment.executionBackend.isEmpty,
              !environment.implementation.isEmpty,
              !environment.deviceName.isEmpty else {
            throw DistinctLaneExchangeError.invalid(
                "result environment requires backend, implementation, and device name"
            )
        }
    }

    private static func records(
        for rows: [DistinctLaneBitsV1],
        ports: [DistinctLanePortV1]
    ) -> [DistinctBatchRecord] {
        var records: [DistinctBatchRecord] = []
        for row in rows.sorted(by: { $0.lane < $1.lane }) {
            var cursor = row.bits.startIndex
            for port in ports {
                for bit in 0..<port.width {
                    let value: UInt32 = row.bits[cursor] == "1" ? 1 : 0
                    records.append(DistinctBatchRecord(
                        lane: row.lane,
                        port: port.name,
                        bit: bit,
                        value: value
                    ))
                    cursor = row.bits.index(after: cursor)
                }
            }
        }
        return records
    }

    private static func bitString(mask: UInt64, width: Int) -> String {
        (0..<width).map { ((mask >> UInt64($0)) & 1) == 0 ? "0" : "1" }.joined()
    }

    private static func digestString(_ records: [DistinctBatchRecord]) -> String {
        String(format: "fnv1a64-%016llx", distinctBatchChecksum(records))
    }

    private static func sha256ID(_ data: Data) -> String {
        "sha256-" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// SHA-256 over a length-prefixed binary transcript, not over JSON key order.
    private static func workloadIdentity(_ workload: DistinctLaneWorkloadV1) -> String {
        var transcript = Data()
        func append(_ value: UInt64) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { transcript.append(contentsOf: $0) }
        }
        func append(_ value: String) {
            let bytes = Data(value.utf8)
            append(UInt64(bytes.count))
            transcript.append(bytes)
        }
        append(UInt64(workload.schemaVersion))
        for value in [
            workload.kind, workload.mode, workload.assignmentSchema,
            workload.encodingSchema, workload.lutSemantics,
            workload.outputDigestSchema, workload.timingScope,
            workload.netlistSHA256, workload.moduleName,
        ] { append(value) }
        for value in [workload.degree, workload.lanes, workload.trials, workload.warmup] {
            append(UInt64(value))
        }
        append(UInt64(workload.inputPorts.count))
        for port in workload.inputPorts { append(port.name); append(UInt64(port.width)) }
        append(UInt64(workload.outputPorts.count))
        for port in workload.outputPorts { append(port.name); append(UInt64(port.width)) }
        append(UInt64(workload.laneInputs.count))
        for row in workload.laneInputs.sorted(by: { $0.lane < $1.lane }) {
            append(UInt64(row.lane)); append(row.bits)
        }
        append(workload.expectedOutputDigest)
        return sha256ID(transcript)
    }
}
