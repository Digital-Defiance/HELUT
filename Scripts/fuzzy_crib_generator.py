#!/usr/bin/env python3
"""Generate fuzzed Kriegsmarine crib menus for P1030680.

Strict historical cribs have cleared the turnover-free space and the curated
top-30 ring sweep. A clean negative on exact matches points at human error:
operator typos, non-standard abbreviations, or header padding that shattered
Welchman Boolean logic. This script mutates high-value naval cribs under those
error profiles and emits a new fixture for `helut`.

Filters (mandatory):
  - crib length >= 16 (no 14-letter false-positive trap)
  - self-encipherment law at every placement

Topology (loops / edges / letters) mirrors BombeMenuBuilder / select_top30.

Usage:
  python3 Scripts/fuzzy_crib_generator.py \\
      Fixtures/p1030680_menus.json \\
      --emit Fixtures/p1030680_fuzzed_menus.json
"""
from __future__ import annotations

import argparse
import json
import re
from collections import defaultdict
from pathlib import Path

MIN_LEN = 16
# Metal Welchman kernel hard-caps at welchmanMaxEdges = 40 (BombeMetal.swift).
MAX_CRIB_LEN = 40

# Core Kriegsmarine register fragments named in fuzzy-crib.md.
CORE_FRAGMENTS = (
    "UUUFLOTTX",
    "KOMXADMXU",
    "KOMXADMX",
    "TRAVEMUE",
    "WETTERVORHERSAGE",
    "WETTER",
    "NULEINS",
    "FLOTTX",
    "VVVUUU",
    "UUUVIRSIBEN",
)

# Longer form first so replace() does not re-expand a short stem inside a long form.
ABBREVIATIONS: list[tuple[str, str]] = [
    ("UUUFLOTTILLE", "UUUFLOTTX"),
    ("UUUFLOTTX", "UFLOTTX"),
    ("UUUFLOTTX", "UUUFLOTTILLE"),
    ("UUUFLOTTXX", "UUUFLOTTX"),
    ("FLOTTILLE", "FLOTTX"),
    ("FLOTTX", "FLOTTILLE"),
    ("KOMMANDADX", "KOMXADMX"),
    ("KOMXADMXU", "KOMMADMXU"),
    ("KOMXADMX", "KOMADMX"),
    ("KOMXADMX", "KOMMANDADX"),
    ("TRAVEMUENDE", "TRAVEMUE"),
    ("TRAVEMUE", "TRAVEMUENDE"),
    ("NACHTRAVEMUENDE", "NACHTRAVEMUE"),
    ("NACHTRAVEMUE", "NACHTRAVEMUENDE"),
    ("WETTERVORHERSAGE", "WETTER"),
    ("VVVUUU", "VVUUU"),
    ("VVVUUU", "VVVUU"),
    ("VVVCHEF", "VVCHEF"),
    ("NULEINS", "NULEIN"),
    ("VIRSIBEN", "VIIRSIBEN"),
    ("BEIROTNUL", "BEIROTNULL"),
    ("MITUUU", "MITU"),
    ("XXMIT", "XMIT"),
]

PHONETIC_PAIRS = (
    ("C", "K"),
    ("K", "C"),
    ("Z", "S"),
    ("S", "Z"),
    ("V", "W"),
    ("W", "V"),
    ("I", "J"),
    ("Y", "I"),
    ("B", "P"),
    ("D", "T"),
    ("T", "D"),
)

# Confusable letters for Hamming-1 probes (body only).
HAMMING_ALPHABET = "AEIOUXNFTR"

ALPHABET = re.compile(r"^[A-Z]+$")


def normalize(text: str) -> str:
    return "".join(ch for ch in text.upper() if "A" <= ch <= "Z")


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
    return {
        "text": crib,
        "offset": offset,
        "edges": edges,
        "letters": len(vertices),
        "loops": loops,
    }


def legal_offsets(crib: str, ciphertext: str) -> list[int]:
    return [
        offset
        for offset in range(len(ciphertext) - len(crib) + 1)
        if build_menu(crib, offset, ciphertext) is not None
    ]


