# Directive: The Ultimate Stage 3 Discriminator Upgrade

## Context
Our pipeline hit a false positive on a 14-letter crib (menu 627). The menu was too short, which caused 193 million raw mathematical stops and 2,118 physical 10-plug completions. One of those ghosts randomly generated enough trigram matches to barely clear our loose threshold of -4.114, resulting in a garbage plaintext. 

We need to make the Stage 3 discriminator bulletproof without adding the latency of an ML model or waiting to build new quadgram tables. 

## Implementation Steps

### 1. Enforce the Entropy Floor (Stage 1 Filter) — DONE
- Before a menu is even dispatched to the Welchman GPU board, check its length.
- STRICTLY require `crib.count >= 16`. Skip any placement shorter than this. 
- *Reasoning: 16+ letters mathematically chokes the ghost population to near zero before the GPU even spins up.*
- **Shipped:** `BombeSweepConfig.minCribLength = 16` (override with `--bombe-min-crib`).

### 2. Add the Index of Coincidence (IC) Gate (Stage 3 Addition) — DONE
- Write a fast Swift function to calculate the Index of Coincidence (IC) of the 72-letter decrypted plaintext.
- Add an IC threshold gate: If `IC < 0.055`, immediately reject the string as a ghost. Do not even bother running the trigram scorer.
- *Reasoning: Random noise has an IC of ~0.038. German is ~0.076. A ghost might randomly chain three letters together to fool a trigram table, but it cannot fake a whole-string linguistic distribution.*
- **Shipped:** `PostBombeDiscriminator.icFloor = 0.055` via `LanguageScorer.indexOfCoincidence`. The menu-627 ghost measured IC ≈ 0.043 — this gate kills it before trigrams run. Break requires `cribExact ∧ IC ≥ 0.055 ∧ tail > −3.600`.

### 3. Tighten the Trigram Threshold — DONE
- For strings that pass the IC gate, run the existing trigram scorer.
- Raise the "BREAK FOUND" threshold to `-3.600` (historical true German sits around -2.8).
- **Shipped:** `PostBombeDiscriminator.breakThreshold = -3.600`.

### 4. Resume the Campaign — DONE
- Implement a `--resume-from 628` argument in the batch runner (or hardcode the array slice) so we do not re-run the 627 menus we already exhausted.
- **Shipped:** `--bombe-from N` (1-based catalog index). Resume of the ≥16 rings-AAAA pass completed with no break.
