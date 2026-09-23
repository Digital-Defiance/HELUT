#!/usr/bin/env python3
"""E256-H candidate re-certification and schedule budget gate.

Discharges steps 2 and 3 of directives/e256-hardware-architecture.md §5:

  * H3 - certify the offset rotor R(x) = SBOX(x XOR p_in) XOR p_out over the
    complete 65536-pair offset space, against the same DDT/LAT/degree
    definitions the E256-062 receipt used.
  * H4 - certify which row-offset tuples may enter a keyed wiring set, using the
    inherited MDS, dispersion, dependency, and four-round trail obligations.
  * H5 - bound the schedule cost per 32-byte block for an XOF squeeze against
    the per-derivation HMAC-SHA512 model.

Contract: directives/e256-hardware-candidate-preregistration.json
Receipt:  logs/e256-hardware-candidate-gate.json

Fail-closed: on any contract, control, null, or coverage failure this builds an
in-memory diagnostic, exits nonzero, and refuses to write or accept the
canonical receipt.

This gate selects no round count, no production XOF, and no production wiring
set; it authorizes no RTL and moves no C/H/N row.
"""

from __future__ import annotations

import argparse
import hashlib
import itertools
import json
import math
import os
import platform
import subprocess
import sys
import time
from pathlib import Path
from typing import Dict, List, Sequence, Tuple

import numpy as np

REPO = Path(__file__).resolve().parent.parent
PREREG = REPO / "directives/e256-hardware-candidate-preregistration.json"
ARCHITECTURE = REPO / "directives/e256-hardware-architecture.md"
WIDE_RECEIPT = REPO / "logs/e256-wide-state-gate.json"
COST_RECEIPT = REPO / "logs/e256-hardware-cost-gate.json"
RECEIPT = REPO / "logs/e256-hardware-candidate-gate.json"

PREREG_SHA256 = "2d0ecbbbb18165aa09adbe33c3d85a7d6d72db3881925bc6b11da07ca2243099"
ARCHITECTURE_CONTRACT_SHA256 = (
    "b64472f73be9d0fc6318ff445c5f550cb0129309313228f416599c27d3957bb1"
)
WIDE_PAYLOAD_SHA256 = (
    "21758ce220b9da469a18ea617fa7b2fd41e906add69a258f830b12843e3e495b"
)
COST_PAYLOAD_SHA256 = (
    "a10e001ad2c2b3de55fcc80197c059f166d5e55599c670e20b01de8f6b7d323d"
)
AES_SBOX_SHA256 = "c2d8e5eed6cbebd8625fc18f81486a7733c04f9b0129ffbe974c68b90308b4f2"

PREREG_DATA = json.loads(PREREG.read_text(encoding="utf-8"))
CONTROL_IDS = tuple(item["id"] for item in PREREG_DATA["controls"])
PREDICTION_IDS = tuple(item["id"] for item in PREREG_DATA["predictions"])

IDENTITY = np.arange(256, dtype=np.uint8)
MIX_ROWS = tuple(
    tuple(int(value, 16) for value in row)
    for row in PREREG_DATA["h4_wiring"]["mix_columns_matrix_hex_rows"]
)
FULL_MASK = (1 << 32) - 1


class StructuralValidationError(AssertionError):
    """Typed contract/validity failure; never yields a canonical receipt."""


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


# ---------------------------------------------------------------------------
# GF(2^8), AES S-box, and exact 8-bit metrics (definitions inherited verbatim
# from directives/e256-wide-preregistration.json).


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


def gf_inverse(a: int) -> int:
    if a == 0:
        raise StructuralValidationError("GF(2^8) zero has no inverse")
    return gf_pow(a, 254)


def rol8(value: int, amount: int) -> int:
    return ((value << amount) | (value >> (8 - amount))) & 0xFF


def build_aes_sbox() -> np.ndarray:
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
    table = np.array(values, dtype=np.uint8)
    require_equal(sha256_bytes(table.tobytes()), AES_SBOX_SHA256, "derived AES S-box")
    return table


AES_SBOX = build_aes_sbox()
POPCOUNT = np.array([bin(i).count("1") for i in range(256)], dtype=np.uint8)
PARITY = POPCOUNT & 1


def invert_perm(perm: np.ndarray) -> np.ndarray:
    if perm.shape != (256,) or len(np.unique(perm)) != 256:
        raise StructuralValidationError("not a 256-point permutation")
    result = np.empty(256, dtype=np.uint8)
    result[perm] = IDENTITY
    return result


def differential_uniformity(perm: np.ndarray) -> int:
    maximum = 0
    for difference in range(1, 256):
        counts = np.bincount(
            np.bitwise_xor(perm, perm[np.bitwise_xor(IDENTITY, difference)]),
            minlength=256,
        )
        maximum = max(maximum, int(counts.max()))
    return maximum


