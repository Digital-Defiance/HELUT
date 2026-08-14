# Research-release doctrine (bulletproof claims)

HELUT is not “yet another TFHE library.” The invention is a **three-pillar stack**.
Every public sentence must survive the five-cell test below, or it is a **non-claim**.

Companion canvas (living matrix): open beside chat in Cursor canvases —
`research-release-doctrine.canvas.tsx`.

**Living inventory** of reproducible results / hedges / non-implications:
[`claim-sheet.md`](claim-sheet.md). **Reproduce commands:** [`../REPRODUCE.md`](../REPRODUCE.md).
**Beyond disclosure:** [`research-trajectory.md`](research-trajectory.md).

## Pillars (reasons for being)

| # | Name | One-line claim | Why it exists |
|---|------|----------------|---------------|
| I | Netlist-clocked torus FHE | Yosys `$lut` sequential netlists evaluate as exact \(\mathbb{Z}/2^{32}\mathbb{Z}\) tensor graphs with real BK blind-rotate + certificates + host clock | Edge SoftBus/ANE is an ML graph machine, not an NTT library |
| II | Differentiable hardware cryptanalysis | Continuous–discrete melt of gate INIT tensors recovers structure combinatoric sieves miss (graded shatter vs hold) | Boolean search rejects; melt proposes genotypes |
| III | Adversarial polymorphic ciphers | Blue ciphers (Enigma256-class) mutate under Red pressure and fail closed; reciprocity by construction | Static stream ciphers die under the same lab that grades Enigma |

**Do not claim:** a new lattice assumption, “we invented TFHE,” or production security without estimator + noisy-BK depth bounds.

## Five-cell test (per atomic claim)

For claim \(C\), ship all five or hedge \(C\):

1. **Proof** — lemma, reduction, or graded empirical protocol with pass/fail
2. **Table** — parameters, comparisons, or grades in a numbered table
3. **Metric** — a number with units and a bar (pass threshold)
4. **Examples** — ≥2 concrete, runnable instances
5. **Application** — ≥1 end-to-end reason someone would use it

Paper rule: every abstract sentence maps to a claim ID with all five cells ≥ *partial*.

## Multiples checklist (minimums before “release”)

| Kind | Minimum |
|------|---------|
| Atomic claims (I+II+III) | ≥12 numbered (C1…) |
| Tables in paper | ≥14 (see canvas) |
| Metrics with bars | ≥10 |
| Worked examples / pillar | ≥6 in appendix |
| Applications total | ≥9 (≥3 per pillar) |
| Proofs / reductions | ≥10 listed; critical path proved or boxed as hypothesis |
| Related-work systems compared | ≥4 (Concrete, OpenFHE, tfhe-rs, HELUT, …) |
| Ablations | ≥3 (refresh mode, Metal vs CPU BR, N sweep) |

## Critical path (order)

1. ~~Rewrite `paper/helut.tex` to three-pillar claim + explicit non-claims~~
2. ~~Lattice-estimator table for production `(n,q,σ)`~~ — **C23** filled (native Sage 10.9); production |Δ|=4.5; four other anchors exceed 16-bit tolerance (**H1**)
3. ~~Noisy BK depth certificate (`TFHENoisyBKCertificate`)~~ — **C22** covering *N*≤128; **C52** covering Track A *N*=1024 σ=128 *k*=7 (ε + SING); **C26** `cryptoPublicMS` *N*=1024 inject still graded fail
4. ~~Encrypted metrics~~ — full_adder SING through *N*=1024 Metal boolean (**C20** 10.6 s) and crypto ℓ=2 (**C21** 11.38 s)
5. **Formal method** section for continuous→discrete (TensorLUT) — **Theorem 1** in `directives/tensorlut-theorem.md` / `paper/helut.tex`; machine-checked by `TensorLUTFormal.certificate()` (**C19**)
5b. **Pillar III SoftBus contract** — **Theorem 2** in `directives/enigma256-theorem.md`; `Enigma256Formal.certificate()` (**C24**)
6. ~~Related-work matrix~~ (paper); ablations via `--cpu-only` / refresh modes
7. **Application gallery** — nine slots in `directives/application-gallery.md`; site figures in `site/public/gallery/`; parameter cookbook at `directives/parameter-cookbook.md`
8. **Artifact tag** — checklist `directives/artifact-tag.md` (`helut-corpus-C54`; CLI/SPM semver **0.1.0**)

Corpus push order: [`../roadmap-overall.md`](../roadmap-overall.md) Phase 0.

Parameter cookbook: `directives/parameter-cookbook.md`.

## Non-claims (always print)

- Calibrated core-SVP ≠ lattice-estimator attack cost on every row (**C23** filled the JSON; 4/8 anchors still |Δ|>16)
- Trivial/oracle Metal graphs ≠ FHE
- `publicMS` semantics and side-channels (Metal/GPU power) out of scope unless measured
- Quantum / poly-memory attacks out of scope
- P1030680 campaign fitness ≠ HELUT tick rate
- TensorLUT involution grades ≠ a U-534 break

## Status pointers

- FHE ladder: `directives/fhe-graduation.md`
- Hardness calibration: `TFHELWECalibration` + canvas `lwe-hardness-calibration`
- Campaign / TensorLUT grades: `BREAK_P1030680.md`, site journals
- Polymorphic Blue: `Enigma256.md`
- Long roadmap: `roadmap-overall.md`
- Wild avenues (post-release): `directives/potential-avenues.md`
- Living textbook (course): `textbook/`
