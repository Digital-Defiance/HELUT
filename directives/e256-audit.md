# E256 hardening ledger

Status: active engineering ledger; E256 is experimental and must not protect real data.

This file records the August 2026 audit findings and the work required to close them. A passing test or failed attack is not a security proof. No entry may be marked `CLOSED` without a reproducible receipt and review of the claim language it affects.

## Compatibility decision

The existing implementation, generated artifacts, fixtures, and receipts are one quarantined suite:

- **E256-v1/gen0...gen5**: historical only; all generation grading is contaminated by the singular LFSR transition. Gen5 is additionally invalidated by a formula-invariant `0.375` correlation to its linear tap.
- **E256-v2/gen0**: the first clean candidate. It is a new suite with a corrected and independently checked transition, new KDF/transcript domains, immutable profile binding, new fixtures, new RTL module/artifact names, and no ciphertext compatibility with v1.
  - **Live fixture-v6:** `E256/v6/gen0/c2abdbe580bad275838fc2650f81fdb14cb5ae3865cb74c5087f488ca51a35b9/fixture-v6`. Golden: `Fixtures/enigma256_golden`. Core: `Hardware/RTL/Enigma256/enigma_256_core.v`.
  - **Historical fixture-v4 (not the loaded profile):** `E256/v2/gen0/fa246e9cba9009a4799e5a81722a9b14e9a67293d9621b45985c5f3e620865d4/fixture-v4`, kept unmodified under `Fixtures/Historical/Enigma256/`. Its 49/49 suite and formal 1/1 stay bound to that tuple.
  - **Historical fixture-v3 (non-loadable):** `Fixtures/Historical/Enigma256/E256-v2-gen0-2a9f54c70a1619805a911758158f1e2204b0fd96c35102a9db5f4575aeb40cb0-fixture-v3`.
- **E256-v2/gen1+**: may exist only after deterministic candidate generation and train/holdout attacks. Candidate selection is allowed to return `NO ACCEPTABLE CANDIDATE`.

The compatibility key is:

```text
(cipher family, suite version, generation, profile hash, fixture schema version)
```

A generation integer alone is never a compatibility identifier. Existing strings containing `-v2` are KDF-revision labels inside the quarantined implementation; they do not identify the new E256-v2 suite.

Normal encryption and wire APIs must never select, detect, or fall back to E256-v1. If legacy recovery is retained, it must be explicit, offline, decrypt-only, loudly unsafe, and isolated from ordinary constructors.

## Acceptance order

1. Quarantine v1 and disable mutation paths that rewrite canonical artifacts.
2. Define one immutable v2/gen0 profile and strict compatibility encoding.
3. Correct and independently verify the state transition.
4. Remove the structural fixed-point leak while preserving reciprocity.
5. Freeze strict long-form KATs and negative vectors.
6. Reach Swift-to-RTL state-trace parity and pass adversarial RTL protocol tests.
7. Harden file, session, trust, replay, parser, and lifecycle behavior.
8. Run deterministic Red/Blue attacks with positive controls and holdout data.
9. Freeze the algorithm and KAT contract.
10. Only then obtain an independently authored and accepted portable CPU-only implementation plus immutable external KATs; in-tree Rust parity is necessary evidence but is not independent acceptance.

The in-tree Rust consumer is not a GPU, Metal, FPGA, or FHE implementation, and its fixture-v4 parity is not an independently accepted external implementation or KAT. A future independent integer reference, file codec, CLI, KAT consumer, and hardware-output verifier must not author or mutate canonical vectors.

## Status vocabulary

- `OPEN`: confirmed or required; no complete fix receipt.
- `IN PROGRESS`: implementation is underway but has not passed all gates.
- `QUARANTINED`: retained only as labeled historical evidence and unavailable for normal use.
- `DEFERRED`: intentionally waits on a prerequisite.
- `CLOSED`: fixed, validated, documented, and reviewed.

## A. Cryptographic construction and generation

| ID | Severity | Status | Finding | Required action and closure receipt |
|---|---|---|---|---|
| E256-001 | Critical | CLOSED | The left-shift/MSB `0xD800000000000000` transition is singular: rank 63 after one clock, rank 5 after 59; low 59 bits become zero; surviving image cycle is 31; about 1/32 sampled seeds lock at zero. | Use the verified right-shift/LSB convention or independently derive a correct reciprocal mask. Require GF(2) rank 64, nonzero preservation, inverse/known vectors, exact order checks for factors `{3,5,17,257,641,65537,6700417}`, and Swift/RTL state-trace parity through at least 1,024 clocks. |
| E256-002 | Critical | QUARANTINED | Every gen0...gen5 empirical grade walked the broken recurrence. Gen5's reported `0.5161` rate is the collapse signature `16/31`, not evidence of successful breeding. | Label all old profiles, logs, fixtures, generated cones, and `blue_hold` rows E256-v1. Remove them from normal profile selection. Start E256-v2 at gen0 with new paths and domains. |
| E256-003 | Critical | OPEN | Live fixture-v4 implements `A_i^-1(A_i(x) XOR k_i)` with a profile-bound HMAC-SHA256 counter schedule. Bounded validation reports zero-plaintext equality `260/65536 = 0.00396729` (`z=0.250`), reciprocal decrypt, and Swift/direct-RTL/internal-Rust/AXIS/LITE parity, but human acceptance is pending; AI semantic review does not close this finding. | Keep E256-003 open until human review accepts the construction, domains, absolute-counter exhaustion behavior, and claim boundary. Preserve the fixture-v4 receipt as bounded implementation/parity evidence only—not IND-CPA, an HMAC-security proof, external cryptanalysis, or production acceptance. |
| E256-004 | Critical | CLOSED | `cubic6: abc XOR de XOR f` equals `f` with probability 11/16, normalized correlation 0.375. Retapping cannot remove this formula defect. | Reject the formula class with an exact truth-table/Walsh gate. Do not promote retapped cubic6 candidates. Use a justified construction or a reviewed schedule primitive. |
| E256-005 | Critical | OPEN | Generation/profile selection is a mutable process-global value and can change between day derivation, message derivation, and individual bytes. | Capture an immutable full profile in `Enigma256Context`, message state, machine, SoftBus, fixtures, framing, and logs. Remove cryptographic reads of `Enigma256Generation.current`. Test that changing any CLI default cannot affect an existing context or stream. |
| E256-006 | High | OPEN | Current KDF labels bind only a generation integer inconsistently; existing `-v2` labels can be confused with the new suite version. | Introduce unambiguous v2 domains binding family, suite, generation, purpose, and profile hash for day, message, mask/schedule, MAC/traffic, handshake, and fixtures. Prove v1/v2 cross-open failure with tests. |
| E256-007 | High | CLOSED | The breeder uses `SystemRandomNumberGenerator`, one trajectory/window, balance and pairwise phi only, and can crown the least-bad candidate. | Use a recorded deterministic seed, complete candidate manifest, multiple nonzero train seeds, disjoint holdout seeds, formula/Walsh gates, autocorrelation, state-bit correlation, Berlekamp-Massey/linear-complexity checks, and explicit `NO ACCEPTABLE CANDIDATE`. |
| E256-008 | High | IN PROGRESS | Candidate mutation and campaign application rewrite only subsets of canonical Swift/RTL/fixture artifacts. | Disable destructive apply during restart. Replace it with atomic generation into a versioned staging directory, full artifact/hash manifest, complete parity validation, then an explicit promotion step. |
| E256-009 | High | IN PROGRESS | Campaign JSON records only taps `a,b,c`, losing `d,e,f`; historical cubic candidates cannot be reconstructed. | Record complete formula, all taps, parent/profile hashes, recurrence, deterministic RNG seed, budgets, train/holdout sets, tool versions, outputs, and verdict. |
| E256-010 | High | CLOSED | Gen1/gen2 never had stable named source profiles; generation IDs are arbitrary integers rather than versioned profiles. | Replace implicit lineage semantics with strict suite/profile types and canonical profile bytes. Reject unknown profiles rather than decoding arbitrary IDs. |
| E256-011 | Medium | OPEN | All-zero seeds are silently coerced to one in multiple layers, hiding malformed state and preventing strict interop. | Define one zero-state policy in the profile. Derivation may use deterministic rejection/remapping; external fixtures/MMIO must reject invalid zero state and report an error. |
| E256-012 | Medium | OPEN | Modulo reduction biases Fisher-Yates and rotor selection. | Use rejection sampling or a reviewed uniform bounded sampler driven by the frozen schedule. Add distribution unit tests; do not present them as cryptanalytic evidence. |

## B. File, authentication, wire, and trust

| ID | Severity | Status | Finding | Required action and closure receipt |
|---|---|---|---|---|
| E256-013 | Critical | OPEN | The shipping file command emits unauthenticated version-1 containers; a ciphertext mutation decrypts successfully into altered plaintext. | Stop v1 emission and ordinary acceptance. Add canonical authenticated v3 framing and bit-flip/truncation/extension/cross-suite rejection tests. Keep any legacy recovery in a separate unsafe decrypt-only command. |
| E256-014 | Critical | OPEN | Version-2 HMAC covers only `nonce || ciphertext`; changing nonce length shifts the parse boundary without changing authenticated bytes. | Authenticate canonical header and lengths: magic, format/suite/profile tuple, direction, session ID, sequence, nonce length/value, ciphertext length/value, and associated data. Verify before constructing cipher state. |
| E256-015 | Critical | OPEN | Default hybrid identity/trust behavior accepts unpinned peers; classical fallback can be unauthenticated, permitting active MITM. | Fail closed without pinned/certified/persisted-TOFU identity. Require explicit unsafe opt-in for unauthenticated compatibility modes. Test active identity substitution and downgrade rejection. |
| E256-016 | High | OPEN | No receive sequence, replay window, direction-specific key, or session identifier prevents replay/reflection. | Derive independent send/receive traffic keys and bind direction, session ID, and monotonically checked sequence into each authenticated frame. Add replay, reorder-window, reflection, and cross-session tests. |
| E256-017 | High | OPEN | Empty nonce can pass parsing and then trigger a `precondition`, creating a remotely reachable process crash. | Replace externally reachable preconditions with typed validation errors. Enforce fixed/bounded nonce length before allocation, profile derivation, or authentication. Fuzz malformed containers and frames. |
| E256-018 | High | OPEN | HELLO/ACK signatures do not bind a complete cumulative transcript, both identities, both flights, and all negotiated parameters. | Define a canonical transcript hash and sign/verify role, identities, ephemeral keys, suite/profile, options, and prior flights. Test unknown-key-share, role swap, downgrade, and message-splice attempts. |
| E256-019 | High | OPEN | PSK traffic is an offline password verifier; file mode uses a constant fallback salt and accepts passphrases on process-visible command lines. | Use random per-container salts and a memory-hard reviewed password KDF with recorded parameters. Prefer secure prompt/file-descriptor input. Document the offline-guessing model and add weak-parameter rejection. |
| E256-020 | High | OPEN | Nonce tracking is process-local and send-only; random wire nonces bypass durable reuse/replay protection. | Make nonce/sequence construction part of the traffic protocol, persist where required, and enforce receive-side uniqueness/replay state. Define crash/restart behavior. |
| E256-021 | High | OPEN | Container/fixture/wire parsers lack complete canonical length/resource limits and strict field validation. | Add typed parsers with maximum sizes, exact lengths, overflow checks, duplicate/unknown-field policy, no silent defaults, and malformed-input fuzz/property tests. |
| E256-022 | Medium | OPEN | X-Wing helper code has no authenticated wire protocol integration. | Either remove it from public capability claims or define and test a transcript-bound negotiated suite after the base protocol is stable. |
| E256-023 | Medium | OPEN | Wire-session shared state has Swift sendability/concurrency hazards. | Isolate mutable session state behind an actor or proven locking discipline; enable strict concurrency checks and add concurrent close/send/receive tests. |
| E256-024 | Medium | OPEN | `burn()` releases references but does not establish zeroization across Swift value copies, heap buffers, or hardware tables. | Narrow claims to lifecycle invalidation unless a reviewed secure-memory strategy and hardware erase receipt exists. Add explicit state invalidation and post-erase access tests. |

