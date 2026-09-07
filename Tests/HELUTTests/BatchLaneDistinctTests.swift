import Metal
import XCTest
@testable import HELUTCore
@testable import HELUTToolKit

/// Do the batch lanes actually do different work?
///
/// Legacy `--bench --batch …` remains a broadcast on purpose so archived logs
/// keep their original meaning. The opt-in shipped
/// `--bench-distinct-lanes` mode uses the production helper exercised here:
///
///   1. every lane carries a unique deterministic stimulus
///   2. every lane's output is read back and checked against its own oracle run
///   3. a canonical checksum covers ordered per-lane results
///   4. one deliberately corrupted output record must break that checksum
///
/// Point 4 is the one that matters. A checksum nothing can falsify is decoration.
final class BatchLaneDistinctTests: XCTestCase {

    private func repoFile(_ name: String) -> String? {
        let fm = FileManager.default
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            url.deleteLastPathComponent()
            let candidate = url.appendingPathComponent(name).path
            if fm.fileExists(atPath: candidate) { return candidate }
        }
        return nil
    }

    private struct LaneRun {
        let lanes: Int
        let inputBits: Int
        let mismatches: Int
        let comparedBits: Int
        let distinctLaneOutputs: Int
        let digest: UInt64
        let wallSeconds: Double
    }

    /// Drives independent assignments through the same production helper used by
    /// `helut-bench --bench-distinct-lanes`, then adapts its receipt to the
    /// historical test-local shape.
    private func runDistinctLanes(
        netlistPath: String,
        lanes requested: Int,
        degree: Int,
        device: MTLDevice,
        queue: MTLCommandQueue,
        corruptExpectationForLane: Int? = nil
    ) throws -> LaneRun {
        let yosys = loadYosysNetlist(from: netlistPath)
        guard let (moduleName, module) = yosys.modules.first(where: { !$0.value.cells.isEmpty })
            .map({ ($0.key, $0.value) })
        else {
            throw XCTSkip("no module with cells in \(netlistPath)")
        }
        let compiler = try XCTUnwrap(
            YosysGraphCompiler(
                degree: degree,
                batch: requested,
                encodingKind: .constantFill,
                lutBackend: .multilinear
            ),
            "could not construct a batch-\(requested) compiler"
        )
        compiler.compile(moduleName: moduleName, module: module)
        let receipt = try runDistinctCombinationalBatch(
            compiler: compiler,
            moduleName: moduleName,
            module: module,
            device: device,
            commandQueue: queue,
            trials: 1,
            warmup: 0,
            corruptFirstOutputInLane: corruptExpectationForLane
        )
        return LaneRun(
            lanes: receipt.lanes,
            inputBits: receipt.inputBits,
            mismatches: receipt.mismatches,
            comparedBits: receipt.comparedBits,
            distinctLaneOutputs: receipt.distinctLaneOutputs,
            digest: receipt.digest,
            wallSeconds: receipt.graphFirstSeconds
        )
    }

    /// Every lane independent, every lane verified, and the lanes must genuinely
    /// disagree with each other — otherwise "distinct" would be unfalsifiable too.
    func testEveryBatchLaneDoesIndependentVerifiedWork() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device not available")
        }
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let path = try XCTUnwrap(
            repoFile("Generated/Netlists/Examples/ripple4_netlist.json")
                ?? repoFile("Generated/Netlists/Examples/csa4_netlist.json")
                ?? repoFile("Generated/Netlists/Examples/netlist.json"),
            "no combinational example netlist found"
        )

        var runs: [LaneRun] = []
        for lanes in [1, 16, 64, 256] {
            let run = try runDistinctLanes(
                netlistPath: path, lanes: lanes, degree: 1, device: device, queue: queue
            )
            runs.append(run)
            print(
                "BATCH_LANES lanes=\(run.lanes) input_bits=\(run.inputBits) "
                    + "checked=\(run.comparedBits) mismatches=\(run.mismatches) "
                    + "distinct_lane_outputs=\(run.distinctLaneOutputs) "
                    + "digest=\(String(run.digest, radix: 16)) "
                    + "wall=\(String(format: "%.4f", run.wallSeconds))s"
            )
            XCTAssertEqual(
                run.mismatches, 0,
                """
                \(run.mismatches) of \(run.comparedBits) lane output bits disagreed \
                with their own oracle evaluation at batch \(run.lanes).
                """
            )
        }

        let widest = try XCTUnwrap(runs.last)
        XCTAssertGreaterThan(
            widest.distinctLaneOutputs, 1,
            """
            all \(widest.lanes) lanes produced identical output signatures, so the \
            stimulus was not actually lane-distinct and this test would pass for a \
            broadcast.
            """
        )
        print(
            "BATCH_LANES verified: \(widest.lanes) lanes, \(widest.comparedBits) output "
                + "bits each checked against its own oracle run, "
                + "\(widest.distinctLaneOutputs) distinct lane output signatures"
        )
    }

    /// The checksum must be falsifiable. One flipped bit in one lane has to change
    /// the digest and surface as a mismatch.
    func testPerLaneChecksumDetectsASingleCorruptedLane() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device not available")
        }
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let path = try XCTUnwrap(
            repoFile("Generated/Netlists/Examples/ripple4_netlist.json")
                ?? repoFile("Generated/Netlists/Examples/csa4_netlist.json")
                ?? repoFile("Generated/Netlists/Examples/netlist.json"),
            "no combinational example netlist found"
        )

        let clean = try runDistinctLanes(
            netlistPath: path, lanes: 64, degree: 1, device: device, queue: queue
        )
        let corrupted = try runDistinctLanes(
            netlistPath: path, lanes: 64, degree: 1, device: device, queue: queue,
            corruptExpectationForLane: 37
        )

        XCTAssertEqual(clean.mismatches, 0, "clean run should agree everywhere")
        XCTAssertEqual(
            corrupted.mismatches, 1,
            "the injected one-record fault must produce exactly one mismatch"
        )
        XCTAssertNotEqual(
            clean.digest, corrupted.digest,
            """
            flipping one output bit in lane 37 left the digest unchanged, so the \
            checksum cannot detect per-lane corruption and the clean digest is \
            meaningless.
            """
        )
        print(
            "BATCH_LANES negative control: lane 37 corruption produced "
                + "\(corrupted.mismatches) mismatch(es); digest "
                + "\(String(clean.digest, radix: 16)) → \(String(corrupted.digest, radix: 16))"
        )
    }

    /// The library helper passing is not enough: exercise the release executable's
    /// actual argv dispatch and require its machine-readable receipt.
    func testShippedBenchCLIExposesVerifiedDistinctMode() throws {
        let executable = try XCTUnwrap(
            repoFile(".build/release/helut-bench"),
            "release helut-bench executable is missing"
        )
        let netlist = try XCTUnwrap(
            repoFile("Generated/Netlists/Examples/ripple4_netlist.json"),
            "ripple4 fixture is missing"
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = [
            "--bench", netlist,
            "--degree", "1",
            "--batch", "256",
            "--ticks", "3",
            "--warmup", "1",
            "--bench-distinct-lanes"
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)

        XCTAssertEqual(
            process.terminationStatus, 0,
            "shipped distinct-lane CLI failed:\n\(output.suffix(4000))"
        )
        XCTAssertTrue(output.contains("batch mode: distinct-verified-v1"))
        XCTAssertTrue(output.contains("lanes=256"))
        XCTAssertTrue(output.contains("distinct_inputs=256"))
        XCTAssertTrue(output.contains("checked=1280 mismatches=0"))
        XCTAssertTrue(output.contains("digest_schema=fnv1a64-lane-port-bit-v1"))
        XCTAssertTrue(output.contains("timing_valid=true"))
        XCTAssertTrue(output.contains("BATCH_LANES result=PASS"))
        print(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
