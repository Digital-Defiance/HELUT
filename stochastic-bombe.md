# The Stochastic Bombe: Evolutionary Decryption under Tensor Arithmetic

The 1945 electromechanical Welchman Bombe was a masterpiece of deterministic logic. It relied on fixed, known-plaintext cribs to form closed electrical loops, allowing the machine to instantly detect and eliminate impossible physical states. However, when confronting short, non-standard intercepts—such as a 72-character dummy test or structural training broadcast from the Thetis network—traditional crib-dragging fails. Without rigid structural loops, the deterministic engine loses its ability to enforce logical contradictions.

**The Stochastic Bombe** flips this paradigm. Instead of relying on boolean elimination to collapse a circuit, it treats decryption as a highly parallelized **key** search against a **fixed or small template library** of hypothesized plaintexts. By combining genetic algorithms with Metal cleartext batch lanes (`B = 26³ = 17 576` per Greek window), the engine scores candidate daily shells by how exactly the decrypt matches the template—not by German n-grams.

> **Not** random search over \(26^{72}\) plaintext space. That is infeasible. Feasible: search keys (stecker / shell / message key) while \(P\) is a hypothesized 72-letter string or a small bank of templates. German-ness is optional; Thetis traffic need not look like Potsdam.

## Implementation status (HELUT)

Shipped in `--hybrid --hybrid-control` (`HybridBombeHarness.swift`, `CleartextBatchHybrid.swift`):

| Piece | Role |
|-------|------|
| Metal kernel `m4_kpa_batch` | Per-lane letter-match count vs known/template PT |
| Host GA | Evolves stecker (optionally full shell) under match fitness |
| Inner scan | Full \(26^4\) message keys = 26 Greek windows × 17 576 L/M/R lanes |
| Parallelism | GPU saturates each chromosome; population eval is sequential in KPA mode to avoid Metal queue thrash; bigram mode parallelizes the population |
| Halt | Exact decrypt == template → control pass |

### Control grades (P1030684, first 72 letters, shell locked UKW B / γ / IV-III-VIII / AACU)

| Mode | Result | Log |
|------|--------|-----|
| Oracle stecker seed | **PASS** 72/72 in ~0.2 s, message key `VYAA` | `logs/stochastic-bombe-control-seeded.log` |
| Near-miss (`--hybrid-seed-drop 1`) | **PASS** 65→72 via hill-climb (~2 s) | `logs/stochastic-bombe-control-nearmiss-drop1.log` |
| Blind stecker (`--hybrid-blind`) | 40 gens × pop 24: climbed 16→**22/72**, then stuck (local max) | `logs/stochastic-bombe-control-blind-climb.log` |

```bash
.build/release/helut --hybrid --hybrid-control --quick
.build/release/helut --hybrid --hybrid-control --hybrid-seed-drop 1 --quick
.build/release/helut --hybrid --hybrid-control --hybrid-blind --hybrid-pop 24 --hybrid-gens 40
```

## Architectural Overview

HELUT hooks into Yosys for netlist→tensor demos, but the **boolean-faithful** Stochastic Bombe datapath is the cleartext Metal/CPU batch (same stepping as `EnigmaM4Machine`). Mock-PBS is never used for fitness.

The host feeds stecker/shell chromosomes; the GPU decrypts all L/M/R starts for each Greek position and returns match scores. Driving the loop on Apple Silicon unified memory keeps bandwidth off the critical path.

## The Evolutionary Pipeline

**1. Population Generation** — stecker (± shell: WO / Greek / UKW / rings).

**2. Parallel Tensor Execution** — for each chromosome, 26 × 17 576 cleartext lanes scored by letter match to the template.

