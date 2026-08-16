# Reproduce

**Bar for public science:** if we assert it, someone else can re-run it from this file (or we mark it open in [`directives/claim-sheet.md`](directives/claim-sheet.md)).

Discovery after disclosure: [`directives/research-trajectory.md`](directives/research-trajectory.md).  
Parameters: [`directives/parameter-cookbook.md`](directives/parameter-cookbook.md).  
Packaging: [`directives/packaging-roadmap.md`](directives/packaging-roadmap.md).

Preferred tools (binary split — umbrella `helut` still accepts the same flags):

| Tool | Role |
|------|------|
| `.build/release/helut-bench` | SING / micro / `--measure-bk-noise` / `--hardness-table` |
| `.build/release/helut-e256` | Enigma256 SoftBus / TensorLUT melt flags |
| `.build/release/helut-bombe` | Welchman / hybrid / campaign |
| `.build/release/helut-compile` | `--validate` |
| `.build/release/helut` | Umbrella shim |

Commands assume macOS Apple Silicon, Swift 6.3+, repo root after:

```bash
swift build -c release
```

## Documents

```bash
make writeup    # writeup.tex → writeup.pdf + writeup.md
make paper      # paper/helut.tex → paper/helut.pdf + paper/helut.md
make textbook   # textbook/helut-living-textbook.tex → pdf + md
make docs       # all three (needs latexmk + pandoc)
```

## Hardness / estimator (**C23**, **H1**)

```bash
.build/release/helut --hardness-table | tee logs/helut-hardness.txt
.build/release/helut --estimator-export > logs/helut-estimator-pending.json
./Scripts/helut_sage_estimate.sh
```

Native SageMath 10.9 lives at `~/Applications/SageMath-10-9.app` (3-manifolds arm64 `.app`; no sudo pkg). The runner finds that path, installs `lattice-estimator`, and writes `logs/helut-estimator-results.json`. Docker qemu amd64 is refused (FLINT SIGILL).

Production `prod-n1024-s16`: HELUT 175.7 vs estimator **180.2** (|Δ|=4.5). Four of eight anchors sit outside the 16-bit merge tolerance — do not quote 176 as estimator cost on every row (**H1**).

## Encrypted ≡ clear (C4–C6) — envelope *N*≤128 (**H2**)

```bash
# Fast multi-netlist SING (CPU)
.build/release/helut --bench netlist.json --degree 8 --bench-encrypted --cpu-only --sing --vectors 8
.build/release/helut --bench tree_netlist.json --degree 8 --bench-encrypted --cpu-only --sing --vectors 256
.build/release/helut --bench regex_netlist.json --degree 8 --bench-encrypted --cpu-only --sing --vectors 32

# Or
./Scripts/helut_encrypted_sing.sh

# Public-MS boolean @ N=128 (within envelope)
.build/release/helut --bench netlist.json --degree 128 --bench-encrypted --cpu-only --vectors 8 \
  --paths 'blind-rotate public-ms boolean'
```

Expect `result PASS` and certificate lines. full_adder multi-LUT SING is graded through *N*=1024 (H2 closed 2026-08-12).

## Encrypted sequential DFF (C38)

Host-clocked encrypted *Q* (not fused metal-netlist). Toy `stateful_counter`: 6 `$lut` + 4 DFFs. Not PicoRV32.

```bash
.build/release/helut --bench counter_netlist.json --degree 8 \
  --bench-encrypted --cpu-only --sing --vectors 8
.build/release/helut --bench counter_netlist.json --degree 1024 \
  --bench-encrypted --sing --vectors 4 \
  --paths 'blind-rotate-metal public-ms boolean' \
  | tee logs/helut-encrypted-n1024-metal-sing-counter.log
```

Metal receipt: **PASS** 15.88 s / 4 rows (3.97 s/row), *N*=1024 public-ms boolean.

## Encrypted E256 1-round scramble (C39)

Frozen offsets=0, identity plug. Algebraic sboxes + UKW (`e256_round1.v`). LUT4 netlist — CPU needs `--degree 16`. Not live BRAM / NLFF / `enigma_256_core`.

```bash
yosys -p "read_verilog e256_round1.v; synth -top e256_round1 -flatten; abc -lut 4; write_json e256_round1_netlist.json"
.build/release/helut --bench e256_round1_netlist.json --degree 16 \
  --bench-encrypted --cpu-only --sing --vectors 32 \
  --paths 'blind-rotate public-ms boolean'
.build/release/helut --bench e256_round1_netlist.json --degree 1024 \
  --bench-encrypted --sing --vectors 2 \
  --paths 'blind-rotate-metal public-ms boolean' \
  | tee logs/helut-encrypted-n1024-metal-sing-e256-round1.log
```

Metal receipt: **PASS** 22.77 s / 2 (11.38 s/row).

## Encrypted toy ISA (C40)

4-bit ACC, `NOP` / `ADD imm`. Not PicoRV32.

```bash
yosys -p "read_verilog toy_isa.v; synth -top toy_isa -flatten; abc -lut 2; write_json toy_isa_netlist.json"
.build/release/helut --bench toy_isa_netlist.json --degree 8 \
  --bench-encrypted --cpu-only --sing --vectors 32
.build/release/helut --bench toy_isa_netlist.json --degree 1024 \
  --bench-encrypted --sing --vectors 4 \
  --paths 'blind-rotate-metal public-ms boolean' \
  | tee logs/helut-encrypted-n1024-metal-sing-toy-isa.log
```

