# FHE / PBS graduation (HELUT)

## Status: mock dropped for the FHE claim

HELUT’s **encrypted** path is BK blind-rotate over Yosys `$lut` netlists
(`EncryptedNetlistSimulator`, `--lut-backend encrypted` / `--bench-encrypted`).
Trivial Metal multilinear / CMUX graphs remain as a **fast boolean oracle** for
shape, batch scaling, and Enigma letter clocks — not as the FHE claim.

| Seam | Today | Next |
|------|-------|------|
| `TorusBitEncoding` | trivial / packed / encrypted packed; discrete noise | — |
| `LUTEvaluationBackend` | oracle backends; **`encrypted`** via **`LUTNode.evaluateEncrypted`** Metal BR | — |
| Inter-LUT refresh | **`publicMS` default** (boolean + crypto via lattice BK); `.secret` / `.none` | — |
| Noise | Discrete + Gaussian ε; **C52** *k*=7 stride-*k* covering-b1 σ=128 @ *N*=1024 (ε + Metal SING); *k*=1 still **C37** | native-*δ* torus-scale; `cryptoPublicMS` noisy |
| Clock | Metal PicoRV NOP-fetch **C51** (demo *N*=8, tiled BR) | Metal *N*=1024 PicoRV; fused sequential metal-netlist |
| E256 in FHE | Frozen 1-byte scramble Metal SING (**C39**) | Live BRAM / NLFF / full core |

Code: `TFHESeam.swift`, `TFHESamples.swift`, `TFHEGGSW.swift`, `MetalGGSW.swift`, `EncryptedNetlistSim.swift`, `ProgrammableBootstrap.swift`, `LUTNode`.  
CLI: `--encoding …`, `--lut-backend multilinear|pbs|pbs-ggsw|encrypted`, `--bench-encrypted`.

## Modes

| Config | N | Use |
|--------|---|-----|
| Encrypted BK PBS | ≥ 2^width | **FHE claim** (`EncryptedNetlistSimulator`) |
| TFHE-shaped trivial Metal | 1024 | Fast boolean oracle / shape |
| Clear-shape boolean | 1 | Batch throughput (multilinear only) |
| Trivial / GGSW-shaped Metal PBS | ≥ 2^width | Oracle CMUX graphs on body wires |
| Packed GLWE | ≥ 2^width | Oracle packed wires (`mask‖body`) |

```bash
# Encrypted FHE path (full_adder)
.build/release/helut --bench netlist.json --degree 8 --lut-backend encrypted
.build/release/helut --bench netlist.json --degree 8 --bench-encrypted
# Fast boolean oracle (still useful)
.build/release/helut --bench netlist.json --degree 64 --lut-backend pbs --encoding phase --bench-equiv
./Scripts/helut_phase_seam.sh
```

## Certification ladder

1. ~~Boolean multilinear under trivial encoding~~ (`MockPBSBooleanTests`)
2. ~~Release PicoRV / Enigma re-bench + N=1024 equiv~~ (`Scripts/helut_boolean_bench.sh`)
3. ~~Batch scaling + N=1 clear-shape~~ (`Scripts/helut_boolean_scale.sh`, 2026-08-12)
4. ~~Phase encoding~~ (`TFHESeamTests`, multilinear equiv)
5. ~~Trivial PBS subgraph (CMUX + negacyclic rotate)~~ (`ProgrammableBootstrap`, 2026-08-12)
6. ~~Encoding trait behind real samples~~ (`TFHESamples.swift`, 2026-08-12)
7. ~~GGSW external product + trivial BK/KS (s=0)~~ (`TFHEGGSW.swift`, `pbs-ggsw`, 2026-08-12)
8. ~~Non-zero secret + crypto gadget on CPU (e=0)~~ (`TFHESecretKey`, `GGSWParams.crypto`, 2026-08-12)
9. ~~Metal GGSW kernel (k=1, boolean gadget)~~ (`MetalGGSW.swift`, 2026-08-12)
10a. ~~Crypto-gadget Metal + real KS + packed-GLWE wires~~ (2026-08-12)
10b. ~~Discrete noise + encrypted packed + Metal GGSW `$lut` body~~ (2026-08-12)
10c. ~~Encrypted Yosys netlist (GGSW PBS per `$lut`)~~ (2026-08-12)
10d. ~~LWE blind-rotate + BK LUT~~ (2026-08-12)
10e. ~~Noise budget + `--lut-backend encrypted` + drop mock FHE claim~~ (2026-08-12)
10f. ~~Public MS inter-LUT + fused Metal BR (one MPSGraph / BR)~~ (2026-08-12)
10g. ~~Public MS under crypto gadget (lattice BK masks)~~ (2026-08-12)
10h. ~~Bounded ∞-norm noise growth (`TFHENoiseGrowth`) + noisy scaled inputs~~ (2026-08-12)
10i. ~~Bounded noise proof (`TFHENoiseProof` / certificate)~~ (2026-08-12)
10j. ~~`LUTNode` encrypted Metal lowering (`evaluateEncrypted`)~~ (2026-08-12)
10k. ~~Gaussian asymptotic security certificate (ε ≤ 2⁻⁶⁴)~~ (2026-08-12)
10l. ~~Whole-netlist encrypted MPSGraph (dynamic X^p)~~ (2026-08-12)
10m. ~~Binary dynamic X^p (O(log N) vs O(2N) mux)~~ (2026-08-12)
10n. ~~Decision-LWE → IND-CPA hardness certificate (~128-bit est.)~~ (2026-08-12)
10o. ~~LWE hardness calibration table (`TFHELWECalibration`)~~ (2026-08-12)
10p. ~~Noisy-BK depth certificate (`TFHENoisyBKCertificate`)~~ (2026-08-12)
10q. ~~Lattice-estimator verification protocol (`TFHELWEEstimatorProtocol`)~~ (2026-08-12)

