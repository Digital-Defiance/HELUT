#!/usr/bin/env python3
"""Recompute reproducible LanguageScorer calibration reference points.

The model source is explicit so invoking this script cannot silently switch the
production objective. Random baselines use a documented SHA-256 counter stream,
not a runtime-specific PRNG, allowing a separately implemented Ruby audit to
score the exact same 400 x 72-symbol corpus.
"""

import argparse
import hashlib
import json
import math
import platform
import re
import struct
import sys
from collections import Counter
from pathlib import Path

ALPHABET_SIZE = 26
SMOOTHING = 0.5
RANDOM_SAMPLE_COUNT = 400
SAMPLE_LENGTH = 72
RANDOM_DOMAIN = b"HELUT dense bigram calibration v2"
DENSE_FIXTURE_SHA256 = "06f8694ec17906e993223e0179c6ca326030e62f77ec86e5c4120fddcf68f111"
CONTROL_PLAINTEXT_SHA256 = "e355b691e78cd71bc1ed816e0808ab4f18aeb73376008b2a71dced197ad07145"
CONTROL_PLAINTEXT = (
    "VVVUUUVIRSOBENNULEINSXXMITUUUVIRSIBENNULZWOYVIRSIBENNULDREIY"
    "ZWODREISECHSEINSYZWODREIDREIACHTEINSDREIOITNACHWZSTENPASSIRT"
)


class CalibrationError(RuntimeError):
    pass


def require(condition, message):
    if not condition:
        raise CalibrationError(message)


def bit_pattern(value):
    return f"0x{struct.unpack('>Q', struct.pack('>d', value))[0]:016x}"


