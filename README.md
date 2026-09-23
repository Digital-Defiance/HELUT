# HELÜT

**Homomorphic Edge Look-Up Tensors** — a Swift / Metal systems prototype that compiles **Yosys gate-level netlists** into a single `MPSGraph` and evaluates every LUT as a dense negacyclic matrix–vector product over $\mathbb{Z}/2^{32}\mathbb{Z}$ on Apple Silicon.

**New here, or not on a Mac?** Read [`INTRO.md`](INTRO.md), or the four-page self-contained note [`note/lut-relaxation.pdf`](note/lut-relaxation.pdf). Then run these, stdlib Python 3, no build step:

```bash
python3 Scripts/toy_cipher_demo.py         # two toy ciphers, one broken on purpose
python3 Scripts/tensorlut_math_ref.py      # the structural checks behind the LUT optimiser
python3 Scripts/lambda_threshold_probe.py  # measured lambda crossover
python3 Scripts/penalty_threshold.py       # exact-penalty bound, 2 + sqrt(3)
```

Linux CI runs both. The Swift package genuinely needs Apple Silicon, because Metal is a hard dependency of the encrypted path rather than a convenience import — see [`directives/why-apple-silicon.md`](directives/why-apple-silicon.md). Reviewer map of what is checkable where: [`REVIEWER.md`](REVIEWER.md).

The point is not “Enigma only.” Enigma is one application. The stack is a **datapath for encrypted-shaped circuit evaluation**: combinational LUTs, sequential DFFs, batch parallelism, and CPU-scale netlists (including a **PicoRV32 RISC-V** core).

| Layer | Role |
|-------|------|
| **HELUTCore** / ToolKit | Swift libraries (SPM) + Metal FHE / netlist stack |
| **CLI tools** | `helut-bench`, `helut-e256`, `helut-bombe`, `helut-compile`, umbrella `helut` |
| **Host oracles** | Boolean-faithful Enigma/M4 for cryptanalysis and validation (campaign path) |

**Homebrew (CLIs):** see [`HOMEBREW.md`](HOMEBREW.md) — `brew tap digital-defiance/homebrew-tap && brew install helut`. Tip of `main`: `brew install --HEAD helut`.  
**Library consumers:** SPM `from: "0.1.0"` (tag `0.1.0`; alias `helut-lib-0.1.0`). Corpus freeze remains `helut-corpus-C54`. Packaging plan: [`directives/packaging-roadmap.md`](directives/packaging-roadmap.md).

The **FHE path** (`--lut-backend encrypted` / `--bench-encrypted`) evaluates masked LWE/GLWE samples with GGSW bootstrap keys and a blind rotate per Yosys `$lut`; SING means every encrypted output matched the clear netlist. The integrated 2026-09-06 full-adder receipt fixes *N*=*n*=1024, covering-b2 (*B*=4, ℓ=16), public MS, Gaussian BK σ=128, exact/noiseless primary inputs, and Boolean stride *k*=14: 192 identity-PBS residuals gave σ₉₅=1,282,097.0 and a 24-event circuit union bound of log₂ε=−93.80, then all 8/8 input rows passed. The sampler prepares RNG inputs and reduces results serially but evaluates up to eight read-only PBS trials concurrently; a 32-sample production replay exactly matched the serial max, σ₉₅, and ε while running 6.03× faster. This is a statistical, circuit-scoped bound—not a hard BK bound, fresh-input-noise result, arbitrary-depth/netlist certificate, or FHE evaluation speedup. The preserved 32-sample *k*=14 run was under-sampled (−48.18); increasing the preregistered sample count recovered the same configuration without changing the circuit or confidence target. Receipt: [`logs/helut-encrypted-k14-recovery-20260906T030525Z.json`](logs/helut-encrypted-k14-recovery-20260906T030525Z.json); raw output: [`…-t192-p8.raw.log`](logs/helut-encrypted-k14-recovery-20260906T030525Z-t192-p8.raw.log). Hardness is a separate model row: calibrated core-SVP ≈175.7 bits at prod-n1024-s16; Sage estimator **180.2** on that row (**C23**). **Do not quote “176-bit secure.”** Four of eight calibration anchors disagree with the estimator by >16 bits (**H1**). Evidence law: [`directives/research-release.md`](directives/research-release.md). Inventory: [`directives/claim-sheet.md`](directives/claim-sheet.md). Reproduce: [`REPRODUCE.md`](REPRODUCE.md). Trajectory: [`directives/research-trajectory.md`](directives/research-trajectory.md).

