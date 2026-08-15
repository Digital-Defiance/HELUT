# Application gallery (Phase 0.6)

Nine slots — ≥3 per pillar — each must point at a reproduce path.
Figures can lag; the **five-cell card** cannot.

Living inventory: [`claim-sheet.md`](claim-sheet.md) · Reproduce: [`../REPRODUCE.md`](../REPRODUCE.md).
Course surface: [`../textbook/chapters/applications.tex`](../textbook/chapters/applications.tex).

## Pillar I — Netlist-clocked FHE

| # | Application | Claim / bar | Reproduce |
|---|-------------|-------------|-----------|
| I.1 | Encrypted `full_adder` SING | **C6**, **C20**; **C21** (*e*=0 BK); covering noisy **C52** | `Scripts/helut_encrypted_sing.sh`; Metal boolean / crypto / covering-b1 *k*=7 |
| I.2 | Encrypted tree / regex SING | **C6** (demo *N*); regex covering **C57** @ production *N* | `--bench regex_netlist.json --degree 1024 --paths 'public-ms covering-b2' --boolean-scale-mul 7 --bk-noise-sigma 128`; tree still demo *N* |
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
| I.1–I.3 | yes (gallery figures) | **C52** covering-b1; **C57** covering-b2 regex @ production *N*. **C26**/**C56** `cryptoPublicMS` still fail. Native *k*=1 still **C37**. Tree Metal covering and PicoRV covering @ *N*=1024 remain. **C58** lut6 cut. |
| II.1–II.2 | yes | II.3 seminar-only until more receipts |
| III.1, III.3 | yes | III.2 empirical, not IND-CPA |

Next: PicoRV `lw` (48-tick prog running); covering KS *n*=512 with *k*=7; native *k*=1 at *n*=*N* (**C37**). **C67** SIGTRAP is superseded by **C69**. Figures live in `site/public/gallery/`. FHE chronology: `/projects/netlist-fhe/journal`.
