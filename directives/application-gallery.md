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
| II.2 | Stecker involution sandwich / blind 3-pair | **C9**, **C19**, **C25** | Formal certs + Phase 21 protocol. Swift-free, Linux CI: `python3 Scripts/tensorlut_math_ref.py` and `python3 Scripts/toy_cipher_demo.py` (**R1**/**R2**, not a new **C**) |
| II.3 | Shatter vs hold under \(\lambda\) | empirical (seminar) | Campaign ledger Phase 21; **not** a decrypt (**H6**) |

## Pillar III — Polymorphic SoftBus

| # | Application | Claim / bar | Reproduce |
|---|-------------|-------------|-----------|
| III.1 | Bounded fixture-v4 reciprocity | **C10**, **C24**; experimental receipt, **E256-003 OPEN** pending human acceptance | `E256/v2/gen0/fa246e9cba9009a4799e5a81722a9b14e9a67293d9621b45985c5f3e620865d4/fixture-v4`; center `A_i^-1(A_i(x) XOR k_i)`; host derives and transports `(payload, centerMask, absoluteByteCounter)` and RTL validates the counter (no RTL HMAC). KAT: 1,024 bytes / 9 tables / 10 traces / 25 artifacts; formal 1/1; suite 49/49; equality 260/65536, z=0.250. Receipt: `logs/e256-v2-gen0-fixture-v4-validation.json` |
| III.2 | Fixture-v4 TensorLUT scramble-cone grade | empirical, bounded optimizer failure only | 366 LUT6 with independent `center_mask`; `blue_hold`, `final_crypto -291592.781250`, `final_nonbinary 1217`. Not HMAC, not the full core, and not a security level or work factor |
| III.3 | Fixture-v4 profile-integrity + KAT publication guards | **C10**, **C24**; fail closed | `testCanonicalGoldenPublicationRejectsMismatchedProfile`; `testProfileKATSplitPublicationFailsClosed`; formal integrity |

## Status

| Slot | Five-cell ready? | Notes |
|------|------------------|-------|
| I.1–I.3 | yes (gallery figures) | **C52** covering-b1; **C57** covering-b2 regex @ production *N*. **C26**/**C56** `cryptoPublicMS` still fail. Native *k*=1 still **C37**. Tree Metal covering and PicoRV covering @ *N*=1024 remain. **C58** lut6 cut. |
| II.1–II.2 | yes | II.3 seminar-only until more receipts |
| III.1, III.3 | receipts present; acceptance OPEN | III.2 is empirical optimizer evidence. Fixture-v4 is experimental and not for real data; no IND-CPA, HMAC-security, or external-cryptanalysis claim. |

Next: PicoRV `lw` (48-tick prog running); native *k*=1 at *n*=*N* (**C37**). **C69** now records covering KS *n*=256 and *n*=512 PASS; the old *n*=512 FAIL is withdrawn as a determinism artifact. **C67** SIGTRAP is superseded by **C69**. Figures live in `site/public/gallery/`. FHE chronology: `/projects/netlist-fhe/journal`.
