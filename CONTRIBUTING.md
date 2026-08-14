# Contributing

This repo’s public sentences have to survive the **five-cell test** (`directives/research-release.md`). If you cannot point at a **C** row + `REPRODUCE.md` command, it is a hedge or a non-claim.

## Rules that protect the science

1. **`directives/claim-sheet.md` wins.** If README, site, videos, or textbook disagree, patch them to the sheet — do not invent a second corpus.
2. **Do not imply a U-534 / P1030680 decrypt.** Campaign fitness is cleartext Metal, not encrypted tick rate.
3. **Do not quote “176-bit secure.”** Hardness is **H1** / **C23**.
4. **Trivial Metal graphs ≠ FHE.** Encrypted means `--lut-backend encrypted` / `--bench-encrypted` + SING.
5. Generated Markdown (`writeup.md`, `paper/helut.md`, `textbook/helut-living-textbook.md`) is **not** hand-edited. Patch the `.tex` and `make docs`.

## How to send work

- Small, reviewable PRs. Name the claim IDs you touch.
- Tests: `swift test -c release` for the seam you changed; Metal SING only when the change is on that path.
- New results: add a **C** row, a reproduce command, and a log under `logs/` in the **same** change.

Questions about packaging (library vs campaign CLI): `directives/packaging-roadmap.md`.

Conduct: [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).
