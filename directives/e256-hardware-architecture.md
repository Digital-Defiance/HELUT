# E256-H — hardware-first Enigma-rotor architecture record

<!-- E256-H-CONTRACT-START -->

Design status: **H0–H10 proposed as research constraints; primitive shape,
round count, fabric target, and mode remain OPEN**.
Evidence status: **no hardware receipt exists on this record**. Every gate/LUT
figure below is a first-order hand estimate, explicitly *not* synthesis output.
Implementation authorization: **AUTHORIZED for preregistered cost-estimation,
structural, ablation, and attack-harness research only**. Production RTL, a
cipher suite, profile, fixture, protocol deployment, promotion, or claim change
remains **blocked**.

Audit row: **E256-063**. Ledger: `directives/e256-audit.md`.
Predecessor records: `directives/e256-vnext-topology.md` (byte-local, rejected),
`directives/e256-wide-architecture.md` (wide state, structurally retained).
Predecessor receipt: `logs/e256-wide-state-gate.json`, deterministic payload
`21758ce220b9da469a18ea617fa7b2fd41e906add69a258f830b12843e3e495b`.

No C/H/N row moves on this file. E256 remains an experimental cryptographic
laboratory and must not protect real data. A reviewed standard AEAD remains the
real-data security boundary.

## 0. Why hardware becomes the primary design axis

The wide-state fork (**E256-062**) certified what it set out to certify: 69/69
nonzero MixColumns minors, branch number 5, structural all-to-all byte
dependency at round 3, a 25-active-rotor four-round certificate, 7/7 planted
controls detected, and 13,824/13,824 round trips. Verdict:
`STRUCTURAL_WIDE_STATE_CANDIDATE_RETAINED_FOR_ATTACK_ONLY`.

That receipt also exposed why structural certificates alone cannot drive this
design forward. Three specific reasons:

1. **Structural bounds cannot rank candidates.** They are pass/fail. The
   `fixed_aes_spn` baseline in the same receipt reaches the *identical* 69
   minors, branch number 5, round-3 dependency, and 25-active bound with no
   keyed rotor namespace at all. A pass/fail gate can never explain why the
   expensive construction should exist. A measured cost axis can.
2. **The frozen cost convention is not hardware cost.** It counts 32 rotor
   evaluations, 64 non-unit GF(2^8) multiplications, 96 MixColumns XORs, and 32
   mask XORs per round. Those abstract operations hide the fact that the keyed
   parts, not the counted parts, dominate area.
3. **Cryptanalysis is the project's actual competence.** HELUT already has a
   netlist/LUT lane (`Apps/Mulein/rtl/`, yosys LUT6 mapping) and a Metal
   compilation lane. If the round function is a netlist, then the honest
   implementation and the attack engine are *the same artifact* instantiated at
   different widths. Attack cost then becomes measurable in LUTs and cycles
   instead of asserted in prose.

### 0.1 The cost estimate that motivates the pivot

Hand estimate, stated as an estimate, for the E256-062 round function:

| Component | Estimated cost | Note |
|---|---|---|
| ShiftRows (0,1,3,4) | ~0 GE | fixed byte permutation; wiring only |
| MixColumns, 8 columns | ~880 XOR2, ~2k GE | unmodified AES matrix; depth 3–4 |
| Mask XOR | 256 XOR2 | trivial |
| AES S-box core, per lane | ~80 GE | Canright tower-field class, tableless |
| **Keyed 8×8 GF(2) wrappers, per lane** | **~435 GE** | two programmable matvecs, 64 AND2 + 56 XOR2 each |
| **Live rotor parameters, per round** | **4608 bits ≈ 23k GE as flops** | 32 lanes × 18 bytes |

Two conclusions follow, and both are uncomfortable for the current shape:

- The **keyed wrapper costs roughly 3–5× the nonlinear core it wraps**. The
  keying is more expensive than the cryptography.
- **Parameter storage dominates the entire datapath.** Holding one round of
  independently selected rotor material costs more than the substitution and
  diffusion layers combined.

Set against a comparator with provably identical structural bounds, that is not
a defensible default. It is a research arm that has not earned its area.

### 0.2 The schedule as modeled is unbuildable

The E256-062 model KDF issues one HMAC-SHA512 per derivation. Per 32-byte block
that is 384 selection bytes plus 13 masks — about **397 HMAC invocations, near
800 SHA-512 compressions, to produce 256 bits**. The preregistration correctly
labels this model-only, and `directives/e256-wide-architecture.md` §4 leaves the
production PRF/XOF OPEN. Hardware-first turns that OPEN item into a blocking one:
a schedule whose cost is unbounded per block cannot be evolved or measured.

One favorable property survives and must be preserved: rotor material derives
from `'E256-W/gate/rotor/v1' || u8(id)` with **no context**, so the namespace is
a key-setup cost, never a traffic cost.

## 1. Proposed research constraints

| ID | Decision | Rationale and consequence |
|---|---|---|
| **H0 — measured cost is a gate** | Every candidate carries a synthesis receipt: LUT6 or GE, logic depth, and register bits. Abstract operation counts are advisory only. | Without a measured axis, "more efficient" is unfalsifiable. AEAD-only and fixed-AES-SPN remain mandatory baselines. |
| **H1 — netlist-only primitives** | The nonlinear layer is a combinational netlist (tower-field / depth-optimized class). No table, ROM, or SRAM in the datapath, and **no secret-indexed memory anywhere**. | Gives constant latency by construction, satisfies the tableless requirement in the strong sense, and makes the honest core and the attack core the same netlist. |
| **H2 — bounded keyed state** | Live per-round keyed material and full-namespace parameter storage both carry explicit byte budgets. Rotor parameters stay per-key, never per-block. | Parameter storage, not logic, is what actually blocks a small implementation. |
| **H3 — rotor keying demoted to offsets** | Default rotor is a fixed certified S-box conjugated by keyed XOR offsets: `R_p(x) = S(x XOR p_in) XOR p_out`. Full keyed 8×8 GF(2) affine wrappers become an OPEN arm that must beat this on measured cost per certified bound. | Costs ~11 GE instead of ~435 GE per lane, stores 2 bytes instead of 18, and **preserves exact DDT 4 / \|LAT\| 32 / degree 7** because XOR-conjugation is affine equivalence. This is also the faithful reading of a rotor: fixed wiring entered at a keyed *position*. |
| **H4 — stepping moves into the wiring** | Keyed row offsets and/or lane permutation drawn from a small offline-certified set, rather than a keyed substitution alphabet. | A byte crossbar is nearly free in hardware, and moving the wiring is what Enigma stepping actually did. Every set member must re-certify branch number 5 and round-3 dependency before use. |
| **H5 — permutation-based bounded schedule** | Retire per-derivation HMAC-SHA512. Derive the complete round-material block in one XOF squeeze (the frozen material block is 800 bytes ≈ 6 Keccak-f[1600] at SHAKE-256 rate), per-message granularity by default, with a stated bound on permutation calls per block. | Turns an unbounded schedule into a single small core that is frequently already present on the target device. |
| **H6 — prefer an encrypt-only datapath** | Choose a mode of use that never instantiates the inverse. If duplex is required, report its area separately. | Deletes the inverse S-box, inverted key-dependent matrices, and InvMixColumns (classically ~2× forward). This makes "mode of use" a hardware decision, not only a protocol one. |
| **H7 — masking cost is a design input** | Prefer keying that stays linear in one secret. Disfavor bilinear (secret matrix × secret data) keying. No side-channel claim without TVLA evidence. | `parity(row AND x)` is bilinear in two secrets, and masking a product of two secrets is materially harder than masking a linear function of one. H3 removes that problem as a side effect. |
| **H8 — attacks must run in hardware** | Every attack arm gets a synthesizable or Metal form, with planted weak-key and reduced-round positive controls that the hardware search must actually recover before any negative result is reportable. | This is the "crackable in hardware" requirement. Attack cost is reported in LUTs, cycles, and energy. A search that cannot recover a planted break has graded nothing. |
| **H9 — evolution is hardware fitness at fixed bounds** | Candidates may differ only in ways that preserve the certified structural bounds; ranking is by measured cost and depth. Deterministic, immutable, preregistered, control-calibrated, holdout-graded, human-promoted. Deployed mutation forbidden. | Makes "evolve and improve" a real optimization problem with a legal search space, inheriting the W11 evolution contract. |
| **H10 — boundary unchanged** | Reviewed standard AEAD remains the external boundary and AEAD-only remains a valid final outcome. No security-bit value is computed. | Hardware efficiency is not a security argument. |

