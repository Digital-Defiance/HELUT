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

## Measured tiny inject on the approx candidate (**C32**)

At \(N=1024\), inject \(B\in\{1,2\}\) (`logs/helut-noisy-bk-measure-n1024-B1.log`):

| Gadget | \(B\) | Decodable? | εlog2 |
|--------|-------|------------|-------|
| `cryptoPublicMS` (incomplete, \(g_0=\delta\)) | 1 | **no** | 0 |
| `cryptoPublicMS` | 2 | **no** | 0 |
| `.crypto` (covering, \(g_0\neq\delta\)) | 1 | **yes** | **≈ −32.2** |
| `.crypto` | 2 | yes | ≈ −1.3 |

So the approx candidate *carries* \(B=1\) with ε ≈ 2⁻³² — better than **C26**’s \(B=4\) (ε ≈ −1), but **not** ε ≤ 2⁻⁶⁴. Track A Metal SING still defaults to `cryptoPublicMS` + *e*=0 BK.

---

## Five-cell test

| Cell | Artifact |
|------|----------|
| Proof | C31 lemmas + certificate |
| Table | Uncovered / approx candidate; C32 inject table |
| Metric | uncoveredBits(1024)=10; εlog2(crypto,B=1)≈−32.2 |
| Examples | Reconstruct covering vs incomplete; closestCoveringBaseLog=8 |
| Application | Cookbook: approx path = covering `.crypto`, not wider limb (**C29**) |
