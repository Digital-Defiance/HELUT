# E256-X1 mixed-walk four-round activity bound

<!-- E256-X1-MIXED-WALK-ACTIVITY-CONTRACT-START -->
## X1.1 Status, predecessors, and freeze boundary

This marker is the frozen pre-implementation contract for **E256-X1**, an exact
lower-bound gate on the number of active S-boxes over any four consecutive
E256-H rounds when the H4 row-offset selector changes per round. X1 grades
exactly one thing that the E256-X0 receipt recorded as
`mixed_four_round_bound = OPEN_NOT_GRADED`. It changes no cipher, selects no
round count or production policy, and does not promote E256-063.

The predecessors are immutable:

- `logs/e256-hardware-candidate-gate.json`, schema
  `E256-HARDWARE-CANDIDATE-GATE-1`, whose
  `deterministic_payload.results.h4_wiring.certified_set` is the ordered
  384-entry H4 catalog with canonical compact-JSON SHA-256
  `199f1f7bddccf19ce5aa0bde0987441735d628354140d53ebdfec538d7b3f5ed`.
- `logs/e256-wide-state-gate.json`, schema `E256-WIDE-STATE-GATE-1`,
  deterministic payload
  `21758ce220b9da469a18ea617fa7b2fd41e906add69a258f830b12843e3e495b`, which
  certified all 69 nonzero MixColumns minors, branch number 5, distinct row
  offsets, and discharged `E256-W-WIDETRAIL-25-v1` for **25 active rotors over
  four rounds** under a **fixed** selector.
- `logs/e256-x0-h4-evolution-gate.json`, schema `E256-X0-H4-EVOLUTION-GATE-1`,
  deterministic payload
  `35060c802427046f5f4630c6b9db6401d8ac90c4649fc0cf088d3f35f31b1b44`, graph root
  `d7e44b625acc693a28469dd993edfe3bf8cd7a4b966275a70ad7cf3941e4a80a`, which
  proved the exact three-round dependency criterion `S(y)+S(z)=Z_8` over all
  147,456 ordered catalog pairs and derived 73,728 safe directed transitions.

At this freeze point `directives/e256-x1-mixed-walk-activity-preregistration.json`,
`Scripts/e256_x1_mixed_walk_activity_gate.py`,
`logs/e256-x1-mixed-walk-activity-gate.json`, and
`build/e256-x1-mixed-walk-activity/` did not exist. The machine preregistration
must be written after this marker and before any runner, receipt, or scratch
artifact, and its raw SHA-256 recorded outside this marker.

**Prior disclosure — X1 is a complete verification, not a blind prediction.**
A read-only exploration preceded this freeze and already observed the following.
Every item is prior disclosure and must be labelled as such in the receipt. X1
must reconstruct each one exactly; any disagreement invalidates the harness.

1. The 16 catalog support masks are exactly the sixteen 4-element subsets
   `S` of `Z_8` with `S+S = Z_8`, out of 70 such subsets.
2. The catalog is closed under offset translation and under cyclic row rotation.
   Single-tuple translation orbits and translation-plus-rotation orbits are
   free, giving 48 and 12 classes respectively.
3. The canonical triple-class count under per-round translation combined with
   global row rotation is **27,648**, equal to `384^3 / 2048`, so that group
   action is free on ordered catalog triples.
4. The exact minimum for the fixed Rijndael tuple `(0,1,3,4)` repeated three
   times is **25**, agreeing with the inherited `E256-W-WIDETRAIL-25-v1` value.
5. The exact minimum for the frozen X0 fallback alternation
   `(0,1,2,5) / (0,1,4,7) / (0,1,2,5)` is **25**.
6. All 384 fixed-repeated catalog triples have exact minimum **25**.
7. A 3,000-class random canonical sample had exact minimum **25** in every
   class, with the X0-safe subfamily and the non-safe complement both at 25.
8. Control minima observed: zero row offsets **10**, MixColumns branch number
   forced to 4 gives **4**, single-parity offsets `(0,2,4,6)` repeated gives
   **25**, and non-certified distinct tuples sampled gave **25**.
9. A greedy `(1,4,...)` witness constructor does **not** reach 25; it returned
   40 or 45. Witnesses therefore come from a solver and must be verified by an
   independent exact checker rather than constructed by that heuristic.

## X1.2 Frozen construction, activity model, and bound direction

The graded round function is the E256-W / E256-H round, byte `4c+r` at row `r`
and column `c` of a 32-byte state in 4x8 geometry:

```text
round: SubBytes(32 lanes) -> ShiftRows(w) -> MixColumns -> AddRoundKey
```

