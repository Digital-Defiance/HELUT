# The Mulein board

*A diagonal board that counts contradictions instead of short-circuiting on the first one.*

Status: **built and graded on known keys. Not a decrypt. No P1030680 verdict.**
Ledger: `BREAK_P1030680.md` Phase 51 · Report: `writeup.tex` · Code: `Sources/HELUTCore/MuleinBoard.swift`

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
Together they make the bombe **edit-distance aware**. The board is only the substitution half.

---

## 4. What is proven

Everything below is a known-key grade against P1030684 (published key, same day, same boat),
following the Phase 11 doctrine: grade the machinery against a key it was not told, *before*
pointing it at the unbroken message.

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
**zero inflation** at tolerance 1 and a measured **15.3×** cost factor — better than the 41×
combinatorial ceiling, because the seed-attachment guard prunes and most closures die early.

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
There is exactly one implementation of the board's logic in the repository, and both entry points
call it.

A second guard exists for a subtler failure: **the seed letter must still touch a surviving
edge.** Without it, a reduced board can constrain nothing at all, and then *every* setting
"survives" — a silent way to turn the sweep into a random number generator.

---

## 7. Honest scope

- **Not a decrypt.** P1030680 remains unbroken.
- **No P1030680 verdict from the board yet.** Pre-qualification passes; the arm is running.
- **It does not assert the target is garbled.** Sensitivity is a statement about the board's
  behaviour under corruption, not evidence that corruption occurred.
- **Tolerance applies to menu edges, not to the diagonal board itself.** It is an algebraic
  relaxation of the deduction. It nominates no letters and makes no claim about the ciphertext.
- **Indels are a separate mechanism** and are not implemented by the board (§3).
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

# The arm. Right-ring coverage, because AAAA covers 0/26 at these crib lengths.
./.build/release/helut --welchman \
  --bombe-fixture Fixtures/p1030680_maxupper_strongest_menus.json \
  --bombe-menus 0 --bombe-min-crib 16 --bombe-ring-sweep --bombe-garble-tolerance 1
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
