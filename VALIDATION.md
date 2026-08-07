# HELUT-Bombe Validation Pipeline

Three-tier verification against real Enigma semantics. Letter-level campaign assertions use the host `EnigmaOracle` and a **cleartext** Yosys netlist simulator. Metal boolean oracle under trivial torus encoding is gated bit-exact (`MockPBSBooleanTests`, `TFHESeamTests`). Encrypted FHE path: BK blind-rotate netlist (`EncryptedNetlistSimulator`, `--lut-backend encrypted`) — **PASS** for full_adder.

## Tier 1 — Synthetic ground truth

- Control plaintext: `KEINEBESONDERENEREIGNISSE`
- Key: rotors `I-II-III`, rings `AAA`, start `ABC`, 10 steckers
- Inject correct Grundstellung into one of 10,000 lanes; remaining lanes get deterministic wrong keys
- Assert exclusive plaintext recovery on the correct lane + language-score spike

Cleartext `enigma_netlist.json` simulation is checked bit-for-bit against the oracle for the HELUT Verilog baseline (empty stecker, rings AAA).

## Mock-PBS boolean gate

```bash
swift test --filter 'MockPBSBooleanTests|TFHESeamTests'
# Release re-bench + N=1024 Enigma Metal≡cleartext
./Scripts/helut_boolean_bench.sh
.build/release/helut --bench enigma_netlist.json --ticks 0 --bench-equiv
# Phase encoding + trivial PBS (full_adder)
./Scripts/helut_phase_seam.sh
```

Asserts Metal multilinear/trivial-PBS `$lut` evaluation matches `CleartextNetlistSim` where claimed. Encrypted path: BK blind-rotate, Decision-LWE hardness cert (prod-n1024-s16 HELUT 175.7 vs estimator 180.2 — **H1**), Gaussian ε≤2⁻⁶⁴, noisy-BK depth — covering Track A **C52**. Multi-netlist CPU lock: full_adder / tree (256×) / regex (sampled). Metrics: `--bench-encrypted --sing` / `./Scripts/helut_encrypted_sing.sh`. Mock/trivial graphs are the boolean oracle (`directives/fhe-graduation.md`). Research-release: `directives/research-release.md`. Parameters: `directives/parameter-cookbook.md`.

## Boolean-path performance snapshot

Logs: `logs/helut-boolean-bench-*.log`, `logs/helut-boolean-scale-*.log`, `logs/helut-phase-seam-*.log`. Seams: `directives/fhe-graduation.md`.

| Target | Compile | Steady |
|--------|---------|--------|
| PicoRV32 N=1024 B=1 | 1.30 s | 173 ms/tick |
| Enigma M3 N=1024 B=1 | 0.04 s | 15 ms/tick |
| Enigma M3 N=1024 B=1000 | 0.53 s | 73 ms/tick (~6 GiB) |
| Enigma M3 N=1 B=1000 | 0.04 s | 15 ms/tick (~91 MiB) |
| Enigma M3 equiv N=1024 / N=1 | — | PASS / PASS |

## Tier 2 — Historical vectors

Fixtures:

- `Fixtures/historical_enigma_vectors.json` — keyed decrypt tests
- `Fixtures/cryptocellar_catalog.json` — full CryptoCellar message + key-sheet index

**Keyed & asserted by HELUT oracle (`supported: true`):**

| Vector | Source |
|--------|--------|
| 1930 Instruction Manual (UKW A) | [CryptoCellar](https://cryptocellar.org/enigma/e-message-1930.html) |
| Barbarossa BLA / LSD (1941) | Franklin Heath / Sullivan–Weierud |
| Scharnhorst last message (1943) | [CryptoCellar / M4 Project](https://cryptocellar.org/bgac/scharnhorst.html) |
| FHPQX HG Nord (1941) | Ostwald–Weierud |

**Catalogued, not yet asserted (avoid false positives):**

- [1938 Army FRX teleprinter](https://cryptocellar.org/enigma/tbombe.html) — CT/PT + pencil keys AGI/YBE/LUN; daily key pending lock
- [Dolphin 1944](https://cryptocellar.org/enigma/dolphin.html) — Erskine break challenge (key withheld)
- [M4 Shark/Turtle/Pike](https://cryptocellar.org/bgac/m4-messages.html) — needs 4-rotor oracle
- [Flossenbürg KL messages](https://cryptocellar.org/Flossenbuerg/index.html) — keys in per-message PDFs
- Army / Luftwaffe / Triton / Nixe **key sheets** (PDF) listed in `cryptocellar_catalog.json`

## Tier 3 — Scoreboard

`LanguageScorer` computes Index of Coincidence and German military n-gram log-probs per lane, then `detectSpikes` isolates winners above the noise floor.

## Commands

```bash
swift test --filter EnigmaBombeValidationTests
swift run -c release helut -- --validate
```
