# Defect and lever: the bigram stage of the staged scorer is data-starved

- Found: 2026-09-06, during episode fact-checking
- Status: **RESOLVED IN CODE — dense bigram model and attack-calibrated objective v2 landed; dependent runs re-banked; historical receipts preserved**
- Severity: affected every cryptanalysis score that passed through stage 2
- Evidence boundary: applying each lever changed scoring output. Historical
  filmed and text receipts remain sealed rather than being silently rewritten;
  successor evidence is banked in timestamped bundles.

## What is wrong

The staged scorer runs index of coincidence, then bigrams, then trigrams. Those
three stages do **not** draw on comparable amounts of language data.

| Stage | Source | Letters behind it | Cells | Empty cells | Mean count/cell |
|---|---|---:|---:|---:|---:|
| trigram | `Fixtures/german_trigrams.txt`, loaded at runtime | 28,508,834 | 14,947 grams | — | — |
| bigram | `LanguageScorer.germanBigramCounts`, compiled in | **10,359** | 676 | **235** | **15.3** |

Meanwhile `Fixtures/german_bigrams.txt` already exists in the repository, is
built from the same 28.5-million-letter corpus as the trigram table, and is
**not** read by `LanguageScorer`:

| Available but unused | Letters | Entries | Mean count/cell |
|---|---:|---:|---:|
| `Fixtures/german_bigrams.txt` | 28,508,833 | 674 | 42,172.8 |

That is **2,752× more data** than the table actually in use.

## Verification

Sum of the compiled-in array, read directly from source:

```text
embedded germanBigramCounts entries: 676
embedded sum                       : 10,358      (= 10,359 corpus letters - 1)
nonzero cells                      : 441 of 676
mean count per cell                : 15.3
```

Sum of the unused fixture:

```text
Fixtures/german_bigrams.txt sum    : 28,508,833
Fixtures/german_bigrams.txt entries: 674
mean count per cell                : 42,172.8
```

Both `Fixtures/german_bigrams.txt` and `Fixtures/german_trigrams.txt` carry the
header `# letters=28508834 ic=0.0747`, and their counts sum to 28,508,833 and
28,508,832 respectively — consistent with n−1 bigrams and n−2 trigrams over the
same corpus. The tables are internally consistent; the compiled bigram table is
the outlier.

Provenance of the small table: `Sources/HELUTCore/LanguageScorer.swift` documents
it as coming from `Fixtures/german_corpus.txt` (10,359 letters, IC 0.0749), and
`Scripts/build_bigrams.py` generates it from that file. `Fixtures/german_corpus.txt`
is a 187-line sample, not the scoring corpus.

## Why it matters

235 of 676 bigram cells have **zero** count. A zero-count cell means any
candidate plaintext containing an uncommon-but-valid German bigram is penalized
as impossible rather than merely unlikely. At 15.3 mean counts per cell the
surviving cells are also noisy. So stage 2 is both sparse and brittle, while
stage 3 is dense.

This is the mechanism most likely to be discarding correct candidates before the
trigram stage ever sees them, which is exactly the failure mode the staged design
was introduced to avoid.

## The lever

Regenerate the compiled table from the 28.5M-letter fixture instead of the
187-line sample:

1. Point the generator at `Fixtures/german_bigrams.txt` (or have `LanguageScorer`
   load it at runtime, matching how `TrigramScorer` already resolves its table).
2. Expected direct effects: empty cells fall from 235 toward 2, and mean count
   per cell rises from 15.3 to roughly 42,173.
3. Re-run `--exhaust-selftest` and the naval A/B to measure whether the 72-letter
   result moves at all.

`TrigramScorer.swift` already implements runtime fixture resolution with a search
over candidate roots, so the same pattern can be reused rather than invented.

## Cost of applying it

Every existing cryptanalysis receipt was produced with the starved table:

- `logs/exhaust-selftest-revalidate-2026-08-15.log` (the `NO BREAK` ceiling)
- `logs/ostwald-naval-ab-2026-08-17.log` (the naval-versus-generic null)
- `logs/ostwald-bombe-seed-ladder-2026-08-17.log` (the plug-seeding ladder)

Those numbers are filmed in ep04 and ep10. Applying the lever changes the scoring
function, so all three must be re-run and the affected episode material re-cut.
Do not apply it as a quiet cleanup.

## What this corrects in published material

