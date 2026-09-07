import Metal
import MetalPerformanceShadersGraph
import XCTest
@testable import HELUTCore

/// Compares HELUT with native HDL execution on one generated circuit and stimulus.
///
/// The historical row is preserved: warmed synchronized `MPSGraph.run` wall time
/// versus a self-timed scalar Verilator loop that assigns inputs, evaluates the
/// model, reads outputs, and hashes them. That row remains intentionally asymmetric.
///
/// The paired row adds a closer end-to-end scope on both sides. One-time parsing,
/// compilation, allocation, model/thread creation, and cold specialization remain
/// excluded. Every timed trial includes deterministic input preparation through an
/// ordered FNV digest. Parallel native execution uses one Verilated context/model per
/// persistent worker and deterministic contiguous lane partitions; output reduction
/// remains serial and canonical. Every digest must match before a timing is retained.
final class NativeBaselineComparisonTests: XCTestCase {

    // MARK: - Shared circuit

    private struct Layout {
        let bits: Int
        func aWire(_ i: Int) -> Int32 { Int32(i) }
        func bWire(_ i: Int) -> Int32 { Int32(bits + i) }
        func cWire(_ i: Int) -> Int32 { Int32(2 * bits + i) }
        func sWire(_ i: Int) -> Int32 { Int32(3 * bits + i) }
        var totalWires: Int { 4 * bits }
        var inputWires: [Int32] { (0..<(2 * bits)).map(Int32.init) }
        var outputWires: [Int32] { (0..<bits).map { sWire($0) } + [cWire(bits - 1)] }
    }

    private func truthTable(inputCount: Int, _ f: ([Int]) -> Int) -> String {
        var out = ""
        for address in stride(from: (1 << inputCount) - 1, through: 0, by: -1) {
            out.append(f((0..<inputCount).map { (address >> $0) & 1 }) == 0 ? "0" : "1")
        }
        return out
    }

    private func makeRippleAdder(bits: Int) -> (TensorLUTNetlist, Layout) {
        let layout = Layout(bits: bits)
        var luts: [TensorLUT6Cell] = []
        var levels: [[Int32]] = []
        let xor2 = truthTable(inputCount: 2) { $0[0] ^ $0[1] }
        let and2 = truthTable(inputCount: 2) { $0[0] & $0[1] }
        let xor3 = truthTable(inputCount: 3) { $0[0] ^ $0[1] ^ $0[2] }
        let maj3 = truthTable(inputCount: 3) { ($0[0] + $0[1] + $0[2]) >= 2 ? 1 : 0 }

        for i in 0..<bits {
            let sumID = luts.count
            let carryID = luts.count + 1
            if i == 0 {
                luts.append(TensorLUT6Cell(
                    cellID: sumID,
                    inputWires: [layout.aWire(0), layout.bWire(0)],
                    outputWire: layout.sWire(0),
                    rawTruthTable: xor2
                ))
                luts.append(TensorLUT6Cell(
                    cellID: carryID,
                    inputWires: [layout.aWire(0), layout.bWire(0)],
                    outputWire: layout.cWire(0),
                    rawTruthTable: and2
                ))
            } else {
                let pins = [layout.aWire(i), layout.bWire(i), layout.cWire(i - 1)]
                luts.append(TensorLUT6Cell(
                    cellID: sumID,
                    inputWires: pins,
                    outputWire: layout.sWire(i),
                    rawTruthTable: xor3
                ))
                luts.append(TensorLUT6Cell(
                    cellID: carryID,
                    inputWires: pins,
                    outputWire: layout.cWire(i),
                    rawTruthTable: maj3
                ))
            }
            levels.append([Int32(sumID), Int32(carryID)])
        }
        return (
            TensorLUTNetlist(
                luts: luts,
                dffs: [],
                totalWires: layout.totalWires,
                executionLevels: levels
            ),
            layout
        )
    }

    private static let lut6Model = """
    module LUT6 (output O, input I0, I1, I2, I3, I4, I5);
        parameter [63:0] INIT = 64'h0000000000000000;
        wire [5:0] addr = {I5, I4, I3, I2, I1, I0};
        assign O = INIT[addr];
    endmodule
    """

    // MARK: - Canonical digest

