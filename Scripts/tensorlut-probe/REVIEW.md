# HELUT & TensorLUT — performance and correctness review

Sep 25, 2026 · @Jessica Mulein

## Summary

The largest wins are in TensorLUT and the Metal blind rotation, not the Welchman kernel. Four correctness bugs come first; one of them is a measured, scheduling-dependent race in the GPU flip-flop update. None of this touches a P1030680 claim: the campaign runs on the separate cleartext Welchman path.

Everything here was checked against the repo at commit `7a980a3` and the checked-in Yosys netlists. The sandbox is Linux with no Metal, so speedups are CPU proxies or arguments. Each row below says which.

## Since the review

30 September 2026. Five commits after `7a980a3` took the correctness row and the balanced digits. C70 stands: the full adder clears at k=7, log₂ε=−72.7, 8/8 PASS. That netlist has one noisy port, and its weight is 1, so it cannot show the failure below.

C71's −88.4 clear was the wrong event. The gate bounded P(|e| > kδ/2), which is the margin for decoding one wire's bit. A consumer LUT packs the refreshed native values with weights 2ⁱ. At k=7, a native error of 1 on any port of weight 4 or more lands in the wrong address. The trace is producer y=653, error 1,205,312, refreshed native 1, still the right bit, then consumer y=654 on its weight-32 port, address 24 instead of 19.

`portcert.py` is the preflight. At σ₉₅=637,757 the full adder is −99.4 and clears −64. PicoRV lut6 is +9.9 and does not. The circuit gate now fails closed on that port-weighted union, after the identity trials and before the netlist tick. Identity trials also histogram the refreshed native integer. The stride cap is 128, so LUT3 at k=127 fits in N=1024. That netlist has two receipts, both 2026-09-30, both with port-weighted log₂ε=−747.6 and every output and DFF Q matched. One all-zero stimulus, wall 3,816.8 s (`logs/c71-picorv-lut3-k127-balanced.log`). Four ticks with reset released on tick 4, wall 14,752.3 s (`logs/c71-picorv-lut3-k127-reset4.log`). Neither of those is a fetch. An eight-tick NOP on 2026-10-01 fetched `0x0` then `0x4`, same gate, wall 28,693.5 s (`logs/c71-picorv-lut3-k127-nop8.log`). That is a receipt, not a claim row, and not a store.

Rows 2–4 of the review (L1 fitness, native gather, the bit-sliced path) have not landed.

| # | Change | Effort | Expected effect | Evidence |
| --- | --- | --- | --- | --- |
| 1 | Two-phase DFF commit; honor `$_SDFFCE_`; fail closed on unknown cells and async resets; full BK cache key | Small | Removes a nondeterministic output and three silent mis-models | Race measured on Enigma M4 |
| 2 | Stop mutating and penalizing INIT padding; fitness MSE to L1 | Small | Melt optimizes the 8.5% of weights that exist; hedges stop being rewarded | Measured on Enigma M4 |
| 3 | Wire-major layout, de Casteljau kernel, bit-sliced Boolean path | Medium | 8.8x (float) and 56–407x (Boolean) per LUT-lane, CPU proxy | Measured on CPU |
| 4 | Keep `$shiftx`, `$shift`, `$mul` as native gather ops in the Future bank | Medium | About 18x fewer LUTs at BANK\_LANES=1 | Yosys census, see Verilog to tensor |
| 5 | Montgomery/Shoup reduction, full-core batching, no bit-reversal in blind rotation | Medium | Prime suspect for 0.42 s/BR; needs a Metal microbench | Code reading; mulmod verified in C |
| 6 | Balanced gadget digits | Small | 2.33x lower key-noise variance at B=4 | Measured digit statistics; noise effect predicted |
| 7 | Sampled mixed-strategy melt | Large | Exact relaxation, no lambda schedule | Theorem plus measured relaxation gap |

## Correctness findings

The GPU flip-flop update in `TensorLUTPipeline.soft_dff_update` races, and its result depends on thread order. The fix is the two-phase commit `CleartextNetlistSim` already uses. The other three findings are silent mis-models that should fail closed.

### 1. In-place DFF commit races

`soft_dff_update` reads D and writes Q in the same dispatch, one thread per flip-flop. When one flip-flop's D, enable or reset is another's Q, the reader may see the new value.

