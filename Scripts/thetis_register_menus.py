#!/usr/bin/env python3
"""Build a Thetis-register crib fixture — not Potsdam, not more UEBUNG pads.

Potsdam openings and the UEBUNG-push hypothesis are exhausted under right-ring
coverage for the cribs tried. This fixture targets training-net register:
Kenngruppe drill (ACH / SEDM / OEDM from this message's own keying material),
school/training address language, and Thetis-shaped openings — still length≥16
and self-stecker legal, head offsets only.

The scraped corpus "plaintext" for P1030680 is Girard's Buchgruppen form
annotation (KACH OEDM / EACH SEDM), not message plaintext — those strings are
excluded here.

Usage:
  python3 Scripts/thetis_register_menus.py \\
      --emit Fixtures/p1030680_thetis_register_menus.json
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

TARGET = "P1030680"
MIN_LEN = 16
MAX_LEN = 40
HEAD_OFFSETS = (0, 1, 2, 3, 4, 5)

# Training / Kenngruppe register — no FLOTTX, TRAVEMUE, KOMXADMX, UUUFLOTT.
SEEDS = (
    # Kenngruppe drill from this message's own Schlüssel / Verfahren material
    "ACHACHACHACHACHA",
    "ACHACHACHACHACHACH",
    "SEDMSSEDMSSEDMSSE",
    "OEDMOEDMOEDMOEDM",
    "ACHSEDMOEDMACHSE",
    "SEDMOEDMACHSEDMO",
    "EACHSEDMEACHSEDM",
    "KACHOEDMKACHOEDM",
    "XXXXACHXXXXACHXX",
    "XXXSEDMXXXSEDMXX",
    # Training-net openings / address
    "AUSBILDUNGXFUNKX",
    "AUSBILDUNGSFUNKSPRUCH",
    "AUSBILDUNGXXXXXX",
    "LEHRGANGFUNKSPRUCH",
    "FUNKSPRUCHUEBUNG",
    "UEBUNGSSPRUCHXXXX",
    "LEHRSPRUCHXXXXXX",
    "FUNKLEHRGANGXXXX",
    "SCHULFUNKSPRUCHX",
    "PRAKTIKUMFUNKXXX",
    "ANALLEFUNKSTELLEN",
    "ANALLEXXANALLEXX",
    "VONFUNKLEHRGANGX",
    "ANFUNKLEHRGANGXX",
    "THETISFUNKSPRUCHX",
    "THETISXTHETISXTH",
    "THETISXTHETISXTHETIS",
    "GRUPPENZAHLXXXXXX",
    "ZEITGRUPPEXXXXXX",
    "VERFAHRENKENNGRUPPE",
    "SCHLUESSELKENNGRUPPE",
)


def viable(crib: str, ciphertext: str, allowed: tuple[int, ...]) -> list[int]:
    hits: list[int] = []
    for offset in allowed:
        if offset + len(crib) > len(ciphertext):
            continue
        if all(crib[i] != ciphertext[offset + i] for i in range(len(crib))):
            hits.append(offset)
    return hits


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--menus", type=Path, default=Path("Fixtures/p1030680_menus.json"))
    parser.add_argument(
        "--emit", type=Path, default=Path("Fixtures/p1030680_thetis_register_menus.json")
    )
    args = parser.parse_args()

    source = json.loads(args.menus.read_text(encoding="utf-8"))
    ciphertext = source["ciphertext"].upper()
    assert source.get("target") == TARGET

    cribs: list[dict] = []
    placements = 0
    for text in SEEDS:
        if not (MIN_LEN <= len(text) <= MAX_LEN):
            print(f"  drop {text} — length {len(text)}")
            continue
        if not text.isalpha() or text != text.upper():
            raise SystemExit(f"bad crib: {text!r}")
        offsets = viable(text, ciphertext, HEAD_OFFSETS)
        if not offsets:
            print(f"  drop {text} — illegal at offsets {HEAD_OFFSETS}")
            continue
        cribs.append(
            {
                "text": text,
                "messages": 0,
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
            "Thetis-register hypothesis: Kenngruppe drill (ACH/SEDM/OEDM) and "
            "training-net openings at offsets 0–5, length≥16. Not Potsdam corpus "
            "cribs; not Girard Buchgruppen form annotation. "
            "Run with --bombe-min-crib 16 --bombe-confirm 1."
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
