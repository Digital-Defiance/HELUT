# Claim re-validation, 2026-08-15

Independent re-check of the claim inventory by a second model (Opus), on the
current laboratory hardware. **This is not the human gate.** It is a different
model with different failure modes reading the same evidence, which is worth
something and is not worth the same thing. Every row below still needs a human
to look at the receipt before it counts as human-checked.

Hardware / toolchain: Apple M4 Max, 64 GB, macOS 26.6.1, Swift 6.3.3
(`swiftlang-6.3.3.1.3`), target `arm64-apple-macosx26.0`.

Mechanical lint, runs on Linux in CI and takes under a second:

```bash
python3 Scripts/claim_audit.py
```

## 1. Defects found and fixed

### 1.1 A seed-fragile test in the encrypted path (not a regression)

**Short answer to "did something break?": no.** The cryptography is fine. A test
that was only ever true by luck finally drew an unlucky RNG stream.

`testBlindRotateIdentityAndXOR` failed in the full suite:

```
XCTAssertEqual failed: ("4294967264") is not equal to ("0")
XCTAssertEqual failed: ("4294967281") is not equal to ("1")
```

Both errors are exact multiples of `twoN = 16`: `-32` and `-16`. Root cause is a
contract mismatch, not broken cryptography. `encryptLWERotationNative` reduces
both `a` and `b` modulo `2N`, so the ciphertext lives in `Z_{2N}`; `decryptLWE`
subtracts the mask over the full `UInt32` ring with no mod-`2N` reduction, so
what it returns is `message - j*2N`. The assertion compared that raw phase to a
bare bit.

The same file already used the correct idiom for exactly this case
(`decodeRotationNativeBit(decryptLWE(...), twoN:, k:)`). The bit-level
assertions in the same test passed, so no C row was overstated — but the suite
was red, which taints every claim that leans on it.

**Provenance.** `git log -S` puts `encryptLWERotationNative` and this assertion
in the same commits (`5f0a68f`, `7c00053`), so this was never a passing test that
later broke. It was latently wrong from the day it was written. At these
parameters — `booleanTrivial(degree: 8)`, so `n = 8` and `2N = 16`, with
`a_i ∈ [0,16)` and `s_i ∈ {0,1}` — raw equality holds only when the mask sum
stays under `2N`, which happens about **15.8%** of the time:

```
P(no wraparound at n=8, 2N=16) ≈ 0.158   (200k trials)
```

So the assertion was a property of the RNG stream, not of the cryptography. The
test is seed-deterministic (`seed: 0xB107`, `LCG32(state: 0xB108)`), and
`bootstrapKey` draws from the same `rng` *before* the encrypt — so any change to
how much RNG the bootstrap key consumes reshuffles the `a` vector and flips the
outcome. C64's extract→KS work is a plausible trigger. The fix removes the
coin flip: the assertion now holds for the right reason at any seed.

**Systemic check:** only two sites in the whole test tree compared a raw
`decryptLWE` result to a bare bit. The other is the zero-secret control on the
line above, where a zero mask makes it sound; it now says so in a comment.

Fixed by decoding with `decodeRotationNativeBit`, with a comment recording why
raw equality is wrong so it does not get "fixed" back. The zero-secret control
above it also got a comment: raw equality is sound there only because a zero
secret cannot wrap.

### 1.2 A measured failure wearing a green "Reproduced" label

`textbook/chapters/metal-compiler.tex:23` wrapped an 11.6-hour host encode that
never reached the GPU and died `SIGTERM 143` in a green `\reproduced` box, keyed
to the free-text string `fused $N=1024$ DNF` rather than any claim id. The prose
was honest; the box semantics were not, and a reader skimming box colours would
have counted it as a receipt.

Added `\negativebox` to `preamble.tex` (purple, "Measured negative") and moved
it there. Doctrine prints clean negatives; they must not be green.

### 1.3 Two more boxes keyed to non-claims

`torus-fhe.tex:111` used `\reproduced{H2 closed}` and `laboratory.tex:50` used
`\reproduced{C6, H2 closed}`. Both are now keyed to `C6`, the row that actually
closed H2, with the closure noted in prose. Any script harvesting box keys would
have tripped on these.

### 1.4 Non-implications had no IDs

`.cursor/rules/` and `writeup.tex` cite **N5**, **N6**, **N7** by number, but the
claim sheet carried the non-implications as an unnumbered prose list, so those
citations had no resolvable target. Numbered **N1–N9** preserving the original
clause order, so existing references keep their meaning:
N5 = P1030680 decrypted, N6 = campaign fitness = encrypted tick rate,
N7 = TensorLUT = U-534 break. All three match how the rules use them.

### 1.5 A stale regeneration command in a committed artifact

