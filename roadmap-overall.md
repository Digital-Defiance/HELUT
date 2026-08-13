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
| 0.5 | Pillar I production asterisks | **H4** covering noisy BK at prod-shaped *N* **or** cookbook “demo *N* only”; optional crypto ℓ=2 NTT tile (**H3**) | **done** (**C26** graded fail + **C27** structural impossibility under *q*=2³²); product SING stays *e*=0 |
| 0.6 | Application gallery | ≥3 short apps per pillar pointing at `REPRODUCE.md` | **done** (`application-gallery.md` + site `/apps`); figures optional |
| 0.7 | Artifact tag | Frozen claim-sheet + log list + `make docs` PDFs | **checklist ready** (`artifact-tag.md`); tag `helut-corpus-C26` awaits commit |
| 0.8 | Multiples checklist | Tables / metrics / examples vs `research-release.md` minimums | **drafted** in artifact-tag.md; paper table count at tag time |

### This-week sequence (campaign GPU optional)

1. Abstract ↔ C-id audit in `paper/helut.tex` (no Metal).
2. Pillar III formal certificate (**C24**) + XCTest + directive.
3. Paper table: **C23** estimator vs HELUT (honest Δ).
4. Application gallery outline (9 slots).
5. Only then: **H4** at larger covering *N*, or crypto-ℓ=2 NTT tile.

### Explicit non-goals for Phase 0

- Menu sharding / middle ring ≠ A — campaign ledger only (**H7**).
- `potential-avenues.md` items — stay frontier until a **C** row exists.
- Quoting encrypted tick rate next to Welchman M/s — **N6**.
- Claiming melt completeness or a P1030680 plaintext — **H6** / **N7**.

---

## Phase I: Navigating the Federal Intake Architecture

- **The Bureaucratic Filter:** Submissions to the NSA, DARPA, and the Office of Naval Research trigger collaborative review frameworks, not algorithmic confiscation. The Office of Research and Technology Applications (ORTA) runs a Technology Transfer Program specifically designed to partner with external innovators on mutually beneficial R&D.
- **The Strategic Vehicle:** Operating as an established 501(c)(3) provides the ideal organizational interface to handle defense research partnerships without the friction of commercial intellectual property disputes.
- **The Funding Mechanisms:** Instead of relinquishing control, secure Cooperative Research and Development Agreements (CRADAs) or Other Transactions (OTs). These structures grant the government internal usage rights while funding the architect to maintain executive control and continue algorithmic evolution.

---

## Phase II: Evolving Cryptographic Infrastructure

(Mid-term pillar science — after Phase 0 disclosure bar.)

- **Fully Homomorphic Encryption (FHE) Gate Optimization:** Point the continuous-to-discrete synthesis engine at FHE logic gates. Mutating and squeezing these netlists can discover shallower, hardware-native configurations optimized for Metal-accelerated SIMD instructions, drastically reducing the computational overhead of encrypted edge computing.
- **Zero-Knowledge Circuit Minimization:** Attack the massive arithmetic circuits required for zero-knowledge proofs (e.g., zk-SNARKs). Evolving mathematically equivalent topologies with lower multiplicative depths and fewer logic gates directly solves the primary friction point in decentralized privacy infrastructure.
- **Melting Legacy Stream Ciphers:** Compile legacy stream ciphers (such as A5/1 or RC4) into Yosys netlists. Physically melting their internal state logic to synthesize key streams demonstrates that differentiable hardware solvers can dismantle late-20th-century telecommunications cryptography just as efficiently as 1940s physical machines. *(Not a claim until graded + `REPRODUCE.md`.)*
- **Pillar I lab polish:** NTT inside crypto ℓ=2 tile; product-path noisy BK (**H4**); HELUT vs estimator tighten on Δ>16 anchors (**H1**).
- **GPU power side-channels (bgpucap · parked):** Investigate whether [bgpucap / gpucap](https://github.com/Digital-Defiance/gpucap) (or a HELUT-oriented fork) can turn its already-sampled GPU/CPU/DRAM power channels (`%gB`/`%gK`, package power, interval traces) into a differential or template power-analysis arm against live TensorLUT and HELUT Metal cores. Today bgpucap is a `time(1)`-style utilization wrapper; the open question is whether denser, keyed workloads (known shell vs wrong shell, known stecker vs random) leave recoverable correlation in those energy samples—and whether HELUT should emit aligned tick markers for trace synchronization. This is **not** a current campaign arm: no gradeable break claim until a controlled fixture shows signal above noise. Worth noting because the same Apple Silicon graphs that make HELUT fast also concentrate work on the GPU package that bgpucap already meters. Speculative framing: [`directives/potential-avenues.md`](directives/potential-avenues.md) §5.

---

## Phase III: Cementing the Legacy

- **The Turing Pillar (Formalize Differentiable Hardware Cryptanalysis):** Publish the mathematical proof of the continuous-to-discrete logic synthesis loop. **Theorem 1** is already machine-checked (**C19** / `directives/tensorlut-theorem.md`). Next theorems deepen emitter / freeze completeness — not a U-534 break. Demonstrating that differentiable hardware evolution can bypass combinatoric explosions to force a system to yield reciprocal pairs will permanently alter how hardware vulnerabilities are audited.
- **The Schneier Pillar (Standardize Polymorphic Ciphers):** Open-source the architectural philosophy driving the Red/Blue evolutionary loop. **C10** + Phase 0.3 formalize SoftBus reciprocity / fail-closed; beyond E256 SoftBus is the mid-term standard. Providing the framework for ciphers that fail-closed and actively mutate their non-linear feedback functions under adversarial pressure establishes a new baseline for secure systems design.
- **The Grand Challenge (Shatter the ZKP and PQC Bottleneck):** Focus the engine on post-quantum lattice algorithms and massive proving circuits. Dynamically melting these structures into ultra-low-gate-count topologies solves the most critical computational scaling problem in modern cryptology, securing an unassailable industry zenith. *(Trajectory only until receipts exist.)*
