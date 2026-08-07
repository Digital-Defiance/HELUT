#!/usr/bin/env python3
"""Run the frozen E256-H H2 integrated-core cost gate.

This runner measures six fixed-R=12, non-production integrated cores after the
already-confirmed H3 XOR-offset collapse.  It validates the frozen ancestry,
derives every effective-mask configuration independently, checks RTL against an
independent byte model, grades all twelve controls, and accounts complete Yosys
hierarchies without flattening before or during mapping.

Contract:  directives/e256-hardware-h2-preregistration.json
Receipt:   logs/e256-hardware-h2-gate.json
RTL:       Hardware/RTL/Research/E256H/e256h_h2_integrated_core.v
Testbench: Hardware/Testbenches/Research/E256H/e256h_h2_integrated_core_tb.v

The measurements are generic Yosys/ABC artifacts.  They do not select a
production architecture, round count, schedule, H4 policy, memory, suite,
profile, fixture, protocol, security value, or implementation.
"""

from __future__ import annotations

import argparse
import hashlib
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
from typing import Any, Dict, Iterable, List, Mapping, MutableMapping, Optional, Sequence, Set, Tuple

REPO = Path(__file__).resolve().parent.parent
PREREG = REPO / "directives/e256-hardware-h2-preregistration.json"
ARCHITECTURE = REPO / "directives/e256-hardware-architecture.md"
ATTACK_RTL = REPO / "Hardware/RTL/Research/E256H/e256h_attack_core.v"
ATTACK_TESTBENCH = REPO / "Hardware/Testbenches/Research/E256H/e256h_attack_core_tb.v"
ATTACK_RUNNER = REPO / "Scripts/e256_hardware_attack_gate.py"
COLLAPSE_MITER = REPO / "Hardware/RTL/Research/E256H/e256h_offset_collapse_miter.v"
COLLAPSE_TESTBENCH = REPO / "Hardware/Testbenches/Research/E256H/e256h_offset_collapse_tb.v"
COLLAPSE_RUNNER = REPO / "Scripts/e256_hardware_offset_collapse_gate.py"
RTL = REPO / "Hardware/RTL/Research/E256H/e256h_h2_integrated_core.v"
TESTBENCH = REPO / "Hardware/Testbenches/Research/E256H/e256h_h2_integrated_core_tb.v"
RECEIPT = REPO / "logs/e256-hardware-h2-gate.json"
SCRATCH = REPO / "build/e256h-h2"

PREREG_SHA256 = "e3f785583fdf2cda3059e46a677d9e73711ab317ef1eeee3dcdf0c9e7e983a03"
BASE_ARCHITECTURE_SHA256 = "b64472f73be9d0fc6318ff445c5f550cb0129309313228f416599c27d3957bb1"
H2_ARCHITECTURE_SHA256 = "214aee439ddf715ebf3e5fc206c336119dd27f85da12ef65f8e590c0cb0bfceb"
CERTIFIED_H4_SET_SHA256 = "199f1f7bddccf19ce5aa0bde0987441735d628354140d53ebdfec538d7b3f5ed"
FROZEN_MATERIAL_SHA256 = "b6738e7f117bb7b916ee002db482f105a3eb5a046ee84dff45f178510cdeb691"
AES_SBOX_SHA256 = "c2d8e5eed6cbebd8625fc18f81486a7733c04f9b0129ffbe974c68b90308b4f2"
COLLAPSE_PREREG_SHA256 = "3d7a12731fcf81f6120577122c55bd8ec25589a82226d49fab7e5b8350ee0cee"

PREDECESSOR_CONTRACTS = (
    (
        "E256-062",
        "logs/e256-wide-state-gate.json",
        "E256-WIDE-STATE-GATE-1",
        "21758ce220b9da469a18ea617fa7b2fd41e906add69a258f830b12843e3e495b",
    ),
    (
        "E256-063-step-1",
        "logs/e256-hardware-cost-gate.json",
        "E256-HARDWARE-COST-GATE-1",
        "a10e001ad2c2b3de55fcc80197c059f166d5e55599c670e20b01de8f6b7d323d",
    ),
    (
        "E256-063-steps-2-3",
        "logs/e256-hardware-candidate-gate.json",
        "E256-HARDWARE-CANDIDATE-GATE-1",
        "98af83ec27093787552475fce588f84a902634afcc969bed26462032dddec3cc",
    ),
    (
        "E256-063-step-4",
        "logs/e256-hardware-attack-gate.json",
        "E256-HARDWARE-ATTACK-GATE-1",
        "1114e260455232a2979f8a4f613fc6d6daf4be4f97c3ca6903c3f639357d7a2d",
    ),
    (
        "E256-063-h3-collapse",
        "logs/e256-hardware-offset-collapse-gate.json",
        "E256-HARDWARE-OFFSET-COLLAPSE-GATE-1",
        "1478a0ba317bce5f33cb053744b050bb6188543405c1dfacf52d8aaf920c4b71",
    ),
)

FROZEN_SOURCE_CONTRACTS = {
    "attack_rtl": (
        ATTACK_RTL,
        "f4b5d6210275d831e48a3b16ca0457fa0927164ab33853b466ae0ca326fbcd3b",
    ),
    "attack_testbench": (
        ATTACK_TESTBENCH,
        "ae9d35af3edb76a696249dd4c32b8a3816c7a06643efbbf8f1397409a8b9ee2b",
    ),
    "attack_runner": (
        ATTACK_RUNNER,
        "6928516545363269fd3c36224ab0013779bb14068336493a068eeb4ce9d077c2",
    ),
    "collapse_miter": (
        COLLAPSE_MITER,
        "8b29ca93334536ad4ba6bfb8f602f73e2b7a37c5cd56dd958c25141f9261c082",
    ),
    "collapse_testbench": (
        COLLAPSE_TESTBENCH,
        "bcbc8e08c01fb3ff3da09db8a8e7aae9cbc6c461c7c5d318b0c7769811f109c0",
    ),
    "collapse_runner": (
        COLLAPSE_RUNNER,
        "5931ec48276c9402bee78382bc82366409e33fa78670246f0d967497d480cd80",
    ),
}