`enigma_m4_tensorlut_baseline.v` instructed the reader to regenerate it with
`--emit-tensorlut-verilog --emit-out`. Neither flag exists: the generic
per-netlist emit path was dropped from the CLI in the packaging split, and the
only surviving emit flags are `--enigma256-*`, which cover the `enigma_256_*`
modules only. Running the documented command prints the tool banner and exits.

Header corrected to say so, to point at the live library-level emitter
(`TensorLUTEmitter.emitVerilog`, covered by `testEmitVerilogTwoBitAdderStructure`
and `testInitHexRoundTripMatchesCleartextDecode`), and to record that re-emitting
this specific file needs a generic-netlist entry point that does not exist yet.
That gap is now printed on C8 rather than hidden.

### 1.6 Claim references that a script cannot read

26 sites called `\cid{}` / `\hid{}` / `\nid{}` with an empty argument as a
generic noun ("a new `\cid{}` row"). It rendered fine and made claim references
non-extractable, which is why drift went unnoticed. Added `\claimkind{C}` and
converted all 26.

### 1.7 A theorem named in the index but never stated

`appendices/claim-index.tex` labelled C27 "Theorem 3", and `certificates.tex`
asserted its successor Theorem 3′ (C29) inside a box, but no chapter ever stated
Theorem 3. That is the exact shape a hallucinated theorem would take, even though
this one is real and machine-checked. Now stated as
`\begin{theorem}[Exact public-MS covering degrees]` with its `\reproduced{C27}`
box and a pointer to `GGSWPublicMSCovering.certificate()`.

## 2. The eight unfalsifiable rows: receipts earned, not withdrawn

An audit found C1–C3 and C8–C12 with no command, no test, and no log — prose
pointers only. All eight are campaign / Phase-21 era. The evidence turned out to
exist on disk in every case; it had simply never been cited. None was
downgraded.

| Row | What it now cites | Verified how |
|-----|-------------------|--------------|
| **C1** | 6 named cleartext-equivalence tests; batch rate **37.4M settings/s** measured | 6/6 re-run PASS here. The old "~40M" was rounded up; corrected to the measured figure |
| **C2** | `logs/control-p1030684-rings.log` — `*** BREAK FOUND ***`, UKW B / Greek γ / WO IV-III-VIII / rings AAAH / pos VYYN / all 10 plugs, IC 0.064 vs floor 0.055, tail −2.848 vs German −2.847, German plaintext | Log read. **The archived log reads 427 s, not the 361 s in prose** — the ledger already explains this (first run vs post–head-scoring re-run, log overwritten); now printed on the row |
| **C3** | Positive control 2→2→BREAK; negative 256 928 raw stops → **0** survive; head gate 1.989×10⁸ → 3 → 0 | Three logs read, sieve behaviour confirmed in both directions |
| **C8** | M4 identity baseline `fitness=0.000000` on 925 LUT / 49 DFF; emitter tests | Log read, 2/2 emitter tests PASS. Regeneration gap recorded (§1.5) |
| **C9** | `logs/tensorlut-m4-stecker-involution-blind-3pair.log` — `fitness=0.000000 pairs=AB CD EF`, `active_map_match=PASS full_map_match=PASS`, `blind=true`, 363.6 s | Log read; 2 involution tests re-run PASS. Files are named `tensorlut-m4-stecker-involution-*`, which is why "involution logs" matched nothing |
| **C10** | 5 named tests: reciprocal+stepping, plugboard involution, bijection sweep, coupledCubic6 distinctness, golden bundle RT | **5/5 re-run PASS here.** Previously said only "E256 tests" |
| **C11** | `Scripts/kiss_hunt.py` + `--exhaust-selftest`, both re-run into fresh logs | **Reproduced the ledger exactly**: 3 recovered daily keys, 72 overlays → 8 survivors vs 5.8 by chance. Exhaustion ceiling: true key ranks **223 118 / 456 976** (= 26⁴, top 48.8%), 4/72 letters, 0/10 plugs, tool prints `NO BREAK` |
| **C12** | Head-gate log: the old **2 219 boards** mass collapses to 3 physical → 0 breaks under the ≥16 filter and dual gate | Log read; best candidate IC 0.051 / tail −4.837, both under bar |

Receipt grades now: **R+L = 56**, **R = 13**, **P = 0**.

Two numbers were corrected downward rather than restated: C1's "~40M settings/s"
became the measured 37.4M/s, and C2 now prints that its archived log shows 427 s
where prose says 361 s.

## 3. What the lint checks, and what it cannot

`Scripts/claim_audit.py` fails the build on: unknown claim ids cited in the book,
C rows no chapter discusses, `\reproduced` boxes keyed to non-claims or to an H
id alone, empty-argument id macros, a `\livingepoch` that does not name the
newest C row, `--filter` names with no matching test function, and cited logs
missing from disk. It runs in Linux CI.

