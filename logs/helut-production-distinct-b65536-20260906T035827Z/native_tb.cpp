#include "Vripple_adder.h"
#include "verilated.h"
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <algorithm>
#include <vector>

static inline void mix(uint64_t* h, uint32_t v) {
    uint8_t b[4] = {
        (uint8_t)(v & 0xff), (uint8_t)((v >> 8) & 0xff),
        (uint8_t)((v >> 16) & 0xff), (uint8_t)((v >> 24) & 0xff)
    };
    for (int i = 0; i < 4; i++) { *h ^= b[i]; *h *= 0x100000001b3ULL; }
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    int lanes = atoi(argv[1]);
    int trials = atoi(argv[2]);
    int inputBits = 16;
    long space = 1L << inputBits;
    long stride = space / (lanes > 0 ? lanes : 1);
    if (stride < 1) stride = 1;

    Vripple_adder* top = new Vripple_adder;
    uint64_t reference = 0;
    std::vector<double> times;

    for (int trial = 0; trial < trials + 1; trial++) {
        uint64_t hash = 0xcbf29ce484222325ULL;
        auto started = std::chrono::steady_clock::now();
        for (int lane = 0; lane < lanes; lane++) {
            long assignment = (lane * stride) % space;
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
            mix(&hash, (uint32_t)lane); mix(&hash, 24); mix(&hash, (uint32_t)top->out_24);
            mix(&hash, (uint32_t)lane); mix(&hash, 25); mix(&hash, (uint32_t)top->out_25);
            mix(&hash, (uint32_t)lane); mix(&hash, 26); mix(&hash, (uint32_t)top->out_26);
            mix(&hash, (uint32_t)lane); mix(&hash, 27); mix(&hash, (uint32_t)top->out_27);
            mix(&hash, (uint32_t)lane); mix(&hash, 28); mix(&hash, (uint32_t)top->out_28);
            mix(&hash, (uint32_t)lane); mix(&hash, 29); mix(&hash, (uint32_t)top->out_29);
            mix(&hash, (uint32_t)lane); mix(&hash, 30); mix(&hash, (uint32_t)top->out_30);
            mix(&hash, (uint32_t)lane); mix(&hash, 31); mix(&hash, (uint32_t)top->out_31);
            mix(&hash, (uint32_t)lane); mix(&hash, 23); mix(&hash, (uint32_t)top->out_23);
        }
        auto elapsed = std::chrono::steady_clock::now() - started;
        double seconds = std::chrono::duration<double>(elapsed).count();
        if (trial == 0) { reference = hash; }
        else {
            times.push_back(seconds);
            if (hash != reference) return 2;
        }
    }
    std::sort(times.begin(), times.end());
    printf("VERILATOR digest=%llx median_s=%.9f min_s=%.9f max_s=%.9f lanes=%d\n",
           (unsigned long long)reference, times[times.size() / 2],
           times.front(), times.back(), lanes);
    delete top;
    return 0;
}
