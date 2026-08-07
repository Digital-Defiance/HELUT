#!/usr/bin/env python3
"""Validate the wider BGNC scrape before any of it is used as training data.

A scraped plaintext is a *claim*, not evidence. Page layouts vary, labels are inconsistent, and
a greedy regex will happily capture prose as ciphertext. So nothing from
Fixtures/bgnc_wider_corpus.json is trusted until it passes structural checks, and the ones that
pass are written to a separate clean fixture.

Checks, in order of severity:
  1. ciphertext and plaintext are equal length. A mismatch means one stream was mis-captured
     (trailing prose, or a truncated transcript) and the pair cannot be aligned.
  2. no letter enciphers to itself at any position -- Enigma's one absolute law. A single
     self-encipherment proves the two streams are not a genuine cipher/plain pair.
  3. plug list is a legal partial involution: pairs of distinct letters, no letter reused,
     at most 13 pairs. "11 plugs" usually means the regex ate a following word.
  4. language: the register model is GERMAN. The Spanish Enigma message is a real break but
     Spanish plaintext, and would poison a German n-gram table. Flagged, not silently kept.

Only records passing 1-3 and marked German are emitted as usable register text.

    python3 Scripts/validate_bgnc_wider.py
    python3 Scripts/validate_bgnc_wider.py --emit Fixtures/bgnc_register_clean.json
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

# German function words / naval register markers vs Spanish markers. Crude but sufficient to
# separate one Spanish message from a German corpus.
GERMAN = ("VON", "EINS", "NULL", "ZWO", "DREI", "VIER", "UUU", "XXX", "UND", "BERIQT",
          "BERICHT", "UHR", "KLAR", "SCHIFF", "FUNK", "GRUPPE", "GRAD", "NORD", "SUED")
SPANISH = ("ESPANA", "RADIOS", "REGRESAR", "POSIBLE", "CONTESTO", "PRONTO")


def letters(text: str) -> str:
    return re.sub(r"[^A-Z]", "", (text or "").upper())


def plug_problem(plugs: str) -> str | None:
    pairs = [p for p in (plugs or "").split() if p]
    if not pairs:
        return None
    seen: set[str] = set()
    for pair in pairs:
        if len(pair) != 2 or not pair.isalpha():
            return f"malformed pair {pair!r}"
        a, b = pair[0], pair[1]
        if a == b:
            return f"self-plug {pair!r}"
        if a in seen or b in seen:
            return f"letter reused in {pair!r}"
        seen.update((a, b))
    if len(pairs) > 13:
        return f"{len(pairs)} pairs exceeds 13"
    return None


def repair(ct: str, pt: str) -> tuple[str, str, str | None]:
    """Conservatively trim a known scrape artefact, offline and only when it PROVES itself.

    Observed on four Norrkoeping records: a single self-encipherment at exactly the last
    position, index len-1, on pairs that are otherwise clean. Cause is the page rendering the
    stream immediately before prose ("Picture source and copyright"), whose leading capital is
    swept into both captures -- the *same* stray letter lands on each stream, which is why it
    shows up as a self-encipherment and always at the final index.

    The repair is to drop the final character. It is applied only if the result has ZERO
    self-encipherments, so a genuinely bad pair can never be trimmed into looking valid. Any
    other shape is left alone and rejected. No re-fetch is needed: the artefact is a suffix, so
    the correct data is already present in what was scraped.
    """
    def selfenc(a: str, b: str) -> list[int]:
        return [i for i in range(min(len(a), len(b))) if a[i] == b[i]]

    if len(ct) == len(pt):
        bad = selfenc(ct, pt)
        if bad == [len(ct) - 1] and not selfenc(ct[:-1], pt[:-1]):
            return ct[:-1], pt[:-1], "trimmed 1 trailing stray letter from both streams"
        return ct, pt, None

    # Plaintext one longer: a trailing capital captured onto the plain stream only.
    if len(pt) == len(ct) + 1 and not selfenc(ct, pt[:-1]):
        return ct, pt[:-1], "trimmed 1 trailing stray letter from the plaintext"
    if len(ct) == len(pt) + 1 and not selfenc(ct[:-1], pt):
        return ct[:-1], pt, "trimmed 1 trailing stray letter from the ciphertext"
    return ct, pt, None


def classify(plain: str) -> str:
    g = sum(plain.count(w) for w in GERMAN)
    s = sum(plain.count(w) for w in SPANISH)
    if s > g:
        return "spanish"
    return "german" if g else "unknown"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", type=Path, default=Path("Fixtures/bgnc_wider_corpus.json"))
    ap.add_argument("--emit", type=Path, default=None)
    args = ap.parse_args()

    data = json.loads(args.corpus.read_text(encoding="utf-8"))
    keyed = [m for m in data["messages"] if m.get("broken")]

    usable, rejected = [], []
    print(f"{'id':30} {'ct':>4} {'pt':>4} {'lang':>8}  verdict")
    print("-" * 78)
    for rec in keyed:
        ct, pt = letters(rec.get("ciphertext")), letters(rec.get("plaintext"))
        ct, pt, note = repair(ct, pt)
        reasons = []
        if len(ct) != len(pt):
            reasons.append(f"length mismatch ct={len(ct)} pt={len(pt)}")
        else:
            selfenc = [i for i in range(len(ct)) if ct[i] == pt[i]]
            if selfenc:
                reasons.append(f"{len(selfenc)} self-encipherment(s) at {selfenc[:4]}")
        problem = plug_problem(rec.get("plugs", ""))
        if problem:
            reasons.append(f"plugs: {problem}")
        lang = classify(pt)
        if lang != "german":
            reasons.append(f"language={lang}")

        verdict = "USABLE" if not reasons else "; ".join(reasons)
        if note:
            verdict += f"  [{note}]"
        print(f"{rec['id'][:30]:30} {len(ct):>4} {len(pt):>4} {lang:>8}  {verdict}")
        if not reasons:
            # Persist the repaired streams so downstream consumers never see the artefact.
            clean = dict(rec)
            clean["ciphertext"], clean["plaintext"] = ct, pt
            clean["length"] = len(ct)
            if note:
                clean["repair"] = note
            usable.append(clean)
        else:
            rejected.append(rec)

    letters_total = sum(len(letters(r["plaintext"])) for r in usable)
    print()
    print(f"usable German register records : {len(usable)} / {len(keyed)}")
    print(f"usable plaintext letters       : {letters_total}")
    print(f"rejected                       : {len(rejected)}")
    print()
    print("Baseline for comparison: Fixtures/u534_corpus.json supplies 4,644 letters of naval")
    print("register, which is what Scripts/lm_margin_probe.py trained on.")
    if letters_total:
        print(f"This scrape would take that to {4644 + letters_total} "
              f"({100 * letters_total / 4644:.0f}% increase).")

    if args.emit:
        args.emit.write_text(json.dumps({
            "source": data.get("source"),
            "credit": data.get("credit"),
            "note": "Structurally validated subset of the wider BGNC scrape: equal-length "
                    "cipher/plain pairs, zero self-encipherments, legal plug involutions, "
                    "German plaintext only. Emitted by Scripts/validate_bgnc_wider.py.",
            "messages": usable,
        }, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"\nwrote {args.emit}: {len(usable)} validated records")
    return 0 if usable else 1


if __name__ == "__main__":
    sys.exit(main())