## 2. Rejected alternatives

- **Keep per-lane programmable affine wrappers as the default.** Estimated
  ~3–5× the S-box area plus ~23k GE of live parameter registers, against a
  comparator with identical certified bounds. Demoted to an OPEN arm, not
  deleted — it may return with measured evidence.
- **Table- or SRAM-backed rotors.** Reintroduces secret-indexed memory that
  **H1** exists to forbid, and the frozen forward+inverse cache is 131,072 bytes
  versus ~4,608 bytes of algebraic parameters.
- **Additive (mod 256) rotor offsets.** Historically the most faithful to ring
  stepping, and cheap. Rejected as default because additive conjugation does
  *not* preserve the XOR-difference DDT, which forfeits the key-independent
  trail bound that is currently E256's only real certificate. Retained as an
  OPEN research arm precisely because it creates genuine analysis work.
- **Small keyed 8-bit SPN rotors built from 4-bit S-boxes.** LUT-native and very
  cheap. Rejected as default because it forfeits exact key-independent DDT 4,
  \|LAT\| 32, and degree 7.
- **Replacing the AES MDS layer to save area.** Rejected. It is already the
  cheapest part of the design and it carries the branch-number-5 certificate.
- **A bespoke AEAD mode or framing.** Rejected, unchanged from prior records.
- **Treating a failed in-house hardware attack as security evidence.** Rejected
  explicitly; see §4.

## 3. Choices deliberately left OPEN

1. **Round count.** Unchanged from W10: evidence-driven, not selected here.
2. **Fabric target** for the primary cost metric: LUT6 FPGA, ASIC GE, or Metal
   throughput. The three do not rank candidates identically.
3. **Exact XOF** and its per-block permutation-call budget.
4. **Mode of use**, which determines whether the inverse datapath exists at all.
5. **Whether a keyed rotor namespace ever earns its measured area** over keyed
   offsets around a fixed certified S-box. Currently unproven in both directions.
6. **Whether the nonlinear core stays the AES S-box** or moves to a cheaper
   8-bit S-box with an equally certified spectrum.
7. **State width beyond 256 bits.**

## 4. Non-claims

- **A bounded hardware attack that finds no break is not a security result.** It
  grades our search, not the cipher. This is the single most important limit on
  this record, because a hardware cracker is seductive evidence of the wrong kind.
- **Cheaper is not stronger.** Any cost win that forfeits the MDS, branch-number,
  DDT/LAT, degree, or dependency certificates is a regression, not an improvement,
  regardless of what it synthesizes to.
- Every figure in §0.1 and §0.2 is a **hand estimate**, not synthesis output. No
  LUT6 count, GE figure, timing closure, power number, TVLA trace, or fault
  campaign exists for any E256 variant.
- No IND-CPA, IND-CCA, AEAD, PRP, PRF, or standalone-cipher security is claimed.
- No security-bit value is computed or implied. "E256" denotes the 256-symbol
  alphabet and the 256-bit state, never 256-bit security.
- Constant latency from **H1** is not side-channel resistance. Power and EM
  leakage remain unmeasured.
- Nothing here is production-ready, no RTL is authorized, and no claim row,
  suite, profile, fixture, or release gate moves on this record.
<!-- E256-H-CONTRACT-END -->

## 4.1 Post-contract evidence-status correction

The marker-bounded block above is the frozen **pre-execution** contract whose
SHA-256 remains
`b64472f73be9d0fc6318ff445c5f550cb0129309313228f416599c27d3957bb1`.
It is preserved as chronology, not current evidence status. Sections 6--9 and
their receipts supersede three statements inside that block:

- hardware receipts and generic yosys/ABC LUT6 measurements now exist; only the
  figures in §§0.1--0.2 remain hand estimates;
- the assertion that parameter storage dominates logic was a hypothesis, not a
  measurement. H2 integrated logic, registers, selectors, and storage remained
  unmeasured through the attack receipt, and no dominance conclusion follows;
- separately stored H3 XOR offsets were cheaper than affine wrappers in the
  marginal lane experiment, but the later exact-collapse gate proves they are
  algebraically redundant in the lean fixed-round representation.

Material byte counts also name different schedules. The predecessor E256-W
layout is 384 rotor-selection bytes plus 416 masks (**800 bytes / six
SHAKE-256 rate blocks**). Raw H3 attack material is 768 offset bytes plus 416
masks (**1,184 bytes / nine blocks**). Collapsing those already-derived raw H3
bytes gives either a prefix-compatible 800-byte representation or, for fixed
`R=12`, a 416-byte effective-mask representation. Neither shorter form
retroactively changes the frozen nine-block derivation; squeezing it directly
would define a new schedule/domain.

## 5. Proposed execution order

This section is outside the contract block and may be revised without a refreeze.

1. **Cost-estimation receipt first.** Preregister and measure a single lane four
   ways through the existing yosys LUT6 flow: fixed AES S-box, keyed-offset
   rotor (**H3**), programmable-affine rotor (E256-062 shape), and a table-backed
   rotor. This is the smallest experiment that can settle §3 item 5 with data
   rather than the §0.1 estimate.
2. **Schedule budget receipt.** Measure the XOF squeeze cost for the 800-byte
   material block and state the per-block permutation-call bound (**H5**).
3. **Re-certify the H3/H4 candidate structurally**, reusing the E256-062 gate's
   MDS/dependency/trail machinery so the certificate is inherited, not restated.
4. **Then, and only then**, the hardware attack lane (**H8**) with planted
   reduced-round and weak-key positives that the search must recover.

Steps 1–3 must land before any round count, efficiency claim, or comparison
against fixed-AES-SPN is written down.

## 6. Step 1 result — measured rotor-lane keying cost (OPEN)

Step 1 has landed. Preregistration
`directives/e256-hardware-cost-preregistration.json`
(`cbaa5b02ca71824866d857edda838d97ceca0816bed5f5af334d8625db336e27`), runner
`Scripts/e256_hardware_cost_gate.py`, receipt
`logs/e256-hardware-cost-gate.json` (`E256-HARDWARE-COST-GATE-1`, deterministic
payload `a10e001ad2c2b3de55fcc80197c059f166d5e55599c670e20b01de8f6b7d323d`).
Reproduce with `make e256-hw-cost-check`. Toolchain: yosys 0.68+post, Icarus
Verilog 13.0. **These are measurements, and they supersede the §0.1 estimates.**

Marginal keying cost for one byte lane, hierarchy preserved so the shared S-box
is never re-optimized against the wrapper. All seven lanes passed exhaustive
functional verification, 1792/1792 checks:

| Lane | Keying LUT6 | Depth | Keyed bits |
|---|---|---|---|
| `identity` (control) | 0 | 0 | 0 |
| `xor_only` (control) | 8 | 1 | 8 |
| `fixed` (baseline) | 0 | 1 | 0 |
| **`offset` (H3 candidate)** | **16** | **3** | 16 |
| `offset_alt` (stability control) | 16 | 3 | 16 |
| **`affine` (E256-062 incumbent)** | **64** | **5** | 144 |
| `table` (H1 violation) | 700 | 5 | 2048 |

Shared AES S-box: 49 LUT6, constant across every S-box-bearing lane.

Verdict `H3_OFFSET_KEYING_SUPPORTED`. All eight preregistered predictions passed:

- **H3 is supported on cost.** Offset keying is 16 LUT6 against 64 for
  programmable affine — exactly **4.0×** less area and **two fewer logic
  levels** — while preserving DDT 4, \|LAT\| 32, and degree 7 by affine
  equivalence. The cheaper option is also the one with the intact certificate.
- **H1 is supported.** The identical rotor function as a runtime lookup costs
  700 LUT6: **43.75×** the offset lane's keying and **14.3×** the entire shared
  S-box netlist. Secret-table rotors are not a cheap shortcut in logic.

### 6.1 Two corrections to §0.1

Recorded because the estimates were wrong in magnitude and the receipt should
say so:

1. The hand estimate put programmable-affine wrappers at **3–5× the S-box**. On
   a 6-LUT fabric the measured ratio is **64 : 49, about 1.3×**. The direction
   was right — the keying is comparable to the nonlinearity it wraps — but the
   magnitude was overstated. GE ratios do not transfer to LUT6.
