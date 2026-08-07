#!/usr/bin/env python3
"""Scrape the U-534 message corpus from enigma.hoerenberg.com into a JSON fixture.

Collects every message page across the "The U534 messages" and "Unbroken"
categories: identifier, indicator groups, ciphertext, plaintext (when broken)
and the recovered daily key.

The indicator groups are taken from the scan filename (P1030684_BDSH_FBFX_WS.jpg),
which is the only reliably-placed source on the page.

Usage:
    Scripts/scrape_u534.py -o Fixtures/u534_corpus.json
"""
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
CATEGORIES = ["The U534 messages", "Unbroken"]
USER_AGENT = "HELUT-research/1.0 (Enigma M4 cryptanalysis; contact via repository)"

FIELDS = {
    "reflector": r"Reflector:\s*([A-Za-z]+)",
    "greek": r"Greek:\s*([A-Za-z]+)",
    "wheels": r"Wheels:\s*([0-9IVX/ ]+)",
    "wheel_positions": r"Wheel positions:\s*([A-Z]{3,4})",
    "rings": r"Rings:\s*([A-Z]{3,4})",
    "plugs": r"Plugs:\s*((?:[A-Z]{2}[ ]?){2,13})",
    "date": r"(\d{1,2}\.\s*(?:January|February|March|April|May|June|July|August|September|October|November|December|Januar|Februar|M\u00e4rz|Mai|Juni|Juli|Oktober|Dezember)\s*19\d\d)",
}


def fetch(url: str, delay: float = 0.4) -> str:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=45) as response:
        raw = response.read()
    time.sleep(delay)
    return raw.decode("utf-8", errors="ignore")


def flatten(markup: str) -> str:
    text = re.sub(r"(?is)<(script|style).*?</\1>", " ", markup)
    text = re.sub(r"(?i)<br\s*/?>", "\n", text)
    text = re.sub(r"(?i)</(p|div|tr|h[1-6]|li|table)>", "\n", text)
    text = re.sub(r"<[^>]+>", " ", text)
    text = html.unescape(text)
    return re.sub(r"[ \t]+", " ", text)


def letter_blocks(markup: str) -> list[str]:
    """Uppercase letter runs inside the two content tables (ciphertext, plaintext)."""
    blocks = []
    for cell in re.findall(r"(?is)<td[^>]*>(.*?)</td>", markup):
        letters = re.sub(r"[^A-Z]", "", re.sub(r"<[^>]+>", " ", cell))
        if len(letters) >= 30:
            blocks.append(letters)
    return blocks


def page_heading(markup: str) -> str:
    found = re.search(r'(?is)<h1[^>]*class="heading1"[^>]*>(.*?)</h1>', markup)
    return html.unescape(re.sub(r"<[^>]+>", "", found.group(1))).strip() if found else ""


def parse_page(page_name: str, markup: str) -> dict:
    text = flatten(markup)
    record: dict = {"id": page_name}

    scan = re.search(r"(P\d{7})_([A-Z]{4})_([A-Z]{4})", markup)
    if scan:
        record["indicators"] = [scan.group(2), scan.group(3)]

    for field, pattern in FIELDS.items():
        found = re.search(pattern, text)
        if found:
            record[field] = found.group(1).strip()

    blocks = letter_blocks(markup)
    if blocks:
        record["ciphertext"] = blocks[0]
        record["length"] = len(blocks[0])
    if len(blocks) > 1:
        record["plaintext"] = blocks[1]

    record["broken"] = "wheel_positions" in record and "plaintext" in record
    return record


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("-o", "--out", type=Path, required=True)
    args = parser.parse_args()

    pages: list[tuple[str, str]] = []
    seen = set()
    for category in CATEGORIES:
        index_url = f"{BASE}/index.php?cat={urllib.parse.quote(category)}"
        try:
            index = fetch(index_url)
        except Exception as error:  # noqa: BLE001
            print(f"! index {category}: {error}", file=sys.stderr)
            continue
        for href in re.findall(r'href="([^"]*page=[^"]*)"', index):
            href = html.unescape(href)
            name = urllib.parse.unquote(href.split("page=")[-1]).strip()
            if not re.match(r"^\s*P\d{7}\s*$", name):
                continue
            name = name.strip()
            if name in seen:
                continue
            seen.add(name)
            pages.append((name, f"{BASE}/index.php?cat={urllib.parse.quote(category)}&page={urllib.parse.quote(name)}"))

    print(f"discovered {len(pages)} message pages", file=sys.stderr)

    records = []
    for index, (name, url) in enumerate(sorted(pages), 1):
        try:
            markup = fetch(url)
        except Exception as error:  # noqa: BLE001
            print(f"! {name}: {error}", file=sys.stderr)
            continue
        # moziloCMS serves a fallback page for unknown page names instead of a 404,
        # so an index link can resolve to an unrelated message. Trust the heading.
        heading = page_heading(markup)
        if not heading.startswith(name):
            print(f"  skip {name}: page served '{heading or 'unknown'}'", file=sys.stderr)
            continue
        record = parse_page(name, markup)
        record["url"] = url
        records.append(record)
        flag = "broken" if record.get("broken") else "UNBROKEN"
        print(f"[{index}/{len(pages)}] {name} len={record.get('length', '?')} {flag}",
              file=sys.stderr)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps({
        "source": BASE,
        "note": "Publicly documented U-534 intercepts (Hörenberg). Scraped for HELUT research.",
        "messages": records,
    }, indent=2), encoding="utf-8")

    broken = sum(1 for r in records if r.get("broken"))
    print(f"\nwrote {args.out}: {len(records)} messages, {broken} broken", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
