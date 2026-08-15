# Why the modulus is 2^32

This page settles a doctrine question. It does not add an FHE claim, and it is
not permission to write "HELUT works at q=2" anywhere. Human gate: everything
below restates choices already recorded in `parameter-cookbook.md`,
`ggsw-public-ms-covering.md`, and [`tensorlut-theorem.md`](tensorlut-theorem.md).

## The question

Is \(q=2^{32}\) forced by the lattice mathematics, or is it an artifact of
32-bit registers and lookup tables?

Mostly the latter. Lattice LWE is defined for a general modulus. HELUT picks
\(q=2^{32}\) so that a machine word *is* a torus element: `UInt32` addition
wraps exactly the way the torus does, on CPU and inside an `MPSGraph` alike, with
no software reduction step anywhere in the hot loop. That is a systems freeze for
the encrypted path, and it is load-bearing for one specific piece of theory,
covered below.

## Two lines of work, two moduli

| | Encrypted netlist path | Continuous-LUT path |
|--|------------------------|---------------------|
| Object | LWE / GLWE samples, GGSW bootstrapping keys | INIT genome \(w\in[0,1]^{64L}\) |
| Modulus | frozen \(q=2^{32}\), `UInt32` wrap | bits \(\{0,1\}\) and the unit interval |
| Why | the machine word is the torus; the covering lemmas in `ggsw-public-ms-covering.md` are stated at this \(q\) | a lookup table is a Boolean table already; **C19** never mentions \(q\) |
| Meaning of \(q=2\) | binary LWE, a genuinely new experiment, not a reread of **C4**–**C6** | already the setting: the emitter is \(E(w)_i=\mathbf{1}[w_i\ge 1/2]\) |

The covering result is the part that actually depends on the word size. Exact
public modulus-switch covering needs \(1+\log_2 N\) to divide the word, which at
32 bits admits ring degrees 8 and 128 and nothing else in the practical range
(**C27**). Change the word and that arithmetic changes with it. The Python
reference asserts the degenerate case as a negative: at word size 1, no useful
degree survives.

## For a first look, use the Boolean side

Someone arriving from mathematics and wanting the smallest interesting object
should ignore the torus entirely. The continuous-LUT work is bit-valued at the
endpoints and needs no modulus at all, which is why the introductory material
lives there:

```bash
python3 Scripts/toy_cipher_demo.py
python3 Scripts/tensorlut_math_ref.py
```

Neither script imports Metal, Swift, or a modulus.

## Sayable

- HELUT's FHE certificates are stated at \(q=2^{32}\) (**C4**–**C6**, cookbook).
- Theorem 1 is Boolean and \([0,1]\)-valued; it does not need the torus word (**C19**).
- Exact public-MS covering at \(q=2^{32}\) exists only for \(N\in\{8,128\}\) (**C27**).

## Not sayable

- That production encrypted SING at \(N=1024\) runs at \(q=2\).
- That bit-valued lookup tables make the encrypted path binary LWE.
- "176-bit secure" (**H1** / **C23**).

A binary-modulus encrypted path would need its own **C** row, a reproduce
command, and a human check. Until then it stays on this page as an open
experiment.
