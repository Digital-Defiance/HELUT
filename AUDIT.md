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

> **PARTLY SUPERSEDED by §14.** The cost figures below are correct, but the
> conclusion is not: resolving ε to ±1 order is indeed infeasible, while
> *demonstrating the bound clears the bar* needs only n≈24 and took 42 minutes.
> C35's bar stands. Left in place because conflating those two requirements is
> an easy and expensive mistake.


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

**This was implemented, and the "~1000×" above is wrong.** See §13.4.1.

Until that lands, the honest position on C35 is unchanged from §9.3(c): the bar
is supportable at inject `B ≤ 4`; `B=8` and `B=16` sit inside the measurement's
resolution and are **not decided**.

### 13.4.1 It landed, and the sample-efficiency estimate was off by ~100×

`TFHENoisyBKMeasurement.identityAllCoefficients` implements the sketch. The two
correctness worries in §13.4 both checked out; the performance claim did not.

**The reference is exact.** Blind rotate leaves `ACC = X^{−p}·v` with
`p = b − Σ_j a_j s_j` the LWE phase in `Z_2N`. This is a self-test, so `s` is in
hand and `p` is recomputed rather than inferred. Two tests pin it: coefficient 0
reproduces the single-residual estimator's value *exactly* at the same seed
(sample-extract lifts exactly that coefficient, `b: ciphertext.body[0]`), and a
noiseless bootstrap key yields a residual of exactly 0 across the whole
accumulator — with no injected noise there is nothing for a wrong reference to
hide behind.

**σ̂ is unbiased.** The two estimators agree at every degree tested:

| N | accumulator σ̂ | single-residual σ̂ |
|---|---------------|-------------------|
| 32 | 14 648 | 14 521 |
| 64 | 53 036 | 54 316 |
| 128 | 221 216 | 215 092 |
| 256 | 751 013 | 770 124 |

**But the coefficients are nowhere near independent.** §13.4 assumed N residuals
means N samples. Measuring the effective count — repeated runs, inverting
`sd(σ̂)/mean(σ̂) ≈ 1/√(2n)`, with a control at a known-independent count to divide
out the residual's excess kurtosis — gives:

| N | effective samples per bootstrap | as % of N |
|---|-------------------------------|-----------|
| 32 | 10.0 | 31.2% |
| 64 | 11.7 | 18.3% |
| 128 | 8.3 | 6.5% |
| 256 | 7.7 | 3.0% |

The gain is **flat at roughly 8–12× and mildly decreasing in N**, not
proportional to N. So the honest figure for the optimisation is about one order
of magnitude, not three. At N=1024 the trend suggests ~7×, though that is an
extrapolation and no measurement has been taken there.

Consequence for the ±1-order question: ~8 450 samples at ~7× is ~1 200
bootstraps, roughly **26 hours** rather than the 23 minutes §13.4 predicted, down
from about eight days. Useful, not transformative.

A plausible mechanism, offered as a hypothesis and not a claim: the accumulator's
noise is dominated by a handful of GGSW external-product error polynomials, each
contributing correlated error across all N coefficients, so the effective count
tracks the number of noise *sources* rather than the number of coefficients. The
measured gains do loosely track `ℓ` (ℓ = 5, 4, 4, 3 for N = 32, 64, 128, 256
under `cryptoPublicMS`), which is suggestive but far from established.

**The bound had to be protected from this.** `sigmaUpper95` and
`epsilonUnresolvedOrders` divide by a new `effectiveSamples` field, not by
`samples`. Had they kept dividing by the raw residual count, merely switching
estimators would have tightened every ε bound by ~√(N/10) with no new evidence —
the optimistic direction. Accumulator measurements are credited a deliberately
conservative 4 samples per bootstrap, below the lowest value measured, and the
certificate note prints the provenance
(`k PBS × N accumulator coeffs = m residuals, credited j independent`) so no
reader mistakes residuals for bootstraps. Locked by
`TFHENoisyBKAccumulatorBoundSafetyTests`.