### Honest limits (still)

- **Decision-LWE binding** for `encryptLWE` IND-CPA + calibrated classical core-SVP *estimate* (`TFHELWEHardnessCertificate` / `TFHELWECalibration`) — lattice-estimator JSON filled (**C23**); production |Δ|=4.5; do not treat every calibration row as estimator cost (`TFHELWEEstimatorProtocol`)
- Gaussian ε-certificate under independent-noise + noiseless-BK hypotheses; noisy BK modeled by `TFHENoisyBKCertificate` / Gaussian depth union bound
- Discrete-inject ∞-norm proof remains (`TFHENoiseProof`)
- Multi-LUT default: **`publicMS`** with lattice BK; `.secret` available
- Single-graph Metal netlist: rotation-native, `.publicMS`, binary X^p (`2N ≤ 4096`)
- Campaign fitness stays Welchman / cleartext batch
- Research-release evidence law: `directives/research-release.md`

### Gaussian asymptotic certificate (step 10k)

Under N(0,σ²) fresh encrypt noise, ingest lattice MS succeeds iff `|e| < δ/2`.
Tail bound via `erfc`; union over primary wires. With noiseless BK, PBS leaves
variance 0 thereafter. Production-shaped params:
`TFHEGaussianParams.productionBoolean64` (N=1024, σ = δ/2¹², target ε ≤ 2⁻⁶⁴).

### Encrypted LUTNode Metal lowering (step 10j)

`LUTNode(backend: .encryptedBlindRotate).evaluateEncrypted(_:context:)` →
`MetalGGSW.evaluateLUTBlindRotate` (fused BR). `EncryptedNetlistSimulator`
`.blindRotateMetal` uses this path.

### Whole-netlist Metal graph (step 10l / 10m)

`MetalGGSW.evaluateTopoNetlistSingleGraph` + `.blindRotateMetalNetlist`:
binary-digit `X^p` (O(log N) static rotates per monomial; was O(2N) mux).
`DynamicRotateCost` documents the speedup.

### LWE hardness binding (step 10n / 10o)

`TFHELWEHardnessCertificate`: standard hybrid Decision-LWE → IND-CPA for
`encryptLWE`, plus calibrated classical core-SVP estimate.
`TFHELWEProduction.certificate128()` targets ≥128 bits at N=1024, σ=2^{16}.
`TFHELWECalibration` anchors the estimator to TFHE-style ballparks
(|Δ| ≤ 12 bits); production row ≈176 bits.
`TFHENoisyBKCertificate` makes the noiseless-BK hypothesis explicit.
`TFHENoisyBKMeasurement` fills *B*<sub>bk</sub> / σ̂ from identity-LUT residuals
(covering gadget; **C22**). ℓ=1 `booleanPublicMS` cannot carry BK noise.
`TFHELWEEstimatorProtocol` exports pending rows for lattice-estimator fill-in
(`--estimator-export`, `Scripts/helut_sage_estimate.sh`, **C23**).
Production row agrees within 4.5 bits; four anchors still exceed Δ=16 (**H1**).
Encrypted metrics: `--bench-encrypted --sing` / `Scripts/helut_encrypted_sing.sh`.

### Sample / GGSW / PBS

- Rotation-native LWE + `blindRotate` / `evaluateLUTBlindRotate` / `MetalGGSW.blindRotate`
- `EncryptedWireRefresh`: `publicMS` | `secret` | `none`
- `TFHENoiseBudget` + `TFHENoiseGrowth` + **`TFHENoiseProof` / `TFHENoiseCertificate`**
- Mask rows encrypt **−μ·g·s**; body rows encrypt **+μ·g**

## Non-goals (unchanged)

- Using HELUT tick rate for P1030680 search
- Dense Toeplitz as a netlist LUT backend
- Calling trivial Metal graphs “homomorphic encryption”
