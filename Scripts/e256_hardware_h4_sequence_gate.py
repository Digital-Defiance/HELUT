#!/usr/bin/env python3
"""Run the frozen E256-H H4 switching-sequence research gate.

This OPEN_PROGRESS gate evaluates the complete preregistered arithmetic sequence
census, exact sequence-specific H3 offset collapse, four integrated FF/ring RTL
tops, all nineteen planted controls, and paired generic Yosys/ABC mapped costs.
It does not select a production H4 policy, architecture, schedule, round count,
XOF, suite, protocol, security value, or implementation.

Contract:  directives/e256-hardware-h4-sequence-preregistration.json
Receipt:   logs/e256-hardware-h4-sequence-gate.json
RTL:       Hardware/RTL/Research/E256H/e256h_h4_sequence_core.v
Testbench: Hardware/Testbenches/Research/E256H/e256h_h4_sequence_core_tb.v
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import math
import os
import platform
import re
import shutil
import subprocess
import sys
import time
from collections import Counter
from pathlib import Path
from typing import Any, Dict, Iterable, Iterator, List, Mapping, MutableMapping, Optional, Sequence, Set, Tuple

REPO = Path(__file__).resolve().parent.parent
PREREG = REPO / "directives/e256-hardware-h4-sequence-preregistration.json"
ARCHITECTURE = REPO / "directives/e256-hardware-architecture.md"
H2_RTL = REPO / "Hardware/RTL/Research/E256H/e256h_h2_integrated_core.v"
H2_TESTBENCH = REPO / "Hardware/Testbenches/Research/E256H/e256h_h2_integrated_core_tb.v"
H2_RUNNER = REPO / "Scripts/e256_hardware_h2_gate.py"
RTL = REPO / "Hardware/RTL/Research/E256H/e256h_h4_sequence_core.v"
TESTBENCH = REPO / "Hardware/Testbenches/Research/E256H/e256h_h4_sequence_core_tb.v"
MAKEFILE = REPO / "Makefile"
RECEIPT = REPO / "logs/e256-hardware-h4-sequence-gate.json"
SCRATCH = REPO / "build/e256h-h4-sequence"

PREREG_SHA256 = "b7afcc67ceac142a800468362ee0c97fcf6c7b6843f0cdd2f96f5d77894fc8e2"
H4_ARCHITECTURE_SHA256 = "aac50bda525ead96234fc3c0e3e3692fabbde101de34d44f632d6a65bfbed1e4"
BASE_ARCHITECTURE_SHA256 = "b64472f73be9d0fc6318ff445c5f550cb0129309313228f416599c27d3957bb1"
H2_ARCHITECTURE_SHA256 = "214aee439ddf715ebf3e5fc206c336119dd27f85da12ef65f8e590c0cb0bfceb"
H2_RTL_SHA256 = "05edd3c1cfb3cfc24ecb12fcada8c07f81451eb9937efd0f3fc10abf3f1d0adf"
H2_TESTBENCH_SHA256 = "fb02e49ab376c761b6ae1bbb3fec6ab1325c5bfda71c9ff2684668cc14cb2b95"
H2_RUNNER_SHA256 = "3a62a7fc56a65682aa735fbb4cd1c611e0da8d4be84081a77c948865f7b77c5c"
CERTIFIED_SHA256 = "199f1f7bddccf19ce5aa0bde0987441735d628354140d53ebdfec538d7b3f5ed"
STRUCTURAL_CORPUS_SHA256 = "fc0eac948c91ec416b5473724af21106e45a05a9fefa7451577bbd73582d85c8"
EXECUTABLE_CORPUS_SHA256 = "8056e742146cffd707f3c5590667766fc376c7b25fee4bcec5cd3fc49cbc2a6a"
FROZEN_MATERIAL_SHA256 = "b6738e7f117bb7b916ee002db482f105a3eb5a046ee84dff45f178510cdeb691"
AES_SBOX_SHA256 = "c2d8e5eed6cbebd8625fc18f81486a7733c04f9b0129ffbe974c68b90308b4f2"
BLOCK_CORPUS_SHA256 = "217ffeaba8348217a84f237ec5aeb4bb6f0358b823b463596277c5bd2494f44d"
COLLAPSE_PREREG_SHA256 = "3d7a12731fcf81f6120577122c55bd8ec25589a82226d49fab7e5b8350ee0cee"

PREDECESSORS = (
    (
        "E256-063-steps-2-3",
        "logs/e256-hardware-candidate-gate.json",
        "E256-HARDWARE-CANDIDATE-GATE-1",
        "0402a53a725f3303ab379bf7f5e986a55cadedb001f4621d9d996f4ee0d93cfc",
        "98af83ec27093787552475fce588f84a902634afcc969bed26462032dddec3cc",
    ),
    (
        "E256-063-h3-collapse",
        "logs/e256-hardware-offset-collapse-gate.json",
        "E256-HARDWARE-OFFSET-COLLAPSE-GATE-1",
        "4b56be2a44ac71d9a89580817a06d6f617247fd3e8b8fc39efd481b888ef0fff",
        "1478a0ba317bce5f33cb053744b050bb6188543405c1dfacf52d8aaf920c4b71",
    ),
    (
        "E256-063-h2-integrated-cost",
        "logs/e256-hardware-h2-gate.json",
        "E256-HARDWARE-H2-GATE-1",
        "1e61489e935e17927b1e66c5387ed83bd303ca797418bae38a3640841d50abd5",
        "b0b62be2cfebd870f71ce0b5e5300eb52ab8c2aea243712d1617f4e2351dc7e1",
    ),
)

EXPECTED_VARIANT_IDS = (
    "ff_repeated",
    "ff_sequence",
    "ring_repeated",
    "ring_sequence",
)
EXPECTED_TOPS = (
    "e256h_h4_ff_repeated",
    "e256h_h4_ff_sequence",
    "e256h_h4_ring_repeated",
    "e256h_h4_ring_sequence",
)
EXPECTED_QUESTION_IDS = ("H4SQ1", "H4SQ2", "H4SQ3", "H4SQ4")
EXPECTED_CONTROL_IDS = (
    "corpus_digest_perturbation",
    "reverse_sequence_order",
    "hold_w0",
    "selector_index_plus_one",
    "wrong_h4_shift_direction",
    "wrong_collapse_transport",
    "terminal_a12",
    "wrong_round_key_address",
    "reverse_mask_word_bytes",
    "broken_ring_rotation",
    "incomplete_configuration",
    "post_commit_pin_change",
    "externalized_sequence_state",
    "externalized_mask_state",
    "nested_child_multiplicity",
    "duplicate_child_accounting",
    "postmap_depth_preservation",
    "extra_repeated_output",
    "missing_cycle_observation",
)
EXPECTED_PREDICTION_IDS = ("H4SP1", "H4SP2", "H4SP3")
EXPECTED_PAYLOAD_KEYS = (
    "schema",
    "status",
    "integrity",
    "corpora",
    "structural_census",
    "collapse_equivalence",
    "functional_equivalence",
    "cycle_evidence",
    "controls",
    "synthesis",
    "paired_measurements",
    "verdicts",
    "non_claims",
)
EXPECTED_OUTER_KEYS = (
    "deterministic_payload",
    "deterministic_payload_sha256",
    "record_sha256",
    "environment_advisory_excluded_from_digest",
    "no_wall_clock",
)
EXPECTED_MATERIAL_IDS = ("frozen_attack_v1", "collapse_aux_0", "collapse_aux_1")
EXPECTED_MATERIAL_DOMAINS = (
    "E256-H/attack/material/v1",
    "E256-H/collapse/material/v1/0",
    "E256-H/collapse/material/v1/1",
)
EXPECTED_MATERIAL_HASHES = (
    "b6738e7f117bb7b916ee002db482f105a3eb5a046ee84dff45f178510cdeb691",
    "8f6d5d6de2a05906198d221d5c90d5f11ebc7a2562620ccce81511bfba9cf67d",
    "f169f6a649e6b1de158fc3e21ac08dd32d3733bd6429de0dd0e007d4c60a92be",
)
EXPECTED_BLOCK_IDS = (
    "all_zero",
    "all_ff",
    "ascending_00_1f",
    "descending_ff_e0",
    "shake_0",
    "shake_1",
    "shake_2",
    "shake_3",
)
STRUCTURAL_VERDICTS = (
    "ARITHMETIC_SEQUENCE_CENSUS_ZERO_MIXED_WINDOW_FAILURES",
    "ARITHMETIC_SEQUENCE_CENSUS_COUNTEREXAMPLE_FOUND",
)

STATE_BYTES = 32
ROUNDS = 12
MASK_WORDS = 13
MASK_BITS = 3328
MATERIAL_BYTES = 1184
MATERIAL_MASK_BASE = 768
CERTIFIED_COUNT = 384
STRUCTURAL_SCHEDULES = 147456
STRUCTURAL_WINDOWS = 1474560
TRANSITION_PLACEMENTS = 1622016
EXECUTABLE_SCHEDULES = 768
CONFIG_COUNT = EXECUTABLE_SCHEDULES * 3
BLOCK_COUNT = 8
EXPECTED_ROWS = EXECUTABLE_SCHEDULES * 3 * BLOCK_COUNT
EXPECTED_MODEL_COMPARISONS = 55296
EXPECTED_STORAGE_COMPARISONS = 27648
EXPECTED_BRIDGES = 18432
EXPECTED_COLLAPSE_PER_STAGE = 221184
FULL_DEPENDENCY_MASK = (1 << STATE_BYTES) - 1
AGGREGATE_ENCODING = (
    "For each record in frozen nested-loop order, append a 4-byte unsigned "
    "big-endian length followed by compact canonical UTF-8 JSON."
)
NO_WALL_CLOCK = (
    "No wall-clock timestamp is asserted; only deterministic inputs and outputs "
    "are graded."
)
SIM_TIMEOUT_SECONDS = 14400
SYNTH_TIMEOUT_SECONDS = 7200

TOP_PORTS = {
    "clk": ("input", 1),
    "rst": ("input", 1),
    "cfg_begin": ("input", 1),
    "cfg_valid": ("input", 1),
    "cfg_ready": ("output", 1),
    "cfg_word": ("input", 256),
    "cfg_commit": ("input", 1),
    "cfg_h4_sequence": ("input", 144),
    "key_valid": ("output", 1),
    "cfg_error": ("output", 1),
    "start": ("input", 1),
    "ready": ("output", 1),
    "block_i": ("input", 256),
    "block_o": ("output", 256),
    "busy": ("output", 1),
    "done": ("output", 1),
}
METRIC_KEYS = (
    "generic_abc_lut6",
    "generic_sequential_bits",
    "generic_memory_bits",
    "generic_primitive_cells",
)


class GateError(RuntimeError):
    """Frozen identity, semantic, execution-set, or accounting failure."""


# ---------------------------------------------------------------------------
# Strict loading, canonical encodings, and trusted-helper loading.


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
        raise GateError(f"could not strictly parse {path}: {error}") from error


def validate_deterministic_types(value, path: str = "payload") -> None:
    if value is None or type(value) in (bool, int, str):
        return
    if isinstance(value, list):
        for index, item in enumerate(value):
            validate_deterministic_types(item, f"{path}[{index}]")
        return
    if isinstance(value, dict):
        for key, item in value.items():
            if type(key) is not str:
                raise GateError(f"non-string deterministic key at {path}")
            validate_deterministic_types(item, f"{path}.{key}")
        return
    raise GateError(
        f"non-canonical deterministic value at {path}: {type(value).__name__}"
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
        raise GateError(f"could not read {path}: {error}") from error


def require_equal(actual, expected, label: str) -> None:
    if actual != expected:
        raise GateError(f"{label} mismatch: expected {expected!r}, got {actual!r}")


def require_true(condition: bool, label: str) -> None:
    if not condition:
        raise GateError(label)


def require_exact_keys(value: Mapping, expected: Sequence[str], label: str) -> None:
    require_true(isinstance(value, dict), f"{label} is not an object")
    require_equal(set(value), set(expected), f"{label} keys")
    require_equal(len(value), len(expected), f"{label} key count")


def strict_decimal(token: str, label: str) -> int:
    if re.fullmatch(r"0|[1-9][0-9]*", token) is None:
        raise GateError(f"non-canonical decimal {label}: {token!r}")
    return int(token)


def update_record_hash(hasher, record: Mapping) -> None:
    encoded = canonical_json_bytes(dict(record))
    require_true(len(encoded) < 2**32, "aggregate record exceeds four-byte length")
    hasher.update(len(encoded).to_bytes(4, "big"))
    hasher.update(encoded)


def canonical_list_digest(records: Iterable[Mapping]) -> Tuple[str, int]:
    hasher = hashlib.sha256()
    hasher.update(b"[")
    count = 0
    for record in records:
        if count:
            hasher.update(b",")
        hasher.update(canonical_json_bytes(dict(record)))
        count += 1
    hasher.update(b"]")
    return hasher.hexdigest(), count


def load_h2_helpers():
    # Repository files are untrusted until the frozen source identity closes.
    require_equal(sha256_file(H2_RUNNER), H2_RUNNER_SHA256, "frozen H2 runner")
    specification = importlib.util.spec_from_file_location(
        "e256_h4_pinned_h2_helpers", str(H2_RUNNER)
    )
    require_true(
        specification is not None and specification.loader is not None,
        "could not construct pinned H2 helper import",
    )
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


# ---------------------------------------------------------------------------
# Frozen identities and contract shape.


def marker_digest_between(raw: bytes, start_text: str, end_text: str) -> str:
    start = start_text.encode("ascii")
    end = end_text.encode("ascii")
    require_equal(raw.count(start), 1, "between-marker start count")
    require_equal(raw.count(end), 1, "between-marker end count")
    start_index = raw.index(start) + len(start)
    end_index = raw.index(end)
    require_true(start_index <= end_index, "between markers out of order")
    return sha256_bytes(raw[start_index:end_index])


def marker_digest_inclusive(raw: bytes, start_text: str, end_text: str) -> str:
    start = start_text.encode("ascii")
    end = end_text.encode("ascii")
    require_equal(raw.count(start), 1, "inclusive-marker start count")
    require_equal(raw.count(end), 1, "inclusive-marker end count")
    start_index = raw.index(start)
    end_index = raw.index(end) + len(end)
    require_true(start_index < end_index, "inclusive markers out of order")
    return sha256_bytes(raw[start_index:end_index])


def validate_contract_shape(prereg: Mapping) -> None:
    require_equal(
        prereg.get("schema"),
        "E256-HARDWARE-H4-SEQUENCE-PREREGISTRATION-1",
        "preregistration schema",
    )
    require_equal(prereg.get("status"), "FROZEN_BEFORE_IMPLEMENTATION", "prereg status")
    require_equal(sha256_file(PREREG), PREREG_SHA256, "raw preregistration SHA-256")
    require_equal(
        tuple(item["id"] for item in prereg["questions"]),
        EXPECTED_QUESTION_IDS,
        "question IDs",
    )
    require_equal(
        tuple(item["id"] for item in prereg["controls"]),
        EXPECTED_CONTROL_IDS,
        "control IDs",
    )
    require_equal(
        tuple(item["id"] for item in prereg["predictions"]),
        EXPECTED_PREDICTION_IDS,
        "prediction IDs",
    )
    require_equal(
        tuple(item["id"] for item in prereg["variants"]),
        EXPECTED_VARIANT_IDS,
        "variant IDs",
    )
    require_equal(
        tuple(item["top"] for item in prereg["variants"]),
        EXPECTED_TOPS,
        "variant tops",
    )
    require_equal(
        tuple((item["storage_id"], item["selector_mode"]) for item in prereg["variants"]),
        (("ff", "repeated"), ("ff", "sequence"), ("ring", "repeated"), ("ring", "sequence")),
        "variant matrix",
    )
    require_equal(
        tuple(item["expected_outputs"] for item in prereg["variants"]),
        (9216, 18432, 9216, 18432),
        "variant output contracts",
    )
    require_equal(
        tuple(item["selector_state_bits"] for item in prereg["variants"]),
        (12, 144, 12, 144),
        "selector state contracts",
    )
    require_true(
        all(item["mask_state_bits"] == MASK_BITS for item in prereg["variants"]),
        "mask-state contract drift",
    )
    architecture = prereg["architecture_contract"]
    require_equal(architecture["sha256"], H4_ARCHITECTURE_SHA256, "declared H4 marker hash")
    require_equal(architecture["base_contract_sha256"], BASE_ARCHITECTURE_SHA256, "declared base marker hash")
    require_equal(architecture["h2_contract_sha256"], H2_ARCHITECTURE_SHA256, "declared H2 marker hash")
    certified = prereg["certified_list"]
    require_equal(certified["count"], CERTIFIED_COUNT, "certified count")
    require_equal(certified["canonical_sha256"], CERTIFIED_SHA256, "certified hash")
    require_equal(certified["fixed_tuple"], [0, 1, 3, 4], "fixed tuple")
    require_equal(certified["fixed_tuple_index"], 1, "fixed tuple index")
    structural = prereg["corpora"]["structural"]
    executable = prereg["corpora"]["executable"]
    require_equal(structural["schedule_count"], STRUCTURAL_SCHEDULES, "structural schedules")
    require_equal(structural["contiguous_three_round_windows"], STRUCTURAL_WINDOWS, "structural windows")
    require_equal(structural["adjacent_transition_placements"], TRANSITION_PLACEMENTS, "transition placements")
    require_equal(structural["canonical_sha256"], STRUCTURAL_CORPUS_SHA256, "structural hash")
    require_equal(executable["schedule_count"], EXECUTABLE_SCHEDULES, "executable schedules")
    require_equal(executable["steps"], [0, 1], "executable steps")
    require_equal(executable["canonical_sha256"], EXECUTABLE_CORPUS_SHA256, "executable hash")
    collapse = prereg["collapse_contract"]
    require_equal(collapse["rounds"], ROUNDS, "collapse rounds")
    require_equal(collapse["stage_a_comparisons"], EXPECTED_COLLAPSE_PER_STAGE, "Stage A comparisons")
    require_equal(collapse["stage_b_comparisons"], EXPECTED_COLLAPSE_PER_STAGE, "Stage B comparisons")
    require_equal(collapse["total_comparisons"], 2 * EXPECTED_COLLAPSE_PER_STAGE, "collapse total")
    execution = prereg["execution_counts"]
    require_equal(execution["schedule_material_block_rows"], EXPECTED_ROWS, "row count")
    require_equal(execution["rtl_model_comparisons"], EXPECTED_MODEL_COMPARISONS, "model comparisons")
    require_equal(execution["per_input_cycle_observations"], EXPECTED_MODEL_COMPARISONS, "cycle observations")
    require_equal(execution["storage_comparisons"], EXPECTED_STORAGE_COMPARISONS, "storage comparisons")
    require_equal(execution["repeated_sequence_bridge_comparisons"], EXPECTED_BRIDGES, "bridge comparisons")
    require_equal(
        tuple(prereg["structural_contract"]["valid_outcomes"]),
        STRUCTURAL_VERDICTS,
        "structural verdicts",
    )
    receipt = prereg["receipt_contract"]
    require_equal(receipt["schema"], "E256-HARDWARE-H4-SEQUENCE-GATE-1", "receipt schema")
    require_equal(receipt["path"], str(RECEIPT.relative_to(REPO)), "receipt path")
    require_equal(receipt["scratch_path"], str(SCRATCH.relative_to(REPO)), "scratch path")
    require_equal(receipt["emit_target"], "make e256-hw-h4-sequence", "emit target")
    require_equal(receipt["check_target"], "make e256-hw-h4-sequence-check", "check target")
    require_equal(tuple(receipt["required_sections"]), EXPECTED_PAYLOAD_KEYS[2:], "receipt sections")
    require_equal(
        tuple(prereg["material_corpus"]["material_set_ids"]),
        EXPECTED_MATERIAL_IDS,
        "material IDs",
    )
    require_equal(prereg["material_corpus"]["canonical_sha256"], FROZEN_MATERIAL_SHA256, "material anchor")
    require_equal(prereg["material_corpus"]["aes_sbox_sha256"], AES_SBOX_SHA256, "AES S-box hash")


def validate_makefile_targets() -> dict:
    text = MAKEFILE.read_text(encoding="utf-8")
    require_equal(text.count("e256-hw-h4-sequence:"), 1, "H4 emit target count")
    require_equal(text.count("e256-hw-h4-sequence-check:"), 1, "H4 check target count")
    require_true(
        re.search(
            r"(?m)^e256-hw-h4-sequence:\n\tpython3 Scripts/e256_hardware_h4_sequence_gate\.py$",
            text,
        )
        is not None,
        "H4 emit target recipe drift",
    )
    require_true(
        re.search(
            r"(?m)^e256-hw-h4-sequence-check:\n\tpython3 Scripts/e256_hardware_h4_sequence_gate\.py --check$",
            text,
        )
        is not None,
        "H4 check target recipe drift",
    )
    phony_lines = [line for line in text.splitlines() if line.startswith(".PHONY:")]
    require_true(any("e256-hw-h4-sequence" in line for line in phony_lines), "H4 targets are not phony")
    return {
        "path": str(MAKEFILE.relative_to(REPO)),
        "emit_recipe_exact": True,
        "check_recipe_exact": True,
        "phony_declared": True,
    }


def validate_predecessors(prereg: Mapping) -> Tuple[List[dict], Dict[str, dict], List[List[int]]]:
    declared = tuple(
        (
            item["id"],
            item["receipt"],
            item["raw_sha256_at_freeze"],
            item["deterministic_payload_sha256"],
        )
        for item in prereg["predecessors"]
    )
    expected_declared = tuple(
        (identifier, relative, raw_hash, payload_hash)
        for identifier, relative, _schema, raw_hash, payload_hash in PREDECESSORS
    )
    require_equal(declared, expected_declared, "predecessor declarations")

    records = []
    payloads: Dict[str, dict] = {}
    for identifier, relative, schema, raw_hash, payload_hash in PREDECESSORS:
        path = REPO / relative
        require_equal(sha256_file(path), raw_hash, f"{identifier} raw receipt")
        outer = strict_json_load(path)
        payload = outer.get("deterministic_payload")
        require_true(isinstance(payload, dict), f"{identifier} payload absent")
        require_equal(payload.get("schema"), schema, f"{identifier} schema")
        require_equal(payload.get("status"), "OPEN_PROGRESS", f"{identifier} status")
        recomputed = sha256_bytes(canonical_json_bytes(payload, deterministic=False))
        require_equal(recomputed, payload_hash, f"{identifier} payload digest")
        require_equal(outer.get("deterministic_payload_sha256"), payload_hash, f"{identifier} stored digest")
        payloads[identifier] = payload
        records.append(
            {
                "id": identifier,
                "path": relative,
                "schema": schema,
                "raw_sha256": raw_hash,
                "deterministic_payload_sha256": payload_hash,
            }
        )

    candidate = payloads["E256-063-steps-2-3"]["results"]["h4_wiring"]
    certified = candidate["certified_set"]
    require_true(isinstance(certified, list), "certified list is not an array")
    require_equal(len(certified), CERTIFIED_COUNT, "certified list count")
    require_equal(candidate["certified_set_sha256"], CERTIFIED_SHA256, "candidate certified hash")
    require_equal(sha256_bytes(canonical_json_bytes(certified)), CERTIFIED_SHA256, "recomputed certified hash")
    require_equal(certified[0], [0, 1, 2, 5], "first certified tuple")
    require_equal(certified[1], [0, 1, 3, 4], "fixed certified tuple")
    require_equal(certified[-1], [7, 6, 5, 2], "last certified tuple")
    normalized = []
    for index, wiring in enumerate(certified):
        require_true(
            isinstance(wiring, list)
            and len(wiring) == 4
            and all(type(value) is int and 0 <= value < 8 for value in wiring),
            f"invalid certified tuple {index}",
        )
        require_equal(len(set(wiring)), 4, f"certified tuple {index} distinctness")
        normalized.append(list(wiring))
    require_equal(len({tuple(item) for item in normalized}), CERTIFIED_COUNT, "unique certified tuples")

    collapse = payloads["E256-063-h3-collapse"]
    require_equal(collapse["inputs"]["preregistration"]["sha256"], COLLAPSE_PREREG_SHA256, "collapse prereg hash")
    require_equal(collapse["material_normal_form"]["terminal_rule"], "K_R excludes A_R and must be derived separately for each tested prefix R", "collapse terminal rule")
    h2 = payloads["E256-063-h2-integrated-cost"]
    require_equal(h2["interpretation"]["harness_valid"], True, "H2 harness validity")
    require_equal(h2["interpretation"]["claim_movement"], False, "H2 claim movement")
    return records, payloads, normalized


def validate_toolchain(h2_helpers, prereg: Mapping) -> dict:
    require_equal(sys.version.split()[0], "3.9.6", "running Python version")
    yosys = h2_helpers.first_output_line(["yosys", "-V"])
    iverilog = h2_helpers.first_output_line(["iverilog", "-V"])
    tool = prereg["toolchain"]
    require_true(yosys.startswith(tool["yosys"]["required_version_prefix"]), f"Yosys version drift: {yosys!r}")
    require_true(tool["yosys"]["required_git_sha"] in yosys, "Yosys git SHA drift")
    require_true(iverilog.startswith(tool["iverilog"]["required_version_prefix"]), f"Icarus version drift: {iverilog!r}")
    require_equal(platform.system(), "Darwin", "target operating system")
    require_true(platform.machine() in ("arm64", "aarch64"), "target is not Apple Silicon")
    return {
        "python": sys.version.split()[0],
        "yosys": yosys,
        "iverilog": iverilog,
        "host_system": platform.system(),
        "host_machine": platform.machine(),
    }


def validate_integrity() -> Tuple[dict, Mapping, Any, List[List[int]], Dict[str, dict]]:
    require_equal(sha256_file(PREREG), PREREG_SHA256, "raw preregistration SHA-256")
    prereg = strict_json_load(PREREG)
    validate_deterministic_types(prereg, "preregistration")
    validate_contract_shape(prereg)

    require_equal(sha256_file(H2_RTL), H2_RTL_SHA256, "frozen H2 RTL")
    require_equal(sha256_file(H2_TESTBENCH), H2_TESTBENCH_SHA256, "frozen H2 testbench")
    require_equal(sha256_file(H2_RUNNER), H2_RUNNER_SHA256, "frozen H2 runner")
    require_true(RTL.is_file() and TESTBENCH.is_file(), "H4 implementation sibling missing")
    h2_helpers = load_h2_helpers()

    architecture_raw = ARCHITECTURE.read_bytes()
    architecture_contract = prereg["architecture_contract"]
    require_equal(
        marker_digest_inclusive(
            architecture_raw,
            architecture_contract["start_marker"],
            architecture_contract["end_marker"],
        ),
        H4_ARCHITECTURE_SHA256,
        "inclusive H4 architecture marker",
    )
    require_equal(
        marker_digest_between(
            architecture_raw,
            "<!-- E256-H-CONTRACT-START -->",
            "<!-- E256-H-CONTRACT-END -->",
        ),
        BASE_ARCHITECTURE_SHA256,
        "base architecture marker",
    )
    require_equal(
        marker_digest_between(
            architecture_raw,
            "<!-- E256-H-H2-CONTRACT-START -->",
            "<!-- E256-H-H2-CONTRACT-END -->",
        ),
        H2_ARCHITECTURE_SHA256,
        "H2 architecture marker",
    )

    predecessor_records, predecessor_payloads, certified = validate_predecessors(prereg)
    frozen_sources = {
        "h2_rtl": {"path": str(H2_RTL.relative_to(REPO)), "sha256": H2_RTL_SHA256},
        "h2_testbench": {"path": str(H2_TESTBENCH.relative_to(REPO)), "sha256": H2_TESTBENCH_SHA256},
        "h2_runner": {"path": str(H2_RUNNER.relative_to(REPO)), "sha256": H2_RUNNER_SHA256},
    }
    for role, record in frozen_sources.items():
        require_equal(prereg["frozen_sources"][role], record, f"declared {role}")

    integrity = {
        "preregistration": {"path": str(PREREG.relative_to(REPO)), "raw_sha256": PREREG_SHA256},
        "architecture_contracts": {
            "path": str(ARCHITECTURE.relative_to(REPO)),
            "h4_inclusive_sha256": H4_ARCHITECTURE_SHA256,
            "base_between_markers_sha256": BASE_ARCHITECTURE_SHA256,
            "h2_between_markers_sha256": H2_ARCHITECTURE_SHA256,
        },
        "predecessors": predecessor_records,
        "frozen_sources": frozen_sources,
        "implementation_sources": {
            "rtl": {"path": str(RTL.relative_to(REPO)), "sha256": sha256_file(RTL)},
            "testbench": {"path": str(TESTBENCH.relative_to(REPO)), "sha256": sha256_file(TESTBENCH)},
            "runner": {"path": str(Path(__file__).resolve().relative_to(REPO)), "sha256": sha256_file(Path(__file__).resolve())},
        },
        "makefile": validate_makefile_targets(),
        "toolchain": validate_toolchain(h2_helpers, prereg),
        "all_exact": True,
    }
    return integrity, prereg, h2_helpers, certified, predecessor_payloads


# ---------------------------------------------------------------------------
# Independent byte model, material derivation, and frozen corpora.


def gf_mul(a: int, b: int) -> int:
    result = 0
    while b:
        if b & 1:
            result ^= a
        a = ((a << 1) ^ 0x11B) if (a & 0x80) else (a << 1)
        a &= 0xFF
        b >>= 1
    return result


def gf_pow(a: int, exponent: int) -> int:
    result = 1
    while exponent:
        if exponent & 1:
            result = gf_mul(result, a)
        a = gf_mul(a, a)
        exponent >>= 1
    return result


def rol8(value: int, amount: int) -> int:
    amount %= 8
    return ((value << amount) | (value >> (8 - amount))) & 0xFF


def build_aes_sbox() -> Tuple[int, ...]:
    values = []
    for value in range(256):
        inverse = 0 if value == 0 else gf_pow(value, 254)
        values.append(
            inverse
            ^ rol8(inverse, 1)
            ^ rol8(inverse, 2)
            ^ rol8(inverse, 3)
            ^ rol8(inverse, 4)
            ^ 0x63
        )
    table = tuple(values)
    require_equal(sha256_bytes(bytes(table)), AES_SBOX_SHA256, "derived AES S-box")
    return table


AES_SBOX = build_aes_sbox()
ZERO_STATE = tuple(0 for _ in range(STATE_BYTES))


def xor_states(*states: Sequence[int]) -> List[int]:
    require_true(bool(states), "state XOR requires operands")
    require_true(all(len(state) == STATE_BYTES for state in states), "state XOR width")
    output = [0] * STATE_BYTES
    for state in states:
        for index, value in enumerate(state):
            require_true(type(value) is int and 0 <= value <= 255, "invalid state byte")
            output[index] ^= value
    return output


def xt(value: int) -> int:
    return (((value << 1) ^ 0x1B) if value & 0x80 else (value << 1)) & 0xFF


def linear_layer(state: Sequence[int], wiring: Sequence[int], direction: int = 1) -> List[int]:
    require_equal(len(state), STATE_BYTES, "linear state width")
    require_equal(len(wiring), 4, "linear wiring width")
    require_true(direction in (-1, 1), "linear direction")
    shifted = [0] * STATE_BYTES
    for column in range(8):
        for row in range(4):
            offset = int(wiring[row])
            require_true(0 <= offset < 8, "H4 offset outside 0..7")
            source_column = (column + direction * offset) % 8
            shifted[4 * column + row] = int(state[4 * source_column + row])
    output = [0] * STATE_BYTES
    for column in range(8):
        a0, a1, a2, a3 = shifted[4 * column : 4 * column + 4]
        output[4 * column + 0] = xt(a0) ^ xt(a1) ^ a1 ^ a2 ^ a3
        output[4 * column + 1] = a0 ^ xt(a1) ^ xt(a2) ^ a2 ^ a3
        output[4 * column + 2] = a0 ^ a1 ^ xt(a2) ^ xt(a3) ^ a3
        output[4 * column + 3] = xt(a0) ^ a0 ^ a1 ^ a2 ^ xt(a3)
    return output


def round_with_key(
    state: Sequence[int],
    round_key: Sequence[int],
    wiring: Sequence[int],
    direction: int = 1,
) -> List[int]:
    substituted = [AES_SBOX[int(value)] for value in state]
    return xor_states(linear_layer(substituted, wiring, direction), round_key)


def h4_code(wiring: Sequence[int]) -> int:
    require_equal(len(wiring), 4, "H4 code arity")
    code = 0
    for index, value in enumerate(wiring):
        require_true(type(value) is int and 0 <= value < 8, "invalid H4 code")
        code |= value << (3 * index)
    return code


def pack_sequence(sequence: Sequence[Sequence[int]]) -> int:
    require_equal(len(sequence), ROUNDS, "sequence tuple count")
    value = 0
    for round_index, wiring in enumerate(sequence):
        value |= h4_code(wiring) << (12 * round_index)
    return value


def sequence_hex(sequence: Sequence[Sequence[int]]) -> str:
    return f"{pack_sequence(sequence):036x}"


def state_hex(state: Sequence[int]) -> str:
    require_equal(len(state), STATE_BYTES, "state hex width")
    return bytes(int(value) for value in state).hex()


def state_to_verilog_hex(state: Sequence[int]) -> str:
    require_equal(len(state), STATE_BYTES, "Verilog state width")
    value = 0
    for index, byte in enumerate(state):
        value |= int(byte) << (8 * index)
    return f"{value:064x}"


def structural_records() -> Iterator[dict]:
    for a in range(CERTIFIED_COUNT):
        for d in range(CERTIFIED_COUNT):
            yield {
                "a": a,
                "d": d,
                "indices": [(a + round_index * d) % CERTIFIED_COUNT for round_index in range(ROUNDS)],
            }


def executable_records() -> List[dict]:
    return [
        {
            "a": a,
            "d": d,
            "indices": [(a + round_index * d) % CERTIFIED_COUNT for round_index in range(ROUNDS)],
        }
        for d in (0, 1)
        for a in range(CERTIFIED_COUNT)
    ]


def corpus_digest_perturbation_control() -> dict:
    def mutated_records() -> Iterator[dict]:
        for index, record in enumerate(structural_records()):
            copied = {"a": record["a"], "d": record["d"], "indices": list(record["indices"])}
            if index == 0:
                copied["indices"][0] = (copied["indices"][0] + 1) % CERTIFIED_COUNT
            yield copied

    digest, count = canonical_list_digest(mutated_records())
    require_equal(count, STRUCTURAL_SCHEDULES, "mutated structural record count")
    require_true(digest != STRUCTURAL_CORPUS_SHA256, "corpus perturbation escaped digest")
    return {
        "mutation": "first generated structural index incremented modulo 384",
        "expected_sha256": STRUCTURAL_CORPUS_SHA256,
        "mutated_sha256": digest,
        "shared_validator_rejected": True,
        "detected": True,
    }


def parse_material(identifier: str, domain: str, raw: bytes) -> dict:
    require_equal(len(raw), MATERIAL_BYTES, f"{identifier} material bytes")
    p_in = [
        [raw[(round_index * 32 + lane) * 2] for lane in range(32)]
        for round_index in range(ROUNDS)
    ]
    p_out = [
        [raw[(round_index * 32 + lane) * 2 + 1] for lane in range(32)]
        for round_index in range(ROUNDS)
    ]
    masks = [
        [raw[MATERIAL_MASK_BASE + mask_index * 32 + lane] for lane in range(32)]
        for mask_index in range(MASK_WORDS)
    ]
    return {
        "id": identifier,
        "domain": domain,
        "raw": raw,
        "raw_sha256": sha256_bytes(raw),
        "p_in": p_in,
        "p_out": p_out,
        "masks": masks,
    }


def derive_materials() -> List[dict]:
    materials = []
    for identifier, domain, expected_hash in zip(
        EXPECTED_MATERIAL_IDS, EXPECTED_MATERIAL_DOMAINS, EXPECTED_MATERIAL_HASHES
    ):
        raw = hashlib.shake_256(domain.encode("ascii")).digest(MATERIAL_BYTES)
        material = parse_material(identifier, domain, raw)
        require_equal(material["raw_sha256"], expected_hash, f"{identifier} raw hash")
        materials.append(material)
    require_equal(materials[0]["raw_sha256"], FROZEN_MATERIAL_SHA256, "material anchor")
    return materials


def derive_blocks() -> List[Tuple[str, bytes]]:
    shake = hashlib.shake_256(b"E256-H/collapse/blocks/v1").digest(128)
    blocks = [
        ("all_zero", bytes(32)),
        ("all_ff", bytes([0xFF] * 32)),
        ("ascending_00_1f", bytes(range(32))),
        ("descending_ff_e0", bytes(range(0xFF, 0xDF, -1))),
    ]
    blocks.extend(
        (f"shake_{index}", shake[index * 32 : (index + 1) * 32])
        for index in range(4)
    )
    require_equal(tuple(identifier for identifier, _ in blocks), EXPECTED_BLOCK_IDS, "block IDs")
    require_equal(sha256_bytes(b"".join(block for _, block in blocks)), BLOCK_CORPUS_SHA256, "block corpus hash")
    return blocks


def build_corpora(certified: Sequence[Sequence[int]], materials: Sequence[Mapping], blocks: Sequence[Tuple[str, bytes]]) -> Tuple[dict, List[dict]]:
    structural_digest, structural_count = canonical_list_digest(structural_records())
    require_equal(structural_count, STRUCTURAL_SCHEDULES, "structural corpus count")
    require_equal(structural_digest, STRUCTURAL_CORPUS_SHA256, "structural corpus digest")
    executable = executable_records()
    require_equal(len(executable), EXECUTABLE_SCHEDULES, "executable corpus count")
    executable_digest = sha256_bytes(canonical_json_bytes(executable))
    require_equal(executable_digest, EXECUTABLE_CORPUS_SHA256, "executable corpus digest")
    require_equal(sum(len(record["indices"]) for record in executable), 9216, "executable tuple placements")
    corpora = {
        "certified_list": {
            "count": len(certified),
            "canonical_sha256": sha256_bytes(canonical_json_bytes(certified)),
            "first": list(certified[0]),
            "fixed_index_1": list(certified[1]),
            "last": list(certified[-1]),
            "order_preserved": True,
        },
        "structural": {
            "order": "a outer 0..383, d inner 0..383",
            "schedule_count": structural_count,
            "rounds_per_schedule": ROUNDS,
            "contiguous_three_round_windows": STRUCTURAL_WINDOWS,
            "adjacent_transition_placements": TRANSITION_PLACEMENTS,
            "canonical_sha256": structural_digest,
        },
        "executable": {
            "order": "d outer in [0,1], a inner 0..383",
            "steps": [0, 1],
            "schedule_count": len(executable),
            "repeated_schedule_count": 384,
            "switching_schedule_count": 384,
            "tuple_placements": 9216,
            "canonical_sha256": executable_digest,
        },
        "materials": [
            {
                "id": material["id"],
                "domain": material["domain"],
                "raw_bytes": len(material["raw"]),
                "raw_sha256": material["raw_sha256"],
            }
            for material in materials
        ],
        "blocks": [
            {"id": identifier, "bytes_hex": block.hex()}
            for identifier, block in blocks
        ],
        "block_corpus_sha256": BLOCK_CORPUS_SHA256,
        "schedule_material_block_rows": EXPECTED_ROWS,
        "all_exact": True,
    }
    return corpora, executable


def sequence_effective_masks(
    material: Mapping,
    sequence: Sequence[Sequence[int]],
    wrong_transport: bool = False,
    include_terminal_a12: bool = False,
) -> List[List[int]]:
    require_equal(len(sequence), ROUNDS, "effective-mask sequence length")
    if include_terminal_a12:
        raise GateError("A_12 does not exist in frozen material")
    keys = [xor_states(material["masks"][0], material["p_in"][0])]
    for key_index in range(1, ROUNDS):
        transport_index = key_index if wrong_transport else key_index - 1
        keys.append(
            xor_states(
                linear_layer(material["p_out"][key_index - 1], sequence[transport_index]),
                material["masks"][key_index],
                material["p_in"][key_index],
            )
        )
    keys.append(
        xor_states(
            linear_layer(material["p_out"][ROUNDS - 1], sequence[ROUNDS - 1]),
            material["masks"][ROUNDS],
        )
    )
    require_equal(len(keys), MASK_WORDS, "effective-mask word count")
    return keys


def canonical_permute(
    block: Sequence[int],
    keys: Sequence[Sequence[int]],
    sequence: Sequence[Sequence[int]],
    direction: int = 1,
) -> List[int]:
    require_equal(len(keys), MASK_WORDS, "canonical key count")
    require_equal(len(sequence), ROUNDS, "canonical sequence count")
    state = xor_states(block, keys[0])
    for round_index in range(ROUNDS):
        state = round_with_key(
            state, keys[round_index + 1], sequence[round_index], direction
        )
    return state


def raw_prefixes(block: Sequence[int], material: Mapping, sequence: Sequence[Sequence[int]]) -> List[List[int]]:
    state = xor_states(block, material["masks"][0])
    outputs = []
    for round_index in range(ROUNDS):
        nonlinear = [
            AES_SBOX[state[lane] ^ material["p_in"][round_index][lane]]
            ^ material["p_out"][round_index][lane]
            for lane in range(STATE_BYTES)
        ]
        state = xor_states(
            linear_layer(nonlinear, sequence[round_index]),
            material["masks"][round_index + 1],
        )
        outputs.append(state)
    return outputs


def stage_a_prefixes(block: Sequence[int], material: Mapping, sequence: Sequence[Sequence[int]]) -> List[List[int]]:
    transformed_masks = [list(material["masks"][0])]
    for round_index in range(ROUNDS):
        transformed_masks.append(
            xor_states(
                material["masks"][round_index + 1],
                linear_layer(material["p_out"][round_index], sequence[round_index]),
            )
        )
    state = xor_states(block, transformed_masks[0])
    outputs = []
    for round_index in range(ROUNDS):
        nonlinear = [
            AES_SBOX[state[lane] ^ material["p_in"][round_index][lane]]
            for lane in range(STATE_BYTES)
        ]
        state = xor_states(
            linear_layer(nonlinear, sequence[round_index]),
            transformed_masks[round_index + 1],
        )
        outputs.append(state)
    return outputs


def canonical_terminal_prefixes(
    block: Sequence[int],
    material: Mapping,
    sequence: Sequence[Sequence[int]],
    keys: Sequence[Sequence[int]],
) -> List[List[int]]:
    # The carried state is Z_r=X_r XOR A_r.  Each recorded boundary removes
    # A_(r+1) so it is the independently comparable terminal X_(r+1).
    boundary = xor_states(block, keys[0])
    outputs = []
    for round_index in range(ROUNDS):
        next_boundary = round_with_key(
            boundary, keys[round_index + 1], sequence[round_index]
        )
        if round_index + 1 < ROUNDS:
            terminal = xor_states(next_boundary, material["p_in"][round_index + 1])
        else:
            terminal = next_boundary
        outputs.append(terminal)
        boundary = next_boundary
    return outputs


def build_configurations(
    certified: Sequence[Sequence[int]],
    executable: Sequence[Mapping],
    materials: Sequence[Mapping],
) -> List[dict]:
    configurations = []
    for schedule_index, record in enumerate(executable):
        sequence = [list(certified[index]) for index in record["indices"]]
        live_indices = [
            ((record["a"] + 1) + round_index * record["d"]) % CERTIFIED_COUNT
            for round_index in range(ROUNDS)
        ]
        live_sequence = [list(certified[index]) for index in live_indices]
        require_true(sequence_hex(sequence) != sequence_hex(live_sequence), "live sequence did not change")
        for material_index, material in enumerate(materials):
            configurations.append(
                {
                    "index": len(configurations),
                    "schedule_index": schedule_index,
                    "material_index": material_index,
                    "material_id": material["id"],
                    "a": record["a"],
                    "d": record["d"],
                    "indices": list(record["indices"]),
                    "sequence": sequence,
                    "sequence_hex": sequence_hex(sequence),
                    "live_indices": live_indices,
                    "live_sequence": live_sequence,
                    "live_sequence_hex": sequence_hex(live_sequence),
                    "keys": sequence_effective_masks(material, sequence),
                }
            )
    require_equal(len(configurations), CONFIG_COUNT, "configuration count")
    require_equal([item["index"] for item in configurations], list(range(CONFIG_COUNT)), "configuration indices")
    return configurations


# ---------------------------------------------------------------------------
# Complete structural census and sequence collapse.


def dependency_window(
    sequence: Sequence[Sequence[int]],
) -> Tuple[bool, Optional[dict]]:
    require_equal(len(sequence), 3, "dependency window length")
    dependencies = [1 << index for index in range(STATE_BYTES)]
    for wiring in sequence:
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
    for lane, value in enumerate(dependencies):
        if value != FULL_DEPENDENCY_MASK:
            missing = [index for index in range(STATE_BYTES) if not (value >> index) & 1]
            return False, {"output_lane": lane, "missing_input_lanes": missing}
    return True, None


def run_structural_census(certified: Sequence[Sequence[int]]) -> dict:
    # A window is determined by its starting certified index b and step d.
    # For each of ten start rounds, a -> b is a permutation, so every (b,d)
    # placement occurs exactly ten times.  We still recover the first witness
    # in the frozen a,d,start order below without filtering any placement.
    failures: Dict[Tuple[int, int], dict] = {}
    unique_windows = 0
    for b in range(CERTIFIED_COUNT):
        for d in range(CERTIFIED_COUNT):
            indices = [
                (b + offset * d) % CERTIFIED_COUNT for offset in range(3)
            ]
            sequence = [certified[index] for index in indices]
            passed, detail = dependency_window(sequence)
            unique_windows += 1
            if not passed:
                failures[(b, d)] = {
                    "indices": indices,
                    "tuples": [list(item) for item in sequence],
                    "detail": detail,
                }
    require_equal(unique_windows, STRUCTURAL_SCHEDULES, "unique dependency windows")
    failure_count = len(failures) * 10
    first = None
    if failures:
        for a in range(CERTIFIED_COUNT):
            if first is not None:
                break
            for d in range(CERTIFIED_COUNT):
                if first is not None:
                    break
                for start_round in range(10):
                    b = (a + start_round * d) % CERTIFIED_COUNT
                    detail = failures.get((b, d))
                    if detail is not None:
                        first = {
                            "a": a,
                            "d": d,
                            "start_round": start_round,
                            "indices": detail["indices"],
                            "tuples": detail["tuples"],
                            "first_incomplete_output": detail["detail"],
                        }
                        break
    require_equal(failure_count == 0, first is None, "structural witness consistency")
    verdict = STRUCTURAL_VERDICTS[0] if failure_count == 0 else STRUCTURAL_VERDICTS[1]
    return {
        "criterion": "three exact per-round selectors, lane-preserving S-box dependencies, exact row shift, and all-nonzero AES column mixing",
        "schedule_count": STRUCTURAL_SCHEDULES,
        "unique_window_classes": unique_windows,
        "windows_per_class": 10,
        "contiguous_three_round_windows": STRUCTURAL_WINDOWS,
        "adjacent_transition_placements": TRANSITION_PLACEMENTS,
        "failure_count": failure_count,
        "first_counterexample": first,
        "verdict": verdict,
        "fixed_tuple_four_round_or_25_active_sbox_inherited": False,
        "complete_no_filtering": True,
    }


def run_collapse_equivalence(
    executable: Sequence[Mapping],
    certified: Sequence[Sequence[int]],
    materials: Sequence[Mapping],
    blocks: Sequence[Tuple[str, bytes]],
) -> dict:
    stage_a_hash = hashlib.sha256()
    stage_b_hash = hashlib.sha256()
    stage_a_count = 0
    stage_b_count = 0
    for schedule_index, record in enumerate(executable):
        sequence = [certified[index] for index in record["indices"]]
        for material in materials:
            keys = sequence_effective_masks(material, sequence)
            for block_id, block in blocks:
                original = raw_prefixes(block, material, sequence)
                stage_a = stage_a_prefixes(block, material, sequence)
                stage_b = canonical_terminal_prefixes(block, material, sequence, keys)
                for round_index in range(ROUNDS):
                    identity = {
                        "schedule_index": schedule_index,
                        "a": record["a"],
                        "d": record["d"],
                        "material": material["id"],
                        "block": block_id,
                        "round": round_index + 1,
                    }
                    if original[round_index] != stage_a[round_index]:
                        raise GateError("Stage A sequence collapse mismatch: " + repr(identity))
                    if original[round_index] != stage_b[round_index]:
                        raise GateError("Stage B sequence collapse mismatch: " + repr(identity))
                    stage_a_record = dict(identity)
                    stage_a_record.update(
                        {
                            "raw": state_hex(original[round_index]),
                            "stage_a": state_hex(stage_a[round_index]),
                        }
                    )
                    stage_b_record = dict(identity)
                    stage_b_record.update(
                        {
                            "raw": state_hex(original[round_index]),
                            "stage_b": state_hex(stage_b[round_index]),
                        }
                    )
                    update_record_hash(stage_a_hash, stage_a_record)
                    update_record_hash(stage_b_hash, stage_b_record)
                    stage_a_count += 1
                    stage_b_count += 1
    require_equal(stage_a_count, EXPECTED_COLLAPSE_PER_STAGE, "Stage A executed comparisons")
    require_equal(stage_b_count, EXPECTED_COLLAPSE_PER_STAGE, "Stage B executed comparisons")
    return {
        "stage_a": {
            "expected_comparisons": EXPECTED_COLLAPSE_PER_STAGE,
            "executed_comparisons": stage_a_count,
            "mismatches": 0,
            "aggregate_sha256": stage_a_hash.hexdigest(),
            "byte_exact": True,
        },
        "stage_b": {
            "expected_comparisons": EXPECTED_COLLAPSE_PER_STAGE,
            "executed_comparisons": stage_b_count,
            "mismatches": 0,
            "aggregate_sha256": stage_b_hash.hexdigest(),
            "previous_selector_transport_exact": True,
            "terminal_a12_absent": True,
            "byte_exact": True,
        },
        "total_comparisons": stage_a_count + stage_b_count,
        "aggregate_encoding": AGGREGATE_ENCODING,
        "all_byte_exact": True,
    }


def wrong_collapse_transport_control(
    configuration: Mapping,
    material: Mapping,
    block_id: str,
    block: Sequence[int],
) -> dict:
    require_equal(configuration["d"], 1, "wrong-transport switching witness d")
    sequence = configuration["sequence"]
    raw = raw_prefixes(block, material, sequence)
    wrong_keys = sequence_effective_masks(material, sequence, wrong_transport=True)
    mutated = canonical_terminal_prefixes(block, material, sequence, wrong_keys)
    mismatches = [index + 1 for index in range(ROUNDS) if raw[index] != mutated[index]]
    require_true(bool(mismatches), "wrong collapse transport produced no mismatch")
    return {
        "schedule": {"a": configuration["a"], "d": configuration["d"], "indices": configuration["indices"]},
        "material": material["id"],
        "block": block_id,
        "mismatching_boundaries": mismatches,
        "first_mismatch_round": mismatches[0],
        "shared_canonical_boundary_path": True,
        "detected": True,
    }


def terminal_a12_control(material: Mapping, sequence: Sequence[Sequence[int]]) -> dict:
    message = None
    try:
        sequence_effective_masks(material, sequence, include_terminal_a12=True)
    except GateError as error:
        message = str(error)
    require_equal(message, "A_12 does not exist in frozen material", "terminal A12 typed rejection")
    return {
        "typed_rejection": message,
        "material_extended": False,
        "detected": True,
    }


# ---------------------------------------------------------------------------
# RTL vectors, strict parsers, exact functional/cycle grading, and controls.


def prepare_scratch() -> None:
    require_equal(SCRATCH.resolve().parent, (REPO / "build").resolve(), "scratch parent")
    if SCRATCH.exists():
        shutil.rmtree(SCRATCH)
    SCRATCH.mkdir(parents=True, exist_ok=False)


def write_hex_lines(path: Path, lines: Sequence[str], pattern: str, label: str) -> None:
    require_true(all(re.fullmatch(pattern, line) is not None for line in lines), f"{label} grammar")
    path.write_text("".join(line + "\n" for line in lines), encoding="utf-8")
    require_equal(path.read_text(encoding="utf-8").splitlines(), list(lines), f"{label} round trip")


def write_main_vectors(configurations: Sequence[Mapping], blocks: Sequence[Tuple[str, bytes]]) -> None:
    mask_lines = [
        state_to_verilog_hex(word)
        for configuration in configurations
        for word in configuration["keys"]
    ]
    sequence_lines = [configuration["sequence_hex"] for configuration in configurations]
    live_lines = [configuration["live_sequence_hex"] for configuration in configurations]
    block_lines = [state_to_verilog_hex(block) for _identifier, block in blocks]
    require_equal(len(mask_lines), CONFIG_COUNT * MASK_WORDS, "main mask lines")
    require_equal(len(sequence_lines), CONFIG_COUNT, "main sequence lines")
    require_equal(len(live_lines), CONFIG_COUNT, "main live sequence lines")
    write_hex_lines(SCRATCH / "masks.hex", mask_lines, r"[0-9a-f]{64}", "main masks")
    write_hex_lines(SCRATCH / "h4-sequences.hex", sequence_lines, r"[0-9a-f]{36}", "main sequences")
    write_hex_lines(SCRATCH / "live-h4-sequences.hex", live_lines, r"[0-9a-f]{36}", "main live sequences")
    write_hex_lines(SCRATCH / "blocks.hex", block_lines, r"[0-9a-f]{64}", "main blocks")


def run_process(command: Sequence[str], timeout: int, label: str) -> str:
    process = subprocess.run(
        list(command), cwd=str(REPO), capture_output=True, text=True,
        timeout=timeout, check=False
    )
    output = (process.stdout or "") + (process.stderr or "")
    if process.returncode != 0:
        raise GateError(f"{label} exited {process.returncode}: {output[-3000:]}")
    return output


def compile_iverilog(top: str, output: Path, parameters: Mapping[str, int], label: str) -> None:
    command = ["iverilog", "-g2012", "-s", top]
    for name, value in parameters.items():
        require_true(type(value) is int and value >= 0, f"{label} parameter {name}")
        command.append(f"-P{top}.{name}={value}")
    command.extend(
        ["-o", str(output), str(TESTBENCH), str(H2_RTL), str(RTL)]
    )
    run_process(command, 900, label + " compile")


def parse_main_result_lines(
    lines: Sequence[str], configurations: Sequence[Mapping]
) -> Dict[Tuple[int, int], dict]:
    rows: Dict[Tuple[int, int], dict] = {}
    expected_line_count = len(configurations) * BLOCK_COUNT
    require_equal(len(lines), expected_line_count, "main result line count")
    for line_index, line in enumerate(lines):
        line_number = line_index + 1
        require_true(bool(line), f"blank main result line {line_number}")
        parts = line.split(" ")
        require_true(all(parts), f"noncanonical whitespace at main line {line_number}")
        require_equal(len(parts), 19, f"main token count at line {line_number}")
        require_equal(parts[0], "rtl", f"main tag at line {line_number}")
        config_index = strict_decimal(parts[1], f"config line {line_number}")
        block_index = strict_decimal(parts[2], f"block line {line_number}")
        expected_key = (line_index // BLOCK_COUNT, line_index % BLOCK_COUNT)
        require_equal((config_index, block_index), expected_key, f"main row order line {line_number}")
        require_true(0 <= config_index < len(configurations), f"config range line {line_number}")
        configuration = configurations[config_index]
        require_equal(strict_decimal(parts[3], f"a line {line_number}"), configuration["a"], f"a line {line_number}")
        require_equal(strict_decimal(parts[4], f"d line {line_number}"), configuration["d"], f"d line {line_number}")
        require_true(re.fullmatch(r"[0-9a-f]{36}", parts[5]) is not None, f"sequence grammar line {line_number}")
        require_equal(parts[5], configuration["sequence_hex"], f"sequence line {line_number}")
        require_true(re.fullmatch(r"[0-9a-f]{2}", parts[6]) is not None, f"run-mask grammar line {line_number}")
        expected_mask = 0x0F if configuration["d"] == 0 else 0x0A
        require_equal(int(parts[6], 16), expected_mask, f"run mask line {line_number}")
        outputs: List[Optional[str]] = []
        latencies: List[Optional[int]] = []
        intervals: List[Optional[int]] = []
        for variant_index, variant in enumerate(EXPECTED_VARIANT_IDS):
            executed = variant.endswith("sequence") or configuration["d"] == 0
            output_token = parts[7 + variant_index]
            latency_token = parts[11 + variant_index]
            interval_token = parts[15 + variant_index]
            if executed:
                require_true(re.fullmatch(r"[0-9a-f]{64}", output_token) is not None, f"{variant} output line {line_number}")
                latency = strict_decimal(latency_token, f"{variant} latency line {line_number}")
                interval = strict_decimal(interval_token, f"{variant} interval line {line_number}")
                require_equal(latency, 12, f"{variant} latency line {line_number}")
                require_equal(interval, 13, f"{variant} interval line {line_number}")
                outputs.append(output_token)
                latencies.append(latency)
                intervals.append(interval)
            else:
                require_equal(
                    (output_token, latency_token, interval_token),
                    ("-", "-", "-"),
                    f"extra repeated output/cycle evidence line {line_number}",
                )
                outputs.append(None)
                latencies.append(None)
                intervals.append(None)
        key = (config_index, block_index)
        require_true(key not in rows, f"duplicate main result key {key}")
        rows[key] = {
            "outputs": outputs,
            "latencies": latencies,
            "intervals": intervals,
            "run_mask": expected_mask,
        }
    expected_keys = {
        (config_index, block_index)
        for config_index in range(len(configurations))
        for block_index in range(BLOCK_COUNT)
    }
    require_equal(set(rows), expected_keys, "main result key set")
    return rows


def run_main_simulation(
    configurations: Sequence[Mapping], blocks: Sequence[Tuple[str, bytes]]
) -> Tuple[dict, List[str], dict]:
    binary = SCRATCH / "e256h_h4_sequence_core_tb.vvp"
    compile_iverilog(
        "e256h_h4_sequence_core_tb",
        binary,
        {"CONFIG_COUNT": len(configurations), "MATERIAL_COUNT": 3},
        "main H4 sequence testbench",
    )
    output = run_process(["vvp", str(binary)], SIM_TIMEOUT_SECONDS, "main H4 sequence simulation")
    sentinel = "E256H_H4_SEQUENCE_CORE_TB_DONE"
    require_equal(output.count(sentinel), 1, "main completion sentinel")
    result_path = SCRATCH / "results.txt"
    require_true(result_path.is_file(), "main results file absent")
    lines = result_path.read_text(encoding="utf-8").splitlines()
    rows = parse_main_result_lines(lines, configurations)
    protocol = {
        "completion_sentinel": sentinel,
        "completion_sentinel_count": 1,
        "incomplete_commit_rejected": True,
        "invalid_start_no_busy_or_done": True,
        "overlapping_begin_start_rejected": True,
        "busy_time_configuration_rejected_without_disturbing_completion": True,
        "post_commit_pins_changed_before_every_graded_run": True,
        "per_input_ready_low_while_busy": True,
        "per_input_ready_high_with_done": True,
    }
    return rows, lines, protocol


def grade_functional(
    rows: Mapping[Tuple[int, int], Mapping],
    configurations: Sequence[Mapping],
    blocks: Sequence[Tuple[str, bytes]],
) -> Tuple[dict, dict]:
    model_hash = hashlib.sha256()
    storage_hash = hashlib.sha256()
    bridge_hash = hashlib.sha256()
    variant_counts = Counter()
    input_sets: Dict[str, Set[Tuple[int, int]]] = {
        variant: set() for variant in EXPECTED_VARIANT_IDS
    }
    latency_sets: Dict[str, Set[int]] = {
        variant: set() for variant in EXPECTED_VARIANT_IDS
    }
    interval_sets: Dict[str, Set[int]] = {
        variant: set() for variant in EXPECTED_VARIANT_IDS
    }
    model_comparisons = 0
    storage_comparisons = 0
    bridges = 0

    for config_index, configuration in enumerate(configurations):
        for block_index, (block_id, block) in enumerate(blocks):
            row = rows[(config_index, block_index)]
            sequence_expected = state_hex(
                canonical_permute(block, configuration["keys"], configuration["sequence"])
            )
            if configuration["d"] == 0:
                repeated_sequence = [configuration["sequence"][0]] * ROUNDS
                repeated_expected = state_hex(
                    canonical_permute(block, configuration["keys"], repeated_sequence)
                )
                require_equal(repeated_expected, sequence_expected, "d=0 model bridge")
            else:
                repeated_expected = None

            for variant_index, variant in enumerate(EXPECTED_VARIANT_IDS):
                executed = variant.endswith("sequence") or configuration["d"] == 0
                observed = row["outputs"][variant_index]
                if not executed:
                    require_equal(observed, None, f"unexecuted {variant}")
                    continue
                expected = sequence_expected if variant.endswith("sequence") else repeated_expected
                require_equal(observed, expected, f"RTL/model {variant} config={config_index} block={block_index}")
                variant_counts[variant] += 1
                input_sets[variant].add((config_index, block_index))
                latency = row["latencies"][variant_index]
                interval = row["intervals"][variant_index]
                require_true(type(latency) is int and type(interval) is int, f"missing cycle evidence {variant}")
                latency_sets[variant].add(latency)
                interval_sets[variant].add(interval)
                model_comparisons += 1
                update_record_hash(
                    model_hash,
                    {
                        "variant": variant,
                        "config": config_index,
                        "a": configuration["a"],
                        "d": configuration["d"],
                        "material": configuration["material_id"],
                        "block": block_id,
                        "output": observed,
                    },
                )

            require_equal(row["outputs"][1], row["outputs"][3], f"sequence FF/ring config={config_index} block={block_index}")
            storage_comparisons += 1
            update_record_hash(storage_hash, {"mode": "sequence", "config": config_index, "block": block_id, "output": row["outputs"][1]})
            if configuration["d"] == 0:
                require_equal(row["outputs"][0], row["outputs"][2], f"repeated FF/ring config={config_index} block={block_index}")
                storage_comparisons += 1
                update_record_hash(storage_hash, {"mode": "repeated", "config": config_index, "block": block_id, "output": row["outputs"][0]})
                require_equal(row["outputs"][0], row["outputs"][1], f"FF bridge config={config_index} block={block_index}")
                require_equal(row["outputs"][2], row["outputs"][3], f"ring bridge config={config_index} block={block_index}")
                bridges += 2
                update_record_hash(bridge_hash, {"storage": "ff", "config": config_index, "block": block_id, "output": row["outputs"][0]})
                update_record_hash(bridge_hash, {"storage": "ring", "config": config_index, "block": block_id, "output": row["outputs"][2]})

    expected_counts = {item["id"]: item["expected_outputs"] for item in PREREG_DATA["variants"]}
    actual_counts = {variant: variant_counts[variant] for variant in EXPECTED_VARIANT_IDS}
    require_equal(actual_counts, expected_counts, "variant output counts")
    require_equal(model_comparisons, EXPECTED_MODEL_COMPARISONS, "model comparisons")
    require_equal(storage_comparisons, EXPECTED_STORAGE_COMPARISONS, "storage comparisons")
    require_equal(bridges, EXPECTED_BRIDGES, "bridge comparisons")

    input_digests = {}
    for variant in EXPECTED_VARIANT_IDS:
        expected_set = {
            (config_index, block_index)
            for config_index, configuration in enumerate(configurations)
            if variant.endswith("sequence") or configuration["d"] == 0
            for block_index in range(BLOCK_COUNT)
        }
        require_equal(input_sets[variant], expected_set, f"{variant} exact input set")
        input_digests[variant] = sha256_bytes(
            canonical_json_bytes([list(item) for item in sorted(expected_set)])
        )

    functional = {
        "expected_rows": EXPECTED_ROWS,
        "executed_rows": len(rows),
        "expected_outputs_by_variant": expected_counts,
        "executed_outputs_by_variant": actual_counts,
        "expected_rtl_model_comparisons": EXPECTED_MODEL_COMPARISONS,
        "executed_rtl_model_comparisons": model_comparisons,
        "model_mismatches": 0,
        "expected_storage_comparisons": EXPECTED_STORAGE_COMPARISONS,
        "executed_storage_comparisons": storage_comparisons,
        "storage_mismatches": 0,
        "expected_repeated_sequence_bridges": EXPECTED_BRIDGES,
        "executed_repeated_sequence_bridges": bridges,
        "bridge_mismatches": 0,
        "variant_input_set_sha256": input_digests,
        "model_aggregate_sha256": model_hash.hexdigest(),
        "storage_aggregate_sha256": storage_hash.hexdigest(),
        "bridge_aggregate_sha256": bridge_hash.hexdigest(),
        "aggregate_encoding": AGGREGATE_ENCODING,
        "exact_execution_sets": True,
        "all_byte_exact": True,
    }
    cycle = {
        "expected_observations": EXPECTED_MODEL_COMPARISONS,
        "executed_observations": sum(actual_counts.values()),
        "per_input_ready_window_checked": True,
        "variant_input_sets_exact": True,
        "variants": {
            variant: {
                "latency_cycles": 12,
                "latency_set": sorted(latency_sets[variant]),
                "initiation_interval_cycles": 13,
                "initiation_interval_set": sorted(interval_sets[variant]),
                "observation_count": actual_counts[variant],
                "input_set_sha256": input_digests[variant],
                "input_independent": sorted(latency_sets[variant]) == [12]
                and sorted(interval_sets[variant]) == [13],
            }
            for variant in EXPECTED_VARIANT_IDS
        },
        "all_exact": True,
        "timing_or_fmax_claim": False,
    }
    require_true(all(item["input_independent"] for item in cycle["variants"].values()), "cycle singleton sets")
    require_equal(cycle["executed_observations"], EXPECTED_MODEL_COMPARISONS, "cycle observation total")
    return functional, cycle


def parser_controls(lines: Sequence[str], configurations: Sequence[Mapping]) -> Tuple[dict, dict]:
    d1_line = 384 * 3 * BLOCK_COUNT
    require_true(d1_line < len(lines), "no d=1 parser-control row")
    extra = list(lines)
    parts = extra[d1_line].split(" ")
    # Inject both repeated outputs and their cycle evidence in an otherwise
    # valid d=1 row; the ordinary parser must reject rather than ignore them.
    parts[7] = parts[8]
    parts[9] = parts[10]
    parts[11] = "12"
    parts[13] = "12"
    parts[15] = "13"
    parts[17] = "13"
    extra[d1_line] = " ".join(parts)
    extra_error = None
    try:
        parse_main_result_lines(extra, configurations)
    except GateError as error:
        extra_error = str(error)
    require_true(extra_error is not None, "extra repeated output escaped parser")

    missing = list(lines)
    missing_parts = missing[0].split(" ")
    missing_parts[12] = "-"  # ff_sequence latency evidence
    missing[0] = " ".join(missing_parts)
    missing_error = None
    try:
        parse_main_result_lines(missing, configurations)
    except GateError as error:
        missing_error = str(error)
    require_true(missing_error is not None, "missing cycle evidence escaped parser")
    return (
        {
            "mutated_line": d1_line + 1,
            "shared_parser_rejection": extra_error,
            "detected": True,
        },
        {
            "mutated_line": 1,
            "shared_parser_rejection": missing_error,
            "detected": True,
        },
    )


def write_control_vectors(
    configurations: Sequence[Mapping],
    blocks: Sequence[Tuple[str, bytes]],
    reverse_mask_bytes: bool,
) -> List[List[List[int]]]:
    transformed_keys = []
    for configuration in configurations:
        keys = [[int(value) for value in word] for word in configuration["keys"]]
        if reverse_mask_bytes:
            keys = [list(reversed(word)) for word in keys]
        transformed_keys.append(keys)
    write_hex_lines(
        SCRATCH / "control-masks.hex",
        [state_to_verilog_hex(word) for keys in transformed_keys for word in keys],
        r"[0-9a-f]{64}",
        "control masks",
    )
    write_hex_lines(
        SCRATCH / "control-h4-sequences.hex",
        [item["sequence_hex"] for item in configurations],
        r"[0-9a-f]{36}",
        "control sequences",
    )
    write_hex_lines(
        SCRATCH / "control-live-h4-sequences.hex",
        [item["live_sequence_hex"] for item in configurations],
        r"[0-9a-f]{36}",
        "control live sequences",
    )
    write_hex_lines(
        SCRATCH / "blocks.hex",
        [state_to_verilog_hex(block) for _identifier, block in blocks],
        r"[0-9a-f]{64}",
        "control blocks",
    )
    return transformed_keys


def parse_control_results(
    path: Path,
    mutation: int,
    storage: int,
    sequence_mode: int,
    configurations: Sequence[Mapping],
) -> Dict[Tuple[int, int], dict]:
    require_true(path.is_file(), "control results absent")
    lines = path.read_text(encoding="utf-8").splitlines()
    require_equal(len(lines), len(configurations) * BLOCK_COUNT, "control row count")
    rows = {}
    for line_index, line in enumerate(lines):
        parts = line.split(" ")
        require_true(all(parts), f"control whitespace line {line_index+1}")
        require_equal(len(parts), 10, f"control tokens line {line_index+1}")
        require_equal(parts[0], "control", f"control tag line {line_index+1}")
        require_equal(strict_decimal(parts[1], "control mutation"), mutation, "control mutation")
        require_equal(strict_decimal(parts[2], "control storage"), storage, "control storage")
        require_equal(strict_decimal(parts[3], "control mode"), sequence_mode, "control mode")
        config_index = strict_decimal(parts[4], "control config")
        block_index = strict_decimal(parts[5], "control block")
        require_equal((config_index, block_index), (line_index // BLOCK_COUNT, line_index % BLOCK_COUNT), "control row order")
        configuration = configurations[config_index]
        require_equal(parts[6], configuration["sequence_hex"], "control committed sequence")
        require_equal(parts[7], configuration["live_sequence_hex"], "control live sequence")
        require_true(re.fullmatch(r"[0-9a-f]{64}", parts[8]) is not None, "control output grammar")
        require_equal(strict_decimal(parts[9], "control latency"), 12, "control latency")
        key = (config_index, block_index)
        require_true(key not in rows, "duplicate control row")
        rows[key] = {"output": parts[8], "latency": 12}
    return rows


def selector_mutation_sequence(control_id: str, configuration: Mapping) -> List[List[int]]:
    sequence = [list(item) for item in configuration["sequence"]]
    if control_id == "reverse_sequence_order":
        return list(reversed(sequence))
    if control_id == "hold_w0":
        return [list(sequence[0]) for _ in range(ROUNDS)]
    if control_id == "selector_index_plus_one":
        return [list(sequence[(index + 1) % ROUNDS]) for index in range(ROUNDS)]
    if control_id == "post_commit_pin_change":
        return [list(item) for item in configuration["live_sequence"]]
    return sequence


def mutated_control_output(
    control_id: str,
    block: Sequence[int],
    block_index: int,
    configuration: Mapping,
    transformed_keys: Sequence[Sequence[int]],
) -> List[int]:
    sequence = selector_mutation_sequence(control_id, configuration)
    keys = configuration["keys"]
    direction = -1 if control_id == "wrong_h4_shift_direction" else 1
    if control_id == "wrong_round_key_address":
        return canonical_permute(block, [keys[0]] + list(keys[:ROUNDS]), sequence)
    if control_id == "reverse_mask_word_bytes":
        return canonical_permute(block, transformed_keys, sequence)
    if control_id == "broken_ring_rotation":
        start_index = (-block_index) % MASK_WORDS
        rotated_keys = [keys[start_index]] + [
            keys[(start_index + round_index) % MASK_WORDS]
            for round_index in range(ROUNDS)
        ]
        return canonical_permute(block, rotated_keys, sequence)
    return canonical_permute(block, keys, sequence, direction)


def run_rtl_control(
    control_id: str,
    mutation: int,
    storage: int,
    sequence_mode: int,
    configurations: Sequence[Mapping],
    blocks: Sequence[Tuple[str, bytes]],
    reverse_mask_bytes: bool = False,
) -> dict:
    transformed = write_control_vectors(configurations, blocks, reverse_mask_bytes)
    binary = SCRATCH / ("control-" + control_id + ".vvp")
    compile_iverilog(
        "e256h_h4_sequence_control_tb",
        binary,
        {
            "STORAGE": storage,
            "SEQUENCE_MODE": sequence_mode,
            "MUTATION": mutation,
            "CONFIG_COUNT": len(configurations),
        },
        control_id,
    )
    output = run_process(["vvp", str(binary)], SIM_TIMEOUT_SECONDS, control_id + " simulation")
    sentinel = "E256H_H4_SEQUENCE_CONTROL_TB_DONE"
    require_equal(output.count(sentinel), 1, control_id + " sentinel")
    rows = parse_control_results(
        SCRATCH / "control-results.txt", mutation, storage, sequence_mode, configurations
    )
    mismatch_count = 0
    first = None
    aggregate = hashlib.sha256()
    for config_index, configuration in enumerate(configurations):
        for block_index, (block_id, block) in enumerate(blocks):
            observed = rows[(config_index, block_index)]["output"]
            correct = state_hex(
                canonical_permute(block, configuration["keys"], configuration["sequence"])
            )
            mutated = state_hex(
                mutated_control_output(
                    control_id,
                    block,
                    block_index,
                    configuration,
                    transformed[config_index],
                )
            )
            require_equal(observed, mutated, f"{control_id} planted model config={config_index} block={block_index}")
            if observed != correct:
                mismatch_count += 1
                if first is None:
                    first = {
                        "config": config_index,
                        "a": configuration["a"],
                        "d": configuration["d"],
                        "material": configuration["material_id"],
                        "block": block_id,
                        "correct": correct,
                        "mutated": observed,
                    }
            update_record_hash(
                aggregate,
                {
                    "control": control_id,
                    "config": config_index,
                    "block": block_id,
                    "correct": correct,
                    "mutated": observed,
                },
            )
    require_true(mismatch_count > 0, control_id + " produced no mismatch witness")
    return {
        "mutation_code": mutation,
        "storage_code": storage,
        "sequence_mode": bool(sequence_mode),
        "configuration_count": len(configurations),
        "executed_rows": len(rows),
        "planted_model_matches": len(rows),
        "correct_model_mismatches": mismatch_count,
        "first_mismatch_witness": first,
        "aggregate_sha256": aggregate.hexdigest(),
        "completion_sentinel_count": 1,
        "detected": True,
    }


def run_rtl_controls(
    configurations: Sequence[Mapping],
    blocks: Sequence[Tuple[str, bytes]],
    protocol_evidence: Mapping,
) -> Dict[str, dict]:
    switching = next(
        item for item in configurations
        if item["d"] == 1 and item["a"] == 0 and item["material_index"] == 0
    )
    singleton = [switching]
    records = {
        "reverse_sequence_order": run_rtl_control("reverse_sequence_order", 1, 0, 1, singleton, blocks),
        "hold_w0": run_rtl_control("hold_w0", 2, 0, 1, singleton, blocks),
        "selector_index_plus_one": run_rtl_control("selector_index_plus_one", 3, 0, 1, singleton, blocks),
        "wrong_h4_shift_direction": run_rtl_control("wrong_h4_shift_direction", 4, 0, 1, singleton, blocks),
        "wrong_round_key_address": run_rtl_control("wrong_round_key_address", 5, 0, 1, singleton, blocks),
        "reverse_mask_word_bytes": run_rtl_control("reverse_mask_word_bytes", 8, 0, 1, singleton, blocks, True),
        "broken_ring_rotation": run_rtl_control("broken_ring_rotation", 6, 1, 1, singleton, blocks),
        "post_commit_pin_change": run_rtl_control("post_commit_pin_change", 7, 0, 1, singleton, blocks),
        "incomplete_configuration": {
            "evidence": dict(protocol_evidence),
            "required_observations": {
                "cfg_error_asserted": True,
                "key_valid_false": True,
                "no_busy": True,
                "no_done": True,
            },
            "detected": True,
        },
    }
    return records


# ---------------------------------------------------------------------------
# Yosys hierarchy, state-boundary accounting, mapped artifacts, and controls.


def yosys_source_list() -> str:
    return " ".join(str(path.relative_to(REPO)) for path in (H2_RTL, RTL))


def run_yosys(script: str, label: str) -> str:
    return run_process(["yosys", "-Q", "-p", script], SYNTH_TIMEOUT_SECONDS, label)


def strict_yosys_json(path: Path, h2_helpers, label: str) -> dict:
    data = strict_json_load(path)
    validate_deterministic_types(data, label)
    require_true(isinstance(data, dict), label + " is not an object")
    return data


def validate_flatten_evidence(
    mapped_metrics: Mapping[str, int],
    flat_metrics: Mapping[str, int],
    mapped_signatures: Counter,
    flat_signatures: Counter,
    mapped_types: Counter,
    flat_types: Counter,
    flat_child_count: int,
    depth_result_count: int,
    loop_free: bool,
) -> None:
    require_equal(flat_metrics, mapped_metrics, "mapped/flat primitive metrics")
    require_equal(flat_signatures, mapped_signatures, "mapped/flat primitive signatures")
    require_equal(flat_types, mapped_types, "mapped/flat primitive types")
    require_equal(flat_child_count, 0, "flat hierarchy child count")
    require_equal(depth_result_count, 1, "depth result count")
    require_true(loop_free, "flattened graph has a combinational loop")


def parse_depth(output: str, top: str) -> Tuple[int, int, bool]:
    loop_free = re.search(
        r"(?i)(found[^\n]*loop|logic loop|combinational loop|loop detected)", output
    ) is None
    matches = re.findall(r"Longest topological path in\s+[^\n]*?\(length=(\d+)\)", output)
    require_equal(len(matches), 1, f"{top} depth result count")
    return int(matches[0]), len(matches), loop_free


def boundary_accounting(
    analysis: Mapping,
    top: str,
    storage_id: str,
    selector_bits: int,
    h2_helpers,
) -> dict:
    core_module = h2_helpers.find_reachable_module(
        analysis, f"e256h_h4_{storage_id}_core", top + " core"
    )
    store_module = h2_helpers.find_reachable_module(
        analysis, f"e256h_h2_{storage_id}_store", top + " store"
    )
    protocol_module = h2_helpers.find_reachable_module(
        analysis, "e256h_h2_protocol", top + " protocol"
    )
    core_bits = analysis["local"][core_module]["metrics"]["generic_sequential_bits"]
    store_bits = analysis["local"][store_module]["metrics"]["generic_sequential_bits"]
    protocol_bits = analysis["local"][protocol_module]["metrics"]["generic_sequential_bits"]
    require_equal(store_bits, MASK_BITS, top + " mask-state bits")
    require_equal(protocol_bits, 7, top + " protocol bits")
    require_equal(core_bits, 518 + selector_bits, top + " core/selector bits")
    require_equal(analysis["recursive_metrics"]["generic_memory_bits"], 0, top + " memory bits")
    total_expected = MASK_BITS + 7 + 518 + selector_bits
    require_equal(
        analysis["recursive_metrics"]["generic_sequential_bits"],
        total_expected,
        top + " total sequential bits",
    )
    ports = analysis["modules"][top]["ports"]
    require_true("mask_words" not in ports, top + " externalizes mask state")
    require_equal(len(ports["cfg_h4_sequence"]["bits"]), 144, top + " sequence port width")
    return {
        "mask_state_bits": store_bits,
        "selector_state_bits": selector_bits,
        "datapath_and_control_state_bits": 518,
        "protocol_state_bits": protocol_bits,
        "total_sequential_bits": total_expected,
        "mask_store_module": store_module,
        "core_module": core_module,
        "wide_live_mask_port": False,
        "committed_selector_boundary_present": True,
        "complete": True,
    }


def synthesize_top(variant: Mapping, h2_helpers) -> dict:
    top = variant["top"]
    prefix = SCRATCH / top
    premap_path = prefix.with_name(prefix.name + "-premap.json")
    mapped_path = prefix.with_name(prefix.name + "-mapped.json")
    flat_path = prefix.with_name(prefix.name + "-flat.json")
    mapped_verilog = prefix.with_name(prefix.name + "-mapped.v")
    sources = yosys_source_list()
    premap_script = (
        f"read_verilog {sources}; hierarchy -check -top {top}; proc; "
        f"memory -nomap; opt; check -assert; write_json {premap_path.relative_to(REPO)}; stat"
    )
    mapped_script = (
        f"read_verilog {sources}; hierarchy -check -top {top}; proc; "
        "memory -nomap; opt; techmap; opt; dffunmap; zinit -all; "
        f"abc -lut 6; opt_clean; check -assert; write_json {mapped_path.relative_to(REPO)}; "
        f"write_verilog -noattr {mapped_verilog.relative_to(REPO)}; stat"
    )
    flat_script = (
        f"read_json {mapped_path.relative_to(REPO)}; hierarchy -check -top {top}; "
        f"flatten; write_json {flat_path.relative_to(REPO)}; check -assert; ltp -noff"
    )
    require_true("flatten" not in premap_script and "flatten" not in mapped_script, top + " premature flatten")
    run_yosys(premap_script, top + " pre-map synthesis")
    run_yosys(mapped_script, top + " mapped synthesis")
    depth_output = run_yosys(flat_script, top + " flat depth")
    require_true(mapped_verilog.is_file(), top + " mapped Verilog absent")

    premap_data = strict_yosys_json(premap_path, h2_helpers, top + " premap")
    mapped_data = strict_yosys_json(mapped_path, h2_helpers, top + " mapped")
    flat_data = strict_yosys_json(flat_path, h2_helpers, top + " flat")
    h2_helpers.validate_top_ports(premap_data, top, TOP_PORTS)
    h2_helpers.validate_top_ports(mapped_data, top, TOP_PORTS)
    premap = h2_helpers.analyze_yosys_graph(premap_data, top, top + " premap")
    mapped = h2_helpers.analyze_yosys_graph(mapped_data, top, top + " mapped")
    flat = h2_helpers.analyze_yosys_graph(flat_data, top, top + " flat")
    selector_bits = variant["selector_state_bits"]
    boundary = boundary_accounting(premap, top, variant["storage_id"], selector_bits, h2_helpers)
    require_equal(mapped["recursive_metrics"]["generic_sequential_bits"], boundary["total_sequential_bits"], top + " mapped sequential bits")
    depth, depth_count, loop_free = parse_depth(depth_output, top)
    validate_flatten_evidence(
        mapped["recursive_metrics"], flat["recursive_metrics"],
        mapped["recursive_signatures"], flat["recursive_signatures"],
        mapped["recursive_types"], flat["recursive_types"],
        len(flat["local"][top]["children"]), depth_count, loop_free,
    )
    metrics = dict(mapped["recursive_metrics"])
    metrics["generic_combinational_levels"] = depth
    artifacts = {
        "pre_map_hierarchy_json": {"path": str(premap_path.relative_to(REPO)), "sha256": sha256_file(premap_path)},
        "mapped_hierarchy_json": {"path": str(mapped_path.relative_to(REPO)), "sha256": sha256_file(mapped_path)},
        "analysis_only_flattened_json": {"path": str(flat_path.relative_to(REPO)), "sha256": sha256_file(flat_path)},
        "mapped_verilog": {"path": str(mapped_verilog.relative_to(REPO)), "sha256": sha256_file(mapped_verilog)},
    }
    return {
        "top": top,
        "storage_id": variant["storage_id"],
        "selector_mode": variant["selector_mode"],
        "h1_eligible": variant["h1_eligible"],
        "artifacts": artifacts,
        "pre_map_hierarchy": premap["public"],
        "mapped_hierarchy": mapped["public"],
        "flat_hierarchy": flat["public"],
        "state_accounting": boundary,
        "metrics": metrics,
        "flatten_preservation": {
            "primitive_metrics_identical": True,
            "primitive_signature_multiset_identical": True,
            "primitive_type_multiset_identical": True,
            "flat_child_cells": 0,
            "depth_result_count": depth_count,
            "loop_free": loop_free,
            "combinational_levels": depth,
        },
        "scripts": {
            "pre_map": premap_script,
            "mapped": mapped_script,
            "analysis_only_flatten": flat_script,
        },
        "_analysis": {"premap": premap, "mapped": mapped, "flat": flat},
    }


def synthesize_premap_control(top: str, h2_helpers) -> dict:
    path = SCRATCH / (top + "-control-premap.json")
    script = (
        f"read_verilog {yosys_source_list()}; hierarchy -check -top {top}; proc; "
        f"memory -nomap; opt; check -assert; write_json {path.relative_to(REPO)}; stat"
    )
    run_yosys(script, top + " accounting control")
    data = strict_yosys_json(path, h2_helpers, top + " control premap")
    analysis = h2_helpers.analyze_yosys_graph(data, top, top + " control premap")
    return {"path": path, "data": data, "analysis": analysis, "script": script}


def externalized_controls(h2_helpers) -> Tuple[dict, dict]:
    sequence_top = "e256h_h4_externalized_sequence_control"
    sequence_result = synthesize_premap_control(sequence_top, h2_helpers)
    h2_helpers.validate_top_ports(sequence_result["data"], sequence_top, TOP_PORTS)
    sequence_error = None
    try:
        boundary_accounting(
            sequence_result["analysis"], sequence_top, "ff", 144, h2_helpers
        )
    except Exception as error:
        sequence_error = str(error)
    require_true(sequence_error is not None, "externalized sequence state passed accounting")

    mask_top = "e256h_h4_externalized_mask_control"
    mask_result = synthesize_premap_control(mask_top, h2_helpers)
    mask_ports = mask_result["data"]["modules"][mask_top]["ports"]
    require_equal(len(mask_ports["mask_words"]["bits"]), MASK_BITS, "external mask port")
    mask_error = None
    try:
        boundary_accounting(mask_result["analysis"], mask_top, "ff", 144, h2_helpers)
    except Exception as error:
        mask_error = str(error)
    require_true(mask_error is not None, "externalized mask state passed accounting")
    return (
        {
            "top": sequence_top,
            "live_sequence_input_bits": 144,
            "shared_boundary_validator_rejection": sequence_error,
            "accepted_as_graded_variant": False,
            "detected": True,
        },
        {
            "top": mask_top,
            "live_mask_input_bits": MASK_BITS,
            "shared_boundary_validator_rejection": mask_error,
            "accepted_as_graded_variant": False,
            "detected": True,
        },
    )


def postmap_depth_control(variant_result: Mapping) -> dict:
    analysis = variant_result["_analysis"]
    mapped = analysis["mapped"]
    flat = analysis["flat"]
    corrupted = dict(flat["recursive_metrics"])
    corrupted["generic_primitive_cells"] += 1
    rejection = None
    try:
        validate_flatten_evidence(
            mapped["recursive_metrics"], corrupted,
            mapped["recursive_signatures"], flat["recursive_signatures"],
            mapped["recursive_types"], flat["recursive_types"],
            len(flat["local"][variant_result["top"]]["children"]), 1, True,
        )
    except GateError as error:
        rejection = str(error)
    require_true(rejection is not None, "post-map corruption escaped validator")
    return {
        "variant": variant_result["top"],
        "mutation": "increment flattened primitive-cell count by one",
        "shared_flatten_validator_rejection": rejection,
        "detected": True,
    }


def run_synthesis(prereg: Mapping, h2_helpers) -> Tuple[dict, dict, Dict[str, dict]]:
    internal_results = {}
    public_variants = {}
    for variant in prereg["variants"]:
        result = synthesize_top(variant, h2_helpers)
        internal_results[variant["id"]] = result
        public = {key: value for key, value in result.items() if key != "_analysis"}
        public_variants[variant["id"]] = public

    paired = {}
    for storage_id in ("ff", "ring"):
        repeated = public_variants[storage_id + "_repeated"]["metrics"]
        sequence = public_variants[storage_id + "_sequence"]["metrics"]
        delta = {
            "generic_lut6": sequence["generic_abc_lut6"] - repeated["generic_abc_lut6"],
            "sequential_bits": sequence["generic_sequential_bits"] - repeated["generic_sequential_bits"],
            "primitive_cells": sequence["generic_primitive_cells"] - repeated["generic_primitive_cells"],
            "combinational_levels": sequence["generic_combinational_levels"] - repeated["generic_combinational_levels"],
        }
        require_equal(delta["sequential_bits"], 132, storage_id + " selector-state delta")
        paired[storage_id] = {
            "comparison": "sequence minus repeated",
            "repeated_top": public_variants[storage_id + "_repeated"]["top"],
            "sequence_top": public_variants[storage_id + "_sequence"]["top"],
            "delta": delta,
            "winner_selected": False,
            "threshold_applied": False,
        }

    external_sequence, external_mask = externalized_controls(h2_helpers)
    synthesis = {
        "logic_basis": prereg["synthesis_contract"]["logic_basis"],
        "tops_synthesized_independently": True,
        "required_artifacts_per_top": list(prereg["synthesis_contract"]["required_artifacts_per_top"]),
        "variants": public_variants,
        "recursive_child_multiplicity_closed": True,
        "independent_flat_primitive_multisets_closed": True,
        "analysis_only_flatten_preserved": True,
        "all_depths_loop_free": True,
        "externalized_controls": {
            "sequence": external_sequence,
            "mask": external_mask,
        },
        "generic_only_no_vendor_physical_claim": True,
    }
    return synthesis, paired, internal_results


# ---------------------------------------------------------------------------
# Control assembly, deterministic record, full build, and self-test.


def assemble_controls(
    corpus_control: Mapping,
    rtl_controls: Mapping[str, dict],
    collapse_control: Mapping,
    terminal_control: Mapping,
    synthesis: Mapping,
    nested_control: Mapping,
    duplicate_control: Mapping,
    depth_control: Mapping,
    extra_control: Mapping,
    missing_control: Mapping,
) -> dict:
    records = {
        "corpus_digest_perturbation": dict(corpus_control),
        "reverse_sequence_order": rtl_controls["reverse_sequence_order"],
        "hold_w0": rtl_controls["hold_w0"],
        "selector_index_plus_one": rtl_controls["selector_index_plus_one"],
        "wrong_h4_shift_direction": rtl_controls["wrong_h4_shift_direction"],
        "wrong_collapse_transport": dict(collapse_control),
        "terminal_a12": dict(terminal_control),
        "wrong_round_key_address": rtl_controls["wrong_round_key_address"],
        "reverse_mask_word_bytes": rtl_controls["reverse_mask_word_bytes"],
        "broken_ring_rotation": rtl_controls["broken_ring_rotation"],
        "incomplete_configuration": rtl_controls["incomplete_configuration"],
        "post_commit_pin_change": rtl_controls["post_commit_pin_change"],
        "externalized_sequence_state": synthesis["externalized_controls"]["sequence"],
        "externalized_mask_state": synthesis["externalized_controls"]["mask"],
        "nested_child_multiplicity": dict(nested_control),
        "duplicate_child_accounting": dict(duplicate_control),
        "postmap_depth_preservation": dict(depth_control),
        "extra_repeated_output": dict(extra_control),
        "missing_cycle_observation": dict(missing_control),
    }
    require_equal(tuple(records), EXPECTED_CONTROL_IDS, "assembled control order")
    require_true(all(record.get("detected") is True for record in records.values()), "one or more controls undetected")
    return {
        "frozen_ids": list(EXPECTED_CONTROL_IDS),
        "executed_ids": list(records),
        "records": records,
        "all_detected": True,
    }


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
    digest = sha256_bytes(canonical_json_bytes(record, deterministic=False))
    record["record_sha256"] = digest
    return record


def validate_record(record: Mapping) -> None:
    require_exact_keys(record, EXPECTED_OUTER_KEYS, "outer record")
    payload = record["deterministic_payload"]
    require_exact_keys(payload, EXPECTED_PAYLOAD_KEYS, "deterministic payload")
    validate_deterministic_types(payload)
    require_equal(payload["schema"], "E256-HARDWARE-H4-SEQUENCE-GATE-1", "stored schema")
    require_equal(payload["status"], "OPEN_PROGRESS", "stored status")
    payload_digest = sha256_bytes(canonical_json_bytes(payload))
    require_equal(record["deterministic_payload_sha256"], payload_digest, "stored payload digest")
    require_true(re.fullmatch(r"[0-9a-f]{64}", record["record_sha256"]) is not None, "record hash grammar")
    unhashed = dict(record)
    stored_record_hash = unhashed["record_sha256"]
    unhashed["record_sha256"] = None
    require_equal(
        sha256_bytes(canonical_json_bytes(unhashed, deterministic=False)),
        stored_record_hash,
        "stored record hash",
    )
    require_equal(record["no_wall_clock"], NO_WALL_CLOCK, "no-wall-clock text")


def build_record() -> dict:
    started = time.perf_counter()
    integrity, prereg, h2_helpers, certified, _predecessors = validate_integrity()
    global PREREG_DATA
    PREREG_DATA = prereg
    materials = derive_materials()
    blocks = derive_blocks()
    corpora, executable = build_corpora(certified, materials, blocks)
    corpus_control = corpus_digest_perturbation_control()
    structural = run_structural_census(certified)
    collapse = run_collapse_equivalence(executable, certified, materials, blocks)
    configurations = build_configurations(certified, executable, materials)

    prepare_scratch()
    write_main_vectors(configurations, blocks)
    rows, raw_lines, protocol_evidence = run_main_simulation(configurations, blocks)
    functional, cycle = grade_functional(rows, configurations, blocks)
    cycle["protocol_evidence"] = protocol_evidence
    extra_control, missing_control = parser_controls(raw_lines, configurations)
    rtl_controls = run_rtl_controls(configurations, blocks, protocol_evidence)

    switching_configuration = next(
        item for item in configurations
        if item["d"] == 1 and item["a"] == 0 and item["material_index"] == 0
    )
    collapse_control = wrong_collapse_transport_control(
        switching_configuration, materials[0], blocks[0][0], blocks[0][1]
    )
    terminal_control = terminal_a12_control(materials[0], switching_configuration["sequence"])

    synthesis, paired, internal_synthesis = run_synthesis(prereg, h2_helpers)
    nested_control, duplicate_control = h2_helpers.synthetic_hierarchy_controls()
    depth_control = postmap_depth_control(internal_synthesis["ff_sequence"])
    controls = assemble_controls(
        corpus_control,
        rtl_controls,
        collapse_control,
        terminal_control,
        synthesis,
        nested_control,
        duplicate_control,
        depth_control,
        extra_control,
        missing_control,
    )

    validity = {
        "frozen_integrity_exact": integrity["all_exact"],
        "corpora_exact": corpora["all_exact"],
        "collapse_exact": collapse["all_byte_exact"],
        "functional_exact": functional["all_byte_exact"] and functional["exact_execution_sets"],
        "cycle_evidence_exact": cycle["all_exact"],
        "all_nineteen_controls_detected": controls["all_detected"],
        "synthesis_accounting_closed": synthesis["recursive_child_multiplicity_closed"]
        and synthesis["independent_flat_primitive_multisets_closed"]
        and synthesis["analysis_only_flatten_preserved"]
        and synthesis["all_depths_loop_free"],
        "paired_measurements_complete": set(paired) == {"ff", "ring"},
    }
    require_true(all(validity.values()), "H4 sequence harness validity failure")
    predictions = {
        "H4SP1": {
            "role": "validity_control",
            "statement": prereg["predictions"][0]["statement"],
            "pass": True,
        },
        "H4SP2": {
            "role": "graded_finding",
            "statement": prereg["predictions"][1]["statement"],
            "observed_failure_count": structural["failure_count"],
            "structural_verdict": structural["verdict"],
            "pass": True,
        },
        "H4SP3": {
            "role": "graded_finding",
            "statement": prereg["predictions"][2]["statement"],
            "observed": paired,
            "pass": True,
        },
    }
    require_equal(tuple(predictions), EXPECTED_PREDICTION_IDS, "prediction order")

    payload = {
        "schema": "E256-HARDWARE-H4-SEQUENCE-GATE-1",
        "status": "OPEN_PROGRESS",
        "integrity": integrity,
        "corpora": corpora,
        "structural_census": structural,
        "collapse_equivalence": collapse,
        "functional_equivalence": functional,
        "cycle_evidence": cycle,
        "controls": controls,
        "synthesis": synthesis,
        "paired_measurements": paired,
        "verdicts": {
            "harness_validity": validity,
            "harness_valid": True,
            "structural": structural["verdict"],
            "executable_semantics": "EXECUTABLE_SEQUENCE_SEMANTICS_BYTE_EXACT",
            "collapse": "SEQUENCE_H3_COLLAPSE_BYTE_EXACT",
            "mapped_costs": "PAIRED_GENERIC_MAPPED_DELTAS_RECORDED_NO_WINNER",
            "predictions": predictions,
            "claim_movement": False,
            "production_h4_policy_selected": False,
            "architecture_selected": False,
        },
        "non_claims": list(prereg["non_claims"]),
    }
    require_equal(tuple(payload), EXPECTED_PAYLOAD_KEYS, "payload key order")
    validate_deterministic_types(payload)
    payload_digest = sha256_bytes(canonical_json_bytes(payload))
    record_without_hash = {
        "deterministic_payload": payload,
        "deterministic_payload_sha256": payload_digest,
        "environment_advisory_excluded_from_digest": advisory(started),
        "no_wall_clock": NO_WALL_CLOCK,
    }
    record = add_record_hash(record_without_hash)
    # add_record_hash appends record_sha256; normalize to frozen outer order.
    record = {
        "deterministic_payload": record["deterministic_payload"],
        "deterministic_payload_sha256": record["deterministic_payload_sha256"],
        "record_sha256": record["record_sha256"],
        "environment_advisory_excluded_from_digest": record["environment_advisory_excluded_from_digest"],
        "no_wall_clock": record["no_wall_clock"],
    }
    # Recompute after key-order normalization; canonical JSON is order-independent,
    # but this makes the complete-record rule explicit.
    unhashed = dict(record)
    unhashed["record_sha256"] = None
    record["record_sha256"] = sha256_bytes(canonical_json_bytes(unhashed, deterministic=False))
    validate_record(record)
    return record


def run_self_test() -> None:
    integrity, prereg, _h2_helpers, certified, _predecessors = validate_integrity()
    global PREREG_DATA
    PREREG_DATA = prereg
    materials = derive_materials()
    blocks = derive_blocks()
    corpora, executable = build_corpora(certified, materials, blocks)
    configurations = build_configurations(certified, executable, materials)
    require_equal(integrity["all_exact"], True, "self-test integrity")
    require_equal(corpora["all_exact"], True, "self-test corpora")
    passed, detail = dependency_window(
        [certified[index] for index in executable[384]["indices"][:3]]
    )
    require_true(type(passed) is bool, "self-test dependency result")
    if passed:
        require_equal(detail, None, "self-test dependency detail")
    sample = configurations[384 * 3]
    raw = raw_prefixes(blocks[0][1], materials[0], sample["sequence"])
    stage_a = stage_a_prefixes(blocks[0][1], materials[0], sample["sequence"])
    stage_b = canonical_terminal_prefixes(
        blocks[0][1], materials[0], sample["sequence"], sample["keys"]
    )
    require_equal(raw, stage_a, "self-test Stage A")
    require_equal(raw, stage_b, "self-test Stage B")
    corpus_digest_perturbation_control()
    terminal_a12_control(materials[0], sample["sequence"])
    print("SELF-TEST PASS: identities, corpora, model, collapse, and pure controls")
    print("No receipt was emitted and no scratch directory was created.")


def atomic_write(path: Path, data: bytes) -> None:
    require_true(path.parent.is_dir(), f"receipt parent absent: {path.parent}")
    temporary = path.with_name(path.name + ".tmp")
    try:
        temporary.write_bytes(data)
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def check_prior(path: Path, current: Mapping) -> None:
    require_true(path.is_file(), f"prior receipt absent: {path.relative_to(REPO)}")
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
    print("=" * 78)
    print("E256-H H4 SWITCHING-SEQUENCE GATE  (OPEN_PROGRESS)")
    print("=" * 78)
    print(f"harness valid: {payload['verdicts']['harness_valid']}")
    print(
        "structural: "
        f"{payload['structural_census']['contiguous_three_round_windows']} windows, "
        f"{payload['structural_census']['failure_count']} failures"
    )
    print(
        "collapse: "
        f"{payload['collapse_equivalence']['total_comparisons']} comparisons, 0 mismatches"
    )
    print(
        "RTL/model: "
        f"{payload['functional_equivalence']['executed_rows']} rows, "
        f"{payload['functional_equivalence']['executed_rtl_model_comparisons']} comparisons"
    )
    print(f"controls: {len(payload['controls']['executed_ids'])}/19 detected")
    for storage_id, measurement in payload["paired_measurements"].items():
        print(f"{storage_id} sequence-minus-repeated: {measurement['delta']}")
    print(f"structural verdict: {payload['verdicts']['structural']}")
    print("NOTE: bounded generic research measurements; no H4 policy or architecture selected")
    print(f"deterministic_payload_sha256: {record['deterministic_payload_sha256']}")
    print(f"record_sha256: {record['record_sha256']}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Run or reproduce-check the frozen E256-H H4 sequence gate."
    )
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--self-test", action="store_true", help="bounded read-only implementation self-test; emits no receipt")
    parser.add_argument("--json", default=str(RECEIPT.relative_to(REPO)))
    args = parser.parse_args()
    output = REPO / args.json
    if args.check and args.self_test:
        print("H4 SEQUENCE GATE FAILED: --check and --self-test are mutually exclusive", file=sys.stderr)
        return 1
    try:
        if args.self_test:
            run_self_test()
            return 0
        record = build_record()
        print_summary(record)
        if args.check:
            check_prior(output, record)
            print("CHECK PASS")
            return 0
        atomic_write(
            output,
            json.dumps(record, indent=2, sort_keys=True, allow_nan=False).encode("utf-8") + b"\n",
        )
        print(f"wrote {output.relative_to(REPO)}")
        print(
            "STATUS: OPEN_PROGRESS; no C/H/N row, production H4 policy, architecture, "
            "schedule, round count, XOF, suite, protocol, security value, or production RTL moved"
        )
        return 0
    except Exception as error:
        print(f"H4 SEQUENCE GATE FAILED: {error}", file=sys.stderr)
        print("No canonical receipt was emitted or accepted; E256-063 remains OPEN.", file=sys.stderr)
        return 1


PREREG_DATA: Mapping = {}

if __name__ == "__main__":
    sys.exit(main())