This does not move C35, whose bar was already cleared at n=32 in §14. It reduces
the cost of *future* ε statements and removes a trap that would have produced
unearned confidence.

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

## 14. C35 resolved: the bar stands, and §13 asked the wrong question

§13 concluded that ε at N=1024 "cannot be established by this measurement
method." That was wrong, and the error was mine: I conflated two different
requirements.

- **Resolving ε to ±1 order** needs n ≈ 35 000 at this magnitude. At ~78 s per
  trial that is about eight days. Infeasible, as §13 said.
- **Demonstrating that the 95% bound clears −64** needs only n ≈ 24. That is
  about half an hour.

The claim requires the second, not the first. Chasing ±1-order resolution was a
self-imposed standard that no bar-clearing claim needs.

### 14.1 The measurement

Run at increasing sample size, inject B=16, covering-b2, N=1024:

| n | σ̂ | ε point | 95% bound | clears −64? | wall |
|---|-----|---------|-----------|-------------|------|
| 4 | 110 587 | −65.4 | −10.6 | no | 5 min |
| 8 | 92 117 | −94.3 | −31.9 | no | 10 min |
| 16 | 84 535 | −111.9 | −55.6 | no | 21 min |
| **32** | **78 551** | **−129.6** | **−81.3** | **YES** | **42 min** |

`logs/c35-eps-n32-2026-08-15.log`. The bound clears the bar with 17 orders of
margin.

Two things to notice. σ̂ decreases monotonically with sample size, so the point
estimate *improves* from −65.4 to −129.6 — the archived figure was pessimistic,
not optimistic. And the bound tightens toward the point as the χ² interval
narrows, which is what eventually clears the bar.

### 14.2 What C35 should say

The claim **stands**, but the quotable number changes:

> ε ≤ 2⁻⁸¹ at 95% confidence, n=32 samples.

not the point estimate of −129.6, and certainly not the original −65.4, which
was true but unsupported at four samples. The original claim was not wrong in
substance; it was unfalsifiable as measured.

### 14.3 Why the whole detour was worth it

The archived value reproduced *exactly* at n=4 (σ̂=110586.5, ε=−65.4), so nothing
was miscomputed and no code was broken. What was missing was any statement of
what four samples can support. Adding the bound turned an unfalsifiable number
into a defensible one, and it took 42 minutes of machine time to do it.

The general lesson, which now sits in the textbook at §"Why ε needs a sample
size": when a measurement is compared against a bar, state the confidence bound
and the sample size, and size the sample to the *bar*, not to some arbitrary
resolution target.

### 14.4 Everything else in Tier D reproduced

| Row | Archived | Re-measured | Bound added |
|-----|----------|-------------|-------------|
| C22 N=8 both gadgets | comfortably clear | identical (σ̂=6395.9 / 59959.9) | clears −64 |
| C32 `cryptoPublicMS` B=1 | undecodable | undecodable, decode_fail=2 | n/a |
| C32 `.crypto` B=1 | ε ≈ −8.4 at 8 trials | **−8.4 exactly** | −1.7, needs n≈259 |

No archived ε figure was found to be wrong. Several were found to be
unsupported at their stated sample size, which is a different and fixable
complaint.

## 15. The nine unre-run rows, and what sample size an ε bar actually needs

§14 closed C35 and re-ran Tier D. Nine rows were left untouched and disclosed as
such: C26, C30, C33, C34, C36, C37, C41, C55, C56. This closes that gap and, in
doing so, turns a hand-waved convention into a computed one.

### 15.1 All nine reproduced

Sixteen invocations, fifteen exit-zero and one expected failure.

The distinction that made this cheap to reason about: `--measure-bk-noise` never
touches `EncryptedNetlistSimulator.tick`, so those halves were structurally
immune to the determinism defect. The `--bench-encrypted --sing` halves do go
through `tick`, and those are the ones that could in principle have been decided
by a mask permutation. All five SING rows (C33, C34, C36, C37, C41) pass.

