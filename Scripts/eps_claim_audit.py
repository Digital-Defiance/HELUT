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

# Observed sigma-hat spread across the 2026-08-16 ladders. A bound with less
# headroom than this can flip between runs without any defect.
FRAGILE_BELOW = 1.5


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


def headroom_from_bound(bound: float, target: float = TARGET) -> float:
    """σ̂ growth a *printed* bound tolerates, needing only the bound itself.

    Since `bound = point / slack(n)` and headroom is
    `√(|point| / (slack(n)·|target|))`, the slack cancels:

        headroom = √(|bound| / |target|)

    Preferred over recomputing from the point estimate, because rows accumulate
    several ε figures as ladders are added and picking the right one by regex is
    error-prone -- an earlier version of this script reported C57 at its
    superseded k=7 value.
    """
    if bound >= 0 or target >= 0:
        return 0.0
    return sqrt(abs(bound) / abs(target))


def sigma_headroom(point: float, n: int, target: float = TARGET) -> float:
    """How far σ̂ could rise before this bound stops clearing the target.

    Pass/fail is not the whole story. `log₂ε ∝ −1/σ²`, so if σ̂ turns out g× larger
    than measured, `|point|` falls by g², and the bound holds only while
    `|point|/g² ≥ slack(n)·|target|`. So the row tolerates

        g ≤ √(|point| / (slack(n)·|target|))

    This matters because σ̂ genuinely moves between runs: on 2026-08-16 the C52
    ladder went 401 326 → 543 612 (1.35×) between n=16 and n=32, and across all
    rows measured that day the spread reached 1.5×. A row with less headroom than
    that can flip on a re-run without anything being wrong, which is a weaker
    claim than a bare "clears" suggests.

    Note the ceiling: as n grows the bound approaches the point estimate, so
    headroom is capped at √(|point|/|target|) no matter how much compute is spent.
    A row whose point estimate is close to the bar cannot be made robust by
    sampling -- it needs a wider decode gap (stride k), which is how C41 and C57
    were fixed.
    """
    need = slack_factor(n) * abs(target)
    if need <= 0:
        return 0.0
    return sqrt(abs(point) / need)


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

    # A row is not one claim. C41 records native k=1 falling short *and* k>=2
    # clearing; C57 does the same at k=7 vs k=14. Classifying per line forced one
    # verdict onto both and hid the fragility of the positive half. So evaluate
    # each printed bound as its own claim, and fall back to line-level reasoning
    # only for rows that print no bound at all.
    print("Bounds printed in the sheet (each is a separate assertion):")
    print(f"  {'row':6s} {'bound':>9s} {'σ̂ room':>7s}  verdict")
    print("  " + "-" * 74)

    problems: list[str] = []
    fragile: list[tuple[str, float]] = []
    bound_count = 0
    no_bound_rows: list[tuple[str, int | None, float]] = []

    for line in rows:
        rid = re.match(r"\|\s*\*\*(C\d+)\*\*", line).group(1)
        eps = [abs(float(x)) for x in
               re.findall(r"εlog2[≈=]?\s*\*{0,2}(?:−|-)(\d+(?:\.\d+)?)", line)]
        bounds = [float(x.replace("\u2212", "-")) for x in
                  re.findall(r"bound\s+\*{0,2}((?:−|-)\d+(?:\.\d+)?)", line)]
        if not eps and not bounds:
            continue

        if bounds:
            # Does this row offer a robust configuration anywhere? A fragile bound
            # sitting beside a robust sibling is a different situation from a
            # fragile bound with nowhere to go: the first needs the row to name
            # the robust setting, the second needs new science. C36 and C37 are
            # the first kind -- native k=1 is thin, k=2 is comfortable.
            best_room = max(
                (headroom_from_bound(b) for b in bounds if b <= TARGET), default=0.0
            )
            has_robust = best_room >= FRAGILE_BELOW
            for b in sorted(bounds):
                bound_count += 1
                if b <= TARGET:
                    room = headroom_from_bound(b)
                    if room < FRAGILE_BELOW:
                        if has_robust:
                            verdict = (f"thin ({room:.2f}x) but row also has a "
                                       f"{best_room:.2f}x setting")
                        else:
                            fragile.append((rid, room))
                            verdict = f"clears, FRAGILE — {room:.2f}x σ̂ growth breaks it"
                    else:
                        verdict = "clears with margin"
                    print(f"  {rid:6s} {b:9.1f} {room:6.2f}x  {verdict}")
                else:
                    print(f"  {rid:6s} {b:9.1f} {'—':>7s}  does not clear (recorded as unmet)")
            continue

        # No printed bound: judge the quoted point against the slack its n buys.
        trials = [int(x) for x in re.findall(r"--trials\s+(\d+)", line)]
        trials += [int(x) for x in re.findall(r"\bn=(\d+)", line)]
        n = max(trials) if trials else None
        best = max(eps)
        negative = bool(re.search(
            r"None meet|does \*\*not\*\*|not −64|not \(−64\)|WITHDRAWN|does NOT meet"
            r"|no ε≤2⁻⁶⁴|short of −64|short of the bar", line))
        no_bound_rows.append((rid, n, best))
        if negative:
            continue
        if n and best >= slack_factor(n) * abs(TARGET):
            continue
        need = required_samples(-best)
        if need is None:
            problems.append(f"{rid}: point estimate {-best} is past the bar; weaken the claim")
        else:
            problems.append(f"{rid}: under-sampled at n={n}; re-run at n>={need} or print a bound")

    print()
    print("Rows quoting an ε figure with no printed bound:")
    for rid, n, best in no_bound_rows:
        need = slack_factor(n) * abs(TARGET) if n else None
        ok = "ok (clears on slack, or recorded negative)"
        if need and best < need and any(p.startswith(rid + ":") for p in problems):
            ok = "UNSUPPORTED"
        print(f"  {rid:6s} n={str(n or '?'):>4s} |ε|={best:8.1f} "
              f"need={('%.0f' % need) if need else '?':>6s}  {ok}")

    print()
    print(f"{bound_count} printed bounds; {len(problems)} unsupported; {len(fragile)} fragile")
    for p_ in problems:
        print(f"  ! {p_}")
    if fragile:
        print()
        print("Fragile bounds — supported, but by less than the σ̂ spread seen across")
        print("today's ladders (up to 1.5x). These can flip on a re-run with nothing")
        print("actually wrong:")
        for rid, room in sorted(fragile, key=lambda r: r[1]):
            print(f"  ! {rid}: {room:.2f}x headroom. More samples raise the bound only")
            print(f"      toward the point estimate; a wider decode gap (stride k) is the")
            print(f"      lever that adds real margin — see C41 and C57.")
    if problems and strict:
        return 1
    if not problems:
        print()
        print("No ε assertion is unsupported by the sample size behind it.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
