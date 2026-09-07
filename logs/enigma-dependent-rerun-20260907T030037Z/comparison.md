# Enigma objective-v2 dependent evidence rerun

The known-shell self-test was rerun because it consumes `EnigmaSearchObjective`.
The staged generic/naval and oracle-seed commands do not consume that objective;
they were rerun as binary-bound negative controls and remained byte-identical to
the immediately preceding evidence bundle. Exact commands, binary/source/fixture
hashes, exits, and raw-stdout hashes are in `manifest.json`.

## Why v2 exists

Objective v1 normalized the full bigram/IC/crib attack score with raw-bigram
moments and used raw-bigram/trigram correlation. Objective v2 calibrates the
exact attack score and its paired trigram relationship on the same frozen 400
controls. The random objective mean moves from −0.858794 to approximately zero
(−0.000000637 with six-decimal production constants). V1 is superseded; its
sealed receipts remain historical and are covered by an additive erratum.

## Exhaustive known-shell self-test

| Metric | sparse August control | dense raw-bigram probe | objective v1 (superseded) | objective v2 (current) |
|---|---:|---:|---:|---:|
| Level-1 rank | 223,118 / 456,976 | 223,118 / 456,976 | 223,118 / 456,976 | 223,118 / 456,976 |
| letters correct | 4 / 72 | 21 / 72 | 25 / 72 | **25 / 72** |
| true plugs recovered | 0 / 10 | 4 / 10 | 5 / 10 | **5 / 10** |
| plugs proposed | 7 | 9 | 7 | 7 |
| final verdict | no break | no break | no break | **no break** |

The corrected calibration changes objective coordinates but not the deterministic
candidate: v1 and v2 recover the same plaintext and seven proposed plugs. The
unchanged Level-1 rank confirms that the IC sieve was not altered. The current
candidate remains incomplete and is rejected by the separate fail-closed final
assessment. `bigram-position=1.08` is diagnostic, not probability or confidence.

## Generic versus leave-one-out naval trigrams

| len | August generic win / margin | current generic win / margin | August naval win / margin | current naval win / margin |
|---:|---:|---:|---:|---:|
| 72 | 7% / -0.2735 | **17% / -0.2306** | 7% / -0.2763 | **13% / -0.2496** |
| 100 | 17% / -0.0996 | 17% / -0.2070 | 17% / -0.1048 | 17% / -0.2241 |
| 140 | 17% / -0.1062 | 0% / -0.1475 | 8% / -0.1168 | 0% / -0.1397 |
| 180 | 33% / -0.0114 | 17% / -0.1287 | 33% / -0.0277 | 17% / -0.1381 |
| 252 | 67% / +0.4957 | **100% / +0.9273** | 67% / +0.5428 | **100% / +1.1531** |

Both v2-binary stdout hashes exactly match the preceding bundle. At the target
72 symbols both margins remain negative, and naval is slightly worse than
generic. Naval improves only the already-winning 252-symbol arm. This benchmark
retains the historical staged IC→bigram→trigram scorer; it measures ranking and
never emits a publication verdict.

## Oracle plug-seeding ladder

| oracle plugs | August win / margin | current win / margin | current median plugs / letters |
|---:|---:|---:|---:|
| 0 | 40% / -0.1503 | 20% / -0.1226 | 1/10 / 7% |
| 2 | 20% / -0.0991 | 30% / -0.1005 | 3/10 / 11% |
| 4 | 70% / +0.1296 | **50% / +0.3308** | 6/10 / 47% |
| 6 | 90% / +0.6656 | **90% / +0.6656** | 8/10 / 85% |
| 8 | 100% / +1.0488 | **100% / +1.0488** | 10/10 / 100% |

All five v2-binary stdout hashes exactly match the preceding bundle. The sign
still flips at four oracle-correct plugs. This remains an oracle-seeded upper
bound on finishing a true Bombe stop, not a way to find one and not a break of
P1030680.