def dense_counts(path):
    raw = path.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    require(digest == DENSE_FIXTURE_SHA256, f"dense fixture SHA-256 changed: {digest}")
    text = raw.decode("ascii")
    lines = text.splitlines()
    header = re.fullmatch(r"# letters=(\d+) ic=([0-9]+(?:\.[0-9]+)?) distinct=(\d+)", lines[0])
    require(header is not None, "malformed dense fixture header")
    letters, corpus_ic, declared = int(header.group(1)), float(header.group(2)), int(header.group(3))
    require((letters, declared) == (28_508_834, 674), "unexpected dense fixture metadata")

    counts = [[0] * ALPHABET_SIZE for _ in range(ALPHABET_SIZE)]
    seen = set()
    pair_total = 0
    for line_number, line in enumerate(lines[1:], start=2):
        match = re.fullmatch(r"([A-Z]{2}) ([0-9]+)", line)
        require(match is not None, f"malformed dense fixture line {line_number}")
        gram, count_text = match.groups()
        require(gram not in seen, f"duplicate dense gram {gram}")
        count = int(count_text)
        require(count > 0, f"non-positive dense count for {gram}")
        seen.add(gram)
        counts[ord(gram[0]) - 65][ord(gram[1]) - 65] = count
        pair_total += count
    require(len(seen) == declared, "dense parsed/declared entry count mismatch")
    require(pair_total == letters - 1, "dense pair total is not letters - 1")
    require({"JX", "QY"} == {a + b for a in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" for b in "ABCDEFGHIJKLMNOPQRSTUVWXYZ"} - seen,
            "dense missing-cell set changed")
    return counts, corpus_ic, digest


def sparse_counts(path):
    raw = path.read_bytes()
    text = re.sub("[^A-Z]", "", raw.decode("utf-8").upper())
    require(len(text) >= 1_000, f"sparse corpus too small: {len(text)}")
    counts = [[0] * ALPHABET_SIZE for _ in range(ALPHABET_SIZE)]
    for index in range(len(text) - 1):
        counts[ord(text[index]) - 65][ord(text[index + 1]) - 65] += 1
    frequencies = Counter(text)
    corpus_ic = sum(value * (value - 1) for value in frequencies.values()) / (len(text) * (len(text) - 1))
    return counts, corpus_ic, hashlib.sha256(raw).hexdigest()


def log_table(counts):
    result = [[0.0] * ALPHABET_SIZE for _ in range(ALPHABET_SIZE)]
    for row in range(ALPHABET_SIZE):
        row_total = 0
        for column in range(ALPHABET_SIZE):
            row_total += counts[row][column]
        denominator = float(row_total) + SMOOTHING * float(ALPHABET_SIZE)
        for column in range(ALPHABET_SIZE):
            numerator = float(counts[row][column]) + SMOOTHING
            result[row][column] = math.log(numerator / denominator)
    return result


def normalize(text):
    return [ord(character) - 65 for character in re.sub("[^A-Z]", "", text.upper())]


def score(symbols, probabilities):
    if len(symbols) < 2:
        return -10.0
    total = 0.0
    for index in range(len(symbols) - 1):
        total = total + probabilities[symbols[index]][symbols[index + 1]]
    return total / float(len(symbols) - 1)


def index_of_coincidence(symbols):
    if len(symbols) < 2:
        return 0.0
    frequencies = [0] * ALPHABET_SIZE
    for symbol in symbols:
        frequencies[symbol] += 1
    numerator = 0
    for value in frequencies:
        numerator += value * (value - 1)
    return float(numerator) / float(len(symbols) * (len(symbols) - 1))


def reproducible_random_sample(sample_index):
    symbols = []
    block_index = 0
    while len(symbols) < SAMPLE_LENGTH:
        payload = (
            RANDOM_DOMAIN
            + b"\x00"
            + sample_index.to_bytes(4, "big")
            + block_index.to_bytes(4, "big")
        )
        for byte in hashlib.sha256(payload).digest():
            # 234 is the largest multiple of 26 below 256, so rejection leaves
            # every letter with exactly nine byte preimages.
            if byte < 234:
                symbols.append(byte % ALPHABET_SIZE)
                if len(symbols) == SAMPLE_LENGTH:
                    break
        block_index += 1
    return symbols


def symbols_as_ascii(symbols):
    return bytes(symbol + 65 for symbol in symbols)


def calibration_receipt(source, counts, corpus_ic, source_sha256):
    control_bytes = CONTROL_PLAINTEXT.encode("ascii")
    require(hashlib.sha256(control_bytes).hexdigest() == CONTROL_PLAINTEXT_SHA256,
            "control plaintext digest changed")
    reference = normalize(CONTROL_PLAINTEXT)[:SAMPLE_LENGTH]
    require(len(reference) == SAMPLE_LENGTH, "German reference is not exactly 72 symbols")

    probabilities = log_table(counts)
    reference_score = score(reference, probabilities)
    random_samples = [reproducible_random_sample(index) for index in range(RANDOM_SAMPLE_COUNT)]
    random_scores = [score(sample, probabilities) for sample in random_samples]

    random_mean = 0.0
    for value in random_scores:
        random_mean = random_mean + value
    random_mean = random_mean / float(len(random_scores))

    squared_total = 0.0
    for value in random_scores:
        delta = value - random_mean
        squared_total = squared_total + delta * delta
    random_deviation = math.sqrt(squared_total / float(len(random_scores)))

    random_corpus = b"\n".join(symbols_as_ascii(sample) for sample in random_samples) + b"\n"
    reference_ascii = symbols_as_ascii(reference)
    return {
        "schema": "helut.bigram-calibration.v2",
        "implementation": "python-independent-v2",
        "runtime": {
            "python": sys.version.splitlines()[0],
            "platform": platform.platform(),
        },
        "model": {
            "source": source,
            "source_sha256": source_sha256,
            "add_k": SMOOTHING,
            "corpus_ic": corpus_ic,
        },
        "german_reference": {
            "definition": "first 72 symbols of ControlMessageP1030684 plaintext",
            "symbols": len(reference),
            "sha256": hashlib.sha256(reference_ascii).hexdigest(),
            "score_decimal": repr(reference_score),
            "score_bit_pattern": bit_pattern(reference_score),
            "ic_decimal": repr(index_of_coincidence(reference)),
        },
        "random_reference": {
            "generator": "SHA-256(domain || 0x00 || sample-u32be || block-u32be), reject bytes >= 234, byte mod 26",
            "domain_hex": RANDOM_DOMAIN.hex(),
            "samples": RANDOM_SAMPLE_COUNT,
            "symbols_per_sample": SAMPLE_LENGTH,
            "first_sample_sha256": hashlib.sha256(symbols_as_ascii(random_samples[0])).hexdigest(),
            "corpus_sha256": hashlib.sha256(random_corpus).hexdigest(),
            "mean_decimal": repr(random_mean),
            "mean_bit_pattern": bit_pattern(random_mean),
            "population_deviation_decimal": repr(random_deviation),
            "population_deviation_bit_pattern": bit_pattern(random_deviation),
        },
        "swift_constants": {
            "germanMean": float(f"{reference_score:.6f}"),
            "randomMean": float(f"{random_mean:.6f}"),
            "randomDeviation": float(f"{random_deviation:.6f}"),
            "germanIC": float(f"{corpus_ic:.4f}"),
        },
    }


def main():
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", choices=["bigrams", "corpus"], required=True)
    parser.add_argument("--json", action="store_true", help="emit the complete machine-readable receipt")
    parser.add_argument(
        "--score-stdin",
        action="store_true",
        help="after the calibration report, score each non-empty line from stdin",
    )
    args = parser.parse_args()

    if args.source == "bigrams":
        counts, corpus_ic, source_sha256 = dense_counts(root / "Fixtures" / "german_bigrams.txt")
    else:
        counts, corpus_ic, source_sha256 = sparse_counts(root / "Fixtures" / "german_corpus.txt")
    receipt = calibration_receipt(args.source, counts, corpus_ic, source_sha256)

    if args.json:
        print(json.dumps(receipt, indent=2, sort_keys=True))
    else:
        german = receipt["german_reference"]
        random_reference = receipt["random_reference"]
        constants = receipt["swift_constants"]
        print(f"model source      {args.source}  SHA-256 {source_sha256}")
        print(f"German sample     n=72  score {german['score_decimal']}  IC {german['ic_decimal']}")
        print(f"random (n=400x72) mean {random_reference['mean_decimal']}  sd {random_reference['population_deviation_decimal']}")
        print("Swift constants   " + "  ".join(f"{key}={value}" for key, value in constants.items()))

    if args.score_stdin:
        probabilities = log_table(counts)
        for line in sys.stdin:
            symbols = normalize(line.strip())
            if symbols:
                print(f"stdin             n={len(symbols)}  score {score(symbols, probabilities):.6f}  IC {index_of_coincidence(symbols):.6f}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (CalibrationError, OSError, UnicodeError) as error:
        print(f"calibration failed: {error}", file=sys.stderr)
        raise SystemExit(1)