It is a lint. It cannot tell you whether a number is true — only whether the
thing that is supposed to prove it exists and is wired up. Verifying that
`logs/…-covering-b2-ks-n64.log` really shows 114.0 s, and that 114.0 s means what
C65 says it means, is human work.

## 4. Still open

- **Human gate.** Nothing here has been human-checked. The queue should start with the rows carrying the biggest numbers and the most downstream citations: C23 (estimator, H1), C52–C54, C62, C65–C69.
- **Grade R rows without archived logs (13).** C4, C5, C7, C14, C42 assert timings with no log. Re-run and archive, or move the numbers onto the rows that do have logs.
- **C8 regeneration.** Needs a generic-netlist emit entry point before the artifact is reproducible end-to-end.
- ~~**Textbook lecture voice.**~~ **Resolved by decision, not by edit** — see §5.
- **Prose drift around C58–C69.** Boxes are current; six surrounding passages still assert an H4 remainder that C65/C66/C68 walked around (`instructor.tex:130`, `pillar-i.tex:223`, `torus-fhe.tex:126`, `certificates.tex:27`, `applications.tex:86`, `open-problems.tex:31`).
- **`\hedgebox` is nearly unused.** H4–H7 have no hedge box, so the documented "hedge → reproduced" growth path has no object to act on.
- **C7, C13, C15** remain index-only by choice; they are superseded lineage rows. Registered as exceptions in the lint, not silently ignored.

## 5. Editorial voice: a decision, and a correction to this audit