- Enigma M4 has `prev_plain_1 <= prev_plain_0` (5 direct Q→D links) and an enable driven by `letters_seen[1]` (2 links).
- Simulated in-place commit in forward order: `linguistic_score` wrong in 9,266 of 73,728 lane-ticks (12.6%). Reverse order: 0. After a round-trip resynthesis of the same design, the failing order flips (see Tensor to Verilog).
- `plaintext_char` is never affected, so the Fcrypto = 0 baseline stands.
- PicoRV lut6 has 15 Q→D and 68 Q→enable/reset links.
- The Future bank netlist lives in `build/`, not the repo, so it was not checked. Its four-surface parity is supporting evidence, not proof, because the race is order-dependent.

Fix: compute next-state into a `[batch, numDFFs]` scratch buffer, then commit in a second dispatch. Also add a compile-time count of Q→D/E/R links to the receipt so any future artifact records its exposure.

### 2. `$_SDFFCE_` ignores enable priority

For `$_SDFFCE_`, enable gates reset: with enable low, the cell holds even if reset is asserted. `parseYosysDFFPolarity` sets `clockEnableGatesReset`, and both `CleartextNetlistSim` and `EncryptedNetlistSim` honor it. `TensorLUTCompiler`, the Metal kernel and `TensorLUTEmitter` all apply reset first. PicoRV lut6 contains 40 such cells.

### 3. Unknown cells and async resets pass silently

- `TensorLUTCompiler.compile` skips any cell that is neither `$lut` nor a DFF type. A latch or `$_AND_` vanishes and its output net reads 0. `MuleinFutureTensorLUTEvaluator` checks cell types; the generic compiler does not.
- Async-reset types such as `$_DFF_PN0_` get no `syncReset`, so every path defaults to active-high reset-to-0. An active-low async reset would hold the design in reset. All current netlists use sync resets, so this is latent.

### 4. Sampled cache key on the NTT-domain bootstrap key

`MetalBRNTTEngine.fingerprint` hashes 32 sampled words of a key that is hundreds of megabytes. A different key sharing those words would reuse the stale NTT transform. Key it on a full hash, or on the key's identity from `TFHESamples`.

## The Nash lens: INIT floats as mixed strategies

Read each live INIT float as the probability that a truth-table bit is 1, and the melt becomes an exact relaxation with no soft cheats. Today's mean-field evaluation is a different object, and 91.5% of the melted genome does not exist. Both change how Phase 21's shatter should be explained, not whether it happened.

### 91.5% of the full-melt genome is padding

The M4 netlist comes from `abc -lut 2` (Makefile line 130): 594 LUT2, 330 LUT3, 1 LUT1. Unused inputs are tied to 0, so only the first 2ʷ INIT entries of each LUT can ever be weighted.

- Of 59,200 INIT floats, 5,018 are live and 54,182 are padding.
- Padding is still mutated (full rate, or 0.35× with `liveWidths`), still in λΣw(1−w), still in `nonBinaryCount`.
- At the 0.5 cold start, padding contributes about 13,546 to the penalty against about 1,254 from live weights.
- 1,089 live corners (21.7%) were never visited in 73,728 lane-ticks. Those are don't-cares.

So "tens of thousands of fractional weights left" after the squeeze is mostly padding. Remap with `abc -lut 6` and live weights rise to 51% (11,550 of 22,656).

### Why the mixed-strategy reading is exact

Let θⱼ be the probability that live bit j is 1, drawn independently once per circuit and held for all ticks. For any fitness F of a binary circuit b:

```latex
\mathbb{E}_\theta[F] = \sum_{b \in \{0,1\}^M} F(b) \prod_j \theta_j^{b_j} (1-\theta_j)^{1-b_j}
```

This is multilinear in θ, so its maximum over the cube sits at a vertex: the best relaxed point is a real circuit. Each truth-table bit is a player in a potential game with E\[F\] as the potential. Its pure Nash equilibria are exactly the circuits no single bit-flip improves.

### What mean-field TensorLUT computes instead

The kernel's formula is exact for one LUT with independent inputs. Reconvergent fanout and state feedback break independence, and MSE drops the output variance y(1−y). Measured on Enigma M4 with melted LUTs at p = 0.5, 256 streams × 72 ticks, 64 sampled circuits:

| LUTs melted | Mean-field MSE/bit | Mean-field L1/bit | True expected bit error |
| --- | --- | --- | --- |
| 1 | 0.192 | 0.378 | 0.191 |
| 5 | 0.225 | 0.444 | 0.323 |
| 20 | 0.248 | 0.492 | 0.486 |
| 80 | 0.248 | 0.492 | 0.491 |

