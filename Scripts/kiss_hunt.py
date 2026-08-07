#!/usr/bin/env python3
"""Cross-reference the U-534 corpus against P1030680 hunting for depth and a 'kiss'.

Two questions:

1. Depth — do any messages share a daily key, and is any of them plausibly the
   same net as P1030680? Depth is worth more than any amount of compute.

2. Kiss — was the same plaintext re-sent on another net? Girard's history says the
   operator tried Potsdam settings, got gibberish, then re-sent on M-Thetis. If a
   readable Potsdam decrypt is the same text, we have a full-length crib.

The kiss filter is Enigma's self-encipherment constraint: no letter ever encrypts
to itself, so a candidate plaintext laid over the target ciphertext must never
agree at any position. A random 72-letter overlay survives with probability
(25/26)^72 ~= 6%, so survivors are leads, not proof.

Usage:
    Scripts/kiss_hunt.py Fixtures/u534_corpus.json
"""
from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path
from typing import Optional

TARGET = "P1030680"


def key_signature(record: dict) -> Optional[str]:
    fields = ("reflector", "greek", "wheels", "rings", "plugs")
    if not all(field in record for field in fields):
        return None
    return " | ".join(f"{field}={record[field]}" for field in fields)


def viable_offsets(crib: str, ciphertext: str) -> list[int]:
    """Offsets where no letter would encrypt to itself."""
    if not crib or len(ciphertext) < len(crib):
        return []
    hits = []
    for offset in range(len(ciphertext) - len(crib) + 1):
        if all(crib[i] != ciphertext[offset + i] for i in range(len(crib))):
            hits.append(offset)
    return hits


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("corpus", type=Path)
    parser.add_argument("--min-crib", type=int, default=40,
                        help="shortest plaintext span to test as a kiss crib")
    args = parser.parse_args()

    data = json.loads(args.corpus.read_text(encoding="utf-8"))
    messages = data["messages"]
    by_id = {record["id"]: record for record in messages}

    target = by_id.get(TARGET)
    if target is None or "ciphertext" not in target:
        print(f"{TARGET} not found in corpus", file=sys.stderr)
        return 1
    target_ct = target["ciphertext"]

    print(f"=== Target {TARGET} ===")
    print(f"length     : {len(target_ct)}")
    print(f"indicators : {' '.join(target.get('indicators', []) or ['?'])}")
    print(f"broken     : {target.get('broken')}")
    print()

    # ---- 1. Depth: group by recovered daily key -------------------------------
    groups: dict[str, list[str]] = defaultdict(list)
    unbroken = []
    for record in messages:
        signature = key_signature(record)
        if signature is None:
            unbroken.append(record["id"])
        else:
            groups[signature].append(record["id"])

    print(f"=== Daily keys across {len(messages)} messages ===")
    for signature, ids in sorted(groups.items(), key=lambda kv: -len(kv[1])):
        total = sum(by_id[i].get("length", 0) for i in ids)
        print(f"\n{len(ids)} messages, {total} letters of depth")
        print(f"  {signature}")
        print(f"  {', '.join(sorted(ids))}")
    if unbroken:
        print(f"\nNo recovered key ({len(unbroken)}): {', '.join(sorted(unbroken))}")
    print()

    # ---- 2. Same-length neighbours -------------------------------------------
    print(f"=== Messages within +/-4 letters of {TARGET} ({len(target_ct)}) ===")
    for record in sorted(messages, key=lambda r: abs(r.get("length", 0) - len(target_ct))):
        if record["id"] == TARGET or "length" not in record:
            continue
        delta = record["length"] - len(target_ct)
        if abs(delta) > 4:
            continue
        print(f"  {record['id']}  len={record['length']:>4} ({delta:+d})  "
              f"{'broken' if record.get('broken') else 'UNBROKEN'}  "
              f"ind={' '.join(record.get('indicators', []) or ['?'])}")
    print()

    # ---- 3. Kiss test ---------------------------------------------------------
    print(f"=== Kiss test: known plaintexts vs {TARGET} ciphertext ===")
    print("(survivor = no self-encipherment collision at that offset)\n")
    leads = []
    trials = 0
    expected = 0.0
    for record in messages:
        plaintext = record.get("plaintext")
        if not plaintext or record["id"] == TARGET:
            continue
        # Full text, then the leading span trimmed to the target length. For a
        # plaintext already short enough these are the same crib.
        candidates = {plaintext: "full"}
        candidates.setdefault(plaintext[:len(target_ct)], "head")
        for crib, label in candidates.items():
            if len(crib) < args.min_crib or len(crib) > len(target_ct):
                continue
            placements = len(target_ct) - len(crib) + 1
            trials += placements
            expected += placements * (25 / 26) ** len(crib)
            offsets = viable_offsets(crib, target_ct)
            if offsets:
                leads.append((record["id"], label, len(crib), offsets))

    survivors = sum(len(offsets) for _, _, _, offsets in leads)
    print(f"  {trials} overlays tested; {survivors} survived, "
          f"{expected:.1f} expected by chance\n")

    if not leads:
        print("  no plaintext survives the self-encipherment overlay — no kiss found")
    else:
        for message_id, label, length, offsets in sorted(leads, key=lambda x: -x[2]):
            shown = ", ".join(str(o) for o in offsets[:8])
            more = "" if len(offsets) <= 8 else f" (+{len(offsets) - 8} more)"
            print(f"  {message_id} [{label}] {length} letters survives at offset(s): {shown}{more}")
        print("\n  Leads only. Confirm by running a bombe with the survivor as a full crib.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