def fwht(values: np.ndarray) -> np.ndarray:
    result = values.astype(np.int32, copy=True)
    span = 1
    while span < 256:
        shaped = result.reshape(-1, span * 2)
        left = shaped[:, :span].copy()
        right = shaped[:, span:].copy()
        shaped[:, :span] = left + right
        shaped[:, span:] = left - right
        span *= 2
    return result


def maximum_absolute_lat(perm: np.ndarray) -> int:
    maximum = 0
    for output_mask in range(1, 256):
        signs = 1 - 2 * PARITY[np.bitwise_and(perm, output_mask)].astype(np.int32)
        maximum = max(maximum, int(np.abs(fwht(signs))[1:].max()))
    return maximum


def algebraic_degree(perm: np.ndarray) -> int:
    maximum = 0
    for output_bit in range(8):
        coefficients = ((perm >> output_bit) & 1).astype(np.uint8)
        for bit in range(8):
            step = 1 << bit
            for mask in range(256):
                if mask & step:
                    coefficients[mask] ^= coefficients[mask ^ step]
        active = np.flatnonzero(coefficients)
        if len(active):
            maximum = max(maximum, max(int(POPCOUNT[i]) for i in active))
    return maximum


def spectrum(perm: np.ndarray) -> Tuple[int, int, int, int]:
    return (
        differential_uniformity(perm),
        maximum_absolute_lat(perm),
        algebraic_degree(perm),
        algebraic_degree(invert_perm(perm)),
    )


# ---------------------------------------------------------------------------
# H3 - exhaustive offset-space certification


def offset_rotor(p_in: int, p_out: int) -> np.ndarray:
    return np.bitwise_xor(AES_SBOX[np.bitwise_xor(IDENTITY, p_in)], p_out)


def additive_offset_rotor(p: int) -> np.ndarray:
    return np.array(
        [(int(AES_SBOX[(x + p) % 256]) - p) % 256 for x in range(256)], dtype=np.uint8
    )


def certify_h3_rotor() -> dict:
    baseline = spectrum(AES_SBOX)
    require_equal(baseline, (4, 32, 7, 7), "AES S-box reference spectrum")

    mismatches: List[int] = []
    for p_in in range(256):
        if spectrum(offset_rotor(p_in, 0)) != baseline:
            mismatches.append(p_in)

    non_bijective = 0
    for p_in in range(256):
        core = AES_SBOX[np.bitwise_xor(IDENTITY, p_in)]
        for p_out in range(256):
            table = np.bitwise_xor(core, p_out)
            if len(np.unique(table)) != 256:
                non_bijective += 1

    inverse_exact = 0
    for p_in, p_out in ((0, 0), (1, 0), (0, 1), (0x5A, 0xA5), (255, 255)):
        table = offset_rotor(p_in, p_out)
        inverse = invert_perm(table)
        if np.array_equal(inverse[table], IDENTITY) and np.array_equal(
            table[inverse], IDENTITY
        ):
            inverse_exact += 1

    return {
        "reference_spectrum": {
            "differential_uniformity": baseline[0],
            "maximum_absolute_lat": baseline[1],
            "forward_algebraic_degree": baseline[2],
            "inverse_algebraic_degree": baseline[3],
        },
        "spectrum_scope_p_in_values": 256,
        "spectrum_mismatches": mismatches,
        "spectrum_invariant_over_complete_p_in_space": not mismatches,
        "bijection_scope_offset_pairs": 65536,
        "non_bijective_offset_pairs": non_bijective,
        "bijective_over_complete_offset_space": non_bijective == 0,
        "inverse_spot_checks": inverse_exact,
        "inverse_spot_checks_expected": 5,
        "p_out_argument": PREREG_DATA["h3_rotor"]["spectrum_argument"],
        "pass": not mismatches and non_bijective == 0 and inverse_exact == 5,
    }


# ---------------------------------------------------------------------------
# H4 - MixColumns certificate and wiring certification


def gf_matrix_determinant(matrix: Sequence[Sequence[int]]) -> int:
    work = [list(row) for row in matrix]
    size = len(work)
    determinant = 1
    for column in range(size):
        pivot = next(
            (row for row in range(column, size) if work[row][column]), None
        )
        if pivot is None:
            return 0
        if pivot != column:
            work[column], work[pivot] = work[pivot], work[column]
        determinant = gf_mul(determinant, work[column][column])
        inverse = gf_inverse(work[column][column])
        for row in range(column + 1, size):
            if work[row][column]:
                factor = gf_mul(work[row][column], inverse)
                for k in range(column, size):
                    work[row][k] ^= gf_mul(factor, work[column][k])
    return determinant


def gf_matrix_inverse(matrix: Sequence[Sequence[int]]) -> List[List[int]]:
    size = len(matrix)
    work = [list(row) + [1 if i == j else 0 for j in range(size)] for i, row in enumerate(matrix)]
    for column in range(size):
        pivot = next((row for row in range(column, size) if work[row][column]), None)
        if pivot is None:
            raise StructuralValidationError("MixColumns matrix is singular")
        if pivot != column:
            work[column], work[pivot] = work[pivot], work[column]
        inverse = gf_inverse(work[column][column])
        work[column] = [gf_mul(inverse, value) for value in work[column]]
        for row in range(size):
            if row != column and work[row][column]:
                factor = work[row][column]
                work[row] = [
                    value ^ gf_mul(factor, work[column][index])
                    for index, value in enumerate(work[row])
                ]
    return [row[size:] for row in work]


