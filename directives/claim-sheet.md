# Claim inventory (living)

**Bar:** anything we say in public must be **reproducible** from this repo (`REPRODUCE.md` + logs/tests). IDs are for bookkeeping, not a premiere freeze — science moves; update rows when evidence moves.

Doctrine: [`research-release.md`](research-release.md) · Cookbook: [`parameter-cookbook.md`](parameter-cookbook.md) · Reproduce: [`../REPRODUCE.md`](../REPRODUCE.md) · Beyond today: [`research-trajectory.md`](research-trajectory.md) · Course book: [`../textbook/`](../textbook/) (agents: `.cursor/rules/living-textbook.mdc`) · Campaign report: [`../writeup.tex`](../writeup.tex) (agents: `.cursor/rules/writeup.mdc`).

**How to talk about it:** lead with what runs and what it does *not* prove. Discovery continues after any disclosure.

---

## Reproducible results (C)

| ID | Result | How to reproduce | Receipts |
|----|--------|------------------|----------|
| **C1** | Yosys `$lut`/DFF → Metal/CPU tensor eval (cleartext / trivial oracle) | benches / equiv tests | PicoRV · Enigma stream · ~40M settings/s campaign batch |
| **C2** | Welchman path breaks known P1030684 end-to-end | campaign control | 361 s · 16B settings · 10 plugs |
| **C3** | ≤10-plug / SAT kill chain removes ghosts | ghost forensics | writeup / BREAK |
| **C4** | Encrypted LWE/GLWE + GGSW BR per `$lut` (publicMS / secret) | `--bench-encrypted` | seam tests · EncryptedNetlistSim · full_adder through *N*=1024 |
| **C5** | Certificates on encrypted ticks (noise, *ε*, calibrated hardness, noisy-BK **measured**) | `--hardness-table` · `--measure-bk-noise` · SING cert lines | cookbook production row · **C22** |
| **C6** | Encrypted ≡ clear multi-netlist SING | `Scripts/helut_encrypted_sing.sh` | `logs/helut-encrypted-*.log` · adder *N*≤1024 |
| **C7** | Metal 1-LUT BR microbench | `--bench-encrypted-micro --degree 64` | fused ~50.3 s/BR · persist-schoolbook **0.001 s/BR** (**C17**) · NTT-tile **0.010 s/BR** (**C18**, `--metal-br-tile 64`) |
| **C8** | TensorLUT M4 baseline *F*<sub>crypto</sub>=0 + Verilog emit | TensorLUT CLI / Phase 21 | `enigma_m4_tensorlut_baseline.v` |
| **C9** | Stecker involution sandwich · blind 3-pair PASS | Phase 21 protocol | involution logs / journal |
| **C10** | Enigma256 reciprocity · fail-closed / bijection | E256 tests | `Enigma256.md` · fixtures |
| **C11** | Potsdam/Plaice keys ≠ P1030680 | exhaustion | BREAK table |
| **C12** | Windowed discriminator vs whole-message turnover flaw | discriminator design | 2 219 boards · writeup §4 |
| **C13** | Metal tiled-kernel BR @ *N*=1024 | `--bench-encrypted-micro --degree 1024 --trials 2` | 3.645 s/BR · bits 0+1 PASS · `logs/helut-encrypted-micro-n1024-tiled.log` |
| **C14** | Metal full_adder SING @ *N*=1024 | `--bench-encrypted --paths 'blind-rotate-metal public-ms boolean'` | boolean 90.6 s / 8 rows (11.3 s/row); crypto 175.6 s (22.0 s/row) |
| **C15** | Metal netlist-scheduled SING @ *N*=1024 | `--metal-netlist-only --degree 1024 --vectors 8` | 91.9 s / 8 rows (11.5 s/row) · tiled-kernel lowering · `logs/helut-encrypted-n1024-metal-netlist-sing.log` |
| **C16** | Metal fused EP kernel (Phase 2.2) | `--bench-encrypted-micro --degree 1024 --trials 2` · boolean SING | **1.043 s/BR** @ *N*=1024 (gpu 0.99 s) · N=64 tiled 0.043 s/BR · boolean SING 25.1 s / 8 rows (3.14 s/row) · `logs/helut-encrypted-micro-n1024-ep.log` · `logs/helut-encrypted-n1024-metal-sing-ep.log` |
| **C17** | GPU-resident BR tile (Phase 2.3) | `--bench-encrypted-micro --degree 1024 --trials 2` · boolean SING | **0.519 s/BR** @ *N*=1024 (gpu 0.50 s, RSS 68 MiB) · N=64 **0.001 s/BR** · boolean SING **12.2 s / 8** (1.52 s/row) · `logs/helut-encrypted-micro-n1024-persist.log` · `logs/helut-encrypted-n1024-metal-sing-persist.log` |
| **C18** | Metal 3-prime NTT persist BR (Phase 2 NTT) | `make test-metal-p1` · `--bench-encrypted-micro --degree 1024 --trials 2 --warmup 1` · boolean SING | CPU+Metal NTT ≡ schoolbook (19 tests) · **0.433 s/BR** @ *N*=1024 (gpu 0.43 s, RSS 148 MiB) · N=64 tiled **0.010 s/BR** · boolean SING **15.6 s / 8** (1.95 s/row) · `logs/helut-ntt-cert.log` · `logs/helut-encrypted-micro-n1024-ntt.log` · `logs/helut-encrypted-micro-n64-ntt.log` · `logs/helut-encrypted-n1024-metal-sing-ntt.log` |
| **C19** | TensorLUT continuous→discrete Theorem 1 | `swift test -c release --filter testTensorLUTFormalCertificate` | 6 lemmas hold (`π`, MSE, \(F\), emitter, involution, freeze) · `directives/tensorlut-theorem.md` · `TensorLUTFormal.certificate()` |
| **C20** | Wavefront-parallel independent `$lut` BRs | `--bench-encrypted --paths 'blind-rotate-metal public-ms boolean'` · N=1024×8 | boolean SING **10.6 s / 8** (1.33 s/row) vs **C17** 12.2 s / **C18** 15.6 s · fused 3-prime NTT micro **0.420 s/BR** · `logs/helut-encrypted-n1024-metal-sing-par.log` · `logs/helut-encrypted-micro-n1024-ntt3.log` |
| **C21** | Metal cryptoPublicMS ℓ=2 SING @ *N*=1024 | `--bench-encrypted --paths 'blind-rotate-metal public-ms crypto'` · N=1024×8 | **11.38 s / 8** (1.42 s/row) vs **C14** 175.6 s · PASS · `logs/helut-encrypted-n1024-metal-sing-crypto.log` |
| **C22** | Measured noisy-BK residual → *B*<sub>bk</sub> / σ̂ | `--measure-bk-noise --degree 8 --trials 8 --bk-noise 64` · `--degree 128 --trials 4` | Covering gadget: *N*=8 inject *B*=64 → max\|*e*\|=11173, σ̂=6396; *N*=128 (same as `.crypto`, ℓ=4) → max\|*e*\|=2.42×10⁶, σ̂=1.47×10⁶ ≪ δ/2 but Gaussian εlog2≈−23.5 (not −64); noiseless → 0; full_adder ≡ clear · `logs/helut-noisy-bk-measure.log` · `logs/helut-noisy-bk-measure-n128.log` |
| **C23** | Native Sage lattice-estimator fill-in | `./Scripts/helut_sage_estimate.sh` | SageMath 10.9 osx-arm64 (`~/Applications/SageMath-10-9.app`); all 8 pending rows filled · prod-n1024-s16 estimator **180.2** vs HELUT **175.7** (\|Δ\|=4.5 ≤ 16) · 4/8 anchors within 16-bit tolerance · `logs/helut-estimator-results.json` · `logs/helut-sage-estimator-run.log` |
| **C24** | Enigma256 SoftBus Theorem 2 (reciprocity / fail-closed) | `swift test -c release --filter testEnigma256FormalCertificate` | 5 lemmas hold (bijection, reciprocity, stream RT, day-key involutions, coupledCubic6 reject) · `directives/enigma256-theorem.md` · `Enigma256Formal.certificate()` · builds on empirical **C10** |
| **C25** | TensorLUT Theorem 1 corollary (emitter–discrete + involution under freeze) | `swift test -c release --filter testTensorLUTFormalCorollaryCertificate` | 2 lemmas hold · `TensorLUTFormal.corollaryCertificate()` · `directives/tensorlut-theorem.md` §corollary · still not melt completeness |
| **C26** | Noisy-BK identity residual @ *N*=1024 (product-shaped) | `--measure-bk-noise --degree 1024 --trials 2 --bk-noise 64` (and `--bk-noise 4`) | Noiseless → *B*<sub>bk</sub>=0. Inject *B*=64: both `cryptoPublicMS` / `crypto` **undecodable** (max\|*e*\| ≫ δ/2). Inject *B*=4: `crypto` ∞-norm OK but εlog2≈−1 (not −64); `cryptoPublicMS` still undecodable. Product SING stays *e*=0 BK. · `logs/helut-noisy-bk-measure-n1024.log` |
| **C27** | Exact public-MS covering only at *N*∈{8,128} under *q*=2³² | `swift test -c release --filter testGGSWPublicMSCoveringCertificate` | Theorem 3: *g₀*=*δ* ∧ covering ⇒ (1+log₂ *N*) \| 32. Among {8…2048}, only 8 and 128. *N*=1024 `cryptoPublicMS` product 11·2=22≠32. · `directives/ggsw-public-ms-covering.md` · `GGSWPublicMSCovering.certificate()` |