`ep10/the-real-bottleneck` stated that the corpus behind the scorer is about
10,300 letters and is too thin for trigrams. That is half wrong and half
understated:

- **Wrong about trigrams.** The trigram table is built from 28,508,834 letters
  with 14,947 distinct grams. It is not thin, and it is not the constraint.
- **Right about bigrams, and worse than stated.** The bigram stage really is
  running on ~10,300 letters, and it has 235 empty cells.
- **Wrong that it is an unaddressed data problem.** The larger table is already
  committed in `Fixtures/`. This is a wiring defect, not a data-collection task.

The episode's other bottleneck items remain receipted and unaffected: the sieve
ranking the true key at 223,118 of 456,976, and the plug-seeding ladder where
seeding 4 plugs flips the median margin from −0.1503 to +0.1296 and seeding 8
plugs reaches 100% wins with 10/10 plugs recovered.

---

# APPLIED AND MEASURED — 2026-09-06T21:32:05Z

The lever was applied, measured, and then **reverted**. The tree ships the sparse
table. Everything below is reproducible from the two banked logs.

## Correction to this document

The claim above that an empty cell "scores valid German as impossible" is wrong.
`germanBigramLogProbs` is add-k smoothed with k = 0.5, so an unobserved cell gets
`log(0.5 / (rowTotal + 13))` — a finite floor, not negative infinity. The real
defect is weaker but still real: **235 cells collapse onto one identical floor
value and carry no discriminating information**, and the 441 observed cells are
estimated from a mean of 15.3 counts each.

Also worth recording: `DenseNGramAuditReceipt.bigramFloorWindowStarts` is empty,
so on the 72-letter control plaintext itself **no** bigram window hit the floor
even with the sparse table. The holes bind during search, where millions of
candidate plaintexts are scored, not on the reference text.

## Control

The current release binary reproduces `exhaust-selftest-revalidate-2026-08-15.log`
byte for byte (banked as `exhaust-selftest-sparse-control-20260906T213205Z.log`),
so the run is deterministic and any change is attributable.

## Result

Banked as `exhaust-selftest-dense-bigrams-20260906T213205Z.log`.

| Metric | sparse (10,359 letters) | dense (28.5M letters) |
|---|---:|---:|
| Level 1 rank | 223,118 / 456,976 | 223,118 / 456,976 |
| Level 1 percentile | top 48.825% | top 48.825% |
| **Level 2 letters correct** | **4 / 72 (6%)** | **21 / 72 (29%)** |
| **Level 2 plugs correct** | **0 / 10** | **4 / 10** |
| plugs proposed | 7 | 9 |
| reference plaintext bigram | −2.8719 | −3.3787 |
| recovered bigram | −3.1270 | −3.3039 |
| likeness | 0.80 | 1.00 |
| Level 3 verdict | NO BREAK | **NO BREAK** |

Level 1 is unchanged, which is the expected internal control: that stage sieves on
index of coincidence and never touches the bigram table. Only the bigram-dependent
stage moved.

**The lever works.** Letters correct improved 5.25×, and plug recovery went from
nothing to 4 of 10.

## But it exposed a second defect, and this one is worse

Under the dense table the recovered text scores **better than the true
plaintext**: −3.3039 against −3.3787. The hill-climb is now finding candidates the
objective prefers over the correct answer, and `likeness` saturated at 1.00 on
text that is plainly not German:

```text
LLLWOHLARGULATTUSZITSPAMIROOOLOSTIKETTOLZFFNLIKDIBAKRJLDNRITZAUDHEMZEKKS
```

So mean bigram log-probability is not a correct objective at this message length.
Better language data made the search better at maximising the wrong thing. The
binding constraint is the **objective and the verdict metric**, not the corpus.
That is the next lever, and it is a more interesting one.

## Recalibration measured

`Calibration` reference points are tied to the table's scale, and `EnigmaM4.swift`
derives `likeness` from `germanMean` and `randomMean`.

| Reference point | sparse | dense |
|---|---:|---:|
| German 72-letter sample | −2.84 | −3.309 |
| random mean (n=400) | −4.29 | −4.656 |
| random sd | 0.17 | 0.247 |
| separation | 8.53 sd | 5.45 sd |

Separation gets **worse**, because the sparse table was built from the same
187-line sample the naval register came from and was therefore register-overfit.
Its 8.53 sd was partly measuring "resembles my sample", not "is German".

## Why it was reverted rather than kept

