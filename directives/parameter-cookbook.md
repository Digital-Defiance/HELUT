# HELUT parameter cookbook (copy-paste safe)

Honest: calibrated classical bits at production *n*=1024, *σ*=2^{16} match lattice-estimator within 4.5 bits (**C23**). Four of eight calibration anchors still exceed the 16-bit merge tolerance — do not quote 176 as estimator cost on every row.

Living inventory: `directives/claim-sheet.md`. Reproduce: `REPRODUCE.md`. Trajectory: `directives/research-trajectory.md`.

## Two tracks (read this first)

**Not a SoftBus bug.** Under \(q=2^{32}\), exact public-MS covering (\(g_0=\delta\) **and** `baseLog·ℓ=32`) holds only for \(N\in\{8,128\}\) (**C27**). That is a torus-parameter fact, not a Metal failure.

| Track | *N* | BK | What it is for |
|-------|-----|-----|----------------|
| **A — throughput / shape** | 1024 | *e*=0 (noiseless) | Metal SING wall-clock (**C20**/**C21**), netlist scale, hardness row prod-n1024-s16 |
| **B — noisy depth** | 128 (or 8) | covering + measured residual (**C22**, **C28**) | Depth / ε story under public MS; Metal SING with inject |

Track A does **not** need noisy BK to be a valid FHE datapath claim (noiseless BK + certificates still certify). Track B is where you quote \(B_{bk}\) / σ̂. Mixing them — e.g. “production *N*=1024 with covering noisy BK under \(q=2^{32}\)” — is what **C26**/**C27** forbid.

**Track B receipt (**C28**):** Metal `cryptoPublicMS` full_adder SING @ *N*=128, `--bk-noise 64`, PASS · *B*<sub>bk</sub>≈1.62×10⁶ decodable · `logs/helut-encrypted-n128-metal-sing-crypto-noisy.log`.

**C52** closes **H4** Grade B (covering Track A): *N*=1024 covering-b1, torus σ=128, *k*=7 stride-*k* test poly + native-*δ* public-MS. εlog2≈−170 (8 trials) and Metal SING PASS (secret + public-ms). **C53**/**C54** are the same setting on a host-clocked counter and toy ISA. Native *k*=1 remains **C37** (**C55**: cutting LWE *n* makes identity decodable but ε still >−64). `cryptoPublicMS` remains **C26** (**C56**: *k*=7 + *B*=1 identity-decodable, Metal SING FAIL).

**C34:** covering `baseLog=4` @ *N*=1024 inject *B*=1 → σ̂≈2.95×10⁴, asymptotic εlog2≈−913; Metal SING PASS.

**C35:** covering `baseLog=2` holds ε≤2⁻⁶⁴ through inject *B*=16 (εlog2≈−65.4) with Metal SING PASS; *B*=32 already ≈−40.

**C36:** covering `baseLog=1` holds ε≤2⁻⁶⁴ through inject *B*=32 (εlog2≈−139, trials=4) with Metal SING PASS; *B*=64 ≈−26; *B*=128 ≈−0.6 (finer covering does **not** unlock torus-scale).

**C41:** torus-scale Gaussian σ=128 on covering-b1 **does** meet ε≤2⁻⁶⁴ at *N*=256 (εlog2≈−2109) and *N*=512 (εlog2≈−76.6, 4 trials) with Metal SING PASS at *N*=512. Production *N*=1024 still undecodable at native *k*=1 (**C37**).

**C43:** `/kδ` public-MS. *k*=4 SING yes / ε unstable; *k*=8 ε yes / public-ms SING fail.

**C52:** public-MS is native *δ* (messages `{0,k}`); test poly `T[k·addr]=bit·kδ`. Same covering-b1 σ=128 at *N*=1024, *k*=7: both bars.

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
| Classical target | \(\ge 128\) bits | HELUT est 175.7; estimator **180.2** at prod-n1024-s16 (**C23**). Other anchors: see **H1** |
| BK noise \(B_{bk}\) | 0 at *N*=1024 SING; **measured** at covering *N*=8 and *N*=128 | *N*=8: σ̂≈6396; *N*=128: σ̂≈1.47×10⁶, εlog2≈−23.5 (not −64). ℓ=1 `booleanPublicMS` cannot carry BK noise |
| Inter-LUT refresh | `publicMS` default | lattice-compatible BK masks |
| Metal netlist | `2N` power of two, \(2N\le 4096\) | binary dynamic \(X^p\) |

```swift
let g = TFHEGaussianParams.productionBoolean64(polynomialDegree: 1024)
let hard = TFHELWEHardnessCertificate.forHELUTEncrypt(gaussian: g)
hard.assertMeetsTarget()
let measured = TFHENoisyBKMeasurement.identity(
  secret: secret, params: .cryptoPublicMS(degree: 8), noise: .demo, trials: 8)
let bk = measured.certificate(lutCount: lutCount)
bk.assertDecodable()
```

## Demo / covering-gadget BK only (H4 honesty)

| Surface | Noisy BK? | What to say |
|---------|-----------|-------------|
| `--measure-bk-noise` @ *N*=8 / *N*=128 covering gadget | **Measured** (**C22**) | Residual → *B*<sub>bk</sub> / σ̂; *N*=128 inject *B*=64 ∞-norm OK, εlog2≈−23.5 |
| `--measure-bk-noise` @ *N*=1024 | **Measured failure** (**C26**) | Inject *B*=64 undecodable; *B*=4 `.crypto` ∞-norm OK but εlog2≈−1. Not a production depth story |
| Default Metal full_adder SING *N*=1024 | **No** (*B*<sub>bk</sub>=0) | Product path stays noiseless BK until a gadget+σ meets ε≤2⁻⁶⁴ |
| ℓ=1 `booleanPublicMS` | Cannot carry BK noise | Use covering gadget / crypto ℓ≥2 for residual experiments |

Cookbook rule: quote noisy-BK *success* numbers only next to covering-gadget *N*∈{8,128} (**C22**, **C27**). At production *N*=1024 under *q*=2³², exact public-MS covering is **impossible** (**C27**); print **C26** residuals or *e*=0 SING — never imply measured production depth.

### Exact public-MS covering (*q*=2³²)

| *N* | baseLog for *g₀*=*δ* | baseLog \| 32? | Exact? |
|-----|----------------------|----------------|--------|
| 8 | 4 | yes (ℓ=8) | **yes** |
| 128 | 8 | yes (ℓ=4) | **yes** |
| 1024 | 11 | **no** (⌊32/11⌋·11=22) | **no** (**C27**) |

See `directives/ggsw-public-ms-covering.md`.## Demo / correctness (not production)

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
# Native SageMath 10.9 at ~/Applications/SageMath-10-9.app (no qemu).
./Scripts/helut_sage_estimate.sh
.build/release/helut --measure-bk-noise --degree 8 --trials 8 --bk-noise 64

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
| 64 | fused ~50.3 / persist-schoolbook **0.001** / NTT-tile **0.010** | ~2.3 GiB / 15 MiB / 16 MiB | PASS; **C17** / **C18** |
| 1024 | NTT-tile **0.433** (persist-schoolbook 0.519 / fused-EP 1.043 / poly-mul 3.645) | 148 MiB | bits 0+1 PASS; fused DNF 11.6 h; gpu 0.43 s; **C18** |

full_adder SING *N*=1024×8: boolean **10.6 s** (**C20**); crypto ℓ=2 **11.38 s** (**C21**).

INIT dedup: `TFHETestPolyCache` + shared test-poly tensors in metal-netlist graph.

## Refuse without certificates

`TFHENoise.refuse` if Gaussian / LWE / discrete certificates are missing on unbounded claims.
See `directives/fhe-graduation.md` and `directives/research-release.md`.
