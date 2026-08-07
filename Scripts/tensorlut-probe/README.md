# HELUT / TensorLUT probe harness

CPU-side probes for the performance and correctness review in `REVIEW.md`
(`Digital-Defiance/HELUT` at commit `7a980a3`, rechecked after the fixes below).
No Metal required; everything runs on Linux or macOS with a C compiler and Python 3.
Run from a HELUT checkout so the netlist paths resolve.

The four correctness items are in the Swift sources: two-phase DFF commit in
`TensorLUTPipeline`, `$_SDFFCE_` enable-over-reset on the TensorLUT, cleartext,
and graph-compiler paths, fail-closed rejection of unknown cells and async resets,
and a full-key NTT bootstrap-key fingerprint. `helut_proposed_kernels.metal` remains
a spec for the unconfirmed performance kernels (wire-major layout, de Casteljau,
bit-sliced ticks, Montgomery/Shoup). Those are not in the live pipeline.

## Files

| File | What it does |
| --- | --- |
| `extract.py` | Flattens a Yosys JSON (`$lut` + `$_DFF*`/`$_SDFF*`/`$_SDFFE*`) into a plain netlist for the C tools, with Kahn levels |
| `harness.c` | Three evaluators on the same netlist: HELUT's 64-corner float kernel (lane-major), de Casteljau (wire-major), bit-sliced 64 lanes/word. Also in-place vs two-phase DFF commit, corner occupancy, output checksum |
| `harness_core.h` | Shared evaluator code (the part of `harness.c` before `main`), used by `relax.c` |
| `relax.c` | Mean-field MSE and L1 vs true expected bit error over 64 sampled binary circuits, for M melted LUTs |
| `emit_generic.py` | Vendor-neutral reverse emitter: Yosys JSON to plain Verilog (width-w localparams, Yosys DFF semantics incl. SDFFCE, fail-closed on unknown cells) |
| `br_math.c` | Montgomery and Shoup mulmod vs `%`; merged-twist negacyclic NTT without bit reversal; two-prime Garner CRT; end-to-end external product vs schoolbook mod 2^32 |
| `kcheck.c` | Transliteration checks for `helut_proposed_kernels.metal`: constant-leaf bit-sliced fold, DFF next-state formulas |
| `helut_proposed_kernels.metal` | Proposed MSL: two-phase DFF, wire-major de Casteljau level, fused bit-sliced multi-tick evaluator, Montgomery/Shoup. **Not compiled on Metal.** |
| `gadget.py` | E[d^2] for unsigned vs balanced gadget digits, B = 2, 4, 16, with exact mod-2^32 reconstruction check |
| `affine.py` | Share of LUTs that are affine over GF(2) (XOR/NOT/wire) per netlist, plus ANF degree histogram |
| `live.py` | Peak live wires along the topological order vs allocated wires |
| `netstat.py` | LUT width histogram, level count, DFF Q-to-D/E/R links per netlist |
| `portcert.py` | Port-weighted packing bound. `python3 portcert.py SIGMA netlist.json:K`. "does NOT clear" means the run fails whatever the per-wire gate prints |

## Commands

```sh
# netlist → C format
python3 extract.py Generated/Netlists/Enigma/enigma_m4_netlist.json enigma_m4_core m4.net
gcc -O3 -march=native -o harness harness.c -lm && ./harness m4.net 1024 72

# relaxation gap: M melted LUTs at p (or -1 for uniform random p)
gcc -O3 -march=native -o relax relax.c -lm && for M in 1 5 20 80; do ./relax m4.net $M 0.5; done

# LUT6 remap and round trip (needs yosys; `pip install yowasp-yosys` works)
yosys -p "read_verilog -sv Hardware/RTL/Enigma/enigma_m4_core.v; synth -top enigma_m4_core -flatten; abc -lut 6; write_json m4_lut6.json"
python3 emit_generic.py Generated/Netlists/Enigma/enigma_m4_netlist.json enigma_m4_core m4_roundtrip.v
yosys -p "read_verilog m4_roundtrip.v; synth -top enigma_m4_core -flatten; abc -lut 6; write_json m4_rt.json"
python3 extract.py m4_rt.json enigma_m4_core m4_rt.net && ./harness m4_rt.net 1024 72   # checksum must match

# blind-rotation arithmetic and kernel transliteration checks
gcc -O2 -march=native -o br_math br_math.c && ./br_math
gcc -O2 -o kcheck kcheck.c && ./kcheck

# statistics
python3 gadget.py
python3 affine.py Generated/Netlists/*/*.json
python3 live.py Generated/Netlists/Enigma/enigma_m4_netlist.json
python3 netstat.py Generated/Netlists/PicoRV32/picorv32_lut6_netlist.json
```

## Results recorded in the review (Enigma M4, 1,024 lanes × 72 ticks, seed 12345)

- In-place DFF commit, forward order: `linguistic_score` wrong in 9,266 / 73,728 lane-ticks; plaintext unaffected.
  After round-trip resynthesis the failing order flips to reverse.
- Output checksum, two-phase reference: `0010572068e524e1` for the checked-in LUT2 netlist, the LUT6 remap and the round trip.
- CPU throughput is a proxy only. Apple GPU ratios will differ.
- The `br_math` CPU timing line is not meaningful: the compiler folds `%` by a compile-time constant.

The Future-bank synthesis census used Yosys `techmap -dont_map $shiftx -dont_map $shift -dont_map $mul`;
see the review document for numbers.
