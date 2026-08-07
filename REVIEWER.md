# Reviewer's map

One page. If you are starting cold, read [`INTRO.md`](INTRO.md) first and skip
this until you want the ledger.

## Without a Mac

Start with the four-page note: [`note/lut-relaxation.pdf`](note/lut-relaxation.pdf).
It is self-contained, has no claim IDs in it, and ends on an open question rather
than a conclusion. Then:

```bash
python3 Scripts/toy_cipher_demo.py         # weak vs broken-by-design toy cipher
python3 Scripts/tensorlut_math_ref.py      # structural checks behind the optimiser
python3 Scripts/lambda_threshold_probe.py  # measured lambda crossover
python3 Scripts/penalty_threshold.py       # the exact-penalty bound, 2 + sqrt(3)
```

Stdlib only, Python 3.8 or newer, verified here on 3.9.6 and 3.14. Both print
PASS and exit 0; the first takes about two seconds because it sweeps a
differential over the full codebook. CI runs both on `ubuntu-latest` against
3.9 and 3.13 on every push, so if they break on Linux that is a bug rather than
a platform excuse.

These are **executable checks, not machine-checked proofs**. They are property
tests over exhaustive small domains and seeded Monte Carlo, ported from the
Swift certificates with the same constants and seeds. Nothing here is Lean or
Coq. The six structural clauses are elementary enough to formalise properly and
nobody has done it.

## The Swift package needs Apple Silicon, and that will not change soon

`Package.swift` pins `swift-tools-version: 6.3`, `macOS 14`, and links `Metal`
and `MetalPerformanceShadersGraph` into the core target. Metal is a hard
dependency of the production path, not a convenience import that can be
`#if`-ed away. Lowering the tools version would not get you a build on Linux;
it would move the failure a few seconds later.

So the split is real and worth stating rather than papering over: the
homomorphic evaluation path is Apple-only today, and the mathematics that path
implements is not. Background in
[`directives/why-apple-silicon.md`](directives/why-apple-silicon.md). A CPU or
CUDA port is wanted and unwritten.

## What you can check where

| Checkable on Linux | Needs Swift and Metal |
|--------------------|------------------------|
| Toy cipher pair: DDT, black-box affineness, one-known-pair recovery, exact 4-round differential, LUT INIT affineness | Encrypted netlist evaluation end to end (**C4**–**C6**, **C20**/**C21**, covering **C52**–**C54**) |
| Six structural clauses of Theorem 1 (**C19**), ported | PicoRV32 covering and key switching (**C60**–**C69**) |
| Unique-maximizer check on the separable case (**C44**), same seeds | Lattice estimator calibration fill (**C23**) |
| Exact public-MS covering exists only at ring degree 8 and 128 (**C27**) | Yosys synthesis of the toy into an actual netlist |

`C25` is only partly ported. The freeze and overlap clauses are in the Python;
the mutation-preserving clause depends on Swift's RNG and is not.

Swift side, if you do have the hardware:

```bash
swift test -c release --filter testTensorLUTFormalCertificate
```

## Reading order for the claims

1. [`directives/theorem-1-plain.md`](directives/theorem-1-plain.md) — the six clauses in English.
2. [`directives/q-32-vs-q-2.md`](directives/q-32-vs-q-2.md) — why the modulus is `2^32`, and where that stops mattering.
3. [`directives/claim-sheet.md`](directives/claim-sheet.md) — every claim, with its receipt.
4. [`REPRODUCE.md`](REPRODUCE.md) — the commands.

## What this repo does not claim

- The wartime message P1030680 is not decrypted (**N5**).
- "176-bit secure" is not a supportable phrase here. The calibration number is
  175.7 against this implementation and 180.2 from Sage on the same row
  (**H1** / **C23**).
- A circuit evaluated as a trivial Metal graph is not being evaluated
  homomorphically.
- Boolean-valued lookup tables in the continuous-LUT work do not make the
  encrypted path binary-modulus LWE.
- Nothing here runs on CUDA.
- The textbook is a scaffold, not a teachable course.

Claim hygiene rules: [`directives/research-release.md`](directives/research-release.md).
