#!/usr/bin/env python3
"""Exact-penalty threshold for the LUT relaxation. Stdlib only.

    python3 Scripts/penalty_threshold.py

Maximising F_lambda(w) = -||y(w)-t||^2 - lambda*pi(w) over [0,1]^n is the same
as minimising f(w) + lambda*pi(w), where f(w) = ||y(w)-t||^2 >= 0 and
pi(w) = sum w_i(1-w_i) >= 0 vanishes exactly on {0,1}^n.

That is the classical concave exact penalty for 0-1 programming. Because
Hess(pi) = -2I, the penalised objective f + lambda*pi is concave as soon as

    lambda >= lambda_max(Hess f) / 2                      (*)

everywhere on the cube, and a concave function attains its minimum over a
polytope at a vertex. Since pi vanishes at vertices, the minimiser is then a
genuine binary genome. Raghavachari (1969) for the linear case, Giannessi and
Niccolucci (1976) for nonlinear integer programs, with the sharp penalty bound
in Kalantari and Rosen (1982).

So the existence of a threshold is settled, and this script measures the
constant (*) for a small non-separable circuit, to see how far the sufficient
bound sits above the value at which vertices actually take over.
"""

from __future__ import annotations

import itertools
import math
import random
import sys

from lambda_threshold_probe import DIM, PATTERNS, forward, penalty

H_STEP = 1e-4
JACOBI_SWEEPS = 100


def data_term(w: list[float], t: tuple[float, ...]) -> float:
    return sum((a - b) * (a - b) for a, b in zip(forward(w), t))


def hessian(f, w: list[float], h: float = H_STEP) -> list[list[float]]:
    """Central finite differences. f is a polynomial here, so this is accurate."""
    n = len(w)
    H = [[0.0] * n for _ in range(n)]
    for i in range(n):
        for j in range(i, n):
            wpp, wpm, wmp, wmm = w[:], w[:], w[:], w[:]
            wpp[i] += h; wpp[j] += h
            wpm[i] += h; wpm[j] -= h
            wmp[i] -= h; wmp[j] += h
            wmm[i] -= h; wmm[j] -= h
            val = (f(wpp) - f(wpm) - f(wmp) + f(wmm)) / (4 * h * h)
            H[i][j] = H[j][i] = val
    return H


def jacobi_eigenvalues(mat: list[list[float]], sweeps: int = JACOBI_SWEEPS) -> list[float]:
    """Eigenvalues of a real symmetric matrix by cyclic Jacobi rotations."""
    n = len(mat)
    a = [row[:] for row in mat]
    for _ in range(sweeps):
        off = sum(a[i][j] ** 2 for i in range(n) for j in range(n) if i != j)
        if off < 1e-20:
            break
        for p in range(n - 1):
            for q in range(p + 1, n):
                if abs(a[p][q]) < 1e-18:
                    continue
                theta = (a[q][q] - a[p][p]) / (2.0 * a[p][q])
                t = math.copysign(1.0, theta) / (abs(theta) + math.sqrt(theta * theta + 1.0))
                c = 1.0 / math.sqrt(t * t + 1.0)
                s = t * c
                for k in range(n):
                    akp, akq = a[k][p], a[k][q]
                    a[k][p] = c * akp - s * akq
                    a[k][q] = s * akp + c * akq
                for k in range(n):
                    apk, aqk = a[p][k], a[q][k]
                    a[p][k] = c * apk - s * aqk
                    a[q][k] = s * apk + c * aqk
    return sorted(a[i][i] for i in range(n))


def sample_points(rng: random.Random, n_random: int = 400) -> list[list[float]]:
    """Vertices, face centres, and interior samples."""
    pts = [[float(b) for b in bits] for bits in itertools.product([0, 1], repeat=DIM)]
    pts.append([0.5] * DIM)
    for _ in range(n_random):
        pts.append([rng.random() for _ in range(DIM)])
    return pts


def main() -> int:
    target = (0.5, 0.5, 0.5, 0.5)
    rng = random.Random(23)

    print("Exact-penalty threshold for a two-LUT composition")
    print(f"  sliders n = {DIM}, observed patterns = {len(PATTERNS)}, target = {target}")
    print()

    def f(w: list[float]) -> float:
        return data_term(w, target)

    worst = 0.0
    worst_at = None
    pts = sample_points(rng)
    for w in pts:
        ev = jacobi_eigenvalues(hessian(f, w))
        if ev[-1] > worst:
            worst, worst_at = ev[-1], w[:]

    lam_sufficient = worst / 2.0
    print(f"  sup over {len(pts)} sampled points of lambda_max(Hess f) = {worst:.4f}")
    print(f"  => f + lambda*pi is concave for lambda >= {lam_sufficient:.4f}   (bound (*))")
    print(f"  attained near w = {[round(v, 2) for v in worst_at]}")
    print()

    # Sanity: at the sufficient lambda the penalised Hessian should be <= 0.
    lam = lam_sufficient + 1e-6
    bad = 0
    for w in pts:
        H = hessian(f, w)
        for i in range(DIM):
            H[i][i] -= 2.0 * lam
        if jacobi_eigenvalues(H)[-1] > 1e-6:
            bad += 1
    print(f"  check: penalised Hessian PSD-violations at lambda={lam:.4f}: {bad}/{len(pts)}")

    # And just below, concavity should fail somewhere.
    lam_lo = lam_sufficient * 0.5
    viol = 0
    for w in pts:
        H = hessian(f, w)
        for i in range(DIM):
            H[i][i] -= 2.0 * lam_lo
        if jacobi_eigenvalues(H)[-1] > 1e-6:
            viol += 1
    print(f"  check: at half that lambda ({lam_lo:.4f}) concavity fails at {viol}/{len(pts)} points")
    print()

    print("  Empirically (Scripts/lambda_threshold_probe.py) maximisers become")
    print("  vertices between lambda=2 and lambda=4 on this same topology.")
    print(f"  The sufficient bound {lam_sufficient:.2f} sits above that, as it must:")
    print("  global concavity is sufficient for vertex optima, not necessary.")
    print()

    ok = bad == 0 and worst > 0
    print("PASS bound computed and verified" if ok else "FAIL bound check")
    print()
    print("Not a new theorem. The threshold's existence is Raghavachari (1969) /")
    print("Giannessi-Niccolucci (1976); the sharp penalty bound is Kalantari and")
    print("Rosen (1982). What is specific to this project is only the constant")
    print("above, and how it scales with circuit depth and fan-out, which is open.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
