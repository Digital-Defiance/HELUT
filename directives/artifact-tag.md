# Artifact tag checklist (Phase 0.7)

Freeze before a public tag. Not a claim — a release packing list.

**Current tag:** `helut-corpus-C30` (epoch through C30)  
**Next proposed:** `helut-corpus-C32` after C31/C32 commit

## Must ship

- [x] `directives/claim-sheet.md` epoch matches newest **C**
- [x] `REPRODUCE.md` covers formal/lab receipts through newest C
- [x] `logs/helut-estimator-results.json` (C23)
- [x] Noisy-BK logs: C22 / C26 / C30 / C32
- [x] Representative SING logs (C20/C21/C28)
- [x] `make textbook` → living PDF
- [x] Formal certs: C19, C24, C25, C27/C29, C31
- [x] Application gallery on site `/apps`

## Do not tag as proven

- Product noisy BK meeting ε≤2⁻⁶⁴ at *N*=1024 (**H4** — **C32** is ≈2⁻³² on approx candidate)
- Exact public-MS covering at *N*=1024 (**C27**/**C29**)
- Estimator agreement on every calibration anchor (**H1**)
- P1030680 plaintext / TensorLUT = U-534 (**H6**, **N**)
