#!/usr/bin/env python3
"""Build bounded multi-anchor Bombe fixtures without inventing plaintext between anchors.

Each --anchor string is an independent historical claim. The generator enumerates absolute
placements, rejects self-encipherment and overlap, unions the resulting board constraints, and
ranks the *joint* graph. It never concatenates the strings or asserts anything about the text
between them.

Example (Selm/Wenselaers Phase 55):

  python3 Scripts/constellation_crib_generator.py \
    --anchor BLEIBTBESETZT --anchor NEUSTADT --top 24 \
    --emit Fixtures/p1030680_wenselaers_constellations.json

The output schema is consumed by BombeSweep.swift. It contains plaintext+offsets only; ciphertext
endpoints, steps, loops, components, and the test register are always rebuilt by the Swift loader.
"""
from __future__ import annotations

import argparse
import itertools
import json
from collections import defaultdict
from pathlib import Path

TARGET = "P1030680"
ALPHABET = set("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
MAX_EDGES = 40


def legal_offsets(text: str, ciphertext: str) -> list[int]:
    return [
        offset
        for offset in range(len(ciphertext) - len(text) + 1)
        if all(text[i] != ciphertext[offset + i] for i in range(len(text)))
    ]


def topology(anchors: tuple[tuple[str, int], ...], ciphertext: str) -> dict:
    constraints: list[tuple[int, int, int]] = []
    ranges: list[range] = []
    for text, offset in anchors:
        current = range(offset, offset + len(text))
        if any(set(current).intersection(prior) for prior in ranges):
            raise ValueError("overlapping anchors")
        ranges.append(current)
        for local, plain_ch in enumerate(text):
            step = offset + local
            plain, cipher = ord(plain_ch) - 65, ord(ciphertext[step]) - 65
            if plain == cipher:
                raise ValueError("self-encipherment")
            constraints.append((step, plain, cipher))
    constraints.sort()
    if len(constraints) > MAX_EDGES:
        raise ValueError("Metal edge cap")

    parent = list(range(26))
    present: set[int] = set()

    def find(x: int) -> int:
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for _, a, b in constraints:
        present.update((a, b))
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb
    components = len({find(x) for x in present})
    loops = len(constraints) - len(present) + components
    return {
        "edges": len(constraints),
        "letters": len(present),
        "components": components,
        "loops": loops,
        "stepHorizon": max(step for step, _, _ in constraints) + 1,
    }


def select_diverse(rows: list[dict], top: int, per_anchor_offset: int) -> list[dict]:
    """Greedy topology rank with a cap on every anchor's absolute offset."""
    usage: list[dict[int, int]] = []
    if rows:
        usage = [defaultdict(int) for _ in rows[0]["offsets"]]
    chosen: list[dict] = []
    for row in sorted(rows, key=rank_key):
        if any(
            usage[index][offset] >= per_anchor_offset
            for index, offset in enumerate(row["offsets"])
        ):
            continue
        chosen.append(row)
        for index, offset in enumerate(row["offsets"]):
            usage[index][offset] += 1
        if len(chosen) >= top:
            break
    return sorted(chosen, key=rank_key)


def rank_key(row: dict) -> tuple:
    shape = row["shape"]
    return (
        shape["components"] != 1,
        -shape["loops"],
        -shape["edges"],
        shape["stepHorizon"],
        tuple(row["offsets"]),
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--corpus", type=Path, default=Path("Fixtures/u534_corpus.json"))
    parser.add_argument("--anchor", action="append", required=True)
    parser.add_argument("--top", type=int, default=24)
    parser.add_argument("--per-anchor-offset", type=int, default=2,
                        help="maximum selected rows using the same offset for any one anchor")
    parser.add_argument("--allow-split", action="store_true")
    parser.add_argument("--emit", type=Path, required=True)
    parser.add_argument("--id-prefix", default="constellation")
    parser.add_argument("--note", default="Independent historical anchors; no intervening plaintext asserted.")
    args = parser.parse_args()

    anchors = [text.upper() for text in args.anchor]
    if len(anchors) < 2:
        parser.error("at least two --anchor values are required")
    for text in anchors:
        if not text or any(ch not in ALPHABET for ch in text):
            parser.error(f"anchor must be strict nonempty A-Z: {text!r}")
    if sum(map(len, anchors)) > MAX_EDGES:
        parser.error(f"anchor constraints exceed Metal cap {MAX_EDGES}")
    if args.top <= 0:
        parser.error("--top must be positive")
    if args.per_anchor_offset <= 0:
        parser.error("--per-anchor-offset must be positive")

    corpus = json.loads(args.corpus.read_text())
    target = next(message for message in corpus["messages"] if message["id"] == TARGET)
    ciphertext = target["ciphertext"]
    offset_lists = [legal_offsets(text, ciphertext) for text in anchors]

    rows: list[dict] = []
    rejected_overlap = 0
    for offsets in itertools.product(*offset_lists):
        placed = tuple(zip(anchors, offsets))
        try:
            shape = topology(placed, ciphertext)
        except ValueError as error:
            if str(error) == "overlapping anchors":
                rejected_overlap += 1
                continue
            raise
        if not args.allow_split and shape["components"] != 1:
            continue
        rows.append({"offsets": list(offsets), "shape": shape})
    rows.sort(key=rank_key)
    chosen = select_diverse(
        rows, min(args.top, len(rows)), args.per_anchor_offset
    )

    print(f"target             : {TARGET} ({len(ciphertext)} letters)")
    for index, (text, offsets) in enumerate(zip(anchors, offset_lists)):
        print(f"anchor {index:<2}          : {text} ({len(text)} letters, {len(offsets)} legal placements)")
    print(f"cartesian product  : {__import__('math').prod(map(len, offset_lists))}")
    print(f"overlap rejected   : {rejected_overlap}")
    print(f"eligible joint rows: {len(rows)}" + (" (split allowed)" if args.allow_split else " (single-component only)"))
    print(f"offset cap         : {args.per_anchor_offset} uses per anchor/offset")
    print(f"selected           : {len(chosen)}")
    for index, row in enumerate(chosen, 1):
        shape = row["shape"]
        pairs = " + ".join(f"{text}@{offset}" for text, offset in zip(anchors, row["offsets"]))
        print(
            f"  {index:2} loops={shape['loops']:2} edges={shape['edges']:2} "
            f"letters={shape['letters']:2} comp={shape['components']} "
            f"span={shape['stepHorizon']:2}  {pairs}"
        )

    payload = {
        "schemaVersion": 2,
        "target": TARGET,
        "ciphertext": ciphertext,
        "note": args.note,
        "cribs": [],
        "constellations": [
            {
                "id": f"{args.id_prefix}-{index:03}",
                "anchors": [
                    {"text": text, "offset": offset}
                    for text, offset in zip(anchors, row["offsets"])
                ],
                "selectionReceipt": row["shape"],
            }
            for index, row in enumerate(chosen, 1)
        ],
    }
    args.emit.parent.mkdir(parents=True, exist_ok=True)
    args.emit.write_text(json.dumps(payload, indent=2) + "\n")
    print(f"wrote              : {args.emit}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