    /// FNV-1a over `(lane, wire, value)` triples in numeric wire order.
    ///
    /// `values` is lane-major flat storage: `values[lane * wires.count + index]`.
    /// The hashed byte stream is unchanged from the nested-array version, so the
    /// digest value is identical and remains comparable to the native side and
    /// to banked receipts.
    private func digest(lanes: Int, wires: [Int32], values: [UInt32]) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        func mix(_ value: UInt32) {
            withUnsafeBytes(of: value.littleEndian) { bytes in
                for byte in bytes {
                    hash ^= UInt64(byte)
                    hash = hash &* 0x100_0000_01b3
                }
            }
        }
        let wireCount = wires.count
        for lane in 0..<lanes {
            let base = lane * wireCount
            for (index, wire) in wires.enumerated() {
                mix(UInt32(lane))
                mix(UInt32(bitPattern: wire))
                mix(values[base + index])
            }
        }
        return hash
    }

    /// Lane `l` gets assignment `l * stride`, so lanes differ in high bits too.
    private func assignment(lane: Int, lanes: Int, inputBits: Int) -> Int {
        let space = 1 << inputBits
        let stride = max(1, space / max(lanes, 1))
        return (lane * stride) % space
    }

    private func median(_ values: [Double]) -> Double {
        let ordered = values.sorted()
        return ordered[ordered.count / 2]
    }

    private func nanosecondSamples(_ values: [Double]) -> String {
        values.map { String(Int64(($0 * 1_000_000_000).rounded())) }.joined(separator: ",")
    }

    // MARK: - Tooling

    private func toolPath(_ names: [String]) -> String? {
        for candidate in names where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return nil
    }

    @discardableResult
    private func run(
        _ launch: String,
        _ args: [String],
        cwd: URL,
        env: [String: String]? = nil
    ) throws -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launch)
        process.arguments = args
        process.currentDirectoryURL = cwd
        if let env {
            process.environment = ProcessInfo.processInfo.environment.merging(env) { _, new in new }
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    // MARK: - Verilator side

    /// Emits both the historical scalar loop and the additive persistent-worker
    /// baseline. Timing stays inside C++ so process startup is excluded.
    private func testbenchSource(layout: Layout, top: String) -> String {
        let scalarInputAssignments = layout.inputWires.enumerated().map { index, wire in
            "        top->in_\(wire) = (assignment >> \(index)) & 1;"
        }.joined(separator: "\n")
        let workerInputAssignments = (["        top->clk = 0;"] +
            layout.inputWires.enumerated().map { index, wire in
                "        top->in_\(wire) = (assignment >> \(index)) & 1;"
            }).joined(separator: "\n")
        let scalarOutputReads = layout.outputWires.map { wire in
            "            mix(&hash, (uint32_t)lane); "
                + "mix(&hash, (uint32_t)\(wire)); "
                + "mix(&hash, (uint32_t)top->out_\(wire));"
        }.joined(separator: "\n")
        let workerOutputStores = layout.outputWires.enumerated().map { index, wire in
            "        outputs_[(size_t)lane * kOutputCount + \(index)] = "
                + "(uint32_t)top->out_\(wire);"
        }.joined(separator: "\n")
        let orderedOutputDigest = layout.outputWires.enumerated().map { index, wire in
            "            mix(&hash, (uint32_t)lane); "
                + "mix(&hash, (uint32_t)\(wire)); "
                + "mix(&hash, outputs[(size_t)lane * kOutputCount + \(index)]);"
        }.joined(separator: "\n")

        return """
        #include "V\(top).h"
        #include "verilated.h"
        #include <algorithm>
        #include <chrono>
        #include <condition_variable>
        #include <cstdint>
        #include <cstdio>
        #include <cstdlib>
        #include <memory>
        #include <mutex>
        #include <thread>
        #include <vector>

        static constexpr int kOutputCount = \(layout.outputWires.count);

        static inline void mix(uint64_t* h, uint32_t v) {
            uint8_t b[4] = {
                (uint8_t)(v & 0xff), (uint8_t)((v >> 8) & 0xff),
                (uint8_t)((v >> 16) & 0xff), (uint8_t)((v >> 24) & 0xff)
            };
            for (int i = 0; i < 4; i++) { *h ^= b[i]; *h *= 0x100000001b3ULL; }
        }

        static double medianSeconds(std::vector<int64_t> samples) {
            std::sort(samples.begin(), samples.end());
            return (double)samples[samples.size() / 2] / 1e9;
        }

        static void printSamples(const std::vector<int64_t>& samples) {
            for (size_t i = 0; i < samples.size(); i++) {
                printf("%s%lld", i == 0 ? "" : ",", (long long)samples[i]);
            }
        }

        static uint64_t digestOutputs(int lanes, const std::vector<uint32_t>& outputs) {
            uint64_t hash = 0xcbf29ce484222325ULL;
            for (int lane = 0; lane < lanes; lane++) {
        \(orderedOutputDigest)
            }
            return hash;
        }

        class WorkerPool {
        public:
            WorkerPool(
                int argc,
                char** argv,
                int lanes,
                int workerCount,
                const std::vector<uint64_t>& assignments,
                std::vector<uint32_t>& outputs
            ) : lanes_(lanes), workerCount_(workerCount),
                assignments_(assignments), outputs_(outputs) {
                workers_.reserve((size_t)workerCount_);
                for (int i = 0; i < workerCount_; i++) {
                    auto worker = std::make_unique<Worker>();
                    worker->context = std::make_unique<VerilatedContext>();
                    worker->context->commandArgs(argc, argv);
                    worker->top = std::make_unique<V\(top)>(worker->context.get(), "worker");
                    workers_.push_back(std::move(worker));
                }
                for (int i = 0; i < workerCount_; i++) {
                    workers_[(size_t)i]->thread = std::thread([this, i] { workerLoop(i); });
                }
            }

            ~WorkerPool() {
                {
                    std::lock_guard<std::mutex> lock(mutex_);
                    stopping_ = true;
                    epoch_++;
                }
                startCondition_.notify_all();
                for (auto& worker : workers_) {
                    if (worker->thread.joinable()) worker->thread.join();
                    worker->top->final();
                }
            }

            void run() {
                std::unique_lock<std::mutex> lock(mutex_);
                completed_ = 0;
                epoch_++;
                startCondition_.notify_all();
                doneCondition_.wait(lock, [this] { return completed_ == workerCount_; });
            }

        private:
            struct Worker {
                std::unique_ptr<VerilatedContext> context;
                std::unique_ptr<V\(top)> top;
                std::thread thread;
            };

            void workerLoop(int workerIndex) {
                uint64_t observedEpoch = 0;
                while (true) {
                    std::unique_lock<std::mutex> lock(mutex_);
                    startCondition_.wait(lock, [this, observedEpoch] {
                        return stopping_ || epoch_ != observedEpoch;
                    });
                    if (stopping_) return;
                    observedEpoch = epoch_;
                    lock.unlock();

                    V\(top)* top = workers_[(size_t)workerIndex]->top.get();
                    int begin = (lanes_ * workerIndex) / workerCount_;
                    int end = (lanes_ * (workerIndex + 1)) / workerCount_;
                    for (int lane = begin; lane < end; lane++) {
                        uint64_t assignment = assignments_[(size_t)lane];
        \(workerInputAssignments)
                        top->eval();
        \(workerOutputStores)
                    }

                    lock.lock();
                    completed_++;
                    if (completed_ == workerCount_) doneCondition_.notify_one();
                }
            }

            int lanes_;
            int workerCount_;
            const std::vector<uint64_t>& assignments_;
            std::vector<uint32_t>& outputs_;
            std::vector<std::unique_ptr<Worker>> workers_;
            std::mutex mutex_;
            std::condition_variable startCondition_;
            std::condition_variable doneCondition_;
            uint64_t epoch_ = 0;
            int completed_ = 0;
            bool stopping_ = false;
        };

        int main(int argc, char** argv) {
            if (argc < 4) {
                printf("usage: sim lanes trials workers\\n");
                return 64;
            }
            Verilated::commandArgs(argc, argv);
            int lanes = atoi(argv[1]);
            int trials = atoi(argv[2]);
            int requestedWorkers = atoi(argv[3]);
            if (lanes < 1 || trials < 1 || requestedWorkers < 1) return 64;

            int inputBits = \(2 * layout.bits);
            uint64_t space = 1ULL << inputBits;
            uint64_t stride = space / (uint64_t)lanes;
            if (stride < 1) stride = 1;

            // Historical scalar baseline: preserve the old timing boundary.
            V\(top)* top = new V\(top);
            uint64_t scalarReference = 0;
            std::vector<int64_t> scalarTimes;
            for (int trial = 0; trial < trials + 1; trial++) {
                uint64_t hash = 0xcbf29ce484222325ULL;
                auto started = std::chrono::steady_clock::now();
                for (int lane = 0; lane < lanes; lane++) {
                    uint64_t assignment = ((uint64_t)lane * stride) % space;
        \(scalarInputAssignments)
                    top->eval();
        \(scalarOutputReads)
                }
                auto elapsed = std::chrono::duration_cast<std::chrono::nanoseconds>(
                    std::chrono::steady_clock::now() - started
                ).count();
                if (trial == 0) {
                    scalarReference = hash;
                } else {
                    scalarTimes.push_back(elapsed);
                    if (hash != scalarReference) {
                        printf("VERILATOR_DIGEST_UNSTABLE\\n");
                        return 2;
                    }
                }
            }
            top->final();
            delete top;

            auto scalarBounds = std::minmax_element(scalarTimes.begin(), scalarTimes.end());
            printf(
                "VERILATOR digest=%llx median_s=%.9f min_s=%.9f max_s=%.9f lanes=%d\\n",
                (unsigned long long)scalarReference,
                medianSeconds(scalarTimes),
                (double)*scalarBounds.first / 1e9,
                (double)*scalarBounds.second / 1e9,
                lanes
            );
            printf("VERILATOR_SCALAR_SAMPLES lanes=%d e2e_ns=", lanes);
            printSamples(scalarTimes);
            printf("\\n");

            // Additive parallel baseline. Models and threads are created before
            // the warm-up and remain alive across every measured pass.
            int workerCount = std::min(requestedWorkers, lanes);
            std::vector<uint64_t> assignments((size_t)lanes, 0);
            std::vector<uint32_t> outputs((size_t)lanes * kOutputCount, 0);
            WorkerPool pool(argc, argv, lanes, workerCount, assignments, outputs);
            uint64_t parallelReference = 0;
            std::vector<int64_t> preparedTimes;
            std::vector<int64_t> endToEndTimes;

            for (int trial = 0; trial < trials + 1; trial++) {
                auto endToEndStarted = std::chrono::steady_clock::now();
                for (int lane = 0; lane < lanes; lane++) {
                    assignments[(size_t)lane] = ((uint64_t)lane * stride) % space;
                }
                auto preparedStarted = std::chrono::steady_clock::now();
                pool.run();
                auto preparedElapsed = std::chrono::duration_cast<std::chrono::nanoseconds>(
                    std::chrono::steady_clock::now() - preparedStarted
                ).count();
                uint64_t hash = digestOutputs(lanes, outputs);
                auto endToEndElapsed = std::chrono::duration_cast<std::chrono::nanoseconds>(
                    std::chrono::steady_clock::now() - endToEndStarted
                ).count();

                if (trial == 0) {
                    parallelReference = hash;
                } else {
                    preparedTimes.push_back(preparedElapsed);
                    endToEndTimes.push_back(endToEndElapsed);
                    if (hash != parallelReference) {
                        printf("VERILATOR_PARALLEL_DIGEST_UNSTABLE\\n");
                        return 2;
                    }
                }
            }
            if (parallelReference != scalarReference) {
                printf("VERILATOR_PARALLEL_MISMATCH scalar=%llx parallel=%llx\\n",
                       (unsigned long long)scalarReference,
                       (unsigned long long)parallelReference);
                return 3;
            }

            printf(
                "VERILATOR_PAIRED digest=%llx prepared_median_s=%.9f "
                "e2e_median_s=%.9f workers=%d requested_workers=%d lanes=%d\\n",
                (unsigned long long)parallelReference,
                medianSeconds(preparedTimes),
                medianSeconds(endToEndTimes),
                workerCount,
                requestedWorkers,
                lanes
            );
            printf("VERILATOR_PAIRED_SAMPLES lanes=%d prepared_ns=", lanes);
            printSamples(preparedTimes);
            printf(" e2e_ns=");
            printSamples(endToEndTimes);
            printf("\\n");
            return 0;
        }
        """
    }

    // MARK: - Comparison

    func testHelutVersusVerilatorOnTheSameCircuit() throws {
        guard let yosys = toolPath([
            "/opt/homebrew/bin/yosys", "/usr/local/bin/yosys", "/usr/bin/yosys"
        ]) else { throw XCTSkip("yosys not found — see REPRODUCE.md") }
        guard let verilator = toolPath([
            "/opt/homebrew/bin/verilator", "/usr/local/bin/verilator", "/usr/bin/verilator"
        ]) else {
            throw XCTSkip("verilator not found — install it (brew install verilator)")
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device not available")
        }
        let queue = try XCTUnwrap(device.makeCommandQueue())

        let bits = 8
        let inputBits = 2 * bits
        let (netlist, layout) = makeRippleAdder(bits: bits)
        let top = "ripple_adder"
        let trials = 5
        let environment = ProcessInfo.processInfo.environment
        let configuredWorkers = environment["HELUT_NATIVE_BASELINE_WORKERS"].flatMap(Int.init)
        let requestedWorkers = max(
            1,
            configuredWorkers ?? ProcessInfo.processInfo.activeProcessorCount
        )
        let lanePoints = [1, 16, 256, 1024, 4096, 16384, 32768, 65536]

        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("helut-native-baseline-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let preserveArtifact = environment["HELUT_PRESERVE_NATIVE_BASELINE_ARTIFACT"] == "1"
        defer {
            if !preserveArtifact { try? FileManager.default.removeItem(at: directory) }
        }
        if preserveArtifact {
            print("NATIVE_BASELINE artifact_dir=\(directory.path)")
        }

        // One emitted source artifact feeds both lineages.
        let verilog = TensorLUTEmitter.emitVerilog(
            moduleName: top,
            netlist: netlist,
            chromosome: TensorChromosome.from(netlist: netlist),
            inputWires: layout.inputWires,
            outputWires: layout.outputWires
        )
        try verilog.write(
            to: directory.appendingPathComponent("emitted.v"),
            atomically: true,
            encoding: .utf8
        )
        try Self.lut6Model.write(
            to: directory.appendingPathComponent("lut6.v"),
            atomically: true,
            encoding: .utf8
        )
        try testbenchSource(layout: layout, top: top).write(
            to: directory.appendingPathComponent("tb.cpp"),
            atomically: true,
            encoding: .utf8
        )
        try """
        read_verilog lut6.v
        read_verilog emitted.v
        hierarchy -top \(top)
        proc
        flatten
        opt
        techmap
        opt
        abc -lut 6
        opt_clean
        write_json resynth.json
        """.write(
            to: directory.appendingPathComponent("flow.ys"),
            atomically: true,
            encoding: .utf8
        )

        let (synthStatus, synthLog) = try run(yosys, ["-q", "flow.ys"], cwd: directory)
        XCTAssertEqual(synthStatus, 0, "yosys failed:\n\(synthLog.suffix(1500))")

        let buildStarted = Date()
        let (verilatorStatus, verilatorLog) = try run(verilator, [
            "--cc", "--exe", "--build", "-j", "0",
            "-O3", "-CFLAGS", "-O3 -pthread", "-LDFLAGS", "-pthread",
            "-Wno-fatal",
            "--top-module", top,
            "-o", "sim",
            "emitted.v", "lut6.v", "tb.cpp"
        ], cwd: directory)
        let buildSeconds = Date().timeIntervalSince(buildStarted)
        guard verilatorStatus == 0 else {
            return XCTFail("verilator build failed:\n\(verilatorLog.suffix(3000))")
        }
        let simulatorPath = directory.appendingPathComponent("obj_dir/sim").path
        guard FileManager.default.isExecutableFile(atPath: simulatorPath) else {
            return XCTFail(
                "verilator produced no sim binary. Log:\n\(verilatorLog.suffix(1500))"
            )
        }
        print(
            "NATIVE_BASELINE verilator build (excluded from timings): "
                + "\(String(format: "%.2f", buildSeconds))s"
        )

        let reloaded = loadYosysNetlist(
            from: directory.appendingPathComponent("resynth.json").path
        )
        guard let module = reloaded.modules[top] else {
            return XCTFail("module \(top) missing from resynth.json")
        }
        let resynthLUTs = module.cells.values.filter { $0.type == "$lut" }.count
        print(
            "NATIVE_BASELINE circuit: \(bits)-bit ripple adder, "
                + "\(netlist.luts.count) emitted LUT6, \(resynthLUTs) $lut after abc -lut 6, "
                + "\(inputBits) functional input bits, \(layout.outputWires.count) output bits"
        )
        print(
            "NATIVE_BASELINE workers requested=\(requestedWorkers) "
                + "source=\(configuredWorkers == nil ? "activeProcessorCount" : "environment")"
        )
        print("")
        print("NATIVE_BASELINE historical scope: synchronized graph run vs scalar assign/eval/read/digest")
        print("NATIVE_BASELINE lanes  helut_graph_s  native_scalar_e2e_s  ratio  digests")
        print("NATIVE_PAIRED scope: prepared pack/assign through ordered output digest")
        print("NATIVE_PAIRED lanes  helut_e2e_s  native_parallel_e2e_s  workers  ratio  digests")

        var rows: [(
            lanes: Int,
            helutGraph: Double,
            helutEndToEnd: Double,
            nativeScalar: Double,
            nativeParallelPrepared: Double,
            nativeParallelEndToEnd: Double,
            workers: Int,
            agreed: Bool
        )] = []

        for lanes in lanePoints {
            let compiler = try XCTUnwrap(
                YosysGraphCompiler(
                    degree: 1,
                    batch: lanes,
                    encodingKind: .constantFill,
                    lutBackend: .multilinear
                )
            )
            compiler.compile(moduleName: top, module: module)
            let encoding = compiler.bitEncoding
            let degree = compiler.degree
            let elementCount = lanes * degree
            let shape: [NSNumber] = [NSNumber(value: lanes), NSNumber(value: degree)]
            let low = encoding.encodeBit(0)
            let high = encoding.encodeBit(1)
            guard low.count == degree, high.count == degree else {
                return XCTFail("encoding degree mismatch")
            }

            var assignmentMasks = [Int](repeating: 0, count: lanes)
            for lane in 0..<lanes {
                assignmentMasks[lane] = assignment(
                    lane: lane,
                    lanes: lanes,
                    inputBits: inputBits
                )
            }

            var feeds: [MPSGraphTensor: MPSGraphTensorData] = [:]
            var inputBuffers: [(bitPosition: Int?, buffer: MTLBuffer)] = []
            var mappedInputWires = Set<Int32>()
            for entry in compiler.inputNodes {
                guard let placeholder = entry.node.placeholder else {
                    return XCTFail("missing placeholder for \(entry.port)")
                }
                let bitPosition: Int?
                if entry.port == "clk" {
                    bitPosition = nil
                } else {
                    let wireName = entry.port.replacingOccurrences(of: "in_", with: "")
                    guard let wire = Int32(wireName),
                          let position = layout.inputWires.firstIndex(of: wire),
                          mappedInputWires.insert(wire).inserted
                    else {
                        return XCTFail("unexpected or duplicate input port \(entry.port)")
                    }
                    bitPosition = position
                }

                var host = [UInt32](repeating: 0, count: elementCount)
                for lane in 0..<lanes {
                    let bit = bitPosition.map { (assignmentMasks[lane] >> $0) & 1 } ?? 0
                    let encoded = bit == 0 ? low : high
                    for coefficient in 0..<degree {
                        host[lane * degree + coefficient] = encoded[coefficient]
                    }
                }
                let buffer = try XCTUnwrap(device.makeBuffer(
                    bytes: host,
                    length: elementCount * MemoryLayout<UInt32>.stride,
                    options: .storageModeShared
                ))
                feeds[placeholder] = MPSGraphTensorData(
                    buffer,
                    shape: shape,
                    dataType: .uInt32
                )
                inputBuffers.append((bitPosition, buffer))
            }
            guard mappedInputWires == Set(layout.inputWires) else {
                return XCTFail(
                    "compiled input mapping incomplete: got \(mappedInputWires.sorted()), "
                        + "expected \(layout.inputWires)"
                )
            }

            // Unwrap each input's immutable bit position once. Buffer pointer
            // acquisition remains inside the timed pack phase so the accepted
            // paired boundary is unchanged.
            let clockSentinel = -1
            let inputPlans: [(position: Int, buffer: MTLBuffer)] = inputBuffers.map { input in
                (input.bitPosition ?? clockSentinel, input.buffer)
            }

            let refillInputs = { () -> Double in
                assignmentMasks.withUnsafeMutableBufferPointer { masks in
                    for lane in 0..<lanes {
                        masks[lane] = self.assignment(
                            lane: lane,
                            lanes: lanes,
                            inputBits: inputBits
                        )
                    }
                }
                let assignmentsEnded = CFAbsoluteTimeGetCurrent()
                low.withUnsafeBufferPointer { lowBuffer in
                    high.withUnsafeBufferPointer { highBuffer in
                        assignmentMasks.withUnsafeBufferPointer { masks in
                            let lowPointer = lowBuffer.baseAddress!
                            let highPointer = highBuffer.baseAddress!
                            if degree == 1 {
                                let lowValue = lowPointer[0]
                                let highValue = highPointer[0]
                                for plan in inputPlans {
                                    let pointer = plan.buffer.contents().bindMemory(
                                        to: UInt32.self,
                                        capacity: elementCount
                                    )
                                    let position = plan.position
                                    if position == clockSentinel {
                                        for lane in 0..<lanes {
                                            pointer[lane] = lowValue
                                        }
                                    } else {
                                        for lane in 0..<lanes {
                                            pointer[lane] = ((masks[lane] >> position) & 1) == 0
                                                ? lowValue
                                                : highValue
                                        }
                                    }
                                }
                            } else {
                                for plan in inputPlans {
                                    let pointer = plan.buffer.contents().bindMemory(
                                        to: UInt32.self,
                                        capacity: elementCount
                                    )
                                    let position = plan.position
                                    for lane in 0..<lanes {
                                        let source: UnsafePointer<UInt32>
                                        if position == clockSentinel {
                                            source = lowPointer
                                        } else {
                                            source = ((masks[lane] >> position) & 1) == 0
                                                ? lowPointer
                                                : highPointer
                                        }
                                        let base = lane * degree
                                        for coefficient in 0..<degree {
                                            pointer[base + coefficient] = source[coefficient]
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                return assignmentsEnded
            }

            var results: [MPSGraphTensor: MPSGraphTensorData] = [:]
            var outputs: [(wire: Int32, column: Int, buffer: MTLBuffer)] = []
            var mappedOutputWires = Set<Int32>()
            for entry in compiler.outputTensors {
                let wireName = entry.port.replacingOccurrences(of: "out_", with: "")
                guard let wire = Int32(wireName),
                      let column = layout.outputWires.firstIndex(of: wire),
                      mappedOutputWires.insert(wire).inserted
                else {
                    return XCTFail("unexpected or duplicate output port \(entry.port)")
                }
                let buffer = try XCTUnwrap(device.makeBuffer(
                    length: elementCount * MemoryLayout<UInt32>.stride,
                    options: .storageModeShared
                ))
                results[entry.tensor] = MPSGraphTensorData(
                    buffer,
                    shape: shape,
                    dataType: .uInt32
                )
                outputs.append((wire, column, buffer))
            }
            guard mappedOutputWires == Set(layout.outputWires) else {
                return XCTFail(
                    "compiled output mapping incomplete: got \(mappedOutputWires.sorted()), "
                        + "expected \(layout.outputWires)"
                )
            }

            // Materialize every decoded value in one lane-major flat buffer.
            // This preserves the canonical byte stream while avoiding per-lane
            // inner-array storage. Output pointer acquisition remains inside the
            // timed decode phase to preserve the accepted paired boundary.
            let wireCount = layout.outputWires.count
            var values = [UInt32](repeating: 0, count: lanes * wireCount)
            let outputPlans: [(column: Int, buffer: MTLBuffer)] = outputs.map { output in
                (output.column, output.buffer)
            }
            let collectOutputs = {
                values.withUnsafeMutableBufferPointer { dst in
                    for entry in outputPlans {
                        let pointer = entry.buffer.contents().bindMemory(
                            to: UInt32.self,
                            capacity: elementCount
                        )
                        var index = entry.column
                        for lane in 0..<lanes {
                            dst[index] = MockTorusEncoding.decodeBit(
                                buffer: pointer,
                                lane: lane,
                                degree: degree,
                                strict: true
                            )
                            index += wireCount
                        }
                    }
                }
            }

            let coldStarted = CFAbsoluteTimeGetCurrent()
            compiler.graph.run(
                with: queue,
                feeds: feeds,
                targetOperations: nil,
                resultsDictionary: results
            )
            let coldSeconds = CFAbsoluteTimeGetCurrent() - coldStarted

            var helutGraphSamples: [Double] = []
            for _ in 0..<trials {
                let started = CFAbsoluteTimeGetCurrent()
                compiler.graph.run(
                    with: queue,
                    feeds: feeds,
                    targetOperations: nil,
                    resultsDictionary: results
                )
                helutGraphSamples.append(CFAbsoluteTimeGetCurrent() - started)
            }
            let helutGraphMedian = median(helutGraphSamples)
            collectOutputs()
            let helutDigest = digest(
                lanes: lanes,
                wires: layout.outputWires,
                values: values
            )

            var helutAssignmentSamples: [Double] = []
            var helutInputPackSamples: [Double] = []
            var helutPairedGraphSamples: [Double] = []
            var helutDecodeSamples: [Double] = []
            var helutDigestSamples: [Double] = []
            var helutEndToEndSamples: [Double] = []
            var helutReconciliationResiduals: [Double] = []
            helutAssignmentSamples.reserveCapacity(trials)
            helutInputPackSamples.reserveCapacity(trials)
            helutPairedGraphSamples.reserveCapacity(trials)
            helutDecodeSamples.reserveCapacity(trials)
            helutDigestSamples.reserveCapacity(trials)
            helutEndToEndSamples.reserveCapacity(trials)
            helutReconciliationResiduals.reserveCapacity(trials)

            for trial in 0..<trials {
                let started = CFAbsoluteTimeGetCurrent()
                let assignmentsEnded = refillInputs()
                let packingEnded = CFAbsoluteTimeGetCurrent()
                compiler.graph.run(
                    with: queue,
                    feeds: feeds,
                    targetOperations: nil,
                    resultsDictionary: results
                )
                let graphEnded = CFAbsoluteTimeGetCurrent()
                collectOutputs()
                let decodeEnded = CFAbsoluteTimeGetCurrent()
                let trialDigest = digest(
                    lanes: lanes,
                    wires: layout.outputWires,
                    values: values
                )
                let digestEnded = CFAbsoluteTimeGetCurrent()

                let assignmentSeconds = assignmentsEnded - started
                let inputPackSeconds = packingEnded - assignmentsEnded
                let graphSeconds = graphEnded - packingEnded
                let decodeSeconds = decodeEnded - graphEnded
                let digestSeconds = digestEnded - decodeEnded
                let endToEndSeconds = digestEnded - started
                let phaseSum = assignmentSeconds + inputPackSeconds + graphSeconds
                    + decodeSeconds + digestSeconds
                let reconciliationResidual = endToEndSeconds - phaseSum
                let phases = [
                    assignmentSeconds,
                    inputPackSeconds,
                    graphSeconds,
                    decodeSeconds,
                    digestSeconds,
                    endToEndSeconds
                ]
                guard phases.allSatisfy({ $0 >= 0 }),
                      abs(reconciliationResidual) <= 0.000_000_001
                else {
                    return XCTFail(
                        "HELUT paired phase accounting failed at lanes=\(lanes), "
                            + "trial=\(trial): phases=\(phases), "
                            + "residual=\(reconciliationResidual)"
                    )
                }

                helutAssignmentSamples.append(assignmentSeconds)
                helutInputPackSamples.append(inputPackSeconds)
                helutPairedGraphSamples.append(graphSeconds)
                helutDecodeSamples.append(decodeSeconds)
                helutDigestSamples.append(digestSeconds)
                helutEndToEndSamples.append(endToEndSeconds)
                helutReconciliationResiduals.append(reconciliationResidual)
                guard trialDigest == helutDigest else {
                    return XCTFail(
                        "HELUT paired digest unstable at lanes=\(lanes), trial=\(trial): "
                            + "reference=\(String(helutDigest, radix: 16)) "
                            + "actual=\(String(trialDigest, radix: 16))"
                    )
                }
            }
            let helutEndToEndMedian = median(helutEndToEndSamples)
            print(
                "HELUT_PAIRED_PHASE_SAMPLES lanes=\(lanes) "
                    + "assignment_ns=\(nanosecondSamples(helutAssignmentSamples)) "
                    + "input_pack_ns=\(nanosecondSamples(helutInputPackSamples)) "
                    + "graph_ns=\(nanosecondSamples(helutPairedGraphSamples)) "
                    + "decode_ns=\(nanosecondSamples(helutDecodeSamples)) "
                    + "digest_ns=\(nanosecondSamples(helutDigestSamples)) "
                    + "total_ns=\(nanosecondSamples(helutEndToEndSamples)) "
                    + "residual_ns=\(nanosecondSamples(helutReconciliationResiduals))"
            )

            let (simulatorStatus, simulatorOutput) = try run(
                simulatorPath,
                [String(lanes), String(trials), String(requestedWorkers)],
                cwd: directory
            )
            let lines = simulatorOutput.split(separator: "\n")
            guard simulatorStatus == 0,
                  let scalarLine = lines.first(where: { $0.hasPrefix("VERILATOR ") }),
                  let pairedLine = lines.first(where: { $0.hasPrefix("VERILATOR_PAIRED ") })
            else {
                return XCTFail(
                    "verilator sim failed at lanes=\(lanes):\n"
                        + String(simulatorOutput.suffix(3000))
                )
            }

            func field(_ key: String, in line: Substring) -> String? {
                line.split(separator: " ")
                    .first { $0.hasPrefix("\(key)=") }?
                    .split(separator: "=").last
                    .map(String.init)
            }

            guard let nativeScalarDigest = UInt64(
                    field("digest", in: scalarLine) ?? "",
                    radix: 16
                  ),
                  let nativeScalarMedian = Double(field("median_s", in: scalarLine) ?? ""),
                  let nativeParallelDigest = UInt64(
                    field("digest", in: pairedLine) ?? "",
                    radix: 16
                  ),
                  let nativeParallelPreparedMedian = Double(
                    field("prepared_median_s", in: pairedLine) ?? ""
                  ),
                  let nativeParallelEndToEndMedian = Double(
                    field("e2e_median_s", in: pairedLine) ?? ""
                  ),
                  let effectiveWorkers = Int(field("workers", in: pairedLine) ?? "")
            else {
                return XCTFail(
                    "could not parse Verilator output at lanes=\(lanes):\n\(simulatorOutput)"
                )
            }

            let historicalAgreed = nativeScalarDigest == helutDigest
            let pairedAgreed = nativeParallelDigest == helutDigest
            let agreed = historicalAgreed && pairedAgreed
            let historicalRatio = nativeScalarMedian > 0
                ? helutGraphMedian / nativeScalarMedian
                : .nan
            let pairedRatio = nativeParallelEndToEndMedian > 0
                ? helutEndToEndMedian / nativeParallelEndToEndMedian
                : .nan

            rows.append((
                lanes,
                helutGraphMedian,
                helutEndToEndMedian,
                nativeScalarMedian,
                nativeParallelPreparedMedian,
                nativeParallelEndToEndMedian,
                effectiveWorkers,
                agreed
            ))

            print(
                "NATIVE_BASELINE \(String(lanes).leftPadded(5))  "
                    + "\(String(format: "%.9f", helutGraphMedian))  "
                    + "\(String(format: "%.9f", nativeScalarMedian))  "
                    + "\(String(format: "%.3f", historicalRatio))x  "
                    + (historicalAgreed
                        ? "match \(String(helutDigest, radix: 16))"
                        : "MISMATCH helut=\(String(helutDigest, radix: 16)) "
                            + "native=\(String(nativeScalarDigest, radix: 16))")
            )
            print(
                "NATIVE_PAIRED  \(String(lanes).leftPadded(5))  "
                    + "\(String(format: "%.9f", helutEndToEndMedian))  "
                    + "\(String(format: "%.9f", nativeParallelEndToEndMedian))  "
                    + "\(String(effectiveWorkers).leftPadded(3))  "
                    + "\(String(format: "%.3f", pairedRatio))x  "
                    + (pairedAgreed
                        ? "match \(String(helutDigest, radix: 16))"
                        : "MISMATCH helut=\(String(helutDigest, radix: 16)) "
                            + "native=\(String(nativeParallelDigest, radix: 16))")
            )

            print(
                "NATIVE_PAIRED_DETAIL lanes=\(lanes) "
                    + "helut_graph_median_s=\(String(format: "%.9f", helutGraphMedian)) "
                    + "native_parallel_prepared_median_s="
                    + "\(String(format: "%.9f", nativeParallelPreparedMedian)) "
                    + "helut_graph_ns=\(nanosecondSamples(helutGraphSamples)) "
                    + "helut_e2e_ns=\(nanosecondSamples(helutEndToEndSamples))"
            )
            if let scalarSamples = lines.first(where: {
                $0.hasPrefix("VERILATOR_SCALAR_SAMPLES ")
            }) {
                print(scalarSamples)
            }
            if let nativeSamples = lines.first(where: {
                $0.hasPrefix("VERILATOR_PAIRED_SAMPLES ")
            }) {
                print(nativeSamples)
            }
            print(
                "                 helut cold first run "
                    + "\(String(format: "%.6f", coldSeconds))s (JIT, excluded)"
            )

            XCTAssertTrue(
                agreed,
                "at \(lanes) lanes at least one native digest disagreed with HELUT"
            )
        }

        let historicalCrossover = rows.first { $0.helutGraph < $0.nativeScalar }
        let pairedCrossover = rows.first {
            $0.helutEndToEnd < $0.nativeParallelEndToEnd
        }
        print("")
        if let historicalCrossover {
            print(
                "NATIVE_BASELINE historical crossover: first tested HELUT graph win at "
                    + "B=\(historicalCrossover.lanes) "
                    + "(\(String(format: "%.9f", historicalCrossover.helutGraph))s vs "
                    + "\(String(format: "%.9f", historicalCrossover.nativeScalar))s)."
            )
        } else {
            print(
                "NATIVE_BASELINE historical crossover: none through B="
                    + "\(rows.last?.lanes ?? 0)."
            )
        }
        if let pairedCrossover {
            print(
                "NATIVE_PAIRED crossover: first tested HELUT end-to-end win at "
                    + "B=\(pairedCrossover.lanes) against "
                    + "\(pairedCrossover.workers)-worker Verilator "
                    + "(\(String(format: "%.9f", pairedCrossover.helutEndToEnd))s vs "
                    + "\(String(format: "%.9f", pairedCrossover.nativeParallelEndToEnd))s)."
            )
        } else {
            print(
                "NATIVE_PAIRED crossover: none through B=\(rows.last?.lanes ?? 0) "
                    + "against the configured parallel Verilator baseline."
            )
        }
        print(
            "NATIVE_PAIRED boundary: one combinational circuit and host; \(trials) timed "
                + "passes per point. Build, graph compile, allocation, model/thread creation, "
                + "and cold specialization are excluded. Historical graph timing remains "
                + "asymmetric. Paired timing includes deterministic input preparation, "
                + "synchronized execution, output read/decode, and ordered digest on both "
                + "sides; HELUT uses release Swift and native uses optimized C++. Native "
                + "workers are scheduler-managed and unpinned. This is not a general HDL, "
                + "sequential, cross-host, or best-possible-native claim."
        )

        XCTAssertTrue(rows.allSatisfy(\.agreed), "at least one width diverged")
    }
}

private extension String {
    func leftPadded(_ width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }
}