2. A first methodology was **rejected by its own control**. Measuring
   whole-module LUT6 after `flatten` let ABC re-synthesize across the S-box
   boundary, which reported `offset` at 158 and the logically identical
   `offset_alt` at 187 LUT6, and absurdly made `affine` (135) look cheaper than
   `offset` (158). Prediction P3 caught it, the harness refused to emit, and the
   preregistration was refrozen with `flatten` prohibited and the P4/P6
   thresholds carried over verbatim. `flatten` remains forbidden in this lane.

### 6.2 What step 1 does not settle

- Nothing about **H2**: full-round logic, effective-mask registers, H4
  selectors, and integrated storage were not measured by this one-lane gate, so
  it supports no storage-versus-logic ranking.
- Nothing about ASIC area, Fmax, power, energy, TVLA, EM, or fault behavior.
- Nothing about security. A 4× cheaper keying scheme is not a stronger one, and
  no structural certificate moved.

## 7. Steps 2–3 result — candidate re-certification and schedule budget (OPEN)

Preregistration `directives/e256-hardware-candidate-preregistration.json`
(`2d0ecbbbb18165aa09adbe33c3d85a7d6d72db3881925bc6b11da07ca2243099`), runner
`Scripts/e256_hardware_candidate_gate.py`, receipt
`logs/e256-hardware-candidate-gate.json` (`E256-HARDWARE-CANDIDATE-GATE-1`,
deterministic payload
`98af83ec27093787552475fce588f84a902634afcc969bed26462032dddec3cc`). Reproduce
with `make e256-hw-candidate-check`. Verdict
`H3_H4_CANDIDATE_STRUCTURALLY_RECERTIFIED`, 5/5 controls detected, all eight
preregistered predictions passed.

An exploratory probe preceded the freeze, so predictions were stated
qualitatively and every exact count below is a measured output rather than a
preregistered number. That disclosure is recorded in the preregistration.

### 7.1 H3 certified exhaustively, not sampled

`R(x) = SBOX(x XOR p_in) XOR p_out` was certified over the **complete offset
space**, which is a stronger result than E256-062 obtained for the programmable
affine family:

- Differential uniformity 4, maximum \|LAT\| 32, and forward and inverse
  algebraic degree 7 for **all 256** values of `p_in`, with **zero** mismatches.
- Bijective for **all 65,536** ordered `(p_in, p_out)` pairs, with zero failures.
- `p_out` cannot affect the spectrum: it cancels in every difference, contributes
  only a sign in every correlation, and cannot change degree.

E256-062 sampled 1,024 rotor tables. H3's offset space is small enough to
certify completely, which is itself an argument for the cheaper scheme.

### 7.2 H4 needs a certified set — distinctness is not sufficient

Of the **1,680** ordered 4-tuples of pairwise distinct row offsets, only **384**
discharge every inherited obligation. The earliest all-to-all dependency
histogram is round 3 for 384 tuples, round 4 for 1,248, and **never within 12
rounds for 48**. Rijndael's `(0,1,3,4)` is in the certified 384.

The 48 failures have an exact characterization, verified separately against the
measured histogram: they are precisely the tuples whose four offsets all share
one parity class. Their pairwise differences then generate only the index-2
subgroup of Z_8, so the eight columns split into two orbits that never mix.
Both `(0,2,4,6)` and `(1,3,5,7)` and all their orderings are in this set —
24 + 24 = 48, matching the measurement exactly.

This is a correction to a natural assumption. The E256-062 certificate required
distinct offsets, and distinctness is necessary but **not** sufficient. A keyed
wiring selection must draw from the certified 384, never from the 1,680.

### 7.3 H5 schedule budget

Per 32-byte block, for the frozen 800-byte round-material block:

| Schedule | Primitive invocations per block |
|---|---|
| E256-062 model, HMAC-SHA512 per derivation | 397 HMAC calls ≈ **1,985 SHA-512 compressions** |
| Candidate, one SHAKE-256 squeeze | **6 Keccak-f[1600] permutations** |

A ratio of **330.83×**, and the earlier §0.2 figure of ~800 compressions was an
undercount; exact accounting gives 1,985. This is arithmetic invocation counting
plus a squeeze-length check, not throughput or area, and no production XOF is
selected.

### 7.4 What steps 2–3 do not settle

- **H2 remains the open integrated-cost question.** Full-round logic,
  effective-mask registers, H4 selectors, and storage organization are still
  unmeasured; the earlier storage-dominance statement was a hand hypothesis,
  not a result.
- No round count, production XOF, or production wiring selection is chosen.
- How keyed offsets are selected, and what that selection leaks, is untouched.
- Exhaustive spectral invariance is a statement about one 8-bit rotor, not about
  the 256-bit permutation.
- The fixed-AES comparator still holds the same structural bounds, so no
  rotor-namespace security advantage is established here either.

## 8. Step 4 result — hardware attack lane (OPEN)

Preregistration `directives/e256-hardware-attack-preregistration.json`
(`15bb0b68d1f0ebb521497d4d06cc4250cf608b3a71e1f0719f3e0a7b2017fde3`), RTL
`Hardware/RTL/Research/E256H/e256h_attack_core.v`, runner
`Scripts/e256_hardware_attack_gate.py`, receipt
`logs/e256-hardware-attack-gate.json` (`E256-HARDWARE-ATTACK-GATE-1`,
deterministic payload
`1114e260455232a2979f8a4f613fc6d6daf4be4f97c3ca6903c3f639357d7a2d`). Reproduce
with `make e256-hw-attack-check`. Verdict
`HARDWARE_ATTACK_LANE_CALIBRATED_REDUCED_ROUND_DISTINGUISHER_FOUND`.

**This grades the search, not the cipher.** That framing is load-bearing here and
is printed in the receipt.

### 8.1 The lane is calibrated

Two arms share one synthesizable round datapath, with defects injected through
the same netlist by a `defect` port rather than by a reimplementation:

- `identity_rotor` planted defect: recovered by the integral arm at **every**
  tested round count (balance survives all 8 rounds, as an affine map must).
- `no_diffusion` planted defect: recovered by the truncated-differential arm at
  **every** tested round count (exactly 1 active output byte, all 8 rounds).
- **48/48** RTL values matched an independent software model bit-exactly across
  all three defect modes and all eight round counts. Without that the lane would
  be attacking a different function than the one specified.

### 8.2 What the lane found against the candidate

| Rounds | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|
| Integral balanced bytes (of 32) | 32 | 32 | 32 | 0 | 0 | 0 | 0 | 0 |
| Truncated active bytes (of 32) | 4 | 16 | 32 | 32 | 32 | 32 | 32 | 32 |

- **A 3-round integral distinguisher exists and dies at round 4.** This is the
  first actual attack result on E256-H. It is expected for an AES-like SPN, it is
  not a break of the construction, and it bounds any future round count from
  below. No round count is selected here.
- The truncated-differential arm reaches all 32 bytes at **round 3**,
  independently reproducing the E256-062 structural dependency certificate by
  dynamic measurement rather than static analysis. Static and dynamic agree.

### 8.3 Measured attack cost

Hierarchy was preserved, so the receipt's module fields are **local** counts:

| Module | Local LUT6 | Local cells | Depth |
|---|---|---|---|
| `e256h_atk_round` (one round datapath) | 1,381 | 1,381 | 5 |
| `e256h_atk_single` (one-block evaluator) | 3,496 | 4,014 | 5 |
| `e256h_atk_integral` (full engine) | 4,007 | 4,542 | 13 |

The shared S-box child maps to 49 local LUT6. `e256h_atk_round` instantiates 32
such children, so its S-box bank contributes `32 * 49 = 1,568` LUT6 outside the
reported 1,381 local LUT6. A simple hierarchy-expanded arithmetic estimate for
one round is therefore **approximately 2,949 LUT6**. The local non-child logic
is about 46.8% of that estimate, not a small residual; moreover, the receipt
does not decompose it into diffusion, input/output keying, final-mask XOR, and
defect-mux costs. The earlier statement that diffusion and keying are a small
fraction of a round is unsupported and is withdrawn. This is generic
yosys/ABC mapping, not a flattened globally optimized result or vendor
place-and-route. No recursive totals are inferred for the single or integral
engines.

Measured integral cycles for the candidate run from 770 at 1 round to 2,563 at
8 rounds, approximately `256*(R+2)`. Only `e256h_atk_round` is a clean datapath
figure; the two engines expose wide flat material ports because this is a
research harness, inflating their local mapped cost. None of these modules
measures the integrated effective-mask registers, H4 selector material, or
storage organization, so no storage-versus-logic dominance conclusion follows.

