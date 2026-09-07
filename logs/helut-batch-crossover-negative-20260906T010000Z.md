# Receipt: the cleartext batch crossover does not exist

**Date:** 2026-09-06
**Host:** Apple M4 Max / macOS 26.6.2
**Question:** HELUT's graph cost looked flat with batch width while native
simulation grows linearly. Does HELUT therefore win at some large enough B?
**Answer:** No. Not at any width, for this circuit class.

This is a pre-registered negative result. It closes the "just go wider" argument
with data rather than leaving it as an open hedge.

---

## Why the question was live

On the 8-bit ripple adder (14 mapped LUTs) HELUT's steady graph time barely moved
across a 32x range of batch width:

| B | graph steady median |
|---:|---:|
| 4,096 | 2.03 ms |
| 32,768 | 2.16 ms |
| 65,536 | 2.23 ms |
| 131,072 | 2.52 ms |

Fitting fixed + linear over that range gives **~2.01 ms fixed and ~0.004 ns/lane**
— a marginal cost of about 4 picoseconds per lane. Against a native baseline that
costs ~4.9 ns/lane, that shape implies a crossover somewhere around 450,000 lanes.

The banked 8-bit artifact cannot test it: 17 declared input bits caps
distinct-lane verification at 2^17 = 131,072
(`--bench-distinct-lanes failed: requested 262144 lanes but only 131072 distinct
assignments exist`).

## Method

Authored a behavioural 12-bit ripple adder with HELUT's `in_<k>` / `out_<k>` port
convention, synthesized through the identical flow as the banked artifact
(`proc; flatten; opt; techmap; opt; abc -lut 6; opt_clean`). Result: **19 `$lut`
cells, 0 DFFs, 25 declared input bits**, so the distinct ceiling rises to
2^25 = 33,554,432 lanes.

```bash
python3 gen.py 12 && yosys -q -s flow.ys
.build/release/helut-bench --bench resynth.json --bench-module ripple_adder \
  --degree 1 --batch <B> --ticks 6 --warmup 1 --bench-distinct-lanes
```

Every width verified exhaustively: distinct inputs per lane, all output bits
checked against per-lane clear oracles, `mismatches=0`, `result=PASS`.

## Result: the graph is not flat, it was under-occupied

12-bit adder, 19 LUTs, distinct-lane verified:

| B | graph steady | Δ over previous | marginal ps/lane | checked bits | mismatches |
|---:|---:|---:|---:|---:|---:|
| 65,536 | 3.195 ms | — | — | 851,968 | 0 |
| 262,144 | 3.864 ms | 0.669 ms | 3.4 | 3,407,872 | 0 |
| 524,288 | 6.800 ms | 2.936 ms | 11.2 | 6,815,744 | 0 |
| 1,048,576 | **14.002 ms** | 7.202 ms | **27.5** | 13,631,488 | 0 |

The marginal cost **accelerates**: 3.4 → 11.2 → 27.5 ps/lane. From 524,288 to
1,048,576 the graph time roughly doubles, i.e. the GPU has become fully linear.

At B=1,048,576 the graph alone costs **13.4 ns/lane**.

## Why that settles it

The crossover argument required HELUT's marginal cost to stay below the native
marginal cost so its fixed overhead could amortize. It does not.

- HELUT asymptotic: **~13.4 ns/lane** (graph only, before any host marshalling).
- Native measured: 4.9 ns/lane at B=65,536 on the 14-LUT adder, **and still
  falling** at that point (16.0 → 7.7 → 5.9 → 4.9 as width grew), so its true
  asymptote is lower still. Scaling by LUT count for the 19-LUT circuit gives a
  generous ~6.7 ns/lane.

So HELUT's asymptotic per-lane cost is roughly **2x the native per-lane cost**,
and native carries essentially no fixed cost. There is no width at which HELUT
wins, and the ratio stops improving once both are linear.

The apparent flatness below ~262,144 lanes was the GPU being under-occupied while
a ~2-3 ms fixed submission cost dominated. That is not a scaling property.

## Regimes

1. **B < ~100K** — HELUT dominated by fixed graph-submission cost (~2-3 ms).
   Native wins by a wide margin.
2. **B ~ 262K-524K** — HELUT's graph begins growing. Native still wins.
3. **B >= ~1M** — Both linear. HELUT ~13.4 ns/lane vs native ~5-7 ns/lane.
   Native wins by ~2x, and the ratio is now roughly constant.

Native wins in every regime.

## Cost of going wider, for the record

At B=1,048,576: resident memory **6,022 MiB**, host verification 2.458 s (outside
the timed region), first graph run 0.123 s. Memory is not the binding constraint
below ~1M lanes on a 64 GB host; the per-lane graph cost is.

## What this means for the project

The batch axis should not be sold as a throughput win for cleartext simulation.
It is not one, at any width, and this receipt is the reason.

What the batch axis is actually for is unchanged and unaffected:

- it is the same representation the **encrypted** path evaluates, where no native
  simulator competes at all; and
- it is a **searchable** representation (melt/freeze/prove), which has no native
  equivalent — see `logs/helut-melt-scaling-20260905T225142Z.log`.

Removing a performance claim the project never needed makes those two easier to
state cleanly.

## Boundaries

- Two cleartext combinational ripple adders (14 and 19 mapped LUTs) at degree 1
  on one Apple M4 Max. Sequential designs, wider logic, and other hosts are
  untested.
- HELUT figures are steady graph medians over 6 trials with 1 warmup; the first
  graph run is excluded and reported separately.
- The native comparison at B > 131,072 is a **projection** from measured 8-bit
  rates scaled by LUT count, not a measurement. It is generous to HELUT: native's
  measured rate was still falling where it was last observed.
- This says nothing about encrypted throughput, about melt/freeze, or about the
  `NATIVE_BASELINE` asymmetric scope.
