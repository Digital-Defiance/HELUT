# The Mulein board

*A diagonal board that counts contradictions instead of short-circuiting on the first one.*

**Campaign machine:** **Nazi Blaster 9000** — the unified P1030680 Mulein search machine and
overall campaign.

**Historical canonical campaign:** **Fahrenheit 261** — the 261-entry canonical-menu/Future
campaign. The name denotes the inventory and campaign; its bounded Phase 51.14 launch executed
only identity Future 0 at settings `0..<256`, not the other 260 Futures.

Status: **known-key mechanisms graded; legacy target prefixes partial; operational-prior
setting-0 preflight complete across all 628 Futures. Not a decrypt.** Tolerance 1 is 3/24,
post-gap δ=4 is 144/237, and full middle × right is 1/24. Complete-receipt benchmarking
selected `BANK_LANES=4`. The Phase 51.15 preflight covered shell 0, setting 0, and all 628
operational Futures with 16,328 checked receipts. Fifteen host-replayed one-edge physical
candidates survived (5 identity-family, 10 post-gap), but every candidate was non-exact:
0 exact hits and 0 BREAK gates. The bounded settings `1..<256` production stripe across all
628 Futures is **RUNNING by operator report; outcomes are unknown and ungraded at this sync**
in fresh ledger `logs/p1030680-mulein-operational-settings-000001-000256-v3.jsonl`; broader
settings and shells remain open.
Ledger: `BREAK_P1030680.md` Phases 51.12–51.15 · Report: `writeup.tex` · Host board:
`Sources/HELUTCore/MuleinBoard.swift` · Production RTL: `Apps/Mulein/rtl/mulein_closure_seed.sv`,
`Apps/Mulein/rtl/mulein_future_tensorlut_top.sv`

---

## 1. On whose shoulders

Nothing here is a break with the 1940s design. It is one more board bolted onto a machine
other people built, and the credit runs in a straight line.

| Contribution | Whose | What we reuse |
|---|---|---|
| The mathematical break of Enigma — rotor wiring recovered from permutation theory | **Marian Rejewski**, with Różycki and Zygalski (Biuro Szyfrów, 1932) | The fact that Enigma is a *group*, and that its structure is attackable at all |
| The **bombe**: test a crib against every rotor setting, reject by contradiction | **Alan Turing** (1939–40) | The entire search architecture. Our sweep is his loop, in Metal |
| The **diagonal board**: exploit that the plugboard is an involution, so σ(x)=y implies σ(y)=x | **Gordon Welchman** (1940) | The other half of every closure we run. `propagateCore` *is* his board |
| Ring-absorption reductions that pin the Greek and left rings | Turing-shaped, standard bombe practice | Our 676× shell collapse, re-verified against a non-AAAA true key |
| Recovering and publishing the U-534 traffic; **degarbling** the sister message P1030681 from two disagreeing transcripts | **Dan Girard** and **Frode Weierud**, hosted by **Hörenberg** | The corpus, the 48 known-key controls, and the entire empirical basis for believing garble matters |
| The crib-free ciphertext-only attack: hill-climb the plugboard per candidate setting | **Olaf Ostwald** and **Frode Weierud** | The discriminator that makes a tolerant board usable rather than a ghost factory |
| `enigma-cuda`, and the `-e` / `-s` interfaces | Ostwald / Weierud lineage | Partial plug exhaustion, and the "seed plugs from a bombe" idea we could finally close the loop on |

**Tolerance 0 is Welchman's board, bit for bit.** That is a design requirement, not a
coincidence: the tolerant path routes straight to `WelchmanBombe.propagate` at tolerance 0 so
the common case cannot drift from the historical machine.

---

## 2. The thing relays cannot do

This is the whole claim, and it is narrow.

On a physical bombe a contradiction **is** current finding a second path through the diagonal
board. The hypothesis short-circuits, the drum advances. There is no register to count in, and
no way to ask a wire to keep going after it has already conducted. Copper cannot answer:

> *How many* contradictions?

