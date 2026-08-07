#!/usr/bin/env python3
"""Receipt for the hapax alignment-collapse figures quoted in BREAK_P1030680.md Phase 54.2.

Phase 54.2 printed its counts without committing the script that produced them, and a 2026-09-23
re-measurement reproduced the two placement counts exactly while every diagonal count came out
10-20% higher. This script is the reproducible side of that reconciliation: it recomputes all five
rows from the corpus so the discrepancy stays visible and cannot drift again unnoticed.

It evaluates no rotor settings, asserts no plaintext and moves no verdict. It is bookkeeping.

    python3 Scripts/hapax_collapse_receipt.py
    python3 Scripts/hapax_collapse_receipt.py --check   # non-zero exit if a figure moved
"""
from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path

TARGET = "P1030680"
MIN_LEN, MAX_LEN = 16, 40

# Re-measured 2026-09-23 with the committed tools. The archived Phase 54.2 trio is kept beside
# these so the unreconciled gap is printed rather than quietly replaced.
EXPECTED = {
    "placements": 2_691_455,
    "single_component_loops8": 714_142,
    "diagonals": 8_779,
    "diagonals_loops8": 6_036,
    "diagonals_loops16": 3_699,
}
ARCHIVED = {
    "placements": 2_691_455,          # reproduces exactly
    "single_component_loops8": 714_142,  # reproduces exactly
    "diagonals": 7_321,               # does NOT reproduce
    "diagonals_loops8": 5_497,        # does NOT reproduce
    "diagonals_loops16": 3_600,       # does NOT reproduce
}


def shape(window: str, offset: int, ciphertext: str):
    """(loops, components) by union-find, or None on self-encipherment."""
    parent = list(range(26))
    present: set[int] = set()
    edges = 0

    def find(x: int) -> int:
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for index, char in enumerate(window):
        plain = ord(char) - 65
        cipher = ord(ciphertext[offset + index]) - 65
        if plain == cipher:
            return None
        present.update((plain, cipher))
        ra, rb = find(plain), find(cipher)
        if ra != rb:
            parent[ra] = rb
        edges += 1
    components = len({find(x) for x in present})
    return edges - len(present) + components, components


def measure(corpus: Path) -> dict:
    data = json.loads(corpus.read_text(encoding="utf-8"))
    messages = data["messages"]
    target = next(r for r in messages if r["id"] == TARGET)
    ciphertext = target["ciphertext"]
    decrypts = [(r["id"], r["plaintext"]) for r in messages
                if r.get("plaintext") and r["id"] != TARGET]

    carriers: dict[str, set[str]] = defaultdict(set)
    # Every DISTINCT (source, start) a window occurs at. This must be counted as a set:
    # the same (window, start) pair is re-encountered once per enclosing length, so
    # incrementing a counter during ingestion measures re-sightings, not distinct starts,
    # and will report spurious ambiguity.
    occurrences: dict[str, set[tuple[str, int]]] = defaultdict(set)
    for message_id, text in decrypts:
        for length in range(MIN_LEN, MAX_LEN + 1):
            for start in range(len(text) - length + 1):
                window = text[start:start + length]
                carriers[window].add(message_id)
                occurrences[window].add((message_id, start))

    hapax = [w for w, ids in carriers.items() if len(ids) == 1]
    # A window with >1 distinct start in its carrier would belong to several diagonals at
    # once, making the key ambiguous. Measured: zero such windows.
    multi_start = sum(1 for w in hapax if len(occurrences[w]) > 1)
    source_start = {w: next(iter(occurrences[w]))[1] for w in hapax}

    placements = 0
    sc_loops8 = 0
    best: dict[tuple, tuple] = {}
    for window in hapax:
        source = next(iter(carriers[window]))
        start = source_start[window]
        for offset in range(len(ciphertext) - len(window) + 1):
            result = shape(window, offset, ciphertext)
            if result is None:
                continue
            loops, components = result
            placements += 1
            if components == 1 and loops >= 8:
                sc_loops8 += 1
            key = (source, start - offset)
            rank = (loops, len(window), -components)
            if key not in best or rank > best[key][0]:
                best[key] = (rank, loops, components)

    return {
        "hapax_windows": len(hapax),
        "multi_start_windows": multi_start,
        "sources": len({s for s, _ in best}),
        "placements": placements,
        "single_component_loops8": sc_loops8,
        "diagonals": len(best),
        "diagonals_loops8": len([v for v in best.values() if v[1] >= 8]),
        "diagonals_loops16": len([v for v in best.values() if v[1] >= 16]),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", type=Path, default=Path("Fixtures/u534_corpus.json"))
    ap.add_argument("--check", action="store_true",
                    help="exit non-zero if any re-measured figure has drifted")
    args = ap.parse_args()

    got = measure(args.corpus)
    print(f"corpus                : {args.corpus}")
    print(f"window lengths        : {MIN_LEN}-{MAX_LEN}")
    print(f"hapax windows         : {got['hapax_windows']}")
    print(f"multi-start windows   : {got['multi_start_windows']}  "
          f"(must be 0 for the diagonal key to be unambiguous)")
    print(f"contributing sources  : {got['sources']}")
    print()
    print(f"{'figure':<28}{'re-measured':>13}{'archived 54.2':>15}  status")
    drift = []
    for key in EXPECTED:
        mine, arch = got[key], ARCHIVED[key]
        if mine != EXPECTED[key]:
            status = f"DRIFT (expected {EXPECTED[key]})"
            drift.append(key)
        elif mine == arch:
            status = "exact"
        else:
            status = f"unreconciled ({(mine - arch) / arch:+.0%} vs archived)"
        print(f"{key:<28}{mine:>13}{arch:>15}  {status}")

    print()
    if got["diagonals"]:
        print(f"raw-surface reduction : {got['placements'] / got['diagonals']:.1f}x "
              f"(archived headline said 130x)")
    print()
    print("Reproduce end-to-end through the committed tools:")
    print("  python3 Scripts/relay_crib_mine.py Fixtures/u534_corpus.json \\")
    print("      --emit /tmp/hapax_all.json --top 10000000 --per-family 10000000")
    print("  python3 Scripts/menu_diagonal_collapse.py /tmp/hapax_all.json \\")
    print("      --use-provenance --quiet")

    if args.check and drift:
        print(f"\nFAIL: {len(drift)} figure(s) drifted: {', '.join(drift)}", file=sys.stderr)
        return 1
    if got["multi_start_windows"] != 0:
        print("\nFAIL: a window occurs at multiple starts in its carrier; the diagonal key "
              "is no longer unambiguous and the collapse needs revisiting.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