EXPECTED_VARIANT_IDS = (
    "ff_fixed",
    "ff_direct",
    "ring_fixed",
    "ring_direct",
    "mem_fixed",
    "mem_direct",
)
EXPECTED_TOPS = (
    "e256h_h2_ff_fixed",
    "e256h_h2_ff_direct",
    "e256h_h2_ring_fixed",
    "e256h_h2_ring_direct",
    "e256h_h2_mem_fixed",
    "e256h_h2_mem_direct",
)
EXPECTED_STORAGE_IDS = ("ff", "ring", "mem")
EXPECTED_H4_IDS = ("fixed", "direct")
EXPECTED_MATERIAL_IDS = ("frozen_attack_v1", "collapse_aux_0", "collapse_aux_1")
EXPECTED_MATERIAL_DOMAINS = (
    "E256-H/attack/material/v1",
    "E256-H/collapse/material/v1/0",
    "E256-H/collapse/material/v1/1",
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
EXPECTED_CONTROL_IDS = (
    "wrong_key_order",
    "wrong_round_key_address",
    "reverse_word_bytes",
    "wrong_h4_shift_direction",
    "ignore_h4_selector",
    "broken_ring_rotation",
    "stale_sync_memory_read",
    "incomplete_configuration",
    "externalized_storage",
    "nested_child_multiplicity",
    "duplicate_child_accounting",
    "postmap_depth_preservation",
)
EXPECTED_PREDICTION_IDS = tuple(f"H2P{index}" for index in range(1, 10))
EXPECTED_QUESTION_IDS = ("H2Q1", "H2Q2", "H2Q3", "H2Q4")
EXPECTED_GRADED_CONSTRAINTS = ("H0", "H1", "H2", "H3", "H4", "H5")
EXPECTED_PAYLOAD_KEYS = (
    "schema",
    "status",
    "inputs",
    "pinned_parameters",
    "coverage",
    "functional",
    "controls",
    "hierarchy_accounting",
    "storage_accounting",
    "measurements",
    "cycles",
    "predictions",
    "interpretation",
    "limitations",
)
OUTER_RECEIPT_KEYS = (
    "deterministic_payload",
    "deterministic_payload_sha256",
    "environment_advisory_excluded_from_digest",
    "no_wall_clock",
)
ADVISORY_KEYS = ("platform", "elapsed_seconds", "git_head", "git_dirty")
NO_WALL_CLOCK = (
    "No wall-clock timestamp is asserted; only deterministic inputs and outputs "
    "are graded."
)
VALID_VERDICT = "H2_INTEGRATED_COSTS_MEASURED_NO_ARCHITECTURE_SELECTED"
INVALID_STATUS = "INVALID_H2_COST_HARNESS; never emitted or accepted as the canonical receipt"

STATE_BYTES = 32
ROUNDS = 12
MATERIAL_BYTES = 1184
MATERIAL_MASK_BASE = 768
MASK_WORDS = 13
MASK_BITS = 3328
FIXED_H4 = (0, 1, 3, 4)
CONFIG_COUNT = 384 * 3
BLOCK_COUNT = 8
EXPECTED_RTL_ROWS = CONFIG_COUNT * BLOCK_COUNT
EXPECTED_FIXED_OUTPUTS_PER_VARIANT = 24
EXPECTED_DIRECT_OUTPUTS_PER_VARIANT = EXPECTED_RTL_ROWS
EXPECTED_TOTAL_MODEL_COMPARISONS = 27720
EXPECTED_STORAGE_COMPARISONS = 18480
EXPECTED_BRIDGE_COMPARISONS = 72
AGGREGATE_ENCODING = (
    "For each record in frozen nested-loop order, append a 4-byte unsigned "
    "big-endian length followed by compact canonical UTF-8 JSON; state outputs "
    "are ascending byte-index order encoded as 64 lowercase hex characters."
)
METRIC_KEYS = (
    "generic_abc_lut6",
    "generic_sequential_bits",
    "generic_memory_bits",
    "generic_primitive_cells",
)
TOP_PORTS = {
    "clk": ("input", 1),
    "rst": ("input", 1),
    "cfg_begin": ("input", 1),
    "cfg_valid": ("input", 1),
    "cfg_ready": ("output", 1),
    "cfg_word": ("input", 256),
    "cfg_commit": ("input", 1),
    "cfg_h4": ("input", 12),
    "key_valid": ("output", 1),
    "cfg_error": ("output", 1),
    "start": ("input", 1),
    "ready": ("output", 1),
    "block_i": ("input", 256),
    "block_o": ("output", 256),
    "busy": ("output", 1),
    "done": ("output", 1),
}
EXTERNAL_TOP = "e256h_h2_externalized_storage_control"
EXTERNAL_PORTS = {
    "clk": ("input", 1),
    "rst": ("input", 1),
    "start": ("input", 1),
    "block_i": ("input", 256),
    "mask_words": ("input", 3328),
    "ready": ("output", 1),
    "block_o": ("output", 256),
    "busy": ("output", 1),
    "done": ("output", 1),
}

STORAGE_SCRIPT_TEMPLATE = (
    "read_verilog <rtl_sources>; hierarchy -check -top <top>; proc; memory -nomap; "
    "opt; check -assert; write_json <storage_json>; stat"
)
MAPPED_SCRIPT_TEMPLATE = (
    "read_verilog <rtl_sources>; hierarchy -check -top <top>; proc; memory -nomap; "
    "opt; techmap; opt; dffunmap; zinit -all; abc -lut 6; opt_clean; "
    "check -assert; write_json <mapped_json>; stat"
)
DEPTH_SCRIPT_TEMPLATE = (
    "read_json <mapped_json>; hierarchy -check -top <top>; "
    "write_json <depth_before_json>; flatten; write_json <depth_after_json>; "
    "check -assert; ltp -noff"
)

SIM_TIMEOUT_SECONDS = 14400
SYNTH_TIMEOUT_SECONDS = 7200


class GateError(RuntimeError):
    """Frozen contract, structural, coverage, or validity failure."""


# ---------------------------------------------------------------------------
# Strict JSON, canonical values, and common guards.


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
        value = json.loads(
            path.read_text(encoding="utf-8"),
            object_pairs_hook=_unique_object,
            parse_constant=_reject_constant,
        )
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise GateError(f"could not strictly parse {path}: {error}") from error
    return value


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


def canonical_json_bytes(value) -> bytes:
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


def update_record_hash(hasher, record: Mapping) -> None:
    encoded = canonical_json_bytes(dict(record))
    require_true(len(encoded) < 2**32, "aggregate record exceeds four-byte length")
    hasher.update(len(encoded).to_bytes(4, "big"))
    hasher.update(encoded)


def strict_decimal(token: str, label: str) -> int:
    if not re.fullmatch(r"0|[1-9][0-9]*", token):
        raise GateError(f"non-canonical decimal {label}: {token!r}")
    return int(token)


PREREG_DATA = strict_json_load(PREREG)
validate_deterministic_types(PREREG_DATA, "preregistration")
MIX_ROWS = tuple(
    tuple(int(value, 16) for value in row)
    for row in PREREG_DATA["construction"]["mix_columns_matrix_hex_rows"]
)


# ---------------------------------------------------------------------------
# Independent byte model and deterministic vector derivation.


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
    require_true(
        all(len(state) == STATE_BYTES for state in states),
        "state XOR received a non-32-byte operand",
    )
    output = [0] * STATE_BYTES
    for state in states:
        for index, value in enumerate(state):
            require_true(type(value) is int and 0 <= value <= 255, "invalid state byte")
            output[index] ^= value
    return output


def linear_layer(
    state: Sequence[int], wiring: Sequence[int], direction: int = 1
) -> List[int]:
    require_equal(len(state), STATE_BYTES, "linear-layer state bytes")
    require_equal(len(wiring), 4, "linear-layer wiring arity")
    require_true(direction in (-1, 1), "linear-layer direction must be +/-1")
    shifted = [0] * STATE_BYTES
    for column in range(8):
        for row in range(4):
            offset = int(wiring[row])
            require_true(0 <= offset < 8, "H4 offset outside 0..7")
            source_column = (column + direction * offset) % 8
            shifted[4 * column + row] = int(state[4 * source_column + row])
    output = [0] * STATE_BYTES
    for column in range(8):
        for row in range(4):
            accumulator = 0
            for inner in range(4):
                accumulator ^= gf_mul(
                    MIX_ROWS[row][inner], shifted[4 * column + inner]
                )
            output[4 * column + row] = accumulator
    return output


def round_with_key(
    state: Sequence[int],
    round_key: Sequence[int],
    wiring: Sequence[int],
    direction: int = 1,
) -> List[int]:
    substituted = [AES_SBOX[int(value)] for value in state]
    return xor_states(linear_layer(substituted, wiring, direction), round_key)


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
    declared_ids = tuple(
        item["id"] for item in PREREG_DATA["functional_coverage"]["material_sets"]
    )
    require_equal(declared_ids, EXPECTED_MATERIAL_IDS, "declared material IDs")
    materials = []
    for identifier, domain in zip(EXPECTED_MATERIAL_IDS, EXPECTED_MATERIAL_DOMAINS):
        raw = hashlib.shake_256(domain.encode("ascii")).digest(MATERIAL_BYTES)
        materials.append(parse_material(identifier, domain, raw))
    require_equal(
        materials[0]["raw_sha256"], FROZEN_MATERIAL_SHA256, "frozen material hash"
    )
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
    return blocks


def effective_masks(material: Mapping, wiring: Sequence[int]) -> List[List[int]]:
    keys = [xor_states(material["masks"][0], material["p_in"][0])]
    for key_index in range(1, ROUNDS):
        keys.append(
            xor_states(
                linear_layer(material["p_out"][key_index - 1], wiring),
                material["masks"][key_index],
                material["p_in"][key_index],
            )
        )
    keys.append(
        xor_states(
            linear_layer(material["p_out"][ROUNDS - 1], wiring),
            material["masks"][ROUNDS],
        )
    )
    require_equal(len(keys), MASK_WORDS, "effective-mask word count")
    return keys


def permute_with_schedule(
    block: Sequence[int],
    initial_key: Sequence[int],
    round_keys: Sequence[Sequence[int]],
    wiring: Sequence[int],
    direction: int = 1,
) -> List[int]:
    require_equal(len(round_keys), ROUNDS, "round-key count")
    state = xor_states(block, initial_key)
    for round_key in round_keys:
        state = round_with_key(state, round_key, wiring, direction)
    return state


def canonical_permute(
    block: Sequence[int], keys: Sequence[Sequence[int]], wiring: Sequence[int]
) -> List[int]:
    require_equal(len(keys), MASK_WORDS, "canonical key count")
    return permute_with_schedule(block, keys[0], keys[1:], wiring)


def state_hex(state: Sequence[int]) -> str:
    require_equal(len(state), STATE_BYTES, "state hex bytes")
    return bytes(int(value) for value in state).hex()


def state_to_verilog_hex(state: Sequence[int]) -> str:
    require_equal(len(state), STATE_BYTES, "Verilog vector bytes")
    value = 0
    for index, byte in enumerate(state):
        value |= int(byte) << (8 * index)
    return f"{value:064x}"


def h4_code(wiring: Sequence[int]) -> int:
    require_equal(len(wiring), 4, "H4 code arity")
    code = 0
    for index, value in enumerate(wiring):
        require_true(type(value) is int and 0 <= value < 8, "invalid H4 code value")
        code |= value << (3 * index)
    return code


def build_configurations(
    certified: Sequence[Sequence[int]], materials: Sequence[Mapping]
) -> List[dict]:
    configurations = []
    for h4_index, wiring in enumerate(certified):
        for material_index, material in enumerate(materials):
            configurations.append(
                {
                    "index": len(configurations),
                    "h4_index": h4_index,
                    "material_index": material_index,
                    "material_id": material["id"],
                    "wiring": list(wiring),
                    "h4_code": h4_code(wiring),
                    "keys": effective_masks(material, wiring),
                }
            )
    require_equal(len(configurations), CONFIG_COUNT, "configuration count")
    require_equal(
        [configuration["index"] for configuration in configurations],
        list(range(CONFIG_COUNT)),
        "configuration indices",
    )
    return configurations


# ---------------------------------------------------------------------------
# Frozen input validation.


def marker_digest(raw: bytes, start_text: str, end_text: str, label: str) -> str:
    start = start_text.encode("ascii")
    end = end_text.encode("ascii")
    require_equal(raw.count(start), 1, f"{label} start-marker count")
    require_equal(raw.count(end), 1, f"{label} end-marker count")
    start_index = raw.index(start) + len(start)
    end_index = raw.index(end)
    require_true(start_index <= end_index, f"{label} markers are out of order")
    return sha256_bytes(raw[start_index:end_index])


def first_output_line(command: Sequence[str]) -> str:
    require_true(shutil.which(command[0]) is not None, f"{command[0]} is not available")
    process = subprocess.run(
        list(command), capture_output=True, text=True, timeout=60, check=False
    )
    text = (process.stdout or "") + (process.stderr or "")
    for line in text.splitlines():
        if line.strip():
            return line.strip()
    raise GateError(f"{command[0]} produced no version output")


def validate_memory_nomap_support() -> bool:
    process = subprocess.run(
        ["yosys", "-Q", "-p", "help memory"],
        cwd=str(REPO),
        capture_output=True,
        text=True,
        timeout=60,
        check=False,
    )
    output = (process.stdout or "") + (process.stderr or "")
    require_equal(process.returncode, 0, "Yosys memory help return code")
    require_true(
        re.search(r"(?<![A-Za-z0-9_])-nomap(?![A-Za-z0-9_])", output)
        is not None,
        "pinned Yosys does not advertise memory -nomap",
    )
    return True


def validate_contract_shape() -> None:
    require_equal(PREREG_DATA["schema"], "E256-HARDWARE-H2-PREREGISTRATION-1", "prereg schema")
    require_equal(PREREG_DATA["status"], "FROZEN_FOR_EXECUTION", "prereg status")
    require_equal(sha256_file(PREREG), PREREG_SHA256, "raw preregistration SHA-256")
    authorization = PREREG_DATA["authorization"]
    require_equal(tuple(authorization["graded_constraints"]), EXPECTED_GRADED_CONSTRAINTS, "graded constraints")
    require_equal(authorization["base_contract_sha256"], BASE_ARCHITECTURE_SHA256, "declared base contract hash")
    require_equal(authorization["h2_contract_sha256"], H2_ARCHITECTURE_SHA256, "declared H2 contract hash")
    require_equal(tuple(item["id"] for item in PREREG_DATA["questions"]), EXPECTED_QUESTION_IDS, "question IDs")
    require_equal(tuple(item["id"] for item in PREREG_DATA["controls"]), EXPECTED_CONTROL_IDS, "control IDs")
    require_equal(tuple(item["id"] for item in PREREG_DATA["predictions"]), EXPECTED_PREDICTION_IDS, "prediction IDs")
    require_equal(tuple(item["id"] for item in PREREG_DATA["variants"]), EXPECTED_VARIANT_IDS, "variant IDs")
    require_equal(tuple(item["top"] for item in PREREG_DATA["variants"]), EXPECTED_TOPS, "variant tops")
    require_equal(
        tuple((item["storage_id"], item["h4_id"]) for item in PREREG_DATA["variants"]),
        tuple((storage, h4) for storage in EXPECTED_STORAGE_IDS for h4 in EXPECTED_H4_IDS),
        "variant storage/H4 matrix",
    )
    construction = PREREG_DATA["construction"]
    require_equal(construction["measurement_rounds"], 12, "measurement rounds")
    require_equal(construction["production_round_count"], None, "production round count")
    require_equal(construction["state_bytes"], STATE_BYTES, "state bytes")
    require_equal(construction["aes_sbox_sha256"], AES_SBOX_SHA256, "declared AES hash")
    require_equal(tuple(construction["h4_scope"]["fixed_tuple"]), FIXED_H4, "fixed H4 tuple")
    require_equal(construction["h4_scope"]["certified_set_size"], 384, "declared H4 size")
    require_equal(construction["h4_scope"]["certified_set_sha256"], CERTIFIED_H4_SET_SHA256, "declared H4 hash")
    require_equal(construction["effective_masks"]["logical_bits"], MASK_BITS, "logical mask bits")
    require_equal(construction["effective_masks"]["words"], MASK_WORDS, "logical mask words")
    require_equal(construction["raw_h3_comparator"]["bits"] - MASK_BITS, 6144, "representation-kernel arithmetic")
    coverage = PREREG_DATA["functional_coverage"]
    require_equal(tuple(coverage["block_ids"]), EXPECTED_BLOCK_IDS, "declared block IDs")
    require_equal(
        coverage["fixed_h4_outputs_per_variant"],
        EXPECTED_FIXED_OUTPUTS_PER_VARIANT,
        "fixed-H4 output count contract",
    )
    require_equal(
        coverage["direct_h4_outputs_per_variant"],
        EXPECTED_DIRECT_OUTPUTS_PER_VARIANT,
        "direct-H4 output count contract",
    )
    require_equal(
        3 * EXPECTED_FIXED_OUTPUTS_PER_VARIANT
        + 3 * EXPECTED_DIRECT_OUTPUTS_PER_VARIANT,
        EXPECTED_TOTAL_MODEL_COMPARISONS,
        "per-variant output-count arithmetic",
    )
    require_equal(coverage["expected_total_rtl_model_comparisons"], EXPECTED_TOTAL_MODEL_COMPARISONS, "model comparison contract")
    require_equal(coverage["expected_storage_equivalence_comparisons"], EXPECTED_STORAGE_COMPARISONS, "storage comparison contract")
    require_equal(coverage["expected_fixed_direct_bridge_comparisons"], EXPECTED_BRIDGE_COMPARISONS, "bridge comparison contract")
    synthesis = PREREG_DATA["synthesis_contract"]
    require_equal(synthesis["storage_preserved_script"], STORAGE_SCRIPT_TEMPLATE, "storage script template")
    require_equal(synthesis["mapped_script"], MAPPED_SCRIPT_TEMPLATE, "mapped script template")
    require_equal(synthesis["depth_script"], DEPTH_SCRIPT_TEMPLATE, "depth script template")
    require_equal(tuple(synthesis["generic_metrics"]), METRIC_KEYS + ("generic_abc_combinational_logic_levels",), "generic metric IDs")
    receipt = PREREG_DATA["receipt_contract"]
    require_equal(receipt["schema"], "E256-HARDWARE-H2-GATE-1", "receipt schema")
    require_equal(receipt["status"], "OPEN_PROGRESS", "receipt status")
    require_equal(receipt["output"], str(RECEIPT.relative_to(REPO)), "receipt path")
    require_equal(receipt["runner"], str(Path(__file__).resolve().relative_to(REPO)), "runner path")
    require_equal(receipt["rtl"], str(RTL.relative_to(REPO)), "receipt RTL path")
    require_equal(receipt["testbench"], str(TESTBENCH.relative_to(REPO)), "receipt testbench path")
    require_equal(receipt["scratch"], str(SCRATCH.relative_to(REPO)), "scratch path")
    require_equal(tuple(receipt["deterministic_payload_top_level_keys"]), EXPECTED_PAYLOAD_KEYS, "payload keys")
    require_equal(PREREG_DATA["interpretation"]["valid_emitted_verdict"], VALID_VERDICT, "valid verdict")
    require_equal(PREREG_DATA["interpretation"]["internal_invalid_status"], INVALID_STATUS, "invalid status")


def validate_predecessors() -> Tuple[List[dict], Dict[str, dict], List[List[int]]]:
    declared = tuple(
        (item["id"], item["receipt"], item["receipt_schema"], item["deterministic_payload_sha256"])
        for item in PREREG_DATA["predecessors"]
    )
    require_equal(declared, PREDECESSOR_CONTRACTS, "predecessor contract list")
    records = []
    payloads: Dict[str, dict] = {}
    for identifier, relative, schema, expected_digest in PREDECESSOR_CONTRACTS:
        outer = strict_json_load(REPO / relative)
        require_exact_keys(outer, OUTER_RECEIPT_KEYS, f"{relative} outer receipt")
        payload = outer["deterministic_payload"]
        require_true(isinstance(payload, dict), f"{relative} payload is not an object")
        # Frozen predecessor schemas predate H2's integer-only payload policy;
        # the cost receipt legitimately contains finite JSON ratios.  The
        # strict loader has already rejected duplicate keys and non-finite
        # constants, so reproduce the historical canonical digest without
        # applying H2's no-float validator to the predecessor payload itself.
        require_equal(payload.get("schema"), schema, f"{relative} payload schema")
        require_equal(payload.get("status"), "OPEN_PROGRESS", f"{relative} payload status")
        predecessor_bytes = json.dumps(
            payload, sort_keys=True, separators=(",", ":"), allow_nan=False
        ).encode("utf-8")
        recomputed = sha256_bytes(predecessor_bytes)
        require_equal(recomputed, expected_digest, f"{relative} recomputed payload digest")
        require_equal(outer["deterministic_payload_sha256"], expected_digest, f"{relative} stored payload digest")
        payloads[identifier] = payload
        records.append(
            {
                "id": identifier,
                "path": relative,
                "schema": schema,
                "deterministic_payload_sha256": expected_digest,
            }
        )

    candidate = payloads["E256-063-steps-2-3"]["results"]["h4_wiring"]
    certified = candidate["certified_set"]
    require_true(isinstance(certified, list), "certified H4 set is not a list")
    require_equal(candidate["certified_set_size"], 384, "candidate H4 size")
    require_equal(candidate["certified_set_sha256"], CERTIFIED_H4_SET_SHA256, "candidate H4 stored hash")
    require_equal(candidate["rijndael_tuple"], list(FIXED_H4), "candidate fixed tuple")
    require_equal(candidate["rijndael_tuple_certified"], True, "candidate fixed-tuple certification")
    require_equal(len(certified), 384, "certified H4 list size")
    require_equal(sha256_bytes(canonical_json_bytes(certified)), CERTIFIED_H4_SET_SHA256, "certified H4 canonical hash")
    normalized = []
    for index, wiring in enumerate(certified):
        require_true(isinstance(wiring, list) and len(wiring) == 4, f"H4 tuple {index} shape")
        require_true(all(type(value) is int and 0 <= value < 8 for value in wiring), f"H4 tuple {index} values")
        require_equal(len(set(wiring)), 4, f"H4 tuple {index} distinctness")
        normalized.append(list(wiring))
    require_equal(len({tuple(wiring) for wiring in normalized}), 384, "unique H4 tuples")
    require_true(FIXED_H4 in {tuple(wiring) for wiring in normalized}, "fixed H4 tuple absent")

    attack = payloads["E256-063-step-4"]
    require_equal(attack["pinned_parameters"]["material_sha256"], FROZEN_MATERIAL_SHA256, "attack material hash")
    collapse = payloads["E256-063-h3-collapse"]
    require_equal(collapse["interpretation"]["verdict"], "H3_XOR_OFFSETS_EXACTLY_COLLAPSE_TO_EFFECTIVE_MASKS", "collapse verdict")
    require_equal(collapse["inputs"]["preregistration"]["sha256"], COLLAPSE_PREREG_SHA256, "collapse prereg hash")
    collapse_h4 = collapse["inputs"]["certified_h4_set"]
    require_equal(collapse_h4["size"], 384, "collapse H4 size")
    require_equal(collapse_h4["sha256"], CERTIFIED_H4_SET_SHA256, "collapse H4 hash")
    collapse_materials = collapse["material_normal_form"]["material_sets"]
    require_equal(tuple(item["id"] for item in collapse_materials), EXPECTED_MATERIAL_IDS, "collapse material IDs")
    require_equal(tuple(item["domain"] for item in collapse_materials), EXPECTED_MATERIAL_DOMAINS, "collapse material domains")
    require_equal(tuple(item["raw_bytes"] for item in collapse_materials), (1184, 1184, 1184), "collapse material sizes")
    require_equal(collapse_materials[0]["raw_sha256"], FROZEN_MATERIAL_SHA256, "collapse frozen material hash")
    require_equal(collapse["material_normal_form"]["terminal_rule"], "K_R excludes A_R and must be derived separately for each tested prefix R", "collapse terminal rule")
    return records, payloads, normalized


def validate_frozen_inputs() -> Tuple[dict, List[List[int]]]:
    validate_contract_shape()
    require_equal(sys.version.split()[0], "3.9.6", "running Python version")
    architecture_raw = ARCHITECTURE.read_bytes()
    authorization = PREREG_DATA["authorization"]
    require_equal(
        marker_digest(
            architecture_raw,
            authorization["base_contract_start_marker"],
            authorization["base_contract_end_marker"],
            "base architecture contract",
        ),
        BASE_ARCHITECTURE_SHA256,
        "recomputed base architecture contract",
    )
    require_equal(
        marker_digest(
            architecture_raw,
            authorization["h2_contract_start_marker"],
            authorization["h2_contract_end_marker"],
            "H2 architecture contract",
        ),
        H2_ARCHITECTURE_SHA256,
        "recomputed H2 architecture contract",
    )
    predecessor_records, _payloads, certified = validate_predecessors()

    source_records = {}
    declared_sources = PREREG_DATA["frozen_predecessor_sources"]
    require_equal(set(declared_sources), set(FROZEN_SOURCE_CONTRACTS), "frozen source roles")
    for role in FROZEN_SOURCE_CONTRACTS:
        path, expected_hash = FROZEN_SOURCE_CONTRACTS[role]
        relative = str(path.relative_to(REPO))
        require_equal(declared_sources[role]["path"], relative, f"{role} path")
        require_equal(declared_sources[role]["sha256"], expected_hash, f"{role} declared hash")
        require_equal(sha256_file(path), expected_hash, f"{role} recomputed hash")
        source_records[role] = {"path": relative, "sha256": expected_hash}

    toolchain = PREREG_DATA["toolchain_contract"]
    require_equal(toolchain["python"], "3.9.6", "pinned Python version")
    yosys_version = first_output_line(["yosys", "-V"])
    iverilog_version = first_output_line(["iverilog", "-V"])
    require_true(yosys_version.startswith(toolchain["yosys_version_prefix"]), f"Yosys version drift: {yosys_version!r}")
    require_true(toolchain["yosys_git_sha1"] in yosys_version, "Yosys git SHA-1 drift")
    require_true(iverilog_version.startswith(toolchain["iverilog_version_prefix"]), f"Icarus version drift: {iverilog_version!r}")
    memory_nomap_supported = validate_memory_nomap_support()

    for path, label in ((RTL, "H2 RTL"), (TESTBENCH, "H2 testbench")):
        require_true(path.is_file(), f"{label} is missing")
    require_equal(sha256_bytes(bytes(AES_SBOX)), AES_SBOX_SHA256, "runtime AES S-box hash")

    inputs = {
        "preregistration": {
            "path": str(PREREG.relative_to(REPO)),
            "sha256": PREREG_SHA256,
        },
        "architecture_contracts": {
            "path": str(ARCHITECTURE.relative_to(REPO)),
            "base_sha256": BASE_ARCHITECTURE_SHA256,
            "h2_sha256": H2_ARCHITECTURE_SHA256,
            "preimage_rule": authorization["contract_hash_preimage"],
        },
        "predecessors": predecessor_records,
        "frozen_predecessor_sources": source_records,
        "gate_artifacts": {
            "runner": {
                "path": str(Path(__file__).resolve().relative_to(REPO)),
                "sha256": sha256_file(Path(__file__).resolve()),
            },
            "rtl": {"path": str(RTL.relative_to(REPO)), "sha256": sha256_file(RTL)},
            "testbench": {
                "path": str(TESTBENCH.relative_to(REPO)),
                "sha256": sha256_file(TESTBENCH),
            },
        },
        "certified_h4_set": {
            "source": "logs/e256-hardware-candidate-gate.json",
            "size": len(certified),
            "sha256": CERTIFIED_H4_SET_SHA256,
        },
        "raw_material_sha256": FROZEN_MATERIAL_SHA256,
        "aes_sbox_sha256": AES_SBOX_SHA256,
        "toolchain": {
            "python": sys.version.split()[0],
            "yosys": yosys_version,
            "iverilog": iverilog_version,
            "memory_nomap_supported": memory_nomap_supported,
        },
    }
    return inputs, certified


# ---------------------------------------------------------------------------
# Scratch vectors, main simulation, and exact functional grading.


def prepare_scratch() -> None:
    require_equal(SCRATCH.resolve().parent, (REPO / "build").resolve(), "scratch parent")
    if SCRATCH.exists():
        shutil.rmtree(SCRATCH)
    SCRATCH.mkdir(parents=True, exist_ok=False)


def write_hex_lines(path: Path, lines: Sequence[str], pattern: str, label: str) -> None:
    require_true(all(re.fullmatch(pattern, line) for line in lines), f"{label} line grammar")
    path.write_text("".join(line + "\n" for line in lines), encoding="utf-8")
    reread = path.read_text(encoding="utf-8").splitlines()
    require_equal(reread, list(lines), f"{label} round-trip lines")


def write_main_vectors(configurations: Sequence[Mapping], blocks: Sequence[Tuple[str, bytes]]) -> None:
    mask_lines = [
        state_to_verilog_hex(word)
        for configuration in configurations
        for word in configuration["keys"]
    ]
    h4_lines = [f"{configuration['h4_code']:03x}" for configuration in configurations]
    block_lines = [state_to_verilog_hex(block) for _identifier, block in blocks]
    require_equal(len(mask_lines), CONFIG_COUNT * MASK_WORDS, "mask vector lines")
    require_equal(len(h4_lines), CONFIG_COUNT, "H4 vector lines")
    require_equal(len(block_lines), BLOCK_COUNT, "block vector lines")
    write_hex_lines(SCRATCH / "masks.hex", mask_lines, r"[0-9a-f]{64}", "mask vectors")
    write_hex_lines(SCRATCH / "h4.hex", h4_lines, r"[0-9a-f]{3}", "H4 vectors")
    write_hex_lines(SCRATCH / "blocks.hex", block_lines, r"[0-9a-f]{64}", "block vectors")


def run_process(command: Sequence[str], timeout: int, label: str) -> str:
    process = subprocess.run(
        list(command),
        cwd=str(REPO),
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
    )
    output = (process.stdout or "") + (process.stderr or "")
    if process.returncode != 0:
        raise GateError(f"{label} exited {process.returncode}: {output[-2000:]}")
    return output


def compile_iverilog(
    top: str, output: Path, parameters: Mapping[str, int], label: str
) -> None:
    command = ["iverilog", "-g2012", "-s", top]
    for name, value in parameters.items():
        require_true(type(value) is int and value >= 0, f"{label} parameter {name}")
        command.append(f"-P{top}.{name}={value}")
    command.extend(
        [
            "-o",
            str(output),
            str(TESTBENCH),
            str(ATTACK_RTL),
            str(RTL),
        ]
    )
    run_process(command, 900, label + " compile")


def parse_main_results(path: Path, configurations: Sequence[Mapping]) -> dict:
    require_true(path.is_file(), "main simulation results file is missing")
    rows: Dict[Tuple[int, int], dict] = {}
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        require_true(bool(line), f"blank main result row at line {line_number}")
        parts = line.split(" ")
        require_true(all(parts), f"non-canonical whitespace at main line {line_number}")
        require_equal(parts[0], "rtl", f"main row tag at line {line_number}")
        require_equal(len(parts), 23, f"main row token count at line {line_number}")
        config_index = strict_decimal(parts[1], f"config at line {line_number}")
        block_index = strict_decimal(parts[2], f"block at line {line_number}")
        require_true(0 <= config_index < CONFIG_COUNT, f"config out of range at line {line_number}")
        require_true(0 <= block_index < BLOCK_COUNT, f"block out of range at line {line_number}")
        require_true(re.fullmatch(r"[0-9a-f]{3}", parts[3]) is not None, f"H4 token at line {line_number}")
        require_equal(int(parts[3], 16), configurations[config_index]["h4_code"], f"H4 value at line {line_number}")
        is_fixed = tuple(configurations[config_index]["wiring"]) == FIXED_H4
        expected_run_mask = 0x3F if is_fixed else 0x2A
        require_true(re.fullmatch(r"[0-9a-f]{2}", parts[4]) is not None, f"run-mask token at line {line_number}")
        require_equal(int(parts[4], 16), expected_run_mask, f"run mask at line {line_number}")

        output_tokens = parts[5:11]
        latency_tokens = parts[11:17]
        interval_tokens = parts[17:23]
        outputs: List[Optional[str]] = []
        latencies: List[Optional[int]] = []
        intervals: List[Optional[int]] = []
        for variant_index, variant in enumerate(PREREG_DATA["variants"]):
            executed = variant["h4_id"] == "direct" or is_fixed
            if executed:
                require_true(
                    re.fullmatch(r"[0-9a-f]{64}", output_tokens[variant_index]) is not None,
                    f"state token for {variant['id']} at line {line_number}",
                )
                latency = strict_decimal(
                    latency_tokens[variant_index],
                    f"latency for {variant['id']} at line {line_number}",
                )
                interval = strict_decimal(
                    interval_tokens[variant_index],
                    f"initiation interval for {variant['id']} at line {line_number}",
                )
                require_equal(latency, variant["latency_cycles"], f"{variant['id']} latency at line {line_number}")
                require_equal(interval, variant["initiation_interval_cycles"], f"{variant['id']} II at line {line_number}")
                outputs.append(output_tokens[variant_index])
                latencies.append(latency)
                intervals.append(interval)
            else:
                require_equal(
                    (output_tokens[variant_index], latency_tokens[variant_index], interval_tokens[variant_index]),
                    ("-", "-", "-"),
                    f"unexecuted fixed slot for {variant['id']} at line {line_number}",
                )
                outputs.append(None)
                latencies.append(None)
                intervals.append(None)
        key = (config_index, block_index)
        require_true(key not in rows, f"duplicate main result key {key}")
        rows[key] = {
            "run_mask": expected_run_mask,
            "outputs": outputs,
            "latencies": latencies,
            "initiation_intervals": intervals,
        }
    expected_keys = {(config, block) for config in range(CONFIG_COUNT) for block in range(BLOCK_COUNT)}
    require_equal(set(rows), expected_keys, "main result key set")
    require_equal(len(rows), EXPECTED_RTL_ROWS, "main RTL row count")
    return rows


def run_main_simulation(
    configurations: Sequence[Mapping], blocks: Sequence[Tuple[str, bytes]]
) -> Tuple[dict, dict]:
    binary = SCRATCH / "e256h_h2_integrated_core_tb.vvp"
    compile_iverilog(
        "e256h_h2_integrated_core_tb",
        binary,
        {"CONFIG_COUNT": CONFIG_COUNT},
        "main H2 testbench",
    )
    output = run_process(["vvp", str(binary)], SIM_TIMEOUT_SECONDS, "main H2 simulation")
    sentinel = "E256H_H2_INTEGRATED_CORE_TB_DONE"
    require_equal(output.count(sentinel), 1, "main completion sentinel count")
    rows = parse_main_results(SCRATCH / "results.txt", configurations)
    protocol_evidence = {
        "source": str(TESTBENCH.relative_to(REPO)),
        "completion_sentinel": sentinel,
        "completion_sentinel_count": 1,
        "asserted_observations": {
            "cfg_error_asserted_all_six": True,
            "key_valid_false_all_six": True,
            "busy_never_asserted_after_invalid_start": True,
            "done_never_asserted_after_invalid_start": True,
            "per_executed_input_ready_low_while_busy": True,
            "per_executed_input_ready_high_with_done": True,
        },
        "basis": "fatal-checked protocol controls and per-input ready-window cycle checks completed before the sentinel",
    }
    return rows, protocol_evidence


def run_sbox_semantic_check() -> dict:
    binary = SCRATCH / "e256h_h2_sbox_tb.vvp"
    compile_iverilog("e256h_h2_sbox_tb", binary, {}, "H2 S-box testbench")
    output = run_process(
        ["vvp", str(binary)], 300, "H2 exhaustive S-box simulation"
    )
    sentinel = "E256H_H2_SBOX_TB_DONE"
    require_equal(output.count(sentinel), 1, "S-box completion sentinel count")
    path = SCRATCH / "sbox-results.txt"
    require_true(path.is_file(), "S-box results file is missing")
    observed = []
    for line_number, line in enumerate(
        path.read_text(encoding="utf-8").splitlines(), start=1
    ):
        parts = line.split(" ")
        require_true(
            all(parts) and len(parts) == 4,
            f"S-box row grammar at line {line_number}",
        )
        require_equal(parts[0], "sbox", f"S-box row tag at line {line_number}")
        require_true(
            all(re.fullmatch(r"[0-9a-f]{2}", token) for token in parts[1:]),
            f"S-box hex grammar at line {line_number}",
        )
        input_value, h2_value, frozen_value = (
            int(token, 16) for token in parts[1:]
        )
        require_equal(input_value, line_number - 1, f"S-box input order at line {line_number}")
        require_equal(h2_value, frozen_value, f"H2/frozen S-box value {input_value}")
        require_equal(h2_value, AES_SBOX[input_value], f"H2/model S-box value {input_value}")
        observed.append(h2_value)
    require_equal(len(observed), 256, "exhaustive S-box row count")
    digest = sha256_bytes(bytes(observed))
    require_equal(digest, AES_SBOX_SHA256, "exhaustive RTL S-box SHA-256")
    return {
        "input_count": len(observed),
        "h2_vs_frozen_mismatches": 0,
        "h2_vs_independent_model_mismatches": 0,
        "output_table_sha256": digest,
        "expected_table_sha256": AES_SBOX_SHA256,
        "completion_sentinel_count": 1,
        "byte_exact": True,
    }


def grade_functional(
    rows: Mapping[Tuple[int, int], Mapping],
    configurations: Sequence[Mapping],
    blocks: Sequence[Tuple[str, bytes]],
) -> dict:
    graded_hash = hashlib.sha256()
    storage_hash = hashlib.sha256()
    bridge_hash = hashlib.sha256()
    direct_comparisons = 0
    graded_fixed_comparisons = 0
    storage_comparisons = 0
    bridge_comparisons = 0
    variant_comparisons = Counter()
    variant_input_keys: Dict[str, Set[Tuple[int, int]]] = {
        identifier: set() for identifier in EXPECTED_VARIANT_IDS
    }
    latency_sets: Dict[str, Set[int]] = {
        identifier: set() for identifier in EXPECTED_VARIANT_IDS
    }
    interval_sets: Dict[str, Set[int]] = {
        identifier: set() for identifier in EXPECTED_VARIANT_IDS
    }
    direct_indices = (1, 3, 5)
    fixed_indices = (0, 2, 4)

    for config_index, configuration in enumerate(configurations):
        wiring = configuration["wiring"]
        keys = configuration["keys"]
        is_fixed = tuple(wiring) == FIXED_H4
        for block_index, (block_id, block) in enumerate(blocks):
            row = rows[(config_index, block_index)]
            outputs = row["outputs"]
            direct_expected = state_hex(canonical_permute(block, keys, wiring))
            for variant_index in direct_indices:
                variant = EXPECTED_VARIANT_IDS[variant_index]
                require_true(outputs[variant_index] is not None, f"missing direct output {variant} config={config_index} block={block_index}")
                require_equal(outputs[variant_index], direct_expected, f"direct RTL/model {variant} config={config_index} block={block_index}")
                direct_comparisons += 1
                update_record_hash(
                    graded_hash,
                    {
                        "comparison": "direct_model",
                        "variant": variant,
                        "h4": list(wiring),
                        "material": configuration["material_id"],
                        "block": block_id,
                        "output": outputs[variant_index],
                    },
                )
            if is_fixed:
                fixed_expected = state_hex(canonical_permute(block, keys, FIXED_H4))
                for variant_index in fixed_indices:
                    variant = EXPECTED_VARIANT_IDS[variant_index]
                    require_true(outputs[variant_index] is not None, f"missing fixed output {variant} config={config_index} block={block_index}")
                    require_equal(outputs[variant_index], fixed_expected, f"fixed RTL/model {variant} config={config_index} block={block_index}")
                    graded_fixed_comparisons += 1
                    update_record_hash(
                        graded_hash,
                        {
                            "comparison": "fixed_model",
                            "variant": variant,
                            "h4": list(FIXED_H4),
                            "material": configuration["material_id"],
                            "block": block_id,
                            "output": outputs[variant_index],
                        },
                    )
            else:
                require_equal(
                    tuple(outputs[index] for index in fixed_indices),
                    (None, None, None),
                    f"fixed outputs outside frozen corpus config={config_index} block={block_index}",
                )

            require_equal(outputs[1], outputs[3], f"direct ff/ring config={config_index} block={block_index}")
            require_equal(outputs[1], outputs[5], f"direct ff/mem config={config_index} block={block_index}")
            storage_comparisons += 2
            update_record_hash(storage_hash, {"path": "direct_ff_ring", "config": config_index, "block": block_id, "output": outputs[1]})
            update_record_hash(storage_hash, {"path": "direct_ff_mem", "config": config_index, "block": block_id, "output": outputs[1]})
            if is_fixed:
                require_equal(outputs[0], outputs[2], f"fixed ff/ring config={config_index} block={block_index}")
                require_equal(outputs[0], outputs[4], f"fixed ff/mem config={config_index} block={block_index}")
                storage_comparisons += 2
                update_record_hash(storage_hash, {"path": "fixed_ff_ring", "config": config_index, "block": block_id, "output": outputs[0]})
                update_record_hash(storage_hash, {"path": "fixed_ff_mem", "config": config_index, "block": block_id, "output": outputs[0]})
                for fixed_index, direct_index in zip(fixed_indices, direct_indices):
                    require_equal(outputs[fixed_index], outputs[direct_index], f"fixed/direct bridge config={config_index} block={block_index} storage={fixed_index // 2}")
                    bridge_comparisons += 1
                    update_record_hash(bridge_hash, {"storage": EXPECTED_VARIANT_IDS[fixed_index].split("_")[0], "material": configuration["material_id"], "block": block_id, "output": outputs[fixed_index]})

            for variant_index, variant in enumerate(EXPECTED_VARIANT_IDS):
                if outputs[variant_index] is None:
                    continue
                latency = row["latencies"][variant_index]
                interval = row["initiation_intervals"][variant_index]
                require_true(type(latency) is int, f"missing latency evidence for {variant}")
                require_true(type(interval) is int, f"missing II evidence for {variant}")
                variant_comparisons[variant] += 1
                variant_input_keys[variant].add((config_index, block_index))
                latency_sets[variant].add(latency)
                interval_sets[variant].add(interval)

    coverage = PREREG_DATA["functional_coverage"]
    expected_variant_counts = {
        variant["id"]: (
            coverage["fixed_h4_outputs_per_variant"]
            if variant["h4_id"] == "fixed"
            else coverage["direct_h4_outputs_per_variant"]
        )
        for variant in PREREG_DATA["variants"]
    }
    actual_variant_counts = {
        identifier: variant_comparisons[identifier]
        for identifier in EXPECTED_VARIANT_IDS
    }
    require_equal(actual_variant_counts, expected_variant_counts, "per-variant output counts")

    input_set_hashes = {}
    for variant in PREREG_DATA["variants"]:
        identifier = variant["id"]
        expected_inputs = {
            (config_index, block_index)
            for config_index, configuration in enumerate(configurations)
            if variant["h4_id"] == "direct" or tuple(configuration["wiring"]) == FIXED_H4
            for block_index in range(BLOCK_COUNT)
        }
        require_equal(variant_input_keys[identifier], expected_inputs, f"{identifier} exact input set")
        input_set_hashes[identifier] = sha256_bytes(
            canonical_json_bytes([list(key) for key in sorted(expected_inputs)])
        )

    total_model_comparisons = direct_comparisons + graded_fixed_comparisons
    require_equal(direct_comparisons, 3 * EXPECTED_DIRECT_OUTPUTS_PER_VARIANT, "direct model comparison count")
    require_equal(graded_fixed_comparisons, 3 * EXPECTED_FIXED_OUTPUTS_PER_VARIANT, "graded fixed model comparison count")
    require_equal(total_model_comparisons, EXPECTED_TOTAL_MODEL_COMPARISONS, "total model comparison count")
    require_equal(sum(actual_variant_counts.values()), EXPECTED_TOTAL_MODEL_COMPARISONS, "variant output total")
    require_equal(storage_comparisons, EXPECTED_STORAGE_COMPARISONS, "storage comparison count")
    require_equal(bridge_comparisons, EXPECTED_BRIDGE_COMPARISONS, "bridge comparison count")
    expected_latency_sets = {
        variant["id"]: [variant["latency_cycles"]]
        for variant in PREREG_DATA["variants"]
    }
    expected_interval_sets = {
        variant["id"]: [variant["initiation_interval_cycles"]]
        for variant in PREREG_DATA["variants"]
    }
    actual_latency_sets = {key: sorted(value) for key, value in latency_sets.items()}
    actual_interval_sets = {key: sorted(value) for key, value in interval_sets.items()}
    require_equal(actual_latency_sets, expected_latency_sets, "latency singleton sets")
    require_equal(actual_interval_sets, expected_interval_sets, "initiation-interval singleton sets")

    return {
        "expected_rtl_rows": EXPECTED_RTL_ROWS,
        "executed_rtl_rows": len(rows),
        "expected_variant_rtl_outputs": expected_variant_counts,
        "executed_variant_rtl_outputs": actual_variant_counts,
        "variant_input_set_sha256": input_set_hashes,
        "variant_input_sets_exact": True,
        "direct_model_comparisons": direct_comparisons,
        "graded_fixed_model_comparisons": graded_fixed_comparisons,
        "expected_total_rtl_model_comparisons": EXPECTED_TOTAL_MODEL_COMPARISONS,
        "executed_total_rtl_model_comparisons": total_model_comparisons,
        "model_mismatches": 0,
        "expected_storage_equivalence_comparisons": EXPECTED_STORAGE_COMPARISONS,
        "executed_storage_equivalence_comparisons": storage_comparisons,
        "storage_equivalence_mismatches": 0,
        "expected_fixed_direct_bridge_comparisons": EXPECTED_BRIDGE_COMPARISONS,
        "executed_fixed_direct_bridge_comparisons": bridge_comparisons,
        "fixed_direct_bridge_mismatches": 0,
        "graded_model_aggregate_sha256": graded_hash.hexdigest(),
        "storage_equivalence_aggregate_sha256": storage_hash.hexdigest(),
        "fixed_direct_bridge_aggregate_sha256": bridge_hash.hexdigest(),
        "aggregate_encoding": AGGREGATE_ENCODING,
        "expected_cycle_observations_per_variant": expected_variant_counts,
        "executed_cycle_observations_per_variant": actual_variant_counts,
        "executed_total_cycle_observations": sum(actual_variant_counts.values()),
        "per_input_ready_window_checked": True,
        "latency_singleton_sets": actual_latency_sets,
        "initiation_interval_singleton_sets": actual_interval_sets,
        "exact_execution_sets": True,
        "all_byte_exact": True,
    }


# ---------------------------------------------------------------------------
# RTL mutation controls.


def write_control_vectors(
    configurations: Sequence[Mapping],
    blocks: Sequence[Tuple[str, bytes]],
    transform: str,
) -> List[List[List[int]]]:
    transformed_configurations: List[List[List[int]]] = []
    for configuration in configurations:
        original = [[int(value) for value in word] for word in configuration["keys"]]
        if transform == "identity":
            transformed = original
        elif transform == "reverse_words":
            transformed = list(reversed(original))
        elif transform == "reverse_word_bytes":
            transformed = [list(reversed(word)) for word in original]
        else:
            raise GateError(f"unknown control-vector transform: {transform}")
        transformed_configurations.append(transformed)
    mask_lines = [state_to_verilog_hex(word) for keys in transformed_configurations for word in keys]
    h4_lines = [f"{configuration['h4_code']:03x}" for configuration in configurations]
    block_lines = [state_to_verilog_hex(block) for _identifier, block in blocks]
    write_hex_lines(SCRATCH / "control-masks.hex", mask_lines, r"[0-9a-f]{64}", "control masks")
    write_hex_lines(SCRATCH / "control-h4.hex", h4_lines, r"[0-9a-f]{3}", "control H4")
    write_hex_lines(SCRATCH / "blocks.hex", block_lines, r"[0-9a-f]{64}", "control blocks")
    return transformed_configurations


def parse_control_results(
    path: Path,
    mutation: int,
    storage: int,
    direct_h4: int,
    configurations: Sequence[Mapping],
) -> Dict[Tuple[int, int], dict]:
    require_true(path.is_file(), "control results file is missing")
    rows: Dict[Tuple[int, int], dict] = {}
    expected_latency = 14 if storage == 2 else 12
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        require_true(bool(line), f"blank control row at line {line_number}")
        parts = line.split(" ")
        require_true(all(parts), f"non-canonical whitespace at control line {line_number}")
        require_equal(len(parts), 9, f"control token count at line {line_number}")
        require_equal(parts[0], "control", f"control tag at line {line_number}")
        values = [strict_decimal(parts[index], f"control field {index} at line {line_number}") for index in range(1, 6)]
        require_equal(values[0], mutation, f"control mutation at line {line_number}")
        require_equal(values[1], storage, f"control storage at line {line_number}")
        require_equal(values[2], direct_h4, f"control direct flag at line {line_number}")
        config_index, block_index = values[3], values[4]
        require_true(0 <= config_index < len(configurations), f"control config range at line {line_number}")
        require_true(0 <= block_index < BLOCK_COUNT, f"control block range at line {line_number}")
        require_true(re.fullmatch(r"[0-9a-f]{3}", parts[6]) is not None, f"control H4 grammar at line {line_number}")
        require_equal(int(parts[6], 16), configurations[config_index]["h4_code"], f"control H4 at line {line_number}")
        require_true(re.fullmatch(r"[0-9a-f]{64}", parts[7]) is not None, f"control output grammar at line {line_number}")
        latency = strict_decimal(parts[8], f"control latency at line {line_number}")
        require_equal(latency, expected_latency, f"control latency at line {line_number}")
        key = (config_index, block_index)
        require_true(key not in rows, f"duplicate control result key {key}")
        rows[key] = {"output": parts[7], "latency": latency}
    expected_keys = {(config, block) for config in range(len(configurations)) for block in range(BLOCK_COUNT)}
    require_equal(set(rows), expected_keys, "control result key set")
    return rows


def mutated_model_output(
    control_id: str,
    block: Sequence[int],
    configuration: Mapping,
    transformed_keys: Sequence[Sequence[int]],
    block_index: int,
) -> List[int]:
    wiring = configuration["wiring"]
    original_keys = configuration["keys"]
    if control_id in ("wrong_key_order", "reverse_word_bytes"):
        return canonical_permute(block, transformed_keys, wiring)
    if control_id in ("wrong_round_key_address", "stale_sync_memory_read"):
        return permute_with_schedule(block, original_keys[0], original_keys[:ROUNDS], wiring)
    if control_id == "broken_ring_rotation":
        # With the acceptance rotation omitted, each block performs only the
        # twelve busy-edge rotations.  The 13-word bank therefore begins the
        # next block one word behind its prior starting position.
        start_index = (-block_index) % MASK_WORDS
        round_keys = [
            original_keys[(start_index + round_index) % MASK_WORDS]
            for round_index in range(ROUNDS)
        ]
        return permute_with_schedule(
            block, original_keys[start_index], round_keys, wiring
        )
    if control_id == "wrong_h4_shift_direction":
        return permute_with_schedule(block, original_keys[0], original_keys[1:], wiring, direction=-1)
    if control_id == "ignore_h4_selector":
        return canonical_permute(block, original_keys, FIXED_H4)
    raise GateError(f"unknown modeled control: {control_id}")


def run_rtl_control(
    control_id: str,
    mutation: int,
    storage: int,
    direct_h4: int,
    configurations: Sequence[Mapping],
    blocks: Sequence[Tuple[str, bytes]],
    transform: str = "identity",
) -> dict:
    transformed = write_control_vectors(configurations, blocks, transform)
    safe_label = re.sub(r"[^a-z0-9]+", "-", control_id.lower()).strip("-")
    binary = SCRATCH / f"control-{safe_label}.vvp"
    compile_iverilog(
        "e256h_h2_control_tb",
        binary,
        {
            "STORAGE": storage,
            "DIRECT_H4": direct_h4,
            "MUTATION": mutation,
            "CONFIG_COUNT": len(configurations),
        },
        f"{control_id} control",
    )
    output = run_process(["vvp", str(binary)], SIM_TIMEOUT_SECONDS, f"{control_id} simulation")
    sentinel = "E256H_H2_CONTROL_TB_DONE"
    require_equal(output.count(sentinel), 1, f"{control_id} completion sentinel count")
    rows = parse_control_results(
        SCRATCH / "control-results.txt", mutation, storage, direct_h4, configurations
    )
    mismatch_count = 0
    aggregate = hashlib.sha256()
    first_witness = None
    for config_index, configuration in enumerate(configurations):
        for block_index, (block_id, block) in enumerate(blocks):
            observed = rows[(config_index, block_index)]["output"]
            correct = state_hex(
                canonical_permute(block, configuration["keys"], configuration["wiring"])
            )
            mutated = state_hex(
                mutated_model_output(
                    control_id,
                    block,
                    configuration,
                    transformed[config_index],
                    block_index,
                )
            )
            require_equal(observed, mutated, f"{control_id} planted-model match config={config_index} block={block_index}")
            if observed != correct:
                mismatch_count += 1
                if first_witness is None:
                    first_witness = {
                        "config": config_index,
                        "h4": list(configuration["wiring"]),
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
                    "h4": list(configuration["wiring"]),
                    "material": configuration["material_id"],
                    "block": block_id,
                    "correct": correct,
                    "mutated": observed,
                },
            )
    require_true(mismatch_count > 0, f"{control_id} produced no model mismatch witness")
    if control_id == "ignore_h4_selector":
        require_equal(len(configurations), 384, "ignore-selector configuration count")
        require_equal(
            sha256_bytes(canonical_json_bytes([configuration["wiring"] for configuration in configurations])),
            CERTIFIED_H4_SET_SHA256,
            "ignore-selector H4 corpus hash",
        )
        require_true(
            first_witness is not None and tuple(first_witness["h4"]) != FIXED_H4,
            "ignore-selector lacks a non-fixed H4 witness",
        )
    return {
        "mutation_code": mutation,
        "storage_code": storage,
        "direct_h4": bool(direct_h4),
        "configuration_count": len(configurations),
        "executed_rows": len(rows),
        "model_comparisons": len(rows),
        "planted_model_matches": len(rows),
        "correct_model_mismatches": mismatch_count,
        "first_mismatch_witness": first_witness,
        "aggregate_sha256": aggregate.hexdigest(),
        "completion_sentinel_count": 1,
        "detected": True,
    }


