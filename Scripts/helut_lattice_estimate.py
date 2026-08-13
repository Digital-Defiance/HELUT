#!/usr/bin/env python3
"""Fill TFHELWEEstimatorProtocol external bits via lattice-estimator.

Usage:
  .build/release/helut --estimator-export > logs/helut-estimator-pending.json
  python3 Scripts/helut_lattice_estimate.py \\
    --pending logs/helut-estimator-pending.json \\
    --out logs/helut-estimator-results.json

Requires: SageMath + lattice-estimator
  pip install 'git+https://github.com/malb/lattice-estimator.git'
  # plus a working `sage` on PATH (estimator imports sage.all)

Does not invent security numbers — missing deps ⇒ PENDING.
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Optional


def dependency_status() -> str:
    try:
        import sage.all  # noqa: F401
    except Exception as exc:
        return f"missing sage.all ({exc})"
    try:
        from estimator import LWE, ND  # noqa: F401
    except Exception as exc:
        return f"missing estimator ({exc})"
    return "ok"


def try_estimate(n: int, q: int, sigma: float) -> Optional[float]:
    try:
        from estimator import LWE, ND  # type: ignore
    except Exception:
        return None
    try:
        params = LWE.Parameters(
            n=n,
            q=q,
            Xs=ND.UniformMod(2),
            Xe=ND.DiscreteGaussian(sigma),
        )
        costs = LWE.estimate(params)
        bits = None
        if isinstance(costs, dict):
            items = costs.items()
        else:
            items = [("estimate", costs)]
        for _name, cost in items:
            if cost is None:
                continue
            rop = getattr(cost, "rop", None)
            if rop is None and isinstance(cost, dict):
                rop = cost.get("rop")
            if rop is None:
                continue
            try:
                val = float(rop)
                if val <= 0:
                    continue
                b = math.log2(val)
            except Exception:
                continue
            bits = b if bits is None else min(bits, b)
        return bits
    except Exception as exc:
        print(f"estimate failed n={n}: {exc}", file=sys.stderr)
        return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pending", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    args = ap.parse_args()

    dep = dependency_status()
    rows = json.loads(args.pending.read_text())
    results = {}
    pending = []
    for row in rows:
        label = row["label"]
        bits = try_estimate(int(row["n"]), int(row["q"]), float(row["sigma"]))
        if bits is None:
            pending.append(label)
            results[label] = None
        else:
            results[label] = round(bits, 2)

    payload = {
        "dependency_status": dep,
        "results": results,
        "pending": pending,
        "note": (
            "Install: pip install 'git+https://github.com/malb/lattice-estimator.git' "
            "and SageMath (sage.all). None values mean not verified — do not treat "
            "HELUT calibrated estimates as lattice-estimator output."
        ),
    }
    args.out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    print(json.dumps(payload, indent=2, sort_keys=True))
    if dep != "ok":
        print(f"\nDependencies: {dep}", file=sys.stderr)
    if pending:
        print(
            f"\n{len(pending)} rows still PENDING.",
            file=sys.stderr,
        )
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