ShiftRows uses the forward convention of `Scripts/e256_wide_gate.py::row_shift`,
`out[r][c] = in[r][(c + w_r) mod 8]`. MixColumns is the AES 4x4 circulant MDS
matrix over `GF(2^8)/0x11b` applied to each of the 8 columns, with branch
number 5 inherited from E256-062 and not re-derived here.

A **byte-activity pattern** is `P` in `{0,1}^{4x8}`. SubBytes and AddRoundKey
preserve activity exactly. ShiftRows permutes it exactly. For MixColumns, let
`a` be the input column weight and `b` the output column weight. The frozen
MDS truncated constraint is

```text
(a = 0 and b = 0)   or   a + b >= 5
```

**Bound direction, stated once and load-bearing.** Every actual differential
trail projects onto an activity pattern satisfying these constraints, so the
relaxation admits at least every real trail. Therefore

```text
min over the relaxation  <=  min over actual differential trails
```

and the relaxation minimum is a **valid lower bound** on the number of active
S-boxes. It is not the number of trails, not a differential probability, and
not a statement that any minimising pattern is realisable by actual
differences. Value and cancellation feasibility remain out of scope, exactly as
X0 left them.

## X1.3 Frozen window convention and canonical quotient

A four-round activity window has exactly four S-box layers `P_1..P_4` and
exactly three ShiftRows/MixColumns boundaries, so it is indexed by exactly
three ordered selectors `(w_1, w_2, w_3)`. This is the same three-selector
window arity that X0 graded for dependency. The graded cost is

```text
cost(P_1..P_4) = |P_1| + |P_2| + |P_3| + |P_4|
```

subject to the MDS constraint at each boundary `i` in `{1,2,3}` between
`SR_{w_i}(P_i)` and `P_{i+1}`, and to `|P_1| >= 1`. The MDS constraint already
forbids activity arising from an inactive boundary, so a nonzero first layer is
the exact nonzero condition and must be verified as such.

Two symmetries are **verified, never assumed**:

- **Per-round translation.** `SR_{w+t} = Rot_t . SR_w`, where `Rot_t` is a
  uniform column rotation. `Rot_t` commutes with MixColumns because MixColumns
  is column-local and identical per column, and with every ShiftRows because
  both are per-row column shifts. Adding a constant to one round's offsets
  therefore preserves all layer weights.
- **Global row rotation.** `R_rho . SR_w = SR_{R_rho w} . R_rho`, and `R_rho`
  commutes with the circulant MDS matrix. Rotating the rows of all three
  selectors simultaneously preserves all layer weights.

The canonical form of a triple is the lexicographic minimum, over
`rho` in `Z_4`, of the triple obtained by rotating all three tuples by `rho` and
then translating each tuple independently so its first offset is 0. The
canonical class count is an **outcome**, not an assumption; the harness must
recompute it, must confirm the recomputed value against the disclosed 27,648,
and must verify empirically on a frozen sample that orbit members share a
minimum.

## X1.4 Three independent oracles and complete coverage

X1 must establish every graded minimum through **three separately implemented
oracles**, plus an independent witness checker:

1. **Exact SMT.** `z3` over `QF_LIA`-shaped pseudo-Boolean constraints, invoked
   as an external process. `unsat` at budget `B` proves the minimum exceeds `B`.
   The SMT arm is authoritative for the lower-bound direction.
2. **Exact ILP.** HiGHS through `scipy.optimize.milp` with all-binary
   variables, returning the exact minimum and an optimal witness.
3. **Pure-Python exhaustive branch and bound.** Independent of both solvers,
   using the sound pruning `cost >= 5(k_1 + k_3)` obtained by summing the
   per-column MDS constraints at the first and third boundaries. Applied to the
   frozen anchor and control cases, where its cost is affordable.
4. **Independent witness checker.** A pure-Python exact re-verification of every
   solver witness against the MDS constraints and the claimed weight. It must
   reject a witness with any single active byte removed.

Disagreement between any two oracles on a shared case is a **validity
failure** that forbids receipt emission.

Coverage is complete, with no sampling in the graded result:

- all 384 fixed-repeated triples `(w, w, w)`;
- every canonical triple class over the ordered catalog, each graded by SMT
  `unsat` at budget 24 and by an exact ILP minimum with an independently
  verified witness;
- the X0-safe subfamily, defined by `S(w_1)+S(w_2) = Z_8` and
  `S(w_2)+S(w_3) = Z_8`, and its non-safe complement, graded and reported
  separately so the comparison is visible.

## X1.5 Frozen diagnostics

Diagnostics are outcomes, not thresholds. The receipt must record the exact
minimum histogram over all canonical classes; the separate minima over the
X0-safe subfamily and its complement; the class counts of each; the
lexicographically first class attaining the global minimum; the per-layer
weight profile of its verified witness; the exact minimum for the fixed
Rijndael tuple and for the X0 fallback alternation; the recomputed canonical
class count with its orbit-size histogram; and the single-trail arithmetic
implied by the bound, labelled as arithmetic on the bound rather than as new
evidence.