**3. Fitness** — \(F(K) = \#\{i : D_K(C)_i = P_i\}\) (0…72). Halt on exact match. German bigrams are a separate legacy path (`m4_attack_batch`) that failed the same control at 72 letters.

**4. Selection / Mutation / Hill-climb** — elite retention, crossover, stecker mutations, optional local KPA hill-climb on elites (`kpaHillSteps`).

## Operational Advantages

- **Crib independence for Welchman:** when no ≥16 loop exists, templates still give a sharp objective.
- **Reversing Turing:** 1945 eliminated impossible keys; we can also *rank* better keys at GPU scale—something electromechanical drums could not do.
- **Noise tolerance:** partial template agreement ranks near-miss steckers (9/10 plugs scored 65/72).
- **Hardware symbiosis:** GPU evaluates massive lane batches; host evolves the discrete stecker/shell genes.
- **Honest limit:** more blind generations alone will not melt a 22/72 local max. **What gets P1030680:** a Thetis-shaped template bank + shell constraints + harder stecker search (Welchman still owns any real ≥16 crib).

## Rigor protocol (Phase 18+)

Do **not** treat ~50–70% of 16–24 constrained letters as evidence. That band is reachable by max-over-\(26^4\) plus GA climb.

| Gate | Rule |
|------|------|
| Fitness | Match **ratio** (fraction of constrained letters), absolute hits as tie-break |
| Survivor | `ratio ≥ 0.80` **and** `ratio ≥ empiricalNoiseFloor + 0.10` |
| Exact | `hits == constrained` → halt; hand crib to Welchman |
| Priors | Run **both** `potsdam` and `two-notch` before blaming the plaintext shape |
| Noise floor | Random shells (no evolution) per template × subspace before the GA |

```bash
.build/release/helut --hybrid --hybrid-stochastic --hybrid-rigor \
  --hybrid-pop 12 --hybrid-gens 12 --hybrid-noise-samples 8 \
  --rings AAAA,AACU 2>&1 | tee logs/stochastic-bombe-p1030680-rigor.log
```

Fixture: `Fixtures/p1030680_stochastic_structural.json` (16–24 constrained, self-stecker legal).  
Ledger: `logs/stochastic-bombe-p1030680-rigor.json` — training structural bank **0 survivors** (best 68.8% `THETIS@1`).

### Collapse / tactical-fallback prior

Same architecture; new lexicon if Thetis was a shadow operational net in the final days:

- Scuttle: `VERSENKEN`, `VERNICHTEN`, `REGENBOGEN`
- Urgency: `SOFORT`, `GEHEIM`, `WICHTIG`
- Hubs: `FLENSBURG`, `KIEL`, `DOENITZ`
- Muster: `ANTWORTEN`, `MELDEN`

```bash
.build/release/helut --hybrid --hybrid-stochastic --hybrid-rigor \
  --hybrid-templates Fixtures/p1030680_stochastic_collapse_rigor24.json \
  --hybrid-ledger logs/stochastic-bombe-p1030680-collapse-rigor.json \
  --rings AAAA,AACU 2>&1 | tee logs/stochastic-bombe-p1030680-collapse-rigor.log
```

Result: **0 survivors**, best **68.8%** `DOENITZFLENSBURG@0` — same rigor ceiling as training. Fixture: `Fixtures/p1030680_stochastic_collapse.json`.

Weather / keyboard / Kurzsignal prior (`Fixtures/p1030680_stochastic_weather.json`): **0 survivors** under rigor — same coincidence band.

## Meta-evolve (self-evolution allocation)

Equal GA budget on a fixed bank leaves evolution on the table. `--hybrid-meta-evolve` closes the loop:

1. **Invent** a broad prior library (`Fixtures/p1030680_stochastic_invented.json` + structural seeds)
2. **Cheap probe** every mask (short GA + noise floor)
3. **Select** top-K by **Δ over noise** (not raw %)
4. **Deepen** only those winners (full GA budget)
5. **Mutate** hypothesized plaintext neighbors of deep parents; repeat

```bash
.build/release/helut --hybrid --hybrid-stochastic --hybrid-meta-evolve \
  --subspace potsdam --rings AAAA,AACU \
  --hybrid-invent-cap 40 --hybrid-deepen-keep 5 --hybrid-neighbors 8 \
  --hybrid-meta-rounds 2 --hybrid-pop 12 --hybrid-gens 16 \
  2>&1 | tee logs/stochastic-bombe-p1030680-meta-evolve.log
```

## RIGA — random-injection GA (Option A shipped; Option B parked)

The ~65–69% coincidence wall is not a Metal throughput problem. Larger populations help only when fitness has a true gradient (control KPA) or when immigration escapes a *shell* local max under a near-true template.

### Option A — Shell-RIGA (implemented: `--hybrid-riga`)

Each chromosome is still a **daily shell + stecker**. Fitness still exhausts all \(26^4\) message keys on the GPU (`B = 17 576` L/M/R × 26 Greek). Host refill each generation:

| Slice | Default | Role |
|-------|---------|------|
| Elites | ~1% (`--hybrid-elites`) | keep intact (after optional KPA hill-climb) |
| Immigrants | ~19% (`--hybrid-immigrants`) | uniform-random fresh shells/steckers |
| Mutants | remainder | crossover + mutation from the top half |

Defaults under `--hybrid-riga`: pop **256** / gens **48** (quick: 32 / 12), `freeRings=true` unless `--hybrid-pool-rings` or `--hybrid-lock-shell`. Scores stay on the host (unified memory — no GPU top-K).

```bash
# Control smoke (stecker-only immigrants; shell stays locked)
.build/release/helut --hybrid --hybrid-control --hybrid-riga --quick

# Live: weather bank + RIGA + unbound rings (still needs a near-true template to clear 80%)
.build/release/helut --hybrid --hybrid-stochastic --hybrid-rigor --hybrid-riga \
  --hybrid-templates Fixtures/p1030680_stochastic_weather.json \
  --hybrid-ledger logs/stochastic-bombe-p1030680-weather-riga.json \
  --hybrid-pop 64 --hybrid-gens 24 \
  2>&1 | tee logs/stochastic-bombe-p1030680-weather-riga.log
```

### Option B — Full-key RIGA (parked)

**Not implemented.** Future path if Option A saturates:

- Grid of \(N \approx 2^{20}\)–\(2^{22}\) **complete** keys (WO + rings + stecker + Grundstellung) per pass
- One 72-letter decrypt per engine (no inner \(26^4\) sweep)
- Host partitions elites / mutants / immigrants; return **raw scores for all N** (top-K on GPU not worth it on Apple Silicon unified memory)
- Memory: ~70 MB @ 1M keys, ~285 MB @ 4M — comfortable on 64 GB
- Does **not** brute \(10^{20}\) naval keys; it is denser sampling of full-key space at the cost of missing the true message key unless immigration lands nearby

Park reason: Option A already spends more message-key work per shell than one fixed-pos decrypt; build B only if shell-RIGA + free rings still cannot climb a known-good control under blind stecker, or a live template clears noise Δ but not absolute ratio.
