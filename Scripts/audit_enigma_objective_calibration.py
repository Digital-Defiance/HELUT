#!/usr/bin/env python3
"""Independently calibrate HELUT's 72-symbol Enigma search objective.

This implementation reads the frozen bigram and trigram fixtures directly. It
neither imports nor invokes Swift or the independent Ruby implementation.
"""

import hashlib
import json
import math
import platform
import re
import struct
import sys
from pathlib import Path

WIDTH = 26
ADD_K = 0.5
SAMPLE_LENGTH = 72
SAMPLE_COUNT = 400
STREAM_DOMAIN = b"HELUT dense bigram calibration v2"
BIGRAM_SHA256 = "06f8694ec17906e993223e0179c6ca326030e62f77ec86e5c4120fddcf68f111"
TRIGRAM_SHA256 = "e08a56593d1e74b88d300e35b18dd504bc5fffef8ae03db51d72e6270e9509d7"
BIGRAM_MODEL_ID = "helut-german-bigram-add-k-0.5-06f8694e-v2"
TRIGRAM_MODEL_ID = "helut-german-trigram-add-k-0.5-e08a5659-v1"
OBJECTIVE_MODEL_ID = "helut-enigma-search-n72-correlation-discounted-z-06f8694e-e08a5659-v2"
CONTROL = (
    "VVVUUUVIRSOBENNULEINSXXMITUUUVIRSIBENNULZWOYVIRSIBENNULDREIY"
    "ZWODREISECHSEINSYZWODREIDREIACHTEINSDREIOITNACHWZSTENPASSIRT"
)
DENSE_RECOVERED_NONSENSE = (
    "LLLWOHLARGULATTUSZITSPAMIROOOLOSTIKETTOLZFFNLIKDIBAKRJLDNRITZAUDHEMZEKKS"
)
ATTACK_CRIBS = (
    "EINS", "ZWO", "DREI", "NULL", "VIER", "FUENF", "SECHS", "ACHT", "NEUN",
    "WETTER", "CHEF", "UBOOT", "MELDUNG", "MARINE", "QUADRAT", "KURS", "FEIND",
    "BOOT", "STANDORT", "ANGRIFF", "VONVON",
)
GERMAN_IC = 0.0747
IC_PENALTY_SCALE = 8.0
CRIB_BONUS = 0.05


class AuditFailure(RuntimeError):
    pass


def require(condition, message):
    if not condition:
        raise AuditFailure(message)


def bit_pattern(value):
    return f"0x{struct.unpack('>Q', struct.pack('>d', value))[0]:016x}"


def rounded_six(value):
    return float(f"{value:.6f}")


def parse_fixture(path, order, expected_sha, expected_entries):
    raw = path.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    require(digest == expected_sha, f"{path.name} SHA-256 changed: {digest}")
    lines = raw.decode("ascii").splitlines()
    header = re.fullmatch(r"# letters=(\d+) ic=([0-9]+(?:\.[0-9]+)?) distinct=(\d+)", lines[0])
    require(header is not None, f"malformed {path.name} header")
    letters = int(header.group(1))
    corpus_ic = float(header.group(2))
    declared = int(header.group(3))
    require((letters, corpus_ic, declared) == (28_508_834, 0.0747, expected_entries),
            f"unexpected {path.name} metadata")

    contexts = WIDTH ** (order - 1)
    table_size = contexts * WIDTH
    counts = [0] * table_size
    seen = set()
    window_total = 0
    pattern = re.compile(rf"([A-Z]{{{order}}}) ([0-9]+)")
    for line_number, line in enumerate(lines[1:], start=2):
        match = pattern.fullmatch(line)
        require(match is not None, f"malformed {path.name} line {line_number}")
        gram, count_text = match.groups()
        require(gram not in seen, f"duplicate {path.name} gram {gram}")
        count = int(count_text)
        require(count > 0, f"non-positive {path.name} count for {gram}")
        index = 0
        for character in gram:
            index = index * WIDTH + ord(character) - 65
        counts[index] = count
        seen.add(gram)
        window_total += count
    require(len(seen) == declared, f"{path.name} parsed/declared count mismatch")
    require(window_total == letters - order + 1,
            f"{path.name} total is not letters - order + 1")

    probabilities = [0.0] * table_size
    for context in range(contexts):
        row_start = context * WIDTH
        row_total = 0
        for symbol in range(WIDTH):
            row_total += counts[row_start + symbol]
        denominator = float(row_total) + ADD_K * float(WIDTH)
        for symbol in range(WIDTH):
            probabilities[row_start + symbol] = math.log(
                (float(counts[row_start + symbol]) + ADD_K) / denominator
            )
    return {
        "probabilities": probabilities,
        "sha256": digest,
        "letters": letters,
        "corpus_ic": corpus_ic,
        "observed_entries": len(seen),
        "window_total": window_total,
    }


