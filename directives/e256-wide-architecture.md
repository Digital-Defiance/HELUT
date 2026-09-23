# E256-W wide-state Enigma-rotor architecture decision record (AUTHORIZED RESEARCH, OPEN)

<!-- E256-W-CONTRACT-START -->

Design status: **W0–W12 accepted as research constraints; round count and
several parameters remain OPEN**.
Evidence status: **no receipt yet on this record**.
Implementation authorization: **AUTHORIZED for preregistered model, structural
verification, and attack-harness research only**. A cipher suite, profile,
fixture, production implementation, RTL, protocol deployment, promotion, or
claim change remains blocked.

This record answers the wide-state fork required by **D10** and specified as a
research requirement in `directives/e256-vnext-topology.md` §0.5. It exists
because the byte-local topology cannot be repaired: the frozen rotor/schedule
campaign proved a rotor-count-invariant ceiling rather than a tuning problem.

No C/H/N row moves on this file. E256 remains an experimental cryptographic
laboratory and must not protect real data. A reviewed standard AEAD remains the
real-data security boundary. E256-v1/v2/v3 and byte-local vNext results are
**not** inherited by this design.

Audit row: **E256-062**. Ledger: `directives/e256-audit.md`.
Predecessor byte-local record: `directives/e256-vnext-topology.md`.

## 0. Why a new design instead of another byte-local iteration

Two measured results from the byte-local campaign
(`logs/e256-vnext-rotor-schedule-bakeoff.json`, payload
`fd54809cbd12de9d6f14151bcd401232aae765b72cb8368128ea54bdfa7b7197`) forced this
fork:

1. **The codebook ceiling is architectural.** Every frozen byte state is a
   permutation on 256 points, so at most 255 chosen-input queries recover the
   complete map. That number was unchanged from 1+1 through 16+16 rotors while
   honest cost rose 16×.
2. **The rotors were not load-bearing.** The executed `prf_mask_only` baseline
   supplied the same tested confidentiality behavior at one mask derivation and
   one XOR per byte. The rotor stack was ablatable, which is disqualifying for a
   design whose identity is "rotor cipher."

The design goal is therefore not "more rotors." It is a construction where
removing the rotors **provably breaks the cipher**, and where the byte codebook
attack has no target.

### 0.1 What "Enigma-based" must and must not mean here

Retained from Enigma, because it is meaningful:

- A large keyed **rotor namespace** with per-position selection.
- **Position-varying substitution**: the active rotor set changes with the
  counter, which is the modern analogue of stepping.
- Rotor **wiring as secret keyed material** derived from the root secret.

Deliberately discarded, because it is proven harmful or merely decorative:

- The **reflector** and reciprocal traversal. It forces a fixed-point-free
  involution with 128 two-cycles and a two-query distinguisher at advantage
  ≈0.992, invariant in rotor count (**E256-061**).
- The **involutive plugboard** constraint.
- An **odometer stepping rule** as a security mechanism.
- Any expectation that encryption and decryption should be the same operation.

## 1. Accepted research constraints

