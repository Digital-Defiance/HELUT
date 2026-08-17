#!/usr/bin/env python3
"""Is every ε figure in the claim sheet supported by the sample size behind it?

Why this exists as its own script.

`claim_audit.py` checks structural integrity -- cited logs exist, `--filter`
names resolve, quoted numbers trace back to a log. None of that catches a row
whose ε point estimate is real, correctly measured, correctly cited, and still
insufficient to support the bar it asserts. That is a *statistical* defect, and it
is the one that bit hardest: C36, C37, C41, C52 and C57 all quoted an ε that
their trial count could not carry.

The arithmetic. A one-sided 95% bound on σ is `σ̂·√(m/χ²₀.₀₅(m))`, and
`log₂ε ∝ −1/σ²`, so the bound clears a target iff

    |point| ≥ (m / χ²₀.₀₅(m)) · |target|

The factor falls monotonically in m, so each sample count buys a fixed slack.
n=4 is not universally too small -- it carries any point estimate at or below
−355. Thin margins are what cost.

Three outcomes, needing different responses:

  supported          quoted ε clears the slack its n buys, or the row prints a
                     95% bound, or the row is a recorded negative
  under-sampled      margin is real but unproven: buy trials
  unreachable        point estimate is itself past the bar: weaken the claim

Usage:
    python3 Scripts/eps_claim_audit.py            # report
    python3 Scripts/eps_claim_audit.py --strict   # exit 1 if any row unsupported
"""

from __future__ import annotations

import os
import re
import sys
from math import sqrt

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHEET = os.path.join(ROOT, "directives", "claim-sheet.md")
TARGET = -64.0


def standard_normal_quantile(p: float) -> float:
    """Acklam's rational approximation, matching TFHEGaussianSecurity.swift."""
    a = [-3.969683028665376e01, 2.209460984245205e02, -2.759285104469687e02,
         1.383577518672690e02, -3.066479806614716e01, 2.506628277459239e00]
    b = [-5.447609879822406e01, 1.615858368580409e02, -1.556989798598866e02,
         6.680131188771972e01, -1.328068155288572e01]
    c = [-7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e00,
         -2.549732539343734e00, 4.374664141464968e00, 2.938163982698783e00]
    d = [7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e00,
         3.754408661907416e00]
    plow = 0.02425
    if p < plow:
        q = sqrt(-2 * __import__("math").log(p))
        return ((((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5])
                / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1))
    q = p - 0.5
    r = q * q
    return ((((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q
            / (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1))


def chi2_lower(dof: int, p: float = 0.05) -> float:
    """Wilson-Hilferty, dof = samples (zero-mean RMS estimator, not samples-1)."""
    m = float(dof)
    z = standard_normal_quantile(p)
    base = 1 - 2 / (9 * m) + z * sqrt(2 / (9 * m))
    return m * base * base * base


def slack_factor(n: int) -> float:
    """|point| must be at least this multiple of |target| to clear at n samples."""
    return n / chi2_lower(n)


def required_samples(point: float, target: float = TARGET, cap: int = 4_000_000) -> int | None:
    """Smallest n whose bound clears `target`, or None if the point estimate fails."""
    if point > target:
        return None
    want = abs(point) / abs(target)
    n = 2
    while n < cap:
        if slack_factor(n) <= want:
            return n
        n += 1 if n < 64 else max(1, n // 8)
    return None


def main() -> int:
    strict = "--strict" in sys.argv
    txt = open(SHEET, encoding="utf-8").read()
    rows = [l for l in txt.split("\n") if re.match(r"\|\s*\*\*C\d+\*\*", l)]

    print("ε claim sufficiency audit")
    print(f"target {TARGET:.0f}; slack needed: "
          + ", ".join(f"n={n}->{slack_factor(n)*abs(TARGET):.0f}"
                      for n in (2, 4, 8, 16, 32, 64)))
    print()
    print(f"{'row':6s} {'n':>5s} {'|eps|':>9s} {'need':>6s} {'status':18s} action")
    print("-" * 96)

    problems: list[str] = []
    counted = 0
    for line in rows:
        rid = re.match(r"\|\s*\*\*(C\d+)\*\*", line).group(1)
        eps = [abs(float(x)) for x in
               re.findall(r"εlog2[≈=]\s*\*{0,2}(?:−|-)(\d+(?:\.\d+)?)", line)]
        if not eps:
            continue
        counted += 1
        trials = [int(x) for x in re.findall(r"--trials\s+(\d+)", line)]
        trials += [int(x) for x in re.findall(r"\bn=(\d+)", line)]
        n = max(trials) if trials else None
        best = max(eps)

        has_bound = bool(re.search(r"bound\s+\*{0,2}(?:−|-)\d", line))
        negative = bool(re.search(
            r"None meet|does \*\*not\*\*|not −64|WITHDRAWN|does NOT meet|no ε≤2⁻⁶⁴",
            line))

        if has_bound:
            status, action = "has 95% bound", "-"
        elif negative:
            status, action = "recorded negative", "-"
        elif n and best >= slack_factor(n) * abs(TARGET):
            status, action = "clears on slack", "-"
        else:
            need = required_samples(-best)
            if need is None:
                status = "UNREACHABLE"
                action = "point estimate past the bar; weaken the claim"
            else:
                status = "UNDER-SAMPLED"
                action = f"re-run at n>={need}, or print a bound"
            problems.append(f"{rid}: {status.lower()} ({action})")

        need_disp = f"{slack_factor(n)*abs(TARGET):.0f}" if n else "?"
        print(f"{rid:6s} {str(n or '?'):>5s} {best:9.1f} {need_disp:>6s} {status:18s} {action}")

    print()
    print(f"{counted} rows quote an ε figure; {len(problems)} unsupported")
    for p in problems:
        print(f"  ! {p}")
    if problems and strict:
        return 1
    if not problems:
        print("\nAll ε figures are supported by the sample size behind them.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