### 8.4 What step 4 does not settle

- Two arms are not the attack matrix. Differential clustering, impossible
  differentials, algebraic and degree growth, meet-in-the-middle, rebound, slide,
  invariant subspace, related-key and related-tweak, multi-user, reset/reuse, and
  TMTO are all untested.
- One active lane, one input difference, one material set, no key recovery.
- **H2 integrated logic, register, selector, and storage cost remains open and
  unmeasured.**
- A calibrated search that had found nothing would still not be a security
  result. Finding the 3-round distinguisher is the useful output.

## 9. Pre-execution decision record — H3 XOR-offset collapse

This section is outside the marker-bounded H0–H10 contract. It records the
design decision **before** the confirmatory gate or any collapsed-schedule RTL
is implemented. The algebraic identity was derived during inspection, so the
next gate is confirmatory rather than a prospective discovery; that disclosure
must remain in its preregistration and receipt.

Write the frozen H3/H4 round for round index `r` as

```text
X_0     = P XOR M_0
X_{r+1} = L_{w_r}(S^32(X_r XOR A_r) XOR B_r) XOR M_{r+1}
```

where `A_r` and `B_r` are the 32-byte `p_in` and `p_out` vectors and
`L_{w_r}` is the complete forward H4 linear layer (RowShift for wiring `w_r`,
then MixColumns). Because `L` is GF(2)-linear,

```text
L(S^32(x XOR A) XOR B) XOR M
  = L(S^32(x XOR A)) XOR L(B) XOR M.
```

Two normal forms follow.

1. **Prefix-compatible output-offset collapse.** Keep `A_r`, set every `B_r` to
   zero, and use `M'_0 = M_0`, `M'_{r+1} = M_{r+1} XOR L_{w_r}(B_r)`. One
   transformed schedule then preserves every round prefix. At 12 rounds this
   reduces live effective material from 1,184 to 800 bytes: 384 input-offset
   bytes plus 416 transformed mask bytes. This 800-byte layout is not the older
   E256-W rotor-ID layout even though the byte count is the same.
2. **Full fixed-round collapse.** For a fixed round count `R`, set both offset
   families to zero and define effective masks

   ```text
   K_0 = M_0 XOR A_0
   K_r = L_{w_{r-1}}(B_{r-1}) XOR M_r XOR A_r,  1 <= r < R
   K_R = L_{w_{R-1}}(B_{R-1}) XOR M_R.
   ```

   The resulting fixed-S-box key-alternating SPN is byte-for-byte the same
   permutation. It needs `(R+1)*32` effective-mask bytes: 416 at `R=12` and 288
   at `R=8`. A separate terminal key is required for each tested prefix; adding
   `A_R` to `K_R` is an off-by-one defect.

### 9.1 Decision if the confirmatory gate passes

- Separately stored H3 XOR offsets are **deleted from the lean candidate**, not
  credited as a distinct rotor namespace or security feature. The measured H3
  lane receipt remains valid historical cost evidence for the representation it
  measured, but it does not justify retaining algebraically redundant state.
- The lean baseline becomes a fixed certified AES S-box bank, effective round
  masks, AES MixColumns, and H4 certified moving wiring. The Enigma mechanism is
  H4 stepping; whether a small non-absorbable rotor-position family earns area
  is a separate OPEN bakeoff against this baseline.
- H4 does not collapse. The exact `L_{w_r}` used in each round must transport the
  preceding output offset. The current RTL covers only the fixed certified tuple
  `(0,1,3,4)`; the 384-member certificate covers repeated use of each member and
  does not authorize arbitrary per-round switching sequences.
- Collapsing already-derived 1,184-byte material reduces live storage but does
  **not** retroactively reduce the frozen attack fixture's nine SHAKE-256 squeeze
  blocks. Directly deriving 800 or 416 bytes under a shorter stream is a new
  schedule/domain and requires a separate freeze and new attack evidence.

### 9.2 Confirmatory gate contract

The gate must fail closed and refuse a canonical receipt unless all of the
following hold:

1. independent software implementations agree for Stage A and fixed-`R` Stage B
   over all 384 certified H4 tuples, rounds 1 through 12, the frozen attack
   material, additional deterministic material sets, and a deterministic block
   corpus;
2. a sequencing RTL comparison agrees for rounds 1 through 8 on the unchanged
   frozen attack datapath, with zero offsets and separately derived terminal
   effective masks on the canonical side;
3. a compositional one-round proof discharges the same arbitrary-input identity without
   asking SAT to re-encode duplicate S-box banks: both forms feed the identical
   nonlinear-boundary value `U = S^32(state XOR A)`, then a Yosys SAT miter proves
   `L(U XOR B) XOR M = L(U) XOR L(B) XOR M` for arbitrary 256-bit `U`, `B`,
   and `M` under `(0,1,3,4)`; the unchanged dual-core sequencing comparison ties
   that lemma back to the frozen RTL;
4. planted wrong-transport, omitted-transport, terminal-key, and mask-index
   mutations are detected; and
5. an independently defined bit-permutation-conjugated S-box control is rejected
   by an exhaustive XOR-translation-family detector, proving the detector does
   not label every keyed 8-bit permutation as absorbable.

A passing receipt establishes an exact material normal form only. It proves no
security property, chooses no round count, XOF, wiring schedule, mode, profile,
or production RTL, moves no C/H/N row, and leaves reviewed AEAD as the real-data
boundary.

### 9.3 Confirmatory result — exact H3 collapse (OPEN)

The gate passed. Preregistration
`directives/e256-hardware-offset-collapse-preregistration.json` froze at SHA-256
`3d7a12731fcf81f6120577122c55bd8ec25589a82226d49fab7e5b8350ee0cee`.
Receipt `logs/e256-hardware-offset-collapse-gate.json`
(`E256-HARDWARE-OFFSET-COLLAPSE-GATE-1`, `OPEN_PROGRESS`) has deterministic
payload SHA-256
`1478a0ba317bce5f33cb053744b050bb6188543405c1dfacf52d8aaf920c4b71`.
Reproduce with `make e256-hw-offset-collapse-check`; the banked check reports
`prior_digest_valid=True`, `payload_bytes_match=True`, `digest_match=True`, and
`CHECK PASS`.

Machine verdict:
`H3_XOR_OFFSETS_EXACTLY_COLLAPSE_TO_EFFECTIVE_MASKS`.

- **Software:** all 384 certified H4 tuples, each repeated across rounds; three
  deterministic 1,184-byte material sets; rounds 1--12; and eight blocks.
  Stage A passed **110,592/110,592** and fixed-R Stage B passed
  **110,592/110,592**, with zero mismatches (**221,184** total). Every Stage-B
  prefix used a separately derived terminal key.
- **Sequential RTL:** unchanged dual `e256h_atk_single` instances under fixed
  certified tuple `(0,1,3,4)` passed **64/64** original-versus-canonical
  comparisons for rounds 1--8 and eight blocks. Both sides also passed all
  **128** comparisons against the independent software model.
- **Formal:** this is a compositional one-round linear proof, not a monolithic
  duplicate-S-box proof. Both forms share
  `U=SBOX^32(state XOR A)`; Yosys SAT proves
  `L(U XOR B) XOR M = L(U) XOR L(B) XOR M` for arbitrary 256-bit `U`, `B`, and
  `M`. The 768-input-bit correct cone is UNSAT for mismatch. All three formal
  mutations are SAT with normalized witnesses; `wrong_transport_source` has
  1,024 arbitrary input bits including `A`. No S-box logic is in the SAT cone.
- **Controls:** all 6/6 were detected: omitted transport, raw rather than
  transported output offset, wrong transport source, terminal `A_R` inclusion
  (every `R=1...11`; `R=12` is inapplicable because no `A_12` exists), wrong
  mask index (**96/96** mismatches), and the non-absorbable bit-permutation
  family (**65,536** exhaustive comparisons, zero matching XOR translations).
  All six preregistered predictions passed.

The material accounting is now:

| Representation | Contents | Live bytes / frozen squeeze accounting |
|---|---|---|
| E256-W predecessor | 384 one-byte rotor IDs + 416 masks | 800 bytes / 6 SHAKE-256 rate blocks |
| Raw H3 attack fixture | 768 interleaved `A_r,B_r` offsets + 416 masks | 1,184 bytes / 9 blocks |
| Stage A | 384 retained input offsets + 416 transported masks | 800 effective bytes; prefix-compatible |
| Stage B, fixed `R=12` | `K_0...K_12` effective masks | 416 live effective bytes |

Thus the fixed-12 representation kernel is **768 bytes / 6,144 bits**. This is
many-to-one representation redundancy, not a security-bit loss or a
cryptanalytic key reduction. Stage A's 800 bytes are not the predecessor's
rotor-ID layout. Stage B's 416 bytes exclude H4 selector material. Both are
computed from already-derived 1,184-byte raw H3 material; directly squeezing
416 bytes would be a new schedule/domain requiring a separate freeze and new
attack evidence.

The lean research baseline therefore drops separately stored H3 offsets and
retains fixed certified AES S-boxes, effective masks, AES MixColumns, and H4
moving wiring. The historical `H3_OFFSET_KEYING_SUPPORTED` receipt remains valid
as marginal representation-cost evidence, but no longer justifies retaining
redundant offset storage. H4 remains parallel evidence rather than a claimed
security advantage: software covers repeated use of each certified tuple, while
RTL and formal cover fixed `(0,1,3,4)` only.

This is an exact material-normal-form equivalence, **not** a break, security-bit
result, or key recovery. It authorizes no arbitrary per-round H4 switching,
production round count, direct-short XOF, key schedule, selector, mode, profile,
fixture, protocol, or RTL. It settles no integrated H2 area, register, Fmax,
power, side-channel, or place-and-route question. **No C/H/N row, E256 finding,
suite, profile, fixture, or release gate closes.** E256-063 remains `OPEN`, and
reviewed standard AEAD remains mandatory for real data.


## 10. Pre-execution decision record — collapsed-schedule H2 integrated core

<!-- E256-H-H2-CONTRACT-START -->

This record is written **before** any H2 integrated-core RTL, testbench, runner,
or receipt exists. It freezes a bounded cost experiment, not a cipher design.
The experiment uses fixed `R=12` only because the exact H3-collapse receipt
banks a 13-word normal form at that point. It does **not** select twelve as a
production round count.

### 10.1 Question and inherited semantics

The experiment asks what a complete iterative research core costs after H3's
redundant offsets are removed, when all live keyed material is inside the
measured system boundary and H4 selection is accounted separately. The frozen
recurrence is

```text
Z_0     = P XOR K_0
Z_{r+1} = L_w(SBOX^32(Z_r)) XOR K_{r+1},  0 <= r < 12.
```

Byte `j` remains `word[8*j +: 8]` in 4-row by 8-column geometry, index
`4*column+row`. Forward H4 RowShift sends output `(column,row)` from source
column `(column+offset[row]) mod 8`, followed by the unchanged AES MixColumns.
Every round includes MixColumns. `K_0...K_12` are exactly thirteen 256-bit
words: **3,328 bits / 416 bytes**.

The core loads effective masks from outside. The gate derives those words by
collapsing each already-derived 1,184-byte H3 material set under the exact H4
tuple used by that run. There is no XOF in this experiment. A direct 416-byte
squeeze is a different schedule/domain and is neither implemented nor implied.

### 10.2 Common non-production core boundary

All measured tops share one iterative 256-bit state, one 32-lane AES S-box bank,
one complete H4 RowShift, eight MixColumns columns, one round counter, and the
same configuration and block protocol. The new RTL may instantiate the frozen
`e256h_atk_sbox` leaf but must not modify its source. It contains no H3 offset
ports and no attack-defect mux.

Configuration is deliberately narrow and runtime-loadable so synthesis cannot
constant-fold the keyed state:

```text
clk, rst
cfg_begin
cfg_valid, cfg_ready, cfg_word[255:0]   // K_0 through K_12, in order
cfg_commit
cfg_h4[11:0]                            // {off3,off2,off1,off0}
key_valid, cfg_error
start, ready, block_i[255:0]
block_o[255:0], busy, done
```

`cfg_begin` invalidates the old configuration and resets the word count.
Exactly thirteen accepted `cfg_valid` beats are required before `cfg_commit`.
Early/late commit, a fourteenth word, configuration while busy, or start without
`key_valid` is rejected and observed by the testbench. The stores themselves
are not reset or claimed to zeroize secrets; `key_valid` is the safety boundary.
This is cost RTL, not a production key-loading protocol.

A runtime H4 tuple is sampled only at successful commit and held across every
round and block until the next configuration. The gate exercises only the
ordered 384-member certified set, each tuple repeated for all twelve rounds.
The direct 12-bit interface is **selector-general**, not an on-chip eligibility
proof: certification filtering remains outside this measurement core. Arbitrary
per-round switching and arbitrary tuple acceptance are not authorized.

### 10.3 Frozen six-top matrix

Three complete storage organizations are crossed with two H4 organizations:

| Storage ID | Organization | H2 eligibility |
|---|---|---|
| `ff` | stationary 3,328-bit runtime-loaded FF vector with public round-index read | eligible research baseline |
| `ring` | runtime-loaded 13-word rotating FF bank; returns to `K_0` after each block | eligible research baseline |
| `mem` | 13x256 generic synchronous memory addressed only by public round index | **H1-ineligible comparator**; never a selected baseline |

| H4 ID | Organization | Scope |
|---|---|---|
| `fixed` | compile-time `(0,1,3,4)` wiring, no selector state | constant-wiring baseline |
| `direct` | one runtime-loaded 12-bit tuple, repeated every round | dynamic H4 marginal-cost measurement over the 384 certified tuples |

The exact tops are:

```text
e256h_h2_ff_fixed       e256h_h2_ff_direct
e256h_h2_ring_fixed     e256h_h2_ring_direct
e256h_h2_mem_fixed      e256h_h2_mem_direct
```

A wide 3,328-bit material-port module with no integrated store may be measured
only as a rejected accounting control. It cannot satisfy H2. The `mem` row is
reported in generic memory bits and surrounding logic; it is not called BRAM,
SRAM, ROM, or an eligible H1 implementation.

### 10.4 Frozen cycle convention

For `ff` and `ring`, acceptance edge `E0` applies `K_0`. Edges `E1...E12`
execute rounds 0...11 with `K_1...K_12`; `E12` registers `block_o`, pulses
`done`, and drops `busy`. The earliest next acceptance is `E13`. Thus block
latency is **12 cycles**, initiation interval is **13 cycles**, steady-state
throughput is exactly `1/13` blocks/cycle and `32/13` bytes/cycle.

The synchronous-memory comparator has explicit fetch boundaries. `E0` accepts
and requests `K_0`; `E1` captures that read and requests `K_1`; `E2` applies
`K_0`; `E3...E14` execute rounds 0...11 with `K_1...K_12`; the earliest next
acceptance is `E15`. Its latency is **14 cycles**, initiation interval is
**15 cycles**, and throughput is `1/15` blocks/cycle and `32/15` bytes/cycle.

These are protocol constants, not measured Fmax. Configuration cost is reported
separately as one begin, thirteen accepted mask words, and one commit. No MHz,
ns, bit/s, or nominal clock rate is inferred from generic logic depth.

### 10.5 Frozen functional coverage

The runner independently rebuilds the AES S-box, complete H4 linear layer, and
fixed-12 effective masks. It reuses the collapse gate's three deterministic raw
material sets and eight-block corpus.

- Each `fixed` top covers three materials times eight blocks: **24** outputs.
- Each `direct` top covers all 384 ordered certified tuples, three materials,
  and eight blocks: **9,216** outputs.
- Across six tops this is **27,720 RTL/model comparisons**.
- For equal masks and tuple, `ff`, `ring`, and `mem` outputs must agree; all
  direct variants must bridge to their fixed counterpart at `(0,1,3,4)`.
- Latency and initiation interval must be input-independent and match §10.4.
- Stimulus changes and start/config pulses occur on negative edges, preserving
  the predecessor's race-avoidance convention.

Exact ciphertext aggregates remain outputs, not predictions. The gate must
also detect wrong key order/addressing, reversed byte packing, wrong H4 shift
direction, an ignored dynamic selector, broken ring rotation, stale synchronous
memory reads, incomplete configuration, and an externalized-storage impostor.

### 10.6 Frozen hierarchy and measurement method