| ID | Decision | Rationale and consequence |
|---|---|---|
| **W0 — security boundary** | A reviewed standard nonce-misuse-resistant AEAD remains the external boundary; AEAD-only remains the comparison baseline. | E256-W has no independent acceptance. It may only ever be an inner keyed permutation candidate. |
| **W1 — wide state** | The security-bearing unit is a **256-bit / 32-byte state**, not an independent byte map. | Removes the 255-query byte-codebook target. "E256" now honestly denotes a 256-symbol alphabet **and** a 256-bit state, never 256-bit security. |
| **W2 — state geometry** | Arrange the state as **4 rows × 8 columns**, byte `j` at row `j mod 4`, column `j div 4`. | Matches the reviewed Rijndael 256-bit-block geometry so the diffusion argument is inherited rather than invented. |
| **W3 — rotor layer is the only nonlinearity** | Each round applies **32 keyed 8-bit bijections**, one per lane, selected per round and lane from a 256-ID keyed namespace. | This is the Enigma rotor stack made parallel and load-bearing. All nonlinearity comes from rotors, so ablating them must collapse the cipher to affine. |
| **W4 — rotor construction** | `R(x) = L_out(AES_SBOX(L_in(x) XOR c_in)) XOR c_out`, with independently derived invertible 8×8 GF(2) matrices and constants. | Affine equivalence **preserves** differential uniformity, linearity, and algebraic degree. Every derived rotor therefore inherits max DDT 4, max \|LAT\| 32, degree 7. The trail bound becomes key-independent, which random Fisher–Yates rotors could never provide. |
| **W5 — explicit cross-byte diffusion** | Row shift with the **Rijndael 256-bit offsets (0, 1, 3, 4)**, then a **4×4 MDS matrix over GF(2^8)** on each of the 8 columns. | MDS gives branch number 5. The shift offsets are diffusion-optimal for 8 columns, so one column's bytes reach 4 distinct columns. Together these give the wide-trail active-S-box bound. |
| **W6 — counter-bound rotor selection** | Rotor IDs, round masks, and any tweak material derive from a keyed PRF over the complete canonical context including direction, sequence, and block counter. | Keeps the Enigma "stepping" character with random access, exact limits, and reproducible domain separation. No LFSR or NLFF appears in the security path. |
| **W7 — round mask injection** | XOR a 32-byte PRF-derived round mask before each rotor layer and once after the final round. | Standard key-injection discipline; makes every round context-bound. |
| **W8 — no reciprocity** | Encryption and decryption are intentionally different routines. | Directly removes the **E256-061** involution class. |
| **W9 — constant-time implementability** | The rotor layer must have a tableless bitsliced evaluation path, or physical-security claims are explicitly excluded. | Arbitrary secret-derived lookup tables have no efficient generic constant-time path. This is why W4 chooses an algebraic family over random permutations. |
| **W10 — round count is evidence-driven** | Test 1–12 rounds. Report diffusion completeness and the trail bound. Do **not** select a production round count in this record. | A round count chosen by fiat is an unforced error. Selection requires the full attack matrix, not a diffusion plot. |
| **W11 — offline evolution only** | Deterministic, immutable, versioned, preregistered, control-calibrated, holdout-graded, human-promoted. Deployed mutation forbidden. | Inherits the §0.6 contract of the predecessor record. |
| **W12 — promotion and claims** | Promotion requires a new incompatible identity, byte-exact specification, two independent implementations, externally held KATs, the full attack matrix, protocol and hardware evidence, external cryptographic review, and human claim review. | Verified structural properties are necessary, never sufficient. |

## 2. Construction

Let the state be 32 bytes. Byte `4c+r` is row `r`, column `c`; bytes are
polynomial coefficients with bit 0 as the constant term. `direction` is the
traffic/channel direction and remains unchanged between permutation and inverse;
it is not an encrypt/decrypt selector. All derived material comes from the
keyed PRF over the canonical context.

```text
E256-W-Permute(W, context, R):
    W <- W XOR RoundMask(context, 0)
    for r in 1 .. R:
        W <- RotorSub(W, context, r)      # 32 keyed 8-bit bijections
        W <- RowShift(W)                  # left rotations (0,1,3,4)
        W <- ColumnMix(W)                 # 4x4 MDS over GF(2^8), 8 columns
        W <- W XOR RoundMask(context, r)
    return W

E256-W-Inverse(W, context, R):
    for r in R .. 1:
        W <- W XOR RoundMask(context, r)
        W <- ColumnMix^-1(W)
        W <- RowShift^-1(W)
        W <- RotorSub^-1(W, context, r)
    return W XOR RoundMask(context, 0)
```

Encryption and decryption differ by construction (**W8**).

Component detail:

- **RotorSub.** Lane `j` in round `r` uses rotor ID
  `id[r][j] = Select(context, r, j)` drawn from the 256-ID keyed namespace.
  Lane/round selections use independently domain-separated inputs; ID repeats
  are allowed and reported rather than silently rejected.
- **RowShift.** For offsets `s=(0,1,3,4)`, left rotation is
  `out[4c+r] = in[4((c+s[r]) mod 8)+r]`; inverse uses `c-s[r]`.
- **ColumnMix.** For each column,
  `out[4c+r] = XOR_k gf_mul(M[r][k], in[4c+k])`, where `M` has rows
  `[02 03 01 01]`, `[01 02 03 01]`, `[01 01 02 03]`, and
  `[03 01 01 02]` over
  `GF(2^8) = GF(2)[x]/(x^8 + x^4 + x^3 + x + 1)`. The inverse is computed by
  exact GF(2^8) Gaussian elimination and must multiply with `M` to identity.