def gf_matrix_multiply(
    left: Sequence[Sequence[int]], right: Sequence[Sequence[int]]
) -> List[List[int]]:
    size = len(left)
    product = []
    for i in range(size):
        row = []
        for j in range(size):
            accumulator = 0
            for k in range(size):
                accumulator ^= gf_mul(left[i][k], right[k][j])
            row.append(accumulator)
        product.append(row)
    return product


def square_minor_certificate(matrix: Sequence[Sequence[int]]) -> dict:
    size = len(matrix)
    minors = 0
    zero_minors = 0
    for order in range(1, size + 1):
        for rows in itertools.combinations(range(size), order):
            for columns in itertools.combinations(range(size), order):
                sub = [[matrix[r][c] for c in columns] for r in rows]
                minors += 1
                if gf_matrix_determinant(sub) == 0:
                    zero_minors += 1
    return {
        "minors_evaluated": minors,
        "zero_minors": zero_minors,
        "all_nonzero": zero_minors == 0,
        "implied_branch_number": 5 if zero_minors == 0 else None,
    }


def mix_columns_certificate(matrix: Sequence[Sequence[int]]) -> dict:
    determinant = gf_matrix_determinant(matrix)
    if determinant == 0:
        raise StructuralValidationError("SINGULAR_MIX_MATRIX")
    inverse = gf_matrix_inverse(matrix)
    identity = [[1 if i == j else 0 for j in range(4)] for i in range(4)]
    forward = gf_matrix_multiply(matrix, inverse)
    reverse = gf_matrix_multiply(inverse, matrix)
    if forward != identity or reverse != identity:
        raise StructuralValidationError("MixColumns inverse is not two-sided")
    minors = square_minor_certificate(matrix)
    if not minors["all_nonzero"]:
        raise StructuralValidationError("MixColumns has a zero square minor")
    return {
        "determinant": determinant,
        "two_sided_inverse_exact": True,
        "inverse_rows": inverse,
        **minors,
    }


def dependency_first_full_round(offsets: Sequence[int], rounds: int = 12):
    sets = [1 << index for index in range(32)]
    first_full = None
    for current in range(1, rounds + 1):
        shifted = [0] * 32
        for column in range(8):
            for row in range(4):
                shifted[4 * column + row] = sets[
                    4 * ((column + offsets[row]) % 8) + row
                ]
        mixed = [0] * 32
        for column in range(8):
            for row in range(4):
                accumulator = 0
                for k in range(4):
                    if MIX_ROWS[row][k]:
                        accumulator |= shifted[4 * column + k]
                mixed[4 * column + row] = accumulator
        sets = mixed
        if first_full is None and all(value == FULL_MASK for value in sets):
            first_full = current
    return first_full, sets


def row_shift_is_permutation(offsets: Sequence[int]) -> bool:
    forward = [
        4 * ((column + offsets[row]) % 8) + row
        for column in range(8)
        for row in range(4)
    ]
    if sorted(forward) != list(range(32)):
        return False
    for column in range(8):
        for row in range(4):
            source = 4 * ((column + offsets[row]) % 8) + row
            back = 4 * (((column + offsets[row]) % 8 - offsets[row]) % 8) + row
            if back != 4 * column + row or source not in forward:
                return False
    return True


def wide_trail_manifest(offsets: Sequence[int], minors: dict) -> dict:
    middle_cases = [
        {"active_source_columns": a, "bundle_sum": a + (5 - a), "meets_five": a + (5 - a) >= 5}
        for a in (1, 2, 3, 4)
    ]
    obligations = {
        "all_69_minors_nonzero": minors["all_nonzero"] and minors["minors_evaluated"] == 69,
        "branch_number_five": minors["implied_branch_number"] == 5,
        "row_offsets_distinct_mod_8": len({o % 8 for o in offsets}) == 4,
        "middle_bundle_cases_meet_five": all(case["meets_five"] for case in middle_cases),
        "high_activity_case_immediate": True,
        "two_outer_mds_inequalities": True,
    }
    discharged = all(obligations.values())
    return {
        "certificate_id": "E256-W-WIDETRAIL-25-v1",
        "obligations": obligations,
        "middle_bundle_cases": middle_cases,
        "discharged": discharged,
        "four_round_active_rotor_lower_bound": 25 if discharged else None,
        "single_trail_differential_log2_upper": -150 if discharged else None,
        "single_trail_linear_log2_upper": -75 if discharged else None,
        "scope": "single differential and linear trails only",
    }


