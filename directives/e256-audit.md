# E256 hardening ledger

Status: active engineering ledger; E256 is experimental and must not protect real data.

This file records the August 2026 audit findings and the work required to close them. A passing test or failed attack is not a security proof. No entry may be marked `CLOSED` without a reproducible receipt and review of the claim language it affects.

## Compatibility decision

The existing implementation, generated artifacts, fixtures, and receipts are one quarantined suite:

- **E256-v1/gen0...gen5**: historical only; all generation grading is contaminated by the singular LFSR transition. Gen5 is additionally invalidated by a formula-invariant `0.375` correlation to its linear tap.
- **E256-v2/gen0**: the first clean candidate. It is a new suite with a corrected and independently checked transition, new KDF/transcript domains, immutable profile binding, new fixtures, new RTL module/artifact names, and no ciphertext compatibility with v1.
  - **Live fixture-v4:** `E256/v2/gen0/fa246e9cba9009a4799e5a81722a9b14e9a67293d9621b45985c5f3e620865d4/fixture-v4`.
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