| Row | Archived | Re-measured 2026-08-16 |
|-----|----------|------------------------|
| C26 | *B*=64 both gadgets undecodable; *B*=4 `crypto` ok but ε≈−1 | exact: max\|e\| 123 370 595 / 27 820 597 vs δ/2 1 048 576; *B*=4 `crypto` ε=−1.0 decodable, `cryptoPublicMS` undecodable |
| C30 | σ̂≈4.6×10⁴ at *B*=1; −260/−215 at 16/32; ≈−24 at 64 | σ̂ **identical to one decimal** at all seven inject levels; −260.7 / −215.5 / −24.1 |
| C33 | Metal SING PASS | PASS (23 s) |
| C34 | σ̂≈2.95×10⁴, ε≈−913, SING PASS | σ̂=29 513.2, ε=−913.0, PASS (85 s) |
| C36 | ε=−139 at 4 trials, SING PASS | ε=−139.3, PASS (333 s) |
| C37 | ε≈−159 at 4 trials, SING PASS | ε=−159.4, PASS (335 s) |
| C41 | *N*=256 ε≈−2109; *N*=512 ε≈−76.6; SING PASS | −2108.7 / −76.6, PASS (48 s) |
| C55 | *n*=256 ε≈−10.9, none meet the bar | −10.9 exactly |
| C56 | identity ε≈−12.6; Metal public-ms **SING FAIL** (sum mismatch tick 2) | −12.6; fails with `sum mismatch blind-rotate-metal public-ms crypto tick 2: want=[1] got=[0]` |

C56's failure is the documented negative reproducing, down to the tick index and
the direction of the mismatch. `rc=133` is how a Swift `fatalError` surfaces.

### 15.2 One archived figure was an artifact: `εlog2 = −∞`

The archived C30 log prints `εlog2=-inf` for inject *B* ≤ 8. That is **not** zero
failure probability; it is the Gaussian tail underflowing in the old evaluation.
The log-space rewrite prints the finite values, and they are large:

| inject *B* | archived | now | 95% bound |
|-----------|----------|-----|-----------|
| 1 | −∞ | −23 744.1 | −8 079.8 |
| 2 | −∞ | −28 107.5 | −9 564.2 |
| 4 | −∞ | −8 925.1 | −3 038.1 |
| 8 | −∞ | −1 966.3 | −670.1 |

σ̂ is unchanged at every level, so this is a reporting fix rather than a
measurement change. It still mattered: "−∞" is an over-claim, and the sheet
carried it.

### 15.3 How many samples an ε bar needs, computed rather than chosen

Trial counts across the ε rows were picked by hand — 2 here, 4 there, 8 elsewhere
— and nothing recorded whether a given choice could support the claim resting on
it. It can be derived. The 95% bound is `σ̂·√(m/χ²₀.₀₅(m))`, and since
`log₂ε ∝ −1/σ²`, the bound clears a target iff

    |point| ≥ (m / χ²₀.₀₅(m)) · |target|

The factor falls monotonically in *m*, so each sample count buys a fixed amount of
slack and any row with more slack than that is already fine:

| samples | \|log₂ε\| needed to clear −64 |
|---------|------------------------------|
| 2 | 1537 |
| 3 | 558 |
| 4 | **355** |
| 8 | 182 |
| 16 | 126 |
| 32 | 100 |
| 128 | 79 |
| 1024 | 69 |

**So `n=4` is not too small in general.** It is sufficient for any row whose point
estimate is at or below −355, which covers most of them. Only thin margins are
expensive, and the cost climbs steeply: a point estimate of −76.6 against a −64
bar needs *n*≈172–256.

Applying this to the twenty-six ε verdicts measured today splits them cleanly into
three kinds, two of which need no action:

- **Fine at the sample size used** (12 verdicts) — C30 at *B*=1…32, C34,
  C41 at *N*=256, C56 `crypto`.
- **Genuinely unmet, and correctly recorded as such** (11 verdicts) — C26,
  C30 at *B*=64, C55, C56 `cryptoPublicMS`. The *point estimate itself* fails the
  bar, so no sample count rescues these. Every one of these rows already reads as
  a negative; none was over-claiming.
