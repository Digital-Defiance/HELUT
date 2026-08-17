#!/usr/bin/env python3
"""Mine the cribs `crib_mine.py` structurally cannot emit: one-off relayed content.

Phase 13 of the campaign ledger names the binding constraint — every crib driving every
arm is register mined from *other nets'* traffic, because no broken M-Thetis message exists
in the corpus. But there is a second, narrower gap hiding inside the miner itself.

`crib_mine.py` gates its emitted pool on `--emit-min-messages` (default **2**): a phrase
must appear in at least two distinct decrypts to become a menu. That is the right filter
for *formulaic register* and the wrong one for a **one-off order relayed onto a training
net** — which is precisely the shape of a general signal on 1 May 1945, the day Donitz
announced his succession and the fleet was told to scuttle. Verbatim content broadcast once
and repeated onto Thetis appears in exactly one decrypt, so it is excluded by construction
and has never been on the board.

This enumerates that excluded surface and emits a curated, loop-ranked fixture from it.
The bombe does not care *why* a crib is believed to be present; it cares that the crib is
long enough to beat unicity and legal under self-encipherment. Every placement here is a
clean, falsifiable Boolean test.

    python3 Scripts/relay_crib_mine.py Fixtures/u534_corpus.json
    python3 Scripts/relay_crib_mine.py Fixtures/u534_corpus.json \
        --emit Fixtures/p1030680_relay_menus.json --top 24 --per-family 2
"""
from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path

TARGET = "P1030680"


def legal_offsets(crib: str, ciphertext: str) -> list[int]:
    """Placements where no letter enciphers to itself — Enigma's one absolute law."""
    return [offset for offset in range(len(ciphertext) - len(crib) + 1)
            if all(crib[i] != ciphertext[offset + i] for i in range(len(crib)))]


def menu_shape(crib: str, offset: int, ciphertext: str) -> tuple[int, int] | None:
    """(loops, vertices) — the cyclomatic number is what makes a menu bite."""
    edges: list[tuple[str, str]] = []
    present: set[str] = set()
    for index, plain in enumerate(crib):
        cipher = ciphertext[offset + index]
        if plain == cipher:
            return None
        edges.append((plain, cipher))
        present.add(plain)
        present.add(cipher)
    parent = {letter: letter for letter in present}

    def find(x: str) -> str:
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for a, b in edges:
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb
    roots = {find(letter) for letter in present}
    return len(edges) - len(present) + len(roots), len(present)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("corpus", type=Path)
    parser.add_argument("--min-len", type=int, default=16,
                        help="unicity floor; 16 is where a menu isolates a true key")
    parser.add_argument("--max-len", type=int, default=40,
                        help="Metal edge cap in BombeMetal.swift")
    parser.add_argument("--catalog", type=Path,
                        default=Path("Fixtures/p1030680_menus.json"),
                        help="existing menu set, so only genuinely new cribs are counted")
    parser.add_argument("--emit", type=Path)
    parser.add_argument("--top", type=int, default=24)
    parser.add_argument("--per-family", type=int, default=2,
                        help="cap alignments per source message, for hypothesis diversity")
    args = parser.parse_args()

    data = json.loads(args.corpus.read_text(encoding="utf-8"))
    messages = data["messages"]
    target = next(r for r in messages if r["id"] == TARGET)
    ciphertext = target["ciphertext"]
    decrypts = [(r["id"], r["plaintext"]) for r in messages
                if r.get("plaintext") and r["id"] != TARGET]

    # Which windows does each decrypt carry?
    carriers: dict[str, set[str]] = defaultdict(set)
    for message_id, text in decrypts:
        for length in range(args.min_len, args.max_len + 1):
            for start in range(len(text) - length + 1):
                carriers[text[start:start + length]].add(message_id)

    unique = {w: ids for w, ids in carriers.items() if len(ids) == 1}
    shared = {w: ids for w, ids in carriers.items() if len(ids) >= 2}

    # Exclude anything the existing catalog already tests.
    already: set[str] = set()
    if args.catalog.exists():
        already = {c["text"] for c in json.loads(args.catalog.read_text())["cribs"]}

    print(f"corpus            : {len(decrypts)} decrypts, target {TARGET} "
          f"({len(ciphertext)} letters)")
    print(f"window lengths    : {args.min_len}-{args.max_len}")
    print(f"distinct windows  : {len(carriers)}")
    print(f"  carried by >=2  : {len(shared)}  <- what crib_mine.py can emit")
    print(f"  carried by 1    : {len(unique)}  <- structurally excluded, never on the board")
    print()

    rows = []
    for window, ids in unique.items():
        if window in already:
            continue
        offsets = legal_offsets(window, ciphertext)
        if not offsets:
            continue
        for offset in offsets:
            shape = menu_shape(window, offset, ciphertext)
            if shape is None:
                continue
            loops, vertices = shape
            rows.append((loops, len(window), vertices, window, offset,
                         next(iter(ids))))

    rows.sort(key=lambda r: (-r[0], -r[1], -r[2]))
    families = {r[5] for r in rows}
    print(f"NEW legal placements from one-off content : {len(rows)}")
    print(f"  distinct windows                        : "
          f"{len({r[3] for r in rows})}")
    print(f"  source messages contributing            : {len(families)}")
    print(f"  best loop count                         : {rows[0][0] if rows else 0}")
    print()
    print("This is unexplored surface: legal, above unicity, and never tested. It is a")
    print("relay hypothesis, not a register one — so it is falsifiable exactly like every")
    print("other arm, and it does not require Thetis to speak Potsdam.")
    print()

    if not rows:
        return 0

    print(f"{'loops':>5} {'len':>4} {'src':>10}  placement")
    seen: dict[str, int] = {}
    chosen = []
    for loops, length, _, window, offset, source in rows:
        if seen.get(source, 0) >= args.per_family:
            continue
        seen[source] = seen.get(source, 0) + 1
        chosen.append((loops, length, window, offset, source))
        print(f"{loops:>5} {length:>4} {source:>10}  {window}@{offset}")
        if len(chosen) >= args.top:
            break

    if args.emit:
        by_text: dict[str, list[int]] = defaultdict(list)
        for _, _, window, offset, _ in chosen:
            by_text[window].append(offset)
        args.emit.write_text(json.dumps({
            "target": TARGET,
            "ciphertext": ciphertext,
            "note": "Relay hypothesis. Windows carried by exactly ONE broken U-534 decrypt, "
                    "which crib_mine.py excludes by construction via --emit-min-messages>=2. "
                    "A one-off order relayed onto a training net is verbatim content, not "
                    "stock register, so the recurrence filter is the wrong gate for it. "
                    "Loop-ranked, capped per source message for hypothesis diversity. "
                    "Emitted by Scripts/relay_crib_mine.py.",
            "cribs": [{"text": t, "messages": 1, "offsets": sorted(o)}
                      for t, o in by_text.items()],
        }, indent=2) + "\n", encoding="utf-8")
        print()
        print(f"wrote {args.emit}: {len(by_text)} cribs, {len(chosen)} placements")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
