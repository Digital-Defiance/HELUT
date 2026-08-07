#!/usr/bin/env python3
"""Curate fuzzed menus for a targeted --bombe-ring-sweep.

Fuzzed rings-AAAA (`logs/campaign-fuzzed-aaaa.log`) is a clean negative on the
physical sieve. Almost all raw stops came from a weak XX+KOM Hamming swarm
(split menus → ghosts). This script picks a surgical set for turnover coverage:

  1. length >= 18 (and <= Metal edge cap 40)
  2. drop XX*+KOM Hamming ghost factories (and any menu that already produced
     raw stops under AAAA — same pathology)
  3. openings (offset 0) first; then loops, edges

Usage:
  python3 Scripts/select_top_fuzzed.py \\
      Fixtures/p1030680_fuzzed_menus.json \\
      --log logs/campaign-fuzzed-aaaa.log \\
      --emit Fixtures/p1030680_fuzzed_top40_menus.json
"""
from __future__ import annotations

import argparse
import json
import re
from collections import defaultdict
from pathlib import Path

METAL_EDGE_CAP = 40
STOP_LINE = re.compile(
    r"\[(\d+)/\d+·\d+\] (\S+)@(\d+) edges=(\d+) letters=(\d+) loops=(\d+)"
    r".*?(dead at the board|(\d+) stops)"
)


def build_menu(crib: str, offset: int, ciphertext: str) -> dict | None:
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


def is_ghost_factory(text: str) -> bool:
    """XX-padded KOM Hamming family produced ~200k ghost stops under AAAA."""
    t = text.upper()
    if "KOM" in t and t.startswith("XX"):
        return True
    # Near-relatives from the same swarm (single-letter slip on the KOM stem).
    if t.startswith("XX") and "ADMXUUUBOO" in t:
        return True
    return False


def load_aaaa_stoppers(log_path: Path) -> set[tuple[str, int]]:
    """Menus that already emitted raw stops under rings-AAAA (ghost factories)."""
    if not log_path.is_file():
        return set()
    stoppers: set[tuple[str, int]] = set()
    for line in log_path.read_text(encoding="utf-8", errors="replace").splitlines():
        m = STOP_LINE.search(line)
        if not m:
            continue
        if m.group(7) == "dead at the board":
            continue
        stoppers.add((m.group(2).upper(), int(m.group(3))))
    return stoppers


def select(
    fuzzed: dict,
    stoppers: set[tuple[str, int]],
    top: int,
    min_len: int,
) -> list[dict]:
    ciphertext = fuzzed["ciphertext"].upper()
    placements: list[dict] = []
    seen: set[tuple[str, int]] = set()

    # Prefer the ranked placements[] block when present; else expand cribs[].
    raw = fuzzed.get("placements") or []
    if not raw:
        for crib in fuzzed.get("cribs", []):
            text = crib["text"].upper()
            for offset in crib.get("offsets", []):
                raw.append({"text": text, "offset": int(offset)})

    for item in raw:
        text = str(item["text"]).upper()
        offset = int(item["offset"])
        if (text, offset) in seen:
            continue
        if len(text) < min_len or len(text) > METAL_EDGE_CAP:
            continue
        if is_ghost_factory(text):
            continue
        if (text, offset) in stoppers:
            continue
        menu = build_menu(text, offset, ciphertext)
        if menu is None:
            continue
        if menu["edges"] > METAL_EDGE_CAP:
            continue
        seen.add((text, offset))
        menu["rank_key"] = (
            0 if offset == 0 else 1,
            -menu["loops"],
            -menu["edges"],
            -len(text),
        )
        placements.append(menu)

    placements.sort(key=lambda m: m["rank_key"])
    if top <= 0:
        return placements
    # Stratify so interiors (turnover-relevant body sites) survive the opening bias.
    openings = [m for m in placements if m["offset"] == 0]
    interior = [m for m in placements if m["offset"] != 0]
    open_budget = min(len(openings), max(top // 2, top - len(interior)))
    chosen = openings[:open_budget] + interior[: top - open_budget]
    chosen.sort(key=lambda m: m["rank_key"])
    return chosen


def emit_fixture(chosen: list[dict], ciphertext: str, source: Path, out: Path) -> None:
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
            "fuzzed": True,
        })

    payload = {
        "target": "P1030680",
        "ciphertext": ciphertext,
        "note": (
            f"Top {len(chosen)} fuzzed placements for --bombe-ring-sweep. "
            f"Filter: len>=18; edges<={METAL_EDGE_CAP}; drop XX+KOM Hamming "
            f"ghost factories and AAAA stop-producers. Openings first, then "
            f"loops/edges. Derived from {source.name}."
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
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "fuzzed",
        type=Path,
        nargs="?",
        default=Path("Fixtures/p1030680_fuzzed_menus.json"),
    )
    parser.add_argument(
        "--log",
        type=Path,
        default=Path("logs/campaign-fuzzed-aaaa.log"),
        help="AAAA campaign log used to drop menus that already produced ghosts",
    )
    parser.add_argument("--top", type=int, default=40)
    parser.add_argument("--min-len", type=int, default=18)
    parser.add_argument(
        "--emit",
        type=Path,
        default=Path("Fixtures/p1030680_fuzzed_top40_menus.json"),
    )
    args = parser.parse_args()

    fuzzed = json.loads(args.fuzzed.read_text(encoding="utf-8"))
    ciphertext = fuzzed["ciphertext"].upper()
    stoppers = load_aaaa_stoppers(args.log)
    chosen = select(fuzzed, stoppers, args.top, args.min_len)
    if len(chosen) < args.top:
        print(
            f"warning: only {len(chosen)} placements survived the filter "
            f"(wanted {args.top})"
        )

    emit_fixture(chosen, ciphertext, args.fuzzed, args.emit)

    openings = sum(1 for m in chosen if m["offset"] == 0)
    print(
        f"wrote {args.emit}: {len(chosen)} placements "
        f"({openings} openings @0, {len(chosen) - openings} interior); "
        f"dropped {len(stoppers)} AAAA stop-producers from log"
    )
    print(f"{'#':>3}  {'off':>3}  {'loops':>5}  {'edges':>5}  {'len':>3}  crib")
    for i, m in enumerate(chosen, 1):
        mark = "*" if m["offset"] == 0 else " "
        print(
            f"{i:>3}{mark} {m['offset']:>3}  {m['loops']:>5}  {m['edges']:>5}  "
            f"{len(m['text']):>3}  {m['text']}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