def select_seed_cribs(menus: dict, corpus_path: Path | None = None) -> list[dict]:
    """Deduped high-value seeds: core fragments or frequent corpus carriers."""
    raw: list[dict] = []
    for crib in menus["cribs"]:
        text = normalize(crib["text"])
        if not (MIN_LEN <= len(text) <= MAX_CRIB_LEN):
            continue
        hit = any(frag in text for frag in CORE_FRAGMENTS)
        frequent = int(crib.get("messages", 0)) >= 3
        if not (hit or frequent):
            continue
        raw.append({
            "text": text,
            "messages": int(crib.get("messages", 0)),
            "offsets": [int(o) for o in crib.get("offsets", [])],
        })

    # Pull longer windows containing scarce cores (TRAVEMUE / WETTER) from corpus.
    if corpus_path is not None and corpus_path.is_file():
        corpus = json.loads(corpus_path.read_text(encoding="utf-8"))
        for msg in corpus.get("messages", []):
            pt = normalize(msg.get("plaintext") or "")
            if len(pt) < MIN_LEN:
                continue
            for frag in CORE_FRAGMENTS:
                start = pt.find(frag)
                if start < 0:
                    continue
                # Prefer a 18–28 letter window centered on the fragment.
                for length in (24, 20, 18, 16):
                    lo = max(0, start - 2)
                    hi = min(len(pt), lo + length)
                    lo = max(0, hi - length)
                    window = pt[lo:hi]
                    if len(window) >= MIN_LEN and frag in window:
                        raw.append({"text": window, "messages": 1, "offsets": []})
                        break

    # Drop a crib if a longer catalog crib contains it (keep maximal phrases).
    texts = {r["text"] for r in raw}
    seeds = []
    seen: set[str] = set()
    for item in sorted(raw, key=lambda r: (-len(r["text"]), -r["messages"], r["text"])):
        text = item["text"]
        if text in seen:
            continue
        if any(text != other and text in other for other in texts):
            continue
        seen.add(text)
        seeds.append(item)

    # Ensure each core fragment has at least one carrier.
    ciphertext = normalize(menus["ciphertext"])
    for frag in CORE_FRAGMENTS:
        if any(frag in s["text"] for s in seeds):
            continue
        carriers = [
            normalize(c["text"])
            for c in menus["cribs"]
            if frag in normalize(c["text"]) and MIN_LEN <= len(normalize(c["text"])) <= MAX_CRIB_LEN
        ]
        if carriers:
            carriers.sort(key=len, reverse=True)
            text = carriers[0]
        elif MIN_LEN <= len(frag) <= MAX_CRIB_LEN:
            text = frag
        else:
            continue
        if text not in seen:
            seen.add(text)
            seeds.append({
                "text": text,
                "messages": 0,
                "offsets": legal_offsets(text, ciphertext),
            })
    return seeds


def _safe_replace(text: str, src: str, dst: str) -> str | None:
    """Replace src→dst once, but never expand a stem that already sits inside dst."""
    if src not in text:
        return None
    # Avoid WETTER→WETTERVORHERSAGE when WETTER is already the stem of that form.
    if src != dst and dst.startswith(src):
        idx = text.find(src)
        while idx != -1:
            if text[idx: idx + len(dst)] == dst:
                idx = text.find(src, idx + 1)
                continue
            return text[:idx] + dst + text[idx + len(src) :]
        return None
    return text.replace(src, dst, 1)


def mutate_abbreviations(text: str) -> set[str]:
    out: set[str] = set()
    for src, dst in ABBREVIATIONS:
        replaced = _safe_replace(text, src, dst)
        if replaced and replaced != text:
            out.add(replaced)
    return {
        normalize(t)
        for t in out
        if ALPHABET.match(normalize(t)) and MIN_LEN <= len(normalize(t)) <= MAX_CRIB_LEN
    }


def mutate_phonetic(text: str) -> set[str]:
    out: set[str] = set()
    # Cap phonetic sites — long openings have many V/W/T hits.
    swaps = 0
    for i, ch in enumerate(text):
        for a, b in PHONETIC_PAIRS:
            if ch == a:
                out.add(text[:i] + b + text[i + 1 :])
                swaps += 1
                break
        if swaps >= 24:
            break
    for i in range(len(text) - 1):
        if text[i] == text[i + 1]:
            out.add(text[:i] + text[i + 1 :])
    # Insert one doubled letter at a few mid sites only.
    for i in range(2, len(text) - 1, 3):
        if text[i] in "FTUXNL" and text[i - 1] != text[i]:
            out.add(text[:i] + text[i] + text[i:])
    return {
        normalize(t)
        for t in out
        if ALPHABET.match(normalize(t)) and MIN_LEN <= len(normalize(t)) <= MAX_CRIB_LEN
    }


def mutate_hamming1(text: str) -> set[str]:
    """Single-character substitutions in the body (non-critical positions)."""
    if not (MIN_LEN <= len(text) <= 28):
        # Long openings: sample every 3rd body site to keep the set tractable.
        step = 3
    else:
        step = 1
    out: set[str] = set()
    lo, hi = 2, len(text) - 2
    for i in range(lo, hi, step):
        if text[i] == "X":
            continue
        for alt in HAMMING_ALPHABET:
            if alt == text[i]:
                continue
            out.add(text[:i] + alt + text[i + 1 :])
    return out