Cost mapping preserves hierarchy through ABC; `flatten` is prohibited before or
during synthesis optimization. Each variant records local module metrics and
computes recursive top totals from the emitted module-instance graph:

```text
recursive(m) = local(m) + sum(instance_count(m,c) * recursive(c)).
```

The formula is applied independently to generic ABC LUT6, sequential bits,
generic memory bits, and primitive cells. Only local primitive cells enter the
base term. Child modules are multiplied once at each immediate hierarchy edge;
design-hierarchy summary totals are never added again. A known nested graph and
a planted duplicate-child accumulator grade this accounting path.

Two frozen views are required. A storage-preserved view records FF and generic
memory capacity without converting memory bits to LUT6. A hierarchy-preserved
ABC `-lut 6` view maps surrounding logic. For end-to-end combinational levels,
a copy of the already-mapped graph is flattened **only for path traversal**;
no optimization follows flattening, the complete primitive multiset must remain
identical, and `ltp -noff` must yield exactly one loop-free result. Local depths
are diagnostic and are never recursively summed.

Sequential and memory cell families are exhaustively classified or rejected.
Every system top must account for all **3,328 logical effective-mask bits** at
its declared boundary, plus separately enumerated state, result, protocol, and
12-bit direct-H4 registers. Runtime H4 marginal cost is the paired recursive
difference between `direct` and `fixed` within the same storage row. No exact
new LUT6, FF, memory, cell, or depth value and no storage winner is predicted.

All measurements are generic yosys/ABC artifacts. They are not vendor LUT/BRAM
utilization, timing closure, Fmax, place-and-route, ASIC area, power, energy,
zeroization, fault, TVLA, EM, or side-channel evidence.

### 10.7 Validity gate and interpretation

The receipt is invalid unless frozen predecessor/source/tool hashes match, all
six tops and exact coverage sets execute, every RTL value matches the
independent model, all cross-variant and cycle obligations hold, every planted
control fires, all storage bits remain inside the graded boundary, recursive
accounting closes against an independent expanded primitive multiset, and
analysis-only flattening preserves that multiset.

A valid receipt reports integrated costs and tradeoffs but selects no
architecture. A surprising cost ordering remains reportable; a validity failure
does not. The intended valid verdict is
`H2_INTEGRATED_COSTS_MEASURED_NO_ARCHITECTURE_SELECTED`; the internal invalid
status is `INVALID_H2_COST_HARNESS` and is never emitted as canonical evidence.

This experiment does not establish security, a rotor-namespace advantage, or a
cryptanalytic result. `R=12` is only a measurement fixture. It chooses no
production round count, XOF, direct-short schedule, H4 switching policy,
storage organization, mode, suite, profile, fixture, protocol, or production
RTL. No C/H/N row or E256 finding closes, and reviewed standard AEAD remains the
real-data boundary.

<!-- E256-H-H2-CONTRACT-END -->

Machine-readable preregistration:
`directives/e256-hardware-h2-preregistration.json`, frozen raw SHA-256
`e3f785583fdf2cda3059e46a677d9e73711ab317ef1eeee3dcdf0c9e7e983a03`.
No H2 implementation artifact existed at this freeze.
### 10.8 Execution result — H2 integrated costs (OPEN)

The gate passed against the frozen preregistration
`directives/e256-hardware-h2-preregistration.json` (raw SHA-256
`e3f785583fdf2cda3059e46a677d9e73711ab317ef1eeee3dcdf0c9e7e983a03`).
Receipt `logs/e256-hardware-h2-gate.json` has schema
`E256-HARDWARE-H2-GATE-1`, machine status `OPEN_PROGRESS`, and deterministic
payload SHA-256
`b0b62be2cfebd870f71ce0b5e5300eb52ab8c2aea243712d1617f4e2351dc7e1`.
Reproduce with `make e256-hw-h2-check`; the banked full rerun reports
`prior_digest_valid=True`, `payload_bytes_match=True`, `digest_match=True`, and
`CHECK PASS`.

Machine verdict:
`H2_INTEGRATED_COSTS_MEASURED_NO_ARCHITECTURE_SELECTED`.

All six tops were exercised over the exact frozen sets: each fixed-H4 top
emitted **24** outputs and each direct-H4 top emitted **9,216**. The **9,216**
canonical result rows discharged **27,720/27,720** independent RTL/model
comparisons with zero mismatches, **18,480** cross-storage comparisons, and
**72** fixed/direct bridges. The exhaustive 256-input tableless S-box bridge matched SHA-256
`c2d8e5eed6cbebd8625fc18f81486a7733c04f9b0129ffbe974c68b90308b4f2`.
All **12/12** controls were detected: wrong key order, wrong round-key address,
reversed word bytes, wrong H4 shift direction, ignored H4 selector, broken ring
rotation, stale synchronous-memory read, incomplete configuration,
externalized storage, nested-child multiplicity, duplicate-child accounting,
and post-map depth preservation. All nine preregistered predictions passed.

Recursive generic measurements under the frozen yosys/ABC flow are:

| Variant | LUT6 | Sequential bits | Generic memory bits | Primitive cells | Levels | Latency / initiation interval |
|---|---:|---:|---:|---:|---:|---:|
| `ff_fixed` | 7,988 | 3,853 | 0 | 11,841 | 8 | 12 / 13 |
| `ff_direct` | 8,224 | 3,865 | 0 | 12,089 | 10 | 12 / 13 |
| `ring_fixed` | 7,878 | 3,853 | 0 | 11,731 | 8 | 12 / 13 |
| `ring_direct` | 8,098 | 3,865 | 0 | 11,963 | 10 | 12 / 13 |
| `mem_fixed` | 4,718 | 1,295 | 3,328 | 6,014 | 8 | 14 / 15 |
| `mem_direct` | 4,730 | 1,307 | 3,328 | 6,038 | 10 | 14 / 15 |

Every integrated boundary accounts for all **3,328** effective-mask bits. For
every one of the **27,720** executed inputs, the testbench observed `ready` low
throughout `busy` and high with `done`; the earliest next acceptance is the
following edge. The resulting per-variant latency and initiation-interval sets
are singleton over exactly 24 fixed or 9,216 direct observations. The FF/ring
cycle constants are 12-cycle latency, 13-cycle initiation interval, and `32/13`
bytes/cycle; the synchronous-memory comparator is 14, 15, and `32/15`. These
are protocol cycles, not clock frequency or physical throughput.

The observed `direct - fixed` top-level deltas are `(+236 LUT6, +12 sequential
bits, +0 memory bits, +248 cells, +2 levels)` for `ff`, `(+220, +12, +0, +232,
+2)` for `ring`, and `(+12, +12, +0, +24, +2)` for `mem`. The normalized
hierarchy and storage-preserved common-module primitive-signature multisets
match within each pair. Separate ABC invocations nevertheless chose different
mapped costs and LUT decompositions for some identical common children; the
receipt records both mapped metric/type multisets rather than falsely requiring
them to be byte-identical across tops. Exact normalized mapped signatures remain
mandatory before versus after analysis-only flattening inside every top. The
paired deltas are therefore reproducible generic-flow observations, not an
isolated physical H4-selector area claim.

The `mem` variants remain **H1-ineligible generic-memory comparators**, not
claimed BRAM, SRAM, ROM, or a storage recommendation. `R=12` remains a bounded
measurement fixture; the 416-byte form is collapsed from already-derived
1,184-byte material and does not authorize a direct-short XOF. These generic
results establish no vendor utilization, timing/Fmax, place-and-route, ASIC
area, power, energy, zeroization, fault, TVLA, EM, side-channel, or security
result. They choose no architecture, storage winner, round count, XOF, H4
switching policy, schedule, mode, suite, profile, fixture, protocol, production
RTL, or security-bit value. **No C/H/N row or E256 finding closes.** E256-063
remains `OPEN`, and reviewed standard AEAD remains mandatory for real data.

## 11. Preregistered H4 per-round switching-sequence gate

<!-- E256-H-H4-SEQUENCE-CONTRACT-START -->
### 11.1 Status and boundary

This is the frozen pre-execution contract for the first bounded E256-H experiment in which the H4 row-offset tuple may change between rounds.  It follows the approved H2 integrated-cost tranche but does not alter, supersede, or reinterpret that frozen evidence.  At freeze time no `e256h_h4_sequence_core.v`, `e256h_h4_sequence_core_tb.v`, `e256_hardware_h4_sequence_gate.py`, H4-sequence receipt, or H4-sequence scratch tree existed.  The machine-readable companion is `directives/e256-hardware-h4-sequence-preregistration.json`; its raw-file SHA-256 must be recorded outside this marker before any implementation artifact is created.