Metal receipt: **PASS** 20.31 s / 4 (5.08 s/row).

## Metal microbench (C7)

```bash
.build/release/helut --bench-encrypted-micro --degree 64 --trials 2 --warmup 1 \
  | tee logs/helut-encrypted-micro-n64.log
```

Published number: ~50.3 s/BR @ *N*=64 fused MPSGraph (**C7**). Current NTT persist BR (**C18**): **0.433 s/BR** @ *N*=1024, bits 0 and 1 PASS (`ring=ntt`). Persist-schoolbook (**C17**) was 0.519 s/BR. Fused-EP (**C16**) was 1.043 s/BR. Fused schoolbook-in-MPSGraph at *N*=1024 **did not finish** (11.6 h). Default at *N*>64 is `tiled-kernel` with inlined NTT:

```bash
make test-metal-p1 2>&1 | tee logs/helut-ntt-cert.log
.build/release/helut --bench-encrypted-micro --degree 1024 --trials 2 --warmup 1 \
  | tee logs/helut-encrypted-micro-n1024-ntt.log
.build/release/helut --bench-encrypted-micro --degree 64 --trials 2 --warmup 1 --metal-br-tile 64 \
  | tee logs/helut-encrypted-micro-n64-ntt.log
```

Metal full_adder SING per-LUT (**C20** wavefront-parallel NTT): boolean **10.6 s / 8 rows** (beats **C17** 12.2 s). Crypto ℓ=2 (**C21**): **11.38 s / 8**. Legacy fused megagraph is `--metal-br-fused` only.

```bash
.build/release/helut --bench netlist.json --degree 1024 --bench-encrypted --sing --vectors 8 \
  --paths 'blind-rotate-metal public-ms boolean' \
  | tee logs/helut-encrypted-n1024-metal-sing-par.log
.build/release/helut --bench netlist.json --degree 1024 --bench-encrypted --sing --vectors 8 \
  --paths 'blind-rotate-metal public-ms crypto' \
  | tee logs/helut-encrypted-n1024-metal-sing-crypto.log
.build/release/helut --bench netlist.json --degree 1024 --bench-encrypted --sing --vectors 8 \
  --metal-netlist-only \
  | tee logs/helut-encrypted-n1024-metal-netlist-sing.log
```

Measured noisy BK (**C22**). Covering gadget only (`cryptoPublicMS` / `.crypto`); ℓ=1 `booleanPublicMS` cannot carry BK noise.

```bash
.build/release/helut --measure-bk-noise --degree 8 --trials 8 --bk-noise 64 \
  | tee logs/helut-noisy-bk-measure.log
.build/release/helut --measure-bk-noise --degree 128 --trials 4 --bk-noise 64 \
  | tee logs/helut-noisy-bk-measure-n128.log
swift test -c release --filter 'TFHESeamTests/testNoisyBKIdentityMeasurement'
swift test -c release --filter 'TFHESeamTests/testEncryptedNetlistFullAdderWithNoisyBK'
```

Product-shaped *N*=1024 residual (**C26**, H4 graded negative — not a production depth close):

```bash
.build/release/helut --measure-bk-noise --degree 1024 --trials 2 --bk-noise 64 \
  | tee logs/helut-noisy-bk-measure-n1024.log
.build/release/helut --measure-bk-noise --degree 1024 --trials 2 --bk-noise 4 \
  | tee -a logs/helut-noisy-bk-measure-n1024.log
```

Expect: noiseless *B*=0; inject *B*=64 undecodable; *B*=4 on `.crypto` may be ∞-norm OK with εlog2≈−1 (not −64).

## Exact public-MS covering (C27)

Why covering noisy BK works at *N*=8/128 but not as `cryptoPublicMS` at *N*=1024 under *q*=2³²:

```bash
swift test -c release --filter testGGSWPublicMSCoveringCertificate
```

Statement: [`directives/ggsw-public-ms-covering.md`](directives/ggsw-public-ms-covering.md). Exact degrees among {8…2048}: **{8, 128}** only — for *any* power-of-two word *w* (**C29**), not just *q*=2³².

## Track B ε vs inject B (C30)

```bash
for B in 1 2 4 8 16 32 64; do
  .build/release/helut --measure-bk-noise --degree 128 --trials 8 --bk-noise $B
done | tee logs/helut-noisy-bk-eps-sweep-n128.log
```

Expect: residual amp large even at *B*=1; printed εlog2 ≈ −24 only at *B*=64.

## Incomplete public-MS gap + Track A approx (C31 / C32)

```bash
swift test -c release --filter testGGSWIncompleteCoveringCertificate
.build/release/helut --measure-bk-noise --degree 1024 --trials 4 --bk-noise 1 \
  | tee logs/helut-noisy-bk-measure-n1024-B1.log
.build/release/helut --measure-bk-noise --degree 1024 --trials 4 --bk-noise 2 \
  | tee -a logs/helut-noisy-bk-measure-n1024-B1.log
```