def mutate_padding_forms(text: str) -> set[str]:
    """Light header/trailer garbage on the crib text itself.

    Primary padding coverage is offset ±1/2/3 on known placements; text pads
    here are only single-character so they do not dominate the ranked fixture.
    """
    out: set[str] = set()
    for pad in ("X", "Y"):
        cand = pad + text
        if len(cand) <= MAX_CRIB_LEN:
            out.add(cand)
        cand = text + pad
        if len(cand) <= MAX_CRIB_LEN:
            out.add(cand)
        if text.startswith(pad) and len(text) - len(pad) >= MIN_LEN:
            out.add(text[len(pad) :])
        if text.endswith(pad) and len(text) - len(pad) >= MIN_LEN:
            out.add(text[: -len(pad)])
    return {
        normalize(t)
        for t in out
        if ALPHABET.match(normalize(t)) and MIN_LEN <= len(normalize(t)) <= MAX_CRIB_LEN
    }


def all_mutations(text: str, max_variants: int) -> set[str]:
    variants: set[str] = {text}
    variants |= mutate_abbreviations(text)
    variants |= mutate_phonetic(text)
    variants |= mutate_padding_forms(text)
    # Hamming last; add until cap.
    for v in mutate_hamming1(text):
        variants.add(v)
        if len(variants) >= max_variants:
            break
    # One abbreviation hop on non-Hamming variants only (keeps expansion bounded).
    base_for_hop = {text} | mutate_abbreviations(text) | mutate_phonetic(text) | mutate_padding_forms(text)
    for v in list(base_for_hop):
        variants |= mutate_abbreviations(v)
        if len(variants) >= max_variants:
            break
    return {v for v in variants if MIN_LEN <= len(v) <= MAX_CRIB_LEN}


def candidate_offsets(
    text: str,
    seed_offsets: list[int],
    ciphertext: str,
    full_scan: bool,
) -> list[int]:
    """Known sites ±1/2/3 (header padding); optional full legal rescan."""
    wanted: set[int] = set()
    for base in seed_offsets:
        for delta in (0, 1, 2, 3, -1, -2, -3):
            wanted.add(base + delta)
    if full_scan or not seed_offsets:
        wanted.update(range(0, max(0, len(ciphertext) - len(text) + 1)))
    return sorted(
        offset
        for offset in wanted
        if build_menu(text, offset, ciphertext) is not None
    )