The gate asks only whether a precisely defined arithmetic family of certified H4 tuples preserves the already-used mixed-window dependency criterion, whether the sequence-specific H3 offset collapse is exact on a frozen executable corpus, whether commit-sampled per-round selection is implemented exactly in two H1-eligible integrated storage organizations, and what bounded mapped-cost delta the extra selector state introduces.  It does **not** authorize arbitrary H4 switching, catalog enforcement in production RTL, a production switching policy, an architecture winner, a round count, a key schedule, an XOF, a security level, a cipher suite, or reviewed AEAD use.  E256-063 remains OPEN regardless of outcome.

### 11.2 Frozen source identities and terminology

The ordered certified list is the exact 384-entry `deterministic_payload.results.h4_wiring.certified_set` in `logs/e256-hardware-candidate-gate.json`, with canonical SHA-256 `199f1f7bddccf19ce5aa0bde0987441735d628354140d53ebdfec538d7b3f5ed`.  Index 0 is `(0,1,2,5)`, index 1 is the H2 fixed tuple `(0,1,3,4)`, and index 383 is `(7,6,5,2)`.  Reordering, deduplication, or replacement invalidates the gate.  Tuple `(o_0,o_1,o_2,o_3)` is packed as the 12-bit little-chunk code `o_0 | (o_1 << 3) | (o_2 << 6) | (o_3 << 9)`, where each offset is in `[0,7]`.

The predecessor H2 RTL, testbench, runner, and receipt remain immutable comparators with SHA-256 values `05edd3c1cfb3cfc24ecb12fcada8c07f81451eb9937efd0f3fc10abf3f1d0adf`, `fb02e49ab376c761b6ae1bbb3fec6ab1325c5bfda71c9ff2684668cc14cb2b95`, `3a62a7fc56a65682aa735fbb4cd1c611e0da8d4be84081a77c948865f7b77c5c`, and deterministic receipt digest `b0b62be2cfebd870f71ce0b5e5300eb52ab8c2aea243712d1617f4e2351dc7e1`.  The frozen material corpus SHA-256 is `b6738e7f117bb7b916ee002db482f105a3eb5a046ee84dff45f178510cdeb691`; the AES S-box table SHA-256 is `c2d8e5eed6cbebd8625fc18f81486a7733c04f9b0129ffbe974c68b90308b4f2`; and the offset-collapse predecessor digest is `1478a0ba317bce5f33cb053744b050bb6188543405c1dfacf52d8aaf920c4b71` under preregistration hash `3d7a12731fcf81f6120577122c55bd8ec25589a82226d49fab7e5b8350ee0cee`.

“HELUT hardware flow” in this tranche means generic RTL mapped by the pinned Yosys/ABC flow and behavior checked by pinned Icarus on an Apple-Silicon host inside the HELUT repository.  A separate MPSGraph/Metal execution may be reported only if a receipt actually invokes it.  This gate is not a vendor FPGA bitstream, placement-and-routing result, Fmax or physical-power measurement, encrypted evaluation, or evidence that an Apple GPU was literally synthesized into an FPGA.

### 11.3 Frozen sequence corpora

Let `C[0] ... C[383]` be the ordered certified list.  For `a,d in [0,383]`, define the twelve-round schedule

`W[a,d][r] = C[(a + r*d) mod 384]`, for `r in [0,11]`.

The structural census is every `(a,d)` in lexicographic order with `a` outermost and `d` innermost: 147,456 schedules, 1,474,560 contiguous three-round windows, and 1,622,016 adjacent transition placements.  Its canonical compact sorted-key JSON records are `{"a":a,"d":d,"indices":[...]}` and the ordered list SHA-256 is `fc0eac948c91ec416b5473724af21106e45a05a9fefa7451577bbd73582d85c8`.

The executable corpus is every `a` for `d=0`, followed by every `a` for `d=1`: 768 schedules in `d`-then-`a` order, 9,216 round placements, and ordered-list SHA-256 `8056e742146cffd707f3c5590667766fc376c7b25fee4bcec5cd3fc49cbc2a6a`.  The first 384 schedules preserve every repeated predecessor baseline; the next 384 form a balanced moving-sequence lane in which every certified tuple appears once at every round position.  This executable subset does not claim exhaustive transition or orbit-length coverage; the complete arithmetic family is graded structurally instead.

Each executable schedule is paired with the exact three frozen predecessor material sets and eight frozen 256-bit blocks, for 18,432 schedule/material/block rows.  The repeated variants execute **only** the `d=0` rows: 9,216 outputs per repeated variant.  The sequence variants execute all rows: 18,432 outputs per sequence variant.  Across four variants this is exactly 55,296 RTL/model comparisons and 55,296 per-input cycle observations.  FF/ring storage comparisons total 27,648 and repeated/sequence bridge comparisons total 18,432.  Extra repeated outputs, absent sequence outputs, duplicate rows, or a missing timing observation invalidate the gate rather than being ignored.

### 11.4 Frozen sequence semantics and collapse identities

A sequence configuration is packed on `cfg_h4_sequence[143:0]` with tuple code `w_r` in bits `[12*r +: 12]`.  A successful configuration commit atomically samples selector state.  Repeated variants retain only the low twelve bits and reuse `w_0` for all rounds.  Sequence variants retain all 144 bits and select `w_r` using the public round index.  Every block starts again at `w_0`.  Changes to the external sequence pins after commit must not affect an in-flight or later block until another complete successful commit.  The interface supplies configuration, not live per-round selector state.

For raw H3 material `(M_0 ... M_12, A_0 ... A_11, B_0 ... B_11)` and schedule `(w_0 ... w_11)`, the only accepted effective-mask collapse is

- `K_0 = M_0 XOR A_0`,
- `K_r = L_{w_(r-1)}(B_(r-1)) XOR M_r XOR A_r` for `1 <= r < 12`, and
- `K_12 = L_{w_11}(B_11) XOR M_12`.

The canonical evaluator is `Z_0 = X XOR K_0` followed by

`Z_(r+1) = L_{w_r}(SBOX^32(Z_r)) XOR K_(r+1)` for `0 <= r < 12`.

The independent raw-H3 evaluator and canonical evaluator must agree at every frozen comparison boundary.  Stage A and Stage B each contain exactly 221,184 comparisons (`768 schedules * 3 materials * 8 blocks * 12 rounds`), for 442,368 software collapse comparisons.  The previous selector `w_(r-1)`, not the current selector, transports `B_(r-1)`; no terminal `A_12` term exists.  A mismatch is a validity failure requiring diagnosis, not a row that may be filtered.

### 11.5 Structural grading

Each of the 1,474,560 contiguous three-round windows is recomputed using its actual ordered selectors.  Dependency starts from 32 independent byte singleton sets; the AES S-box is lane-preserving for this criterion, and each `L_w` applies the exact AES row mixing plus that round's certified row-offset wiring.  The receipt must report the complete failure count and the first deterministic counterexample, if any, without filtering or replacing schedules.

A zero-failure census and a nonzero-failure census are both valid scientific outcomes.  The latter parks unrestricted arithmetic switching and prints the counterexample.  Local tuple certification does not prejudge this mixed-sequence result.  In particular, the fixed-tuple/local four-round wide-trail manifest and its 25-active-S-box statement are **not** inherited as a mixed-sequence theorem; this gate neither proves nor asserts a mixed-sequence differential, linear, integral, algebraic, or cryptographic security bound.

### 11.6 Integrated variants, protocol, and mapped accounting

The only four tops are `ff_repeated`, `ff_sequence`, `ring_repeated`, and `ring_sequence`.  Both storage organizations retain all thirteen 256-bit effective masks internally (3,328 logical mask bits) and are H1-eligible comparators.  FF variants use stationary indexed effective-mask storage.  Ring variants use the predecessor rotating thirteen-word bank and must return to `K_0` ordering after every completed block.  No generic-memory top is introduced.

The accepted protocol is the predecessor H2 protocol: a clean idle `cfg_begin`, thirteen accepted effective-mask words, then one idle `cfg_commit`; start is accepted only while ready; E0 applies `K_0`; E1 through E12 execute rounds 0 through 11; done is E12.  Every variant has frozen latency 12 cycles and earliest initiation interval 13 cycles, with ready low throughout busy.  Incomplete, overlapping, or busy-time configuration is rejected without changing committed in-flight state.  No reset or zeroization property is claimed for mask or selector storage.