## C. Tables, state, and software/RTL contract

| ID | Severity | Status | Finding | Required action and closure receipt |
|---|---|---|---|---|
| E256-025 | High | OPEN | Wiring constructors validate lengths only, not uniqueness, inverse relationships, involutions, or profile hash. | Add throwing validation for every table and complete table-set invariants. Reject malformed tables before context/core configuration. Include negative vectors. |
| E256-026 | High | OPEN | The current golden schema omits suite/profile/recurrence/NLFF/KDF/update-order semantics and is verified by the same implementation that writes it. | Create a strict v2 KAT schema with canonical profile bytes/hash, derivation intermediates, long streams, state checkpoints at 0/1/2/58/59/60/64/128/1024, rejection vectors, and artifact hashes. |
| E256-027 | High | OPEN | The committed 36-byte golden ends before the historical 59-clock collapse and checks final ciphertext, not internal state evolution. | Add basis-vector recurrence KATs and >=1,024-byte stream/state traces. Differential-check every accepted beat in Swift and hand-authored RTL. |
| E256-028 | High | OPEN | Fixture parsing uses `[String:Any]`, maps malformed hex to zero, coerces zero LFSR to one, and does not validate duplicate `.bin`/`.hex` artifacts. | Replace with strict `Codable` schema and typed errors; reject malformed hex/zero state/version mismatch; verify all duplicate files and rederive day/message state from KAT inputs. |
| E256-029 | High | OPEN | Swift/RTL agreement currently demonstrates shared behavior, not correctness, and all transition-bearing generated cones encode v1. | Version hand-authored v2 modules and regenerate every cone/netlist from one manifest. Prove recurrence oracle agreement independently before using Swift as KAT authority. |
| E256-030 | Medium | OPEN | SoftBus is cycle-free and cannot expose ready/valid, collision, backpressure, or lifecycle bugs. | Keep SoftBus only as a functional model. Add adversarial cycle-level RTL tests/formal properties for all bus and stream guarantees. |

## D. RTL protocol, lifecycle, and physical-security hazards

| ID | Severity | Status | Finding | Required action and closure receipt |
|---|---|---|---|---|
| E256-031 | Critical | OPEN | AXI4-Lite accepts AW and W independently but executes only same-cycle pairs. A legal AW-first/W-later transaction receives no response/write. | Add independent AW/W holding registers and internal join. Test AW-first, W-first, simultaneous, backpressure, and repeated outstanding attempts; return one response per joined write. |
| E256-032 | Critical | OPEN | AXIS table loader asserts ready while unarmed and treats any early TLAST as successful completion; the fixture-v4 expected loader count is 2,304 beats for nine tables. | Implement IDLE/ARMED/LOADING/DONE/ERROR states, accept exactly 2,304 beats, require TLAST only on beat 2,304, reject missing/early/late/extra traffic, and expose error status. Fixture-v4 friendly-path AXIS parity does not close these adversarial protocol cases. |
| E256-033 | High | OPEN | Tables are modified live; there is no shadow bank, validation, hash, or atomic commit. | Load an inactive bank, validate count/invariants/hash, then commit atomically while payload is idle. Preserve the active bank on load failure. |
| E256-034 | High | OPEN | Configuration writes, `LOAD_STATE`, table writes, and payload can race; simultaneous load/input can discard data. | Define lifecycle states and reject illegal operations with errors. Add assertions that configuration cannot alter an active message and every accepted input has exactly one output. |
| E256-035 | High | OPEN | One-entry pending input can be overwritten; no input backpressure contract protects it. | Add proper input FIFO/ready semantics or reject new input while occupied. Stress with consecutive writes and response stalls. |
| E256-036 | High | OPEN | One-entry output latch can be overwritten or expose stale data across messages. | Add output FIFO/valid-consume semantics and explicit flush on lifecycle transitions. Prove no loss, duplication, or stale cross-message output. |
| E256-037 | High | OPEN | WSTRB, invalid addresses/selectors, and conflicts are ignored while returning OKAY. | Apply byte strobes correctly; return SLVERR/DECERR for invalid or illegal operations. Mirror errors in host driver and tests. |
| E256-038 | High | OPEN | Reset/state invalidation leaves secret tables in hardware memory. | Add security erase for state and both table banks, completion status, and verification that post-erase reads/use cannot recover prior configuration. Do not claim physical zeroization without implementation evidence. |
| E256-039 | Medium | OPEN | The fixture-v4 combinational path makes ten serial asynchronous accesses across nine unique tables—plugboard on entry, four forward rotors, four reverse rotors, and the same plugboard on exit—plus center XOR and offset arithmetic. This does not match ordinary synchronous FPGA BRAM inference and limits timing. | After semantics freeze, pipeline synchronous lookup stages and carry message metadata/offset snapshots with each byte. Measure area, Fmax, latency, and sustained throughput; bounded parity and cone counts do not close this physical implementation row. |
| E256-040 | High | OPEN | Secret-dependent table addresses are directly observable; deterministic 0-3-cycle jitter is not a meaningful DPA defense. | Remove security claims for jitter. Develop and measure a constant-time/masked/oblivious lookup option or explicitly scope the threat model. Require TVLA/side-channel receipts on real hardware. |
| E256-041 | High | OPEN | No table integrity, parity/ECC, fault detection, lock bit, or tamper/error response exists. | Add integrity metadata, fault signaling, configuration lock, and fail-closed state invalidation. Run bit-flip/fault-injection simulations before claims. |

## E. Evidence, attacks, and claim hygiene

| ID | Severity | Status | Finding | Required action and closure receipt |
|---|---|---|---|---|
| E256-042 | High | OPEN | Existing LFSR tests assert two shared one-step values and enshrine the broken convention. | Replace with independent known vectors, GF(2) rank/inverse/order tests, zero/nonzero policy, long trajectory checkpoints, and Swift/RTL parity. |
| E256-043 | High | OPEN | Most tests force old gen0 while committed RTL/fixtures/documentation describe gen5; normal CLI paths may use another default. | Remove ambient defaults from tests and production. Every test/receipt must name and hash its full profile. |
| E256-044 | High | OPEN | Entropy testing encrypts pseudorandom plaintext; an identity transform can pass. Zero plaintext was excluded despite exposing the fixed-point break. | Treat `ent` as a smoke test only. Add chosen-plaintext equality/differential tests, calibrated null distributions, and known-broken positive controls. |
| E256-045 | High | OPEN | Sampled bijection/reciprocity checks are necessary functional properties but are presented too close to security evidence. | Keep structural results explicitly separate from confidentiality claims. Mechanize universal finite-table/reciprocity properties where feasible. |
| E256-046 | High | OPEN | C24's “formal certificate” samples a small deterministic set; it is not a machine proof of a universal theorem. | Rename/hedge the claim or provide an actual proof artifact. Keep sample counts and exact scope visible in claim sheet, textbook, site, and reproduction docs. |
| E256-047 | High | OPEN | TensorLUT `blue_hold` means one optimizer failed under one budget; it is not a cryptographic work factor. | Require planted-easy positive controls, repeated seeds/budgets, complete objective disclosure, and language that reports optimizer failure only. |
| E256-048 | High | OPEN | KPA gates require complete recovery and lack null distributions, multiple starts, partial-leak thresholds, and calibrated controls. | Score partial leakage and advantage, run multiple deterministic starts, include planted weak/near-weak profiles, and publish budgets and confidence intervals. |
| E256-049 | High | OPEN | No standard fast-correlation, SAT/SMT, algebraic, cube, guess-and-determine, linear-complexity, related-nonce, multi-user, fault, or side-channel campaign exists. | Build a versioned attack matrix after v2/gen0 freezes. A failed attack remains a bounded negative, never a proof. |
| E256-050 | High | DEFERRED | Internal CPU-only Rust parity now exists for fixture-v4, but it is repository-coupled; no independently authored implementation or independently accepted immutable external KAT exists. | After semantics and KATs freeze, obtain an independently authored/reviewed CPU-only implementation and immutable external vectors, then require external-Rust/Swift/RTL differential verification. The in-tree Rust consumer must not retroactively define the algorithm. |
| E256-051 | Medium | OPEN | Archived TensorLUT fragments and sampler dimensions have drifted from current sources. | Attach source/profile/tool hashes to every receipt and reject stale or mismatched inputs automatically. Preserve old receipts as labeled historical negatives. |
| E256-052 | High | OPEN | Fixture-v4 public/spec drift has been corrected against canonical C10/C24/C39 on the audited surfaces, but the corrected bounded claim boundary remains pending human review. | Keep this row open until human review accepts the corrected public/spec language: fixture-v4 is live; fixture-v3 and C39 are historical; C24 is a bounded executable certificate; internal Rust is not independent review; and “experimental/not for real data,” v1 quarantine, no IND-CPA/HMAC proof, and no external-review claims remain visible. |
| E256-053 | High | OPEN | “Schneier-solid” is not an engineering acceptance criterion and no external cryptanalysis has reviewed v2. | Use explicit invariant, protocol, implementation, attack-budget, and hardware gates. Never ship an “unbreakable,” “proven secure,” or expert-endorsed claim without the corresponding independent evidence. |
| E256-061 | High | OPEN | **Mirrored conjugated-XOR topology has a rotor-count-invariant fixed-state involution.** Because `S_i = A_i^-1 o T_{M_i} o A_i` conjugates XOR-by-constant, the frozen-state byte map is the identity at mask 0 and a fixed-point-free involution with exactly 128 two-cycles otherwise — for **every** key and every active rotor count. Measured exhaustively over all 256 masks × 256 inputs, 64 keys per row, at rotor counts {1,4,8,16,256}, anchored to shipped fixture-v5 at 1024/1024 trace rows. A **two-query** same-state distinguisher achieves advantage **0.99195**, unchanged from 1 to 256 rotors, against a 0.00805 random-permutation control. The involution also halves same-state codebook cost (128 vs 255 queries). Adding rotors is therefore not a mitigation: 256 active rotors leaves the advantage identical while raising the byte path from 10 to 514 dependent lookups. | Do not treat reciprocity as a security property, and do not attempt to mitigate by increasing active rotor count. Either (a) keep the mirrored transform strictly as an inner experimental layer beneath a reviewed standard AEAD with an independent key and state the involution as a known structural property, or (b) adopt an independent ingress/egress topology `C_i = B_i(A_i(P_i) XOR M_i)` with separate KDF domains, non-involutive input/output permutations, and a PRF-derived schedule. Candidate design and promotion gates: `directives/e256-vnext-topology.md`. Progress receipt: `logs/e256-vnext-topology-gate.json` (`E256-VNEXT-TOPOLOGY-GATE-1`, `results_sha256 cc1ca362872c0a822270a3f8ad7b18525301aac54f7b3b59bf819aa6c10635fe`), reproduce with `make e256-vnext-topology-check`. Closure requires a frozen specification, construction analysis, the full attack matrix with planted controls, blinded active-count selection, independent implementation/KATs, and human review — none of which this receipt supplies. |
| E256-062 | High | OPEN | **Wide-state fork is structurally retained but establishes no rotor-namespace advantage.** The byte-local topology could not be repaired: its 255-query byte-codebook ceiling was invariant from 1+1 to 16+16 rotors while cost rose 16×, and the rotor stack was ablatable. E256-W replaces it with one 256-bit/32-byte state in 4×8 Rijndael geometry, 32 keyed affine-AES rotors per round as the only nonlinearity, row offsets (0,1,3,4), and AES MDS MixColumns. Certified: **69/69** nonzero square minors, branch number **5**, exact two-sided inverse, all-to-all structural byte dependency at round **3**, `E256-W-WIDETRAIL-25-v1` discharged for **25** active rotors over four rounds (single-trail 2^-150 differential / 2^-75 linear), 1,024 exact rotor table pairs at DDT **4** / \|LAT\| **32** / degree **7** forward and inverse, 13,824/13,824 round trips over 144 contexts, **7/7** planted controls detected on declared shared paths, and both ablations firing (identity rotors match the recovered affine model 64/64; no-diffusion leaves 32 singleton lanes). | Do not read retention as security. The `fixed_aes_spn` baseline reached the **same** structural bounds with no keyed rotor namespace, so this receipt establishes **no rotor-namespace advantage** and selects **no production round count**. Preregistration `directives/e256-wide-preregistration.json` (`686df3175e91555ee1983bdf4a12fe8f28c463128e06985f3baa1d7777b34c42`); architecture `directives/e256-wide-architecture.md`; receipt `logs/e256-wide-state-gate.json` (`E256-WIDE-STATE-GATE-1`, deterministic payload `21758ce220b9da469a18ea617fa7b2fd41e906add69a258f830b12843e3e495b`), reproduce with `make e256-wide-check`. Closure requires the full attack matrix with planted reduced-round positives, a byte-exact specification, independent implementations and externally held KATs, protocol/hardware evidence, external cryptographic review, and human claim review — none of which this receipt supplies. AEAD-only remains the production baseline. |
| E256-063 | High | OPEN | **Hardware-first E256-H now has reproducible integrated-cost, mixed-sequence falsification, and X0 compositional-policy evidence, but no architecture is selected and the security case remains open.** The H4 sequence census found **737,280/1,474,560** mixed three-round windows failing all-to-all byte dependency, parking unrestricted arithmetic switching. X0 then proved the exact criterion `S(y)+S(z)=Z8` over all **147,456** ordered pairs and derived **73,728** safe directed transitions. Every node has degree 192, but the graph has two 192-node SCCs; the 16-support quotient has two 8-node SCCs and no Hamiltonian cycle. The frozen fallback path alternates indices 0 and 3 and verifies **11/11** safe transitions; **23/23** controls fired. X0 receipt: `logs/e256-x0-h4-evolution-gate.json`, deterministic payload `35060c802427046f5f4630c6b9db6401d8ac90c4649fc0cf088d3f35f31b1b44`; reproduce with `make e256-x0-h4-evolution-check`. | Keep the finding **OPEN**. X0 certifies only a structural transition graph and one bounded path; it does not cross the two support components, inherit the fixed-tuple four-round/25-active-S-box statement, select a production evolution policy, or establish cryptographic security. Mixed-walk activity bounds, the attack matrix, cancellation/value feasibility, RTL enforcement, vendor implementation, round/XOF/schedule choices, independent review, and human acceptance remain separate gates. Reviewed standard AEAD remains mandatory. |