def run_rtl_controls(
    configurations: Sequence[Mapping],
    blocks: Sequence[Tuple[str, bytes]],
    protocol_evidence: Mapping,
) -> Dict[str, dict]:
    nonfixed = next(
        configuration
        for configuration in configurations
        if configuration["material_index"] == 0 and tuple(configuration["wiring"]) != FIXED_H4
    )
    singleton = [nonfixed]
    h4_corpus = [
        configuration
        for configuration in configurations
        if configuration["material_index"] == 0
    ]
    require_equal(len(h4_corpus), 384, "control H4 corpus count")
    records = {
        "wrong_key_order": run_rtl_control(
            "wrong_key_order", 6, 0, 1, singleton, blocks, "reverse_words"
        ),
        "wrong_round_key_address": run_rtl_control(
            "wrong_round_key_address", 1, 0, 1, singleton, blocks
        ),
        "reverse_word_bytes": run_rtl_control(
            "reverse_word_bytes", 7, 0, 1, singleton, blocks, "reverse_word_bytes"
        ),
        "wrong_h4_shift_direction": run_rtl_control(
            "wrong_h4_shift_direction", 2, 0, 1, singleton, blocks
        ),
        "ignore_h4_selector": run_rtl_control(
            "ignore_h4_selector", 3, 0, 1, h4_corpus, blocks
        ),
        "broken_ring_rotation": run_rtl_control(
            "broken_ring_rotation", 4, 1, 1, singleton, blocks
        ),
        "stale_sync_memory_read": run_rtl_control(
            "stale_sync_memory_read", 5, 2, 1, singleton, blocks
        ),
        "incomplete_configuration": {
            "evidence": dict(protocol_evidence),
            "required_observations": {
                "cfg_error_asserted": True,
                "key_valid_false": True,
                "no_done_pulse": True,
            },
            "detected": True,
        },
    }
    return records


