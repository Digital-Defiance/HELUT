# Mulein

Mulein is the bounded transcript-hypothesis subsystem around the Welchman diagonal board. This directory owns the cleartext hardware lane and its hardware tests. The Swift oracle remains in `Sources/HELUTCore`; Metal dispatch and campaign integration remain in `Sources/HELUTToolKit` until the planned campaign-library split can move them coherently.

## Naming

| Name | Responsibility |
|---|---|
| **Mulein Board** | The whole hypothesis-screening system: evidence geometry, board closure, parallel execution, and auditable receipts. |
| **Mulein Future Lattice** | The host-side set/DAG of bounded transcript futures and their provenance. Identity geometry, missing/extra recorded symbols, replacements, and transpositions are distinct transitions. |
| **Mulein Future Bank** | Parallel executor over settings, futures, and central-letter seeds. It shares rotor/scrambler work instead of replicating an Enigma for every lane. |
| **Mulein Splice Engine** | Geometry layer for missing or extra transmitted/recorded symbols. Informal name: **Indel Blaster 9000**. Geometry changes rotor-step alignment; it is not edge erasure. |
| **Mulein Tolerant Closure** | Exact-first diagonal-board closure with bounded active-edge erasure and physical plug-budget checks. Informal name: **Garble Blaster 9000**. |
| **Mulein Closure Core** | Scalar synthesizable closure primitive. It owns only mutable partial-involution state and reads shared menu descriptors and scrambler rows. |

Use **edge-erasure tolerance** for a suspect menu constraint. Use **splice geometry** for missing or extra characters. A tolerant survivor is only a repair hypothesis; confirmation must replay the retained geometry and erased-edge receipt exactly.

## Current layout

```text
Apps/Mulein/
├── README.md
├── rtl/
│   ├── mulein_closure_core.sv          # 26-seed scalar conformance baseline
│   ├── mulein_closure_bounded.sv       # four-edge/four-step TensorLUT fixture
│   ├── mulein_closure_seed.sv          # production single-seed held-receipt lane
│   └── mulein_future_tensorlut_top.sv  # parameterized shared-trail Future Bank
└── tests/rtl/
    ├── mulein_closure_core_tb.sv
    └── mulein_closure_bounded_tb.sv
```

The full production source/post-Yosys/clear-JSON/TensorLUT grade is generated from
`Tests/HELUTTests/MuleinFutureTensorLUTTests.swift`; it does not require a checked-in
known-key testbench literal.

Related source remains at:

- `Sources/HELUTCore/MuleinBoard.swift` — independent blind Swift closure oracle.
- `Sources/HELUTCore/MuleinFuture.swift` — typed transcript geometry, hypotheses, provenance, and execution-equivalence merging.
- `Sources/HELUTCore/SpliceMenu.swift` — earlier missing-recording geometry prototype.
- `Sources/HELUTToolKit/MuleinFutureMetal.swift` — cleartext Metal Future Bank, complete overflow drain, Swift parity oracle, and throughput grade.
- `Sources/HELUTToolKit/MuleinFutureControl.swift` — generated/P1030684 parity, repair, overflow, Greek-V, and full-range controls.
- `Sources/HELUTToolKit/MuleinFutureTensorLUTPacking.swift` — slot-major descriptor/shared-trail packing and held-receipt decoding with stable host provenance.
- `Sources/HELUTToolKit/MuleinFutureTensorLUTBench.swift` — identical complete-receipt width workload, parity checks, and measured runtime selection.
- `Sources/HELUTToolKit/MuleinFutureTensorLUTEvaluator.swift` — fail-closed Metal execution, receipt/accounting validation, held-result checks, and timeout.
- `Sources/HELUTToolKit/P1030680MuleinCampaign.swift` — identity-bound chunk planning, synchronized JSONL resume, host replay, and conservative BREAK gating.
- `Sources/HELUTToolKit/MuleinFutureManifest.swift` — deterministic finite target inventory generation and replay validation.
- `Sources/HELUTToolKit/MuleinTranscriptControls.swift` — self-generated edit controls and the P1030681/P1030714 regression.
- `Sources/HELUTToolKit/ControlMessageP1030681.swift` — separately retained source transcription, theoretical reconstruction, and final consensus layers.
- `Sources/HELUTToolKit/BombeMetal.swift` and `BombeSweep.swift` — existing campaign accelerator and orchestration; the Future Bank does not replace or invoke them for P1030680.
- `mulein_closure_core.v` — published root compatibility include. New HDL commands should use the canonical `.sv`; compatibility tests intentionally exercise the wrapper.