## F. Deferred performance and research opportunities

These are not security fixes and must not start by weakening or changing frozen semantics.

| ID | Priority | Status | Opportunity | Gate |
|---|---|---|---|---|
| E256-054 | Medium | DEFERRED | Pipeline the table path with synchronous RAM. | Only after v2 semantics and state ordering freeze; maintain differential KAT parity. |
| E256-055 | Medium | DEFERRED | Add true AXI-Stream payload FIFOs/backpressure. | First close E256-031...E256-038 and prove one-accepted-input/one-output behavior. |
| E256-056 | Low | DEFERRED | Cache the full rotor pool and atomically select active wiring. | Requires validated double-buffered configuration and measured BRAM budget. |
| E256-057 | Low | DEFERRED | Parallel message processing and random access using a counter-based schedule. | Requires reviewed schedule primitive and frozen per-position derivation. |
| E256-058 | Low | DEFERRED | Optimize Red-team scoring with tuple caching, batching, and optional Metal. | Attack correctness/positive controls first; acceleration must not alter scoring semantics. |
| E256-059 | Medium | DEFERRED | Produce real FPGA area/Fmax/throughput/power/fault/TVLA comparisons against reviewed baselines. | Stable RTL, reproducible build, and explicit threat model required. |
| E256-060 | Medium | DEFERRED | Publish a reproducible v1 autopsy and frozen v2 challenge with negative evidence retained. | Remove secrets/private data, pin all artifacts, define attack models and budgets, and obtain human review before publication. |

## Reproduced audit evidence

The following measurements were reproduced against E256-v1 and must remain labeled historical:

- Swift E256 suite: 35/35 tests passed, demonstrating that existing tests did not cover the failures.
- Direct core and cooperative AXI RTL matched the 36-byte Swift golden.
- GF(2) transition: rank 63 at one step, rank 5 at 59; low 59 bits forced zero; image cycle 31.
- Seeds 1...4096: 127 reached zero lock around the collapse boundary.
- Fixed-point equality: 29.42% live zero-plaintext rate; 11/36 equal bytes in committed golden.
- `cubic6` exact truth table: `P(output == f) = 11/16`, normalized correlation `0.375`.
- File mutation: unauthenticated v1 ciphertext bit flip was accepted and altered one plaintext byte.
- Framing ambiguity: changing nonce length preserved the authenticated `nonce || ciphertext` bytes while changing parse semantics.
- AXI4-Lite: AW-first/W-later handshakes were accepted individually but produced no write response.
- AXIS loader: `TREADY=1` before arm; one beat plus early TLAST reported done with count one.

These receipts prove the listed v1 defects and friendly-path parity only. They do not grade the frozen E256-v2/gen0 candidate documented below.

## Closure rule

For every row moved to `CLOSED`, record:

```text
implementation commit or diff
reproduction command
artifact/log path
profile tuple and hash
toolchain versions
positive and negative controls
claim/document surfaces reviewed
reviewer and date
```

Until all critical rows and the applicable high-severity rows are closed, E256 remains an experimental cryptographic laboratory rather than a production cipher.

## OPEN progress receipts

### E256-003 — fixture-v4 bounded validation (OPEN)

This is an **OPEN progress receipt**, not a closure receipt:

- Aggregate receipt: `logs/e256-v2-gen0-fixture-v4-validation.json`.
- Exact live compatibility tuple: `E256/v2/gen0/fa246e9cba9009a4799e5a81722a9b14e9a67293d9621b45985c5f3e620865d4/fixture-v4`.
- The live center is `A_i^-1(A_i(x) XOR k_i)`. The bounded zero-plaintext equality result is `260/65536 = 0.00396729` with `z=0.250`.
- The fixture-v4 contract carries `1,024 bytes / 9 tables / 10 traces / 25 artifacts`; Swift/direct-RTL/internal-Rust/AXIS/LITE parity and reciprocal decrypt pass on that contract.
- Post-promotion formal certificate: **1/1 PASS** with the five bounded C24 checks. Publication-guard Enigma256 suite: **49/49 PASS**.
- The host derives and transports `(payload, centerMask, absoluteByteCounter)`. RTL validates the transported counter and does not implement HMAC.
- Counter limit: `UInt64.max` is exhausted; `UInt64.max - 1` is the final accepted pre-counter.
- TensorLUT is a bounded optimizer failure only: baseline sanity `true`, verdict `blue_hold`, `final_crypto = -291592.781250`, and `final_nonbinary = 1217`.
- Historical fixture-v3 is preserved as non-loadable evidence at `Fixtures/Historical/Enigma256/E256-v2-gen0-2a9f54c70a1619805a911758158f1e2204b0fd96c35102a9db5f4575aeb40cb0-fixture-v3`.
- The aggregate receipt asserts no wall-clock timestamp because the available clocks conflicted.
- Human acceptance is pending. AI semantic review does not close E256-003.
- These results are not IND-CPA, not an HMAC-security proof, and not external cryptanalysis. The Rust consumer is internal, and no immutable independently accepted external KAT exists.

### E256-061 — mirrored topology and vNext rotor/schedule gates (OPEN)

These are **OPEN progress receipts**, not closure receipts:

- Topology receipt: `logs/e256-vnext-topology-gate.json`, schema `E256-VNEXT-TOPOLOGY-GATE-1`, status `OPEN_PROGRESS`, `results_sha256` `cc1ca362872c0a822270a3f8ad7b18525301aac54f7b3b59bf819aa6c10635fe`. Reproduce: `make e256-vnext-topology-check` (deterministic; verified digest-identical on an independent run).
- Fidelity anchor against the staged `E256/v3/gen0/0206c00e…d376e16/fixture-v5`: **1024/1024** trace rows agree on recomputed HMAC-SHA256 center mask, modeled byte output, collapsed-algebra center input/output, and ciphertext→plaintext round trip. The harness refuses to emit a receipt if this fails.
- Exhaustive mirrored structural result at rotor counts **{1, 4, 8, 16, 256}**, all 256 masks × all 256 inputs, 64 keys per row: identity at mask 0; involution and fixed-point-free for all 255 nonzero masks; exactly 128 two-cycles on the pinned mask sample; literal per-rotor walk equals the collapsed algebra.
- Exhaustive mask-recovery result: exactly one mask maps `P` to `C`, with `M = A(P) XOR A(C)` (mirrored) and `M = A(P) XOR B^-1(C)` (independent). **Rotor count appears in neither formula.**
- Measured two-query distinguisher advantage: mirrored **0.99195** at every rotor count; independent candidate 0.00015–0.00115; random-permutation control 0.00805; 20,000 trials per cell.
- Candidate cycle statistics over 64 keys: mean fixed points 1.031 and involution rate 0.0, against a random-permutation control of 0.828 and 0.0, consistent with the Poisson(1) expectation. Bijection and exact decrypt asserted per key.
- Advisory topology cost (excluded from the digest): mirrored `2R+2` dependent lookups per byte — 10 at *R*=4 and 514 at *R*=256 (~1.8 µs/B vs ~87.9 µs/B in-harness). This rejected 256 active mirrored rotors but did not select an independent depth.
- Rotor/schedule preregistration: `directives/e256-vnext-bakeoff-preregistration.json`, SHA-256 `ebeb9e48d63ffb412b67ddbb20bce66086238b9afc26f8f56d0b0eea809b1fcd`. Receipt: `logs/e256-vnext-rotor-schedule-bakeoff.json`, schema `E256-VNEXT-ROTOR-SCHEDULE-BAKEOFF-1`, deterministic-payload SHA-256 `fd54809cbd12de9d6f14151bcd401232aae765b72cb8368128ea54bdfa7b7197`. Reproduce: `make e256-vnext-bakeoff-check` (`digest_match=True`, `payload_match=True`). The superseded `58231c…10b41b` / `8d286b…e9655e5` run was invalidated before claim or promotion after `semantic-review/2026-09-07-200027-pr-0.md` identified incomplete contract execution.
- Bake-off scope: **46,080** ordinary complete state maps across random-Fisher–Yates and affine-AES rotor families, three schedule arms, depths 1+1 through 16+16, 16 key labels, two streams, two directions, two replications, twelve counters, and all 256 inputs/state. The corpus includes the 16-bit and 32-bit adjacent boundaries. A separately counted **7,680** reset-endpoint maps make **3,840** `(sequence=7,counter=65536)→(sequence=8,counter=0)` comparisons. Pinned subsets carry exact DDT/LAT/ANF and cross-state diagnostics. The visible holdout is disjoint, not sealed.
- Remediated execution gate: every operational preregistration field is authenticated and checked; `rotor/in`, `rotor/out`, schedule, mask, and `controls` domains are executed; active-depth state serialization excludes inactive suffixes; D0–D11 definitions and the immutable architecture-authorization section are hash-bound; and structured fallback tests enforce schedule, family, then numeric-depth priority.
- Semantic follow-up: `semantic-review/2026-09-08-075406-pr-0.md` is **APPROVED** with zero actionable findings after targeted negative probes. This AI review is not human claim review or independent cryptographer acceptance.
- Control gate: all eight planted weaknesses traversed shared campaign paths where applicable and were detected. The ideal independent null traversed **9,216** ordinary canonical contexts plus **1,536** reset endpoints without an exact rejection. Frozen control/baseline IDs and coverage match exactly; **64/64** pinned key-bit-flip checks and all required direction, boundary, and reset comparisons remained distinct.
- Baseline/Q4 gate: PRF-mask-only executed over the same canonical contexts and records one-pair repeated-state mask recovery plus one mask derivation/one XOR per byte; AEAD-only records zero inner-transform cost and byte-map/codebook metrics as not applicable. No rotor is production-retained without a later frozen independent-key compromise experiment that beats both under common cost accounting.
- New exact negative: holding `A_i` and `B_i` fixed while changing only `M_i` leaves the related-position quotient conjugate to XOR translation. Every tested unequal-mask adjacent relative map in that control had the exact 128-transposition involution signature, and repeated masks produced state/map collisions. Independent ingress/egress alone is therefore insufficient if endpoints are reused.
- All 20 candidate family/schedule/depth cells avoided the frozen exact hard-rejection conditions. This is bounded failure to reject, not pseudorandomness or security.
- **No active depth was security-selected.** The 255-query repeated-state byte-codebook ceiling and bounded detector costs were unchanged while honest rotor evaluations rose from 2 at 1+1 to 32 at 16+16. Machine verdict: `NO_BYTE_LOCAL_PRODUCTION_CANDIDATE_RESEARCH_BASELINE_RETAINED`.
- The tested structured tie-break retains `aes_affine_v1|full_counter_reselect_v1|1+1` only as the next attack/control baseline and a possible tableless implementation research path. It is not a cipher/profile choice. AEAD-only remains the production baseline; the next architecture tranche is the separately specified wide-state fork.
- Scope limits: bounded structural and measured-advantage evidence only. The repeated-state distinguishers are **not** decrypts of nonce-respecting traffic and imply no plaintext recovery against v3 beneath a standard AEAD. Exact diagnostics do not supply IND-CPA/CCA, AEAD, HKDF/HMAC/PRF, side-channel, fault, external-cryptanalysis, or production evidence.
- **E256-003, E256-061, and every tranche row remain OPEN.** No C/H/N row, suite, profile, fixture, or release gate is promoted. Human claim review and independent cryptographer review remain pending. Standard AEAD remains mandatory for real data.

### E256-062 — wide-state structural gate (OPEN)

This is an **OPEN progress receipt**, not a closure receipt:

- Architecture: `directives/e256-wide-architecture.md`, marker-bounded contract hash `1f18c46884d13b010dca9a8217eb8d5472cb5b85fac59ec9ba886defb8fc4c5d`. Preregistration: `directives/e256-wide-preregistration.json`, SHA-256 `686df3175e91555ee1983bdf4a12fe8f28c463128e06985f3baa1d7777b34c42`, refrozen twice before execution with no receipt under either superseded draft.
- Receipt: `logs/e256-wide-state-gate.json`, schema `E256-WIDE-STATE-GATE-1`, status `OPEN_PROGRESS`, deterministic payload SHA-256 `21758ce220b9da469a18ea617fa7b2fd41e906add69a258f830b12843e3e495b`. Reproduce: `make e256-wide-check` (`digest_match=True`, `payload_match=True`).
- Construction: 256-bit/32-byte state, 4×8 Rijndael geometry with byte index `4c+r`, 32 keyed affine-AES rotors per round as the only nonlinear layer, row offsets (0,1,3,4), AES 4×4 MDS MixColumns over `0x11b`, and 32-byte PRF-derived masks before round one and after every round. Encryption and decryption are deliberately different; no reflector or reciprocity.
- Diffusion certificate: all **69** nonempty square minors nonzero, exact two-sided inverse, branch number **5**, distinct row offsets, earliest structural all-to-all byte dependency at round **3**.
- Trail obligation `E256-W-WIDETRAIL-25-v1` discharged: **25** active rotors over any four-round trail, giving single-trail bounds 2^-150 differential and 2^-75 linear. **Single trails only** — no clustering, integral, algebraic, MITM, rebound, slide, invariant-subspace, related-key, multi-user, or implementation coverage.
- Rotor evidence: **1,024** forward/inverse table pairs (four key labels × 256 IDs) exact and bijective; every sampled spectrum equals DDT max **4**, nontrivial \|LAT\| max **32**, and forward/inverse coordinate ANF degree **7**, confirming the W4 prediction is key-independent across sampled keys and IDs.
- Functional coverage: **13,824/13,824** round trips over the exact 144-context Cartesian product (four key labels × two streams × two directions × nine context cases × rounds 1–12 × eight blocks), plus the compositional round-bijection certificate. No 2^256 exhaustive claim is made.
- Load-bearing ablations both fired: identity rotors made the complete permutation exactly affine and matched the recovered 256-bit affine model on **64/64** frozen holdouts, while removing diffusion left all 32 dependency rows singleton same-index lanes through round 12. The candidate mismatched the recovered affine model at every probed round.
- Control gate: **7/7** planted controls detected through their declared shared paths — `affine_rotor_bypass`, `no_diffusion`, `singular_mix_matrix`, `zero_row_shifts`, `reciprocal_sandwich`, `truncated_counter_32`, `direction_omitted`. Candidate and fixed-AES null calibrations passed, and all required counter-boundary, reset, direction, and pinned key-bit-flip material comparisons stayed distinct.
- Machine verdict: `STRUCTURAL_WIDE_STATE_CANDIDATE_RETAINED_FOR_ATTACK_ONLY`. **No production round count was selected.**
- Honest negative: the `fixed_aes_spn` baseline reached the **same** structural bounds with no keyed rotor namespace and less machinery. This receipt therefore establishes **no rotor-namespace security advantage**, and the open question of whether the namespace earns its cost is what opens **E256-063**.
- Scope limits: bounded structural and diagnostic evidence only. Avalanche histograms and structural dependency are diagnostics, not confidentiality evidence, and boolean dependency does not prove the absence of algebraic cancellation. The HMAC-SHA512 derivation is a model baseline, not a selected PRF/XOF. No tableless implementation, constant-time, TVLA, power, EM, cache, fault, RTL, protocol, external KAT, independent implementation, or external cryptanalysis evidence lands here. The visible holdout is disjoint but not sealed or blind.
- **No C/H/N row, E256 finding, suite, profile, fixture, or release gate closes.** Standard AEAD remains mandatory for real data and AEAD-only remains a valid final outcome.

### E256-063 — rotor-lane hardware cost gate (OPEN)

This is an **OPEN progress receipt**, not a closure receipt:

- Architecture: `directives/e256-hardware-architecture.md`, marker-bounded contract hash `b64472f73be9d0fc6318ff445c5f550cb0129309313228f416599c27d3957bb1`. Preregistration: `directives/e256-hardware-cost-preregistration.json`, SHA-256 `cbaa5b02ca71824866d857edda838d97ceca0816bed5f5af334d8625db336e27`.
- Receipt: `logs/e256-hardware-cost-gate.json`, schema `E256-HARDWARE-COST-GATE-1`, status `OPEN_PROGRESS`, deterministic payload SHA-256 `a10e001ad2c2b3de55fcc80197c059f166d5e55599c670e20b01de8f6b7d323d`. Reproduce: `make e256-hw-cost-check` (`digest_match=True`, `payload_match=True`). Toolchain: yosys 0.68+post (git sha1 `c12172fbae8af5e20f6fb52e3d4e92d56ed587b6`), Icarus Verilog 13.0. Tool versions enter the deterministic payload because synthesis numbers are tool-dependent.
- Non-production research RTL: `Hardware/RTL/Research/E256H/e256h_cost_lanes.v`; testbench `Hardware/Testbenches/Research/E256H/e256h_cost_lanes_tb.v`. Combinational, unregistered, and explicitly not a specification, suite, profile, or fixture.
- Method: seven single-byte rotor lanes synthesized with **hierarchy preserved**, so the shared AES S-box (49 LUT6, constant across every S-box-bearing lane) is never re-optimized against the keying logic. The graded quantity is the top module's local `$lut` count, which is exactly the keying overhead. Key material is derived by the frozen E256-W model KDF at key label 0 and rotor ID 0, so the measured lane matches the certified construction.
- Functional gate: **1792/1792** exhaustive checks passed across all seven lanes and all 256 inputs, including the frozen equivalence obligations that the offset lane equals the affine lane at identity matrices, that the table lane equals the affine lane, and that `offset_alt` equals `offset`.
- Measured keying cost (LUT6 / longest topological path): `identity` 0/0, `xor_only` 8/1, `fixed` 0/1, **`offset` 16/3**, `offset_alt` 16/3, **`affine` 64/5**, `table` 700/5.
- **H3 supported.** XOR-offset rotor keying costs **4.0× less area and two fewer logic levels** than programmable GF(2) affine wrappers (16 vs 64 LUT6, depth 3 vs 5) while preserving DDT 4, \|LAT\| 32, and forward/inverse degree 7 by affine equivalence. Machine verdict: `H3_OFFSET_KEYING_SUPPORTED`, with all eight preregistered predictions passing.
- **H1 supported.** The identical rotor function realized as a runtime-loaded 256-entry lookup costs **700 LUT6** — 43.75× the offset lane's keying and 14.3× the entire shared S-box netlist — so secret-table rotors are not a cheap shortcut in logic.
- **Two corrections printed.** First, the E256-063 hand estimate of 3–5× for affine wrappers over the S-box is **wrong in magnitude**: the measured LUT6 ratio is 64:49, about 1.3×. The direction held, the magnitude did not, and gate-equivalent ratios do not transfer to a 6-LUT fabric. Second, an initial methodology was **rejected by its own control**: measuring whole-module LUT6 after `flatten` let ABC re-synthesize across the S-box boundary, reporting `offset` at 158 against 187 for the logically identical `offset_alt`, and absurdly making `affine` (135) look cheaper than `offset` (158). Prediction P3 detected it, the harness failed closed with `INVALID_COST_HARNESS` and wrote no receipt, and the preregistration was refrozen with `flatten` prohibited and the P4/P6 thresholds carried over verbatim so the fix could not be mistaken for goalpost-moving.
- Scope limits: one combinational byte lane on a generic 6-LUT target. This
  one-lane gate does **not** measure full-round logic, effective-mask registers,
  H4 selectors, or integrated storage, so it establishes no
  storage-versus-logic dominance conclusion and does not settle H2. No ASIC
  gate-equivalent, place-and-route, Fmax, timing-closure, power, energy, TVLA,
  EM, or fault result exists. Constant-latency combinational logic is **not**
  side-channel resistance.
