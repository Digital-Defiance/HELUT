# Theorem (exact public-MS covering under \(q=2^{32}\))

**Status:** machine-checked in `GGSWPublicMSCovering.certificate()` (**C27**).  
Explains why product-shaped *N*=1024 cannot carry measured noisy BK the way *N*=8 / *N*=128 covering gadgets do (**C22**, **C26**, **H4**).

Living inventory: [`claim-sheet.md`](claim-sheet.md). Cookbook: [`parameter-cookbook.md`](parameter-cookbook.md).

---

## Setup

Freeze torus modulus \(q=2^{32}\). Let \(N=2^v\) (\(v\ge 1\)). Rotation spacing:

\[
\delta=\frac{q}{2N}=2^{32-(1+v)}.
\]

A public-MS gadget with \(g_0=\delta\) needs \(\mathrm{baseLog}=1+v\).
An exact covering decomposition (digit extract / Metal EP precondition
`baseLog·ℓ = 32`) needs \((1+v)\mid 32\).

---

## Theorem 3 (structural)

Under the hypotheses on the certificate (\(q=2^{32}\), power-of-two \(N\)):

1. **Public-MS baseLog.** \(g_0=\delta\) iff \(\mathrm{baseLog}=1+\log_2 N\).
2. **Covering.** Exact covering exists iff \(\mathrm{baseLog}\mid 32\).
3. **Conjunction.** Exact public-MS covering holds iff \((1+\log_2 N)\mid 32\).
4. **Practical sizes.** Among \(N\in\{8,16,\ldots,2048\}\), the only exact degrees are
   **\(N=8\)** and **\(N=128\)**. In particular **\(N=1024\)** is not exact
   (`cryptoPublicMS` uses \(\ell=\lfloor 32/11\rfloor=2\), product \(22\neq 32\)).

**Proof (machine-checked).** `GGSWPublicMSCovering.check*` in
`Sources/HELUTCore/GGSWPublicMSCovering.swift`. Reproduce:
`swift test -c release --filter testGGSWPublicMSCoveringCertificate`.

**What this does not prove.** That `.crypto`
(covering, \(g_0\neq\delta\) at *N*=1024) cannot carry tiny noise (see **C26** ε fail);
that HELUT must stay at *N*=1024 forever.

---

## Theorem 3′ (power-of-two word, **C29**)

Same setup with torus word \(w\) (so \(q=2^w\)): exact public-MS covering
iff \((1+\log_2 N)\mid w\).

When \(w\) is itself a power of two, every positive divisor of \(w\) is a
power of two, so \(1+\log_2 N=2^a\) and \(N=2^{2^a-1}\). Among
\(N\in\{8,\ldots,2048\}\) that yields **only** \(\{8,128\}\) — for
**every** \(w\in\{16,32,64,128\}\). In particular **widening the limb to
UInt64 does not unlock *N*=1024** (baseLog=11 never divides a power of two).

Machine check: lemma `powerOfTwoWordObstruction` in the same certificate test as **C27**.

---

## Consequences for H4

| Path | *N* | Covering? | \(g_0=\delta\)? | Noisy BK |
|------|-----|-----------|-----------------|----------|
| Covering public-MS | 8, 128 | yes | yes | **C22** measured; **C28** Metal SING + inject PASS; **C30** ε vs *B* |
| `cryptoPublicMS` | 1024 | **no** | yes | **C26** inject blows up |
| `.crypto` | 1024 | yes | **no** | **C26** *B*=4 ∞-norm OK, ε≪64-bit |

**Two tracks:** throughput *N*=1024 stays *e*=0 BK (Track A). Noisy depth lives at covering *N*∈{8,128} (Track B). Closing Track A needs an **approximate** gadget — not a new power-of-two \(q\) (**C29**).
---

## Five-cell test

| Cell | Artifact |
|------|----------|
| Proof | Theorem 3 + 3′ + `GGSWPublicMSCoveringCertificate` |
| Table | Exact degrees {8,128} vs practical list for *w*∈{16,32,64,128}; H4 path table above |
| Metric | `baseLog·ℓ == w` iff exact; *N*=1024 product under *w*=32 is 22 |
| Examples | *N*=128 exact; *N*=1024 not for any listed *w*; matches `GGSWParams.cryptoPublicMS` |
| Application | Honest production cookbook: do not claim covering noisy BK at *N*=1024 under any \(q=2^{2^k}\) |
