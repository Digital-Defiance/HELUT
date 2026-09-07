# Claim-recovery coordination freeze

Timestamp: `2026-09-06T15:56:04Z`

This session is deliberately separated from the concurrent implementation/claim-sheet session.

## Files this session will not edit

- `Tests/HELUTTests/NativeBaselineComparisonTests.swift` — contested/untracked; checkpoint Git blob `0d389184f6cc341d61e6d71dec6be75d00a79e0e`.
- `Tests/HELUTTests/TensorLUTYosysRoundTripTests.swift` — concurrently modified; checkpoint Git blob `285441315e1bddf4268059e51cd4ef3629c925c7`.
- Every pre-existing modified or untracked HELUT source, test, directive, README, and reproduction file visible in the `2026-09-06T15:5xZ` working-tree snapshot.
- In particular: `README.md`, `REPRODUCE.md`, `directives/claim-sheet.md`, `directives/parameter-cookbook.md`, `directives/research-release.md`, `Sources/HELUTCLI/CLIFlags.swift`, `Sources/HELUTCore/EncryptedNetlistSim.swift`, `Sources/HELUTCore/TFHENoisyBK.swift`, `Sources/HELUTToolKit/HelutBench.swift`, and all new benchmark/evolution implementation tests.

No benchmark instrumentation or optimization will be reapplied. No `swift build` or `swift test` build planning will be launched while this freeze is active. Existing gates will be exercised only through prebuilt release executables or the prebuilt release XCTest bundle.

## Files this session may create or edit

- New append-only evidence under `logs/claim-recovery-*`.
- Episode scripts that were clean at the coordination snapshot, after a fresh pre-edit status check: ep01, ep03, and ep04.
- A narrowly targeted correction to another episode only if its pre-edit hash is pinned and it is not changing concurrently.

## Scientific boundary

This session may recover a claim only when a named executable gate passes and the receipt records the exact command, output, scope, and non-implications. It will not try to recover:

- cleartext batch throughput superiority;
- native-dimension noisy PicoRV32 at the known failing parameters;
- arbitrary TensorLUT/GA completeness or an area/depth win over ABC;
- P1030680 corruption, key, plaintext, decrypt, or global elimination;
- discrete-GPU superiority.

The independent candidate fronts are the three-tier `helut-compile --validate` control, circuit-scoped encrypted SING, the TensorLUT formal certificate, known-control Bombe/garble/indel mechanisms, bounded sampled-search/SAT proof, and one-DFF sequential induction.

## Final concurrent-drift check

At `2026-09-06T17:15:48Z`, after all independent gates had completed, `Tests/HELUTTests/NativeBaselineComparisonTests.swift` no longer matched the execution checkpoint: Git blob `0d389184f6cc341d61e6d71dec6be75d00a79e0e` had moved to `b0dce16ca9844ce499d07ea090ed4ff7cedae6f9`. `Tests/HELUTTests/TensorLUTYosysRoundTripTests.swift` remained at `285441315e1bddf4268059e51cd4ef3629c925c7`.

This session did not edit, rebuild through, or rerun the native benchmark after that drift. The independent claim-recovery receipts use pinned prebuilt artifacts and do not depend on `NativeBaselineComparisonTests.swift`. The changed file remains owned by the concurrent session.