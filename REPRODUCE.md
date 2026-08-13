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
make docs       # both (needs latexmk + pandoc)
```

## Hardness / estimator (H1)

```bash
.build/release/helut --hardness-table | tee logs/helut-hardness.txt
.build/release/helut --estimator-export > logs/helut-estimator-pending.json
python3 Scripts/helut_lattice_estimate.py \
  --pending logs/helut-estimator-pending.json \
  --out logs/helut-estimator-results.json
```

Until SageMath provides `sage.all`, results stay `null` — do not treat calibrated bits as estimator output (**H1**, **N3**).

Install path (host): `brew install --cask sage` (may need interactive sudo), then re-run the estimator script. Lattice-estimator Python package alone is not enough.

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

Published number: ~50.3 s/BR @ *N*=64 fused MPSGraph (**C7**). Current GPU-resident BR tile (**C17**): **0.519 s/BR** @ *N*=1024, bits 0 and 1 PASS. Fused-EP (**C16**) was 1.043 s/BR. Fused schoolbook-in-MPSGraph at *N*=1024 **did not finish** (11.6 h). Default at *N*>64 is `tiled-kernel`:

```bash
.build/release/helut --bench-encrypted-micro --degree 1024 --trials 2 --warmup 0 \
  | tee logs/helut-encrypted-micro-n1024-persist.log
```

Metal full_adder SING per-LUT persist-tile (**C17**): boolean **12.2 s / 8 rows**. Legacy fused megagraph is `--metal-br-fused` only.

```bash
.build/release/helut --bench netlist.json --degree 1024 --bench-encrypted --sing --vectors 8 \
  --paths 'blind-rotate-metal public-ms boolean' \
  | tee logs/helut-encrypted-n1024-metal-sing-persist.log
.build/release/helut --bench netlist.json --degree 1024 --bench-encrypted --sing --vectors 8 \
  --metal-netlist-only \
  | tee logs/helut-encrypted-n1024-metal-netlist-sing.log
```


## Campaign control (C2) — cleartext, not FHE (**N6**)

Welchman blind control on known P1030684 (see journal / `BREAK_P1030680.md`). Fitness is cleartext Metal batch — never HELUT encrypted tick rate.

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
