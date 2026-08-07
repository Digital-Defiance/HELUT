#!/usr/bin/env python3
"""Independently attest the dense German-bigram P1030684 receipt.

This read-only program intentionally does not import HELUT code or generated Swift
constants. It parses the committed counted-bigram fixture, reconstructs the
row-normalized add-0.5 model, and scores the frozen 120-symbol control with an
explicit binary64 left fold. The numeric IEEE-754 patterns are written to stdout
for comparison with a separately implemented Ruby audit and Swift under test.
"""

import argparse
import hashlib
import json
import math
import platform
import re
import struct
import sys
from pathlib import Path

ALPHABET_SIZE = 26
ADD_K = 0.5
EXPECTED_FIXTURE_SHA256 = (
    "06f8694ec17906e993223e0179c6ca326030e62f77ec86e5c4120fddcf68f111"
)
EXPECTED_LETTERS = 28_508_834
EXPECTED_DISTINCT = 674
EXPECTED_MISSING = ("JX", "QY")
EXPECTED_PLAINTEXT_SHA256 = (
    "e355b691e78cd71bc1ed816e0808ab4f18aeb73376008b2a71dced197ad07145"
)
CONTROL_PLAINTEXT = (
    "VVVUUUVIRSOBENNULEINSXXMITUUUVIRSIBENNULZWOYVIRSIBENNULDREIY"
    "ZWODREISECHSEINSYZWODREIDREIACHTEINSDREIOITNACHWZSTENPASSIRT"
)
HEADER_PATTERN = re.compile(
    r"# letters=(\d+) ic=([0-9]+(?:\.[0-9]+)?) distinct=(\d+)"
)
ENTRY_PATTERN = re.compile(r"([A-Z]{2}) ([0-9]+)")