# ---------------------------------------------------------------------------
# Yosys JSON classification and independent hierarchy accounting.


COARSE_SEQUENTIAL_TYPES = {
    "$ff",
    "$dff",
    "$dffe",
    "$dffsr",
    "$dffsre",
    "$adff",
    "$adffe",
    "$aldff",
    "$aldffe",
    "$sdff",
    "$sdffe",
    "$sdffce",
    "$sdffre",
    "$sdffsre",
    "$sr",
}
FINE_SEQUENTIAL_RE = re.compile(
    r"^\$_(?:DFF|DFFE|DFFSR|DFFSRE|ADFF|ADFFE|ALDFF|ALDFFE|SDFF|SDFFE|SDFFCE|SDFFRE|SDFFSRE|SR)(?:_[A-Z0-9]+)*_$"
)
FORBIDDEN_LATCH_RE = re.compile(r"(?:LATCH|\$[a-z]*latch)", re.IGNORECASE)
SEQUENTIAL_LOOKING_RE = re.compile(r"(?:DFF|FLIPFLOP|\$ff$|\$sr$)", re.IGNORECASE)
MEMORY_TYPE = "$mem_v2"
IGNORED_METADATA_CELL_TYPES = {"$scopeinfo"}


def parse_yosys_int(value, label: str) -> int:
    if type(value) is int:
        require_true(value >= 0, f"negative Yosys integer {label}")
        return value
    require_true(type(value) is str and bool(value), f"invalid Yosys integer {label}")
    if re.fullmatch(r"[01]+", value):
        return int(value, 2)
    if re.fullmatch(r"[0-9]+", value):
        return int(value, 10)
    match = re.fullmatch(r"([0-9]+)'([bodh])([0-9a-fA-F]+)", value)
    if match:
        base = {"b": 2, "o": 8, "d": 10, "h": 16}[match.group(2)]
        return int(match.group(3), base)
    raise GateError(f"undefined or unsupported Yosys integer {label}: {value!r}")


