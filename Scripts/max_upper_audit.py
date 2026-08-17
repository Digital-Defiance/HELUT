#!/usr/bin/env python3
"""Did the old MAX_UPPER = 4 cap ever silently eliminate a lane?

The Metal bombe kernel tabulates one "upper involution" table per distinct slow-wheel
`(l, m)` state reached at a menu's edge steps. Until 2026-08-16 the cap was four, and
overflow wrote `outSurvivors[lane] = 0` — reporting the lane *eliminated* rather than
*undecided*. That is a false negative: a lane the board never actually tested, recorded
as a clean kill.

This asks whether the cap was reachable for the menus the campaign actually ran. It is
pure stepping arithmetic — no GPU, no Enigma wiring — so it can audit every completed arm
without re-running a single sweep.

    python3 Scripts/max_upper_audit.py Fixtures/p1030680_menus.json
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

# Window-letter turnover notches. Naval VI-VIII carry two.
NOTCHES = {
    "I": {16}, "II": {4}, "III": {21}, "IV": {9}, "V": {25},
    "VI": {12, 25}, "VII": {12, 25}, "VIII": {12, 25},
}
NAVAL = list(NOTCHES)
OLD_CAP = 4


def distinct_slow_states(edge_steps: set[int], max_step: int,
                         notch_m: set[int], notch_r: set[int],
                         pos_l: int, pos_m: int, pos_r: int) -> int:
    """Mirror of the kernel's trail loop: step first, then record at edge steps."""
    l, m, r = pos_l, pos_m, pos_r
    seen = set()
    for t in range(max_step + 1):
        mid = m in notch_m
        right = r in notch_r
        if mid:
            l = (l + 1) % 26
        if mid or right:
            m = (m + 1) % 26
        r = (r + 1) % 26
        if t in edge_steps:
            seen.add((l, m))
    return len(seen)


def worst_case_for_span(offset: int, length: int) -> tuple[int, int, str, str, int, int]:
    """Max distinct (l, m) over every lane and every (middle, right) rotor pair.

    Also counts severity: how many (rotor pair, window m, window r) combinations
    overflow, out of 56 x 676. Neither `pos_l` nor `pos_g` affects the state *count*
    (`l` only shifts the pair uniformly), so this fraction is the fraction of full lanes.
    """
    edge_steps = set(range(offset, offset + length))
    max_step = offset + length - 1
    worst = 0
    worst_lane = (0, 0, 0)
    worst_pair = ("", "")
    overflow = 0
    combos = 0
    for mid_name in NAVAL:
        for right_name in NAVAL:
            if right_name == mid_name:
                continue
            notch_m, notch_r = NOTCHES[mid_name], NOTCHES[right_name]
            # l only ever shifts the pair uniformly, so pos_l = 0 loses no generality.
            for pos_m in range(26):
                for pos_r in range(26):
                    combos += 1
                    count = distinct_slow_states(
                        edge_steps, max_step, notch_m, notch_r, 0, pos_m, pos_r
                    )
                    if count > OLD_CAP:
                        overflow += 1
                    if count > worst:
                        worst = count
                        worst_lane = (0, pos_m, pos_r)
                        worst_pair = (mid_name, right_name)
    return worst, worst_lane[1], worst_pair[0], worst_pair[1], overflow, combos


