---
inclusion: always
---
# Campaign writeup sync

`writeup.tex` is the canonical P1030680 campaign report. `writeup.md` / `writeup.pdf` are generated. It lags unless you update it in the same turn as the science.

**Trigger:** you add or change a campaign **C** / **H** / **N** row (especially H6–H7, N5–N7, C2–C3, C8–C12, C19), or `BREAK_P1030680.md` / `site/src/pages/JournalPage.tsx` campaign status moved (those two update first — `.cursor/rules/campaign-journal.mdc`).

**Then, same turn:**
1. Diff `BREAK_P1030680.md` “What we know” / honest scope against Table~\ref{tab:campaign} and the TensorLUT / quarantine paragraphs in `writeup.tex`. The ledger wins.
2. Patch **`writeup.tex` only**. Never hand-edit `writeup.md`.
3. Keep the report a *graded summary*, not a journal dump: proven / eliminated / open, claim IDs, no implied decrypt (N5). Fitness is cleartext Metal, not encrypted tick rate (N6). TensorLUT is parallel, not a Thetis crib (N7, H6).
4. Rebuild: `make writeup` → `writeup.pdf` + `writeup.md`. If TeX tools are missing, still patch the `.tex` and say the PDF/MD rebuild is pending.
5. Do not invent lecture-voice claims. Catalog resume index, middle ring ≠ A, and garble risk stay printed until evidence moves.

Contract: `writeup.tex` header comments. Ledger: `BREAK_P1030680.md`. Claims: `directives/claim-sheet.md`.