The audit flagged ~40 sites where the textbook speaks as a live course
("this edition teaches…", "students who report only milliseconds have not
completed the lab", assigned exercises, a syllabus with grading weights) while
four separate places said it was not ready to teach. I first treated that as a
defect and renamed the environments to *Draft exercise (not assigned)* and
*Draft laboratory (not assigned)*.

That was the wrong fix and has been reverted. The book is being **prepared** as
a textbook, so it should be written in the voice of the finished book. A draft
that apologises in every environment title is a worse draft, harder to read and
harder to grow, and it buries the pedagogy under hedging.

The status is now carried structurally instead, in two places and no others:

1. **`\draftnotice`** — a full boxed page immediately after the title page:
   `DRAFT — NOT READY TO TEACH FROM`, edition and epoch, and an explicit
   statement that later text lecturing, setting exercises and assigning weeks
   is *drafting* and not a claim that the course exists. It says why the prose
   does not hedge itself sentence by sentence.
2. **A per-page footer stamp** — `DRAFT 0.1.2 (epoch) — prose is being
   prepared; not ready to teach from`, on **74 of 75 pages** (the title page is
   deliberately bare). A page photographed, quoted or printed alone still
   carries its status.

The distinction the notice draws is the one that matters:

> Editorial readiness and factual correctness are separate axes.

Editorial voice is now free. Evidential discipline is not, and is unchanged:
every `\cid`/`\hid`/`\nid`, every **Reproduced** box and every theorem is bound
to `directives/claim-sheet.md` and a receipt, mechanically checked by
`Scripts/claim_audit.py` in CI, and *if a sentence disagrees with the sheet, the
sheet wins and the sentence is a bug*. That sentence is now printed in the book.

The box legend was rewritten to say the same thing: the seven living boxes carry
**evidential** status, not editorial status, and it names the two boxes added in
this audit (`\negativebox`, `\recheckbox`).

Exercises and labs are back to `Exercise 10.1`, `Laboratory 7.1` and so on:
16 exercises, 2 labs, zero "Draft …" leftovers, 75 pages, 0 undefined
references, 0 TeX errors.

## 6. Timing variance

Every timing in the claim sheet was a single observation. That is not
reproducible even on the same machine — a cold first run of the C64 adder
measured **0.805 s** against **0.34 s** warm, a 2.4× penalty purely from cache
state.

`Scripts/bench_repeat.py` runs a command N times with optional warmup, scrapes
the tool's own reported figure via `--metric`, and reports min / median / mean /
max / stdev / relative spread. It refuses to let a mean stand in for a median at
small n, warns below a 3-run floor, discards timings from failed runs, and flags
any figure whose spread exceeds 25% as unquotable as a single number.

The sheet now carries a **timing variance rule**: quote the median of at least
three runs with the spread printed.

Two rows re-measured on M4 Max, median of 5 with warmup discarded:

| Row | Claimed | Measured median | Spread | Verdict |
|-----|---------|-----------------|--------|---------|
| C59 | 0.165 s | **0.1626 s** | 5.5% | holds |
| C64 (adder) | 0.264 s | **0.2653 s** | 7.3% | holds |

Both land essentially on the claimed figure, which is a good result: the numbers
were honest, they were just unqualified. Remaining single-observation timings are
being replaced incrementally.

One caveat found while doing it: **C58's 1.35 s cannot be re-measured** — it
timed the pre-wavefront code path that C59 replaced. It is a lineage row, like
C7/C13/C15. The 8.2× ratio it anchors is therefore historical: C59's measured
0.1626 s against C58's archived 1.35 s gives 8.3×, but only one side of that
ratio is still runnable.

## 7. Do you need to re-run everything multi-pass? No.

Short answer: **33 of 69 rows quote no timing at all**, so a blanket repeat would
cost about 6.4 hours of machine time and teach nothing on half the ledger. Measured
cost of "5 runs of everything", by tier:

| Tier | Rows | 5× cost | Recommendation |
|------|------|---------|----------------|
| **A** cheap, < 5 s | 10 | **~2 min** | Do all of them. No reason not to |
| **B** moderate, < 2 min | 18 | ~50 min | One sitting, opportunistically |
| **C** expensive, > 2 min | 9 | **~5.5 h** | **Do not repeat.** Label single-observation and say so |
| — no timing quoted | 33 | 0 | Nothing to measure |

Tier C is where a blanket policy goes wrong: C66 alone is 1135.8 s per run, so
five runs is 1.6 hours for one row. C60 and C61 are ~33 and ~61 minutes *each*.
The honest treatment there is to mark the figure as a single observation on a
named date and machine, not to pretend a median exists.

### What re-running actually caught

Four Tier-A rows re-measured, median of 5 with warmup discarded:

| Row | Claimed | Median | Spread | Finding |
|-----|---------|--------|--------|---------|
| C46 | 0.972 s / 10 | **0.473 s / 10** | 0.7% | **2.06× faster than the sheet** — stale, understated. Row corrected |
| C59 | 0.165 s | 0.1626 s | 5.5% | holds |
| C63 | 1.72 s | 1.80 s | 4.4% | archived figure is *below* our observed minimum — a best-case single run |
| C64 | 0.264 s | 0.2653 s | 7.3% | holds |

Two held, one was a lucky best case, one had drifted 2× *conservative*. Nothing
was optimistically wrong by more than its spread. That is the useful shape of
this: it catches stale numbers as often as flattering ones, and a repo that
understates itself by 2× is also mis-describing itself.

### The higher-value use of the harness: negative stability

For rows whose claim is a **FAIL** — C60, C61, C69's `n=512`, C56, C43's `k=8`,
C57's covering-b4 and E256 — the interesting question is not timing but whether
the failure is *deterministic*. A negative that only reproduces sometimes is a
much weaker claim than one that always fails the same way, and the campaign
doctrine leans hard on printed clean negatives.

`bench_repeat.py` already reports failures separately and discards their timings,
so `--runs 3` on a negative answers "is this stable?" directly. That is worth
more than shaving error bars onto a PASS, and none of it has been done yet.

### Suggested order

1. Tier A remaining (~2 min): C13, C28, C45, C47, C49, C50, C58*, C63 done, C59 done.
2. Negative stability, cheap ones first: C69 `n=512`, C56, C57 covering-b4.
3. Tier B in one sitting (~50 min).
4. Tier C: leave the numbers, add the single-observation label.

\* C58's 1.35 s is not re-runnable — it timed the pre-wavefront path C59 replaced.
It is lineage, like C7/C13/C15, and the 8.2× ratio it anchors has only one live side.

## 8. Flow and register fixes (the "AI slop" surface)

The framework does not need to be perfect, but it does need to survive a hostile
skim. Three classes of thing fail that test, and all three are now fixed.

### 8.1 Disproportionate grading language

`appendices/syllabus.tex` said, of the final oral defense:

> If the student upgrades the hedge, they have not passed the course's signature skill.

That declares a student has failed a core competency for one overstatement in a
viva. The underlying point is right — sliding from "H1 applies" into "so it is
176-bit secure" is the characteristic failure — but the absolutism is exactly what
reads as machine-written, and it is bad pedagogy besides. Rewritten as a rubric
line to discuss rather than an automatic fail, ending "everyone does it once; the
difference is whether they catch themselves."

Same register elsewhere, all softened without losing the point:

- `certificates.tex:47` "Students who report only milliseconds have not completed the lab" → a statement about what a complete report contains.
- `preface.tex:63` "``176-bit secure'' is a forbidden exam answer" → "not a sentence this corpus supports."
- `the-subject.tex:52` "which sentences remain forbidden?" → "which sentences does the evidence still not support?"

A sweep for `have not passed|automatic fail|forbidden|Do not let students` now
returns nothing.

### 8.2 Theorems carried two incompatible numbers

The corpus has called these results Theorem 1, Theorem 1$''$, Theorem 2 and
Theorem 3 since before the book existed; `directives/`, the claim sheet and the
external note all cite them that way. `amsthm` numbers by chapter, so the book
rendered Theorem 9.1, 10.1, 10.2, 10.3, 11.1. Two naming systems for the same
objects, in a book whose entire job is stable claim identity — and a reader
following a claim-sheet reference would find nothing.

Added `\corpusthm{}`; every theorem title now prints both, e.g. *Theorem 9.1
(TensorLUT continuous→discrete; corpus Theorem 1)*. A front-matter paragraph
"Why theorems carry two numbers" explains which to match on.

### 8.3 Forward references

Three items were used before they were defined:

- **Theorem 1** was cited in Part I (`instructor.tex`, `the-subject.tex`) but stated in Part IV. Both sites now say "stated in Chapter~\ref{ch:pillarii}".
- `living-contract.tex:76` cited "Theorem 1" as bare prose rather than a reference; now resolves through `\corpusthm{1}` plus `\ref{thm:tensorlut}`.
- **SING** appears in Part I before its Part III definition — already handled correctly with an inline gloss and a forward `\ref`, left alone.

The spine itself is sound: `$lut`/DFF IR precedes torus/LWE, which precedes the
FHE pipeline, which precedes the Metal lowering it motivates, which precedes
certificates. The syllabus appendix maps weeks onto that same part order. No
reordering was needed.

### 8.4 What the book now says about itself

One boxed front page (`DRAFT — NOT READY TO TEACH FROM`) plus a footer stamp on
74 of 75 pages, and the notice states the distinction plainly: *editorial
readiness and factual correctness are separate axes.* The prose is allowed to
read like the finished book because it is being prepared as one; the claims are
not allowed to drift, and that binding is machine-checked in CI. The book prints
its own failure rule: **if a sentence disagrees with the claim sheet, the sheet
wins and the sentence is a bug.**

## 9. C35: what is wrong and how to fix it

**C35 claims** `ε ≤ 2⁻⁶⁴` is met at inject `B=16` on covering-b2, quoting
`εlog2 = −65.4 (still ≤ −64)`, measured at `--trials 4`.

### 9.1 Root cause

ε is not a sampled quantity. It is an *analytic* Gaussian tail evaluated at a
**measured** σ̂:

```
ε = P(|Z| ≥ δ/2),   Z ~ N(0, σ̂²)
log₂ε ≈ −(δ/2)² / (2 σ̂² ln2)        so   log₂ε ∝ −1/σ̂²
```

Differentiating: a relative error `r` in σ̂ moves `log₂ε` by about
`2·|log₂ε|·r`. At `|log₂ε| = 65`, **a 1% error in σ̂ is worth 1.3 orders.**

And σ̂ is thin. In `TFHENoisyBK.swift` the measurement loop runs exactly
`trials` iterations and takes **one residual sample per trial**:

```swift
for _ in 0..<trials { ...; sumSq += err*err }
return ...(rms: sqrt(sumSq / Double(trials)), samples: trials, ...)
```

So `--trials 4` gives `m = 4` samples, whose standard error on σ is
`1/√(2m) ≈ 35%`. Propagated:

| m | SE(σ̂)/σ̂ | unresolved orders at log₂ε = −65 |
|---|---------|----------------------------------|
| 2 | 50.0% | ±65 |
| **4** | **35.4%** | **±46** |
| 8 | 25.0% | ±32 |
| 64 | 8.8% | ±11.5 |
| 1 024 | 2.2% | ±2.9 |
| **8 450** | **0.77%** | **±1** |

**C35's "−65.4, still ≤ −64" carries ±46 orders of statistical uncertainty.**
It has no resolving power against the bar at all. The same artifact explains
every "sample-sensitive" note already in the sheet: C32 (−32 at 4 trials →
−8.4 at 8), C41 (−696 at 2 → −76.6 at 4), C43 (−107 at 2 → −43 at 4). None of
those are physical changes; they are one statistic being re-estimated from a
handful of samples.

### 9.2 What the honest number is today

Putting a one-sided 95% χ² upper bound on σ (`m·σ̂²/σ² ~ χ²(m)`) and recomputing
ε at that bound, from C35's own logged σ̂ values at m=4:

| B | σ̂ | ε (point) | σ₉₅ᵤₚ | ε @ 95% | clears −64? |
|---|-----|-----------|-------|---------|-------------|
| 1 | 10 065 | −7835 | 24 230 | −1357 | yes |
| 2 | 3 705 | −57 797 | 8 918 | −9980 | yes |
| 4 | 21 944 | −1653 | 52 823 | −289 | yes |
| 8 | 49 364 | −330 | 118 829 | **−59.7** | **no** |
| 16 | 110 587 | −68.4 | 266 203 | **−13.6** | **no** |
| 32 | 140 335 | −43.5 | 337 812 | −9.0 | no |

(The point column reproduces the logged ε to within the erfc approximation,
confirming the model.) At m=4 the supportable claim is **B ≤ 4**, not B=16 —
and not even B=8, despite its comfortable-looking −330.

### 9.3 The fix, in three parts

**(a) Report the bound, not the point.** Implemented in
`Sources/HELUTCore/TFHEGaussianSecurity.swift`:
`chiSquareQuantile`, `standardNormalQuantile`, `sigmaUpperConfidenceBound`,
`epsilonResolutionOrders`, `samplesForEpsilonResolution`. Surfaced on
`TFHENoisyBKMeasurement` as `sigmaUpper95`, `failureLog2Upper95`,
`failureLog2Point`, `epsilonUnresolvedOrders`, `samplesForOneOrder`, and
`meetsTargetWithConfidence(targetLog2:)`. The measurement certificate now prints
the sample size, the unresolved orders, both ε figures, and the sample count
that would be needed for ±1 order — so ε can no longer be quoted bare.

**(b) Measure with enough samples.** To resolve `log₂ε` to ±1 order at this
magnitude needs **~8 450 samples**, i.e. `--trials 8450`, not 4. Cost is being
measured; the identity-LUT PBS is the cheapest thing in the stack, so this is
plausibly minutes rather than hours. Until then, no ε within ~46 orders of a bar
should be described as meeting it.

**(c) Re-scope the claim until (b) is run.** The defensible statement is:
*covering-b2 clears ε ≤ 2⁻⁶⁴ with confidence at inject B ≤ 4; B=8 and B=16 are
inside the measurement's resolution and are not decided.* That is weaker than
C35 as written and it is what the evidence supports.

A cheaper structural option worth considering: take more than one residual per
trial. Each BR yields one scalar error, so samples currently cost one PBS each —
but the loop could sample several bits per bootstrap key, amortising key
generation and making m=10⁴ nearly free.

## 10. C69 at n=512: a negative that does not reproduce

> **SUPERSEDED by §12.** The mechanism proposed in this section (a residual
> sitting near the decode threshold) is **wrong**. The real cause was a
> determinism bug, the negative is withdrawn, and n=512 now passes. Kept
> unedited because the reasoning error is instructive: a plausible physical
> story was fitted to data that had a software explanation.


Tier B ran C69's `n=512` case five times. The sheet records it as
**SING FAIL (sum mismatch want=0 got=1)**. Observed:

```
exits:    [0, -5, -5, 0, 0]
verdicts: [PASS, (none), (none), PASS, PASS]
```

Signal 5 is SIGTRAP, and the archived log shows why they are the same event:

```
HelutBench.swift:371: Fatal error: sum mismatch ... tick 1: want=[0] got=[1]
```

A Swift `fatalError` *is* the trap. So the documented failure reproduced **2 of
5 times**, and the run **PASSed the other 3**. The claim is presented as a
deterministic negative; it is not one.

### 10.1 Why: it sits on the decode threshold

The identity residual against the decode half-gap `δ/2 = 1 048 576`:

| n | B_bk | % of δ/2 | headroom | behaviour |
|---|------|----------|----------|-----------|
| 64 | 428 318 | 40.8% | 620 258 | comfortable |
| 128 | 610 382 | 58.2% | 438 194 | marginal |
| 256 | 385 360 | 36.8% | 663 216 | comfortable |
| **512** | **858 907** | **81.9%** | **189 669** | **straddles** |

At n=512 the residual is at 82% of the limit with 18% headroom, so run-to-run
variation in the noise draw decides the outcome. A 3/2 split over five passes is
exactly what that predicts.

### 10.2 The honest claim

*n=256 covering-b2 SING passes with comfortable margin (37% of δ/2). n=512 is
**marginal, not failing**: the identity residual reaches 82% of δ/2, and the
adder SINGs on roughly 60% of runs and traps on a sum mismatch on the rest.*

That is more useful than "FAIL", because it names the quantity to watch — the
ratio `B_bk / (δ/2)` — and it predicts that anything above roughly 80% of the
gap is unreliable rather than broken.

### 10.3 It also found a bug in this harness

`leeloo.stability()` originally discarded passes that printed no verdict, so it
reported this row as `stable-pass`: it threw away the two crashes. A harness that
hides crashes is worse than none. Exit status is now part of the outcome tuple,
crashes render as `CRASH(signal 5)`, and this row correctly reads
`FLAKY:CRASH(signal 5)x2,PASSx3`. Already-collected results were reclassified
from the recorded exits without re-running anything.

## 11. The unifying finding: margin, not verdicts

C35 and C69 are the same disease in two places.

- **C35** reports a bar as *met* when the point estimate is 1.4 orders from it and the uncertainty is ±46.
- **C69** reports a *failure* as definite when the headroom is 18% and the outcome flips run to run.

In both cases a binary verdict was rendered from a quantity whose margin is
inside its own noise. The discipline that fixes both:

1. Always print the **margin** — distance to the bar — next to the verdict.
2. Always print the **resolution** — what the sample size or headroom can actually distinguish.
3. Withhold the verdict when (1) is inside (2); say "not decided" instead.

`epsilonUnresolvedOrders` and `meetsTargetWithConfidence` implement this for ε.
The equivalent for SING is the `B_bk / (δ/2)` ratio, which the tool already
computes and should print as a percentage with a marginality flag above ~80%.

For a corpus meant to outlive its author, this matters more than any single row:
a reader who inherits the ledger can check margins mechanically, but cannot
recover the fact that a verdict was never resolvable.

## 12. The determinism bug — and two claims recovered

This is the most consequential finding of the re-validation, and it corrects §10.

### 12.1 The observation that did not fit

C69's `n=512` case failed 2 of 5 passes. §10 explained that as the identity
residual sitting at 82% of `δ/2`, close enough that noise straddled the decode
threshold. That story was plausible and it was wrong.

The disproof is in the tool's own output. Across repeated runs of the *same
command*:

```
run 1: rc=133  B_bk=858907   want=[0] got=[1]
run 2: rc=133  B_bk=858907   want=[0] got=[1]
run 3: rc=0    B_bk=858907   PASS
```

`B_bk` is byte-identical every time. Every seed in `HelutBench.swift` is a
hardcoded constant (`0xE11C`, `0xE120`, `0xB10C`, …) — there is no time-based or
random seeding anywhere. So the secret, the bootstrap key and the injected noise
are identical run to run. **Identical inputs producing different outputs is not
marginal noise. It is a bug.**

### 12.2 Isolating it

Two experiments, each decisive:

1. **Serialise the wavefront.** Added `HELUT_SERIAL_WAVEFRONT=1` to force the
   ready-LUT set through the serial path. Still nondeterministic
   (`133, 133, 0`) — so the `concurrentPerform` introduced by C59 was *not* the
   cause. Its locking is in fact correct, as are `TFHETestPolyCache`,
   `NegacyclicNTT.modulusCache`, and the cached Metal engines, all of which hold
   an `NSLock` around their shared state.
2. **Disable hash randomisation.** `SWIFT_DETERMINISTIC_HASHING=1` passed
   **4/4** where the default alternated. Swift randomises `Dictionary` and `Set`
   hash seeds per process, so this pinned the fault to iteration order.

### 12.3 The bug

`EncryptedNetlistSim.tick`, encrypting the primary inputs:

```swift
for (port, bits) in inputs {              // Dictionary — order randomised per process
    ...
    wires[wire] = encryptLWE(..., rng: &rng, ...)   // draws from the shared serial RNG
```

`inputs` is a `[String: [UInt8]]`. The loop consumes the shared `rng` while
walking it in hash order, so **each run assigns a different mask vector to a
different wire.** The ciphertexts differ, the noise realisation differs, and
wherever the margin is thin the decode sometimes fails. Everything downstream —
`keySwitch`, the gadget decomposition, the wavefront — was deterministic and
correct.

Fix: iterate in sorted key order. Two sites (`:371`, `:860`).

```swift
for (port, bits) in inputs.sorted(by: { $0.key < $1.key }) {
```

### 12.4 Two claims recovered, not lost

| Row | Before | After the fix |
|-----|--------|---------------|
| **C69** `n=512` | "SING FAIL (sum mismatch want=0 got=1)" | **PASS 5/5.** The negative is **withdrawn** — it was an artifact. The covering KS ladder reaches **n=512**, not n=256 |
| **C52** | FLAKY, 1 of 5 passes trapped | **PASS 4/4**, both paths. Claim restored |
| **H4 Grade B** | re-opened (rested on flaky C52) | **re-closed** — the fault was software determinism, not the cryptography |

So the audit did not cost a claim. It removed a spurious negative and made a
real one stronger, and the ledger now says the covering ladder goes one rung
further than it previously admitted.

### 12.5 Why this matters more than the rows

Every encrypted measurement in the corpus was taken from a process whose input
ciphertexts depended on hash-seed order. Correctness claims were mostly immune,
because a PASS is a PASS whichever masks were drawn — but any run near a noise
margin was a coin toss, and no encrypted run was bit-reproducible from its seed.
That is a bad property for a corpus whose entire premise is reproducible
receipts, and it is exactly the class of defect a second reader is for: the
numbers all looked consistent, and the *process* was not.

Three lessons worth keeping:

- **A verdict that varies under fixed seeds is a bug, never a parameter.** Check
  determinism before reaching for a physical explanation. §10 is left in place as
  a record of getting that backwards.
- **`nonisolated(unsafe)` is not evidence of a race.** Every one of those sites
  here was correctly locked. The fault was in ordinary single-threaded code.
- **Hash-order dependence is invisible to review and to CI.** It only shows up
  across repeated whole-process runs, which is precisely what leeloo does and
  what a single-run receipt cannot.

### 12.6 Follow-up

- `HELUT_SERIAL_WAVEFRONT=1` is kept as a permanent debug switch; it is the
  cheapest way to test a concurrency hypothesis on this path.
- Worth adding a regression test: run a tick twice in one process and assert the
  output ciphertexts are byte-identical. That would have caught this.
- Everything measured before 2026-08-15 was taken under the old behaviour. The
  Tier A/B medians are unaffected (timings, not values), but any *marginal*
  encrypted result predating the fix deserves a re-run — starting with C43's
  `k=4` ε instability and C41's n=512 figure.

## 13. Epsilon: one row resolved, and a measurement method that cannot resolve the rest

Following §9, the confidence machinery is now wired into the CLI, so every
measured row prints its sample count, its 95% upper bound, and whether that
bound clears the target.

### 13.1 C22 at N=128 is now resolved

The archived figure was `εlog2 ≈ −23.5` at **n=4**, which §9 showed cannot decide
anything. Re-measured across sample sizes (0.21 s/trial at N=128, so this is
cheap):

| n | σ̂ | union ε log₂ | union 95% bound |
|---|-----|--------------|-----------------|
| 4 | 1 466 383 | −23.5 | −2.8 |
| 64 | 1 766 748 | −15.9 | −11.3 |
| **512** | **1 666 139** | **−18.0** | **−16.1** |

σ̂ converges to about 1.67×10⁶ and the union ε to about **−18.0**, with a 95%
bound of **−16.1**. The row's conclusion — that this is nowhere near 2⁻⁶⁴ — was
correct and is now properly established rather than asserted from four samples.
The archived −23.5 was optimistic small-sample noise.

### 13.2 C43's k=4 figure moved

Recorded: `εlog2 ≈ −107 (2 trials) / −43 (4 trials)`. Measured now at n=4:
σ̂ = 768 411.7, **εlog2 = −21.3**. All three numbers are far above −64, so the
row's verdict ("SING yes, ε bar not stable") is unchanged — but the specific
figure moved again, which is the third independent demonstration of the same
small-sample instability.

### 13.3 The method cannot resolve N=1024, and that is the real finding

Measured per-trial cost:

| configuration | s/trial | n for ±1 order | wall time |
|---------------|---------|----------------|-----------|
| N=128, `cryptoPublicMS` | 0.21 | ~1 400 | ~5 min |
| N=1024, covering-b1 (ℓ=32) | **155** | ~8 450 | **~15 days** |

So the plan in §9.3(b) — "just run more trials" — is **infeasible at production
degree**. This is not a scheduling problem to be solved with patience; ε at
N=1024 cannot be established by this measurement method at all, and C35's
`B=16` bar claim therefore cannot be settled the way it is currently measured.

### 13.4 The fix that would make it feasible

The measurement wastes almost all of its information. `TFHENoisyBK` runs one
PBS per trial and keeps **one** scalar residual:

```swift
for _ in 0..<trials { ...; sumSq += err*err }
return ...(rms: sqrt(sumSq / Double(trials)), samples: trials, ...)
```

But the GLWE accumulator produced by that PBS has **N coefficients**, and the
noise in each is a sample from the same distribution. Only the coefficient
carrying the message is used; the other N−1 are discarded. Estimating σ̂ from all
N would give 1024 samples per trial at N=1024, so the ~8 450 samples needed for
±1 order would take about **9 trials, roughly 23 minutes** instead of 15 days —
a ~1000× improvement in sample efficiency for no extra cryptographic work.

Implementation sketch: measure before sample-extract. Compute the noiseless
reference accumulator (`X^phase · testPoly`, exactly computable), subtract it
from the decrypted accumulator, and take the RMS over all N coefficient
residuals rather than the single extracted one. Care needed on two points:
coefficient noise is only approximately i.i.d., and the reference must be exact
or its error contaminates the estimate.

Until that lands, the honest position on C35 is unchanged from §9.3(c): the bar
is supportable at inject `B ≤ 4`; `B=8` and `B=16` sit inside the measurement's
resolution and are **not decided**.

### 13.5 A reporting bug found in this work

The first version of the CLI note compared a **union** point estimate against a
**single-LUT** bound, which produced an impossible ordering: at n=512 the "95%
upper bound" read −19.1 against a point estimate of −18.0, i.e. the bound looked
better than the estimate. An upper bound on σ can only make ε worse. The
single-LUT numbers were right (independently reproduced in Python: point −21.00,
bound −19.09); the union factor `log₂(lutCount)` was missing from the bound.
Fixed in 070f511.

Worth noting how it was caught: not by review, but by an ordering sanity check —
"the bound must be worse than the estimate" — applied to real output. That
invariant is cheap and should be asserted in the tool.