Expect: uncoveredBits(1024)=10; `cryptoPublicMS` *B*≥1 undecodable; `.crypto` *B*=1 εlog2≈−8.4 at 8 trials.
Statement: [`directives/ggsw-incomplete-covering.md`](directives/ggsw-incomplete-covering.md).

## Track A Metal covering-crypto SING with noisy BK (C33)

```bash
.build/release/helut --bench netlist.json --degree 1024 \
  --bench-encrypted --sing --vectors 2 --bk-noise 1 \
  --paths 'blind-rotate-metal secret crypto' \
  | tee logs/helut-encrypted-n1024-metal-sing-covering-crypto-noisy-B1.log
.build/release/helut --bench netlist.json --degree 1024 \
  --bench-encrypted --sing --vectors 2 --bk-noise 1 \
  --paths covering-crypto \
  | tee logs/helut-encrypted-n1024-metal-sing-covering-publicms-noisy-B1.log
```

Expect PASS on both; non-zero decodable *B*<sub>bk</sub>. Not `cryptoPublicMS`.

## Track A covering-b4: ε≤2⁻⁶⁴ + Metal SING (C34)

```bash
.build/release/helut --measure-bk-noise --degree 1024 --trials 8 --bk-noise 1 \
  --covering-base-log 4 | tee logs/helut-noisy-bk-covering-b4-n1024-B1.log
.build/release/helut --bench netlist.json --degree 1024 \
  --bench-encrypted --sing --vectors 2 --bk-noise 1 \
  --paths covering-b4 \
  | tee logs/helut-encrypted-n1024-metal-sing-covering-b4-noisy-B1.log
```

Expect: εlog2 ≈ −913 (≪ −64); Metal secret + public-ms covering-b4 PASS.
Finer covering cuts EP β: baseLog 8→4 drops σ̂ ~10× (`--covering-sweep`).

## Track A covering-b2: ε≤2⁻⁶⁴ through B=16 + Metal SING (C35)

```bash
.build/release/helut-bench --measure-bk-noise --degree 1024 --trials 4 --bk-noise 16 \
  --covering-base-log 2 | tee logs/helut-noisy-bk-covering-b2-n1024-B16.log
# full ε vs B: see logs/helut-noisy-bk-covering-b2-eps-vs-B.log
.build/release/helut-bench --bench netlist.json --degree 1024 \
  --bench-encrypted --sing --vectors 2 --bk-noise 16 \
  --paths covering-b2 \
  | tee logs/helut-encrypted-n1024-metal-sing-covering-b2-noisy-B16.log
```

Expect: εlog2 ≈ −65.4 at *B*=16 (≤ −64); *B*=32 ≈ −40 (fails bar); Metal secret + public-ms covering-b2 PASS.

## Track A covering-b1: ε≤2⁻⁶⁴ through B=32 + Metal SING (C36)

```bash
.build/release/helut-bench --measure-bk-noise --degree 1024 --trials 4 --bk-noise 32 \
  --covering-base-log 1 | tee logs/helut-noisy-bk-covering-b1-n1024-B32.log
# ladder: logs/helut-noisy-bk-covering-b1-eps-vs-B.log
.build/release/helut-bench --bench netlist.json --degree 1024 \
  --bench-encrypted --sing --vectors 2 --bk-noise 32 \
  --paths covering-b1 \
  | tee logs/helut-encrypted-n1024-metal-sing-covering-b1-noisy-B32.log
```

Expect: εlog2 ≈ −139 at *B*=32 (≤ −64); *B*=64 ≈ −26 (fails); *B*=128 ≈ −0.6 (fails, no unlock vs b2); Metal PASS.

## Track A Gaussian BK inject covering-b1 (C37)

```bash
.build/release/helut-bench --measure-bk-noise --degree 1024 --trials 4 \
  --bk-noise-sigma 24 --covering-base-log 1 \
  | tee logs/helut-noisy-bk-covering-b1-gauss-sigma24.log
.build/release/helut-bench --bench netlist.json --degree 1024 \
  --bench-encrypted --sing --vectors 2 --bk-noise-sigma 24 \
  --paths covering-b1 \
  | tee logs/helut-encrypted-n1024-metal-sing-covering-b1-gauss-sigma24.log
```

Expect εlog2 ≈ −159 at σ=24; Metal PASS. Torus σ=128 at *N*=1024 still undecodable.

## Track A param map: σ=128 covering-b1 at N≤512 (C41)

```bash
.build/release/helut --measure-bk-noise --degree 256 --trials 2 \
  --bk-noise-sigma 128 --covering-base-log 1
.build/release/helut --measure-bk-noise --degree 512 --trials 4 \
  --bk-noise-sigma 128 --covering-base-log 1 \
  | tee logs/helut-noisy-bk-covering-b1-gauss-sigma128-N256-N512.log
.build/release/helut --bench netlist.json --degree 512 \
  --bench-encrypted --sing --vectors 2 --bk-noise-sigma 128 \
  --paths covering-b1 \
  | tee logs/helut-encrypted-n512-metal-sing-covering-b1-gauss-sigma128.log
```

Expect: *N*=256 εlog2≈−2109; *N*=512 εlog2≈−76.6 (4 trials); Metal PASS. Does **not** close *N*=1024 at native *k*=1.

## kδ encoding at N=1024 covering-b1 σ=128 (C43)

