# Theorem 1 in plain English

A distillation of the six structural clauses of **C19**. Uniqueness of the
genome is a different result (**C44**). Diffed against
[`tensorlut-theorem.md`](tensorlut-theorem.md), which is the formal statement.

Check it without Swift: `python3 Scripts/tensorlut_math_ref.py`

## Setup

A lookup table is a truth table: for a six-input LUT, sixty-four bits saying what
the gate outputs on each input pattern. Take those bits and let them slide. Each
entry becomes \(w_i\in[0,1]\), and the table's response to a binary input is the
multilinear extension of the original, which agrees with the real gate whenever
every \(w_i\) sits at 0 or 1 and interpolates smoothly in between.

For a genome \(w\in[0,1]^{64L}\) over \(L\) lookup tables, write

- \(F_{\mathrm{crypto}}=-\lVert y(w)-t\rVert_2^2\), the negative squared error between the soft circuit output and a target,
- \(\pi(w)=\sum_i w_i(1-w_i)\), a penalty measuring how far the sliders are from being bits,
- \(F=F_{\mathrm{crypto}}-\lambda\pi\) with \(\lambda\ge 0\).

Search over \(F\) with \(\lambda\) rising, and at the end round each slider back
to a bit. The theorem is about whether that arrangement is coherent.

## What the six clauses say

1. \(\pi\ge 0\), with equality exactly when every slider is 0 or 1. So the penalty measures what it claims to.
2. \(F_{\mathrm{crypto}}\le 0\), with equality exactly when the soft outputs hit the target.
3. Hold \(w\) fixed and raise \(\lambda\): \(F\) cannot improve, and strictly worsens whenever \(\pi>0\). The pressure only ever points toward bits.
4. The emitter \(E(w)_i=\mathbf{1}[w_i\ge 1/2]\) is the identity on genomes that are already binary, so rounding a finished solution leaves it alone.
5. Plugboard pairs must form a partial involution, meaning no letter appears twice. Applying a valid pair set twice returns the identity.
6. Frozen blocks of the genome do not contribute to \(\pi\), so freezing part of a circuit does not distort the pressure on the rest.

That is the architecture, and it is deliberately modest.

## What it does not say

Clause 4 is about genomes already at the corners. It does not say that rounding a
fractional \(w\) improves \(F_{\mathrm{crypto}}\), because rounding moves \(y\)
as well. Nor is there a claim that the binary \(w\) with
\(F_{\mathrm{crypto}}=0\) is unique, since many different truth tables can
produce the same output on the patterns you observed. Unique maximizer at
\(w=t\) is **C44**, and holds only in the separable case where \(y(w)=w\): one
fully observed table, no interpolation between layers.

Nothing here recovers a key, decrypts anything, or shows that a genetic algorithm
will find a solution on an arbitrary netlist.

## What a mathematician can skip

Swift, Metal, Homebrew, Yosys, and the wartime message. What is left is a
polynomial objective on the unit cube plus an involution constraint on a finite
alphabet.

## Standing caveats

- Melt completeness for multi-LUT topologies is open; **C44** covers the separable interpolant only. Note that *termination on bits* is not the open part: raising \(\lambda\) is the classical concave exact penalty for 0–1 programming (Raghavachari 1969), and the sufficient bound for a two-LUT topology is \(\lambda\ge 2+\sqrt3\) (`Scripts/penalty_threshold.py`). What is open is how that bound scales with circuit structure — §4–§5 of [`../note/lut-relaxation.tex`](../note/lut-relaxation.tex).
- No cryptanalytic break and no P1030680 plaintext (**H6**).
- The \(q=2^{32}\) torus is a different object from this one ([`q-32-vs-q-2.md`](q-32-vs-q-2.md)).

Smallest worked example of the LUT view: [`../INTRO.md`](../INTRO.md).
