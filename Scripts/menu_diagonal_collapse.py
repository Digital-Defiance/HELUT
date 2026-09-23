"""Collapse redundant Bombe placements to distinct hypotheses before any GPU time.

The campaign discovered by hand (Phase 54.2) that a crib window slid by one letter is **not a new
hypothesis**: it asserts the same source text at the same alignment against the ciphertext. Grouping
by that alignment and keeping the strongest menu per group was measured at a 130x reduction and is
what turns "weeks of decades" of hapax sweeping into weeks. That collapse had no reusable tool; this
is it.

What counts as the same hypothesis, made precise
------------------------------------------------
A placement asserts a partial map ``position -> plaintext letter`` over the ciphertext. Call that its
*assertion set*, a set of ``(position, letter)`` pairs. Two placements are:

  * **conflicting** if they assert different letters at a shared position — genuinely different
    hypotheses, never merged;
  * **nested** if one assertion set is a subset of another and they never conflict — the subset is
    redundant, because every board constraint it contributes is already contributed by the superset
    at the same positions;
  * **diagonal-equal** if their assertion sets are equal — the same hypothesis written at two
    offsets (the one-letter-slide case).

The tool groups placements into connected components under "shares >= 1 assertion pair and does not
conflict", then within each component keeps only the *maximal* placements (no other kept placement's
assertion set is a strict superset). Ties in coverage break by Bombe strength: more loops, then more
edges, then single-component, then lexicographic id, so the survivor is the menu the board most wants
to run.

This is a **cost** tool, not a search. It evaluates no settings, asserts no plaintext, and changes no
verdict. Its output is a smaller fixture that provably covers the same hypotheses, plus a report of
exactly what was dropped and why, so a human can see nothing real was discarded.

Union-find and topology are shared verbatim with constellation_crib_generator.py, whose loops/
components already agree with the Swift board (ConstellationFixtureTopologyTests).

Usage
-----
    python3 Scripts/menu_diagonal_collapse.py Fixtures/p1030680_relay_menus.json
    python3 Scripts/menu_diagonal_collapse.py Fixtures/p1030680_menus.json \
        --emit Fixtures/p1030680_menus_collapsed.json --min-loops 8
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def legal(text: str, ciphertext: str, offset: int) -> bool:
    if offset < 0 or offset + len(text) > len(ciphertext):
        return False
    return all(text[i] != ciphertext[offset + i] for i in range(len(text)))


def topology(text: str, offset: int, ciphertext: str) -> dict:
    """Loops/components for one contiguous crib, by the shared union-find."""
    parent = list(range(26))
    present: set[int] = set()
    edges = 0

    def find(x: int) -> int:
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for i, ch in enumerate(text):
        plain = ord(ch) - 65
        cipher = ord(ciphertext[offset + i]) - 65
        present.update((plain, cipher))
        ra, rb = find(plain), find(cipher)
        if ra != rb:
            parent[ra] = rb
        edges += 1
    components = len({find(x) for x in present}) if present else 0
    loops = edges - len(present) + components if present else 0
    return {"edges": edges, "letters": len(present),
            "components": components, "loops": loops}


class Placement:
    __slots__ = ("id", "text", "offset", "assert_set", "top")

    def __init__(self, text: str, offset: int, ciphertext: str):
        self.id = f"{text}@{offset}"
        self.text = text
        self.offset = offset
        # The hypothesis: position -> plaintext letter over the ciphertext.
        self.assert_set = frozenset(
            (offset + i, ch) for i, ch in enumerate(text))
        self.top = topology(text, offset, ciphertext)

    def conflicts(self, other: "Placement") -> bool:
        mine = {p: c for p, c in self.assert_set}
        for p, c in other.assert_set:
            if p in mine and mine[p] != c:
                return True
        return False

    def shares(self, other: "Placement") -> bool:
        return not self.assert_set.isdisjoint(other.assert_set)

    def strength(self) -> tuple:
        # Board preference: loops, edges, single-componentness, then stable id.
        return (self.top["loops"], self.top["edges"],
                -self.top["components"], self.id)


def load_placements(fixture: dict) -> list[Placement]:
    ciphertext = "".join(c for c in fixture["ciphertext"].upper() if c.isalpha())
    placements: list[Placement] = []
    dropped_illegal = 0
    for crib in fixture.get("cribs") or []:
        text = "".join(c for c in crib["text"].upper() if c.isalpha())
        for offset in crib.get("offsets", []):
            if not legal(text, ciphertext, offset):
                dropped_illegal += 1
                continue
            placements.append(Placement(text, offset, ciphertext))
    return placements, ciphertext, dropped_illegal


def connected_components(placements: list[Placement]) -> list[list[Placement]]:
    """Group by 'shares an assertion pair and does not conflict'."""
    n = len(placements)
    parent = list(range(n))

    def find(x: int) -> int:
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    # Index placements by asserted position so we only compare plausible pairs.
    by_pos: dict[int, list[int]] = {}
    for idx, pl in enumerate(placements):
        for pos, _ in pl.assert_set:
            by_pos.setdefault(pos, []).append(idx)

    for sharers in by_pos.values():
        for a in range(len(sharers)):
            for b in range(a + 1, len(sharers)):
                i, j = sharers[a], sharers[b]
                if find(i) == find(j):
                    continue
                if placements[i].shares(placements[j]) and not placements[i].conflicts(placements[j]):
                    parent[find(i)] = find(j)

    groups: dict[int, list[Placement]] = {}
    for idx, pl in enumerate(placements):
        groups.setdefault(find(idx), []).append(pl)
    return list(groups.values())


def keep_maximal(group: list[Placement]) -> tuple[list[Placement], list[tuple[Placement, str]]]:
    """Within one non-conflicting group, keep placements whose assertion set is not a
    strict subset of another. Coverage ties (equal assertion sets) keep the strongest."""
    kept: list[Placement] = []
    dropped: list[tuple[Placement, str]] = []
    ordered = sorted(group, key=lambda p: (-len(p.assert_set),) + tuple(
        -x if isinstance(x, int) else 0 for x in p.strength()[:3]) + (p.id,))
    for pl in ordered:
        superset = None
        for k in kept:
            if pl.assert_set == k.assert_set:
                superset = k
                reason = f"diagonal-equal to {k.id}"
                break
            if pl.assert_set < k.assert_set:
                superset = k
                reason = f"nested in {k.id} (+{len(k.assert_set) - len(pl.assert_set)} more anchored)"
                break
        if superset is None:
            kept.append(pl)
        else:
            # Soundness invariant: a placement is only safe to drop if the menu that covers
            # it is at least as strong. Otherwise a later loops/length gate could keep the
            # subset while discarding the superset, and collapsing first would lose coverage.
            # Nesting adds constraints at the same positions, so this should always hold; we
            # assert it rather than trust it.
            if pl.top["loops"] > superset.top["loops"]:
                raise AssertionError(
                    f"UNSOUND COLLAPSE: {pl.id} (loops={pl.top['loops']}) would be dropped "
                    f"in favour of weaker {superset.id} (loops={superset.top['loops']})")
            dropped.append((pl, reason))
    return kept, dropped


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("fixture")
    ap.add_argument("--emit", help="write the collapsed fixture here")
    ap.add_argument("--min-loops", type=int, default=0,
                    help="drop survivors below this many loops (0 = keep all)")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    fixture = json.loads(Path(args.fixture).read_text())
    placements, ciphertext, dropped_illegal = load_placements(fixture)
    if not placements:
        print(f"no legal placements in {args.fixture}", file=sys.stderr)
        return 1

    groups = connected_components(placements)
    kept_all: list[Placement] = []
    drops: list[tuple[Placement, str]] = []
    for group in groups:
        kept, dropped = keep_maximal(group)
        kept_all.extend(kept)
        drops.extend(dropped)

    below = [p for p in kept_all if p.top["loops"] < args.min_loops]
    kept_all = [p for p in kept_all if p.top["loops"] >= args.min_loops]

    total = len(placements)
    reduction = total / len(kept_all) if kept_all else float("inf")
    print(f"fixture              : {args.fixture}")
    print(f"ciphertext length    : {len(ciphertext)}")
    print(f"legal placements     : {total}"
          + (f"  (+{dropped_illegal} illegal skipped)" if dropped_illegal else ""))
    print(f"distinct hypotheses  : {len(kept_all)}   ({reduction:.1f}x reduction)")
    print(f"redundant dropped    : {len(drops)}"
          + (f"  + {len(below)} below min-loops {args.min_loops}" if below else ""))
    print()

    if not args.quiet and drops:
        print("dropped as redundant (each is covered by a kept, stronger menu):")
        for pl, reason in sorted(drops, key=lambda d: d[0].id)[:40]:
            print(f"  {pl.id:34} loops={pl.top['loops']:2} -> {reason}")
        if len(drops) > 40:
            print(f"  ... {len(drops) - 40} more")
        print()

    if not args.quiet:
        print("kept (distinct hypotheses, strongest per diagonal):")
        for pl in sorted(kept_all, key=lambda p: (-p.top["loops"], p.id))[:40]:
            t = pl.top
            print(f"  {pl.id:34} edges={t['edges']:2} loops={t['loops']:2} "
                  f"comp={t['components']} letters={t['letters']:2}")
        if len(kept_all) > 40:
            print(f"  ... {len(kept_all) - 40} more")

    if args.emit:
        out = {
            "target": fixture.get("target", "P1030680"),
            "ciphertext": fixture["ciphertext"],
            "note": (f"Diagonal-collapsed from {args.fixture}: {total} legal placements -> "
                     f"{len(kept_all)} distinct hypotheses ({reduction:.1f}x). Redundant windows "
                     f"(nested / one-letter-slide) removed; no plaintext invented, no setting "
                     f"evaluated. Regenerate with Scripts/menu_diagonal_collapse.py."),
            "cribs": [{"text": pl.text, "offsets": [pl.offset]}
                      for pl in sorted(kept_all, key=lambda p: (-p.top["loops"], p.id))],
        }
        Path(args.emit).write_text(json.dumps(out, indent=2) + "\n")
        print(f"\nwrote {args.emit}: {len(kept_all)} distinct menus")

    return 0


if __name__ == "__main__":
    sys.exit(main())