```bash
.build/release/helut --measure-bk-noise --degree 1024 --trials 4 \
  --bk-noise-sigma 128 --covering-base-log 1 --boolean-scale-mul 4 \
  | tee logs/helut-noisy-bk-covering-b1-gauss-sigma128-n1024-k4.log
.build/release/helut --bench netlist.json --degree 1024 \
  --bench-encrypted --sing --vectors 2 --bk-noise-sigma 128 \
  --paths covering-b1 --boolean-scale-mul 4 \
  | tee logs/helut-encrypted-n1024-metal-sing-covering-b1-gauss-sigma128-k4.log
```

Expect: *k*=4 Metal SING PASS; 4-trial εlog2≈−43 (not −64). Sweep: `logs/helut-noisy-bk-covering-b1-gauss-sigma128-n1024-kdelta.log`. *k*=8 meets ε; public-ms SING fails under `/kδ` refresh (**C43**).

## Stride-k public-MS at N=1024 covering-b1 σ=128 (C52)

```bash
.build/release/helut --measure-bk-noise --degree 1024 --trials 8 \
  --bk-noise-sigma 128 --covering-base-log 1 --boolean-scale-mul 7 \
  | tee logs/helut-noisy-bk-covering-b1-gauss-sigma128-n1024-k7-stride-t8.log
.build/release/helut --bench netlist.json --degree 1024 \
  --bench-encrypted --sing --vectors 2 --bk-noise-sigma 128 \
  --paths covering-b1 --boolean-scale-mul 7 \
  | tee logs/helut-encrypted-n1024-metal-sing-covering-b1-gauss-sigma128-k7-stride.log
```

Expect: 8-trial εlog2≈−170 (decodable); Metal secret + public-ms **PASS**. Native *k*=1 still **C37**. Not `cryptoPublicMS`.

## Sequential covering counter at N=1024 σ=128 k=7 (C53)

```bash
.build/release/helut --bench counter_netlist.json --degree 1024 \
  --bench-encrypted --sing --vectors 2 --bk-noise-sigma 128 \
  --paths covering-b1 --boolean-scale-mul 7 \
  | tee logs/helut-encrypted-n1024-metal-sing-counter-covering-b1-gauss-sigma128-k7-stride.log
```

Expect Metal secret + public-ms **PASS** (~110 s / ~68 s per 2 rows). Same encoding as **C52**. Not PicoRV.

## Sequential covering toy ISA at N=1024 σ=128 k=7 (C54)

```bash
.build/release/helut --bench toy_isa_netlist.json --degree 1024 \
  --bench-encrypted --sing --vectors 2 --bk-noise-sigma 128 \
  --paths covering-b1 --boolean-scale-mul 7 \
  | tee logs/helut-encrypted-n1024-metal-sing-toy-isa-covering-b1-gauss-sigma128-k7-stride.log
```

Expect Metal secret + public-ms **PASS** (~194 s / ~104 s per 2 rows). Not PicoRV.

## Native k=1 LWE-n map at N=1024 covering-b1 σ=128 (C55)

```bash
.build/release/helut-bench --measure-bk-noise --degree 1024 --trials 8 \
  --bk-noise-sigma 128 --covering-base-log 1 --lwe-dimension 256 \
  | tee logs/helut-noisy-bk-covering-b1-gauss-sigma128-n1024-lwe256-t8.log
# omit --lwe-dimension for n=N=1024 (C37)
```

Expect: *n*=64 ε≈−36.6; *n*=256 ε≈−10.9; *n*=512 ε≈−6.5; *n*=1024 undecodable. None ≤−64.

## cryptoPublicMS + k=7 tiny inject (C56)

```bash
.build/release/helut-bench --measure-bk-noise --degree 1024 --trials 4 \
  --bk-noise 1 --boolean-scale-mul 7 \
  | tee logs/helut-noisy-bk-cryptoPublicMS-n1024-B1-k7-t4.log
.build/release/helut-bench --bench netlist.json --degree 1024 \
  --bench-encrypted --sing --vectors 2 --bk-noise 1 --boolean-scale-mul 7 \
  --paths 'blind-rotate-metal public-ms crypto' \
  | tee logs/helut-encrypted-n1024-metal-sing-cryptoPublicMS-B1-k7.log
```

Expect: identity decodable ε≈−12.6; Metal SING **FAIL**. Torus σ=128 still undecodable.

## Covering-b2 k=7 σ=128 cheaper SING (C57)

```bash
.build/release/helut --measure-bk-noise --degree 1024 --trials 4 \
  --bk-noise-sigma 128 --covering-base-log 2 --boolean-scale-mul 7 \
  | tee logs/helut-noisy-bk-covering-b2-gauss-sigma128-n1024-k7-e1.log
.build/release/helut --bench netlist.json --degree 1024 \
  --bench-encrypted --sing --vectors 1 --bk-noise-sigma 128 \
  --paths 'public-ms covering-b2' --boolean-scale-mul 7 \
  | tee logs/helut-encrypted-n1024-metal-sing-covering-b2-gauss-sigma128-k7-e1.log
.build/release/helut --bench regex_netlist.json --degree 1024 \
  --bench-encrypted --sing --vectors 1 --bk-noise-sigma 128 \
  --paths 'public-ms covering-b2' --boolean-scale-mul 7 \
  | tee logs/helut-encrypted-n1024-metal-sing-regex-covering-b2-gauss-sigma128-k7-e1.log
```

