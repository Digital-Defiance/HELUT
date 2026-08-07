// Proposed Metal kernels for HELUT / TensorLUT.
// STATUS: not compiled or run on Metal (review sandbox is Linux). The arithmetic of each function
// mirrors a C reference that was checked bit-exact: harness.c (LUT eval, DFF), br_math.c (mulmod,
// NTT). Treat these as a spec to port, then grade against the existing Swift/CPU references.
#include <metal_stdlib>
using namespace metal;

// ============================================================================================
// 1. Two-phase DFF commit (fixes the in-place read-after-write race in soft_dff_update).
//    Adds enableGatesReset for $_SDFFCE_. Swift TensorDFFCell grows to 8 x int32 (stride 32).
// ============================================================================================
struct DFFInputs2 {
    int32_t dWire, qWire, enableWire, resetWire;
    int32_t enableActiveHigh, resetActiveHigh, resetValue, enableGatesReset;
};

// Phase 1: read only. Wire-major storage: wires[w * batch + lane].
kernel void dff_next_state(
    device DFFInputs2 const *dffs  [[buffer(0)]],
    device float const *wires      [[buffer(1)]],
    device float *qNext            [[buffer(2)]],   // [numDFFs * batch]
    constant uint &numDFFs         [[buffer(3)]],
    constant uint &batch           [[buffer(4)]],
    uint2 pos                      [[thread_position_in_grid]])   // x: lane, y: dff
{
    uint lane = pos.x, i = pos.y;
    if (lane >= batch || i >= numDFFs) return;
    DFFInputs2 f = dffs[i];
    float d = f.dWire >= 0 ? wires[uint(f.dWire) * batch + lane] : 0.0f;
    float q = wires[uint(f.qWire) * batch + lane];
    // Multilinear (mean-field-consistent) enable: q' = e*d + (1-e)*q. For binary e this is the mux.
    float e = 1.0f;
    if (f.enableWire >= 0) {
        float raw = wires[uint(f.enableWire) * batch + lane];
        e = f.enableActiveHigh != 0 ? raw : 1.0f - raw;
    }
    float r = 0.0f;
    if (f.resetWire >= 0) {
        float raw = wires[uint(f.resetWire) * batch + lane];
        r = f.resetActiveHigh != 0 ? raw : 1.0f - raw;
    }
    float rv = float(f.resetValue);
    float next;
    if (f.enableGatesReset != 0) {            // $_SDFFCE_: enable has priority over reset
        next = e * (r * rv + (1.0f - r) * d) + (1.0f - e) * q;
    } else {                                  // $_SDFF_/$_SDFFE_: reset has priority
        next = r * rv + (1.0f - r) * (e * d + (1.0f - e) * q);
    }
    qNext[i * batch + lane] = next;
}

// Phase 2: write only. Separate dispatch (or separate encoder) after phase 1.
kernel void dff_commit(
    device DFFInputs2 const *dffs  [[buffer(0)]],
    device float *wires            [[buffer(1)]],
    device float const *qNext      [[buffer(2)]],
    constant uint &numDFFs         [[buffer(3)]],
    constant uint &batch           [[buffer(4)]],
    uint2 pos                      [[thread_position_in_grid]])
{
    uint lane = pos.x, i = pos.y;
    if (lane >= batch || i >= numDFFs) return;
    wires[uint(dffs[i].qWire) * batch + lane] = qNext[i * batch + lane];
}

// ============================================================================================
// 2. Float LUT level, wire-major, width-aware de Casteljau fold (2^w - 1 FMAs, same math as the
//    64-corner sum; max diff 4.8e-7 on 200k random melted LUT6s). INIT stays 64-wide so the
//    chromosome layout does not change; only the first 2^w entries are read.
// ============================================================================================
struct LUT6Rec {
    int32_t in0, in1, in2, in3, in4, in5;
    int32_t outWire;
    int32_t width;                            // live inputs, 1..6 (new field; stride 32)
};

kernel void tensor_lut_level_dc(
    device float const *inits              [[buffer(0)]],   // [numLUTs * 64]
    device LUT6Rec const *nodes            [[buffer(1)]],   // this level
    device float *wires                    [[buffer(2)]],   // [numWires * batch]
    device uint const *globalIdx           [[buffer(3)]],
    constant uint &numInLevel              [[buffer(4)]],
    constant uint &batch                   [[buffer(5)]],
    uint2 pos                              [[thread_position_in_grid]])   // x: lane (coalesced)
{
    uint lane = pos.x, j = pos.y;
    if (lane >= batch || j >= numInLevel) return;
    LUT6Rec r = nodes[j];
    device float const *t = inits + globalIdx[j] * 64u;
    int ins[6] = { r.in0, r.in1, r.in2, r.in3, r.in4, r.in5 };
    float v[64];
    uint n = 1u << uint(r.width);
    for (uint k = 0; k < n; ++k) v[k] = t[k];
    for (int m = 0; m < r.width; ++m) {
        float x = wires[uint(ins[m]) * batch + lane];
        n >>= 1;
        for (uint k = 0; k < n; ++k) v[k] = fma(x, v[2 * k + 1] - v[2 * k], v[2 * k]);
    }
    wires[uint(r.outWire) * batch + lane] = v[0];
}