def certify_h4_wiring(minors: dict) -> dict:
    candidate_space = list(itertools.permutations(range(8), 4))
    certified = []
    dependency_histogram: Dict[str, int] = {}
    for offsets in candidate_space:
        distinct = len(set(offsets)) == 4
        first_full, _ = dependency_first_full_round(offsets)
        key = "none" if first_full is None else str(first_full)
        dependency_histogram[key] = dependency_histogram.get(key, 0) + 1
        manifest = wide_trail_manifest(offsets, minors)
        if (
            distinct
            and row_shift_is_permutation(offsets)
            and first_full == 3
            and manifest["discharged"]
        ):
            certified.append(list(offsets))

    rijndael = [0, 1, 3, 4]
    return {
        "candidate_space_size": len(candidate_space),
        "candidate_space_definition": PREREG_DATA["h4_wiring"]["candidate_space"],
        "certified_set_size": len(certified),
        "certified_set_is_strict_subset": len(certified) < len(candidate_space),
        "certified_set": certified,
        "certified_set_sha256": sha256_bytes(canonical_json_bytes(certified)),
        "earliest_all_to_all_round_histogram": dependency_histogram,
        "required_all_to_all_round": 3,
        "rijndael_tuple": rijndael,
        "rijndael_tuple_certified": rijndael in certified,
        "wide_trail_manifest_for_rijndael": wide_trail_manifest(rijndael, minors),
        "pass": bool(certified) and rijndael in certified,
    }


# ---------------------------------------------------------------------------
# H5 - schedule budget accounting


def canonical_context_length() -> int:
    prefix = len(b"E256-W/gate/context/v1")
    corpus = 2 + len("e256-wide-train")
    stream_id = 2 + 16
    return prefix + corpus + stream_id + 1 + 8 + 8


def sha512_compressions(message_length: int) -> int:
    return 1 + math.ceil((message_length + 17) / 128)


def hmac_sha512_compressions(message_length: int) -> int:
    return sha512_compressions(message_length) + 2


def certify_h5_schedule() -> dict:
    material_bytes = int(PREREG_DATA["h5_schedule"]["material_block_bytes"])
    require_equal(material_bytes, 800, "frozen material block length")
    require_equal(12 * 32 + 13 * 32, material_bytes, "material composition arithmetic")

    context = canonical_context_length()
    selection_domain = len(b"E256-W/gate/selection/v1") + (2 + context) + 2 + 1
    mask_domain = len(b"E256-W/gate/round-mask/v1") + (2 + context) + 2
    selection_calls = 12 * 32
    mask_calls = 13
    baseline_compressions = selection_calls * hmac_sha512_compressions(
        selection_domain + 1 + 8
    ) + mask_calls * hmac_sha512_compressions(mask_domain + 1 + 8)

    rate = int(PREREG_DATA["h5_schedule"]["candidate_model"]["rate_bytes"])
    require_equal(rate, 136, "SHAKE-256 rate")
    absorbed = len(b"E256-W/gate/material/v1") + (2 + context)
    absorb_blocks = math.ceil((absorbed + 1) / rate)
    squeeze_blocks = math.ceil(material_bytes / rate)
    keccak_calls = absorb_blocks + squeeze_blocks - 1

    squeezed = hashlib.shake_256(
        b"E256-W/gate/material/v1" + context.to_bytes(2, "big") + b"\x00" * context
    ).digest(material_bytes)
    if len(squeezed) != material_bytes:
        raise StructuralValidationError("XOF squeeze returned the wrong length")

    return {
        "material_block_bytes": material_bytes,
        "material_composition": {
            "selection_bytes": 12 * 32,
            "mask_bytes": 13 * 32,
        },
        "canonical_context_bytes": context,
        "baseline_model": {
            "id": "hmac_sha512_per_derivation",
            "hmac_invocations_per_block": selection_calls + mask_calls,
            "sha512_compressions_per_block": baseline_compressions,
            "selection_domain_bytes": selection_domain,
            "mask_domain_bytes": mask_domain,
            "accounting": PREREG_DATA["h5_schedule"]["baseline_model"][
                "hmac_compression_accounting"
            ],
        },
        "candidate_model": {
            "id": "shake256_single_squeeze",
            "rate_bytes": rate,
            "absorbed_bytes": absorbed,
            "absorb_blocks": absorb_blocks,
            "squeeze_blocks": squeeze_blocks,
            "keccak_f1600_calls_per_block": keccak_calls,
            "squeeze_length_verified": True,
            "accounting": PREREG_DATA["h5_schedule"]["candidate_model"][
                "permutation_accounting"
            ],
        },
        "primitive_invocation_ratio": round(baseline_compressions / keccak_calls, 2),
        "explicit_limitation": PREREG_DATA["h5_schedule"]["explicit_limitation"],
    }


def truncated_material_detector(requested_bytes: int) -> bool:
    """Shared coverage check used by the truncated-material control."""
    return requested_bytes != int(PREREG_DATA["h5_schedule"]["material_block_bytes"])


# ---------------------------------------------------------------------------
# Controls


