# Claim inventory (living)

**Bar:** anything we say in public must be **reproducible** from this repo (`REPRODUCE.md` + logs/tests). IDs are for bookkeeping, not a premiere freeze — science moves; update rows when evidence moves.

Doctrine: [`research-release.md`](research-release.md) · Cookbook: [`parameter-cookbook.md`](parameter-cookbook.md) · Reproduce: [`../REPRODUCE.md`](../REPRODUCE.md) · Beyond today: [`research-trajectory.md`](research-trajectory.md)

**How to talk about it:** lead with what runs and what it does *not* prove. Discovery continues after any disclosure.

---

## Reproducible results (C)

| ID | Result | How to reproduce | Receipts |
|----|--------|------------------|----------|
| **C1** | Yosys `$lut`/DFF → Metal/CPU tensor eval (cleartext / trivial oracle) | benches / equiv tests | PicoRV · Enigma stream · ~40M settings/s campaign batch |
| **C2** | Welchman path breaks known P1030684 end-to-end | campaign control | 361 s · 16B settings · 10 plugs |
| **C3** | ≤10-plug / SAT kill chain removes ghosts | ghost forensics | writeup / BREAK |
| **C4** | Encrypted LWE/GLWE + GGSW BR per `$lut` (publicMS / secret) | `--bench-encrypted` | seam tests · EncryptedNetlistSim · full_adder through *N*=1024 |
| **C5** | Certificates on encrypted ticks (noise, *ε*, calibrated hardness, noisy-BK model) | `--hardness-table` · SING cert lines | cookbook production row |
| **C6** | Encrypted ≡ clear multi-netlist SING | `Scripts/helut_encrypted_sing.sh` | `logs/helut-encrypted-*.log` · adder *N*≤1024 |
| **C7** | Metal 1-LUT BR microbench | `--bench-encrypted-micro --degree 64` | ~50.3 s/BR · `logs/helut-encrypted-micro-n64.log` |
| **C8** | TensorLUT M4 baseline *F*<sub>crypto</sub>=0 + Verilog emit | TensorLUT CLI / Phase 21 | `enigma_m4_tensorlut_baseline.v` |
| **C9** | Stecker involution sandwich · blind 3-pair PASS | Phase 21 protocol | involution logs / journal |
| **C10** | Enigma256 reciprocity · fail-closed / bijection | E256 tests | `Enigma256.md` · fixtures |
| **C11** | Potsdam/Plaice keys ≠ P1030680 | exhaustion | BREAK table |
| **C12** | Windowed discriminator vs whole-message turnover flaw | discriminator design | 2 219 boards · writeup §4 |

---

## Open science / hedges (H) — say with the asterisk

| ID | Open item | Honest asterisk |
|----|-----------|-----------------|
| **H1** | ~176‑bit calibrated @ production (*n*,*σ*) | ≠ lattice-estimator until Sage fills pending JSON |
| **H2** | Multi-LUT encrypted @ large *N* | **Closed 2026-08-12:** `rotationPower` / pack now keep Z_{2N}; full_adder SING PASS @ N=256/512/1024. Was arity-3 pack overflowing 256·2N headroom. |
| **H3** | Metal encrypted @ *N*=1024 | **In flight:** micro PID harness; after HARDNESS spends long CPU in MPSGraph build (`externalProduct` / `negacyclicPolyMul`). Log: `logs/helut-encrypted-micro-n1024.log`. N=64 ≈48 s/BR PASS. |
| **H4** | Noisy BK in product path | Depth **modeled**; BK encrypt still noiseless |
| **H5** | `*PublicMS` gadgets (*g*<sub>0</sub>=*δ*) | On-lattice intent; does not alone clear H2 |
| **H6** | TensorLUT / quarantine vs campaign | Parallel research — not P1030680 plaintext |
| **H7** | Catalog / Regenbogen / UEBUNG | Negatives / not-BREAK as graded; middle ring ≠A untested; catalog @265 |

---

## Non-implications (N)

Do not let prose imply: new lattice assumption; “we invented TFHE”; production keys without estimator; mock-torus = FHE; P1030680 decrypted; campaign fitness = encrypted tick rate; TensorLUT = U‑534 break; side-channels measured; quantum attacks analyzed. Wild ideas in [`potential-avenues.md`](potential-avenues.md) are **trajectory**, not current results.

---

## Encrypted envelope (H2) — closed 2026-08-12

| N | XOR / chain | full_adder SING |
|---|-------------|-----------------|
| ≤128 | PASS | PASS |
| 256–1024 | PASS | **PASS** (fix: Z_{2N} pack / `rotationPower`) |
