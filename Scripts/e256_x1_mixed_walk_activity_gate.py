#!/usr/bin/env python3
"""Certify the frozen E256-X1 mixed-walk four-round active-S-box lower bound.

This gate grades exactly one item that the E256-X0 receipt recorded as
`mixed_four_round_bound = OPEN_NOT_GRADED`: the exact minimum number of active
S-boxes over any four consecutive E256-H rounds when the H4 row-offset selector
changes per round.

The graded quantity is the minimum of a truncated byte-activity relaxation.
Every actual differential trail projects onto a feasible activity pattern, so
the relaxation minimum is a *lower bound* on the active S-box count.  It is not
a trail count, not a differential probability, and not a claim that a minimising
pattern is realisable by actual differences.

It selects no round count, schedule, architecture, or security level, and it
does not close E256-063.
"""

import argparse
import hashlib
import itertools
import json
import os
import platform
import re
import subprocess
import sys
import time
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path
from typing import Dict, Iterable, List, Mapping, Optional, Sequence, Tuple

import numpy as np
from scipy.optimize import Bounds, LinearConstraint, milp

REPO = Path(__file__).resolve().parent.parent
CONTRACT = REPO / "directives/e256-x1-mixed-walk-activity.md"
PREREG = REPO / "directives/e256-x1-mixed-walk-activity-preregistration.json"
CANDIDATE_RECEIPT = REPO / "logs/e256-hardware-candidate-gate.json"
WIDE_RECEIPT = REPO / "logs/e256-wide-state-gate.json"
X0_RECEIPT = REPO / "logs/e256-x0-h4-evolution-gate.json"
X0_CONTRACT = REPO / "directives/e256-x0-h4-evolution.md"
X0_RUNNER = REPO / "Scripts/e256_x0_h4_evolution_gate.py"
WIDE_RUNNER = REPO / "Scripts/e256_wide_gate.py"
MAKEFILE = REPO / "Makefile"
RECEIPT = REPO / "logs/e256-x1-mixed-walk-activity-gate.json"
SCRATCH = REPO / "build/e256-x1-mixed-walk-activity"

CONTRACT_SHA256 = "c0f951f08ced7e7897a8fb1e1770b823ec62127f94c96fb2afac755e366a1716"
PREREG_SHA256 = "e80e9c11005db16924ad54e4a1bf5bef365af241ee5e23d189c40b9d59fa3041"
CANDIDATE_RAW_SHA256 = "0402a53a725f3303ab379bf7f5e986a55cadedb001f4621d9d996f4ee0d93cfc"
CANDIDATE_PAYLOAD_SHA256 = "98af83ec27093787552475fce588f84a902634afcc969bed26462032dddec3cc"
WIDE_RAW_SHA256 = "6e904713366d16de938ebb9bf93139e760b5748a3ec52ae973c5895baa80c584"
WIDE_PAYLOAD_SHA256 = "21758ce220b9da469a18ea617fa7b2fd41e906add69a258f830b12843e3e495b"
X0_RAW_SHA256 = "8db5f21b6e0a7249fa9b558c02a989324911575e91704b5e096e2749744ac2c9"
X0_PAYLOAD_SHA256 = "35060c802427046f5f4630c6b9db6401d8ac90c4649fc0cf088d3f35f31b1b44"
X0_CONTRACT_MARKER_SHA256 = "1ef354e9b933838eb3e74b32b202e4693f1bfdd62379f10dbc6a8673b3383962"
X0_RUNNER_SHA256 = "d011419ca4a712101481162748c4fcafe960d733582ffd2e2fd635f7a99fd602"
WIDE_RUNNER_SHA256 = "d6946d2007535a6371ddeef35693747fde8b4b94a110f65f32ea8b86cec22252"
CERTIFIED_SHA256 = "199f1f7bddccf19ce5aa0bde0987441735d628354140d53ebdfec538d7b3f5ed"

CONTRACT_START = "<!-- E256-X1-MIXED-WALK-ACTIVITY-CONTRACT-START -->"
CONTRACT_END = "<!-- E256-X1-MIXED-WALK-ACTIVITY-CONTRACT-END -->"
X0_CONTRACT_START = "<!-- E256-X0-H4-EVOLUTION-CONTRACT-START -->"
X0_CONTRACT_END = "<!-- E256-X0-H4-EVOLUTION-CONTRACT-END -->"

PREREG_SCHEMA = "E256-X1-MIXED-WALK-ACTIVITY-PREREGISTRATION-1"
RECEIPT_SCHEMA = "E256-X1-MIXED-WALK-ACTIVITY-GATE-1"
STATUS = "OPEN_PROGRESS"
PASS_VERDICT = "MIXED_WALK_FOUR_ROUND_ACTIVITY_LOWER_BOUND_CERTIFIED"
NO_WALL_CLOCK = (
    "No wall-clock timestamp is asserted; deterministic inputs and outputs are graded."
)

NODE_COUNT = 384
SUPPORT_COUNT = 16
PERMUTATIONS_PER_SUPPORT = 24
ROWS = 4
COLUMNS = 8
STATE_BYTES = ROWS * COLUMNS
LAYERS = 4
BOUNDARIES = LAYERS - 1
SELECTORS = BOUNDARIES
BRANCH_NUMBER = 5
FULL_SUPPORT_MASK = 0xFF
ASSERTED_BOUND = 25
SMT_BUDGET = ASSERTED_BOUND - 1
SYMMETRY_GROUP_ORDER = 2048
EXPECTED_CLASS_COUNT = 27648
FIXED_TUPLE = (0, 1, 3, 4)
FIXED_TUPLE_INDEX = 1
ALTERNATION_INDICES = (0, 3, 0)
ZERO_OFFSET_MINIMUM = 10
FOUR_SUBSET_TOTAL = 70

# Frozen deterministic sample used for the empirical orbit check and for the
# exhaustive-oracle cross-check, where full-family exhaustive search is not
# affordable.  Indices are catalog positions.
ORBIT_CHECK_TRIPLES = (
    (0, 0, 0),
    (0, 3, 0),
    (1, 1, 1),
    (5, 200, 41),
    (17, 300, 128),
    (383, 0, 191),
)
EXHAUSTIVE_CROSS_CHECK_TRIPLES = (
    (1, 1, 1),
    (0, 3, 0),
    (0, 0, 0),
    (17, 300, 128),
)
# The pure-Python oracle enumerates first-boundary column tiers, and the cost of
# the third tier is prohibitive.  Its honest role is therefore twofold: rule out
# every trail below this sub-bound on the non-degenerate cross-check triples, and
# reproduce the exact minimum on the degenerate controls, which proves it can
# find a minimum and is not vacuously returning "none found".
EXHAUSTIVE_SUB_BOUND = 20
EXHAUSTIVE_EXACT_CASES = (
    ("zero_row_offsets", ((0, 0, 0, 0),) * SELECTORS, ZERO_OFFSET_MINIMUM),
    ("repeated_offset_in_tuple", ((0, 1, 3, 3),) * SELECTORS, 15),
)
SELF_TEST_CLASS_LIMIT = 64

CONTROL_IDS = (
    "branch_number_four",
    "zero_row_offsets",
    "repeated_offset_in_tuple",
    "nonzero_requirement_omitted",
    "reverse_shift_direction",
    "three_sbox_layers",
    "five_sbox_layers",
    "stale_catalog_hash",
    "catalog_reorder",
    "tuple_element_mutation",
    "duplicate_tuple_offset",
    "out_of_range_tuple_offset",
    "witness_byte_removed",
    "witness_weight_forged",
    "omitted_column_constraint",
    "injected_oracle_disagreement",
    "noncertified_support_admitted",
    "orbit_member_minimum_mismatch",
    "canonical_class_count_mismatch",
    "filtered_class_corpus",
    "xor_safe_adjacency",
    "budget_off_by_one",
    "fabricated_exhaustive_minimum",
)

PAYLOAD_KEYS = (
    "schema",
    "status",
    "integrity",
    "catalog",
    "activity_model",
    "symmetry_quotient",
    "oracle_agreement",
    "coverage",
    "safe_subfamily",
    "diagnostics",
    "controls",
    "verdicts",
    "non_claims",
)
OUTER_KEYS = (
    "deterministic_payload",
    "deterministic_payload_sha256",
    "record_sha256",
    "environment_advisory_excluded_from_digest",
    "no_wall_clock",
)


class GateError(RuntimeError):
    """A frozen identity, coverage, oracle, symmetry, or witness failure."""


# ---------------------------------------------------------------------------
# Strict JSON, canonical hashing, and assertions.


def _reject_constant(value: str):
    raise GateError("non-finite JSON constant is forbidden: " + value)


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise GateError("duplicate JSON object key: " + str(key))
        result[key] = value
    return result


def strict_json_load(path: Path):
    try:
        return json.loads(
            path.read_text(encoding="utf-8"),
            object_pairs_hook=_unique_object,
            parse_constant=_reject_constant,
        )
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise GateError("could not strictly parse %s: %s" % (path, error)) from error


def canonical_json_bytes(value) -> bytes:
    return json.dumps(
        value, separators=(",", ":"), sort_keys=True, allow_nan=False
    ).encode("utf-8")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def require_true(condition: bool, message: str) -> None:
    if not condition:
        raise GateError(message)


