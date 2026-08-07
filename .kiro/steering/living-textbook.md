---
inclusion: always
---
# Living textbook sync

The book (`textbook/`) is an AI-bootstrapped **scaffold** on the claim inventory — a collecting place for theorems and formulae, **not ready to teach**. It lags unless you update it in the same turn as the science. Do not write lecture voice that treats edition 0.1.x as a runnable university course.

**Do not invent claims or lemmas.** `\reproduced`, `\begin{theorem}`, and claim-index rows must match a human-checked **C** row + `REPRODUCE.md`. Draft TeX is allowed; committing a new theorem, lemma, or **C**/**H**/**N** row requires a human check of the receipt. Hallucinated formulae stay out of git.

**Trigger:** you add or change a **C** / **H** / **N** row, close a hedge, graduate an avenue, land a reproduce command, or edit `directives/tensorlut-theorem.md` / `metal-compiler-phases.md` / `parameter-cookbook.md` / `research-trajectory.md` / `potential-avenues.md` / `REPRODUCE.md`.

**Then, same turn:**
1. Diff `directives/claim-sheet.md` against `\livingepoch` in `textbook/preamble.tex`. If they disagree, the sheet wins.
2. Patch the matching chapter under `textbook/chapters/` (example, table, lab receipt, or convert `\hedgebox` → `\reproduced`). Do not invent lecture-voice claims.
3. Refresh the snapshot in `textbook/appendices/claim-index.tex`.
4. Bump `\livingepoch` to `YYYY-MM-DD / C<n>` (newest C-id).
5. Point labs at `REPRODUCE.md`. Never hand-edit `textbook/helut-living-textbook.md`.
6. Frontier stays `\frontierbox` until a **C** row exists. Non-claims stay printed.

**Map:** Pillar I ← metal-compiler / cookbook / fhe-graduation · Pillar II ← `tensorlut-theorem.md` · Pillar III ← `Enigma256.md` · open problems ← trajectory · frontier ← avenues.

Contract: `textbook/README.md`. Build: `make textbook`. Campaign report: `writeup.tex` (`.cursor/rules/writeup.mdc`). Public site: `.cursor/rules/site-sync.mdc`.
