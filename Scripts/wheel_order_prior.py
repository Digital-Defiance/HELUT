#!/usr/bin/env python3
"""Measure the same-day wheel-order prior from the recovered daily keys.

The campaign already carried a general convention prior (`naval-two-notch-right`: one of
VI/VII/VIII on the fast wheel, 126 of 336 orders). This measures what the corpus actually
shows, which is tighter: every daily key recovered from the 1 May 1945 U-534 scrape puts
rotor **VIII** specifically in the fast position, on three different nets.

Why this is worth having: it is an ORDERING prior over wheel orders, so it costs nothing to
be wrong. Fronting an arm with the 42 VIII-fast orders instead of all 336 is an 8x speedup on
the part of the space most likely to contain the answer; if the prior is wrong the remaining
294 orders are simply run afterwards and nothing has been eliminated. A negative under this
prior must never be reported as covering the wheel-order space.

Honest limits, printed with the result: three nets is a thin sample, the nets may have drawn
from a shared Schluesseltafel rather than independently, and the sample is the set of keys
Hoerenberg happened to break rather than a random draw.

    python3 Scripts/wheel_order_prior.py
    python3 Scripts/wheel_order_prior.py --check   # non-zero exit if the pattern breaks
"""
from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROMAN = {"1": "I", "2": "II", "3": "III", "4": "IV",
         "5": "V", "6": "VI", "7": "VII", "8": "VIII"}


def split_wheels(wheels: str) -> list[str]:
    text = str(wheels).strip()
    if not text:
        return []
    if text.isdigit():
        return [ROMAN.get(c, c) for c in text]
    return [ROMAN.get(t, t) for t in text.replace("-", " ").split()]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", type=Path, default=Path("Fixtures/u534_corpus.json"))
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    data = json.loads(args.corpus.read_text(encoding="utf-8"))
    msgs = [m for m in data["messages"] if m.get("broken") and m.get("wheels")]

    # A daily key is (wheels, rings, plugs). Messages sharing one share the plugboard.
    groups: dict[tuple, list[str]] = defaultdict(list)
    for m in msgs:
        groups[(str(m["wheels"]), m.get("rings"), m.get("plugs"))].append(m["id"])

    print(f"corpus            : {args.corpus}")
    print(f"keyed messages    : {len(msgs)}")
    print(f"distinct daily keys: {len(groups)}")
    print()
    print(f"{'wheels':10} {'rings':7} {'msgs':>5}  left / middle / RIGHT")
    print("-" * 60)
    fast = Counter()
    for (wheels, rings, _plugs), ids in sorted(groups.items(), key=lambda kv: -len(kv[1])):
        parts = split_wheels(wheels)
        if len(parts) != 3:
            print(f"{wheels:10} {str(rings):7} {len(ids):>5}  (unparsed)")
            continue
        fast[parts[2]] += 1
        print(f"{wheels:10} {str(rings):7} {len(ids):>5}  "
              f"{parts[0]} / {parts[1]} / {parts[2]}")

    print()
    total = sum(fast.values())
    print(f"fast-wheel distribution across {total} nets: {dict(fast)}")

    unanimous = len(fast) == 1 and total >= 2
    if unanimous:
        rotor = next(iter(fast))
        p = (1 / 8) ** (total - 1)
        kept = 7 * 6  # orders with that rotor pinned in the fast position
        print(f"UNANIMOUS: rotor {rotor} on the fast wheel in all {total} nets.")
        print(f"  probability under independent per-net choice : {p:.4f}")
        print(f"  wheel orders with {rotor} fast               : {kept} of 336 "
              f"({336 / kept:.0f}x speedup as an ordering prior)")
        print()
        print("  Use: --subspace viii-fast-wheel (M4ThetisAttack.vIIIFastWheelPrior).")
        print("  This ELIMINATES NOTHING. It reorders the search so the most likely wheel")
        print("  orders run first; the other 294 remain open and must be run before any")
        print("  wheel-order coverage claim is made.")
        print()
        print("  Limits: 3 nets is a thin sample; the nets may share a Schluesseltafel")
        print("  rather than choosing independently; and these are the keys that happened")
        print("  to be broken, not a random draw.")
    else:
        print("NOT unanimous — the fast-wheel prior does not hold on this corpus.")

    if args.check and not unanimous:
        print("\nFAIL: expected a unanimous fast wheel; the prior has changed.",
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