- **Under-sampled** (3 verdicts) — C36 (needs *n*≈16), C37 (*n*≈12), C41 at
  *N*=512 (*n*≈256). The margin is real but unproven at the *n* used.

Only the third group is a defect, and only two rows in it actually assert the bar
in their text: C36's title ("ε≤2⁻⁶⁴ through inject *B*=32") and C41's body
("ε≈−76.6 (≤−64)"). C37 quotes −159 without claiming the bar.

`samplesToClearFailureTarget` computes the required count and returns `nil` when
the point estimate fails, because the two cases need opposite responses — buy
trials, or weaken the claim. The CLI prints which, replacing the old
`±1 needs n≈40489`. That figure was the cost of resolving ε to ±1 order, a far
stricter standard than clearing a bar, and quoting it made merely under-sampled
rows look hopeless. §14 records making exactly that error about C35.

### 15.4 All three under-sampled rows resolved, and none was lost

Sampling each properly. Every one of them is now supported at 95% confidence,
though the third needed a parameter change rather than more compute.

| Row | ladder (n → εlog2) | settled bound | outcome |
|-----|--------------------|---------------|---------|
| C37 *N*=1024 σ=24 | 4 → −159.4 · 20 → −149.8 | **−81.4** | clears at n=20 |
| C41 *N*=256 σ=128 | 2 → −2108.7 · 32 → −946.9 | **−594.5** | clears at n=32 |
| C36 *N*=1024 *B*=32 | 4 → −139.3 · 24 → −90.6 · 64 → −97.8 | **−71.2** | clears at n=64 |
| C41 *N*=512 σ=128 *k*=1 | 4 → −76.6 · 16 → −36.8 · 64 → −61.1 · 256 → −50.6 | −43.5 | **fails at native *k*=1** |
| C41 *N*=512 σ=128 *k*=2 | 16 → −138.7 · 64 → −207.9 | **−151.5** | clears |
| C41 *N*=512 σ=128 *k*=3 | 16 → −314.3 · 64 → −515.8 | **−375.9** | clears |

C36 is the instructive one for cost: the n=4 estimate said n≈16 would settle it,
the n=24 estimate said n≈55, and n=64 finally cleared. The required-sample
estimate is only as good as the σ̂ it is computed from, so on a thin margin the
right procedure is to climb a ladder rather than take one shot at a predicted n.

### 15.5 Retraction: the σ̂ "drift" was noise, not bias

Partway through this work I recorded that σ̂ grew with sample size on four
consecutive measurements (1.03×, 1.24×, 1.44×, 1.49×) and called it suggestive of
a systematic low bias at small *n*, p≈0.06. **That reading did not survive more
data.** Extending the ladders shows the sequences are not monotone:

| Row | σ̂ across the ladder |
|-----|---------------------|
| C41 *N*=512 *k*=1 | 204 462 → 294 285 → **228 797** → 251 262 |
| C36 *N*=1024 | 75 752 → 93 986 → **90 452** |
| C41 *N*=512 *k*=2 | 303 654 (n=16) → **247 845** (n=64) |

They go up and then down, settling. That is sampling noise around a fixed value,
not a trend. The theoretical bias is real but small — the RMS estimator is low by
about 6% at n=4 by Jensen — whereas the noise on σ̂ at n=4 is **±35%**, which
swamps it. The 1.4× excursions were high and low draws, and I over-read four of
them as a pattern.

The operational conclusion is unchanged and never depended on the bias question:
±35% at n=4 means a point estimate at that sample size must not be quoted against
a bar unless the margin is enormous. What changes is the reason given.

### 15.6 The fix for *N*=512: stride *k*, and a clean *k*² law

Native *k*=1 at *N*=512 genuinely misses the bar — −50.6 settled at n=256, where
σ̂ noise is only ±4.4%. More sampling cannot help a point estimate on the wrong
side. But the row is a **parameter map**, and the parameter that matters was
already identified by **C52** at *N*=1024: stride *k* encoding, wires in `{0,k}`,
decode gap *k*δ.