Every faithful reimplementation inherits that, including ours — `WelchmanBombe.propagate`
returns `nil` on the first doubled row. That is fidelity, not a bug.

In silicon the question can be posed differently:

> **How few menu edges must be deleted before this setting closes consistently?**

Accept the setting when ≤ *t* deletions suffice. That is the **deletion-tolerant diagonal
board**. It is not a new bombe; it is a new *board* on the existing one, which is exactly the
slot Welchman's contribution occupied — hence naming it for the board.

### Why anyone should care

A single mis-transcribed ciphertext letter contradicts a **true** menu, and an exact board then
discards the real key without comment or trace.

Girard needed *two independent transcripts* to degarble P1030681, and found an entire
four-letter group (`HMHY`) present on the Schlüsselzettel copy and blank on the plain-paper
copy. Our target is from the same boat, the same day, the same signals office.

So every exact-crib clean negative in this campaign — and there are many — is a negative about
the **recorded** ciphertext, not necessarily the transmitted one. The tolerant board is how
those negatives get re-opened against a transcription error instead of re-run identically.

---

## 3. Two failure modes, two mechanisms

Transcription error is edit distance, and edit distance has two halves. They need different
machinery, and conflating them was the first thing that had to be sorted out.

| Error | What actually went wrong | Fix | Which board |
|---|---|---|---|
| **Substitution** — `U` read as `N` | Wrong *letter* at a known position | Delete that menu edge | **Mulein board** (tolerance ≥ 1) |
| **Indel** — a four-letter group dropped | *Correct* letters at *shifted* positions | Re-index edges and shift step numbers | **Exact board**, new menu geometry |

### One board, two mechanisms

The Mulein board is the **garble-tolerant board**, and it comprises both mechanisms. That is a
naming decision, not a technical one: the two act at genuinely different layers and the
difference matters operationally, so it stays documented as internal structure rather than
collapsed away.

* The Mulein board relaxes the **deduction** while the crib-position → rotor-step alignment
  stays fixed.
* An indel changes **which scrambler each edge uses**. After the splice, every edge pairs with a
  different machine state. Nothing is relaxed — it is a different, *more specific* hypothesis.

The consequences favour the indel side:

1. **Indels need no new board at all.** The Metal kernel already reads a per-edge step array
   (`edgeStep[]`), so a spliced menu runs on the historical exact board with no kernel change.
2. **Therefore zero survivor inflation.** No pre-qualification gate, no ghost flood. Tolerance's
   entire cost problem simply does not arise.
3. **It is the better-evidenced hypothesis.** Girard *found* a missing group. In our own corpus,
   isolated substitution garble is only **4 controls / 8 events** — too thin to fit a confusion
   model on (Phase 50.9, which retracted an earlier overclaim about this).
4. **The search is small if you use the historical structure.** Kriegsmarine traffic was sent in
   four-letter groups, so a *group* going missing puts the splice on a multiple of four. For
   δ = 4 that is ~17 candidate splice points per placement, not 72.

They compose — a spliced menu can also be run at tolerance ≥ 1 — but neither contains the other.
The **deletion-tolerant diagonal board** is the substitution mechanism; explicit Future geometry
is the indel mechanism. Together they make the campaign machine edit-distance aware without
pretending the operations are equivalent.

### Production hardware shape

The production path is unified Verilog rather than a set of independent software closures:

1. One outer TensorLUT lane owns one rotor setting and one shared 80×26 scrambler trail.
2. Parameterized bank slots own explicit Future-Lattice `(a,b,step)` geometry and one seed each.
3. `mulein_closure_seed` runs exact-first one-edge repair, max/exact plug feasibility, and holds a
   complete tagged receipt until `result_ready`.
4. The host compiles evidence-preserving descriptors and replays hits; it does not substitute a
   host closure for the RTL result.

This is cleartext Verilog→Yosys→Float TensorLUT→Metal evaluation, **not FHE**.

---

## 4. What is proven

