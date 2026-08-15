#!/usr/bin/env python3
"""Where do maximizers of F = -||y(w)-t||^2 - lambda*pi(w) live?

Measures the lambda at which maximizers stop being interior and become cube
vertices, on a small non-separable topology. Stdlib only.

    python3 Scripts/lambda_threshold_probe.py

Setup: two composed 2-input lookup tables. Each is multilinear in its own four
entries, but the composition is not multilinear in w jointly, so this is a
genuinely non-separable topology rather than the y(w)=w case that the repo
already has a certificate for.

Why a threshold exists at all is classical, not open: maximizing F is the same
as minimizing f + lambda*pi with f = ||y-t||^2, which is the concave exact
penalty for 0-1 programming (Raghavachari 1969; Giannessi-Niccolucci 1976 for
the nonlinear case; Kalantari-Rosen 1982 for the bound). The sufficient bound
for this topology is computed in Scripts/penalty_threshold.py and comes out at
lambda >= 2 + sqrt(3). This script measures where the crossover actually is, so
the gap between guarantee and practice is visible.

NOT a theorem and NOT a claim row. Discussion: note/lut-relaxation.tex section 4.
"""

from __future__ import annotations

import itertools
import random
import sys

PATTERNS = [(0, 0), (0, 1), (1, 0), (1, 1)]
DIM = 8


def mlin2(w: list[float], a: float, b: float) -> float:
    """Multilinear extension of a 2-input LUT, exact on binary (a, b)."""
    return w[0] * (1 - a) * (1 - b) + w[1] * a * (1 - b) + w[2] * (1 - a) * b + w[3] * a * b


def forward(w: list[float]) -> list[float]:
    """LUT A on (x0, x1); LUT B consumes A's soft output and x1."""
    out = []
    for x0, x1 in PATTERNS:
        ya = mlin2(w[0:4], x0, x1)
        out.append(mlin2(w[4:8], ya, x1))
    return out


def penalty(w: list[float]) -> float:
    return sum(v * (1.0 - v) for v in w)


def objective(w: list[float], t: tuple[float, ...], lam: float) -> float:
    err = sum((a - b) * (a - b) for a, b in zip(forward(w), t))
    return -err - lam * penalty(w)


def maximize(t, lam, rng, restarts=50, iters=1500):
    """Coordinate ascent with restarts. Candidates include both endpoints."""
    best, best_val = None, float("-inf")
    for _ in range(restarts):
        w = [rng.random() for _ in range(DIM)]
        val = objective(w, t, lam)
        for _ in range(iters):
            i = rng.randrange(DIM)
            cands = [0.0, 1.0] + [rng.random() for _ in range(4)]
            cands.append(min(1.0, max(0.0, w[i] + rng.uniform(-0.08, 0.08))))
            arg, top = w[i], val
            for c in cands:
                keep, w[i] = w[i], c
                v = objective(w, t, lam)
                if v > top:
                    arg, top = c, v
                w[i] = keep
            w[i], val = arg, top
        if val > best_val:
            best, best_val = w[:], val
    return best, best_val


def distance_to_nearest_vertex(w: list[float]) -> float:
    return max(min(abs(v), abs(v - 1.0)) for v in w)


def binary_reachable_outputs() -> set:
    return {tuple(forward([float(b) for b in bits])) for bits in itertools.product([0, 1], repeat=DIM)}


def main() -> int:
    reachable = binary_reachable_outputs()
    target = (0.5, 0.5, 0.5, 0.5)
    print(__doc__.strip().splitlines()[0])
    print()
    print(f"topology: two composed 2-input LUTs, {DIM} sliders, {len(PATTERNS)} observed patterns")
    print(f"distinct outputs reachable by a binary genome: {len(reachable)} of 2^{DIM}")
    print(f"target {target} reachable by a binary genome: {target in reachable}")
    print()
    print("  lambda        F     dist to nearest vertex   maximizer")
    rng = random.Random(5)
    rows = []
    for lam in (0.0, 0.25, 1.0, 2.0, 4.0, 8.0, 16.0):
        w, val = maximize(target, lam, rng)
        d = distance_to_nearest_vertex(w)
        rows.append((lam, val, d))
        print(f"  {lam:6.2f}  {val:9.5f}   {d:18.4f}   {'vertex' if d < 1e-3 else 'interior'}")
    print()
    interior = [lam for lam, _, d in rows if d >= 1e-3]
    vertex = [lam for lam, _, d in rows if d < 1e-3]
    print(f"interior maximizers at lambda in {interior}")
    print(f"vertex   maximizers at lambda in {vertex}")
    if interior and vertex:
        print(f"observed crossover between lambda={max(interior)} and lambda={min(vertex)}")
    print()
    print("Coordinate ascent is a heuristic, so the F column is a lower bound on the")
    print("true maximum and the crossover is empirical. The classical sufficient")
    print("bound for this topology is lambda >= 2 + sqrt(3) ~ 3.732; see")
    print("Scripts/penalty_threshold.py. Open: how that bound scales with circuit")
    print("depth and fan-out (note/lut-relaxation.tex section 5).")
    ok = bool(interior) and bool(vertex) and max(interior) < min(vertex)
    print()
    print("PASS crossover observed" if ok else "NOTE no clean crossover in this sweep")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
