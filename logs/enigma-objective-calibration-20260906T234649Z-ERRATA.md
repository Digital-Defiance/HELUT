# Errata for the sealed v1 Enigma objective attestation

This note is additive. It does **not** modify the sealed files under
`logs/enigma-objective-calibration-20260906T234649Z/`.

## Scientific correction

Semantic review found that v1 standardized `HostM4Bombe.attackScore` with the
random mean and population deviation of the raw bigram score. `attackScore` also
contains the variable IC penalty and configured-crib bonus, so those moments do
not describe the quantity being standardized. V1 likewise discounted trigrams
with raw-bigram/trigram correlation rather than attack-score/trigram correlation.
The v1 random objective mean was therefore −0.858794 rather than approximately
zero.

Objective v2 calibrates the exact attack score on the same frozen 400 × 72-symbol
controls. Independent Python and Ruby implementations agree on attack mean
`0xc013ca64ce71e32b`, attack population deviation `0x3fcde0455070675d`, and
attack/trigram correlation `0x3fe00553b8b446b6`. Production v2 and its receipts
are sealed under `logs/enigma-objective-calibration-20260907T025406Z/`.

## V1 receipt-byte provenance correction

Before the v2 scripts replaced the v1 script bytes, fresh read-only execution of
the exact Python and Ruby files bound by the v1 manifest showed that the stored
receipt JSON was a projected/compacted representation, not direct stdout:

| Implementation | Bound script SHA-256 | Stored receipt SHA-256 / bytes | Fresh stdout SHA-256 / bytes |
|---|---|---|---|
| Python | `4c6aabdf659e201a6905a1e4a1ae4dae0de31e4826c7be1de796684e6d3e9452` | `e2fa3d9a056798b1b36ebb7c3dda014cd0269cc248a5366ba821f91dc5f5d407` / 3,547 | `38ecf844047e3b965abfbd0ebe14654f3a9e39ba736a2cd961dd4b58df6c3bba` / 4,790 |
| Ruby | `db18a50dba91b4e6c59e35ed6cbccc8ffeb938eb93fac20e9b01453afee547b5` | `ef5e01fcffbfb4f112c353bd6865e90b553759317b888dacd09465440b6b8acf` / 3,620 | `eddb3667e779affd940a6989537c5043a41fe885143c813dd5d7e2fcc2f7a18c` / 4,830 |

Fields common to stored and fresh v1 JSON agreed, including every reported
binary64 calibration pattern. The stored receipts omitted model order/add-k,
attack and discount definitions, rounded constants, and candidate IC fields;
they also used compacted formatting. No transformation was documented, so the
v1 manifest must not be read as proving direct source-to-stdout byte
reproducibility.

V2 fixes that provenance defect as well: each external receipt is unmodified
stdout, and the v2 manifest binds its exact byte count and SHA-256 and records a
fresh byte-identical replay.

## Immutable parent hashes

- V1 manifest: `af9658e5809c55738c76c82fd6346e49519554b07e4ad7999cf83c784d2bf75a`
- V1 Python receipt: `e2fa3d9a056798b1b36ebb7c3dda014cd0269cc248a5366ba821f91dc5f5d407`
- V1 Ruby receipt: `ef5e01fcffbfb4f112c353bd6865e90b553759317b888dacd09465440b6b8acf`

Those bytes remain historical evidence of the superseded v1 process; they are
not current calibration evidence.
