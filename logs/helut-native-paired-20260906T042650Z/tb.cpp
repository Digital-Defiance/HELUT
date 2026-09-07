#include "Vripple_adder.h"
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

static constexpr int kOutputCount = 9;

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
            mix(&hash, (uint32_t)lane); mix(&hash, (uint32_t)24); mix(&hash, outputs[(size_t)lane * kOutputCount + 0]);
            mix(&hash, (uint32_t)lane); mix(&hash, (uint32_t)25); mix(&hash, outputs[(size_t)lane * kOutputCount + 1]);
            mix(&hash, (uint32_t)lane); mix(&hash, (uint32_t)26); mix(&hash, outputs[(size_t)lane * kOutputCount + 2]);
            mix(&hash, (uint32_t)lane); mix(&hash, (uint32_t)27); mix(&hash, outputs[(size_t)lane * kOutputCount + 3]);
            mix(&hash, (uint32_t)lane); mix(&hash, (uint32_t)28); mix(&hash, outputs[(size_t)lane * kOutputCount + 4]);
            mix(&hash, (uint32_t)lane); mix(&hash, (uint32_t)29); mix(&hash, outputs[(size_t)lane * kOutputCount + 5]);
            mix(&hash, (uint32_t)lane); mix(&hash, (uint32_t)30); mix(&hash, outputs[(size_t)lane * kOutputCount + 6]);
            mix(&hash, (uint32_t)lane); mix(&hash, (uint32_t)31); mix(&hash, outputs[(size_t)lane * kOutputCount + 7]);
            mix(&hash, (uint32_t)lane); mix(&hash, (uint32_t)23); mix(&hash, outputs[(size_t)lane * kOutputCount + 8]);
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
            worker->top = std::make_unique<Vripple_adder>(worker->context.get(), "worker");
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
        std::unique_ptr<Vripple_adder> top;
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

            Vripple_adder* top = workers_[(size_t)workerIndex]->top.get();
            int begin = (lanes_ * workerIndex) / workerCount_;
            int end = (lanes_ * (workerIndex + 1)) / workerCount_;
            for (int lane = begin; lane < end; lane++) {
                uint64_t assignment = assignments_[(size_t)lane];
        top->clk = 0;
        top->in_0 = (assignment >> 0) & 1;
        top->in_1 = (assignment >> 1) & 1;
        top->in_2 = (assignment >> 2) & 1;
        top->in_3 = (assignment >> 3) & 1;
        top->in_4 = (assignment >> 4) & 1;
        top->in_5 = (assignment >> 5) & 1;
        top->in_6 = (assignment >> 6) & 1;
        top->in_7 = (assignment >> 7) & 1;
        top->in_8 = (assignment >> 8) & 1;
        top->in_9 = (assignment >> 9) & 1;
        top->in_10 = (assignment >> 10) & 1;
        top->in_11 = (assignment >> 11) & 1;
        top->in_12 = (assignment >> 12) & 1;
        top->in_13 = (assignment >> 13) & 1;
        top->in_14 = (assignment >> 14) & 1;
        top->in_15 = (assignment >> 15) & 1;
                top->eval();
        outputs_[(size_t)lane * kOutputCount + 0] = (uint32_t)top->out_24;
        outputs_[(size_t)lane * kOutputCount + 1] = (uint32_t)top->out_25;
        outputs_[(size_t)lane * kOutputCount + 2] = (uint32_t)top->out_26;
        outputs_[(size_t)lane * kOutputCount + 3] = (uint32_t)top->out_27;
        outputs_[(size_t)lane * kOutputCount + 4] = (uint32_t)top->out_28;
        outputs_[(size_t)lane * kOutputCount + 5] = (uint32_t)top->out_29;
        outputs_[(size_t)lane * kOutputCount + 6] = (uint32_t)top->out_30;
        outputs_[(size_t)lane * kOutputCount + 7] = (uint32_t)top->out_31;
        outputs_[(size_t)lane * kOutputCount + 8] = (uint32_t)top->out_23;
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
        printf("usage: sim lanes trials workers\n");
        return 64;
    }
    Verilated::commandArgs(argc, argv);
    int lanes = atoi(argv[1]);
    int trials = atoi(argv[2]);
    int requestedWorkers = atoi(argv[3]);
    if (lanes < 1 || trials < 1 || requestedWorkers < 1) return 64;

    int inputBits = 16;
    uint64_t space = 1ULL << inputBits;
    uint64_t stride = space / (uint64_t)lanes;
    if (stride < 1) stride = 1;

    // Historical scalar baseline: preserve the old timing boundary.
    Vripple_adder* top = new Vripple_adder;
    uint64_t scalarReference = 0;
    std::vector<int64_t> scalarTimes;
    for (int trial = 0; trial < trials + 1; trial++) {
        uint64_t hash = 0xcbf29ce484222325ULL;
        auto started = std::chrono::steady_clock::now();
        for (int lane = 0; lane < lanes; lane++) {
            uint64_t assignment = ((uint64_t)lane * stride) % space;
        top->in_0 = (assignment >> 0) & 1;
        top->in_1 = (assignment >> 1) & 1;
        top->in_2 = (assignment >> 2) & 1;
        top->in_3 = (assignment >> 3) & 1;
        top->in_4 = (assignment >> 4) & 1;
        top->in_5 = (assignment >> 5) & 1;
        top->in_6 = (assignment >> 6) & 1;
        top->in_7 = (assignment >> 7) & 1;
        top->in_8 = (assignment >> 8) & 1;
        top->in_9 = (assignment >> 9) & 1;
        top->in_10 = (assignment >> 10) & 1;
        top->in_11 = (assignment >> 11) & 1;
        top->in_12 = (assignment >> 12) & 1;
        top->in_13 = (assignment >> 13) & 1;
        top->in_14 = (assignment >> 14) & 1;
        top->in_15 = (assignment >> 15) & 1;
            top->eval();
            mix(&hash, (uint32_t)lane); mix(&hash, (uint32_t)24); mix(&hash, (uint32_t)top->out_24);
            mix(&hash, (uint32_t)lane); mix(&hash, (uint32_t)25); mix(&hash, (uint32_t)top->out_25);
            mix(&hash, (uint32_t)lane); mix(&hash, (uint32_t)26); mix(&hash, (uint32_t)top->out_26);
            mix(&hash, (uint32_t)lane); mix(&hash, (uint32_t)27); mix(&hash, (uint32_t)top->out_27);
            mix(&hash, (uint32_t)lane); mix(&hash, (uint32_t)28); mix(&hash, (uint32_t)top->out_28);
            mix(&hash, (uint32_t)lane); mix(&hash, (uint32_t)29); mix(&hash, (uint32_t)top->out_29);
            mix(&hash, (uint32_t)lane); mix(&hash, (uint32_t)30); mix(&hash, (uint32_t)top->out_30);
            mix(&hash, (uint32_t)lane); mix(&hash, (uint32_t)31); mix(&hash, (uint32_t)top->out_31);
            mix(&hash, (uint32_t)lane); mix(&hash, (uint32_t)23); mix(&hash, (uint32_t)top->out_23);
        }
        auto elapsed = std::chrono::duration_cast<std::chrono::nanoseconds>(
            std::chrono::steady_clock::now() - started
        ).count();
        if (trial == 0) {
            scalarReference = hash;
        } else {
            scalarTimes.push_back(elapsed);
            if (hash != scalarReference) {
                printf("VERILATOR_DIGEST_UNSTABLE\n");
                return 2;
            }
        }
    }
    top->final();
    delete top;

    auto scalarBounds = std::minmax_element(scalarTimes.begin(), scalarTimes.end());
    printf(
        "VERILATOR digest=%llx median_s=%.9f min_s=%.9f max_s=%.9f lanes=%d\n",
        (unsigned long long)scalarReference,
        medianSeconds(scalarTimes),
        (double)*scalarBounds.first / 1e9,
        (double)*scalarBounds.second / 1e9,
        lanes
    );

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
                printf("VERILATOR_PARALLEL_DIGEST_UNSTABLE\n");
                return 2;
            }
        }
    }
    if (parallelReference != scalarReference) {
        printf("VERILATOR_PARALLEL_MISMATCH scalar=%llx parallel=%llx\n",
               (unsigned long long)scalarReference,
               (unsigned long long)parallelReference);
        return 3;
    }

    printf(
        "VERILATOR_PAIRED digest=%llx prepared_median_s=%.9f "
        "e2e_median_s=%.9f workers=%d requested_workers=%d lanes=%d\n",
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
    printf("\n");
    return 0;
}