Measuring across *k* at *N*=512, σ=128, covering-b1:

| *k* | δ/2 | σ̂ | εlog2 (union/8) | single-LUT | implied exponent |
|-----|-----|-----|-----------------|------------|------------------|
| 1 | 2 097 152 | 251 262 | −50.6 | −53.7 | — |
| 2 | 4 194 304 | 247 845 | −207.9 | −211.0 | 1.94 |
| 3 | 6 291 456 | 235 748 | −515.8 | −518.8 | 1.95 |
| 7 | 14 680 064 | 261 545 | −2275.7 | −2278.7 | 1.97 |

σ̂ is independent of *k* — it is a property of the CMUX ladder, not of the message
scale — while the gap grows linearly. So the *N*=512 shortfall is a gap-budget
problem with a known exchange rate, not a noise wall.

**Correcting an over-claim made earlier in this same session.** I first wrote that
`|log₂ε|` follows a *k*² law "to ~1%". It does not. The leading term of the
Gaussian tail is `−t²/(2σ²ln2)`, which is exactly *k*², but the tail also carries
`−log₂(t/σ)`, so growth is slightly **sub**-quadratic — measured exponent 1.94 to
1.97 over *k* ∈ [2,11], and strictly below *k*² at every point. The apparent 1%
agreement was an artifact: σ̂ differed between the four runs in a direction that
happened to cancel the correction. Caught by writing the law down as a test
(`EpsilonStrideExchangeRateTests`), which failed on first run.

Every measured figure is fully accounted for: it is the exact Gaussian tail at
that run's σ̂, plus a union penalty of log₂(8)=3.0 for the eight LUTs. The observed
offsets are 3.06, 3.10, 3.01, 2.96. No residual anomaly.

Correctness holds too, which matters because ε alone is not a claim: Metal SING
**PASS** on both covering-b1 paths (secret and public-ms) at *k*=2, 3 and 7, with
306.1 classical bits. That check was not optional — **C56** shows *k*=7 breaking
SING on a different path at *N*=1024, so a stride that fixes ε can still fail
functionally.

So C41 keeps its ε claim, restated honestly: *N*=512 meets ε≤2⁻⁶⁴ **at *k*≥2**,
and not at native *k*=1. One order of stride buys a 4× improvement in `|log₂ε|`,
and the shortfall at *k*=1 was only 1.27×.

## 16. Fragility, the stride lever, and two claims the old bug was still hiding

§15 established that every ε figure was *supported* by its sample size. That is a
weaker property than it sounds, and this section is about the gap between "clears
the bar" and "would still clear it tomorrow".

### 16.1 A bound that clears is not necessarily a bound you can rely on

`log₂ε ∝ −1/σ²`, so if σ̂ turns out `g`× larger than measured, `|point|` falls by
`g²` and the bound survives only while `|point|/g² ≥ slack(n)·|target|`. Working
that through, and using `bound = point/slack(n)`, the slack cancels:

    σ̂ headroom = √(|bound| / |target|)

Worth measuring because σ̂ genuinely moves between runs: the C52 ladder went
401 326 → 543 612 (1.35×) from n=16 to n=32, and across every row measured on
2026-08-16 the spread reached ~1.5×. A bound with less headroom than that can flip
on a re-run with nothing wrong.

Applying it corrected my own read of which rows were weak, in **both** directions.
I had called C34 thin; it is comfortable at 2.21×. I had called C36 fine; it sat at
**1.05×**, meaning a 5% σ̂ rise would break it.

There is also a ceiling. As `n` grows the bound rises toward the point estimate and
stops, so headroom is capped at `√(|point|/|target|)` however much compute is
spent. For C36 that ceiling was 1.24×: five more hours of sampling could not have
made it robust. **Sampling is the wrong lever for a thin margin.**

### 16.2 The right lever is stride, and it is now used four times

σ̂ is a property of the CMUX ladder, not of the message scale, so widening the
decode gap to `kδ` improves ε without touching the noise. Three fragile rows were
fixed this way, each with Metal SING checked *first* on both paths, since ε alone
is not a claim:

| Row | before | after | headroom |
|-----|--------|-------|----------|
| C36 *B*=32 | *k*=1, bound −71.2 | *k*=2, bound **−345.5** | 1.05× → **2.32×** |
| C37 σ=24 | *k*=1, bound −81.4 | *k*=2, bound **−245.2** | 1.13× → **1.96×** |
| C52 σ=128 | *k*=7, bound −83.2 | *k*=14, bound **−265.8** | 1.14× → **2.04×** |

Nothing was withdrawn: the native-*k*=1 bounds still clear. The rows now *name* the
robust setting instead of resting on one a 5% drift would break. The audit
distinguishes a thin bound with a robust sibling in the same row from a thin bound
with nowhere to go, because the first needs documentation and the second needs new
science.

Together with C41 (*N*=512 recovered at *k*≥2) and C57 (recovered at *k*=14), the
stride lever has now rescued or hardened five rows. That makes it a pattern rather
than a trick: **at *N*=1024 these are gap-budget problems with a known exchange
rate, not noise walls.**

### 16.3 The determinism bug was still hiding a claim

Nine rows assert a SING FAIL or SIGTRAP. **Every one of their logs predates the
2026-08-15 determinism fix**, which makes the whole set suspect: C69's *n*=512
failure had already turned out to be Dictionary-order nondeterminism rather than a
noise limit.

Re-running them post-fix splits the set cleanly.

**Recovered.** C43's `k=8 public-ms SING FAIL` was logged 2026-08-14. Post-fix it
**passes both paths** with no mismatch. Its ε settles at n=32 to −181.0 with a
bound of −113.6, so *k*=8 meets ε **and** SING — where the row previously had
*k*=4 failing ε and *k*=8 failing SING, i.e. no working configuration at all. That
is the second claim this one bug was suppressing.

**Confirmed structural, which is equally valuable.** PicoRV lut6 at *N*=1024 *k*=7
still fails post-fix on both gadgets, at the *identical* DFF cells —
`slice$14361` for covering-b2, `slice$14359` for covering-b1. Same mismatch, same
slice, so C60 and C61 are deterministic and structural. They are stronger negatives
now than when they were recorded, and the only way to know that was to re-run them.
C56 likewise reproduces exactly, tick index and direction included.

### 16.4 A meta-claim falsified

C43 asserted its *k*=4 figure "cannot be resolved by more trials", citing the
~15 days that ±1-order resolution would need at 155 s/trial. That is the standard
§14 already corrected: clearing a bar is far cheaper than resolving to ±1 order.
Settled at n=32 in about **80 minutes** — *k*=4 gives −34.1 and genuinely fails, so
the row's "not stable" hedge was right while its cost estimate was wrong.

This was the last surviving instance of that error in the corpus, and it was the
expensive kind: a maintainer reading "unresolvable" does not try.

### 16.5 The Bombe question: load cannot move these numbers

A P1030680 Welchman Bombe ran concurrently through much of this work, which raises
a fair objection: were the fragility verdicts artifacts of a loaded machine?

No, and it is checkable rather than arguable. σ̂ is deterministic arithmetic off a
fixed LCG seed, so contention changes when an answer arrives, never what it is.
Two measurements re-run under the Bombe came back **bit-identical**:

| Measurement | earlier | under Bombe |
|-------------|---------|-------------|
| C22 *N*=128 n=512 | σ̂ 1 666 138.7, ε −18.0 | σ̂ 1 666 138.7, ε −18.0 |
| C41 *N*=512 *k*=2 n=16 | σ̂ 303 653.9, ε −138.7, bound −69.0 | identical |

**Timings are a different matter**, and there the guard already exists and works.
`Scripts/leeloo.py` detects a competing HELUT process *by name* and refuses with
exit 2. Confirmed live: it listed the Bombe (pid 47376) while `machine_busy()` read
False at 0.284/core — one bench is only ~26% of a core on this box, so load average
alone does not catch it. The by-name check is what saves the timing rows. No timing
was re-measured in this work, so nothing timing-based moved.
