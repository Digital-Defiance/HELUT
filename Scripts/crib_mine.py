#!/usr/bin/env python3
"""Mine bombe cribs for P1030680 from the 48 broken U-534 decrypts.

The archival work established that P1030680 is M-Thetis: a Baltic U-boat
*training* net. Bletchley Park never worked it, so no daily key survives and no
statistical shortcut exists at 72 letters. What does survive is register: the 48
broken messages are the same boat, the same day, the same signals office, and
training traffic is heavily formulaic.

This produces the two things a Welchman bombe menu needs:
  1. candidate cribs, ranked by how many distinct messages carry them
  2. for each crib, the offsets in P1030680 where it can legally sit
     (Enigma never encrypts a letter to itself)

Usage:
    Scripts/crib_mine.py Fixtures/u534_corpus.json
"""
from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path

TARGET = "P1030680"


def viable_offsets(crib: str, ciphertext: str) -> list[int]:
    return [offset for offset in range(len(ciphertext) - len(crib) + 1)
            if all(crib[i] != ciphertext[offset + i] for i in range(len(crib)))]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("corpus", type=Path)
    parser.add_argument("--min-len", type=int, default=6)
    parser.add_argument("--max-len", type=int, default=40)
    parser.add_argument("--min-messages", type=int, default=4)
    parser.add_argument("--top", type=int, default=25)
    parser.add_argument("--emit", type=Path,
                        help="write the crib/offset menu set as JSON for the bombe")
    # A bombe menu wants length, not popularity: 16+ letters leaves a unique stop,
    # while 8 letters leaves ~10^8. So the emitted set uses looser thresholds than
    # the display table and is ordered longest-first.
    parser.add_argument("--emit-min-len", type=int, default=12)
    parser.add_argument("--emit-min-messages", type=int, default=2)
    args = parser.parse_args()

    data = json.loads(args.corpus.read_text(encoding="utf-8"))
    messages = data["messages"]
    target = next(r for r in messages if r["id"] == TARGET)
    target_ct = target["ciphertext"]
    decrypts = [r["plaintext"] for r in messages if r.get("plaintext") and r["id"] != TARGET]

    print(f"mining {len(decrypts)} decrypts for cribs against {TARGET} "
          f"({len(target_ct)} letters)\n")

    # ---- openings -------------------------------------------------------------
    print("=== Message openings (first 12 letters) ===")
    openings = Counter(text[:12] for text in decrypts)
    for opening, count in openings.most_common(10):
        print(f"  {count:2}x  {opening}")
    print()

    # ---- phrases carried by many distinct messages -----------------------------
    carriers: dict[str, set[int]] = defaultdict(set)
    for index, text in enumerate(decrypts):
        for length in range(args.min_len, args.max_len + 1):
            for start in range(len(text) - length + 1):
                carriers[text[start:start + length]].add(index)

    # Keep only maximal phrases: drop a phrase if an extension has the same reach.
    ranked = {phrase: seen for phrase, seen in carriers.items()
              if len(seen) >= args.min_messages}
    maximal = {phrase: seen for phrase, seen in ranked.items()
               if not any(other != phrase and phrase in other and len(oseen) >= len(seen)
                          for other, oseen in ranked.items())}

    print(f"=== Crib candidates (in >= {args.min_messages} distinct messages) ===")
    print(f"{'crib':<16} {'msgs':>4} {'len':>3}  legal offsets in target")
    order = sorted(maximal.items(), key=lambda kv: (-len(kv[1]), -len(kv[0])))
    menu = []
    for phrase, seen in order[:args.top]:
        offsets = viable_offsets(phrase, target_ct)
        shown = ",".join(str(o) for o in offsets[:12])
        if len(offsets) > 12:
            shown += f",+{len(offsets) - 12}"
        print(f"{phrase:<16} {len(seen):>4} {len(phrase):>3}  "
              f"{len(offsets):>2} sites: {shown if offsets else '(none - excluded)'}")
        if offsets:
            menu.append((phrase, offsets))

    total = sum(len(offsets) for _, offsets in menu)
    print(f"\n{len(menu)} cribs survive with {total} legal placements total.")
    print("Each (crib, offset) is one bombe menu. Deterministic: a menu either")
    print("yields a consistent stecker or it contradicts. No overfitting.")

    # A crib excluded at every offset is itself information.
    dead = [p for p, s in order[:args.top] if not viable_offsets(p, target_ct)]
    if dead:
        print(f"\nRuled out at every offset by self-encipherment: {', '.join(dead)}")

    if args.emit:
        emitted = build_emit_set(decrypts, carriers, target_ct, args)
        payload = {
            "target": TARGET,
            "ciphertext": target_ct,
            "note": "Cribs mined from the 48 broken U-534 decrypts; offsets are the "
                    "self-encipherment-legal placements. Consumed by WelchmanDiagonalBoard.",
            "cribs": emitted,
        }
        args.emit.parent.mkdir(parents=True, exist_ok=True)
        args.emit.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        placements = sum(len(c["offsets"]) for c in emitted)
        longest = max((len(c["text"]) for c in emitted), default=0)
        print(f"\nwrote {args.emit}: {len(emitted)} cribs, {placements} placements, "
              f"longest {longest} letters")
    return 0


def build_emit_set(decrypts, carriers, target_ct, args):
    """Menus for the bombe, longest first, plus offset-0-anchored message openings."""
    pool = {phrase: seen for phrase, seen in carriers.items()
            if len(phrase) >= args.emit_min_len
            and len(seen) >= args.emit_min_messages
            and len(phrase) <= len(target_ct)}
    # Drop any phrase that a longer phrase already contains with equal reach.
    by_length = sorted(pool, key=len, reverse=True)
    kept: list[str] = []
    for phrase in by_length:
        if any(phrase in longer and len(pool[longer]) >= len(pool[phrase])
               for longer in kept):
            continue
        kept.append(phrase)

    emitted = []
    for phrase in kept:
        offsets = viable_offsets(phrase, target_ct)
        if offsets:
            emitted.append({"text": phrase, "messages": len(pool[phrase]),
                            "offsets": offsets, "anchored": False})

    # Openings are worth far more per menu: one legal offset instead of ~50.
    openings: dict[str, set] = defaultdict(set)
    for index, text in enumerate(decrypts):
        for length in range(args.emit_min_len, min(len(target_ct), len(text)) + 1):
            openings[text[:length]].add(index)
    anchored = []
    for phrase, seen in openings.items():
        if len(seen) < args.emit_min_messages:
            continue
        if all(phrase[i] != target_ct[i] for i in range(len(phrase))):
            anchored.append({"text": phrase, "messages": len(seen),
                             "offsets": [0], "anchored": True})
    anchored.sort(key=lambda c: -len(c["text"]))
    for candidate in anchored:
        if not any(candidate["text"] in other["text"] and other["anchored"]
                   for other in emitted if other is not candidate):
            emitted.append(candidate)

    emitted.sort(key=lambda c: (-len(c["text"]), -c["messages"]))
    return emitted


if __name__ == "__main__":
    raise SystemExit(main())