Expect: εlog2≈−110.7; adder ~10.3 s/1 PASS; regex 23 LUT ~26.7 s/1 PASS. Covering-b4 public-ms and E256 58-LUT covering-b2 SING FAIL.

CPU covering (same gadget, demo *N*):

```bash
.build/release/helut --bench netlist.json --degree 8 --bench-encrypted --cpu-only \
  --sing --vectors 1 --bk-noise-sigma 24 --paths 'public-ms covering-b2'
```

## PicoRV abc -lut 6 (C58)

```bash
yosys -p "read_verilog picorv32.v; synth -top picorv32 -flatten; abc -lut 6; write_json picorv32_lut6_netlist.json"
.build/release/helut --bench picorv32_lut6_netlist.json --degree 64 \
  --bench-encrypted --cpu-only --sing --vectors 1 \
  --paths 'blind-rotate public-ms boolean' \
  | tee logs/helut-encrypted-n64-cpu-sing-picorv32-lut6.log
```

Expect 2006 `$lut` / 1565 DFF; **PASS** ~1.35 s/1, 32-bit hardness. *N*=8 traps (`table` 64 > *N*). Not covering; not *N*=1024.

## Sequential wavefront (C59)

Same command as **C58** after wavefront. Expect **PASS** ~0.165 s/1 (~8.2×).

## PicoRV lut6 covering-b2 Q SING FAIL (C60)

```bash
.build/release/helut --bench picorv32_lut6_netlist.json --degree 1024 \
  --bench-encrypted --sing --vectors 1 --bk-noise-sigma 128 \
  --paths 'public-ms covering-b2' --boolean-scale-mul 7 \
  | tee logs/helut-encrypted-n1024-metal-sing-picorv32-lut6-covering-b2-k7-e6.log
```

Expect combinational BRs to finish (~33 min) then **DFF Q SING FAIL** (want=0 got=1).

## PicoRV lut6 Metal N=1024 e=0 (C62)

```bash
.build/release/helut --bench picorv32_lut6_netlist.json --degree 1024 \
  --bench-encrypted --sing --vectors 1 \
  --paths 'blind-rotate-metal public-ms boolean' \
  | tee logs/helut-encrypted-n1024-metal-sing-picorv32-lut6-boolean-e0.log
```

Expect **PASS** ~374 s / 1, Q SING, *B*<sub>bk</sub>=0. Hardness 175.7 with **H1**. Not covering.

## PicoRV lut6 covering-b2 noisy BK at N=64 (C63)

```bash
.build/release/helut --bench picorv32_lut6_netlist.json --degree 64 \
  --bench-encrypted --cpu-only --sing --vectors 1 \
  --paths 'public-ms covering-b2' --bk-noise-sigma 128 \
  | tee logs/helut-encrypted-n64-cpu-sing-picorv32-lut6-covering-b2-sigma128.log
```

Expect **PASS** ~1.72 s / 1, Q SING, *B*<sub>bk</sub>≈88782. Do **not** add `--boolean-scale-mul 7` at *N*=64 (SIGTRAP). Does not close **C60**.

## Extract→key-switch n=64 (C64)

```bash
swift test -c release --filter testExtractKeySwitchClosesPBSWhenNLessThanKN
.build/release/helut --bench netlist.json --degree 1024 --bench-encrypted --cpu-only \
  --sing --vectors 1 --paths 'public-ms boolean' --lwe-dimension 64 \
  | tee logs/helut-encrypted-n1024-cpu-sing-adder-ks-n64-e0.log
.build/release/helut --bench netlist.json --degree 1024 --bench-encrypted --cpu-only \
  --sing --vectors 1 --paths 'public-ms covering-b2' --bk-noise-sigma 128 \
  --lwe-dimension 64 \
  | tee logs/helut-encrypted-n1024-cpu-sing-adder-covering-b2-ks-n64-sigma128.log
.build/release/helut --bench counter_netlist.json --degree 1024 --bench-encrypted --cpu-only \
  --sing --vectors 1 --paths 'public-ms covering-b2' --bk-noise-sigma 128 \
  --lwe-dimension 64 \
  | tee logs/helut-encrypted-n1024-cpu-sing-counter-covering-b2-ks-n64-sigma128.log
```

Expect extract→KS print, all **PASS**. Do not quote 175.7 as LWE-*n*=64 security (**H1**). Does not close **C37** (*n*=*N*) or PicoRV **C60**.

## PicoRV lut6 covering extract→KS n=64 (C65)

```bash
.build/release/helut --bench picorv32_lut6_netlist.json --degree 1024 \
  --bench-encrypted --sing --vectors 1 --bk-noise-sigma 128 \
  --lwe-dimension 64 --paths 'public-ms covering-b2' \
  | tee logs/helut-encrypted-n1024-metal-sing-picorv32-lut6-covering-b2-ks-n64.log
.build/release/helut --bench picorv32_lut6_netlist.json --degree 1024 \
  --bench-encrypted --sing --vectors 1 --bk-noise-sigma 128 \
  --lwe-dimension 64 --paths 'public-ms covering-b1' \
  | tee logs/helut-encrypted-n1024-metal-sing-picorv32-lut6-covering-b1-ks-n64.log
```

