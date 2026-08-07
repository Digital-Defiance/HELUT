#!/usr/bin/env python3
"""Scrape the WIDER Breaking German Navy Ciphers corpus, beyond the U-534 pages.

Why this exists. `scrape_u534.py` collects two categories ("The U534 messages",
"Unbroken") and filters page names to `^P\\d{7}$`. That filter is why the rest of the
project was invisible to us: the Norrkoeping intercepts are named `PAGE_23_COEW`, and the
Graf Spee / Rasch / Schroeder / Looks / Spanish messages have prose page names. The BGNC
project states it has broken over 70 messages; we were modelling naval register on 48.

That gap matters for one measured reason. `Scripts/lm_margin_probe.py` trained on **4,644
letters** of naval plaintext, and its conclusion ("n-gram order saturates at n=4") is
therefore confounded with a tiny sample. The general-German trigram table already has 28.5M
letters; what is scarce is *register* -- the actual dialect of the target. Every additional
decrypt is register training text. Secondary payoffs: more recovered **daily keys** (the
plugboard is a daily setting, so any same-day key constrains the 47-bit nuisance parameter),
and a larger attested crib catalogue, which only became schedulable once
`Scripts/menu_diagonal_collapse.py` existed.

This writes a SEPARATE fixture. `Fixtures/u534_corpus.json` is load-bearing for the campaign's
controls and the verified `Scripts/enigma_m4.py` round-trip, and must not be perturbed by a
broader scrape.

Provenance and courtesy. Every record keeps its source URL. This is Michael Hoerenberg's
project and these breaks are his and his collaborators' work; the corpus is research input,
not ours, and anything published from it must credit BGNC. The scraper identifies itself and
rate-limits.

    python3 Scripts/scrape_bgnc_wider.py -o Fixtures/bgnc_wider_corpus.json
"""
from __future__ import annotations

import argparse
import html
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

BASE = "https://www.enigma.hoerenberg.com"
USER_AGENT = "HELUT-research/1.0 (Enigma M4 cryptanalysis; contact via repository)"

# Categories carrying message pages. Deliberately excludes the two the U534 scraper owns,
# plus non-message categories (Gallery, Guestbook, Links, Welcome).
CATEGORIES = [
    "Norrk\u00f6ping messages",
    "The Spanish Enigma Message",
    "M4 Project 2006",
    "Reservehandverfahren",
    "Breaking the M4",
]

# Field patterns. The site labels vary between the M4 pages and the Enigma I (Norrkoeping)
# pages, so several spellings are accepted per field. Trailing prose is stripped by bounding
# each capture to the characters the field can legally contain.
FIELDS = {
    "reflector": r"(?:Reflector|Umkehrwalze|UKW)\s*:\s*([A-Za-z]{1,5})",
    "greek": r"(?:Greek|Griechische Walze)\s*:\s*([A-Za-z]+)",
    "wheels": r"(?:Wheels|Wheel Order|Walzenlage)\s*:\s*([0-9IVX]{1,12}(?:[ /-][0-9IVX]{1,4})*)",
    # The Norrkoeping/Enigma I pages label this "Message Key"; the M4 pages use
    # "Wheel positions". Both mean the start position of the wheels.
    "wheel_positions": r"(?:Wheel positions|Message Key|Grundstellung|Start position)"
                       r"\s*:\s*([A-Z]{3,4})",
    "rings": r"(?:Rings|Ring Settings|Ringstellung)\s*:\s*([A-Z]{3,4})",
    "plugs": r"(?:Plugs|Steckerverbindungen|Stecker)\s*:\s*((?:[A-Z]{2}\s+){1,12}[A-Z]{2})",
    "date": r"(\d{1,2}\.\s*(?:January|February|March|April|May|June|July|August|September|"
            r"October|November|December|Januar|Februar|M\u00e4rz|Mai|Juni|Juli|Oktober|"
            r"Dezember)\s*19\d\d)",
}

SKIP_PAGES = {"news", "introduction", "explanation", "publication", "software", "links",
              "welcome", "guestbook", "gallery", "luftwaffe kenngruppen"}


def fetch(url: str, delay: float = 0.5) -> str:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=45) as response:
        raw = response.read()
    time.sleep(delay)
    return raw.decode("utf-8", errors="ignore")


def flatten(markup: str) -> str:
    markup = re.sub(r"(?is)<(script|style).*?</\1>", " ", markup)
    markup = re.sub(r"(?s)<[^>]+>", " ", markup)
    return re.sub(r"\s+", " ", html.unescape(markup))


def letter_blocks(markup: str) -> list[str]:
    """Contiguous runs of 4-5 letter groups, which is how the site renders cipher and plain."""
    text = flatten(markup)
    out = []
    for run in re.findall(r"(?:\b[A-Z]{4,5}\b\s+){6,}", text):
        joined = re.sub(r"[^A-Z]", "", run)
        if len(joined) >= 40:
            out.append(joined)
    return out


