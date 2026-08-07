# Roadmap: The Differentiable Hardware Paradigm

Living inventory: [`directives/claim-sheet.md`](directives/claim-sheet.md) ·
Disclosure bar: [`directives/research-release.md`](directives/research-release.md) ·
Discovery path: [`directives/research-trajectory.md`](directives/research-trajectory.md) ·
Course book: [`textbook/`](textbook/) · Campaign ledger: [`BREAK_P1030680.md`](BREAK_P1030680.md).

**North star (disclosure):** HELUT is a three-pillar stack with machine-checked TensorLUT
structure, certified netlist-clocked torus FHE on Apple graph hardware, and fail-closed
polymorphic SoftBus — not another TFHE library and not a U-534 decrypt.

Campaign catalog (Welchman rings) may burn in the background. Do **not** mix campaign
fitness into FHE prose (**N6**). Do **not** treat avenues as claims until they have a
**C** row + reproduce command.

**Product shape (parallel track):** HELUT must become a **library + thin binaries +
Apps/** that researchers can extend — not one Enigma megabin. See
[`directives/packaging-roadmap.md`](directives/packaging-roadmap.md).

---

## Phase 0.9 — 57-day release kill plan (ACTIVE · start 2026-08-13)

Goal: kill remaining asterisks that block an undeniable drop, and land **2–3 mic-drop
demos**. Not more microbench noise. Epoch at plan start: **C36** (covering-b1 meets
ε≤2⁻⁶⁴ through inject *B*=32; torus *B*~128 still open).

### Mic-drop milestones (ordered)

| # | Milestone | Success bar | First experiment | Status |
|---|-----------|-------------|------------------|--------|
| **M5** | Push-button grand audit | `./Scripts/helut_grand_audit.sh` runs formal certs + Sage (**C23**) + short SING; `--full` adds Metal C20/C21; stamps git SHA into textbook | Compose existing scripts | **landed** (default short SING is CPU-only; `--full` Metal) |
| **M3** | Close **H4** at torus scale | covering gadget @ *N*=1024, inject ~128 (σ≈2⁻²⁵), ε≤2⁻⁶⁴, Metal SING PASS. Grade B OK: covering Track A, not `cryptoPublicMS` | stride-*k* + native-*δ* public-MS | **landed C52** (*k*=7 covering-b1 σ=128: εlog2≈−170 / 8 trials + Metal secret/public-ms SING). Native *k*=1 and `cryptoPublicMS` remain graded elsewhere |
| **M2** | TensorLUT depth squeeze | ≥10% LUT or multiplicative-depth cut on tiny ZK/FHE bottleneck; bit-exact Verilog snap | NAND / 4-bit CSA first — not full SHA-256 | **C42** CSA vs ripple LUT2 11→8 (−27%) + SING; λ-melt still stretch |
| **M1** | Encrypted soft-CPU tick | Toy ISA (`NOP`/`ADD`, ≪50 LUTs) @ *N*=1024 encrypted + DFF host clock, SING PASS. **Not** full PicoRV32 | Encrypted sequential seam | **C38** counter + **C40** NOP/ADD ISA Metal *N*=1024 SING PASS |
| **M4** | E256 round inside Torus FHE | 1-byte / 1-round SoftBus slice under GGSW Metal SING | Needs M1 seam or combinational round netlist | **C39** frozen scramble Metal *N*=1024 SING PASS (not live BRAM / NLFF) |

### Cut rules

- If **M3** or **M1** is red past day 35 → park **M2**; ship **M4** only if sequential/combinational encrypted path is already green.
- Full PicoRV32 encrypted boot and full SHA-256 depth win are **post-drop** unless toy bars land early.
- **H1** stays printed (estimator vs core-SVP). **H2** dead. **H3** soft-closed by C20/C21. **H5–H7** not release blockers.

### Today sprint (do in order; parallelize M3 with M5)

1. Write this section (done) → implement **M5** `helut_grand_audit.sh`.
2. **M3:** add Gaussian BK inject + measure covering-b1 @ σ≈2⁻²⁵ / *B*~128.
3. **M1:** **C38** counter + **C40** NOP/ADD ISA SING.
4. **M4:** **C39** frozen 1-round E256 scramble Metal SING.
5. Only if bandwidth remains → TensorLUT depth fitness (**M2**).

### Explicit non-goals this sprint

- Campaign catalog / middle ring (**H7**).
- Avenue 2 self-mutating dark PicoRV as a claim.
- Quoting Welchman M/s next to encrypted ms/row (**N6**).

Detail / discovery notes: [`directives/research-trajectory.md`](directives/research-trajectory.md).

---

## Phase 0.95 — Audience punch list (reviewer)

Answers to an outside review of the shipped repo. None of these are **C** rows,
and none of them touch production Metal. Status below means "the artifact exists
and its script exits 0 in Linux CI"; a human still has to read the prose before
any of it counts as stronger than the **C** row it describes
([`directives/research-release.md`](directives/research-release.md) §Human gate).

| # | Punch | Why it blocks outsiders | Artifact | Status |
|---|-------|-------------------------|----------|--------|
| **R1** | CPU-only, dependency-free math reference | Production FHE and the λ-squeeze live in Swift `MPSGraph` on Apple Silicon. Even `--cpu-only` HELUT needs the Swift stack, so Linux and Windows readers hit a wall at step one. | `Scripts/tensorlut_math_ref.py` — the objective \(F=F_{\mathrm{crypto}}-\lambda\pi\) and the six **C19** checks, stdlib only. `EncryptedNetlistSim` deliberately not ported. | Ships. Linux CI green; Swift `testTensorLUTFormalCertificate` PASS. Executable checks, not a formal proof. Not a **C** row. |
| **R2** | Toy cipher, the smallest honest example | A 35-year scope hides the actual idea. Reviewer asked for two ciphers of the same type, one sound and one broken by design, and a demonstration of telling them apart. | `Scripts/toy_cipher_demo.py` — one SPN skeleton, PRESENT S-box vs an invertible affine S-box. Four distinguishers: DDT 4 vs 16, black-box XOR identity, one-known-pair recovery at zero key search, LUT INIT affineness. | Ships. Linux CI green. Yosys synthesis of the toy into a real netlist is still open. |
| **R3** | Distillation of Theorem 1 | Nobody installs Swift to learn an invariant. The statement was buried in `TensorLUTFormal` plus `directives/tensorlut-theorem.md`. | [`directives/theorem-1-plain.md`](directives/theorem-1-plain.md) — setup, six clauses, and an explicit list of what they do not give. Uniqueness at \(w=t\) attributed to **C44**, separable case only. | Ships. Uniqueness overclaim removed. Needs a human read before it is quoted. |
| **R4** | \(q=2^{32}\) vs \(q=2\) | Fair question: is the 32-bit torus a lattice requirement or a register artifact? | [`directives/q-32-vs-q-2.md`](directives/q-32-vs-q-2.md) — systems freeze, not a theorem; the covering lemmas are what actually depend on the word size (**C27**, degrees 8 and 128); the continuous-LUT side is bit-valued already and is where newcomers should start. | Ships, with the \(q=2\) degenerate case asserted as a negative in Python. Binary-modulus FHE remains an open experiment, not a **C** row. |
| **R5** | Outsider on-ramp | Four scattered markdown files answered a "too much scaffolding" critique with more scaffolding. | [`INTRO.md`](INTRO.md) — self-contained, no claim IDs, honest limits. [`REVIEWER.md`](REVIEWER.md) is the ledger-side map. | Ships. |
| **R6** | Five-page note for a maths audience | Reviewer point: do not chuck the repo at r/math, reduce to the essence and ask about that. Needs a specific question, not a tour. | [`note/lut-relaxation.tex`](note/lut-relaxation.tex) → `make note`. Toy-cipher table, the multilinear relaxation, propositions with receipts, the exact-penalty threshold, then two narrow open questions. Probes: `Scripts/lambda_threshold_probe.py`, `Scripts/penalty_threshold.py`. | Ships, 5 pages. |
| **R7** | \(\lambda\)-threshold: was it open? | We nearly posted a solved problem as an open question. | **No.** Maximizing \(F_\lambda\) is minimizing \(f+\lambda\pi\), the classical concave exact penalty for 0–1 programming: Raghavachari (1969), Giannessi–Niccolucci (1976) for the nonlinear case, Kalantari–Rosen (1982) for the bound. Sufficient condition \(\lambda\ge\tfrac12\sup\lambda_{\max}(\nabla^2 f)\); measured \(=2+\sqrt3\approx 3.732\) on the two-LUT topology, against an observed crossover in \((2,4]\). | Literature-resolved, **not** a new theorem. Cited in the note. Still open and now narrower: how the bound scales with depth / fan-out, and behaviour below the bound. |

Standing constraints for this list: **R1** and **R2** are the on-ramp and should
stay runnable with nothing but `python3`. Do not quote "HELUT works at \(q=2\)"
until a **C** row exists. Metal is a hard dependency of the encrypted path, so
the Apple split is documented rather than engineered away
([`directives/why-apple-silicon.md`](directives/why-apple-silicon.md)).

Still open from the same review: a machine-checked (Lean or Coq) version of the
six clauses, and the toy cipher pushed through Yosys so the netlist claim is
demonstrated rather than described. The vertex-maximizer question turned out to be
classical (**R7**) — worth remembering as a process lesson: search the
optimization literature before calling something open. What remains of it is the
scaling of \(\lambda^\star\) with circuit structure, and what happens below the
sufficient bound where a real schedule lives. If either resolves it becomes a
lemma with a receipt and a **C** row, and not before.

---

## Phase 0 — Corpus / proofs push (active)

Goal: graduate the *release corpus* (paper, theorems, five-cell claims), not more FHE
microbenches and not speculative avenues.

### Doctrine

Every public sentence survives the five-cell test (proof · table · metric · ≥2 examples ·
application) or stays a hedge / non-claim. Map abstract sentences in `paper/helut.tex` to
claim IDs. Sync living textbook (`\livingepoch`) whenever a **C** / **H** moves.

### Ordered work

| # | Track | Deliverable | Status |
|---|--------|-------------|--------|
| 0.1 | Abstract ↔ C-id audit | Every abstract sentence ↔ **C** (≥ partial five cells) or cut/hedge | **done** (paper abstract tagged C1/C4–C24 + H1/H4) |
| 0.2 | Pillar II next formal | Theorem 1 (**C19**) exists; next: emitter–discrete agreement **or** involution completeness under freeze → new **C** + `TensorLUTFormal` lemma | **done** (**C25** corollary) |
| 0.3 | Pillar III theoremoid | Upgrade paper §Pillar III from sketch: reciprocity + fail-closed protocol → **C24** `Enigma256Formal` + `directives/enigma256-theorem.md` | **done** (**C24**) |
| 0.4 | Honest estimator table | Paper hardness table: HELUT vs lattice-estimator (**C23**); print |Δ|>16 anchors; do not quote 176 as estimator cost | **done** (`tab:hardness`) |
| 0.5 | Pillar I production asterisks | **H4** covering noisy BK at prod-shaped *N* **or** cookbook “demo *N* only”; optional crypto ℓ=2 NTT tile (**H3**) | **C36** baseLog=1 + *B*=32 → ε≈−139 + Metal PASS; torus *B*~128 open → **Phase 0.9 M3** |
| 0.6 | Application gallery | ≥3 short apps per pillar pointing at `REPRODUCE.md` | **done** (`application-gallery.md` + site `/apps`); figures optional |
| 0.7 | Artifact tag | Frozen claim-sheet + log list + `make docs` PDFs | **checklist ready** (`artifact-tag.md`); tag `helut-corpus-C26` awaits commit |
| 0.8 | Multiples checklist | Tables / metrics / examples vs `research-release.md` minimums | **drafted** in artifact-tag.md; paper table count at tag time |

### This-week sequence (campaign GPU optional)

1. ~~Abstract ↔ C-id audit~~ · ~~C24~~ · ~~C23 table~~ · ~~gallery~~.
2. **Phase 0.9** kill plan (M5 → M3 → M1 → M4; M2 stretch).
3. Only background: campaign catalog (**H7**).

### Explicit non-goals for Phase 0

- Menu sharding / middle ring ≠ A — campaign ledger only (**H7**).
- `potential-avenues.md` items — stay frontier until a **C** row exists.
- Quoting encrypted tick rate next to Welchman M/s — **N6**.
- Claiming melt completeness or a P1030680 plaintext — **H6** / **N7**.

---

## Phase 0.5 — Library / packaging (parallel with science)

Goal: make HELUT a **general-purpose research tool** others will depend on —
core libraries, thin binaries, and an `Apps/` growth surface.

Canonical plan: [`directives/packaging-roadmap.md`](directives/packaging-roadmap.md).

| # | Track | Deliverable | Status |
|---|--------|-------------|--------|
| P0 | Inventory | Core file → layer map; flag → binary map; `public-api.md` stub | **partial** — flag→binary + ToolKit done |
| P1 | SPM split | `HELUTNetlist` / `TensorLUT` / `SoftBus` / `Bombe` targets; single `helut` still works | **interim** `HELUTToolKit` |
| P2 | Binaries | `helut-bench`, `helut-compile`, `helut-e256`, `helut-bombe` + umbrella `helut` | **done** (tensorlut still via e256) |
| P3 | Apps/ | Template app; gallery points at Apps; third-party can add without editing Core | pending |
| P4 | Docs / semver | DocC for Core; `helut-lib-0.x` tags separate from `helut-corpus-C*` | Homebrew stable **0.1.0**; SPM `from: "0.1.0"`; DocC still pending |

Doctrine: campaign is an **app**; claim-sheet stays one; reproduce commands migrate to
named binaries with a shim epoch so old scripts do not die overnight.

---

## Phase I: Navigating the Federal Intake Architecture

- **The Bureaucratic Filter:** Submissions to the NSA, DARPA, and the Office of Naval Research trigger collaborative review frameworks, not algorithmic confiscation. The Office of Research and Technology Applications (ORTA) runs a Technology Transfer Program specifically designed to partner with external innovators on mutually beneficial R&D.
- **The Strategic Vehicle:** Operating as an established 501(c)(3) provides the ideal organizational interface to handle defense research partnerships without the friction of commercial intellectual property disputes.
- **The Funding Mechanisms:** Instead of relinquishing control, secure Cooperative Research and Development Agreements (CRADAs) or Other Transactions (OTs). These structures grant the government internal usage rights while funding the architect to maintain executive control and continue algorithmic evolution.

---

## Phase II: Evolving Cryptographic Infrastructure

(Mid-term pillar science — after Phase 0 disclosure bar.)

- **Fully Homomorphic Encryption (FHE) Gate Optimization:** Point the continuous-to-discrete synthesis engine at FHE logic gates. Mutating and squeezing these netlists can discover shallower, hardware-native configurations optimized for Metal-accelerated SIMD instructions, drastically reducing the computational overhead of encrypted edge computing. *(Phase 0.9 **M2**.)*
- **Zero-Knowledge Circuit Minimization:** Attack the massive arithmetic circuits required for zero-knowledge proofs (e.g., zk-SNARKs). Evolving mathematically equivalent topologies with lower multiplicative depths and fewer logic gates directly solves the primary friction point in decentralized privacy infrastructure. *(Phase 0.9 **M2** stretch.)*
- **Melting Legacy Stream Ciphers:** Compile legacy stream ciphers (such as A5/1 or RC4) into Yosys netlists. Physically melting their internal state logic to synthesize key streams demonstrates that differentiable hardware solvers can dismantle late-20th-century telecommunications cryptography just as efficiently as 1940s physical machines. *(Not a claim until graded + `REPRODUCE.md`.)*
- **Pillar I lab polish:** NTT inside crypto ℓ=2 tile; product-path noisy BK (**H4** → Phase 0.9 **M3**); HELUT vs estimator tighten on Δ>16 anchors (**H1**). Encrypted soft-CPU tick: Phase 0.9 **M1**.
- **GPU power side-channels (bgpucap · parked):** Investigate whether [bgpucap / gpucap](https://github.com/Digital-Defiance/gpucap) (or a HELUT-oriented fork) can turn its already-sampled GPU/CPU/DRAM power channels (`%gB`/`%gK`, package power, interval traces) into a differential or template power-analysis arm against live TensorLUT and HELUT Metal cores. Today bgpucap is a `time(1)`-style utilization wrapper; the open question is whether denser, keyed workloads (known shell vs wrong shell, known stecker vs random) leave recoverable correlation in those energy samples—and whether HELUT should emit aligned tick markers for trace synchronization. This is **not** a current campaign arm: no gradeable break claim until a controlled fixture shows signal above noise. Worth noting because the same Apple Silicon graphs that make HELUT fast also concentrate work on the GPU package that bgpucap already meters. Speculative framing: [`directives/potential-avenues.md`](directives/potential-avenues.md) §5.

---

## Phase III: Cementing the Legacy

- **The Turing Pillar (Formalize Differentiable Hardware Cryptanalysis):** Publish the mathematical proof of the continuous-to-discrete logic synthesis loop. **Theorem 1** is already machine-checked (**C19** / `directives/tensorlut-theorem.md`). Next theorems deepen emitter / freeze completeness — not a U-534 break. Demonstrating that differentiable hardware evolution can bypass combinatoric explosions to force a system to yield reciprocal pairs will permanently alter how hardware vulnerabilities are audited.
- **The Schneier Pillar (Standardize Polymorphic Ciphers):** Open-source the architectural philosophy driving the Red/Blue evolutionary loop. **C10** + Phase 0.3 formalize SoftBus reciprocity / fail-closed; beyond E256 SoftBus is the mid-term standard. Providing the framework for ciphers that fail-closed and actively mutate their non-linear feedback functions under adversarial pressure establishes a new baseline for secure systems design. *(Phase 0.9 **M4** unifies SoftBus with Torus FHE.)*
- **The Grand Challenge (Shatter the ZKP and PQC Bottleneck):** Focus the engine on post-quantum lattice algorithms and massive proving circuits. Dynamically melting these structures into ultra-low-gate-count topologies solves the most critical computational scaling problem in modern cryptology, securing an unassailable industry zenith. *(Trajectory only until receipts exist.)*
