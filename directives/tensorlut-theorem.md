# Theorem (TensorLUT continuous→discrete)

**Status:** machine-checked lemmas in `TensorLUTFormal.certificate()` (**C19**). Not a cryptanalytic break.  
**Hypotheses** are listed on the certificate; empirical grades (baseline / shatter / blind 3-pair) are separate evidence in `BREAK_P1030680.md`.

Living inventory: [`claim-sheet.md`](claim-sheet.md). Paper: `paper/helut.tex` §Pillar II.

---

## Setup

Let \(L\) be the number of LUT6 cells and \(w\in[0,1]^{64L}\) the concatenated INIT genome.
Let \(y(w)\) be the **multilinear extension** of those INITs on \([0,1]\) (exact on \(\{0,1\}\) inputs).
Let \(t\) be a target bit vector of matching width. Soft crypto fitness and discreteness penalty:

\[
F_{\mathrm{crypto}}(w)=-\lVert y(w)-t\rVert_2^2,\qquad
\pi(w)=\sum_i w_i(1-w_i),\qquad
F(w)=F_{\mathrm{crypto}}(w)-\lambda\,\pi(w),\quad\lambda\ge 0.
\]

Emitter: \(E(w)_i=\mathbf{1}[w_i\ge\tfrac12]\). Freeze mask \(M\subseteq\{1,\dots,64L\}\) removes frozen coordinates from \(\pi\).
Stecker genotypes are **partial involutions** (disjoint pairs) on \(\{0,\dots,25\}\).

---

## Theorem 1 (structural)

Assume the hypotheses on the certificate (multilinear LUT, GA mutates only unfrozen \(w_i\in[0,1]\), involution sandwich freezes core INITs). Then:

1. **Discreteness.** \(\pi(w)\ge 0\), with equality iff \(w\in\{0,1\}^{64L}\).
2. **Crypto MSE.** \(F_{\mathrm{crypto}}(w)\le 0\), with equality iff \(y(w)=t\).
3. **Combined objective.** \(F(w)\le F_{\mathrm{crypto}}(w)\); if \(\pi(w)>0\), increasing \(\lambda\) strictly decreases \(F\).
4. **Emitter.** \(E\) is idempotent on \(\{0,1\}^{64L}\) and agrees with threshold \(\tfrac12\).
5. **Involution sandwich.** Overlapping pairs are rejected; applying a valid pair-set twice is the identity on the alphabet.
6. **Freeze.** Coordinates in \(M\) do not contribute to \(\pi\).

**Proof (machine-checked).** Each clause is `TensorLUTFormal.check*` in `Sources/HELUTCore/TensorLUTFormal.swift`, aggregated by `TensorLUTFormal.certificate()`. Reproduce: `swift test -c release --filter testTensorLUTFormalCertificate`.

**What this does not prove.** Recovery of arbitrary keys; a U-534 / P1030680 plaintext; that melt is complete for all netlists. Shatter / hold grades remain empirical.

---

## Theorem 1 corollary (emitter / freeze completeness)

**Status:** machine-checked in `TensorLUTFormal.corollaryCertificate()` (**C25**).

Assume Theorem 1 hypotheses, plus: Verilog emit uses \(E\); stecker GA uses `mutatedPreserving` for frozen pairs. Then:

7. **Emitter–discrete agreement.** If \(\pi(w)=0\), then \(E(w)_i=w_i\) (as bits) for all \(i\) — emitted INIT equals the binary cube.
8. **Involution under freeze.** Every genotype returned by `mutatedPreserving(frozen:…)` contains all frozen pairs and remains a partial involution; overlapping a frozen letter is rejected by `isValid`.

**Proof.** `checkEmitterDiscreteAgreement` / `checkInvolutionUnderFreeze`. Reproduce:
`swift test -c release --filter testTensorLUTFormalCorollaryCertificate`.

**Still does not prove.** Melt completeness for arbitrary netlists; that every shatter lineage reaches \(\pi=0\). Restricted melt–freeze–snap for a separable interpolant is **C44**.

---

## Five-cell test

| Cell | Artifact |
|------|----------|
| Proof | Theorem 1 + `TensorLUTFormalCertificate`; corollary **C25** |
| Table | Lemmas vs `holds` on the certificate; campaign grades in BREAK §21 |
| Metric | \(F_{\mathrm{crypto}}=0\) on unmutated baseline; \(\pi=0\) on binary INIT |
| Examples | M4 baseline emit; freeze-core involution; blind 3-pair PASS |
| Application | Stecker search that cannot propose a non-reciprocal map |

---

## Theorem 1″ (melt–freeze–snap, separable interpolant)

**Status:** machine-checked in `TensorLUTFormal.meltFreezeSnapCertificate()` (**C44**).

Assume each used INIT address is an independent Boolean target \(t\in\{0,1\}^k\) (fully observed 1-LUT), \(w\in[0,1]^k\), \(\lambda\ge 0\), and
\[
F(w)=-\lVert w-t\rVert_2^2-\lambda\,\pi(w).
\]

9. **Unique maximizer.** \(F(w)\le 0=F(t)\), with equality iff \(w=t\). The objective snaps; it does not have a fractional global max.
10. **Snap basin.** If \(\lvert w_i-t_i\rvert<1/2\) for all \(i\), then \(E(w)=t\) (emitted Verilog INIT equals the interpolant). Crossing \(1/2\) on any used address leaves the basin.
11. **Freeze.** Coordinates already at \(t\) may be removed from search without changing the unique maximizer on free coordinates. A coordinate frozen away from \(t\) makes \(F=0\) unreachable.

**Proof.** `checkSeparableMeltUniqueMaximizer` / `checkSnapBasinCompleteness` / `checkFreezePreservesMaximizer`. Reproduce: `swift test -c release --filter testTensorLUTMeltFreezeSnapCertificate`. Empirical 1-LUT XOR: `testXORLambdaCoolingSnapsTowardBinary` with `polishBinaryAtEnd`.

**Empirical (C48).** A 2-LUT cascade \(y=(a\land b)\oplus c\) melted from \(w=1/2\), snapped, and emitted as two LUT6 cells. Snapped INIT matches all 8 corners (NAND+XNOR is a valid dual). Not Yosys re-synth; not arbitrary-netlist completeness.