MSE charges a hopeless 0.5 hedge half its real cost. Mean-field L1 overstates the damage of one melted LUT twofold. It is neither an upper nor a lower bound. Uniform-random p gave the same pattern.

### Fixes, cheapest first

1. Mutate, penalize and count only live entries. Emit padding as copies of the live sub-table.
2. Replace `diff * diff` with `abs(diff)` in `computeCryptoFitness`. For binary targets that is expected Hamming error at the outputs.
3. Make `soft_dff_update` a real multilinear cell: q' = e·d + (1−e)·q, instead of thresholding enable at 0.5 while D stays soft.
4. Score by sampling: 64 binary circuits per word, bit-sliced, with the same random draws for every child in a generation. λ becomes unnecessary.
5. Canonicalize output inversion before crossover. Inverting a LUT and remapping its consumers gives the same function, so parents can disagree by 2^(LUT count) equivalent encodings. This one is a hypothesis about shatter, not a measurement.

## TensorLUT on Metal

Most campaign TensorLUT work is Boolean: the frozen core, the involution sandwich and every Future bank receipt. A bit-sliced path runs that 56–349× faster per lane-tick on CPU, bit-exact. The float kernel gains from a factored formula, wire-major storage and one fused multi-tick dispatch.

### Measured on CPU (proxy for the Metal kernel's arithmetic)

Same stimulus: 1,024 lanes × 72 ticks of random ciphertext, two-phase DFF commit. All three evaluators agree on every plaintext and `linguistic_score` output, and the two mappings produce the same output checksum.

| Mapping | LUTs / levels | 64-corner float (lane-ticks/s) | de Casteljau float | Bit-sliced, 64 lanes/word |
| --- | --- | --- | --- | --- |
| `abc -lut 2` (checked in) | 925 / 169 | 21.5k | 189k (8.8×) | 7.5M (349×) |
| `abc -lut 6` | 354 / 47 | 63.0k | 98.0k (1.6×) | 3.5M (56×) |

On CPU the compiler vectorizes the 64-corner loop well, which is why LUT6 shows only 1.6×. Apple GPU ratios will differ; the ALU count per LUT-lane drops from about 770 operations to 2ʷ−1 interpolations either way.

### Kernel math

- **Factor the sum.** The 64-corner product sum equals folding one input at a time: v\[j\] = v\[2j\] + xₘ·(v\[2j+1\] − v\[2j\]). A width-w LUT needs 2ʷ−1 fused multiply-adds. Max difference over 200,000 random melted LUT6s: 4.8×10⁻⁷.
- **Bit-slice the Boolean case.** Pack 32 or 64 lanes per word and evaluate the same fold with bitwise selects. Constant truth-table leaves make the first fold level free, roughly halving LUT6 cost.
- **Stochastic melts reuse it.** The sampled mixed-strategy fitness runs on the same bit-sliced evaluator, with lanes as sampled circuits.

### Memory and dispatch

- **Wire-major storage.** Wires are stored `wires[lane * totalWires + w]`, so each thread's six reads land 4 × totalWires bytes apart: about 820 KB in the Future bank. `wires[w * batch + lane]` makes them coalesced.
- **Peak live state is tiny.** Enigma M4 needs at most 107 live wires (LUT2 mapping) or 96 (LUT6), against 988 or 417 allocated. A whole tick fits in registers or threadgroup memory. PicoRV lut6 peaks at 1,858 of 3,675.
- **One fused kernel.** The M4 core costs 169 dispatches per tick plus a commit-and-wait. A lane-per-thread kernel walks the netlist in topological order with no inter-level barriers.
- **Multi-tick on the GPU.** Inject from a `[tick, input]` buffer, sample into `[tick, output]`, loop inside the kernel, and let each lane exit when `result_valid` is set.

### Why the Future bank will feel it

Receipts per second stay flat (233, 265, 276, 274, 231) while the graph grows from 45k to 758k LUT6 across bank widths 1–16. Per-tick cost therefore scales with LUT count: the bank is bound by LUT evaluation, not host overhead. Every change above lands directly on receipts per second.

## Verilog to tensor lowering

The Future bank spends most of its LUT fabric on array indexing. Yosys turns every dynamic part-select into a mux tree; on a GPU each is one indexed load. Keeping those cells native cuts BANK\_LANES=1 from 45,463 LUT6 to 2,456.

