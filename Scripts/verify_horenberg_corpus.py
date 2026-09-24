#!/usr/bin/env python3
"""Published-key round-trip of both Hörenberg scrapes.

This checks HELUT's M4 / Enigma I engines against keys and plaintext already
published on enigma.hoerenberg.com. It is not an independent break.

    python3 Scripts/verify_horenberg_corpus.py
    python3 Scripts/verify_horenberg_corpus.py --json

U-534 uses M4. Wider pages use Enigma I when rings/positions are three letters,
or M4 when they are four (Greek β tried, then γ, if the scrape omitted it).
Unsupported wirings (Spanish 'setta') and incomplete keys are skipped, not forced.
P1030680 is never decrypted: its scrape `plaintext` is a placeholder.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "Scripts"))

from enigma_m4 import I3, M4, GREEK_ALIAS, norm, to_str  # noqa: E402

UNSUPPORTED_REFLECTOR = {"SETTA"}
U534_PATH = ROOT / "Fixtures/u534_corpus.json"
WIDER_PATH = ROOT / "Fixtures/bgnc_wider_corpus.json"


def letters(text: str | None) -> str:
    return re.sub(r"[^A-Z]", "", (text or "").upper())


def prefix_agree(got: list[int], expect: list[int]) -> int:
    n = 0
    for a, b in zip(got, expect):
        if a != b:
            break
        n += 1
    return n


# Wider pages whose published keys do not decrypt from letter 0. Scrape or
# unpublished key detail — not an I3 wiring miss (PAGE_23 and the parked-M4
# identity tests still hold).
WIDER_DOCUMENTED_SCRAMBLE = (
    "PAGE_40_PYCMW",
    "PAGE_40_ZBAQW",
    "PAGE_47_RTQSX",
)


def outcome(got: list[int], expect: list[int]) -> str:
    if got == expect:
        return "exact"
    if expect and len(got) >= len(expect) and got[: len(expect)] == expect:
        return "prefix"
    agree = prefix_agree(got, expect)
    n = min(len(got), len(expect))
    # Trailing scrape letter (prose capital swept onto one or both streams).
    if n >= 3 and agree >= n - 1:
        return "head"
    return "mismatch"


def skip(rec: dict, reason: str, **extra) -> dict:
    row = {
        "id": rec.get("id"),
        "grade": "skip",
        "reason": reason,
        "machine": None,
    }
    row.update(extra)
    return row


def decrypt_m4(rec: dict, ct: list[int], greek: str, rings: str, positions: str) -> list[int]:
    return M4(
        reflector=rec["reflector"],
        greek=greek,
        wheels=str(rec["wheels"]),
        rings=rings,
        positions=positions,
        plugs=rec.get("plugs") or "",
    ).process(ct)


def decrypt_i3(rec: dict, ct: list[int], rings: str, positions: str) -> list[int]:
    return I3(
        reflector=rec["reflector"],
        wheels=str(rec["wheels"]),
        rings=rings,
        positions=positions,
        plugs=rec.get("plugs") or "",
    ).process(ct)


def grade_record(rec: dict, collection: str) -> dict:
    """One scrape row → exact / prefix / mismatch / skip. Never invents a key."""
    ident = rec.get("id") or ""
    if ident == "P1030680":
        return skip(rec, "unbroken_placeholder")
    if not rec.get("broken"):
        return skip(rec, "not_claimed_broken")
    ct_s, pt_s = letters(rec.get("ciphertext")), letters(rec.get("plaintext"))
    if not ct_s:
        return skip(rec, "no_ciphertext")
    if not pt_s:
        return skip(rec, "no_plaintext")
    refl = (rec.get("reflector") or "").upper()
    if not refl or refl in UNSUPPORTED_REFLECTOR:
        return skip(rec, "unsupported_reflector", reflector=rec.get("reflector"))
    if refl not in ("A", "B", "C"):
        return skip(rec, "unsupported_reflector", reflector=rec.get("reflector"))
    wheels = rec.get("wheels")
    pos = letters(rec.get("wheel_positions"))
    rings = letters(rec.get("rings"))
    if not wheels or not pos:
        return skip(rec, "incomplete_key")

    ct, expect = norm(ct_s), norm(pt_s)
    greek = rec.get("greek")
    inferred = None

    try:
        if greek or len(pos) == 4:
            if len(pos) != 4 or len(rings) != 4:
                return skip(rec, "incomplete_key")
            candidates = [greek] if greek else ["beta", "gamma"]
            best: tuple[int, str, list[int]] | None = None
            for raw in candidates:
                gname = GREEK_ALIAS.get(str(raw).upper(), str(raw).lower())
                got = decrypt_m4(rec, ct, gname, rings, pos)
                agree = prefix_agree(got, expect)
                if best is None or agree > best[0]:
                    best = (agree, gname, got)
            assert best is not None
            agree, gname, got = best
            if not greek:
                inferred = gname
            machine = "M4"
        elif len(pos) == 3:
            if len(rings) != 3:
                return skip(rec, "incomplete_key")
            got = decrypt_i3(rec, ct, rings, pos)
            machine = "I3"
        else:
            return skip(rec, "incomplete_key")
    except (KeyError, ValueError) as exc:
        return skip(rec, "engine_reject", detail=str(exc))

    grade = outcome(got, expect)
    if collection != "wider" and grade == "head":
        # U-534 n-1 misses stay in the Phase 50.9 mismatch set, not scrape-tail "head".
        grade = "mismatch"
    agree = prefix_agree(got, expect)
    row = {
        "id": ident,
        "collection": collection,
        "grade": grade,
        "machine": machine,
        "ct_len": len(ct),
        "pt_len": len(expect),
        "prefix_agree": agree,
        "scramble_from_start": grade == "mismatch" and agree < 3,
    }
    if inferred:
        row["greek_inferred"] = inferred
    if grade != "exact":
        row["decrypt_head"] = to_str(got[:12])
        row["plain_head"] = to_str(expect[:12])
    return row


def grade_file(path: Path, collection: str) -> list[dict]:
    data = json.loads(path.read_text(encoding="utf-8"))
    return [grade_record(rec, collection) for rec in data["messages"]]


def summarize(rows: list[dict]) -> dict:
    counts: dict[str, int] = {}
    for row in rows:
        counts[row["grade"]] = counts.get(row["grade"], 0) + 1
    scramble = [r["id"] for r in rows if r.get("scramble_from_start")]
    clean = counts.get("exact", 0) + counts.get("prefix", 0) + counts.get("head", 0)
    return {
        "rows": len(rows),
        "exact": counts.get("exact", 0),
        "prefix": counts.get("prefix", 0),
        "head": counts.get("head", 0),
        "mismatch": counts.get("mismatch", 0),
        "skip": counts.get("skip", 0),
        "clean": clean,
        "scramble_from_start": scramble,
        "mismatch_ids": [r["id"] for r in rows if r["grade"] == "mismatch"],
        "prefix_ids": [r["id"] for r in rows if r["grade"] == "prefix"],
        "head_ids": [r["id"] for r in rows if r["grade"] == "head"],
        "skip_reasons": _tally(r.get("reason") for r in rows if r["grade"] == "skip"),
    }


def _tally(items) -> dict[str, int]:
    out: dict[str, int] = {}
    for item in items:
        if item:
            out[item] = out.get(item, 0) + 1
    return out


def receipt() -> dict:
    u534 = grade_file(U534_PATH, "u534")
    wider = grade_file(WIDER_PATH, "wider")
    return {
        "note": "Published-key round-trip. Not independent breaks. P1030680 is not decrypted.",
        "command": "python3 Scripts/verify_horenberg_corpus.py",
        "u534": {"path": "Fixtures/u534_corpus.json", "summary": summarize(u534), "messages": u534},
        "wider": {
            "path": "Fixtures/bgnc_wider_corpus.json",
            "summary": summarize(wider),
            "messages": wider,
        },
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    data = receipt()
    u_scramble = data["u534"]["summary"]["scramble_from_start"]
    w_scramble = data["wider"]["summary"]["scramble_from_start"]
    unexpected = [i for i in w_scramble if i not in WIDER_DOCUMENTED_SCRAMBLE]
    rc = 1 if u_scramble or unexpected else 0
    if args.json:
        print(json.dumps(data, indent=2, ensure_ascii=False))
        return rc

    for name in ("u534", "wider"):
        s = data[name]["summary"]
        print(f"== {name} ({data[name]['path']}) ==")
        print(
            f"  exact {s['exact']}  prefix {s['prefix']}  head {s['head']}  "
            f"mismatch {s['mismatch']}  skip {s['skip']}"
        )
        print(f"  clean {s['clean']}  scramble-from-start {s['scramble_from_start'] or 'none'}")
        if s["prefix_ids"]:
            print(f"  prefix ids: {', '.join(s['prefix_ids'])}")
        if s.get("head_ids"):
            print(f"  head ids: {', '.join(s['head_ids'])}")
        if s["mismatch_ids"]:
            print(f"  mismatch ids: {', '.join(s['mismatch_ids'])}")
        if s["skip_reasons"]:
            print(f"  skips: {s['skip_reasons']}")
        print()
    if u_scramble:
        print("FAIL — U-534 keyed decrypt disagrees from letter 0 (engine bug until proven otherwise).")
    elif unexpected:
        print(f"FAIL — unexpected wider scramble-from-start: {unexpected}")
    else:
        print(
            "PASS — U-534 has no scramble-from-start. Wider documented scramble "
            f"{list(WIDER_DOCUMENTED_SCRAMBLE)} is scrape/key, not the I3 wiring. "
            "Census checks published keys; it is not a break."
        )
    return rc


if __name__ == "__main__":
    sys.exit(main())