- **RoundMask.** One domain-separated purpose stream emits 32 consecutive bytes
  for each mask index `0...R`, bound to the complete canonical context.

### 2.1 The trail argument this buys

Because **W4** rotors are affine-equivalent to the AES S-box, for every key and
every derived rotor:

```text
max differential probability per active rotor   = 4/256   = 2^-6
max linear correlation per active rotor         = 32/256  = 2^-3
algebraic degree                                = 7
```

Because **W5** targets branch number 5 with diffusion-optimal row shifts, the
preregistered theorem target is a lower bound of **25 active rotors over any
4-round trail**. The harness must certify rather than restate the premises:
all 69 nonempty square MixColumns minors are nonzero; the four row offsets are
distinct; and for each `a=1...4` active source columns, the middle two rounds
satisfy the bundle case `a + (5-a) >= 5`, while `a>=5` is immediate. Combined
with the two outer MDS inequalities, this yields `5*5=25`. If that finite
certificate passes, the corresponding single-trail bounds are:

```text
4-round differential probability  <=  (2^-6)^25   = 2^-150
4-round linear correlation        <=  (2^-3)^25   = 2^-75
```

This is the property the byte-local design could never state. It is a bound on
**single differential and linear trails only**. It is not a security proof, and
it says nothing about differential clustering, integral, algebraic, meet-in-the-
middle, invariant-subspace, related-key, or implementation attacks.

### 2.2 Why the rotors are now load-bearing

This is the design's central falsifiable assertion, and the harness must test it
as a control that **fails loudly**:

- Replace the rotors with identity or any affine map, and the whole permutation
  becomes **exactly affine**: masks are XORs and both diffusion layers are
  GF(2)-linear. An affine 256-bit map is recovered by linear algebra from 257
  chosen pairs (zero plus the 256 basis vectors), then checked on disjoint
  vectors. The cipher is dead.
- Remove the diffusion layer instead, and the construction degenerates to 32
  independent byte maps, which restores the 255-query byte codebook the
  predecessor campaign already rejected.

Neither layer is ablatable. That is the structural difference from the
byte-local candidate, where the rotor stack could be removed with no measured
loss.

## 3. Rejected alternatives

- **More byte-local rotors.** Measured: no attack-scaling gain from 2 to 32
  rotors per byte, 16× honest cost. Rejected.
- **Reflector / reciprocal traversal.** Proven involution and two-query
  distinguisher, rotor-count invariant. Rejected.
- **Random Fisher–Yates rotors as a production family.** Uncontrolled DDT/LAT,
  key-dependent bounds, and no generic constant-time lookup path. Retained only
  as a null/comparison family, never as a candidate.
- **Fixed public S-box with no rotor namespace.** Defensible, but abandons the
  Enigma character the project explicitly wants. Kept as the honest fallback if
  the rotor namespace earns nothing measurable.
- **Feistel over 256 bits.** Viable and considered. An SPN with an MDS layer
  gives cleaner provable trail bounds per round, so it was preferred. Not
  claimed superior in every respect.
- **A bespoke AEAD mode or framing.** Rejected. Designing a mode is a larger
  risk than designing a permutation; use reviewed constructions.
- **LFSR/NLFF schedule material in the security path.** Rejected; period and
  balance are not unpredictability.
- **Secret S-boxes as a security argument.** Explicitly rejected. The trail
  bound holds for every drawn rotor, so security must not rest on the wiring
  being hidden.

## 4. Choices deliberately left OPEN

1. **Round count.** A floor may be justified from diffusion completeness and the
   trail bound, but the production value requires the full attack matrix.
2. **Whether the rotor namespace earns its cost** over a single fixed reviewed
   S-box with keyed affine conjugation. This must be measured, not assumed.
3. **Tweak/domain granularity**: per message, per block, or per round.
4. **Mode of use**: keyed permutation inside a reviewed construction versus a
   block cipher with an external mode.
5. **Exact PRF/XOF** for masks and selection.
6. **Bitsliced implementation technique** and its measured leakage/area cost.
7. **State width beyond 256 bits**, if multi-user or long-message limits demand
   it.

## 5. Gates before any promotion

1. Verified structural properties: MDS/branch number, diffusion optimality,
   exact rotor DDT/LAT/degree, diffusion completeness, ablation controls.