### Where the Future bank's LUTs come from

Census after `proc; flatten; memory; opt`, before `techmap`, at BANK\_LANES=1:

- One `$shiftx` over 10,400 bits: the `step_rows` read, S\_t(x) at `(t*130)+(x*5)`.
- 16 more `$shiftx` (130, 26, 200, 280 bits) and 22 `$shift` (130, 40, 26 bits): reads and writes of `live_values` and the edge tables.
- 13 `$mul_32` from `letter * 5` index arithmetic.

| Flow at BANK\_LANES=1 | Gate cells after techmap | LUT6 after `abc -lut 6` |
| --- | --- | --- |
| As in the Makefile | 117,324 (106,996 are 2:1 muxes) | 45,463 (reproduced; matches the journal) |
| `$shiftx` kept native | 25,527 | not run |
| `$shiftx`, `$shift`, `$mul` kept native | 17,111 + 52 native ops | 2,456 + 52 native ops |

`$shiftx` alone accounts for 78% of the gates. Yosys 0.69 reproduces the journal's 45,463 LUT6 and 693 DFF exactly, so the 18.5× ratio is like for like.

### What the tensor IR needs

1. A `gather(bus, index, width)` op for `$shiftx`, a masked `insert` for `$shift` writes, and constant multiply as shift-add. Produce them with `techmap -dont_map $shiftx -dont_map $shift -dont_map $mul`.
2. A lane-major word layout for bus ops beside the bit-sliced layout for LUT fabric. A 64×64 bit-matrix transpose between them costs about 6 × 64 word operations.
3. `step_rows` is stable per setting lane, so store it as 80 × 26 bytes. Each read becomes one byte load instead of a 10,400-input mux.

### Clock economy

On a GPU every tick costs the whole netlist, so the quantity to minimize is ticks × LUTs per tick. The closure FSM handles one edge per clock, which suits an FPGA and taxes a GPU. Receipts already carry `result_cycle_counts`; that gives the tick budget to trade against unrolling one full propagation pass per tick.

### Pick the mapping by backend

| Backend | Cost it pays | Best mapping | Evidence |
| --- | --- | --- | --- |
| Per-level float kernel (today) | Dispatches and LUT count | `abc -lut 6` | M4: 169 → 47 levels, same outputs |
| Fused bit-sliced kernel | Bitwise operations | Small LUTs or an AND/XOR graph | M4 LUT2 ran 2.1× faster per tick than LUT6 |
| Encrypted (Path B) | Blind rotations | Fewest non-affine LUTs | Affine LUTs: ripple4 and toy\_isa 64%, csa4 50%, M4 16%, PicoRV lut6 2.5% |

Affine LUTs are the research lead on the FHE side. Folding them into a consumer's bootstrap address could remove a blind rotation each, within the message space the stride allows.

## Tensor to Verilog

A vendor-neutral emitter closes the loop: Yosys JSON to plain Verilog, back through Yosys, back to tensors, same outputs. The prototype `emit_generic.py` does this for Enigma M4 with an identical output checksum (`0010572068e524e1`) over 73,728 lane-ticks.

### What `TensorLUTEmitter` does today

- Instantiates Xilinx `LUT6` primitives, so re-ingest needs a vendor simulation model.
- Thresholds all 64 INIT floats, including padding. Padding bits come out arbitrary, so two emits of the same function can differ.
- Wraps enable, then reset, for every flip-flop. That is wrong for `$_SDFFCE_`.
- Declares one `wire [totalWires-1:0] n` whose unused bits are undriven.

### What the prototype does instead

- Each LUT becomes a width-w `localparam` indexed by its live inputs. No primitive, no padding.
- Flip-flops follow Yosys semantics per type, including enable-over-reset for `$_SDFFCE_`.
- Any cell type it does not know stops the emit with an error.

Round trip on Enigma M4: 925 LUT2/3 in, emitted, resynthesized with `abc -lut 6` to 405 LUT6 in 50 levels, same checksum.

The round trip also re-ordered the flip-flops, and the DFF race flipped direction. In the original netlist, forward commit order corrupts `linguistic_score`; in the resynthesized one, reverse order does, again 9,266 lane-ticks. Same design, opposite failing order: that is what order-dependence looks like.

### For melted designs

