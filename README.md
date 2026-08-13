# HELUT

**Homomorphic Edge Look-Up Tensors** — a Swift / Metal systems prototype that compiles **Yosys gate-level netlists** into a single `MPSGraph` and evaluates every LUT as a dense negacyclic matrix–vector product over $\mathbb{Z}/2^{32}\mathbb{Z}$ on Apple Silicon.

The point is not “Enigma only.” Enigma is one application. The stack is a **datapath for encrypted-shaped circuit evaluation**: combinational LUTs, sequential DFFs, batch parallelism, and CPU-scale netlists (including a **PicoRV32 RISC-V** core).

| Layer | Role |
|-------|------|
| **HELUTCore** | Yosys JSON → `MPSGraph`, boolean-safe mock PBS (multilinear LUTs), DFF clocking, batch axis |
| **`helut` CLI** | Drive netlists / apps (Enigma bombe UI is the current default front-end) |
| **Host oracles** | Boolean-faithful Enigma/M4 for cryptanalysis and validation (campaign path) |

Values labeled “encrypted” on the **FHE path** (`--lut-backend encrypted` / `--bench-encrypted`) are LWE/GLWE samples evaluated with GGSW bootstrap keys (blind-rotate per Yosys `$lut`, `LUTNode` or whole-netlist Metal graph). HELUT ships Decision-LWE → IND-CPA binding (`TFHELWEHardnessCertificate`, ~176-bit classical estimate at N=1024 via `TFHELWECalibration`), Gaussian ε≤2⁻⁶⁴, discrete-inject proofs, and noisy-BK depth certificates. Metrics: `--bench-encrypted --sing` / `Scripts/helut_encrypted_sing.sh`. Bit estimates should be cross-checked with a lattice estimator (`Scripts/helut_lattice_estimate.py`) before production key sizes. Research-release evidence law: `directives/research-release.md`.
Living results inventory: [`directives/claim-sheet.md`](directives/claim-sheet.md). Reproduce: [`REPRODUCE.md`](REPRODUCE.md). Trajectory beyond disclosure: [`directives/research-trajectory.md`](directives/research-trajectory.md).

Papers (canonical **TeX**; Markdown is generated — do not hand-edit `*.md`):

| Doc | Source | Build |
|-----|--------|-------|
| Campaign (P1030680) | [`writeup.tex`](writeup.tex) | `make writeup` → `writeup.pdf` + `writeup.md` |
| Three-pillar stack | [`paper/helut.tex`](paper/helut.tex) | `make paper` → `paper/helut.pdf` + `paper/helut.md` |
| Living textbook (course) | [`textbook/helut-living-textbook.tex`](textbook/helut-living-textbook.tex) | `make textbook` → pdf + md |
| All three | | `make docs` |

Needs `latexmk` (MacTeX / TeX Live) and `pandoc`. Aux files land under `build/`.

