# HELUT independent claim-recovery manifest

Receipt set: `claim-recovery-20260906T155604Z`  
Run date: `2026-09-06`  
Repository commit at execution: `4d47ad0ef40c593bb3a0e4ab5aa2e668b917f975`  
Platform: macOS 26.6.2 (`25G83`), arm64  
Swift driver: 1.148.6

## Execution isolation

The repository was dirty and another session owned the active implementation and claim-sheet work. This receipt set therefore does **not** claim clean-tree reproducibility. It records tests of pinned prebuilt artifacts while every pre-existing modified/untracked source, test, directive, README, and reproduction file remained frozen. The coordination record is `../claim-recovery-coordination-20260906T155604Z.md`.

No `swift build` or `swift test` planning was launched. Commands used release executables directly or invoked the prebuilt XCTest bundle with `xcrun xctest -XCTest ...`.

Execution checkpoints at gate start and immediately after all experimental commands:

- `Tests/HELUTTests/NativeBaselineComparisonTests.swift`: Git blob `0d389184f6cc341d61e6d71dec6be75d00a79e0e`.
- `Tests/HELUTTests/TensorLUTYosysRoundTripTests.swift`: Git blob `285441315e1bddf4268059e51cd4ef3629c925c7`.

A final coordination check at `2026-09-06T17:15:48Z` found post-run concurrent drift in the contested native benchmark file: `NativeBaselineComparisonTests.swift` had moved to Git blob `b0dce16ca9844ce499d07ea090ed4ff7cedae6f9`; `TensorLUTYosysRoundTripTests.swift` remained `285441315e1bddf4268059e51cd4ef3629c925c7`. The drift happened after these gates had completed. This session did not edit or build through that file, and no receipt in this directory depends on it.

Tested artifact SHA-256 values:

- `.build/release/helut-compile`: `70927a2e307151ff89f4ae66fd9e6779cb4ffff1e5fa350f8ff68153799b86df`
- `.build/release/helut-bombe`: `d284055ca3b4cb1017fbda2cde56bede31ff52f6c95d3ffa2d245a513334ca8c`
- `.build/release/helut`: `9e3d5020db6a6f7b838d158189f2e9783da48412339564193075634ec4e9c46d`
- `.build/arm64-apple-macosx/release/helutPackageTests.xctest/Contents/MacOS/helutPackageTests`: `d339f1933249d51d808000df2e4ce0312029f00e2060896579537df8fb925ce6`

## Exit-status note

The IDE terminal transport displayed its own trailing `Exit Code: -1` for commands in this session, including harmless metadata commands. Every accepted experimental command was therefore launched through `subprocess.run`, and acceptance required both `PROCESS_RETURN_CODE=0` from the child and the command-specific non-vacuity markers. The first streaming `helut-compile --validate` attempt stopped after Tier 1 and is explicitly excluded; the accepted non-streaming rerun completed all three tiers.

## Receipt index

- `01-compiler-validation.md` — narrow three-tier Enigma validation recovery.
- `02-c69-functional-sing.md` — recovered functional SING path with an explicit no-confidence-certificate boundary.
- `03-tensorlut-proof-ladder.md` — formal, sampled, multi-LUT-boundary, resource-null, and one-DFF evidence.
- `04-bombe-mechanism-controls.md` — known-control garble, indel, GPU parity, and Future-bank qualification.
- `05-negative-ledger.md` — claims that remain withdrawn/open and were not promoted by these passes.

No receipt in this directory depends on `NativeBaselineComparisonTests.swift`.