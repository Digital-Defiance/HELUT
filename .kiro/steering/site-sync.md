---
inclusion: always
---
# HELUT site sync (`site/`)

The public site is a teaching surface on the claim inventory. It lags unless you update it in the **same turn** as the science.

**Trigger:** you add or change a **C** / **H** / **N** row that any public page asserts (especially hardness **H1**/**C23**, noisy BK **H4**/**C22**/**C26**/**C52**–**C54**, Metal SING **C20**/**C21**, covering **C27**, sequential **C38**/**C40**/**C51**, campaign **H7**/**N**), or you bump `\livingepoch` in `textbook/preamble.tex`.

**Then, same turn:**
1. Diff `directives/claim-sheet.md` (sheet wins) against:
   - `site/src/pages/HomePage.tsx` (lede + honest limits)
   - `site/src/pages/StackPage.tsx` (Path B certs / SING / non-claims)
   - `site/src/pages/AppsPage.tsx` (nine-slot gallery = `directives/application-gallery.md`)
   - `site/src/projects/registry.ts` (`netlist-fhe` summary + stakes)
   - `site/src/pages/NetlistFheJournalPage.tsx` (Pillar I chronology)
2. Patch stale numbers and hedges. Do not invent lecture-voice claims. Do not quote “176-bit secure.” Do not imply a P1030680 decrypt. Trivial Metal ≠ FHE.
3. If a gallery slot’s claim IDs moved, patch `directives/application-gallery.md` and `AppsPage.tsx` together.
4. Campaign chronology is **not** this rule — `JournalPage.tsx` follows `.cursor/rules/campaign-journal.mdc` (BREAK ledger wins). The hunt is still in progress until BREAK FOUND.
5. Footer / GitHub links: keep Security, Oppenheimer, AI disclosure if those files exist.

**Remainders vs site bugs:** tree/regex encrypted Metal SING at production *N*, PicoRV covering at *N*=1024, and native *k*=1 (**C37**) are **open science**. If the site does not claim them as done, that is correct — do not “fix” copy by inventing those bars.

**Map:** Pillar I ← Home / Stack / Apps I.* / `netlist-fhe` · Pillar II ← Apps II.* / differentiable-hardware hub · Pillar III ← Apps III.* / e256 · campaign ← Enigma + journal (other rule).

Contract: `site/README.md`. Build: `cd site && npm run build`. Textbook: `.cursor/rules/living-textbook.mdc`. Videos: `.cursor/rules/helut-videos-sync.mdc`.
