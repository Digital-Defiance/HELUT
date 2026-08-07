# Enigma256 bounded certificate protocol (C24)

**Status:** bounded executable certificate in `Enigma256Formal.certificate()`; **1/1 PASS** for the certificate test. It builds on the bounded fixture-v4 implementation/KAT parity in **C10**. It is not a universal proof.

Living inventory: [`claim-sheet.md`](claim-sheet.md). Implementation: `Sources/HELUTCore/Enigma256Formal.swift`. Receipt: `logs/e256-v2-gen0-fixture-v4-validation.json`.

## Live profile and hypotheses

The certificate is bound to the live native profile:

```text
E256/v2/gen0/fa246e9cba9009a4799e5a81722a9b14e9a67293d9621b45985c5f3e620865d4/fixture-v4
```

For a tested frozen byte position \(i\), let \(A_i\) be the fixture plugboard followed by four forward rotor maps at that position. The live center and inverse path define

\[
S_i(x) = A_i^{-1}\!\left(A_i(x) \mathbin{\mathrm{XOR}} k_i\right).
\]

The executable checks assume the following implementation contract:

- `k_i` is one lane of a profile-bound HMAC-SHA256 block selected by a UInt64 big-endian block counter.
- The pre-step NLFF mask and absolute byte counter each advance exactly once per accepted payload byte.
- The host derives and transports `(payload, centerMask, absoluteByteCounter)`. RTL validates the transported counter; RTL does not implement HMAC.
- Day/message/profile inputs and update order match the exact schema-4 native profile checked by `checkNativeProfileIntegrity()`.
- Exhaustive byte and table checks apply only to the finite domains named below. Key and state coverage is bounded to deterministic sampled states.

## Exact five-check protocol

`Enigma256Formal.certificate()` returns true only when all five checks hold:

1. **Deterministic four-state scramble-bijection sweep.** `checkScrambleBijection(states: 4, seed: 0xE256_B1)` checks all 256 byte inputs within each of four deterministically sampled frozen states and requires no sweep failure.
2. **Exhaustive byte reciprocity for one frozen fixture state.** `checkScrambleReciprocity(seed: 0xE256_B2)` checks all 256 byte inputs for one deterministic frozen fixture-derived state.
3. **Deterministic 128-byte stream round-trip.** `checkStreamRoundTrip(bytes: 128, seed: 0xE256_B3)` encrypts one deterministic 128-byte stream and decrypts it from the identical initial day/message state, including stepping.
4. **Fixture plugboard plus selected XOR-center involution/fixed-point checks.** `checkDayKeyAndCenterInvolutions()` exhaustively checks the 256-entry fixture plugboard as a fixed-point-free involution. It exhaustively checks XOR-center maps for masks `0x00`, `0x01`, `0xA5`, and `0xFF`: the zero mask has 256 fixed points; each selected nonzero mask has none.
5. **Exact schema-4 native-profile integrity.** `checkNativeProfileIntegrity()` validates the live E256-v2/gen0 identity and profile hash, schema version 4, center/KDF/PRF/counter/map-order identifiers, corrected transition and update order, native reversible component/fold/tap structure, and checked domain separation.

The first two checks exhaust the byte domain only inside five deterministic frozen states. The fourth exhausts one 256-entry plugboard and four selected center masks. Those finite sweeps do not quantify over every key, message state, mask, counter, or stream.

## Reproduction and receipt

Run:

```sh
swift test -c release --filter testEnigma256FormalCertificate
```

The `post_promotion_validation.formal_certificate` entry in `logs/e256-v2-gen0-fixture-v4-validation.json` records **1 test, 0 failures, five checks held**. The broader fixture-v4 suite and cross-implementation parity are C10 evidence, not additional universal clauses of this certificate.

## Explicit non-claims

This protocol is not an IND-CPA proof, not an HMAC-security proof, not external cryptanalysis, and not external review. It does not establish universal key/state coverage, production security, protocol security, or side-channel resistance. Host-derived mask/counter transport and RTL parity do not mean RTL implements HMAC.

**E256-003 remains OPEN** pending human acceptance. AI semantic review does not close it.
