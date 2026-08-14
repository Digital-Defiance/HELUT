# Application gallery (Phase 0.6)

Nine slots — ≥3 per pillar — each must point at a reproduce path.
Figures can lag; the **five-cell card** cannot.

Living inventory: [`claim-sheet.md`](claim-sheet.md) · Reproduce: [`../REPRODUCE.md`](../REPRODUCE.md).
Course surface: [`../textbook/chapters/applications.tex`](../textbook/chapters/applications.tex).

## Pillar I — Netlist-clocked FHE

| # | Application | Claim / bar | Reproduce |
|---|-------------|-------------|-----------|
| I.1 | Encrypted `full_adder` SING | **C6**, **C20**/**C21** | `Scripts/helut_encrypted_sing.sh`; Metal boolean / crypto paths |
| I.2 | Encrypted tree / regex SING | **C6** (demo *N*) | `--bench tree_netlist.json` / `regex_netlist.json --bench-encrypted --sing` |
| I.3 | Hardness + noisy-BK certificates | **C5**, **C22**, **C23**, **C52** | `--hardness-table`; `--measure-bk-noise`; `Scripts/helut_sage_estimate.sh`; covering-b1 *k*=7 |

Shape laboratory (oracle, not FHE claim): decision tree / regex / PicoRV32 (**C1**) — labeled distinct from I.1–I.3.

## Pillar II — Differentiable hardware

| # | Application | Claim / bar | Reproduce |
|---|-------------|-------------|-----------|
| II.1 | M4 TensorLUT baseline emit | **C8** | TensorLUT CLI / Phase 21 baseline Verilog |
| II.2 | Stecker involution sandwich / blind 3-pair | **C9**, **C19**, **C25** | Formal certs + Phase 21 protocol |
| II.3 | Shatter vs hold under \(\lambda\) | empirical (seminar) | Campaign ledger Phase 21; **not** a decrypt (**H6**) |

## Pillar III — Polymorphic SoftBus

| # | Application | Claim / bar | Reproduce |
|---|-------------|-------------|-----------|
| III.1 | SoftBus reciprocity / bijection | **C10**, **C24** | `testEnigma256FormalCertificate`; `Scripts/enigma256_bijection.sh` |
| III.2 | Red battery (TensorLUT / KPA / `ent`) | empirical grades | `Scripts/enigma256_red_battery.sh`; logs under `logs/enigma256-*` |
| III.3 | Fail-closed NLFF harden | **C24** clause 5 | `Enigma256Formal.checkFailClosedCoupling` |

## Status

| Slot | Five-cell ready? | Notes |
|------|------------------|-------|
| I.1–I.3 | yes (partial figures) | **C52** covering Track A *N*=1024 σ=128 *k*=7 (ε + SING). **C26** `cryptoPublicMS` inject still graded fail. Native *k*=1 still **C37**. |
| II.1–II.2 | yes | II.3 seminar-only until more receipts |
| III.1, III.3 | yes | III.2 empirical, not IND-CPA |

Next: site/paper figures; encrypted tree/regex Metal SING at production *N* if GPU free.