class AuditError(RuntimeError):
    """The frozen audit input or protocol did not satisfy an invariant."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AuditError(message)


def binary64_bits(value: float) -> str:
    numeric_bits = struct.unpack(">Q", struct.pack(">d", value))[0]
    return f"0x{numeric_bits:016x}"


def parse_fixture(path: Path):
    raw = path.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    require(
        digest == EXPECTED_FIXTURE_SHA256,
        f"fixture SHA-256 changed: expected {EXPECTED_FIXTURE_SHA256}, got {digest}",
    )

    try:
        text = raw.decode("ascii")
    except UnicodeDecodeError as error:
        raise AuditError("fixture is not strict ASCII") from error

    lines = text.splitlines()
    require(bool(lines), "fixture is empty")
    header_match = HEADER_PATTERN.fullmatch(lines[0])
    require(header_match is not None, "fixture metadata header is malformed")
    letters = int(header_match.group(1))
    ic_text = header_match.group(2)
    declared_distinct = int(header_match.group(3))

    entries = {}
    lexical_order = []
    for line_number, line in enumerate(lines[1:], start=2):
        require(bool(line), f"blank line at fixture line {line_number}")
        match = ENTRY_PATTERN.fullmatch(line)
        require(match is not None, f"malformed fixture line {line_number}: {line!r}")
        gram, count_text = match.groups()
        require(gram not in entries, f"duplicate gram {gram} at fixture line {line_number}")
        count = int(count_text)
        require(count > 0, f"non-positive observed count for {gram}")
        require(count <= 0xFFFF_FFFF, f"count for {gram} exceeds Swift UInt32")
        entries[gram] = count
        lexical_order.append(gram)

    require(lexical_order == sorted(lexical_order), "fixture entries are not lexical")
    require(letters == EXPECTED_LETTERS, f"unexpected letters metadata: {letters}")
    require(
        declared_distinct == EXPECTED_DISTINCT,
        f"unexpected distinct metadata: {declared_distinct}",
    )
    require(
        len(entries) == declared_distinct,
        f"metadata says {declared_distinct} entries but parsed {len(entries)}",
    )

    expected_grams = {
        chr(65 + first) + chr(65 + second)
        for first in range(ALPHABET_SIZE)
        for second in range(ALPHABET_SIZE)
    }
    missing = tuple(sorted(expected_grams.difference(entries)))
    require(missing == EXPECTED_MISSING, f"unexpected missing grams: {missing}")

    counted_pairs = 0
    for count in entries.values():
        counted_pairs += count
    require(
        counted_pairs == letters - 1,
        f"pair total {counted_pairs} does not equal letters - 1 ({letters - 1})",
    )

    counts = [0] * (ALPHABET_SIZE * ALPHABET_SIZE)
    for gram, count in entries.items():
        first = ord(gram[0]) - 65
        second = ord(gram[1]) - 65
        counts[first * ALPHABET_SIZE + second] = count

    return counts, {
        "sha256": digest,
        "letters": letters,
        "ic": ic_text,
        "declared_distinct": declared_distinct,
        "parsed_distinct": len(entries),
        "counted_pairs": counted_pairs,
        "missing": list(missing),
    }


def build_log_probabilities(counts):
    log_probabilities = [0.0] * len(counts)
    for first in range(ALPHABET_SIZE):
        row_total = 0
        row_offset = first * ALPHABET_SIZE
        for second in range(ALPHABET_SIZE):
            row_total += counts[row_offset + second]
        denominator = float(row_total) + ADD_K * float(ALPHABET_SIZE)
        for second in range(ALPHABET_SIZE):
            numerator = float(counts[row_offset + second]) + ADD_K
            log_probabilities[row_offset + second] = math.log(numerator / denominator)
    return log_probabilities


def score_control(counts, log_probabilities):
    plaintext_bytes = CONTROL_PLAINTEXT.encode("ascii")
    plaintext_digest = hashlib.sha256(plaintext_bytes).hexdigest()
    require(
        plaintext_digest == EXPECTED_PLAINTEXT_SHA256,
        f"control plaintext changed: {plaintext_digest}",
    )
    require(len(plaintext_bytes) == 120, f"control length is {len(plaintext_bytes)}, not 120")

    total = 0.0
    indices = []
    floor_window_starts = []
    for start in range(len(plaintext_bytes) - 1):
        first = plaintext_bytes[start] - 65
        second = plaintext_bytes[start + 1] - 65
        require(0 <= first < 26 and 0 <= second < 26, "control contains a non-A-Z byte")
        table_index = first * ALPHABET_SIZE + second
        indices.append(table_index)
        if counts[table_index] == 0:
            floor_window_starts.append(start)
        total = total + log_probabilities[table_index]

    windows = len(indices)
    require(windows == 119, f"control produced {windows} windows, not 119")
    mean = total / float(windows)
    return {
        "plaintext_sha256": plaintext_digest,
        "symbols": len(plaintext_bytes),
        "windows": windows,
        "first_index": indices[0],
        "last_index": indices[-1],
        "floor_window_starts": floor_window_starts,
    }, total, mean


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--fixture",
        type=Path,
        default=root / "Fixtures" / "german_bigrams.txt",
        help="counted bigram fixture to attest (default: repository dense fixture)",
    )
    args = parser.parse_args()

    counts, fixture_receipt = parse_fixture(args.fixture.resolve())
    log_probabilities = build_log_probabilities(counts)
    control_receipt, total, mean = score_control(counts, log_probabilities)

    receipt = {
        "schema": "helut.dense-bigram-audit.v1",
        "implementation": "python-independent-v1",
        "runtime": {
            "python": sys.version.splitlines()[0],
            "platform": platform.platform(),
            "architecture": platform.machine(),
        },
        "fixture": fixture_receipt,
        "control": control_receipt,
        "scoring": {
            "layout": "row-major A-Z conditional bigrams",
            "add_k": ADD_K,
            "logarithm": "natural",
            "accumulation": "explicit left fold from +0.0",
            "mean_denominator": control_receipt["windows"],
        },
        "result": {
            "total_decimal": repr(total),
            "mean_decimal": repr(mean),
            "total_bit_pattern": binary64_bits(total),
            "mean_bit_pattern": binary64_bits(mean),
        },
    }
    print(json.dumps(receipt, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AuditError, OSError) as error:
        print(f"dense-bigram audit failed: {error}", file=sys.stderr)
        raise SystemExit(1)
