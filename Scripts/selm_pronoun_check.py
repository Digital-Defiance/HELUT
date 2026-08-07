#!/usr/bin/env python3
"""Windowed pronoun / attribution check around every Selm Merel Wenselaers reference.

The campaign ledger, the public journal and the report all credit a named human
contributor. Three things go wrong when agents edit those surfaces:

  1. a pronoun drifts to the wrong person (``he``, ``they``) for a named woman;
  2. a pronoun binds to the nearest *other* proper noun (Hoerenberg, Girard,
     HELUT) instead of to her, which silently reassigns the finding;
  3. her source-reported evidence gets promoted to repo-verified voice
     ("proves", "confirms") when the ledger holds it one grade lower.

This script does not rewrite anything. It prints a window around every mention
and flags the three classes so a human can adjudicate. Exit status is 1 if any
hard flag fires, so it can gate a commit.

Usage:
    python3 Scripts/selm_pronoun_check.py [--window N] [--quiet]
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# Files we actually assert about. Generated artifacts are checked read-only
# (writeup.md, site/dist) because a mismatch there means the source is stale.
GENERATED = {"writeup.md", "site/dist"}

SUBJECT = re.compile(r"\b(Selm|Merel|Wenselaers)\b")

# Pronouns that are correct for her.
OK_PRONOUN = re.compile(r"\b(she|her|hers|herself|She|Her|Hers|Herself)\b")
# Masculine pronouns are unambiguously wrong for a named woman and have no
# non-personal reading, so they are always HARD.
MASC_PRONOUN = re.compile(r"\b([Hh]e|[Hh]im|[Hh]is|[Hh]imself)\b")
# Plural-personal pronouns are wrong for one person, but "they/them/their" also
# has a legitimate neuter reading (menus, lists, candidates). Flagged only when
# the antecedent resolves to her with no competing plural noun.
PLURAL_PRONOUN = re.compile(r"\b([Tt]hey|[Tt]hem|[Tt]heir|[Tt]heirs|"
                            r"[Tt]hemselves)\b")
# Neuter pronouns almost always bind to a document/finding here; kept only for
# an optional low-severity pass, never HARD.
NEUTER_PRONOUN = re.compile(r"\b([Ii]t|[Ii]ts|[Ii]tself)\b")

# Other proper nouns a pronoun could legitimately bind to. If one of these sits
# between the subject mention and the pronoun, binding is ambiguous, not wrong.
COMPETING = re.compile(
    r"\b(H[oö]erenberg|Girard|HELUT|Dönitz|Donitz|Thetis|Potsdam|Plaice|"
    r"Regenbogen|Hannibal|Ostwald|Weierud|Welchman|Turing|U-?534|U-?3024|"
    r"U-?2538|Kriegsmarine|Zuteilungsliste|Schlüsseltafel|Enigma|Bletchley)\b")

# Repo-verified voice. Applied to her *source-reported* material this overstates
# the grade; the ledger's rule is that provenance and mechanics are separate
# gates (Phase 55.4).
PROMOTION = re.compile(
    r"\b(prove[sd]?|proven|confirm(?:s|ed)?|establishe[sd]|demonstrate[sd]?|"
    r"verified|validates?|shows conclusively|settles?)\b")

# Hedges that correctly mark source-reported grade.
HEDGE = re.compile(
    r"\b(reported|source-reported|attested|pending|held at|unverified|"
    r"independently flagged|supplied|claims?|suggests?|indicates?|"
    r"plausibl[ey]|open|hypothesis|not established|provisional|"
    r"awaiting|per her|according to)\b")


def tracked_files() -> list[Path]:
    out = subprocess.run(
        ["git", "grep", "-lI", "-e", "Wenselaers", "-e", "Selm", "-e", "Merel"],
        cwd=REPO, capture_output=True, text=True)
    files = [REPO / line for line in out.stdout.split() if line]
    # Untracked fixtures still matter.
    extra = subprocess.run(
        ["git", "ls-files", "--others", "--exclude-standard"],
        cwd=REPO, capture_output=True, text=True)
    for line in extra.stdout.split():
        path = REPO / line
        if path.suffix in {".md", ".tex", ".tsx", ".ts", ".json", ".py"}:
            try:
                if SUBJECT.search(path.read_text(errors="replace")):
                    files.append(path)
            except OSError:
                pass
    return sorted(set(files))


def rel(path: Path) -> str:
    try:
        return str(path.relative_to(REPO))
    except ValueError:
        return str(path)


def is_generated(path: Path) -> bool:
    name = rel(path)
    return any(name == g or name.startswith(g + "/") for g in GENERATED)


def sentences(text: str) -> list[tuple[int, str]]:
    """Split into sentence-ish spans, carrying the absolute offset of each."""
    spans, start = [], 0
    for match in re.finditer(r"(?<=[.!?;:])\s+|\n\n+|\n(?=[-|#*])", text):
        spans.append((start, text[start:match.start()]))
        start = match.end()
    spans.append((start, text[start:]))
    return [(off, chunk) for off, chunk in spans if chunk.strip()]


def line_of(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def check_file(path: Path, window: int) -> list[dict]:
    try:
        text = path.read_text(errors="replace")
    except OSError:
        return []
    findings = []
    spans = sentences(text)

    for index, (offset, chunk) in enumerate(spans):
        if not SUBJECT.search(chunk):
            continue
        # Window: the sentence with the mention plus the following `window`
        # sentences, which is where a drifting pronoun lands.
        tail = spans[index + 1: index + 1 + window]
        scope = [(offset, chunk)] + tail

        for scope_offset, scope_chunk in scope:
            own_mention = bool(SUBJECT.search(scope_chunk))

            def antecedent_is_her(match: re.Match) -> tuple[bool, bool]:
                """(binds_to_her, competing_noun_intervenes) for a pronoun."""
                before = scope_chunk[:match.start()]
                last_subject = None
                for sub in SUBJECT.finditer(before):
                    last_subject = sub.end()
                if last_subject is None:
                    if own_mention:
                        # Her name appears only after the pronoun in this
                        # sentence — the pronoun looks back to something else.
                        return (False, False)
                    # Trailing sentence: antecedent is the earlier mention
                    # unless a competing noun sits before the pronoun here.
                    return (True, bool(COMPETING.search(before)))
                return (True, bool(COMPETING.search(before, last_subject)))

            # Masculine pronouns: wrong for her whenever they bind to her, and
            # a competing noun only downgrades to AMBIGUOUS, never clears it,
            # because there is no correct masculine reading of her name.
            for match in MASC_PRONOUN.finditer(scope_chunk):
                binds, competing = antecedent_is_her(match)
                if not binds:
                    continue
                findings.append({
                    "file": rel(path),
                    "line": line_of(text, scope_offset + match.start()),
                    "kind": "pronoun",
                    "severity": "AMBIGUOUS" if competing else "HARD",
                    "token": match.group(0),
                    "note": ("masculine pronoun with a competing antecedent — "
                             "confirm it is not her" if competing
                             else "masculine pronoun binds to her name"),
                    "text": " ".join(scope_chunk.split())[:300],
                })

            # Plural-personal pronouns: flag only when they bind to her with no
            # competing plural/collective noun. A competing noun is the normal,
            # correct case (menus/lists/candidates) and is dropped.
            for match in PLURAL_PRONOUN.finditer(scope_chunk):
                binds, competing = antecedent_is_her(match)
                if not binds or competing:
                    continue
                findings.append({
                    "file": rel(path),
                    "line": line_of(text, scope_offset + match.start()),
                    "kind": "pronoun", "severity": "AMBIGUOUS",
                    "token": match.group(0),
                    "note": "plural pronoun may refer to one person (her)",
                    "text": " ".join(scope_chunk.split())[:300],
                })

        # Grade check: repo-verified voice in the same sentence as her name,
        # with no hedge anywhere in the window.
        window_text = " ".join(c for _, c in scope)
        if PROMOTION.search(chunk) and not HEDGE.search(window_text):
            match = PROMOTION.search(chunk)
            findings.append({
                "file": rel(path), "line": line_of(text, offset + match.start()),
                "kind": "grade", "severity": "REVIEW",
                "token": match.group(0),
                "note": "repo-verified voice near her name with no hedge in window",
                "text": " ".join(chunk.split())[:300],
            })

    return findings


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--window", type=int, default=2,
                        help="sentences after the mention to scan (default 2)")
    parser.add_argument("--quiet", action="store_true",
                        help="only print flags, not the per-file mention count")
    args = parser.parse_args()

    files = tracked_files()
    all_findings, mentions = [], 0
    for path in files:
        try:
            mentions += len(SUBJECT.findall(path.read_text(errors="replace")))
        except OSError:
            pass
        found = check_file(path, args.window)
        if is_generated(path):
            for item in found:
                item["severity"] = "GENERATED"
        all_findings.extend(found)

    if not args.quiet:
        print(f"scanned {len(files)} files, {mentions} subject mentions, "
              f"window={args.window} sentences")
        for path in files:
            tag = " (generated)" if is_generated(path) else ""
            print(f"  - {rel(path)}{tag}")
        print()

    order = {"HARD": 0, "AMBIGUOUS": 1, "REVIEW": 2, "GENERATED": 3}
    all_findings.sort(key=lambda f: (order.get(f["severity"], 9), f["file"],
                                     f["line"]))

    hard = [f for f in all_findings if f["severity"] == "HARD"]
    for item in all_findings:
        print(f"[{item['severity']}] {item['file']}:{item['line']} "
              f"({item['kind']}: '{item['token']}') — {item['note']}")
        print(f"    {item['text']}")
        print()

    counts: dict[str, int] = {}
    for item in all_findings:
        counts[item["severity"]] = counts.get(item["severity"], 0) + 1
    print("summary: " + (", ".join(f"{k}={v}" for k, v in sorted(counts.items()))
                         or "no flags"))
    return 1 if hard else 0


if __name__ == "__main__":
    sys.exit(main())