// ============================================================================================
// 3. Fused bit-sliced Boolean evaluator: 32 lanes per thread, whole netlist in topological
//    order, T ticks per dispatch, inject/sample through buffers, two-phase DFF per thread.
//    No inter-level barriers: each thread owns its lanes, which also removes the DFF race.
//    Use when every INIT is binary (frozen core, involution sandwich, Future bank receipts) or
//    for sampled mixed-strategy fitness (lanes = sampled circuits).
// ============================================================================================
struct BitLUT { uint in[6]; uint out; uint width; ulong tt; };        // tt: LSB = address 0
struct BitDFF { uint d, q; int e, r; uint ePol, rPol, rVal, eGatesR; };

inline uint mux(uint a, uint b, uint s) { return a ^ ((a ^ b) & s); }  // s ? b : a, per bit

kernel void tensorlut_bitsliced_ticks(
    device BitLUT const *luts        [[buffer(0)]],   // topological order
    device BitDFF const *dffs        [[buffer(1)]],
    device uint *wires               [[buffer(2)]],   // [numWires * words]
    device uint const *inject        [[buffer(3)]],   // [ticks * numIn * words]
    device uint const *inWires       [[buffer(4)]],   // [numIn]
    device uint *sample              [[buffer(5)]],   // [ticks * numOut * words]
    device uint const *outWires      [[buffer(6)]],   // [numOut]
    device uint *qScratch            [[buffer(7)]],   // [numDFFs * words]
    constant uint4 &dims             [[buffer(8)]],   // numLUTs, numDFFs, numIn, numOut
    constant uint2 &tw               [[buffer(9)]],   // ticks, words
    uint g                           [[thread_position_in_grid]])
{
    uint words = tw.y;
    if (g >= words) return;
    for (uint t = 0; t < tw.x; ++t) {
        for (uint i = 0; i < dims.z; ++i)
            wires[inWires[i] * words + g] = inject[(t * dims.z + i) * words + g];
        for (uint li = 0; li < dims.x; ++li) {
            BitLUT L = luts[li];
            uint v[32];
            uint x0 = wires[L.in[0] * words + g];
            uint half = (1u << L.width) >> 1;
            for (uint k = 0; k < max(half, 1u); ++k) {        // first fold: constant leaves
                uint bits = uint((L.tt >> (2u * k)) & 3ul);
                v[k] = bits == 0u ? 0u : bits == 1u ? ~x0 : bits == 2u ? x0 : 0xFFFFFFFFu;
            }
            uint n = half;
            for (uint m = 1; m < L.width; ++m) {
                uint s = wires[L.in[m] * words + g];
                n >>= 1;
                for (uint k = 0; k < n; ++k) v[k] = mux(v[2 * k], v[2 * k + 1], s);
            }
            wires[L.out * words + g] = v[0];
        }
        for (uint i = 0; i < dims.y; ++i) {                   // phase 1: next state
            BitDFF f = dffs[i];
            uint d = wires[f.d * words + g], q = wires[f.q * words + g];
            uint en = 0xFFFFFFFFu, rs = 0u;
            if (f.e >= 0) { uint e = wires[uint(f.e) * words + g]; en = f.ePol ? e : ~e; }
            if (f.r >= 0) { uint r = wires[uint(f.r) * words + g]; rs = f.rPol ? r : ~r; }
            uint rv = f.rVal ? 0xFFFFFFFFu : 0u;
            uint nx = f.eGatesR ? mux(q, mux(d, rv, rs), en) : mux(mux(q, d, en), rv, rs);
            qScratch[i * words + g] = nx;
        }
        for (uint i = 0; i < dims.y; ++i)                     // phase 2: commit
            wires[dffs[i].q * words + g] = qScratch[i * words + g];
        for (uint o = 0; o < dims.w; ++o)
            sample[(t * dims.w + o) * words + g] = wires[outWires[o] * words + g];
    }
}

// ============================================================================================
// 4. Modular multiply for the blind rotation (replaces uint((ulong)a*(ulong)b % (ulong)p)).
//    Verified bit-exact against the 64-bit remainder for all three NegacyclicNTT primes.
//    pinv = -p^{-1} mod 2^32. Store the NTT-domain key in Montgomery form (key * 2^32 mod p)
//    so mont_mul(digitHat, keyMont) returns digitHat * key mod p in standard form.
//    Twiddles, twist and 1/N are constants: use Shoup with wq = floor(w * 2^32 / p).
// ============================================================================================
inline uint mont_mul(uint a, uint b, uint p, uint pinv) {
    uint lo = a * b;
    uint hi = mulhi(a, b);
    uint m  = lo * pinv;
    uint t  = hi + mulhi(m, p) + (lo != 0u ? 1u : 0u);   // < 2p < 2^32 because p < 2^31
    return t >= p ? t - p : t;
}

inline uint shoup_mul(uint a, uint w, uint wq, uint p) {
    uint q = mulhi(a, wq);
    uint r = a * w - q * p;                                // exact, in [0, 2p)
    return r >= p ? r - p : r;
}