Mechanism claims below begin with known-key grades against P1030684 (published key, same day,
same boat), following the Phase 11 doctrine: grade machinery against a key it was not told
*before* pointing it at the unbroken message. Legacy target prefixes remain incomplete; the
unified bank's separately bounded target slice is listed with its exact coverage.

### Sensitivity — the exact board really does throw the key away

27-letter crib, offset 0, letters corrupted inside the crib span:

| Garbled letters | tolerance 0 | tolerance = *g* | plugs forced (correct/total) |
|---|---|---|---|
| 0 | KEPT | KEPT | 25/25 |
| 1 | **LOST** | **KEPT** | **25/25** |
| 2 | **LOST** | **KEPT** | **25/25** |
| 3 | **LOST** | **KEPT** | **25/25** |

The `LOST → KEPT` transition is the mechanism working. The plug column matters just as much:
a tolerant stop still forces **all 25** deductions correctly, and the crib-free climber needs
only **4** correct plugs to flip its margin positive at 72 letters (Phase 50.6). The two halves
compose — a garbled true key survives the board *and* is finishable.

Receipt: `logs/garble-board-selftest-2026-08-17.log`

### Equivalence in silicon

| Check | Result |
|---|---|
| Kernel vs host, lane by lane | **0/192 mismatches**, every tolerance, 45 crib × offset × tolerance cells |
| No-op trap (verdicts) | Cleared — kernel reproduces `LOST → KEPT` |
| No-op trap (work performed) | Cleared — per-shell time 0.03 s → 0.5 s → ~7 s at tolerance 0 → 1 → 2 |
| Refactor regression | Byte-identical after moving the board into `MuleinBoard.swift` |

Receipts: `logs/garble-gpu-t2-2026-08-17.log`, `logs/garble-gpu-postrefactor-2026-08-17.log`

### The pinned-ring flag, graded two-sided

A flag that *narrows* the search space can silently exclude the answer, so it gets the same
treatment:

| Pinned ring | Expected | Result |
|---|---|---|
| `AAAH` (the control's ring in reduced coordinates) | BREAK | **BREAK FOUND**, all ten plugs, IC 0.064, tail −2.848 |
| `AAAA` (wrong ring) | no break | dead at the board |

Receipt: `logs/control-pinnedrings-2026-08-17.log`

### Bounded target prefixes — incomplete

| Arm | Durable boundary | Resume |
|---|---|---|
| Tolerance 1 × right rings | **3/24**, all three completed placements dead at board | `--bombe-menus 0 --bombe-ring-sweep --bombe-garble-tolerance 1 --bombe-from 4` |
| Post-gap δ=4 × right rings | **144/237**; entry 111's 8 raw stops produce 0 valid ≤10-plug completions | `--bombe-menus 0 --bombe-from 145` |
| Full middle × right rings | **1/24**, completed placement dead over 4.152×10¹¹ settings | `--bombe-menus 0 --bombe-middle-ring --bombe-ring-sweep --bombe-from 2` |

These are local negatives from the existing cleartext Welchman/Metal campaign path. None is a
completed hypothesis family or a decrypt.

### Fahrenheit 261 — runtime-selected historical 261-entry bank

At `BANK_LANES=1`, thirteen P1030684 probes emit identical complete held receipts across
source RTL, post-Yosys RTL, clear Yosys-JSON simulation, and cleartext Float TensorLUT,
including backpressure. The original four digest-bound jobs remain unchanged. Nine separate
probes add target-shaped 72-symbol recordings: correct leading Δ6 (`CT[6..<78]`,
`PT[38..<78]`) at `VYAA/I` survives exactly through step 77 with zero dropped edges; correct
leading Δ8 (`CT[8..<80]`, `PT[40..<80]`) at `VYAA/J` survives exactly through step 79 with
zero dropped edges. A true-Δ8 recording falsely interpreted as Δ6 is absent at `VYAA/V`; the
correct Δ8 Future is also absent at adjacent setting `VYAB/J` and adjacent seed `VYAA/K`.

The composed controls inject one post-gap garble at crib edge 20 / recorded index 52. Under Δ6
that edge is transmitted step 58; under Δ8 it is step 60. In both cases tolerance 0 rejects the
published true candidate, while tolerance 1 recovers it non-exactly by dropping that edge alone.
The independent Swift oracle enumerates both settings, all eleven work items, and all 26 seeds
before truth metadata selects submitted jobs. The fast oracle grade passed in 0.007 s; the
13-case four-surface grade passed in 609.635 s with 44,341 LUT6, 693 DFF, 56,181 wires, and
28 levels. Reproduce with:

```bash
swift test -c release --filter MuleinFutureTests
swift test -c release --filter MuleinFutureTensorLUTTests/testDeltaSixAndEightGarbleSwiftOracleControls
swift test -c release --filter MuleinFutureTensorLUTTests/testProductionSourcePostYosysClearAndTensorLUTAgree
```

This is a P1030684 known-key geometry/composition receipt only: it reads no P1030680 data, does
not promote the staged target Δ6/Δ8 inventories to campaign coverage, and is cleartext rather
than FHE. Width-qualified artifacts pass at **1/2/4/8/16**. Identical complete-receipt workloads
(16 settings × 16 jobs × 5 repetitions) produced the same normalized digest and median rates of
**233.777350172 / 264.718510307 / 276.035471632 / 273.889660462 /
230.780129610 receipts/s**, selecting **`BANK_LANES=4`** by runtime rather than graph size.
The selected graph has 189,032 LUT6, 2,772 DFF, 205,177 wires, and 28 levels. Selection receipt:
`logs/mulein-future-tensorlut-selection.json`.

The protocol-v3 runner binds one immutable manifest snapshot, netlist, graph, width, protocol,
and exact plan. Its ledger admits only an exact ordered prefix and stores every canonical per-job
receipt projection, allowing digest recomputation and derived hit/BREAK-gate state. Persisted hits
are host/scoring-replayed; a prior gate halts before evaluator submission. Semantic drift, sparse
or reordered rows, post-gate records, and candidate deletion fail closed. Atomic non-truncating
open plus one retained exclusive descriptor enforces a single writer through final synchronization.
Repaired and post-gap positives stay non-BREAK-eligible until their correction/full-message
geometry is explicitly replayed.

The Fahrenheit 261 deterministic P1030680 inventory contains **261 entries** (24 identity + 237 post-gap δ=4),
fingerprint `fnv1a64-32fd2543824a62a3`. Only shell 0 `B/beta/IV-III-VIII/AAAA`, identity
Future 0, settings `0..<256` ran. Protocol-v3 run
`sha256-e6dc10d45b2e2e9fb4fbc69936fd0909a89dbecc4d53063cb415c58232fc1360` completed
**16/16 synchronized chunks, 6,656/6,656 canonical receipt projections, 0 hardware positives,
and 0 BREAK gates**; exact-prefix resume revalidated 16/16 without append. Receipt:
`logs/p1030680-mulein-unified-smoke-v3.jsonl`, SHA-256
`687d08383111b90b284ca08496d5ba02c9d0b560c17613c2e56283362b1f7e7d`.

This is one historical clean local negative, not a 261-Future result: the other 260 Futures,
settings `256..<456976`, and other shells were not part of that Phase 51.14 plan. This is
cleartext Float TensorLUT/Metal, not FHE, and supplies no key or decrypt.

### Nazi Blaster 9000 — operational-prior preflight and production stripe

The operational/scuttle arm uses a separate immutable inventory rather than rewriting the
canonical artifact: `Fixtures/p1030680_mulein_regenbogen_hannibal_identity_postgap_delta4.json`,
SHA-256 `1086b697d70ef9f05855292dd2e041b94a8551d18b1c51ec12c161a0c974c510`, fingerprint
`fnv1a64-616326e94036a97d`. It contains **628 Futures**: 314 identity plus 314 post-gap δ=4.

Two additional single-gap inventories are now **STAGED / UNEXECUTED** against the same 80-step
W=4 graph; they do not change the active delta-4 run or count as campaign coverage:

| gap | transmitted envelope | immutable manifest | inventory fingerprint | SHA-256 |
|---:|---:|---|---|---|
| δ=6 | 78 steps, max step 77 | `Fixtures/p1030680_mulein_regenbogen_hannibal_identity_postgap_delta6.json` | `fnv1a64-cd2a80759510a7ba` | `189a40e30a32415f722fdfc75bffbb132e59059883e7c262288c31812a21b3a6` |
| δ=8 | 80 steps, max step 79 | `Fixtures/p1030680_mulein_regenbogen_hannibal_identity_postgap_delta8.json` | `fnv1a64-686233848aefd1b9` | `20c9905a7a541bd756786838a70c203ccd7d930b743966c9a51b5b1c94428959` |

Each contains 314 identity plus 314 post-gap Futures. Protocol-v3 plan-only validation selected
only the post-gap suffix `314..<628`: 5,024 chunks and 2,089,984 planned receipts per arm, run
identities `sha256-d5d4f97f96cb5741c02d6cbde54ae3d6b04216b6e5be9de8cff8a235185e6224`
(δ=6) and `sha256-6a0c961b4a752118bee0873815afee371e90b3eb3e0d602b0fd284dabc50989c`
(δ=8). Plan-only evaluated no P1030680 settings and created no ledger. These inventories model
one contiguous missing span wholly before the crib; straddling or multiple gaps remain outside
this staged scope, and every post-gap survivor remains non-BREAK-eligible without calibrated
sparse full-message replay.

Protocol-v3 run `sha256-2b6bde1ead5ffd33b3e598038a7af597d9c1c189c9b607147c98451a527c727a`
covered shell 0 `B/beta/IV-III-VIII/AAAA`, setting 0, and Futures `0..<628`. It completed
**628/628 chunks and 16,328 checked receipts**. Host replay retained 15 one-edge physical
candidates: 5 identity-family repairs and 10 post-gap repairs. Every candidate was
`exact=false`, so the grade is **0 exact hits and 0 BREAK gates**. Identity-family repairs
remain non-BREAK-eligible without explicit correction replay; post-gap repairs require
geometry-aware full-message replay. These receipts do not establish that the ciphertext is
garbled. Durable ledger: `logs/p1030680-mulein-operational-preflight-v3.jsonl`, SHA-256
`55a68266f79ca0b17b6de18a80644883c7c8a2585ab2508d42d5d73c9a17f993`.

The exact bounded stripe is **RUNNING by operator report; outcomes are unknown and no receipt
grade has been ingested at this sync**: the same shell and all 628 Futures,
settings `1..<256`, fresh ledger
`logs/p1030680-mulein-operational-settings-000001-000256-v3.jsonl`, run identity
`sha256-efb770bcaddd2bc0581edbb19b66077160a806c30650a60d0b9d6a733c592cc0`, 10,048 chunks,
and 4,163,640 planned receipts. The prior plan-only invocation evaluated no settings and wrote
no ledger; the active operator invocation omits only `--mulein-future-plan-only`. No live hit,
gate, key, plaintext, or decrypt is claimed. Operational/scuttle hypotheses run first.
Afterward, the old playbook
returns through the same garble/indel/Future machinery; ordinary legacy resumes remain lower
priority at their durable boundaries. This ordering is a working search prior, not historical
proof.

---

## 5. What it costs — and the rule that was wrong

Tolerance *widens* what survives. Its price is survivor inflation, and getting this wrong is
how a tolerant board becomes a ghost factory.

At crib offset 0, inflation looked like a clean function of menu size:

| crib / edges @ offset 0 | *t*=0 | *t*=1 | *t*=2 |
|---|---|---|---|
| 16 | 1 | **130,787** | 454,052 |
| 17–19 | 1 | 1 | ~134,000 |
| 20–21 | 1 | 1 | ~85,000 |
| 22–27 | 1 | 1 | **1** |

That produced a rule — *"tolerance 1 needs ≥17 edges, tolerance 2 needs ≥22"* — which was
written into the ledger and the report.

**It was wrong, and it is withdrawn.** Varying the *placement* destroys it:

| Placement | *t*=0 | *t*=1 | *t*=2 |
|---|---|---|---|
| offset 15, crib **16** | 1 | **1** | 268,702 |
| offset 15, crib 18 | 1 | 1 | **3** |
| offset 40, crib 18 | **35** | **4,301** | 369,212 |
| offset 65, crib 18 | **79** | **16,019** | 281,743 |
| offset 40, crib **22** | 1 | 1 | **20,823** |

Sixteen edges costs nothing at offset 15; eighteen edges detonates at offsets 40 and 65. Crib
length does not predict inflation, and neither does the exact-board baseline on its own.

What governs it is the menu's **loop structure** — tolerance *spends* redundancy, and only a
loop-rich menu has enough to spend. Look at which placements detonate: the ones where the exact
board was *already* weak (`t0 = 35`, `t0 = 79`). **Tolerance amplifies an under-determined menu
rather than rescuing it.**

### The replacement rule is better than the one we lost

Tolerance is a **per-menu decision, pre-qualified by measurement**, never a global switch.
`--bombe-tolerance-prequal` is that gate. On the target's 24 strongest placements it passes with
**zero inflation** at tolerance 1. Conflict-directed one-edge repair measures a **6.2×** cost
factor rather than the 41× combinatorial ceiling: exact runs first, candidate deletions are
ordered by observed conflict, and most closures die early.

Tolerance 2 fails the gate on three of those menus (19,552 / 344 / **330,704** survivors), and
the worst is the weakest menu in the set — 18 edges, 14 letters. Exactly as predicted.

Receipts: `logs/garble-gpu-placements-2026-08-17.log`, `logs/tolerance-prequal-2026-08-17.log`

### Cost model

Closures per seed are `1 + E + C(E,2) + C(E,3)`. One 26⁴ shell is ~10 ms, so tolerance is cheap
per *shell* and expensive per *sweep*:

| Arm, per menu | *t*=0 | *t*=1 |
|---|---|---|
| Rings AAAA / pinned (1,344 shells) | ~12 s | ~8 min |
| Right-ring sweep (34,944 shells) | ~5 min | ~1.4 h |
| Full middle × right (908,544 shells) | 2.2 h | ~90 h |

Note the trap we nearly fell into: at ≥26 letters, rings AAAA covers **0/26** of the ring space,
so a tolerance run there is close to vacuous on long menus. Right-ring coverage is the minimum
that carries a real negative.

---

## 6. The implementation lesson: it was a no-op first

Recorded because it is easy to reintroduce and it measured as *nothing*.

Tolerance must **remove** edges *before* propagating, never abandon them mid-flight. The first
version did the latter, and produced one survivor at every tolerance level. Two causes
compounded:

1. **The bad value is already committed.** A garbled edge processed early writes a wrong σ(x)
   into `live`, which then propagates through other edges *and through the diagonal board*.
   Restoring the two rows that just conflicted unwinds none of that.
2. **The conflict surfaces at the wrong edge.** Whichever edge is being visited when the
   inconsistency becomes visible gets blamed — and that is usually a *correct* edge, so dropping
   it does not help and the real culprit stays in.

Enumerating the deleted set is order-independent and reuses the already-validated exact closure.
Within the legacy host path there is exactly one implementation of the board's logic, and both
host entry points call it. The production RTL is intentionally independent and must remain
cross-graded against the Swift oracle through all four surfaces.

A second guard exists for a subtler failure: **the seed letter must still touch a surviving
edge.** Without it, a reduced board can constrain nothing at all, and then *every* setting
"survives" — a silent way to turn the sweep into a random number generator.

---

## 7. Honest scope

- **Not a decrypt.** P1030680 remains unbroken.
- **Target evidence is bounded, not absent and not global.** Tolerance 1 is 3/24, post-gap δ=4
  is 144/237, and full middle × right coverage is 1/24; all three legacy arms are suspended at
  the printed resume boundaries above. The historical canonical-manifest unified slice remains
  DONE at shell 0 / identity Future 0 / settings `0..<256`, with 6,656 receipts and zero
  positives.
- **The operational-prior setting-0 preflight is complete, not a global elimination.** All 628
  Futures ran at setting 0, yielding 16,328 receipts and 15 host-replayed one-edge physical
  candidates. All were non-exact; no BREAK gate fired. Settings `1..<256` are plan-validated
  next in a fresh ledger; settings `256..<456976` and other shells remain open. Four-surface
  parity remains a P1030684 mechanism grade.
- **It does not assert the target is garbled or missing a group.** Sensitivity is a statement
  about mechanism behaviour under corruption, not evidence that corruption occurred.
- **Tolerance applies to menu edges, not to the diagonal board itself.** It is an algebraic
  relaxation of deduction. It nominates no letters and makes no claim about the ciphertext.
- **Indels are a distinct exact-board geometry mechanism.** Unified hardware carries both
  descriptor types without collapsing their meanings.
- **Cleartext TensorLUT is not FHE.** Fitness and receipt throughput here are cleartext Metal
  measurements, not encrypted tick rates.
- **A tolerant board without a discriminator is a ghost factory.** This one is only usable
  because Phase 50 supplies a scorer that provably finishes a true stop at 72 letters given four
  plugs, and leaves ghosts *below* the random-setting noise floor.
- The naming is local. In writing, prefer **deletion-tolerant diagonal board**.

---

## 8. Reproduce

```bash
# Sensitivity on a known key with deliberately corrupted ciphertext
./.build/release/helut --garble-board-selftest --garble-tolerance 3

# Kernel vs host, plus inflation at a chosen placement
./.build/release/helut --garble-gpu --garble-tolerance 2
./.build/release/helut --garble-gpu --garble-offset 40 --garble-crib 18 --garble-tolerance 2

# The gate. Must pass before any arm spends GPU-hours.
./.build/release/helut --bombe-tolerance-prequal Fixtures/p1030680_maxupper_strongest_menus.json \
  --bombe-garble-tolerance 2

# Pinned ring hypotheses ride one sweep; concurrent processes only timeshare the queue
./.build/release/helut --welchman --bombe-fixture Fixtures/p1030684_control_menus.json \
  --bombe-menus 1 --bombe-min-crib 16 --bombe-rings AAAH

# Resume tolerance 1 from its durable boundary.
./.build/release/helut --welchman \
  --bombe-fixture Fixtures/p1030680_maxupper_strongest_menus.json \
  --bombe-menus 0 --bombe-min-crib 16 --bombe-ring-sweep \
  --bombe-garble-tolerance 1 --bombe-from 4

# Resume the legacy post-gap δ=4 arm.
./.build/release/helut --welchman \
  --bombe-fixture Fixtures/p1030680_maxupper_strongest_menus.json \
  --bombe-menus 0 --bombe-min-crib 16 --bombe-ring-sweep \
  --bombe-indel 4 --bombe-indel-post-gap --bombe-indel-only --bombe-menus 0 --bombe-from 145

# Reproduce unified known-key parity, finite inventory, and W1/2/4/8/16 runtime selection.
make test-mulein-future-tensorlut
make emit-mulein-future-manifest
make sweep-mulein-future-tensorlut

# Plan or resume the completed bounded W4 target slice. With unchanged identities,
# the resume reads 16/16 durable chunks and appends nothing.
make build-mulein-future-campaign
.build/release/helut-bombe \
  --mulein-future-campaign \
  --mulein-future-manifest Fixtures/p1030680_mulein_identity_postgap_delta4.json \
  --mulein-future-netlist build/mulein/mulein_future_bank4_lut6.json \
  --mulein-bank-lanes 4 --subspace potsdam-neighbourhood --rings AAAA \
  --shell-from 0 --shell-count 1 --setting-from 0 --setting-count 256 \
  --future-from 0 --future-count 1 --chunk-settings 16 --tensor-batch 16 \
  --campaign-ledger logs/p1030680-mulein-unified-smoke-v3.jsonl

# Reproduce the active Nazi Blaster 9000 stripe's deterministic plan without evaluating P1030680
# or creating its ledger. The operator-reported active invocation omits only
# --mulein-future-plan-only; do not launch a second writer against the locked ledger.
.build/release/helut-bombe \
  --mulein-future-campaign --mulein-future-plan-only \
  --mulein-future-manifest Fixtures/p1030680_mulein_regenbogen_hannibal_identity_postgap_delta4.json \
  --mulein-future-netlist build/mulein/mulein_future_bank4_lut6.json \
  --mulein-bank-lanes 4 --subspace potsdam-neighbourhood --rings AAAA \
  --shell-from 0 --shell-count 1 --setting-from 1 --setting-count 255 \
  --future-from 0 --future-count 628 --chunk-settings 16 --tensor-batch 16 \
  --campaign-ledger logs/p1030680-mulein-operational-settings-000001-000256-v3.jsonl
```

## 9. Where the pieces live

| Piece | File |
|---|---|
| Host board, drop-subset enumeration, cost model | `Sources/HELUTCore/MuleinBoard.swift` |
| The MSL the GPU kernel embeds | `MuleinBoard.metalClosureSource` |
| The one shared closure (Welchman's board) | `WelchmanBombe.propagateCore` |
| The sweep that embeds the board | `Sources/HELUTToolKit/BombeMetal.swift` |
| Sensitivity + kernel cross-check | `Sources/HELUTToolKit/GarbleBoardSelfTest.swift` |
| The per-menu cost gate | `Sources/HELUTToolKit/TolerancePrequal.swift` |
| Production closure lane / shared-trail bank | `Apps/Mulein/rtl/mulein_closure_seed.sv`, `Apps/Mulein/rtl/mulein_future_tensorlut_top.sv` |
| TensorLUT packing / held-receipt decode | `Sources/HELUTToolKit/MuleinFutureTensorLUTPacking.swift` |
| Fahrenheit 261 deterministic 261-entry canonical inventory | `Sources/HELUTToolKit/MuleinFutureManifest.swift`, `Fixtures/p1030680_mulein_identity_postgap_delta4.json` |
| Nazi Blaster 9000 immutable 628-Future operational-prior inventory | `Fixtures/p1030680_mulein_regenbogen_hannibal_identity_postgap_delta4.json` · 314 identity + 314 post-gap δ=4 · `fnv1a64-616326e94036a97d` · SHA-256 `1086b697d70ef9f05855292dd2e041b94a8551d18b1c51ec12c161a0c974c510` |
| Four-surface known-key grade | `Tests/HELUTTests/MuleinFutureTensorLUTTests.swift` |
| Complete-receipt width benchmark / selection | `Sources/HELUTToolKit/MuleinFutureTensorLUTBench.swift`, `logs/mulein-future-tensorlut-selection.json` |
| Checked TensorLUT evaluator / durable target runner | `Sources/HELUTToolKit/MuleinFutureTensorLUTEvaluator.swift`, `Sources/HELUTToolKit/P1030680MuleinCampaign.swift` |
| Fahrenheit 261 historical bounded target receipt | `logs/p1030680-mulein-unified-smoke-v3.jsonl` |
| Nazi Blaster 9000 operational-prior setting-0 receipt | `logs/p1030680-mulein-operational-preflight-v3.jsonl` · 628/628 chunks · 16,328 receipts · 15 repaired/non-exact candidates · 0 exact hits/gates · SHA-256 `55a68266f79ca0b17b6de18a80644883c7c8a2585ab2508d42d5d73c9a17f993` |
| Nazi Blaster 9000 active production ledger | `logs/p1030680-mulein-operational-settings-000001-000256-v3.jsonl` · settings `1..<256` × 628 Futures · RUNNING by operator report · outcomes unknown/ungraded |
