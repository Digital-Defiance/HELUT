# ASIC-esque self-evolving cracker (veritable)

Goal: a **real** P1030680 attack machine — not HELUT mock-PBS theater.

## Split brain (intentional)

| Layer | Role | Analogy |
|-------|------|---------|
| **Cleartext batch datapath** (`CleartextBatchHybrid.swift`) | Decrypt + **attack score** (bigram) **or KPA letter-match** over `B = 17 576` | ASIC / hard macros |
| **Evolutionary outer loop** (`HybridBombeHarness.swift`) | Population of **shell + stecker** chromosomes | Self-evolution / reconfigurable search |
| **Host plugboard** | Stecker as tables | Bonding pads / soft I/O |
| **HELUT mock-PBS / PicoRV** | Systems research | **Out of band for cracking** |

Mock PBS cannot assign fitness. This cracker does not use them.

## Stochastic Bombe / KPA mode

German bigrams failed the P1030684 control at 72 letters (flat landscape). `--hybrid-control` switches fitness to **exact letter match** against a known/template plaintext and uses Metal kernel `m4_kpa_batch`. See [`stochastic-bombe.md`](stochastic-bombe.md).

```bash
.build/release/helut --hybrid --hybrid-control --quick          # oracle stecker smoke
.build/release/helut --hybrid --hybrid-control --hybrid-seed-drop 1
.build/release/helut --hybrid --hybrid-control --hybrid-blind --hybrid-pop 24 --hybrid-gens 40
```

## Chromosome genes

| Gene | Evolves? | Notes |
|------|----------|--------|
| Walzenlage (WO) | yes | Index into `--subspace` wheel-order pool (default `potsdam` = 6) |
| Greek wheel | yes | β / γ |
| Thin UKW | yes | B / C |
| Ringstellung | yes | **Free letter mutation** by default — AACU can become AAAA |
| Stecker | yes | Reciprocal pairs ≤ 10 |

`--hybrid-lock-shell` → only stecker mutates (old behaviour).  
`--hybrid-pool-rings` → rings only jump among subspace/CLI seed rings (no free A…Z walks).

```text
generation g
  for each shell chromosome:
    rebind stecker/rings/WO tables (µs — not Yosys)
    Block A/B: Metal m4_attack_batch over B=17576
      score = mean(bigram) − |IC−0.0749|×8 + 0.05×cribHits
    fitness = best lane score; host decrypts winner only
  elites + crossover + mutate
  halt on evaluateBreak
```

**Recompile note:** a Yosys→HELUT rebuild is fine for *systems* experiments (boolean-safe mock PBS under trivial encoding). For this cracker, scoring LUTs live in the cleartext Metal kernel (compile once per process); shell genes only reload 26-byte tables.

## Run

```bash
swift build -c release

# Smoke (potsdam WO × evolving rings/stecker/…)
.build/release/helut --hybrid --quick

# Start seeded on AACU — can still evolve toward AAAA / VCCH / elsewhere
.build/release/helut --hybrid --rings AACU --hybrid-pop 32 --hybrid-gens 80

# Broader WO pool
.build/release/helut --hybrid --subspace two-notch --hybrid-pop 48 --hybrid-gens 100
.build/release/helut --hybrid --subspace full-potsdam-rings --hybrid-full-greek

# Legacy: fix shell, evolve stecker only
.build/release/helut --hybrid --hybrid-lock-shell --rings AACU
```

Still useful to run `--campaign` in parallel for exhaustive shell ladders; hybrid is the stochastic multi-gene searcher.

## What “done” looks like

`evaluateBreak` → strong naval cribs + German IC/likeness → then Kenngruppen/Grund on `VROL NMKA`.

## Known-key rehearsal — READ THIS BEFORE ANY LONG RUN

```bash
.build/release/helut --exhaust-selftest
```

Runs the whole pipeline against **P1030684** (Potsdam 1 May 1945, published key: UKW B, γ,
IV-III-VIII, rings AACU, key VYAA, 10 plugs) truncated to P1030680’s 72 letters. Measured:

| Check | Result | Meaning |
|---|---|---|
| Level 1: rank of the true message key by zero-plug IC, correct wheels/rings | **223 118 / 456 976 (48.8th pct)** | IC has **no** signal at 72 letters with 10 plugs (true IC 0.0379 ≈ random 0.0385) |
| Level 2: stecker hill-climb *from the true rotor setting* | **4/72 letters, 0/10 plugs**, bigram −3.127 vs truth −2.872 | The climb finds a wrong local optimum that *scores better* than the truth |

**Conclusion: the blocker is statistical, not computational.** The GPU sweep, the degeneracy
pinning and the GA are all sound; the objective function cannot see the answer. A high
`likeness` on a 72-letter decrypt is meaningless — the search overfits ~47 bits of stecker
freedom to 72 letters. Do not trust `likeness` without strong cribs.

Any proposed improvement must move those two numbers. That is the gate.

## Next hardening (in priority order)

1. **Bigger n-gram statistics.** `Fixtures/german_corpus.txt` is ~10.3k letters — ~15 counts
   per bigram cell, and far too small for trigrams. Published ciphertext-only Enigma work
   uses tri/quadgram tables from millions of letters. This is a data problem, and it gates
   everything else.
2. **Hill-climb at every rotor setting**, not after an IC sieve — Level 1 proves the sieve
   discards the answer. That is ~614M climbs, which is exactly the workload the GPU exists
   for (move `hillClimb` into the kernel).
3. **Crib-driven Bombe with a Welchman diagonal board.** At n=72 statistics are marginal but
   crib logic is *deterministic*: a menu plus the diagonal board eliminates stecker
   hypotheses by contradiction instead of fitting them. `M4CribDrag` supplies placements;
   the closure/deduction step is not built yet. Historically this is the method that worked.
4. Multi-process shard of subspaces (only worth it after 1–3).