**Project site:** [helut.digitaldefiance.org](https://helut.digitaldefiance.org) — stack overview, the three pre-Enigma apps, and the P1030680 campaign. Source in [`site/`](site/).

**YouTube concept videos:** Remotion + ElevenLabs TTS under [`videos/`](videos/) (overview + three pillars).

## Requirements

- macOS 14+
- Apple Silicon (Metal + `MetalPerformanceShadersGraph`)
- Swift 6.3 (`swift-tools-version: 6.3` in [`Package.swift`](Package.swift))
- Optional: [Yosys](https://github.com/YosysHQ/yosys) to re-synthesize Verilog → JSON
- Large unified memory for big nets / wide batches (64 GB class machine for PicoRV compile and `B ≈ 30k` Enigma)

## Quick start

```bash
git clone https://github.com/Digital-Defiance/HELUT.git
cd HELUT
swift build -c release
swift test
```

```bash
# Compile any Yosys JSON netlist into an MPSGraph (setup timing)
swift run -c release helut -- path/to/netlist.json --compile-only
```

## What HELUT evaluates

### Core pipeline

1. **Negacyclic matvec** — multiply in $\mathbb{Z}_{2^{32}}[X]/(X^N+1)$ as an $N\times N$ Toeplitz matrix–vector product (`N = 1024`), using native `UInt32` wraparound (Phase-1 kernel proof).
2. **LUT / mock PBS** — each Yosys `$lut` becomes a multilinear expansion of its truth table over trivial torus encodings (boolean-safe); the dense matvec kernel remains available for modular-arithmetic stress tests.
3. **Sequential logic** — `$_DFF*` / `$_SDFF*` / enable / sync-reset, with a host clock loop and ping-pong state buffers.
4. **Batch axis `B`** — many independent instances of the same circuit in one `graph.run` (search, scoring, parallel machines).

Phased design docs: [`PRD.md`](PRD.md) (kernel) → [`phase-2.md`](phase-2.md) (netlist graph) → [`phase-3.md`](phase-3.md) (Yosys JSON) → [`audit.md`](audit.md).

### Application circuits (in-repo)

| App | Sources | Netlist | Idea |
|-----|---------|---------|------|
| **Encrypted RISC-V** | [`picorv32.v`](picorv32.v) | [`picorv32_netlist.json`](picorv32_netlist.json) | Capstone: ~4.8k LUTs / ~1.5k DFFs; scripted `resetn` boot, multi-tick clocking ([`PRD_App1_RISCV.md`](PRD_App1_RISCV.md), [`PRD_App1.md`](PRD_App1.md)) |
| **Batched search** | [`regex_matcher.v`](regex_matcher.v) | [`regex_netlist.json`](regex_netlist.json) | 3-character matcher × large `B` ([`PRD_App2.md`](PRD_App2.md)) |
| **Decision tree** | [`decision_tree.v`](decision_tree.v) | [`tree_netlist.json`](tree_netlist.json) | Exact non-linear classify over batched records ([`PRD_App3.md`](PRD_App3.md)) |
| **Small sequential demos** | [`counter.v`](counter.v), [`circuit.v`](circuit.v), … | [`core_netlist.json`](core_netlist.json), … | DFF retention / early bring-up |
| **Enigma Bombe** | [`enigma_core.v`](enigma_core.v), [`enigma_m4_core.v`](enigma_m4_core.v) | `enigma_*_netlist.json` | Parallel rotor hypotheses + scoring ([`PRD_App_Enigma_Bombe.md`](PRD_App_Enigma_Bombe.md), [`PRD_App_P1030680_Bombe.md`](PRD_App_P1030680_Bombe.md)) |

Re-synthesize examples:

```bash
# PicoRV32 (heavy)
yosys -p "read_verilog picorv32.v; synth -top picorv32 -flatten; abc -lut 2; write_json picorv32_netlist.json"

# M4 Enigma + linguistic score port
yosys -p "read_verilog -sv enigma_m4_core.v; synth -top enigma_m4_core -flatten; abc -lut 2; write_json enigma_m4_netlist.json"
```

### Measured boolean-path benches (2026-08-12)

Trivial torus encoding + multilinear `$lut`. Drivers: `./Scripts/helut_boolean_bench.sh`, `./Scripts/helut_boolean_scale.sh`, `./Scripts/helut_phase_seam.sh`. Graduation seams: [`directives/fhe-graduation.md`](directives/fhe-graduation.md).

| Netlist | Cells | Compile | Steady tick | Notes |
|---------|-------|---------|-------------|-------|
| PicoRV32 N=1024 B=1 | 4785 LUT / 1565 DFF | **1.30 s** | **173 ms** (~5.8 Hz) | RSS ~0.65 GiB; paper Toeplitz path was ~469 s / tens of GiB |
| Enigma M3 N=1024 B=1 | 688 LUT / 26 DFF | **0.04 s** | **15 ms** (~66 Hz) | |
| Enigma M4 N=1024 B=1 | 925 LUT / 49 DFF | **0.06 s** | — | compile-only |
| Enigma M3 equiv N=1024 | — | 0.04 s | 27 ms/letter | Metal ≡ cleartext — **PASS** |
| Enigma M3 equiv N=1 | — | 0.03 s | 26 ms/letter | clear-shape ≡ cleartext — **PASS** |

**Batch scaling (Enigma M3, steady tick after warmup):**

| B | N=1024 tick | N=1024 RSS | N=1 tick | N=1 RSS |
|---|-------------|------------|----------|---------|
| 1 | 14.5 ms | ~92 MiB | 13.4 ms | ~76 MiB |
| 10 | 14.7 ms | ~157 MiB | 13.1 ms | ~77 MiB |
| 100 | 16.6 ms | ~688 MiB | 16.3 ms | ~89 MiB |
| 1000 | **73 ms** | **~6.0 GiB** | **15 ms** | **~91 MiB** |

At small B, graph overhead dominates `N`; at B=1000, TFHE-shaped `N=1024` becomes memory-bound while clear-shape (`N=1`) stays flat. Use `--degree 1` for throughput experiments; keep `--degree 1024` for TFHE-shaped certification.

```bash
./Scripts/helut_boolean_bench.sh
./Scripts/helut_boolean_scale.sh
.build/release/helut --bench picorv32_netlist.json --batch 1 --degree 1024 --ticks 10
.build/release/helut --bench enigma_netlist.json --degree 1 --batch 1000 --ticks 8 --reset-hold 0
.build/release/helut --bench enigma_netlist.json --ticks 0 --bench-equiv
```

> **Note:** Default `helut` UX remains Enigma-bombe oriented. `--bench` is the general HELUTCore clock harness. Campaign cryptanalysis stays on host Welchman / cleartext batch.

## Enigma & P1030680

Two different jobs:

| Command family | Engine | Purpose |
|----------------|--------|---------|
| `--p1030680-bombe` / default Enigma Metal run | Boolean-safe mock-PBS tensors | Parallel bombe **architecture** + decrypt path |
| `--break-p1030680` / `--campaign` | Host M4 oracle | **Cryptanalysis** (Welchman / campaign ladder) |
| `--hybrid` | GA shell+stecker × cleartext Metal/CPU `B=17576` | ASIC-esque / Stochastic Bombe ([`ASIC_CRACKER.md`](ASIC_CRACKER.md), [`stochastic-bombe.md`](stochastic-bombe.md)) |

Mock-PBS under trivial torus encoding preserves boolean plaintext. Campaign search still uses the host/Welchman ladder and cleartext batch fitness — not in-graph `linguistic_score` alone — because the unbroken-message problem is archival, not tensor fidelity.

```bash
# Host campaign against unbroken U-534 / M-Thetis message P1030680
.build/release/helut --campaign 2>&1 | tee logs/campaign.log
# ./Scripts/p1030680_campaign.sh

# ASIC-esque: evolving WO/Greek/UKW/rings/stecker × cleartext batch (bigram fitness)
.build/release/helut --hybrid --quick
.build/release/helut --hybrid --rings AACU --hybrid-pop 32 --hybrid-gens 80

# Stochastic Bombe KPA control (letter-match fitness on P1030684)
.build/release/helut --hybrid --hybrid-control --quick
.build/release/helut --hybrid --hybrid-control --hybrid-seed-drop 1
.build/release/helut --hybrid --hybrid-control --hybrid-blind --hybrid-pop 24 --hybrid-gens 40

# Rigor campaign vs P1030680 (ratio fitness, noise floor, potsdam + two-notch)
.build/release/helut --hybrid --hybrid-stochastic --hybrid-rigor \
  --hybrid-pop 12 --hybrid-gens 12 --hybrid-noise-samples 8 \
  --rings AAAA,AACU 2>&1 | tee logs/stochastic-bombe-p1030680-rigor.log

# Metal M4 bombe (demo)
.build/release/helut --p1030680-bombe --batch 30000 --compile-only
```

Full attack notes: [`BREAK_P1030680.md`](BREAK_P1030680.md). Validation tiers: [`VALIDATION.md`](VALIDATION.md).

```bash
swift test --filter EnigmaBombeValidationTests
swift test --filter EnigmaM4Tests
swift run -c release helut -- --validate
```

## Project layout

```
Sources/HELUTCore/     Compiler, boolean-safe mock PBS, DFF clocking, Enigma/M4 oracles, scorers
Sources/helut/         CLI (Enigma bombe + campaign + validate; netlist argv)
Tests/HELUTTests/      Kernel, state, Enigma/M4 tests
Fixtures/              Historical Enigma vectors, German corpus
*.v / *_netlist.json   Application circuits (PicoRV32, regex, tree, Enigma, …)
Scripts/               Campaign + scorer calibration
paper/                 Technical write-up (helut.tex)
PRD*.md / phase-*.md   Design progression
```

## Status (honest)

- **General HELUT:** Yosys `$lut` + sequential cells → one `MPSGraph`; boolean-safe under trivial constant-fill / phase / glwe-trivial; LUT backends `multilinear` and trivial `pbs`; PicoRV32 ~1.3 s / ~173 ms tick; Enigma M3 Metal≡cleartext at N=1024 **PASS**.
- **Not claimed:** that calibrated core-SVP estimates replace a lattice-estimator run, or that trivial Metal graphs are FHE. (Decision-LWE binding + ε-cert: `TFHELWEHardnessCertificate` / `TFHEAsymptoticSecurityCertificate`.)
- **Enigma host attack:** real M4 decrypt / crib-drag / stecker / campaign ladder; P1030680 remains historically unbroken — catalog rings **suspended** at originalIndex 417 (resume `--bombe-from 418`).
- **CLI:** `--bench` for general netlist clocking; day-to-day UX still Enigma-first for campaign tools.

## License

MIT — see [`LICENSE`](LICENSE). Copyright © 2026 Digital Defiance.
