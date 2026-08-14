# Artifact tag checklist (Phase 0.7)

Freeze before a public tag. Not a claim — a release packing list.

**Current corpus tag:** `helut-corpus-C54` (epoch 2026-08-14 / C54)  
**Semver:** `0.1.0` (alias `helut-lib-0.1.0`) — Homebrew `brew install helut`; SPM `from: "0.1.0"`.

## Must ship

- [x] `directives/claim-sheet.md` epoch matches newest **C** (**C54**)
- [x] `REPRODUCE.md` covers formal/lab receipts through newest C
- [x] `logs/helut-estimator-results.json` (**C23**)
- [x] Noisy-BK logs: **C22** / **C26** / covering ladder / **C52** ε (`…-k7-stride-t8.log`)
- [x] Representative SING logs (**C20**/**C21**/**C28** + **C52**–**C54** covering)
- [x] `make textbook` → living PDF (epoch C54)
- [x] Formal certs: **C19**, **C24**, **C25**, **C27**/**C29**, **C31**
- [x] Application gallery on site `/apps`

## Do not tag as proven

- Native-*k*=1 torus-scale noisy BK at *N*=1024 (**C37**; **H4** remainder)
- Noisy `cryptoPublicMS` at *N*=1024 (**C26** / **C27**/**C29**)
- Estimator agreement on every calibration anchor (**H1**)
- P1030680 plaintext / TensorLUT = U-534 (**H6**, **N**)
- Encrypted PicoRV at production *N* (**C51** is demo *N*=8)
- “176-bit secure” as an estimator quote (**H1**)