def emit_fixture(payload: dict, contaminated: set[tuple[int, int]], out: Path) -> int:
    """Write a menu fixture holding only the contaminated (crib, offset) placements.

    Keeps the re-run honest: the set of spans to retest is derived from the audit rather
    than picked by hand, so the fixture and the verdict are reproducible together.
    """
    cribs = []
    placements = 0
    for crib in payload["cribs"]:
        length = len(crib["text"])
        offsets = [o for o in crib["offsets"] if (o, length) in contaminated]
        if not offsets:
            continue
        placements += len(offsets)
        cribs.append({
            "text": crib["text"],
            "messages": crib.get("messages", 0),
            "offsets": offsets,
        })
    out.write_text(json.dumps({
        "target": payload.get("target", "P1030680"),
        "ciphertext": payload["ciphertext"],
        "note": "Placements whose spans could exceed the old Metal MAX_UPPER=4 slow-state "
                "cap, which reported such lanes ELIMINATED without testing them. Prior "
                "clean negatives on these placements are incomplete by up to 5.56% of "
                "lanes and must be re-run on the corrected kernel. Emitted by "
                "Scripts/max_upper_audit.py --emit.",
        "cribs": cribs,
    }, indent=2) + "\n", encoding="utf-8")
    print()
    print(f"wrote {out}: {len(cribs)} cribs, {placements} placements to re-run")
    return placements


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    emit = None
    if "--emit" in sys.argv:
        index = sys.argv.index("--emit")
        if index + 1 < len(sys.argv):
            emit = Path(sys.argv[index + 1])
    path = Path(args[0] if args else "Fixtures/p1030680_menus.json")
    payload = json.loads(path.read_text())
    ciphertext_len = len(payload["ciphertext"])

    # One (offset, length) span per placement; the verdict depends only on the span.
    spans: set[tuple[int, int]] = set()
    for crib in payload["cribs"]:
        length = len(crib["text"])
        for offset in crib["offsets"]:
            spans.add((offset, length))

    print(f"fixture           : {path}")
    print(f"ciphertext        : {ciphertext_len} letters")
    print(f"distinct spans    : {len(spans)}")
    print(f"old kernel cap    : MAX_UPPER = {OLD_CAP}")
    print()

    over = []
    worst_overall = 0
    total_overflow = 0
    total_combos = 0
    by_length: dict[int, list[float]] = {}
    cache: dict[tuple[int, int], tuple[int, int, str, str, int, int]] = {}
    for offset, length in sorted(spans):
        key = (offset, length)
        if key not in cache:
            cache[key] = worst_case_for_span(offset, length)
        worst, pos_m, mid, right, overflow, combos = cache[key]
        worst_overall = max(worst_overall, worst)
        total_overflow += overflow
        total_combos += combos
        by_length.setdefault(length, []).append(overflow / combos)
        if worst > OLD_CAP:
            over.append((offset, length, worst, pos_m, mid, right, overflow / combos))

    print(f"worst distinct (l, m) over every span x lane x rotor pair: {worst_overall}")
    print(f"lanes exceeding the old cap: {total_overflow} of {total_combos} "
          f"({total_overflow / total_combos * 100:.4f}% of the whole catalog lane space)")
    print()
    print("by crib length (share of lanes silently eliminated by the old cap):")
    for length in sorted(by_length):
        shares = by_length[length]
        peak = max(shares) * 100
        mark = "  <-- contaminated" if peak > 0 else ""
        print(f"  len {length:3d}: {len(shares):4d} placement(s), worst-case "
              f"{peak:.4f}% of lanes{mark}")
    print()
    if not over:
        print("VERDICT: the old cap of 4 was never reachable for any placement in this")
        print("fixture, at any lane, for any naval (middle, right) rotor pair. No lane in")
        print("a completed arm was silently eliminated by MAX_UPPER. Prior negatives on")
        print("this fixture stand. The cap was still wrong to fail closed — it is now")
        print("reported as undecided — but it never fired.")
        return 0

    affected_lengths = sorted({length for _, length, *_ in over})
    print(f"VERDICT: {len(over)} of {len(spans)} spans could exceed the old cap, all at "
          f"crib length {affected_lengths}.")
    print("Those lanes were reported *eliminated* without being tested, so any clean")
    print("negative covering them is incomplete by that fraction. Menus at or below the")
    print("longest unaffected length are unaffected and their negatives stand.")
    print()
    for offset, length, worst, pos_m, mid, right, share in over[:12]:
        print(f"  offset {offset:3d} len {length:3d} -> {worst} states, "
              f"{share * 100:.4f}% of lanes (e.g. middle {mid} right {right}, m={pos_m})")
    if len(over) > 12:
        print(f"  ... {len(over) - 12} more")

    if emit is not None:
        emit_fixture(payload, {(o, l) for o, l, *_ in over}, emit)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
