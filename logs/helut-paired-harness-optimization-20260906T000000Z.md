# Receipt: paired-scope harness optimization, and a correction to the paired claim

**Date:** 2026-09-06
**Host:** Apple M4 Max / macOS 26.6.2
**Test:** `NativeBaselineComparisonTests.testHelutVersusVerilatorOnTheSameCircuit`
**Raw log:** `logs/helut-paired-harness-optimization-20260906T000000Z.log`

This receipt has two halves. The first is a real, verified speedup. The second is
a correction that matters more, and it points the opposite way.

---

# Part 1 — Harness optimization (verified)

Two changes in `Tests/HELUTTests/NativeBaselineComparisonTests.swift`. Both are
host-side data marshalling. Neither touches the engine, the circuit, the
stimulus, or any output bit.

1. **Decode destination flattened.** `values` was `[[UInt32]]` — one inner
   `Array` per lane, 65,536 separate heap allocations at B=65,536 — and
   `collectOutputs` ran output-outer / lane-inner, touching a different
   allocation on every one of 589,824 stores. Replaced with a single contiguous
   lane-major `[UInt32]`, each output buffer bound once instead of per call.

2. **Input pack invariants hoisted.** `refillInputs` evaluated an
   `Optional.map` closure and an `Array` assignment (`bit == 0 ? low : high`, so
   ARC retain/release) once per `(input, lane)` pair — 17 x 65,536 = 1.1M of each
   per refill. Bind, bit-position unwrap, and `low`/`high` base pointers are now
   hoisted out of the lane loop.

## Correctness gate

**All eight per-width digests are byte-identical before and after**, every row
still reports `match` against the native side:

```
1      8f9f7fb8cfd7dde2      4096   53efd78eadd2ee5
16     84c0b917691450a5      16384  5bae3d89c7c044e5
256    aa0c5f15c933c725      32768  f79eaea4cb7276a5
1024   25bc9c05761bbee5      65536  52f209ab0358725
```

The hashed byte stream is unchanged; only the read addressing changed. Banked
receipts referencing `fnv1a64-3f03b6872d46d5a5` and the ep00/ep14 capture
transcripts remain valid.

## Stage medians at B=65,536

| stage | before | after | gain |
|---|---:|---:|---:|
| assignment | 0.04 ms | 0.03 ms | 1.3x |
| input pack | 3.15 ms | 1.01 ms | 3.1x |
| graph (GPU) | 3.62 ms | 2.24 ms | variance, out of scope |
| **decode** | **20.46 ms** | **0.55 ms** | **37.4x** |
| digest | 6.53 ms | 6.61 ms | 1.0x |
| **end-to-end** | **32.09 ms** | **10.92 ms** | **2.9x** |

Reported paired ratio at B=65,536 moved from **4.51x to 1.56x**.
`NATIVE_PAIRED crossover: none through B=65536` still holds.

---

# Part 2 — Correction: the paired ratio flatters HELUT by ~8x

## A claim in this repository's own analysis was wrong

An earlier draft of this receipt asserted that HELUT's digest hashed 12 bytes per
output *bit* while the native side hashed 8 bytes per *lane*, a "13.5x asymmetry
that only HELUT pays", and recommended aligning them for a projected 1.5x win.

**That was false.** Reading the generated testbench shows both sides compile from
one shared definition in the same Swift source:

- `orderedOutputDigest` (parallel path) and `scalarOutputReads` (scalar path)
  both emit `mix(&hash, lane); mix(&hash, wire); mix(&hash, value);` per output
  bit.
- `outputs` on the native side is `std::vector<uint32_t>` indexed
  `lane * kOutputCount + index` — the same flat lane-major layout HELUT now uses.

So the schemes are identical: **12 bytes per output bit, 7.08 MB hashed, on both
sides.** There is no asymmetry to remove. The proposed "win" did not exist.

## What the digest actually does to the comparison

The native harness times two things separately: `prepared` (its pack/assign/eval/
read) and `endToEnd` (`prepared` + digest). At B=65,536:

| | eval | digest | e2e | digest share |
|---|---:|---:|---:|---:|
| Verilator (16 workers) | **0.32 ms** | ~6.60 ms | 6.92 ms | **95%** |
| HELUT | 3.88 ms | 6.64 ms | 10.69 ms | 62% |

**Verilator's reported paired figure is 95% digest.** Its actual evaluation of
65,536 lanes across 16 workers takes 0.32 ms. The digest is a large shared
constant sitting on both sides, and it compresses the ratio from 12.1x to 1.56x.

## The contract says to exclude it

The pre-registered benchmark contract (narrated in the video series and quoted in
the test's own comments) specifies: *outputs consumed inside the timed region,
**then hashed outside it***. The PAIRED scope hashes **inside** the timed region.
That is a compliance gap, not a rounding detail — it is the difference between a
1.56x and a 12.1x reported result.

## Eval-only comparison (digest excluded symmetrically)

| lanes | HELUT work | Verilator eval | ratio | HELUT ns/lane | Verilator ns/lane |
|---:|---:|---:|---:|---:|---:|
| 4,096 | 2.14 ms | 0.066 ms | 32.7x | 26.9 | 16.0 |
| 16,384 | 2.50 ms | 0.126 ms | 19.9x | 25.5 | 7.7 |
| 32,768 | 3.03 ms | 0.192 ms | 15.7x | 26.4 | 5.9 |
| 65,536 | **3.88 ms** | **0.321 ms** | **12.1x** | 24.9 | 4.9 |

## No crossover exists in this scope, at any width

HELUT = ~2.2 ms fixed graph-submission cost (flat: 2.03 ms at B=4,096, 2.24 ms at
B=65,536) **plus ~25 ns/lane** of host marshalling.
Verilator = ~0 fixed **plus ~4.9 ns/lane**.

HELUT's *marginal* cost is about 5x the native marginal cost. A fixed cost only
amortizes when the marginal cost is lower; here it is higher, so the gap **widens**
with width rather than closing. The apparent convergence in the PAIRED rows is an
artifact of the shared digest constant and must not be read as the backends
approaching each other.

## Consequence for the optimization proposal

Optimizing the digest would have **removed a constant that was hiding a 12x
deficit**, while presenting as a benchmark win. It is the exact failure mode the
paired scope was built to prevent. Not done, and should not be done as a
performance measure.

## The real target, if a crossover is wanted

Get HELUT's per-lane host cost below the native per-lane eval cost. Current
split at B=65,536: pack 16.2 ns/lane, decode 8.4 ns/lane. Both are plausibly
reducible with bulk/vectorized writes. Even at zero, the ~2.2 ms fixed submission
cost means native wins until roughly 450,000 lanes, where memory becomes the
binding constraint (339 MiB resident at B=65,536).

## Boundaries

- One degree-1 cleartext combinational 8-bit ripple adder (14 mapped LUTs,
  0 DFFs) on one Apple M4 Max, 5 timed passes per point.
- Build, graph compile, allocation, thread creation, and cold specialization are
  excluded from steady medians on both sides.
- The paired sequential case (per-lane state) is still unbuilt.
- Part 1 is a harness improvement and says nothing about HELUT's engine, about
  encrypted throughput, or about any other circuit or host.
- The eval-only figures are derived from the test's existing
  `HELUT_PAIRED_PHASE_SAMPLES` and `VERILATOR_PAIRED_SAMPLES` output. No
  instrumentation was added to produce them.
