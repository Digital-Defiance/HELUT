# Incomplete public-MS covering gap (Track A / approximate path)

**Status:** machine-checked in `GGSWIncompleteCovering.certificate()` (**C31**).  
Companion to exact covering (**C27**/**C29**): grades the *truncation budget* at production *N*=1024.

Living inventory: [`claim-sheet.md`](claim-sheet.md). Exact covering: [`ggsw-public-ms-covering.md`](ggsw-public-ms-covering.md).

---

## Setup

`cryptoPublicMS` keeps \(g_0=\delta\) with \(\ell=\lfloor 32/\mathrm{baseLog}\rfloor\).
When \(\mathrm{baseLog}\nmid 32\), the product is incomplete:

\[
\mathrm{uncoveredBits}=32-\mathrm{baseLog}\cdot\ell.
\]

At \(N=1024\): \(\mathrm{baseLog}=11\), \(\ell=2\), product \(22\), **uncoveredBits = 10**.

---

## Theorem (structural gap)

1. **Live match.** `uncoveredBits(cryptoPublicMS(N))` equals \(32-\mathrm{baseLog}\cdot\ell\) for every practical \(N\).
2. **Production.** Exact degrees have uncoveredBits \(=0\); \(N=1024\) has uncoveredBits \(=10\).
3. **Reconstruction.** Covering decomp (`.crypto`) recovers every `UInt32`. Incomplete public-MS recovers only the top \(\mathrm{baseLog}\cdot\ell\) bits (low uncoveredBits forced to 0).
4. **Approx candidate.** Closest covering \(\mathrm{baseLog}\le\) public-MS ideal among divisors of 32 is **8** at \(N=1024\) — the classic `.crypto` gadget (\(g_0\neq\delta\)).

Reproduce: `swift test -c release --filter testGGSWIncompleteCoveringCertificate`.

---

## Measured tiny inject on the approx candidate (**C32** / **C33**)

At \(N=1024\), inject \(B=1\):

| Surface | Receipt |
|---------|---------|
| Measure 4 trials | `.crypto` εlog2≈−32.2; `cryptoPublicMS` undecodable · `…-B1.log` |
| Measure 8 trials | `.crypto` εlog2≈**−8.4** (σ̂≈2.95×10⁵) · `…-B1-t8.log` |
| Metal SING secret + `.crypto` | **PASS** · *B*<sub>bk</sub>=712370 · `…-covering-crypto-noisy-B1.log` (**C33**) |
| Metal SING public-ms + `.crypto` | **PASS** · *B*<sub>bk</sub>=352756 · `…-covering-publicms-noisy-B1.log` (**C33**) |

So Track A *can* run Metal SING with covering-non-δ + inject \(B=1\).
**C34** upgrades the gadget to covering `baseLog=4` (ℓ=8): σ̂≈2.95×10⁴,
asymptotic εlog2≈−913 (meets ≤2⁻⁶⁴) with Metal SING PASS.
**C35** pushes covering `baseLog=2` (ℓ=16): ε≤2⁻⁶⁴ through inject \(B=16\)
(εlog2≈−65.4) + Metal SING PASS.
**C36** pushes covering `baseLog=1` (ℓ=32): ε≤2⁻⁶⁴ through inject \(B=32\)
(εlog2≈−139) + Metal SING PASS; \(B=128\) stays ε≈−0.6 (no unlock vs b2).
`cryptoPublicMS` + noise remains undecodable; noiseless `cryptoPublicMS` SING is still **C21**.

---

## Five-cell test

| Cell | Artifact |
|------|----------|
| Proof | C31 lemmas + certificate |
| Table | Uncovered / approx candidate; C32 inject table |
| Metric | uncoveredBits(1024)=10; εlog2(crypto,B=1)≈−32.2 |
| Examples | Reconstruct covering vs incomplete; closestCoveringBaseLog=8 |
| Application | Cookbook: approx path = covering `.crypto`, not wider limb (**C29**) |
