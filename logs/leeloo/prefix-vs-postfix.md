# Leeloo: pre-fix vs post-fix (determinism fix 8e76919)

Same 23 rows, same machine (M4 Max), 5 passes + warmup each.

| Row | Tier | pre-fix stability | post-fix stability | pre median | post median |
|-----|------|-------------------|--------------------|-----------:|------------:|
| C38 | A | stable-pass | stable-pass | 0.0006 s | 0.0009 s |
| C39 | A | stable-pass | stable-pass | 0.0383 s | 0.05 s |
| C40 | A | stable-pass | stable-pass | 0.0051 s | 0.0079 s |
| C45 | A | stable-pass | stable-pass | 0.0479 s | 0.0497 s |
| C46 | A | stable-pass | stable-pass | 0.4704 s | 0.4894 s |
| C47 | A | stable-pass | stable-pass | 1.515 s | 1.562 s |
| C49 | A | stable-pass | stable-pass | 2.288 s | 2.356 s |
| C58 | A | stable-pass | stable-pass | 0.1621 s | 0.1587 s |
| C59 | A | stable-pass | stable-pass | 0.1635 s | 0.1591 s |
| C6 | A | stable-pass | stable-pass | 0.0006 s | 0.001 s |
| C63 | A | stable-pass | stable-pass | 1.784 s | 1.745 s |
| C64 | A | stable-pass | stable-pass | 0.2833 s | 0.2768 s |
| C64b | A | stable-pass | stable-pass | 4.304 s | 4.335 s |
| C20 | B | stable-pass | stable-pass | 9.199 s | 9.191 s |
| C21 | B | stable-pass | stable-pass | 9.954 s | 9.924 s |
| C38m | B | stable-pass | stable-pass | 7.012 s | 7.003 s |
| C39m | B | stable-pass | stable-pass | 22.66 s | 22.7 s |
| C40m | B | stable-pass | stable-pass | 11.45 s | 11.45 s |
| C52 | B | FLAKY:CRASH(signal 5)+PASSx1,PASS/PASSx4 | stable-pass **fixed** | 44.26 s | 43.51 s |
| C57 | B | stable-pass | stable-pass | 10.73 s | 10.24 s |
| C67 | B | stable-pass | stable-pass | 8.631 s | 8.583 s |
| C69 | B | stable-pass | stable-pass | 17.28 s | 17.28 s |
| C69fail | B | FLAKY:CRASH(signal 5)x2,PASSx3 | stable-pass **fixed** | 35.49 s | 34.29 s |

Two rows moved, both from FLAKY to stable-pass: **C52** and **C69fail**.
Every other row was already stable and stayed stable; timings shift by a few
percent, which is ordinary run-to-run spread and not attributable to the fix.

Timings are the tool's own reported wall where available. Note that process
wall can be much larger — C52 reports 43 s internally while the process takes
280 s — and it is process wall that a sweep actually costs.