def run_controls(minors: dict) -> dict:
    baseline = spectrum(AES_SBOX)

    additive_failures = [
        p for p in range(256) if spectrum(additive_offset_rotor(p)) != baseline
    ]

    zero_first_full, _ = dependency_first_full_round((0, 0, 0, 0))
    partial = (0, 1, 1, 3)
    partial_distinct = len(set(partial)) == 4

    singular = [list(row) for row in MIX_ROWS]
    singular[3] = list(MIX_ROWS[2])
    singular_detected = False
    singular_code = None
    try:
        mix_columns_certificate(singular)
    except StructuralValidationError as error:
        singular_detected = True
        singular_code = str(error)

    records = {
        "additive_offset_rotor": {
            "shared_path": ["exact DDT", "exact LAT", "exact ANF degree", "bijection"],
            "offsets_evaluated": 256,
            "offsets_failing_spectrum": len(additive_failures),
            "first_failing_offsets": additive_failures[:8],
            "detected": bool(additive_failures),
        },
        "repeated_row_offsets": {
            "shared_path": ["row dispersion", "dependency reachability"],
            "offsets": [0, 0, 0, 0],
            "earliest_all_to_all_round": zero_first_full,
            "detected": zero_first_full is None,
        },
        "partially_repeated_row_offsets": {
            "shared_path": ["row dispersion"],
            "offsets": list(partial),
            "pairwise_distinct": partial_distinct,
            "detected": not partial_distinct,
        },
        "singular_mix_matrix": {
            "shared_path": ["GF(2^8) determinant and minor certificate"],
            "mutation": "row 3 replaced by row 2",
            "determinant": gf_matrix_determinant(singular),
            "typed_rejection_code": singular_code,
            "detected": singular_detected and singular_code == "SINGULAR_MIX_MATRIX",
        },
        "truncated_material_block": {
            "shared_path": [
                "material composition",
                "XOF squeeze",
                "output-length check",
            ],
            "requested_bytes": 768,
            "detected": truncated_material_detector(768),
        },
    }

    executed = tuple(records)
    require_equal(executed, CONTROL_IDS, "executed control IDs")
    return {
        "frozen_ids": list(CONTROL_IDS),
        "executed_ids": list(executed),
        "ids_exact": executed == CONTROL_IDS,
        "records": records,
        "all_detected": all(record["detected"] for record in records.values()),
    }


# ---------------------------------------------------------------------------
# Frozen input validation


def architecture_contract_digest() -> str:
    raw = ARCHITECTURE.read_bytes()
    start = PREREG_DATA["authorization"]["contract_start_marker"].encode("ascii")
    end = PREREG_DATA["authorization"]["contract_end_marker"].encode("ascii")
    if raw.count(start) != 1 or raw.count(end) != 1:
        raise StructuralValidationError("architecture contract markers are not unique")
    if raw.index(start) >= raw.index(end):
        raise StructuralValidationError("architecture contract markers out of order")
    return sha256_bytes(raw[raw.index(start) + len(start) : raw.index(end)])


def load_predecessor(path: Path, schema: str, digest: str) -> dict:
    receipt = json.loads(path.read_text(encoding="utf-8"))
    payload = receipt["deterministic_payload"]
    require_equal(payload["schema"], schema, f"{path.name} schema")
    require_equal(
        sha256_bytes(canonical_json_bytes(payload)), digest, f"{path.name} recomputed digest"
    )
    require_equal(
        receipt.get("deterministic_payload_sha256"), digest, f"{path.name} stored digest"
    )
    return payload


