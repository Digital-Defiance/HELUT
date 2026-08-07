# E256-vNext clean-sheet architecture decision record (AUTHORIZED RESEARCH, OPEN)

Decision status: **D0–D11 accepted as research constraints; parameter selection remains OPEN**.
Evidence status: **OPEN progress only**.
Implementation authorization: **AUTHORIZED for preregistered model, attack-harness,
and specification research only**. A cipher suite/profile, fixture, production
software, RTL, protocol deployment, promotion, or claim change remains blocked
until its later gates are separately satisfied.

This is the design record that precedes every E256-vNext change. It records
research constraints, alternatives, consequences, and unresolved choices; it is
not a byte-exact cipher specification and does not authorize production use.

Architecture delegation: **ACCEPTED FOR STAGED RESEARCH**

- Authority: workspace owner, via the instruction to choose the best
  Enigma-based 256-centric cipher
- Decision date: **2026-08-20 session date**
- Accepted research constraints: **D0–D11**
- Delegated discretion: resolve OPEN choices by preregistered evidence; retain
  `NO ACCEPTABLE CANDIDATE` and AEAD-only as valid outcomes
- Still requires separate human action: C/H/N claim movement, suite/profile
  promotion, publication, or production authorization
- Independent cryptographer acceptance: **PENDING**

No C/H/N row moves on this file. E256 remains an experimental cryptographic
laboratory and must not protect real data. A reviewed standard AEAD remains the
real-data security boundary. Existing E256-v2 claims and staged E256-v3 receipts
remain bound to their exact profiles; this research direction neither supersedes
nor inherits them.

Topology receipt: `logs/e256-vnext-topology-gate.json`
(schema `E256-VNEXT-TOPOLOGY-GATE-1`, status `OPEN_PROGRESS`,
`results_sha256 = cc1ca362872c0a822270a3f8ad7b18525301aac54f7b3b59bf819aa6c10635fe`).
Reproduce: `make e256-vnext-topology` / `make e256-vnext-topology-check`.
Audit row: **E256-061**. Ledger: `directives/e256-audit.md`.

## 0. Scope and decision discipline

This is a clean-sheet review from root-secret acquisition through rotor
construction, key derivation, per-position scheduling, framing, authentication,
replay handling, hardware, lifecycle, and offline Red/Blue evolution.
Compatibility, reciprocity, and historical resemblance are not requirements.

“Better” means a design with a smaller and clearer trusted surface, explicit
security boundaries, fewer structural invariants, standard protocol components,
reproducible attack evidence, implementable side-channel policy, and a credible
path to independent review. It does **not** mean more rotors, more state, better
avalanche plots, lower optimizer fitness, or a larger key label.

The safest comparator is always **standard AEAD without E256**. E256-vNext is
allowed to survive as an optional inner research transform only if it adds a
specific, measured defense or research value without weakening the standard
boundary. `NO ACCEPTABLE CANDIDATE` and “use AEAD only” are valid final outcomes.

### 0.1 Accepted research constraints

The workspace owner delegated architecture selection under these constraints.
They authorize staged specifications and attack harnesses, not a production
cipher or a security claim. Every implementation must cite the accepted revision
of this record and must not silently fill an OPEN choice.