def emit_fixture(
    placements: list[dict],
    ciphertext: str,
    source: Path,
    out: Path,
) -> None:
    by_text: dict[str, list[int]] = defaultdict(list)
    for menu in placements:
        by_text[menu["text"]].append(menu["offset"])

    seen: set[str] = set()
    ordered = []
    for menu in placements:
        text = menu["text"]
        if text in seen:
            continue
        seen.add(text)
        ordered.append({
            "text": text,
            "messages": 0,
            "offsets": sorted(by_text[text]),
            "anchored": 0 in by_text[text],
            "fuzzed": True,
        })

    payload = {
        "target": "P1030680",
        "ciphertext": ciphertext,
        "note": (
            f"Fuzzed Kriegsmarine crib menus ({len(placements)} placements, "
            f"{len(ordered)} distinct texts). Mutations: header ±1/2/3, signal "
            f"abbreviations, phonetic/orthographic slips, Hamming-1 body swaps. "
            f"Filter: len>={MIN_LEN} and <={MAX_CRIB_LEN} (Metal edge cap); "
            f"self-encipherment illegal. "
            f"Derived from {source.name}. Topology matches BombeMenuBuilder."
        ),
        "cribs": ordered,
        "placements": [
            {
                "text": m["text"],
                "offset": m["offset"],
                "loops": m["loops"],
                "edges": m["edges"],
                "letters": m["letters"],
                "opening": m["offset"] == 0,
                "mutation": m.get("mutation", "seed"),
            }
            for m in placements
        ],
    }
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "menus",
        type=Path,
        nargs="?",
        default=Path("Fixtures/p1030680_menus.json"),
    )
    parser.add_argument(
        "--emit",
        type=Path,
        default=Path("Fixtures/p1030680_fuzzed_menus.json"),
    )
    parser.add_argument(
        "--corpus",
        type=Path,
        default=Path("Fixtures/u534_corpus.json"),
        help="optional decrypt corpus used to extend scarce cores (TRAVEMUE/WETTER)",
    )
    parser.add_argument("--min-len", type=int, default=16)
    parser.add_argument(
        "--max-variants-per-seed",
        type=int,
        default=120,
        help="cap mutated texts retained per seed crib",
    )
    parser.add_argument(
        "--max-placements",
        type=int,
        default=400,
        help="keep the top-N by loops/edges after ranking (0 = keep all)",
    )
    args = parser.parse_args()
    global MIN_LEN
    MIN_LEN = args.min_len

    menus = json.loads(args.menus.read_text(encoding="utf-8"))
    ciphertext = normalize(menus["ciphertext"])
    seeds = select_seed_cribs(menus, corpus_path=args.corpus)

    # Exact catalog pairs already cleared — fuzzed fixture must be novel.
    catalog_pairs: set[tuple[str, int]] = set()
    for crib in menus["cribs"]:
        text = normalize(crib["text"])
        for offset in crib.get("offsets", []):
            catalog_pairs.add((text, int(offset)))

    placements: list[dict] = []
    seen_pair: set[tuple[str, int]] = set()

    for seed in seeds:
        base = seed["text"]
        seed_neighborhood = {
            base_off + delta
            for base_off in seed["offsets"]
            for delta in (0, 1, 2, 3, -1, -2, -3)
        }
        variants = all_mutations(base, args.max_variants_per_seed)
        # Keep the exact seed text only for offset-shifted padding probes.
        if len(base) >= MIN_LEN:
            variants.add(base)

        for text in sorted(variants, key=lambda t: (-len(t), t)):
            mutation = "seed-shift" if text == base else "fuzz"
            # Offset ±1/2/3 covers header padding. Full rescan only for brand-new
            # texts with no seed offsets to anchor them.
            full_scan = not seed["offsets"]
            offsets = candidate_offsets(
                text, seed["offsets"], ciphertext, full_scan=full_scan
            )
            for offset in offsets:
                key = (text, offset)
                if key in seen_pair or key in catalog_pairs:
                    continue
                # Exact crib text only at shifted offsets (header padding).
                if text == base and offset in seed["offsets"]:
                    continue
                menu = build_menu(text, offset, ciphertext)
                if menu is None:
                    continue
                seen_pair.add(key)
                menu["mutation"] = mutation
                menu["rank_key"] = (
                    0 if offset in seed_neighborhood else 1,
                    -menu["loops"],
                    -menu["edges"],
                    -len(text),
                    offset,  # stable tie-break
                )
                placements.append(menu)

    placements.sort(key=lambda m: m["rank_key"])

    if args.max_placements > 0:
        # Stratify by core fragment so FLOTTX expansions do not crowd out
        # KOMXADMX / TRAVEMUE / WETTER / digit-word families.
        def family(text: str) -> str:
            for frag in (
                "FLOTT", "KOMX", "TRAV", "WETTER", "VIRSIBEN",
                "NULEINS", "VVV", "BEIROT",
            ):
                if frag in text:
                    return frag
            return "other"

        openings = [m for m in placements if m["offset"] == 0]
        interior = [m for m in placements if m["offset"] != 0]
        open_budget = min(len(openings), args.max_placements // 2)
        interior_budget = args.max_placements - open_budget

        def take_stratified(pool: list[dict], budget: int) -> list[dict]:
            if budget <= 0 or not pool:
                return []
            by_fam: dict[str, list[dict]] = defaultdict(list)
            for m in pool:
                by_fam[family(m["text"])].append(m)
            families = sorted(by_fam.keys())
            per = max(1, budget // max(1, len(families)))
            chosen: list[dict] = []
            seen: set[tuple[str, int]] = set()
            for fam in families:
                for m in by_fam[fam][:per]:
                    key = (m["text"], m["offset"])
                    if key in seen:
                        continue
                    seen.add(key)
                    chosen.append(m)
                    if len(chosen) >= budget:
                        return chosen
            for m in pool:
                if len(chosen) >= budget:
                    break
                key = (m["text"], m["offset"])
                if key in seen:
                    continue
                seen.add(key)
                chosen.append(m)
            return chosen

        placements = (
            take_stratified(openings, open_budget)
            + take_stratified(interior, interior_budget)
        )
        placements.sort(key=lambda m: m["rank_key"])

    emit_fixture(placements, ciphertext, args.menus, args.emit)

    fuzzed = sum(1 for m in placements if m.get("mutation") == "fuzz")
    shifted = sum(1 for m in placements if m.get("mutation") == "seed-shift")
    openings = sum(1 for m in placements if m["offset"] == 0)
    texts = len({m["text"] for m in placements})
    print(
        f"wrote {args.emit}: {len(placements)} placements "
        f"({texts} texts, {fuzzed} fuzzed, {shifted} offset-shifted, "
        f"{openings} openings @0)"
    )
    print(f"seeds considered: {len(seeds)}")
    print(f"{'#':>3}  {'off':>3}  {'loops':>5}  {'edges':>5}  {'len':>3}  crib")
    for i, m in enumerate(placements[:25], 1):
        mark = "*" if m["offset"] == 0 else " "
        print(
            f"{i:>3}{mark} {m['offset']:>3}  {m['loops']:>5}  {m['edges']:>5}  "
            f"{len(m['text']):>3}  {m['text'][:52]}"
        )
    if len(placements) > 25:
        print(f"  … {len(placements) - 25} more")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
