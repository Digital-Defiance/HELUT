#!/usr/bin/env python3
"""Build a Thetis-specific UEBUNG header menu fixture for P1030680.

Potsdam openings may be the wrong register for an M-Thetis training message.
Training traffic was padded with UEBUNG (Enigma has no umlaut). This script
emits only length≥16 legal placements at offsets 0–2 so the Welchman board can
test the hunch without reopening the short-crib ghost factory.

Usage:
  python3 Scripts/thetis_uebung_menus.py \\
      --emit Fixtures/p1030680_uebung_menus.json
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

TARGET = "P1030680"
MIN_LEN = 16
MAX_LEN = 40
# Absolute head only — the hypothesis is a training pad before the body.
HEAD_OFFSETS = (0, 1, 2)

# Historically plausible training pads / repeats. Length≥16 after expansion;
# self-stecker filters illegal sites at emit time.
SEEDS = (
    "UEBUNGUEBUNGUEBUNG",
    "UEBUNGXUEBUNGXUEBUNG",
    "UEBUNGXUEBUNGUEBUNG",
    "UEBUNGUEBUNGXUEBUNG",
    "XUEBUNGXUEBUNGUEBUNG",
    "XUEBUNGXUEBUNGXUEBUNG",
    "FUNKUEBUNGFUNKUEBUNG",
    "FUNKUEBUNGXFUNKUEBUNG",
    "FUNKUEBUNGXUEBUNG",
    "FUNKXUEBUNGXUEBUNG",
    "UEBUNGSFUNKUEBUNGSFUNK",
    "UEBUNGSFUNKXUEBUNG",
    "UEBUNGSMELDUNGXX",
    "UEBUNGSMELDUNGXXX",
    "UEBUNGSMELDUNGXXXX",
    "UEBUNGSMELDUNGXUEBUNG",
    "UEBUNGSMELDUNGUEBUNGSMELDUNG",
    "XXUEBUNGSMELDUNG",
    "XXXUEBUNGSMELDUNG",
    "XXXXUEBUNGSMELDUNG",
    "XXXXXUEBUNGSMELDUNG",
    "UEBUNGXXXXUEBUNG",
    "UEBUNGXXXXXUEBUNG",
    "XUEBUNGSMELDUNGX",
    "XXXUEBUNGXUEBUNG",
    "UEBUNGXFUNKXUEBUNG",
)


def viable_offsets(crib: str, ciphertext: str, allowed: tuple[int, ...]) -> list[int]:
    hits: list[int] = []
    for offset in allowed:
        if offset + len(crib) > len(ciphertext):
            continue
        if all(crib[i] != ciphertext[offset + i] for i in range(len(crib))):
            hits.append(offset)
    return hits


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--menus",
        type=Path,
        default=Path("Fixtures/p1030680_menus.json"),
        help="source fixture (ciphertext + target id)",
    )
    parser.add_argument(
        "--emit",
        type=Path,
        default=Path("Fixtures/p1030680_uebung_menus.json"),
    )
    args = parser.parse_args()

    source = json.loads(args.menus.read_text(encoding="utf-8"))
    ciphertext = source["ciphertext"]
    assert source.get("target") == TARGET

    cribs: list[dict] = []
    placements = 0
    for text in SEEDS:
        if not (MIN_LEN <= len(text) <= MAX_LEN):
            continue
        if not text.isalpha() or text != text.upper():
            raise SystemExit(f"bad crib orthography: {text!r}")
        offsets = viable_offsets(text, ciphertext, HEAD_OFFSETS)
        if not offsets:
            print(f"  drop {text} — illegal at offsets {HEAD_OFFSETS}")
            continue
        cribs.append(
            {
                "text": text,
                "messages": 0,  # not mined from decrypts — Thetis hypothesis
                "offsets": offsets,
                "anchored": 0 in offsets,
            }
        )
        placements += len(offsets)
        print(f"  keep {text}@{offsets} len={len(text)}")

    cribs.sort(key=lambda c: (-len(c["text"]), c["text"]))
    payload = {
        "target": TARGET,
        "ciphertext": ciphertext,
        "note": (
            "Thetis training-header hypothesis: UEBUNG / FUNKUEBUNG pads at "
            "offsets 0–2, length≥16 only. Not mined from Potsdam decrypts. "
            "Illegal self-stecker placements dropped."
        ),
        "cribs": cribs,
    }
    args.emit.parent.mkdir(parents=True, exist_ok=True)
    args.emit.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(
        f"\nwrote {args.emit}: {len(cribs)} cribs, {placements} placements "
        f"(offsets {list(HEAD_OFFSETS)}, len {MIN_LEN}–{MAX_LEN})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