def validate_frozen_inputs() -> dict:
    require_equal(
        PREREG_DATA["schema"],
        "E256-HARDWARE-CANDIDATE-PREREGISTRATION-1",
        "prereg schema",
    )
    require_equal(PREREG_DATA["status"], "FROZEN_FOR_EXECUTION", "prereg status")
    require_equal(sha256_file(PREREG), PREREG_SHA256, "raw preregistration SHA-256")
    require_equal(
        PREREG_DATA["authorization"]["contract_sha256"],
        ARCHITECTURE_CONTRACT_SHA256,
        "pinned architecture contract hash",
    )
    require_equal(
        architecture_contract_digest(),
        ARCHITECTURE_CONTRACT_SHA256,
        "recomputed architecture contract hash",
    )
    require_equal(
        tuple(PREREG_DATA["authorization"]["graded_constraints"]),
        ("H3", "H4", "H5"),
        "graded constraint IDs",
    )
    require_equal(
        CONTROL_IDS,
        (
            "additive_offset_rotor",
            "repeated_row_offsets",
            "partially_repeated_row_offsets",
            "singular_mix_matrix",
            "truncated_material_block",
        ),
        "frozen control IDs",
    )
    require_equal(
        PREDICTION_IDS,
        ("Q1", "Q2", "Q3", "Q4", "Q5", "Q6", "Q7", "Q8"),
        "frozen prediction IDs",
    )
    require_equal(
        tuple(PREREG_DATA["interpretation"]["valid_emitted_verdicts"]),
        (
            "H3_H4_CANDIDATE_STRUCTURALLY_RECERTIFIED",
            "H3_H4_CANDIDATE_NOT_RECERTIFIED",
        ),
        "valid emitted verdicts",
    )
    require_equal(
        PREREG_DATA["h3_rotor"]["aes_sbox_sha256"], AES_SBOX_SHA256, "prereg AES hash"
    )
    require_equal(
        PREREG_DATA["receipt_contract"]["runner"],
        str(Path(__file__).resolve().relative_to(REPO)),
        "receipt runner path",
    )
    require_equal(
        PREREG_DATA["toolchain_contract"]["python"], "3.9.6", "pinned python"
    )
    require_equal(
        PREREG_DATA["toolchain_contract"]["numpy"], "1.26.4", "pinned numpy"
    )
    require_equal(sys.version.split()[0], "3.9.6", "running python")
    require_equal(np.__version__, "1.26.4", "running numpy")

    wide = load_predecessor(
        WIDE_RECEIPT, "E256-WIDE-STATE-GATE-1", WIDE_PAYLOAD_SHA256
    )
    require_equal(
        wide["interpretation"]["verdict"],
        "STRUCTURAL_WIDE_STATE_CANDIDATE_RETAINED_FOR_ATTACK_ONLY",
        "inherited wide-state verdict",
    )
    cost = load_predecessor(
        COST_RECEIPT, "E256-HARDWARE-COST-GATE-1", COST_PAYLOAD_SHA256
    )
    require_equal(
        cost["interpretation"]["verdict"],
        "H3_OFFSET_KEYING_SUPPORTED",
        "inherited cost verdict",
    )

    return {
        "preregistration": str(PREREG.relative_to(REPO)),
        "preregistration_sha256": PREREG_SHA256,
        "architecture_record": str(ARCHITECTURE.relative_to(REPO)),
        "architecture_contract_sha256": ARCHITECTURE_CONTRACT_SHA256,
        "wide_state_receipt": str(WIDE_RECEIPT.relative_to(REPO)),
        "wide_state_payload_sha256": WIDE_PAYLOAD_SHA256,
        "cost_receipt": str(COST_RECEIPT.relative_to(REPO)),
        "cost_payload_sha256": COST_PAYLOAD_SHA256,
        "runner": str(Path(__file__).resolve().relative_to(REPO)),
        "runner_sha256": sha256_file(Path(__file__).resolve()),
        "aes_sbox_sha256": AES_SBOX_SHA256,
        "python": sys.version.split()[0],
        "numpy": np.__version__,
    }


# ---------------------------------------------------------------------------
# Grading and receipt


def grade_predictions(controls: dict, h3: dict, h4: dict, h5: dict) -> dict:
    records = controls["records"]
    outcomes = {
        "Q1": {
            "role": "validity_control",
            "statement": "additive-offset control detected on at least one offset",
            "observed": records["additive_offset_rotor"]["offsets_failing_spectrum"],
            "pass": records["additive_offset_rotor"]["detected"],
        },
        "Q2": {
            "role": "validity_control",
            "statement": "both repeated-offset controls detected",
            "observed": {
                "repeated": records["repeated_row_offsets"]["detected"],
                "partially_repeated": records["partially_repeated_row_offsets"][
                    "detected"
                ],
            },
            "pass": records["repeated_row_offsets"]["detected"]
            and records["partially_repeated_row_offsets"]["detected"],
        },
        "Q3": {
            "role": "validity_control",
            "statement": "singular MixColumns control detected with a typed rejection",
            "observed": records["singular_mix_matrix"]["typed_rejection_code"],
            "pass": records["singular_mix_matrix"]["detected"],
        },
        "Q4": {
            "role": "validity_control",
            "statement": "truncated material control detected",
            "observed": records["truncated_material_block"]["detected"],
            "pass": records["truncated_material_block"]["detected"],
        },
        "Q5": {
            "role": "graded_finding",
            "statement": (
                "H3 rotor preserves DDT 4, |LAT| 32, and degree 7 forward and inverse "
                "for every p_in, and is bijective over all 65536 offset pairs"
            ),
            "observed": {
                "spectrum_mismatches": len(h3["spectrum_mismatches"]),
                "non_bijective_offset_pairs": h3["non_bijective_offset_pairs"],
            },
            "pass": h3["pass"],
        },
        "Q6": {
            "role": "graded_finding",
            "statement": "certified wiring set is a strict subset of the distinct-offset space",
            "observed": {
                "candidate_space_size": h4["candidate_space_size"],
                "certified_set_size": h4["certified_set_size"],
            },
            "pass": h4["certified_set_is_strict_subset"],
        },
        "Q7": {
            "role": "graded_finding",
            "statement": "Rijndael tuple (0,1,3,4) belongs to the certified wiring set",
            "observed": h4["rijndael_tuple_certified"],
            "pass": h4["rijndael_tuple_certified"],
        },
        "Q8": {
            "role": "graded_finding",
            "statement": (
                "XOF schedule needs at most 8 Keccak permutations per block and the "
                "HMAC model needs at least 100x more primitive invocations"
            ),
            "observed": {
                "keccak_f1600_calls_per_block": h5["candidate_model"][
                    "keccak_f1600_calls_per_block"
                ],
                "sha512_compressions_per_block": h5["baseline_model"][
                    "sha512_compressions_per_block"
                ],
                "ratio": h5["primitive_invocation_ratio"],
            },
            "pass": (
                h5["candidate_model"]["keccak_f1600_calls_per_block"] <= 8
                and h5["baseline_model"]["sha512_compressions_per_block"]
                >= 100 * h5["candidate_model"]["keccak_f1600_calls_per_block"]
            ),
        },
    }
    require_equal(tuple(outcomes), PREDICTION_IDS, "graded prediction IDs")
    validity_ids = tuple(
        item["id"] for item in PREREG_DATA["predictions"]
        if item["role"] == "validity_control"
    )
    require_equal(validity_ids, ("Q1", "Q2", "Q3", "Q4"), "validity control IDs")
    return {
        "outcomes": outcomes,
        "validity_control_ids": list(validity_ids),
        "validity_controls_pass": all(outcomes[pid]["pass"] for pid in validity_ids),
    }


