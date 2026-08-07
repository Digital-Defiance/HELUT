#!/usr/bin/env python3
"""Derive and verify the frozen E256-X0 H4 safe-transition certificate.

This is a pure-standard-library structural gate.  It does not implement or
select a production cipher, security level, RTL architecture, or mixed-walk
wide-trail theorem.
"""

import argparse
import functools
import hashlib
import json
import os
import platform
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Dict, Iterable, List, Mapping, Optional, Sequence, Tuple


REPO = Path(__file__).resolve().parent.parent
PREREG = REPO / "directives/e256-x0-h4-evolution-preregistration.json"
CONTRACT = REPO / "directives/e256-x0-h4-evolution.md"
H4_ARCHITECTURE = REPO / "directives/e256-hardware-architecture.md"
H4_PREREG = REPO / "directives/e256-hardware-h4-sequence-preregistration.json"
H4_RUNNER = REPO / "Scripts/e256_hardware_h4_sequence_gate.py"
H4_RTL = REPO / "Hardware/RTL/Research/E256H/e256h_h4_sequence_core.v"
H4_TESTBENCH = REPO / "Hardware/Testbenches/Research/E256H/e256h_h4_sequence_core_tb.v"
CANDIDATE_RECEIPT = REPO / "logs/e256-hardware-candidate-gate.json"
H4_RECEIPT = REPO / "logs/e256-hardware-h4-sequence-gate.json"
MAKEFILE = REPO / "Makefile"
RECEIPT = REPO / "logs/e256-x0-h4-evolution-gate.json"
SCRATCH = REPO / "build/e256-x0-h4-evolution"

PREREG_SHA256 = "d39759bc2677fa17227ea129fc3ec20791a749cec2b9cdd33aa18c45df338711"
CONTRACT_SHA256 = "1ef354e9b933838eb3e74b32b202e4693f1bfdd62379f10dbc6a8673b3383962"
H4_ARCHITECTURE_SHA256 = "aac50bda525ead96234fc3c0e3e3692fabbde101de34d44f632d6a65bfbed1e4"
H4_PREREG_SHA256 = "b7afcc67ceac142a800468362ee0c97fcf6c7b6843f0cdd2f96f5d77894fc8e2"
H4_RUNNER_SHA256 = "f451077a706ff3cc6a13f676b5c1ba3cc9f367c77ebcb4f0cb0f67abf8b4f2ee"
H4_RTL_SHA256 = "d6d9dd85b663a1dad02ced8ffe2c375130d322f6ccbcfb16a83734871031f7e8"
H4_TESTBENCH_SHA256 = "8c06092ecaba633d62461ca6072d066a8505b19ebc45ef8551921144204464ec"
CANDIDATE_RAW_SHA256 = "0402a53a725f3303ab379bf7f5e986a55cadedb001f4621d9d996f4ee0d93cfc"
CANDIDATE_PAYLOAD_SHA256 = "98af83ec27093787552475fce588f84a902634afcc969bed26462032dddec3cc"
H4_RECEIPT_RAW_SHA256 = "9d06dcca6d83d1f9bcc04806f8fbb1e12cf7b66f390069fe3b4ad90edeaf34e6"
H4_PAYLOAD_SHA256 = "4562482417cb2917208cf37f8c4441efbdde602230d878ba49d249b017822064"
H4_RECORD_SHA256 = "4e53a53caa1da8bee7f45c572f6208624fd02703d358cdfb52ca9a31c98e0bae"
CERTIFIED_SHA256 = "199f1f7bddccf19ce5aa0bde0987441735d628354140d53ebdfec538d7b3f5ed"

CONTRACT_START = "<!-- E256-X0-H4-EVOLUTION-CONTRACT-START -->"
CONTRACT_END = "<!-- E256-X0-H4-EVOLUTION-CONTRACT-END -->"
H4_CONTRACT_START = "<!-- E256-H-H4-SEQUENCE-CONTRACT-START -->"
H4_CONTRACT_END = "<!-- E256-H-H4-SEQUENCE-CONTRACT-END -->"
GRAPH_DOMAIN = b"E256-X0/H4-safe-graph/v1"
GRAPH_SCHEMA = "E256-X0-H4-SAFE-GRAPH-1"
PATH_SCHEMA = "E256-X0-H4-PATH-CERTIFICATE-1"
PREREG_SCHEMA = "E256-X0-H4-EVOLUTION-PREREGISTRATION-1"
RECEIPT_SCHEMA = "E256-X0-H4-EVOLUTION-GATE-1"
STATUS = "OPEN_PROGRESS"
NO_WALL_CLOCK = (
    "No wall-clock timestamp is asserted; deterministic inputs and outputs are graded."
)

NODE_COUNT = 384
SUPPORT_COUNT = 16
PERMUTATIONS_PER_SUPPORT = 24
ROW_BYTES = 48
BITSET_BYTES = 18432
PAIR_COUNT = 147456
FIRST_SELECTOR_CASES = 98304
TRANSLATION_CASES = 2048
EXPECTED_SAFE_PAIRS = 73728
EXPECTED_UNSAFE_PAIRS = 73728
EXPECTED_FAILED_PLACEMENTS = 737280
STATE_BYTES = 32
FULL_DEPENDENCY_MASK = (1 << STATE_BYTES) - 1
FULL_SUPPORT_MASK = 0xFF
WALK_LENGTHS = (1, 2, 3, 11)
PATH_SELECTORS = 12
PATH_TRANSITIONS = 11

CONTROL_IDS = (
    "catalog_reorder",
    "stale_catalog_hash",
    "tuple_element_mutation",
    "duplicate_tuple_offset",
    "out_of_range_tuple_offset",
    "wrong_xy_pair",
    "xor_sumset",
    "wrong_modulus",
    "omitted_support_element",
    "graph_bit_flip",
    "reversed_bit_order",
    "missing_graph_row",
    "duplicate_graph_row",
    "stale_graph_root",
    "forged_graph_root",
    "insert_unsafe_edge",
    "remove_safe_edge",
    "filtered_pair_corpus",
    "tuple_code_index_mismatch",
    "out_of_range_path_index",
    "truncated_path",
    "known_unsafe_transition",
    "missing_scc_cycle_observation",
)

