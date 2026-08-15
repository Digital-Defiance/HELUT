# Living textbook

Canonical TeX for a first university course in **reconfigurable homomorphic computing** — netlist-clocked torus FHE, differentiable hardware, and adversarial polymorphic ciphers.

| Artifact | Path |
|----------|------|
| Master file | [`helut-living-textbook.tex`](helut-living-textbook.tex) |
| Epoch / edition | `\livingepoch` in [`preamble.tex`](preamble.tex) — currently **2026-08-14 / C62**, edition **0.1.2** |
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

This is not a frozen monograph. It is a **teaching surface on a moving corpus**.

1. **`directives/claim-sheet.md` is canonical.** The appendix claim index is a snapshot. If they disagree, the sheet wins and the TeX must catch up.
2. **A new `C` row** → add a numbered example, table, or lab receipt to the matching pillar chapter; bump `\livingepoch`.
3. **A closed `H` row** → convert the hedge box into a reproduced box; move leftover asterisks into the next open hedge.
4. **An avenue that graduates** (receipts in `REPRODUCE.md`) → leave Part~VI (frontier) and enter a pillar chapter. Until then it stays `\frontierbox`.
5. **Lecture voice never outruns receipts.** Frontier chapters are seminar reading, not midterm facts.
6. **Non-claims stay printed.** See `directives/research-release.md`.

Chapter ↔ corpus map:

| Book | Grows from |
|------|------------|
| Pillar I, Metal compiler, certificates | `fhe-graduation.md`, `metal-compiler-phases.md`, `parameter-cookbook.md` |
| Pillar II | `tensorlut-theorem.md` (**C19**), `tensorlut.md`, `adversarial-synthesis.md` |
| Pillar III | `enigma256-theorem.md` (**C24**), `Enigma256.md`, `roadmap-overall.md` Schneier pillar |
| Open problems | `research-trajectory.md` |
| Frontier | `potential-avenues.md` |
| Labs / reproduce | `REPRODUCE.md` |

## Course

A 15-week syllabus lives in the book (appendix). Instructors: start with [To the instructor](chapters/instructor.tex). Two tracks are designed in: **theory** (certificates, five-cell test) and **systems** (Apple Silicon labs). A department without Macs can still teach the theory track from published logs.