| ID | Proposed decision | Rationale and consequence |
|---|---|---|
| **D0 — security boundary** | Use a reviewed, standard, nonce-misuse-resistant AEAD as the external confidentiality and integrity boundary, with an independent directional key. Keep an AEAD-only suite as the baseline. | E256 currently has no independent cryptographic acceptance. A custom inner transform must never substitute for standard authenticated encryption. Exact AEAD remains OPEN. |
| **D1 — topology** | Replace reciprocal mirror traversal with independently derived ingress and egress stacks: `B_i(A_i(P_i) XOR M_i)`. | Removes the proven conjugated-XOR involution and 128-pair codebook structure. Encryption and decryption intentionally differ. |
| **D2 — historical constraints** | Remove the fixed-point-free involutive plugboard requirement. Use arbitrary validated bijections or fold boundary permutations into the independent stacks. | Reciprocity and historical stecker behavior constrain the map without supplying a demonstrated modern security property. |
| **D3 — rotor namespace and depth** | Permit 256 **logical** rotor IDs, but derive/cache only selected tables. Start research at 4 ingress + 4 egress; choose final depth only from blinded attack evidence. Never infer security from the number 256. | The current receipt shows no structural improvement from 1 through 256 mirrored active rotors, while path cost rises from 10 to 514 dependent lookups at 4 versus 256. The 4+4 split matches the current ten-lookup depth; it is a candidate, not an accepted optimum. |
| **D4 — schedule** | Remove the LFSR/NLFF from the security-critical vNext schedule. Derive selections, order, offsets, mask material, and random-access state from a standard keyed PRF/XOF over canonical context and counters. Historical stepping may remain only in a separately labeled laboratory profile with no security claim. | Maximal period and empirical balance do not establish unpredictability. A counter-based schedule is easier to domain-separate, parallelize, reproduce, bound, and analyze for reset/reuse. Exact primitive and schedule granularity remain OPEN. |
| **D5 — key tree** | Perform one explicit standard extract from the root or handshake secret, then domain-separated expansion into independent profile, ingress, egress, schedule, mask, AEAD-send, AEAD-receive, and any key-confirmation material. Bind the complete suite/profile and protocol transcript. | Prevents implicit key reuse and cross-role/cross-suite ambiguity. HKDF-SHA-512 is the staged baseline, not an irrevocable choice. |
| **D6 — nonce, sequence, and direction** | Bind every operation to canonical suite/profile, session ID, role, direction, monotonically controlled sequence, nonce/tweak, and local counter. Define durable uniqueness, crash recovery, anti-rollback, replay windows, and hard per-key limits. | A random nonce API alone does not provide lifecycle safety. Misuse resistance limits damage; it does not permit intentional reuse or sequence wrap. |
| **D7 — framing and release** | Authenticate canonical metadata and lengths with the standard AEAD. Parse strictly, verify AEAD before running unauthenticated data through stateful consumers, and release no E256 plaintext before verification succeeds. | Closes malleability, parse-boundary, replay/reflection, and unauthenticated-release classes at the protocol boundary. |
| **D8 — implementation and hardware trust boundary** | Either evaluate rotors in a constant-time/oblivious manner or explicitly exclude local address/power observers. When the hardware threat model includes the host bus, generate schedule and mask inside the trusted hardware boundary rather than transporting per-byte mask material. Require atomic shadow-bank load, profile validation, integrity/error detection, lifecycle lock, erase/invalidation, fault tests, and measured leakage work before any physical-security claim. | Secret-dependent table addresses and host-transported mask bytes can dominate the topology. Software/RTL parity alone is not side-channel or fault evidence. |
| **D9 — offline evolution only** | Generate immutable, versioned candidates offline. Use deterministic manifests, preregistered gates, positive controls, disjoint train/holdout sets, sealed Red evaluation, and explicit human promotion. Never mutate a deployed profile or silently move an alias. | Reproducibility and independent analysis require stable targets. Red/Blue evolution is research selection, not runtime polymorphism. |
| **D10 — byte-local versus standalone primitive** | Keep the independent byte topology only as an AEAD-protected inner-transform candidate. If E256 itself is expected to resist mask compromise/reuse or claim modern standalone-cipher security, create a separate wide-state candidate with cross-byte diffusion and its own analysis; do not imply that byte-local rotors provide it. | Every frozen byte state has only 256 inputs and is codebookable. A good mask can provide stream-style confidentiality, but the rotor stack does not create cross-byte diffusion. |
| **D11 — promotion and claims** | Promotion requires a new incompatible suite identity, byte-exact specification, two independently authored implementations, externally held KATs, calibrated Red controls, protocol and hardware evidence, independent cryptographic review, and human receipt review. | Passing local tests, random-looking statistics, or one failed attack cannot establish production suitability or a security-bit claim. |