Papers (canonical **TeX**; Markdown is generated — do not hand-edit `*.md`):

| Doc | Source | Build |
|-----|--------|-------|
| Campaign (P1030680) | [`writeup.tex`](writeup.tex) | `make writeup` → `writeup.pdf` + `writeup.md` |
| Three-pillar stack | [`paper/helut.tex`](paper/helut.tex) | `make paper` → `paper/helut.pdf` + `paper/helut.md` |
| Living textbook (scaffold; **not ready to teach**) | [`textbook/helut-living-textbook.tex`](textbook/helut-living-textbook.tex) | `make textbook` → pdf + md |
| All three | | `make docs` |

Needs `latexmk` (MacTeX / TeX Live) and `pandoc`. Aux files land under `build/`.

**Project site:** [helut.org](https://helut.org) — stack overview, the three pre-Enigma apps, and the P1030680 campaign. Source in [`site/`](site/).

**YouTube concept videos:** Remotion + ElevenLabs TTS live in
[`MuleinLabs/helut-videos`](https://github.com/JessicaMulein/MuleinLabs/tree/main/helut-videos)
(local: `/Volumes/Code/MuleinLabs/helut-videos`).

## A Note on Pronunciation

I will settle one future debate early. As an acronym for Homomorphic Edge Look-Up Tensors, it probably 'should' be an unpronounceable sequence of letters. However, in my head, it has taken on a distinctly Scandinavian bent. It is pronounced hell-yoot (think HELÜT). If anything, "H-E LUT" is acceptable. Settle accordingly.

## Requirements

- macOS 14+
- Apple Silicon (Metal + `MetalPerformanceShadersGraph`)
- Swift 6.3 (`swift-tools-version: 6.3` in [`Package.swift`](Package.swift))
- Optional: [Yosys](https://github.com/YosysHQ/yosys) to re-synthesize Verilog → JSON
- Large unified memory for big nets / wide batches (64 GB class machine for PicoRV compile and `B ≈ 30k` Enigma)

**Why Apple first:** the project began by stressing one Mac — M-series / `MPSGraph` — so the λ-squeeze and synthesis loops had enough acceleration to exist. Production kernels are Metal-dependent *because that was the laboratory*, not because the math names Apple. Linux / FPGA / r/math readers: [`directives/why-apple-silicon.md`](directives/why-apple-silicon.md). Swift-free Theorem 1 check: `python3 Scripts/tensorlut_math_ref.py`. CUDA and a CPU-only *production* FHE path are trajectory, not claims.

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
2. **LUT execution** — the ordinary Boolean/oracle path expands each Yosys `$lut` over trivial torus encodings (boolean-safe); those timings are not FHE. The separate `--bench-encrypted` path evaluates masked LWE/GLWE samples with noisy or noiseless GGSW bootstrap keys and blind rotation. The dense matvec kernel remains available for modular-arithmetic stress tests.
3. **Sequential logic** — `$_DFF*` / `$_SDFF*` / enable / sync-reset, with a host clock loop and ping-pong state buffers.
4. **Batch axis `B`** — many independent instances of the same circuit in one `graph.run` (search, scoring, parallel machines).

Phased design docs: [`PRD.md`](directives/PRD.md) (kernel) → [`phase-2.md`](directives/phase-2.md) (netlist graph) → [`phase-3.md`](directives/phase-3.md) (Yosys JSON) → [`audit.md`](directives/audit.md).

### Application circuits (in-repo)

| App | Sources | Netlist | Idea |
|-----|---------|---------|------|
| **Encrypted RISC-V** | [`Hardware/RTL/Vendor/PicoRV32/picorv32.v`](Hardware/RTL/Vendor/PicoRV32/picorv32.v) | [`Generated/Netlists/PicoRV32/picorv32_netlist.json`](Generated/Netlists/PicoRV32/picorv32_netlist.json) | CPU `lw` sees 1 (**C50**); Metal NOP-fetch (**C51**, ~7.9 s/tick) at demo *N*=8. Not production *N*. |
| **Batched search** | [`Hardware/RTL/Examples/regex_matcher.v`](Hardware/RTL/Examples/regex_matcher.v) | [`Generated/Netlists/Examples/regex_netlist.json`](Generated/Netlists/Examples/regex_netlist.json) | 3-character matcher × large `B` ([`PRD_App2.md`](directives/PRD_App2.md)) |
| **Decision tree** | [`Hardware/RTL/Examples/decision_tree.v`](Hardware/RTL/Examples/decision_tree.v) | [`Generated/Netlists/Examples/tree_netlist.json`](Generated/Netlists/Examples/tree_netlist.json) | Exact non-linear classify over batched records ([`PRD_App3.md`](directives/PRD_App3.md)) |
| **Small sequential demos** | [`Hardware/RTL/Examples/counter.v`](Hardware/RTL/Examples/counter.v), [`Hardware/RTL/Examples/circuit.v`](Hardware/RTL/Examples/circuit.v), … | [`Generated/Netlists/Examples/counter_netlist.json`](Generated/Netlists/Examples/counter_netlist.json), [`Generated/Netlists/Examples/netlist.json`](Generated/Netlists/Examples/netlist.json), … | DFF retention / early bring-up |
| **Enigma Bombe** | [`Hardware/RTL/Enigma/enigma_core.v`](Hardware/RTL/Enigma/enigma_core.v), [`Hardware/RTL/Enigma/enigma_m4_core.v`](Hardware/RTL/Enigma/enigma_m4_core.v) | [`Generated/Netlists/Enigma/enigma_netlist.json`](Generated/Netlists/Enigma/enigma_netlist.json), [`Generated/Netlists/Enigma/enigma_m4_netlist.json`](Generated/Netlists/Enigma/enigma_m4_netlist.json) | Parallel rotor hypotheses + scoring ([`PRD_App_Enigma_Bombe.md`](directives/PRD_App_Enigma_Bombe.md), [`PRD_App_P1030680_Bombe.md`](directives/PRD_App_P1030680_Bombe.md)) |

Hardware generation is scratch-first and never writes through root compatibility names:

```bash
make hardware-check             # manifest + byte-identical compatibility copies
make generate-m4-artifacts      # build/hardware/EnigmaM4/
make generate-e256-profile      # build/hardware/Profiles/Enigma256/
make check-e256-profile         # read-only check of checked-in canonical profile

# After reviewing a scratch artifact, promote only that family, then refresh aliases:
make promote-m4-artifacts
make hardware-compat-sync
make hardware-check
```

`generate-e256-tensorlut` / `promote-e256-tensorlut` provide the corresponding, longer E256 flow. Promotion updates `Generated/` (and the E256 profile fixture where applicable); `hardware-compat-sync` is a separate explicit canonical-to-root operation.

The fixture-v4 golden flow is scratch-first too:

```bash
.build/release/helut-e256 --enigma256-golden
# default output: build/hardware/Enigma256/enigma256_golden
```

An explicit `Fixtures/enigma256_golden` output is compatibility-key guarded; routine reproduction should keep the scratch default rather than overwrite canonical fixtures. The bounded hardware/KAT validation record is `logs/e256-v2-gen0-fixture-v4-validation.json` (1,024 bytes, 9 tables, 10 trace files, 25 artifacts; formal 1/1 and `Enigma256Tests` 49/49).

### Measured boolean-path benches (2026-08-12)

Trivial torus encoding + multilinear `$lut`. Drivers: `./Scripts/helut_boolean_bench.sh`, `./Scripts/helut_boolean_scale.sh`, `./Scripts/helut_phase_seam.sh`. Graduation seams: [`directives/fhe-graduation.md`](directives/fhe-graduation.md).

| Netlist | Cells | Compile | Steady tick | Notes |
|---------|-------|---------|-------------|-------|
| PicoRV32 N=1024 B=1 | 4785 LUT / 1565 DFF | **1.30 s** | **173 ms** (~5.8 Hz) | RSS ~0.65 GiB; paper Toeplitz path was ~469 s / tens of GiB |
| Enigma M3 N=1024 B=1 | 688 LUT / 26 DFF | **0.04 s** | **15 ms** (~66 Hz) | |
| Enigma M4 N=1024 B=1 | 925 LUT / 49 DFF | **0.06 s** | — | compile-only |
| Enigma M3 equiv N=1024 | — | 0.04 s | 27 ms/letter | Metal ≡ cleartext — **PASS** |
| Enigma M3 equiv N=1 | — | 0.03 s | 26 ms/letter | clear-shape ≡ cleartext — **PASS** |

**Legacy broadcast batch scaling (Enigma M3, steady tick after warmup):**

These archived rows replicate one encoded trajectory across B lanes and do not read outputs back. They measure graph allocation/bandwidth/synchronization, **not independently verified throughput**; the default remains `legacy-broadcast-v1` so their meaning does not change.

| B | N=1024 tick | N=1024 RSS | N=1 tick | N=1 RSS |
|---|-------------|------------|----------|---------|
| 1 | 14.5 ms | ~92 MiB | 13.4 ms | ~76 MiB |
| 10 | 14.7 ms | ~157 MiB | 13.1 ms | ~77 MiB |
| 100 | 16.6 ms | ~688 MiB | 16.3 ms | ~89 MiB |
| 1000 | **73 ms** | **~6.0 GiB** | **15 ms** | **~91 MiB** |

For independent work, use the opt-in combinational `distinct-verified-v1` mode. It assigns every lane a unique deterministic input, retains and decodes every output, checks each result against its own clear oracle, and emits a versioned FNV digest. Packing, oracle evaluation, readback, and hashing remain outside the separately labeled graph timing; any mismatch voids that timing.

The banked production-path B=65,536 receipt uses the same post-ABC 14-LUT 8-bit adder as the native comparison: 65,536 distinct assignments, all 589,824 output bits checked, zero mismatches, and 511 output signatures. Its warmed graph median was 3.043 ms versus 7.356 ms for the then-current same-artifact single-threaded Verilator loop, a 2.42× time ratio in that deliberately asymmetric harness. The 338 ms first graph run and 103 ms post-run verification are preserved and excluded. Receipt: [`logs/helut-production-distinct-b65536-20260906T035827Z/receipt.json`](logs/helut-production-distinct-b65536-20260906T035827Z/receipt.json).

A subsequent preregistered comparison added 16 persistent native workers and a closer paired scope in which both sides prepare inputs, execute, collect outputs, and compute the ordered digest. Every five-sample row matched, including exhaustive B=65,536 digest `52f209ab0358725`, but **no paired crossover occurred through B=65,536**: HELUT took 31.954 ms versus 6.959 ms for native, or 4.592× the native time. Even the prepared diagnostic favored native: 2.133 ms synchronized HELUT graph time versus 0.326 ms parallel assign/eval/collect. The historical graph-versus-scalar row still first favored HELUT at B=32,768 in that run, demonstrating graph amortization—not end-to-end or best-native superiority. Complete receipt: [`logs/helut-native-paired-rerun-20260906T044651Z/receipt.json`](logs/helut-native-paired-rerun-20260906T044651Z/receipt.json).

That negative result exposed a real host lever. An additive phase run measured **20.576 ms** of strict output decode at B=65,536, then a preregistered change replaced 589,824 requested one-element Swift array materializations with the existing strict constant-fill pointer decoder. All exhaustive digests and timing boundaries stayed unchanged. Decode fell to **0.572 ms** (35.97× lower) and paired HELUT fell to **13.420 ms** (2.42× lower) versus a contemporaneous **7.186 ms** native median. This is a substantial recovery, not yet a crossover: HELUT remained **1.867× slower**. The remaining differential gap is mainly input packing plus graph execution; the canonical digest is large on both sides. Baseline phase receipt: [`logs/helut-native-phase-baseline-20260906T051035Z/receipt.json`](logs/helut-native-phase-baseline-20260906T051035Z/receipt.json). Optimized receipt: [`logs/helut-native-decode-pointer-20260906T053925Z/receipt.json`](logs/helut-native-decode-pointer-20260906T053925Z/receipt.json).

```bash
./Scripts/helut_boolean_bench.sh
./Scripts/helut_boolean_scale.sh
.build/release/helut --bench picorv32_netlist.json --batch 1 --degree 1024 --ticks 10
.build/release/helut --bench enigma_netlist.json --degree 1 --batch 1000 --ticks 8 --reset-hold 0
.build/release/helut --bench enigma_netlist.json --ticks 0 --bench-equiv
.build/release/helut-bench --bench Generated/Netlists/Examples/ripple4_netlist.json \
  --degree 1 --batch 256 --ticks 6 --warmup 1 --bench-distinct-lanes
```

> **Note:** Default `helut` UX remains Enigma-bombe oriented. `--bench` is the general HELUTCore clock harness. Campaign cryptanalysis stays on host Welchman / cleartext batch.

## Enigma & P1030680

Two different jobs:

| Command family | Engine | Purpose |
|----------------|--------|---------|
| `--p1030680-bombe` / default Enigma Metal run | Boolean-safe mock-PBS tensors | Parallel bombe **architecture** + decrypt path |
| `--break-p1030680` / `--campaign` | Host M4 oracle | **Cryptanalysis** (Welchman / campaign ladder) |
| `--hybrid` | GA shell+stecker × cleartext Metal/CPU `B=17576` | ASIC-esque / Stochastic Bombe ([`ASIC_CRACKER.md`](ASIC_CRACKER.md), [`stochastic-bombe.md`](directives/stochastic-bombe.md)) |

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
Hardware/RTL/                 Canonical authored and vendored Verilog/SystemVerilog
Hardware/Testbenches/         Canonical authored HDL testbenches
Hardware/artifact-manifest.json  Stable ownership, canonical paths, and compatibility policy
Generated/                    Checked-in Yosys, TensorLUT, and profile derivatives
build/                        Ignored disposable generation, simulation, and benchmark scratch
Apps/                         Application-owned hardware and integration surfaces (including Mulein)
Reference/Rust/               Portable CPU integer/KAT/Yosys consumer (independent Cargo package)
Sources/HELUTCore/            Compiler, boolean-safe mock PBS, DFF clocking, Enigma/M4 oracles, scorers
Sources/HELUTRadio/           C ABI dylib for GNU Radio / ctypes (`helut.h`)
Sources/helut/                CLI (Enigma bombe + campaign + validate; netlist argv)
Tests/HELUTTests/             Kernel, state, Enigma/M4 tests
Fixtures/                     Historical vectors, generated profile fixture, and campaign inputs
Scripts/                      Build, generation, campaign, and scorer-calibration entry points
*.v / *_netlist.json          Published compatibility wrappers/copies only; not canonical sources
paper/                        Technical write-up (`helut.tex`)
PRD*.md / phase-*.md          Design progression
```

New hardware consumers should use `Hardware/` or `Generated/` directly. Root Verilog wrappers and generated JSON/Verilog copies remain for published commands and downstream compatibility; `make hardware-check` detects drift, while `make hardware-compat-sync` performs the explicit canonical-to-root refresh.

### Portable Rust reference

`Reference/Rust/` is a separate, CPU-only integer reference. It strictly consumes the checked-in fixture-v4 profile/KAT for `E256/v2/gen0/fa246e9cba9009a4799e5a81722a9b14e9a67293d9621b45985c5f3e620865d4/fixture-v4` and the checked-in Yosys examples; it does not expose Metal, GPU, FPGA, FHE, Swift FFI, vector generation, `bless`, or promotion commands. Its E256 result is an **internal three-track parity check**, not an accepted immutable external KAT and not enough to close **E256-050**.

```bash
make rust-reference-check

# Direct commands run from the package directory so rustup discovers the
# pinned Reference/Rust/rust-toolchain.toml. They remain explicit consumers.
cd Reference/Rust
CARGO_TARGET_DIR=../../build/rust-reference cargo run --locked -- e256-kat \
  --profile ../../Fixtures/enigma256_generation.json \
  --bundle ../../Fixtures/enigma256_golden \
  --receipt ../../logs/e256-v2-gen0-nlff-search.json
CARGO_TARGET_DIR=../../build/rust-reference cargo run --locked -- yosys-parity \
  --full-adder ../../Generated/Netlists/Examples/netlist.json \
  --counter ../../Generated/Netlists/Examples/counter_netlist.json \
  --toy-isa ../../Generated/Netlists/Examples/toy_isa_netlist.json
```

The validated fixture-v4 Rust parity surface is bounded to the 1,024-byte KAT, 9 tables, 10 trace files, and 25-artifact bundle, including reciprocal decrypt. It is one consumer represented in `logs/e256-v2-gen0-fixture-v4-validation.json`; it is not a separately curated external vector set.

Cargo build output is routed to ignored `build/rust-reference/`. The Make targets select and verify Rust 1.97.1; package-local commands discover the same pin from `rust-toolchain.toml`. The package pins its direct dependencies and commits `Cargo.lock`; its isolated Linux workflow checks formatting, Clippy, tests, both verifier commands, and that the consumer leaves `Fixtures/`, `Hardware/`, and `Generated/` unchanged.

GNU Radio demo ([radioconda](https://github.com/radioconda/radioconda-installer): install [Apple Silicon .pkg](https://glare-sable.vercel.app/radioconda/radioconda-installer/radioconda-.*-MacOSX-arm64.pkg) to your home dir → activate conda → [CondaInstall](https://wiki.gnuradio.org/index.php/CondaInstall); Homebrew `gnuradio` is deprecated):

```bash
# Bootstrap (env, build, ladder of demos — start here):
#   Apps/gr-helut/README.md

make radio                                          # dylib + selftest (no GRC needed)
python3 Apps/gr-helut/examples/helut_regex_demo.py  # ctypes path
# after radioconda: conda activate base   # or: conda activate gnuradio
python Apps/gr-helut/examples/helut_edge_matcher.py --batch 10000
```

## Status (honest)

- **FHE (what “encrypted” means):** LWE/GLWE + GGSW blind rotate per `$lut`, checked against the clear netlist. The integrated full-adder receipt is exhaustive 8/8 at *N*=*n*=1024, covering-b2, BK σ=128, exact primary inputs, and stride *k*=14; 192 identity-PBS samples with explicit parallelism 8 gave σ₉₅=1,282,097.0 and a 95%-confidence 24-event bound of log₂ε=−93.80, and SING is **PASS**. The preserved *k*=14/32-sample preflight is a timed, under-sampled negative at −48.18; it executed no circuit rows. An exact 32-sample serial/parallel replay matched every bound field before the preregistered larger sample recovered the same configuration. The *k*=16/t40 PASS remains valid fallback history, not the narrowest integrated stride. This does not certify arbitrary circuits or fresh-input noise. Older **C52**–**C54** remain narrower stride-*k* SING receipts. Native *k*=1 at σ=128 is still undecodable (**C37**); noisy `cryptoPublicMS` is still open (**C26**). Encrypted PicoRV at production *N* is not claimed (**C51** is demo *N*=8).
- **Oracle path (not FHE):** trivial torus + multilinear / trivial PBS. PicoRV32 cleartext ~1.3 s compile / ~173 ms tick; Enigma M3 Metal≡cleartext at *N*=1024 **PASS**.
- **Hardness:** Decision-LWE binding + ε certificates exist, but they are different claims. The 175.7-bit figure is an interim calibrated core-SVP model for the prod-n1024-s16 row—not the measured BK σ=128 residual bound, not every calibration row, and not a blanket security proof (**H1**, **C23**). Trivial Metal graphs are not FHE.
- **Enigma host attack:** real M4 decrypt / crib-drag / stecker / campaign ladder. **P1030680 is not decrypted.** Catalog rings parked at originalIndex 417 (resume `--bombe-from 418`). Campaign fitness is cleartext Metal, not encrypted ms/row.
- **CLI:** `--bench` clocks netlists; campaign tools are Enigma-first. Homebrew: `brew install helut` (semver **0.1.0**); `--HEAD` for tip of `main`.
- **How this was built:** [`AI_DISCLOSURE.md`](AI_DISCLOSURE.md) (architect vs engine — not a **C** row).

## License

MIT — see [`LICENSE`](LICENSE). Copyright © 2026 Digital Defiance.

[`SECURITY.md`](SECURITY.md) · [`CONTRIBUTING.md`](CONTRIBUTING.md) · [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) · [`AI_DISCLOSURE.md`](AI_DISCLOSURE.md)