Expect **PASS** ~114 s (b2) / ~212 s (b1), Q SING. Native *k*. **C60**/**C61** (*n*=*N*, *k*=7) stay FAIL. Not LWE-176. Not Linux.

## PicoRV lut6 covering 10-tick boot (C66)

```bash
.build/release/helut --bench picorv32_lut6_netlist.json --degree 1024 \
  --bench-encrypted --sing --ticks 10 --reset-hold 3 \
  --bk-noise-sigma 128 --lwe-dimension 64 --paths 'public-ms covering-b2' \
  | tee logs/helut-encrypted-n1024-metal-sing-picorv32-lut6-covering-b2-ks-n64-boot10.log
```

Expect **PASS** ~1136 s / 10 (~114 s/row), Q SING. Idle mem. Not NOP-fetch.

## Covering KS n-ladder (C67)

```bash
.build/release/helut --bench netlist.json --degree 1024 --bench-encrypted --cpu-only \
  --sing --vectors 1 --paths 'public-ms covering-b2' --bk-noise-sigma 128 \
  --lwe-dimension 128 \
  | tee logs/helut-encrypted-n1024-cpu-sing-adder-covering-b2-ks-n128-sigma128.log
```

Expect *n*=128 **PASS** ~8.6 s. *n*=256/512 **SIGTRAP** after extract→KS was **C67** (identity×4). **C69** retries with 1 identity trial.

## Covering KS n=256 / n=512 after identity cap (C69)

Same adder command as **C67** with current `EncryptedNetlistSim` (identity trials=1 at *n*≥256). Expect *n*=256 **PASS** ~17 s; *n*=512 **SING FAIL** (sum mismatch).

## PicoRV lut6 covering NOP-fetch (C68)

```bash
.build/release/helut --bench picorv32_lut6_netlist.json --degree 1024 \
  --bench-encrypted --sing --ticks 8 --reset-hold 3 --encrypted-mem nop \
  --bk-noise-sigma 128 --lwe-dimension 64 --paths 'public-ms covering-b2' \
  | tee logs/helut-encrypted-n1024-metal-sing-picorv32-lut6-covering-b2-ks-n64-nop8.log
```

Expect **PASS** ~911 s / 8, FETCH `0x0,0x4`. Not 10-fetch. Not Linux.

## TensorLUT melt–freeze–snap (C44)

```bash
swift test -c release --filter testTensorLUTMeltFreezeSnapCertificate
swift test -c release --filter testXORLambdaCoolingSnapsTowardBinary
```

Expect three lemmas `holds`. XOR elite after `polishBinaryAtEnd` emits INIT bits `0110`. Not multi-LUT topological melt.

## Encrypted PicoRV32 1-tick (C45)

```bash
.build/release/helut --bench picorv32_netlist.json --degree 8 \
  --bench-encrypted --cpu-only --sing --vectors 1 \
  --paths 'blind-rotate public-ms boolean' \
  | tee logs/helut-encrypted-n8-cpu-sing-picorv32.log
```

Expect **PASS** ~76 ms/row, 4785 LUT / 1565 DFF, hardness 4.0 bits (demo *N*=8). One host posedge. Output SING; register SING from **C46**.

## Encrypted PicoRV32 10-tick resetn boot (C46)

```bash
.build/release/helut --bench picorv32_netlist.json --degree 8 \
  --bench-encrypted --cpu-only --sing --ticks 10 --reset-hold 3 \
  --paths 'blind-rotate public-ms boolean' \
  | tee logs/helut-encrypted-n8-cpu-sing-picorv32-boot10.log
```

Expect **PASS** 0.972 s / 10 (97.20 ms/row), Q ≡ clear. Idle `mem_ready=0`. LUT-tax 1-tick: *N*=32 **819 ms** (16 bits); *N*=64 **4.35 s** (32 bits).

## Encrypted PicoRV32 NOP-fetch (C47)

```bash
.build/release/helut --bench picorv32_netlist.json --degree 8 \
  --bench-encrypted --cpu-only --sing --ticks 32 --reset-hold 3 \
  --encrypted-mem nop --paths 'blind-rotate public-ms boolean' \
  | tee logs/helut-encrypted-n8-cpu-sing-picorv32-nop-fetch.log
```

Expect **PASS**, 10 fetches, `mem_addr` 0x0,0x4,…,0x24, ~98 ms/row, Q ≡ clear.

## Encrypted PicoRV32 addi+sw store (C49)

```bash
.build/release/helut --bench picorv32_netlist.json --degree 8 \
  --bench-encrypted --cpu-only --sing --ticks 48 --reset-hold 3 \
  --encrypted-mem prog --paths 'blind-rotate public-ms boolean' \
  | tee logs/helut-encrypted-n8-cpu-sing-picorv32-prog-store.log
```

Expect **PASS**, STORE `wdata=1`, host RAM0=1, 14 fetches, ~79 ms/row, Q ≡ clear. Demo *N*=8. Load-back is **C50**.

## Encrypted PicoRV32 lw sees 1 (C50)

```bash
.build/release/helut --bench picorv32_netlist.json --degree 8 \
  --bench-encrypted --cpu-only --sing --ticks 48 --reset-hold 3 \
  --encrypted-mem prog --paths 'blind-rotate public-ms boolean' \
  | tee logs/helut-encrypted-n8-cpu-sing-picorv32-prog-lw.log
```

Expect **PASS**, LOAD xfer `rdata=1`, STORE `wdata=1`, RAM0=1, 14 fetches, ~79 ms/row, Q ≡ clear. Demo *N*=8. Not Metal PicoRV.

## Metal PicoRV32 NOP-fetch (C51)

```bash
.build/release/helut --bench picorv32_netlist.json --degree 8 \
  --bench-encrypted --sing --ticks 8 --reset-hold 3 \
  --encrypted-mem nop --paths 'blind-rotate-metal public-ms boolean' \
  --metal-br-tile 8 \
  | tee logs/helut-encrypted-n8-metal-sing-picorv32-nop-fetch.log
```

Expect **PASS**, 2 fetches (`0x0`, `0x4`), ~64 s / 8 (~7.9 s/row). Tiled BR; fused default traps. Demo *N*. Not fused metal-netlist.

## 2-LUT cascade melt–snap–emit (C48)

```bash
swift test -c release --filter testTwoLUTCascadeMeltFreezeSnapEmit
```

Expect 8-corner SING of snapped INIT and two LUT6 cells in emitted Verilog.

## 4-bit CSA vs ripple LUT cut (C42)

Architecture, not TensorLUT melt.

```bash
yosys -p "read_verilog ripple4.v; synth -top ripple4 -flatten; abc -lut 2; write_json ripple4_netlist.json"
yosys -p "read_verilog csa4.v; synth -top csa4 -flatten; abc -lut 2; write_json csa4_netlist.json"
.build/release/helut --bench ripple4_netlist.json --degree 8 --compile-only
.build/release/helut --bench csa4_netlist.json --degree 8 --compile-only
.build/release/helut --bench csa4_netlist.json --degree 8 \
  --bench-encrypted --cpu-only --sing --vectors 64 \
  --paths 'blind-rotate public-ms boolean'
```

Expect: 11 → 8 LUT2 (−27%); both SING PASS.

## Grand audit (Phase 0.9 M5)

```bash
./Scripts/helut_grand_audit.sh           # formal certs + Sage + CPU-only short SING + textbook stamp
./Scripts/helut_grand_audit.sh --full    # also Metal N=1024 C20/C21 SING
```

## Track B Metal SING with noisy BK (C28)

```bash
.build/release/helut --bench netlist.json --degree 128 \
  --bench-encrypted --sing --vectors 4 --bk-noise 64 \
  --paths 'blind-rotate-metal public-ms crypto' \
  | tee logs/helut-encrypted-n128-metal-sing-crypto-noisy.log
```

Expect PASS, non-zero decodable *B*<sub>bk</sub>, covering degree.

## Campaign control (C2) — cleartext, not FHE (**N6**)

Welchman blind control on known P1030684 (see journal / `BREAK_P1030680.md`). Fitness is cleartext Metal batch — never HELUT encrypted tick rate.

## TensorLUT Theorem 1 (C19)

```bash
swift test -c release --filter testTensorLUTFormalCertificate
```

Six lemmas must hold (`π`, MSE, \(F\), emitter, involution, freeze). Statement: [`directives/tensorlut-theorem.md`](directives/tensorlut-theorem.md). Structural — not a U-534 / P1030680 decrypt (**H6**, **N**).

No Swift, no Mac (Phase 0.95 **R1**–**R5**):

```bash
python3 Scripts/toy_cipher_demo.py
python3 Scripts/tensorlut_math_ref.py
python3 Scripts/lambda_threshold_probe.py
python3 Scripts/penalty_threshold.py
make note   # note/lut-relaxation.tex → pdf + md (needs latexmk + pandoc)
```

The first is the introductory module: one SPN skeleton with a nonlinear S-box and an affine one, five ways to tell them apart, including the exact 4-round differential (2^-10 vs probability 1) and the LUT `INIT` view. The second expects PASS on C19 (with the analytic identities), C25-structural, C44, C27 sizes \(\{8,128\}\), and the toy involution. The third and fourth are **not** claims. The third measures where maximizers of \(F_\lambda\) sit as \(\lambda\) grows on a non-separable two-LUT topology (crossover in \((2,4]\)). The fourth computes the classical exact-penalty bound that explains it: \(\lambda\ge\tfrac12\sup\lambda_{\max}(\nabla^2 f) = 2+\sqrt3\) here. That threshold is Raghavachari (1969) / Giannessi–Niccolucci (1976), **not** a HELUT result — see `note/lut-relaxation.tex` §4.

Both are stdlib only and run in Linux CI (`.github/workflows/linux-math.yml`). They are executable checks rather than machine-checked proofs, and neither is a new **C** row. C25 omits `mutatedPreserving`, which needs Swift's RNG. Start-here page: [`INTRO.md`](INTRO.md). Reviewer map: [`REVIEWER.md`](REVIEWER.md).

## TensorLUT Theorem 1 corollary (C25)

```bash
swift test -c release --filter testTensorLUTFormalCorollaryCertificate
```

Two lemmas must hold (emitter–discrete agreement; involution under freeze). Still not melt completeness.

## Enigma256 SoftBus Theorem 2 (C24)

```bash
swift test -c release --filter testEnigma256FormalCertificate
```

Five lemmas must hold (bijection, reciprocity, stream round-trip, day-key involutions, `coupledCubic6` reject). Statement: [`directives/enigma256-theorem.md`](directives/enigma256-theorem.md). Structural SoftBus contract — not IND-CPA; builds on empirical **C10**.

## TensorLUT baseline (C8)

```bash
# Emit / grades — see tensorlut.md and campaign Phase 21 artifacts
# Baseline: enigma_m4_tensorlut_baseline.v (925 LUT6 + 49 DFFs)

# Emitted Verilog is synthesizable AND functionally equivalent.
# Needs yosys on PATH (brew install yosys); skips cleanly without it.
swift test -c release --filter TensorLUTYosysRoundTripTests \
  | tee logs/tensorlut-yosys-roundtrip-2026-08-16.log
```

Expected:

```
TENSORLUT_ROUNDTRIP ok: 48 output bits over 16 input assignments, yosys-resynthesized vs source netlist
TENSORLUT_ROUNDTRIP negative control: 4 mismatch(es) detected
```

The loop is emit → `yosys -q` (`read_verilog`, `hierarchy`, `proc`, `flatten`,
`techmap`, `abc -lut 6`, `write_json`) → reload through the repo's own Yosys
loader → `CleartextNetlistSimulator`, compared against direct evaluation of the
source TensorLUT cells over **all 16** input assignments. Exhaustive, so
agreement is proof rather than sampling. A behavioural `LUT6` model is supplied
in-test so the flow does not depend on where a Yosys install keeps its Xilinx
library.

The negative control matters more than the positive result: flipping a single
INIT bit must produce a visible mismatch. Without it, a comparison reading the
wrong ports — or a Yosys pass that optimised INIT away — would pass silently.

**Still open.** This validates the 4-LUT design, not the 925-LUT M4 baseline.
The generic per-netlist emit CLI was dropped in the packaging split, so
`enigma_m4_tensorlut_baseline.v` cannot yet be regenerated end-to-end.

## Determinism gates (encrypted path)

The 2026-08-15 defect: `EncryptedNetlistSimulator.tick` encrypted primary inputs
while iterating `inputs` as a `Dictionary`, drawing from the shared serial RNG
inside the loop. Swift reseeds Dictionary hashing per process, so each run gave a
different mask to a different wire, and thin decode margins became coin tosses.
It cost a claim: the *n*=512 covering adder was filed as a noise-limit FAIL
before being traced to this.

```bash
make gates        # both determinism gates + claim integrity lint
make determinism  # determinism gates only
```

or individually:

```bash
# In-process guard: decoy keys permute Dictionary layout, fingerprint must hold.
swift test -c release --filter EncryptedDeterminismTests

# Cross-process guard: the property that actually broke. Runs the emitting test
# as N separate processes and requires byte-identical fingerprints.
python3 Scripts/determinism_cross_process.py --runs 5 --verbose
```

**Not CI-enforced.** Both GitHub runners are `ubuntu-latest` and this needs
macOS, so `make gates` is a local pre-commit ritual rather than a merge gate. The
claim integrity lint *is* in CI (`.github/workflows/linux-math.yml`) because it is
pure Python.

Expected: `PASS all 5 processes agreed: 9820c89a488d815d`.

`SWIFT_DETERMINISTIC_HASHING` must stay **unset** — it pins the hash seed and
makes the cross-process check vacuous. The script refuses to run if it is set
(exit 2). Exit 1 means fingerprints genuinely diverged.

Both gates were verified to *catch* the bug by reintroducing it: the cross-process
driver reported 3 distinct fingerprints across 6 processes. A determinism test
that has never been shown to fail is not evidence.

## Noise-measurement estimators (ε)

```bash
# Accumulator sampling agrees with the single-residual estimator (coefficient 0
# reproduces it exactly; a noiseless BK gives residual 0 everywhere).
swift test -c release --filter TFHENoisyBKAccumulatorTests

# The confidence bound is not tightened by correlated residuals.
swift test -c release --filter TFHENoisyBKAccumulatorBoundSafetyTests

# Measured effective sample size per bootstrap (~7 min; prints the table in
# AUDIT.md 13.4.1). Expect gain 8-12x, flat in N -- not the N-fold that
# AUDIT 13.4 originally predicted.
swift test -c release --filter TFHENoisyBKEffectiveSampleTests
```

## Tests (smoke)

```bash
swift test --filter 'TFHESeamTests/testRotationNativePackStaysInZ2N'
swift test -c release --filter 'N256BlindRotateSmoke/testArity3CarryAtDegrees'
swift test --filter 'TFHESeamTests/testEncryptedNetlistWireRefreshPublicMSFullAdder'
make test-metal-p1   # Phase 1 tiled-kernel / CSE / cache battery
```

## Artifact layout (for a release tag)

| Path | Role |
|------|------|
| `directives/claim-sheet.md` | C / H / N freeze |
| `writeup.pdf` / `paper/helut.pdf` | Campaign + stack PDFs |
| `logs/helut-encrypted-*.log` | SING / micro receipts |
| `logs/helut-estimator-*.json` | Pending / results |
| `logs/helut-hardness*.txt` | Hardness table printout |
| `BREAK_P1030680.md` | Campaign ledger (negatives included) |