Every top is synthesized independently with the pinned Yosys/ABC generic LUT6 flow.  The receipt must preserve the pre-map hierarchy JSON, mapped hierarchy JSON, analysis-only flattened JSON, and mapped Verilog; recursively close child-instance multiplicities against an independent flat primitive multiset; distinguish mask-state bits from selector-state bits; reject wide live ports that externalize either state; and prove flattening preserves primitive counts while producing a loop-free end-to-end combinational depth.  Paired cost deltas compare sequence against repeated only within the same storage organization.  LUT6, sequential-bit, primitive-cell, and level deltas are graded findings with no frozen sign, magnitude, or winner.

### 11.7 Frozen controls and validity rule

The runner must detect all of the following planted failures through the same parsers, models, protocol, or accounting paths used for the main result: corpus digest perturbation; reversed sequence order; holding `w_0` for every round; selector-index rotation by one; wrong H4 shift direction; using `w_r` rather than `w_(r-1)` in collapse transport; adding terminal `A_12`; wrong effective-mask address; reversed bytes inside every mask word; broken ring rotation; incomplete configuration; post-commit dependence on changed sequence pins; externalized live sequence state; externalized live mask state; nested-child multiplicity; duplicate child accounting; post-map flatten/depth corruption; an extra repeated-variant output; and a missing per-input cycle observation.

Harness validity requires exact source/tool/corpus identities, all controls detected, exact execution sets and counts, complete collapse agreement, byte-exact independent-model/RTL agreement, exact ready/busy timing evidence for every executed input, and closed synthesis/accounting invariants.  Structural dependency failures and either sign of any mapped-cost delta remain reportable valid science.  No result may be promoted by deleting an adverse schedule or output.

### 11.8 Frozen verdicts and non-claims

A valid receipt must select exactly one structural verdict: `ARITHMETIC_SEQUENCE_CENSUS_ZERO_MIXED_WINDOW_FAILURES` or `ARITHMETIC_SEQUENCE_CENSUS_COUNTEREXAMPLE_FOUND`.  It must separately report executable semantic validity and paired mapped measurements.  Neither verdict selects an H4 policy.  At most, the first says that this finite arithmetic family had no failure under this specific three-round byte-dependency criterion; the second rejects unrestricted use of the tested family under that criterion.

This tranche remains bounded measurement and falsification evidence.  It makes no IND-CPA/CCA, PRP/PRF, collision, preimage, related-key, quantum, nonce-misuse, side-channel, physical-hardware, performance-at-production-N, FHE, or AEAD claim.  Reviewed standard AEAD remains mandatory around any experimental construction.  No C/H/N row, public claim epoch, site assertion, textbook theorem, or video voiceover moves merely because this gate executes.
<!-- E256-H-H4-SEQUENCE-CONTRACT-END -->

**H4 sequence preregistration freeze.** The machine-readable preregistration was written after the marker above and before any new RTL, testbench, runner, receipt, or scratch artifact.  Its raw-file SHA-256 is `b7afcc67ceac142a800468362ee0c97fcf6c7b6843f0cdd2f96f5d77894fc8e2`; the immutable marker digest it pins is `aac50bda525ead96234fc3c0e3e3692fabbde101de34d44f632d6a65bfbed1e4`.

### 11.9 Execution result — arithmetic switching counterexample (OPEN)

The frozen gate executed validly.  Preregistration `directives/e256-hardware-h4-sequence-preregistration.json` retains raw SHA-256 `b7afcc67ceac142a800468362ee0c97fcf6c7b6843f0cdd2f96f5d77894fc8e2` and marker digest `aac50bda525ead96234fc3c0e3e3692fabbde101de34d44f632d6a65bfbed1e4`.  Receipt `logs/e256-hardware-h4-sequence-gate.json` has schema `E256-HARDWARE-H4-SEQUENCE-GATE-1`, status `OPEN_PROGRESS`, deterministic-payload SHA-256 `4562482417cb2917208cf37f8c4441efbdde602230d878ba49d249b017822064`, and original full-record SHA-256 `4e53a53caa1da8bee7f45c572f6208624fd02703d358cdfb52ca9a31c98e0bae`.  Reproduce the deterministic payload with `make e256-hw-h4-sequence-check`.

The preregistered verdict is **`ARITHMETIC_SEQUENCE_CENSUS_COUNTEREXAMPLE_FOUND`**: **737,280 of 1,474,560** contiguous three-round windows in the complete arithmetic schedule census fail the exact all-to-all byte-dependency criterion.  The first frozen-order witness is `a=0`, `d=1`, `start_round=1`, list indices `[1,2,3]`, and tuples `(0,1,3,4)`, `(0,1,4,3)`, `(0,1,4,7)`; output lane 0 lacks dependencies on input lanes `[6,11,24,29]`.  This parks unrestricted use of the tested arithmetic per-round switching family under this criterion.  It does not show that every possible H4 switching policy fails, and the fixed-tuple four-round/25-active-S-box result is not inherited as a mixed-sequence theorem.

The adverse structural result is not an implementation mismatch.  Sequence-specific H3 collapse passed **221,184 Stage-A plus 221,184 Stage-B comparisons** (**442,368 total**) with zero mismatches, exact previous-selector transport, and no terminal `A_12`.  The four integrated tops passed **55,296/55,296** independent RTL/model comparisons over **18,432** rows, **27,648** FF/ring storage comparisons, **18,432** repeated/sequence bridges, and **55,296/55,296** per-input ready/busy observations.  Every variant retained latency 12 and initiation interval 13.  All **19/19** planted controls were detected.

The paired generic Yosys/ABC sequence-minus-repeated observations are FF `(-407 LUT6, +132 sequential bits, -275 primitive cells, +1 combinational level)` and ring `(-57 LUT6, +132 sequential bits, +75 primitive cells, +1 level)`.  There was no threshold and no winner.  In particular, negative LUT deltas from independent generic ABC mappings are not physical selector savings, vendor utilization, timing/Fmax, or an architecture recommendation.

This remains bounded falsification and generic mapped-RTL evidence on an Apple-Silicon host, not Metal/FHE execution or a literal GPU-to-FPGA synthesis result.  It selects no H4 policy, architecture, storage winner, round count, XOF, schedule, cipher suite, AEAD construction, physical implementation, or security value.  No C/H/N row or public claim epoch moves; **E256-063 remains OPEN**, and reviewed standard AEAD remains mandatory for real data.

## 12. E256-X0 compositional transition-policy certificate (OPEN)

The separately frozen X0 contract is `directives/e256-x0-h4-evolution.md`, inclusive marker SHA-256 `1ef354e9b933838eb3e74b32b202e4693f1bfdd62379f10dbc6a8673b3383962`; its preregistration raw SHA-256 is `d39759bc2677fa17227ea129fc3ec20791a749cec2b9cdd33aa18c45df338711`. Receipt `logs/e256-x0-h4-evolution-gate.json` has schema `E256-X0-H4-EVOLUTION-GATE-1`, status `OPEN_PROGRESS`, deterministic-payload SHA-256 `35060c802427046f5f4630c6b9db6401d8ac90c4649fc0cf088d3f35f31b1b44`, and graph root `d7e44b625acc693a28469dd993edfe3bf8cd7a4b966275a70ad7cf3941e4a80a`. Reproduce it with `make e256-x0-h4-evolution-check`.

X0 independently proved the exact mixed-window criterion `S(y)+S(z)=Z8` over all 147,456 ordered pairs and derived 73,728 safe directed transitions. Every catalog node has degree 192, but the full graph splits into two 192-node SCCs; the 16-support quotient splits into two 8-node SCCs and has no Hamiltonian cycle. Under the frozen fallback, the proof-carrying 12-selector path alternates indices 0 and 3 and verifies 11/11 adjacent transitions. All 23 controls fired, and the predecessor census reconstructed exactly.

This is a host-side structural policy grammar and path certificate, not new RTL or an architecture selection. It does not inherit the fixed-selector four-round/25-active-S-box statement, cross the two support components, choose a schedule or round count, establish attack resistance, enforce catalog membership in hardware, or provide Metal/FHE/vendor-FPGA evidence. The alternating path is a bounded witness, not a production self-evolution mechanism. E256-063 remains OPEN and reviewed standard AEAD remains mandatory.
