#!/usr/bin/env python3
"""Measure the reference points in LanguageScorer.Calibration.

Reports mean bigram log-probability for German plaintext, random letters, and any
text passed on stdin, so that a "possible break" threshold can be set from data
rather than guessed.
"""
import math
import random
import re
import sys
from collections import Counter
from pathlib import Path

root = Path(__file__).resolve().parent.parent
corpus = re.sub("[^A-Z]", "", (root / "Fixtures" / "german_corpus.txt").read_text().upper())

counts = [[0] * 26 for _ in range(26)]
for i in range(len(corpus) - 1):
    counts[ord(corpus[i]) - 65][ord(corpus[i + 1]) - 65] += 1

SMOOTHING = 0.5
logprob = [[0.0] * 26 for _ in range(26)]
for r in range(26):
    total = sum(counts[r]) + SMOOTHING * 26
    for c in range(26):
        logprob[r][c] = math.log((counts[r][c] + SMOOTHING) / total)


def score(text):
    text = re.sub("[^A-Z]", "", text.upper())
    if len(text) < 2:
        return -10.0
    pairs = (logprob[ord(text[i]) - 65][ord(text[i + 1]) - 65] for i in range(len(text) - 1))
    return sum(pairs) / (len(text) - 1)


def index_of_coincidence(text):
    text = re.sub("[^A-Z]", "", text.upper())
    n = len(text)
    if n < 2:
        return 0.0
    return sum(v * (v - 1) for v in Counter(text).values()) / (n * (n - 1))


GERMAN_SAMPLE = ("VVVUUUVIRSOBENNULEINSXXMITUUUVIRSIBENNULZWOYVIRSIBENNUL"
                 "DREIYZWODREISECHSEINS")

random.seed(1)
samples = ["".join(random.choice("ABCDEFGHIJKLMNOPQRSTUVWXYZ") for _ in range(72))
           for _ in range(400)]
random_scores = [score(s) for s in samples]
random_mean = sum(random_scores) / len(random_scores)
random_sd = (sum((v - random_mean) ** 2 for v in random_scores) / len(random_scores)) ** 0.5

print(f"corpus (self)   score {score(corpus):.3f}  IC {index_of_coincidence(corpus):.4f}")
print(f"German sample   score {score(GERMAN_SAMPLE):.3f}  IC {index_of_coincidence(GERMAN_SAMPLE):.4f}")
print(f"random (n=400)  score {random_mean:.3f}  sd {random_sd:.3f}")

for line in sys.stdin:
    line = line.strip()
    if line:
        print(f"stdin           score {score(line):.3f}  IC {index_of_coincidence(line):.4f}")