---

## Open science / hedges (H) — say with the asterisk

| ID | Open item | Honest asterisk |
|----|-----------|-----------------|
| **H1** | ~176‑bit calibrated @ production (*n*,*σ*) | **C23:** estimator JSON filled (native Sage 10.9). Production prod-n1024-s16: HELUT 175.7 vs estimator **180.2** (\|Δ\|=4.5). 4/8 anchors within 16-bit tolerance; demo-N8, classic-n630, n1024-s17, n2048-s16 exceed it. Do not quote 176 as estimator cost on every row. |
| **H2** | Multi-LUT encrypted @ large *N* | **Closed 2026-08-12:** `rotationPower` / pack now keep Z_{2N}; full_adder SING PASS @ N=256/512/1024. Was arity-3 pack overflowing 256·2N headroom. |
| **H3** | Metal encrypted @ *N*=1024 | **C20** boolean **10.6 s / 8**; **C21** crypto ℓ=2 **11.38 s / 8** (was **C14** 175.6 s). Micro fused 3-prime **0.420 s/BR**. Fused megagraph DNF. |
| **H4** | Noisy BK in product path | **C22** covering *N*=8/*N*=128; **C26** *N*=1024 inject fails; **C27** under *q*=2³² exact public-MS covering only at *N*∈{8,128} (*N*=1024 cannot be both *g₀*=*δ* and covering). Default Metal SING still *e*=0 BK. ε≤2⁻⁶⁴ at production *N* needs new (*q*,*N*) or approximate gadget. |
| **H5** | `*PublicMS` gadgets (*g*<sub>0</sub>=*δ*) | On-lattice intent; does not alone clear H2 |
| **H6** | TensorLUT / quarantine vs campaign | Parallel research — not P1030680 plaintext |
| **H7** | Catalog / Regenbogen / UEBUNG | Negatives / not-BREAK as graded; middle ring ≠A untested; catalog parked @417, resume `--bombe-from 418` |

---

## Non-implications (N)

Do not let prose imply: new lattice assumption; “we invented TFHE”; production keys without estimator; mock-torus = FHE; P1030680 decrypted; campaign fitness = encrypted tick rate; TensorLUT = U‑534 break; side-channels measured; quantum attacks analyzed. Wild ideas in [`potential-avenues.md`](potential-avenues.md) are **trajectory**, not current results.

---

## Encrypted envelope (H2) — closed 2026-08-12

| N | XOR / chain | full_adder SING |
|---|-------------|-----------------|
| ≤128 | PASS | PASS |
| 256–1024 | PASS | **PASS** (fix: Z_{2N} pack / `rotationPower`) |
