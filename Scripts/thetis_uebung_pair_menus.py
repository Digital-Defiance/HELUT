#!/usr/bin/env python3
"""Build a paired Thetis UEBUNG-header + mid-message body fixture.

Arm 1 showed ≥16 training pads at offsets 0–2 are dead under rings AAAA.
The original hunch is a *short* UEBUNG head pushing operational language to
offsets ~10–20. Short menus are below unicity alone — this fixture is meant
for `--bombe-confirm 2` with the solo-break gate (cribs <16 cannot announce
BREAK without an independent partner).

Usage:
  python3 Scripts/thetis_uebung_pair_menus.py \\
      --emit Fixtures/p1030680_uebung_pair_menus.json
"""
from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path

TARGET = "P1030680"
HEAD_OFFSETS = (0, 1, 2)
BODY_OFFSETS = range(10, 21)
BODY_MIN_LEN = 16
BODY_MAX_LEN = 40
BODY_CAP = 40

# Short / medium training pads — intentionally under the solo-break floor.
SHORT_HEADERS = (
    "UEBUNG",
    "UEBUNGX",
    "XUEBUNG",
    "UEBUNGUEBUNG",
    "UEBUNGXUEBUNG",
    "XUEBUNGXUEBUNG",
    "FUNKUEBUNG",
    "FUNKXUEBUNG",
    "UEBUNGSFUNK",
    "UEBUNGXFUNK",
    "XXXUEBUNG",
    "UEBUNGXXX",
    "XXUEBUNG",
    "UEBUNGXX",
    "UEBUNGSMELDUNG",  # 14 — under 16 on purpose
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


def emit_cribs(placements: list[dict]) -> list[dict]:
    by_text: dict[str, list[int]] = defaultdict(list)
    for m in placements:
        by_text[m["text"]].append(m["offset"])
    ordered = []
    for text, offsets in sorted(by_text.items(), key=lambda kv: (-len(kv[0]), kv[0])):
        ordered.append(
            {
                "text": text,
                "messages": 0,
                "offsets": sorted(set(offsets)),
                "anchored": 0 in offsets,
            }
        )
    return ordered


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--menus", type=Path, default=Path("Fixtures/p1030680_menus.json"))
    parser.add_argument(
        "--emit", type=Path, default=Path("Fixtures/p1030680_uebung_pair_menus.json")
    )
    parser.add_argument("--body-cap", type=int, default=BODY_CAP)
    args = parser.parse_args()

    source = json.loads(args.menus.read_text(encoding="utf-8"))
    ciphertext = source["ciphertext"].upper()
    assert source.get("target") == TARGET

    headers: list[dict] = []
    for text in SHORT_HEADERS:
        assert text.isalpha() and text == text.upper()
        for offset in HEAD_OFFSETS:
            menu = build_menu(text, offset, ciphertext)
            if menu:
                headers.append(menu)
                print(f"  head {text}@{offset} len={len(text)} loops={menu['loops']}")

    bodies: list[dict] = []
    seen: set[tuple[str, int]] = set()
    for crib in source["cribs"]:
        text = crib["text"].upper()
        if not (BODY_MIN_LEN <= len(text) <= BODY_MAX_LEN):
            continue
        for offset in BODY_OFFSETS:
            key = (text, offset)
            if key in seen:
                continue
            menu = build_menu(text, offset, ciphertext)
            if not menu:
                continue
            seen.add(key)
            bodies.append(menu)

    bodies.sort(key=lambda m: (-m["loops"], -m["edges"], -len(m["text"]), m["offset"]))
    chosen_bodies = bodies[: args.body_cap]
    print(f"\n  body partners: {len(chosen_bodies)} of {len(bodies)} legal mid-message")

    placements = headers + chosen_bodies
    payload = {
        "target": TARGET,
        "ciphertext": ciphertext,
        "note": (
            "Thetis Übung pair fixture: short UEBUNG-family headers at offsets 0–2 "
            f"plus top-{args.body_cap} ≥16 catalog cribs at offsets 10–20. "
            "Run with --bombe-confirm 2 --bombe-min-crib 6. Solo BREAK requires "
            "length ≥16; short headers need independent shell agreement."
        ),
        "cribs": emit_cribs(placements),
        "placements": [
            {
                "text": m["text"],
                "offset": m["offset"],
                "edges": m["edges"],
                "loops": m["loops"],
                "role": "head" if m["offset"] in HEAD_OFFSETS else "body",
            }
            for m in placements
        ],
    }
    args.emit.parent.mkdir(parents=True, exist_ok=True)
    args.emit.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(
        f"\nwrote {args.emit}: {len(headers)} head + {len(chosen_bodies)} body "
        f"= {len(placements)} placements"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
