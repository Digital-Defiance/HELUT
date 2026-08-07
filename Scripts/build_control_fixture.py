#!/usr/bin/env python3
"""Build a known-key control fixture so the sweep itself can be graded.

The rehearsal (`--welchman-rehearsal`) hands the bombe the true shell and only
searches 26^4 window positions. It cannot tell us whether the *campaign* path —
336 wheel orders x 2 Greek x 2 UKW x 26 right rings, GPU kernel, stecker
deduction, discriminator — recovers a key it was never told.

This emits a fixture in the same shape as p1030680_menus.json but carrying
P1030684 (Potsdam, 1 May 1945), whose key is published: wheel order IV-III-VIII,
Greek gamma, UKW B, rings AACU, message key VYAA, ten known plugs. Cribs are
taken from the true plaintext at their true offsets, so a working pipeline must
break it. rings AACU also puts the middle-ring reduction under test: the sweep
only ever tries middle ring A, so it can only succeed if middle ring C really is
absorbed into the middle window position.

    python3 Scripts/build_control_fixture.py
    .build/release/helut --welchman \
        --bombe-fixture Fixtures/p1030684_control_menus.json \
        --bombe-menus 3 --bombe-ring-sweep
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

CIPHERTEXT = (
    "RFBYWKIKELDCHBSXUNFJFSNRRVFWASXYLQCQFADYJXNTBMVLRDCGULOWHTBGWUSSOQHGAY"
    "EDKMJDNGVZNZFOXFKMIBKQNXFDWFIVGCYMJVQCKYQFBHYKZSCJ"
)
PLAINTEXT = (
    "VVVUUUVIRSOBENNULEINSXXMITUUUVIRSIBENNULZWOYVIRSIBENNULDREIYZWODREISEC"
    "HSEINSYZWODREIDREIACHTEINSDREIOITNACHWZSTENPASSIRT"
)

# Matches BombeSweepConfig.minCribLength and welchmanMaxEdges.
MIN_LEN = 18
MAX_LEN = 40


def build_menu(crib: str, offset: int, ciphertext: str) -> dict | None:
    """Mirror HELUTCore.BombeMenuBuilder.menu — None on self-encipherment."""
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
    return {"text": crib, "offset": offset, "edges": edges, "loops": loops}


def candidates(min_len: int, max_len: int) -> list[dict]:
    found: list[dict] = []
    for offset in range(len(PLAINTEXT)):
        for length in range(min_len, max_len + 1):
            if offset + length > len(PLAINTEXT):
                break
            crib = PLAINTEXT[offset : offset + length]
            menu = build_menu(crib, offset, CIPHERTEXT)
            if menu is not None:
                found.append(menu)
    # Highest deduction power first, same ordering the sweep uses.
    found.sort(key=lambda m: (m["loops"], m["edges"], len(m["text"])), reverse=True)
    return found


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--emit", default="Fixtures/p1030684_control_menus.json")
    parser.add_argument("--count", type=int, default=3)
    parser.add_argument("--min-len", type=int, default=MIN_LEN)
    parser.add_argument("--max-len", type=int, default=MAX_LEN)
    parser.add_argument(
        "--offset-zero",
        action="store_true",
        help="only emit offset-0 openings (the realistic attack case)",
    )
    args = parser.parse_args()

    pool = candidates(args.min_len, args.max_len)
    if args.offset_zero:
        pool = [m for m in pool if m["offset"] == 0]

    chosen: list[dict] = []
    seen_offsets: set[int] = set()
    for menu in pool:
        if menu["offset"] in seen_offsets:
            continue
        chosen.append(menu)
        seen_offsets.add(menu["offset"])
        if len(chosen) >= args.count:
            break

    payload = {
        "target": "P1030684 (known key control — IV-III-VIII gamma B, rings AACU, key VYAA)",
        "ciphertext": CIPHERTEXT,
        "cribs": [
            {"text": m["text"], "messages": 1, "offsets": [m["offset"]]} for m in chosen
        ],
    }
    out = Path(args.emit)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(payload, indent=2) + "\n")

    print(f"wrote {out} — {len(chosen)} control menus from {len(pool)} legal placements")
    for m in chosen:
        print(
            f"  @{m['offset']:>3} len {len(m['text']):>2} "
            f"edges {m['edges']:>2} loops {m['loops']:>2}  {m['text']}"
        )


if __name__ == "__main__":
    main()