PAYLOAD_KEYS = (
    "schema",
    "status",
    "integrity",
    "catalog",
    "algebraic_equivalence",
    "prior_census_reconstruction",
    "safe_graph",
    "support_quotient",
    "diagnostics",
    "path_certificate_controls",
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
DIAGNOSTIC_KEYS = (
    "degree_vectors",
    "degree_histograms",
    "edge_classes",
    "full_graph_sccs",
    "first_unsafe_pair",
    "first_support_changing_safe_two_cycle",
    "walk_counts",
)
QUOTIENT_KEYS = (
    "schema",
    "support_masks",
    "support_elements",
    "adjacency",
    "directed_edge_count",
    "sccs",
    "hamiltonian_cycle_dp",
)


class GateError(RuntimeError):
    """A frozen identity, coverage, oracle, graph, or certificate failure."""


# ---------------------------------------------------------------------------
# Strict JSON and canonical hashing.


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


def validate_deterministic_types(value, path: str = "payload") -> None:
    if value is None or type(value) in (bool, int, str):
        return
    if isinstance(value, list):
        for index, item in enumerate(value):
            validate_deterministic_types(item, "%s[%d]" % (path, index))
        return
    if isinstance(value, dict):
        for key, item in value.items():
            if type(key) is not str:
                raise GateError("non-string deterministic key at " + path)
            validate_deterministic_types(item, path + "." + key)
        return
    raise GateError(
        "non-canonical deterministic value at %s: %s"
        % (path, type(value).__name__)
    )


def canonical_json_bytes(value, deterministic: bool = True) -> bytes:
    if deterministic:
        validate_deterministic_types(value)
    return json.dumps(
        value, sort_keys=True, separators=(",", ":"), allow_nan=False
    ).encode("utf-8")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    try:
        return sha256_bytes(path.read_bytes())
    except OSError as error:
        raise GateError("could not read %s: %s" % (path, error)) from error


def _diagnostic_value(value) -> str:
    if isinstance(value, bytes):
        return "bytes(len=%d,sha256=%s)" % (len(value), sha256_bytes(value))
    if isinstance(value, (set, frozenset)):
        ordered = sorted(repr(item) for item in value)
        encoded = "\n".join(ordered).encode("utf-8")
        return "%s(len=%d,sha256=%s)" % (
            type(value).__name__, len(value), sha256_bytes(encoded)
        )
    if isinstance(value, (list, tuple, dict)) and len(value) > 64:
        encoded = canonical_json_bytes(value, deterministic=False)
        return "%s(len=%d,sha256=%s)" % (
            type(value).__name__, len(value), sha256_bytes(encoded)
        )
    return repr(value)


def require_equal(actual, expected, label: str) -> None:
    if actual != expected:
        raise GateError(
            "%s mismatch: expected %s, got %s"
            % (label, _diagnostic_value(expected), _diagnostic_value(actual))
        )


def require_true(condition: bool, label: str) -> None:
    if not condition:
        raise GateError(label)


def require_exact_keys(value: Mapping, expected: Sequence[str], label: str) -> None:
    require_true(isinstance(value, dict), label + " is not an object")
    require_equal(sorted(value), sorted(expected), label + " keys")
    require_equal(len(value), len(expected), label + " key count")


def update_record_hash(hasher, record: Mapping) -> None:
    encoded = canonical_json_bytes(dict(record))
    require_true(len(encoded) < 2 ** 32, "aggregate record exceeds four-byte length")
    hasher.update(len(encoded).to_bytes(4, "big"))
    hasher.update(encoded)


def atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_bytes(data)
    os.replace(str(temporary), str(path))


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
# Frozen identities, predecessors, catalog, and Make entry points.


def validate_makefile_targets() -> dict:
    text = MAKEFILE.read_text(encoding="utf-8")
    require_equal(
        text.count("e256-x0-h4-evolution:"), 1, "X0 emit target count"
    )
    require_equal(
        text.count("e256-x0-h4-evolution-check:"), 1, "X0 check target count"
    )
    require_true(
        re.search(
            r"(?m)^e256-x0-h4-evolution:\n\tpython3 Scripts/e256_x0_h4_evolution_gate\.py$",
            text,
        )
        is not None,
        "X0 emit target recipe drift",
    )
    require_true(
        re.search(
            r"(?m)^e256-x0-h4-evolution-check:\n\tpython3 Scripts/e256_x0_h4_evolution_gate\.py --check$",
            text,
        )
        is not None,
        "X0 check target recipe drift",
    )
    phony_lines = [line for line in text.splitlines() if line.startswith(".PHONY:")]
    require_true(
        any(
            "e256-x0-h4-evolution" in line
            and "e256-x0-h4-evolution-check" in line
            for line in phony_lines
        ),
        "X0 targets are not both phony",
    )
    return {
        "path": str(MAKEFILE.relative_to(REPO)),
        "emit_recipe_exact": True,
        "check_recipe_exact": True,
        "phony_declared": True,
    }


def validate_predecessor(
    path: Path,
    expected_raw: str,
    expected_schema: str,
    expected_payload: str,
    expected_record: Optional[str] = None,
) -> Tuple[dict, dict]:
    require_equal(sha256_file(path), expected_raw, path.name + " raw SHA-256")
    outer = strict_json_load(path)
    payload = outer.get("deterministic_payload")
    require_true(isinstance(payload, dict), path.name + " deterministic payload absent")
    require_equal(payload.get("schema"), expected_schema, path.name + " schema")
    require_equal(payload.get("status"), STATUS, path.name + " status")
    recomputed = sha256_bytes(canonical_json_bytes(payload, deterministic=False))
    require_equal(recomputed, expected_payload, path.name + " payload digest")
    require_equal(
        outer.get("deterministic_payload_sha256"),
        expected_payload,
        path.name + " stored payload digest",
    )
    if expected_record is not None:
        require_equal(outer.get("record_sha256"), expected_record, path.name + " record hash")
        unhashed = dict(outer)
        unhashed["record_sha256"] = None
        require_equal(
            sha256_bytes(canonical_json_bytes(unhashed, deterministic=False)),
            expected_record,
            path.name + " recomputed record hash",
        )
    return outer, payload


def support_mask(wiring: Sequence[int]) -> int:
    mask = 0
    for value in wiring:
        mask |= 1 << int(value)
    return mask


def support_elements(mask: int) -> List[int]:
    return [value for value in range(8) if (mask >> value) & 1]


def tuple_code(wiring: Sequence[int]) -> int:
    return sum(int(value) << (3 * row) for row, value in enumerate(wiring))


def validate_catalog(catalog, claimed_digest: str = CERTIFIED_SHA256) -> List[List[int]]:
    require_true(isinstance(catalog, list), "certified catalog is not an array")
    require_equal(len(catalog), NODE_COUNT, "certified catalog count")
    normalized = []
    for index, wiring in enumerate(catalog):
        require_true(
            isinstance(wiring, list) and len(wiring) == 4,
            "catalog tuple %d shape" % index,
        )
        require_true(
            all(type(value) is int and 0 <= value < 8 for value in wiring),
            "catalog tuple %d offset range" % index,
        )
        require_equal(len(set(wiring)), 4, "catalog tuple %d distinctness" % index)
        normalized.append(list(wiring))
    require_equal(
        len({tuple(wiring) for wiring in normalized}),
        NODE_COUNT,
        "catalog tuple uniqueness",
    )
    digest = sha256_bytes(canonical_json_bytes(normalized))
    require_equal(claimed_digest, CERTIFIED_SHA256, "claimed certified catalog digest")
    require_equal(digest, claimed_digest, "recomputed certified catalog digest")
    require_equal(normalized[0], [0, 1, 2, 5], "first certified tuple")
    require_equal(normalized[1], [0, 1, 3, 4], "fixed certified tuple")
    require_equal(normalized[-1], [7, 6, 5, 2], "last certified tuple")

    by_support: Dict[int, List[Tuple[int, ...]]] = {}
    for wiring in normalized:
        by_support.setdefault(support_mask(wiring), []).append(tuple(wiring))
    require_equal(len(by_support), SUPPORT_COUNT, "support-class count")
    for mask, tuples in by_support.items():
        require_equal(
            len(tuples), PERMUTATIONS_PER_SUPPORT, "support-class multiplicity"
        )
        expected = set(__import__("itertools").permutations(support_elements(mask), 4))
        require_equal(set(tuples), expected, "support permutation closure")
    return normalized


def validate_contract_shape(prereg: Mapping) -> None:
    require_equal(prereg.get("schema"), PREREG_SCHEMA, "preregistration schema")
    require_equal(
        prereg.get("status"), "FROZEN_BEFORE_IMPLEMENTATION", "preregistration status"
    )
    require_equal(
        prereg["contract"]["inclusive_sha256"],
        CONTRACT_SHA256,
        "declared contract digest",
    )
    require_equal(
        tuple(item["id"] for item in prereg["controls"]),
        CONTROL_IDS,
        "control IDs",
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
    require_equal(prereg["catalog"]["count"], NODE_COUNT, "catalog count contract")
    require_equal(
        prereg["catalog"]["canonical_sha256"],
        CERTIFIED_SHA256,
        "catalog hash contract",
    )
    require_equal(
        prereg["graph_contract"]["bitset_bytes"], BITSET_BYTES, "graph bytes contract"
    )
    require_equal(
        prereg["graph_contract"]["prior_consistency_edge_count"],
        EXPECTED_SAFE_PAIRS,
        "prior edge count contract",
    )
    require_equal(
        prereg["algebraic_contract"]["ordered_pair_count"],
        PAIR_COUNT,
        "pair count contract",
    )
    require_equal(
        prereg["algebraic_contract"]["first_selector_invariance_cases"],
        FIRST_SELECTOR_CASES,
        "first-selector case contract",
    )
    require_equal(
        prereg["algebraic_contract"]["translation_invariance_cases"],
        TRANSLATION_CASES,
        "translation case contract",
    )
    require_equal(
        tuple(prereg["diagnostics_contract"]["walk_lengths"]),
        WALK_LENGTHS,
        "walk lengths",
    )
    require_equal(
        prereg["path_certificate_contract"]["selector_count"],
        PATH_SELECTORS,
        "path selector count",
    )
    require_equal(
        prereg["path_certificate_contract"]["transition_count"],
        PATH_TRANSITIONS,
        "path transition count",
    )
    require_equal(
        prereg["toolchain"]["python_required_exact"], "3.9.6", "Python pin"
    )


def validate_integrity() -> Tuple[dict, Mapping, List[List[int]], Mapping]:
    require_equal(sha256_file(PREREG), PREREG_SHA256, "raw preregistration SHA-256")
    prereg = strict_json_load(PREREG)
    validate_deterministic_types(prereg, "preregistration")
    validate_contract_shape(prereg)
    require_equal(sys.version.split()[0], "3.9.6", "running Python version")

    contract_raw = CONTRACT.read_bytes()
    require_equal(
        marker_digest_inclusive(contract_raw, CONTRACT_START, CONTRACT_END),
        CONTRACT_SHA256,
        "X0 inclusive contract marker",
    )
    require_equal(sha256_file(H4_PREREG), H4_PREREG_SHA256, "frozen H4 preregistration")
    require_equal(sha256_file(H4_RUNNER), H4_RUNNER_SHA256, "frozen H4 runner")
    require_equal(sha256_file(H4_RTL), H4_RTL_SHA256, "frozen H4 RTL")
    require_equal(sha256_file(H4_TESTBENCH), H4_TESTBENCH_SHA256, "frozen H4 testbench")
    require_equal(
        marker_digest_inclusive(
            H4_ARCHITECTURE.read_bytes(), H4_CONTRACT_START, H4_CONTRACT_END
        ),
        H4_ARCHITECTURE_SHA256,
        "frozen H4 architecture marker",
    )

    candidate_outer, candidate = validate_predecessor(
        CANDIDATE_RECEIPT,
        CANDIDATE_RAW_SHA256,
        "E256-HARDWARE-CANDIDATE-GATE-1",
        CANDIDATE_PAYLOAD_SHA256,
    )
    h4_outer, h4 = validate_predecessor(
        H4_RECEIPT,
        H4_RECEIPT_RAW_SHA256,
        "E256-HARDWARE-H4-SEQUENCE-GATE-1",
        H4_PAYLOAD_SHA256,
        H4_RECORD_SHA256,
    )
    candidate_h4 = candidate["results"]["h4_wiring"]
    require_equal(
        candidate_h4["certified_set_sha256"], CERTIFIED_SHA256, "stored catalog hash"
    )
    catalog = validate_catalog(candidate_h4["certified_set"])
    require_equal(h4["structural_census"]["failure_count"], EXPECTED_FAILED_PLACEMENTS, "prior H4 failures")
    require_equal(
        h4["structural_census"]["contiguous_three_round_windows"],
        1474560,
        "prior H4 windows",
    )
    require_equal(h4["verdicts"]["harness_valid"], True, "prior H4 harness")
    require_equal(h4["verdicts"]["claim_movement"], False, "prior H4 claim movement")

    predecessors = [
        {
            "id": "E256-063-H4-CANDIDATE-CATALOG",
            "path": str(CANDIDATE_RECEIPT.relative_to(REPO)),
            "schema": candidate["schema"],
            "raw_sha256": CANDIDATE_RAW_SHA256,
            "deterministic_payload_sha256": CANDIDATE_PAYLOAD_SHA256,
        },
        {
            "id": "E256-063-H4-SEQUENCE-CENSUS",
            "path": str(H4_RECEIPT.relative_to(REPO)),
            "schema": h4["schema"],
            "raw_sha256": H4_RECEIPT_RAW_SHA256,
            "deterministic_payload_sha256": H4_PAYLOAD_SHA256,
            "record_sha256": H4_RECORD_SHA256,
        },
    ]
    frozen_sources = {
        "h4_preregistration": {
            "path": str(H4_PREREG.relative_to(REPO)),
            "sha256": H4_PREREG_SHA256,
        },
        "h4_architecture_marker": {
            "path": str(H4_ARCHITECTURE.relative_to(REPO)),
            "inclusive_sha256": H4_ARCHITECTURE_SHA256,
        },
        "h4_runner": {
            "path": str(H4_RUNNER.relative_to(REPO)),
            "sha256": H4_RUNNER_SHA256,
        },
        "h4_rtl": {
            "path": str(H4_RTL.relative_to(REPO)),
            "sha256": H4_RTL_SHA256,
        },
        "h4_testbench": {
            "path": str(H4_TESTBENCH.relative_to(REPO)),
            "sha256": H4_TESTBENCH_SHA256,
        },
    }
    integrity = {
        "preregistration": {
            "path": str(PREREG.relative_to(REPO)),
            "raw_sha256": PREREG_SHA256,
        },
        "contract": {
            "path": str(CONTRACT.relative_to(REPO)),
            "inclusive_sha256": CONTRACT_SHA256,
        },
        "predecessors": predecessors,
        "frozen_sources": frozen_sources,
        "implementation_source": {
            "path": str(Path(__file__).resolve().relative_to(REPO)),
            "sha256": sha256_file(Path(__file__).resolve()),
        },
        "makefile": validate_makefile_targets(),
        "toolchain": {
            "python": sys.version.split()[0],
            "dependencies": "standard-library-only",
            "host_system_advisory": platform.system(),
            "host_machine_advisory": platform.machine(),
        },
        "all_exact": True,
    }
    return integrity, prereg, catalog, h4


# ---------------------------------------------------------------------------
# Independent algebraic and literal dependency oracles.


def rotate_support_mask(mask: int, amount: int) -> int:
    amount %= 8
    return ((mask << amount) | (mask >> (8 - amount))) & 0xFF


def sumset_mask(left: int, right: int) -> int:
    result = 0
    for value in range(8):
        if (left >> value) & 1:
            result |= rotate_support_mask(right, value)
    return result


def xor_sumset_mask(left: int, right: int) -> int:
    result = 0
    for a in support_elements(left):
        for b in support_elements(right):
            result |= 1 << (a ^ b)
    return result


def wrong_modulus_sumset_mask(left: int, right: int) -> int:
    result = 0
    for a in support_elements(left):
        for b in support_elements(right):
            result |= 1 << ((a + b) % 7)
    return result


def literal_dependency_vector(sequence: Sequence[Sequence[int]]) -> Tuple[int, ...]:
    require_equal(len(sequence), 3, "literal dependency window length")
    dependencies = [1 << index for index in range(STATE_BYTES)]
    for wiring in sequence:
        require_equal(len(wiring), 4, "literal selector width")
        shifted = [0] * STATE_BYTES
        for column in range(8):
            for row in range(4):
                shifted[4 * column + row] = dependencies[
                    4 * ((column + int(wiring[row])) % 8) + row
                ]
        mixed = [0] * STATE_BYTES
        for column in range(8):
            union = (
                shifted[4 * column]
                | shifted[4 * column + 1]
                | shifted[4 * column + 2]
                | shifted[4 * column + 3]
            )
            for row in range(4):
                mixed[4 * column + row] = union
        dependencies = mixed
    return tuple(dependencies)


def closed_form_dependency_vector(
    x: Sequence[int], y: Sequence[int], z: Sequence[int]
) -> Tuple[int, ...]:
    yz = sumset_mask(support_mask(y), support_mask(z))
    output = []
    deltas = support_elements(yz)
    for column in range(8):
        value = 0
        for original_row in range(4):
            for delta in deltas:
                source_column = (column + int(x[original_row]) + delta) % 8
                value |= 1 << (4 * source_column + original_row)
        for _output_row in range(4):
            output.append(value)
    return tuple(output)


def vector_is_full(vector: Sequence[int]) -> bool:
    return all(value == FULL_DEPENDENCY_MASK for value in vector)


def vector_digest(vector: Sequence[int]) -> str:
    return sha256_bytes(b"".join(int(value).to_bytes(4, "big") for value in vector))


def first_incomplete(vector: Sequence[int]) -> Optional[dict]:
    for lane, value in enumerate(vector):
        if value != FULL_DEPENDENCY_MASK:
            return {
                "output_lane": lane,
                "missing_input_lanes": [
                    source for source in range(STATE_BYTES) if not ((value >> source) & 1)
                ],
            }
    return None


def build_ordered_pair_corpus() -> List[Tuple[int, int]]:
    return [
        (source, destination)
        for source in range(NODE_COUNT)
        for destination in range(NODE_COUNT)
    ]


def validate_ordered_pair_corpus(
    corpus: Sequence[Tuple[int, int]],
) -> dict:
    identity_hasher = hashlib.sha256()
    seen = set()
    count = 0
    for position, pair in enumerate(corpus):
        require_true(
            isinstance(pair, (list, tuple)) and len(pair) == 2,
            "ordered pair corpus record shape",
        )
        source, destination = pair
        require_true(
            type(source) is int
            and type(destination) is int
            and 0 <= source < NODE_COUNT
            and 0 <= destination < NODE_COUNT,
            "ordered pair corpus record range",
        )
        expected = divmod(position, NODE_COUNT)
        require_equal(
            (source, destination),
            expected,
            "ordered pair corpus identity at position %d" % position,
        )
        require_true(
            (source, destination) not in seen,
            "duplicate ordered pair corpus identity",
        )
        seen.add((source, destination))
        update_record_hash(
            identity_hasher, {"i": source, "j": destination}
        )
        count += 1
    require_equal(count, PAIR_COUNT, "ordered algebraic pair coverage")
    require_equal(len(seen), PAIR_COUNT, "ordered algebraic pair uniqueness")
    return {
        "count": count,
        "unique_count": len(seen),
        "identity_aggregate_sha256": identity_hasher.hexdigest(),
        "lexicographic_order_exact": True,
    }


def run_algebraic_equivalence(
    catalog: Sequence[Sequence[int]], graph_bytes: bytes
) -> dict:
    pair_corpus = build_ordered_pair_corpus()
    pair_coverage = validate_ordered_pair_corpus(pair_corpus)
    pair_hasher = hashlib.sha256()
    safe_count = 0
    unsafe_count = 0
    pair_count = 0
    x = catalog[0]
    for i, j in pair_corpus:
        y = catalog[i]
        z = catalog[j]
        literal = literal_dependency_vector((x, y, z))
        closed = closed_form_dependency_vector(x, y, z)
        require_equal(literal, closed, "literal/closed-form vector at (%d,%d)" % (i, j))
        sumset_safe = sumset_mask(support_mask(y), support_mask(z)) == FULL_SUPPORT_MASK
        literal_safe = vector_is_full(literal)
        require_equal(literal_safe, sumset_safe, "sumset/literal verdict at (%d,%d)" % (i, j))
        require_equal(
            edge_at(graph_bytes, i, j), sumset_safe, "graph/algebraic verdict at (%d,%d)" % (i, j)
        )
        safe_count += int(sumset_safe)
        unsafe_count += int(not sumset_safe)
        update_record_hash(
            pair_hasher,
            {
                "i": i,
                "j": j,
                "safe": sumset_safe,
                "dependency_vector_sha256": vector_digest(literal),
            },
        )
        pair_count += 1
    require_equal(pair_count, PAIR_COUNT, "ordered algebraic pair coverage")
    require_equal(safe_count, EXPECTED_SAFE_PAIRS, "safe ordered pair count")
    require_equal(unsafe_count, EXPECTED_UNSAFE_PAIRS, "unsafe ordered pair count")

    masks = sorted({support_mask(wiring) for wiring in catalog})
    representative = {
        mask: min(index for index, wiring in enumerate(catalog) if support_mask(wiring) == mask)
        for mask in masks
    }
    first_hasher = hashlib.sha256()
    first_cases = 0
    for x_index, first in enumerate(catalog):
        for y_mask in masks:
            y_index = representative[y_mask]
            for z_mask in masks:
                z_index = representative[z_mask]
                literal = literal_dependency_vector(
                    (first, catalog[y_index], catalog[z_index])
                )
                closed = closed_form_dependency_vector(
                    first, catalog[y_index], catalog[z_index]
                )
                require_equal(
                    literal,
                    closed,
                    "first-selector vector invariance at (%d,%d,%d)"
                    % (x_index, y_index, z_index),
                )
                require_equal(
                    vector_is_full(literal),
                    sumset_mask(y_mask, z_mask) == FULL_SUPPORT_MASK,
                    "first-selector safe invariance",
                )
                update_record_hash(
                    first_hasher,
                    {
                        "x": x_index,
                        "y_support": y_mask,
                        "z_support": z_mask,
                        "dependency_vector_sha256": vector_digest(literal),
                    },
                )
                first_cases += 1
    require_equal(first_cases, FIRST_SELECTOR_CASES, "first-selector invariance coverage")

    translation_hasher = hashlib.sha256()
    translation_cases = 0
    for left in masks:
        for right in masks:
            base = sumset_mask(left, right)
            for translation in range(8):
                translated = sumset_mask(rotate_support_mask(left, translation), right)
                require_equal(
                    translated,
                    rotate_support_mask(base, translation),
                    "sumset translation identity",
                )
                require_equal(
                    translated == FULL_SUPPORT_MASK,
                    base == FULL_SUPPORT_MASK,
                    "sumset translation safe invariance",
                )
                update_record_hash(
                    translation_hasher,
                    {
                        "left": left,
                        "right": right,
                        "translation": translation,
                        "sumset": translated,
                    },
                )
                translation_cases += 1
    require_equal(translation_cases, TRANSLATION_CASES, "translation invariance coverage")

    return {
        "closed_form": "c+x_a+y_b+z_k mod 8",
        "safe_criterion": "S(y)+S(z)=Z8",
        "ordered_pair_cases": pair_count,
        "ordered_pair_unique_cases": pair_coverage["unique_count"],
        "ordered_pair_identity_aggregate_sha256": pair_coverage[
            "identity_aggregate_sha256"
        ],
        "ordered_pair_lexicographic_order_exact": pair_coverage[
            "lexicographic_order_exact"
        ],
        "safe_pairs": safe_count,
        "unsafe_pairs": unsafe_count,
        "pair_vector_aggregate_sha256": pair_hasher.hexdigest(),
        "literal_and_closed_form_vectors_exact": True,
        "sumset_and_literal_verdicts_exact": True,
        "first_selector_invariance_cases": first_cases,
        "first_selector_invariance_aggregate_sha256": first_hasher.hexdigest(),
        "translation_invariance_cases": translation_cases,
        "translation_invariance_aggregate_sha256": translation_hasher.hexdigest(),
        "complete_no_filtering": True,
    }


# ---------------------------------------------------------------------------
# Canonical graph, quotient, SCC, Hamiltonian DP, and exact walk counts.


def graph_root(bitset: bytes) -> str:
    require_equal(len(bitset), BITSET_BYTES, "graph-root bitset length")
    preimage = (
        GRAPH_DOMAIN
        + b"\x00"
        + NODE_COUNT.to_bytes(2, "big")
        + bytes.fromhex(CERTIFIED_SHA256)
        + bitset
    )
    return sha256_bytes(preimage)


def build_graph(catalog: Sequence[Sequence[int]]) -> Tuple[bytes, List[List[int]]]:
    masks = [support_mask(wiring) for wiring in catalog]
    encoded = bytearray(BITSET_BYTES)
    adjacency: List[List[int]] = [[] for _ in range(NODE_COUNT)]
    for i, left in enumerate(masks):
        for j, right in enumerate(masks):
            if sumset_mask(left, right) == FULL_SUPPORT_MASK:
                encoded[i * ROW_BYTES + j // 8] |= 1 << (j % 8)
                adjacency[i].append(j)
    return bytes(encoded), adjacency


def edge_at(bitset: bytes, source: int, destination: int) -> bool:
    require_true(0 <= source < NODE_COUNT, "edge source out of range")
    require_true(0 <= destination < NODE_COUNT, "edge destination out of range")
    require_equal(len(bitset), BITSET_BYTES, "edge bitset length")
    return bool(
        bitset[source * ROW_BYTES + destination // 8] & (1 << (destination % 8))
    )


def verify_graph_bytes(
    candidate: bytes,
    claimed_root: str,
    expected: bytes,
    expected_root: str,
) -> None:
    require_equal(len(candidate), BITSET_BYTES, "candidate graph bitset length")
    require_equal(candidate, expected, "canonical reconstructed graph bytes")
    require_true(re.fullmatch(r"[0-9a-f]{64}", claimed_root) is not None, "graph root grammar")
    require_equal(graph_root(candidate), expected_root, "recomputed graph root")
    require_equal(claimed_root, expected_root, "claimed graph root")


def histogram(values: Sequence[int]) -> dict:
    counts: Dict[int, int] = {}
    for value in values:
        counts[value] = counts.get(value, 0) + 1
    return {str(key): counts[key] for key in sorted(counts)}


def tarjan_scc(adjacency: Sequence[Sequence[int]]) -> List[List[int]]:
    count = len(adjacency)
    index = 0
    indices = [-1] * count
    lowlink = [0] * count
    stack: List[int] = []
    on_stack = [False] * count
    components: List[List[int]] = []

    def visit(vertex: int) -> None:
        nonlocal index
        indices[vertex] = index
        lowlink[vertex] = index
        index += 1
        stack.append(vertex)
        on_stack[vertex] = True
        for neighbor in sorted(adjacency[vertex]):
            if indices[neighbor] == -1:
                visit(neighbor)
                lowlink[vertex] = min(lowlink[vertex], lowlink[neighbor])
            elif on_stack[neighbor]:
                lowlink[vertex] = min(lowlink[vertex], indices[neighbor])
        if lowlink[vertex] == indices[vertex]:
            component = []
            while True:
                member = stack.pop()
                on_stack[member] = False
                component.append(member)
                if member == vertex:
                    break
            components.append(sorted(component))

    for vertex in range(count):
        if indices[vertex] == -1:
            visit(vertex)
    return sorted(components, key=lambda component: tuple(component))


def quotient_hamiltonian_cycle(adjacency: Sequence[Sequence[int]]) -> dict:
    require_equal(len(adjacency), SUPPORT_COUNT, "quotient node count")
    all_remaining = ((1 << SUPPORT_COUNT) - 1) ^ 1
    states_evaluated = [0]

    @functools.lru_cache(maxsize=None)
    def complete(current: int, remaining: int):
        states_evaluated[0] += 1
        if remaining == 0:
            return () if 0 in adjacency[current] else None
        for neighbor in sorted(adjacency[current]):
            bit = 1 << neighbor
            if remaining & bit:
                suffix = complete(neighbor, remaining ^ bit)
                if suffix is not None:
                    return (neighbor,) + suffix
        return None

    suffix = complete(0, all_remaining)
    if suffix is None:
        cycle = None
        verdict = "FULL_SUPPORT_QUOTIENT_HAMILTONIAN_CYCLE_NOT_FOUND"
        found = False
    else:
        cycle = [0] + list(suffix) + [0]
        require_equal(len(cycle), SUPPORT_COUNT + 1, "Hamiltonian cycle length")
        require_equal(len(set(cycle[:-1])), SUPPORT_COUNT, "Hamiltonian vertex coverage")
        require_true(
            all(cycle[index + 1] in adjacency[cycle[index]] for index in range(SUPPORT_COUNT)),
            "Hamiltonian edge closure",
        )
        verdict = "FULL_SUPPORT_QUOTIENT_HAMILTONIAN_CYCLE_FOUND"
        found = True
    return {
        "algorithm": "exact memoized subset DP with ascending-neighbor reconstruction anchored at node 0",
        "found": found,
        "cycle": cycle,
        "states_evaluated": states_evaluated[0],
        "verdict": verdict,
    }


def integer_log2_bounds(value: int) -> Tuple[int, int]:
    require_true(type(value) is int and value > 0, "walk count is not a positive integer")
    floor = value.bit_length() - 1
    ceil = floor if value == (1 << floor) else floor + 1
    return floor, ceil


def exact_walk_counts(adjacency: Sequence[Sequence[int]]) -> List[dict]:
    vector = [1] * len(adjacency)
    results = []
    requested = set(WALK_LENGTHS)
    for length in range(1, max(WALK_LENGTHS) + 1):
        next_vector = [0] * len(adjacency)
        for source, destinations in enumerate(adjacency):
            value = vector[source]
            for destination in destinations:
                next_vector[destination] += value
        vector = next_vector
        if length in requested:
            count = sum(vector)
            floor, ceil = integer_log2_bounds(count)
            results.append(
                {
                    "length": length,
                    "sum_A_power": count,
                    "floor_log2": floor,
                    "ceil_log2": ceil,
                }
            )
    require_equal(tuple(item["length"] for item in results), WALK_LENGTHS, "walk lengths")
    return results


def build_quotient(catalog: Sequence[Sequence[int]]) -> Tuple[dict, List[List[int]], Dict[int, int]]:
    masks = sorted({support_mask(wiring) for wiring in catalog})
    require_equal(len(masks), SUPPORT_COUNT, "quotient support count")
    index_by_mask = {mask: index for index, mask in enumerate(masks)}
    adjacency: List[List[int]] = [[] for _ in masks]
    for i, left in enumerate(masks):
        for j, right in enumerate(masks):
            if sumset_mask(left, right) == FULL_SUPPORT_MASK:
                adjacency[i].append(j)
    cycle = quotient_hamiltonian_cycle(adjacency)
    record = {
        "schema": "E256-X0-H4-SUPPORT-QUOTIENT-1",
        "support_masks": masks,
        "support_elements": [support_elements(mask) for mask in masks],
        "adjacency": adjacency,
        "directed_edge_count": sum(len(row) for row in adjacency),
        "sccs": tarjan_scc(adjacency),
        "hamiltonian_cycle_dp": cycle,
    }
    require_exact_keys(record, QUOTIENT_KEYS, "support quotient")
    return record, adjacency, index_by_mask


def build_diagnostics(
    catalog: Sequence[Sequence[int]], bitset: bytes, adjacency: Sequence[Sequence[int]]
) -> dict:
    out_degrees = [len(row) for row in adjacency]
    in_degrees = [0] * NODE_COUNT
    loops = 0
    same_support = 0
    support_changing = 0
    masks = [support_mask(wiring) for wiring in catalog]
    first_unsafe = None
    first_support_cycle = None
    for i in range(NODE_COUNT):
        for j in range(NODE_COUNT):
            present = edge_at(bitset, i, j)
            if present:
                in_degrees[j] += 1
                loops += int(i == j)
                if masks[i] == masks[j]:
                    same_support += 1
                else:
                    support_changing += 1
                    if i < j and first_support_cycle is None and edge_at(bitset, j, i):
                        first_support_cycle = {
                            "indices": [i, j, i],
                            "supports": [masks[i], masks[j], masks[i]],
                        }
            elif first_unsafe is None:
                literal = literal_dependency_vector((catalog[0], catalog[i], catalog[j]))
                first_unsafe = {
                    "indices": [i, j],
                    "tuples": [list(catalog[i]), list(catalog[j])],
                    "first_incomplete_output": first_incomplete(literal),
                }
    edge_count = sum(out_degrees)
    require_equal(edge_count, EXPECTED_SAFE_PAIRS, "diagnostic edge count")
    require_equal(sum(in_degrees), edge_count, "in/out edge closure")
    require_equal(loops + (edge_count - loops), edge_count, "loop/off-diagonal closure")
    require_equal(same_support + support_changing, edge_count, "support edge closure")
    require_true(first_unsafe is not None, "first unsafe pair absent")
    require_true(first_support_cycle is not None, "support-changing safe two-cycle absent")
    require_true(
        all(edge_at(bitset, j, i) for i, row in enumerate(adjacency) for j in row),
        "graph relation is not symmetric",
    )
    record = {
        "degree_vectors": {
            "out": out_degrees,
            "in": in_degrees,
            "out_sha256": sha256_bytes(canonical_json_bytes(out_degrees)),
            "in_sha256": sha256_bytes(canonical_json_bytes(in_degrees)),
        },
        "degree_histograms": {
            "out": histogram(out_degrees),
            "in": histogram(in_degrees),
        },
        "edge_classes": {
            "directed_total": edge_count,
            "loops": loops,
            "off_diagonal": edge_count - loops,
            "same_support": same_support,
            "support_changing": support_changing,
            "symmetric": True,
        },
        "full_graph_sccs": tarjan_scc(adjacency),
        "first_unsafe_pair": first_unsafe,
        "first_support_changing_safe_two_cycle": first_support_cycle,
        "walk_counts": exact_walk_counts(adjacency),
    }
    require_exact_keys(record, DIAGNOSTIC_KEYS, "diagnostics")
    return record


def validate_diagnostics(record: Mapping, quotient: Mapping) -> None:
    require_exact_keys(record, DIAGNOSTIC_KEYS, "diagnostics")
    require_exact_keys(quotient, QUOTIENT_KEYS, "support quotient")
    require_true(isinstance(record["full_graph_sccs"], list), "full SCC observation absent")
    require_true(isinstance(quotient["sccs"], list), "quotient SCC observation absent")
    hamiltonian = quotient["hamiltonian_cycle_dp"]
    require_true(isinstance(hamiltonian, dict), "Hamiltonian observation absent")
    require_true("verdict" in hamiltonian and "found" in hamiltonian, "Hamiltonian result incomplete")
    require_equal(
        tuple(item["length"] for item in record["walk_counts"]),
        WALK_LENGTHS,
        "diagnostic walk lengths",
    )


# ---------------------------------------------------------------------------
# Prior-census reconstruction and deterministic path certificate.


def reconstruct_prior_census(
    catalog: Sequence[Sequence[int]], bitset: bytes, prior_h4: Mapping
) -> dict:
    observed_pairs = set()
    stride_failures = [0] * NODE_COUNT
    failed_classes = 0
    mapping_hasher = hashlib.sha256()
    for b in range(NODE_COUNT):
        for d in range(NODE_COUNT):
            i = (b + d) % NODE_COUNT
            j = (b + 2 * d) % NODE_COUNT
            inverse_d = (j - i) % NODE_COUNT
            inverse_b = (2 * i - j) % NODE_COUNT
            require_equal((inverse_b, inverse_d), (b, d), "prior census inverse")
            require_true((i, j) not in observed_pairs, "prior census map is not injective")
            observed_pairs.add((i, j))
            failed = not edge_at(bitset, i, j)
            if failed:
                failed_classes += 1
                stride_failures[d] += 1
            update_record_hash(
                mapping_hasher,
                {"b": b, "d": d, "i": i, "j": j, "failed": failed},
            )
    require_equal(len(observed_pairs), PAIR_COUNT, "prior census pair coverage")
    require_equal(failed_classes, EXPECTED_UNSAFE_PAIRS, "prior failed classes")
    failed_placements = failed_classes * 10
    require_equal(failed_placements, EXPECTED_FAILED_PLACEMENTS, "prior failed placements")
    zero_failure_strides = [d for d, count in enumerate(stride_failures) if count == 0]
    require_equal(zero_failure_strides, [0], "disclosed zero-failure strides")

    first = None
    for a in range(NODE_COUNT):
        if first is not None:
            break
        for d in range(NODE_COUNT):
            if first is not None:
                break
            for start_round in range(10):
                b = (a + start_round * d) % NODE_COUNT
                indices = [b, (b + d) % NODE_COUNT, (b + 2 * d) % NODE_COUNT]
                if not edge_at(bitset, indices[1], indices[2]):
                    literal = literal_dependency_vector([catalog[index] for index in indices])
                    first = {
                        "a": a,
                        "d": d,
                        "start_round": start_round,
                        "indices": indices,
                        "tuples": [list(catalog[index]) for index in indices],
                        "first_incomplete_output": first_incomplete(literal),
                    }
                    break
    require_true(first is not None, "prior first counterexample absent")
    expected_first = prior_h4["structural_census"]["first_counterexample"]
    require_equal(first, expected_first, "prior first counterexample reconstruction")
    require_equal(
        prior_h4["structural_census"]["failure_count"],
        failed_placements,
        "prior receipt failure count",
    )
    return {
        "class_map": "(b,d)->(b+d,b+2d) mod 384",
        "inverse": "d=j-i; b=2i-j mod 384",
        "class_count": len(observed_pairs),
        "map_bijective": True,
        "safe_classes": PAIR_COUNT - failed_classes,
        "failed_classes": failed_classes,
        "placements_per_class": 10,
        "failed_placements": failed_placements,
        "stride_failure_counts": stride_failures,
        "stride_failure_counts_sha256": sha256_bytes(canonical_json_bytes(stride_failures)),
        "zero_failure_strides": zero_failure_strides,
        "zero_failure_stride_role": "prior exploratory disclosure reconstructed, not blind prediction",
        "first_counterexample": first,
        "mapping_aggregate_sha256": mapping_hasher.hexdigest(),
        "prior_receipt_exact": True,
    }


def select_path_certificate(
    catalog: Sequence[Sequence[int]],
    bitset: bytes,
    root: str,
    quotient: Mapping,
) -> dict:
    masks = quotient["support_masks"]
    lift = {
        mask: min(index for index, wiring in enumerate(catalog) if support_mask(wiring) == mask)
        for mask in masks
    }
    cycle = quotient["hamiltonian_cycle_dp"]["cycle"]
    if cycle is not None:
        quotient_path = cycle[:PATH_SELECTORS]
        indices = [lift[masks[node]] for node in quotient_path]
        rule = "hamiltonian_cycle_first_twelve_lowest_catalog_lift"
    else:
        support_pair = None
        for i in range(NODE_COUNT):
            for j in range(i + 1, NODE_COUNT):
                if (
                    support_mask(catalog[i]) != support_mask(catalog[j])
                    and edge_at(bitset, i, j)
                    and edge_at(bitset, j, i)
                ):
                    support_pair = (i, j)
                    break
            if support_pair is not None:
                break
        if support_pair is not None:
            indices = [support_pair[index % 2] for index in range(PATH_SELECTORS)]
            rule = "first_support_changing_safe_two_cycle_alternation"
        else:
            loop = next((index for index in range(NODE_COUNT) if edge_at(bitset, index, index)), None)
            require_true(loop is not None, "no safe path fallback edge")
            indices = [loop] * PATH_SELECTORS
            rule = "lowest_safe_loop_repetition"
    certificate = {
        "schema": PATH_SCHEMA,
        "safe_graph_root": root,
        "catalog_indices": indices,
        "tuple_codes": [tuple_code(catalog[index]) for index in indices],
        "selection_rule": rule,
    }
    verify_path_certificate(certificate, catalog, bitset, root)
    return certificate


def verify_path_certificate(
    certificate: Mapping,
    catalog: Sequence[Sequence[int]],
    bitset: bytes,
    expected_root: str,
) -> dict:
    required = (
        "schema",
        "safe_graph_root",
        "catalog_indices",
        "tuple_codes",
        "selection_rule",
    )
    require_exact_keys(certificate, required, "path certificate")
    require_equal(certificate["schema"], PATH_SCHEMA, "path schema")
    require_equal(certificate["safe_graph_root"], expected_root, "path graph root")
    indices = certificate["catalog_indices"]
    codes = certificate["tuple_codes"]
    require_true(isinstance(indices, list), "path indices are not an array")
    require_true(isinstance(codes, list), "path tuple codes are not an array")
    require_equal(len(indices), PATH_SELECTORS, "path selector count")
    require_equal(len(codes), PATH_SELECTORS, "path tuple-code count")
    for position, index in enumerate(indices):
        require_true(type(index) is int and 0 <= index < NODE_COUNT, "path index range")
        require_equal(codes[position], tuple_code(catalog[index]), "path tuple-code/index binding")
    for position in range(PATH_TRANSITIONS):
        require_true(
            edge_at(bitset, indices[position], indices[position + 1]),
            "unsafe path transition at position %d" % position,
        )
    return {
        "selector_count": len(indices),
        "verified_transition_count": PATH_TRANSITIONS,
        "all_adjacent_transitions_safe": True,
        "indices_sha256": sha256_bytes(canonical_json_bytes(indices)),
        "tuple_codes_sha256": sha256_bytes(canonical_json_bytes(codes)),
        "scope": "contiguous three-round structural all-to-all dependency only",
    }


# ---------------------------------------------------------------------------
# Planted controls through production validators.


def expect_rejection(identifier: str, operation) -> dict:
    try:
        operation()
    except GateError as error:
        return {
            "id": identifier,
            "detected": True,
            "rejection": str(error),
        }
    raise GateError("control was not detected: " + identifier)


def mutated_oracle_control(
    identifier: str,
    catalog: Sequence[Sequence[int]],
    mode: str,
) -> dict:
    x = catalog[0]
    x_mask = support_mask(x)
    for i, y in enumerate(catalog):
        for j, z in enumerate(catalog):
            literal_safe = vector_is_full(literal_dependency_vector((x, y, z)))
            y_mask = support_mask(y)
            z_mask = support_mask(z)
            if mode == "xy":
                mutated = sumset_mask(x_mask, y_mask) == FULL_SUPPORT_MASK
            elif mode == "xor":
                mutated = xor_sumset_mask(y_mask, z_mask) == FULL_SUPPORT_MASK
            elif mode == "mod7":
                mutated = wrong_modulus_sumset_mask(y_mask, z_mask) == FULL_SUPPORT_MASK
            elif mode == "omit":
                elements = support_elements(y_mask)
                reduced = y_mask & ~(1 << elements[-1])
                mutated = sumset_mask(reduced, z_mask) == FULL_SUPPORT_MASK
            else:
                raise GateError("unknown oracle control mode")
            if mutated != literal_safe:
                return {
                    "id": identifier,
                    "detected": True,
                    "first_mismatch": {"i": i, "j": j, "literal": literal_safe, "mutated": mutated},
                }
    raise GateError("mutated oracle control had no mismatch: " + identifier)


def run_controls(
    catalog: Sequence[Sequence[int]],
    bitset: bytes,
    root: str,
    diagnostics: Mapping,
    quotient: Mapping,
    certificate: Mapping,
) -> dict:
    records: Dict[str, dict] = {}

    reordered = [list(item) for item in catalog]
    reordered[0], reordered[1] = reordered[1], reordered[0]
    records["catalog_reorder"] = expect_rejection(
        "catalog_reorder", lambda: validate_catalog(reordered)
    )
    records["stale_catalog_hash"] = expect_rejection(
        "stale_catalog_hash", lambda: validate_catalog([list(item) for item in catalog], "0" * 64)
    )
    changed = [list(item) for item in catalog]
    changed[0][3] = 6
    records["tuple_element_mutation"] = expect_rejection(
        "tuple_element_mutation", lambda: validate_catalog(changed)
    )
    duplicate = [list(item) for item in catalog]
    duplicate[0][3] = duplicate[0][2]
    records["duplicate_tuple_offset"] = expect_rejection(
        "duplicate_tuple_offset", lambda: validate_catalog(duplicate)
    )
    out_of_range = [list(item) for item in catalog]
    out_of_range[0][3] = 8
    records["out_of_range_tuple_offset"] = expect_rejection(
        "out_of_range_tuple_offset", lambda: validate_catalog(out_of_range)
    )

    records["wrong_xy_pair"] = mutated_oracle_control("wrong_xy_pair", catalog, "xy")
    records["xor_sumset"] = mutated_oracle_control("xor_sumset", catalog, "xor")
    records["wrong_modulus"] = mutated_oracle_control("wrong_modulus", catalog, "mod7")
    records["omitted_support_element"] = mutated_oracle_control(
        "omitted_support_element", catalog, "omit"
    )

    first_unsafe = diagnostics["first_unsafe_pair"]["indices"]
    first_safe = next(
        (i, j)
        for i in range(NODE_COUNT)
        for j in range(NODE_COUNT)
        if edge_at(bitset, i, j)
    )

    flipped = bytearray(bitset)
    flipped[0] ^= 1
    records["graph_bit_flip"] = expect_rejection(
        "graph_bit_flip", lambda: verify_graph_bytes(bytes(flipped), root, bitset, root)
    )
    reverse_table = bytes(int(format(value, "08b")[::-1], 2) for value in range(256))
    reversed_bits = bytes(reverse_table[value] for value in bitset)
    records["reversed_bit_order"] = expect_rejection(
        "reversed_bit_order", lambda: verify_graph_bytes(reversed_bits, root, bitset, root)
    )
    records["missing_graph_row"] = expect_rejection(
        "missing_graph_row", lambda: verify_graph_bytes(bitset[:-ROW_BYTES], root, bitset, root)
    )
    records["duplicate_graph_row"] = expect_rejection(
        "duplicate_graph_row",
        lambda: verify_graph_bytes(bitset[:ROW_BYTES] + bitset, root, bitset, root),
    )
    records["stale_graph_root"] = expect_rejection(
        "stale_graph_root", lambda: verify_graph_bytes(bitset, "0" * 64, bitset, root)
    )
    forged_bytes = bytearray(bitset)
    forged_bytes[first_unsafe[0] * ROW_BYTES + first_unsafe[1] // 8] |= 1 << (first_unsafe[1] % 8)
    forged_root = graph_root(bytes(forged_bytes))
    records["forged_graph_root"] = expect_rejection(
        "forged_graph_root",
        lambda: verify_graph_bytes(bytes(forged_bytes), forged_root, bitset, root),
    )
    inserted = bytearray(bitset)
    inserted[first_unsafe[0] * ROW_BYTES + first_unsafe[1] // 8] |= 1 << (first_unsafe[1] % 8)
    records["insert_unsafe_edge"] = expect_rejection(
        "insert_unsafe_edge", lambda: verify_graph_bytes(bytes(inserted), root, bitset, root)
    )
    removed = bytearray(bitset)
    removed[first_safe[0] * ROW_BYTES + first_safe[1] // 8] &= ~(1 << (first_safe[1] % 8))
    records["remove_safe_edge"] = expect_rejection(
        "remove_safe_edge", lambda: verify_graph_bytes(bytes(removed), root, bitset, root)
    )

    filtered_pair_corpus = build_ordered_pair_corpus()
    del filtered_pair_corpus[PAIR_COUNT // 2]
    records["filtered_pair_corpus"] = expect_rejection(
        "filtered_pair_corpus",
        lambda: validate_ordered_pair_corpus(filtered_pair_corpus),
    )
    bad_code = dict(certificate)
    bad_code["catalog_indices"] = list(certificate["catalog_indices"])
    bad_code["tuple_codes"] = list(certificate["tuple_codes"])
    bad_code["tuple_codes"][0] ^= 1
    records["tuple_code_index_mismatch"] = expect_rejection(
        "tuple_code_index_mismatch",
        lambda: verify_path_certificate(bad_code, catalog, bitset, root),
    )
    bad_index = dict(certificate)
    bad_index["catalog_indices"] = list(certificate["catalog_indices"])
    bad_index["tuple_codes"] = list(certificate["tuple_codes"])
    bad_index["catalog_indices"][0] = NODE_COUNT
    records["out_of_range_path_index"] = expect_rejection(
        "out_of_range_path_index",
        lambda: verify_path_certificate(bad_index, catalog, bitset, root),
    )
    truncated = dict(certificate)
    truncated["catalog_indices"] = list(certificate["catalog_indices"][:-1])
    truncated["tuple_codes"] = list(certificate["tuple_codes"][:-1])
    records["truncated_path"] = expect_rejection(
        "truncated_path", lambda: verify_path_certificate(truncated, catalog, bitset, root)
    )
    unsafe_path = dict(certificate)
    unsafe_path["catalog_indices"] = list(certificate["catalog_indices"])
    unsafe_path["tuple_codes"] = list(certificate["tuple_codes"])
    unsafe_path["catalog_indices"][0] = first_unsafe[0]
    unsafe_path["catalog_indices"][1] = first_unsafe[1]
    unsafe_path["tuple_codes"][0] = tuple_code(catalog[first_unsafe[0]])
    unsafe_path["tuple_codes"][1] = tuple_code(catalog[first_unsafe[1]])
    records["known_unsafe_transition"] = expect_rejection(
        "known_unsafe_transition",
        lambda: verify_path_certificate(unsafe_path, catalog, bitset, root),
    )
    missing_quotient = dict(quotient)
    missing_quotient.pop("hamiltonian_cycle_dp")
    records["missing_scc_cycle_observation"] = expect_rejection(
        "missing_scc_cycle_observation",
        lambda: validate_diagnostics(diagnostics, missing_quotient),
    )

    require_equal(tuple(records), CONTROL_IDS, "executed control order")
    require_true(all(record["detected"] is True for record in records.values()), "control detection")
    return {
        "frozen_ids": list(CONTROL_IDS),
        "executed_ids": list(records),
        "records": records,
        "all_detected": True,
    }


# ---------------------------------------------------------------------------
# Scratch artifacts, deterministic payload, and archival record.


def scratch_artifacts(
    bitset: bytes,
    root: str,
    edge_count: int,
    certificate: Mapping,
    write: bool,
) -> dict:
    graph_manifest = {
        "schema": GRAPH_SCHEMA,
        "nodes": NODE_COUNT,
        "row_bytes": ROW_BYTES,
        "bitset_bytes": BITSET_BYTES,
        "bitset_sha256": sha256_bytes(bitset),
        "safe_graph_root": root,
        "directed_edge_count": edge_count,
    }
    graph_json = json.dumps(graph_manifest, indent=2, sort_keys=True).encode("utf-8") + b"\n"
    path_json = json.dumps(certificate, indent=2, sort_keys=True).encode("utf-8") + b"\n"
    if write:
        SCRATCH.mkdir(parents=True, exist_ok=True)
        atomic_write(SCRATCH / "safe-graph.bin", bitset)
        atomic_write(SCRATCH / "safe-graph.json", graph_json)
        atomic_write(SCRATCH / "path-certificate.json", path_json)
    return {
        "safe_graph_bin": {
            "path": str((SCRATCH / "safe-graph.bin").relative_to(REPO)),
            "bytes": len(bitset),
            "sha256": sha256_bytes(bitset),
        },
        "safe_graph_json": {
            "path": str((SCRATCH / "safe-graph.json").relative_to(REPO)),
            "bytes": len(graph_json),
            "sha256": sha256_bytes(graph_json),
        },
        "path_certificate_json": {
            "path": str((SCRATCH / "path-certificate.json").relative_to(REPO)),
            "bytes": len(path_json),
            "sha256": sha256_bytes(path_json),
        },
    }


def build_deterministic_payload(write_scratch: bool = True) -> dict:
    integrity, prereg, catalog, prior_h4 = validate_integrity()
    graph_bytes, adjacency = build_graph(catalog)
    root = graph_root(graph_bytes)
    verify_graph_bytes(graph_bytes, root, graph_bytes, root)
    edge_count = sum(len(row) for row in adjacency)
    require_equal(edge_count, EXPECTED_SAFE_PAIRS, "safe graph edge count")

    algebraic = run_algebraic_equivalence(catalog, graph_bytes)
    prior = reconstruct_prior_census(catalog, graph_bytes, prior_h4)
    quotient, _quotient_adjacency, _index_by_mask = build_quotient(catalog)
    diagnostics = build_diagnostics(catalog, graph_bytes, adjacency)
    validate_diagnostics(diagnostics, quotient)
    certificate = select_path_certificate(catalog, graph_bytes, root, quotient)
    path_verification = verify_path_certificate(certificate, catalog, graph_bytes, root)
    controls = run_controls(
        catalog, graph_bytes, root, diagnostics, quotient, certificate
    )
    artifacts = scratch_artifacts(
        graph_bytes, root, edge_count, certificate, write_scratch
    )

    catalog_record = {
        "source": prereg["catalog"]["source"],
        "count": len(catalog),
        "canonical_sha256": sha256_bytes(canonical_json_bytes(catalog)),
        "first_tuple": list(catalog[0]),
        "fixed_tuple_index": 1,
        "fixed_tuple": list(catalog[1]),
        "last_tuple": list(catalog[-1]),
        "support_count": len({support_mask(wiring) for wiring in catalog}),
        "permutations_per_support": PERMUTATIONS_PER_SUPPORT,
        "catalog_order_exact": True,
    }
    safe_graph = {
        "schema": GRAPH_SCHEMA,
        "nodes": NODE_COUNT,
        "row_bytes": ROW_BYTES,
        "bitset_bytes": len(graph_bytes),
        "destination_bit_rule": "row i byte j//8 bit 1<<(j%8)",
        "bitset_hex": graph_bytes.hex(),
        "bitset_sha256": sha256_bytes(graph_bytes),
        "safe_graph_root": root,
        "directed_edge_count": edge_count,
        "directed_non_edge_count": PAIR_COUNT - edge_count,
        "canonical_reconstruction_exact": True,
        "scratch_artifacts": artifacts,
    }
    path_controls = {
        "certificate": certificate,
        "verification": path_verification,
        "controls": controls,
    }
    validity = {
        "frozen_integrity_exact": integrity["all_exact"],
        "catalog_exact": catalog_record["catalog_order_exact"],
        "algebraic_pair_coverage_exact": algebraic["ordered_pair_cases"] == PAIR_COUNT,
        "literal_closed_form_exact": algebraic["literal_and_closed_form_vectors_exact"],
        "first_selector_invariance_exact": algebraic["first_selector_invariance_cases"] == FIRST_SELECTOR_CASES,
        "translation_invariance_exact": algebraic["translation_invariance_cases"] == TRANSLATION_CASES,
        "prior_census_reconstructed": prior["prior_receipt_exact"],
        "graph_root_closed": safe_graph["canonical_reconstruction_exact"],
        "diagnostics_complete": True,
        "path_certificate_verified": path_verification["all_adjacent_transitions_safe"],
        "all_twenty_three_controls_detected": controls["all_detected"],
    }
    require_true(all(validity.values()), "X0 harness validity failure")

    payload = {
        "schema": RECEIPT_SCHEMA,
        "status": STATUS,
        "integrity": integrity,
        "catalog": catalog_record,
        "algebraic_equivalence": algebraic,
        "prior_census_reconstruction": prior,
        "safe_graph": safe_graph,
        "support_quotient": quotient,
        "diagnostics": diagnostics,
        "path_certificate_controls": path_controls,
        "verdicts": {
            "harness_validity": validity,
            "harness_valid": True,
            "transition_policy": "SAFE_TRANSITION_GRAPH_DERIVED_AND_PATH_CERTIFIED",
            "support_quotient_hamiltonian": quotient["hamiltonian_cycle_dp"]["verdict"],
            "path_certificate": "TWELVE_SELECTORS_ELEVEN_SAFE_TRANSITIONS_VERIFIED",
            "mixed_four_round_bound": "OPEN_NOT_GRADED",
            "production_policy_selected": False,
            "architecture_selected": False,
            "security_claim": False,
            "claim_movement": False,
        },
        "non_claims": list(prereg["non_claims"]),
    }
    require_equal(tuple(payload), PAYLOAD_KEYS, "payload key order")
    validate_deterministic_types(payload)
    return payload


def advisory(started: float) -> dict:
    def run(command: Sequence[str]) -> Tuple[bool, str]:
        try:
            process = subprocess.run(
                list(command), capture_output=True, text=True, timeout=20, check=False
            )
            return process.returncode == 0, process.stdout.strip()
        except Exception:
            return False, ""

    head_ok, head = run(["git", "-C", str(REPO), "rev-parse", "HEAD"])
    status_ok, status = run(["git", "-C", str(REPO), "status", "--porcelain"])
    return {
        "platform": platform.platform(),
        "elapsed_seconds": round(time.perf_counter() - started, 3),
        "git_head": head.splitlines()[0] if head_ok and head else "unavailable",
        "git_dirty": bool(status) if status_ok else "unavailable",
    }


def add_record_hash(record_without_hash: Mapping) -> dict:
    record = dict(record_without_hash)
    record["record_sha256"] = None
    record["record_sha256"] = sha256_bytes(
        canonical_json_bytes(record, deterministic=False)
    )
    return record


def validate_record(record: Mapping) -> None:
    require_exact_keys(record, OUTER_KEYS, "outer record")
    payload = record["deterministic_payload"]
    require_exact_keys(payload, PAYLOAD_KEYS, "deterministic payload")
    validate_deterministic_types(payload)
    require_equal(payload["schema"], RECEIPT_SCHEMA, "stored receipt schema")
    require_equal(payload["status"], STATUS, "stored receipt status")
    payload_digest = sha256_bytes(canonical_json_bytes(payload))
    require_equal(
        record["deterministic_payload_sha256"], payload_digest, "stored payload digest"
    )
    require_true(
        re.fullmatch(r"[0-9a-f]{64}", record["record_sha256"]) is not None,
        "record hash grammar",
    )
    unhashed = dict(record)
    stored = unhashed["record_sha256"]
    unhashed["record_sha256"] = None
    require_equal(
        sha256_bytes(canonical_json_bytes(unhashed, deterministic=False)),
        stored,
        "stored record hash",
    )
    require_equal(record["no_wall_clock"], NO_WALL_CLOCK, "no-wall-clock text")


def build_record(write_scratch: bool = True) -> dict:
    started = time.perf_counter()
    payload = build_deterministic_payload(write_scratch=write_scratch)
    payload_digest = sha256_bytes(canonical_json_bytes(payload))
    without_hash = {
        "deterministic_payload": payload,
        "deterministic_payload_sha256": payload_digest,
        "environment_advisory_excluded_from_digest": advisory(started),
        "no_wall_clock": NO_WALL_CLOCK,
    }
    hashed = add_record_hash(without_hash)
    record = {
        "deterministic_payload": hashed["deterministic_payload"],
        "deterministic_payload_sha256": hashed["deterministic_payload_sha256"],
        "record_sha256": hashed["record_sha256"],
        "environment_advisory_excluded_from_digest": hashed[
            "environment_advisory_excluded_from_digest"
        ],
        "no_wall_clock": hashed["no_wall_clock"],
    }
    unhashed = dict(record)
    unhashed["record_sha256"] = None
    record["record_sha256"] = sha256_bytes(
        canonical_json_bytes(unhashed, deterministic=False)
    )
    validate_record(record)
    return record


def check_prior(path: Path, current: Mapping) -> None:
    require_true(path.is_file(), "prior X0 receipt absent: " + str(path.relative_to(REPO)))
    prior = strict_json_load(path)
    validate_record(prior)
    require_equal(
        canonical_json_bytes(prior["deterministic_payload"]),
        canonical_json_bytes(current["deterministic_payload"]),
        "reproduced deterministic payload bytes",
    )
    require_equal(
        prior["deterministic_payload_sha256"],
        current["deterministic_payload_sha256"],
        "reproduced deterministic payload digest",
    )


def print_summary(record: Mapping) -> None:
    payload = record["deterministic_payload"]
    graph = payload["safe_graph"]
    quotient = payload["support_quotient"]
    path = payload["path_certificate_controls"]
    print("=" * 78)
    print("E256-X0 H4 PROOF-CARRYING EVOLUTION GATE  (OPEN_PROGRESS)")
    print("=" * 78)
    print("harness valid: %s" % payload["verdicts"]["harness_valid"])
    print(
        "safe graph: %d/%d directed pairs; root %s"
        % (graph["directed_edge_count"], PAIR_COUNT, graph["safe_graph_root"])
    )
    print(
        "oracles: %d pair vectors, %d first-selector cases, %d translations"
        % (
            payload["algebraic_equivalence"]["ordered_pair_cases"],
            payload["algebraic_equivalence"]["first_selector_invariance_cases"],
            payload["algebraic_equivalence"]["translation_invariance_cases"],
        )
    )
    print(
        "prior census: %d failed classes / %d failed placements; zero-failure strides %s"
        % (
            payload["prior_census_reconstruction"]["failed_classes"],
            payload["prior_census_reconstruction"]["failed_placements"],
            payload["prior_census_reconstruction"]["zero_failure_strides"],
        )
    )
    print(
        "quotient: %d SCC(s), %s"
        % (len(quotient["sccs"]), quotient["hamiltonian_cycle_dp"]["verdict"])
    )
    print(
        "path: %s; %d/%d transitions verified"
        % (
            path["certificate"]["catalog_indices"],
            path["verification"]["verified_transition_count"],
            PATH_TRANSITIONS,
        )
    )
    print("controls: %d/%d detected" % (len(path["controls"]["executed_ids"]), len(CONTROL_IDS)))
    print("verdict: %s" % payload["verdicts"]["transition_policy"])
    print("NOTE: bounded structural policy certificate; no security or production claim")
    print("deterministic_payload_sha256: %s" % record["deterministic_payload_sha256"])
    print("record_sha256: %s" % record["record_sha256"])


def run_self_test() -> None:
    record = build_record(write_scratch=False)
    require_equal(record["deterministic_payload"]["verdicts"]["harness_valid"], True, "self-test harness")
    require_equal(record["deterministic_payload"]["safe_graph"]["bitset_bytes"], BITSET_BYTES, "self-test graph bytes")
    require_equal(
        record["deterministic_payload"]["path_certificate_controls"]["verification"][
            "verified_transition_count"
        ],
        PATH_TRANSITIONS,
        "self-test path transitions",
    )
    print("SELF-TEST PASS: full deterministic X0 payload validated; no receipt or scratch emitted")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Derive or reproduce-check the frozen E256-X0 H4 transition-policy certificate."
    )
    parser.add_argument("--check", action="store_true")
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="run the full deterministic gate without emitting receipt or scratch artifacts",
    )
    parser.add_argument("--json", default=str(RECEIPT.relative_to(REPO)))
    args = parser.parse_args()
    output = REPO / args.json
    if args.check and args.self_test:
        print("X0 GATE FAILED: --check and --self-test are mutually exclusive", file=sys.stderr)
        return 1
    try:
        if args.self_test:
            run_self_test()
            return 0
        record = build_record(write_scratch=True)
        print_summary(record)
        if args.check:
            check_prior(output, record)
            print("CHECK PASS")
            return 0
        atomic_write(
            output,
            json.dumps(record, indent=2, sort_keys=True, allow_nan=False).encode("utf-8")
            + b"\n",
        )
        print("wrote %s" % output.relative_to(REPO))
        print(
            "STATUS: OPEN_PROGRESS; no C/H/N row, security level, production policy, "
            "round count, schedule, architecture, Metal/FHE path, or physical FPGA claim moved"
        )
        return 0
    except Exception as error:
        print("X0 GATE FAILED: %s" % error, file=sys.stderr)
        print(
            "No canonical X0 receipt was emitted or accepted; E256-063 remains OPEN.",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    sys.exit(main())
