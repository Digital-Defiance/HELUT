# Receipt 02 — C69 functional SING preservation

Result: **PASS for functional equivalence; deliberately no noisy-BK confidence certificate**  
Artifact: `.build/release/helut`  
SHA-256: `9e3d5020db6a6f7b838d158189f2e9783da48412339564193075634ec4e9c46d`

## Command

```bash
make c69-smoke
```

This invokes `Scripts/c69_n512_smoke.sh`, which rejects vacuous path selection, rejects any ordinary scientific `result PASS`, and requires exactly one functional diagnostic receipt. Child return code: `0`.

## Observed contract

- Full-adder netlist: 3 LUTs, 0 DFFs.
- Polynomial degree `N=1024`; LWE dimension `n=512`.
- Exactly one `public-ms covering-b2` path.
- Gaussian BK injection `σ=128`.
- Identity residual trials: `1`.
- Extract-to-key-switch path `kN=1024 → n=512`.
- One evaluated row.
- Wall time: `35.1628 s`.
- Observed maximum residual magnitude: `858907`, sample-decodable.
- `functional result PASS`.
- `result DIAGNOSTIC ONLY — NO NOISY-BK CONFIDENCE CERTIFICATE`.
- Final non-vacuity marker:

```text
PASS: C69 covering-b2 N=1024 / n=512 functional SING equivalence remains (diagnostic-only; no noisy-BK confidence certificate)
PROCESS_RETURN_CODE=0
```

The printed 95% confidence sigma was infinite at one trial, the 24/3-event confidence target did not clear, and the script correctly refused to turn functional agreement into an epsilon certificate.

## Defensible claim

The exact `N=1024`, `n=512`, covering-b2, Gaussian-σ=128, one-vector full-adder path retains end-to-end functional SING equivalence after the Dictionary-order/shared-RNG determinism repair.

## Withdrawn history and remaining boundary

The old `n=512` mismatch remains withdrawn as a harness determinism artifact. This gate does **not** establish a noisy-BK confidence bound, arbitrary-circuit or arbitrary-depth correctness, native `n=N` production PicoRV correctness, `cryptoPublicMS`, full PicoRV `lw`, or a production security level. The post-fix native-dimension PicoRV failures remain separate timed negatives.