# Directive: Build the Kriegsmarine Fuzzy Crib Generator

## Context
Our strict historical crib catalog has cleared the turnover-free space. If exact historical matches return a clean negative, it points directly to human error—such as an operator typo, a non-standard signal abbreviation, or header padding—that shattered the rigid Welchman Boolean logic.

We need a Python script to generate mutated, fuzzed variations of our high-value naval cribs, outputting a new expanded JSON menu fixture for `helut`.

## Objective
Create a new script named `Scripts/fuzzy_crib_generator.py` that ingests our high-probability naval cribs and generates an expanded, fuzzed menu fixture saved to `Fixtures/p1030680_fuzzed_menus.json`.

## Implementation Requirements

### 1. Source Cribs — DONE
- Pull from our core high-probability Kriegsmarine terms (e.g., `UUUFLOTTX`, `KOMXADMXU`, `TRAVEMUE`, `WETTERVORHERSAGE`) and their known valid placements in `Fixtures/p1030680_menus.json`.
- Scarce cores extended from `Fixtures/u534_corpus.json` decrypt windows when the mined catalog has no ≥16 carrier.

### 2. Mutation Engine — DONE
Implement functions to apply historical operator error profiles:
- **Header Padding & Offsets:** Generate variants shifted by +1, +2, and +3 characters to account for stray padding characters or unrecorded prefix garbage at the start of the transmission.
- **Signal Abbreviations:** Introduce common U-boat traffic shorthand contractions and expansions.
- **Phonetic & Orthographic Slips:** Simulate radio telephony and hand-keying confusion (`C` <-> `K`, `Z` <-> `S`, dropped double-letters like `FF` -> `F`).
- **Hamming-Distance-1 Swaps:** Generate single-character substitutions for non-critical positions in long cribs.

### 3. Strict Validation Filters (Mandatory) — DONE
- **Length Constraint:** Enforce `crib.count >= 16` strictly. Drop any mutated crib shorter than 16 characters to prevent the 14-letter false-positive trap.
- **Self-Encipherment Law:** Discard any crib placement where a plaintext letter maps directly to the identical ciphertext position (an Enigma impossibility).
- Exact catalog `(crib, offset)` pairs excluded so the fixture is novel relative to cleared campaigns.

### 4. Output Schema — DONE
- Format the resulting array of mutated menus to match the exact JSON schema expected by `BombeMenuBuilder.swift`.
- Ensure it includes valid loop rankings and edge counts so the engine can process them by deduction power.
- Default emit caps at 400 stratified placements (`--max-placements 0` keeps all).
- Hard length ceiling **40** — matches `welchmanMaxEdges` in `BombeMetal.swift`. Longer menus silently failed to enqueue and looked like instant board kills.

## Constraints
- Do not modify the Swift host binary, the Metal GPU kernel, or the Stage 3 IC/trigram discriminator. This tool operates strictly upstream as a fixture generator.

## Shipped
```bash
python3 Scripts/fuzzy_crib_generator.py
# → Fixtures/p1030680_fuzzed_menus.json
```
