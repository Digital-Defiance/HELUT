#!/usr/bin/env python3
"""Run a benchmark N times and report the spread, not a single lucky number.

    python3 Scripts/bench_repeat.py --runs 3 -- <command...>
    python3 Scripts/bench_repeat.py --runs 5 --metric 'PASS ([0-9.]+) s' -- <cmd...>

Why this exists: almost every timing in directives/claim-sheet.md is a single
observation. Thermal state, page cache, GPU clock residency and other jobs on the
box all move these numbers, so a lone figure is not reproducible even on the same
machine. A reviewer is right to distrust it.

What it reports:
  n, min, median, mean, max, stdev, and relative spread (max-min)/median.

Reporting rule this repo adopts (2026-08-15): quote the **median of at least 3**
runs and print the spread alongside. Do not quote a minimum as if it were typical,
and do not quote a mean when n=3 and one run is an outlier.

Two clocks are captured:
  wall    - wall time of the whole process, always available
  metric  - an optional number scraped from stdout via --metric regex, group 1,
            for when the tool reports its own internal timing

Exit code is 0 if every run exited 0, else 1. Timing of failed runs is discarded
and reported separately, because a crashed run's wall time is meaningless.
"""

from __future__ import annotations

import argparse
import re
import statistics
import subprocess
import sys
import time


def summarize(label: str, xs: list[float], unit: str = "s") -> dict:
    if not xs:
        return {}
    med = statistics.median(xs)
    row = {
        "label": label,
        "n": len(xs),
        "min": min(xs),
        "median": med,
        "mean": statistics.fmean(xs),
        "max": max(xs),
        "stdev": statistics.stdev(xs) if len(xs) > 1 else 0.0,
        "spread": (max(xs) - min(xs)) / med if med else 0.0,
    }
    print(
        f"  {label:8} n={row['n']}  min={row['min']:.4g}{unit}  "
        f"median={row['median']:.4g}{unit}  mean={row['mean']:.4g}{unit}  "
        f"max={row['max']:.4g}{unit}  sd={row['stdev']:.3g}  "
        f"spread={row['spread'] * 100:.1f}%"
    )
    return row


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--warmup", type=int, default=0, help="discarded runs first")
    ap.add_argument("--metric", default=None, help="regex, group 1 = a number on stdout")
    ap.add_argument("--label", default=None, help="what is being measured")
    ap.add_argument("cmd", nargs=argparse.REMAINDER)
    args = ap.parse_args()

    cmd = args.cmd[1:] if args.cmd and args.cmd[0] == "--" else args.cmd
    if not cmd:
        print("error: no command given (use: --runs 3 -- <command>)", file=sys.stderr)
        return 2
    if args.runs < 3:
        print(
            f"warning: --runs {args.runs} is below the 3-run reporting floor; "
            f"the median will not be meaningful",
            file=sys.stderr,
        )

    label = args.label or " ".join(cmd)[:60]
    pat = re.compile(args.metric) if args.metric else None

    print(f"benchmark: {label}")
    print(f"command  : {' '.join(cmd)}")
    print(f"runs     : {args.runs} (warmup {args.warmup})")
    print()

    walls: list[float] = []
    metrics: list[float] = []
    failures: list[int] = []

    for i in range(args.warmup + args.runs):
        warm = i < args.warmup
        t0 = time.monotonic()
        proc = subprocess.run(cmd, capture_output=True, text=True)
        wall = time.monotonic() - t0
        tag = "warmup" if warm else f"run {i - args.warmup + 1}"

        got = None
        if pat:
            m = pat.search(proc.stdout) or pat.search(proc.stderr)
            if m:
                try:
                    got = float(m.group(1))
                except (ValueError, IndexError):
                    got = None

        status = "ok" if proc.returncode == 0 else f"EXIT {proc.returncode}"
        extra = f"  metric={got:.4g}" if got is not None else ""
        print(f"  {tag:8} wall={wall:8.3f}s  {status}{extra}")

        if warm:
            continue
        if proc.returncode != 0:
            failures.append(i - args.warmup + 1)
            continue
        walls.append(wall)
        if got is not None:
            metrics.append(got)

    print()
    if failures:
        print(f"  {len(failures)} run(s) failed: {failures} (timings discarded)")
    summarize("wall", walls)
    if metrics:
        summarize("metric", metrics)
    if not metrics and pat:
        print("  metric   not found on stdout/stderr — check the --metric regex")

    print()
    if walls:
        med = statistics.median(walls)
        spread = (max(walls) - min(walls)) / med if med else 0
        print(f"Quote as: median {med:.3g}s of {len(walls)} runs, spread {spread * 100:.1f}%")
        if spread > 0.25:
            print("NOTE spread exceeds 25% — this figure is not stable enough to")
            print("     quote as a single number; report the range instead.")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
