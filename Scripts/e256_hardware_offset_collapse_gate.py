#!/usr/bin/env python3
"""Confirm the E256-H H3 XOR-offset material normal form.

This OPEN_PROGRESS research gate checks the frozen offset-collapse contract with
three independent paths: exhaustive deterministic software coverage, two
unchanged sequential RTL evaluators, and an arbitrary-input compositional Yosys
SAT lemma over the complete H4 linear layer with three planted mutations.

Contract:  directives/e256-hardware-offset-collapse-preregistration.json
Receipt:   logs/e256-hardware-offset-collapse-gate.json
Miter:     Hardware/RTL/Research/E256H/e256h_offset_collapse_miter.v
Testbench: Hardware/Testbenches/Research/E256H/e256h_offset_collapse_tb.v

The gate confirms a representation identity only.  It does not select rounds,
a schedule, a suite, a profile, a protocol, production RTL, or a security level.
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
from pathlib import Path
from typing import Dict, List, Mapping, Sequence, Tuple

REPO = Path(__file__).resolve().parent.parent
PREREG = REPO / "directives/e256-hardware-offset-collapse-preregistration.json"
ARCHITECTURE = REPO / "directives/e256-hardware-architecture.md"
FROZEN_RTL = REPO / "Hardware/RTL/Research/E256H/e256h_attack_core.v"
FROZEN_TESTBENCH = REPO / "Hardware/Testbenches/Research/E256H/e256h_attack_core_tb.v"
FROZEN_RUNNER = REPO / "Scripts/e256_hardware_attack_gate.py"
MITER = REPO / "Hardware/RTL/Research/E256H/e256h_offset_collapse_miter.v"
TESTBENCH = REPO / "Hardware/Testbenches/Research/E256H/e256h_offset_collapse_tb.v"
RECEIPT = REPO / "logs/e256-hardware-offset-collapse-gate.json"
SCRATCH = REPO / "build/e256h-offset-collapse"

PREREG_SHA256 = "3d7a12731fcf81f6120577122c55bd8ec25589a82226d49fab7e5b8350ee0cee"
ARCHITECTURE_CONTRACT_SHA256 = (
    "b64472f73be9d0fc6318ff445c5f550cb0129309313228f416599c27d3957bb1"
)
AES_SBOX_SHA256 = "c2d8e5eed6cbebd8625fc18f81486a7733c04f9b0129ffbe974c68b90308b4f2"
CERTIFIED_H4_SET_SHA256 = (
    "199f1f7bddccf19ce5aa0bde0987441735d628354140d53ebdfec538d7b3f5ed"
)
FROZEN_MATERIAL_SHA256 = (
    "b6738e7f117bb7b916ee002db482f105a3eb5a046ee84dff45f178510cdeb691"
)
FORMAL_DECOMPOSITION_SUPERSEDED_PREREG_SHA256 = (
    "3823e2632a6b2a38264a7c6d4630cafcda457a711c0f0fdf275c00d1698a23a2"
)
SUPERSEDED_PREREG_SHA256 = (
    "ef369bf4356ba938c0da847f8a5b3244104fc47427bf1ad03aa78df36fcbf74e"
)

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
)

FROZEN_SOURCE_HASHES = {
    "rtl": "f4b5d6210275d831e48a3b16ca0457fa0927164ab33853b466ae0ca326fbcd3b",
    "testbench": "ae9d35af3edb76a696249dd4c32b8a3816c7a06643efbbf8f1397409a8b9ee2b",
    "runner": "6928516545363269fd3c36224ab0013779bb14068336493a068eeb4ce9d077c2",
}

EXPECTED_GRADED_CONSTRAINTS = ("H1", "H2", "H3", "H4", "H5")
EXPECTED_QUESTION_IDS = ("HQ13", "HQ14", "HQ15", "HQ16")
EXPECTED_MATERIAL_IDS = ("frozen_attack_v1", "collapse_aux_0", "collapse_aux_1")
EXPECTED_CONTROL_IDS = (
    "omit_output_transport",
    "raw_output_offset",
    "wrong_transport_source",
    "terminal_input_offset_included",
    "wrong_mask_index",
    "non_absorbable_bit_permutation",
)
EXPECTED_PREDICTION_IDS = ("OC1", "OC2", "OC3", "OC4", "OC5", "OC6")
EXPECTED_ROUNDS = tuple(range(1, 13))
EXPECTED_RTL_ROUNDS = tuple(range(1, 9))
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
EXPECTED_FORMAL_MODES = (
    "correct",
    "omit_output_transport",
    "raw_output_offset",
    "wrong_transport_source",
)
EXPECTED_PAYLOAD_KEYS = (
    "schema",
    "status",
    "inputs",
    "pinned_parameters",
    "coverage",
    "controls",
    "equivalence",
    "material_normal_form",
    "interpretation",
    "limitations",
)
VALID_VERDICTS = (
    "H3_XOR_OFFSETS_EXACTLY_COLLAPSE_TO_EFFECTIVE_MASKS",
    "H3_XOR_OFFSET_COLLAPSE_NOT_CONFIRMED",
)

STATE_BYTES = 32
MATERIAL_BYTES = 1184
MATERIAL_MASK_BASE = 768
RAW_OFFSET_BYTES = 768
MASK_BYTES_12 = 416
STAGE_A_BYTES_12 = 800
STAGE_B_BYTES_12 = 416
STAGE_B_BYTES_8 = 288
FIXED_H4 = (0, 1, 3, 4)
SHAKE256_RATE_BYTES = 136
SOFTWARE_COMPARISONS_PER_STAGE = 384 * 3 * 12 * 8
RTL_COMPARISONS = 8 * 8
AGGREGATE_ENCODING = (
    "For each record in frozen nested-loop order, append a 4-byte unsigned "
    "big-endian length followed by compact canonical UTF-8 JSON. State outputs "
    "are 32 bytes in ascending byte-index order encoded as 64 lowercase hex "
    "characters."
)

PREREG_DATA = json.loads(PREREG.read_text(encoding="utf-8"))
CONSTRUCTION = PREREG_DATA["construction"]
MIX_ROWS = tuple(
    tuple(int(value, 16) for value in row)
    for row in CONSTRUCTION["mix_columns_matrix_hex_rows"]
)

FORMAL_TOPS = {
    "correct": "e256h_offset_collapse_correct",
    "omit_output_transport": "e256h_offset_collapse_omit_output_transport",
    "raw_output_offset": "e256h_offset_collapse_raw_output_offset",
    "wrong_transport_source": "e256h_offset_collapse_wrong_transport_source",
}
FORMAL_INPUT_SIGNALS = {
    "correct": ("U", "B", "M"),
    "omit_output_transport": ("U", "B", "M"),
    "raw_output_offset": ("U", "B", "M"),
    "wrong_transport_source": ("U", "A", "B", "M"),
}
FORMAL_INPUT_BITS = {
    mode: 256 * len(signals) for mode, signals in FORMAL_INPUT_SIGNALS.items()
}


class StructuralValidationError(AssertionError):
    """Contract, tool, coverage, or validity failure; never emit a receipt."""


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def canonical_json_bytes(value) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")


def require_equal(actual, expected, label: str) -> None:
    if actual != expected:
        raise StructuralValidationError(
            f"{label} mismatch: expected {expected!r}, got {actual!r}"
        )


def require_true(condition: bool, label: str) -> None:
    if not condition:
        raise StructuralValidationError(label)


def update_record_hash(hasher, record: Mapping) -> None:
    encoded = canonical_json_bytes(record)
    hasher.update(len(encoded).to_bytes(4, "big"))
    hasher.update(encoded)


# ---------------------------------------------------------------------------
# Independent byte-oriented model.


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


def ror8(value: int, amount: int) -> int:
    amount %= 8
    return ((value >> amount) | (value << (8 - amount))) & 0xFF


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
    if not states or any(len(state) != STATE_BYTES for state in states):
        raise StructuralValidationError("state XOR received a non-32-byte operand")
    output = [0] * STATE_BYTES
    for state in states:
        for index, value in enumerate(state):
            output[index] ^= int(value)
    return output


def linear_layer(state: Sequence[int], wiring: Sequence[int]) -> List[int]:
    require_equal(len(state), STATE_BYTES, "linear-layer state bytes")
    require_equal(len(wiring), 4, "linear-layer wiring arity")
    shifted = [0] * STATE_BYTES
    for column in range(8):
        for row in range(4):
            source = 4 * ((column + int(wiring[row])) % 8) + row
            shifted[4 * column + row] = int(state[source])
    output = [0] * STATE_BYTES
    for column in range(8):
        for row in range(4):
            value = 0
            for inner in range(4):
                value ^= gf_mul(MIX_ROWS[row][inner], shifted[4 * column + inner])
            output[4 * column + row] = value
    return output


def round_once(
    state: Sequence[int],
    p_in: Sequence[int],
    p_out: Sequence[int],
    following_mask: Sequence[int],
    wiring: Sequence[int],
) -> List[int]:
    substituted = [
        AES_SBOX[int(state[index]) ^ int(p_in[index])] ^ int(p_out[index])
        for index in range(STATE_BYTES)
    ]
    return xor_states(linear_layer(substituted, wiring), following_mask)


def parse_material(identifier: str, domain: str, raw: bytes) -> dict:
    require_equal(len(raw), MATERIAL_BYTES, f"{identifier} material bytes")
    p_in = [
        [raw[(round_index * 32 + lane) * 2] for lane in range(32)]
        for round_index in range(12)
    ]
    p_out = [
        [raw[(round_index * 32 + lane) * 2 + 1] for lane in range(32)]
        for round_index in range(12)
    ]
    masks = [
        [raw[MATERIAL_MASK_BASE + mask_index * 32 + lane] for lane in range(32)]
        for mask_index in range(13)
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


def derive_material_sets() -> List[dict]:
    definitions = (
        ("frozen_attack_v1", "E256-H/attack/material/v1"),
        ("collapse_aux_0", "E256-H/collapse/material/v1/0"),
        ("collapse_aux_1", "E256-H/collapse/material/v1/1"),
    )
    declared = tuple(
        item["id"] for item in PREREG_DATA["software_coverage"]["material_sets"]
    )
    require_equal(declared, EXPECTED_MATERIAL_IDS, "declared material IDs")
    materials = []
    for identifier, domain in definitions:
        raw = hashlib.shake_256(domain.encode("ascii")).digest(MATERIAL_BYTES)
        materials.append(parse_material(identifier, domain, raw))
    require_equal(
        materials[0]["raw_sha256"], FROZEN_MATERIAL_SHA256, "frozen material SHA-256"
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
    require_equal(len(b"".join(block for _, block in blocks)), 8 * 32, "block corpus bytes")
    return blocks


def original_prefixes(
    block: Sequence[int], material: Mapping, wiring: Sequence[int]
) -> List[List[int]]:
    state = xor_states(block, material["masks"][0])
    outputs = []
    for round_index in range(12):
        state = round_once(
            state,
            material["p_in"][round_index],
            material["p_out"][round_index],
            material["masks"][round_index + 1],
            wiring,
        )
        outputs.append(state)
    return outputs


def stage_a_masks(material: Mapping, wiring: Sequence[int]) -> List[List[int]]:
    masks = [list(material["masks"][0])]
    for round_index in range(12):
        masks.append(
            xor_states(
                material["masks"][round_index + 1],
                linear_layer(material["p_out"][round_index], wiring),
            )
        )
    return masks


def wrong_index_stage_a_masks(
    material: Mapping, wiring: Sequence[int]
) -> List[List[int]]:
    masks = [list(material["masks"][0])]
    for round_index in range(12):
        masks.append(
            xor_states(
                material["masks"][round_index],
                linear_layer(material["p_out"][round_index], wiring),
            )
        )
    return masks


def offset_input_prefixes(
    block: Sequence[int],
    material: Mapping,
    wiring: Sequence[int],
    transformed_masks: Sequence[Sequence[int]],
) -> List[List[int]]:
    state = xor_states(block, transformed_masks[0])
    outputs = []
    for round_index in range(12):
        state = round_once(
            state,
            material["p_in"][round_index],
            ZERO_STATE,
            transformed_masks[round_index + 1],
            wiring,
        )
        outputs.append(state)
    return outputs


def fixed_round_keys(
    material: Mapping,
    wiring: Sequence[int],
    rounds: int,
    include_terminal_input_offset: bool = False,
) -> List[List[int]]:
    if rounds not in EXPECTED_ROUNDS:
        raise StructuralValidationError(f"fixed-round schedule outside 1..12: {rounds}")
    if include_terminal_input_offset and rounds == 12:
        raise StructuralValidationError("A_12 does not exist in frozen material")
    keys = [xor_states(material["masks"][0], material["p_in"][0])]
    for key_index in range(1, rounds):
        keys.append(
            xor_states(
                linear_layer(material["p_out"][key_index - 1], wiring),
                material["masks"][key_index],
                material["p_in"][key_index],
            )
        )
    terminal = xor_states(
        linear_layer(material["p_out"][rounds - 1], wiring),
        material["masks"][rounds],
    )
    if include_terminal_input_offset:
        terminal = xor_states(terminal, material["p_in"][rounds])
    keys.append(terminal)
    require_equal(len(keys), rounds + 1, f"fixed-R key count for R={rounds}")
    return keys


def canonical_permute(
    block: Sequence[int], keys: Sequence[Sequence[int]], wiring: Sequence[int]
) -> List[int]:
    state = xor_states(block, keys[0])
    for round_index in range(len(keys) - 1):
        state = round_once(state, ZERO_STATE, ZERO_STATE, keys[round_index + 1], wiring)
    return state


def state_hex(state: Sequence[int]) -> str:
    require_equal(len(state), STATE_BYTES, "state hex bytes")
    return bytes(int(value) for value in state).hex()


def state_to_verilog_hex(state: Sequence[int]) -> str:
    value = 0
    for index, byte in enumerate(state):
        value |= int(byte) << (8 * index)
    return f"{value:064x}"


def verilog_hex_to_state(value: str) -> List[int]:
    integer = int(value, 16)
    return [(integer >> (8 * index)) & 0xFF for index in range(STATE_BYTES)]


# ---------------------------------------------------------------------------
# Frozen contract validation.


def architecture_contract_digest() -> str:
    raw = ARCHITECTURE.read_bytes()
    start = PREREG_DATA["authorization"]["contract_start_marker"].encode("ascii")
    end = PREREG_DATA["authorization"]["contract_end_marker"].encode("ascii")
    if raw.count(start) != 1 or raw.count(end) != 1:
        raise StructuralValidationError("architecture contract markers are not unique")
    if raw.index(start) >= raw.index(end):
        raise StructuralValidationError("architecture contract markers are out of order")
    return sha256_bytes(raw[raw.index(start) + len(start) : raw.index(end)])


def tool_versions() -> dict:
    def first_line(command: Sequence[str]) -> str:
        if shutil.which(command[0]) is None:
            raise StructuralValidationError(f"{command[0]} is not available")
        process = subprocess.run(
            command, capture_output=True, text=True, timeout=60, check=False
        )
        text = (process.stdout or "") + (process.stderr or "")
        for line in text.splitlines():
            if line.strip():
                return line.strip()
        raise StructuralValidationError(f"{command[0]} produced no version output")

    return {
        "yosys": first_line(["yosys", "-V"]),
        "iverilog": first_line(["iverilog", "-V"]),
    }


def validate_contract_shape() -> None:
    require_equal(
        PREREG_DATA["schema"],
        "E256-HARDWARE-OFFSET-COLLAPSE-PREREGISTRATION-1",
        "preregistration schema",
    )
    require_equal(PREREG_DATA["status"], "FROZEN_FOR_EXECUTION", "preregistration status")
    require_equal(sha256_file(PREREG), PREREG_SHA256, "raw preregistration SHA-256")
    require_equal(
        tuple(PREREG_DATA["authorization"]["graded_constraints"]),
        EXPECTED_GRADED_CONSTRAINTS,
        "graded constraint IDs",
    )
    require_equal(
        tuple(item["id"] for item in PREREG_DATA["questions"]),
        EXPECTED_QUESTION_IDS,
        "question IDs",
    )
    require_equal(
        tuple(item["id"] for item in PREREG_DATA["controls"]),
        EXPECTED_CONTROL_IDS,
        "control IDs",
    )
    require_equal(
        tuple(item["id"] for item in PREREG_DATA["predictions"]),
        EXPECTED_PREDICTION_IDS,
        "prediction IDs",
    )
    require_equal(
        tuple(item["id"] for item in PREREG_DATA["formal_contract"]["mutation_modes"]),
        EXPECTED_FORMAL_MODES[1:],
        "formal mutation IDs",
    )
    formal_contract = PREREG_DATA["formal_contract"]
    proof_decomposition = formal_contract["proof_decomposition"]
    require_equal(
        proof_decomposition["supersedes_preregistration_sha256"],
        FORMAL_DECOMPOSITION_SUPERSEDED_PREREG_SHA256,
        "formal-decomposition superseded preregistration hash",
    )
    require_equal(
        formal_contract["correct_mode"],
        (
            "prove mismatch=0 between original_linear=L(U XOR B) XOR M and "
            "canonical_linear=L(U) XOR L(B) XOR M"
        ),
        "formal correct mode",
    )
    require_equal(
        formal_contract["correct_expected"],
        "UNSAT for mismatch",
        "formal correct expectation",
    )
    require_true(
        "arbitrary 256-bit U, B, and M" in formal_contract["scope"],
        "formal scope must expose arbitrary U, B, and M",
    )
    require_true(
        "L(U XOR B) XOR M = L(U) XOR L(B) XOR M"
        in proof_decomposition["sat_lemma"],
        "formal SAT lemma drift",
    )
    require_true(
        "unchanged dual-core RTL comparison"
        in proof_decomposition["nonlinear_boundary"],
        "formal nonlinear-boundary integration link drift",
    )
    require_equal(
        tuple(FORMAL_INPUT_SIGNALS), EXPECTED_FORMAL_MODES, "formal input modes"
    )
    require_equal(FORMAL_INPUT_BITS["correct"], 3 * 256, "correct formal input bits")
    require_equal(
        FORMAL_INPUT_BITS["wrong_transport_source"],
        4 * 256,
        "wrong-source formal input bits",
    )
    require_equal(tuple(CONSTRUCTION["rounds_covered"]), EXPECTED_ROUNDS, "software rounds")
    require_equal(CONSTRUCTION["state_bytes"], STATE_BYTES, "state bytes")
    require_equal(CONSTRUCTION["raw_material"]["bytes"], MATERIAL_BYTES, "raw material bytes")
    require_equal(
        CONSTRUCTION["raw_material"]["frozen_sha256"],
        FROZEN_MATERIAL_SHA256,
        "declared frozen material SHA-256",
    )
    require_equal(
        CONSTRUCTION["raw_material"]["shake256_rate_bytes"],
        SHAKE256_RATE_BYTES,
        "SHAKE256 rate bytes",
    )
    require_equal(
        CONSTRUCTION["raw_material"]["frozen_squeeze_blocks"], 9, "frozen squeeze blocks"
    )
    require_equal(math.ceil(MATERIAL_BYTES / SHAKE256_RATE_BYTES), 9, "squeeze arithmetic")
    require_equal(12 * 32 * 2 + 13 * 32, MATERIAL_BYTES, "material layout arithmetic")
    require_equal(MATERIAL_MASK_BASE, 12 * 32 * 2, "raw mask offset")
    require_equal(CONSTRUCTION["stage_a"]["raw_bytes_at_12_rounds"], MATERIAL_BYTES, "Stage A raw bytes")
    require_equal(CONSTRUCTION["stage_a"]["effective_bytes_at_12_rounds"], STAGE_A_BYTES_12, "Stage A effective bytes")
    require_equal(CONSTRUCTION["stage_b"]["effective_bytes_at_12_rounds"], STAGE_B_BYTES_12, "Stage B 12-round bytes")
    require_equal(CONSTRUCTION["stage_b"]["effective_bytes_at_8_rounds"], STAGE_B_BYTES_8, "Stage B 8-round bytes")
    require_equal(RAW_OFFSET_BYTES + MASK_BYTES_12, MATERIAL_BYTES, "raw byte accounting")
    require_equal(12 * 32 + 13 * 32, STAGE_A_BYTES_12, "Stage A byte accounting")
    require_equal(13 * 32, STAGE_B_BYTES_12, "Stage B byte accounting")
    require_equal(9 * 32, STAGE_B_BYTES_8, "Stage B R=8 byte accounting")
    require_equal(CONSTRUCTION["aes_sbox_sha256"], AES_SBOX_SHA256, "declared AES S-box hash")
    require_equal(
        tuple(tuple(int(value, 16) for value in row) for row in CONSTRUCTION["mix_columns_matrix_hex_rows"]),
        ((2, 3, 1, 1), (1, 2, 3, 1), (1, 1, 2, 3), (3, 1, 1, 2)),
        "MixColumns matrix",
    )
    software = PREREG_DATA["software_coverage"]
    require_equal(software["stage_a_expected_comparisons"], SOFTWARE_COMPARISONS_PER_STAGE, "Stage A comparison contract")
    require_equal(software["stage_b_expected_comparisons"], SOFTWARE_COMPARISONS_PER_STAGE, "Stage B comparison contract")
    require_equal(software["total_expected_comparisons"], 2 * SOFTWARE_COMPARISONS_PER_STAGE, "total software comparisons")
    require_equal(software["block_corpus"]["count"], 8, "block count")
    require_equal(tuple(PREREG_DATA["rtl_coverage"]["fixed_h4_tuple"]), FIXED_H4, "fixed RTL H4 tuple")
    require_equal(tuple(PREREG_DATA["rtl_coverage"]["rounds"]), EXPECTED_RTL_ROUNDS, "RTL rounds")
    require_equal(PREREG_DATA["rtl_coverage"]["expected_original_vs_canonical_comparisons"], RTL_COMPARISONS, "RTL comparison contract")
    terminal = PREREG_DATA["controls"][3]
    require_equal(
        terminal["freeze_correction"]["supersedes_preregistration_sha256"],
        SUPERSEDED_PREREG_SHA256,
        "superseded preregistration hash",
    )
    require_true("R=1..11" in terminal["required_result"], "terminal control must cover R=1..11")
    require_true("R=12" in terminal["required_result"], "terminal control must mark R=12 inapplicable")
    require_equal(tuple(PREREG_DATA["interpretation"]["valid_emitted_verdicts"]), VALID_VERDICTS, "valid verdicts")
    require_true(
        PREREG_DATA["interpretation"]["internal_invalid_status"].startswith(
            "INVALID_OFFSET_COLLAPSE_HARNESS"
        ),
        "internal invalid status drift",
    )
    receipt = PREREG_DATA["receipt_contract"]
    require_equal(receipt["schema"], "E256-HARDWARE-OFFSET-COLLAPSE-GATE-1", "receipt schema")
    require_equal(receipt["status"], "OPEN_PROGRESS", "receipt status")
    require_equal(receipt["output"], str(RECEIPT.relative_to(REPO)), "receipt path")
    require_equal(receipt["runner"], str(Path(__file__).resolve().relative_to(REPO)), "runner path")
    require_equal(receipt["rtl_miter"], str(MITER.relative_to(REPO)), "miter path")
    require_equal(receipt["testbench"], str(TESTBENCH.relative_to(REPO)), "testbench path")
    require_equal(tuple(receipt["deterministic_payload_top_level_keys"]), EXPECTED_PAYLOAD_KEYS, "payload top-level keys")


def validate_frozen_inputs() -> Tuple[dict, List[List[int]]]:
    validate_contract_shape()
    require_equal(
        PREREG_DATA["authorization"]["contract_sha256"],
        ARCHITECTURE_CONTRACT_SHA256,
        "declared architecture contract hash",
    )
    require_equal(
        architecture_contract_digest(),
        ARCHITECTURE_CONTRACT_SHA256,
        "recomputed architecture contract hash",
    )
    require_equal(sys.version.split()[0], "3.9.6", "running Python version")

    declared_predecessors = tuple(
        (
            item["id"],
            item["receipt"],
            item["receipt_schema"],
            item["deterministic_payload_sha256"],
        )
        for item in PREREG_DATA["predecessors"]
    )
    require_equal(declared_predecessors, PREDECESSOR_CONTRACTS, "predecessor contracts")

    predecessor_records = []
    predecessor_payloads: Dict[str, dict] = {}
    for identifier, relative, schema, expected_digest in PREDECESSOR_CONTRACTS:
        path = REPO / relative
        receipt = json.loads(path.read_text(encoding="utf-8"))
        payload = receipt.get("deterministic_payload")
        require_true(isinstance(payload, dict), f"{relative} has no deterministic payload")
        require_equal(payload.get("schema"), schema, f"{relative} payload schema")
        recomputed = sha256_bytes(canonical_json_bytes(payload))
        require_equal(recomputed, expected_digest, f"{relative} recomputed payload digest")
        require_equal(receipt.get("deterministic_payload_sha256"), expected_digest, f"{relative} stored payload digest")
        predecessor_payloads[identifier] = payload
        predecessor_records.append(
            {
                "id": identifier,
                "path": relative,
                "schema": schema,
                "deterministic_payload_sha256": expected_digest,
            }
        )

    candidate_payload = predecessor_payloads["E256-063-steps-2-3"]
    certified = candidate_payload["results"]["h4_wiring"]["certified_set"]
    require_true(isinstance(certified, list), "certified H4 set is not a list")
    require_equal(len(certified), 384, "certified H4 set size")
    require_equal(
        sha256_bytes(canonical_json_bytes(certified)),
        CERTIFIED_H4_SET_SHA256,
        "certified H4 set SHA-256",
    )
    normalized_certified = []
    for index, wiring in enumerate(certified):
        require_true(
            isinstance(wiring, list)
            and len(wiring) == 4
            and all(isinstance(value, int) and 0 <= value < 8 for value in wiring),
            f"invalid certified H4 tuple at index {index}",
        )
        normalized_certified.append(list(wiring))
    require_equal(len({tuple(wiring) for wiring in normalized_certified}), 384, "unique certified H4 tuples")
    require_true(FIXED_H4 in {tuple(wiring) for wiring in normalized_certified}, "fixed RTL tuple is not certified")

    attack_payload = predecessor_payloads["E256-063-step-4"]
    require_equal(
        attack_payload["pinned_parameters"]["material_sha256"],
        FROZEN_MATERIAL_SHA256,
        "attack receipt material hash",
    )

    declared_sources = PREREG_DATA["frozen_predecessor_sources"]
    source_paths = {
        "rtl": FROZEN_RTL,
        "testbench": FROZEN_TESTBENCH,
        "runner": FROZEN_RUNNER,
    }
    source_records = {}
    for role in ("rtl", "testbench", "runner"):
        expected_path = str(source_paths[role].relative_to(REPO))
        require_equal(declared_sources[role]["path"], expected_path, f"{role} source path")
        require_equal(declared_sources[role]["sha256"], FROZEN_SOURCE_HASHES[role], f"{role} declared source hash")
        require_equal(sha256_file(source_paths[role]), FROZEN_SOURCE_HASHES[role], f"{role} recomputed source hash")
        source_records[role] = {
            "path": expected_path,
            "sha256": FROZEN_SOURCE_HASHES[role],
        }

    versions = tool_versions()
    toolchain = PREREG_DATA["toolchain_contract"]
    require_equal(toolchain["python"], "3.9.6", "pinned Python version")
    if not versions["yosys"].startswith(toolchain["yosys_version_prefix"]):
        raise StructuralValidationError(f"Yosys version drift: {versions['yosys']!r}")
    if toolchain["yosys_git_sha1"] not in versions["yosys"]:
        raise StructuralValidationError("Yosys git SHA-1 drift")
    if not versions["iverilog"].startswith(toolchain["iverilog_version_prefix"]):
        raise StructuralValidationError(f"Icarus version drift: {versions['iverilog']!r}")

    require_equal(sha256_bytes(bytes(AES_SBOX)), AES_SBOX_SHA256, "runtime AES S-box hash")
    require_true(MITER.is_file(), "offset-collapse miter is missing")
    require_true(TESTBENCH.is_file(), "offset-collapse testbench is missing")

    inputs = {
        "preregistration": {
            "path": str(PREREG.relative_to(REPO)),
            "sha256": PREREG_SHA256,
        },
        "architecture_contract": {
            "path": str(ARCHITECTURE.relative_to(REPO)),
            "sha256": ARCHITECTURE_CONTRACT_SHA256,
        },
        "predecessors": predecessor_records,
        "frozen_predecessor_sources": source_records,
        "gate_artifacts": {
            "runner": {
                "path": str(Path(__file__).resolve().relative_to(REPO)),
                "sha256": sha256_file(Path(__file__).resolve()),
            },
            "rtl_miter": {
                "path": str(MITER.relative_to(REPO)),
                "sha256": sha256_file(MITER),
            },
            "testbench": {
                "path": str(TESTBENCH.relative_to(REPO)),
                "sha256": sha256_file(TESTBENCH),
            },
        },
        "certified_h4_set": {
            "source": "logs/e256-hardware-candidate-gate.json",
            "size": len(normalized_certified),
            "sha256": CERTIFIED_H4_SET_SHA256,
        },
        "aes_sbox_sha256": AES_SBOX_SHA256,
        "toolchain": {
            "python": sys.version.split()[0],
            "yosys": versions["yosys"],
            "iverilog": versions["iverilog"],
        },
    }
    return inputs, normalized_certified


# ---------------------------------------------------------------------------
# Exhaustive software equivalence and software controls.


def canonical_fixed_round_prefixes(
    block: Sequence[int],
    material: Mapping,
    wiring: Sequence[int],
    transported_p_out: Sequence[Sequence[int]],
) -> List[List[int]]:
    """Return every fixed-R terminal output in one shared 12-round pass.

    The state carried between iterations is the next nonlinear-boundary value
    Z_r = X_r XOR A_r.  Each recorded prefix is terminal, so it excludes A_R;
    only the continuation state XORs A_R back in for the following round.
    """
    require_equal(len(transported_p_out), 12, "transported p_out count")
    boundary = xor_states(block, material["masks"][0], material["p_in"][0])
    outputs: List[List[int]] = []
    for round_index in range(12):
        core = round_once(
            boundary, ZERO_STATE, ZERO_STATE, ZERO_STATE, wiring
        )
        terminal = xor_states(
            core,
            transported_p_out[round_index],
            material["masks"][round_index + 1],
        )
        outputs.append(terminal)
        if round_index + 1 < 12:
            boundary = xor_states(
                terminal, material["p_in"][round_index + 1]
            )
    require_equal(len(outputs), 12, "canonical fixed-R prefix count")
    return outputs


def run_software_equivalence(
    certified: Sequence[Sequence[int]],
    materials: Sequence[Mapping],
    blocks: Sequence[Tuple[str, bytes]],
) -> Tuple[dict, dict]:
    stage_a_hash = hashlib.sha256()
    stage_b_hash = hashlib.sha256()
    combined_hash = hashlib.sha256()
    stage_a_count = 0
    stage_b_count = 0
    seen_wirings: List[List[int]] = []
    seen_materials: List[str] = []
    seen_rounds = set()
    seen_blocks = set()

    for wiring in certified:
        normalized_wiring = [int(value) for value in wiring]
        seen_wirings.append(normalized_wiring)
        for material in materials:
            material_id = str(material["id"])
            if material_id not in seen_materials:
                seen_materials.append(material_id)
            transformed_masks = stage_a_masks(material, normalized_wiring)
            transported_p_out = [
                linear_layer(material["p_out"][round_index], normalized_wiring)
                for round_index in range(12)
            ]
            original_by_block = []
            stage_a_by_block = []
            stage_b_by_block = []
            for block_id, block in blocks:
                seen_blocks.add(block_id)
                original_by_block.append(
                    original_prefixes(list(block), material, normalized_wiring)
                )
                stage_a_by_block.append(
                    offset_input_prefixes(
                        list(block), material, normalized_wiring, transformed_masks
                    )
                )
                stage_b_by_block.append(
                    canonical_fixed_round_prefixes(
                        list(block),
                        material,
                        normalized_wiring,
                        transported_p_out,
                    )
                )

            for rounds in EXPECTED_ROUNDS:
                seen_rounds.add(rounds)
                for block_index, (block_id, block) in enumerate(blocks):
                    original = original_by_block[block_index][rounds - 1]
                    collapsed_a = stage_a_by_block[block_index][rounds - 1]
                    collapsed_b = stage_b_by_block[block_index][rounds - 1]
                    stage_a_count += 1
                    stage_b_count += 1
                    if original != collapsed_a:
                        raise StructuralValidationError(
                            "Stage A mismatch at "
                            f"wiring={normalized_wiring} material={material_id} "
                            f"rounds={rounds} block={block_id}"
                        )
                    if original != collapsed_b:
                        raise StructuralValidationError(
                            "Stage B mismatch at "
                            f"wiring={normalized_wiring} material={material_id} "
                            f"rounds={rounds} block={block_id}"
                        )
                    identity = {
                        "wiring": normalized_wiring,
                        "material": material_id,
                        "rounds": rounds,
                        "block": block_id,
                    }
                    original_hex = state_hex(original)
                    stage_a_record = dict(identity)
                    stage_a_record.update(
                        {"original": original_hex, "stage_a": state_hex(collapsed_a)}
                    )
                    stage_b_record = dict(identity)
                    stage_b_record.update(
                        {"original": original_hex, "stage_b": state_hex(collapsed_b)}
                    )
                    combined_record = dict(identity)
                    combined_record.update(
                        {
                            "original": original_hex,
                            "stage_a": state_hex(collapsed_a),
                            "stage_b": state_hex(collapsed_b),
                        }
                    )
                    update_record_hash(stage_a_hash, stage_a_record)
                    update_record_hash(stage_b_hash, stage_b_record)
                    update_record_hash(combined_hash, combined_record)

    require_equal(seen_wirings, [list(wiring) for wiring in certified], "executed H4 wiring order")
    require_equal(tuple(seen_materials), EXPECTED_MATERIAL_IDS, "executed material IDs")
    require_equal(tuple(sorted(seen_rounds)), EXPECTED_ROUNDS, "executed software rounds")
    require_equal(tuple(block_id for block_id, _ in blocks), EXPECTED_BLOCK_IDS, "executed block order")
    require_equal(seen_blocks, set(EXPECTED_BLOCK_IDS), "executed block set")
    require_equal(stage_a_count, SOFTWARE_COMPARISONS_PER_STAGE, "executed Stage A comparisons")
    require_equal(stage_b_count, SOFTWARE_COMPARISONS_PER_STAGE, "executed Stage B comparisons")

    equivalence = {
        "stage_a": {
            "expected_comparisons": SOFTWARE_COMPARISONS_PER_STAGE,
            "executed_comparisons": stage_a_count,
            "mismatches": 0,
            "byte_exact": True,
            "aggregate_sha256": stage_a_hash.hexdigest(),
        },
        "stage_b": {
            "expected_comparisons": SOFTWARE_COMPARISONS_PER_STAGE,
            "executed_comparisons": stage_b_count,
            "mismatches": 0,
            "byte_exact": True,
            "fixed_round_terminal_keys_derived_separately": True,
            "aggregate_sha256": stage_b_hash.hexdigest(),
        },
        "total_comparisons": stage_a_count + stage_b_count,
        "combined_aggregate_sha256": combined_hash.hexdigest(),
        "aggregate_encoding": AGGREGATE_ENCODING,
    }
    executed = {
        "h4_set_size": len(seen_wirings),
        "h4_set_sha256": sha256_bytes(canonical_json_bytes(seen_wirings)),
        "material_ids": seen_materials,
        "rounds": sorted(seen_rounds),
        "block_ids": [block_id for block_id, _ in blocks],
    }
    return equivalence, executed


def run_terminal_input_control(
    material: Mapping, blocks: Sequence[Tuple[str, bytes]]
) -> dict:
    counts_by_round = {}
    aggregate = hashlib.sha256()
    for rounds in range(1, 12):
        original_keys = fixed_round_keys(material, FIXED_H4, rounds)
        mutated_keys = fixed_round_keys(
            material, FIXED_H4, rounds, include_terminal_input_offset=True
        )
        mismatches = 0
        for block_id, block in blocks:
            expected = canonical_permute(list(block), original_keys, FIXED_H4)
            mutated = canonical_permute(list(block), mutated_keys, FIXED_H4)
            if expected != mutated:
                mismatches += 1
            update_record_hash(
                aggregate,
                {
                    "rounds": rounds,
                    "block": block_id,
                    "expected": state_hex(expected),
                    "mutated": state_hex(mutated),
                },
            )
        counts_by_round[str(rounds)] = mismatches
    detected_rounds = [
        rounds for rounds in range(1, 12) if counts_by_round[str(rounds)] > 0
    ]
    detected = detected_rounds == list(range(1, 12))
    require_true(detected, "terminal A_R control was not detected for every R=1..11")
    return {
        "mutation": "incorrectly XOR A_R into terminal K_R",
        "rounds_tested": list(range(1, 12)),
        "round_12": "inapplicable: frozen material has A_0 through A_11 only",
        "blocks_per_round": len(blocks),
        "mismatches_by_round": counts_by_round,
        "detected_rounds": detected_rounds,
        "aggregate_sha256": aggregate.hexdigest(),
        "detected": detected,
    }


def run_wrong_mask_index_control(
    material: Mapping, blocks: Sequence[Tuple[str, bytes]]
) -> dict:
    correct_masks = stage_a_masks(material, FIXED_H4)
    mutated_masks = wrong_index_stage_a_masks(material, FIXED_H4)
    mismatches = 0
    rounds_detected = set()
    aggregate = hashlib.sha256()
    for block_id, block in blocks:
        correct = offset_input_prefixes(list(block), material, FIXED_H4, correct_masks)
        mutated = offset_input_prefixes(list(block), material, FIXED_H4, mutated_masks)
        for rounds in EXPECTED_ROUNDS:
            if correct[rounds - 1] != mutated[rounds - 1]:
                mismatches += 1
                rounds_detected.add(rounds)
            update_record_hash(
                aggregate,
                {
                    "rounds": rounds,
                    "block": block_id,
                    "correct": state_hex(correct[rounds - 1]),
                    "mutated": state_hex(mutated[rounds - 1]),
                },
            )
    detected = mismatches > 0
    require_true(detected, "wrong-mask-index control was not detected")
    return {
        "mutation": "use M_r where M_{r+1} is required in Stage A",
        "expected_cases": 12 * 8,
        "executed_cases": 12 * 8,
        "mismatches": mismatches,
        "rounds_detected": sorted(rounds_detected),
        "aggregate_sha256": aggregate.hexdigest(),
        "detected": detected,
    }


def run_non_absorbable_control() -> dict:
    def control_family(value: int) -> int:
        return ror8(AES_SBOX[rol8(value, 1)], 1)

    matching_pairs = []
    comparisons = 0
    control_zero = control_family(0)
    for a_value in range(256):
        b_value = control_zero ^ AES_SBOX[a_value]
        matches = True
        for x_value in range(256):
            comparisons += 1
            if control_family(x_value) != (AES_SBOX[x_value ^ a_value] ^ b_value):
                matches = False
        if matches:
            matching_pairs.append({"a": a_value, "b": b_value})
    require_equal(comparisons, 256 * 256, "non-absorbable control comparisons")
    detected = len(matching_pairs) == 0
    require_true(detected, "non-translation-equivalent control was accepted")
    return {
        "family": "C(x)=ror8(SBOX(rol8(x,1)),1)",
        "a_values": 256,
        "x_values_per_a": 256,
        "executed_comparisons": comparisons,
        "matching_xor_translation_pairs": matching_pairs,
        "detected": detected,
    }


# ---------------------------------------------------------------------------
# Sequential RTL comparison.


def prepare_scratch(material: Mapping, blocks: Sequence[Tuple[str, bytes]]) -> None:
    expected_parent = (REPO / "build").resolve()
    require_equal(SCRATCH.resolve().parent, expected_parent, "scratch parent")
    if SCRATCH.exists():
        shutil.rmtree(SCRATCH)
    SCRATCH.mkdir(parents=True, exist_ok=False)
    (SCRATCH / "material.hex").write_text(
        "".join(f"{value:02x}\n" for value in material["raw"]), encoding="utf-8"
    )
    (SCRATCH / "blocks.hex").write_text(
        "".join(
            f"{value:02x}\n" for _, block in blocks for value in block
        ),
        encoding="utf-8",
    )


def run_rtl_equivalence(
    material: Mapping, blocks: Sequence[Tuple[str, bytes]]
) -> dict:
    prepare_scratch(material, blocks)
    binary = SCRATCH / "e256h_offset_collapse_tb.vvp"
    compile_process = subprocess.run(
        [
            "iverilog",
            "-g2012",
            "-s",
            "e256h_offset_collapse_tb",
            "-o",
            str(binary),
            str(TESTBENCH),
            str(FROZEN_RTL),
        ],
        cwd=str(REPO),
        capture_output=True,
        text=True,
        timeout=600,
        check=False,
    )
    if compile_process.returncode != 0:
        raise StructuralValidationError(
            "Icarus compile failed: "
            + ((compile_process.stdout or "") + (compile_process.stderr or ""))[-1000:]
        )
    run_process = subprocess.run(
        ["vvp", str(binary)],
        cwd=str(REPO),
        capture_output=True,
        text=True,
        timeout=3600,
        check=False,
    )
    output = (run_process.stdout or "") + (run_process.stderr or "")
    if run_process.returncode != 0:
        raise StructuralValidationError(f"RTL simulation failed: {output[-1000:]}")
    require_true("E256H_OFFSET_COLLAPSE_TB DONE" in output, "RTL completion sentinel missing")
    results_path = SCRATCH / "results.txt"
    require_true(results_path.is_file(), "RTL results file missing")

    rows: Dict[Tuple[int, int], Tuple[str, str]] = {}
    hex_pattern = re.compile(r"^[0-9a-f]{64}$")
    for line_number, line in enumerate(
        results_path.read_text(encoding="utf-8").splitlines(), start=1
    ):
        parts = line.split()
        if len(parts) != 5 or parts[0] != "rtl":
            raise StructuralValidationError(
                f"unknown RTL result row at line {line_number}: {line!r}"
            )
        try:
            rounds = int(parts[1])
            block_index = int(parts[2])
        except ValueError as error:
            raise StructuralValidationError(
                f"non-integer RTL key at line {line_number}"
            ) from error
        if not hex_pattern.fullmatch(parts[3]) or not hex_pattern.fullmatch(parts[4]):
            raise StructuralValidationError(
                f"non-canonical RTL output at line {line_number}"
            )
        key = (rounds, block_index)
        if key in rows:
            raise StructuralValidationError(f"duplicate RTL result key: {key}")
        rows[key] = (parts[3], parts[4])

    expected_keys = {
        (rounds, block_index)
        for rounds in EXPECTED_RTL_ROUNDS
        for block_index in range(len(blocks))
    }
    require_equal(set(rows), expected_keys, "RTL result key set")

    aggregate = hashlib.sha256()
    side_comparisons = 0
    original_vs_canonical = 0
    for rounds in EXPECTED_RTL_ROUNDS:
        keys = fixed_round_keys(material, FIXED_H4, rounds)
        for block_index, (block_id, block) in enumerate(blocks):
            original_expected = original_prefixes(list(block), material, FIXED_H4)[
                rounds - 1
            ]
            canonical_expected = canonical_permute(list(block), keys, FIXED_H4)
            original_hex, canonical_hex = rows[(rounds, block_index)]
            side_comparisons += 2
            original_vs_canonical += 1
            require_equal(
                original_hex,
                state_to_verilog_hex(original_expected),
                f"RTL original R={rounds} block={block_id}",
            )
            require_equal(
                canonical_hex,
                state_to_verilog_hex(canonical_expected),
                f"RTL canonical R={rounds} block={block_id}",
            )
            require_equal(
                original_hex,
                canonical_hex,
                f"RTL original/canonical R={rounds} block={block_id}",
            )
            update_record_hash(
                aggregate,
                {
                    "rounds": rounds,
                    "block": block_id,
                    "original": original_hex,
                    "canonical": canonical_hex,
                },
            )

    require_equal(original_vs_canonical, RTL_COMPARISONS, "RTL comparison count")
    require_equal(side_comparisons, RTL_COMPARISONS * 2, "RTL/software side comparisons")
    return {
        "fixed_h4_tuple": list(FIXED_H4),
        "rounds": list(EXPECTED_RTL_ROUNDS),
        "block_ids": [identifier for identifier, _ in blocks],
        "expected_original_vs_canonical_comparisons": RTL_COMPARISONS,
        "executed_original_vs_canonical_comparisons": original_vs_canonical,
        "rtl_vs_software_side_comparisons": side_comparisons,
        "mismatches": 0,
        "both_sides_match_independent_software": True,
        "aggregate_sha256": aggregate.hexdigest(),
    }


# ---------------------------------------------------------------------------
# Compositional linear SAT proof and normalized mutation witnesses.


def normalize_witness(output: str, mode: str) -> dict:
    require_true(mode in FORMAL_INPUT_SIGNALS, f"unknown witness mode: {mode}")
    widths = {name: 64 for name in FORMAL_INPUT_SIGNALS[mode]}
    widths.update(
        {
            "original_out": 64,
            "canonical_out": 64,
            "mismatch": 1,
        }
    )
    found: Dict[str, str] = {}
    for line in output.splitlines():
        parts = line.split()
        if len(parts) < 4:
            continue
        name = parts[0].lstrip("\\")
        if name not in widths:
            continue
        if name in found:
            raise StructuralValidationError(f"duplicate SAT witness signal: {name}")
        hexadecimal = parts[-2].lower()
        if re.fullmatch(r"[0-9a-f]+", hexadecimal):
            if len(hexadecimal) > widths[name]:
                raise StructuralValidationError(
                    f"SAT witness signal {name} exceeds width"
                )
            normalized = hexadecimal.zfill(widths[name])
        else:
            binary = parts[-1].lower()
            if not re.fullmatch(r"[01]+", binary):
                raise StructuralValidationError(
                    f"SAT witness signal {name} is undefined or malformed: "
                    f"hex={hexadecimal!r} binary={binary!r}"
                )
            if len(binary) > 4 * widths[name]:
                raise StructuralValidationError(
                    f"SAT witness signal {name} exceeds width"
                )
            normalized = f"{int(binary, 2):0{widths[name]}x}"
        found[name] = normalized
    require_equal(set(found), set(widths), f"{mode} SAT witness signal set")
    return {name: found[name] for name in widths}


def validate_mutation_witness(mode: str, witness: Mapping[str, str]) -> None:
    substituted = verilog_hex_to_state(witness["U"])
    p_out = verilog_hex_to_state(witness["B"])
    mask = verilog_hex_to_state(witness["M"])
    original = xor_states(
        linear_layer(xor_states(substituted, p_out), FIXED_H4), mask
    )
    canonical_linear = linear_layer(substituted, FIXED_H4)
    if mode == "omit_output_transport":
        canonical_transport = list(ZERO_STATE)
    elif mode == "raw_output_offset":
        canonical_transport = list(p_out)
    elif mode == "wrong_transport_source":
        p_in = verilog_hex_to_state(witness["A"])
        canonical_transport = linear_layer(p_in, FIXED_H4)
    else:
        raise StructuralValidationError(f"unknown formal mutation mode: {mode}")
    canonical = xor_states(canonical_linear, canonical_transport, mask)
    require_equal(
        witness["original_out"],
        state_to_verilog_hex(original),
        f"{mode} witness original output",
    )
    require_equal(
        witness["canonical_out"],
        state_to_verilog_hex(canonical),
        f"{mode} witness canonical output",
    )
    require_true(original != canonical, f"{mode} witness does not mismatch")
    require_equal(int(witness["mismatch"], 16), 1, f"{mode} witness mismatch bit")


def run_formal_mode(mode: str) -> dict:
    require_true(mode in FORMAL_TOPS, f"unknown formal mode: {mode}")
    top = FORMAL_TOPS[mode]
    verify = "-verify " if mode == "correct" else ""
    script = "; ".join(
        (
            f"read_verilog {MITER.relative_to(REPO)}",
            f"hierarchy -check -top {top}",
            "proc",
            "flatten",
            "opt",
            "check -assert",
            (
                f"sat {verify}-prove mismatch 0 -show-inputs -show-outputs "
                f"{top}"
            ),
        )
    )
    process = subprocess.run(
        ["yosys", "-Q", "-p", script],
        cwd=str(REPO),
        capture_output=True,
        text=True,
        timeout=3600,
        check=False,
    )
    output = (process.stdout or "") + (process.stderr or "")
    if process.returncode != 0:
        raise StructuralValidationError(
            f"Yosys SAT mode {mode} exited {process.returncode}: {output[-1200:]}"
        )
    proved = "no model found: SUCCESS" in output
    refuted = "model found: FAIL" in output
    require_true(proved != refuted, f"ambiguous or missing SAT verdict for {mode}")
    common = {
        "mode": mode,
        "top": top,
        "input_signals": list(FORMAL_INPUT_SIGNALS[mode]),
        "arbitrary_input_bits": FORMAL_INPUT_BITS[mode],
    }
    if mode == "correct":
        require_true(proved, "correct offset-collapse linear lemma was not proven UNSAT")
        return {
            **common,
            "expected": "UNSAT for mismatch",
            "outcome": "UNSAT",
            "witness": None,
        }
    require_true(refuted, f"formal mutation {mode} did not produce SAT")
    witness = normalize_witness(output, mode)
    validate_mutation_witness(mode, witness)
    return {
        **common,
        "expected": "SAT for mismatch",
        "outcome": "SAT",
        "witness": witness,
    }


def run_formal_equivalence() -> dict:
    records = [run_formal_mode(mode) for mode in EXPECTED_FORMAL_MODES]
    require_equal(tuple(record["mode"] for record in records), EXPECTED_FORMAL_MODES, "executed formal modes")
    require_equal(
        tuple(record["arbitrary_input_bits"] for record in records),
        tuple(FORMAL_INPUT_BITS[mode] for mode in EXPECTED_FORMAL_MODES),
        "formal input-bit accounting",
    )
    aggregate = hashlib.sha256()
    for record in records:
        update_record_hash(aggregate, record)
    correct = records[0]
    mutations = records[1:]
    require_equal(correct["outcome"], "UNSAT", "correct formal outcome")
    require_true(all(record["outcome"] == "SAT" for record in mutations), "formal mutation outcome")
    require_true(all(record["witness"] is not None for record in mutations), "formal mutation witness")
    return {
        "engine": PREREG_DATA["toolchain_contract"]["formal_engine"],
        "flattened_proof_cone": True,
        "fixed_h4_tuple": list(FIXED_H4),
        "scope": PREREG_DATA["formal_contract"]["scope"],
        "proof_decomposition": PREREG_DATA["formal_contract"][
            "proof_decomposition"
        ],
        "input_signals_by_mode": {
            mode: list(FORMAL_INPUT_SIGNALS[mode]) for mode in EXPECTED_FORMAL_MODES
        },
        "arbitrary_input_bits_by_mode": {
            mode: FORMAL_INPUT_BITS[mode] for mode in EXPECTED_FORMAL_MODES
        },
        "nonlinear_or_sbox_logic_in_sat_cone": False,
        "independent_complete_linear_paths": {
            "original": "L(U XOR B)",
            "canonical": ["L(U)", "L(B)"],
            "wrong_transport_control": "L(A)",
        },
        "executed_modes": list(EXPECTED_FORMAL_MODES),
        "records": records,
        "aggregate_sha256": aggregate.hexdigest(),
        "correct_proved_unsat": True,
        "all_mutations_sat_with_witnesses": True,
    }


# ---------------------------------------------------------------------------
# Controls, grading, receipt, and check mode.


def build_controls(
    formal: Mapping,
    terminal_control: Mapping,
    wrong_mask_control: Mapping,
    non_absorbable_control: Mapping,
) -> dict:
    formal_by_mode = {record["mode"]: record for record in formal["records"]}
    prereg_controls = {item["id"]: item for item in PREREG_DATA["controls"]}
    records = {}
    for control_id in EXPECTED_CONTROL_IDS[:3]:
        formal_record = formal_by_mode[control_id]
        records[control_id] = {
            "shared_path": prereg_controls[control_id]["shared_path"],
            "expected": prereg_controls[control_id]["required_result"],
            "formal_outcome": formal_record["outcome"],
            "witness": formal_record["witness"],
            "detected": formal_record["outcome"] == "SAT"
            and formal_record["witness"] is not None,
        }
    records["terminal_input_offset_included"] = dict(terminal_control)
    records["terminal_input_offset_included"]["shared_path"] = prereg_controls[
        "terminal_input_offset_included"
    ]["shared_path"]
    records["wrong_mask_index"] = dict(wrong_mask_control)
    records["wrong_mask_index"]["shared_path"] = prereg_controls[
        "wrong_mask_index"
    ]["shared_path"]
    records["non_absorbable_bit_permutation"] = dict(non_absorbable_control)
    records["non_absorbable_bit_permutation"]["shared_path"] = [
        "independent exhaustive byte-family detector"
    ]
    require_equal(tuple(records), EXPECTED_CONTROL_IDS, "executed control IDs")
    all_detected = all(bool(records[identifier]["detected"]) for identifier in EXPECTED_CONTROL_IDS)
    require_true(all_detected, "one or more planted controls were not detected")
    return {
        "frozen_ids": list(EXPECTED_CONTROL_IDS),
        "executed_ids": list(records),
        "records": records,
        "all_detected": all_detected,
    }


def grade_predictions(
    controls: Mapping,
    software: Mapping,
    rtl: Mapping,
    formal: Mapping,
    normal_form: Mapping,
) -> dict:
    outcomes = {
        "OC1": {
            "role": "validity_control",
            "statement": PREREG_DATA["predictions"][0]["statement"],
            "observed": {
                "controls": len(controls["executed_ids"]),
                "all_detected": controls["all_detected"],
            },
            "pass": controls["all_detected"],
        },
        "OC2": {
            "role": "graded_finding",
            "statement": PREREG_DATA["predictions"][1]["statement"],
            "observed": {
                "comparisons": software["stage_a"]["executed_comparisons"],
                "mismatches": software["stage_a"]["mismatches"],
            },
            "pass": software["stage_a"]["byte_exact"]
            and software["stage_a"]["executed_comparisons"]
            == SOFTWARE_COMPARISONS_PER_STAGE,
        },
        "OC3": {
            "role": "graded_finding",
            "statement": PREREG_DATA["predictions"][2]["statement"],
            "observed": {
                "comparisons": software["stage_b"]["executed_comparisons"],
                "mismatches": software["stage_b"]["mismatches"],
                "fixed_round_terminal_keys": software["stage_b"][
                    "fixed_round_terminal_keys_derived_separately"
                ],
            },
            "pass": software["stage_b"]["byte_exact"]
            and software["stage_b"]["fixed_round_terminal_keys_derived_separately"]
            and software["stage_b"]["executed_comparisons"]
            == SOFTWARE_COMPARISONS_PER_STAGE,
        },
        "OC4": {
            "role": "graded_finding",
            "statement": PREREG_DATA["predictions"][3]["statement"],
            "observed": {
                "comparisons": rtl["executed_original_vs_canonical_comparisons"],
                "mismatches": rtl["mismatches"],
            },
            "pass": rtl["executed_original_vs_canonical_comparisons"]
            == RTL_COMPARISONS
            and rtl["mismatches"] == 0
            and rtl["both_sides_match_independent_software"],
        },
        "OC5": {
            "role": "graded_finding",
            "statement": PREREG_DATA["predictions"][4]["statement"],
            "observed": {
                "correct_unsat": formal["correct_proved_unsat"],
                "mutations_sat_with_witnesses": formal[
                    "all_mutations_sat_with_witnesses"
                ],
            },
            "pass": formal["correct_proved_unsat"]
            and formal["all_mutations_sat_with_witnesses"],
        },
        "OC6": {
            "role": "graded_finding",
            "statement": PREREG_DATA["predictions"][5]["statement"],
            "observed": {
                "effective_bytes": normal_form["stage_b_fixed_12_round_bytes"],
                "kernel_bytes": normal_form["representation_kernel_bytes"],
                "kernel_bits": normal_form["representation_kernel_bits"],
            },
            "pass": normal_form["stage_b_fixed_12_round_bytes"] == 416
            and normal_form["representation_kernel_bytes"] == 768
            and normal_form["representation_kernel_bits"] == 6144,
        },
    }
    require_equal(tuple(outcomes), EXPECTED_PREDICTION_IDS, "graded prediction IDs")
    validity_ids = tuple(
        item["id"]
        for item in PREREG_DATA["predictions"]
        if item["role"] == "validity_control"
    )
    require_equal(validity_ids, ("OC1",), "validity-control prediction IDs")
    require_true(all(outcome["pass"] for outcome in outcomes.values()), "prediction failure")
    return {
        "frozen_ids": list(EXPECTED_PREDICTION_IDS),
        "executed_ids": list(outcomes),
        "validity_control_ids": list(validity_ids),
        "validity_controls_pass": all(outcomes[identifier]["pass"] for identifier in validity_ids),
        "all_predictions_pass": all(outcome["pass"] for outcome in outcomes.values()),
        "outcomes": outcomes,
    }


def material_normal_form(materials: Sequence[Mapping]) -> dict:
    kernel_bytes = MATERIAL_BYTES - STAGE_B_BYTES_12
    kernel_bits = kernel_bytes * 8
    require_equal(kernel_bytes, 768, "representation kernel bytes")
    require_equal(kernel_bits, 6144, "representation kernel bits")
    return {
        "raw_material_bytes": MATERIAL_BYTES,
        "raw_offset_bytes": RAW_OFFSET_BYTES,
        "raw_mask_bytes": MASK_BYTES_12,
        "stage_a_12_round_bytes": STAGE_A_BYTES_12,
        "stage_a_semantics": CONSTRUCTION["stage_a"]["semantics_warning"],
        "stage_b_fixed_12_round_bytes": STAGE_B_BYTES_12,
        "stage_b_fixed_8_round_bytes": STAGE_B_BYTES_8,
        "representation_kernel_bytes": kernel_bytes,
        "representation_kernel_bits": kernel_bits,
        "material_sets": [
            {
                "id": material["id"],
                "domain": material["domain"],
                "raw_bytes": len(material["raw"]),
                "raw_sha256": material["raw_sha256"],
            }
            for material in materials
        ],
        "collapse_source": "all forms are collapsed from each already-derived 1184-byte material set",
        "direct_short_xof_compatibility": False,
        "terminal_rule": CONSTRUCTION["stage_b"]["terminal_rule"],
    }


def git_advisory() -> dict:
    def run(command: Sequence[str]) -> Tuple[bool, str]:
        try:
            process = subprocess.run(
                command, capture_output=True, text=True, timeout=20, check=False
            )
            return process.returncode == 0, process.stdout.strip()
        except Exception:
            return False, ""

    head_ok, head = run(["git", "-C", str(REPO), "rev-parse", "HEAD"])
    status_ok, status = run(["git", "-C", str(REPO), "status", "--porcelain"])
    return {
        "platform": platform.platform(),
        "git_head": head.splitlines()[0] if head_ok and head else "unavailable",
        "git_dirty": bool(status) if status_ok else "unavailable",
    }


def build_receipt() -> dict:
    started = time.perf_counter()
    inputs, certified = validate_frozen_inputs()
    materials = derive_material_sets()
    blocks = derive_blocks()

    software, executed_software = run_software_equivalence(
        certified, materials, blocks
    )
    terminal_control = run_terminal_input_control(materials[0], blocks)
    wrong_mask_control = run_wrong_mask_index_control(materials[0], blocks)
    non_absorbable_control = run_non_absorbable_control()
    rtl = run_rtl_equivalence(materials[0], blocks)
    formal = run_formal_equivalence()
    controls = build_controls(
        formal, terminal_control, wrong_mask_control, non_absorbable_control
    )
    normal_form = material_normal_form(materials)
    predictions = grade_predictions(controls, software, rtl, formal, normal_form)

    block_hex = [
        {"id": identifier, "bytes_hex": block.hex()} for identifier, block in blocks
    ]
    block_corpus_sha256 = sha256_bytes(b"".join(block for _, block in blocks))
    coverage = {
        "software": {
            "frozen_h4_set_size": 384,
            "frozen_h4_set_sha256": CERTIFIED_H4_SET_SHA256,
            "executed_h4_set_size": executed_software["h4_set_size"],
            "executed_h4_set_sha256": executed_software["h4_set_sha256"],
            "frozen_material_ids": list(EXPECTED_MATERIAL_IDS),
            "executed_material_ids": executed_software["material_ids"],
            "frozen_rounds": list(EXPECTED_ROUNDS),
            "executed_rounds": executed_software["rounds"],
            "frozen_block_ids": list(EXPECTED_BLOCK_IDS),
            "executed_block_ids": executed_software["block_ids"],
            "block_corpus": block_hex,
            "block_corpus_sha256": block_corpus_sha256,
            "expected_stage_a_comparisons": SOFTWARE_COMPARISONS_PER_STAGE,
            "executed_stage_a_comparisons": software["stage_a"]["executed_comparisons"],
            "expected_stage_b_comparisons": SOFTWARE_COMPARISONS_PER_STAGE,
            "executed_stage_b_comparisons": software["stage_b"]["executed_comparisons"],
            "expected_total_comparisons": 2 * SOFTWARE_COMPARISONS_PER_STAGE,
            "executed_total_comparisons": software["total_comparisons"],
        },
        "rtl": {
            "fixed_h4_tuple": list(FIXED_H4),
            "frozen_rounds": list(EXPECTED_RTL_ROUNDS),
            "executed_rounds": rtl["rounds"],
            "frozen_block_ids": list(EXPECTED_BLOCK_IDS),
            "executed_block_ids": rtl["block_ids"],
            "expected_comparisons": RTL_COMPARISONS,
            "executed_comparisons": rtl[
                "executed_original_vs_canonical_comparisons"
            ],
        },
        "formal": {
            "frozen_modes": list(EXPECTED_FORMAL_MODES),
            "executed_modes": formal["executed_modes"],
            "arbitrary_input_bits": FORMAL_INPUT_BITS["correct"],
            "arbitrary_input_bits_by_mode": {
                mode: FORMAL_INPUT_BITS[mode] for mode in EXPECTED_FORMAL_MODES
            },
            "proved_output_bits": 256,
            "complete_rounds": 0,
            "complete_linear_lemmas": 1,
            "nonlinear_or_sbox_logic_in_sat_cone": False,
        },
        "controls": {
            "frozen_ids": list(EXPECTED_CONTROL_IDS),
            "executed_ids": controls["executed_ids"],
        },
        "predictions": {
            "frozen_ids": list(EXPECTED_PREDICTION_IDS),
            "executed_ids": predictions["executed_ids"],
        },
    }

    require_equal(coverage["software"]["executed_h4_set_sha256"], CERTIFIED_H4_SET_SHA256, "executed H4 set hash")
    require_equal(tuple(coverage["software"]["executed_material_ids"]), EXPECTED_MATERIAL_IDS, "coverage material IDs")
    require_equal(tuple(coverage["software"]["executed_rounds"]), EXPECTED_ROUNDS, "coverage software rounds")
    require_equal(tuple(coverage["software"]["executed_block_ids"]), EXPECTED_BLOCK_IDS, "coverage block IDs")
    require_equal(tuple(coverage["rtl"]["executed_rounds"]), EXPECTED_RTL_ROUNDS, "coverage RTL rounds")
    require_equal(tuple(coverage["formal"]["executed_modes"]), EXPECTED_FORMAL_MODES, "coverage formal modes")
    require_equal(tuple(coverage["controls"]["executed_ids"]), EXPECTED_CONTROL_IDS, "coverage controls")
    require_equal(tuple(coverage["predictions"]["executed_ids"]), EXPECTED_PREDICTION_IDS, "coverage predictions")

    harness_checks = {
        "frozen_contract_validated": True,
        "software_sets_exact": True,
        "software_equivalence_exact": software["stage_a"]["byte_exact"]
        and software["stage_b"]["byte_exact"],
        "rtl_equivalence_exact": rtl["mismatches"] == 0,
        "formal_correct_unsat": formal["correct_proved_unsat"],
        "formal_mutations_sat_with_witnesses": formal[
            "all_mutations_sat_with_witnesses"
        ],
        "all_controls_detected": controls["all_detected"],
        "validity_controls_pass": predictions["validity_controls_pass"],
        "all_predictions_pass": predictions["all_predictions_pass"],
    }
    harness_valid = all(harness_checks.values())
    require_true(harness_valid, "offset-collapse harness is invalid")

    pinned_parameters = {
        "date_basis": PREREG_DATA["date_basis"],
        "graded_constraints": list(EXPECTED_GRADED_CONSTRAINTS),
        "question_ids": list(EXPECTED_QUESTION_IDS),
        "geometry": CONSTRUCTION["geometry"],
        "state_bytes": STATE_BYTES,
        "software_rounds": list(EXPECTED_ROUNDS),
        "rtl_rounds": list(EXPECTED_RTL_ROUNDS),
        "fixed_rtl_and_formal_h4_tuple": list(FIXED_H4),
        "linear_layer": CONSTRUCTION["linear_layer"],
        "mix_columns_matrix_hex_rows": CONSTRUCTION[
            "mix_columns_matrix_hex_rows"
        ],
        "original_recurrence": CONSTRUCTION["original_recurrence"],
        "stage_a_formula": CONSTRUCTION["stage_a"]["formula"],
        "stage_b_formula": CONSTRUCTION["stage_b"]["formula"],
        "stage_b_canonical_recurrence": CONSTRUCTION["stage_b"][
            "canonical_recurrence"
        ],
        "terminal_rule": CONSTRUCTION["stage_b"]["terminal_rule"],
        "raw_material_layout": CONSTRUCTION["raw_material"]["layout"],
        "raw_mask_offset_bytes": MATERIAL_MASK_BASE,
        "material_ids": list(EXPECTED_MATERIAL_IDS),
        "material_domains": [material["domain"] for material in materials],
        "block_ids": list(EXPECTED_BLOCK_IDS),
        "aggregate_encoding": AGGREGATE_ENCODING,
        "control_ids": list(EXPECTED_CONTROL_IDS),
        "prediction_ids": list(EXPECTED_PREDICTION_IDS),
        "formal_mode_ids": list(EXPECTED_FORMAL_MODES),
        "formal_scope": PREREG_DATA["formal_contract"]["scope"],
        "formal_proof_decomposition": PREREG_DATA["formal_contract"][
            "proof_decomposition"
        ],
        "formal_input_signals_by_mode": {
            mode: list(FORMAL_INPUT_SIGNALS[mode]) for mode in EXPECTED_FORMAL_MODES
        },
        "formal_arbitrary_input_bits_by_mode": {
            mode: FORMAL_INPUT_BITS[mode] for mode in EXPECTED_FORMAL_MODES
        },
        "compatibility_rule": CONSTRUCTION["raw_material"][
            "compatibility_rule"
        ],
    }

    deterministic_payload = {
        "schema": PREREG_DATA["receipt_contract"]["schema"],
        "status": PREREG_DATA["receipt_contract"]["status"],
        "inputs": inputs,
        "pinned_parameters": pinned_parameters,
        "coverage": coverage,
        "controls": controls,
        "equivalence": {
            "software": software,
            "sequential_rtl": rtl,
            "formal": formal,
        },
        "material_normal_form": normal_form,
        "interpretation": {
            "harness_validity_checks": harness_checks,
            "harness_valid": harness_valid,
            "verdict": VALID_VERDICTS[0],
            "passing_interpretation": PREREG_DATA["interpretation"][
                "passing_interpretation"
            ],
            "scope": PREREG_DATA["interpretation"]["scope"],
            "next": PREREG_DATA["interpretation"]["next"],
            "predictions": predictions,
            "internal_invalid_status_not_emitted": PREREG_DATA[
                "interpretation"
            ]["internal_invalid_status"],
            "claim_movement": False,
        },
        "limitations": list(PREREG_DATA["non_claims"]),
    }
    require_equal(tuple(deterministic_payload), EXPECTED_PAYLOAD_KEYS, "built payload keys")
    require_equal(deterministic_payload["status"], "OPEN_PROGRESS", "built receipt status")
    require_true(
        deterministic_payload["interpretation"]["verdict"] in VALID_VERDICTS,
        "built verdict is not allowed",
    )
    require_true(
        deterministic_payload["interpretation"]["verdict"]
        != "INVALID_OFFSET_COLLAPSE_HARNESS",
        "invalid harness status cannot be emitted",
    )

    digest = sha256_bytes(canonical_json_bytes(deterministic_payload))
    advisory = git_advisory()
    advisory["elapsed_seconds_single_run_not_a_claim"] = round(
        time.perf_counter() - started, 3
    )
    return {
        "deterministic_payload": deterministic_payload,
        "deterministic_payload_sha256": digest,
        "environment_advisory_excluded_from_digest": advisory,
        "no_wall_clock": (
            "No wall-clock timestamp is asserted; only deterministic inputs and "
            "outputs are graded."
        ),
    }


def atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_bytes(data)
    os.replace(temporary, path)


def print_summary(receipt: Mapping) -> None:
    payload = receipt["deterministic_payload"]
    software = payload["equivalence"]["software"]
    rtl = payload["equivalence"]["sequential_rtl"]
    formal = payload["equivalence"]["formal"]
    print("=" * 78)
    print("E256-H H3 XOR-OFFSET COLLAPSE  (OPEN_PROGRESS)")
    print("=" * 78)
    print(f"harness valid: {payload['interpretation']['harness_valid']}")
    print(
        "software: "
        f"Stage A {software['stage_a']['executed_comparisons']}, "
        f"Stage B {software['stage_b']['executed_comparisons']}, 0 mismatches"
    )
    print(
        "sequential RTL: "
        f"{rtl['executed_original_vs_canonical_comparisons']} comparisons, "
        f"{rtl['mismatches']} mismatches"
    )
    print(
        "formal: correct UNSAT="
        f"{formal['correct_proved_unsat']}, mutations SAT+witnesses="
        f"{formal['all_mutations_sat_with_witnesses']}"
    )
    print(f"all six controls detected: {payload['controls']['all_detected']}")
    print(f"verdict: {payload['interpretation']['verdict']}")
    print("NOTE: representation normal form only; no security or production claim")
    print(f"deterministic_payload_sha256: {receipt['deterministic_payload_sha256']}")


def check_prior_receipt(output: Path, receipt: Mapping) -> bool:
    if not output.is_file():
        print(f"CHECK FAILED: {output.relative_to(REPO)} does not exist")
        return False
    try:
        prior = json.loads(output.read_text(encoding="utf-8"))
        prior_payload = prior["deterministic_payload"]
        prior_digest = prior["deterministic_payload_sha256"]
    except (KeyError, TypeError, json.JSONDecodeError) as error:
        print(f"CHECK FAILED: malformed prior receipt: {error}")
        return False
    prior_payload_bytes = canonical_json_bytes(prior_payload)
    current_payload_bytes = canonical_json_bytes(receipt["deterministic_payload"])
    prior_digest_valid = sha256_bytes(prior_payload_bytes) == prior_digest
    payload_match = prior_payload_bytes == current_payload_bytes
    digest_match = prior_digest == receipt["deterministic_payload_sha256"]
    print(
        "reproducibility: "
        f"prior_digest_valid={prior_digest_valid} "
        f"payload_bytes_match={payload_match} digest_match={digest_match}"
    )
    return prior_digest_valid and payload_match and digest_match


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--json", default=str(RECEIPT.relative_to(REPO)))
    args = parser.parse_args()
    output = REPO / args.json

    try:
        receipt = build_receipt()
    except Exception as error:
        print(f"OFFSET-COLLAPSE GATE FAILED: {error}", file=sys.stderr)
        print(
            "No canonical receipt was emitted or accepted; status remains "
            "OPEN_PROGRESS.",
            file=sys.stderr,
        )
        return 1

    print_summary(receipt)
    if not receipt["deterministic_payload"]["interpretation"]["harness_valid"]:
        print("VALIDITY GATE FAILED — refusing receipt", file=sys.stderr)
        return 1

    if args.check:
        passed = check_prior_receipt(output, receipt)
        print("CHECK PASS" if passed else "CHECK FAIL")
        return 0 if passed else 1

    atomic_write(
        output,
        json.dumps(receipt, indent=2, sort_keys=True).encode("utf-8") + b"\n",
    )
    print(f"wrote {output.relative_to(REPO)}")
    print(
        "STATUS: OPEN_PROGRESS; no C/H/N claim, suite, profile, fixture, release "
        "gate, production RTL, XOF, or round count moved"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
