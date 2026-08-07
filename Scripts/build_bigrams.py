#!/usr/bin/env python3
"""Regenerate the embedded German bigram table in LanguageScorer.swift.

Reads the counted n-gram table at Fixtures/german_bigrams.txt (28.5M-letter
corpus, "GRAM COUNT" lines, same source as Fixtures/german_trigrams.txt) and
prints the Swift literal for `LanguageScorer.germanBigramCounts`. Paste the
output into Sources/HELUTCore/LanguageScorer.swift.

History: this script previously read Fixtures/german_corpus.txt, a 187-line
10,359-letter sample. That left the bigram stage of the staged scorer running on
2,752x less data than the trigram stage, with 235 of 676 cells unobserved and
collapsing onto the add-k floor. See
logs/defect-bigram-stage-starved-20260906T000000Z.md.

`--source` is deliberately required. The `bigrams` source reproduces the
currently shipped dense table. The `corpus` source is retained only to
reproduce the historical sparse table used by old receipts. Requiring the
choice prevents an accidental model swap from invalidating independently
attested bit patterns and calibration reference points.

    python3 Scripts/build_bigrams.py --source bigrams  # reproduce the shipped dense table
    python3 Scripts/build_bigrams.py --source corpus   # reproduce the historical sparse table
"""
import argparse
import re
import sys
from collections import Counter
from pathlib import Path

root = Path(__file__).resolve().parent.parent

parser = argparse.ArgumentParser()
parser.add_argument(
    "--source",
    choices=["bigrams", "corpus"],
    required=True,
    help="bigrams = Fixtures/german_bigrams.txt (28.5M letters, currently shipped); "
    "corpus = Fixtures/german_corpus.txt (historical 10,359-letter sparse table)",
)
args = parser.parse_args()

counts = [[0] * 26 for _ in range(26)]

if args.source == "bigrams":
    path = root / "Fixtures" / "german_bigrams.txt"
    header = ""
    for line in path.read_text().splitlines():
        if line.startswith("#"):
            header = line.lstrip("# ").strip()
            continue
        parts = line.split()
        if len(parts) != 2 or not parts[1].isdigit():
            continue
        gram, count = parts[0].upper(), int(parts[1])
        if len(gram) != 2 or not gram.isalpha():
            continue
        counts[ord(gram[0]) - 65][ord(gram[1]) - 65] = count
    total = sum(sum(row) for row in counts)
    if total < 1_000_000:
        sys.exit(f"bigram table too small: {total} counted pairs")
    letters_match = re.search(r"letters=(\d+)", header)
    ic_match = re.search(r"ic=([\d.]+)", header)
    letters = letters_match.group(1) if letters_match else str(total + 1)
    ic = ic_match.group(1) if ic_match else "unknown"
    provenance = f"`Fixtures/german_bigrams.txt` ({int(letters):,} letters, IC {ic})"
else:
    path = root / "Fixtures" / "german_corpus.txt"
    text = re.sub("[^A-Z]", "", path.read_text().upper())
    if len(text) < 1000:
        sys.exit(f"corpus too small: {len(text)} letters")
    for i in range(len(text) - 1):
        counts[ord(text[i]) - 65][ord(text[i + 1]) - 65] += 1
    occurrences = Counter(text)
    ic = sum(v * (v - 1) for v in occurrences.values()) / (len(text) * (len(text) - 1))
    provenance = f"`Fixtures/german_corpus.txt` ({len(text)} letters, IC {ic:.4f})"

observed = sum(1 for r in range(26) for c in range(26) if counts[r][c] > 0)
missing = [
    chr(65 + r) + chr(65 + c)
    for r in range(26)
    for c in range(26)
    if counts[r][c] == 0
]

print(f"    /// German bigram counts from {provenance}.")
if missing:
    if len(missing) == 1:
        floor_description = missing[0]
    elif len(missing) == 2:
        floor_description = f"{missing[0]} and {missing[1]}"
    else:
        floor_description = f"{len(missing)} cells"
    print(
        f"    /// {observed} of 676 cells observed; "
        f"{floor_description} fall to the row-specific add-k floor."
    )
else:
    print("    /// All 676 cells observed; no cell uses the add-k floor.")
print("    /// Row = first letter, column = second letter.")
print(f"    /// Regenerate with `Scripts/build_bigrams.py --source {args.source}`.")
print("    package static let germanBigramCounts: [UInt32] = [")
for r in range(26):
    row = ", ".join(str(counts[r][c]) for c in range(26))
    print(f"        {row},  // {chr(65 + r)}")
print("    ]")