Repository-wide authored shared hardware is canonical under `Hardware/`, and checked-in generated derivatives are canonical under `Generated/`, as declared by `Hardware/artifact-manifest.json`. Mulein-owned RTL intentionally remains under `Apps/Mulein/`; `mulein_closure_core.v` is its fixed root compatibility wrapper. Experiments write only under ignored `build/`, and any repository-wide promotion and root-copy refresh must be explicit (`make hardware-compat-sync`).

## RTL contract

`mulein_closure_core` remains the 26-seed scalar conformance baseline. It runs exact closure first and, when requested, tries one active edge erasure after contradiction or an over-budget physical mapping. The lane exposes aggregate survivor/erasure masks and cycle/closure/drop counters.

The production path is separate: `mulein_closure_seed` evaluates one explicit seed, adds max/exact plug feasibility, and holds a full result until `result_ready`, including tag, exact/repair status, one-hot dropped-edge mask, pair/determined counts, live-state hash, and work counters. `mulein_future_tensorlut_top` instantiates a parameterized number of those lanes. A TensorLUT batch lane supplies one packed M4 trail shared by all bank slots while each slot receives its own Future-Lattice `(a,b,step)` geometry. Bank width remains parameterized, but the production campaign artifact uses **`BANK_LANES=4`**, selected by measured complete-receipt throughput rather than an assumption that wider is faster.

Neither closure lane owns rotor ROMs or edit-script parsing. The host compiles evidence-preserving splice hypotheses to finite descriptor tables; a trail producer supplies `S_0 ... S_n` once per setting. This keeps splice geometry distinct from edge erasure and avoids synthesizing a private Enigma datapath for every future/seed slot. Inputs remain stable until held results are consumed.

Current RTL bounds are 40 edges, 80 transmitted steps, and tolerance 0/1. Higher tolerance remains a Swift/Metal concern until independently cross-graded. Packed stores are combinational after Yosys lowering; a synchronous RAM wrapper would need an explicit latency protocol.

## Build and validation

The Future Bank controls require macOS Metal and the Swift release toolchain. RTL gates additionally require Icarus Verilog (`iverilog`, `vvp`) and Yosys on `PATH`.

### Swift oracle and cleartext Metal Future Bank

```bash
swift test -c release --filter MuleinFutureTests
make test-mulein-future-control
make grade-mulein-future-metal
```

`test-mulein-future-control` builds `helut-bench` and runs the full blind known-key grade. For each parity arm, it requires complete, duplicate-free equality between the independent Swift board and Metal receipts, including setting/future/seed, stable dropped-edge IDs, plug/determined counts, exactness, and the full 32-bit live-state hash. The grade covers:

- a locally encrypted fixed-key M4 message damaged with substitution, deletion, insertion, and transposition edits;
- source-attributed P1030681/P1030714 early and locally rebased late controls, including the four-cell `HMHY` blank and corrected-source futures;
- P1030684 64-setting slices for exact-first monotonicity, stable repair IDs, plug-budget repair, and transmitted step 79;
- an intentionally overflowing capacity-one queue, typed failure, attempted-count retry, and recursive range bisection, with incomplete prefixes discarded;
- Greek-V slice parity plus a Metal-only, duplicate-checked chunked drain of all 456,976 P1030684 settings retaining the published true lane/seed. The exhaustive drain checks completeness and uniqueness, not full-range Swift parity.