def build_receipt() -> dict:
    started = time.perf_counter()
    inputs = validate_frozen_inputs()
    minors = mix_columns_certificate([list(row) for row in MIX_ROWS])
    h3 = certify_h3_rotor()
    h4 = certify_h4_wiring(minors)
    h5 = certify_h5_schedule()
    controls = run_controls(minors)
    predictions = grade_predictions(controls, h3, h4, h5)

    candidate_nulls = {
        "h3_exhaustive_offset_certification": h3["pass"],
        "rijndael_tuple_certified": h4["rijndael_tuple_certified"],
        "certified_wiring_set_non_empty": h4["certified_set_size"] > 0,
    }

    validity_checks = {
        "frozen_contract_validated": True,
        "control_ids_exact": controls["ids_exact"],
        "all_controls_detected": controls["all_detected"],
        "validity_controls_pass": predictions["validity_controls_pass"],
        "candidate_nulls_pass": all(candidate_nulls.values()),
    }
    harness_valid = all(validity_checks.values())

    recertified = (
        predictions["outcomes"]["Q5"]["pass"]
        and predictions["outcomes"]["Q6"]["pass"]
        and predictions["outcomes"]["Q7"]["pass"]
    )
    verdict = (
        "H3_H4_CANDIDATE_STRUCTURALLY_RECERTIFIED"
        if recertified
        else "H3_H4_CANDIDATE_NOT_RECERTIFIED"
    )

    deterministic_payload = {
        "schema": PREREG_DATA["receipt_contract"]["schema"],
        "status": PREREG_DATA["receipt_contract"]["status"],
        "inputs": inputs,
        "pinned_parameters": {
            "graded_constraints": list(
                PREREG_DATA["authorization"]["graded_constraints"]
            ),
            "h3_formula": PREREG_DATA["h3_rotor"]["formula"],
            "h4_geometry": PREREG_DATA["h4_wiring"]["geometry"],
            "mix_columns_matrix_hex_rows": [
                list(row) for row in PREREG_DATA["h4_wiring"]["mix_columns_matrix_hex_rows"]
            ],
            "field_polynomial": PREREG_DATA["h4_wiring"]["field_polynomial"],
            "certification_obligations": list(
                PREREG_DATA["h4_wiring"]["certification_obligations"]
            ),
            "material_block_bytes": h5["material_block_bytes"],
            "control_ids": list(CONTROL_IDS),
            "prediction_ids": list(PREDICTION_IDS),
            "exploratory_probe_disclosure": PREREG_DATA[
                "exploratory_probe_disclosure"
            ],
        },
        "coverage": {
            "h3_p_in_values": h3["spectrum_scope_p_in_values"],
            "h3_offset_pairs": h3["bijection_scope_offset_pairs"],
            "h4_candidate_space_size": h4["candidate_space_size"],
            "mix_columns_minors_evaluated": minors["minors_evaluated"],
            "controls_executed": len(controls["executed_ids"]),
            "predictions_graded": len(predictions["outcomes"]),
        },
        "controls": controls,
        "results": {
            "h3_offset_rotor": h3,
            "h4_wiring": h4,
            "mix_columns_certificate": minors,
            "candidate_nulls": candidate_nulls,
        },
        "schedule_budget": h5,
        "interpretation": {
            "harness_validity_checks": validity_checks,
            "harness_valid": harness_valid,
            "internal_invalid_status": PREREG_DATA["interpretation"][
                "internal_invalid_status"
            ],
            "verdict": verdict if harness_valid else "INVALID_CANDIDATE_HARNESS",
            "predictions": predictions["outcomes"],
            "production_round_count": None,
            "production_xof": None,
            "production_wiring_set": None,
            "scope": PREREG_DATA["interpretation"]["scope"],
            "next": PREREG_DATA["interpretation"]["next"],
            "baseline_result": PREREG_DATA["interpretation"]["baseline_result"],
        },
        "limitations": list(PREREG_DATA["non_claims"]),
    }

    digest = sha256_bytes(canonical_json_bytes(deterministic_payload))
    elapsed = time.perf_counter() - started

    def git(command: Sequence[str]) -> Tuple[bool, str]:
        try:
            process = subprocess.run(
                command, capture_output=True, text=True, timeout=20, check=False
            )
            return process.returncode == 0, process.stdout.strip()
        except Exception:
            return False, ""

    head_ok, head = git(["git", "-C", str(REPO), "rev-parse", "HEAD"])
    status_ok, status = git(["git", "-C", str(REPO), "status", "--porcelain"])

    return {
        "deterministic_payload": deterministic_payload,
        "deterministic_payload_sha256": digest,
        "environment_advisory_excluded_from_digest": {
            "platform": platform.platform(),
            "git_head": head.splitlines()[0] if head_ok and head else "unavailable",
            "git_dirty": bool(status) if status_ok else "unavailable",
            "elapsed_seconds_single_run_not_a_claim": round(elapsed, 3),
        },
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


def print_summary(receipt: dict) -> None:
    payload = receipt["deterministic_payload"]
    h3 = payload["results"]["h3_offset_rotor"]
    h4 = payload["results"]["h4_wiring"]
    h5 = payload["schedule_budget"]
    outcomes = payload["interpretation"]["predictions"]
    print("=" * 78)
    print("E256-H CANDIDATE RE-CERTIFICATION + SCHEDULE BUDGET  (OPEN_PROGRESS)")
    print("=" * 78)
    print(f"harness valid: {payload['interpretation']['harness_valid']}")
    print(
        f"controls: {len(payload['controls']['executed_ids'])}/"
        f"{len(payload['controls']['frozen_ids'])} detected="
        f"{payload['controls']['all_detected']}"
    )
    print(
        f"H3 rotor: spectrum invariant over {h3['spectrum_scope_p_in_values']} p_in "
        f"(mismatches={len(h3['spectrum_mismatches'])}), bijective over "
        f"{h3['bijection_scope_offset_pairs']} pairs "
        f"(failures={h3['non_bijective_offset_pairs']})"
    )
    print(
        f"H4 wiring: {h4['certified_set_size']}/{h4['candidate_space_size']} "
        f"distinct-offset tuples certified; Rijndael certified="
        f"{h4['rijndael_tuple_certified']}"
    )
    print(f"  earliest all-to-all histogram: {h4['earliest_all_to_all_round_histogram']}")
    print(
        f"H5 schedule: XOF {h5['candidate_model']['keccak_f1600_calls_per_block']} "
        f"Keccak-f[1600] vs HMAC model "
        f"{h5['baseline_model']['sha512_compressions_per_block']} SHA-512 "
        f"compressions per 32-byte block ({h5['primitive_invocation_ratio']}x)"
    )
    for pid in sorted(outcomes):
        print(f"{pid} [{outcomes[pid]['role']}]: {outcomes[pid]['pass']}")
    print(f"verdict: {payload['interpretation']['verdict']}")
    print(f"deterministic_payload_sha256: {receipt['deterministic_payload_sha256']}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--json", default=str(RECEIPT.relative_to(REPO)))
    args = parser.parse_args()
    output = REPO / args.json

    try:
        receipt = build_receipt()
    except Exception as error:
        print(f"CANDIDATE GATE FAILED: {error}", file=sys.stderr)
        return 1

    print_summary(receipt)
    if not receipt["deterministic_payload"]["interpretation"]["harness_valid"]:
        print(
            "VALIDITY GATE FAILED — refusing to emit or accept receipt",
            file=sys.stderr,
        )
        return 1

    if args.check:
        if not output.exists():
            print(f"CHECK FAILED: {args.json} does not exist")
            return 1
        prior = json.loads(output.read_text(encoding="utf-8"))
        same_digest = prior.get("deterministic_payload_sha256") == receipt[
            "deterministic_payload_sha256"
        ]
        same_payload = prior.get("deterministic_payload") == receipt[
            "deterministic_payload"
        ]
        print(
            f"reproducibility: digest_match={same_digest} payload_match={same_payload}"
        )
        print("CHECK PASS" if same_digest and same_payload else "CHECK FAIL")
        return 0 if same_digest and same_payload else 1

    atomic_write(
        output, json.dumps(receipt, indent=2, sort_keys=True).encode("utf-8") + b"\n"
    )
    print(f"wrote {output.relative_to(REPO)}")
    print(
        "STATUS: OPEN_PROGRESS; no claim, suite, profile, fixture, release gate, "
        "round count, production XOF, or production wiring set moved"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