- **No security conclusion.** A cheaper lane is not a stronger lane. Every structural certificate (69 MixColumns minors, branch number 5, round-3 dependency, 25 active rotors over four rounds, DDT/LAT/degree) comes from **E256-062** and is untouched by any figure here.
- **No C/H/N row, E256 finding, suite, profile, fixture, or release gate closes**, no round count is selected, no production keying scheme is declared, and no production RTL is authorized. Standard AEAD remains mandatory for real data and AEAD-only remains a valid final outcome.

### E256-063 — H3/H4 candidate re-certification and H5 schedule budget (OPEN)

This is an **OPEN progress receipt**, not a closure receipt:

- Preregistration: `directives/e256-hardware-candidate-preregistration.json`, SHA-256 `2d0ecbbbb18165aa09adbe33c3d85a7d6d72db3881925bc6b11da07ca2243099`. Receipt: `logs/e256-hardware-candidate-gate.json`, schema `E256-HARDWARE-CANDIDATE-GATE-1`, status `OPEN_PROGRESS`, deterministic payload SHA-256 `98af83ec27093787552475fce588f84a902634afcc969bed26462032dddec3cc`. Reproduce: `make e256-hw-candidate-check` (`digest_match=True`, `payload_match=True`). Authenticates both predecessors: the E256-062 wide-state payload and the E256-063 step-1 cost payload.
- An **exploratory probe preceded the freeze**. Predictions were therefore stated qualitatively and every exact count is a measured output, not a preregistered number. The disclosure is recorded in the preregistration itself.
- **H3 certified exhaustively.** `R(x) = SBOX(x XOR p_in) XOR p_out` holds differential uniformity **4**, maximum \|LAT\| **32**, and forward and inverse algebraic degree **7** for **all 256** values of `p_in` with **zero** mismatches, and is bijective for **all 65,536** ordered offset pairs with zero failures. `p_out` cancels in every difference, contributes only a sign in every correlation, and cannot change degree. This is strictly stronger than E256-062, which sampled 1,024 tables; the offset space is small enough to certify completely.
- **H4 needs a certified set, and distinctness is not sufficient.** Of the **1,680** ordered 4-tuples of pairwise distinct row offsets, only **384** discharge every inherited obligation (69 nonzero minors, branch number 5, exact row-shift inverse, all-to-all structural dependency by round 3, and the 25-active four-round manifest). Earliest all-to-all histogram: round 3 for 384, round 4 for 1,248, and **never within 12 rounds for 48**. Rijndael's `(0,1,3,4)` is certified.
- **Exact characterization of the 48 failures**, verified separately against the measured histogram: they are precisely the tuples whose four offsets all share one parity class, so their pairwise differences generate only the index-2 subgroup of `Z_8` and the eight columns split into two orbits that never mix (24 orderings of `{0,2,4,6}` plus 24 of `{1,3,5,7}`). **This corrects a natural assumption:** distinct offsets are necessary but not sufficient, so a keyed wiring selection must draw from the certified 384 and never from the 1,680.
- **H5 schedule budget.** Per 32-byte block for the frozen 800-byte material block: the E256-062 per-derivation HMAC-SHA512 model needs **397 HMAC calls ≈ 1,985 SHA-512 compressions**, while one SHAKE-256 squeeze needs **6 Keccak-f[1600] permutations** — a ratio of **330.83×**. The earlier ~800-compression figure in the architecture record was an undercount and is corrected. This is arithmetic invocation accounting plus a squeeze-length check, not throughput, latency, area, or energy, and **no production XOF is selected**.
- Control gate: **5/5** detected through declared shared paths — `additive_offset_rotor` (252 of 256 offsets break the spectrum, confirming the rejected additive alternative is genuinely different and the invariance check has power), `repeated_row_offsets`, `partially_repeated_row_offsets`, `singular_mix_matrix` (typed `SINGULAR_MIX_MATRIX` rejection before inverse computation), and `truncated_material_block`. All three candidate nulls passed. Machine verdict: `H3_H4_CANDIDATE_STRUCTURALLY_RECERTIFIED`.
- Scope limits: **H2 remains open and unmeasured** — no integrated receipt yet
  accounts recursively for logic, effective-mask registers, H4 selectors, or
  storage organization, so the earlier storage-dominance hypothesis is not an
  evidence-backed conclusion. Exhaustive spectral invariance is a statement
  about one 8-bit rotor, not about the 256-bit permutation. Structural byte
  dependency does not prove the absence of algebraic cancellation. The
  four-round bound covers single differential and linear trails only. How keyed
  offsets are selected and what that selection leaks is untouched. No
  throughput, area, Fmax, power, TVLA, EM, or fault evidence exists.
- **No security conclusion.** The fixed-AES comparator retains the same structural bounds, so no rotor-namespace security advantage is established here either. AEAD-only remains the production baseline.
- **No C/H/N row, E256 finding, suite, profile, fixture, or release gate closes**, no round count is selected, no production XOF or wiring set is chosen, and no production RTL is authorized. Standard AEAD remains mandatory for real data.

### E256-063 — hardware attack lane, 3-round integral distinguisher (OPEN)

This is an **OPEN progress receipt**, not a closure receipt. **It grades the search, not the cipher.**