`DenseNGramAuditReceipt` in `Tests/HELUTTests/P1030684SparseControlFixtureTests.swift`
carries the comment: *independently audited in read-only Python and Ruby
implementations … intentionally not derived from the Swift evaluator*. Its two
bigram bit patterns (`0xc075_02db_7cf3_4e60`, `0xc006_99a9_6621_ac81`) failed
under the dense table, exactly as they should. The trigram patterns passed,
confirming the change was scoped to bigrams.

Regenerating those constants from Swift would destroy the three-way independent
agreement that makes them evidence. They must be recomputed by the Python and
Ruby implementations first. Until that happens, keeping the dense table would mean
shipping a red test and a stale attestation.

## To apply it properly

1. Recompute the bigram bit patterns in the read-only Python and Ruby
   implementations against the dense table; update `DenseNGramAuditReceipt` from
   those, not from Swift.
2. Move the floor probe in `MuleinGermanNGramModelTests` from `AJ` (1,200 in the
   dense table) to `JX` or `QY`, the only two bigrams still unobserved.
3. Update `LanguageScorer.Calibration` to the dense reference points above.
4. Fix the objective before trusting the improvement, since `likeness` currently
   saturates on non-German text.
5. Re-run and re-cut the affected filmed material: `exhaust-selftest`, the naval
   A/B, and the seed ladder, which are on camera in ep04 and ep10.

`Scripts/build_bigrams.py` now requires `--source` so that regenerating cannot
silently swap the model. `--source corpus` reproduces the shipped table exactly;
this was verified after the revert.

---

# OBJECTIVE V1 CALIBRATION — SUPERSEDED 2026-09-07

This section preserves the v1 chronology and measurements. V1 is not the current
calibration; the attack-score calibration defect and v2 replacement are recorded
below.

The dense table remains landed, but raw bigram likelihood is no longer the
phase-2 publication story. The objective and the final decision are now separate
APIs with separate evidence.

## Frozen calibration

`Fixtures/german_trigrams.txt` is bound by SHA-256
`e08a56593d1e74b88d300e35b18dd504bc5fffef8ae03db51d72e6270e9509d7`
and model ID `helut-german-trigram-add-k-0.5-e08a5659-v1`.
Independent Python and Ruby implementations scored the same 400 deterministic
72-symbol controls used by dense-bigram calibration and agreed bit-for-bit:

| Quantity | Decimal | Binary64 |
|---|---:|---:|
| trigram German reference | −2.9671219321853144 | `0xc007bcaa6c6fd790` |
| trigram random mean | −5.1000271107154695 | `0xc014666d81c4f1fc` |
| trigram random population SD | 0.2482559206812514 | `0x3fcfc6d99a2ea2da` |
| bigram/trigram random correlation | 0.5175068467419289 | `0x3fe08f6a84c6ce2f` |

The production ranking model is
`helut-enigma-search-n72-correlation-discounted-z-06f8694e-e08a5659-v1`:

```text
attackZ  = (HostM4Bombe.attackScore - bigramRandomMean) / bigramRandomSD
trigramZ = (trigram - trigramRandomMean) / trigramRandomSD
weight   = 1 - roundedRandomCorrelation = 0.482493
objective = (attackZ + weight * trigramZ) / (1 + weight)
```

The correlation discount prevents the two corpus-derived models from counting
all shared signal twice while retaining the smoother bigram/IC/crib gradient as
the primary search component. This is a ranking heuristic, not confidence.
Receipts are sealed under
`logs/enigma-objective-calibration-20260906T234649Z/`.

## Measured lever

On the frozen 72-symbol P1030684 true shell:

| Phase-2 objective | Letters correct | True plugs recovered | Plugs proposed |
|---|---:|---:|---:|
| dense bigram | 21/72 | 4/10 | 9 |
| equal-z bigram/trigram experiment | 21/72 | 5/10 | 7 |
| correlation-discounted production objective | **25/72** | **5/10** | **7** |

The production result is deterministic:

```text
NNNWOLNARSUNSTTOSOITSXDMIROOONISSIKETTONZWBGNIKSIBATRONDORIVZAUDLEGSEKKS
```

A broad exact-depth beam was rejected: width 2 happened to reach 29/72 and 6/10,
but wider beams selected higher-objective nonsense and an exact ten-plug
requirement is not valid for generic traffic. The shipped change remains the
bounded greedy climb with `maxPlugs` as an upper bound.

