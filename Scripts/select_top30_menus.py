#!/usr/bin/env python3
"""Curate the top-30 Welchman menus for a targeted right-ring (turnover) sweep.

rings-AAAA already covered every legal placement for turnover-free spans. What
remains is the ~81% of keys where a middle-rotor turnover falls inside the crib.
Sweeping all 2,513 placements at 26× cost is ~8 days; this picks the thirty
highest-probability placements so a ring sweep finishes in hours.

Ranking (strict):
  1. length >= 16 (hard filter)
  2. offset == 0 heavily preferred (openings first)
  3. then highest loops, then highest edges
     — same topology measure the Swift loader uses:
       loops = edges − vertices + components

Usage:
  python3 Scripts/select_top30_menus.py \\
      Fixtures/p1030680_menus.json \\
      --emit Fixtures/p1030680_top30_menus.json
"""
from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path


def build_menu(crib: str, offset: int, ciphertext: str) -> dict | None:
    """Mirror HELUTCore.BombeMenuBuilder.menu — nil on self-encipherment."""
    if offset < 0 or offset + len(crib) > len(ciphertext):
        return None
    ends: list[tuple[int, int]] = []
    present = [False] * 26
    for i, ch in enumerate(crib):
        plain = ord(ch) - 65
        cipher = ord(ciphertext[offset + i]) - 65
        if plain == cipher:
            return None
        ends.append((plain, cipher))
        present[plain] = True
        present[cipher] = True

    parent = list(range(26))

    def find(x: int) -> int:
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for a, b in ends:
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb

    vertices = [i for i in range(26) if present[i]]
    roots = {find(v) for v in vertices}
    edges = len(ends)
    loops = edges - len(vertices) + len(roots)
    return {
        "text": crib,
        "offset": offset,
        "edges": edges,
        "letters": len(vertices),
        "loops": loops,
    }


def select_top(path: Path, n: int, min_len: int) -> tuple[list[dict], str]:
    data = json.loads(path.read_text(encoding="utf-8"))
    ciphertext = data["ciphertext"].upper()
    placements: list[dict] = []
    seen: set[tuple[str, int]] = set()
    for crib in data["cribs"]:
        text = crib["text"].upper()
        if len(text) < min_len:
            continue
        for raw_offset in crib["offsets"]:
            offset = int(raw_offset)
            if (text, offset) in seen:
                continue
            menu = build_menu(text, offset, ciphertext)
            if menu is None:
                continue
            seen.add((text, offset))
            # Openings sort ahead of everything else; within each band, topology.
            menu["rank_key"] = (
                0 if menu["offset"] == 0 else 1,
                -menu["loops"],
                -menu["edges"],
                -len(menu["text"]),
            )
            placements.append(menu)

    placements.sort(key=lambda m: m["rank_key"])
    return placements[:n], ciphertext


def emit_fixture(chosen: list[dict], ciphertext: str, source: Path, out: Path) -> None:
    """One crib entry per distinct text, carrying only the selected offsets."""
    by_text: dict[str, list[int]] = defaultdict(list)
    for menu in chosen:
        by_text[menu["text"]].append(menu["offset"])

    seen: set[str] = set()
    ordered = []
    for menu in chosen:
        text = menu["text"]
        if text in seen:
            continue
        seen.add(text)
        ordered.append({
            "text": text,
            "messages": 0,
            "offsets": sorted(by_text[text]),
            "anchored": 0 in by_text[text],
        })

    payload = {
        "target": "P1030680",
        "ciphertext": ciphertext,
        "note": (
            f"Top {len(chosen)} placements for a targeted --bombe-ring-sweep. "
            f"Filter: len>=16; openings (offset 0) first; then loops, edges. "
            f"Derived from {source.name}. Topology matches BombeMenuBuilder."
        ),
        "cribs": ordered,
        "placements": [
            {
                "text": m["text"],
                "offset": m["offset"],
                "loops": m["loops"],
                "edges": m["edges"],
                "letters": m["letters"],
                "opening": m["offset"] == 0,
            }
            for m in chosen
        ],
    }
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("menus", type=Path, nargs="?",
                        default=Path("Fixtures/p1030680_menus.json"))
    parser.add_argument("--top", type=int, default=30)
    parser.add_argument("--min-len", type=int, default=16)
    parser.add_argument("--emit", type=Path,
                        default=Path("Fixtures/p1030680_top30_menus.json"))
    args = parser.parse_args()

    chosen, ciphertext = select_top(args.menus, args.top, args.min_len)
    if len(chosen) < args.top:
        print(f"warning: only {len(chosen)} placements survived the filter "
              f"(wanted {args.top})")

    emit_fixture(chosen, ciphertext, args.menus, args.emit)

    openings = sum(1 for m in chosen if m["offset"] == 0)
    print(f"wrote {args.emit}: {len(chosen)} placements "
          f"({openings} openings @0, {len(chosen) - openings} interior)")
    print(f"{'#':>3}  {'off':>3}  {'loops':>5}  {'edges':>5}  {'len':>3}  crib")
    for i, m in enumerate(chosen, 1):
        mark = "*" if m["offset"] == 0 else " "
        print(f"{i:>3}{mark} {m['offset']:>3}  {m['loops']:>5}  {m['edges']:>5}  "
              f"{len(m['text']):>3}  {m['text']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
