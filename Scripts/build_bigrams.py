#!/usr/bin/env python3
"""Regenerate the embedded German bigram table in LanguageScorer.swift.

Reads Fixtures/german_corpus.txt and prints the Swift literal for
`LanguageScorer.germanBigramCounts`. Paste the output into
Sources/HELUTCore/LanguageScorer.swift.
"""
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
corpus_path = root / "Fixtures" / "german_corpus.txt"
text = re.sub("[^A-Z]", "", corpus_path.read_text().upper())
if len(text) < 1000:
    sys.exit(f"corpus too small: {len(text)} letters")

counts = [[0] * 26 for _ in range(26)]
for i in range(len(text) - 1):
    counts[ord(text[i]) - 65][ord(text[i + 1]) - 65] += 1

occurrences = {c: text.count(c) for c in set(text)}
ic = sum(v * (v - 1) for v in occurrences.values()) / (len(text) * (len(text) - 1))

print(f"    /// German bigram counts from `Fixtures/german_corpus.txt` "
      f"({len(text)} letters, IC {ic:.4f}).")
print("    /// Row = first letter, column = second letter. "
      "Regenerate with `Scripts/build_bigrams.py`.")
print("    package static let germanBigramCounts: [UInt32] = [")
for r in range(26):
    row = ", ".join(str(counts[r][c]) for c in range(26))
    print(f"        {row},  // {chr(65 + r)}")
print("    ]")
