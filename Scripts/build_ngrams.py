#!/usr/bin/env python3
"""Build German bigram/trigram count fixtures for LanguageScorer.

Enigma traffic has no umlauts or punctuation, so source text is transliterated
(ae/oe/ue/ss) and reduced to A-Z before counting.

Usage:
    Scripts/build_ngrams.py CORPUS [CORPUS ...] [--repeat N:PATH] -o Fixtures/

Each --repeat N:PATH oversamples a corpus N times, which is how the naval
register is weighted against bulk newswire German.

Writes german_bigrams.txt and german_trigrams.txt as "GRAM COUNT" lines.
"""
import argparse
import re
import sys
from collections import Counter
from pathlib import Path

TRANSLITERATION = {
    "Ä": "AE", "Ö": "OE", "Ü": "UE", "ß": "SS",
    "ä": "AE", "ö": "OE", "ü": "UE",
    "É": "E", "È": "E", "Á": "A", "À": "A", "Â": "A", "Ç": "C", "Ñ": "N",
}

NON_LETTER = re.compile("[^A-Z]")


def normalise(raw: str) -> str:
    for source, target in TRANSLITERATION.items():
        raw = raw.replace(source, target)
    return NON_LETTER.sub("", raw.upper())


def read_corpus(path: Path) -> str:
    text = path.read_text(encoding="utf-8", errors="ignore")
    # Leipzig sentence files are "<id>\t<sentence>".
    if "\t" in text[:4096]:
        text = "\n".join(line.split("\t", 1)[-1] for line in text.splitlines())
    return normalise(text)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("corpus", nargs="*", type=Path)
    parser.add_argument("--repeat", action="append", default=[],
                        help="N:PATH — include PATH N times")
    parser.add_argument("-o", "--out", type=Path, required=True)
    args = parser.parse_args()

    chunks = []
    for path in args.corpus:
        chunks.append(read_corpus(path))
    for spec in args.repeat:
        count, _, raw_path = spec.partition(":")
        chunks.extend([read_corpus(Path(raw_path))] * int(count))

    text = "".join(chunks)
    if len(text) < 10_000:
        return f"corpus too small: {len(text)} letters"

    bigrams = Counter(text[i:i + 2] for i in range(len(text) - 1))
    trigrams = Counter(text[i:i + 3] for i in range(len(text) - 2))

    freq = Counter(text)
    ic = sum(v * (v - 1) for v in freq.values()) / (len(text) * (len(text) - 1))

    args.out.mkdir(parents=True, exist_ok=True)
    for name, table in (("german_bigrams.txt", bigrams), ("german_trigrams.txt", trigrams)):
        target = args.out / name
        with target.open("w", encoding="ascii") as handle:
            handle.write(f"# letters={len(text)} ic={ic:.4f} distinct={len(table)}\n")
            for gram, count in sorted(table.items()):
                handle.write(f"{gram} {count}\n")
        print(f"wrote {target} ({len(table)} entries)")

    print(f"letters={len(text)} IC={ic:.4f}")
    print(f"trigram coverage: {len(trigrams)}/17576 "
          f"({100.0 * len(trigrams) / 17576:.1f}%)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