The historical regression is attributed to the [Hörenberg/Girard P1030681 de-garbling transcription](https://enigma.hoerenberg.com/index.php?cat=The%20U534%20messages&page=Degarbling%20the%20D%C3%B6nitz%20Message%20P1030681). It is a regression against published transcriptions, not independent scan custody; raw copy text, theoretical re-encipherment, and final consensus remain distinct. The source description is rephrased for compliance with licensing restrictions.

For a shorter development pass that skips only the Greek-V and full-range drains:

```bash
swift build -c release --product helut-bench -Xswiftc -suppress-warnings
.build/release/helut-bench --mulein-future-control-grade --mulein-future-control-quick
```

`grade-mulein-future-metal` defaults to 2,048 settings and five repetitions for each of 1, 2, 4, 8, and 16 futures. It compares duplicate-free **full** fused receipts with repeated singleton receipts, requires complete queues and the repair-free P1030684 true lane/central seed under explicit max-10/exact-10 completion budgets, and disables tolerance. Override the workload without editing source:

```bash
make grade-mulein-future-metal MULEIN_FUTURE_SETTINGS=4096 MULEIN_FUTURE_REPETITIONS=7
```

### RTL and TensorLUT conformance

```bash
make -B test-mulein-rtl
make -B synth-mulein-rtl
make -B test-mulein-bounded-rtl
make -B synth-mulein-tensorlut
swift test -c release --filter MuleinClosureTensorLUTTests
swift test -c release --filter MuleinFutureTests
swift test -c release --filter MuleinFutureTensorLUTTests/testDeltaSixAndEightGarbleSwiftOracleControls
swift test -c release --filter MuleinFutureTensorLUTTests/testProductionSourcePostYosysClearAndTensorLUTAgree
make test-mulein-future-tensorlut
make synth-mulein-future-tensorlut MULEIN_BANK_LANES=1
make emit-mulein-future-manifest
make sweep-mulein-future-tensorlut
make build-mulein-future-campaign
make plan-mulein-future-campaign
```

The production known-key grade is **PASS** at `BANK_LANES=1`. It uses a full 40-edge/80-step artifact and compares complete held receipts across source RTL, post-Yosys RTL, clear JSON simulation, and Float TensorLUT. The original four digest-bound P1030684 jobs remain unchanged: clean exact, exact negative, combined missing-group plus one post-gap garble repair, and transmitted step 79. The conformance grade submits nine additional probes after a blind Swift-oracle enumeration of both settings, all eleven work items, and all 26 seeds:

- a 72-symbol `CT[6..<78]` recording with a claimed leading Δ6 and `PT[38..<78]` crib survives at published setting/seed `VYAA/I`, exactly and with zero dropped edges (steps `38..<78`, max 77);
- a 72-symbol `CT[8..<80]` recording with a claimed leading Δ8 and `PT[40..<80]` crib survives at `VYAA/J`, exactly and with zero dropped edges (steps `40..<80`, max 79);
- the same Δ8 recording falsely claimed as Δ6 is absent at `VYAA/V`; the correct Δ8 Future is also absent at adjacent setting `VYAB/J` and adjacent seed `VYAA/K`;
- Δ6 plus one synthetic post-gap garble at crib edge 20 (`recordedIndex=52`, transmitted step 58) loses the published true candidate at tolerance 0 and recovers it at tolerance 1 by dropping exactly that stable edge;
- Δ8 plus the corresponding garble at crib edge 20 (`recordedIndex=52`, transmitted step 60) has the same exact-negative → one-edge-repair transition at the 80-step ceiling.

The fast blind-oracle composition grade passed in 0.007 s. The 13-case production run passed all four surfaces in 609.635 s and reported 44,341 LUT6, 693 DFF, 56,181 wires, and 28 levels for this one-lane grade flow. `MuleinFutureTests` separately passed 11/11, including synthetic 72→78 and 72→80 coordinate maps. These are target-shaped **P1030684 known-key controls** demonstrating bounded geometry sensitivity and one-garble composition; they do not evaluate P1030680, do not make the staged Δ6/Δ8 target manifests campaign coverage, and do not establish a decrypt. Ordinary Float TensorLUT remains cleartext, not FHE.

`emit-mulein-future-manifest` deterministically regenerates
`Fixtures/p1030680_mulein_identity_postgap_delta4.json` from the pinned strongest-menu fixture. It contains **261 entries** — 24 identity and 237 post-gap-delta4 — with complete evidence, geometry, stable edge IDs, tolerance-1 policy, fingerprint `fnv1a64-32fd2543824a62a3`, and SHA-256 `f6e85991f6f52e904988ae5c43a52023431add36710506cd155b0e69ea706ad0`. It is a finite hypothesis inventory only: generation evaluates no rotor settings and cannot establish a decrypt. The bounded campaign described below consumed only identity Future 0; the other 260 entries remain staged and unexecuted.

The emitter now accepts `MULEIN_FUTURE_DELTA` / `--mulein-future-manifest-delta` and fails closed above the existing 80-step Future-Bank envelope. Two separate operational-prior inventories extend the 72-letter recording without changing the active delta-4 artifact:

| gap | transmitted steps | immutable manifest | inventory | fingerprint | SHA-256 |
|---:|---:|---|---:|---|---|
| 6 | 78 (max step 77) | `Fixtures/p1030680_mulein_regenbogen_hannibal_identity_postgap_delta6.json` | 314 identity + 314 post-gap | `fnv1a64-cd2a80759510a7ba` | `189a40e30a32415f722fdfc75bffbb132e59059883e7c262288c31812a21b3a6` |
| 8 | 80 (max step 79) | `Fixtures/p1030680_mulein_regenbogen_hannibal_identity_postgap_delta8.json` | 314 identity + 314 post-gap | `fnv1a64-686233848aefd1b9` | `20c9905a7a541bd756786838a70c203ccd7d930b743966c9a51b5b1c94428959` |

```bash
make emit-mulein-future-manifest \
  MULEIN_FUTURE_DELTA=6 \
  MULEIN_FUTURE_MANIFEST_SOURCE=Fixtures/p1030680_regenbogen_hannibal_menus.json \
  MULEIN_FUTURE_MANIFEST=Fixtures/p1030680_mulein_regenbogen_hannibal_identity_postgap_delta6.json
make emit-mulein-future-manifest \
  MULEIN_FUTURE_DELTA=8 \
  MULEIN_FUTURE_MANIFEST_SOURCE=Fixtures/p1030680_regenbogen_hannibal_menus.json \
  MULEIN_FUTURE_MANIFEST=Fixtures/p1030680_mulein_regenbogen_hannibal_identity_postgap_delta8.json
```

Both files reuse the existing W=4 netlist. Their post-gap suffixes (`314..<628`) passed protocol-v3 plan-only validation at 5,024 chunks and 2,089,984 planned receipts each; no target setting was evaluated and no ledger was written. They are **STAGED / UNEXECUTED**, model one contiguous gap wholly before the crib, and remain non-BREAK-eligible without calibrated sparse full-message replay.

The width-qualified synthesis sweep is **PASS** for every candidate bank. Synthesis time and
size are recorded separately from the production complete-receipt benchmark:

| `BANK_LANES` | LUTs | DFFs | synthesis wall | median complete receipts/s |
|---:|---:|---:|---:|---:|
| 1 | 45,463 | 693 | 158.659 s | 233.777350172 |
| 2 | 92,059 | 1,386 | 296.261 s | 264.718510307 |
| **4** | **189,032** | **2,772** | **650.294 s** | **276.035471632 — selected** |
| 8 | 369,468 | 5,544 | 1,501.129 s | 273.889660462 |
| 16 | 758,323 | 11,088 | 3,814.859 s | 230.780129610 |

The runtime workload is 16 settings × 16 jobs × 5 repetitions in a fresh process per width.
Every width passes oracle parity, held/backpressure, consume/rearm, and tag/accounting checks and
produces the identical normalized digest `fnv1a64-17435188996435da`. Width 4 wins on measured
complete receipts, not synthesis time, graph size, or RAM availability. Selection receipt:
`logs/mulein-future-tensorlut-selection.json`; per-width logs:
`build/mulein/mulein_future_bank{1,2,4,8,16}_bench.txt`.

The selected artifact is `build/mulein/mulein_future_bank4_lut6.json`, SHA-256
`6a502ae4a21984c6b5e443c6bd14c39c97976dec13ce48401294330af5d31872`, with 189,032
LUT6, 2,772 DFF, 205,177 wires, and 28 levels.

### Bounded P1030680 campaign

The protocol-v3 runner SHA-256-binds one immutable manifest snapshot, netlist, bank width, graph,
protocol, and exact shell/Future/setting plan. Its ledger accepts only an exact ordered plan
prefix and records every canonical per-job receipt projection, enabling digest recomputation and
derived hit/BREAK-gate state. Every persisted hit is host/scoring-replayed; a prior valid gate
halts before evaluator work and cannot print a no-break completion. Semantic drift, sparse or
reordered rows, post-gate records, and candidate deletion fail closed. Atomic non-truncating open
and one retained exclusive descriptor enforce a single writer through final synchronization.
Metal status, tags, seeds, config failures, complete counts, held receipts, consume/rearm, and
timeout are checked. Only exact identity/no-drop positives may enter existing completion/scoring.
Repaired and post-gap positives remain non-BREAK-eligible until correction replay or Future-aware
full-message geometry exists. The runner never announces a break automatically.

```bash
.build/release/helut-bombe \
  --mulein-future-campaign \
  --mulein-future-manifest Fixtures/p1030680_mulein_identity_postgap_delta4.json \
  --mulein-future-netlist build/mulein/mulein_future_bank4_lut6.json \
  --mulein-bank-lanes 4 \
  --subspace potsdam-neighbourhood --rings AAAA \
  --shell-from 0 --shell-count 1 \
  --setting-from 0 --setting-count 256 \
  --future-from 0 --future-count 1 \
  --chunk-settings 16 --tensor-batch 16 \
  --campaign-ledger logs/p1030680-mulein-unified-smoke-v3.jsonl
```

Protocol-v3 run `sha256-e6dc10d45b2e2e9fb4fbc69936fd0909a89dbecc4d53063cb415c58232fc1360`
completed shell 0 `B/beta/IV-III-VIII/AAAA`, identity Future 0, settings `0..<256`:
**16/16 synced chunks, 6,656/6,656 canonical receipt projections, zero hardware positives,
zero BREAK gates**. Exact-prefix resume revalidated 16/16 and appended nothing. Durable ledger:
`logs/p1030680-mulein-unified-smoke-v3.jsonl`, SHA-256
`687d08383111b90b284ca08496d5ba02c9d0b560c17613c2e56283362b1f7e7d`.

This is one clean local negative, not full inventory coverage. The other 260 manifest Futures,
settings `256..<456976`, other shells, and the legacy tolerance/indel/middle-ring/catalog
remainders stay open. P1030680 remains unbroken.

The scalar RTL gate compiles through the root compatibility include and runs four-state-aware protocol/closure controls. Yosys writes generated artifacts under ignored `build/mulein`. The bounded source/post-Yosys fixtures, blind Swift row oracle, Yosys JSON simulator, and nine-lane Float TensorLUT batch must emit identical receipts; a changed scrambler row is a required negative control.

All mechanism, conformance, benchmark, and campaign execution here is cleartext. Ordinary Metal
and Float TensorLUT are **not FHE**, and receipt throughput is not encrypted tick rate. The
known-key conformance and width-benchmark commands do not read P1030680. Manifest generation
reads pinned target evidence but evaluates no settings. Only the explicit campaign command above
executes target settings, and its evidence is bounded to one Future, one shell, and 256 settings;
it establishes no decrypt. Operational status remains canonical in `BREAK_P1030680.md`.

## Architecture direction

1. The Future Lattice retains evidence coordinates and a stable hypothesis ID; it never flattens splice or repair provenance into a bare `BombeMenu`.
2. A Scrambler Trail Engine computes `S_0 ... S_n` once per setting and shell.
3. Future/seed lanes read that shared trail and keep only mutable closure state private.
4. A sparse hit queue records setting, future, seed, repair mask, budget counts, and overflow status.
5. The host replays every hit with the blind Swift oracle before completion or language scoring.

## Staged repository plan

1. Keep the current ownership split while the scalar RTL and Swift oracle are cross-graded.
2. Add the typed Future Lattice to `HELUTCore`; preserve adapters for existing `BombeMenu` and `SplicedMenu` callers.
3. Add the cleartext future-batch Metal engine to `HELUTToolKit`, behind known-key controls and without changing the target campaign path by default.
4. Once the public API is stable, move Welchman/Mulein/splice/Metal campaign code together into the planned `HELUTBombe` package target. Do not move one file at a time across the dependency boundary.
5. Relocate other root HDL/netlists only through a separate manifest-backed migration that updates every reproduction command and keeps compatibility paths for a deprecation window.

Operational campaign status and evidence remain canonical in `BREAK_P1030680.md`; this README defines software ownership and validation scope only.