def require_equal(observed, expected, message: str) -> None:
    if observed != expected:
        raise GateError("%s: expected %r, got %r" % (message, expected, observed))


def require_exact_keys(mapping: Mapping, keys: Sequence[str], message: str) -> None:
    require_equal(tuple(mapping.keys()), tuple(keys), message + " key order")


def update_record_hash(hasher, record) -> None:
    hasher.update(canonical_json_bytes(record))
    hasher.update(b"\n")


def marker_digest_inclusive(raw: bytes, start_text: str, end_text: str) -> str:
    start = start_text.encode("ascii")
    end = end_text.encode("ascii")
    require_equal(raw.count(start), 1, "inclusive marker start count")
    require_equal(raw.count(end), 1, "inclusive marker end count")
    start_index = raw.index(start)
    end_index = raw.index(end) + len(end)
    require_true(start_index < end_index, "inclusive markers out of order")
    return sha256_bytes(raw[start_index:end_index])


# ---------------------------------------------------------------------------
# Catalog, supports, and the exact sumset criterion.


def support_mask(tuple_offsets: Sequence[int]) -> int:
    mask = 0
    for value in tuple_offsets:
        mask |= 1 << value
    return mask


def support_elements(mask: int) -> Tuple[int, ...]:
    return tuple(index for index in range(COLUMNS) if (mask >> index) & 1)


def sumset_mask(left: int, right: int) -> int:
    out = 0
    for i in range(COLUMNS):
        if not (left >> i) & 1:
            continue
        for j in range(COLUMNS):
            if (right >> j) & 1:
                out |= 1 << ((i + j) % COLUMNS)
    return out


def xor_sumset_mask(left: int, right: int) -> int:
    out = 0
    for i in range(COLUMNS):
        if not (left >> i) & 1:
            continue
        for j in range(COLUMNS):
            if (right >> j) & 1:
                out |= 1 << (i ^ j)
    return out


def safe_transition(left: Sequence[int], right: Sequence[int]) -> bool:
    return sumset_mask(support_mask(left), support_mask(right)) == FULL_SUPPORT_MASK


def load_catalog() -> List[Tuple[int, ...]]:
    receipt = strict_json_load(CANDIDATE_RECEIPT)
    raw = receipt["deterministic_payload"]["results"]["h4_wiring"]["certified_set"]
    return validate_catalog(raw)


def validate_catalog(raw, claimed_digest: str = CERTIFIED_SHA256) -> List[Tuple[int, ...]]:
    require_true(isinstance(raw, list), "certified catalog is not an array")
    require_equal(len(raw), NODE_COUNT, "certified catalog count")
    normalized: List[Tuple[int, ...]] = []
    for index, wiring in enumerate(raw):
        require_true(
            isinstance(wiring, (list, tuple)) and len(wiring) == 4,
            "catalog tuple %d shape" % index,
        )
        require_true(
            all(type(value) is int and 0 <= value < COLUMNS for value in wiring),
            "catalog tuple %d offset range" % index,
        )
        require_equal(len(set(wiring)), 4, "catalog tuple %d distinctness" % index)
        normalized.append(tuple(wiring))
    require_equal(
        len(set(normalized)), NODE_COUNT, "catalog tuple uniqueness"
    )
    digest = sha256_bytes(canonical_json_bytes([list(t) for t in normalized]))
    require_equal(claimed_digest, CERTIFIED_SHA256, "claimed certified catalog digest")
    require_equal(digest, claimed_digest, "recomputed certified catalog digest")
    require_equal(normalized[0], (0, 1, 2, 5), "first certified tuple")
    require_equal(normalized[FIXED_TUPLE_INDEX], FIXED_TUPLE, "fixed certified tuple")
    require_equal(normalized[-1], (7, 6, 5, 2), "last certified tuple")

    by_support: Dict[int, List[Tuple[int, ...]]] = {}
    for wiring in normalized:
        by_support.setdefault(support_mask(wiring), []).append(wiring)
    require_equal(len(by_support), SUPPORT_COUNT, "support-class count")
    for mask, tuples in by_support.items():
        require_equal(
            len(tuples), PERMUTATIONS_PER_SUPPORT, "support-class multiplicity"
        )
        expected = set(itertools.permutations(support_elements(mask), 4))
        require_equal(set(tuples), expected, "support permutation closure")
        require_equal(
            sumset_mask(mask, mask), FULL_SUPPORT_MASK, "catalog support self-sumset"
        )
    return normalized


def characterise_supports(catalog: Sequence[Sequence[int]]) -> dict:
    """The 16 catalog supports are exactly the 4-subsets with S+S = Z_8."""
    observed = sorted({support_mask(w) for w in catalog})
    every = [support_mask(c) for c in itertools.combinations(range(COLUMNS), 4)]
    require_equal(len(every), FOUR_SUBSET_TOTAL, "four-subset enumeration")
    predicted = sorted(m for m in every if sumset_mask(m, m) == FULL_SUPPORT_MASK)
    require_equal(observed, predicted, "S+S=Z8 characterisation of catalog supports")
    require_equal(len(observed), SUPPORT_COUNT, "characterised support count")
    single_parity = sorted(
        m for m in every if m in (support_mask((0, 2, 4, 6)), support_mask((1, 3, 5, 7)))
    )
    require_equal(len(single_parity), 2, "single-parity support count")
    require_true(
        all(m not in observed for m in single_parity),
        "single-parity support must not be certified",
    )
    return {
        "four_subsets_total": FOUR_SUBSET_TOTAL,
        "certified_support_count": len(observed),
        "support_masks": observed,
        "characterisation": "S+S = Z_8",
        "characterisation_exact": True,
        "single_parity_masks": single_parity,
        "single_parity_certified": False,
    }


# ---------------------------------------------------------------------------
# Byte-activity patterns.  Bit (4*column + row) matches the repo byte index.


def bit_index(row: int, column: int) -> int:
    return 1 << (ROWS * column + row)


def shift_rows(pattern: int, offsets: Sequence[int], reverse: bool = False) -> int:
    out = 0
    for column in range(COLUMNS):
        for row in range(ROWS):
            if reverse:
                source = (column - offsets[row]) % COLUMNS
            else:
                source = (column + offsets[row]) % COLUMNS
            if pattern & bit_index(row, source):
                out |= bit_index(row, column)
    return out


def column_weights(pattern: int) -> List[int]:
    return [
        bin((pattern >> (ROWS * column)) & 0xF).count("1") for column in range(COLUMNS)
    ]


def weight(pattern: int) -> int:
    return bin(pattern).count("1")


def verify_trail(
    patterns: Sequence[int],
    offsets: Sequence[Sequence[int]],
    branch: int = BRANCH_NUMBER,
    reverse: bool = False,
    skip_column: Optional[Tuple[int, int]] = None,
) -> Optional[int]:
    """Exact independent re-verification.  Returns the total weight or None."""
    require_equal(len(patterns), len(offsets) + 1, "witness layer count")
    if weight(patterns[0]) == 0:
        return None
    for index in range(len(offsets)):
        shifted = column_weights(shift_rows(patterns[index], offsets[index], reverse))
        output = column_weights(patterns[index + 1])
        for column in range(COLUMNS):
            if skip_column == (index, column):
                continue
            a = shifted[column]
            b = output[column]
            if a == 0 and b == 0:
                continue
            if a + b < branch:
                return None
    return sum(weight(pattern) for pattern in patterns)


# ---------------------------------------------------------------------------
# Oracle 1: exact SMT decision through the z3 binary.


def smt_text(
    budget: int,
    offsets: Sequence[Sequence[int]],
    branch: int = BRANCH_NUMBER,
    nonzero: bool = True,
    reverse: bool = False,
    skip_column: Optional[Tuple[int, int]] = None,
) -> str:
    layers = len(offsets) + 1
    lines = ["(set-logic ALL)"]
    name = lambda i, r, c: "p%d_%d_%d" % (i, r, c)
    for i in range(layers):
        for r in range(ROWS):
            for c in range(COLUMNS):
                lines.append("(declare-const %s Bool)" % name(i, r, c))

    def indicator(term: str) -> str:
        return "(ite %s 1 0)" % term

    def total(terms: Sequence[str]) -> str:
        if not terms:
            return "0"
        if len(terms) == 1:
            return terms[0]
        return "(+ %s)" % " ".join(terms)

    for i, offs in enumerate(offsets):
        for c in range(COLUMNS):
            if skip_column == (i, c):
                continue
            source = [
                indicator(
                    name(
                        i,
                        r,
                        (c - offs[r]) % COLUMNS if reverse else (c + offs[r]) % COLUMNS,
                    )
                )
                for r in range(ROWS)
            ]
            sink = [indicator(name(i + 1, r, c)) for r in range(ROWS)]
            lines.append("(declare-const a%d_%d Int)" % (i, c))
            lines.append("(declare-const b%d_%d Int)" % (i, c))
            lines.append("(assert (= a%d_%d %s))" % (i, c, total(source)))
            lines.append("(assert (= b%d_%d %s))" % (i, c, total(sink)))
            lines.append(
                "(assert (or (>= (+ a%d_%d b%d_%d) %d) (and (= a%d_%d 0) (= b%d_%d 0))))"
                % (i, c, i, c, branch, i, c, i, c)
            )
    if nonzero:
        lines.append(
            "(assert (>= %s 1))"
            % total(
                [
                    indicator(name(0, r, c))
                    for r in range(ROWS)
                    for c in range(COLUMNS)
                ]
            )
        )
    lines.append(
        "(assert (<= %s %d))"
        % (
            total(
                [
                    indicator(name(i, r, c))
                    for i in range(layers)
                    for r in range(ROWS)
                    for c in range(COLUMNS)
                ]
            ),
            budget,
        )
    )
    lines.append("(check-sat)")
    return "\n".join(lines)


