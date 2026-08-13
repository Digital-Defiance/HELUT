# Theorem / Protocol (Enigma256 SoftBus reciprocity)

**Status:** machine-checked lemmas in `Enigma256Formal.certificate()` (**C24**).  
Builds on empirical **C10** (reciprocity · fail-closed / bijection tests).  
Not an IND-CPA proof; not a claim that Red TensorLUT/KPA/`ent` cannot pressure Blue.

Living inventory: [`claim-sheet.md`](claim-sheet.md). Paper: `paper/helut.tex` §Pillar III. Spec: [`../Enigma256.md`](../Enigma256.md).

---

## Setup

Let \(M\) be an Enigma256 SoftBus machine under day key \(D\) and message key \(m\).
Let \(S_{D,m}\) be the **frozen** combinational scramble (no NLFF step):
plugboard → rotors fwd → un-reflector → rotors rev → plugboard.
Let \(G\) be an NLFF generation (quadratic3 / cubic6 / coupledCubic6).

---

## Theorem 2 (structural SoftBus contract)

Assume the hypotheses on the certificate (reciprocal rotor path; day-key table
builders emit involutions; NLFF retaps do not rewrite the scramble combinational
net). Then:

1. **Bijection.** For every frozen \((D,m)\), \(S_{D,m}\) is a permutation of \(\{0,\ldots,255\}\).
2. **Reciprocity.** \(S_{D,m}\circ S_{D,m}=\mathrm{id}\) (encrypt ≡ decrypt under the same state).
3. **Stream round-trip.** Encrypt-then-decrypt of a byte stream under identical
   \((D,m)\) recovers the plaintext (stepping included).
4. **Day-key involutions.** Derived plugboard is a fixed-point-free involution;
   un-reflector is an involution (fixed points allowed).
5. **Fail-closed coupling.** `hardenedCubic()` rejects `coupledCubic6` and rolls
   back to independent `cubic6` (gen3).

**Proof (machine-checked).** Each clause is `Enigma256Formal.check*` in
`Sources/HELUTCore/Enigma256Formal.swift`, aggregated by
`Enigma256Formal.certificate()`. Reproduce:
`swift test -c release --filter testEnigma256FormalCertificate`.

**What this does not prove.** Semantic security; resistance to all Red arms;
that generation rolls always improve entropy; SoftBus side-channel flatness.

---

## Five-cell test

| Cell | Artifact |
|------|----------|
| Proof | Theorem 2 + `Enigma256FormalCertificate` |
| Table | Lemmas vs `holds` on the certificate; Red battery summaries in logs |
| Metric | Sweep failure = nil; stream round-trip error count = 0 |
| Examples | Fixture IKM day key; 4-state bijection sweep; coupled→gen3 harden |
| Application | SoftBus cipher that cannot ship a non-reciprocal scramble or coupled NLFF harden |