def score(symbols, probabilities, order):
    if len(symbols) < order:
        return -10.0
    total = 0.0
    for start in range(len(symbols) - order + 1):
        index = 0
        for offset in range(order):
            index = index * WIDTH + symbols[start + offset]
        total = total + probabilities[index]
    return total / float(len(symbols) - order + 1)


def index_of_coincidence(symbols):
    if len(symbols) < 2:
        return 0.0
    frequencies = [0] * WIDTH
    for symbol in symbols:
        frequencies[symbol] += 1
    numerator = 0
    for frequency in frequencies:
        numerator += frequency * (frequency - 1)
    return float(numerator) / float(len(symbols) * (len(symbols) - 1))


def attack_score(symbols, bigram_score):
    text = bytes(symbol + 65 for symbol in symbols).decode("ascii")
    score_value = bigram_score - abs(index_of_coincidence(symbols) - GERMAN_IC) * IC_PENALTY_SCALE
    for crib in ATTACK_CRIBS:
        if crib in text:
            score_value += CRIB_BONUS
    return score_value


def deterministic_sample(sample_index):
    symbols = []
    block_index = 0
    while len(symbols) < SAMPLE_LENGTH:
        payload = (
            STREAM_DOMAIN
            + b"\x00"
            + sample_index.to_bytes(4, "big")
            + block_index.to_bytes(4, "big")
        )
        for byte in hashlib.sha256(payload).digest():
            if byte < 234:
                symbols.append(byte % WIDTH)
                if len(symbols) == SAMPLE_LENGTH:
                    break
        block_index += 1
    return symbols


def population_stats(values):
    total = 0.0
    for value in values:
        total = total + value
    mean = total / float(len(values))
    squared_total = 0.0
    for value in values:
        delta = value - mean
        squared_total = squared_total + delta * delta
    return mean, math.sqrt(squared_total / float(len(values)))


def metric(value):
    return {"decimal": repr(value), "bit_pattern": bit_pattern(value)}


