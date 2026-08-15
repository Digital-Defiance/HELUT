# Living textbook

Canonical TeX for a **long-term living textbook** of **reconfigurable homomorphic computing** — netlist-clocked torus FHE, differentiable hardware, and adversarial polymorphic ciphers.

**Not ready to teach.** Edition 0.1.x is an AI-bootstrapped scaffold: a collecting place for theorems, formulae, and claim-sheet receipts. Humans must vet, bulk up, fill in, and edit it before it is a course. Do not assign it as a university class. **Claims and lemmas are not AI-invented:** they require a human check against the claim sheet and a reproduce receipt **before commit**. Repo-level AI boundary: [`../AI_DISCLOSURE.md`](../AI_DISCLOSURE.md).

| Artifact | Path |
|----------|------|
| Master file | [`helut-living-textbook.tex`](helut-living-textbook.tex) |
| Epoch / edition | `\livingepoch` in [`preamble.tex`](preamble.tex) — currently **2026-08-14 / C69**, edition **0.1.2** |
| Corpus of record | [`../directives/claim-sheet.md`](../directives/claim-sheet.md) |
| Trajectory | [`../directives/research-trajectory.md`](../directives/research-trajectory.md) |
| Frontier (not claims) | [`../directives/potential-avenues.md`](../directives/potential-avenues.md) |

Build (repo root, needs `latexmk` + `pandoc` + a BibTeX-capable TeX Live / MacTeX):

```bash
make textbook
```

PDF and generated Markdown land next to the master file. Aux files go under `build/textbook/`. Do not hand-edit `helut-living-textbook.md`.

Draft a subset while writing by commenting out `\input` lines in the master file.

## Living contract (how the book grows)

Enforced for agents by [`.cursor/rules/living-textbook.mdc`](../.cursor/rules/living-textbook.mdc) (always-on). Humans: same checklist.

This is not a frozen monograph. It is a **scaffold on a moving corpus**, written so receipts have a book-shaped home. It is not a course you can run.

1. **`directives/claim-sheet.md` is canonical.** The appendix claim index is a snapshot. If they disagree, the sheet wins and the TeX must catch up.
2. **A new `C` row** → add a numbered example, table, or lab receipt to the matching pillar chapter; bump `\livingepoch`.
3. **A closed `H` row** → convert the hedge box into a reproduced box; move leftover asterisks into the next open hedge.
4. **An avenue that graduates** (receipts in `REPRODUCE.md`) → leave Part~VI (frontier) and enter a pillar chapter. Until then it stays `\frontierbox`.
5. **Lecture voice never outruns receipts.** Frontier chapters are seminar reading, not midterm facts. New theorems/lemmas wait for a **human check** before commit.
6. **Non-claims stay printed.** See `directives/research-release.md`.

Chapter ↔ corpus map:

| Book | Grows from |
|------|------------|
| Pillar I, Metal compiler, certificates | `fhe-graduation.md`, `metal-compiler-phases.md`, `parameter-cookbook.md` |
| Pillar II | `tensorlut-theorem.md` (**C19**), `theorem-1-plain.md`, `tensorlut.md` |
| Pillar I torus \(q\) | `q-32-vs-q-2.md` (doctrine split; not a **C** row) |
| Why Apple first | `why-apple-silicon.md` (lab history; not a CUDA claim) |
| Pillar III | `enigma256-theorem.md` (**C24**), `Enigma256.md`, `roadmap-overall.md` Schneier pillar |
| Open problems | `research-trajectory.md` |
| Frontier | `potential-avenues.md` |
| Labs / reproduce | `REPRODUCE.md` |

## Future course (not this edition)

A 15-week syllabus sketch lives in the book (appendix). It is aspirational. [To the instructor](chapters/instructor.tex) is a design note, not permission to open a section. Two tracks are sketched: **theory** (certificates, five-cell test) and **systems** (Apple Silicon labs). Neither track is ready.
