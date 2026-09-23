#!/usr/bin/env python3
"""Deterministic E256-W wide-state structural gate.

STATUS: OPEN_PROGRESS model, structural-certificate, ablation, and attack-harness
research only. This runner implements the frozen machine-readable contract at
`directives/e256-wide-preregistration.json`. It does not define a cipher suite,
select a production round count, move a C/H/N row, or authorize real-data use.

Usage:
  python3 Scripts/e256_wide_gate.py
  python3 Scripts/e256_wide_gate.py --check
"""

from __future__ import annotations

import argparse
import hashlib
import hmac
import itertools
import json
import os
import platform
import re
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Set, Tuple

import numpy as np


REPO = Path(__file__).resolve().parent.parent
PREREG = REPO / "directives/e256-wide-preregistration.json"
ARCHITECTURE = REPO / "directives/e256-wide-architecture.md"
PREDECESSOR_RECEIPT = REPO / "logs/e256-vnext-rotor-schedule-bakeoff.json"
RECEIPT = REPO / "logs/e256-wide-state-gate.json"

PREREG_SHA256 = "686df3175e91555ee1983bdf4a12fe8f28c463128e06985f3baa1d7777b34c42"
ARCHITECTURE_CONTRACT_SHA256 = (
    "1f18c46884d13b010dca9a8217eb8d5472cb5b85fac59ec9ba886defb8fc4c5d"
)
PREDECESSOR_PAYLOAD_SHA256 = (
    "fd54809cbd12de9d6f14151bcd401232aae765b72cb8368128ea54bdfa7b7197"
)
AES_SBOX_SHA256 = "c2d8e5eed6cbebd8625fc18f81486a7733c04f9b0129ffbe974c68b90308b4f2"
EXPECTED_PYTHON = "3.9.6"
EXPECTED_NUMPY = "1.26.4"

