# Enigma-dependent evidence rerun

Only receipts whose scores depend on the German n-gram model were rerun. The IC-only lane sieve is retained as an internal control. Exact commands, binary/source/fixture hashes, exits, and raw-stdout hashes are in `manifest.json`.

## Exhaustive known-shell self-test

| Metric | sparse August control | dense raw-bigram probe | repaired objective |
|---|---:|---:|---:|
| Level-1 rank | 223,118 / 456,976 | 223,118 / 456,976 | 223,118 / 456,976 |
| letters correct | 4 / 72 | 21 / 72 | **25 / 72** |
| true plugs recovered | 0 / 10 | 4 / 10 | **5 / 10** |
| plugs proposed | 7 | 9 | 7 |
| final verdict | no break | no break | **no break** |

The unchanged Level-1 rank confirms that the IC sieve was not altered. The repaired phase-2 objective improves recovery again, but its partial plaintext is still rejected by the independent final assessment. The `bigram-position=1.08` value is diagnostic, not probability or confidence.

## Generic versus leave-one-out naval trigrams

| len | old generic win / margin | new generic win / margin | old naval win / margin | new naval win / margin |
|---:|---:|---:|---:|---:|
| 72 | 7% / -0.2735 | **17% / -0.2306** | 7% / -0.2763 | **13% / -0.2496** |
| 100 | 17% / -0.0996 | 17% / -0.2070 | 17% / -0.1048 | 17% / -0.2241 |
| 140 | 17% / -0.1062 | 0% / -0.1475 | 8% / -0.1168 | 0% / -0.1397 |
| 180 | 33% / -0.0114 | 17% / -0.1287 | 33% / -0.0277 | 17% / -0.1381 |
| 252 | 67% / +0.4957 | **100% / +0.9273** | 67% / +0.5428 | **100% / +1.1531** |

The dense model changes individual rates but not the decision. At the target 72 symbols both median margins remain negative, and the naval model is slightly worse than generic. Naval specialization only improves the already-winning 252-symbol arm. This benchmark intentionally retains the historical staged IC→bigram→trigram scorer; it measures ranking and never emits a publication verdict.

## Oracle plug-seeding ladder

| oracle plugs | old win / margin | new win / margin | new median plugs / letters |
|---:|---:|---:|---:|
| 0 | 40% / -0.1503 | 20% / -0.1226 | 1/10 / 7% |
| 2 | 20% / -0.0991 | 30% / -0.1005 | 3/10 / 11% |
| 4 | 70% / +0.1296 | **50% / +0.3308** | 6/10 / 47% |
| 6 | 90% / +0.6656 | **90% / +0.6656** | 8/10 / 85% |
| 8 | 100% / +1.0488 | **100% / +1.0488** | 10/10 / 100% |

The sign still flips at four oracle-correct plugs. Six- and eight-plug rows are byte-for-byte numerically unchanged because those climbs are already in the trigram-dominated stage. This remains an oracle-seeded upper bound on a future Bombe coupling, not a break of P1030680.