## Confidence repair

`germanLikeness` was renamed to `bigramCalibrationPosition`. It is explicitly an
unbounded affine diagnostic: zero is the frozen random reference and one is one
frozen German reference. It is not a probability.

ToolKit final assessment now requires all of:

1. the Core bigram-position, IC, and structural-crib gate;
2. the exact hash-bound trigram fixture being available; and
3. trigram score above the existing conservative −3.600 post-Bombe threshold.

Missing trigram evidence fails closed. Exhaustive reports, hybrid early halt and
final report, and the campaign entry use this assessment; post-Bombe publication
also refuses to announce without a loaded exact trigram model. The true control
passes. Both the frozen dense-bigram overfit and the improved but still partial
phase-2 recovery fail. Ranking improvement therefore cannot become a break claim.

The 456,976-lane IC sieve, its Metal/CPU paths, and the hybrid GPU batch shape are
unchanged. The hybrid CPU/Metal IC target was only synchronized from stale 0.0749
to the attested `LanguageScorer.Calibration.germanIC` value 0.0747.
---

# OBJECTIVE V2: CALIBRATE THE SCORE ACTUALLY RANKED — 2026-09-07T02:54:06Z

Semantic review found a second-order calibration defect in v1. The search ranks
`HostM4Bombe.attackScore`, which is dense bigram score plus a variable IC penalty
and configured-crib bonus. V1 centered and scaled that quantity with **raw
bigram** moments and discounted it with **raw bigram/trigram** correlation. The
Python, Ruby, and Swift implementations agreed on the arithmetic, but all three
were reproducing the wrong stated protocol. V1's random objective mean was
−0.858794 rather than approximately zero.

V2 keeps the exact same fixtures, 400 deterministic 72-symbol controls, attack
formula, trigram calibration, IC sieve, and search algorithm. It calibrates the
attack score itself and computes covariance against the paired trigram scores:

| Quantity | Decimal | Binary64 |
|---|---:|---:|
| attack random mean | −4.947650170994886 | `0xc013ca64ce71e32b` |
| attack random population SD | 0.23340670039834324 | `0x3fcde0455070675d` |
| attack/trigram covariance | 0.02900997746102821 | `0x3f9db4caa1cfae49` |
| attack/trigram correlation | 0.5006502730850204 | `0x3fe00553b8b446b6` |
| v2 random objective mean | −0.0000006371431262240657 | `0xbea561048d3b051f` |
| v2 random objective population SD | 0.8821346353073959 | `0x3fec3a726a2a0d89` |

The production ranking model is
`helut-enigma-search-n72-correlation-discounted-z-06f8694e-e08a5659-v2`:

```text
attackZ  = (HostM4Bombe.attackScore - (-4.947650)) / 0.233407
trigramZ = (trigram - (-5.100027)) / 0.248256
weight   = 1 - roundedAttackTrigramCorrelation = 0.499350
objective = (attackZ + weight * trigramZ) / (1 + weight)
```

Python and Ruby independently recomputed the fixtures and emitted direct stdout
receipts; Swift matched every v2 calibration and candidate bit pattern. Receipts
are sealed under `logs/enigma-objective-calibration-20260907T025406Z/`.

The corrected coordinates do **not** change the deterministic known-shell
candidate: it remains 25/72 letters, 5/10 true plugs, 7 proposed, and `NO BREAK`.
The objective values move to 7.7110 at truth and 6.7292 at the recovered
candidate. Generic/naval staged rows and all K=0/2/4/6/8 seed rows do not consume
this objective; rerunning them against the v2 binary produced byte-identical
stdout. The binary-bound successor evidence is
`logs/enigma-dependent-rerun-20260907T030037Z/`.

Final assessment remains a **separate fail-closed publication gate**, not
statistically independent evidence: ranking and assessment inspect the same
candidate and share corpus-derived n-gram evidence. User-facing text now says
separate/fail-closed. Missing trigram models print `unavailable` in the known-shell
diagnostics, and the Ostwald escalation/curve entry points abort rather than
silently treating a bigram fallback as trigram evidence.

The v1 files remain byte-for-byte historical. An additive provenance and
scientific erratum is recorded at
`logs/enigma-objective-calibration-20260906T234649Z-ERRATA.md`; it also documents
that the v1 stored external receipts were compacted projections rather than the
direct stdout their manifest appeared to imply.