1. Canonicalize before thresholding: copy the live sub-table into padding, so INIT diffs mean function changes.
2. Carry the never-visited corners (21.7% of live entries on M4 LUT2, 50.8% on LUT6) as don't-cares into resynthesis.
3. Grade every emit with a fixed-point test: emit, resynthesize, re-ingest, compare against the frozen reference on a fixed stimulus.

## Blind rotation on Metal

The prime suspect for 0.42 s per blind rotation is arithmetic. Every modular multiply in `helut_blind_rotate_ntt_tile` is `(ulong)a*(ulong)b % (ulong)p`, a 64-bit remainder by a runtime prime. On top of that, one rotation uses one of 40 GPU cores, and the covering gadgets pay for a third prime they don't need.

### Changes, all verified bit-exact in C

| Change | What it removes | Check |
| --- | --- | --- |
| Montgomery multiply for the key pointwise product (key stored in Montgomery form); Shoup for twiddles, twist and 1/N | Every 64-bit `%` in the kernel: four 32-bit multiplies instead | 0 mismatches vs `%` over 10M pairs, each of the 3 primes |
| Twist merged into butterflies; Cooley–Tukey forward, Gentleman–Sande inverse, pointwise in bit-reversed order | Every `bitrev_plane` call (2 barriers each) and N twist multiplies per transform | 0 of 1,024 coefficients differ from schoolbook |
| Two primes instead of three when the exact result fits | One third of all NTTs; CRT becomes one Garner step, and mod 2³² is the low word | Same end-to-end check at B=4, ℓ=16, N=1024 |

The bit-reversal cost is not small. At ℓ=16 each CMux runs 2ℓ+2 three-prime transforms, each with three `bitrev_plane` calls: 204 barriers per CMux spent only on permutation.

### When two primes are enough

The exact negacyclic coefficient of the summed external product is bounded by 2·2ℓ·N·(B−1)·2³², two-sided. The first two primes give 2^61.66.

| Gadget | CRT range needed | Primes |
| --- | --- | --- |
| covering-b1 (B=2, ℓ=32) | 2^49.0 | 2 |
| covering-b2 (B=4, ℓ=16) | 2^49.6 | 2 |
| covering-b4 (B=16, ℓ=8) | 2^50.9 | 2 |
| B=2¹⁶, ℓ=2 | 2^61.0 | 2 (0.66-bit margin; centered key coefficients add 1 bit) |
| baseLog 32, ℓ=1 | 2^76.0 | 3 |

### Occupancy and bandwidth

- **One core per rotation.** `blindRotate` dispatches one threadgroup of N threads. Put all rotations of a level, and all SING rows, into one dispatch.
- **Share the key.** Run those accumulators in lockstep over the LWE bits so each key load serves all of them. At ℓ=16 the NTT-domain key is about 805 MB per rotation with three primes, 537 MB with two.
- **Idle half.** Every butterfly stage runs under `if (k < n/2)`, so 512 of 1,024 threads wait. Use 512 threads with two coefficients each, or radix-4 in registers with `simd_shuffle` for strides under 32.
- **Small items.** Digits already below p still get `% pA`. Digits and results round-trip through device `scratch` instead of registers.

Apple GPUs have no hardware 64-bit divide, so the `%` should be expensive. Confirm with a microbenchmark before the rewrite: 10⁸ dependent multiplies, `%` against Montgomery, on the M4 Max. The CPU comparison is meaningless here because the compiler folds `%` by a constant.

### Balanced gadget digits

Both the CPU path (`TFHEGGSW.swift` line 469) and Metal use unsigned digits in \[0, B). Balanced digits in \[−B/2, B/2) reconstruct exactly mod 2³² and shrink the digit second moment that multiplies key noise:

| B | E\[d²\] unsigned | E\[d²\] balanced | Variance ratio |
| --- | --- | --- | --- |
| 2 | 0.50 | 0.50 | 1.0 (non-adjacent form gives about 1.5) |
| 4 | 3.50 | 1.50 | 2.33 |
| 16 | 77.5 | 21.5 | 3.60 |

If key noise dominates the covering-b2 budget, log₂ε scales by roughly that ratio in the Gaussian regime. C57 at stride k=7 would move from −60.5 toward about −140, clearing −64 without k=14. This is a prediction: it needs checking against the covering proof and the noise certificate first.

Longer term, a prime ciphertext modulus instead of 2³² removes CRT entirely, at the cost of recalibrating the hardness table.

## Drop-in code

`helut_proposed_kernels.metal` holds four proposed kernels. None has been compiled on Metal. Each one's logic was transliterated to C and checked, so port them as a spec and grade against the existing Swift references.