- Preregistration: `directives/e256-hardware-attack-preregistration.json`, SHA-256 `15bb0b68d1f0ebb521497d4d06cc4250cf608b3a71e1f0719f3e0a7b2017fde3` (refrozen once for an arithmetic correction: the expected RTL/model comparison count was 72, which is not 3 defect modes × 8 rounds × 2 arms; the runner's own coverage assertion failed closed before any receipt was written, and no prediction, threshold, or verdict definition changed). Receipt: `logs/e256-hardware-attack-gate.json`, schema `E256-HARDWARE-ATTACK-GATE-1`, deterministic payload SHA-256 `1114e260455232a2979f8a4f613fc6d6daf4be4f97c3ca6903c3f639357d7a2d`. Reproduce: `make e256-hw-attack-check`. Authenticates all three predecessor payloads (E256-062 and both E256-063 steps).
- Non-production research RTL: `Hardware/RTL/Research/E256H/e256h_attack_core.v`; testbench `Hardware/Testbenches/Research/E256H/e256h_attack_core_tb.v`. Target is the H3 offset rotor with certified wiring `(0,1,3,4)`, material derived by SHAKE-256 (1,184 bytes for the H3 scheme, 9 squeeze blocks — recomputed rather than inherited from the 800-byte E256-062 selection scheme).
- **Lane calibration.** Two arms share one synthesizable round datapath; defects are injected through the same netlist by a `defect` port, not by a reimplementation. `identity_rotor` was recovered by the integral arm at **every** tested round count (balance survives all 8 rounds, as an affine map must); `no_diffusion` was recovered by the truncated-differential arm at **every** tested round count (exactly 1 active output byte). **48/48** RTL values matched an independent software model bit-exactly across all defect modes and round counts.
- **Finding: a 3-round integral distinguisher exists and dies at round 4.** Candidate integral balanced bytes by round (of 32): **32, 32, 32, 0, 0, 0, 0, 0**. This is the first actual attack result on E256-H. It is expected for an AES-like SPN, it is **not** a break of the construction, and it bounds any future round count from below. **No round count is selected.**
- **Static and dynamic agree.** The truncated-differential arm gives active output bytes by round of **4, 16, 32, 32, 32, 32, 32, 32**, reaching full diffusion at **round 3** and independently reproducing the E256-062 structural dependency certificate by dynamic measurement.
- Measured attack cost (yosys LUT6, hierarchy preserved): `e256h_atk_round`
  reports **1,381 local LUT6** at depth 5, `e256h_atk_single` reports **3,496
  local LUT6**, and `e256h_atk_integral` reports **4,007 local LUT6** at depth
  13; the S-box child is **49 local LUT6**. The round instantiates 32 S-box
  children, so they contribute `32 × 49 = 1,568` LUT6 outside the local round
  count and a simple hierarchy-expanded round estimate is approximately
  **2,949 LUT6**. The 1,381 local non-child LUT6 are about 46.8% of that
  estimate, not a small fraction, and the receipt does not decompose them by
  diffusion/keying/defect logic. No recursive totals are inferred for the two
  engines. Measured integral cycles run 770 at 1 round to 2,563 at 8 rounds
  (about `256*(R+2)`). Only the round module is a clean datapath figure; both
  engines expose wide flat material ports as a research-harness artifact. This
  generic mapping measures no integrated effective-mask storage or H4 selector,
  so it establishes no storage-versus-logic dominance conclusion.
- Machine verdict: `HARDWARE_ATTACK_LANE_CALIBRATED_REDUCED_ROUND_DISTINGUISHER_FOUND`, all six predictions passing, both planted defects recovered.
- Scope limits: **two arms are not the attack matrix.** Differential clustering, impossible differentials, algebraic and degree growth, meet-in-the-middle, rebound, slide, invariant subspace, related-key and related-tweak, multi-user, reset/reuse, and TMTO are all untested. One active lane, one input difference, one material set, and no key-recovery attack. LUT6 and cycle figures are yosys/ABC and simulation artifacts, not place-and-route, Fmax, energy, or silicon. **H2 parameter and register storage remains unmeasured.**
- **A calibrated search that finds nothing is not a security result.** That constraint is preregistered, printed in the receipt, and must not be softened in any downstream surface.
- **No C/H/N row, E256 finding, suite, profile, fixture, or release gate closes**, no round count is selected, and no production keying, wiring, XOF, mode, or RTL is authorized. Standard AEAD remains mandatory for real data and AEAD-only remains a valid final outcome.

### E256-063 — exact H3 XOR-offset collapse (OPEN)

This is an **OPEN progress receipt**, not a closure receipt:

- Preregistration: `directives/e256-hardware-offset-collapse-preregistration.json`, frozen SHA-256 `3d7a12731fcf81f6120577122c55bd8ec25589a82226d49fab7e5b8350ee0cee`. Receipt: `logs/e256-hardware-offset-collapse-gate.json`, schema `E256-HARDWARE-OFFSET-COLLAPSE-GATE-1`, status `OPEN_PROGRESS`, deterministic payload SHA-256 `1478a0ba317bce5f33cb053744b050bb6188543405c1dfacf52d8aaf920c4b71`. Reproduce with `make e256-hw-offset-collapse-check` (`prior_digest_valid=True`, `payload_bytes_match=True`, `digest_match=True`, `CHECK PASS`).
- Machine verdict: **`H3_XOR_OFFSETS_EXACTLY_COLLAPSE_TO_EFFECTIVE_MASKS`**. For a fixed H4 wiring sequence in scope, separate H3 `p_in`/`p_out` bytes add no permutation-family freedom beyond effective masks. The lean research baseline therefore drops separate H3 offsets and retains fixed AES S-boxes, effective masks, MixColumns, and H4 moving wiring.
- Software coverage: all **384** certified H4 tuples, each repeated across rounds; three deterministic 1,184-byte material sets; rounds **1--12**; eight blocks. Stage A passed **110,592/110,592** and fixed-R Stage B passed **110,592/110,592**, zero mismatches (**221,184** total); each Stage-B prefix used a separately derived terminal key.
- Sequential RTL coverage: unchanged dual `e256h_atk_single` cores under fixed tuple `(0,1,3,4)`, rounds 1--8 and eight blocks, passed **64/64** original-versus-canonical comparisons and **128** RTL-side-versus-independent-software comparisons.
- Formal scope is deliberately compositional. Both forms share the nonlinear boundary `U=SBOX^32(state XOR A)`; a Yosys SAT miter proves `L(U XOR B) XOR M = L(U) XOR L(B) XOR M` for arbitrary 256-bit `U`, `B`, and `M`. The correct 768-input-bit linear cone is UNSAT for mismatch; all three formal mutations are SAT with normalized witnesses. The proof cone contains no S-box logic; unchanged dual-core RTL ties the lemma to the frozen round implementation.
- Controls: **6/6 detected** — omitted transport, raw output offset, wrong transport source, terminal `A_R` inclusion (all `R=1...11`; `R=12` is inapplicable because no `A_12` exists), wrong mask index (**96/96** mismatches), and the non-absorbable bit-permutation family (**65,536** exhaustive comparisons, zero XOR-translation matches). All six preregistered predictions passed.
- Material accounting: the predecessor E256-W schedule is 384 rotor IDs plus 416 masks (**800 bytes / six SHAKE-256 rate blocks**). Raw H3 is 768 offsets plus 416 masks (**1,184 bytes / nine blocks**). Stage A is a different 800-byte representation: 384 retained input offsets plus 416 transported masks. Fixed `R=12` Stage B is **416 live effective-mask bytes**; its representation kernel is **768 bytes / 6,144 bits**. H4 selector material is separate.
- The 416-byte form collapses already-derived 1,184-byte material. Directly squeezing 416 bytes would be a new schedule/domain requiring its own freeze and attack evidence; this receipt does not turn the frozen nine-block fixture into a four-block schedule.
- Scope limits: this is exact material-normal-form equivalence, **not** a cryptanalytic break, security-bit result, or key recovery. It certifies repeated use of each H4 tuple in software, not arbitrary per-round switching; RTL/formal cover only fixed `(0,1,3,4)`. It selects no production round count, XOF, key schedule, selector, mode, profile, fixture, protocol, or RTL, and settles no integrated H2 area, register, Fmax, power, side-channel, or place-and-route question.
- **No C/H/N row, E256 finding, suite, profile, fixture, or release gate closes.** E256-063 remains `OPEN`; reviewed standard AEAD remains mandatory for real data.

### E256-063 — H2 integrated-cost gate (OPEN)

This is an **OPEN progress receipt**, not a closure receipt:

- Preregistration: `directives/e256-hardware-h2-preregistration.json`, frozen raw SHA-256 `e3f785583fdf2cda3059e46a677d9e73711ab317ef1eeee3dcdf0c9e7e983a03`. Receipt: `logs/e256-hardware-h2-gate.json`, schema `E256-HARDWARE-H2-GATE-1`, status `OPEN_PROGRESS`, deterministic payload SHA-256 `b0b62be2cfebd870f71ce0b5e5300eb52ab8c2aea243712d1617f4e2351dc7e1`. Reproduce with `make e256-hw-h2-check` (`prior_digest_valid=True`, `payload_bytes_match=True`, `digest_match=True`, `CHECK PASS`).
- Machine verdict: **`H2_INTEGRATED_COSTS_MEASURED_NO_ARCHITECTURE_SELECTED`**.
- Functional coverage: all six fixed/direct-H4 × FF/ring/generic-memory tops; each fixed top emitted exactly **24** outputs and each direct top exactly **9,216**; **9,216** canonical rows; **27,720/27,720** independent RTL/model comparisons; **18,480** cross-storage comparisons; **72** fixed/direct bridges; zero mismatches. The exhaustive 256-input tableless S-box bridge matched the frozen AES table hash.
- Recursive generic totals `(LUT6, sequential bits, generic memory bits, primitive cells, levels)` are: `ff_fixed=(7988,3853,0,11841,8)`, `ff_direct=(8224,3865,0,12089,10)`, `ring_fixed=(7878,3853,0,11731,8)`, `ring_direct=(8098,3865,0,11963,10)`, `mem_fixed=(4718,1295,3328,6014,8)`, and `mem_direct=(4730,1307,3328,6038,10)`.
- Protocol cycles are input-independent across the exact corpus: all **27,720** executed inputs kept `ready` low while busy and raised it with `done`, yielding 24 fixed and 9,216 direct observations per variant. FF/ring variants have latency **12**, initiation interval **13**, and `32/13` bytes/cycle; memory comparators have **14**, **15**, and `32/15`. These are cycle constants, not timing or Fmax.
- Every graded boundary contains all **3,328** effective-mask bits. Recursive and independent expanded accounting close exactly. Each top preserves its exact normalized mapped primitive multiset across analysis-only flattening. Within a fixed/direct pair, normalized hierarchy and storage-preserved common-module primitive signatures match.
- Observed direct-minus-fixed deltas are `(+236 LUT6,+12 sequential,+0 memory,+248 cells,+2 levels)` for FF, `(+220,+12,+0,+232,+2)` for ring, and `(+12,+12,+0,+24,+2)` for memory. Separate ABC runs selected different mapped costs/decompositions for some identical common children; both mapped metric/type multisets are recorded rather than required equal. These are reproducible generic-flow comparisons, not isolated physical selector-area claims.
- Controls: **12/12 detected** — wrong key order/address, reverse byte packing, wrong H4 direction, ignored selector, broken ring, stale memory read, incomplete configuration, externalized storage, nested multiplicity, duplicate accounting, and post-map depth preservation. All nine preregistered predictions passed.
- Scope: fixed `R=12` is measurement-only. The 416-byte masks are collapsed from already-derived 1,184-byte material; no direct 416-byte XOF is authorized. One commit-sampled H4 tuple repeats across rounds; there is no per-round policy or on-chip catalog claim. Generic memory remains an H1-ineligible comparator. No vendor utilization, timing/Fmax, physical implementation, power, energy, fault, zeroization, TVLA, EM, side-channel, cryptanalytic, or security-bit result lands here.
- **No C/H/N row, E256 finding, architecture, storage winner, round count, XOF, schedule, H4 policy, suite, profile, fixture, protocol, production RTL, or release gate closes.** E256-063 remains `OPEN`; reviewed standard AEAD remains mandatory for real data.

### E256-063 — H4 per-round switching-sequence gate (OPEN)

This is an **OPEN progress receipt** and a valid bounded falsification result, not a closure receipt:

- Frozen contract: `directives/e256-hardware-architecture.md` §11, inclusive marker SHA-256 `aac50bda525ead96234fc3c0e3e3692fabbde101de34d44f632d6a65bfbed1e4`. Preregistration: `directives/e256-hardware-h4-sequence-preregistration.json`, raw SHA-256 `b7afcc67ceac142a800468362ee0c97fcf6c7b6843f0cdd2f96f5d77894fc8e2`. Receipt: `logs/e256-hardware-h4-sequence-gate.json`, schema `E256-HARDWARE-H4-SEQUENCE-GATE-1`, status `OPEN_PROGRESS`, deterministic payload SHA-256 `4562482417cb2917208cf37f8c4441efbdde602230d878ba49d249b017822064`. Reproduce with `make e256-hw-h4-sequence-check`.
- Machine structural verdict: **`ARITHMETIC_SEQUENCE_CENSUS_COUNTEREXAMPLE_FOUND`**. Exactly **737,280/1,474,560** preregistered contiguous three-round windows in the complete arithmetic schedule family fail the all-to-all byte-dependency criterion. The first frozen-order witness is `a=0`, `d=1`, `start_round=1`, indices `[1,2,3]`, tuples `(0,1,3,4)`, `(0,1,4,3)`, `(0,1,4,7)`; output lane 0 lacks input lanes `[6,11,24,29]`.
- This parks unrestricted use of the tested arithmetic switching family under this criterion. It does **not** establish that all possible H4 switching fails, and it does not inherit the fixed-tuple four-round/25-active-S-box statement as a mixed-sequence theorem. Any narrower policy needs a fresh freeze, complete mixed-window grading, controls, and attack evidence.
- Sequence-specific H3 offset collapse passed **221,184 Stage-A + 221,184 Stage-B = 442,368** exact comparisons with zero mismatches, previous-selector transport exact, and no terminal `A_12`.
- Four integrated FF/ring repeated/sequence tops passed **55,296/55,296** independent RTL/model comparisons over **18,432** rows, **27,648** storage comparisons, **18,432** repeated/sequence bridges, and **55,296/55,296** per-input ready/busy observations. Every variant retained latency 12 and initiation interval 13.
- All **19/19** planted controls were detected, including selector-order, collapse-transport, configuration, post-commit-pin, externalized-state, accounting, extra-output, and missing-cycle failures.
- Generic Yosys/ABC sequence-minus-repeated observations are FF `(-407 LUT6,+132 sequential bits,-275 primitive cells,+1 level)` and ring `(-57,+132,+75,+1)`. There was no threshold and no winner. Negative LUT deltas from independently mapped generic graphs are not physical area savings, vendor utilization, timing/Fmax, or an architecture selection.
- This is Yosys/ABC-mapped RTL with Icarus-validated behavior on an Apple-Silicon host. It is not vendor P&R, physical FPGA evidence, Metal/FHE execution, or literal GPU-to-FPGA synthesis. No H4 policy, architecture, storage winner, round count, XOF, schedule, suite, AEAD construction, production RTL, or security value is selected.
- **No C/H/N row or public claim epoch moves. E256-063 remains `OPEN`; reviewed standard AEAD remains mandatory for real data.**

### E256-063 — X0 proof-carrying H4 transition policy (OPEN)

This is an **OPEN structural progress receipt**, not a cipher promotion or closure receipt:

- Frozen contract: `directives/e256-x0-h4-evolution.md`, inclusive marker SHA-256 `1ef354e9b933838eb3e74b32b202e4693f1bfdd62379f10dbc6a8673b3383962`. Preregistration: `directives/e256-x0-h4-evolution-preregistration.json`, raw SHA-256 `d39759bc2677fa17227ea129fc3ec20791a749cec2b9cdd33aa18c45df338711`. Receipt: `logs/e256-x0-h4-evolution-gate.json`, schema `E256-X0-H4-EVOLUTION-GATE-1`, status `OPEN_PROGRESS`, raw SHA-256 `8db5f21b6e0a7249fa9b558c02a989324911575e91704b5e096e2749744ac2c9`, deterministic payload SHA-256 `35060c802427046f5f4630c6b9db6401d8ac90c4649fc0cf088d3f35f31b1b44`. Reproduce with `make e256-x0-h4-evolution-check`.
- Independent literal three-round propagation and the exact sumset law `S(y)+S(z)=Z8` agreed for all **147,456** ordered catalog pairs, **98,304** first-selector cases, and **2,048** translated support cases. The safe graph has **73,728/147,456** directed edges, bitset SHA-256 `33752c5f7a689fbeb031b0a5b7f8e80b0849dc4d8962ce04a74e1f73bb5fe0c3`, and root `d7e44b625acc693a28469dd993edfe3bf8cd7a4b966275a70ad7cf3941e4a80a`.
- Every catalog node has in/out degree 192. Counts close at 384 loops, 73,344 off-diagonal edges, 9,216 same-support edges, and 64,512 support-changing edges. The full graph has two 192-node SCCs. The 16-support quotient has two 8-node SCCs and the exact DP verdict **`FULL_SUPPORT_QUOTIENT_HAMILTONIAN_CYCLE_NOT_FOUND`**. This is a valid adverse topology outcome, not a harness failure.
- The preregistered fallback certificate alternates indices `[0,3,0,3,0,3,0,3,0,3,0,3]`, corresponding to tuples `(0,1,2,5)` and `(0,1,4,7)`, and verifies **11/11** adjacent transitions against a reconstructed graph/root. It does not cross the two support components or cover all 16 supports.
- The predecessor arithmetic census reconstructed exactly: **73,728** failed classes, **737,280** failed placements, its original first witness, and the previously disclosed zero-failure stride set `[0]`. All **23/23** catalog, algebra, graph/root, coverage, path, and diagnostic controls were detected.
- The machine verdict **`SAFE_TRANSITION_GRAPH_DERIVED_AND_PATH_CERTIFIED`** means only that the complete structural transition grammar and one deterministic path were verified. It is not a mixed four-round/25-active-S-box theorem, differential/linear/integral/algebraic/cube/related-key result, attack work factor, production schedule, self-evolving cipher, RTL policy-enforcement mechanism, Metal/FHE execution, or physical FPGA result.
- **No C/H/N row, public epoch, architecture, round count, schedule, XOF, suite, protocol, production RTL, or security value moves. E256-063 remains `OPEN`; reviewed standard AEAD remains mandatory for real data.**

### E256-062 — namespace versus fixed-AES twin, one integral (OPEN)

This is an **OPEN progress receipt**, not a closure receipt. It answers wide-state §4 item 2 for a single attack and does not close E256-062.

- Preregistration: `directives/e256-namespace-vs-aes-preregistration.json`, SHA-256 `90c5ae3fbd4af29e37777792856ae43f5e52fadc3774977eeb7c02a89f3090b4`. Receipt: `logs/e256-namespace-vs-aes-gate.json`, schema `E256-NAMESPACE-VS-AES-GATE-1`, status `OPEN_PROGRESS`, deterministic payload SHA-256 `964c922269c61f4b7dfcb3d85a2a1cf005e1bae866e127eec37748a78374dd7a`. Reproduce with `make e256-namespace-vs-aes-check`.
- Machines share the AES S-box, MixColumns, and one SHAKE-256 mask schedule. `p_in` and `p_out` are zero. The twin repeats wiring `(0,1,3,4)`. The candidate draws each round from the catalog `(0,1,3,4)`, `(0,1,2,5)`, `(0,1,4,7)` by SHAKE-256.
- Integral over one active byte, rounds 1–8: both machines stay balanced for **3** rounds and break at round 4. Balanced-byte counts: twin `32,32,32,0,0,0,1,0`; candidate `32,32,32,0,0,0,0,0`.
- Controls: identity rotor on the candidate schedule stayed balanced at all **8** rounds. Mono-parity wiring `(0,2,4,6)` was not all-to-all by round 12.
- Machine verdict: **`NAMESPACE_FAILS_ON_THIS_INTEGRAL`**. Equal surviving-round counts are a namespace failure under the frozen win rule. The round-7 lane counts are not a second metric.
- Scope: one integral, one key label, a three-tuple catalog. Not the attack matrix, not a round-count selection, not a security result. AEAD-only remains the production baseline.

### E256 patched rotor — power exponent 112 (OPEN)

This is an **OPEN research receipt**. The rotor is not installed in E256-H.

- Preregistration: `directives/e256-patched-rotor-preregistration.json`, SHA-256 `fb779d447d462f6a700a3ae2ebc04cb7b03cfc58126cecca457cf14379c08cf7`. Receipt: `logs/e256-patched-rotor-gate.json`, schema `E256-PATCHED-ROTOR-GATE-1`, deterministic payload SHA-256 `5a3316337bfeeeeed75a475f8e07dfacfc52c3d01b74e027fa170274b795c510`. Reproduce with `make e256-patched-rotor-check`.
- Selected map: GF(2^8) power `x^112`, 0 sent to 0. It is a 256-symbol bijection, not an involution, and not a translation. Its DDT histogram is outside the inverse/AES class. 121 maps in the searched family were outside that class.
- Measured bounds: differential peak **6**, absolute Walsh peak **64**, algebraic degree **3**. AES is 4, 32, and 7. These bounds are worse.
- The same integral stays balanced for **3** rounds on this rotor and on the AES twin, then breaks. That tie is the SPN bijection property.
- **Not a replacement for the AES S-box.** No suite, profile, fixture, or C/H/N row moves.

### Enigma defect patch — wide rotor stack against the byte-local walk (OPEN)

Measured by `Scripts/e256_enigma_defect_patch.py` on the E256-W candidate at 4 rounds. Not a cipher selection.

- Byte-local mirrored center, one rotor from the same namespace: mask 0 is the identity, and **255/255** nonzero masks are fixed-point-free involutions of 128 two-cycles.
- Wide rotor stack: encrypting the ciphertext does not return the plaintext. A ciphertext byte matches the plaintext byte on **3/1024** positions. A one-byte plaintext flip never changes only one output byte (**0/32**).
- The related-position defect is still there if the rotors stay put. Two wide encryptions that differ by one XOR on a single mask byte have a quotient that is an involution on **16/16** full blocks. That is `F⁻¹(F(x) XOR d)` for the partial map up to the mask. Rounds after the mask cancel.
- Changing one rotor id, and leaving the masks alone, drops that involution to **0/16**. A position change has to reselect a rotor. A new mask is not the patch.

### E256-v5 — current research machine (OPEN)

Research build, and the machine this journal now treats as current. It is not fixture-v4, and it is not the staged `E256/v3/gen0/.../fixture-v5` lane. `enigma_256_core.v` was not overwritten.

- Code: `Scripts/e256_v5.py`, `Hardware/RTL/Research/E256H/e256v5_round.v`. Reproduce with `make e256-v5`.
- State is 32 bytes. Each round applies a keyed affine rotor on every byte, shifts rows by `(0,1,3,4)`, mixes the eight columns, then XORs a mask. Decrypt is the inverse path. The block index is inside the rotor derivation, so a new block reselects the rotors.
- Widths checked: **4**, **8**, and **14** rounds. Verilog is the 14-round width. No production round count is selected.
- At each width, encrypt-twice does not return the plaintext, a one-byte plaintext flip changes all **32** output bytes, and the neighboring block index does not decrypt. A one-byte mask change with the rotors held fixed is an involution on **8/8** blocks. Replacing one rotor drops that to **0/8**.
- Lane-0 integral at 14 rounds: **32, 32, 32, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1**. It dies at round **4**. All **32** input lanes die at round 4. After that the busiest round has **2** balanced bytes, never 32.
- One key bit reselects **448/448** lanes. A planted schedule that ignores the key collides.
- Four drawn rotors match the AES S-box spectrum: differential peak **4**, Walsh peak **32**, output-bit degree **7**. The keyed wrapper does not beat the fixed substitution on those three numbers.
- A 16-bit rotor, the field inverse in GF(2^16), was measured in `Scripts/e256_v5_wide_rotor.py` and then installed as E256-v6, not inside this 8-bit round. The 8-bit inverse calibrates at differential **4/256**, degree **7**, coordinate Walsh **32**. The 16-bit inverse is differential **4/65536** (`2^-14`), degree **15**, coordinate Walsh **512** (`2^-7`). The AES box is `2^-6` and `2^-3` on those same ratios.
- The schedule binds the block index into every rotor. Across blocks 0–15, all **16** rotor schedules differ. Block 0 and block 1 differ in **448/448** lanes. A planted schedule that ignores the block index collides, so the check is not vacuous. The fourteen rounds inside one block also use fourteen different rotor sets. Verilog matches Python on **2** blocks × **14** rounds.
- Messages are padded with `0x80` and then zeros out to 32 bytes, including a whole extra block when the message already fills one. Lengths 0, 1, 15, 31, 32, and 33 round-trip at 4 rounds. A padded block is a multiple of 2 bytes, so a 16-bit rotor can take it.
- No suite, profile, fixture, or C/H/N row moves. Fixture-v4 stays the live machine.

### E256-v6 — 16-bit inverse round (OPEN)

Research build. It does not replace E256-v5 as the current machine, and it does not touch fixture-v4.

- Code: `Scripts/e256_v6.py`, `Hardware/RTL/Research/E256H/e256v6_round.v`. Reproduce with `make e256-v6`.
- State is 32 bytes, read as **16** words of 16 bits. Each word is multiplied by a nonzero field element and inverted in GF(2^16) with polynomial `0x1100B`, then XORed with the public constant `1`. Rows shift by `(0,1,2,3)` across four columns. MixColumns uses the AES coefficients over that field. Decrypt is the inverse path. There is no keyed XOR mask. Schedule domain `E256-v6/schedule/v2`.
- Four, eight, and twenty-five rounds round-trip. Encrypt-twice is not the plaintext. A one-word flip changes **16/16** words. Dependency reaches all 16 words by round 4. The neighboring block index does not decrypt. Twenty-five is the experimental Verilog width, not a selected round count.
- The mix matrix has **69** nonzero minors over GF(2^16), so its branch number is **5**. With row shifts `(0,1,2,3)`, a four-round trail has at least **25** active inverses and a two-round trail has at least **5**. Each inverse has differential probability at most `2^-14` and correlation at most `2^-7`. Four rounds are therefore at most `2^-350` differential and correlation `2^-175`. Two rounds stop at `2^-70`, short of a 256-bit key. The first 24 rounds of the 25-round width are six such windows: **150** active inverses, differential `2^-2100`, correlation `2^-1050`. This is a single-trail bound. It does not sum every trail.
- Word 0, taken through all **65536** values, is balanced on **16, 16, 16** words after rounds 1–3 and on **0** words from round 4 through round 25. All **16** input words die at round **4**. After that, no word is balanced again. Without the public constant the same word stayed balanced for all 25 rounds, because the pure inverse undoes itself.
- One known pair recovers the first-round multiplier when the plaintext has a single nonzero word. The same formula misses at 2, 3, 4, and 25 rounds. A key with one flipped bit does not decrypt. The least-significant bit of output word 0, as a function of that one input word, has degree **15** after one, two, and three rounds. At three rounds, with a second word contributing, that bit has degree **15, 16, 17, 19** over **16, 17, 18, 20** input bits. The degree over all 256 input bits was not computed.
- One word difference, over all **65536** values of that word: the rotor differential peak is **4/65536**. After one round the heaviest output difference occurs **4** times, across **32767** differences, in **4** words. After 2, 3, and 25 rounds the heaviest occurs **2** times and **32768** full-state differences are reached. Two is the floor of this test, because `F(x)` and `F(x XOR δ)` always share a difference. Hitting that floor means no second pair produced the same 32-byte difference. This sample cannot see a probability below `2^-15`.
- An XOR grafted onto the round, with the multipliers held fixed, is an involution on **8/8** blocks. The installed round has no such XOR. Changing one multiplier drops the quotient to **0/8** at 4 rounds and at 25.
- The schedule binds the key and the block index into every multiplier. Blocks 0–15 all differ. Block 0 and block 1 differ in **400/400** scales, and one key bit does the same. A planted schedule that ignores the block collides, and a planted schedule that ignores the key collides. Verilog checks the same **400/400** key-bit and block-index reselection on the scale table.
- Verilog matches Python on **2** blocks × **25** rounds.
- Messages padded with `0x80` and zeros to 32 bytes round-trip at lengths 0, 1, 15, 31, 32, and 33.
- No suite, profile, fixture, or C/H/N row moves. v5 stays the current research machine.

### E256 repaired machine — 14-round schedule (OPEN)

This is an **OPEN functional receipt**. It is not a security result and not a promoted round count.

- Code: `Scripts/e256_repaired_round.py`, `Scripts/e256_repaired_twin.py`, `Hardware/RTL/Research/E256H/e256r_round.v`. Receipt: `logs/e256-repaired-machine.json`. Reproduce with `make e256-repaired-round`.
- Schedule: each round mask is SHAKE-256 over `E256-R/schedule/v2 || R || round_index || key || block_index`. A separate final whitening mask (`|| W ||`) is XORed after the last MixColumns. Experimental width is **14** rounds. Byte dependency is complete at 3 (reach 4, 16, 32).
- Integral on this schedule, lane 0: **32, 32, 32, 1, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0**. All **32** input lanes die at round **4**. After that, the busiest round has **2** balanced bytes, never 32. The identity S-box stays balanced for all 14 rounds. Death at round 4 is the expected AES-like behavior, not a defect.
- Four-round single-trail certificate: **69** minors, **0** zero, offsets `(0,1,3,4)` distinct, **25** active S-boxes per four rounds and **5** over the two-round tail. Three windows plus rounds 13–14 give a lower bound of **80** active S-boxes. S-box peaks differential **4** and Walsh **32**, so a single trail is at most `2^-480` differential and `2^-240` linear. Identity peak **256**. Mix removed: byte reach at 14 rounds stays **1**.
- Algebraic degree: every AES S-box output bit has degree **7**. One input byte after one round still has degree **7**. Two input bytes still show degree **7** after two rounds, then **14** after three rounds inside that 16-bit window. The identity S-box stays degree **1**. The degree upper bound is 7, 49, then **255** from round 3 through round 14, so a low-degree interpolation does not apply at the 14-round width. The exact degree of a full 256-bit output bit was not computed.
- One known plaintext-ciphertext pair recovers a one-round mask exactly. The same peel on a 14-round ciphertext does not recover the first mask.
- Routes that still fit in one process, all on this schedule: the 15 masks (14 rounds plus whitening) are pairwise distinct on the planted key, so a slide of identical rounds has no place to land. Stripping MixColumns and ShiftRows from the ciphertext does not expose the last S-box output; removing the whitening first does. Guessing one secret byte of a 2-round mask recovers that byte (exactly one hit in 256). The same 256 guesses, peeling only two rounds off a 14-round ciphertext, recover nothing.
- What this process cannot run: the sum of every 14-round trail, a meet-in-the-middle over the full 256-bit state, and the exact degree of one full-width output bit. Those are the routes left. They are not a security claim.
- One two-round output difference is reached by **64** trails, weight **3040** against best trail **1024** (2.97×). Carried through 14 rounds that bundle is still 64 trails, **372** S-boxes, cluster about `2^-2230`. The sum over every other trail was not counted.
- Every one of the 256 plaintext bits, every key bit, and every ciphertext bit was flipped on a planted block. Output bits changed in the ranges 101–150, 97–146, and 106–154. No key bit still decrypted. The first MixColumns column matches the published AES vector `d4 bf 5d 30` → `04 66 81 e5`. Eight counters produced eight distinct keystream blocks, and the neighboring counter did not decrypt.
- The second model matched encrypt and decrypt on **256** blocks. Same-session code, not an external review. Verilog matched on **16** blocks × **14** rounds. Identity S-box recovered on 16/16 held-out blocks; the real S-box missed 16/16. 256 keyed blocks round-trip; the neighboring block index does not.
- Fixture-v4 `enigma_256_core.v` is unchanged. No suite, profile, fixture, or C/H/N row moves.

### E256-v3/gen0 — fixture-v5 first core-freeze tranche (OPEN)

This is an **OPEN progress receipt**, not a closure receipt:

- Aggregate receipt: `logs/e256-v3-gen0-fixture-v5-core-freeze-validation.json` (SHA-256 `cd17dd2226393e4c28ef9a998d057a3280f891389696ebbdbcda5cbe44be1760`).
- Exact staging tuple: `E256/v3/gen0/0206c00e5084ebafe1f841708d2af3f4a029bcf160f7b22ed63bb5078d376e16/fixture-v5`; the 2,161-byte canonical profile independently hashes to the embedded profile ID.
- This incompatible lane implements bounded progress on E256-005/006, E256-011/012, and E256-025...029: immutable profile binding, exact profile-scoped domains, unbiased `UInt16BE` rejection sampling, strict external-zero rejection, complete wiring validation, strict canonical fixture-v5, 1,024-byte/state traces, and portable in-tree Rust rederivation.
- Swift scoped gate: **19 tests reported, 1 opt-in emitter skipped, 0 failures**. A separate explicit emission regenerated all **27 files** byte-for-byte; path+content aggregate SHA-256 is `8466b87e0b3895f520ee34a063ad6af4faa217b5d50dc0a9b387778c16ab1c60`.
- Fixture-v5 freezes **26 artifacts**, **64 recurrence basis rows**, checkpoints `0/1/2/58/59/60/64/128/1024`, and **13 declared negative vectors**. The declarations are not represented as 13 independently executed portable controls; the receipt enumerates the controls actually run.
- The MMIO plan validates before transaction start and requires inactive staging plus atomic commit/abort. Seven injected sink failures preserved the modeled active configuration. No concrete production sink or RTL shadow bank lands here, so E256-033 remains open.
- `./Scripts/enigma256_v3_sim.sh` first rederives the exact selected bundle with the Rust verifier, then passes reset/rejected-load quiescence and **1,024/1,024** direct RTL trace beats. V3 AXIS/LITE wrappers are not present and no such parity is claimed.
- Pinned Rust format, Clippy `-D warnings`, complete package tests, fixture-v5 rederivation, existing v2 fixture consumption, and Yosys examples pass. The Rust lane remains internal and repository-coupled, not independently accepted evidence.
- Semantic review first returned `NEEDS_CHANGES`; the bounded follow-up is `APPROVED` at `semantic-review/2026-08-28-153347-pr-0.md`. AI review is not human acceptance.
- Existing fixture-v4 **49/49**, C24 **1/1**, AXIS/LITE, and TensorLUT `blue_hold` evidence remains bound to v2 and is not inherited by v3.
- No canonical alias was promoted. **E256-003 and every tranche row remain OPEN.** This is not IND-CPA, not a security proof, not external cryptanalysis, and not production suitability. Standard AEAD remains mandatory for real data.

## Closure receipts

### E256-001 — corrected 64-bit transition (2026-08-20)

- Swift and all hand-authored recurrence-bearing RTL now implement `(state >> 1) XOR (LSB ? 0xD800000000000000 : 0)`.
- Independent checkpoints for seed `0x0123456789abcdef` agree at clocks 0, 1, 2, 58, 59, 60, 64, 128, and 1,024.
- Swift test constructs the 64x64 GF(2) transition matrix, verifies rank 64 initially and after 59 clocks, verifies `T^(2^64-1) = I`, and rejects each proper factor quotient using the complete factor set `{3,5,17,257,641,65537,6700417}`.
- Swift test verifies forward/inverse vectors and no zero lock or repeated state over the first 4,096 clocks of the regression seed.
- `swift test -c release --filter Enigma256Tests`: 38 tests, 0 failures.
- `./Scripts/enigma256_lfsr_sim.sh`: RTL matched independent checkpoints through 1,024 clocks.
- `./Scripts/enigma256_tensorlut_synth.sh`: all five active cone sources synthesized after the repair; the committed step-cone TensorLUT derivative was re-emitted.
- This receipt closes the recurrence defect only. It does not validate the quarantined NLFF generations or establish cipher security.

### E256-004 / E256-007 / E256-010 — frozen native NLFF research profile (2026-08-20)

- Quarantined `quadratic3`, `cubic6`, and `coupledCubic6` are no longer decodable or selectable by normal Swift source. The only accepted profile is `E256-v2/gen0`, formula `native_reversible_16`.
- Historical task-3 compatibility key: `E256/v2/gen0/6734d50d5e985edea4278a897a42e03ec0cf220cc4014bbeb3c3197e2ab83eac/fixture-v2`. It binds the corrected recurrence and native NLFF before the center revision and remains non-loadable evidence. The later fixture-v3/schema-3 tuple is also historical and non-loadable; the live tuple is `E256/v2/gen0/fa246e9cba9009a4799e5a81722a9b14e9a67293d9621b45985c5f3e620865d4/fixture-v4`.
- Search receipt: `logs/e256-v2-gen0-nlff-search.json`, SHA-256 `5c5bc931a145048037ec420b2c0c47ff310570e963bd45b8262f18a1640f0027`, status `ACCEPTED_RESEARCH_PROFILE`.
- Deterministic replay with the recorded seed and full budget produced a byte-identical receipt. The accepted component nonlinearities are all 52; algebraic degrees are `[5, 6, 5, 6, 5, 4, 6, 5]`.
- Train maxima: rate deviation `0.0050048828125`, pair phi `0.010483884009151326`, autocorrelation `0.019936399217221134`, state-bit phi `0.024499656877625717`; minimum BM complexity `1024`.
- Untouched holdout maxima: rate deviation `0.01080322265625`, pair phi `0.02356735226755637`, autocorrelation `0.023011658426417628`, state-bit phi `0.022959502555601297`; minimum BM complexity `1022`.
- `python3 Scripts/e256_nlff_emit.py --check` validates the receipt, recomputes every reversible gate-network truth table, and verifies byte-identical `enigma_256_nlff_v2.vh` and `Fixtures/enigma256_generation.json` outputs. In-process breeding and campaign apply flags now fail closed and point to the offline search/emitter flow.
- `swift test -c release --filter Enigma256Tests`: 40 tests, 0 failures. New checks cover strict profile/fixture rejection, receipt/hash parity, 14 pinned masks, eight exactly balanced components, a complete 64-tap partition, and exhaustive balance plus first-order correlation immunity for each 16-input fold.
- `./Scripts/enigma256_nlff_sim.sh`: hand-authored RTL matched the same 14 independent fixed masks. `./Scripts/enigma256_lfsr_sim.sh`: recurrence still matched independent checkpoints through 1,024 clocks.
- `./Scripts/enigma256_tensorlut_synth.sh` regenerated all five active Yosys cones. Emitted TensorLUT derivatives carry compatibility, receipt, and source-netlist hashes; the native NLFF cone maps to 62 LUT6 cells and the sequential step cone to 145 LUT6 cells plus 64 DFFs under the recorded local Yosys run.
- The historical fixture-v3 golden bundle records its full profile tuple. Hand-authored core, AXIS table-burst, and legacy AXI-Lite friendly-path simulations each matched all 36 historical bytes.
- This closes the defective formula-class rejection, deterministic candidate gate, and ambiguous generation-ID findings only. It does not establish confidentiality or production security. E256-003, E256-005/006, E256-008/009, strict long-form and adversarial KAT work, protocol hardening, calibrated cryptanalysis, and independently accepted external implementation/KAT review remain open or in progress; the in-tree Rust consumer now has bounded fixture-v4 parity.
