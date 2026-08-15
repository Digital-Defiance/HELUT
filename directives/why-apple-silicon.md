# Why Apple Silicon first

Engineering history, recorded so that nobody mistakes it for a statement about
the mathematics.

HELUT began as an attempt to push one machine to its limit: an Apple Silicon Mac
running `MPSGraph`. The λ-squeeze and the adversarial synthesis loops needed that
much graph throughput before they produced anything at all, so the production
stack grew Metal-shaped. "Works on my laptop" was the research method. It was
never meant as a claim about what the work requires.

The cost of that is real. A mathematician, an FPGA person, or anyone on Linux
cannot get in through Homebrew and macOS 14, and Metal is a hard dependency of
the encrypted path rather than an import that could be conditionally compiled
away. If the only way to see the invariant is a high-end Mac, then for most of
the audience the invariant might as well not exist.

Hence the two Python scripts. Theorem 1 lives on \([0,1]\) and \(\{0,1\}\), so a
stdlib restatement is possible and now exists, along with a toy cipher pair that
demonstrates the LUT-level property on any machine:

```bash
python3 Scripts/toy_cipher_demo.py
python3 Scripts/tensorlut_math_ref.py
```

CI runs both on Linux. They are executable checks rather than formal proofs.

The torus arithmetic is a separate story. HELUT freezes \(q=2^{32}\) because a
machine word then behaves as a torus element for free
([`q-32-vs-q-2.md`](q-32-vs-q-2.md)). A CPU-only production backend, CUDA, or
MLIR would be ports of the same arithmetic rather than a different lattice
assumption, and all three are wishlist items without **C** rows. So: Apple was
the first engine because it was the machine that could take the squeeze. The
next engine should be whoever can run the same graphs.
