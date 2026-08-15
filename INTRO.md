# Start here

This page is the whole introduction. You do not need the rest of the repo, and
you do not need a Mac. Three commands, all stdlib Python 3:

```bash
python3 Scripts/toy_cipher_demo.py         # two toy ciphers, one broken on purpose
python3 Scripts/tensorlut_math_ref.py      # the structural facts the optimiser rests on
python3 Scripts/lambda_threshold_probe.py  # where the optimiser lands as the penalty grows
python3 Scripts/penalty_threshold.py       # the classical bound that explains why
```

If you would rather read four pages than run anything, the same material is in
[`note/lut-relaxation.pdf`](note/lut-relaxation.pdf), which is self-contained and
ends on the open question. If neither the note nor the scripts interest you,
nothing further in the repo will.

## Two ciphers, same skeleton

`toy_cipher_demo.py` builds two 16-bit block ciphers. Four rounds, four-bit
S-boxes, a bit permutation between rounds, round keys by rotation. Identical
wiring, identical schedule. The only thing that differs is the S-box:

| | S-box | Structure |
|--|-------|-----------|
| Nonlinear | PRESENT | differentially 4-uniform |
| Broken on purpose | an invertible affine map over GF(2) | every output bit is a parity of input bits |

Both S-boxes are permutations of the sixteen nibbles. Printed side by side they
look equally scrambled. One of them is a cipher and the other is a linear
equation wearing a costume.

Neither is a good cipher, and it is worth being blunt about that up front. A
16-bit key falls to exhaustive search in well under a second, and four rounds is
nowhere near enough: the script measures a differential holding with probability
about `2^-10` for the nonlinear version, where an ideal 16-bit permutation would
give roughly `2^-16`. So the honest comparison here is between weak and
structurally dead, not between strong and weak. That turns out to be the more
useful thing to learn to see, and it is why the tests below report numbers
rather than verdicts.

## Five ways to spot the difference

The script runs each of these on both ciphers and prints the numbers.

**1. Look at the S-box alone.** Build the difference distribution table: for
each input difference `a`, count how often `S(x) ^ S(x^a)` lands on the same
output difference. The nonlinear box never exceeds 4 out of 16. The affine box
scores 16, because a linear map sends every input difference to exactly one
output difference. This is the first thing a cryptographer checks and it needs
no access to the cipher at all.

**2. Test the whole cipher as a black box.** Any affine map over GF(2)
satisfies

```
E(x) ^ E(y) ^ E(z) == E(x ^ y ^ z)
```

for every triple. Three encryptions and one comparison per test, no key, no
internals. The broken cipher passes the identity on all 200 random triples the
script tries, which is exactly the bad news. The nonlinear cipher fails all 200.

**3. Turn that into a key recovery.** If the cipher is affine then
`E_k(x) = A·x ^ c(k)`, where the matrix `A` does not depend on the key. So you
extract `A` offline by encrypting the basis vectors under any key you like,
invert it over GF(2), then take a single known plaintext-ciphertext pair to pin
down the offset `c`. After that you decrypt every other message. The script
does this against a random key it never inspects and recovers 64 out of 64
plaintexts, having tried zero keys. The same attack against the nonlinear cipher
recovers nothing, and in fact the extracted matrix is singular, so the affine
model does not even fit.

**4. Put a number on it.** The previous three tests answer yes or no. This one
measures. For every one- and two-bit input difference, count over the entire
codebook of 2^16 plaintexts how often each output difference appears. The
nonlinear cipher's best is 66 out of 65536, about `2^-10`. The broken cipher's
best is 65536 out of 65536: probability one, every plaintext, no exceptions. Both
numbers are worse than the `2^-16` an ideal permutation would give, and the
distance between them is the whole point. Counts are exact rather than sampled;
only the set of input differences is restricted, because low-weight differences
are where characteristics live.

**5. Look at the netlist.** Each S-box output bit is a four-input truth table: a
16-bit constant, the thing a `$lut` cell carries once the circuit is synthesised,
called the INIT in this repo. The script prints all eight. For the broken cipher
every one of those INITs is an affine
function of its inputs, which you can check with the same XOR identity from
test 2, one level down. This is the level the rest of this repo works at.

None of the above is new mathematics. Differential and linear cryptanalysis go
back to Biham-Shamir and Matsui in the early nineties, and finding an affine
S-box this way is a homework exercise. The reason it is here is that it is the
smallest honest example of the thing the repo cares about: a circuit-level
property that is visible in the lookup tables.

## What the rest of the repo is

Two mostly separate lines of work share the LUT view above.

The first evaluates gate-level netlists under homomorphic encryption. Yosys
JSON goes in, every `$lut` cell becomes a blind rotation over
`Z/2^32`, and the whole netlist becomes one graph. The interesting question is
how far that scales, and the answers are a stack of measured certificates, some
of which are negative.

The second treats a lookup table's contents as continuous. A truth table entry
becomes a slider in `[0,1]`, exact at the endpoints and a multilinear
interpolation between them, so you can run gradient-style search over circuit
behaviour and then round back to real gates. `tensorlut_math_ref.py` checks the
structural facts that make the rounding step well behaved.
[`directives/theorem-1-plain.md`](directives/theorem-1-plain.md) states them in
English.

Whether `2^32` is essential to any of this is a fair question, and the answer is
no for the second line and yes-for-now for the first.
[`directives/q-32-vs-q-2.md`](directives/q-32-vs-q-2.md) has the detail.

## Honest limits

The production stack is Swift and Metal, and it requires Apple Silicon. That is
not a claim about the mathematics. It is where the work happened, and porting it
is unfinished business rather than a solved problem. See
[`directives/why-apple-silicon.md`](directives/why-apple-silicon.md). The two
Python scripts exist precisely so that the parts which are just mathematics can
be checked without that hardware, and they are executable checks rather than
formal proofs.

Some things this repo does not show, and which you should not read into it:

- No cipher is broken here. The wartime message in `BREAK_P1030680.md` is not
  decrypted, and the campaign log is a record of eliminated key space.
- Running a circuit as a Metal graph is not the same as running it
  homomorphically. The repo keeps those two paths separately labelled and so
  should you.
- The security figures in the calibration tables are measured against this
  implementation, not vetted third-party estimates for production keys.
- The textbook under `textbook/` is scaffolding for collecting results. It is
  not a course anyone should teach from yet.

## If you want to go further

[`REVIEWER.md`](REVIEWER.md) is a one-page map of what can be checked without a
Mac and what cannot. [`REPRODUCE.md`](REPRODUCE.md) has the commands.
[`directives/claim-sheet.md`](directives/claim-sheet.md) is the ledger every
number in this repo has to answer to.