### 0.2 Choices deliberately left OPEN

These choices need discriminating experiments or external review. They must not be
chosen merely to start coding.

1. **Exact standard AEAD.** Compare standardized misuse-resistant candidates,
   implementation availability, data limits, hardware support, side-channel
   properties, and protocol requirements. Do not invent a custom mode.
2. **Rotor permutation family.** Compare at least:
   - unbiased, key-derived random permutations with deterministic quality gates;
   - a fixed audited nonlinear permutation family with key-derived affine or
     positional conjugations; and
   - AEAD-only / no rotor layer.

   Random permutations are easy to derive but have variable DDT/LAT quality and
   secret-table address risk. A fixed algebraic family permits stable bounds and
   constant-time designs but introduces a smaller, more structured family.
   Preregister exact differential, linear, algebraic, equivalent-key,
   cycle/slide, implementation, and leakage gates before selecting either.
3. **Active depth.** Compare at least 1+1, 2+2, 4+4, 8+8, and 16+16 with
   random-permutation controls, reduced/weak positive controls, and sealed
   holdouts. Select the smallest depth that changes attack scaling beyond the
   linear cost paid by honest users. The present 4+4 value is only a starting
   profile.
4. **Schedule/mask primitive and granularity.** Select a standard PRF/XOF and
   define whether rotor selection is per session, message, block, or position.
   Preserve random access and exact counter limits. Use separate keys or
   unambiguous domains for schedule and mask outputs.
5. **Handshake and file-key suites.** Use a standard authenticated key exchange
   and standard transcript binding. If post-quantum or hybrid operation is
   required, use reviewed standardized components and a reviewed combiner. File
   passphrases require a random salt and reviewed memory-hard KDF. No quantum or
   post-quantum strength is claimed here.
6. **Wide-state research family.** No round function, state width, diffusion
   matrix, round count, or security claim is selected. Those require a separate
   design record and analysis rather than an undocumented patch to this byte
   topology.
7. **Physical implementation technique.** Bitslicing, masked tables, oblivious
   scan, dedicated constant-time permutation logic, and trusted-memory options
   require measured area/throughput/leakage/fault comparisons.

### 0.3 Recommended end-to-end data path

The proposed packet path is:

```text
standard authenticated root/handshake secret
    |
    +-- canonical transcript + suite/profile + identities/roles
    |
    `-- KDF-Extract
          |
          +-- K_rotor_in[direction]
          +-- K_rotor_out[direction]
          +-- K_schedule[direction]
          +-- K_mask[direction]
          +-- K_AEAD[direction]
          `-- K_confirm / exporter material only where the protocol requires it

P, canonical context, sequence, local counter
    |
    `-- inner E256 candidate: Y_i = B_i(A_i(P_i) XOR M_i)
          |
          `-- standard AEAD.Seal(K_AEAD, nonce, Y,
                                 AAD = canonical authenticated header)
                |
                `-- wire: canonical header || authenticated ciphertext/tag