PREREG_TOP_LEVEL_KEYS = (
    "schema",
    "status",
    "revision",
    "date_basis",
    "toolchain_contract",
    "authorization",
    "predecessor",
    "questions",
    "non_claims",
    "byte_encodings",
    "experimental_kdf",
    "execution_serialization",
    "construction",
    "metric_definitions",
    "theorem_targets",
    "corpus",
    "baselines",
    "planted_controls",
    "control_execution_contract",
    "metrics",
    "hard_rejection_rules",
    "interpretation",
    "receipt_contract",
)
PAYLOAD_TOP_LEVEL_KEYS = (
    "schema",
    "status",
    "inputs",
    "pinned_parameters",
    "coverage",
    "controls",
    "baselines",
    "results",
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
VALID_VERDICTS = (
    "WIDE_STATE_CANDIDATE_REJECTED",
    "STRUCTURAL_WIDE_STATE_CANDIDATE_RETAINED_FOR_ATTACK_ONLY",
)

EXTRACT_KEY = b"E256-W/gate/extract/v1"
CONTEXT_PREFIX = b"E256-W/gate/context/v1"
ROTOR_PREFIX = b"E256-W/gate/rotor/v1"
SELECTION_PREFIX = b"E256-W/gate/selection/v1"
MASK_PREFIX = b"E256-W/gate/round-mask/v1"
RECIPROCAL_CONTROL_DOMAIN = b"E256-W/gate/control/reciprocal-sandwich/v1"
MAX_U64 = (1 << 64) - 1

MIX_MATRIX = (
    (0x02, 0x03, 0x01, 0x01),
    (0x01, 0x02, 0x03, 0x01),
    (0x01, 0x01, 0x02, 0x03),
    (0x03, 0x01, 0x01, 0x02),
)
IDENTITY_MIX_MATRIX = (
    (0x01, 0x00, 0x00, 0x00),
    (0x00, 0x01, 0x00, 0x00),
    (0x00, 0x00, 0x01, 0x00),
    (0x00, 0x00, 0x00, 0x01),
)
ROW_OFFSETS = (0, 1, 3, 4)
ZERO_ROW_OFFSETS = (0, 0, 0, 0)
ROUND_COUNTS = tuple(range(1, 13))
LANES = tuple(range(32))
MASK_INDICES = tuple(range(13))

POPCOUNT_BYTE = np.array([bin(value).count("1") for value in range(256)], dtype=np.uint8)
PARITY_BYTE = np.array([bin(value).count("1") & 1 for value in range(256)], dtype=np.uint8)
IDENTITY_U8 = np.arange(256, dtype=np.uint8)
LANE_INDEX = np.arange(32, dtype=np.int64)

AES_SBOX: Optional[np.ndarray] = None
AES_SBOX_INVERSE: Optional[np.ndarray] = None
GF_TABLE: Optional[np.ndarray] = None


class ContractError(RuntimeError):
    """Frozen input or operational contract mismatch."""


class HarnessInvalid(RuntimeError):
    """Control, null, or coverage failure that forbids receipt emission."""

    def __init__(self, diagnostic: dict) -> None:
        super().__init__("INVALID_CONTROLS_OR_CONTRACT")
        self.diagnostic = diagnostic


class StructuralError(RuntimeError):
    """Typed structural rejection used by the singular-matrix control."""

    def __init__(self, code: str, details: dict) -> None:
        super().__init__(code)
        self.code = code
        self.details = details


# ---------------------------------------------------------------------------
# Strict JSON, canonical bytes, ranges, and deterministic type checks


def _reject_constant(value: str):
    raise ContractError("non-finite JSON constant is forbidden: " + value)


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ContractError("duplicate JSON object key: " + str(key))
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
        raise ContractError(f"could not strictly parse {path}: {error}") from error


def canonical_json_bytes(value) -> bytes:
    return json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def require_equal(actual, expected, label: str) -> None:
    if actual != expected:
        raise ContractError(f"{label} mismatch: expected {expected!r}, got {actual!r}")


def require_true(condition: bool, label: str) -> None:
    if not condition:
        raise ContractError(label)


def _integer(value: int, minimum: int, maximum: int, label: str) -> int:
    if type(value) is not int or value < minimum or value > maximum:
        raise ValueError(f"{label} outside {minimum}...{maximum}")
    return value


def u8(value: int) -> bytes:
    return bytes([_integer(value, 0, 255, "u8")])


def u16be(value: int) -> bytes:
    return _integer(value, 0, 65535, "u16be").to_bytes(2, "big")


def u64be(value: int) -> bytes:
    return _integer(value, 0, MAX_U64, "u64be").to_bytes(8, "big")


def field(value: bytes) -> bytes:
    if not isinstance(value, bytes):
        raise TypeError("field value must be bytes")
    if len(value) > 65535:
        raise ValueError("field exceeds frozen u16 byte length")
    return u16be(len(value)) + value


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
                raise ContractError(f"non-string deterministic key at {path}")
            validate_deterministic_types(item, f"{path}.{key}")
        return
    raise ContractError(
        f"non-canonical deterministic value at {path}: {type(value).__name__}"
    )


class ManifestHasher:
    """Length-delimited canonical-record manifest without floating values."""

    def __init__(self) -> None:
        self._hash = hashlib.sha256()
        self.count = 0

    def update(self, value) -> None:
        validate_deterministic_types(value, "manifest_record")
        raw = canonical_json_bytes(value)
        self._hash.update(u64be(len(raw)))
        self._hash.update(raw)
        self.count += 1

    def hexdigest(self) -> str:
        return self._hash.hexdigest()


class SharedPathTrace:
    """Records exact frozen shared-path stage coverage for one control."""

    def __init__(self, expected: Sequence[str]) -> None:
        self.expected = tuple(expected)
        self.seen: Set[str] = set()

    def mark_if_expected(self, stage: str) -> None:
        if stage in self.expected:
            self.seen.add(stage)

    def record(self) -> List[str]:
        return [stage for stage in self.expected if stage in self.seen]

    def complete(self) -> bool:
        return self.record() == list(self.expected)


# Load only the frozen record at module initialization. Experiments and derived
# primitives are deferred until after toolchain and input validation.
PREREG_DATA = strict_json_load(PREREG)

AUTHORIZATION = PREREG_DATA["authorization"]
CONSTRUCTION = PREREG_DATA["construction"]
CORPUS = PREREG_DATA["corpus"]
THEOREM_TARGETS = PREREG_DATA["theorem_targets"]
TRAIN_KEY_LABELS = tuple(int(value) for value in CORPUS["train_key_labels"])
HOLDOUT_KEY_LABELS = tuple(
    int(value) for value in CORPUS["disjoint_holdout_key_labels"]
)
KEY_LABELS = TRAIN_KEY_LABELS + HOLDOUT_KEY_LABELS
STREAM_INDICES = tuple(int(value) for value in CORPUS["stream_indices"])
DIRECTIONS = tuple(int(value) for value in CORPUS["directions"])
CONTEXT_CASES = tuple(CORPUS["context_cases"])
CONTEXT_CASE_BY_ID = {record["id"]: record for record in CONTEXT_CASES}
CONTEXT_PAIR_IDS = tuple(
    (str(pair[0]), str(pair[1])) for pair in CORPUS["required_distinct_context_pairs"]
)
SPECTRUM_KEY_LABELS = tuple(
    int(value) for value in CORPUS["rotor_spectrum_key_labels"]
)
SPECTRUM_IDS = tuple(int(value) for value in CORPUS["rotor_spectrum_ids"])
AFFINE_ROUNDS = tuple(int(value) for value in CORPUS["affine_probe"]["rounds"])
AVALANCHE_ROUNDS = tuple(
    int(value) for value in CORPUS["avalanche_probe"]["rounds"]
)
KEY_FLIP_INDICES = tuple(
    int(value) for value in CORPUS["key_bit_flip_probe"]["indices"]
)
CONTROL_IDS = tuple(record["id"] for record in PREREG_DATA["planted_controls"])
BASELINE_IDS = tuple(record["id"] for record in PREREG_DATA["baselines"])
QUESTION_IDS = tuple(record["id"] for record in PREREG_DATA["questions"])
ACCEPTED_CONSTRAINT_IDS = tuple(AUTHORIZATION["accepted_research_constraints"])


# ---------------------------------------------------------------------------
# Frozen contract validation before any experiment


def validate_exact_operational_records() -> None:
    require_equal(sha256_file(PREREG), PREREG_SHA256, "raw preregistration SHA-256")
    require_equal(tuple(PREREG_DATA), PREREG_TOP_LEVEL_KEYS, "preregistration sections")
    require_equal(PREREG_DATA["schema"], "E256-WIDE-PREREGISTRATION-1", "schema")
    require_equal(PREREG_DATA["status"], "FROZEN_FOR_EXECUTION", "status")
    require_equal(
        PREREG_DATA["revision"],
        {
            "supersedes_sha256": "ed23922b81ee699fac39a8d9283ac9f657a64d9ea44a04e20bf3c828e5d7f3cf",
            "supersession_chain": [
                "4231dcdc080b9f0a5f038ef589ffb8e5f79c53bcaf4d885cbc8bce40cf191e78"
            ],
            "reason": "Refrozen before execution after implementation audit pinned the reciprocal-control stream domain, raw material serialization, exhaustive inverse scope, and diagnostic encodings that the prior draft left implicit.",
            "prior_receipt_status": "no receipt was generated under either superseded preregistration",
        },
        "revision record",
    )
    require_equal(
        PREREG_DATA["date_basis"],
        "2026-08-20 session date; no wall-clock timestamp asserted",
        "date basis",
    )
    require_equal(
        PREREG_DATA["toolchain_contract"],
        {
            "python": EXPECTED_PYTHON,
            "numpy": EXPECTED_NUMPY,
            "deterministic_operations": "integer and byte operations only; no floating-point value enters the deterministic payload",
            "advisory_only": list(ADVISORY_KEYS),
        },
        "toolchain contract",
    )

    require_equal(
        tuple(AUTHORIZATION),
        (
            "architecture_record",
            "contract_start_marker",
            "contract_end_marker",
            "contract_hash_preimage",
            "contract_sha256",
            "accepted_research_constraints",
            "accepted_constraint_definitions",
            "allowed",
            "blocked",
        ),
        "authorization fields",
    )
    require_equal(
        AUTHORIZATION["architecture_record"],
        str(ARCHITECTURE.relative_to(REPO)),
        "architecture path",
    )
    require_equal(AUTHORIZATION["contract_sha256"], ARCHITECTURE_CONTRACT_SHA256, "contract hash")
    require_equal(
        ACCEPTED_CONSTRAINT_IDS,
        tuple(f"W{index}" for index in range(13)),
        "accepted W constraint IDs",
    )
    require_equal(
        tuple(AUTHORIZATION["accepted_constraint_definitions"]),
        ACCEPTED_CONSTRAINT_IDS,
        "accepted W definition IDs",
    )
    require_equal(
        AUTHORIZATION["accepted_constraint_definitions"],
        {
            "W0": "Reviewed nonce-misuse-resistant AEAD is the external boundary; AEAD-only is the production baseline.",
            "W1": "Use one 256-bit / 32-byte security-bearing state rather than independent byte maps.",
            "W2": "Use 4x8 Rijndael geometry with byte j at row j mod 4 and column j div 4.",
            "W3": "Use 32 keyed 8-bit rotor bijections per round as the only nonlinear layer.",
            "W4": "Use keyed affine equivalents of the AES S-box so every rotor preserves exact DDT, LAT, and algebraic-degree bounds.",
            "W5": "Use Rijndael-256 row offsets 0,1,3,4 and a 4x4 MDS MixColumns layer for explicit cross-byte diffusion.",
            "W6": "Derive rotor selection, round masks, and tweak material from a keyed PRF over complete canonical context.",
            "W7": "Inject a 32-byte PRF-derived mask before round one and after every round.",
            "W8": "Encryption and decryption are deliberately different; reflector reciprocity is forbidden.",
            "W9": "Require a tableless/bitsliced rotor path or explicitly exclude physical-security claims.",
            "W10": "Test rounds 1 through 12 but select no production round count in this gate.",
            "W11": "Evolution is immutable, deterministic, preregistered, control-calibrated, holdout-graded, and human-promoted; deployed mutation is forbidden.",
            "W12": "Promotion requires a new identity, byte-exact spec, independent implementations and KATs, full attacks, protocol/hardware evidence, external review, and human claim review.",
        },
        "accepted W definitions",
    )
    require_equal(
        AUTHORIZATION["allowed"],
        "deterministic model, structural certificate, ablation, and attack-harness research",
        "authorization scope",
    )
    require_equal(
        tuple(AUTHORIZATION["blocked"]),
        (
            "cipher-suite or profile promotion",
            "production software or RTL",
            "fixture or protocol promotion",
            "C/H/N claim movement",
            "security-bit or production-readiness claim",
            "publication claim without separate review",
        ),
        "blocked actions",
    )

    require_equal(
        PREREG_DATA["predecessor"],
        {
            "architecture": "directives/e256-vnext-topology.md",
            "receipt": "logs/e256-vnext-rotor-schedule-bakeoff.json",
            "receipt_schema": "E256-VNEXT-ROTOR-SCHEDULE-BAKEOFF-1",
            "deterministic_payload_sha256": PREDECESSOR_PAYLOAD_SHA256,
            "inherited_result": "No byte-local depth was security-selected; 1+1 affine-AES/full-counter remains attack-only and AEAD-only remains production baseline.",
        },
        "predecessor contract",
    )
    require_equal(QUESTION_IDS, ("WQ1", "WQ2", "WQ3", "WQ4", "WQ5"), "question IDs")
    require_equal(len(PREREG_DATA["questions"]), 5, "question count")
    require_equal(len(PREREG_DATA["non_claims"]), 8, "non-claim count")

    require_equal(
        PREREG_DATA["byte_encodings"],
        {
            "u8": "one unsigned big-endian byte",
            "u16be": "two unsigned big-endian bytes",
            "u64be": "eight unsigned big-endian bytes",
            "field": "u16be(byte_length) || bytes; reject byte_length > 65535",
            "bit_numbering": "bit i is byte floor(i/8), mask 1 << (i mod 8); bit 0 is the LSB of byte 0",
            "canonical_json": "UTF-8 JSON with sort_keys=true and separators=(',', ':'); integers only in deterministic numeric results",
            "spectrum_serialization": "DDT as row-major little-endian uint16; LAT as row-major little-endian int16",
            "aes_sbox_hash_preimage": "256 bytes SBOX[0] through SBOX[255]",
        },
        "byte encodings",
    )

    kdf = PREREG_DATA["experimental_kdf"]
    require_equal(
        tuple(kdf),
        (
            "status",
            "extract_key_ascii",
            "extract",
            "subkey",
            "purpose_stream",
            "subkeys",
            "bounded_sampler",
            "canonical_context",
            "rotor_derivation",
            "selection_derivation",
            "round_mask_derivation",
            "control_root",
        ),
        "experimental KDF sections",
    )
    require_equal(kdf["status"], "model-only HMAC-SHA512 PRF; not a suite decision", "KDF status")
    require_equal(kdf["extract_key_ascii"], EXTRACT_KEY.decode("ascii"), "extract key")
    require_equal(tuple(kdf["subkeys"]), ("rotor", "selection", "round-mask", "controls"), "subkeys")
    require_equal(kdf["canonical_context"]["prefix_ascii"], CONTEXT_PREFIX.decode("ascii"), "context prefix")
    require_equal(
        tuple(kdf["canonical_context"]["ordered_fields"]),
        ("corpus", "stream_id", "direction", "sequence", "block_counter"),
        "context fields",
    )
    require_equal(
        kdf["canonical_context"]["corpus_values"],
        {"train": "e256-wide-train", "disjoint_holdout": "e256-wide-holdout"},
        "corpus values",
    )
    require_equal(kdf["rotor_derivation"]["base"], "ASCII 'E256-W/gate/rotor/v1' || u8(logical_id)", "rotor base")
    require_equal(kdf["selection_derivation"]["round_range"], "1 through 12", "selection rounds")
    require_equal(kdf["selection_derivation"]["lane_range"], "0 through 31", "selection lanes")
    require_equal(kdf["round_mask_derivation"]["mask_index_range"], "0 through selected round count", "mask indices")
    require_equal(kdf["control_root"], "subkey(extract_prk(test_ikm(0)), 'controls')", "control root")

    serialization = PREREG_DATA["execution_serialization"]
    require_equal(
        tuple(serialization),
        (
            "purpose_stream_chunk_range",
            "reciprocal_sandwich_control_stream",
            "complete_round_material",
            "rotor_table_record",
            "rotor_namespace",
            "key_bit_flip_material",
            "digest_rule",
            "duplicate_table_count",
            "rotor_inverse_validation",
            "rotor_id_repeat_count",
            "affine_holdout_attempts",
            "singular_mix_matrix_error_code",
            "avalanche_histogram",
            "fixed_aes_material",
            "outer_receipt_keys",
        ),
        "execution serialization fields",
    )
    require_equal(
        serialization["reciprocal_sandwich_control_stream"],
        {
            "key": "control_root",
            "domain_ascii": RECIPROCAL_CONTROL_DOMAIN.decode("ascii"),
            "mask": "read consecutive 32-byte values from one PurposeStream and use the first value that is not 32 zero bytes",
        },
        "reciprocal control stream",
    )
    require_equal(serialization["singular_mix_matrix_error_code"], "SINGULAR_MIX_MATRIX", "singular code")
    require_equal(tuple(serialization["outer_receipt_keys"]), OUTER_RECEIPT_KEYS, "outer receipt keys")
    require_equal(serialization["rotor_inverse_validation"]["expected_table_pairs"], 1024, "inverse pairs")

    require_equal(
        tuple(CONSTRUCTION),
        (
            "identity",
            "state_bytes",
            "state_bits",
            "rows",
            "columns",
            "byte_mapping",
            "round_counts",
            "round_order",
            "inverse_loop",
            "logical_rotor_ids",
            "rotor_family",
            "row_shift",
            "mix_columns",
            "round_masks",
            "round_bijection_certificate",
        ),
        "construction fields",
    )
    require_equal(CONSTRUCTION["identity"], "E256-W/gate-candidate/v1", "construction identity")
    require_equal((CONSTRUCTION["state_bytes"], CONSTRUCTION["state_bits"]), (32, 256), "state width")
    require_equal((CONSTRUCTION["rows"], CONSTRUCTION["columns"]), (4, 8), "geometry")
    require_equal(tuple(CONSTRUCTION["round_counts"]), ROUND_COUNTS, "round counts")
    require_equal(CONSTRUCTION["logical_rotor_ids"], 256, "logical rotor IDs")
    family_record = CONSTRUCTION["rotor_family"]
    require_equal(family_record["id"], "aes_affine_v1", "rotor family ID")
    require_equal(family_record["aes_sbox_sha256"], AES_SBOX_SHA256, "rotor AES hash")
    require_equal(
        (
            family_record["expected_bijection"],
            family_record["expected_differential_uniformity"],
            family_record["expected_maximum_absolute_lat"],
            family_record["expected_forward_algebraic_degree"],
            family_record["expected_inverse_algebraic_degree"],
        ),
        (True, 4, 32, 7, 7),
        "rotor expected metrics",
    )
    require_equal(tuple(CONSTRUCTION["row_shift"]["offsets"]), ROW_OFFSETS, "row offsets")
    require_equal(
        tuple(tuple(int(cell, 16) for cell in row) for row in CONSTRUCTION["mix_columns"]["matrix_hex_rows"]),
        MIX_MATRIX,
        "MixColumns matrix",
    )

    require_equal(
        tuple(PREREG_DATA["metric_definitions"]),
        ("differential_uniformity", "maximum_absolute_lat", "algebraic_degree", "dependency", "affine_model", "avalanche"),
        "metric definitions",
    )
    require_equal(
        (
            THEOREM_TARGETS["mds_expected_minor_count"],
            THEOREM_TARGETS["mix_columns_branch_number"],
            THEOREM_TARGETS["full_structural_byte_dependency_by_round"],
            THEOREM_TARGETS["four_round_active_rotor_lower_bound"],
            THEOREM_TARGETS["four_round_single_trail_differential_probability_log2_upper"],
            THEOREM_TARGETS["four_round_single_trail_linear_correlation_log2_upper"],
        ),
        (69, 5, 3, 25, -150, -75),
        "theorem targets",
    )
    require_equal(THEOREM_TARGETS["four_round_certificate_id"], "E256-W-WIDETRAIL-25-v1", "certificate ID")
    require_equal(len(THEOREM_TARGETS["four_round_proof_obligations"]), 6, "proof obligations")

    require_equal(TRAIN_KEY_LABELS, (0, 1), "train labels")
    require_equal(HOLDOUT_KEY_LABELS, (8, 9), "holdout labels")
    require_equal(STREAM_INDICES, (0, 1), "stream indices")
    require_equal(DIRECTIONS, (0, 1), "directions")
    require_equal(
        tuple((case["id"], case["sequence"], case["counter"]) for case in CONTEXT_CASES),
        (
            ("counter_0", 7, 0),
            ("counter_1", 7, 1),
            ("counter_255", 7, 255),
            ("counter_256", 7, 256),
            ("counter_65535", 7, 65535),
            ("counter_65536", 7, 65536),
            ("counter_2p32_minus_1", 7, 4294967295),
            ("counter_2p32", 7, 4294967296),
            ("sequence_reset", 8, 0),
        ),
        "context cases",
    )
    require_equal(
        CONTEXT_PAIR_IDS,
        (
            ("counter_0", "counter_1"),
            ("counter_255", "counter_256"),
            ("counter_65535", "counter_65536"),
            ("counter_2p32_minus_1", "counter_2p32"),
            ("counter_0", "counter_2p32"),
            ("counter_0", "sequence_reset"),
            ("counter_65536", "sequence_reset"),
        ),
        "required context pairs",
    )
    require_equal(CORPUS["roundtrip_cartesian_product"]["expected_contexts"], 144, "context count")
    require_equal(CORPUS["roundtrip_cartesian_product"]["expected_tests"], 13824, "roundtrip count")
    require_equal(SPECTRUM_KEY_LABELS, (0, 8), "spectrum labels")
    require_equal(
        SPECTRUM_IDS,
        (0, 1, 2, 3, 16, 17, 63, 64, 127, 128, 191, 192, 252, 253, 254, 255),
        "spectrum IDs",
    )
    require_equal(CORPUS["expected_rotor_spectrum_records"], 32, "spectrum count")
    require_equal(AFFINE_ROUNDS, (1, 2, 4, 8, 12), "affine rounds")
    require_equal(CORPUS["affine_probe"]["holdout_count"], 64, "affine holdouts")
    require_equal(AVALANCHE_ROUNDS, (1, 2, 3, 4, 6, 8, 10, 12), "avalanche rounds")
    require_equal(CORPUS["avalanche_probe"]["expected_comparisons"], 4096, "avalanche count")
    require_equal(CORPUS["context_material_separation"]["expected_context_pair_comparisons"], 112, "context comparisons")
    require_equal(CORPUS["context_material_separation"]["expected_direction_pair_comparisons"], 72, "direction comparisons")
    require_equal(KEY_FLIP_INDICES, (0, 1, 7, 8, 31, 32, 63, 64, 127, 128, 191, 255), "key-flip indices")
    require_equal(CORPUS["key_bit_flip_probe"]["expected_comparisons"], 12, "key-flip count")

    require_equal(BASELINE_IDS, ("fixed_aes_spn", "aead_only"), "baseline IDs")
    require_equal(
        CONTROL_IDS,
        (
            "affine_rotor_bypass",
            "no_diffusion",
            "singular_mix_matrix",
            "zero_row_shifts",
            "reciprocal_sandwich",
            "truncated_counter_32",
            "direction_omitted",
        ),
        "control IDs",
    )
    for record in PREREG_DATA["planted_controls"]:
        require_true(bool(record["mutation"]), f"empty mutation for {record['id']}")
        require_true(bool(record["shared_path"]), f"empty shared path for {record['id']}")
        require_true(bool(record["detector"]), f"empty detector for {record['id']}")
        require_equal(record["required_result"], "detected", f"control result {record['id']}")
    require_equal(PREREG_DATA["control_execution_contract"]["exact_control_ids"], True, "exact control IDs")
    require_equal(len(PREREG_DATA["control_execution_contract"]["candidate_nulls"]), 3, "candidate nulls")
    require_equal(len(PREREG_DATA["control_execution_contract"]["baseline_nulls"]), 3, "baseline nulls")
    require_equal(
        tuple(PREREG_DATA["metrics"]),
        ("functional", "rotor", "diffusion", "load_bearing", "context", "diagnostic_only", "cost_convention"),
        "metric sections",
    )
    require_equal(len(PREREG_DATA["hard_rejection_rules"]), 9, "hard-rejection rules")
    require_equal(
        tuple(PREREG_DATA["interpretation"]["valid_emitted_verdicts"]),
        VALID_VERDICTS,
        "valid verdicts",
    )
    require_equal(
        PREREG_DATA["interpretation"]["internal_invalid_status"],
        "INVALID_CONTROLS_OR_CONTRACT; never emitted or accepted as the canonical receipt",
        "invalid status",
    )

    receipt = PREREG_DATA["receipt_contract"]
    require_equal(receipt["schema"], "E256-WIDE-STATE-GATE-1", "receipt schema")
    require_equal(receipt["status"], "OPEN_PROGRESS", "receipt status")
    require_equal(receipt["output"], str(RECEIPT.relative_to(REPO)), "receipt output")
    require_equal(receipt["runner"], str(Path(__file__).resolve().relative_to(REPO)), "runner path")
    require_equal(tuple(receipt["deterministic_payload_top_level_keys"]), PAYLOAD_TOP_LEVEL_KEYS, "payload keys")
    require_equal(tuple(receipt["environment_advisory_excluded_from_digest"]), ADVISORY_KEYS, "advisory keys")


def architecture_authorization_record() -> dict:
    raw = ARCHITECTURE.read_bytes()
    start = AUTHORIZATION["contract_start_marker"].encode("ascii")
    end = AUTHORIZATION["contract_end_marker"].encode("ascii")
    if raw.count(start) != 1 or raw.count(end) != 1:
        raise ContractError("architecture contract markers are not unique")
    start_index = raw.index(start) + len(start)
    end_index = raw.index(end)
    if start_index >= end_index:
        raise ContractError("architecture contract markers are out of order")
    contract = raw[start_index:end_index]
    digest = sha256_bytes(contract)
    require_equal(digest, ARCHITECTURE_CONTRACT_SHA256, "architecture marker-slice hash")
    text = contract.decode("utf-8")
    pattern = re.compile(r"^\| \*\*(W(?:[0-9]|1[0-2])) — [^*]+\*\* \|", re.MULTILINE)
    row_ids = tuple(pattern.findall(text))
    require_equal(row_ids, ACCEPTED_CONSTRAINT_IDS, "architecture W rows")
    for constraint_id in ACCEPTED_CONSTRAINT_IDS:
        require_true(constraint_id in text, f"architecture omits {constraint_id}")
    return {
        "path": str(ARCHITECTURE.relative_to(REPO)),
        "contract_start_marker": AUTHORIZATION["contract_start_marker"],
        "contract_end_marker": AUTHORIZATION["contract_end_marker"],
        "marker_slice_sha256": digest,
        "accepted_constraint_ids": list(row_ids),
    }


def predecessor_record() -> dict:
    receipt = strict_json_load(PREDECESSOR_RECEIPT)
    require_true(isinstance(receipt, dict), "predecessor receipt is not an object")
    payload = receipt.get("deterministic_payload")
    require_true(isinstance(payload, dict), "predecessor deterministic payload is absent")
    recomputed = sha256_bytes(canonical_json_bytes(payload))
    require_equal(recomputed, PREDECESSOR_PAYLOAD_SHA256, "predecessor recomputed payload digest")
    require_equal(receipt.get("deterministic_payload_sha256"), PREDECESSOR_PAYLOAD_SHA256, "predecessor stored digest")
    require_equal(payload.get("schema"), "E256-VNEXT-ROTOR-SCHEDULE-BAKEOFF-1", "predecessor schema")
    require_equal(payload.get("status"), "OPEN_PROGRESS", "predecessor status")
    selection = payload.get("selection", {})
    require_equal(selection.get("verdict"), "NO_BYTE_LOCAL_PRODUCTION_CANDIDATE_RESEARCH_BASELINE_RETAINED", "predecessor verdict")
    require_equal(selection.get("security_selected_depth"), None, "predecessor selected depth")
    require_equal(selection.get("next_research_baseline"), "aes_affine_v1|full_counter_reselect_v1|1+1", "predecessor attack baseline")
    production_result = selection.get("production_result", "")
    require_true("AEAD-only remains the production baseline" in production_result, "predecessor AEAD baseline missing")
    return {
        "path": str(PREDECESSOR_RECEIPT.relative_to(REPO)),
        "schema": payload["schema"],
        "deterministic_payload_sha256": recomputed,
        "verdict": selection["verdict"],
        "security_selected_depth": None,
        "next_research_baseline": selection["next_research_baseline"],
        "inherited_result": PREREG_DATA["predecessor"]["inherited_result"],
    }


def verify_toolchain() -> dict:
    actual_python = platform.python_version()
    actual_numpy = np.__version__
    require_equal(actual_python, EXPECTED_PYTHON, "Python toolchain")
    require_equal(actual_numpy, EXPECTED_NUMPY, "NumPy toolchain")
    return {
        "python": actual_python,
        "numpy": actual_numpy,
        "deterministic_operations": PREREG_DATA["toolchain_contract"]["deterministic_operations"],
    }


# ---------------------------------------------------------------------------
# KDF, exact purpose stream, AES derivation, and rotor namespace


class PurposeStream:
    def __init__(self, key: bytes, domain: bytes, start_chunk: int = 0) -> None:
        if not isinstance(key, bytes) or not isinstance(domain, bytes):
            raise TypeError("purpose-stream key and domain must be bytes")
        self.key = key
        self.domain = domain
        self.chunk_index = _integer(start_chunk, 0, MAX_U64, "purpose chunk")
        self.buffer = b""
        self.offset = 0
        self.exhausted_after_buffer = False

    def _refill(self) -> None:
        if self.exhausted_after_buffer:
            raise OverflowError("purpose stream exhausted before chunk-index wrap")
        index = self.chunk_index
        self.buffer = hmac.new(
            self.key,
            self.domain + b"\x00" + u64be(index),
            hashlib.sha512,
        ).digest()
        self.offset = 0
        if index == MAX_U64:
            self.exhausted_after_buffer = True
        else:
            self.chunk_index += 1

    def byte(self) -> int:
        if self.offset == len(self.buffer):
            self._refill()
        value = self.buffer[self.offset]
        self.offset += 1
        return value

    def read(self, count: int) -> bytes:
        _integer(count, 0, MAX_U64, "purpose read count")
        return bytes(self.byte() for _ in range(count))

    def u16be(self) -> int:
        return (self.byte() << 8) | self.byte()

    def bounded(self, upper: int) -> int:
        _integer(upper, 1, 65536, "bounded sampler upper")
        limit = 65536 - (65536 % upper)
        while True:
            value = self.u16be()
            if value < limit:
                return value % upper


def purpose_stream_contract_self_test() -> dict:
    terminal = PurposeStream(b"terminal-key", b"terminal-domain", MAX_U64)
    terminal_chunk = terminal.read(64)
    raised = False
    try:
        terminal.byte()
    except OverflowError:
        raised = True
    require_true(len(terminal_chunk) == 64 and raised, "terminal purpose-stream chunk contract failed")
    try:
        PurposeStream(b"k", b"d").read(-1)
        negative_rejected = False
    except ValueError:
        negative_rejected = True
    require_true(negative_rejected, "negative purpose-stream read was accepted")
    return {
        "terminal_chunk_index": MAX_U64,
        "terminal_chunk_bytes_emitted": len(terminal_chunk),
        "next_byte_rejected_before_wrap": raised,
        "negative_read_rejected": negative_rejected,
    }


def extract_prk(ikm: bytes) -> bytes:
    if not isinstance(ikm, bytes) or len(ikm) != 32:
        raise ValueError("test IKM must be exactly 32 bytes")
    return hmac.new(EXTRACT_KEY, ikm, hashlib.sha512).digest()


def subkey(prk: bytes, domain: str) -> bytes:
    if not isinstance(prk, bytes) or len(prk) != 64:
        raise ValueError("PRK must be exactly 64 bytes")
    if domain not in ("rotor", "selection", "round-mask", "controls"):
        raise ValueError("subkey domain is outside the frozen set")
    return hmac.new(prk, b"subkey\x00" + domain.encode("ascii"), hashlib.sha512).digest()


def test_ikm(label: int) -> bytes:
    return hashlib.sha512(b"E256-W/gate/key/v1/" + u16be(label)).digest()[:32]


def stream_id_for(label: int, stream_index: int) -> bytes:
    return hashlib.sha256(
        b"E256-W/gate/stream/v1/" + u16be(label) + u8(stream_index)
    ).digest()[:16]


def corpus_for_label(label: int) -> str:
    if label in TRAIN_KEY_LABELS:
        return "e256-wide-train"
    if label in HOLDOUT_KEY_LABELS:
        return "e256-wide-holdout"
    raise ValueError("key label is outside the frozen corpus")


def canonical_context(
    corpus: str,
    stream_id: bytes,
    direction: int,
    sequence: int,
    block_counter: int,
    trace: Optional[SharedPathTrace] = None,
) -> bytes:
    if corpus not in ("e256-wide-train", "e256-wide-holdout"):
        raise ValueError("corpus is outside the frozen set")
    if not isinstance(stream_id, bytes) or len(stream_id) != 16:
        raise ValueError("stream ID must be exactly 16 bytes")
    if direction not in DIRECTIONS:
        raise ValueError("direction is outside the frozen set")
    if trace is not None:
        trace.mark_if_expected("canonical context")
    return (
        CONTEXT_PREFIX
        + field(corpus.encode("utf-8"))
        + field(stream_id)
        + u8(direction)
        + u64be(sequence)
        + u64be(block_counter)
    )


def gf_mul(a: int, b: int) -> int:
    a = _integer(a, 0, 255, "GF factor")
    b = _integer(b, 0, 255, "GF factor")
    result = 0
    while b:
        if b & 1:
            result ^= a
        a = ((a << 1) ^ 0x11B) if (a & 0x80) else (a << 1)
        a &= 0xFF
        b >>= 1
    return result


def gf_pow(value: int, exponent: int) -> int:
    value = _integer(value, 0, 255, "GF base")
    exponent = _integer(exponent, 0, MAX_U64, "GF exponent")
    result = 1
    while exponent:
        if exponent & 1:
            result = gf_mul(result, value)
        value = gf_mul(value, value)
        exponent >>= 1
    return result


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
    require_equal(sha256_bytes(table.tobytes(order="C")), AES_SBOX_SHA256, "derived AES S-box")
    return table


def inverse_table(table: np.ndarray) -> np.ndarray:
    if not isinstance(table, np.ndarray) or table.shape != (256,):
        raise ValueError("table is not a 256-point map")
    values = table.astype(np.int64, copy=False)
    if len(np.unique(values)) != 256 or int(values.min()) != 0 or int(values.max()) != 255:
        raise ValueError("table is not a 256-point bijection")
    inverse = np.empty(256, dtype=np.uint8)
    inverse[values] = IDENTITY_U8
    return inverse


def initialize_primitives() -> dict:
    global AES_SBOX, AES_SBOX_INVERSE, GF_TABLE
    AES_SBOX = build_aes_sbox()
    AES_SBOX_INVERSE = inverse_table(AES_SBOX)
    gf_values = np.empty((256, 256), dtype=np.uint8)
    for first in range(256):
        for second in range(256):
            gf_values[first, second] = gf_mul(first, second)
    GF_TABLE = gf_values
    require_true(np.array_equal(AES_SBOX_INVERSE[AES_SBOX], IDENTITY_U8), "AES inverse mismatch")
    return {
        "aes_sbox_sha256": sha256_bytes(AES_SBOX.tobytes(order="C")),
        "aes_inverse_exact": True,
        "gf_field_polynomial": "0x11b",
    }


def gf2_rank(rows: Sequence[int]) -> int:
    if len(rows) != 8:
        raise ValueError("GF(2) matrix must have eight rows")
    work = [_integer(int(row), 0, 255, "GF(2) row") for row in rows]
    rank = 0
    for column in range(7, -1, -1):
        pivot = next(
            (index for index in range(rank, 8) if (work[index] >> column) & 1),
            None,
        )
        if pivot is None:
            continue
        work[rank], work[pivot] = work[pivot], work[rank]
        for row in range(8):
            if row != rank and ((work[row] >> column) & 1):
                work[row] ^= work[rank]
        rank += 1
    return rank


def derive_matrix(key: bytes, base: bytes, side: bytes) -> Tuple[int, ...]:
    if side not in (b"in", b"out"):
        raise ValueError("rotor matrix side is not frozen")
    for attempt in range(65536):
        domain = base + b"/matrix/" + side + b"/attempt/" + u16be(attempt)
        rows = tuple(PurposeStream(key, domain).read(8))
        if gf2_rank(rows) == 8:
            return rows
    raise ContractError("no invertible rotor matrix in attempts 0...65535")


def apply_linear(rows: Sequence[int], value: int) -> int:
    value = _integer(value, 0, 255, "linear-map input")
    output = 0
    for bit, row in enumerate(rows):
        output |= ((bin(int(row) & value).count("1") & 1) << bit)
    return output


def linear_table(rows: Sequence[int]) -> np.ndarray:
    return np.array([apply_linear(rows, value) for value in range(256)], dtype=np.uint8)


class RotorNamespace:
    def __init__(self, prk: bytes) -> None:
        self.rotor_key = subkey(prk, "rotor")
        self._forward: Optional[np.ndarray] = None
        self._inverse: Optional[np.ndarray] = None

    def build_all(self) -> None:
        global AES_SBOX
        if AES_SBOX is None:
            raise ContractError("AES primitive not initialized")
        if self._forward is not None:
            return
        forward = np.empty((256, 256), dtype=np.uint8)
        inverse = np.empty((256, 256), dtype=np.uint8)
        for logical_id in range(256):
            base = ROTOR_PREFIX + u8(logical_id)
            matrix_in = derive_matrix(self.rotor_key, base, b"in")
            matrix_out = derive_matrix(self.rotor_key, base, b"out")
            constants = PurposeStream(self.rotor_key, base + b"/constants").read(2)
            input_map = linear_table(matrix_in)
            output_map = linear_table(matrix_out)
            table = np.bitwise_xor(
                output_map[AES_SBOX[np.bitwise_xor(input_map, constants[0])]],
                constants[1],
            ).astype(np.uint8, copy=False)
            table_inverse = inverse_table(table)
            forward[logical_id] = table
            inverse[logical_id] = table_inverse
        self._forward = forward
        self._inverse = inverse

    @property
    def forward(self) -> np.ndarray:
        self.build_all()
        assert self._forward is not None
        return self._forward

    @property
    def inverse(self) -> np.ndarray:
        self.build_all()
        assert self._inverse is not None
        return self._inverse

    def table_record(self, logical_id: int) -> bytes:
        logical_id = _integer(logical_id, 0, 255, "logical rotor ID")
        raw = self.forward[logical_id].tobytes(order="C") + self.inverse[logical_id].tobytes(order="C")
        if len(raw) != 512:
            raise ContractError("rotor table record is not 512 bytes")
        return raw

    def serialize(self) -> bytes:
        raw = b"".join(self.table_record(logical_id) for logical_id in range(256))
        if len(raw) != 131072:
            raise ContractError("rotor namespace is not 131072 bytes")
        return raw


@dataclass(frozen=True)
class RoundMaterial:
    context: bytes
    rotor_ids: np.ndarray
    masks: np.ndarray

    def selection_bytes(self) -> bytes:
        raw = self.rotor_ids.tobytes(order="C")
        if len(raw) != 384:
            raise ContractError("round selection is not 384 bytes")
        return raw

    def mask_bytes(self) -> bytes:
        raw = self.masks.tobytes(order="C")
        if len(raw) != 416:
            raise ContractError("round masks are not 416 bytes")
        return raw

    def serialize(self) -> bytes:
        raw = self.selection_bytes() + self.mask_bytes()
        if len(raw) != 800:
            raise ContractError("complete round material is not 800 bytes")
        return raw


def derive_round_material(
    prk: bytes,
    context: bytes,
    trace: Optional[SharedPathTrace] = None,
) -> RoundMaterial:
    if not isinstance(context, bytes):
        raise TypeError("canonical context must be bytes")
    if trace is not None:
        trace.mark_if_expected("round material")
        trace.mark_if_expected("selection material")
    selection_key = subkey(prk, "selection")
    rotor_ids = np.empty((12, 32), dtype=np.uint8)
    for round_index in ROUND_COUNTS:
        for lane in LANES:
            domain = SELECTION_PREFIX + field(context) + u16be(round_index) + u8(lane)
            rotor_ids[round_index - 1, lane] = PurposeStream(selection_key, domain).byte()
    if trace is not None:
        trace.mark_if_expected("round masks")
    mask_key = subkey(prk, "round-mask")
    masks = np.empty((13, 32), dtype=np.uint8)
    for mask_index in MASK_INDICES:
        domain = MASK_PREFIX + field(context) + u16be(mask_index)
        masks[mask_index] = np.frombuffer(
            PurposeStream(mask_key, domain).read(32), dtype=np.uint8
        )
    material = RoundMaterial(context=context, rotor_ids=rotor_ids, masks=masks)
    material.serialize()
    return material


# ---------------------------------------------------------------------------
# Exact GF(2^8) matrices, candidate permutation, and dependency propagation


def gf_matrix_determinant(matrix: Sequence[Sequence[int]]) -> int:
    size = len(matrix)
    if size < 1 or any(len(row) != size for row in matrix):
        raise ValueError("determinant requires a nonempty square matrix")
    work = [[_integer(int(value), 0, 255, "matrix value") for value in row] for row in matrix]
    determinant = 1
    for column in range(size):
        pivot = next((row for row in range(column, size) if work[row][column] != 0), None)
        if pivot is None:
            return 0
        if pivot != column:
            work[column], work[pivot] = work[pivot], work[column]
        pivot_value = work[column][column]
        determinant = gf_mul(determinant, pivot_value)
        pivot_inverse = gf_pow(pivot_value, 254)
        for entry in range(column, size):
            work[column][entry] = gf_mul(work[column][entry], pivot_inverse)
        for row in range(column + 1, size):
            factor = work[row][column]
            if factor:
                for entry in range(column, size):
                    work[row][entry] ^= gf_mul(factor, work[column][entry])
    return determinant


def gf_matrix_inverse(matrix: Sequence[Sequence[int]]) -> Tuple[Tuple[int, ...], ...]:
    size = len(matrix)
    if size < 1 or any(len(row) != size for row in matrix):
        raise ValueError("inverse requires a nonempty square matrix")
    work = []
    for row_index, row in enumerate(matrix):
        work.append(
            [_integer(int(value), 0, 255, "matrix value") for value in row]
            + [1 if row_index == column else 0 for column in range(size)]
        )
    for column in range(size):
        pivot = next((row for row in range(column, size) if work[row][column] != 0), None)
        if pivot is None:
            raise StructuralError("SINGULAR_MIX_MATRIX", {"inverse_available": False})
        if pivot != column:
            work[column], work[pivot] = work[pivot], work[column]
        pivot_inverse = gf_pow(work[column][column], 254)
        work[column] = [gf_mul(value, pivot_inverse) for value in work[column]]
        for row in range(size):
            if row == column:
                continue
            factor = work[row][column]
            if factor:
                work[row] = [
                    left ^ gf_mul(factor, right)
                    for left, right in zip(work[row], work[column])
                ]
    return tuple(tuple(row[size:]) for row in work)


def gf_matrix_multiply(
    left: Sequence[Sequence[int]], right: Sequence[Sequence[int]]
) -> Tuple[Tuple[int, ...], ...]:
    rows = len(left)
    inner = len(right)
    columns = len(right[0]) if right else 0
    if rows < 1 or inner < 1 or any(len(row) != inner for row in left) or any(len(row) != columns for row in right):
        raise ValueError("matrix multiplication dimensions mismatch")
    output = []
    for row in range(rows):
        values = []
        for column in range(columns):
            value = 0
            for index in range(inner):
                value ^= gf_mul(int(left[row][index]), int(right[index][column]))
            values.append(value)
        output.append(tuple(values))
    return tuple(output)


def analyze_mix_matrix(
    matrix: Sequence[Sequence[int]],
    trace: Optional[SharedPathTrace] = None,
) -> dict:
    if trace is not None:
        trace.mark_if_expected("GF(2^8) determinant and minor certificate")
    normalized = tuple(tuple(int(value) for value in row) for row in matrix)
    if len(normalized) != 4 or any(len(row) != 4 for row in normalized):
        raise ContractError("MixColumns matrix must be 4x4")
    minor_records = []
    zero_minors = []
    for size in range(1, 5):
        for rows in itertools.combinations(range(4), size):
            for columns in itertools.combinations(range(4), size):
                minor = tuple(tuple(normalized[row][column] for column in columns) for row in rows)
                determinant = gf_matrix_determinant(minor)
                record = {
                    "size": size,
                    "rows": list(rows),
                    "columns": list(columns),
                    "determinant": determinant,
                }
                minor_records.append(record)
                if determinant == 0:
                    zero_minors.append(record)
    if len(minor_records) != 69:
        raise ContractError("MixColumns minor enumeration did not produce 69 records")
    determinant = gf_matrix_determinant(normalized)
    if determinant == 0 or zero_minors:
        raise StructuralError(
            "SINGULAR_MIX_MATRIX",
            {
                "determinant": determinant,
                "minor_count": len(minor_records),
                "zero_minor_count": len(zero_minors),
                "first_zero_minor": zero_minors[0] if zero_minors else None,
                "inverse_available": False,
                "inverse_attempted": False,
            },
        )
    inverse = gf_matrix_inverse(normalized)
    identity = tuple(tuple(1 if row == column else 0 for column in range(4)) for row in range(4))
    left_product = gf_matrix_multiply(normalized, inverse)
    right_product = gf_matrix_multiply(inverse, normalized)
    pass_value = bool(left_product == identity and right_product == identity and not zero_minors)
    return {
        "matrix": [list(row) for row in normalized],
        "determinant": determinant,
        "minor_count": len(minor_records),
        "zero_minor_count": 0,
        "minor_records": minor_records,
        "all_nonempty_square_minors_nonzero": True,
        "inverse": [list(row) for row in inverse],
        "matrix_times_inverse_is_identity": left_product == identity,
        "inverse_times_matrix_is_identity": right_product == identity,
        "branch_number_certificate": 5,
        "pass": pass_value,
    }


def row_dispersion_certificate(
    offsets: Sequence[int], trace: Optional[SharedPathTrace] = None
) -> dict:
    if trace is not None:
        trace.mark_if_expected("row-dispersion certificate")
    normalized = tuple(_integer(int(value), 0, 7, "row offset") for value in offsets)
    if len(normalized) != 4:
        raise ValueError("row offsets must contain four entries")
    destinations = tuple((-offset) % 8 for offset in normalized)
    distinct = len(set(normalized)) == 4
    distinct_destinations = len(set(destinations)) == 4
    return {
        "offsets": list(normalized),
        "offsets_distinct_modulo_8": distinct,
        "source_column_0_destination_columns": list(destinations),
        "single_column_rows_reach_distinct_columns": distinct_destinations,
        "pass": bool(distinct and distinct_destinations),
    }


def row_shift(state: np.ndarray, offsets: Sequence[int], inverse: bool = False) -> np.ndarray:
    if state.shape != (32,):
        raise ValueError("state must contain 32 bytes")
    normalized = tuple(int(value) for value in offsets)
    if len(normalized) != 4:
        raise ValueError("row offsets must contain four entries")
    output = np.empty(32, dtype=np.uint8)
    for column in range(8):
        for row in range(4):
            source_column = (column - normalized[row]) % 8 if inverse else (column + normalized[row]) % 8
            output[4 * column + row] = state[4 * source_column + row]
    return output


def mix_columns(state: np.ndarray, matrix: Sequence[Sequence[int]]) -> np.ndarray:
    global GF_TABLE
    if GF_TABLE is None:
        raise ContractError("GF multiplication table not initialized")
    if state.shape != (32,):
        raise ValueError("state must contain 32 bytes")
    normalized = tuple(tuple(int(value) for value in row) for row in matrix)
    if len(normalized) != 4 or any(len(row) != 4 for row in normalized):
        raise ValueError("MixColumns matrix must be 4x4")
    columns = state.reshape((8, 4))
    output = np.empty((8, 4), dtype=np.uint8)
    for row in range(4):
        value = np.zeros(8, dtype=np.uint8)
        for source_row in range(4):
            coefficient = normalized[row][source_row]
            value = np.bitwise_xor(value, GF_TABLE[coefficient, columns[:, source_row]])
        output[:, row] = value
    return output.reshape(32)


def rotor_substitute(
    state: np.ndarray,
    namespace: RotorNamespace,
    rotor_ids: np.ndarray,
    mode: str,
    inverse: bool = False,
    trace: Optional[SharedPathTrace] = None,
) -> np.ndarray:
    global AES_SBOX, AES_SBOX_INVERSE
    if state.shape != (32,) or rotor_ids.shape != (32,):
        raise ValueError("rotor substitution dimensions mismatch")
    if trace is not None:
        trace.mark_if_expected("rotor layer")
    if mode == "candidate":
        tables = namespace.inverse if inverse else namespace.forward
        return tables[rotor_ids.astype(np.int64), state.astype(np.int64)]
    if mode == "fixed_aes":
        table = AES_SBOX_INVERSE if inverse else AES_SBOX
        if table is None:
            raise ContractError("AES primitive not initialized")
        return table[state]
    if mode == "identity":
        return state.copy()
    raise ValueError("unknown rotor mode")


def permute(
    state_bytes: bytes,
    namespace: RotorNamespace,
    material: RoundMaterial,
    rounds: int,
    mode: str = "candidate",
    offsets: Sequence[int] = ROW_OFFSETS,
    mix_matrix: Sequence[Sequence[int]] = MIX_MATRIX,
    trace: Optional[SharedPathTrace] = None,
    trace_stage: str = "permute",
) -> bytes:
    rounds = _integer(rounds, 1, 12, "round count")
    if not isinstance(state_bytes, bytes) or len(state_bytes) != 32:
        raise ValueError("permutation state must be exactly 32 bytes")
    if trace is not None:
        trace.mark_if_expected(trace_stage)
    state = np.frombuffer(state_bytes, dtype=np.uint8).copy()
    state = np.bitwise_xor(state, material.masks[0])
    for round_index in range(1, rounds + 1):
        state = rotor_substitute(
            state,
            namespace,
            material.rotor_ids[round_index - 1],
            mode,
            inverse=False,
            trace=trace,
        )
        state = row_shift(state, offsets, inverse=False)
        state = mix_columns(state, mix_matrix)
        state = np.bitwise_xor(state, material.masks[round_index])
    return state.tobytes(order="C")


def inverse_permute(
    state_bytes: bytes,
    namespace: RotorNamespace,
    material: RoundMaterial,
    rounds: int,
    mode: str = "candidate",
    offsets: Sequence[int] = ROW_OFFSETS,
    inverse_mix_matrix: Sequence[Sequence[int]] = IDENTITY_MIX_MATRIX,
    trace: Optional[SharedPathTrace] = None,
    trace_stage: str = "inverse permute",
) -> bytes:
    rounds = _integer(rounds, 1, 12, "round count")
    if not isinstance(state_bytes, bytes) or len(state_bytes) != 32:
        raise ValueError("inverse state must be exactly 32 bytes")
    if trace is not None:
        trace.mark_if_expected(trace_stage)
    state = np.frombuffer(state_bytes, dtype=np.uint8).copy()
    for round_index in range(rounds, 0, -1):
        state = np.bitwise_xor(state, material.masks[round_index])
        state = mix_columns(state, inverse_mix_matrix)
        state = row_shift(state, offsets, inverse=True)
        state = rotor_substitute(
            state,
            namespace,
            material.rotor_ids[round_index - 1],
            mode,
            inverse=True,
            trace=trace,
        )
    state = np.bitwise_xor(state, material.masks[0])
    return state.tobytes(order="C")


def dependency_reachability(
    offsets: Sequence[int],
    matrix: Sequence[Sequence[int]],
    trace: Optional[SharedPathTrace] = None,
) -> dict:
    if trace is not None:
        trace.mark_if_expected("dependency reachability")
    normalized_offsets = tuple(int(value) for value in offsets)
    normalized_matrix = tuple(tuple(int(value) for value in row) for row in matrix)
    dependencies: List[Set[int]] = [{lane} for lane in range(32)]
    rounds = []
    earliest_all_to_all = None
    for round_index in ROUND_COUNTS:
        shifted: List[Set[int]] = [set() for _ in range(32)]
        for column in range(8):
            for row in range(4):
                source_column = (column + normalized_offsets[row]) % 8
                shifted[4 * column + row] = set(dependencies[4 * source_column + row])
        mixed: List[Set[int]] = [set() for _ in range(32)]
        for column in range(8):
            for row in range(4):
                union: Set[int] = set()
                for source_row in range(4):
                    if normalized_matrix[row][source_row] != 0:
                        union.update(shifted[4 * column + source_row])
                mixed[4 * column + row] = union
        dependencies = mixed
        rows = [sorted(values) for values in dependencies]
        all_to_all = all(len(values) == 32 for values in dependencies)
        if all_to_all and earliest_all_to_all is None:
            earliest_all_to_all = round_index
        rounds.append(
            {
                "round": round_index,
                "dependency_rows": rows,
                "row_cardinalities": [len(values) for values in dependencies],
                "all_to_all": all_to_all,
            }
        )
    isolated_same_lane_all_rounds = all(
        record["dependency_rows"] == [[lane] for lane in range(32)] for record in rounds
    )
    return {
        "rounds": rounds,
        "earliest_all_to_all_round": earliest_all_to_all,
        "all_to_all_by_round_3": earliest_all_to_all is not None and earliest_all_to_all <= 3,
        "isolated_same_lane_all_rounds": isolated_same_lane_all_rounds,
    }


def wide_trail_certificate(mix_record: dict, row_record: dict) -> dict:
    middle_cases = [
        {"active_source_columns": active, "required_next": 5 - active, "sum": 5}
        for active in range(1, 5)
    ]
    obligations = [
        mix_record["minor_count"] == 69 and mix_record["zero_minor_count"] == 0,
        mix_record["branch_number_certificate"] == 5,
        row_record["offsets_distinct_modulo_8"],
        all(record["sum"] == 5 for record in middle_cases),
        True,
        mix_record["branch_number_certificate"] == 5,
    ]
    require_equal(len(obligations), len(THEOREM_TARGETS["four_round_proof_obligations"]), "wide-trail obligation count")
    return {
        "certificate_id": THEOREM_TARGETS["four_round_certificate_id"],
        "obligations": [
            {
                "text": text,
                "satisfied": bool(satisfied),
            }
            for text, satisfied in zip(
                THEOREM_TARGETS["four_round_proof_obligations"], obligations
            )
        ],
        "middle_bundle_cases": middle_cases,
        "active_source_columns_at_least_5_immediate": True,
        "outer_branch_factors": [5, 5],
        "four_round_active_rotor_lower_bound": 25,
        "single_trail_differential_probability_log2_upper": -150,
        "single_trail_linear_correlation_log2_upper": -75,
        "scope": THEOREM_TARGETS["scope"],
        "pass": all(obligations),
    }


# ---------------------------------------------------------------------------
# Exact rotor diagnostics


def is_affine_8bit(table: np.ndarray) -> bool:
    base = int(table[0])
    columns = [int(table[1 << bit]) ^ base for bit in range(8)]
    for value in range(256):
        prediction = base
        for bit in range(8):
            if (value >> bit) & 1:
                prediction ^= columns[bit]
        if prediction != int(table[value]):
            return False
    return True


def anf_degree(table: np.ndarray) -> int:
    maximum = 0
    for output_bit in range(8):
        coefficients = ((table >> output_bit) & 1).astype(np.uint8)
        for bit in range(8):
            step = 1 << bit
            for mask in range(256):
                if mask & step:
                    coefficients[mask] ^= coefficients[mask ^ step]
        active = np.flatnonzero(coefficients)
        if len(active):
            maximum = max(
                maximum,
                max(bin(int(index)).count("1") for index in active),
            )
    return int(maximum)


def ddt_diagnostics(table: np.ndarray) -> dict:
    matrix = np.zeros((256, 256), dtype=np.uint16)
    for difference in range(256):
        outputs = np.bitwise_xor(
            table,
            table[np.bitwise_xor(IDENTITY_U8, difference)],
        )
        matrix[difference] = np.bincount(outputs, minlength=256).astype(np.uint16)
    return {
        "differential_uniformity": int(matrix[1:].max()),
        "spectrum_sha256": sha256_bytes(matrix.astype("<u2", copy=False).tobytes(order="C")),
    }


def fwht(values: np.ndarray) -> np.ndarray:
    result = values.astype(np.int16, copy=True)
    span = 1
    while span < 256:
        shaped = result.reshape((-1, span * 2))
        left = shaped[:, :span].copy()
        right = shaped[:, span:].copy()
        shaped[:, :span] = left + right
        shaped[:, span:] = left - right
        span *= 2
    return result


def lat_diagnostics(table: np.ndarray) -> dict:
    matrix = np.zeros((256, 256), dtype=np.int16)
    for output_mask in range(256):
        parity = PARITY_BYTE[np.bitwise_and(table, output_mask)].astype(np.int16)
        signs = 1 - 2 * parity
        matrix[:, output_mask] = fwht(signs)
    return {
        "maximum_absolute_coefficient": int(np.abs(matrix[1:, 1:]).max()),
        "spectrum_sha256": sha256_bytes(matrix.astype("<i2", copy=False).tobytes(order="C")),
    }


def validate_namespaces() -> Tuple[Dict[int, RotorNamespace], dict]:
    namespaces: Dict[int, RotorNamespace] = {}
    inverse_manifest = hashlib.sha256()
    namespace_records = []
    inverse_pairs = 0
    inverse_failures = 0
    for key_label in KEY_LABELS:
        namespace = RotorNamespace(extract_prk(test_ikm(key_label)))
        namespace.build_all()
        namespaces[key_label] = namespace
        raw_namespace = namespace.serialize()
        for logical_id in range(256):
            forward = namespace.forward[logical_id]
            inverse = namespace.inverse[logical_id]
            forward_bijection = len(np.unique(forward)) == 256
            inverse_bijection = len(np.unique(inverse)) == 256
            both_orders = bool(
                np.array_equal(inverse[forward], IDENTITY_U8)
                and np.array_equal(forward[inverse], IDENTITY_U8)
            )
            if not (forward_bijection and inverse_bijection and both_orders):
                inverse_failures += 1
            record = namespace.table_record(logical_id)
            inverse_manifest.update(record)
            inverse_pairs += 1
        namespace_records.append(
            {
                "key_label": key_label,
                "corpus": corpus_for_label(key_label),
                "namespace_sha256": sha256_bytes(raw_namespace),
                "namespace_bytes": len(raw_namespace),
            }
        )
    require_equal(inverse_pairs, 1024, "exhaustive rotor inverse pair count")

    key_zero = namespaces[0]
    table_record_hashes = [
        sha256_bytes(key_zero.table_record(logical_id)) for logical_id in range(256)
    ]
    duplicate_count = 256 - len(set(table_record_hashes))

    spectra = []
    quality_failures = []
    for key_label in SPECTRUM_KEY_LABELS:
        namespace = namespaces[key_label]
        for logical_id in SPECTRUM_IDS:
            table = namespace.forward[logical_id]
            inverse = namespace.inverse[logical_id]
            ddt = ddt_diagnostics(table)
            lat = lat_diagnostics(table)
            record = {
                "key_label": key_label,
                "corpus": corpus_for_label(key_label),
                "logical_id": logical_id,
                "table_record_sha256": sha256_bytes(namespace.table_record(logical_id)),
                "bijection": len(np.unique(table)) == 256,
                "inverse_exact": bool(
                    np.array_equal(inverse[table], IDENTITY_U8)
                    and np.array_equal(table[inverse], IDENTITY_U8)
                ),
                "is_affine": is_affine_8bit(table),
                "differential_uniformity": ddt["differential_uniformity"],
                "ddt_spectrum_sha256": ddt["spectrum_sha256"],
                "maximum_absolute_lat": lat["maximum_absolute_coefficient"],
                "lat_spectrum_sha256": lat["spectrum_sha256"],
                "forward_algebraic_degree": anf_degree(table),
                "inverse_algebraic_degree": anf_degree(inverse),
            }
            passed = bool(
                record["bijection"]
                and record["inverse_exact"]
                and not record["is_affine"]
                and record["differential_uniformity"] == 4
                and record["maximum_absolute_lat"] == 32
                and record["forward_algebraic_degree"] == 7
                and record["inverse_algebraic_degree"] == 7
            )
            record["pass"] = passed
            if not passed:
                quality_failures.append([key_label, logical_id])
            spectra.append(record)
    require_equal(len(spectra), 32, "rotor spectrum record count")
    return namespaces, {
        "exhaustive_inverse_validation": {
            "key_labels": list(KEY_LABELS),
            "logical_ids_per_key": 256,
            "table_pairs": inverse_pairs,
            "failures": inverse_failures,
            "table_record_manifest_sha256": inverse_manifest.hexdigest(),
            "pass": inverse_failures == 0,
        },
        "namespace_records": namespace_records,
        "key_label_0_namespace_sha256": sha256_bytes(key_zero.serialize()),
        "key_label_0_namespace_bytes": len(key_zero.serialize()),
        "key_label_0_duplicate_table_count": duplicate_count,
        "key_label_0_table_record_digest_manifest_sha256": sha256_bytes(
            b"".join(bytes.fromhex(value) for value in table_record_hashes)
        ),
        "spectrum_records": spectra,
        "spectrum_record_count": len(spectra),
        "spectrum_quality_failures": quality_failures,
        "spectrum_pass": not quality_failures,
    }


# ---------------------------------------------------------------------------
# Frozen corpus, material separation, and sampled round trips


@dataclass(frozen=True)
class ContextExecution:
    key_label: int
    stream_index: int
    direction: int
    case_id: str
    sequence: int
    counter: int
    corpus: str
    stream_id: bytes
    context: bytes
    material: RoundMaterial

    def tag(self) -> dict:
        return {
            "key_label": self.key_label,
            "stream_index": self.stream_index,
            "direction": self.direction,
            "context_case": self.case_id,
            "sequence": self.sequence,
            "counter": self.counter,
        }


def roundtrip_block(context: bytes, block_index: int) -> bytes:
    return hashlib.sha512(
        b"E256-W/gate/block/v1/" + field(context) + u16be(block_index)
    ).digest()[:32]


def build_context_campaign(
    namespaces: Dict[int, RotorNamespace],
    inverse_mix: Sequence[Sequence[int]],
) -> Tuple[List[ContextExecution], dict]:
    executions: List[ContextExecution] = []
    lookup: Dict[Tuple[int, int, int, str], ContextExecution] = {}
    material_records = []
    material_aggregate = hashlib.sha256()
    selection_aggregate = hashlib.sha256()
    mask_aggregate = hashlib.sha256()
    rotor_histogram = [0] * 256

    for key_label in KEY_LABELS:
        corpus = corpus_for_label(key_label)
        prk = extract_prk(test_ikm(key_label))
        for stream_index in STREAM_INDICES:
            stream_id = stream_id_for(key_label, stream_index)
            for direction in DIRECTIONS:
                for case in CONTEXT_CASES:
                    context = canonical_context(
                        corpus,
                        stream_id,
                        direction,
                        int(case["sequence"]),
                        int(case["counter"]),
                    )
                    material = derive_round_material(prk, context)
                    execution = ContextExecution(
                        key_label=key_label,
                        stream_index=stream_index,
                        direction=direction,
                        case_id=str(case["id"]),
                        sequence=int(case["sequence"]),
                        counter=int(case["counter"]),
                        corpus=corpus,
                        stream_id=stream_id,
                        context=context,
                        material=material,
                    )
                    executions.append(execution)
                    lookup[(key_label, stream_index, direction, execution.case_id)] = execution
                    raw = material.serialize()
                    ids_raw = material.selection_bytes()
                    masks_raw = material.mask_bytes()
                    material_aggregate.update(raw)
                    selection_aggregate.update(ids_raw)
                    mask_aggregate.update(masks_raw)
                    for value in ids_raw:
                        rotor_histogram[value] += 1
                    material_records.append(
                        {
                            **execution.tag(),
                            "canonical_context_sha256": sha256_bytes(context),
                            "complete_material_sha256": sha256_bytes(raw),
                            "selection_sha256": sha256_bytes(ids_raw),
                            "round_masks_sha256": sha256_bytes(masks_raw),
                            "material_bytes": len(raw),
                        }
                    )
    require_equal(len(executions), 144, "executed context count")

    roundtrip_manifest = ManifestHasher()
    roundtrip_tests = 0
    roundtrip_failures = []
    state_width_failures = 0
    for execution in executions:
        namespace = namespaces[execution.key_label]
        for block_index in range(8):
            plaintext = roundtrip_block(execution.context, block_index)
            if len(plaintext) != 32:
                state_width_failures += 1
            for rounds in ROUND_COUNTS:
                ciphertext = permute(
                    plaintext,
                    namespace,
                    execution.material,
                    rounds,
                    mode="candidate",
                    offsets=ROW_OFFSETS,
                    mix_matrix=MIX_MATRIX,
                )
                recovered = inverse_permute(
                    ciphertext,
                    namespace,
                    execution.material,
                    rounds,
                    mode="candidate",
                    offsets=ROW_OFFSETS,
                    inverse_mix_matrix=inverse_mix,
                )
                if len(ciphertext) != 32 or len(recovered) != 32:
                    state_width_failures += 1
                matched = recovered == plaintext
                if not matched:
                    roundtrip_failures.append(
                        {**execution.tag(), "block_index": block_index, "rounds": rounds}
                    )
                roundtrip_manifest.update(
                    {
                        **execution.tag(),
                        "block_index": block_index,
                        "rounds": rounds,
                        "plaintext_sha256": sha256_bytes(plaintext),
                        "ciphertext_sha256": sha256_bytes(ciphertext),
                        "roundtrip": matched,
                    }
                )
                roundtrip_tests += 1
    require_equal(roundtrip_tests, 13824, "sampled roundtrip count")

    context_records = []
    context_collisions = 0
    for key_label in KEY_LABELS:
        for stream_index in STREAM_INDICES:
            for direction in DIRECTIONS:
                for first_id, second_id in CONTEXT_PAIR_IDS:
                    first = lookup[(key_label, stream_index, direction, first_id)]
                    second = lookup[(key_label, stream_index, direction, second_id)]
                    first_raw = first.material.serialize()
                    second_raw = second.material.serialize()
                    collision = first_raw == second_raw
                    context_collisions += int(collision)
                    context_records.append(
                        {
                            "key_label": key_label,
                            "stream_index": stream_index,
                            "direction": direction,
                            "first_context_case": first_id,
                            "second_context_case": second_id,
                            "first_material_sha256": sha256_bytes(first_raw),
                            "second_material_sha256": sha256_bytes(second_raw),
                            "collision": collision,
                        }
                    )
    require_equal(len(context_records), 112, "context separation comparisons")

    direction_records = []
    direction_collisions = 0
    for key_label in KEY_LABELS:
        for stream_index in STREAM_INDICES:
            for case in CONTEXT_CASES:
                case_id = str(case["id"])
                first = lookup[(key_label, stream_index, 0, case_id)]
                second = lookup[(key_label, stream_index, 1, case_id)]
                first_raw = first.material.serialize()
                second_raw = second.material.serialize()
                collision = first_raw == second_raw
                direction_collisions += int(collision)
                direction_records.append(
                    {
                        "key_label": key_label,
                        "stream_index": stream_index,
                        "context_case": case_id,
                        "first_material_sha256": sha256_bytes(first_raw),
                        "second_material_sha256": sha256_bytes(second_raw),
                        "collision": collision,
                    }
                )
    require_equal(len(direction_records), 72, "direction separation comparisons")

    id_count = sum(rotor_histogram)
    repeat_count = sum(max(count - 1, 0) for count in rotor_histogram)
    require_equal(id_count, 55296, "rotor-ID traversal count")
    return executions, {
        "contexts": len(executions),
        "material_records": material_records,
        "material_record_manifest_sha256": sha256_bytes(canonical_json_bytes(material_records)),
        "complete_material_aggregate_sha256": material_aggregate.hexdigest(),
        "selection_aggregate_sha256": selection_aggregate.hexdigest(),
        "round_masks_aggregate_sha256": mask_aggregate.hexdigest(),
        "roundtrip_tests": roundtrip_tests,
        "roundtrip_failures": roundtrip_failures,
        "roundtrip_manifest_count": roundtrip_manifest.count,
        "roundtrip_manifest_sha256": roundtrip_manifest.hexdigest(),
        "state_width_failures": state_width_failures,
        "context_separation": {
            "comparisons": len(context_records),
            "collisions": context_collisions,
            "records": context_records,
            "records_sha256": sha256_bytes(canonical_json_bytes(context_records)),
            "pass": context_collisions == 0,
        },
        "direction_separation": {
            "comparisons": len(direction_records),
            "collisions": direction_collisions,
            "records": direction_records,
            "records_sha256": sha256_bytes(canonical_json_bytes(direction_records)),
            "pass": direction_collisions == 0,
        },
        "rotor_id_repeat_diagnostic": {
            "selection_ids": id_count,
            "occurrence_histogram": rotor_histogram,
            "repeat_count_after_first_occurrence": repeat_count,
        },
        "pass": bool(
            not roundtrip_failures
            and state_width_failures == 0
            and context_collisions == 0
            and direction_collisions == 0
        ),
        "lookup": lookup,
    }


def key_bit_flip_probe(
    base_namespace: RotorNamespace,
    base_execution: ContextExecution,
) -> dict:
    base_raw = base_namespace.serialize() + base_execution.material.serialize()
    if len(base_raw) != 131872:
        raise ContractError("base key-bit-flip material is not 131872 bytes")
    records = []
    collisions = 0
    base_ikm = test_ikm(0)
    for bit_index in KEY_FLIP_INDICES:
        changed = bytearray(base_ikm)
        changed[bit_index // 8] ^= 1 << (bit_index % 8)
        changed_prk = extract_prk(bytes(changed))
        changed_namespace = RotorNamespace(changed_prk)
        changed_namespace.build_all()
        changed_material = derive_round_material(changed_prk, base_execution.context)
        changed_raw = changed_namespace.serialize() + changed_material.serialize()
        if len(changed_raw) != 131872:
            raise ContractError("mutated key-bit-flip material is not 131872 bytes")
        collision = changed_raw == base_raw
        collisions += int(collision)
        records.append(
            {
                "bit_index": bit_index,
                "base_material_sha256": sha256_bytes(base_raw),
                "mutated_material_sha256": sha256_bytes(changed_raw),
                "material_bytes": len(changed_raw),
                "collision": collision,
            }
        )
    require_equal(len(records), 12, "key-bit-flip comparison count")
    return {
        "comparisons": len(records),
        "collisions": collisions,
        "records": records,
        "records_sha256": sha256_bytes(canonical_json_bytes(records)),
        "pass": collisions == 0,
    }


# ---------------------------------------------------------------------------
# Affine probes, avalanche diagnostics, controls, and baselines


def derive_affine_holdouts() -> List[bytes]:
    holdouts: List[bytes] = []
    seen: Set[bytes] = set()
    count = int(CORPUS["affine_probe"]["holdout_count"])
    for index in range(count):
        selected = None
        for attempt in range(65536):
            value = hashlib.sha512(
                b"E256-W/gate/affine-holdout/v1/" + u16be(index) + u16be(attempt)
            ).digest()[:32]
            bit_weight = sum(int(POPCOUNT_BYTE[byte]) for byte in value)
            if value != bytes(32) and bit_weight != 1 and value not in seen:
                selected = value
                break
        if selected is None:
            raise ContractError(f"no admissible affine holdout for index {index}")
        seen.add(selected)
        holdouts.append(selected)
    require_equal(len(holdouts), 64, "affine holdout count")
    return holdouts


def basis_vector(bit_index: int) -> bytes:
    bit_index = _integer(bit_index, 0, 255, "basis bit")
    value = bytearray(32)
    value[bit_index // 8] = 1 << (bit_index % 8)
    return bytes(value)


def affine_predict(offset: bytes, columns: Sequence[bytes], value: bytes) -> bytes:
    if len(offset) != 32 or len(columns) != 256 or len(value) != 32:
        raise ValueError("affine model dimensions mismatch")
    prediction = bytearray(offset)
    for byte_index, byte_value in enumerate(value):
        for bit in range(8):
            if (byte_value >> bit) & 1:
                column = columns[8 * byte_index + bit]
                for output_index in range(32):
                    prediction[output_index] ^= column[output_index]
    return bytes(prediction)


def affine_probe(
    namespace: RotorNamespace,
    material: RoundMaterial,
    holdouts: Sequence[bytes],
    mode: str,
    inverse_mix: Sequence[Sequence[int]],
    trace: Optional[SharedPathTrace] = None,
    verify_inverse_path: bool = False,
) -> dict:
    if trace is not None:
        trace.mark_if_expected("affine probe")
    records = []
    for rounds in AFFINE_ROUNDS:
        zero_output = permute(
            bytes(32), namespace, material, rounds, mode=mode,
            offsets=ROW_OFFSETS, mix_matrix=MIX_MATRIX, trace=trace,
        )
        basis_outputs = [
            permute(
                basis_vector(bit_index), namespace, material, rounds, mode=mode,
                offsets=ROW_OFFSETS, mix_matrix=MIX_MATRIX, trace=trace,
            )
            for bit_index in range(256)
        ]
        columns = [
            bytes(first ^ second for first, second in zip(output, zero_output))
            for output in basis_outputs
        ]
        matches = 0
        inverse_failures = 0
        actual_outputs = []
        for holdout in holdouts:
            actual = permute(
                holdout, namespace, material, rounds, mode=mode,
                offsets=ROW_OFFSETS, mix_matrix=MIX_MATRIX, trace=trace,
            )
            prediction = affine_predict(zero_output, columns, holdout)
            matches += int(actual == prediction)
            actual_outputs.append(actual)
            if verify_inverse_path:
                recovered = inverse_permute(
                    actual,
                    namespace,
                    material,
                    rounds,
                    mode=mode,
                    offsets=ROW_OFFSETS,
                    inverse_mix_matrix=inverse_mix,
                    trace=trace,
                )
                inverse_failures += int(recovered != holdout)
        records.append(
            {
                "rounds": rounds,
                "model_samples": 257,
                "holdouts": len(holdouts),
                "matches": matches,
                "mismatches": len(holdouts) - matches,
                "inverse_failures": inverse_failures,
                "model_output_manifest_sha256": sha256_bytes(
                    zero_output + b"".join(basis_outputs)
                ),
                "holdout_output_manifest_sha256": sha256_bytes(b"".join(actual_outputs)),
            }
        )
    return {
        "mode": mode,
        "records": records,
        "every_round_has_mismatch": all(record["mismatches"] >= 1 for record in records),
        "every_round_matches_all": all(record["matches"] == len(holdouts) for record in records),
        "inverse_failures": sum(record["inverse_failures"] for record in records),
    }


def self_composition_probe(
    namespace: RotorNamespace,
    material: RoundMaterial,
    holdouts: Sequence[bytes],
    mode: str,
) -> dict:
    matches = 0
    output_manifest = hashlib.sha256()
    for holdout in holdouts:
        first = permute(holdout, namespace, material, 4, mode=mode, offsets=ROW_OFFSETS, mix_matrix=MIX_MATRIX)
        second = permute(first, namespace, material, 4, mode=mode, offsets=ROW_OFFSETS, mix_matrix=MIX_MATRIX)
        matches += int(second == holdout)
        output_manifest.update(second)
    return {
        "probes": len(holdouts),
        "self_composition_identity_matches": matches,
        "self_composition_mismatches": len(holdouts) - matches,
        "output_manifest_sha256": output_manifest.hexdigest(),
        "fails_identity_on_at_least_one_probe": matches < len(holdouts),
    }


def avalanche_probe(
    namespaces: Dict[int, RotorNamespace],
    lookup: Dict[Tuple[int, int, int, str], ContextExecution],
) -> dict:
    records = []
    comparisons = 0
    for key_label in tuple(int(value) for value in CORPUS["avalanche_probe"]["key_labels"]):
        execution = lookup[(key_label, 0, 0, "counter_0")]
        namespace = namespaces[key_label]
        for rounds in AVALANCHE_ROUNDS:
            base = permute(bytes(32), namespace, execution.material, rounds)
            histogram = [0] * 257
            for bit_index in range(256):
                changed = permute(basis_vector(bit_index), namespace, execution.material, rounds)
                distance = sum(int(POPCOUNT_BYTE[first ^ second]) for first, second in zip(base, changed))
                histogram[distance] += 1
                comparisons += 1
            require_equal(len(histogram), 257, "avalanche histogram length")
            require_equal(sum(histogram), 256, "avalanche histogram comparisons")
            records.append(
                {
                    "key_label": key_label,
                    "rounds": rounds,
                    "histogram": histogram,
                    "comparisons": 256,
                }
            )
    require_equal(comparisons, 4096, "avalanche comparison count")
    return {
        "records": records,
        "record_count": len(records),
        "comparisons": comparisons,
        "records_sha256": sha256_bytes(canonical_json_bytes(records)),
        "diagnostic_only": True,
    }


def control_definition(control_id: str) -> dict:
    return next(record for record in PREREG_DATA["planted_controls"] if record["id"] == control_id)


def finish_control(
    definition: dict,
    trace: SharedPathTrace,
    detected: bool,
    details: dict,
) -> dict:
    record = {
        "id": definition["id"],
        "mutation": definition["mutation"],
        "detector": definition["detector"],
        "required_result": definition["required_result"],
        "declared_shared_path": list(definition["shared_path"]),
        "executed_shared_path": trace.record(),
        "shared_path_exact": trace.complete(),
        "detected": bool(detected),
        "details": details,
    }
    if "adapter_exception" in definition:
        record["adapter_exception"] = definition["adapter_exception"]
    record["pass"] = bool(record["shared_path_exact"] and record["detected"])
    return record


def run_controls_and_baselines(
    namespace: RotorNamespace,
    base_execution: ContextExecution,
    holdouts: Sequence[bytes],
    inverse_mix: Sequence[Sequence[int]],
    candidate_affine: dict,
    fixed_affine: dict,
    candidate_dependency: dict,
    fixed_dependency: dict,
) -> Tuple[dict, dict, dict]:
    records: Dict[str, dict] = {}

    definition = control_definition("affine_rotor_bypass")
    trace = SharedPathTrace(definition["shared_path"])
    material = derive_round_material(extract_prk(test_ikm(0)), base_execution.context, trace=trace)
    identity_affine = affine_probe(
        namespace,
        material,
        holdouts,
        mode="identity",
        inverse_mix=inverse_mix,
        trace=trace,
        verify_inverse_path=True,
    )
    detected = bool(identity_affine["every_round_matches_all"] and identity_affine["inverse_failures"] == 0)
    records[definition["id"]] = finish_control(definition, trace, detected, identity_affine)

    definition = control_definition("no_diffusion")
    trace = SharedPathTrace(definition["shared_path"])
    material = derive_round_material(extract_prk(test_ikm(0)), base_execution.context, trace=trace)
    no_diffusion_dependency = dependency_reachability(ZERO_ROW_OFFSETS, IDENTITY_MIX_MATRIX, trace=trace)
    control_plaintext = roundtrip_block(base_execution.context, 0)
    no_diffusion_roundtrip_failures = 0
    for rounds in ROUND_COUNTS:
        ciphertext = permute(
            control_plaintext,
            namespace,
            material,
            rounds,
            mode="candidate",
            offsets=ZERO_ROW_OFFSETS,
            mix_matrix=IDENTITY_MIX_MATRIX,
            trace=trace,
        )
        recovered = inverse_permute(
            ciphertext,
            namespace,
            material,
            rounds,
            mode="candidate",
            offsets=ZERO_ROW_OFFSETS,
            inverse_mix_matrix=IDENTITY_MIX_MATRIX,
            trace=trace,
        )
        no_diffusion_roundtrip_failures += int(recovered != control_plaintext)
    detected = bool(
        no_diffusion_dependency["isolated_same_lane_all_rounds"]
        and no_diffusion_roundtrip_failures == 0
    )
    records[definition["id"]] = finish_control(
        definition,
        trace,
        detected,
        {
            "dependency": no_diffusion_dependency,
            "roundtrip_tests": 12,
            "roundtrip_failures": no_diffusion_roundtrip_failures,
        },
    )

    definition = control_definition("singular_mix_matrix")
    trace = SharedPathTrace(definition["shared_path"])
    singular = [list(row) for row in MIX_MATRIX]
    singular[3] = list(singular[2])
    caught: Optional[StructuralError] = None
    try:
        analyze_mix_matrix(singular, trace=trace)
    except StructuralError as error:
        caught = error
    detected = bool(
        caught is not None
        and caught.code == "SINGULAR_MIX_MATRIX"
        and caught.details.get("inverse_available") is False
        and caught.details.get("inverse_attempted") is False
        and (
            int(caught.details.get("determinant", 1)) == 0
            or int(caught.details.get("zero_minor_count", 0)) > 0
        )
    )
    records[definition["id"]] = finish_control(
        definition,
        trace,
        detected,
        {
            "error_code": caught.code if caught is not None else None,
            "structural_diagnostic": caught.details if caught is not None else None,
            "permutation_attempted": False,
        },
    )

    definition = control_definition("zero_row_shifts")
    trace = SharedPathTrace(definition["shared_path"])
    zero_dependency = dependency_reachability(ZERO_ROW_OFFSETS, MIX_MATRIX, trace=trace)
    zero_dispersion = row_dispersion_certificate(ZERO_ROW_OFFSETS, trace=trace)
    detected = zero_dependency["earliest_all_to_all_round"] is None
    records[definition["id"]] = finish_control(
        definition,
        trace,
        detected,
        {"dependency": zero_dependency, "row_dispersion": zero_dispersion},
    )

    candidate_self = self_composition_probe(namespace, base_execution.material, holdouts, "candidate")
    fixed_self = self_composition_probe(namespace, base_execution.material, holdouts, "fixed_aes")

    definition = control_definition("reciprocal_sandwich")
    trace = SharedPathTrace(definition["shared_path"])
    control_root = subkey(extract_prk(test_ikm(0)), "controls")
    stream = PurposeStream(control_root, RECIPROCAL_CONTROL_DOMAIN)
    reciprocal_mask = bytes(32)
    mask_reads = 0
    while reciprocal_mask == bytes(32):
        reciprocal_mask = stream.read(32)
        mask_reads += 1
    reciprocal_matches = 0
    reciprocal_manifest = hashlib.sha256()

    def reciprocal(value: bytes) -> bytes:
        forward = permute(
            value,
            namespace,
            base_execution.material,
            4,
            mode="candidate",
            offsets=ROW_OFFSETS,
            mix_matrix=MIX_MATRIX,
            trace=trace,
            trace_stage="candidate permute",
        )
        masked = bytes(first ^ second for first, second in zip(forward, reciprocal_mask))
        return inverse_permute(
            masked,
            namespace,
            base_execution.material,
            4,
            mode="candidate",
            offsets=ROW_OFFSETS,
            inverse_mix_matrix=inverse_mix,
            trace=trace,
            trace_stage="candidate inverse permute",
        )

    for holdout in holdouts:
        twice = reciprocal(reciprocal(holdout))
        reciprocal_matches += int(twice == holdout)
        reciprocal_manifest.update(twice)
    detected = reciprocal_matches == len(holdouts)
    records[definition["id"]] = finish_control(
        definition,
        trace,
        detected,
        {
            "mask_reads": mask_reads,
            "mask_sha256": sha256_bytes(reciprocal_mask),
            "probes": len(holdouts),
            "involution_matches": reciprocal_matches,
            "output_manifest_sha256": reciprocal_manifest.hexdigest(),
            "candidate_null_calibration": candidate_self,
            "fixed_aes_null_calibration": fixed_self,
        },
    )

    definition = control_definition("truncated_counter_32")
    trace = SharedPathTrace(definition["shared_path"])
    prk = extract_prk(test_ikm(0))
    stream_id = stream_id_for(0, 0)
    truncated_materials = []
    for original_counter in (0, 1 << 32):
        context = canonical_context(
            "e256-wide-train",
            stream_id,
            0,
            7,
            original_counter % (1 << 32),
            trace=trace,
        )
        truncated_materials.append(derive_round_material(prk, context, trace=trace))
    trace.mark_if_expected("complete material collision detector")
    truncated_collision = truncated_materials[0].serialize() == truncated_materials[1].serialize()
    records[definition["id"]] = finish_control(
        definition,
        trace,
        truncated_collision,
        {
            "counter_0_material_sha256": sha256_bytes(truncated_materials[0].serialize()),
            "counter_2p32_material_sha256": sha256_bytes(truncated_materials[1].serialize()),
            "complete_material_collision": truncated_collision,
        },
    )

    definition = control_definition("direction_omitted")
    trace = SharedPathTrace(definition["shared_path"])
    direction_materials = []
    for tagged_direction in DIRECTIONS:
        context = canonical_context(
            "e256-wide-train", stream_id, 0, 7, 0, trace=trace
        )
        direction_materials.append(derive_round_material(prk, context, trace=trace))
    trace.mark_if_expected("complete material collision detector")
    direction_collision = direction_materials[0].serialize() == direction_materials[1].serialize()
    records[definition["id"]] = finish_control(
        definition,
        trace,
        direction_collision,
        {
            "tagged_directions": list(DIRECTIONS),
            "direction_0_material_sha256": sha256_bytes(direction_materials[0].serialize()),
            "direction_1_material_sha256": sha256_bytes(direction_materials[1].serialize()),
            "complete_material_collision": direction_collision,
        },
    )

    executed_ids = tuple(records)
    ids_exact = executed_ids == CONTROL_IDS
    candidate_null_checks = {
        "affine_mismatch_every_frozen_round": candidate_affine["every_round_has_mismatch"],
        "dependency_not_lane_isolated": not candidate_dependency["isolated_same_lane_all_rounds"],
        "dependency_all_to_all_by_round_3": candidate_dependency["all_to_all_by_round_3"],
        "four_round_self_composition_fails_identity": candidate_self["fails_identity_on_at_least_one_probe"],
    }
    baseline_null_checks = {
        "affine_mismatch_every_frozen_round": fixed_affine["every_round_has_mismatch"],
        "dependency_not_lane_isolated": not fixed_dependency["isolated_same_lane_all_rounds"],
        "four_round_self_composition_fails_identity": fixed_self["fails_identity_on_at_least_one_probe"],
    }
    controls = {
        "frozen_control_ids": list(CONTROL_IDS),
        "executed_control_ids": list(executed_ids),
        "control_ids_exact": ids_exact,
        "records": records,
        "all_planted_controls_detected": all(record["detected"] for record in records.values()),
        "all_shared_paths_exact": all(record["shared_path_exact"] for record in records.values()),
        "candidate_nulls": {
            "checks": candidate_null_checks,
            "pass": all(candidate_null_checks.values()),
        },
        "baseline_nulls": {
            "checks": baseline_null_checks,
            "pass": all(baseline_null_checks.values()),
        },
    }
    controls["pass"] = bool(
        controls["control_ids_exact"]
        and controls["all_planted_controls_detected"]
        and controls["all_shared_paths_exact"]
        and controls["candidate_nulls"]["pass"]
        and controls["baseline_nulls"]["pass"]
    )

    fixed_baseline = {
        "id": "fixed_aes_spn",
        "uses_identical_candidate_material": True,
        "selection_bytes_derived_and_retained": 384,
        "round_mask_bytes_shared": 416,
        "affine_probe": fixed_affine,
        "dependency": fixed_dependency,
        "four_round_self_composition": fixed_self,
        "same_structural_trail_bounds": True,
        "required_nulls_pass": controls["baseline_nulls"]["pass"],
        "security_advantage_over_fixed_aes_claimed": False,
    }
    aead_baseline = {
        "id": "aead_only",
        "inner_permutation": "none",
        "byte_metrics": "not applicable",
        "inner_transform_operations": 0,
        "mandatory_production_baseline": True,
    }
    baselines = {
        "frozen_baseline_ids": list(BASELINE_IDS),
        "executed_baseline_ids": ["fixed_aes_spn", "aead_only"],
        "baseline_ids_exact": BASELINE_IDS == ("fixed_aes_spn", "aead_only"),
        "records": {
            "fixed_aes_spn": fixed_baseline,
            "aead_only": aead_baseline,
        },
        "pass": bool(
            BASELINE_IDS == ("fixed_aes_spn", "aead_only")
            and fixed_baseline["required_nulls_pass"]
            and aead_baseline["mandatory_production_baseline"]
        ),
    }
    load_bearing = {
        "candidate_affine_probe": candidate_affine,
        "fixed_aes_affine_probe": fixed_affine,
        "identity_rotor_control": identity_affine,
        "candidate_four_round_self_composition": candidate_self,
        "fixed_aes_four_round_self_composition": fixed_self,
        "candidate_dependency": candidate_dependency,
        "fixed_aes_dependency": fixed_dependency,
    }
    return controls, baselines, load_bearing


# ---------------------------------------------------------------------------
# Receipt construction, validity gate, check mode, and output


def verify_frozen_inputs() -> dict:
    toolchain = verify_toolchain()
    validate_exact_operational_records()
    architecture = architecture_authorization_record()
    predecessor = predecessor_record()
    purpose_stream = purpose_stream_contract_self_test()
    primitives = initialize_primitives()
    reread = strict_json_load(PREREG)
    require_equal(reread, PREREG_DATA, "reread preregistration")
    return {
        "preregistration": {
            "path": str(PREREG.relative_to(REPO)),
            "raw_sha256": sha256_file(PREREG),
            "canonical_sha256": sha256_bytes(canonical_json_bytes(PREREG_DATA)),
            "schema": PREREG_DATA["schema"],
            "status": PREREG_DATA["status"],
            "top_level_keys": list(PREREG_TOP_LEVEL_KEYS),
        },
        "architecture": architecture,
        "predecessor": predecessor,
        "toolchain": toolchain,
        "purpose_stream_contract": purpose_stream,
        "primitives": primitives,
        "runner": {
            "path": str(Path(__file__).resolve().relative_to(REPO)),
            "sha256": sha256_file(Path(__file__).resolve()),
            "does_not_import_predecessor_runner": True,
        },
        "authorization": {
            "accepted_research_constraints": list(ACCEPTED_CONSTRAINT_IDS),
            "accepted_constraint_definitions": AUTHORIZATION["accepted_constraint_definitions"],
            "allowed": AUTHORIZATION["allowed"],
            "blocked": AUTHORIZATION["blocked"],
        },
    }


def environment_advisory(elapsed_seconds: float) -> dict:
    def run(command: Sequence[str]) -> Tuple[bool, str]:
        try:
            result = subprocess.run(
                command,
                capture_output=True,
                text=True,
                timeout=20,
                check=False,
            )
            return result.returncode == 0, result.stdout.strip()
        except Exception:
            return False, ""

    head_ok, head = run(["git", "-C", str(REPO), "rev-parse", "HEAD"])
    status_ok, status = run(["git", "-C", str(REPO), "status", "--porcelain"])
    return {
        "platform": platform.platform(),
        "elapsed_seconds": round(float(elapsed_seconds), 3),
        "git_head": head.splitlines()[0] if head_ok and head else "unavailable",
        "git_dirty": bool(status) if status_ok else "unavailable",
    }


def build_receipt() -> dict:
    started = time.perf_counter()
    inputs = verify_frozen_inputs()

    mix_record = analyze_mix_matrix(MIX_MATRIX)
    inverse_mix = tuple(tuple(int(value) for value in row) for row in mix_record["inverse"])
    row_record = row_dispersion_certificate(ROW_OFFSETS)
    candidate_dependency = dependency_reachability(ROW_OFFSETS, MIX_MATRIX)
    fixed_dependency = dependency_reachability(ROW_OFFSETS, MIX_MATRIX)
    trail_record = wide_trail_certificate(mix_record, row_record)

    namespaces, rotor_results = validate_namespaces()
    executions, campaign = build_context_campaign(namespaces, inverse_mix)
    lookup = campaign.pop("lookup")
    base_execution = lookup[(0, 0, 0, "counter_0")]
    key_flips = key_bit_flip_probe(namespaces[0], base_execution)

    holdouts = derive_affine_holdouts()
    holdout_record = {
        "count": len(holdouts),
        "distinct": len(set(holdouts)) == len(holdouts),
        "manifest_sha256": sha256_bytes(b"".join(holdouts)),
        "all_nonzero_nonbasis": all(
            value != bytes(32)
            and sum(int(POPCOUNT_BYTE[byte]) for byte in value) != 1
            for value in holdouts
        ),
    }
    candidate_affine = affine_probe(
        namespaces[0], base_execution.material, holdouts, "candidate", inverse_mix
    )
    fixed_affine = affine_probe(
        namespaces[0], base_execution.material, holdouts, "fixed_aes", inverse_mix
    )

    controls, baselines, load_bearing = run_controls_and_baselines(
        namespaces[0],
        base_execution,
        holdouts,
        inverse_mix,
        candidate_affine,
        fixed_affine,
        candidate_dependency,
        fixed_dependency,
    )
    avalanche = avalanche_probe(namespaces, lookup)

    compositional_round_bijection = {
        "all_rotors_bijective": rotor_results["exhaustive_inverse_validation"]["pass"],
        "row_shift_is_byte_permutation": sorted(
            4 * ((column + ROW_OFFSETS[row]) % 8) + row
            for column in range(8)
            for row in range(4)
        ) == list(range(32)),
        "mix_columns_determinant_nonzero": mix_record["determinant"] != 0,
        "xor_masks_invertible": True,
        "certificate_scope": "compositional only; no 2^256 exhaustive claim",
    }
    compositional_round_bijection["pass"] = all(
        value
        for key, value in compositional_round_bijection.items()
        if key != "certificate_scope"
    )

    expected_counts = {
        "contexts": 144,
        "roundtrip_tests": 13824,
        "rotor_inverse_table_pairs": 1024,
        "rotor_spectrum_records": 32,
        "mix_columns_minors": 69,
        "context_pair_comparisons": 112,
        "direction_pair_comparisons": 72,
        "key_bit_flip_comparisons": 12,
        "rotor_selection_ids": 55296,
        "affine_holdouts": 64,
        "affine_probe_rounds_per_variant": 5,
        "avalanche_comparisons": 4096,
        "avalanche_histogram_bins": 257,
        "planted_controls": 7,
        "baselines": 2,
    }
    actual_counts = {
        "contexts": campaign["contexts"],
        "roundtrip_tests": campaign["roundtrip_tests"],
        "rotor_inverse_table_pairs": rotor_results["exhaustive_inverse_validation"]["table_pairs"],
        "rotor_spectrum_records": rotor_results["spectrum_record_count"],
        "mix_columns_minors": mix_record["minor_count"],
        "context_pair_comparisons": campaign["context_separation"]["comparisons"],
        "direction_pair_comparisons": campaign["direction_separation"]["comparisons"],
        "key_bit_flip_comparisons": key_flips["comparisons"],
        "rotor_selection_ids": campaign["rotor_id_repeat_diagnostic"]["selection_ids"],
        "affine_holdouts": holdout_record["count"],
        "affine_probe_rounds_per_variant": len(candidate_affine["records"]),
        "avalanche_comparisons": avalanche["comparisons"],
        "avalanche_histogram_bins": len(avalanche["records"][0]["histogram"]),
        "planted_controls": len(controls["records"]),
        "baselines": len(baselines["records"]),
    }
    coverage_checks = {
        key: actual_counts[key] == expected_counts[key] for key in expected_counts
    }
    coverage_checks.update(
        {
            "roundtrip_manifest_complete": campaign["roundtrip_manifest_count"] == 13824,
            "all_avalanche_histograms_complete": all(
                len(record["histogram"]) == 257
                and sum(record["histogram"]) == 256
                for record in avalanche["records"]
            ),
            "material_serialization_800_bytes": all(
                record["material_bytes"] == 800 for record in campaign["material_records"]
            ),
            "namespace_serialization_131072_bytes": all(
                record["namespace_bytes"] == 131072
                for record in rotor_results["namespace_records"]
            ),
            "key_flip_serialization_131872_bytes": all(
                record["material_bytes"] == 131872 for record in key_flips["records"]
            ),
        }
    )
    coverage = {
        "canonical_traversal_order": [
            "key_label: train then holdout order 0,1,8,9",
            "stream_index: 0,1",
            "direction: 0,1",
            "context_case: preregistered order",
            "round: 1 through 12",
            "lane: 0 through 31",
        ],
        "expected_counts": expected_counts,
        "actual_counts": actual_counts,
        "checks": coverage_checks,
        "pass": all(coverage_checks.values()),
    }

    harness_checks = {
        "coverage_complete": coverage["pass"],
        "control_ids_paths_and_detectors": controls["pass"],
        "candidate_nulls_calibrated": controls["candidate_nulls"]["pass"],
        "baseline_nulls_calibrated": controls["baseline_nulls"]["pass"],
        "baseline_ids_and_policy": baselines["pass"],
    }
    if not all(harness_checks.values()):
        raise HarnessInvalid(
            {
                "status": "INVALID_CONTROLS_OR_CONTRACT",
                "checks": harness_checks,
                "coverage": coverage,
                "controls": controls,
                "baselines": baselines,
            }
        )

    functional = {
        "state_bytes": 32,
        "state_bits": 256,
        "sampled_roundtrips": campaign["roundtrip_tests"],
        "roundtrip_failures": len(campaign["roundtrip_failures"]),
        "state_width_failures": campaign["state_width_failures"],
        "roundtrip_manifest_sha256": campaign["roundtrip_manifest_sha256"],
        "compositional_round_bijection": compositional_round_bijection,
        "pass": bool(
            campaign["pass"]
            and rotor_results["exhaustive_inverse_validation"]["pass"]
            and compositional_round_bijection["pass"]
        ),
    }
    diffusion = {
        "mix_columns": mix_record,
        "row_dispersion": row_record,
        "candidate_dependency": candidate_dependency,
        "earliest_all_to_all_round": candidate_dependency["earliest_all_to_all_round"],
        "wide_trail": trail_record,
        "pass": bool(
            mix_record["pass"]
            and row_record["pass"]
            and candidate_dependency["all_to_all_by_round_3"]
            and trail_record["pass"]
        ),
    }
    context_results = {
        "material_records": campaign["material_records"],
        "material_record_manifest_sha256": campaign["material_record_manifest_sha256"],
        "complete_material_aggregate_sha256": campaign["complete_material_aggregate_sha256"],
        "selection_aggregate_sha256": campaign["selection_aggregate_sha256"],
        "round_masks_aggregate_sha256": campaign["round_masks_aggregate_sha256"],
        "context_separation": campaign["context_separation"],
        "direction_separation": campaign["direction_separation"],
        "key_bit_flip_separation": key_flips,
        "pass": bool(
            campaign["context_separation"]["pass"]
            and campaign["direction_separation"]["pass"]
            and key_flips["pass"]
        ),
    }

    candidate_hard_checks = {
        "functional_bijection_and_roundtrip": functional["pass"],
        "sampled_rotor_quality": rotor_results["spectrum_pass"],
        "mix_columns_and_wide_trail": diffusion["pass"],
        "context_material_separation": context_results["pass"],
        "candidate_non_affinity_each_probe_round": candidate_affine["every_round_has_mismatch"],
        "candidate_not_lane_isolated": not candidate_dependency["isolated_same_lane_all_rounds"],
    }
    candidate_failures = sorted(
        key for key, passed in candidate_hard_checks.items() if not passed
    )
    verdict = (
        "STRUCTURAL_WIDE_STATE_CANDIDATE_RETAINED_FOR_ATTACK_ONLY"
        if not candidate_failures
        else "WIDE_STATE_CANDIDATE_REJECTED"
    )
    require_true(verdict in VALID_VERDICTS, "noncanonical verdict")

    costs = {
        "candidate_per_round": {
            "rotor_evaluations": 32,
            "non_unit_gf_multiplications": 64,
            "mix_columns_xors": 96,
            "round_mask_xors": 32,
            "initial_mask_xors_per_permutation": 32,
        },
        "fixed_aes_per_round": {
            "fixed_aes_sbox_evaluations": 32,
            "non_unit_gf_multiplications": 64,
            "mix_columns_xors": 96,
            "round_mask_xors": 32,
            "initial_mask_xors_per_permutation": 32,
        },
        "aead_only_inner_transform_operations": 0,
        "full_forward_inverse_table_cache_bytes": 131072,
        "tableless_status": PREREG_DATA["metrics"]["cost_convention"]["tableless_status"],
    }

    results = {
        "functional": functional,
        "rotor": rotor_results,
        "diffusion": diffusion,
        "load_bearing": load_bearing,
        "context": context_results,
        "diagnostic_only": {
            "avalanche": avalanche,
            "rotor_id_repeats": campaign["rotor_id_repeat_diagnostic"],
        },
        "cost": costs,
    }

    interpretation = {
        "harness_valid": True,
        "harness_checks": harness_checks,
        "candidate_hard_checks": candidate_hard_checks,
        "candidate_hard_failures": candidate_failures,
        "verdict": verdict,
        "valid_emitted_verdicts": list(VALID_VERDICTS),
        "production_round_count": None,
        "round_selection": PREREG_DATA["interpretation"]["round_selection"],
        "candidate_retention": PREREG_DATA["interpretation"]["candidate_retention"],
        "baseline_result": PREREG_DATA["interpretation"]["baseline_result"],
        "next_if_retained": PREREG_DATA["interpretation"]["next_if_retained"],
        "production_baseline": "AEAD-only",
        "rotor_namespace_advantage_established": False,
    }

    pinned_parameters = {
        "questions": PREREG_DATA["questions"],
        "non_claims": PREREG_DATA["non_claims"],
        "byte_encodings": PREREG_DATA["byte_encodings"],
        "experimental_kdf": PREREG_DATA["experimental_kdf"],
        "execution_serialization": PREREG_DATA["execution_serialization"],
        "construction": PREREG_DATA["construction"],
        "metric_definitions": PREREG_DATA["metric_definitions"],
        "theorem_targets": PREREG_DATA["theorem_targets"],
        "corpus": PREREG_DATA["corpus"],
        "baseline_contract": PREREG_DATA["baselines"],
        "planted_control_contract": PREREG_DATA["planted_controls"],
        "control_execution_contract": PREREG_DATA["control_execution_contract"],
        "hard_rejection_rules": PREREG_DATA["hard_rejection_rules"],
        "expected_counts": expected_counts,
    }

    limitations = list(PREREG_DATA["non_claims"]) + [
        "The table-backed model is not constant-time, side-channel, leakage, or fault evidence; W9 remains open.",
        "No independent implementation, externally held KAT, full attack campaign, protocol, RTL, or external cryptographic review lands here.",
        "No production round count is selected; rounds 1 through 12 are experimental coverage only.",
    ]

    payload = {
        "schema": PREREG_DATA["receipt_contract"]["schema"],
        "status": PREREG_DATA["receipt_contract"]["status"],
        "inputs": inputs,
        "pinned_parameters": pinned_parameters,
        "coverage": coverage,
        "controls": controls,
        "baselines": baselines,
        "results": results,
        "interpretation": interpretation,
        "limitations": limitations,
    }
    require_equal(tuple(payload), PAYLOAD_TOP_LEVEL_KEYS, "deterministic payload key order")
    validate_deterministic_types(payload)
    digest = sha256_bytes(canonical_json_bytes(payload))
    elapsed = time.perf_counter() - started
    receipt = {
        "deterministic_payload": payload,
        "deterministic_payload_sha256": digest,
        "environment_advisory_excluded_from_digest": environment_advisory(elapsed),
        "no_wall_clock": "No wall-clock timestamp is asserted; only deterministic inputs and outputs are graded.",
    }
    require_equal(tuple(receipt), OUTER_RECEIPT_KEYS, "outer receipt key order")
    require_equal(
        tuple(receipt["environment_advisory_excluded_from_digest"]),
        ADVISORY_KEYS,
        "advisory key order",
    )
    return receipt


def atomic_write(path: Path, data: bytes) -> None:
    if not path.parent.is_dir():
        raise ContractError(f"receipt parent directory does not exist: {path.parent}")
    temporary = path.with_name(path.name + ".tmp")
    try:
        temporary.write_bytes(data)
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def validate_stored_receipt_shape(receipt: dict) -> None:
    require_true(isinstance(receipt, dict), "stored receipt is not an object")
    require_equal(set(receipt), set(OUTER_RECEIPT_KEYS), "stored outer receipt keys")
    require_equal(len(receipt), len(OUTER_RECEIPT_KEYS), "stored outer receipt key count")
    payload = receipt.get("deterministic_payload")
    require_true(isinstance(payload, dict), "stored deterministic payload is not an object")
    require_equal(set(payload), set(PAYLOAD_TOP_LEVEL_KEYS), "stored payload keys")
    require_equal(len(payload), len(PAYLOAD_TOP_LEVEL_KEYS), "stored payload key count")
    validate_deterministic_types(payload)
    digest = sha256_bytes(canonical_json_bytes(payload))
    require_equal(receipt.get("deterministic_payload_sha256"), digest, "stored payload digest")
    advisory = receipt.get("environment_advisory_excluded_from_digest")
    require_true(isinstance(advisory, dict), "stored advisory object is absent")
    require_equal(set(advisory), set(ADVISORY_KEYS), "stored advisory keys")
    require_equal(len(advisory), len(ADVISORY_KEYS), "stored advisory key count")
    interpretation = payload.get("interpretation", {})
    require_equal(interpretation.get("harness_valid"), True, "stored harness validity")
    require_true(interpretation.get("verdict") in VALID_VERDICTS, "stored verdict is invalid")
    require_equal(interpretation.get("production_round_count"), None, "stored production round")


def print_summary(receipt: dict) -> None:
    payload = receipt["deterministic_payload"]
    coverage = payload["coverage"]
    results = payload["results"]
    interpretation = payload["interpretation"]
    print("=" * 78)
    print("E256-W WIDE-STATE STRUCTURAL GATE  (OPEN_PROGRESS)")
    print("=" * 78)
    print(f"harness valid: {interpretation['harness_valid']}")
    print(f"controls: {len(payload['controls']['records'])}/7 detected with exact paths")
    print(
        "coverage: "
        f"contexts={coverage['actual_counts']['contexts']} "
        f"roundtrips={coverage['actual_counts']['roundtrip_tests']} "
        f"rotor_pairs={coverage['actual_counts']['rotor_inverse_table_pairs']} "
        f"avalanche={coverage['actual_counts']['avalanche_comparisons']}"
    )
    print(
        "structure: "
        f"MDS_minors={results['diffusion']['mix_columns']['minor_count']} "
        f"all_to_all_round={results['diffusion']['earliest_all_to_all_round']} "
        f"active_rotors_4r={results['diffusion']['wide_trail']['four_round_active_rotor_lower_bound']}"
    )
    print(f"verdict: {interpretation['verdict']}")
    print("production round count: none")
    print(f"deterministic_payload_sha256: {receipt['deterministic_payload_sha256']}")
    print("production boundary: reviewed standard AEAD; AEAD-only remains baseline")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    try:
        receipt = build_receipt()
    except HarnessInvalid as error:
        print("E256-W GATE INVALID — refusing to write or accept canonical receipt", file=sys.stderr)
        print(json.dumps(error.diagnostic, indent=2, sort_keys=True), file=sys.stderr)
        return 1
    except Exception as error:
        print(f"E256-W GATE FAILED: {error}", file=sys.stderr)
        return 1

    print_summary(receipt)
    if args.check:
        if not RECEIPT.exists():
            print(f"CHECK FAILED: {RECEIPT.relative_to(REPO)} does not exist")
            return 1
        try:
            prior = strict_json_load(RECEIPT)
            validate_stored_receipt_shape(prior)
        except Exception as error:
            print(f"CHECK FAILED: invalid stored receipt: {error}")
            return 1
        same_digest = prior["deterministic_payload_sha256"] == receipt["deterministic_payload_sha256"]
        same_payload = canonical_json_bytes(prior["deterministic_payload"]) == canonical_json_bytes(receipt["deterministic_payload"])
        print(f"reproducibility: digest_match={same_digest} payload_match={same_payload}")
        print("CHECK PASS" if same_digest and same_payload else "CHECK FAIL")
        return 0 if same_digest and same_payload else 1

    atomic_write(
        RECEIPT,
        json.dumps(receipt, indent=2, sort_keys=True, allow_nan=False).encode("utf-8") + b"\n",
    )
    print(f"wrote {RECEIPT.relative_to(REPO)}")
    print("STATUS: OPEN_PROGRESS; no claim, suite, profile, fixture, release gate, or production round moved")
    return 0


if __name__ == "__main__":
    sys.exit(main())
