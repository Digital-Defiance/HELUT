# Evidence errata and preservation boundary

This file is additive. It does **not** alter or supersede the sealed preregistration, raw log, receipt, or their hashes.

## Mtime labels

The source and compiled-XCTest mtimes were captured with correct Unix epochs, byte sizes, and content hashes. The human-readable fields in `preregister.json`, `raw.log`, and `receipt.json` were formatted from local Pacific time and incorrectly suffixed with `Z`.

| Artifact | Epoch | Recorded text | Correct local time | Correct UTC time |
|---|---:|---|---|---|
| `Tests/HELUTTests/NativeBaselineComparisonTests.swift` | `1788714090` | `2026-09-06T10:01:30Z` | `2026-09-06T10:01:30-0700` | `2026-09-06T17:01:30Z` |
| compiled `helutPackageTests` executable | `1788714217` | `2026-09-06T10:03:37Z` | `2026-09-06T10:03:37-0700` | `2026-09-06T17:03:37Z` |

This labeling defect does not break source-to-binary binding: the epochs, sizes, source SHA-256, and compiled-XCTest SHA-256 all matched at the pre-execution gate.

## Preserved generated evidence

The bundle contains byte-identical copies of `emitted.v`, `lut6.v`, `flow.ys`, and `tb.cpp`. The still-present run artifact was rehashed during publication handoff and matched the sealed values:

- `resynth.json`: `84ba190a62302f886b63f7607480b0e3f50f27b380f139ce91bb178fac8164fb`, 44,729 bytes.
- `obj_dir/sim`: `60aab5d844d2b5fc36d6efc20ea0b0fe224a2bde12c4afbe847e4a47e1dfacb9`, 360,784 bytes.

Those two generated files are not copied into this directory. Their sidecars identify them, but the bundle must not be described as self-contained for rehashing those bytes. Preserve them in external artifact storage or Git LFS if byte retention is required for publication.

## Capture provenance

`raw.log` was reconstructed from the complete sole-run tool output retained in session context after compaction. It was mechanically validated against all eight widths, phase/native sample counts, totals, digests, fixture hashes, and the XCTest footer. No benchmark rerun was used to repair or replace it.

## Historical predecessor

The coordination note recorded predecessor Git blob `0d389184f6cc341d61e6d71dec6be75d00a79e0e`, but that blob's bytes were not written into the Git object database. The exact predecessor cannot be recovered for a direct byte diff. The current source is Git blob `b0dce16ca9844ce499d07ea090ed4ff7cedae6f9` and SHA-256 `3ee58213f460cbc8a0a316dc90e6edb9a7af5e77426b839fb1d83e8675e490e2`.