```

The canonical authenticated header must include at least the wire version,
algorithm/suite and profile identity, endpoint identities or stable role-bound
identifiers where applicable, session ID, direction, sequence, nonce/tweak,
lengths, and application AAD. The byte encoding, field order, limits, unknown
field policy, and endianness belong in the eventual byte-exact specification.

Receive order is fail-closed:

1. Parse bounded canonical framing without constructing E256 state.
2. Check suite/profile support and cheap resource limits.
3. Apply replay prefiltering only in a way that cannot authenticate a forgery.
4. Verify the standard AEAD over the full canonical header and ciphertext.
5. Atomically commit receive-sequence/replay state as defined by the protocol.
6. Run `P_i = A_i^-1(B_i^-1(Y_i) XOR M_i)` with the authenticated context.
7. Release plaintext only after all checks succeed.

For file encryption, the same principles apply with a random per-file salt,
memory-hard password derivation when passwords are used, authenticated metadata,
and an explicit format/suite/profile tuple. For sessions, standard AKE forward
secrecy, rekey policy, crash behavior, and directional state must be specified;
E256 must not improvise those properties.

### 0.4 Inner-transform security target

For a fixed context and position, the proposed inner map is:

```text
encrypt:  C_i = B_i( A_i(P_i) XOR M_i )
decrypt:  P_i = A_i^-1( B_i^-1(C_i) XOR M_i )
```

`A_i` and `B_i` are independently keyed bijections and `M_i` is generated from a
separate standard PRF/XOF domain. The intended analysis target is a reduction of
nonce-respecting inner confidentiality to mask-PRF security and uniqueness of the
canonical PRF input. Such a reduction has **not** been written or reviewed. It
would not provide integrity, nonce-misuse safety, side-channel resistance, or a
standalone security claim for the rotors.

This target has an important consequence: under an ideal fresh mask, rotor count
is not the confidentiality lever. Rotors can change the representation and may
supply defense-in-depth under a precisely stated partial-compromise model, but
that value must be measured. If no such value survives Red evaluation, the
AEAD-only baseline wins.

### 0.5 Wide-state fork, if standalone E256 is required

A byte-local transform cannot honestly be relabeled as a modern wide primitive.
If the research goal requires E256 to remain meaningful after mask compromise or
reuse, the project must separately investigate a tweakable wide-state design,
for example a substitution/permutation or Feistel family with:

- at least a 128- or 256-bit state rather than independent one-byte maps;
- independently reviewed nonlinear layers;
- explicit invertible cross-byte diffusion;
- round keys/tweaks bound to profile, direction, nonce, and block counter;
- differential/linear trail bounds and reduced-round positive-control attacks;
- integral, algebraic, impossible-differential, meet-in-the-middle,
  related-key/tweak, rebound, slide, and invariant-subspace evaluation; and
- a separate design identity, fixtures, implementations, and review.

This list is a research requirement, not a proposed round function. No formula,
round count, or theorem is being introduced by this record.

### 0.6 Offline Red/Blue evolution contract

Offline evolution may search rotor families, schedules, active depths, or future
wide-state candidates only under this contract:

1. Freeze an immutable candidate manifest, source hash, profile bytes, domains,
   toolchain, seeds, budget, and train/holdout split before scoring.
2. Include planted weak candidates and reduced variants that the Red harness must
   recover. Failure to recover a positive control invalidates the campaign.
3. Keep sealed holdouts and attack budgets unavailable to candidate selection.
4. Retain every clean negative and every failed candidate; do not report only the
   winner.
5. Grade attack data/time/memory/scaling, equivalent keys, reset/reuse, related
   contexts, mask compromise, multi-user behavior, and side-channel cost.
6. Treat avalanche, entropy, balance, large periods, and optimizer failure only
   as diagnostics, never as confidentiality evidence.
7. Require an explicit human promotion action. Runtime mutation and automatic
   promotion are forbidden.
8. Permit `NO ACCEPTABLE CANDIDATE` without weakening a gate after results are
   known.

### 0.7 Research and implementation order

The workspace owner accepted D0–D11 as research constraints and delegated OPEN
parameter selection. That authorizes preregistered specifications and attack
harnesses, not a production cipher. The first rotor/schedule rejection campaign
has now landed; it security-selected no byte-local depth and authorizes no suite
implementation.

Work therefore proceeds in this order:

1. Preserve the byte-local 1+1 affine-AES/full-counter result only as the next
   attack/control baseline; do not freeze it as a suite.
2. Write a separate wide-state design record and threat model before introducing
   any cross-byte round function.
3. Compare that design against AEAD-only and a separately keyed standard
   primitive under the same compromise model and honest-cost accounting.
4. Preregister reduced-round, trail, related-state, equivalent-key, and
   mask-compromise attacks with planted weak controls.
5. Write a byte-exact specification only for a candidate that survives those
   model gates.
6. Implement two independently authored software references against externally
   held KATs.
7. Implement standard AEAD framing, then adversarial parser, replay, rollback,
   misuse, multi-user, and lifecycle tests.
8. Implement RTL/hardware only after software semantics freeze; add formal bus,
   atomic-load, integrity, erase, fault, and leakage evidence.
9. Obtain independent cryptographic review and repair findings.
10. Only then consider a new suite/profile promotion and, separately, a human-
    checked C/H/N claim change.

## 1. The measured problem in the staged v3 topology

E256-v3/gen0 fixture-v5 computes, at absolute byte counter *i*:

```text
C_i = A_i^-1( A_i(P_i) XOR M_i )
```

where `A_i` is the plugboard plus the offset forward rotor stack, and `M_i` is the
HMAC-SHA256 center-mask byte. `A_i^-1` is the mirrored reverse stack plus the
involutive plugboard.

Because the same permutation appears on both sides, the whole byte map at a
frozen state is a **conjugation** of XOR-by-constant:

```text
S_i = A_i^-1  o  T_{M_i}  o  A_i        T_m(u) = u XOR m
```

Conjugation preserves cycle type, and for `m != 0` the map `T_m` on 256 points is
exactly 128 disjoint transpositions. Therefore, for **every** key and **every**
active rotor count:

- `M_i = 0`  ⇒ `S_i` is the identity.
- `M_i != 0` ⇒ `S_i` is a fixed-point-free involution with exactly 128 two-cycles.
- `S_i(S_i(x)) = x` unconditionally.

The receipt verifies this exhaustively over all 256 masks × all 256 inputs, 64
independent keys per rotor count, at rotor counts **{1, 4, 8, 16, 256}**, with a
literal per-rotor walk cross-checked against the collapsed algebra. It also
anchors the model to the exact staged fixture-v5 tuple: 1024/1024 trace rows agree
on recomputed center mask, byte output, center input/output, and
ciphertext→plaintext round trip.

Consequences measured in the same receipt:

| Property | Mirrored | Independent stacks | Random permutation |
|---|---|---|---|
| Two-query same-state distinguisher advantage | **0.99195** at every rotor count | 0.00015–0.00115 | control 0.00805 |
| Involution rate | 1.0 | 0.0 | 0.0 |
| Mean fixed points | 0.0 | 1.031 | 0.828 (Poisson(1) ≈ 1.0) |
| Same-state codebook queries | **128** | 255 | 255 |
| Dependent lookups/byte | `2R + 2` | `R_in + R_out + 2` | — |

**The decisive negative result: rotor count is not a lever for this structural
property.** Going from 4 to 256 active mirrored rotors leaves the distinguisher
advantage unchanged at 0.99195 while raising the byte path from 10 to 514
dependent lookups (~87.9 µs/byte versus ~1.8 µs/byte in the harness). More
mirrored rotors buy no structural improvement and cost throughput, area, and
side-channel surface.

The mask-recovery identity explains why. Exhaustively verified, exactly one mask
maps a given `P` to a given `C`, and it is:

```text
mirrored:    M = A(P) XOR A(C)
independent: M = A(P) XOR B^-1(C)
```

Neither formula contains a rotor-count term. Given a good fresh PRF mask, the
ciphertext byte is uniform at one rotor and at 256; the stack changes *where* the
mask lands, not how unpredictable it is.

## 2. Candidate topology

The topology proposal is:

```text
encrypt:  C_i = B_i( A_i(P_i) XOR M_i )
decrypt:  P_i = A_i^-1( B_i^-1(C_i) XOR M_i )
```

Required properties if **D1–D4** are accepted:

1. `A_i` and `B_i` derive from **separate KDF domains** and separate logical
   rotor banks. `B_i` is never `A_i^-1`.
2. Input and output permutations are **arbitrary validated bijections**, not
   involutions. The fixed-point-free historical plugboard policy is removed.
3. Encryption and decryption are deliberately **different** operations.
   Reciprocal self-decryption is removed as a feature.
4. `M_i` and position/selection material come from separate standard PRF/XOF
   keys or unambiguous domains bound to profile, session, nonce/tweak, direction,
   sequence, and absolute counter.
5. LFSR/NLFF stepping is not part of the security-critical vNext profile.
6. A 256-entry logical rotor namespace is permitted. Only the selected tables
   are derived/materialized unless measured hardware caching justifies more.
7. The construction remains inside a reviewed standard AEAD with an independent
   directional key and is never presented as standalone authenticated encryption.

### 2.1 Rotor/schedule rejection result

The earlier 4+4 value was only an equal-lookup starting point. The first
bake-off receipt (`8d286b…e9655e5`) was invalidated before claim or promotion
after `semantic-review/2026-09-07-200027-pr-0.md` found that the runner did not
execute its complete frozen contract. Research selection now uses the refrozen,
end-to-end campaign:

- Preregistration:
  `directives/e256-vnext-bakeoff-preregistration.json`, SHA-256
  `ebeb9e48d63ffb412b67ddbb20bce66086238b9afc26f8f56d0b0eea809b1fcd`.
- Receipt: `logs/e256-vnext-rotor-schedule-bakeoff.json`, schema
  `E256-VNEXT-ROTOR-SCHEDULE-BAKEOFF-1`, deterministic-payload SHA-256
  `fd54809cbd12de9d6f14151bcd401232aae765b72cb8368128ea54bdfa7b7197`.
- Reproduce: `make e256-vnext-bakeoff` / `make e256-vnext-bakeoff-check`.
- Semantic follow-up: `semantic-review/2026-09-08-075406-pr-0.md` is
  **APPROVED** with zero actionable findings after targeted drift, fail-closed,
  active-prefix, rank, and D0–D11 binding probes. This AI review is not human
  claim review or independent cryptographer acceptance.
- Scope: **46,080** ordinary complete state maps across key-derived random and
  affine-AES rotor families; common-endpoint, full-counter-reselection, and
  counter-wrapper schedules; depths 1+1, 2+2, 4+4, 8+8, and 16+16; 16 key
  labels, two streams, two directions, two replications, twelve counters, and
  all 256 inputs per state. The counter corpus includes both
  `65535→65536` and `4294967295→4294967296`. A separately counted **7,680**
  reset-endpoint maps make **3,840** comparisons for
  `(sequence=7,counter=65536)→(sequence=8,counter=0)`. Exact DDT/LAT/ANF and
  related-state diagnostics use the pinned subsets in the preregistration.
- Contract execution: operational fields come from the authenticated
  preregistration; `rotor/in`, `rotor/out`, schedule, mask, and control domains
  are checked; depth-state digests serialize active prefixes only; the embedded
  D0–D11 definitions and the immutable architecture-authorization section are
  hash-bound without hashing this mutable result section.
- Controls: all eight planted weaknesses traverse the shared derivation,
  observation, summarization, and rejection paths where applicable. The ideal
  independent null traversed 9,216 ordinary canonical contexts plus 1,536
  reset endpoints with no exact rejection. All 64 pinned key-bit-flip checks,
  required direction comparisons, 16/32-bit boundaries, and reset comparisons
  passed; control IDs and coverage match the frozen manifests exactly.
- Baselines: PRF-mask-only ran over the same canonical contexts and confirms
  one known/chosen plaintext-ciphertext pair recovers a repeated-state byte
  mask; AEAD-only records zero inner-transform work and no byte-map metric.
  Neither is a simulated AEAD-security experiment. Q4 therefore retains no
  rotor for production absent a later, separately frozen independent-key
  compromise experiment that beats both baselines under common cost accounting.
- **Common endpoints are rejected.** When only the mask changed, every tested
  unequal-mask adjacent relative map had the exact 128-transposition
  involution signature, while repeated masks produced complete state/map
  collisions. Removing the reflector is not enough if `A_i` and `B_i` are held
  fixed across positions.
- All 20 candidate family/schedule/depth cells avoided the frozen exact
  hard-rejection conditions. That is a bounded failure to reject, **not** a
  security result.
- **No depth was security-selected.** Every tested depth retains the 255-query
  repeated-state byte-codebook ceiling and changed none of the preregistered
  bounded attack scaling beyond increasing honest rotor evaluations from 2 at
  1+1 to 32 at 16+16.

The machine verdict is
`NO_BYTE_LOCAL_PRODUCTION_CANDIDATE_RESEARCH_BASELINE_RETAINED`. A tested
structured schedule/family/numeric-depth tie-break retains
`aes_affine_v1|full_counter_reselect_v1|1+1` only as the smallest next attack
target with a plausible tableless implementation path. It is **not** an
accepted cipher, profile, active-depth security result, or production option.
AEAD-only remains the production baseline. The next design tranche is the
separate wide-state fork required by **D10**.

## 3. What is proven, and what is not

Proven by the current topology receipt:

- **T1 (structure invariance).** The mirrored fixed-state map is the identity at
  mask 0 and a fixed-point-free involution otherwise, for all tested rotor counts
  including 256. The mask/input domain is exhaustive; key sampling is 64 per row.
- **T2 (mask uniqueness).** Exactly one mask maps `P` to `C`, with the closed
  forms above. Rotor count is absent.
- **M1 (bounded distinguisher).** Two queries at one frozen state detect the
  mirrored construction with measured advantage ≈ 0.992, invariant in tested
  rotor count. The candidate is consistent with the random control under this
  one test.
- **M2 (bounded codebook result).** The involution halves same-state codebook
  cost, 128 versus 255 queries in the modeled setting.

Explicitly **not** proven:

- No IND-CPA/AEAD proof, no HKDF/HMAC proof, no PRF reduction, no standalone
  rotor security, and no external cryptanalysis.
- The distinguisher assumes a repeated-state or chosen-plaintext oracle at a
  frozen position. It is **not** a decrypt of nonce-respecting traffic and
  implies no plaintext recovery against E256-v3 beneath a standard AEAD.
- Passing one two-query control is not pseudorandomness or security. The
  candidate has no independent implementation, external KATs, RTL,
  side-channel/fault evidence, or cryptographer acceptance.
- Cycle statistics over 64 keys are consistent with random-permutation behavior;
  they are not a pseudorandomness proof.
- The measured timing values are harness-local advisory figures, not portable
  performance claims.
- No effective security-bit strength is computed or implied. “E256” denotes the
  256-symbol alphabet, not 256-bit security.

## 4. Gates before any candidate may be promoted

1. **Architecture direction (satisfied for research only).** D0–D11 are accepted
   as research constraints and OPEN selection is delegated. This does not
   authorize a suite, production implementation, promotion, or claim.
2. **Byte-exact specification.** Freeze immutable profile bytes, complete domain
   registry, key tree, canonical context, state/update order, parser limits,
   nonce/sequence/counter rules, data limits, and stated security notions.
3. **Rotor-family selection.** Preregister and run exact DDT/LAT, algebraic,
   cycle, equivalent-key, trail, implementation, and leakage comparisons against
   controls and the AEAD-only baseline.
4. **Construction analysis.** Attempt a nonce-respecting reduction to the chosen
   PRF assumptions; account for reachable state, related contexts, weak keys,
   equivalent keys, reuse, resets, multi-user scaling, and mask compromise.
5. **Attack matrix.** Differential, linear, integral, cycle/slide, fast
   correlation, SAT/SMT, algebraic, cube, guess-and-determine, state recovery,
   TMTO, related-key/nonce/tweak, multi-user, reset/reuse, and protocol attacks.
   Planted weak and reduced positive controls must be recovered.
6. **Active-depth selection.** Compare 1+1 through 16+16 under blinded campaigns.
   Promote the smallest depth with a reproducible improvement in attack
   data/time/memory/scaling on sealed holdouts. Linear slowdown, avalanche, and
   entropy output do not qualify.
7. **Independent implementation.** Two independently authored implementations,
   immutable externally held KATs, strict parsers, fuzzing, differential tests,
   constant-time review, and toolchain manifests.
8. **Protocol.** Standard AEAD over canonical metadata, durable directional
   nonce/sequence state, anti-rollback, replay windows, transcript binding,
   per-key limits, rekey, and no unauthenticated plaintext release.
9. **Hardware.** Defined trust/threat boundary, internal schedule/mask generation
   when required, atomic shadow banks, profile validation, integrity/ECC policy,
   lifecycle and erase, formal bus properties, post-synthesis parity, then TVLA
   and fault work.
10. **Independent review and promotion.** Repair external findings, retain
    negatives, make a human suite decision, assign a fresh incompatible identity,
    and only then consider a separately human-checked claim row.

Selection may return **NO ACCEPTABLE CANDIDATE**. No candidate silently replaces
an active profile.

## 5. Alternatives considered

| Alternative | Decision in this proposal | Reason |
|---|---|---|
| Keep reciprocal mirrored topology | Reject | It has an exact involution/cycle invariant and cheap same-state distinguisher. |
| Add more mirrored active rotors, up to 256 | Reject | Exhaustive receipt shows the same structural result while dependent lookup cost rises sharply. |
| Preserve the involutive plugboard | Reject as a security requirement | Historical reciprocity is not a clean-sheet requirement and constrains the permutation family. |
| Keep LFSR/NLFF as security-critical schedule | Reject for vNext | Period, balance, and local empirical tests do not provide a standard PRF assumption; mutable sequential state complicates reset and random access. |
| Use custom encrypt-then-MAC framing as the final boundary | Reject | Standard AEAD avoids a new composition and framing proof obligation. |
| Mutate/evolve deployed profiles | Reject | It destroys immutable identity, reproducibility, KAT custody, and independent review. |
| Adopt key-derived random rotor tables without quality/leakage gates | Leave OPEN; do not adopt by default | Their cryptographic and implementation distributions must be compared with audited structured alternatives. |
| Add an improvised cross-byte mixer to the byte topology | Reject | A standalone wide primitive needs a separate design and attack program, not an undocumented patch. |
| Require E256 inside every production suite | Reject | AEAD-only remains the control and may be the correct final architecture. |

## 6. Consequences if accepted

- E256-vNext is intentionally incompatible with v1, v2, and staged v3.
- Reciprocity, one-machine encrypt/decrypt, historical plugboard constraints, and
  LFSR/NLFF security dependence disappear from the candidate.
- Independent ingress/egress tables increase derivation/storage complexity but
  remove the measured mirror invariant at equal initial lookup depth.
- Counter-based state permits random access and parallelism but makes canonical
  context, uniqueness, and key/data limits mandatory.
- Standard AEAD remains the security boundary, so E256 is defense-in-depth or a
  research object until it earns a narrower claim.
- Side-channel-safe rotor evaluation may be substantially more expensive than
  direct table indexing. That cost cannot be omitted from candidate selection.
- Offline evolution becomes more rigorous and less autonomous: profiles remain
  immutable, negative evidence remains printed, and humans control promotion.
- The project may conclude that AEAD-only is better, or that a separate
  wide-state family is needed. Neither outcome is a failure of the research.

## 7. Non-implications

- This does not claim E256-v3 is broken in deployment. It identifies a structural
  property under a stated repeated-state/chosen-input model.
- This does not claim the independent topology is secure. It removes one measured
  invariant and creates new keying, implementation, and review obligations.
- This does not claim rotors add security beyond the PRF mask or outer AEAD.
- This does not claim that 4+4 is optimal or that 256 logical IDs add entropy.
- This does not claim any password, handshake, post-quantum, side-channel, fault,
  or hardware property.
- This does not claim a standalone wide-state E256 design exists.
- This does not compute or imply a security-bit value, “unbreakable” status,
  production readiness, or protection against unknown attacks.
- Nothing here closes E256-003, E256-061, any release gate, or promotes a C/H/N
  row. Human review of receipts and claim language remains mandatory.