def validate_top_ports(data: Mapping, top: str, expected: Mapping[str, Tuple[str, int]]) -> None:
    modules = data.get("modules")
    require_true(isinstance(modules, dict), "Yosys JSON modules object is absent")
    require_true(top in modules, f"Yosys JSON top {top} is absent")
    ports = modules[top].get("ports")
    require_true(isinstance(ports, dict), f"{top} ports object is absent")
    require_equal(set(ports), set(expected), f"{top} port names")
    for name, (direction, width) in expected.items():
        port = ports[name]
        require_equal(port.get("direction"), direction, f"{top}.{name} direction")
        bits = port.get("bits")
        require_true(isinstance(bits, list), f"{top}.{name} bits are absent")
        require_equal(len(bits), width, f"{top}.{name} width")


def primitive_signature(cell_type: str, cell: Mapping) -> str:
    raw_parameters = cell.get("parameters", {})
    directions = cell.get("port_directions", {})
    connections = cell.get("connections", {})
    require_true(isinstance(raw_parameters, dict), f"{cell_type} parameters are not an object")
    parameters = dict(raw_parameters)
    if cell_type == MEMORY_TYPE:
        # `flatten` rewrites this diagnostic hierarchy name while preserving
        # every functional memory parameter and port.  MEMID is not hardware.
        require_true("MEMID" in parameters, "$mem_v2 MEMID metadata is absent")
        parameters.pop("MEMID")
    require_true(isinstance(directions, dict), f"{cell_type} port directions are not an object")
    require_true(isinstance(connections, dict), f"{cell_type} connections are not an object")
    require_equal(set(directions), set(connections), f"{cell_type} direction/connection ports")
    ports = []
    for port_name in sorted(connections):
        direction = directions[port_name]
        require_true(direction in ("input", "output", "inout"), f"{cell_type}.{port_name} direction")
        bits = connections[port_name]
        require_true(isinstance(bits, list), f"{cell_type}.{port_name} connection bits")
        ports.append([port_name, direction, len(bits)])
    return canonical_json_bytes(
        {
            "type": cell_type,
            "parameters": parameters,
            "ports": ports,
        }
    ).decode("utf-8")


def classify_primitive(cell_type: str, cell: Mapping, label: str) -> Tuple[int, int, int]:
    """Return LUT6 count, sequential bits, and generic memory bits."""
    if FORBIDDEN_LATCH_RE.search(cell_type):
        raise GateError(f"latch primitive is forbidden at {label}: {cell_type}")
    if cell_type == MEMORY_TYPE:
        parameters = cell.get("parameters", {})
        width = parse_yosys_int(parameters.get("WIDTH"), label + ".WIDTH")
        size = parse_yosys_int(parameters.get("SIZE"), label + ".SIZE")
        require_true(width > 0 and size > 0, f"zero-sized memory at {label}")
        return 0, 0, width * size
    if cell_type.startswith("$mem"):
        raise GateError(f"unclassified or residual memory primitive at {label}: {cell_type}")
    is_coarse = cell_type in COARSE_SEQUENTIAL_TYPES
    is_fine = FINE_SEQUENTIAL_RE.fullmatch(cell_type) is not None
    if is_coarse or is_fine:
        connections = cell.get("connections", {})
        require_true(isinstance(connections, dict) and "Q" in connections, f"sequential Q port absent at {label}")
        q_bits = connections["Q"]
        require_true(isinstance(q_bits, list) and len(q_bits) > 0, f"sequential Q width invalid at {label}")
        width = len(q_bits)
        if is_fine:
            require_equal(width, 1, f"fine sequential width at {label}")
        parameter_width = cell.get("parameters", {}).get("WIDTH")
        if parameter_width is not None:
            require_equal(parse_yosys_int(parameter_width, label + ".WIDTH"), width, f"sequential parameter width at {label}")
        return 0, width, 0
    if SEQUENTIAL_LOOKING_RE.search(cell_type):
        raise GateError(f"unclassified sequential primitive at {label}: {cell_type}")
    if cell_type == "$lut":
        width = parse_yosys_int(cell.get("parameters", {}).get("WIDTH"), label + ".WIDTH")
        require_true(1 <= width <= 6, f"mapped LUT width outside 1..6 at {label}")
        return 1, 0, 0
    return 0, 0, 0


def zero_metrics() -> Dict[str, int]:
    return {key: 0 for key in METRIC_KEYS}


def add_metrics(left: Mapping[str, int], right: Mapping[str, int], multiplier: int = 1) -> Dict[str, int]:
    require_true(type(multiplier) is int and multiplier >= 0, "metric multiplier")
    return {key: int(left[key]) + multiplier * int(right[key]) for key in METRIC_KEYS}


def multiply_counter(counter: Counter, multiplier: int) -> Counter:
    result = Counter()
    for key, value in counter.items():
        result[key] = value * multiplier
    return result


def counter_digest(counter: Counter) -> str:
    entries = [[key, counter[key]] for key in sorted(counter)]
    return sha256_bytes(canonical_json_bytes(entries))


def analyze_yosys_graph(data: Mapping, top: str, label: str) -> dict:
    validate_deterministic_types(data, label)
    modules = data.get("modules")
    require_true(isinstance(modules, dict) and modules, f"{label} modules object")
    require_true(top in modules, f"{label} top is absent")
    local: Dict[str, dict] = {}
    for module_name, module in modules.items():
        require_true(isinstance(module, dict), f"{label} module {module_name}")
        memories = module.get("memories", {})
        require_true(isinstance(memories, dict), f"{label} module memories {module_name}")
        require_equal(len(memories), 0, f"{label} unlowered memories in {module_name}")
        cells = module.get("cells", {})
        require_true(isinstance(cells, dict), f"{label} cells in {module_name}")
        metrics = zero_metrics()
        signatures = Counter()
        primitive_types = Counter()
        children = Counter()
        child_instances: List[str] = []
        primitive_cells: List[Tuple[str, str, Mapping]] = []
        for cell_name, cell in cells.items():
            require_true(isinstance(cell, dict), f"{label} cell {module_name}.{cell_name}")
            cell_type = cell.get("type")
            require_true(type(cell_type) is str and cell_type, f"{label} cell type {module_name}.{cell_name}")
            if cell_type in modules:
                children[cell_type] += 1
                child_instances.append(cell_type)
                continue
            if cell_type in IGNORED_METADATA_CELL_TYPES:
                continue
            lut6, sequential_bits, memory_bits = classify_primitive(
                cell_type, cell, f"{label}:{module_name}.{cell_name}"
            )
            metrics["generic_abc_lut6"] += lut6
            metrics["generic_sequential_bits"] += sequential_bits
            metrics["generic_memory_bits"] += memory_bits
            metrics["generic_primitive_cells"] += 1
            signature = primitive_signature(cell_type, cell)
            signatures[signature] += 1
            primitive_types[cell_type] += 1
            primitive_cells.append((cell_name, cell_type, cell))
        local[module_name] = {
            "metrics": metrics,
            "signatures": signatures,
            "primitive_types": primitive_types,
            "children": children,
            "child_instances": child_instances,
            "primitive_cells": primitive_cells,
        }

    reachable: Set[str] = set()
    active: Set[str] = set()
    finished: Set[str] = set()

    def visit(module_name: str) -> None:
        if module_name in active:
            raise GateError(f"hierarchy cycle in {label} at {module_name}")
        if module_name in finished:
            reachable.add(module_name)
            return
        active.add(module_name)
        reachable.add(module_name)
        for child in local[module_name]["children"]:
            visit(child)
        active.remove(module_name)
        finished.add(module_name)

    visit(top)

    memo: Dict[str, Tuple[Dict[str, int], Counter, Counter]] = {}
    recursive_active: Set[str] = set()

    def recursive(module_name: str) -> Tuple[Dict[str, int], Counter, Counter]:
        if module_name in memo:
            return memo[module_name]
        if module_name in recursive_active:
            raise GateError(f"recursive accounting cycle in {label} at {module_name}")
        recursive_active.add(module_name)
        metrics = dict(local[module_name]["metrics"])
        signatures = Counter(local[module_name]["signatures"])
        primitive_types = Counter(local[module_name]["primitive_types"])
        for child, multiplicity in local[module_name]["children"].items():
            child_metrics, child_signatures, child_types = recursive(child)
            metrics = add_metrics(metrics, child_metrics, multiplicity)
            signatures.update(multiply_counter(child_signatures, multiplicity))
            primitive_types.update(multiply_counter(child_types, multiplicity))
        recursive_active.remove(module_name)
        memo[module_name] = (metrics, signatures, primitive_types)
        return memo[module_name]

    recursive_metrics, recursive_signatures, recursive_types = recursive(top)

    expanded_metrics = zero_metrics()
    expanded_signatures = Counter()
    expanded_types = Counter()
    module_instances = Counter()
    stack = [top]
    expanded_count = 0
    while stack:
        module_name = stack.pop()
        expanded_count += 1
        require_true(expanded_count <= 1000000, f"hierarchy expansion runaway in {label}")
        module_instances[module_name] += 1
        expanded_metrics = add_metrics(expanded_metrics, local[module_name]["metrics"])
        expanded_signatures.update(local[module_name]["signatures"])
        expanded_types.update(local[module_name]["primitive_types"])
        stack.extend(local[module_name]["child_instances"])
    require_equal(expanded_metrics, recursive_metrics, f"{label} recursive/expanded metrics")
    require_equal(expanded_signatures, recursive_signatures, f"{label} recursive/expanded primitive signatures")
    require_equal(expanded_types, recursive_types, f"{label} recursive/expanded primitive types")

    public_local = {
        module_name: {
            "metrics": dict(local[module_name]["metrics"]),
            "child_multiplicities": {
                child: local[module_name]["children"][child]
                for child in sorted(local[module_name]["children"])
            },
            "primitive_type_multiset": {
                primitive_type: local[module_name]["primitive_types"][primitive_type]
                for primitive_type in sorted(local[module_name]["primitive_types"])
            },
        }
        for module_name in sorted(reachable)
    }
    public = {
        "top": top,
        "reachable_modules": sorted(reachable),
        "reachable_module_count": len(reachable),
        "local_modules": public_local,
        "recursive_metrics": dict(recursive_metrics),
        "recursive_primitive_type_multiset": {
            primitive_type: recursive_types[primitive_type]
            for primitive_type in sorted(recursive_types)
        },
        "recursive_primitive_signature_entries": sum(recursive_signatures.values()),
        "recursive_primitive_signature_multiset_sha256": counter_digest(recursive_signatures),
        "independent_expansion": {
            "module_instance_multiplicities": {
                module_name: module_instances[module_name]
                for module_name in sorted(module_instances)
            },
            "expanded_module_instances": sum(module_instances.values()),
            "metrics_match": True,
            "primitive_signature_multiset_match": True,
            "primitive_type_multiset_match": True,
        },
        "hierarchy_cycle": False,
    }
    return {
        "data": data,
        "modules": modules,
        "local": local,
        "reachable": reachable,
        "recursive_metrics": recursive_metrics,
        "recursive_signatures": recursive_signatures,
        "recursive_types": recursive_types,
        "module_instances": module_instances,
        "public": public,
    }


def module_matches_base(module_name: str, base: str) -> bool:
    return module_name == base or base in module_name


def find_reachable_module(analysis: Mapping, base: str, label: str) -> str:
    matches = sorted(
        module_name
        for module_name in analysis["reachable"]
        if module_matches_base(module_name, base)
    )
    require_equal(len(matches), 1, f"{label} module match for {base}")
    return matches[0]