## X1.6 Frozen controls and validity

Every control must be detected through the same loaders, oracles, canonical
quotient, or witness checker that produce the main result:

1. MixColumns branch number forced to 4;
2. all row offsets zero within every tuple;
3. a repeated offset inside one tuple;
4. the nonzero-first-layer requirement omitted;
5. the reverse ShiftRows direction substituted on a case where it differs;
6. three S-box layers instead of four;
7. five S-box layers instead of four;
8. a stale catalog digest;
9. two catalog entries reordered;
10. one tuple element mutated;
11. a duplicated tuple offset;
12. an out-of-range tuple offset;
13. one active byte removed from a verified witness;
14. a witness weight forged below its verified weight;
15. one column's MDS constraint omitted;
16. an injected SMT/ILP disagreement;
17. a non-certified support admitted into the catalog;
18. an orbit member assigned a different minimum;
19. a canonical class count mismatch;
20. one class filtered out of the canonical corpus;
21. XOR substituted for modular addition in the safe-adjacency oracle;
22. the budget shifted by one so `unsat` is asserted at the achieved minimum;
23. a fabricated exhaustive-search minimum below the SMT and ILP value.

A minimum **below** 25 for any class is a valid adverse outcome and would
refute the inherited fixed-selector bound under switching. A minimum **above**
25 is likewise a valid graded outcome. Missing a required oracle agreement,
control detection, or coverage count is a validity failure.

## X1.7 Receipt, verdicts, and non-claims

The receipt schema is `E256-X1-MIXED-WALK-ACTIVITY-GATE-1`, status
`OPEN_PROGRESS`, at `logs/e256-x1-mixed-walk-activity-gate.json`. The scratch
directory is `build/e256-x1-mixed-walk-activity/`. The only Make entry points
are `make e256-x1-mixed-walk-activity` and
`make e256-x1-mixed-walk-activity-check`. The deterministic payload sections,
in addition to `schema` and `status`, are exactly `integrity`, `catalog`,
`activity_model`, `symmetry_quotient`, `oracle_agreement`, `coverage`,
`safe_subfamily`, `diagnostics`, `controls`, `verdicts`, and `non_claims`. The
payload digest is SHA-256 of canonical compact sorted-key JSON. The
complete-record hash is computed with `record_sha256` set to null. `--check`
must regenerate and compare byte-identical deterministic payload bytes and
digest.

Solver models are **excluded** from the deterministic payload because they are
tool-version dependent. Only verdicts, exact minima, recomputed counts, and
digests over those deterministic streams enter the digest. Solver versions are
recorded as advisory environment data outside the digest, because a verdict is
reproducible where a model is not.

A valid receipt reports
`MIXED_WALK_FOUR_ROUND_ACTIVITY_LOWER_BOUND_CERTIFIED` once oracle agreement,
complete coverage, and all controls pass.

This is a structural lower bound on active S-box count in a truncated
relaxation. It is **not** a differential or linear probability bound beyond the
arithmetic already printed by E256-062, **not** trail clustering, **not**
integral, algebraic, cube, meet-in-the-middle, impossible-differential,
rebound, slide, invariant-subspace, related-key, related-tweak, multi-user, or
TMTO analysis, and **not** a statement that any minimising activity pattern is
realisable by actual differences. It selects no round count, schedule, evolution
policy, key or XOF derivation, architecture, storage organisation, RTL
enforcement mechanism, Metal or FHE path, physical FPGA target, suite,
protocol, security level, or standard. It is pure host analysis: not RTL, not
Yosys, not vendor place and route, not Metal, not encrypted execution, and not a
self-modifying cipher. A bound that survives switching is not evidence that
switching is beneficial. Standard reviewed AEAD remains mandatory for real
data. E256-063 remains OPEN. No C/H/N row, claim epoch, site assertion,
campaign record, or video voiceover moves merely because X1 executes.
<!-- E256-X1-MIXED-WALK-ACTIVITY-CONTRACT-END -->

**X1 preregistration freeze.** The machine-readable preregistration was written
after the inclusive marker above and before any X1 runner, receipt, or scratch
artifact. Its raw-file SHA-256 is
`e80e9c11005db16924ad54e4a1bf5bef365af241ee5e23d189c40b9d59fa3041`; the
immutable inclusive marker SHA-256 it pins is
`c0f951f08ced7e7897a8fb1e1770b823ec62127f94c96fb2afac755e366a1716`. At that
point `Scripts/e256_x1_mixed_walk_activity_gate.py`,
`logs/e256-x1-mixed-walk-activity-gate.json`, and
`build/e256-x1-mixed-walk-activity/` were verified absent.
