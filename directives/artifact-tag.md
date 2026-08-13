# Artifact tag checklist (Phase 0.7)

Freeze before a public tag. Not a claim — a release packing list.

**Proposed tag:** `helut-corpus-C26` (epoch 2026-08-13 / C26)  
**Blocker:** working tree has uncommitted Phase 0 edits — ask before `git commit` + `git tag`.

## Must ship

- [x] `directives/claim-sheet.md` epoch matches newest **C** (**C26**)
- [x] `REPRODUCE.md` covers C19–C26 formal/lab receipts
- [x] `logs/helut-estimator-results.json` (C23)
- [x] `logs/helut-noisy-bk-measure*.log` (C22 + C26 n1024)
- [x] Representative SING logs: `helut-encrypted-n1024-metal-sing-par.log`, `…-crypto.log`
- [x] `make textbook` → `textbook/helut-living-textbook.pdf` (rebuild after C26 sync)
- [x] `make writeup` when campaign rows moved (catalog park @417 done)
- [ ] Paper `paper/helut.tex` PDF build (optional; `.tex` updated through C26)
- [x] Application gallery on site `/apps` (nine slots)
- [x] Formal certs reproduce: C19, C24, C25

## Multiples bar (`research-release.md`)

| Kind | Minimum | Rough count now |
|------|---------|-----------------|
| Atomic claims | ≥12 | C1–C26 (26) |
| Tables in paper | ≥14 | hardness, certs, related, gallery, campaign, … |
| Metrics with bars | ≥10 | SING s/BR, estimator Δ, noisy-BK σ̂ / εlog2, … |
| Worked examples / pillar | ≥6 | gallery + labs |
| Applications total | ≥9 | `application-gallery.md` + `/apps` |
| Proofs / reductions | ≥10 | C19 (6) + C25 (2) + C24 (5) + cert surface |
| Related-work systems | ≥4 | related-work matrix |
| Ablations | ≥3 | Metal vs CPU; refresh modes; N sweep |

## Do not tag as proven

- Product noisy BK meeting ε≤2⁻⁶⁴ at *N*=1024 (**H4** — **C26** is the graded fail)
- Estimator agreement on every calibration anchor (**H1**)
- P1030680 plaintext / TensorLUT = U-534 (**H6**, **N**)

## Cut command (after commit)

```bash
git tag -a helut-corpus-C26 -m "HELUT disclosure corpus epoch 2026-08-13 / C26

Three-pillar stack receipts through C26 (N=1024 noisy-BK graded negative).
See directives/claim-sheet.md and directives/artifact-tag.md."
```