def memory_cell_details(analysis: Mapping, module_name: str, label: str) -> dict:
    memory_cells = [
        (cell_name, cell)
        for cell_name, cell_type, cell in analysis["local"][module_name]["primitive_cells"]
        if cell_type == MEMORY_TYPE
    ]
    require_equal(len(memory_cells), 1, f"{label} memory-cell count")
    cell_name, cell = memory_cells[0]
    parameters = cell["parameters"]
    width = parse_yosys_int(parameters.get("WIDTH"), label + ".WIDTH")
    size = parse_yosys_int(parameters.get("SIZE"), label + ".SIZE")
    read_clock_enable = parse_yosys_int(parameters.get("RD_CLK_ENABLE"), label + ".RD_CLK_ENABLE")
    write_clock_enable = parse_yosys_int(parameters.get("WR_CLK_ENABLE"), label + ".WR_CLK_ENABLE")
    require_equal(width, 256, f"{label} memory width")
    require_equal(size, 13, f"{label} memory size")
    require_equal(read_clock_enable, 0, f"{label} collected memory read-clock encoding")
    require_true(write_clock_enable != 0, f"{label} write clock is absent")
    return {
        "cell": cell_name,
        "type": MEMORY_TYPE,
        "width": width,
        "size": size,
        "logical_bits": width * size,
        "read_clock_enable": read_clock_enable,
        "write_clock_enable": write_clock_enable,
        "read_timing_representation": "asynchronous collected-memory read followed by separately-accounted 256-bit output register",
    }


def run_yosys(script: str, label: str, timeout: int = SYNTH_TIMEOUT_SECONDS) -> str:
    return run_process(["yosys", "-Q", "-p", script], timeout, label)


def strict_yosys_json(path: Path, label: str) -> dict:
    require_true(path.is_file(), f"{label} JSON is missing")
    data = strict_json_load(path)
    validate_deterministic_types(data, label)
    require_true(isinstance(data, dict), f"{label} JSON is not an object")
    return data


def parse_depth(output: str, top: str) -> int:
    require_true(
        re.search(r"(?i)(found[^\n]*loop|logic loop|combinational loop|loop detected)", output) is None,
        f"loop diagnostic in depth analysis for {top}",
    )
    matches = re.findall(
        r"Longest topological path in\s+[^\n]*?\(length=(\d+)\)", output
    )
    require_equal(len(matches), 1, f"{top} depth result count")
    depth = int(matches[0])
    require_true(depth >= 0, f"negative depth for {top}")
    return depth


def instantiate_script(template: str, top: str, replacements: Mapping[str, str]) -> str:
    script = template.replace("<rtl_sources>", " ".join(str(path.relative_to(REPO)) for path in (ATTACK_RTL, RTL)))
    script = script.replace("<top>", top)
    for placeholder, value in replacements.items():
        script = script.replace(placeholder, value)
    require_true("<" not in script and ">" not in script, f"unreplaced synthesis placeholder for {top}")
    return script


def synthesize_top(top: str, expected_ports: Mapping[str, Tuple[str, int]]) -> dict:
    prefix = SCRATCH / top
    storage_path = prefix.with_name(prefix.name + "-storage.json")
    mapped_path = prefix.with_name(prefix.name + "-mapped.json")
    depth_before_path = prefix.with_name(prefix.name + "-depth-before.json")
    depth_after_path = prefix.with_name(prefix.name + "-depth-after.json")
    storage_script = instantiate_script(
        STORAGE_SCRIPT_TEMPLATE,
        top,
        {"<storage_json>": str(storage_path.relative_to(REPO))},
    )
    mapped_script = instantiate_script(
        MAPPED_SCRIPT_TEMPLATE,
        top,
        {"<mapped_json>": str(mapped_path.relative_to(REPO))},
    )
    depth_script = instantiate_script(
        DEPTH_SCRIPT_TEMPLATE,
        top,
        {
            "<mapped_json>": str(mapped_path.relative_to(REPO)),
            "<depth_before_json>": str(depth_before_path.relative_to(REPO)),
            "<depth_after_json>": str(depth_after_path.relative_to(REPO)),
        },
    )
    require_true("flatten" not in storage_script, f"flatten in storage script for {top}")
    require_true("flatten" not in mapped_script, f"flatten in mapped script for {top}")
    require_true(depth_script.split("flatten", 1)[1].strip() == f"; write_json {depth_after_path.relative_to(REPO)}; check -assert; ltp -noff", f"post-flatten command drift for {top}")
    run_yosys(storage_script, f"{top} storage-preserved synthesis")
    run_yosys(mapped_script, f"{top} mapped synthesis")
    depth_output = run_yosys(depth_script, f"{top} analysis-only depth")

    storage_data = strict_yosys_json(storage_path, f"{top} storage JSON")
    mapped_data = strict_yosys_json(mapped_path, f"{top} mapped JSON")
    before_data = strict_yosys_json(depth_before_path, f"{top} depth-before JSON")
    after_data = strict_yosys_json(depth_after_path, f"{top} depth-after JSON")
    validate_top_ports(storage_data, top, expected_ports)
    validate_top_ports(mapped_data, top, expected_ports)
    storage = analyze_yosys_graph(storage_data, top, f"{top} storage")
    mapped = analyze_yosys_graph(mapped_data, top, f"{top} mapped")
    before = analyze_yosys_graph(before_data, top, f"{top} depth-before")
    after = analyze_yosys_graph(after_data, top, f"{top} depth-after")
    require_equal(before["recursive_metrics"], mapped["recursive_metrics"], f"{top} mapped/depth-before metrics")
    require_equal(before["recursive_signatures"], mapped["recursive_signatures"], f"{top} mapped/depth-before primitives")
    require_equal(len(after["local"][top]["children"]), 0, f"{top} hierarchy remains after flatten")
    require_equal(after["recursive_metrics"], mapped["recursive_metrics"], f"{top} primitive metrics after flatten")
    require_equal(after["recursive_signatures"], mapped["recursive_signatures"], f"{top} primitive multiset after flatten")
    require_equal(after["recursive_types"], mapped["recursive_types"], f"{top} primitive types after flatten")
    depth = parse_depth(depth_output, top)
    return {
        "top": top,
        "storage": storage,
        "mapped": mapped,
        "before": before,
        "after": after,
        "depth": depth,
        "scripts": {
            "storage_preserved": storage_script,
            "mapped": mapped_script,
            "depth": depth_script,
        },
        "depth_preservation": {
            "primitive_metrics_identical": True,
            "primitive_type_multiset_identical": True,
            "primitive_signature_multiset_identical": True,
            "post_flatten_hierarchy_cells": 0,
            "loop_free": True,
            "parsed_depth_results": 1,
            "generic_abc_combinational_logic_levels": depth,
        },
    }


def expected_hierarchy_shape(result: Mapping, variant: Mapping) -> dict:
    analysis = result["mapped"]
    storage_id = variant["storage_id"]
    h4_id = variant["h4_id"]
    bases = {
        "top": variant["top"],
        "core": f"e256h_h2_{storage_id}_core",
        "protocol": "e256h_h2_protocol",
        "store": f"e256h_h2_{storage_id}_store",
        "round": f"e256h_h2_round_{h4_id}",
        "subbytes": "e256h_h2_subbytes",
        "mixcolumns": "e256h_h2_mixcolumns",
        "sbox": "e256h_h2_sbox",
    }
    modules = {role: find_reachable_module(analysis, base, variant["id"]) for role, base in bases.items()}
    expected_instances = {
        "top": 1,
        "core": 1,
        "protocol": 1,
        "store": 1,
        "round": 1,
        "subbytes": 1,
        "mixcolumns": 1,
        "sbox": 32,
    }
    for role, expected in expected_instances.items():
        require_equal(analysis["module_instances"][modules[role]], expected, f"{variant['id']} {role} instances")
    normalized_edges = {}
    reverse_roles = {module_name: role for role, module_name in modules.items()}
    for role, module_name in modules.items():
        edges = Counter()
        for child, multiplicity in analysis["local"][module_name]["children"].items():
            require_true(child in reverse_roles, f"{variant['id']} unknown hierarchy child {child}")
            child_role = reverse_roles[child]
            if child_role == "round":
                child_role = "round"
            edges[child_role] += multiplicity
        normalized_edges["core" if role == "core" else "round" if role == "round" else role] = {
            key: edges[key] for key in sorted(edges)
        }
    return {"modules": modules, "instance_multiplicities": expected_instances, "normalized_edges": normalized_edges}


def storage_accounting_record(result: Mapping, variant: Mapping, shape: Mapping) -> dict:
    storage = result["storage"]
    mapped = result["mapped"]
    storage_id = variant["storage_id"]
    h4_id = variant["h4_id"]
    store_module = find_reachable_module(storage, f"e256h_h2_{storage_id}_store", variant["id"] + " storage")
    core_module = find_reachable_module(storage, f"e256h_h2_{storage_id}_core", variant["id"] + " core")
    protocol_module = find_reachable_module(storage, "e256h_h2_protocol", variant["id"] + " protocol")
    store_metrics = storage["local"][store_module]["metrics"]
    core_metrics = storage["local"][core_module]["metrics"]
    protocol_metrics = storage["local"][protocol_module]["metrics"]
    require_equal(protocol_metrics["generic_sequential_bits"], 7, f"{variant['id']} protocol register bits")
    direct_bits = 12 if h4_id == "direct" else 0
    expected_core_bits = (1032 if storage_id == "mem" else 518) + direct_bits
    require_equal(core_metrics["generic_sequential_bits"], expected_core_bits, f"{variant['id']} core register bits")
    memory_detail = None
    if storage_id in ("ff", "ring"):
        require_equal(store_metrics["generic_sequential_bits"], MASK_BITS, f"{variant['id']} keyed FF bits")
        require_equal(store_metrics["generic_memory_bits"], 0, f"{variant['id']} keyed memory bits")
        keyed_sequential_bits = MASK_BITS
        keyed_memory_bits = 0
    else:
        require_equal(store_metrics["generic_sequential_bits"], 256, f"{variant['id']} synchronous memory read-output register bits")
        require_equal(store_metrics["generic_memory_bits"], MASK_BITS, f"{variant['id']} keyed memory bits")
        memory_detail = memory_cell_details(storage, store_module, variant["id"])
        keyed_sequential_bits = 0
        keyed_memory_bits = MASK_BITS
    require_equal(keyed_sequential_bits + keyed_memory_bits, MASK_BITS, f"{variant['id']} integrated mask accounting")
    require_equal(storage["recursive_metrics"]["generic_memory_bits"], keyed_memory_bits, f"{variant['id']} system memory bits")
    require_equal(mapped["recursive_metrics"]["generic_sequential_bits"], storage["recursive_metrics"]["generic_sequential_bits"], f"{variant['id']} mapped/storage sequential bits")
    require_equal(mapped["recursive_metrics"]["generic_memory_bits"], storage["recursive_metrics"]["generic_memory_bits"], f"{variant['id']} mapped/storage memory bits")

    state_bits = 256
    result_bits = 256
    protocol_bits = 7
    control_bits = 8 if storage_id == "mem" else 6
    input_hold_bits = 256 if storage_id == "mem" else 0
    memory_prefetch_register_bits = 256 if storage_id == "mem" else 0
    synchronous_read_output_bits = 256 if storage_id == "mem" else 0
    generic_categorized = (
        keyed_sequential_bits
        + state_bits
        + result_bits
        + protocol_bits
        + control_bits
        + direct_bits
        + input_hold_bits
        + memory_prefetch_register_bits
        + synchronous_read_output_bits
    )
    generic_total = storage["recursive_metrics"]["generic_sequential_bits"]
    require_equal(generic_categorized, generic_total, f"{variant['id']} generic sequential category sum")
    return {
        "variant": variant["id"],
        "storage_id": storage_id,
        "h2_eligible": variant["h2_eligible"],
        "logical_effective_mask_bits": MASK_BITS,
        "keyed_storage": {
            "sequential_bits": keyed_sequential_bits,
            "generic_memory_bits": keyed_memory_bits,
            "accounted_bits": keyed_sequential_bits + keyed_memory_bits,
            "module": store_module,
            "memory_cell": memory_detail,
        },
        "register_boundaries": {
            "state_bits": state_bits,
            "result_bits": result_bits,
            "protocol_bits": protocol_bits,
            "control_bits": control_bits,
            "direct_h4_bits": direct_bits,
            "input_hold_bits": input_hold_bits,
            "memory_prefetch_register_bits": memory_prefetch_register_bits,
            "memory_synchronous_read_output_register_bits": synchronous_read_output_bits,
            "memory_pipeline_logical_bits": memory_prefetch_register_bits + synchronous_read_output_bits,
            "generic_sequential_category_sum": generic_categorized,
            "generic_sequential_bits": generic_total,
            "unclassified_generic_sequential_bits": 0,
        },
        "storage_preserved_recursive_metrics": dict(storage["recursive_metrics"]),
        "mapped_recursive_metrics": dict(mapped["recursive_metrics"]),
        "hierarchy_shape": dict(shape),
        "wide_external_mask_port": False,
        "complete": True,
    }


