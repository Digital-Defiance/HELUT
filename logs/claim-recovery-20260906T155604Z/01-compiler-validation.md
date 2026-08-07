# Receipt 01 — three-tier `helut-compile --validate`

Result: **PASS, narrowly recovered**  
Artifact: `.build/release/helut-compile`  
SHA-256: `70927a2e307151ff89f4ae66fd9e6779cb4ffff1e5fa350f8ff68153799b86df`

## Command

```bash
.build/release/helut-compile --validate
```

The accepted run used the same argv through a non-streaming `subprocess.run` wrapper. Child return code: `0`.

## Required and observed markers

```text
Tier 1 — Synthetic ground truth
Assert: lane 42 exclusive plaintext recovery — PASS
Cleartext netlist ≡ oracle for HELUT baseline — PASS

Tier 2 — Historical vector FHPQX (Ostwald/Weierud 1941-07-13)
Decrypt prefix: ANXPANZXGRUPPEXVIERXSIEG
Crib window contains SIEGFR: PASS

Tier 3 — IC / n-gram scoreboard spike detection
Winner IC=0.0680 score=-5.208 plaintext=ANXPANZXGRUPPEXVIERXSIEGFRIE
Spike isolation of SDV among 200 hypotheses — PASS

VALIDATION COMPLETE — tiers 1–3 green.
PROCESS_RETURN_CODE=0
```

Tier 1 also reported the expected synthetic plaintext `KEINEBESONDERENEREIGNISSE`, ciphertext `HNVUSQZJIDSUHTXLZUTMUTMLH`, and key `I-II-III`, rings `AAA`, start `ABC`, with 10 steckers.

## Defensible claim

On the command's default Enigma validation fixture, the three-tier control exclusively recovers the injected lane, checks the clear netlist against an independent Enigma oracle, reproduces the named FHPQX prefix/crib, and isolates the known SDV setting among 200 hypotheses.

## Non-implications

This receipt is **not**:

- a proof that arbitrary Verilog or every supported Yosys netlist compiles correctly;
- an encrypted/FHE result;
- a generic DFF-semantics proof;
- a Metal/MPSGraph throughput result;
- a P1030680 break, key, plaintext, or decrypt.

The first direct streaming invocation emitted only Tier 1 and no final marker. It was rejected rather than counted as a pass.