def smt_decide(
    budget: int,
    offsets: Sequence[Sequence[int]],
    branch: int = BRANCH_NUMBER,
    nonzero: bool = True,
    reverse: bool = False,
    skip_column: Optional[Tuple[int, int]] = None,
    timeout: int = 600,
) -> str:
    text = smt_text(
        budget, offsets, branch=branch, nonzero=nonzero, reverse=reverse,
        skip_column=skip_column,
    )
    try:
        process = subprocess.run(
            ["z3", "-smt2", "-in", "-T:%d" % timeout],
            input=text,
            capture_output=True,
            text=True,
            timeout=timeout + 120,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise GateError("z3 invocation failed: %s" % error) from error
    output = (process.stdout or "").strip().splitlines()
    verdict = output[0].strip() if output else ""
    if verdict not in ("sat", "unsat"):
        raise GateError(
            "z3 returned no decision (%r); stderr=%r"
            % (verdict, (process.stderr or "")[:200])
        )
    return verdict


# ---------------------------------------------------------------------------
# Oracle 2: exact ILP through HiGHS, returning the minimum and a witness.


def ilp_minimum(
    offsets: Sequence[Sequence[int]],
    branch: int = BRANCH_NUMBER,
    nonzero: bool = True,
    reverse: bool = False,
    skip_column: Optional[Tuple[int, int]] = None,
) -> Tuple[Optional[int], Optional[List[int]]]:
    layers = len(offsets) + 1
    boundaries = len(offsets)
    n_pattern = layers * STATE_BYTES
    n_total = n_pattern + boundaries * COLUMNS
    pv = lambda i, r, c: i * STATE_BYTES + c * ROWS + r
    dv = lambda i, c: n_pattern + i * COLUMNS + c

    rows: List[List[float]] = []
    lower: List[float] = []
    upper: List[float] = []

    def add(coefficients: Sequence[Tuple[int, float]], lo: float, hi: float) -> None:
        row = [0.0] * n_total
        for index, value in coefficients:
            row[index] += value
        rows.append(row)
        lower.append(lo)
        upper.append(hi)

    for i, offs in enumerate(offsets):
        for c in range(COLUMNS):
            if skip_column == (i, c):
                continue
            source = [
                (
                    pv(
                        i,
                        r,
                        (c - offs[r]) % COLUMNS if reverse else (c + offs[r]) % COLUMNS,
                    ),
                    1.0,
                )
                for r in range(ROWS)
            ]
            sink = [(pv(i + 1, r, c), 1.0) for r in range(ROWS)]
            add(list(source) + [(dv(i, c), -float(ROWS))], -np.inf, 0.0)
            add(list(sink) + [(dv(i, c), -float(ROWS))], -np.inf, 0.0)
            add(list(source) + list(sink) + [(dv(i, c), -float(branch))], 0.0, np.inf)
    if nonzero:
        add(
            [(pv(0, r, c), 1.0) for r in range(ROWS) for c in range(COLUMNS)],
            1.0,
            np.inf,
        )
    objective = np.zeros(n_total)
    for i in range(layers):
        for r in range(ROWS):
            for c in range(COLUMNS):
                objective[pv(i, r, c)] = 1.0
    result = milp(
        c=objective,
        constraints=LinearConstraint(np.array(rows), lower, upper),
        integrality=np.ones(n_total),
        bounds=Bounds(np.zeros(n_total), np.ones(n_total)),
    )
    if result.x is None:
        return None, None
    patterns: List[int] = []
    for i in range(layers):
        pattern = 0
        for c in range(COLUMNS):
            for r in range(ROWS):
                if result.x[pv(i, r, c)] > 0.5:
                    pattern |= bit_index(r, c)
        patterns.append(pattern)
    return int(round(result.fun)), patterns


# ---------------------------------------------------------------------------
# Oracle 3: pure-Python exhaustive branch and bound.
#
# Soundness of the pruning.  Summing the per-column MDS constraint over the
# active columns at boundary i gives |P_i| + |P_{i+1}| >= branch * k_i.  Taking
# i = 0 and i = 2 and adding, cost >= branch * (k_0 + k_2) >= branch * (k_0 + 1),
# because a nonzero first layer forces every later layer nonzero.  Hence any
# trail with cost < bound has k_0 <= (bound - branch)/branch, and its first
# boundary image occupies at most that many columns.  Enumerating all target
# column sets of that size, with every per-row pre-image subset, therefore
# covers every candidate.

SUBSETS_AT_LEAST = tuple(
    tuple(
        (mask, bin(mask).count("1"))
        for mask in range(1 << ROWS)
        if bin(mask).count("1") >= k
    )
    for k in range(ROWS + 1)
)
# Row-major helpers.  A pattern is carried as four 8-bit column masks, one per
# row, which makes ShiftRows a table lookup and keeps column accounting sparse.
_ROTATE_RIGHT = tuple(
    tuple(((value >> k) | (value << (COLUMNS - k))) & 0xFF for value in range(256))
    for k in range(COLUMNS)
)
_SET_COLUMNS = tuple(
    tuple(c for c in range(COLUMNS) if (value >> c) & 1) for value in range(256)
)
_POPCOUNT = tuple(bin(value).count("1") for value in range(256))


def _column_pattern(column: int, mask: int) -> Tuple[int, int]:
    pattern = 0
    for row in range(ROWS):
        if (mask >> row) & 1:
            pattern |= bit_index(row, column)
    return pattern, _POPCOUNT[mask]


def _shift_rows_masks(rows: Sequence[int], offsets: Sequence[int]) -> List[int]:
    """out[r] column mask after out[r][c] = in[r][(c + w_r) mod 8]."""
    return [_ROTATE_RIGHT[offsets[row] % COLUMNS][rows[row]] for row in range(ROWS)]


def _column_weights_from_masks(rows: Sequence[int]) -> Tuple[List[int], int]:
    weights = [0] * COLUMNS
    union = 0
    for mask in rows:
        union |= mask
        for column in _SET_COLUMNS[mask]:
            weights[column] += 1
    return weights, union


def exhaustive_below(
    offsets: Sequence[Sequence[int]],
    bound: int,
    branch: int = BRANCH_NUMBER,
) -> Optional[int]:
    """Least trail cost strictly below `bound`, or None if no such trail exists."""
    require_equal(len(offsets), BOUNDARIES, "exhaustive oracle boundary count")
    best = bound
    # Tightest sound tier: any trail with cost < bound obeys
    # branch * (k_0 + 1) <= cost < bound, so k_0 is the largest integer with
    # branch * (k_0 + 1) < bound.
    max_columns = (bound - 1) // branch - 1
    if max_columns < 1:
        return None
    max_columns = min(max_columns, COLUMNS)
    # Extra sound bound for the second-to-last layer, valid only when the last
    # round's offsets are pairwise distinct.  One column of that layer carrying
    # `s` active rows is then spread by ShiftRows across `s` distinct columns, so
    # k_last >= s and the remaining two layers cost at least branch * s.
    spread_prune = len(set(offsets[BOUNDARIES - 1])) == ROWS

    def cross(rows: Sequence[int], running: int, boundary: int) -> None:
        """Cross offsets[boundary], choosing the next layer's column patterns."""
        nonlocal best
        shifted, union = _column_weights_from_masks(
            _shift_rows_masks(rows, offsets[boundary])
        )
        actives = _SET_COLUMNS[union]
        needs = [max(1, branch - shifted[c]) for c in actives]
        floor = sum(needs)
        if boundary == BOUNDARIES - 1:
            # Final layer: nothing consumes its byte positions, so the minimum
            # is exactly the per-column need and no branching is required.
            total = running + floor
            if total < best:
                best = total
            return
        # Later layers still cost at least one byte each.
        if running + floor + (BOUNDARIES - 1 - boundary) >= best:
            return
        suffix = [0] * (len(needs) + 1)
        for index in range(len(needs) - 1, -1, -1):
            suffix[index] = suffix[index + 1] + needs[index]

        tail = BOUNDARIES - 1 - boundary
        penultimate = spread_prune and boundary == BOUNDARIES - 2
        base = running

        def choose(index: int, accumulated: List[int], carried: int, widest: int) -> None:
            if index == len(actives):
                cross(accumulated, carried, boundary + 1)
                return
            if carried + suffix[index] + tail >= best:
                return
            column = actives[index]
            bit = 1 << column
            for mask, added in SUBSETS_AT_LEAST[needs[index]]:
                if carried + added + suffix[index + 1] + tail >= best:
                    continue
                if penultimate:
                    spread = added if added > widest else widest
                    if base + branch * spread >= best:
                        continue
                else:
                    spread = widest
                nxt = list(accumulated)
                for row in range(ROWS):
                    if (mask >> row) & 1:
                        nxt[row] |= bit
                choose(index + 1, nxt, carried + added, spread)

        choose(0, [0] * ROWS, running, 0)

    for size in range(1, max_columns + 1):
        if branch * (size + 1) >= bound:
            continue
        for targets in itertools.combinations(range(COLUMNS), size):
            # Pre-images of the target columns under this round's row shifts.
            row_options: List[List[Tuple[int, int]]] = []
            for row in range(ROWS):
                sources = [(c + offsets[0][row]) % COLUMNS for c in targets]
                options = []
                for mask in range(1 << size):
                    bits = 0
                    for position in range(size):
                        if (mask >> position) & 1:
                            bits |= 1 << sources[position]
                    options.append((bits, _POPCOUNT[bits]))
                row_options.append(options)
            for a0, w0 in row_options[0]:
                for a1, w1 in row_options[1]:
                    if w0 + w1 + BOUNDARIES >= best:
                        continue
                    for a2, w2 in row_options[2]:
                        if w0 + w1 + w2 + BOUNDARIES >= best:
                            continue
                        for a3, w3 in row_options[3]:
                            n1 = w0 + w1 + w2 + w3
                            if n1 == 0 or n1 + BOUNDARIES >= best:
                                continue
                            cross([a0, a1, a2, a3], n1, 0)
    return None if best >= bound else best


# ---------------------------------------------------------------------------
# Symmetry quotient over ordered catalog triples.


def translate(tuple_offsets: Sequence[int], shift: int) -> Tuple[int, ...]:
    return tuple((value + shift) % COLUMNS for value in tuple_offsets)


def rotate_rows(tuple_offsets: Sequence[int], amount: int) -> Tuple[int, ...]:
    return tuple(tuple_offsets[(row + amount) % ROWS] for row in range(ROWS))


def normalise(tuple_offsets: Sequence[int]) -> Tuple[int, ...]:
    return translate(tuple_offsets, (-tuple_offsets[0]) % COLUMNS)


def canonical_triple(triple: Sequence[Sequence[int]]) -> Tuple[Tuple[int, ...], ...]:
    best = None
    for amount in range(ROWS):
        rotated = [rotate_rows(t, amount) for t in triple]
        candidate = tuple(normalise(t) for t in rotated)
        if best is None or candidate < best:
            best = candidate
    return best


def verify_catalog_symmetry(catalog: Sequence[Sequence[int]]) -> dict:
    members = set(catalog)
    require_true(
        all(translate(t, k) in members for t in catalog for k in range(COLUMNS)),
        "catalog is not closed under offset translation",
    )
    require_true(
        all(rotate_rows(t, k) in members for t in catalog for k in range(ROWS)),
        "catalog is not closed under cyclic row rotation",
    )
    translation_orbits: Dict[Tuple[int, ...], int] = {}
    for t in catalog:
        key = min(translate(t, k) for k in range(COLUMNS))
        translation_orbits[key] = translation_orbits.get(key, 0) + 1
    combined_orbits: Dict[Tuple[int, ...], int] = {}
    for t in catalog:
        key = min(
            rotate_rows(translate(t, k), j)
            for k in range(COLUMNS)
            for j in range(ROWS)
        )
        combined_orbits[key] = combined_orbits.get(key, 0) + 1
    return {
        "closed_under_translation": True,
        "closed_under_row_rotation": True,
        "single_tuple_translation_classes": len(translation_orbits),
        "single_tuple_translation_orbit_sizes": sorted(set(translation_orbits.values())),
        "single_tuple_combined_classes": len(combined_orbits),
        "single_tuple_combined_orbit_sizes": sorted(set(combined_orbits.values())),
    }


def rotate_normalised(
    triple: Sequence[Sequence[int]], amount: int
) -> Tuple[Tuple[int, ...], ...]:
    """The row-rotation action on translation-normalised triples."""
    return tuple(normalise(rotate_rows(t, amount)) for t in triple)


def build_canonical_classes(
    catalog: Sequence[Sequence[int]],
) -> Tuple[List[Tuple[Tuple[int, ...], ...]], dict]:
    """Enumerate canonical representatives directly instead of quotienting 384^3.

    Per-round translation is free with orbit size 8 on single tuples, so the
    translation quotient of ordered triples is exactly `NORM^3` where `NORM` is
    the set of translation-normalised catalog tuples.  Row rotation then acts on
    `NORM^3`; every orbit of that action is verified to have size 4, so the full
    group orbit on ordered catalog triples has size 8^3 * 4 = 2048 and the class
    count is `|NORM|^3 / 4`.  The arithmetic identity against 384^3 is asserted.
    """
    preimages: Dict[Tuple[int, ...], int] = {}
    for t in catalog:
        key = normalise(t)
        preimages[key] = preimages.get(key, 0) + 1
    norm = sorted(preimages)
    require_equal(
        sorted(set(preimages.values())),
        [COLUMNS],
        "translation preimage counts per normalised tuple",
    )
    require_equal(len(norm) * COLUMNS, NODE_COUNT, "translation quotient size")

    seen = set()
    classes: List[Tuple[Tuple[int, ...], ...]] = []
    orbit_sizes = set()
    for a in norm:
        for b in norm:
            for c in norm:
                triple = (a, b, c)
                if triple in seen:
                    continue
                orbit = {rotate_normalised(triple, amount) for amount in range(ROWS)}
                require_true(
                    all(member in preimages or True for member in orbit),
                    "rotation action left the normalised set",
                )
                for member in orbit:
                    require_true(
                        all(t in preimages for t in member),
                        "rotation action produced a non-catalog tuple",
                    )
                seen.update(orbit)
                orbit_sizes.add(len(orbit))
                classes.append(min(orbit))
    classes.sort()
    require_equal(len(seen), len(norm) ** 3, "row-rotation orbit cover")
    structure = {
        "normalised_tuples": len(norm),
        "translation_orbit_size": COLUMNS,
        "row_rotation_orbit_sizes": sorted(orbit_sizes),
        "class_count": len(classes),
        "orbit_size_product": COLUMNS ** SELECTORS * ROWS,
    }
    require_equal(
        structure["orbit_size_product"],
        SYMMETRY_GROUP_ORDER,
        "reconstructed symmetry group order",
    )
    require_equal(
        len(classes) * SYMMETRY_GROUP_ORDER,
        NODE_COUNT ** SELECTORS,
        "class count times orbit size must equal the ordered triple total",
    )
    return classes, structure


# ---------------------------------------------------------------------------
# Parallel sweep workers.  Module-level for picklability.


def _sweep_worker(payload):
    triple, budget = payload
    offsets = [list(t) for t in triple]
    minimum, witness = ilp_minimum(offsets)
    if minimum is None or witness is None:
        return {"error": "ilp returned no solution"}
    verified = verify_trail(witness, offsets)
    verdict = smt_decide(budget, offsets)
    return {
        "minimum": minimum,
        "witness_weight": verified,
        "smt_verdict": verdict,
        "layer_weights": [weight(p) for p in witness],
    }


def run_sweep(
    triples: Sequence[Sequence[Sequence[int]]],
    workers: int,
    budget: int = SMT_BUDGET,
    label: str = "sweep",
    progress: bool = False,
) -> List[dict]:
    payloads = [(tuple(tuple(t) for t in triple), budget) for triple in triples]
    results: List[dict] = []
    started = time.time()
    if workers <= 1:
        for index, payload in enumerate(payloads):
            results.append(_sweep_worker(payload))
            if progress and (index + 1) % 500 == 0:
                _progress(label, index + 1, len(payloads), started)
    else:
        with ProcessPoolExecutor(max_workers=workers) as pool:
            for index, record in enumerate(
                pool.map(_sweep_worker, payloads, chunksize=8)
            ):
                results.append(record)
                if progress and (index + 1) % 500 == 0:
                    _progress(label, index + 1, len(payloads), started)
    if progress:
        _progress(label, len(payloads), len(payloads), started)
    return results


def _progress(label: str, done: int, total: int, started: float) -> None:
    elapsed = time.time() - started
    rate = done / elapsed if elapsed > 0 else 0.0
    remaining = (total - done) / rate if rate > 0 else 0.0
    sys.stderr.write(
        "  %s %d/%d  %.0fs elapsed  ~%.0fs left\n" % (label, done, total, elapsed, remaining)
    )
    sys.stderr.flush()


def grade_sweep(
    triples: Sequence[Sequence[Sequence[int]]],
    results: Sequence[dict],
    budget: int,
    bound: int,
    label: str,
) -> dict:
    require_equal(len(results), len(triples), label + " result count")
    histogram: Dict[int, int] = {}
    hasher = hashlib.sha256()
    below = []
    for triple, record in zip(triples, results):
        require_true("error" not in record, "%s worker error: %r" % (label, record))
        minimum = record["minimum"]
        require_true(type(minimum) is int, label + " minimum type")
        require_equal(
            record["witness_weight"],
            minimum,
            "%s witness weight for %r" % (label, triple),
        )
        expected = "unsat" if minimum > budget else "sat"
        require_equal(
            record["smt_verdict"],
            expected,
            "%s SMT/ILP agreement for %r" % (label, triple),
        )
        histogram[minimum] = histogram.get(minimum, 0) + 1
        if minimum < bound:
            below.append({"triple": [list(t) for t in triple], "minimum": minimum})
        update_record_hash(
            hasher,
            {
                "triple": [list(t) for t in triple],
                "minimum": minimum,
                "smt_verdict": record["smt_verdict"],
                "witness_weight": record["witness_weight"],
                "witness_layer_weights": record["layer_weights"],
            },
        )
    return {
        "graded_cases": len(results),
        "minimum_histogram": {str(k): histogram[k] for k in sorted(histogram)},
        "global_minimum": min(histogram),
        "global_maximum": max(histogram),
        "all_at_or_above_asserted_bound": not below,
        "classes_below_asserted_bound": below[:8],
        "classes_below_asserted_bound_count": len(below),
        "stream_aggregate_sha256": hasher.hexdigest(),
    }


# ---------------------------------------------------------------------------
# Planted controls.


def expect_rejection(identifier: str, operation) -> dict:
    try:
        operation()
    except GateError as error:
        return {"id": identifier, "detected": True, "rejection": str(error)[:240]}
    raise GateError("control was not detected: " + identifier)


def expect_minimum_change(
    identifier: str, observed: Optional[int], baseline: int, direction: str
) -> dict:
    if observed is None:
        raise GateError("control produced no minimum: " + identifier)
    if direction == "below" and not observed < baseline:
        raise GateError(
            "control did not drop the minimum: %s (%r vs %r)"
            % (identifier, observed, baseline)
        )
    if direction == "above" and not observed > baseline:
        raise GateError(
            "control did not raise the minimum: %s (%r vs %r)"
            % (identifier, observed, baseline)
        )
    return {
        "id": identifier,
        "detected": True,
        "observed_minimum": observed,
        "baseline_minimum": baseline,
        "direction": direction,
    }


def run_controls(catalog: Sequence[Sequence[int]], classes_count: int) -> List[dict]:
    fixed = [list(FIXED_TUPLE)] * SELECTORS
    records: List[dict] = []

    branch4, _ = ilp_minimum(fixed, branch=4)
    records.append(
        expect_minimum_change("branch_number_four", branch4, ASSERTED_BOUND, "below")
    )

    zero = [[0, 0, 0, 0]] * SELECTORS
    zero_min, zero_witness = ilp_minimum(zero)
    require_equal(zero_min, ZERO_OFFSET_MINIMUM, "zero-offset control minimum")
    require_equal(
        verify_trail(zero_witness, zero), ZERO_OFFSET_MINIMUM, "zero-offset witness"
    )
    records.append(
        expect_minimum_change("zero_row_offsets", zero_min, ASSERTED_BOUND, "below")
    )

    repeated = [[0, 1, 3, 3]] * SELECTORS
    repeated_min, _ = ilp_minimum(repeated)
    records.append(
        expect_minimum_change(
            "repeated_offset_in_tuple", repeated_min, ASSERTED_BOUND, "below"
        )
    )

    open_min, _ = ilp_minimum(fixed, nonzero=False)
    require_equal(open_min, 0, "nonzero-omitted control minimum")
    records.append(
        {
            "id": "nonzero_requirement_omitted",
            "detected": True,
            "observed_minimum": open_min,
            "note": "all-zero trail becomes feasible once the nonzero gate is dropped",
        }
    )

    asymmetric = [list(catalog[0]), list(catalog[3]), list(catalog[17])]
    forward = shift_rows(bit_index(0, 1) | bit_index(2, 5), asymmetric[0])
    backward = shift_rows(bit_index(0, 1) | bit_index(2, 5), asymmetric[0], reverse=True)
    require_true(forward != backward, "reverse-direction control is vacuous")
    smt_forward = smt_decide(SMT_BUDGET, asymmetric)
    smt_reverse = smt_decide(SMT_BUDGET, asymmetric, reverse=True)
    ilp_forward, _ = ilp_minimum(asymmetric)
    ilp_reverse, _ = ilp_minimum(asymmetric, reverse=True)
    records.append(
        {
            "id": "reverse_shift_direction",
            "detected": True,
            "forward_image_differs": True,
            "forward_smt": smt_forward,
            "reverse_smt": smt_reverse,
            "forward_minimum": ilp_forward,
            "reverse_minimum": ilp_reverse,
            "note": "the reverse convention is a distinct permutation and is graded, not assumed equal",
        }
    )

    three, _ = ilp_minimum(fixed[:2])
    records.append(
        expect_minimum_change("three_sbox_layers", three, ASSERTED_BOUND, "below")
    )
    five, _ = ilp_minimum(fixed + [list(FIXED_TUPLE)])
    records.append(
        expect_minimum_change("five_sbox_layers", five, ASSERTED_BOUND, "above")
    )

    records.append(
        expect_rejection(
            "stale_catalog_hash",
            lambda: validate_catalog([list(t) for t in catalog], claimed_digest="0" * 64),
        )
    )
    reordered = [list(t) for t in catalog]
    reordered[0], reordered[2] = reordered[2], reordered[0]
    records.append(
        expect_rejection("catalog_reorder", lambda: validate_catalog(reordered))
    )
    mutated = [list(t) for t in catalog]
    mutated[7] = [mutated[7][0], mutated[7][1], mutated[7][2], (mutated[7][3] + 1) % 8]
    records.append(
        expect_rejection("tuple_element_mutation", lambda: validate_catalog(mutated))
    )
    duplicated = [list(t) for t in catalog]
    duplicated[9] = [duplicated[9][0], duplicated[9][0], duplicated[9][2], duplicated[9][3]]
    records.append(
        expect_rejection("duplicate_tuple_offset", lambda: validate_catalog(duplicated))
    )
    out_of_range = [list(t) for t in catalog]
    out_of_range[11] = [8, 1, 2, 3]
    records.append(
        expect_rejection(
            "out_of_range_tuple_offset", lambda: validate_catalog(out_of_range)
        )
    )

    baseline_min, baseline_witness = ilp_minimum(fixed)
    require_equal(baseline_min, ASSERTED_BOUND, "control baseline minimum")
    require_equal(
        verify_trail(baseline_witness, fixed), ASSERTED_BOUND, "control baseline witness"
    )
    stripped = list(baseline_witness)
    lowest = stripped[1] & -stripped[1]
    stripped[1] = stripped[1] ^ lowest
    require_true(
        verify_trail(stripped, fixed) is None,
        "witness byte removal was not rejected",
    )
    records.append(
        {
            "id": "witness_byte_removed",
            "detected": True,
            "note": "removing one active byte from a verified witness is rejected by the checker",
        }
    )
    records.append(
        expect_rejection(
            "witness_weight_forged",
            lambda: require_equal(
                verify_trail(baseline_witness, fixed),
                ASSERTED_BOUND - 1,
                "forged witness weight",
            ),
        )
    )

    skipped, _ = ilp_minimum(fixed, skip_column=(1, 3))
    records.append(
        expect_minimum_change(
            "omitted_column_constraint", skipped, ASSERTED_BOUND, "below"
        )
    )

    records.append(
        expect_rejection(
            "injected_oracle_disagreement",
            lambda: require_equal(
                "sat",
                "unsat" if baseline_min > SMT_BUDGET else "sat",
                "injected SMT/ILP agreement",
            ),
        )
    )

    non_certified = support_mask((0, 2, 4, 6))
    admitted = [list(t) for t in catalog]
    admitted[0] = [0, 2, 4, 6]
    records.append(
        expect_rejection(
            "noncertified_support_admitted", lambda: validate_catalog(admitted)
        )
    )
    require_true(
        sumset_mask(non_certified, non_certified) != FULL_SUPPORT_MASK,
        "single-parity support unexpectedly satisfies S+S=Z8",
    )

    orbit_base = [list(catalog[5]), list(catalog[200]), list(catalog[41])]
    orbit_min, _ = ilp_minimum(orbit_base)
    moved = [
        list(rotate_rows(translate(catalog[5], 3), 2)),
        list(rotate_rows(translate(catalog[200], 6), 2)),
        list(rotate_rows(translate(catalog[41], 1), 2)),
    ]
    moved_min, _ = ilp_minimum(moved)
    require_equal(moved_min, orbit_min, "symmetry orbit minimum")
    records.append(
        expect_rejection(
            "orbit_member_minimum_mismatch",
            lambda: require_equal(moved_min + 1, orbit_min, "orbit minimum mismatch"),
        )
    )

    records.append(
        expect_rejection(
            "canonical_class_count_mismatch",
            lambda: require_equal(
                classes_count + 1, EXPECTED_CLASS_COUNT, "canonical class count"
            ),
        )
    )
    records.append(
        expect_rejection(
            "filtered_class_corpus",
            lambda: require_equal(
                classes_count - 1, EXPECTED_CLASS_COUNT, "filtered class corpus"
            ),
        )
    )

    # The XOR substitution admits exactly as many full pairs as modular addition,
    # so a gate that only counted safe pairs would not notice.  Pin the first
    # index pair in each direction where the two operators actually disagree.
    modular_only = None
    xor_only = None
    for i in range(NODE_COUNT):
        for j in range(NODE_COUNT):
            left = support_mask(catalog[i])
            right = support_mask(catalog[j])
            modular_full = sumset_mask(left, right) == FULL_SUPPORT_MASK
            xor_full = xor_sumset_mask(left, right) == FULL_SUPPORT_MASK
            if modular_full and not xor_full and modular_only is None:
                modular_only = (i, j)
            if xor_full and not modular_full and xor_only is None:
                xor_only = (i, j)
        if modular_only is not None and xor_only is not None:
            break
    require_true(modular_only is not None, "no modular-only safe pair exists")
    require_true(xor_only is not None, "no XOR-only safe pair exists")
    pinned_left = support_mask(catalog[modular_only[0]])
    pinned_right = support_mask(catalog[modular_only[1]])
    require_equal(
        sumset_mask(pinned_left, pinned_right),
        FULL_SUPPORT_MASK,
        "safe-adjacency baseline on the pinned discriminating pair",
    )
    record = expect_rejection(
        "xor_safe_adjacency",
        lambda: require_equal(
            xor_sumset_mask(pinned_left, pinned_right),
            FULL_SUPPORT_MASK,
            "XOR sumset substituted for modular addition",
        ),
    )
    record["modular_only_pair"] = list(modular_only)
    record["xor_only_pair"] = list(xor_only)
    records.append(record)

    at_bound = smt_decide(ASSERTED_BOUND, fixed)
    require_equal(at_bound, "sat", "budget off-by-one control")
    records.append(
        expect_rejection(
            "budget_off_by_one",
            lambda: require_equal(at_bound, "unsat", "unsat asserted at the achieved minimum"),
        )
    )

    exhaustive_zero = exhaustive_below(zero, ASSERTED_BOUND)
    require_equal(
        exhaustive_zero, ZERO_OFFSET_MINIMUM, "exhaustive oracle on the zero control"
    )
    records.append(
        expect_rejection(
            "fabricated_exhaustive_minimum",
            lambda: require_equal(
                ZERO_OFFSET_MINIMUM - 1,
                exhaustive_zero,
                "fabricated exhaustive minimum",
            ),
        )
    )

    require_equal(
        tuple(record["id"] for record in records), CONTROL_IDS, "control IDs"
    )
    return records


# ---------------------------------------------------------------------------
# Frozen input validation.


def validate_frozen_inputs() -> dict:
    prereg = strict_json_load(PREREG)
    require_equal(prereg.get("schema"), PREREG_SCHEMA, "preregistration schema")
    require_equal(
        prereg.get("status"), "FROZEN_BEFORE_IMPLEMENTATION", "preregistration status"
    )
    require_equal(sha256_file(PREREG), PREREG_SHA256, "preregistration raw SHA-256")
    require_equal(
        prereg["contract"]["inclusive_sha256"],
        CONTRACT_SHA256,
        "declared contract digest",
    )
    require_equal(
        marker_digest_inclusive(CONTRACT.read_bytes(), CONTRACT_START, CONTRACT_END),
        CONTRACT_SHA256,
        "recomputed X1 contract marker",
    )
    require_equal(
        marker_digest_inclusive(
            X0_CONTRACT.read_bytes(), X0_CONTRACT_START, X0_CONTRACT_END
        ),
        X0_CONTRACT_MARKER_SHA256,
        "recomputed X0 contract marker",
    )
    require_equal(
        tuple(item["id"] for item in prereg["controls"]), CONTROL_IDS, "control IDs"
    )
    require_equal(
        tuple(prereg["receipt_contract"]["required_sections"]),
        PAYLOAD_KEYS[2:],
        "required receipt sections",
    )
    require_equal(
        prereg["receipt_contract"]["schema"], RECEIPT_SCHEMA, "receipt schema"
    )
    require_equal(prereg["receipt_contract"]["status"], STATUS, "receipt status")
    require_equal(
        prereg["receipt_contract"]["path"],
        str(RECEIPT.relative_to(REPO)),
        "receipt path",
    )
    require_equal(
        prereg["receipt_contract"]["scratch_path"],
        str(SCRATCH.relative_to(REPO)),
        "scratch path",
    )
    require_equal(
        tuple(prereg["make_entry_points"]),
        ("e256-x1-mixed-walk-activity", "e256-x1-mixed-walk-activity-check"),
        "make entry points",
    )
    require_equal(
        prereg["coverage"]["canonical_classes_expected"],
        EXPECTED_CLASS_COUNT,
        "declared canonical class count",
    )
    require_equal(
        prereg["coverage"]["smt_budget_for_lower_bound"], SMT_BUDGET, "declared budget"
    )
    require_equal(
        prereg["coverage"]["asserted_lower_bound"], ASSERTED_BOUND, "declared bound"
    )
    require_equal(
        prereg["symmetry_quotient"]["group_order"],
        SYMMETRY_GROUP_ORDER,
        "declared symmetry group order",
    )
    require_equal(
        prereg["activity_model"]["branch_number"], BRANCH_NUMBER, "declared branch number"
    )

    predecessors = {
        "candidate_receipt": (CANDIDATE_RECEIPT, CANDIDATE_RAW_SHA256, CANDIDATE_PAYLOAD_SHA256),
        "wide_receipt": (WIDE_RECEIPT, WIDE_RAW_SHA256, WIDE_PAYLOAD_SHA256),
        "x0_receipt": (X0_RECEIPT, X0_RAW_SHA256, X0_PAYLOAD_SHA256),
    }
    predecessor_record = {}
    for name, (path, raw_expected, payload_expected) in predecessors.items():
        require_equal(sha256_file(path), raw_expected, name + " raw SHA-256")
        document = strict_json_load(path)
        payload = sha256_bytes(canonical_json_bytes(document["deterministic_payload"]))
        require_equal(payload, payload_expected, name + " payload SHA-256")
        require_equal(
            prereg["predecessors"][name]["raw_sha256"],
            raw_expected,
            name + " declared raw SHA-256",
        )
        require_equal(
            prereg["predecessors"][name]["payload_sha256"],
            payload_expected,
            name + " declared payload SHA-256",
        )
        predecessor_record[name] = {
            "path": str(path.relative_to(REPO)),
            "raw_sha256": raw_expected,
            "payload_sha256": payload_expected,
        }
    require_equal(sha256_file(X0_RUNNER), X0_RUNNER_SHA256, "X0 runner SHA-256")
    require_equal(sha256_file(WIDE_RUNNER), WIDE_RUNNER_SHA256, "wide runner SHA-256")

    x0 = strict_json_load(X0_RECEIPT)["deterministic_payload"]
    require_equal(
        x0["verdicts"]["mixed_four_round_bound"],
        "OPEN_NOT_GRADED",
        "X0 mixed four-round bound status",
    )

    makefile = MAKEFILE.read_text(encoding="utf-8")
    for target in ("e256-x1-mixed-walk-activity:", "e256-x1-mixed-walk-activity-check:"):
        require_true(target in makefile, "missing Make target " + target)

    return {
        "contract_path": str(CONTRACT.relative_to(REPO)),
        "contract_inclusive_sha256": CONTRACT_SHA256,
        "preregistration_path": str(PREREG.relative_to(REPO)),
        "preregistration_raw_sha256": PREREG_SHA256,
        "x0_contract_inclusive_sha256": X0_CONTRACT_MARKER_SHA256,
        "x0_runner_sha256": X0_RUNNER_SHA256,
        "wide_runner_sha256": WIDE_RUNNER_SHA256,
        "predecessors": predecessor_record,
        "x0_item_closed_by_this_gate": "mixed_four_round_bound",
        "x0_item_prior_status": "OPEN_NOT_GRADED",
        "make_targets_present": True,
    }


# ---------------------------------------------------------------------------
# Deterministic payload assembly.


def build_payload(workers: int, class_limit: Optional[int], progress: bool) -> dict:
    integrity = validate_frozen_inputs()
    catalog = load_catalog()
    supports = characterise_supports(catalog)
    symmetry = verify_catalog_symmetry(catalog)

    classes, quotient_structure = build_canonical_classes(catalog)
    recomputed = len(classes)
    require_equal(recomputed, EXPECTED_CLASS_COUNT, "canonical class count")
    require_equal(
        quotient_structure["row_rotation_orbit_sizes"], [ROWS], "row-rotation orbit sizes"
    )
    graded_classes = classes if class_limit is None else classes[:class_limit]

    fixed_triples = [(w, w, w) for w in catalog]
    fixed_results = run_sweep(
        fixed_triples, workers, label="fixed-repeated", progress=progress
    )
    fixed_grade = grade_sweep(
        fixed_triples, fixed_results, SMT_BUDGET, ASSERTED_BOUND, "fixed-repeated"
    )

    class_results = run_sweep(
        graded_classes, workers, label="canonical-classes", progress=progress
    )
    class_grade = grade_sweep(
        graded_classes, class_results, SMT_BUDGET, ASSERTED_BOUND, "canonical-classes"
    )

    safe_minima: List[int] = []
    unsafe_minima: List[int] = []
    for triple, record in zip(graded_classes, class_results):
        walk_safe = safe_transition(triple[0], triple[1]) and safe_transition(
            triple[1], triple[2]
        )
        (safe_minima if walk_safe else unsafe_minima).append(record["minimum"])
    require_true(bool(safe_minima), "no X0-safe class present in the graded corpus")
    require_true(bool(unsafe_minima), "no non-safe class present in the graded corpus")

    anchor = [list(FIXED_TUPLE)] * SELECTORS
    anchor_min, anchor_witness = ilp_minimum(anchor)
    require_equal(anchor_min, ASSERTED_BOUND, "anchor minimum")
    require_equal(
        verify_trail(anchor_witness, anchor), ASSERTED_BOUND, "anchor witness weight"
    )
    require_equal(smt_decide(SMT_BUDGET, anchor), "unsat", "anchor SMT lower bound")
    require_equal(smt_decide(ASSERTED_BOUND, anchor), "sat", "anchor SMT achievability")

    alternation = [list(catalog[i]) for i in ALTERNATION_INDICES]
    alternation_min, alternation_witness = ilp_minimum(alternation)
    require_equal(
        verify_trail(alternation_witness, alternation),
        alternation_min,
        "alternation witness weight",
    )
    require_equal(
        smt_decide(SMT_BUDGET, alternation), "unsat", "alternation SMT lower bound"
    )

    exhaustive_records = []
    for indices in EXHAUSTIVE_CROSS_CHECK_TRIPLES:
        offsets = [list(catalog[i]) for i in indices]
        found = exhaustive_below(offsets, EXHAUSTIVE_SUB_BOUND)
        ilp_value, _ = ilp_minimum(offsets)
        smt_sub = smt_decide(EXHAUSTIVE_SUB_BOUND - 1, offsets)
        smt_value = smt_decide(SMT_BUDGET, offsets)
        require_true(
            found is None,
            "exhaustive oracle contradicts the sub-bound for %r" % (indices,),
        )
        require_equal(smt_sub, "unsat", "exhaustive cross-check SMT sub-bound")
        require_equal(ilp_value, ASSERTED_BOUND, "exhaustive cross-check ILP minimum")
        require_equal(smt_value, "unsat", "exhaustive cross-check SMT verdict")
        exhaustive_records.append(
            {
                "catalog_indices": list(indices),
                "tuples": [list(catalog[i]) for i in indices],
                "exhaustive_sub_bound": EXHAUSTIVE_SUB_BOUND,
                "exhaustive_trail_below_sub_bound": False,
                "smt_verdict_at_sub_bound": smt_sub,
                "ilp_minimum": ilp_value,
                "smt_verdict_at_budget": smt_value,
                "three_oracles_agree_on_sub_bound": True,
            }
        )
    exhaustive_exact = []
    for label, tuples, expected in EXHAUSTIVE_EXACT_CASES:
        offsets = [list(t) for t in tuples]
        found = exhaustive_below(offsets, ASSERTED_BOUND)
        ilp_value, ilp_witness = ilp_minimum(offsets)
        require_equal(found, expected, "exhaustive exact minimum for " + label)
        require_equal(ilp_value, expected, "ILP exact minimum for " + label)
        require_equal(
            verify_trail(ilp_witness, offsets), expected, "witness for " + label
        )
        exhaustive_exact.append(
            {
                "case": label,
                "tuples": [list(t) for t in tuples],
                "exhaustive_minimum": found,
                "ilp_minimum": ilp_value,
                "witness_verified_weight": expected,
                "three_oracles_agree_exactly": True,
            }
        )

    orbit_records = []
    for indices in ORBIT_CHECK_TRIPLES:
        base = [list(catalog[i]) for i in indices]
        base_min, _ = ilp_minimum(base)
        moved_minima = []
        for shift, amount in ((1, 1), (3, 2), (5, 3), (7, 0)):
            moved = [
                list(rotate_rows(translate(catalog[i], shift), amount)) for i in indices
            ]
            moved_min, _ = ilp_minimum(moved)
            require_equal(
                moved_min, base_min, "orbit minimum invariance for %r" % (indices,)
            )
            moved_minima.append(moved_min)
        orbit_records.append(
            {
                "catalog_indices": list(indices),
                "base_minimum": base_min,
                "transported_minima": moved_minima,
                "invariant": True,
            }
        )

    controls = run_controls(catalog, recomputed)

    first_minimal = None
    for triple, record in zip(graded_classes, class_results):
        if record["minimum"] == class_grade["global_minimum"]:
            first_minimal = {
                "triple": [list(t) for t in triple],
                "minimum": record["minimum"],
                "witness_layer_weights": record["layer_weights"],
            }
            break

    global_minimum = min(class_grade["global_minimum"], fixed_grade["global_minimum"])
    bound_certified = global_minimum >= ASSERTED_BOUND

    payload = {
        "schema": RECEIPT_SCHEMA,
        "status": STATUS,
        "integrity": integrity,
        "catalog": {
            "count": NODE_COUNT,
            "canonical_sha256": CERTIFIED_SHA256,
            "first_tuple": list(catalog[0]),
            "fixed_tuple": list(FIXED_TUPLE),
            "last_tuple": list(catalog[-1]),
            "support_characterisation": supports,
        },
        "activity_model": {
            "state_bytes": STATE_BYTES,
            "rows": ROWS,
            "columns": COLUMNS,
            "byte_index_rule": "4*column + row",
            "shift_rows_forward": "out[r][c] = in[r][(c + w_r) mod 8]",
            "mix_columns": "AES 4x4 circulant MDS over GF(2^8)/0x11b per column",
            "branch_number": BRANCH_NUMBER,
            "mds_truncated_constraint": "(a = 0 and b = 0) or a + b >= 5",
            "sbox_layers": LAYERS,
            "mix_boundaries": BOUNDARIES,
            "selectors_per_window": SELECTORS,
            "nonzero_condition": "first layer weight >= 1",
            "bound_direction": (
                "every actual differential trail projects to a feasible activity "
                "pattern, so the relaxation minimum is a lower bound on the active "
                "S-box count"
            ),
        },
        "symmetry_quotient": {
            "group_order": SYMMETRY_GROUP_ORDER,
            "per_round_translation": "SR_{w+t} = Rot_t . SR_w",
            "global_row_rotation": "R_rho . SR_w = SR_{R_rho w} . R_rho",
            "catalog_closure": symmetry,
            "quotient_structure": quotient_structure,
            "recomputed_class_count": recomputed,
            "action_is_free": (
                quotient_structure["row_rotation_orbit_sizes"] == [ROWS]
                and symmetry["single_tuple_translation_orbit_sizes"] == [COLUMNS]
            ),
            "class_count_times_orbit_equals_ordered_total": (
                recomputed * SYMMETRY_GROUP_ORDER == NODE_COUNT ** SELECTORS
            ),
            "empirical_orbit_checks": orbit_records,
        },
        "oracle_agreement": {
            "smt_tool": "z3",
            "ilp_tool": "scipy.optimize.milp (HiGHS)",
            "exhaustive_tool": "pure-Python branch and bound",
            "witness_checker": "pure-Python exact re-verification",
            "smt_ilp_agreement_cases": fixed_grade["graded_cases"]
            + class_grade["graded_cases"],
            "smt_ilp_disagreements": 0,
            "witness_verified_cases": fixed_grade["graded_cases"]
            + class_grade["graded_cases"],
            "witness_failures": 0,
            "exhaustive_scope": (
                "the pure-Python oracle rules out every trail below the sub-bound on "
                "the non-degenerate cross-check triples and reproduces the exact "
                "minimum on the degenerate cases; it does not independently reach the "
                "asserted bound, whose lower-bound direction rests on the SMT arm"
            ),
            "exhaustive_sub_bound": EXHAUSTIVE_SUB_BOUND,
            "exhaustive_cross_checks": exhaustive_records,
            "exhaustive_exact_agreement": exhaustive_exact,
            "anchor": {
                "tuples": [list(FIXED_TUPLE)] * SELECTORS,
                "minimum": anchor_min,
                "witness_layer_weights": [weight(p) for p in anchor_witness],
                "smt_unsat_at_budget": True,
                "smt_sat_at_bound": True,
                "matches_inherited_fixed_selector_value": anchor_min == ASSERTED_BOUND,
            },
            "x0_fallback_alternation": {
                "catalog_indices": list(ALTERNATION_INDICES),
                "tuples": [list(catalog[i]) for i in ALTERNATION_INDICES],
                "minimum": alternation_min,
                "witness_layer_weights": [weight(p) for p in alternation_witness],
                "smt_unsat_at_budget": True,
            },
        },
        "coverage": {
            "smt_budget": SMT_BUDGET,
            "asserted_lower_bound": ASSERTED_BOUND,
            "fixed_repeated": fixed_grade,
            "canonical_classes": class_grade,
            "canonical_classes_graded": len(graded_classes),
            "canonical_classes_total": recomputed,
            "complete_family_graded": class_limit is None,
            "ordered_triples_represented": (
                None if class_limit is not None else NODE_COUNT ** 3
            ),
        },
        "safe_subfamily": {
            "safe_rule": "S(w_1)+S(w_2) = Z_8 and S(w_2)+S(w_3) = Z_8",
            "safe_class_count": len(safe_minima),
            "safe_minimum": min(safe_minima),
            "non_safe_class_count": len(unsafe_minima),
            "non_safe_minimum": min(unsafe_minima),
            "safety_changes_the_bound": min(safe_minima) != min(unsafe_minima),
            "interpretation": (
                "the X0 safe-transition criterion governs dependency completeness, "
                "not the activity lower bound"
            ),
        },
        "diagnostics": {
            "global_minimum": global_minimum,
            "first_class_attaining_global_minimum": first_minimal,
            "fixed_tuple_minimum": anchor_min,
            "x0_alternation_minimum": alternation_min,
            "single_trail_arithmetic_on_the_bound": {
                "active_sboxes": global_minimum,
                "differential_log2_upper": -6 * global_minimum,
                "linear_log2_upper": -3 * global_minimum,
                "note": (
                    "arithmetic on the bound using the DDT 4 and |LAT| 32 figures "
                    "already certified by E256-062; not new evidence and not a "
                    "security level"
                ),
            },
        },
        "controls": {
            "expected_ids": list(CONTROL_IDS),
            "detected_count": len(controls),
            "records": controls,
            "all_detected": len(controls) == len(CONTROL_IDS),
        },
        "verdicts": {
            "activity_bound": (
                PASS_VERDICT
                if bound_certified
                else "MIXED_WALK_FOUR_ROUND_ACTIVITY_LOWER_BOUND_REFUTED"
            ),
            "certified_lower_bound": global_minimum,
            "inherited_fixed_selector_value": ASSERTED_BOUND,
            "bound_survives_per_round_switching": bound_certified,
            "architecture_selected": False,
            "round_count_selected": False,
            "production_policy_selected": False,
            "security_claim": False,
            "claim_movement": False,
            "e256_063": "OPEN",
        },
        "non_claims": [
            "the graded quantity is a truncated-relaxation lower bound, not a trail count",
            "no claim that a minimising activity pattern is realisable by actual differences",
            "single trails only; trail clustering is not covered",
            "no differential or linear probability beyond arithmetic already printed by E256-062",
            "no integral, algebraic, cube, meet-in-the-middle, impossible-differential, rebound, slide, invariant-subspace, related-key, related-tweak, multi-user, or TMTO analysis",
            "no side-channel, fault, power, EM, or TVLA evidence",
            "no round count, schedule, evolution policy, key or XOF derivation, architecture, or storage organisation is selected",
            "no RTL enforcement mechanism, Metal or FHE path, or physical FPGA result",
            "a bound that survives switching is not evidence that switching is beneficial",
            "reviewed standard AEAD remains mandatory for real data",
            "E256-063 remains OPEN and no C/H/N row, claim epoch, site assertion, campaign record, or video voiceover moves",
        ],
    }
    require_exact_keys(payload, PAYLOAD_KEYS, "deterministic payload")
    return payload


def advisory_environment() -> dict:
    def tool_version(command: Sequence[str]) -> str:
        try:
            process = subprocess.run(
                command, capture_output=True, text=True, timeout=60, check=False
            )
        except (OSError, subprocess.TimeoutExpired) as error:
            return "unavailable: %s" % error
        text = (process.stdout or "") + (process.stderr or "")
        for line in text.splitlines():
            if line.strip():
                return line.strip()
        return "unavailable"

    import scipy

    return {
        "note": (
            "advisory only and excluded from the deterministic digest; solver "
            "verdicts are reproducible where solver models are not"
        ),
        "python": platform.python_version(),
        "platform": platform.platform(),
        "z3": tool_version(["z3", "--version"]),
        "scipy": scipy.__version__,
        "numpy": np.__version__,
    }


def assemble_record(payload: dict) -> dict:
    payload_bytes = canonical_json_bytes(payload)
    record = {
        "deterministic_payload": payload,
        "deterministic_payload_sha256": sha256_bytes(payload_bytes),
        "record_sha256": None,
        "environment_advisory_excluded_from_digest": advisory_environment(),
        "no_wall_clock": NO_WALL_CLOCK,
    }
    require_exact_keys(record, OUTER_KEYS, "receipt record")
    record["record_sha256"] = sha256_bytes(canonical_json_bytes(record))
    return record


def write_scratch(payload: dict) -> dict:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    artifacts = {}
    for name, value in (
        ("catalog-supports.json", payload["catalog"]["support_characterisation"]),
        ("symmetry-quotient.json", payload["symmetry_quotient"]),
        ("coverage.json", payload["coverage"]),
        ("safe-subfamily.json", payload["safe_subfamily"]),
    ):
        path = SCRATCH / name
        data = canonical_json_bytes(value)
        path.write_bytes(data)
        artifacts[name] = sha256_bytes(data)
    return artifacts


def emit(workers: int, progress: bool) -> dict:
    payload = build_payload(workers, None, progress)
    record = assemble_record(payload)
    artifacts = write_scratch(payload)
    RECEIPT.parent.mkdir(parents=True, exist_ok=True)
    RECEIPT.write_text(
        json.dumps(record, indent=2, sort_keys=True, allow_nan=False) + "\n",
        encoding="utf-8",
    )
    print("EMIT PASS")
    print("  receipt                %s" % RECEIPT.relative_to(REPO))
    print("  raw sha256             %s" % sha256_file(RECEIPT))
    print("  payload sha256         %s" % record["deterministic_payload_sha256"])
    print("  record sha256          %s" % record["record_sha256"])
    print("  certified lower bound  %d" % payload["verdicts"]["certified_lower_bound"])
    print("  verdict                %s" % payload["verdicts"]["activity_bound"])
    print(
        "  canonical classes      %d"
        % payload["coverage"]["canonical_classes_graded"]
    )
    print("  controls detected      %d/%d" % (payload["controls"]["detected_count"], len(CONTROL_IDS)))
    for name, digest in sorted(artifacts.items()):
        print("  scratch %-22s %s" % (name, digest))
    return record


def check(workers: int, progress: bool) -> dict:
    require_true(RECEIPT.exists(), "receipt is absent; run the emit target first")
    stored = strict_json_load(RECEIPT)
    require_exact_keys(stored, OUTER_KEYS, "stored receipt record")
    payload = build_payload(workers, None, progress)
    regenerated = canonical_json_bytes(payload)
    stored_bytes = canonical_json_bytes(stored["deterministic_payload"])
    require_equal(
        sha256_bytes(regenerated),
        sha256_bytes(stored_bytes),
        "regenerated deterministic payload digest",
    )
    require_equal(regenerated, stored_bytes, "regenerated deterministic payload bytes")
    require_equal(
        stored["deterministic_payload_sha256"],
        sha256_bytes(stored_bytes),
        "stored payload digest",
    )
    probe = dict(stored)
    probe["record_sha256"] = None
    require_equal(
        stored["record_sha256"],
        sha256_bytes(canonical_json_bytes(probe)),
        "stored record digest",
    )
    print("CHECK PASS")
    print("  payload sha256  %s" % stored["deterministic_payload_sha256"])
    print("  record sha256   %s" % stored["record_sha256"])
    print("  payload_bytes_match True")
    print("  digest_match         True")
    return stored


def self_test(workers: int) -> None:
    receipt_before = RECEIPT.exists()
    scratch_before = SCRATCH.exists()
    payload = build_payload(workers, SELF_TEST_CLASS_LIMIT, False)
    record = assemble_record(payload)
    require_equal(payload["status"], STATUS, "self-test status")
    require_true(
        payload["controls"]["all_detected"], "self-test controls not all detected"
    )
    require_equal(
        payload["coverage"]["complete_family_graded"], False, "self-test coverage flag"
    )
    require_true(
        payload["verdicts"]["certified_lower_bound"] >= ASSERTED_BOUND,
        "self-test bound",
    )
    require_equal(RECEIPT.exists(), receipt_before, "self-test must not create a receipt")
    require_equal(
        SCRATCH.exists(), scratch_before, "self-test must not create the scratch tree"
    )
    print("SELF-TEST PASS")
    print("  graded classes        %d" % payload["coverage"]["canonical_classes_graded"])
    print("  fixed-repeated cases  %d" % payload["coverage"]["fixed_repeated"]["graded_cases"])
    print("  controls detected     %d/%d" % (payload["controls"]["detected_count"], len(CONTROL_IDS)))
    print("  provisional payload   %s" % record["deterministic_payload_sha256"])


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify without emitting")
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="reduced-coverage validation that emits no receipt or scratch tree",
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=min(14, (os.cpu_count() or 4)),
        help="parallel solver workers",
    )
    parser.add_argument(
        "--progress", action="store_true", help="write sweep progress to stderr"
    )
    args = parser.parse_args(argv)
    require_true(args.workers >= 1, "worker count must be positive")
    try:
        if args.self_test:
            self_test(args.workers)
        elif args.check:
            check(args.workers, args.progress)
        else:
            emit(args.workers, args.progress)
    except GateError as error:
        print("GATE FAIL: %s" % error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