def run_synthesis_and_accounting() -> Tuple[dict, dict, dict, Dict[str, dict]]:
    results: Dict[str, dict] = {}
    hierarchy_public = {}
    storage_records = {}
    measurements = {}
    shapes = {}
    for variant in PREREG_DATA["variants"]:
        result = synthesize_top(variant["top"], TOP_PORTS)
        results[variant["id"]] = result
        shape = expected_hierarchy_shape(result, variant)
        shapes[variant["id"]] = shape
        storage_record = storage_accounting_record(result, variant, shape)
        storage_records[variant["id"]] = storage_record
        metrics = dict(result["mapped"]["recursive_metrics"])
        metrics["generic_abc_combinational_logic_levels"] = result["depth"]
        measurements[variant["id"]] = {
            "top": variant["top"],
            "storage_id": variant["storage_id"],
            "h4_id": variant["h4_id"],
            "h2_eligible": variant["h2_eligible"],
            "metrics": metrics,
        }
        hierarchy_public[variant["id"]] = {
            "storage_preserved": result["storage"]["public"],
            "mapped": result["mapped"]["public"],
            "depth_before": result["before"]["public"],
            "depth_after": result["after"]["public"],
            "depth_preservation": result["depth_preservation"],
            "scripts": result["scripts"],
        }

    common_roles = ("protocol", "store", "subbytes", "mixcolumns", "sbox")
    paired_deltas = {}
    for storage_id in EXPECTED_STORAGE_IDS:
        fixed_id = f"{storage_id}_fixed"
        direct_id = f"{storage_id}_direct"
        fixed_shape = shapes[fixed_id]
        direct_shape = shapes[direct_id]
        require_equal(fixed_shape["normalized_edges"], direct_shape["normalized_edges"], f"{storage_id} fixed/direct normalized hierarchy")
        common_bases = {
            "protocol": "e256h_h2_protocol",
            "store": f"e256h_h2_{storage_id}_store",
            "subbytes": "e256h_h2_subbytes",
            "mixcolumns": "e256h_h2_mixcolumns",
            "sbox": "e256h_h2_sbox",
        }
        common_module_evidence = {}
        for role in common_roles:
            fixed_mapped_module = fixed_shape["modules"][role]
            direct_mapped_module = direct_shape["modules"][role]
            fixed_storage_module = find_reachable_module(
                results[fixed_id]["storage"], common_bases[role], f"{fixed_id} storage {role}"
            )
            direct_storage_module = find_reachable_module(
                results[direct_id]["storage"], common_bases[role], f"{direct_id} storage {role}"
            )
            fixed_storage_signatures = results[fixed_id]["storage"]["local"][fixed_storage_module]["signatures"]
            direct_storage_signatures = results[direct_id]["storage"]["local"][direct_storage_module]["signatures"]
            require_equal(
                fixed_storage_signatures,
                direct_storage_signatures,
                f"{storage_id} fixed/direct storage-preserved common module {role}",
            )
            fixed_mapped_metrics = results[fixed_id]["mapped"]["local"][fixed_mapped_module]["metrics"]
            direct_mapped_metrics = results[direct_id]["mapped"]["local"][direct_mapped_module]["metrics"]
            fixed_mapped_types = results[fixed_id]["mapped"]["local"][fixed_mapped_module]["primitive_types"]
            direct_mapped_types = results[direct_id]["mapped"]["local"][direct_mapped_module]["primitive_types"]
            common_module_evidence[role] = {
                "storage_preserved_primitive_signature_entries": sum(fixed_storage_signatures.values()),
                "storage_preserved_primitive_signature_multiset_sha256": counter_digest(fixed_storage_signatures),
                "mapped_fixed_metrics": dict(fixed_mapped_metrics),
                "mapped_direct_metrics": dict(direct_mapped_metrics),
                "mapped_direct_minus_fixed": {
                    key: direct_mapped_metrics[key] - fixed_mapped_metrics[key]
                    for key in METRIC_KEYS
                },
                "mapped_metrics_equal": fixed_mapped_metrics == direct_mapped_metrics,
                "mapped_fixed_primitive_type_multiset": {
                    primitive_type: fixed_mapped_types[primitive_type]
                    for primitive_type in sorted(fixed_mapped_types)
                },
                "mapped_direct_primitive_type_multiset": {
                    primitive_type: direct_mapped_types[primitive_type]
                    for primitive_type in sorted(direct_mapped_types)
                },
                "mapped_primitive_type_multisets_equal": fixed_mapped_types == direct_mapped_types,
            }
        fixed_metrics = measurements[fixed_id]["metrics"]
        direct_metrics = measurements[direct_id]["metrics"]
        delta = {key: direct_metrics[key] - fixed_metrics[key] for key in METRIC_KEYS + ("generic_abc_combinational_logic_levels",)}
        require_equal(delta["generic_sequential_bits"], 12, f"{storage_id} direct H4 register delta")
        require_equal(delta["generic_memory_bits"], 0, f"{storage_id} direct H4 memory delta")
        paired_deltas[storage_id] = {
            "direct_minus_fixed": delta,
            "non_h4_hierarchy_equal": True,
            "common_module_comparison": {
                "roles": common_module_evidence,
                "storage_preserved_primitive_signature_multisets_equal": True,
                "mapped_metric_vectors_recorded": True,
                "mapped_primitive_type_multisets_recorded": True,
                "cross_run_mapped_metric_or_signature_equality_required": False,
                "within_top_mapped_flatten_signature_equality_required": True,
                "policy": "separate ABC runs may choose different mapped costs and LUT decompositions for identical storage-preserved modules; record those artifacts without treating them as a non-H4 graph change",
            },
            "storage_selection": None,
        }

    external_result = synthesize_top(EXTERNAL_TOP, EXTERNAL_PORTS)
    external = external_result["storage"]
    store_matches = [
        module_name
        for module_name in external["reachable"]
        if any(
            module_matches_base(module_name, f"e256h_h2_{storage_id}_store")
            for storage_id in EXPECTED_STORAGE_IDS
        )
    ]
    require_equal(store_matches, [], "externalized control integrated store modules")
    require_equal(external["recursive_metrics"]["generic_memory_bits"], 0, "externalized control memory bits")
    require_equal(len(external["modules"][EXTERNAL_TOP]["ports"]["mask_words"]["bits"]), MASK_BITS, "externalized live mask port width")
    external_record = {
        "top": EXTERNAL_TOP,
        "live_mask_input_bits": MASK_BITS,
        "integrated_keyed_storage_bits": 0,
        "integrated_store_modules": [],
        "accepted_as_h2_result": False,
        "rejection": "complete effective-mask schedule is a live external input",
        "detected": True,
    }

    hierarchy_accounting = {
        "classification": {
            "accepted_coarse_sequential_types": sorted(COARSE_SEQUENTIAL_TYPES),
            "accepted_fine_sequential_pattern": FINE_SEQUENTIAL_RE.pattern,
            "accepted_memory_type": MEMORY_TYPE,
            "ignored_nonhardware_metadata_cell_types": sorted(
                IGNORED_METADATA_CELL_TYPES
            ),
            "normalized_nonfunctional_cell_parameters": {
                "$mem_v2": ["MEMID"]
            },
            "latches_forbidden": True,
            "unclassified_sequential_or_memory_cells": 0,
            "memory_capacity_rule": "WIDTH*SIZE",
        },
        "variants": hierarchy_public,
        "all_recursive_expansions_close": True,
        "all_hierarchies_acyclic": True,
        "all_postmap_primitive_multisets_preserved": True,
    }
    storage_accounting = {
        "logical_effective_mask_bits": MASK_BITS,
        "variants": storage_records,
        "paired_fixed_direct": paired_deltas,
        "externalized_storage_control": external_record,
        "all_integrated_boundaries_complete": True,
        "production_storage_selection": None,
    }
    measurement_payload = {
        "generic_boundary": PREREG_DATA["synthesis_contract"]["generic_boundary"],
        "variants": measurements,
        "paired_fixed_direct_deltas": paired_deltas,
        "production_architecture_selected": False,
    }
    return hierarchy_accounting, storage_accounting, measurement_payload, results


# ---------------------------------------------------------------------------
# Synthetic hierarchy controls, prediction grading, and receipt construction.


def synthetic_hierarchy_controls() -> Tuple[dict, dict]:
    synthetic = {
        "leaf": {
            "metrics": {
                "generic_abc_lut6": 2,
                "generic_sequential_bits": 0,
                "generic_memory_bits": 0,
                "generic_primitive_cells": 2,
            },
            "children": Counter(),
        },
        "middle": {
            "metrics": {
                "generic_abc_lut6": 0,
                "generic_sequential_bits": 3,
                "generic_memory_bits": 0,
                "generic_primitive_cells": 1,
            },
            "children": Counter({"leaf": 2}),
        },
        "top": {
            "metrics": {
                "generic_abc_lut6": 0,
                "generic_sequential_bits": 0,
                "generic_memory_bits": 5,
                "generic_primitive_cells": 1,
            },
            "children": Counter({"middle": 3, "leaf": 1}),
        },
    }

    def recursive(name: str, active: Set[str], memo: MutableMapping[str, Dict[str, int]]) -> Dict[str, int]:
        if name in memo:
            return memo[name]
        require_true(name not in active, "synthetic hierarchy cycle")
        active.add(name)
        metrics = dict(synthetic[name]["metrics"])
        for child, multiplicity in synthetic[name]["children"].items():
            metrics = add_metrics(metrics, recursive(child, active, memo), multiplicity)
        active.remove(name)
        memo[name] = metrics
        return metrics

    recursive_metrics = recursive("top", set(), {})
    expected = {
        "generic_abc_lut6": 14,
        "generic_sequential_bits": 9,
        "generic_memory_bits": 5,
        "generic_primitive_cells": 18,
    }
    require_equal(recursive_metrics, expected, "synthetic nested multiplicity totals")
    expanded = zero_metrics()
    stack = ["top"]
    while stack:
        name = stack.pop()
        expanded = add_metrics(expanded, synthetic[name]["metrics"])
        for child, multiplicity in synthetic[name]["children"].items():
            stack.extend([child] * multiplicity)
    require_equal(expanded, expected, "synthetic expanded totals")

    duplicate = add_metrics(expected, recursive("middle", set(), {}))
    require_true(duplicate != expanded, "duplicate-child mutation was not detected")
    nested_record = {
        "synthetic_child_multiplicities": {
            "top": {"leaf": 1, "middle": 3},
            "middle": {"leaf": 2},
            "leaf": {},
        },
        "expected_recursive_metrics": expected,
        "observed_recursive_metrics": recursive_metrics,
        "independent_expanded_metrics": expanded,
        "detected": True,
    }
    duplicate_record = {
        "mutation": "add the middle child contribution once after correct recursion",
        "correct_metrics": expanded,
        "mutated_metrics": duplicate,
        "mismatch_metrics": [key for key in METRIC_KEYS if duplicate[key] != expanded[key]],
        "detected": True,
    }
    return nested_record, duplicate_record


def assemble_controls(
    rtl_records: Mapping[str, dict],
    hierarchy: Mapping,
    storage: Mapping,
    synthetic_nested: Mapping,
    synthetic_duplicate: Mapping,
) -> dict:
    records = dict(rtl_records)
    records["externalized_storage"] = storage["externalized_storage_control"]
    records["nested_child_multiplicity"] = dict(synthetic_nested)
    records["duplicate_child_accounting"] = dict(synthetic_duplicate)
    depth_variants = {
        variant_id: hierarchy["variants"][variant_id]["depth_preservation"]
        for variant_id in EXPECTED_VARIANT_IDS
    }
    require_true(
        all(
            record["primitive_signature_multiset_identical"]
            and record["parsed_depth_results"] == 1
            and record["loop_free"]
            for record in depth_variants.values()
        ),
        "postmap depth preservation control failed",
    )
    records["postmap_depth_preservation"] = {
        "variants": depth_variants,
        "detected": True,
    }
    ordered = {identifier: records[identifier] for identifier in EXPECTED_CONTROL_IDS}
    require_equal(tuple(ordered), EXPECTED_CONTROL_IDS, "assembled control IDs")
    require_true(all(record["detected"] is True for record in ordered.values()), "one or more controls were not detected")
    return {
        "frozen_ids": list(EXPECTED_CONTROL_IDS),
        "executed_ids": list(ordered),
        "records": ordered,
        "all_detected": True,
    }


def grade_predictions(
    functional: Mapping,
    controls: Mapping,
    hierarchy: Mapping,
    storage: Mapping,
    measurements: Mapping,
    cycles: Mapping,
) -> dict:
    statements = {item["id"]: item for item in PREREG_DATA["predictions"]}
    recursive_local_differences = {}
    for variant_id in EXPECTED_VARIANT_IDS:
        mapped = hierarchy["variants"][variant_id]["mapped"]
        top = mapped["top"]
        local_metrics = mapped["local_modules"][top]["metrics"]
        recursive_metrics = mapped["recursive_metrics"]
        different = local_metrics != recursive_metrics
        require_true(different, f"{variant_id} recursive total did not differ from local top")
        recursive_local_differences[variant_id] = different
    cycle_pass = (
        cycles["variant_input_sets_exact"]
        and cycles["per_input_ready_window_checked"]
        and cycles["executed_cycle_observations"]
        == cycles["expected_cycle_observations"]
        and all(
            cycles["variants"][variant_id]["latency_set"]
            == [cycles["variants"][variant_id]["latency_cycles"]]
            and cycles["variants"][variant_id]["initiation_interval_set"]
            == [cycles["variants"][variant_id]["initiation_interval_cycles"]]
            and cycles["variants"][variant_id]["latency_observation_count"]
            == cycles["variants"][variant_id]["initiation_interval_observation_count"]
            and cycles["variants"][variant_id]["input_independent"]
            for variant_id in EXPECTED_VARIANT_IDS
        )
    )
    outcomes = {
        "H2P1": {
            "role": statements["H2P1"]["role"],
            "statement": statements["H2P1"]["statement"],
            "observed": {
                "variants": len(EXPECTED_VARIANT_IDS),
                "rtl_rows": functional["executed_rtl_rows"],
                "model_comparisons": functional["executed_total_rtl_model_comparisons"],
                "controls": len(controls["executed_ids"]),
            },
            "pass": functional["all_byte_exact"] and controls["all_detected"],
        },
        "H2P2": {
            "role": statements["H2P2"]["role"],
            "statement": statements["H2P2"]["statement"],
            "observed": {
                "all_recursive_expansions_close": hierarchy["all_recursive_expansions_close"],
                "duplicate_child_control_detected": controls["records"]["duplicate_child_accounting"]["detected"],
            },
            "pass": hierarchy["all_recursive_expansions_close"] and controls["records"]["duplicate_child_accounting"]["detected"],
        },
        "H2P3": {
            "role": statements["H2P3"]["role"],
            "statement": statements["H2P3"]["statement"],
            "observed": {variant_id: storage["variants"][variant_id]["keyed_storage"]["accounted_bits"] for variant_id in EXPECTED_VARIANT_IDS},
            "pass": storage["all_integrated_boundaries_complete"],
        },
        "H2P4": {
            "role": statements["H2P4"]["role"],
            "statement": statements["H2P4"]["statement"],
            "observed": {variant_id: measurements["variants"][variant_id]["metrics"]["generic_abc_combinational_logic_levels"] for variant_id in EXPECTED_VARIANT_IDS},
            "pass": hierarchy["all_postmap_primitive_multisets_preserved"],
        },
        "H2P5": {
            "role": statements["H2P5"]["role"],
            "statement": statements["H2P5"]["statement"],
            "observed": cycles["variants"],
            "pass": cycle_pass,
        },
        "H2P6": {
            "role": statements["H2P6"]["role"],
            "statement": statements["H2P6"]["statement"],
            "observed": {"raw_bits": 9472, "effective_bits": MASK_BITS, "difference_bits": 6144},
            "pass": 9472 - MASK_BITS == 6144,
        },
        "H2P7": {
            "role": statements["H2P7"]["role"],
            "statement": statements["H2P7"]["statement"],
            "observed": measurements["paired_fixed_direct_deltas"],
            "pass": all(pair["direct_minus_fixed"]["generic_sequential_bits"] == 12 for pair in measurements["paired_fixed_direct_deltas"].values()),
        },
        "H2P8": {
            "role": statements["H2P8"]["role"],
            "statement": statements["H2P8"]["statement"],
            "observed": {
                "storage_ids": list(EXPECTED_STORAGE_IDS),
                "metrics_measured": list(METRIC_KEYS) + ["generic_abc_combinational_logic_levels"],
                "production_storage_selection": None,
            },
            "pass": set(record["storage_id"] for record in measurements["variants"].values()) == set(EXPECTED_STORAGE_IDS),
        },
        "H2P9": {
            "role": statements["H2P9"]["role"],
            "statement": statements["H2P9"]["statement"],
            "observed": recursive_local_differences,
            "pass": all(recursive_local_differences.values()),
        },
    }
    require_equal(tuple(outcomes), EXPECTED_PREDICTION_IDS, "prediction outcome IDs")
    require_true(all(outcome["pass"] for outcome in outcomes.values()), "one or more predictions failed")
    validity_ids = tuple(item["id"] for item in PREREG_DATA["predictions"] if item["role"] == "validity_control")
    require_equal(validity_ids, EXPECTED_PREDICTION_IDS[:5], "validity prediction IDs")
    return {
        "frozen_ids": list(EXPECTED_PREDICTION_IDS),
        "executed_ids": list(outcomes),
        "validity_control_ids": list(validity_ids),
        "validity_controls_pass": True,
        "all_predictions_pass": True,
        "outcomes": outcomes,
    }


