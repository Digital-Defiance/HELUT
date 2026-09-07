import Foundation
import Metal
import XCTest
@testable import HELUTCore
@testable import HELUTToolKit

final class DistinctLaneExchangeTests: XCTestCase {
    private func repoFile(_ name: String) -> String? {
        let manager = FileManager.default
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            url.deleteLastPathComponent()
            let candidate = url.appendingPathComponent(name).path
            if manager.fileExists(atPath: candidate) { return candidate }
        }
        return nil
    }

    private func fixture(lanes: Int = 256) throws -> (DistinctLaneWorkloadV1, Data, String) {
        let path = try XCTUnwrap(
            repoFile("Generated/Netlists/Examples/ripple4_netlist.json"),
            "ripple4 fixture is missing"
        )
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let yosys = try JSONDecoder().decode(YosysNetlist.self, from: data)
        let module = try XCTUnwrap(
            yosys.modules.first(where: { $0.value.cells.values.contains { $0.type == "$lut" } })?.key
        )
        let workload = try DistinctLaneExchange.makeWorkload(
            netlistData: data,
            moduleName: module,
            degree: 1,
            lanes: lanes,
            trials: 3,
            warmup: 1
        )
        return (workload, data, module)
    }

    private var syntheticEnvironment: DistinctLaneEnvironmentV1 {
        DistinctLaneEnvironmentV1(
            executionBackend: "reference-clear",
            implementation: "HELUT exchange test",
            implementationVersion: "1",
            deviceName: "CPU oracle",
            vendor: "test",
            deviceIdentifier: "fixture",
            operatingSystem: "test",
            architecture: "test",
            unifiedMemory: nil,
            lowPower: nil,
            removable: nil
        )
    }

    func testGoldenWorkloadAndCleanReplayAreDeterministic() throws {
        let (workload, data, module) = try fixture()
        XCTAssertEqual(workload.schemaVersion, 1)
        XCTAssertEqual(workload.kind, DistinctLaneExchange.workloadKind)
        XCTAssertEqual(workload.moduleName, module)
        XCTAssertEqual(workload.netlistSHA256.count, 71) // "sha256-" + 64 hex digits
        XCTAssertEqual(workload.inputPorts.reduce(0) { $0 + $1.width }, 8)
        XCTAssertEqual(workload.outputPorts.reduce(0) { $0 + $1.width }, 5)
        XCTAssertEqual(workload.laneInputs.count, 256)
        XCTAssertEqual(workload.laneInputs[0].bits, "00000000")
        XCTAssertEqual(workload.laneInputs[1].bits, "10000000")
        XCTAssertEqual(workload.laneInputs[255].bits, "11111111")
        XCTAssertEqual(
            workload.expectedOutputDigest,
            "fnv1a64-316ae77a78a0150d",
            "the exchange contract drifted from the shipped B=256 distinct-lane receipt"
        )

        let repeated = try DistinctLaneExchange.makeWorkload(
            netlistData: data,
            moduleName: module,
            degree: 1,
            lanes: 256,
            trials: 3,
            warmup: 1
        )
        XCTAssertEqual(repeated, workload)

        let expectedRows = try DistinctLaneExchange.expectedOutputRows(workload: workload)
        let result = try DistinctLaneExchange.makeResult(
            workload: workload,
            outputRows: expectedRows,
            timingSamplesNanoseconds: [11, 7, 9],
            environment: syntheticEnvironment
        )
        let receipt = try DistinctLaneExchange.replay(workload: workload, result: result)
        XCTAssertEqual(receipt.lanes, 256)
        XCTAssertEqual(receipt.distinctInputAssignments, 256)
        XCTAssertEqual(receipt.comparedBits, 1_280)
        XCTAssertEqual(receipt.mismatches, 0)
        XCTAssertEqual(receipt.distinctLaneOutputs, 31)
        XCTAssertEqual(receipt.outputDigest, workload.expectedOutputDigest)
        XCTAssertEqual(receipt.firstNanoseconds, 11)
        XCTAssertEqual(receipt.steadyMedianNanoseconds, 8)
        XCTAssertEqual(receipt.steadyAverageNanoseconds, 8)
        XCTAssertTrue(receipt.timingValid)

        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("helut-distinct-exchange-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let workloadURL = directory.appendingPathComponent("workload.json")
        let resultURL = directory.appendingPathComponent("result.json")
        try DistinctLaneExchange.write(workload, to: workloadURL)
        try DistinctLaneExchange.write(result, to: resultURL)
        XCTAssertEqual(try DistinctLaneExchange.loadWorkload(from: workloadURL), workload)
        XCTAssertEqual(try DistinctLaneExchange.loadResult(from: resultURL), result)
        XCTAssertEqual(try Data(contentsOf: workloadURL).last, 0x0A)
        XCTAssertEqual(try Data(contentsOf: resultURL).last, 0x0A)
    }

    func testReplayDetectsOneBitCorruptionAndRejectsStaleDigest() throws {
        let (workload, _, _) = try fixture(lanes: 64)
        let cleanRows = try DistinctLaneExchange.expectedOutputRows(workload: workload)
        let clean = try DistinctLaneExchange.makeResult(
            workload: workload,
            outputRows: cleanRows,
            timingSamplesNanoseconds: [100, 80, 90],
            environment: syntheticEnvironment
        )

        var corruptRows = cleanRows
        let index = try XCTUnwrap(corruptRows.firstIndex(where: { $0.lane == 37 }))
        var characters = Array(corruptRows[index].bits)
        characters[0] = characters[0] == "0" ? "1" : "0"
        corruptRows[index].bits = String(characters)
        let corrupt = try DistinctLaneExchange.makeResult(
            workload: workload,
            outputRows: corruptRows,
            timingSamplesNanoseconds: [100, 80, 90],
            environment: syntheticEnvironment
        )
        let receipt = try DistinctLaneExchange.replay(workload: workload, result: corrupt)
        XCTAssertEqual(receipt.mismatches, 1)
        XCTAssertFalse(receipt.timingValid)
        XCTAssertNotEqual(corrupt.outputDigest, clean.outputDigest)

        var staleDigest = corrupt
        staleDigest.outputDigest = clean.outputDigest
        XCTAssertThrowsError(
            try DistinctLaneExchange.replay(workload: workload, result: staleDigest)
        ) { error in
            guard case DistinctLaneExchangeError.outputDigest = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testTamperedWorkloadAndMalformedResultsFailClosed() throws {
        let (workload, _, _) = try fixture(lanes: 16)
        let rows = try DistinctLaneExchange.expectedOutputRows(workload: workload)
        let result = try DistinctLaneExchange.makeResult(
            workload: workload,
            outputRows: rows,
            timingSamplesNanoseconds: [5, 4, 3],
            environment: syntheticEnvironment
        )

        var tampered = workload
        tampered.yosysJSONBase64.append("A")
        XCTAssertThrowsError(try DistinctLaneExchange.expectedOutputRows(workload: tampered))

        var wrongWorkload = result
        wrongWorkload.workloadID = "sha256-wrong"
        XCTAssertThrowsError(
            try DistinctLaneExchange.replay(workload: workload, result: wrongWorkload)
        ) { error in
            guard case DistinctLaneExchangeError.resultWorkload = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }

        var missingLane = result
        missingLane.outputRows.removeLast()
        XCTAssertThrowsError(
            try DistinctLaneExchange.replay(workload: workload, result: missingLane)
        )

        var nonBinary = result
        nonBinary.outputRows[0].bits.replaceSubrange(
            nonBinary.outputRows[0].bits.startIndex...nonBinary.outputRows[0].bits.startIndex,
            with: "x"
        )
        XCTAssertThrowsError(
            try DistinctLaneExchange.replay(workload: workload, result: nonBinary)
        )
    }

    func testShippedCLIExportsMetalResultAndReplaysWithoutMetalExecution() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal device not available")
        }
        let executable = try XCTUnwrap(
            repoFile(".build/release/helut-bench"),
            "release helut-bench executable is missing"
        )
        let netlist = try XCTUnwrap(
            repoFile("Generated/Netlists/Examples/ripple4_netlist.json"),
            "ripple4 fixture is missing"
        )
        let data = try Data(contentsOf: URL(fileURLWithPath: netlist))
        let yosys = try JSONDecoder().decode(YosysNetlist.self, from: data)
        let module = try XCTUnwrap(
            yosys.modules.first(where: { $0.value.cells.values.contains { $0.type == "$lut" } })?.key
        )

        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("helut-distinct-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let workload = directory.appendingPathComponent("workload.json")
        let result = directory.appendingPathComponent("result.json")

        let runOutput = try runProcess(
            executable,
            [
                "--bench", netlist,
                "--bench-module", module,
                "--degree", "1",
                "--batch", "64",
                "--ticks", "3",
                "--warmup", "1",
                "--bench-distinct-lanes",
                "--bench-distinct-export-workload", workload.path,
                "--bench-distinct-result-out", result.path,
            ]
        )
        XCTAssertEqual(runOutput.status, 0, runOutput.output)
        XCTAssertTrue(runOutput.output.contains("BATCH_LANE_WORKLOAD result=PASS"))
        XCTAssertTrue(runOutput.output.contains("BATCH_LANE_RESULT"))
        XCTAssertTrue(runOutput.output.contains("replay=PASS"))

        let replayOutput = try runProcess(
            executable,
            [
                "--bench",
                "--bench-distinct-replay-workload", workload.path,
                "--bench-distinct-replay-result", result.path,
            ]
        )
        XCTAssertEqual(replayOutput.status, 0, replayOutput.output)
        XCTAssertTrue(replayOutput.output.contains("BATCH_LANE_REPLAY result=PASS"))
        XCTAssertTrue(replayOutput.output.contains("mismatches=0"))

        let decodedWorkload = try DistinctLaneExchange.loadWorkload(from: workload)
        let decodedResult = try DistinctLaneExchange.loadResult(from: result)
        let receipt = try DistinctLaneExchange.replay(
            workload: decodedWorkload,
            result: decodedResult
        )
        XCTAssertEqual(receipt.comparedBits, 320)
        XCTAssertEqual(receipt.mismatches, 0)
        XCTAssertEqual(decodedResult.environment.executionBackend, "metal-mpsgraph")
        XCTAssertEqual(decodedResult.environment.unifiedMemory, true)
    }

    private func runProcess(
        _ executable: String,
        _ arguments: [String]
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