def parse_page(page_name: str, markup: str, url: str) -> dict:
    text = flatten(markup)
    record: dict = {"id": page_name, "url": url}

    scan = re.search(r"(P\d{7})_([A-Z]{4})_([A-Z]{4})", markup)
    if scan:
        record["indicators"] = [scan.group(2), scan.group(3)]
    else:
        tag = re.match(r"PAGE_(\d+)_([A-Z]{4,5})", page_name)
        if tag:
            record["indicators"] = [tag.group(2)]

    for field, pattern in FIELDS.items():
        found = re.search(pattern, text)
        if found:
            record[field] = re.sub(r"\s+", " ", found.group(1)).strip()

    # These pages label the streams explicitly and render them as ONE continuous run with no
    # 4-5 letter grouping, so a group-based regex misses them entirely. Prefer the labels.
    # Bound each capture so it cannot run into the following sentence. The streams are a single
    # run of capitals; the next thing on the page is prose like "Picture source and copyright",
    # whose leading capital would otherwise be appended to BOTH streams -- which shows up as a
    # self-encipherment at exactly the last position, since the same stray letter lands on each.
    # Requiring the run to end at a lowercase letter, punctuation, or end-of-text removes it.
    labelled_ct = re.search(
        r"Ciphertext(?:\s*\(without indicator groups\))?\s*:\s*"
        r"([A-Z][A-Z\s]{39,}?)(?=\s*[a-z(:.,]|\s*$)", text)
    labelled_pt = re.search(
        r"Plaintext\s*:\s*([A-Z][A-Z\s]{39,}?)(?=\s*[a-z(:.,]|\s*$)", text)

    blocks = letter_blocks(markup)
    if labelled_ct:
        record["ciphertext"] = re.sub(r"[^A-Z]", "", labelled_ct.group(1))
    elif blocks:
        record["ciphertext"] = blocks[0]
    if record.get("ciphertext"):
        record["length"] = len(record["ciphertext"])

    if labelled_pt:
        record["plaintext"] = re.sub(r"[^A-Z]", "", labelled_pt.group(1))
    elif len(blocks) > 1:
        # Prefer the longest subsequent block; pages sometimes interleave partial-break
        # fragments before the full decrypt.
        record["plaintext"] = max(blocks[1:], key=len)

    record["machine"] = "M4" if record.get("greek") else "EnigmaI"
    record["broken"] = bool(record.get("plaintext")) and bool(record.get("wheel_positions"))
    return record


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("-o", "--out", type=Path, required=True)
    parser.add_argument("--categories", default=None,
                        help="comma-separated override of the category list")
    args = parser.parse_args()

    categories = ([c.strip() for c in args.categories.split(",")]
                  if args.categories else CATEGORIES)

    pages: list[tuple[str, str, str]] = []
    seen: set[str] = set()
    for category in categories:
        index_url = f"{BASE}/index.php?cat={urllib.parse.quote(category)}"
        try:
            index = fetch(index_url)
        except Exception as error:  # noqa: BLE001
            print(f"! index {category}: {error}", file=sys.stderr)
            continue
        for href in re.findall(r'href="([^"]*page=[^"]*)"', index):
            name = urllib.parse.unquote(html.unescape(href).split("page=")[-1]).strip()
            if not name or name.lower() in SKIP_PAGES:
                continue
            key = f"{category}/{name}"
            if key in seen:
                continue
            seen.add(key)
            pages.append((
                name, category,
                f"{BASE}/index.php?cat={urllib.parse.quote(category)}"
                f"&page={urllib.parse.quote(name)}"))

    print(f"discovered {len(pages)} candidate pages across {len(categories)} categories",
          file=sys.stderr)

    records = []
    for name, category, url in sorted(pages):
        try:
            markup = fetch(url)
        except Exception as error:  # noqa: BLE001
            print(f"! {name}: {error}", file=sys.stderr)
            continue
        record = parse_page(name, markup, url)
        record["category"] = category
        if not record.get("ciphertext"):
            continue
        records.append(record)
        flag = "BROKEN" if record["broken"] else "cipher-only"
        print(f"  {category[:22]:22} {name[:30]:30} {record['machine']:8} "
              f"{record.get('length', 0):4} {flag}", file=sys.stderr)

    broken = [r for r in records if r["broken"]]
    args.out.write_text(json.dumps({
        "source": BASE,
        "credit": "Breaking German Navy Ciphers project (Michael Hoerenberg and "
                  "collaborators). Breaks and transcriptions are theirs; this fixture is a "
                  "research-input copy. Any publication must credit BGNC.",
        "note": "Wider BGNC scrape beyond the U-534 pages, collected because "
                "Fixtures/u534_corpus.json supplies only 4,644 letters of naval register and "
                "Scripts/lm_margin_probe.py is confounded by that sample size. Separate from "
                "u534_corpus.json, which is load-bearing for campaign controls.",
        "categories": categories,
        "messages": records,
    }, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    letters = sum(len(re.sub(r"[^A-Z]", "", r.get("plaintext", ""))) for r in broken)
    print(f"\nwrote {args.out}", file=sys.stderr)
    print(f"  messages with ciphertext : {len(records)}", file=sys.stderr)
    print(f"  with a recovered key     : {len(broken)}", file=sys.stderr)
    print(f"  new plaintext letters    : {letters}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