2. Byte-exact specification with canonical encodings and limits.
3. Full attack matrix: differential/linear including clustering, integral,
   algebraic and degree growth, meet-in-the-middle, impossible differential,
   rebound, slide, invariant subspace, related-key/tweak, multi-user,
   reset/reuse, and TMTO — each with planted weak and reduced-round positive
   controls that must be recovered.
4. Independent implementations, externally held KATs, and differential testing.
5. Protocol integration and hardware/side-channel/fault evidence.
6. Independent cryptographer review, then human claim review.

## 6. Non-claims

- No IND-CPA, IND-CCA, AEAD, PRF, or standalone-cipher security is claimed.
- **No security-bit value is computed or implied.** "E256" denotes the 256-symbol
  alphabet and the 256-bit state, never 256-bit security.
- A single-trail differential/linear bound is **not** a security proof and does
  not cover trail clustering or the attack classes listed in §5.
- Verified MDS, structural byte-dependency reachability, DDT/LAT, and avalanche
  behavior are structural diagnostics, not confidentiality evidence. Boolean
  dependency paths do not prove that algebraic cancellation is impossible.
- No external cryptanalysis, independent implementation, external KAT, RTL,
  protocol, side-channel, or fault evidence exists for this design.
- Passing this record's controls is a bounded failure to reject, not security.
- Reviewed standard AEAD remains mandatory for real data, and AEAD-only remains
  a valid final outcome.
- Nothing here is production-ready, and no claim row, suite, profile, fixture,
  or release gate moves on this record.
<!-- E256-W-CONTRACT-END -->


## 7. Receipt interpretation (E256-062, OPEN)

Added after the contract block; the hash preimage above is unchanged.

Preregistration `directives/e256-wide-preregistration.json`
(`686df3175e91555ee1983bdf4a12fe8f28c463128e06985f3baa1d7777b34c42`) was
executed by `Scripts/e256_wide_gate.py`. Receipt:
`logs/e256-wide-state-gate.json`, schema `E256-WIDE-STATE-GATE-1`, status
`OPEN_PROGRESS`, deterministic payload
`21758ce220b9da469a18ea617fa7b2fd41e906add69a258f830b12843e3e495b`. Reproduce
with `make e256-wide-check` (`digest_match=True`, `payload_match=True`).

Machine verdict: `STRUCTURAL_WIDE_STATE_CANDIDATE_RETAINED_FOR_ATTACK_ONLY`.
**No production round count was selected**, as required by W10.

What the harness certified:

- **Diffusion.** All **69** nonempty square MixColumns minors nonzero over
  GF(2^8), exact two-sided inverse, branch number **5**, distinct row offsets,
  and earliest structural all-to-all byte dependency at round **3**.
- **Trail obligation.** `E256-W-WIDETRAIL-25-v1` premises all discharged, giving
  the preregistered lower bound of **25 active rotors** over four rounds, with
  single-trail bounds 2^-150 differential and 2^-75 linear. Single trails only.
- **Rotors.** 1,024 forward/inverse table pairs exact and bijective; every
  sampled spectrum equals DDT max **4**, nontrivial \|LAT\| max **32**, forward
  and inverse coordinate ANF degree **7**, matching the W4 prediction for every
  sampled key and ID.
- **Functional.** 13,824/13,824 round trips across the exact 144-context
  Cartesian product, with the compositional round-bijection certificate.
- **Load-bearing.** Both ablations fired: identity rotors made the whole
  permutation exactly affine and matched the recovered model on **64/64**
  holdouts, while removing diffusion left all 32 dependency rows singleton. The
  candidate mismatched the affine model at every probed round.
- **Controls.** **7/7** planted controls detected through their declared shared
  paths, with candidate and fixed-AES null calibrations passing.

What it did **not** establish, and what drives the next fork:

- The `fixed_aes_spn` baseline reached the **same** structural bounds with no
  keyed rotor namespace. This gate therefore establishes **no rotor-namespace
  advantage**, exactly as preregistered.
- §4 item 2 (does the namespace earn its cost) remains OPEN, and a hardware cost
  analysis indicates the keyed wrappers and their parameter storage are the most
  expensive part of the design. That analysis opens the hardware-first fork:
  `directives/e256-hardware-architecture.md` (**E256-063**).
- AEAD-only remains the production baseline. Retention authorizes only a further
  preregistered attack campaign.