def main():
    root = Path(__file__).resolve().parent.parent
    bigram = parse_fixture(
        root / "Fixtures" / "german_bigrams.txt", 2, BIGRAM_SHA256, 674
    )
    trigram = parse_fixture(
        root / "Fixtures" / "german_trigrams.txt", 3, TRIGRAM_SHA256, 14_947
    )
    require(bigram["letters"] == trigram["letters"], "fixture letter totals differ")
    require(bigram["corpus_ic"] == trigram["corpus_ic"], "fixture IC values differ")

    reference = [ord(character) - 65 for character in CONTROL[:SAMPLE_LENGTH]]
    recovered = [ord(character) - 65 for character in DENSE_RECOVERED_NONSENSE]
    require(len(reference) == SAMPLE_LENGTH, "reference is not 72 symbols")
    require(len(recovered) == SAMPLE_LENGTH, "recovered control is not 72 symbols")

    samples = [deterministic_sample(index) for index in range(SAMPLE_COUNT)]
    random_corpus = b"\n".join(bytes(symbol + 65 for symbol in sample) for sample in samples) + b"\n"
    bigram_scores = [score(sample, bigram["probabilities"], 2) for sample in samples]
    trigram_scores = [score(sample, trigram["probabilities"], 3) for sample in samples]
    attack_scores = [
        attack_score(sample, bigram_value)
        for sample, bigram_value in zip(samples, bigram_scores)
    ]
    bigram_mean, bigram_deviation = population_stats(bigram_scores)
    trigram_mean, trigram_deviation = population_stats(trigram_scores)
    attack_mean, attack_deviation = population_stats(attack_scores)

    covariance_total = 0.0
    for attack_value, trigram_value in zip(attack_scores, trigram_scores):
        covariance_total = covariance_total + (
            (attack_value - attack_mean) * (trigram_value - trigram_mean)
        )
    covariance = covariance_total / float(SAMPLE_COUNT)
    correlation = covariance / (attack_deviation * trigram_deviation)
    production_correlation = rounded_six(correlation)
    trigram_weight = rounded_six(1.0 - production_correlation)

    attack_constants = {
        "randomMean": rounded_six(attack_mean),
        "randomDeviation": rounded_six(attack_deviation),
    }
    trigram_constants = {
        "germanMean": rounded_six(score(reference, trigram["probabilities"], 3)),
        "randomMean": rounded_six(trigram_mean),
        "randomDeviation": rounded_six(trigram_deviation),
    }

    def objective(symbols):
        bigram_value = score(symbols, bigram["probabilities"], 2)
        trigram_value = score(symbols, trigram["probabilities"], 3)
        attack_value = attack_score(symbols, bigram_value)
        attack_component = (
            (attack_value - attack_constants["randomMean"])
            / attack_constants["randomDeviation"]
        )
        trigram_component = (
            (trigram_value - trigram_constants["randomMean"])
            / trigram_constants["randomDeviation"]
        )
        return (
            attack_component + trigram_weight * trigram_component
        ) / (1.0 + trigram_weight)

    random_objectives = [objective(sample) for sample in samples]
    objective_mean, objective_deviation = population_stats(random_objectives)

    def candidate_record(symbols):
        bigram_value = score(symbols, bigram["probabilities"], 2)
        trigram_value = score(symbols, trigram["probabilities"], 3)
        return {
            "sha256": hashlib.sha256(bytes(symbol + 65 for symbol in symbols)).hexdigest(),
            "bigram": metric(bigram_value),
            "trigram": metric(trigram_value),
            "index_of_coincidence": metric(index_of_coincidence(symbols)),
            "attack_score": metric(attack_score(symbols, bigram_value)),
            "objective": metric(objective(symbols)),
        }

    receipt = {
        "schema": "helut.enigma-objective-calibration.v2",
        "implementation": "python-independent-v2",
        "runtime": {
            "python": sys.version.splitlines()[0],
            "platform": platform.platform(),
        },
        "models": {
            "bigram": {
                "model_id": BIGRAM_MODEL_ID,
                "source_sha256": bigram["sha256"],
                "order": 2,
                "add_k": ADD_K,
                "observed_entries": bigram["observed_entries"],
                "window_total": bigram["window_total"],
            },
            "trigram": {
                "model_id": TRIGRAM_MODEL_ID,
                "source_sha256": trigram["sha256"],
                "order": 3,
                "add_k": ADD_K,
                "observed_entries": trigram["observed_entries"],
                "window_total": trigram["window_total"],
            },
        },
        "controls": {
            "generator": "SHA-256(domain || 0x00 || sample-u32be || block-u32be), reject bytes >= 234, byte mod 26",
            "domain_hex": STREAM_DOMAIN.hex(),
            "samples": SAMPLE_COUNT,
            "symbols_per_sample": SAMPLE_LENGTH,
            "first_sample_sha256": hashlib.sha256(
                bytes(symbol + 65 for symbol in samples[0])
            ).hexdigest(),
            "corpus_sha256": hashlib.sha256(random_corpus).hexdigest(),
        },
        "bigram_calibration": {
            "german": metric(score(reference, bigram["probabilities"], 2)),
            "random_mean": metric(bigram_mean),
            "random_population_deviation": metric(bigram_deviation),
        },
        "attack_calibration": {
            "german": metric(
                attack_score(reference, score(reference, bigram["probabilities"], 2))
            ),
            "random_mean": metric(attack_mean),
            "random_population_deviation": metric(attack_deviation),
            "swift_constants": attack_constants,
        },
        "trigram_calibration": {
            "german": metric(score(reference, trigram["probabilities"], 3)),
            "random_mean": metric(trigram_mean),
            "random_population_deviation": metric(trigram_deviation),
            "swift_constants": trigram_constants,
        },
        "attack_trigram_relationship": {
            "covariance": metric(covariance),
            "correlation": metric(correlation),
        },
        "objective": {
            "model_id": OBJECTIVE_MODEL_ID,
            "definition": "(attackZ + trigramWeight * trigramZ) / (1 + trigramWeight)",
            "attack_score_definition": "bigram - 8 * abs(IC - 0.0747) + 0.05 per matched configured crib",
            "correlation_discount_definition": "trigramWeight is the six-decimal non-shared fraction 1 - attack/trigram rho",
            "uses_rounded_production_constants": True,
            "attack_trigram_correlation": production_correlation,
            "trigram_weight": trigram_weight,
            "attack_constants": attack_constants,
            "trigram_constants": trigram_constants,
            "random_mean": metric(objective_mean),
            "random_population_deviation": metric(objective_deviation),
            "german_reference": candidate_record(reference),
            "dense_recovered_nonsense": candidate_record(recovered),
        },
    }
    print(json.dumps(receipt, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AuditFailure, OSError, UnicodeError, ValueError) as error:
        print(f"objective calibration failed: {error}", file=sys.stderr)
        raise SystemExit(1)
