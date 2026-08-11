# HELUT

**Homomorphic Edge Look-Up Tensors** — a Swift / Metal systems prototype that compiles **Yosys gate-level netlists** into a single `MPSGraph` and evaluates every LUT as a dense negacyclic matrix–vector product over $\mathbb{Z}/2^{32}\mathbb{Z}$ on Apple Silicon.

The point is not “Enigma only.” Enigma is one application. The stack is a **datapath for encrypted-shaped circuit evaluation**: combinational LUTs, sequential DFFs, batch parallelism, and CPU-scale netlists (including a **PicoRV32 RISC-V** core).

| Layer | Role |
|-------|------|
| **HELUTCore** | Yosys JSON → `MPSGraph`, mock PBS (Toeplitz LUTs), DFF clocking, batch axis |
| **`helut` CLI** | Drive netlists / apps (Enigma bombe UI is the current default front-end) |
| **Host oracles** | Boolean-faithful Enigma/M4 for cryptanalysis and validation (not Metal PBS) |

Values labeled “encrypted” in the Metal path are **mock torus polynomials** (`UInt32` vectors shaped like TFHE ciphertexts). HELUT does **not** claim end-to-end TFHE security, LWE noise, or key switching — it proves exact modular tensor graphs of real netlists can be built and clocked on commodity Apple Silicon.

Paper notes: [`paper/helut.tex`](paper/helut.tex) (PDF buildable from that tree).

**Project site:** [helut.digitaldefiance.org](https://helut.digitaldefiance.org) — stack overview, the three pre-Enigma apps, and the P1030680 campaign. Source in [`site/`](site/).

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

1. **Negacyclic matvec** — multiply in $\mathbb{Z}_{2^{32}}[X]/(X^N+1)$ as an $N\times N$ Toeplitz matrix–vector product (`N = 1024`), using native `UInt32` wraparound.
2. **LUT / mock PBS** — each Yosys `$lut` becomes one of those matvecs inside one unified `MPSGraph`.
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

### Measured PicoRV32 sketch (from the paper harness)

On the evaluation machine, compiling the PicoRV32 netlist into the tensor graph is setup-dominated (host Toeplitz expansion of thousands of LUT matrices). After warm-up, steady-state mock-encrypted ticks were on the order of **~90 ms** per clock in the reported release run — an existence proof that **CPU-scale** netlists fit the HELUT clock loop, not a claim of a secure FHE CPU.

```bash
# Graph compile only (avoids Enigma-specific runtime wiring in the current CLI)
swift run -c release helut -- picorv32_netlist.json --compile-only
```

> **Note:** The current `helut` executable’s *default runtime path* is Enigma-bombe oriented (Grundstellung seeding, ciphertext ticks). **HELUTCore** remains the general compiler/executor (`YosysGraphCompiler`, `runClockCycles`). Full PicoRV `resetn` boot harnesses follow [`PRD_App1_RISCV.md`](PRD_App1_RISCV.md); use `--compile-only` on arbitrary JSON to exercise the shared frontend today.

## Enigma & P1030680

Two different jobs:

| Command family | Engine | Purpose |
|----------------|--------|---------|
| `--p1030680-bombe` / default Enigma Metal run | Mock-PBS tensors | Parallel bombe **architecture** demo |
| `--break-p1030680` / `--campaign` | Host M4 oracle | **Cryptanalysis** (boolean-faithful) |
| `--hybrid` | GA shell+stecker × cleartext Metal/CPU `B=17576` | ASIC-esque / Stochastic Bombe ([`ASIC_CRACKER.md`](ASIC_CRACKER.md), [`stochastic-bombe.md`](stochastic-bombe.md)) |

Mock-PBS does not preserve boolean plaintext — do not treat Metal `linguistic_score` rankings as a break.

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
Sources/HELUTCore/     Compiler, mock PBS, DFF clocking, Enigma/M4 oracles, scorers
Sources/helut/         CLI (Enigma bombe + campaign + validate; netlist argv)
Tests/HELUTTests/      Kernel, state, Enigma/M4 tests
Fixtures/              Historical Enigma vectors, German corpus
*.v / *_netlist.json   Application circuits (PicoRV32, regex, tree, Enigma, …)
Scripts/               Campaign + scorer calibration
paper/                 Technical write-up (helut.tex)
PRD*.md / phase-*.md   Design progression
```

## Status (honest)

- **General HELUT:** Yosys `$lut` + sequential cells → one `MPSGraph`; batching and multi-tick clocking work; PicoRV32 compiles and has been stepped under mock encryption in the paper harness.
- **Not claimed:** real TFHE noise budget, key switching, or production FHE performance.
- **Enigma host attack:** real M4 decrypt / crib-drag / stecker / campaign ladder; P1030680 remains historically unbroken — high bigram scores without naval structure are not breaks.
- **CLI gap:** day-to-day `helut` UX is Enigma-first; arbitrary netlists are first-class in **HELUTCore** and via `--compile-only`.

## License

MIT — see [`LICENSE`](LICENSE). Copyright © 2026 Digital Defiance.