| Kernel | Replaces | Check in C |
| --- | --- | --- |
| `dff_next_state` + `dff_commit` | `soft_dff_update` | 0 of 128 mismatches vs Yosys SDFF, SDFFE, SDFFCE, exhaustive |
| `tensor_lut_level_dc` | `tensor_lut6_eval_level` | Same fold as `harness.c`; max 4.8×10⁻⁷ vs 64-corner sum |
| `tensorlut_bitsliced_ticks` | Level-by-level Boolean ticks | Constant-leaf fold: 0 of 200,000 mismatches |
| `mont_mul`, `shoup_mul` | 64-bit `%` in `mod_mul` | 0 of 10M mismatches per prime |

### Two-phase DFF with SDFFCE and soft enable

The struct gains `enableGatesReset`, so `TensorDFFCell` grows from 28 to 32 bytes and its Swift stride precondition changes. Enable and reset become multilinear, matching the LUTs, instead of thresholding at 0.5:

```metal
if (f.enableGatesReset != 0) {            // $_SDFFCE_: enable has priority
    next = e * (r * rv + (1.0f - r) * d) + (1.0f - e) * q;
} else {                                  // $_SDFF_ / $_SDFFE_: reset has priority
    next = r * rv + (1.0f - r) * (e * d + (1.0f - e) * q);
}
qNext[i * batch + lane] = next;          // commit in a second dispatch
```

### Width-aware fold, wire-major

```metal
uint n = 1u << uint(r.width);
for (uint k = 0; k < n; ++k) v[k] = t[k];
for (int m = 0; m < r.width; ++m) {
    float x = wires[uint(ins[m]) * batch + lane];
    n >>= 1;
    for (uint k = 0; k < n; ++k) v[k] = fma(x, v[2 * k + 1] - v[2 * k], v[2 * k]);
}
wires[uint(r.outWire) * batch + lane] = v[0];
```

### Montgomery and Shoup

Store the NTT-domain key as key·2³² mod p, so `mont_mul` returns the standard-form product. Twiddles, twist and 1/N are constants: store `wq = floor(w·2³²/p)` beside each.

```metal
inline uint mont_mul(uint a, uint b, uint p, uint pinv) {   // pinv = -p^-1 mod 2^32
    uint lo = a * b, hi = mulhi(a, b);
    uint m  = lo * pinv;
    uint t  = hi + mulhi(m, p) + (lo != 0u ? 1u : 0u);      // < 2p since p < 2^31
    return t >= p ? t - p : t;
}
inline uint shoup_mul(uint a, uint w, uint wq, uint p) {
    uint q = mulhi(a, wq);
    uint r = a * w - q * p;                                  // exact, in [0, 2p)
    return r >= p ? r - p : r;
}
```

The fused bit-sliced kernel is too long to inline here. It runs 32 lanes per thread through the whole netlist in topological order for T ticks, injects and samples through buffers, and commits flip-flops in two phases per thread. Each thread owns its lanes, which removes the race by construction.

## Reproduce

Every number in this review comes from the `helut-probe` files delivered with it. They need a C compiler, Python 3 and, for synthesis, Yosys (`pip install yowasp-yosys` works). Run them from a HELUT checkout.

| Claim | Command | Expected |
| --- | --- | --- |
| DFF race, evaluator agreement, throughput, padding share | `./harness m4.net 1024 72` | 9,266 forward-order mismatches; checksum `0010572068e524e1` |
| Relaxation gap | `./relax m4.net M 0.5` for M = 1, 5, 20, 80 | The Nash-lens table |
| LUT6 remap and round trip | Yosys `abc -lut 6`, `emit_generic.py`, re-extract, `./harness` | Same checksum; race order flips |
| Blind-rotation arithmetic | `./br_math` | 0 mismatches on every check |
| Kernel transliteration | `./kcheck` | 0 of 200,000 and 0 of 128 |
| Gadget digit moments | `python3 gadget.py` | 3.50 → 1.50 at B=4 |
| Affine LUT share, liveness, DFF links | `affine.py`, `live.py`, `netstat.py` | Numbers as quoted above |
| Future bank census | Yosys flow with `techmap -dont_map $shiftx -dont_map $shift -dont_map $mul` | 17,111 gates; 2,456 LUT6 after ABC |

The README in the probe folder lists every command in full. All stimulus uses fixed seeds, so reruns match exactly.