def cycle_payload(functional: Mapping) -> dict:
    variants = {}
    for variant in PREREG_DATA["variants"]:
        identifier = variant["id"]
        latency = variant["latency_cycles"]
        interval = variant["initiation_interval_cycles"]
        observation_count = functional["executed_cycle_observations_per_variant"][identifier]
        input_independent = (
            observation_count
            == functional["expected_cycle_observations_per_variant"][identifier]
            and functional["latency_singleton_sets"][identifier] == [latency]
            and functional["initiation_interval_singleton_sets"][identifier]
            == [interval]
        )
        variants[identifier] = {
            "latency_cycles": latency,
            "latency_set": functional["latency_singleton_sets"][identifier],
            "latency_observation_count": observation_count,
            "initiation_interval_cycles": interval,
            "initiation_interval_set": functional["initiation_interval_singleton_sets"][identifier],
            "initiation_interval_observation_count": observation_count,
            "input_set_sha256": functional["variant_input_set_sha256"][identifier],
            "blocks_per_cycle": {"numerator": 1, "denominator": interval},
            "bytes_per_cycle": {"numerator": 32, "denominator": interval},
            "input_independent": input_independent,
        }
    expected_total = sum(functional["expected_cycle_observations_per_variant"].values())
    executed_total = sum(functional["executed_cycle_observations_per_variant"].values())
    require_equal(executed_total, expected_total, "total per-input cycle observations")
    require_true(all(record["input_independent"] for record in variants.values()), "per-input cycle singleton sets")
    return {
        "stimulus_rule": PREREG_DATA["protocol_contract"]["stimulus_rule"],
        "earliest_reacceptance_basis": "for every executed input, ready remained low while busy and rose with done; the earliest next acceptance edge is one cycle after that observed completion",
        "expected_cycle_observations": expected_total,
        "executed_cycle_observations": executed_total,
        "variant_input_sets_exact": functional["variant_input_sets_exact"],
        "per_input_ready_window_checked": functional["per_input_ready_window_checked"],
        "variants": variants,
        "timing_or_fmax_claim": False,
    }


def git_advisory(elapsed: float) -> dict:
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
        "elapsed_seconds": round(elapsed, 3),
        "git_head": head.splitlines()[0] if head_ok and head else "unavailable",
        "git_dirty": bool(status) if status_ok else "unavailable",
    }


def build_receipt() -> dict:
    started = time.perf_counter()
    inputs, certified = validate_frozen_inputs()
    materials = derive_materials()
    blocks = derive_blocks()
    configurations = build_configurations(certified, materials)
    prepare_scratch()
    sbox_semantic = run_sbox_semantic_check()
    write_main_vectors(configurations, blocks)
    rows, protocol_evidence = run_main_simulation(configurations, blocks)
    functional = grade_functional(rows, configurations, blocks)
    functional["sbox_semantic_bridge"] = sbox_semantic
    cycles = cycle_payload(functional)
    rtl_control_records = run_rtl_controls(configurations, blocks, protocol_evidence)
    hierarchy, storage, measurements, _synthesis_results = run_synthesis_and_accounting()
    nested_control, duplicate_control = synthetic_hierarchy_controls()
    controls = assemble_controls(
        rtl_control_records,
        hierarchy,
        storage,
        nested_control,
        duplicate_control,
    )
    predictions = grade_predictions(
        functional, controls, hierarchy, storage, measurements, cycles
    )

    material_records = [
        {
            "id": material["id"],
            "domain": material["domain"],
            "raw_bytes": len(material["raw"]),
            "raw_sha256": material["raw_sha256"],
        }
        for material in materials
    ]
    block_records = [
        {"id": identifier, "bytes_hex": block.hex()} for identifier, block in blocks
    ]
    coverage = {
        "variant_ids": list(EXPECTED_VARIANT_IDS),
        "top_modules": list(EXPECTED_TOPS),
        "storage_ids": list(EXPECTED_STORAGE_IDS),
        "h4_ids": list(EXPECTED_H4_IDS),
        "h4_set_size": len(certified),
        "h4_set_sha256": sha256_bytes(canonical_json_bytes(certified)),
        "material_ids": list(EXPECTED_MATERIAL_IDS),
        "block_ids": list(EXPECTED_BLOCK_IDS),
        "configuration_count": len(configurations),
        "rtl_rows": len(rows),
        "variant_rtl_outputs": functional["executed_variant_rtl_outputs"],
        "cycle_observations": cycles["executed_cycle_observations"],
        "exhaustive_sbox_inputs": sbox_semantic["input_count"],
        "exhaustive_sbox_sha256": sbox_semantic["output_table_sha256"],
        "control_ids": list(controls["executed_ids"]),
        "prediction_ids": list(predictions["executed_ids"]),
        "synthesized_graded_tops": list(EXPECTED_TOPS),
        "externalized_control_top": EXTERNAL_TOP,
        "exact_sets": True,
    }
    pinned_parameters = {
        "date_basis": PREREG_DATA["date_basis"],
        "graded_constraints": list(EXPECTED_GRADED_CONSTRAINTS),
        "question_ids": list(EXPECTED_QUESTION_IDS),
        "identity": PREREG_DATA["construction"]["identity"],
        "measurement_rounds": ROUNDS,
        "state_bytes": STATE_BYTES,
        "geometry": PREREG_DATA["construction"]["geometry"],
        "canonical_recurrence": PREREG_DATA["construction"]["canonical_recurrence"],
        "linear_layer": PREREG_DATA["construction"]["linear_layer"],
        "mix_columns_matrix_hex_rows": PREREG_DATA["construction"]["mix_columns_matrix_hex_rows"],
        "effective_mask_words": MASK_WORDS,
        "effective_mask_bits": MASK_BITS,
        "terminal_rule": PREREG_DATA["construction"]["effective_masks"]["terminal_rule"],
        "raw_h3_bits": 9472,
        "representation_kernel_bits": 6144,
        "fixed_h4_tuple": list(FIXED_H4),
        "direct_h4_state_bits": 12,
        "configuration_order": "certified H4 receipt order, then material preregistration order",
        "aggregate_encoding": AGGREGATE_ENCODING,
        "material_sets": material_records,
        "block_corpus": block_records,
        "block_corpus_sha256": sha256_bytes(b"".join(block for _identifier, block in blocks)),
        "compatibility_rule": PREREG_DATA["construction"]["compatibility_rule"],
        "production_round_count": None,
        "production_xof": None,
        "production_h4_switching_policy": None,
        "production_storage_selection": None,
        "production_suite": None,
        "production_profile": None,
        "production_fixture": None,
        "production_protocol": None,
        "security_bits": None,
    }
    harness_checks = {
        "frozen_inputs_validated": True,
        "memory_nomap_supported_before_measurement": True,
        "functional_coverage_exact": functional["exact_execution_sets"],
        "functional_values_byte_exact": functional["all_byte_exact"],
        "tableless_sbox_semantic_bridge_exact": sbox_semantic["byte_exact"],
        "all_controls_detected": controls["all_detected"],
        "recursive_hierarchy_accounting_closed": hierarchy["all_recursive_expansions_close"],
        "integrated_storage_boundaries_complete": storage["all_integrated_boundaries_complete"],
        "postmap_depth_preserved": hierarchy["all_postmap_primitive_multisets_preserved"],
        "cycle_sets_exact": predictions["outcomes"]["H2P5"]["pass"],
        "all_predictions_pass": predictions["all_predictions_pass"],
    }
    require_true(all(harness_checks.values()), "H2 harness validity check failed")
    deterministic_payload = {
        "schema": PREREG_DATA["receipt_contract"]["schema"],
        "status": PREREG_DATA["receipt_contract"]["status"],
        "inputs": inputs,
        "pinned_parameters": pinned_parameters,
        "coverage": coverage,
        "functional": functional,
        "controls": controls,
        "hierarchy_accounting": hierarchy,
        "storage_accounting": storage,
        "measurements": measurements,
        "cycles": cycles,
        "predictions": predictions,
        "interpretation": {
            "harness_validity_checks": harness_checks,
            "harness_valid": True,
            "verdict": VALID_VERDICT,
            "scope": PREREG_DATA["interpretation"]["scope"],
            "passing_interpretation": PREREG_DATA["interpretation"]["passing_interpretation"],
            "next": PREREG_DATA["interpretation"]["next"],
            "internal_invalid_status_not_emitted": INVALID_STATUS,
            "claim_movement": False,
            "production_decisions": {
                "round_count": None,
                "xof": None,
                "direct_short_schedule": None,
                "h4_switching_policy": None,
                "storage": None,
                "suite": None,
                "profile": None,
                "fixture": None,
                "protocol": None,
                "production_rtl": None,
                "security_bits": None,
            },
            "generic_measurements_only": True,
            "production_architecture_selected": False,
        },
        "limitations": list(PREREG_DATA["non_claims"]),
    }
    require_equal(tuple(deterministic_payload), EXPECTED_PAYLOAD_KEYS, "built payload key order")
    validate_deterministic_types(deterministic_payload)
    require_equal(deterministic_payload["status"], "OPEN_PROGRESS", "built status")
    require_equal(deterministic_payload["interpretation"]["verdict"], VALID_VERDICT, "built verdict")
    require_equal(deterministic_payload["interpretation"]["claim_movement"], False, "claim movement")
    digest = sha256_bytes(canonical_json_bytes(deterministic_payload))
    receipt = {
        "deterministic_payload": deterministic_payload,
        "deterministic_payload_sha256": digest,
        "environment_advisory_excluded_from_digest": git_advisory(
            time.perf_counter() - started
        ),
        "no_wall_clock": NO_WALL_CLOCK,
    }
    require_equal(tuple(receipt), OUTER_RECEIPT_KEYS, "outer receipt key order")
    require_equal(tuple(receipt["environment_advisory_excluded_from_digest"]), ADVISORY_KEYS, "advisory key order")
    return receipt


def validate_stored_receipt(receipt: Mapping) -> None:
    require_exact_keys(receipt, OUTER_RECEIPT_KEYS, "stored outer receipt")
    payload = receipt["deterministic_payload"]
    require_exact_keys(payload, EXPECTED_PAYLOAD_KEYS, "stored deterministic payload")
    validate_deterministic_types(payload)
    require_equal(payload.get("schema"), "E256-HARDWARE-H2-GATE-1", "stored schema")
    require_equal(payload.get("status"), "OPEN_PROGRESS", "stored status")
    require_equal(payload.get("interpretation", {}).get("harness_valid"), True, "stored harness validity")
    require_equal(payload.get("interpretation", {}).get("verdict"), VALID_VERDICT, "stored verdict")
    require_equal(payload.get("interpretation", {}).get("claim_movement"), False, "stored claim movement")
    production = payload.get("interpretation", {}).get("production_decisions")
    require_true(isinstance(production, dict) and all(value is None for value in production.values()), "stored production decisions are not all null")
    digest = receipt["deterministic_payload_sha256"]
    require_true(type(digest) is str and re.fullmatch(r"[0-9a-f]{64}", digest) is not None, "stored digest grammar")
    require_equal(sha256_bytes(canonical_json_bytes(payload)), digest, "stored payload digest")
    advisory = receipt["environment_advisory_excluded_from_digest"]
    require_exact_keys(advisory, ADVISORY_KEYS, "stored advisory")
    require_true(type(advisory["platform"]) is str, "stored advisory platform")
    require_true(type(advisory["elapsed_seconds"]) in (int, float) and math.isfinite(advisory["elapsed_seconds"]), "stored advisory elapsed seconds")
    require_true(type(advisory["git_head"]) is str, "stored advisory git head")
    require_true(type(advisory["git_dirty"]) in (bool, str), "stored advisory git dirty")
    require_equal(receipt["no_wall_clock"], NO_WALL_CLOCK, "stored no-wall-clock text")


def atomic_write(path: Path, data: bytes) -> None:
    require_true(path.parent.is_dir(), f"receipt parent directory does not exist: {path.parent}")
    temporary = path.with_name(path.name + ".tmp")
    try:
        temporary.write_bytes(data)
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def check_prior_receipt(path: Path, current: Mapping) -> bool:
    require_true(path.is_file(), f"prior receipt does not exist: {path.relative_to(REPO)}")
    prior = strict_json_load(path)
    validate_stored_receipt(prior)
    prior_payload_bytes = canonical_json_bytes(prior["deterministic_payload"])
    current_payload_bytes = canonical_json_bytes(current["deterministic_payload"])
    prior_digest = prior["deterministic_payload_sha256"]
    current_digest = current["deterministic_payload_sha256"]
    require_equal(prior_payload_bytes, current_payload_bytes, "reproduced canonical payload bytes")
    require_equal(prior_digest, current_digest, "reproduced payload digest")
    print("reproducibility: prior_digest_valid=True payload_bytes_match=True digest_match=True")
    return True


def print_summary(receipt: Mapping) -> None:
    payload = receipt["deterministic_payload"]
    print("=" * 78)
    print("E256-H H2 INTEGRATED COST GATE  (OPEN_PROGRESS)")
    print("=" * 78)
    print(f"harness valid: {payload['interpretation']['harness_valid']}")
    print(
        "functional: "
        f"{payload['functional']['executed_rtl_rows']} rows, "
        f"{payload['functional']['executed_total_rtl_model_comparisons']} graded model comparisons, "
        "0 mismatches"
    )
    print(
        "cross-variant: "
        f"{payload['functional']['executed_storage_equivalence_comparisons']} storage comparisons, "
        f"{payload['functional']['executed_fixed_direct_bridge_comparisons']} bridges"
    )
    print(f"controls: {len(payload['controls']['executed_ids'])}/12 detected")
    print(f"{'variant':<14}{'LUT6':>10}{'seq bits':>12}{'mem bits':>12}{'cells':>12}{'levels':>10}")
    for variant_id in EXPECTED_VARIANT_IDS:
        metrics = payload["measurements"]["variants"][variant_id]["metrics"]
        print(
            f"{variant_id:<14}"
            f"{metrics['generic_abc_lut6']:>10}"
            f"{metrics['generic_sequential_bits']:>12}"
            f"{metrics['generic_memory_bits']:>12}"
            f"{metrics['generic_primitive_cells']:>12}"
            f"{metrics['generic_abc_combinational_logic_levels']:>10}"
        )
    print(f"verdict: {payload['interpretation']['verdict']}")
    print("NOTE: generic non-production measurements; no architecture selected")
    print(f"deterministic_payload_sha256: {receipt['deterministic_payload_sha256']}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Run or reproduce-check the frozen non-production E256-H H2 "
            "integrated-core cost gate."
        )
    )
    parser.add_argument("--check", action="store_true", help="rerun every obligation and require byte-identical deterministic payload")
    parser.add_argument("--json", default=str(RECEIPT.relative_to(REPO)), help="receipt path relative to the repository")
    args = parser.parse_args()
    output = REPO / args.json

    try:
        receipt = build_receipt()
        require_equal(receipt["deterministic_payload"]["interpretation"]["harness_valid"], True, "final harness validity")
        print_summary(receipt)
        if args.check:
            check_prior_receipt(output, receipt)
            print("CHECK PASS")
            return 0
        atomic_write(
            output,
            json.dumps(receipt, indent=2, sort_keys=True, allow_nan=False).encode("utf-8")
            + b"\n",
        )
        print(f"wrote {output.relative_to(REPO)}")
        print(
            "STATUS: OPEN_PROGRESS; no C/H/N row, production architecture, "
            "round count, schedule, H4 policy, suite, profile, fixture, protocol, "
            "security value, or production RTL moved"
        )
        return 0
    except Exception as error:
        print(f"H2 GATE FAILED: {error}", file=sys.stderr)
        print(
            "No canonical receipt was emitted or accepted; status remains "
            "OPEN_PROGRESS.",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    sys.exit(main())
