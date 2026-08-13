# HELUT parameter cookbook (copy-paste safe)

Honest: calibrated classical bits ≠ lattice-estimator attack cost until
`Scripts/helut_lattice_estimate.py` returns filled rows (needs SageMath).

Living inventory: `directives/claim-sheet.md`. Reproduce: `REPRODUCE.md`. Trajectory: `directives/research-trajectory.md`.

## Encrypted multi-LUT correctness envelope (H2)

| N | full_adder SING (publicMS / secret) | Notes |
|---|-------------------------------------|-------|
| ≤128 | **PASS** | demo / CI fast path |
| 256–1024 | **PASS** (2026-08-12) | Fix: rotation-native encrypt + `packLWEBits` reduce mod `2N`; `rotationPower` prefers Z_{2N} reps |

Public-MS gadgets with `g₀ = δ`: `GGSWParams.booleanPublicMS` / `.cryptoPublicMS` (bench public-MS paths). Classic `.booleanTrivial` / `.crypto` remain for secret / full-gadget coverage.

## Production-shaped boolean (certificates)

| Knob | Value | Notes |
|------|-------|-------|
| \(N\) (poly / LWE dim) | 1024 | `TFHEGaussianParams.productionBoolean64` |
| \(q\) | \(2^{32}\) | native `UInt32` torus |
| \(\sigma\) | \(2^{16}\) | ≪ \(\delta/2 = 2^{20}\) at \(N=1024\) |
| \(\delta\) | \(q/(2N)\) | rotation scale / message spacing |
| Target ingest \(\varepsilon\) | \(\le 2^{-64}\) | Gaussian union over primary wires |
| Classical target | \(\ge 128\) bits | HELUT est ≈176; **verify with estimator** |
| BK noise \(B_{bk}\) | 0 (HELUT now) | `TFHENoisyBKCertificate`; production uses noisy BK |
| Inter-LUT refresh | `publicMS` default | lattice-compatible BK masks |
| Metal netlist | `2N` power of two, \(2N\le 4096\) | binary dynamic \(X^p\) |

```swift
let g = TFHEGaussianParams.productionBoolean64(polynomialDegree: 1024)
let hard = TFHELWEHardnessCertificate.forHELUTEncrypt(gaussian: g)
hard.assertMeetsTarget()
let bk = TFHENoisyBKCertificate.forNetlist(
  params: .noiseless(polynomialDegree: 1024, lutCount: lutCount)
)
bk.assertDecodable()
```

## Demo / correctness (not production)

| Knob | Value |
|------|-------|
| \(N\) | 8 (or 16/32 for scale) |
| Params | `GGSWParams.crypto(degree:)` / `.booleanTrivial` |
| Hardness | will **not** meet 128-bit — certificate reports honestly |

## CLI

```bash
.build/release/helut --hardness-table
.build/release/helut --estimator-export > logs/helut-estimator-pending.json
python3 Scripts/helut_lattice_estimate.py \
  --pending logs/helut-estimator-pending.json \
  --out logs/helut-estimator-results.json

# Encrypted ≡ clear (generic stimuli)
.build/release/helut --bench netlist.json --degree 8 --bench-encrypted --sing
.build/release/helut --bench tree_netlist.json --degree 8 --bench-encrypted --cpu-only --sing
.build/release/helut --bench regex_netlist.json --degree 8 --bench-encrypted --cpu-only --vectors 32 --sing

# N=1024 levers
.build/release/helut --bench-encrypted-micro --degree 64    # fused; ~50 s/BR measured
.build/release/helut --bench-encrypted-micro --degree 1024  # auto tiled-kernel; not fused
# Fused schoolbook at N=1024 does not finish (H3 kill 2026-08-13). Force only for debug:
# .build/release/helut --bench-encrypted-micro --degree 64 --metal-br-fused
# Prefer production-shaped N for public multi-LUT SING (H2 closed @ 256–1024)
.build/release/helut --bench netlist.json --degree 1024 --bench-encrypted --cpu-only --vectors 8 --sing
./Scripts/helut_encrypted_sing.sh
```

## Measured Metal microbench (1-LUT identity BR)

| N | s/BR | RSS | Note |
|---|-----:|----:|------|
| 64 | fused ~50.3 / persist-tile **0.001** | ~2.3 GiB / 15 MiB | PASS; **C17** |
| 1024 | persist-tile **0.519** (fused-EP 1.043 / poly-mul 3.645) | 68 MiB | bits 0+1 PASS; fused DNF 11.6 h; gpu 0.50 s |

INIT dedup: `TFHETestPolyCache` + shared test-poly tensors in metal-netlist graph.

## Refuse without certificates

`TFHENoise.refuse` if Gaussian / LWE / discrete certificates are missing on unbounded claims.
See `directives/fhe-graduation.md` and `directives/research-release.md`.
