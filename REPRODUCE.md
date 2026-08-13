# Reproduce

**Bar for public science:** if we assert it, someone else can re-run it from this file (or we mark it open in [`directives/claim-sheet.md`](directives/claim-sheet.md)).

Discovery after disclosure: [`directives/research-trajectory.md`](directives/research-trajectory.md).  
Parameters: [`directives/parameter-cookbook.md`](directives/parameter-cookbook.md).

Commands assume macOS Apple Silicon, Swift 6.3+, repo root after:

```bash
swift build -c release --product helut
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
