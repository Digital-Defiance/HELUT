#!/usr/bin/env python3
"""Deterministic E256-vNext rotor/schedule rejection campaign.

STATUS: OPEN_PROGRESS model and attack-harness research only. This runner does
not define or implement a cipher suite, does not modify v3, and does not move a
C/H/N row. It executes the frozen machine-readable preregistration at
`directives/e256-vnext-bakeoff-preregistration.json`.

Usage:
  python3 Scripts/e256_vnext_bakeoff.py
  python3 Scripts/e256_vnext_bakeoff.py --check
"""

from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import os
import platform
import re
import statistics
import subprocess
import sys
import time
from collections import Counter
from pathlib import Path
from typing import Dict, List, Sequence, Tuple

import numpy as np

REPO = Path(__file__).resolve().parent.parent
PREREG = REPO / "directives/e256-vnext-bakeoff-preregistration.json"
RECEIPT = REPO / "logs/e256-vnext-rotor-schedule-bakeoff.json"
ARCHITECTURE = REPO / "directives/e256-vnext-topology.md"
PREDECESSOR_RECEIPT = REPO / "logs/e256-vnext-topology-gate.json"
PREDECESSOR_HARNESS = REPO / "Scripts/e256_topology_experiment.py"

PREREG_SHA256 = "ebeb9e48d63ffb412b67ddbb20bce66086238b9afc26f8f56d0b0eea809b1fcd"
PREDECESSOR_RECEIPT_SHA256 = "8ec0b22c10f391c14461d81bcfd18d2df117e7442bba168e1d1bd09c6f19fe6a"
PREDECESSOR_HARNESS_SHA256 = "2fb7f25af28b3ccdd2117911daaee13e60fdb8c51aafd2d499f16cbff30735c3"
PREDECESSOR_RESULTS_SHA256 = "cc1ca362872c0a822270a3f8ad7b18525301aac54f7b3b59bf819aa6c10635fe"
AES_SBOX_SHA256 = "c2d8e5eed6cbebd8625fc18f81486a7733c04f9b0129ffbe974c68b90308b4f2"

PREREG_DATA = json.loads(PREREG.read_text(encoding="utf-8"))
IDENTITY = np.arange(256, dtype=np.uint8)
DEPTHS = tuple(int(value) for value in PREREG_DATA["active_depths_per_bank"])
FAMILY_RECORDS = tuple(PREREG_DATA["rotor_families"])
SCHEDULE_RECORDS = tuple(PREREG_DATA["schedule_arms"])
FAMILIES = tuple(item["id"] for item in FAMILY_RECORDS)
SCHEDULES = tuple(item["id"] for item in SCHEDULE_RECORDS)
CANDIDATE_SCHEDULES = tuple(item["id"] for item in SCHEDULE_RECORDS if item["candidate"])
CONTROL_SCHEDULES = tuple(item["id"] for item in SCHEDULE_RECORDS if not item["candidate"])
TRAIN_KEY_LABELS = tuple(int(value) for value in PREREG_DATA["corpus"]["train_key_labels"])
HOLDOUT_KEY_LABELS = tuple(
    int(value) for value in PREREG_DATA["corpus"]["disjoint_holdout_key_labels"]
)
KEY_LABELS = TRAIN_KEY_LABELS + HOLDOUT_KEY_LABELS
STREAM_IDS_PER_KEY = int(PREREG_DATA["corpus"]["stream_ids_per_key"])
DIRECTIONS = tuple(int(value) for value in PREREG_DATA["corpus"]["directions"])
REPLICATIONS = tuple(PREREG_DATA["corpus"]["replications"])
SEQUENCE = int(PREREG_DATA["corpus"]["sequence"])
COUNTERS = tuple(int(value) for value in PREREG_DATA["corpus"]["counters"])
ADJACENT_PAIRS = tuple(
    (int(pair[0]), int(pair[1])) for pair in PREREG_DATA["corpus"]["adjacent_pairs"]
)
RESET_CONTEXT_PAIRS = tuple(PREREG_DATA["corpus"]["reset_context_pairs"])
SPECTRUM_SUBSET = PREREG_DATA["corpus"]["exact_spectrum_subset"]
INTRINSIC_ROTOR_IDS = tuple(
    int(value) for value in PREREG_DATA["corpus"]["intrinsic_rotor_spectrum_ids"]
)
KEY_BIT_FLIP_INDICES = tuple(
    int(value) for value in PREREG_DATA["corpus"]["key_bit_flip_indices"]
)
ACCEPTED_CONSTRAINT_IDS = tuple(
    PREREG_DATA["authorization"]["accepted_research_constraints"]
)
ACCEPTED_CONSTRAINT_DEFINITIONS = dict(
    PREREG_DATA["authorization"]["accepted_constraint_definitions"]
)
PLANTED_CONTROL_IDS = tuple(item["id"] for item in PREREG_DATA["planted_controls"])
IDEAL_CONTROL_IDS = tuple(item["id"] for item in PREREG_DATA["ideal_controls"])
QUESTION_IDS = tuple(item["id"] for item in PREREG_DATA["questions"])
BANK_NAMES = tuple(FAMILY_RECORDS[0]["banks"])
STACK_WIDTH = max(DEPTHS)
EXTRACT_KEY = b"E256-vNext/bakeoff/extract/v1"
CONTEXT_PREFIX = PREREG_DATA["experimental_kdf"]["canonical_context"]["prefix"].encode(
    "ascii"
)
ROTOR_BANK_DOMAINS = {
    "ingress": PREREG_DATA["experimental_kdf"]["subkeys"][0],
    "egress": PREREG_DATA["experimental_kdf"]["subkeys"][1],
}
CONTROL_DOMAIN = PREREG_DATA["experimental_kdf"]["subkeys"][-1]
SPECTRUM_KEY_LABELS = tuple(int(value) for value in SPECTRUM_SUBSET["key_labels"])
SPECTRUM_COUNTERS = tuple(int(value) for value in SPECTRUM_SUBSET["counters"])
SPECTRUM_SCHEDULES = tuple(SPECTRUM_SUBSET["schedule_arms"])
SPECTRUM_COUNTER_PAIRS = tuple(
    pair
    for pair in ADJACENT_PAIRS
    if pair[0] in SPECTRUM_COUNTERS and pair[1] in SPECTRUM_COUNTERS
)

CELL_SERIES_COUNT = (
    len(KEY_LABELS) * STREAM_IDS_PER_KEY * len(REPLICATIONS) * len(DIRECTIONS)
)
CELL_DIRECTION_BASE_COUNT = len(KEY_LABELS) * STREAM_IDS_PER_KEY * len(REPLICATIONS)
CELL_MAIN_MAP_COUNT = CELL_SERIES_COUNT * len(COUNTERS)
CELL_RESET_MAP_COUNT = CELL_SERIES_COUNT * len(RESET_CONTEXT_PAIRS) * 2
MAIN_CONTEXT_COUNT = (
    len(KEY_LABELS)
    * len(FAMILIES)
    * len(SCHEDULES)
    * STREAM_IDS_PER_KEY
    * len(REPLICATIONS)
    * len(DIRECTIONS)
    * len(COUNTERS)
)
MAIN_MAP_COUNT = MAIN_CONTEXT_COUNT * len(DEPTHS)
RESET_COMPARISON_COUNT = (
    len(KEY_LABELS)
    * len(FAMILIES)
    * len(SCHEDULES)
    * STREAM_IDS_PER_KEY
    * len(REPLICATIONS)
    * len(DIRECTIONS)
    * len(RESET_CONTEXT_PAIRS)
    * len(DEPTHS)
)
RESET_MAP_COUNT = RESET_COMPARISON_COUNT * 2

OPERATIONAL_KEYS = (
    "schema",
    "status",
    "authorization",
    "predecessor",
    "questions",
    "non_claims",
    "experimental_kdf",
    "rotor_families",
    "schedule_arms",
    "active_depths_per_bank",
    "depth_pairing",
    "corpus",
    "ideal_controls",
    "baseline_execution_contract",
    "planted_controls",
    "control_execution_contract",
    "metrics",
    "hard_rejection_rules",
    "depth_selection_rule",
    "family_retention_rule",
    "receipt_contract",
)


# ---------------------------------------------------------------------------
# Deterministic bytes, exact sampling, and canonical encodings


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def canonical_json_bytes(value) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")


def field(value: bytes) -> bytes:
    if len(value) > 65535:
        raise ValueError("canonical field exceeds u16 length")
    return len(value).to_bytes(2, "big") + value


def context_bytes(
    corpus: str,
    family: str,
    schedule: str,
    stream_id: bytes,
    direction: int,
    sequence: int,
    counter: int,
) -> bytes:
    if direction not in DIRECTIONS or not 0 <= direction <= 255:
        raise ValueError("direction is outside the frozen u8 domain")
    if not 0 <= sequence < (1 << 64) or not 0 <= counter < (1 << 64):
        raise ValueError("sequence/counter is outside the frozen u64 domain")
    return (
        CONTEXT_PREFIX
        + field(corpus.encode("utf-8"))
        + field(family.encode("utf-8"))
        + field(schedule.encode("utf-8"))
        + field(stream_id)
        + bytes([direction])
        + sequence.to_bytes(8, "big")
        + counter.to_bytes(8, "big")
    )


def message_context_bytes(
    corpus: str,
    family: str,
    schedule: str,
    stream_id: bytes,
    direction: int,
    sequence: int,
) -> bytes:
    if direction not in DIRECTIONS or not 0 <= direction <= 255:
        raise ValueError("direction is outside the frozen u8 domain")
    if not 0 <= sequence < (1 << 64):
        raise ValueError("sequence is outside the frozen u64 domain")
    return (
        CONTEXT_PREFIX
        + b"/message"
        + field(corpus.encode("utf-8"))
        + field(family.encode("utf-8"))
        + field(schedule.encode("utf-8"))
        + field(stream_id)
        + bytes([direction])
        + sequence.to_bytes(8, "big")
    )


class PurposeStream:
    def __init__(self, key: bytes, domain: bytes) -> None:
        self.key = key
        self.domain = domain
        self.counter = 0
        self.buffer = b""
        self.offset = 0

    def byte(self) -> int:
        if self.offset == len(self.buffer):
            if self.counter == (1 << 64) - 1:
                raise OverflowError("purpose stream exhausted")
            message = self.domain + b"\x00" + self.counter.to_bytes(8, "big")
            self.buffer = hmac.new(self.key, message, hashlib.sha512).digest()
            self.counter += 1
            self.offset = 0
        value = self.buffer[self.offset]
        self.offset += 1
        return value

    def read(self, count: int) -> bytes:
        return bytes(self.byte() for _ in range(count))

    def u16be(self) -> int:
        return (self.byte() << 8) | self.byte()

    def bounded(self, upper: int) -> int:
        if not 1 <= upper <= 65536:
            raise ValueError("bounded sampler upper outside 1...65536")
        limit = 65536 - (65536 % upper)
        while True:
            value = self.u16be()
            if value < limit:
                return value % upper


def fisher_yates(count: int, stream: PurposeStream) -> np.ndarray:
    items = list(range(count))
    for index in range(count - 1, 0, -1):
        other = stream.bounded(index + 1)
        items[index], items[other] = items[other], items[index]
    return np.array(items, dtype=np.uint8)


def invert(perm: np.ndarray) -> np.ndarray:
    if perm.shape != (256,) or len(np.unique(perm)) != 256:
        raise ValueError("not a 256-point permutation")
    result = np.empty(256, dtype=np.uint8)
    result[perm] = IDENTITY
    return result


def compose(left: np.ndarray, right: np.ndarray) -> np.ndarray:
    """Return left o right."""
    return left[right]


def extract_prk(ikm: bytes) -> bytes:
    return hmac.new(EXTRACT_KEY, ikm, hashlib.sha512).digest()


def subkey(prk: bytes, domain: str) -> bytes:
    return hmac.new(
        prk, b"subkey\x00" + domain.encode("ascii"), hashlib.sha512
    ).digest()


def test_ikm(label: int) -> bytes:
    if not 0 <= label <= 65535:
        raise ValueError("test key label is outside u16")
    material = b"E256-vNext/bakeoff/key/v1/" + label.to_bytes(2, "big")
    return hashlib.sha512(material).digest()[:32]


def stream_id_for(label: int, stream_index: int) -> bytes:
    if not 0 <= label <= 65535 or not 0 <= stream_index <= 255:
        raise ValueError("stream identifier component is outside its frozen width")
    material = (
        b"E256-vNext/bakeoff/stream/v1/"
        + label.to_bytes(2, "big")
        + bytes([stream_index])
    )
    return hashlib.sha256(material).digest()[:16]


def context_tag(
    corpus: str,
    key_label: int,
    stream_index: int,
    replication: str,
    direction: int,
    sequence: int,
    counter: int,
) -> Tuple[object, ...]:
    return (
        corpus,
        key_label,
        stream_index,
        replication,
        direction,
        sequence,
        counter,
    )


# ---------------------------------------------------------------------------
# AES S-box and affine-equivalent rotor family


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
    return ((value << amount) | (value >> (8 - amount))) & 0xFF


def build_aes_sbox() -> np.ndarray:
    out = []
    for value in range(256):
        inverse = 0 if value == 0 else gf_pow(value, 254)
        out.append(
            inverse
            ^ rol8(inverse, 1)
            ^ rol8(inverse, 2)
            ^ rol8(inverse, 3)
            ^ rol8(inverse, 4)
            ^ 0x63
        )
    table = np.array(out, dtype=np.uint8)
    if sha256_bytes(table.tobytes()) != AES_SBOX_SHA256:
        raise AssertionError("AES S-box derivation/hash mismatch")
    return table


AES_SBOX = build_aes_sbox()


def popcount(value: int) -> int:
    """Python 3.9-compatible population count for one-byte values."""
    return bin(value & 0xFF).count("1")


PARITY = np.array([popcount(i) & 1 for i in range(256)], dtype=np.uint8)
POPCOUNT = np.array([popcount(i) for i in range(256)], dtype=np.uint8)


def gf2_rank(rows: Sequence[int]) -> int:
    work = [int(row) for row in rows]
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


def derive_matrix(key: bytes, label: bytes) -> Tuple[int, ...]:
    for attempt in range(65536):
        stream = PurposeStream(key, label + b"/attempt/" + attempt.to_bytes(2, "big"))
        rows = tuple(stream.byte() for _ in range(8))
        if gf2_rank(rows) == 8:
            return rows
    raise AssertionError("could not derive invertible matrix")


def apply_linear(rows: Sequence[int], value: int) -> int:
    output = 0
    for bit, row in enumerate(rows):
        output |= ((popcount(int(row & value)) & 1) << bit)
    return output


class RotorBank:
    def __init__(self, prk: bytes, family: str, bank: str) -> None:
        self.family = family
        self.bank = bank
        domain = ROTOR_BANK_DOMAINS.get(bank)
        if domain is None:
            raise ValueError("bank is outside the frozen ingress/egress set")
        self.key = subkey(prk, domain)
        self.cache: Dict[int, Tuple[np.ndarray, np.ndarray]] = {}

    def rotor(self, logical_id: int) -> Tuple[np.ndarray, np.ndarray]:
        if logical_id not in self.cache:
            label = (
                f"E256-vNext/bakeoff/{self.family}/{self.bank}/{logical_id:03d}"
            ).encode("ascii")
            if self.family == "random_fisher_yates_v1":
                forward = fisher_yates(256, PurposeStream(self.key, label + b"/fy"))
            elif self.family == "aes_affine_v1":
                matrix_in = derive_matrix(self.key, label + b"/matrix/in")
                matrix_out = derive_matrix(self.key, label + b"/matrix/out")
                constants = PurposeStream(self.key, label + b"/constants").read(2)
                c_in, c_out = constants[0], constants[1]
                forward = np.array(
                    [
                        apply_linear(
                            matrix_out,
                            int(AES_SBOX[apply_linear(matrix_in, x) ^ c_in]),
                        )
                        ^ c_out
                        for x in range(256)
                    ],
                    dtype=np.uint8,
                )
            else:
                raise ValueError("unknown frozen rotor family")
            reverse = invert(forward)
            if not np.array_equal(reverse[forward], IDENTITY):
                raise AssertionError("rotor inverse mismatch")
            self.cache[logical_id] = (forward, reverse)
        return self.cache[logical_id]


class FixedRotorBank:
    """Injected all-ID alias used only by the duplicate-bank positive control."""

    def __init__(self, forward: np.ndarray) -> None:
        self.forward = forward.copy()
        self.reverse = invert(self.forward)

    def rotor(self, _logical_id: int) -> Tuple[np.ndarray, np.ndarray]:
        return self.forward, self.reverse


class InjectedRotorBank:
    """Control-only bank with isolated per-ID overrides and unique fallbacks."""

    def __init__(
        self,
        key: bytes,
        label: bytes,
        overrides: Dict[int, np.ndarray],
    ) -> None:
        self.key = key
        self.label = label
        self.overrides = {
            int(logical_id): forward.copy()
            for logical_id, forward in overrides.items()
        }
        self.cache: Dict[int, Tuple[np.ndarray, np.ndarray]] = {}

    def rotor(self, logical_id: int) -> Tuple[np.ndarray, np.ndarray]:
        if logical_id not in self.cache:
            if logical_id in self.overrides:
                forward = self.overrides[logical_id].copy()
            else:
                forward = fisher_yates(
                    256,
                    PurposeStream(
                        self.key,
                        self.label + b"/id/" + logical_id.to_bytes(2, "big"),
                    ),
                )
            self.cache[logical_id] = (forward, invert(forward))
        return self.cache[logical_id]


# ---------------------------------------------------------------------------
# Candidate state derivation and byte maps


def select_ids(key: bytes, domain: bytes) -> Tuple[int, ...]:
    return tuple(
        int(value)
        for value in fisher_yates(256, PurposeStream(key, domain))[:STACK_WIDTH]
    )


def derive_mask(
    prk: bytes,
    family: str,
    schedule: str,
    corpus: str,
    stream_id: bytes,
    direction: int,
    sequence: int,
    counter: int,
    replication: str,
) -> int:
    full_context = context_bytes(
        corpus, family, schedule, stream_id, direction, sequence, counter
    )
    replica = b"/replication/" + replication.encode("ascii")
    return PurposeStream(
        subkey(prk, "mask"), b"mask" + replica + full_context
    ).byte()


def derive_state_material(
    prk: bytes,
    family: str,
    schedule: str,
    corpus: str,
    stream_id: bytes,
    direction: int,
    sequence: int,
    counter: int,
    replication: str,
) -> dict:
    full_context = context_bytes(
        corpus, family, schedule, stream_id, direction, sequence, counter
    )
    message_context = message_context_bytes(
        corpus, family, schedule, stream_id, direction, sequence
    )
    schedule_key = subkey(prk, "schedule")
    replica = b"/replication/" + replication.encode("ascii")

    if schedule == "full_counter_reselect_v1":
        selection_context = full_context
        wrapper_context = full_context
    elif schedule == "message_stack_counter_wrappers_v1":
        selection_context = message_context
        wrapper_context = full_context
    elif schedule == "common_endpoint_mask_only_control":
        selection_context = message_context
        wrapper_context = message_context
    else:
        raise ValueError("unknown frozen schedule")

    ingress_ids = select_ids(
        schedule_key, b"schedule/ingress/ids" + replica + selection_context
    )
    egress_ids = select_ids(
        schedule_key, b"schedule/egress/ids" + replica + selection_context
    )
    ingress_wrappers = PurposeStream(
        schedule_key, b"schedule/ingress/wrappers" + replica + wrapper_context
    ).read(2 * STACK_WIDTH)
    egress_wrappers = PurposeStream(
        schedule_key, b"schedule/egress/wrappers" + replica + wrapper_context
    ).read(2 * STACK_WIDTH)

    return {
        "ingress_ids": ingress_ids,
        "egress_ids": egress_ids,
        "ingress_wrappers": tuple(
            (ingress_wrappers[2 * index], ingress_wrappers[2 * index + 1])
            for index in range(STACK_WIDTH)
        ),
        "egress_wrappers": tuple(
            (egress_wrappers[2 * index], egress_wrappers[2 * index + 1])
            for index in range(STACK_WIDTH)
        ),
        "mask": derive_mask(
            prk,
            family,
            schedule,
            corpus,
            stream_id,
            direction,
            sequence,
            counter,
            replication,
        ),
    }


def extend_stack(
    current: np.ndarray,
    bank,
    logical_id: int,
    wrapper: Tuple[int, int],
) -> np.ndarray:
    pre, post = wrapper
    rotor = bank.rotor(logical_id)[0]
    return np.bitwise_xor(rotor[np.bitwise_xor(current, pre)], post)


def literal_stack(
    value: int,
    bank,
    ids: Sequence[int],
    wrappers: Sequence[Tuple[int, int]],
    depth: int,
) -> int:
    out = value
    for index in range(depth):
        pre, post = wrappers[index]
        out = int(bank.rotor(ids[index])[0][out ^ pre]) ^ post
    return out


def build_depth_maps(ingress_bank, egress_bank, material: dict) -> Dict[int, dict]:
    ingress = IDENTITY.copy()
    egress = IDENTITY.copy()
    output = {}
    for index in range(STACK_WIDTH):
        ingress = extend_stack(
            ingress,
            ingress_bank,
            material["ingress_ids"][index],
            material["ingress_wrappers"][index],
        )
        egress = extend_stack(
            egress,
            egress_bank,
            material["egress_ids"][index],
            material["egress_wrappers"][index],
        )
        depth = index + 1
        if depth not in DEPTHS:
            continue
        full = egress[np.bitwise_xor(ingress, material["mask"])]
        ingress_inverse = invert(ingress)
        egress_inverse = invert(egress)
        decrypted = ingress_inverse[
            np.bitwise_xor(egress_inverse[full], material["mask"])
        ]
        if not np.array_equal(decrypted, IDENTITY):
            raise AssertionError("candidate round-trip mismatch")
        probes = (0, 1, 17, 127, 255)
        if any(
            literal_stack(
                value,
                ingress_bank,
                material["ingress_ids"],
                material["ingress_wrappers"],
                depth,
            )
            != int(ingress[value])
            for value in probes
        ):
            raise AssertionError("literal/collapsed ingress mismatch")
        if any(
            literal_stack(
                value,
                egress_bank,
                material["egress_ids"],
                material["egress_wrappers"],
                depth,
            )
            != int(egress[value])
            for value in probes
        ):
            raise AssertionError("literal/collapsed egress mismatch")
        output[depth] = {
            "A": ingress.copy(),
            "A_inv": ingress_inverse,
            "B": egress.copy(),
            "B_inv": egress_inverse,
            "F": full,
        }
    if tuple(sorted(output)) != tuple(sorted(DEPTHS)):
        raise AssertionError("not every frozen depth was built")
    return output


def effective_state_bytes(material: dict, maps: dict, depth: int) -> bytes:
    """Serialize only the active depth, never an inactive derived suffix."""
    if depth not in DEPTHS:
        raise ValueError("effective state depth is not frozen")
    raw = bytearray(b"E256-vNext/effective-state/v2")
    raw.extend(depth.to_bytes(2, "big"))
    raw.extend(bytes(material["ingress_ids"][:depth]))
    raw.extend(bytes(material["egress_ids"][:depth]))
    for wrapper in material["ingress_wrappers"][:depth]:
        raw.extend(wrapper)
    for wrapper in material["egress_wrappers"][:depth]:
        raw.extend(wrapper)
    raw.append(int(material["mask"]))
    raw.extend(maps["A"].tobytes())
    raw.extend(maps["B"].tobytes())
    return bytes(raw)


def full_derivation_transcript_bytes(material: dict, maps_by_depth: dict) -> bytes:
    """Serialize the complete frozen derivation for key-bit sensitivity checks."""
    raw = bytearray(b"E256-vNext/full-derivation-transcript/v1")
    raw.extend(bytes(material["ingress_ids"]))
    raw.extend(bytes(material["egress_ids"]))
    for wrapper in material["ingress_wrappers"]:
        raw.extend(wrapper)
    for wrapper in material["egress_wrappers"]:
        raw.extend(wrapper)
    raw.append(int(material["mask"]))
    for depth in DEPTHS:
        raw.extend(depth.to_bytes(2, "big"))
        for name in ("A", "B", "F"):
            raw.extend(maps_by_depth[depth][name].tobytes())
    return bytes(raw)


def synthetic_maps(ingress: np.ndarray, egress: np.ndarray, mask: int) -> dict:
    full = egress[np.bitwise_xor(ingress, mask & 0xFF)]
    return {
        "A": ingress.copy(),
        "A_inv": invert(ingress),
        "B": egress.copy(),
        "B_inv": invert(egress),
        "F": full,
    }


# ---------------------------------------------------------------------------
# Exact diagnostics on 256-point maps


def cycle_stats(perm: np.ndarray) -> dict:
    seen = np.zeros(256, dtype=bool)
    lengths = []
    for start in range(256):
        if seen[start]:
            continue
        cursor = start
        length = 0
        while not seen[cursor]:
            seen[cursor] = True
            cursor = int(perm[cursor])
            length += 1
        lengths.append(length)
    histogram = Counter(lengths)
    return {
        "fixed_points": histogram.get(1, 0),
        "two_cycles": histogram.get(2, 0),
        "max_cycle": max(lengths),
        "cycle_count": len(lengths),
        "cycle_histogram": ",".join(
            f"{length}:{histogram[length]}" for length in sorted(histogram)
        ),
        "is_involution": bool(np.array_equal(perm[perm], IDENTITY)),
    }


def is_affine(perm: np.ndarray) -> bool:
    base = int(perm[0])
    deltas = [int(perm[1 << bit]) ^ base for bit in range(8)]
    for value in range(256):
        predicted = base
        for bit in range(8):
            if (value >> bit) & 1:
                predicted ^= deltas[bit]
        if predicted != int(perm[value]):
            return False
    return True


def anf_degree(perm: np.ndarray) -> int:
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
            maximum = max(maximum, max(int(POPCOUNT[index]) for index in active))
    return maximum


def ddt_diagnostics(perm: np.ndarray) -> dict:
    matrix = np.zeros((256, 256), dtype=np.uint16)
    for difference in range(256):
        outputs = np.bitwise_xor(perm, perm[np.bitwise_xor(IDENTITY, difference)])
        matrix[difference] = np.bincount(outputs, minlength=256)
    maximum = int(matrix[1:].max())
    return {
        "differential_uniformity": maximum,
        "spectrum_sha256": sha256_bytes(matrix.astype("<u2").tobytes()),
    }


def fwht(values: np.ndarray) -> np.ndarray:
    result = values.astype(np.int16, copy=True)
    span = 1
    while span < 256:
        shaped = result.reshape(-1, span * 2)
        left = shaped[:, :span].copy()
        right = shaped[:, span:].copy()
        shaped[:, :span] = left + right
        shaped[:, span:] = left - right
        span *= 2
    return result


def lat_diagnostics(perm: np.ndarray) -> dict:
    matrix = np.zeros((256, 256), dtype=np.int16)
    for output_mask in range(256):
        signs = 1 - 2 * PARITY[np.bitwise_and(perm, output_mask)].astype(np.int16)
        matrix[:, output_mask] = fwht(signs)
    nontrivial = np.abs(matrix[1:, 1:])
    return {
        "maximum_absolute_coefficient": int(nontrivial.max()),
        "spectrum_sha256": sha256_bytes(matrix.astype("<i2").tobytes()),
    }


def full_spectrum_record(perm: np.ndarray) -> dict:
    inverse = invert(perm)
    cycle = cycle_stats(perm)
    return {
        "map_sha256": sha256_bytes(perm.tobytes()),
        "fixed_points": cycle["fixed_points"],
        "two_cycles": cycle["two_cycles"],
        "max_cycle": cycle["max_cycle"],
        "cycle_histogram": cycle["cycle_histogram"],
        "is_involution": cycle["is_involution"],
        "is_affine": is_affine(perm),
        "anf_degree": anf_degree(perm),
        "inverse_anf_degree": anf_degree(inverse),
        "ddt": ddt_diagnostics(perm),
        "lat": lat_diagnostics(perm),
    }


def cross_ddt_maximum(first: np.ndarray, second: np.ndarray) -> int:
    maximum = 0
    for difference in range(256):
        outputs = np.bitwise_xor(first, second[np.bitwise_xor(IDENTITY, difference)])
        maximum = max(maximum, int(np.bincount(outputs, minlength=256).max()))
    return maximum


def related_record(first: np.ndarray, second: np.ndarray) -> dict:
    second_inverse = invert(second)
    first_inverse = invert(first)
    relative = compose(first, second_inverse)
    reverse_relative = compose(first_inverse, second)
    cycle = cycle_stats(relative)
    reverse_cycle = cycle_stats(reverse_relative)
    xor_map = np.bitwise_xor(first, second)
    xor_counts = np.bincount(xor_map, minlength=256)
    return {
        "agreement": int(np.sum(first == second)),
        "relative_fixed_points": cycle["fixed_points"],
        "relative_two_cycles": cycle["two_cycles"],
        "relative_max_cycle": cycle["max_cycle"],
        "relative_is_involution": cycle["is_involution"],
        "reverse_relative_is_involution": reverse_cycle["is_involution"],
        "exact_128_transposition_signature": bool(
            cycle["is_involution"]
            and cycle["fixed_points"] == 0
            and cycle["two_cycles"] == 128
            and reverse_cycle["is_involution"]
        ),
        "xor_image_size": int(np.count_nonzero(xor_counts)),
        "xor_maximum_preimage": int(xor_counts.max()),
    }


def commutator(first: np.ndarray, second: np.ndarray) -> np.ndarray:
    first_inverse = invert(first)
    second_inverse = invert(second)
    return first_inverse[second_inverse[first[second]]]


def summary(values: Sequence[int]) -> dict:
    if not values:
        return {
            "count": 0,
            "minimum": None,
            "median": None,
            "maximum": None,
            "mean": None,
        }
    return {
        "count": len(values),
        "minimum": int(min(values)),
        "median": float(statistics.median(values)),
        "maximum": int(max(values)),
        "mean": round(float(statistics.mean(values)), 6),
    }


def derive_random_permutation(key: bytes, label: bytes) -> np.ndarray:
    return fisher_yates(256, PurposeStream(key, label))


def rotor_bank_digest_record(bank, logical_ids: Sequence[int]) -> dict:
    records = []
    for logical_id in logical_ids:
        digest = sha256_bytes(bank.rotor(int(logical_id))[0].tobytes())
        records.append({"logical_id": int(logical_id), "map_sha256": digest})
    unique = len({record["map_sha256"] for record in records})
    return {
        "logical_ids": [int(value) for value in logical_ids],
        "tables": len(records),
        "unique_table_digests": unique,
        "duplicate_table_digests": len(records) - unique,
        "manifest_sha256": sha256_bytes(canonical_json_bytes(records)),
    }


# ---------------------------------------------------------------------------
# Shared state observation, related-map, domain, and rejection paths


def empty_cell() -> dict:
    return {
        "states": 0,
        "state_digest_first": {},
        "map_digest_first": {},
        "state_collisions": 0,
        "map_collisions": 0,
        "identity_maps": 0,
        "affine_maps": 0,
        "involution_maps": 0,
        "constructed_identity_maps": 0,
        "constructed_affine_maps": 0,
        "constructed_involution_maps": 0,
        "constructed_related_signatures": 0,
        "fixed_points": [],
        "max_cycles": [],
        "related_pairs": 0,
        "relative_signatures": 0,
        "relative_involutions": 0,
        "agreements": [],
        "xor_image_sizes": [],
        "xor_max_preimages": [],
        "id_overlaps": [],
        "unequal_mask_related_pairs": 0,
        "unequal_mask_relative_signatures": 0,
        "equal_mask_related_pairs": 0,
        "equal_mask_map_collisions": 0,
        "commutator_tests": 0,
        "identity_commutators": 0,
        "commutator_fixed_points": [],
        "domain_pairs": Counter(),
        "domain_state_collisions": Counter(),
        "domain_map_collisions": Counter(),
        "coverage": {
            "adjacent": Counter(),
            "reset": Counter(),
            "direction": Counter(),
        },
        "reset_observations": 0,
        "duplicate_rotor_banks": 0,
    }


def make_state_observation(material: dict, maps: dict, depth: int) -> dict:
    full = maps["F"]
    cycle = cycle_stats(full)
    return {
        "depth": depth,
        "state_digest": sha256_bytes(effective_state_bytes(material, maps, depth)),
        "map_digest": sha256_bytes(full.tobytes()),
        "map": full,
        "mask": int(material["mask"]),
        "identity": bool(np.array_equal(full, IDENTITY)),
        "affine": bool(is_affine(full)),
        "involution": bool(cycle["is_involution"]),
        "fixed_points": int(cycle["fixed_points"]),
        "max_cycle": int(cycle["max_cycle"]),
    }


def observe_state(cell: dict, observation: dict, tag: Tuple[object, ...]) -> None:
    cell["states"] += 1
    state_digest = observation["state_digest"]
    map_digest = observation["map_digest"]
    if state_digest in cell["state_digest_first"]:
        if cell["state_digest_first"][state_digest] != tag:
            cell["state_collisions"] += 1
    else:
        cell["state_digest_first"][state_digest] = tag
    if map_digest in cell["map_digest_first"]:
        if cell["map_digest_first"][map_digest] != tag:
            cell["map_collisions"] += 1
    else:
        cell["map_digest_first"][map_digest] = tag
    cell["identity_maps"] += int(observation["identity"])
    cell["affine_maps"] += int(observation["affine"])
    cell["involution_maps"] += int(observation["involution"])
    cell["fixed_points"].append(observation["fixed_points"])
    cell["max_cycles"].append(observation["max_cycle"])


def domain_collision_record(first: dict, second: dict) -> dict:
    return {
        "state_collision": first["state_digest"] == second["state_digest"],
        "map_collision": first["map_digest"] == second["map_digest"],
    }


def record_domain_pair(cell: dict, kind: str, record: dict) -> None:
    cell["domain_pairs"][kind] += 1
    cell["domain_state_collisions"][kind] += int(record["state_collision"])
    cell["domain_map_collisions"][kind] += int(record["map_collision"])


def observe_related_maps(
    cell: dict,
    first: dict,
    second: dict,
    total_id_overlap: int,
) -> dict:
    related = related_record(first["map"], second["map"])
    cell["related_pairs"] += 1
    cell["relative_signatures"] += int(related["exact_128_transposition_signature"])
    cell["relative_involutions"] += int(related["relative_is_involution"])
    cell["agreements"].append(related["agreement"])
    cell["xor_image_sizes"].append(related["xor_image_size"])
    cell["xor_max_preimages"].append(related["xor_maximum_preimage"])
    cell["id_overlaps"].append(int(total_id_overlap))
    if first["mask"] == second["mask"]:
        cell["equal_mask_related_pairs"] += 1
        cell["equal_mask_map_collisions"] += int(
            first["map_digest"] == second["map_digest"]
        )
    else:
        cell["unequal_mask_related_pairs"] += 1
        cell["unequal_mask_relative_signatures"] += int(
            related["exact_128_transposition_signature"]
        )
    return related


def observe_commutator(cell: dict, first: dict, second: dict) -> None:
    value = commutator(first["map"], second["map"])
    cell["commutator_tests"] += 1
    cell["identity_commutators"] += int(np.array_equal(value, IDENTITY))
    cell["commutator_fixed_points"].append(int(np.sum(value == IDENTITY)))


def adjacent_label(pair: Tuple[int, int]) -> str:
    return f"{SEQUENCE}:{pair[0]}->{SEQUENCE}:{pair[1]}"


def reset_label(pair: dict) -> str:
    before = pair["before"]
    after = pair["after"]
    return (
        f"{before['sequence']}:{before['counter']}"
        f"->{after['sequence']}:{after['counter']}"
    )


def direction_label(counter: int) -> str:
    return f"{SEQUENCE}:{counter}"


def coverage_record_for_cell(cell: dict) -> dict:
    expected_adjacent = {
        adjacent_label(pair): CELL_SERIES_COUNT for pair in ADJACENT_PAIRS
    }
    expected_reset = {
        reset_label(pair): CELL_SERIES_COUNT for pair in RESET_CONTEXT_PAIRS
    }
    expected_direction = {
        direction_label(counter): CELL_DIRECTION_BASE_COUNT for counter in COUNTERS
    }
    actual_adjacent = dict(sorted(cell["coverage"]["adjacent"].items()))
    actual_reset = dict(sorted(cell["coverage"]["reset"].items()))
    actual_direction = dict(sorted(cell["coverage"]["direction"].items()))
    checks = {
        "main_maps": cell["states"] == CELL_MAIN_MAP_COUNT,
        "adjacent_pairs": actual_adjacent == expected_adjacent,
        "direction_pairs": actual_direction == expected_direction,
        "reset_pairs": actual_reset == expected_reset,
        "reset_endpoint_maps": cell["reset_observations"] == CELL_RESET_MAP_COUNT,
    }
    return {
        "pass": all(checks.values()),
        "checks": checks,
        "missing_or_mismatched": sorted(
            name for name, passed in checks.items() if not passed
        ),
        "main_maps": {"actual": cell["states"], "expected": CELL_MAIN_MAP_COUNT},
        "adjacent_pair_counts": actual_adjacent,
        "adjacent_pair_expected": expected_adjacent,
        "direction_pair_counts": actual_direction,
        "direction_pair_expected": expected_direction,
        "reset_pair_counts": actual_reset,
        "reset_pair_expected": expected_reset,
        "reset_endpoint_maps": {
            "actual": cell["reset_observations"],
            "expected": CELL_RESET_MAP_COUNT,
        },
    }


def summarize_cell(cell: dict, depth: int, coverage: dict = None) -> dict:
    if coverage is None:
        coverage = {"pass": True, "missing_or_mismatched": []}
    return {
        "states": cell["states"],
        "unique_state_digests": len(cell["state_digest_first"]),
        "state_collisions": cell["state_collisions"],
        "unique_map_digests": len(cell["map_digest_first"]),
        "map_collisions": cell["map_collisions"],
        "identity_maps": cell["identity_maps"],
        "affine_maps": cell["affine_maps"],
        "involution_maps": cell["involution_maps"],
        "constructed_identity_maps": cell["constructed_identity_maps"],
        "constructed_affine_maps": cell["constructed_affine_maps"],
        "constructed_involution_maps": cell["constructed_involution_maps"],
        "constructed_related_signatures": cell["constructed_related_signatures"],
        "fixed_points": summary(cell["fixed_points"]),
        "max_cycle": summary(cell["max_cycles"]),
        "related_pairs": cell["related_pairs"],
        "relative_128_transposition_signatures": cell["relative_signatures"],
        "relative_involutions": cell["relative_involutions"],
        "agreement": summary(cell["agreements"]),
        "xor_image_size": summary(cell["xor_image_sizes"]),
        "xor_maximum_preimage": summary(cell["xor_max_preimages"]),
        "adjacent_total_id_overlap": summary(cell["id_overlaps"]),
        "unequal_mask_related_pairs": cell["unequal_mask_related_pairs"],
        "unequal_mask_relative_128_transposition_signatures": cell[
            "unequal_mask_relative_signatures"
        ],
        "equal_mask_related_pairs": cell["equal_mask_related_pairs"],
        "equal_mask_map_collisions": cell["equal_mask_map_collisions"],
        "commutator_tests": cell["commutator_tests"],
        "identity_commutators": cell["identity_commutators"],
        "commutator_fixed_points": summary(cell["commutator_fixed_points"]),
        "domain_pairs": dict(sorted(cell["domain_pairs"].items())),
        "domain_state_collisions": dict(
            sorted(cell["domain_state_collisions"].items())
        ),
        "domain_map_collisions": dict(
            sorted(cell["domain_map_collisions"].items())
        ),
        "duplicate_rotor_banks": cell["duplicate_rotor_banks"],
        "coverage": coverage,
        "deterministic_rotor_evaluations_per_byte": 2 * depth,
    }


def candidate_rejection_reasons(
    cell: dict,
    schedule: str,
    key_flip_collisions: int = 0,
    require_coverage: bool = True,
) -> List[str]:
    reasons = []
    if cell["state_collisions"]:
        reasons.append("complete_state_collision")
    if cell["map_collisions"]:
        reasons.append("complete_map_collision")

    # The frozen rule distinguishes a planted/structural construction from an
    # isolated chance diagnostic. Candidate cells therefore reject only an
    # explicit injected construction or a property shared by every tested map.
    structural_identity = bool(
        cell["constructed_identity_maps"]
        or (cell["states"] > 1 and cell["identity_maps"] == cell["states"])
    )
    structural_affine = bool(
        cell["constructed_affine_maps"]
        or (cell["states"] > 1 and cell["affine_maps"] == cell["states"])
    )
    structural_involution = bool(
        cell["constructed_involution_maps"]
        or (cell["states"] > 1 and cell["involution_maps"] == cell["states"])
    )
    if structural_identity:
        reasons.append("identity_state_map")
    if structural_affine:
        reasons.append("affine_state_map")
    if structural_involution:
        reasons.append("involution_state_map")

    # A repeated common-endpoint quotient is a hard rule only for the frozen
    # full-counter candidate. The noncandidate control arm and injected control
    # deliberately calibrate the same detector with one or more signatures.
    repeated_candidate_signature = bool(
        schedule == "full_counter_reselect_v1"
        and cell["relative_128_transposition_signatures"] >= 2
    )
    planted_control_signature = bool(
        schedule in CONTROL_SCHEDULES
        and (
            cell["constructed_related_signatures"]
            or cell["relative_128_transposition_signatures"]
        )
    )
    if repeated_candidate_signature or planted_control_signature:
        reasons.append("related_128_transposition_signature")

    # Commutator identity remains a reported exact diagnostic; no frozen hard
    # rejection rule promotes it by itself.
    if cell["duplicate_rotor_banks"]:
        reasons.append("duplicate_rotor_bank")
    for kind in ("adjacent", "reset", "direction"):
        if cell["domain_state_collisions"].get(kind, 0):
            reasons.append(f"{kind}_state_collision")
        if cell["domain_map_collisions"].get(kind, 0):
            reasons.append(f"{kind}_map_collision")
    if key_flip_collisions:
        reasons.append("key_bit_flip_collision")
    if require_coverage and not cell["coverage"]["pass"]:
        reasons.append("missing_required_coverage")
    if schedule not in SCHEDULES:
        reasons.append("unknown_schedule")
    return sorted(set(reasons))


# ---------------------------------------------------------------------------
# Main candidate campaign


def cell_key(family: str, schedule: str, depth: int) -> str:
    return f"{family}|{schedule}|{depth}+{depth}"


def parse_cell_key(value: str) -> Tuple[str, str, int]:
    family, schedule, depth_pair = value.split("|")
    first, second = depth_pair.split("+")
    if first != second:
        raise ValueError("asymmetric depth is outside the frozen campaign")
    return family, schedule, int(first)


def is_spectrum_state(
    key_label: int,
    stream_index: int,
    direction: int,
    counter: int,
    schedule: str,
) -> bool:
    return (
        key_label in SPECTRUM_KEY_LABELS
        and stream_index == int(SPECTRUM_SUBSET["stream_index"])
        and direction == int(SPECTRUM_SUBSET["direction"])
        and counter in SPECTRUM_COUNTERS
        and schedule in SPECTRUM_SCHEDULES
    )


def corpus_name(key_label: int) -> str:
    if key_label in TRAIN_KEY_LABELS:
        return "train"
    if key_label in HOLDOUT_KEY_LABELS:
        return "disjoint_holdout"
    raise ValueError("key label is outside the frozen corpus")


def run_intrinsic_rotor_diagnostics() -> List[dict]:
    records = []
    for key_label in SPECTRUM_KEY_LABELS:
        prk = extract_prk(test_ikm(key_label))
        for family in FAMILIES:
            for bank_name in BANK_NAMES:
                bank = RotorBank(prk, family, bank_name)
                for logical_id in INTRINSIC_ROTOR_IDS:
                    forward = bank.rotor(logical_id)[0]
                    record = full_spectrum_record(forward)
                    record.update(
                        {
                            "corpus": corpus_name(key_label),
                            "key_label": key_label,
                            "family": family,
                            "bank": bank_name,
                            "logical_id": logical_id,
                        }
                    )
                    records.append(record)
    return records


def run_candidates() -> dict:
    cells = {
        cell_key(family, schedule, depth): empty_cell()
        for family in FAMILIES
        for schedule in SCHEDULES
        for depth in DEPTHS
    }
    spectrum_records = []
    cross_spectrum_records = []
    bank_digest_records = []
    family_duplicate_banks = Counter()
    deterministic_manifest = hashlib.sha256()

    for key_label in KEY_LABELS:
        corpus = corpus_name(key_label)
        prk = extract_prk(test_ikm(key_label))
        for family in FAMILIES:
            ingress_bank = RotorBank(prk, family, "ingress")
            egress_bank = RotorBank(prk, family, "egress")
            for bank_name, bank in (
                ("ingress", ingress_bank),
                ("egress", egress_bank),
            ):
                bank_record = rotor_bank_digest_record(bank, INTRINSIC_ROTOR_IDS)
                bank_record.update(
                    {
                        "corpus": corpus,
                        "key_label": key_label,
                        "family": family,
                        "bank": bank_name,
                    }
                )
                bank_digest_records.append(bank_record)
                if bank_record["duplicate_table_digests"]:
                    family_duplicate_banks[family] += 1

            for schedule in SCHEDULES:
                for stream_index in range(STREAM_IDS_PER_KEY):
                    stream_id = stream_id_for(key_label, stream_index)
                    for replication in REPLICATIONS:
                        direction_series = {}
                        for direction in DIRECTIONS:
                            series = {depth: {} for depth in DEPTHS}
                            materials = {}
                            for counter in COUNTERS:
                                material = derive_state_material(
                                    prk,
                                    family,
                                    schedule,
                                    corpus,
                                    stream_id,
                                    direction,
                                    SEQUENCE,
                                    counter,
                                    replication,
                                )
                                maps_by_depth = build_depth_maps(
                                    ingress_bank, egress_bank, material
                                )
                                materials[counter] = material
                                tag = context_tag(
                                    corpus,
                                    key_label,
                                    stream_index,
                                    replication,
                                    direction,
                                    SEQUENCE,
                                    counter,
                                )
                                for depth in DEPTHS:
                                    key = cell_key(family, schedule, depth)
                                    cell = cells[key]
                                    observation = make_state_observation(
                                        material, maps_by_depth[depth], depth
                                    )
                                    observe_state(cell, observation, tag)
                                    series[depth][counter] = observation
                                    deterministic_manifest.update(
                                        canonical_json_bytes(
                                            {
                                                "kind": "main",
                                                "cell": key,
                                                "context": tag,
                                                "state": observation["state_digest"],
                                                "map": observation["map_digest"],
                                            }
                                        )
                                    )

                                    if is_spectrum_state(
                                        key_label,
                                        stream_index,
                                        direction,
                                        counter,
                                        schedule,
                                    ):
                                        record = full_spectrum_record(
                                            observation["map"]
                                        )
                                        record.update(
                                            {
                                                "corpus": corpus,
                                                "key_label": key_label,
                                                "family": family,
                                                "schedule": schedule,
                                                "replication": replication,
                                                "sequence": SEQUENCE,
                                                "counter": counter,
                                                "depth": f"{depth}+{depth}",
                                            }
                                        )
                                        spectrum_records.append(record)

                            for depth in DEPTHS:
                                key = cell_key(family, schedule, depth)
                                cell = cells[key]
                                for pair in ADJACENT_PAIRS:
                                    first_counter, second_counter = pair
                                    if (
                                        first_counter not in series[depth]
                                        or second_counter not in series[depth]
                                    ):
                                        raise AssertionError(
                                            "frozen adjacent pair lacks a main-corpus endpoint"
                                        )
                                    first = series[depth][first_counter]
                                    second = series[depth][second_counter]
                                    collision = domain_collision_record(first, second)
                                    record_domain_pair(cell, "adjacent", collision)
                                    cell["coverage"]["adjacent"][adjacent_label(pair)] += 1
                                    overlap_in = len(
                                        set(materials[first_counter]["ingress_ids"][:depth])
                                        & set(
                                            materials[second_counter]["ingress_ids"][:depth]
                                        )
                                    )
                                    overlap_out = len(
                                        set(materials[first_counter]["egress_ids"][:depth])
                                        & set(
                                            materials[second_counter]["egress_ids"][:depth]
                                        )
                                    )
                                    related = observe_related_maps(
                                        cell,
                                        first,
                                        second,
                                        overlap_in + overlap_out,
                                    )

                                    if (
                                        key_label in SPECTRUM_KEY_LABELS
                                        and stream_index
                                        == int(SPECTRUM_SUBSET["stream_index"])
                                        and direction
                                        == int(SPECTRUM_SUBSET["direction"])
                                        and schedule in SPECTRUM_SCHEDULES
                                        and pair in SPECTRUM_COUNTER_PAIRS
                                    ):
                                        cross_spectrum_records.append(
                                            {
                                                "corpus": corpus,
                                                "key_label": key_label,
                                                "family": family,
                                                "schedule": schedule,
                                                "replication": replication,
                                                "depth": f"{depth}+{depth}",
                                                "sequence": SEQUENCE,
                                                "counters": list(pair),
                                                "cross_ddt_maximum": cross_ddt_maximum(
                                                    first["map"], second["map"]
                                                ),
                                                "related": related,
                                            }
                                        )

                                if all(
                                    counter in series[depth]
                                    for counter in COUNTERS[:3]
                                ):
                                    first = series[depth][COUNTERS[0]]
                                    second = series[depth][COUNTERS[1]]
                                    third = series[depth][COUNTERS[2]]
                                    observe_commutator(cell, first, second)
                                    observe_commutator(cell, second, third)

                            for pair in RESET_CONTEXT_PAIRS:
                                endpoint_observations = []
                                for endpoint_name in ("before", "after"):
                                    endpoint = pair[endpoint_name]
                                    reset_sequence = int(endpoint["sequence"])
                                    reset_counter = int(endpoint["counter"])
                                    material = derive_state_material(
                                        prk,
                                        family,
                                        schedule,
                                        corpus,
                                        stream_id,
                                        direction,
                                        reset_sequence,
                                        reset_counter,
                                        replication,
                                    )
                                    maps_by_depth = build_depth_maps(
                                        ingress_bank, egress_bank, material
                                    )
                                    tag = context_tag(
                                        corpus,
                                        key_label,
                                        stream_index,
                                        replication,
                                        direction,
                                        reset_sequence,
                                        reset_counter,
                                    )
                                    by_depth = {}
                                    for depth in DEPTHS:
                                        key = cell_key(family, schedule, depth)
                                        observation = make_state_observation(
                                            material, maps_by_depth[depth], depth
                                        )
                                        by_depth[depth] = observation
                                        cells[key]["reset_observations"] += 1
                                        deterministic_manifest.update(
                                            canonical_json_bytes(
                                                {
                                                    "kind": "reset_endpoint",
                                                    "endpoint": endpoint_name,
                                                    "cell": key,
                                                    "context": tag,
                                                    "state": observation[
                                                        "state_digest"
                                                    ],
                                                    "map": observation["map_digest"],
                                                }
                                            )
                                        )
                                    endpoint_observations.append(by_depth)
                                for depth in DEPTHS:
                                    key = cell_key(family, schedule, depth)
                                    cell = cells[key]
                                    collision = domain_collision_record(
                                        endpoint_observations[0][depth],
                                        endpoint_observations[1][depth],
                                    )
                                    record_domain_pair(cell, "reset", collision)
                                    cell["coverage"]["reset"][reset_label(pair)] += 1

                            direction_series[direction] = series

                        first_direction, second_direction = DIRECTIONS
                        for depth in DEPTHS:
                            key = cell_key(family, schedule, depth)
                            cell = cells[key]
                            for counter in COUNTERS:
                                first = direction_series[first_direction][depth][counter]
                                second = direction_series[second_direction][depth][counter]
                                collision = domain_collision_record(first, second)
                                record_domain_pair(cell, "direction", collision)
                                cell["coverage"]["direction"][
                                    direction_label(counter)
                                ] += 1

    for family in FAMILIES:
        if family_duplicate_banks[family]:
            for schedule in SCHEDULES:
                for depth in DEPTHS:
                    cells[cell_key(family, schedule, depth)][
                        "duplicate_rotor_banks"
                    ] = family_duplicate_banks[family]

    summarized_cells = {}
    coverage_cells = {}
    for family in FAMILIES:
        for schedule in SCHEDULES:
            for depth in DEPTHS:
                key = cell_key(family, schedule, depth)
                coverage = coverage_record_for_cell(cells[key])
                coverage_cells[key] = coverage
                summarized_cells[key] = summarize_cell(cells[key], depth, coverage)

    aggregate_coverage = {
        "main_maps": sum(cell["states"] for cell in cells.values()),
        "expected_main_maps": MAIN_MAP_COUNT,
        "ordinary_counters": len(COUNTERS),
        "reset_endpoint_maps": sum(
            cell["reset_observations"] for cell in cells.values()
        ),
        "expected_reset_endpoint_maps": RESET_MAP_COUNT,
        "reset_comparisons": sum(
            cell["domain_pairs"]["reset"] for cell in cells.values()
        ),
        "expected_reset_comparisons": RESET_COMPARISON_COUNT,
        "adjacent_comparisons": sum(
            cell["domain_pairs"]["adjacent"] for cell in cells.values()
        ),
        "direction_comparisons": sum(
            cell["domain_pairs"]["direction"] for cell in cells.values()
        ),
        "cell_coverage_pass": all(record["pass"] for record in coverage_cells.values()),
    }
    aggregate_coverage["pass"] = bool(
        aggregate_coverage["cell_coverage_pass"]
        and aggregate_coverage["main_maps"] == MAIN_MAP_COUNT
        and aggregate_coverage["reset_endpoint_maps"] == RESET_MAP_COUNT
        and aggregate_coverage["reset_comparisons"] == RESET_COMPARISON_COUNT
    )

    common_cells = {
        key: summarized_cells[key]
        for family in FAMILIES
        for schedule in CONTROL_SCHEDULES
        for depth in DEPTHS
        for key in (cell_key(family, schedule, depth),)
    }
    common_checks = {}
    for key, cell in common_cells.items():
        checks = {
            "coverage": cell["coverage"]["pass"],
            "has_unequal_masks": cell["unequal_mask_related_pairs"] > 0,
            "every_unequal_mask_pair_has_signature": (
                cell["unequal_mask_relative_128_transposition_signatures"]
                == cell["unequal_mask_related_pairs"]
            ),
            "every_equal_mask_pair_collides": (
                cell["equal_mask_map_collisions"]
                == cell["equal_mask_related_pairs"]
            ),
        }
        common_checks[key] = {"pass": all(checks.values()), "checks": checks}
    common_endpoint_execution = {
        "cells": common_checks,
        "pass": bool(common_checks)
        and all(record["pass"] for record in common_checks.values()),
    }

    return {
        "cells": summarized_cells,
        "coverage": {
            "aggregate": aggregate_coverage,
            "cells": coverage_cells,
            "pass": aggregate_coverage["pass"],
        },
        "common_endpoint_control_execution": common_endpoint_execution,
        "candidate_manifest_sha256": deterministic_manifest.hexdigest(),
        "rotor_bank_digest_records": bank_digest_records,
        "rotor_bank_digest_records_sha256": sha256_bytes(
            canonical_json_bytes(bank_digest_records)
        ),
        "state_spectrum_records": spectrum_records,
        "state_spectrum_records_sha256": sha256_bytes(
            canonical_json_bytes(spectrum_records)
        ),
        "cross_spectrum_records": cross_spectrum_records,
        "cross_spectrum_records_sha256": sha256_bytes(
            canonical_json_bytes(cross_spectrum_records)
        ),
    }


# ---------------------------------------------------------------------------
# Key-flip checks, end-to-end controls, and declared baselines


def derivation_transcript_for_ikm(
    ikm: bytes,
    family: str,
    schedule: str,
    use_control_domain: bool = False,
) -> str:
    prk = extract_prk(ikm)
    if use_control_domain:
        prk = subkey(prk, CONTROL_DOMAIN)
    key_label = TRAIN_KEY_LABELS[0]
    stream_id = stream_id_for(key_label, int(SPECTRUM_SUBSET["stream_index"]))
    material = derive_state_material(
        prk,
        family,
        schedule,
        corpus_name(key_label),
        stream_id,
        DIRECTIONS[0],
        SEQUENCE,
        COUNTERS[0],
        REPLICATIONS[0],
    )
    maps_by_depth = build_depth_maps(
        RotorBank(prk, family, "ingress"),
        RotorBank(prk, family, "egress"),
        material,
    )
    return sha256_bytes(full_derivation_transcript_bytes(material, maps_by_depth))


def key_flip_pair_record(
    family: str,
    schedule: str,
    base_ikm: bytes,
    bit_index: int,
    transform=None,
    use_control_domain: bool = False,
) -> dict:
    changed = bytearray(base_ikm)
    byte_index = bit_index // 8
    changed[byte_index] ^= 1 << (bit_index % 8)
    first = base_ikm if transform is None else transform(base_ikm)
    second_bytes = bytes(changed)
    second = second_bytes if transform is None else transform(second_bytes)
    first_digest = derivation_transcript_for_ikm(
        first, family, schedule, use_control_domain
    )
    second_digest = derivation_transcript_for_ikm(
        second, family, schedule, use_control_domain
    )
    return {
        "family": family,
        "schedule": schedule,
        "bit_index": bit_index,
        "first_transcript_sha256": first_digest,
        "second_transcript_sha256": second_digest,
        "collision": first_digest == second_digest,
    }


def key_flip_collision_check() -> dict:
    records = []
    collisions_by_arm = Counter()
    base_ikm = test_ikm(TRAIN_KEY_LABELS[0])
    expected_cases = tuple(
        (family, schedule, bit_index)
        for family in FAMILIES
        for schedule in CANDIDATE_SCHEDULES
        for bit_index in KEY_BIT_FLIP_INDICES
    )
    for family, schedule, bit_index in expected_cases:
        record = key_flip_pair_record(family, schedule, base_ikm, bit_index)
        records.append(record)
        if record["collision"]:
            collisions_by_arm[f"{family}|{schedule}"] += 1
    executed_cases = tuple(
        (record["family"], record["schedule"], record["bit_index"])
        for record in records
    )
    coverage_exact = executed_cases == expected_cases
    collisions = [record for record in records if record["collision"]]
    return {
        "tests": len(records),
        "expected_tests": len(expected_cases),
        "expected_cases": [list(case) for case in expected_cases],
        "executed_cases": [list(case) for case in executed_cases],
        "coverage_exact": coverage_exact,
        "records_sha256": sha256_bytes(canonical_json_bytes(records)),
        "collisions": collisions,
        "collisions_by_arm": dict(sorted(collisions_by_arm.items())),
        "pass": bool(coverage_exact and len(records) == len(expected_cases) and not collisions),
    }


def control_record(expected: Sequence[str], actual: Sequence[str], details: dict) -> dict:
    expected_values = sorted(expected)
    actual_values = sorted(actual)
    return {
        "expected_rejection_outcomes": expected_values,
        "actual_rejection_outcomes": actual_values,
        "detected": actual_values == expected_values,
        **details,
    }


def run_controls(candidate_results: dict, key_flips: dict) -> dict:
    control_root = subkey(
        extract_prk(test_ikm(TRAIN_KEY_LABELS[0])), CONTROL_DOMAIN
    )
    family = FAMILIES[0]
    schedule = CANDIDATE_SCHEDULES[0]
    depth = DEPTHS[0]
    corpus = corpus_name(TRAIN_KEY_LABELS[0])
    stream_id = stream_id_for(
        TRAIN_KEY_LABELS[0], int(SPECTRUM_SUBSET["stream_index"])
    )
    controls = {}

    def frozen_control_material(schedule_name: str, counter: int = COUNTERS[0]) -> dict:
        return derive_state_material(
            control_root,
            family,
            schedule_name,
            corpus,
            stream_id,
            DIRECTIONS[0],
            SEQUENCE,
            counter,
            REPLICATIONS[0],
        )

    def isolated_bank_record(ingress_bank, egress_bank) -> dict:
        ingress_record = rotor_bank_digest_record(ingress_bank, tuple(range(256)))
        egress_record = rotor_bank_digest_record(egress_bank, tuple(range(256)))
        return {
            "ingress": ingress_record,
            "egress": egress_record,
            "pass": bool(
                ingress_record["duplicate_table_digests"] == 0
                and egress_record["duplicate_table_digests"] == 0
            ),
        }

    mirrored_cell = empty_cell()
    mirrored_a = derive_random_permutation(control_root, b"mirrored/A")
    mirrored_material = frozen_control_material(schedule)
    mirrored_material["mask"] = 0x5A
    mirrored_material["ingress_wrappers"] = tuple(
        (0, 0) for _ in range(STACK_WIDTH)
    )
    mirrored_material["egress_wrappers"] = tuple(
        (0, 0) for _ in range(STACK_WIDTH)
    )
    mirrored_ingress = InjectedRotorBank(
        control_root,
        b"control/mirrored/ingress",
        {mirrored_material["ingress_ids"][0]: mirrored_a},
    )
    mirrored_egress = InjectedRotorBank(
        control_root,
        b"control/mirrored/egress",
        {mirrored_material["egress_ids"][0]: invert(mirrored_a)},
    )
    mirrored_maps_by_depth = build_depth_maps(
        mirrored_ingress, mirrored_egress, mirrored_material
    )
    mirrored_observation = make_state_observation(
        mirrored_material, mirrored_maps_by_depth[depth], depth
    )
    observe_state(mirrored_cell, mirrored_observation, ("control", "mirrored", 0))
    mirrored_cycle = cycle_stats(mirrored_observation["map"])
    mirrored_banks = isolated_bank_record(mirrored_ingress, mirrored_egress)
    mirrored_predicate = bool(
        mirrored_material["mask"] != 0
        and mirrored_observation["involution"]
        and mirrored_cycle["fixed_points"] == 0
        and mirrored_cycle["two_cycles"] == 128
    )
    mirrored_cell["constructed_involution_maps"] = int(mirrored_predicate)
    mirrored_summary = summarize_cell(mirrored_cell, depth)
    mirrored_reasons = candidate_rejection_reasons(
        mirrored_summary, schedule, require_coverage=False
    )
    if not mirrored_banks["pass"]:
        mirrored_reasons = list(mirrored_reasons) + [
            "unintended_duplicate_rotor_bank"
        ]
    controls["mirrored_endpoints"] = control_record(
        ["involution_state_map"],
        mirrored_reasons,
        {
            "involution": mirrored_observation["involution"],
            "two_cycles": mirrored_cycle["two_cycles"],
            "measured_predicate": mirrored_predicate,
            "isolated_banks": mirrored_banks,
            "shared_path": "isolated injected banks -> build_depth_maps -> measured predicate -> state observation -> cell summary -> candidate rejection",
        },
    )

    identity_cell = empty_cell()
    identity_material = frozen_control_material(schedule)
    identity_material["mask"] = 0
    identity_material["ingress_wrappers"] = tuple(
        (0, 0) for _ in range(STACK_WIDTH)
    )
    identity_material["egress_wrappers"] = tuple(
        (0, 0) for _ in range(STACK_WIDTH)
    )
    identity_ingress = InjectedRotorBank(
        control_root,
        b"control/identity/ingress",
        {identity_material["ingress_ids"][0]: IDENTITY},
    )
    identity_egress = InjectedRotorBank(
        control_root,
        b"control/identity/egress",
        {identity_material["egress_ids"][0]: IDENTITY},
    )
    identity_maps_by_depth = build_depth_maps(
        identity_ingress, identity_egress, identity_material
    )
    identity_observation = make_state_observation(
        identity_material, identity_maps_by_depth[depth], depth
    )
    observe_state(identity_cell, identity_observation, ("control", "identity", 0))
    identity_banks = isolated_bank_record(identity_ingress, identity_egress)
    identity_cell["constructed_identity_maps"] = int(
        identity_observation["identity"]
    )
    identity_cell["constructed_affine_maps"] = int(identity_observation["affine"])
    identity_cell["constructed_involution_maps"] = int(
        identity_observation["involution"]
    )
    identity_summary = summarize_cell(identity_cell, depth)
    identity_reasons = candidate_rejection_reasons(
        identity_summary, schedule, require_coverage=False
    )
    identity_ddt = ddt_diagnostics(identity_observation["map"])
    identity_lat = lat_diagnostics(identity_observation["map"])
    if (
        identity_ddt["differential_uniformity"] != 256
        or identity_lat["maximum_absolute_coefficient"] != 256
    ):
        identity_reasons = list(identity_reasons) + ["identity_spectrum_mismatch"]
    if not identity_banks["pass"]:
        identity_reasons = list(identity_reasons) + [
            "unintended_duplicate_rotor_bank"
        ]
    controls["identity_affine"] = control_record(
        ["affine_state_map", "identity_state_map", "involution_state_map"],
        identity_reasons,
        {
            "ddt_maximum": identity_ddt["differential_uniformity"],
            "lat_maximum": identity_lat["maximum_absolute_coefficient"],
            "measured_identity": identity_observation["identity"],
            "measured_affine": identity_observation["affine"],
            "measured_involution": identity_observation["involution"],
            "isolated_banks": identity_banks,
            "shared_path": "isolated injected banks -> build_depth_maps -> measured predicates -> state observation -> cell summary -> candidate rejection",
        },
    )

    duplicate_cell = empty_cell()
    duplicate_ingress = FixedRotorBank(IDENTITY)
    duplicate_egress = FixedRotorBank(AES_SBOX)
    duplicate_material = frozen_control_material(schedule)
    duplicate_material["mask"] = 0
    duplicate_material["ingress_wrappers"] = tuple(
        (0, 0) for _ in range(STACK_WIDTH)
    )
    duplicate_material["egress_wrappers"] = tuple(
        (0, 0) for _ in range(STACK_WIDTH)
    )
    duplicate_maps = build_depth_maps(
        duplicate_ingress, duplicate_egress, duplicate_material
    )
    duplicate_observation = make_state_observation(
        duplicate_material, duplicate_maps[depth], depth
    )
    observe_state(duplicate_cell, duplicate_observation, ("control", "duplicate", 0))
    ingress_digest_record = rotor_bank_digest_record(
        duplicate_ingress, INTRINSIC_ROTOR_IDS
    )
    egress_digest_record = rotor_bank_digest_record(
        duplicate_egress, INTRINSIC_ROTOR_IDS
    )
    duplicate_cell["duplicate_rotor_banks"] = int(
        ingress_digest_record["unique_table_digests"] == 1
    ) + int(egress_digest_record["unique_table_digests"] == 1)
    duplicate_summary = summarize_cell(duplicate_cell, depth)
    duplicate_reasons = candidate_rejection_reasons(
        duplicate_summary, schedule, require_coverage=False
    )
    controls["duplicate_rotor_bank"] = control_record(
        ["duplicate_rotor_bank"],
        duplicate_reasons,
        {
            "ingress": ingress_digest_record,
            "egress": egress_digest_record,
            "shared_path": "rotor digest -> state observation -> cell summary -> candidate rejection",
        },
    )

    common_cell = empty_cell()
    common_a = derive_random_permutation(control_root, b"common/A")
    common_b = derive_random_permutation(control_root, b"common/B")
    common_base_material = frozen_control_material(CONTROL_SCHEDULES[0])
    common_base_material["ingress_wrappers"] = tuple(
        (0, 0) for _ in range(STACK_WIDTH)
    )
    common_base_material["egress_wrappers"] = tuple(
        (0, 0) for _ in range(STACK_WIDTH)
    )
    common_ingress = InjectedRotorBank(
        control_root,
        b"control/common/ingress",
        {common_base_material["ingress_ids"][0]: common_a},
    )
    common_egress = InjectedRotorBank(
        control_root,
        b"control/common/egress",
        {common_base_material["egress_ids"][0]: common_b},
    )
    common_observations = []
    common_materials = []
    for index, mask in enumerate((0x11, 0xA7)):
        material = dict(common_base_material)
        material["mask"] = mask
        maps_by_depth = build_depth_maps(common_ingress, common_egress, material)
        observation = make_state_observation(material, maps_by_depth[depth], depth)
        observe_state(common_cell, observation, ("control", "common", index))
        common_materials.append(material)
        common_observations.append(observation)
    common_related = observe_related_maps(
        common_cell, common_observations[0], common_observations[1], 0
    )
    common_material_fixed = all(
        common_materials[0][name] == common_materials[1][name]
        for name in (
            "ingress_ids",
            "egress_ids",
            "ingress_wrappers",
            "egress_wrappers",
        )
    )
    common_masks_differ = common_materials[0]["mask"] != common_materials[1]["mask"]
    common_banks = isolated_bank_record(common_ingress, common_egress)
    common_predicate = bool(
        common_material_fixed
        and common_masks_differ
        and common_related["exact_128_transposition_signature"]
    )
    common_cell["constructed_related_signatures"] = int(common_predicate)
    common_summary = summarize_cell(common_cell, depth)
    common_reasons = candidate_rejection_reasons(
        common_summary, CONTROL_SCHEDULES[0], require_coverage=False
    )
    if not common_material_fixed or not common_masks_differ:
        common_reasons = list(common_reasons) + [
            "common_endpoint_material_drift"
        ]
    if not common_banks["pass"]:
        common_reasons = list(common_reasons) + [
            "unintended_duplicate_rotor_bank"
        ]
    campaign_common_pass = candidate_results[
        "common_endpoint_control_execution"
    ]["pass"]
    if not campaign_common_pass:
        common_reasons = list(common_reasons) + [
            "campaign_common_endpoint_contract_failure"
        ]
    controls["common_endpoint_mask_only"] = control_record(
        ["related_128_transposition_signature"],
        common_reasons,
        {
            "relative_involution": common_related["relative_is_involution"],
            "two_cycles": common_related["relative_two_cycles"],
            "only_mask_varies": common_material_fixed and common_masks_differ,
            "measured_predicate": common_predicate,
            "isolated_banks": common_banks,
            "campaign_same_path_pass": campaign_common_pass,
            "shared_path": "isolated injected banks/fixed material -> build_depth_maps -> measured related-map predicate -> cell summary -> candidate rejection",
        },
    )

    truncated_cell = empty_cell()
    truncated_banks = (
        RotorBank(control_root, family, "ingress"),
        RotorBank(control_root, family, "egress"),
    )
    truncated_observations = []
    for original_counter in (0, 256):
        material = derive_state_material(
            control_root,
            family,
            schedule,
            corpus,
            stream_id,
            DIRECTIONS[0],
            SEQUENCE,
            original_counter & 0xFF,
            REPLICATIONS[0],
        )
        maps = build_depth_maps(*truncated_banks, material)[depth]
        observation = make_state_observation(material, maps, depth)
        observe_state(
            truncated_cell,
            observation,
            ("control", "truncated", SEQUENCE, original_counter),
        )
        truncated_observations.append(observation)
    truncated_collision = domain_collision_record(
        truncated_observations[0], truncated_observations[1]
    )
    record_domain_pair(truncated_cell, "adjacent", truncated_collision)
    observe_related_maps(
        truncated_cell, truncated_observations[0], truncated_observations[1], 0
    )
    truncated_summary = summarize_cell(truncated_cell, depth)
    truncated_reasons = candidate_rejection_reasons(
        truncated_summary, schedule, require_coverage=False
    )
    controls["truncated_counter_8"] = control_record(
        [
            "adjacent_map_collision",
            "adjacent_state_collision",
            "complete_map_collision",
            "complete_state_collision",
        ],
        truncated_reasons,
        {
            "counter_0_equals_256": bool(
                truncated_collision["state_collision"]
                and truncated_collision["map_collision"]
            ),
            "shared_path": "normal derivation -> state observation -> domain collision -> candidate rejection",
        },
    )

    direction_cell = empty_cell()
    direction_banks = (
        RotorBank(control_root, family, "ingress"),
        RotorBank(control_root, family, "egress"),
    )
    direction_observations = []
    for tagged_direction in DIRECTIONS:
        material = derive_state_material(
            control_root,
            family,
            schedule,
            corpus,
            stream_id,
            DIRECTIONS[0],
            SEQUENCE,
            COUNTERS[0],
            REPLICATIONS[0],
        )
        maps = build_depth_maps(*direction_banks, material)[depth]
        observation = make_state_observation(material, maps, depth)
        observe_state(
            direction_cell,
            observation,
            ("control", "direction", tagged_direction),
        )
        direction_observations.append(observation)
    direction_collision = domain_collision_record(
        direction_observations[0], direction_observations[1]
    )
    record_domain_pair(direction_cell, "direction", direction_collision)
    direction_summary = summarize_cell(direction_cell, depth)
    direction_reasons = candidate_rejection_reasons(
        direction_summary, schedule, require_coverage=False
    )
    controls["direction_omitted"] = control_record(
        [
            "complete_map_collision",
            "complete_state_collision",
            "direction_map_collision",
            "direction_state_collision",
        ],
        direction_reasons,
        {
            "direction_0_equals_1": bool(
                direction_collision["state_collision"]
                and direction_collision["map_collision"]
            ),
            "shared_path": "normal derivation -> state observation -> domain collision -> candidate rejection",
        },
    )

    def clear_bit_255(value: bytes) -> bytes:
        changed = bytearray(value)
        changed[31] &= 0x7F
        return bytes(changed)

    ignored_record = key_flip_pair_record(
        family,
        schedule,
        test_ikm(TRAIN_KEY_LABELS[0]),
        255,
        transform=clear_bit_255,
        use_control_domain=True,
    )
    ignored_summary = summarize_cell(empty_cell(), depth)
    ignored_reasons = candidate_rejection_reasons(
        ignored_summary,
        schedule,
        key_flip_collisions=int(ignored_record["collision"]),
        require_coverage=False,
    )
    controls["ignored_key_bit"] = control_record(
        ["key_bit_flip_collision"],
        ignored_reasons,
        {
            "transcript_collision": ignored_record["collision"],
            "record": ignored_record,
            "shared_path": "full derivation transcript -> key-flip collision -> candidate rejection",
        },
    )

    multiplicities = Counter(value % 255 for value in range(65536))
    modulo_actual = (
        ["primitive_modulo_sampler_bias"]
        if len(set(multiplicities.values())) != 1
        else []
    )
    controls["modulo_sampler"] = control_record(
        ["primitive_modulo_sampler_bias"],
        modulo_actual,
        {
            "minimum_multiplicity": min(multiplicities.values()),
            "maximum_multiplicity": max(multiplicities.values()),
            "shared_path": "allowed primitive-level standalone exception",
        },
    )

    ideal_cell = empty_cell()
    ideal_manifest = hashlib.sha256()
    ideal_main_observations = 0
    ideal_reset_observations = 0
    ideal_main_context_tags = set()
    ideal_reset_context_tags = set()

    def ideal_observation(
        corpus_name_value: str,
        family_name: str,
        schedule_name: str,
        stream_id_value: bytes,
        direction_value: int,
        sequence_value: int,
        counter_value: int,
        replication_value: str,
    ) -> dict:
        canonical_context = context_bytes(
            corpus_name_value,
            family_name,
            schedule_name,
            stream_id_value,
            direction_value,
            sequence_value,
            counter_value,
        )
        domain = (
            b"ideal-independent-state"
            + field(replication_value.encode("ascii"))
            + canonical_context
        )
        ideal_map = derive_random_permutation(control_root, domain)
        material = derive_state_material(
            control_root,
            family_name,
            schedule_name,
            corpus_name_value,
            stream_id_value,
            direction_value,
            sequence_value,
            counter_value,
            replication_value,
        )
        maps = synthetic_maps(IDENTITY, ideal_map, int(material["mask"]))
        return make_state_observation(material, maps, depth)

    for ideal_key_label in KEY_LABELS:
        ideal_corpus = corpus_name(ideal_key_label)
        for ideal_family in FAMILIES:
            for ideal_schedule in SCHEDULES:
                for ideal_stream_index in range(STREAM_IDS_PER_KEY):
                    ideal_stream_id = stream_id_for(
                        ideal_key_label, ideal_stream_index
                    )
                    for ideal_replication in REPLICATIONS:
                        ideal_direction_series = {}
                        for ideal_direction in DIRECTIONS:
                            ideal_series = {}
                            for ideal_counter in COUNTERS:
                                observation = ideal_observation(
                                    ideal_corpus,
                                    ideal_family,
                                    ideal_schedule,
                                    ideal_stream_id,
                                    ideal_direction,
                                    SEQUENCE,
                                    ideal_counter,
                                    ideal_replication,
                                )
                                tag = (
                                    ideal_family,
                                    ideal_schedule,
                                ) + context_tag(
                                    ideal_corpus,
                                    ideal_key_label,
                                    ideal_stream_index,
                                    ideal_replication,
                                    ideal_direction,
                                    SEQUENCE,
                                    ideal_counter,
                                )
                                observe_state(ideal_cell, observation, tag)
                                ideal_main_context_tags.add(tag)
                                ideal_series[ideal_counter] = observation
                                ideal_manifest.update(
                                    canonical_json_bytes(
                                        {
                                            "kind": "main",
                                            "context": tag,
                                            "state": observation["state_digest"],
                                            "map": observation["map_digest"],
                                        }
                                    )
                                )
                                ideal_main_observations += 1

                            for pair in ADJACENT_PAIRS:
                                first = ideal_series[pair[0]]
                                second = ideal_series[pair[1]]
                                record_domain_pair(
                                    ideal_cell,
                                    "adjacent",
                                    domain_collision_record(first, second),
                                )
                                observe_related_maps(
                                    ideal_cell, first, second, 0
                                )
                            first = ideal_series[COUNTERS[0]]
                            second = ideal_series[COUNTERS[1]]
                            third = ideal_series[COUNTERS[2]]
                            observe_commutator(ideal_cell, first, second)
                            observe_commutator(ideal_cell, second, third)

                            for pair in RESET_CONTEXT_PAIRS:
                                reset_observations = []
                                for endpoint_name in ("before", "after"):
                                    endpoint = pair[endpoint_name]
                                    reset_sequence = int(endpoint["sequence"])
                                    reset_counter = int(endpoint["counter"])
                                    observation = ideal_observation(
                                        ideal_corpus,
                                        ideal_family,
                                        ideal_schedule,
                                        ideal_stream_id,
                                        ideal_direction,
                                        reset_sequence,
                                        reset_counter,
                                        ideal_replication,
                                    )
                                    tag = (
                                        ideal_family,
                                        ideal_schedule,
                                    ) + context_tag(
                                        ideal_corpus,
                                        ideal_key_label,
                                        ideal_stream_index,
                                        ideal_replication,
                                        ideal_direction,
                                        reset_sequence,
                                        reset_counter,
                                    )
                                    observe_state(ideal_cell, observation, tag)
                                    ideal_reset_context_tags.add(tag)
                                    reset_observations.append(observation)
                                    ideal_manifest.update(
                                        canonical_json_bytes(
                                            {
                                                "kind": "reset_endpoint",
                                                "endpoint": endpoint_name,
                                                "context": tag,
                                                "state": observation[
                                                    "state_digest"
                                                ],
                                                "map": observation["map_digest"],
                                            }
                                        )
                                    )
                                    ideal_reset_observations += 1
                                record_domain_pair(
                                    ideal_cell,
                                    "reset",
                                    domain_collision_record(
                                        reset_observations[0],
                                        reset_observations[1],
                                    ),
                                )
                            ideal_direction_series[ideal_direction] = ideal_series

                        first_direction, second_direction = DIRECTIONS
                        for ideal_counter in COUNTERS:
                            record_domain_pair(
                                ideal_cell,
                                "direction",
                                domain_collision_record(
                                    ideal_direction_series[first_direction][
                                        ideal_counter
                                    ],
                                    ideal_direction_series[second_direction][
                                        ideal_counter
                                    ],
                                ),
                            )

    expected_ideal_reset_observations = RESET_MAP_COUNT // len(DEPTHS)
    ideal_coverage = {
        "main_observations": ideal_main_observations,
        "expected_main_observations": MAIN_CONTEXT_COUNT,
        "unique_main_contexts": len(ideal_main_context_tags),
        "expected_unique_main_contexts": MAIN_CONTEXT_COUNT,
        "reset_endpoint_observations": ideal_reset_observations,
        "expected_reset_endpoint_observations": expected_ideal_reset_observations,
        "unique_reset_endpoint_contexts": len(ideal_reset_context_tags),
        "expected_unique_reset_endpoint_contexts": expected_ideal_reset_observations,
        "adjacent_comparisons": ideal_cell["domain_pairs"]["adjacent"],
        "expected_adjacent_comparisons": (
            (MAIN_CONTEXT_COUNT // len(COUNTERS)) * len(ADJACENT_PAIRS)
        ),
        "direction_comparisons": ideal_cell["domain_pairs"]["direction"],
        "expected_direction_comparisons": MAIN_CONTEXT_COUNT // len(DIRECTIONS),
        "reset_comparisons": ideal_cell["domain_pairs"]["reset"],
        "expected_reset_comparisons": expected_ideal_reset_observations // 2,
    }
    ideal_coverage["pass"] = all(
        ideal_coverage[actual_name] == ideal_coverage[expected_name]
        for actual_name, expected_name in (
            ("main_observations", "expected_main_observations"),
            ("unique_main_contexts", "expected_unique_main_contexts"),
            (
                "reset_endpoint_observations",
                "expected_reset_endpoint_observations",
            ),
            (
                "unique_reset_endpoint_contexts",
                "expected_unique_reset_endpoint_contexts",
            ),
            ("adjacent_comparisons", "expected_adjacent_comparisons"),
            ("direction_comparisons", "expected_direction_comparisons"),
            ("reset_comparisons", "expected_reset_comparisons"),
        )
    )
    ideal_summary = summarize_cell(ideal_cell, depth)
    ideal_reasons = candidate_rejection_reasons(
        ideal_summary, CANDIDATE_SCHEDULES[0], require_coverage=False
    )
    if not ideal_coverage["pass"]:
        ideal_reasons = list(ideal_reasons) + ["ideal_null_coverage_failure"]
    ideal_null = {
        "expected_rejection_outcomes": [],
        "actual_rejection_outcomes": sorted(ideal_reasons),
        "detected_no_false_positive": not ideal_reasons,
        "maps": ideal_cell["states"],
        "manifest_sha256": ideal_manifest.hexdigest(),
        "coverage": ideal_coverage,
        "shared_path": "frozen canonical contexts -> independent maps -> state/related/commutator/domain observation -> cell summary -> candidate rejection",
    }

    candidate_cells = [
        candidate_results["cells"][cell_key(family_name, schedule_name, depth_value)]
        for family_name in FAMILIES
        for schedule_name in CANDIDATE_SCHEDULES
        for depth_value in DEPTHS
    ]
    clean_domain_controls = {
        "coverage_complete": candidate_results["coverage"]["pass"],
        "adjacent_state_collisions": sum(
            cell["domain_state_collisions"].get("adjacent", 0)
            for cell in candidate_cells
        ),
        "adjacent_map_collisions": sum(
            cell["domain_map_collisions"].get("adjacent", 0)
            for cell in candidate_cells
        ),
        "reset_state_collisions": sum(
            cell["domain_state_collisions"].get("reset", 0)
            for cell in candidate_cells
        ),
        "reset_map_collisions": sum(
            cell["domain_map_collisions"].get("reset", 0)
            for cell in candidate_cells
        ),
        "direction_state_collisions": sum(
            cell["domain_state_collisions"].get("direction", 0)
            for cell in candidate_cells
        ),
        "direction_map_collisions": sum(
            cell["domain_map_collisions"].get("direction", 0)
            for cell in candidate_cells
        ),
        "key_flip_collisions": len(key_flips["collisions"]),
    }
    clean_domain_controls["pass"] = bool(
        clean_domain_controls["coverage_complete"]
        and not any(
            clean_domain_controls[name]
            for name in clean_domain_controls
            if name.endswith("collisions")
        )
        and key_flips["pass"]
    )

    executed_ids = tuple(controls)
    expected_ids_exact = executed_ids == PLANTED_CONTROL_IDS
    all_positive = expected_ids_exact and all(
        controls[control_id]["detected"] for control_id in PLANTED_CONTROL_IDS
    )
    null_pass = ideal_null["detected_no_false_positive"]
    return {
        "control_derivation": "subkey(extract_prk(frozen test IKM), 'controls')",
        "frozen_planted_control_ids": list(PLANTED_CONTROL_IDS),
        "executed_planted_control_ids": list(executed_ids),
        "control_ids_exact": expected_ids_exact,
        "controls": controls,
        "ideal_independent_state_null": ideal_null,
        "clean_domain_controls": clean_domain_controls,
        "all_planted_controls_detected": all_positive,
        "ideal_null_no_exact_false_positive": null_pass,
        "pass": bool(all_positive and null_pass and clean_domain_controls["pass"]),
    }


def run_baselines() -> dict:
    mask_manifest = hashlib.sha256()
    main_contexts = 0
    reset_endpoint_contexts = 0
    same_context_recovery_verified = True

    for key_label in KEY_LABELS:
        corpus = corpus_name(key_label)
        prk = extract_prk(test_ikm(key_label))
        for family in FAMILIES:
            for schedule in SCHEDULES:
                for stream_index in range(STREAM_IDS_PER_KEY):
                    stream_id = stream_id_for(key_label, stream_index)
                    for replication in REPLICATIONS:
                        for direction in DIRECTIONS:
                            for counter in COUNTERS:
                                mask = derive_mask(
                                    prk,
                                    family,
                                    schedule,
                                    corpus,
                                    stream_id,
                                    direction,
                                    SEQUENCE,
                                    counter,
                                    replication,
                                )
                                plaintext = 0xA5
                                ciphertext = plaintext ^ mask
                                same_context_recovery_verified = bool(
                                    same_context_recovery_verified
                                    and (plaintext ^ ciphertext) == mask
                                )
                                tag = context_tag(
                                    corpus,
                                    key_label,
                                    stream_index,
                                    replication,
                                    direction,
                                    SEQUENCE,
                                    counter,
                                )
                                mask_manifest.update(
                                    canonical_json_bytes(
                                        {
                                            "kind": "main",
                                            "family": family,
                                            "schedule": schedule,
                                            "context": tag,
                                            "mask": mask,
                                        }
                                    )
                                )
                                main_contexts += 1
                            for pair in RESET_CONTEXT_PAIRS:
                                for endpoint_name in ("before", "after"):
                                    endpoint = pair[endpoint_name]
                                    reset_sequence = int(endpoint["sequence"])
                                    reset_counter = int(endpoint["counter"])
                                    mask = derive_mask(
                                        prk,
                                        family,
                                        schedule,
                                        corpus,
                                        stream_id,
                                        direction,
                                        reset_sequence,
                                        reset_counter,
                                        replication,
                                    )
                                    plaintext = 0xA5
                                    ciphertext = plaintext ^ mask
                                    same_context_recovery_verified = bool(
                                        same_context_recovery_verified
                                        and (plaintext ^ ciphertext) == mask
                                    )
                                    tag = context_tag(
                                        corpus,
                                        key_label,
                                        stream_index,
                                        replication,
                                        direction,
                                        reset_sequence,
                                        reset_counter,
                                    )
                                    mask_manifest.update(
                                        canonical_json_bytes(
                                            {
                                                "kind": "reset_endpoint",
                                                "endpoint": endpoint_name,
                                                "family": family,
                                                "schedule": schedule,
                                                "context": tag,
                                                "mask": mask,
                                            }
                                        )
                                    )
                                    reset_endpoint_contexts += 1

    expected_reset_contexts = RESET_MAP_COUNT // len(DEPTHS)
    prf_mask_only = {
        "main_canonical_contexts": main_contexts,
        "expected_main_canonical_contexts": MAIN_CONTEXT_COUNT,
        "reset_endpoint_contexts": reset_endpoint_contexts,
        "expected_reset_endpoint_contexts": expected_reset_contexts,
        "mask_manifest_sha256": mask_manifest.hexdigest(),
        "same_context_recovery": {
            "known_or_chosen_plaintext_ciphertext_pairs": 1,
            "recovery_equation": "mask = plaintext XOR ciphertext",
            "verified_for_every_executed_context": same_context_recovery_verified,
            "scope": "repeated identical canonical state only",
        },
        "deterministic_inner_cost_per_byte": {
            "rotor_evaluations": 0,
            "mask_derivations": 1,
            "xor_operations": 1,
            "secret_table_lookups": 0,
        },
        "production_proposal": False,
    }
    aead_only = {
        "inner_transform": "none",
        "deterministic_inner_cost_per_byte": {
            "rotor_evaluations": 0,
            "mask_derivations": 0,
            "xor_operations": 0,
            "secret_table_lookups": 0,
        },
        "byte_map_diagnostics": "not_applicable",
        "repeated_state_codebook_queries": "not_applicable",
        "policy": "mandatory production complexity and security-boundary baseline",
        "simulated_aead_security_experiment": False,
    }
    records = {
        "prf_mask_only": prf_mask_only,
        "aead_only": aead_only,
    }
    passed = bool(
        main_contexts == MAIN_CONTEXT_COUNT
        and reset_endpoint_contexts == expected_reset_contexts
        and same_context_recovery_verified
        and tuple(records) == tuple(
            control_id
            for control_id in IDEAL_CONTROL_IDS
            if control_id != "ideal_independent_state"
        )
    )
    return {
        "records": records,
        "q4_comparison": {
            "frozen_rule": PREREG_DATA["baseline_execution_contract"]["comparison"],
            "production_retained_rotor": None,
            "result": "No rotor is production-retained absent later independent-key compromise evidence under common cost accounting.",
            "aead_only_remains_production_baseline": True,
        },
        "pass": passed,
    }


# ---------------------------------------------------------------------------
# Structured research-baseline ranking and candidate selection


def structured_cell_rank(value: str) -> Tuple[int, int, int, int, int]:
    family, schedule, depth = parse_cell_key(value)
    schedule_declaration_index = CANDIDATE_SCHEDULES.index(schedule)
    family_declaration_index = FAMILIES.index(family)
    schedule_priority = 0 if schedule == "full_counter_reselect_v1" else 1
    family_priority = 0 if family == "aes_affine_v1" else 1
    return (
        schedule_priority,
        family_priority,
        depth,
        schedule_declaration_index,
        family_declaration_index,
    )


def choose_research_baseline(eligible: Sequence[str]) -> str:
    if not eligible:
        return None
    return min(eligible, key=structured_cell_rank)


def run_rank_self_tests() -> dict:
    preferred = cell_key("aes_affine_v1", "full_counter_reselect_v1", DEPTHS[0])
    all_cells = [
        cell_key(family, schedule, depth)
        for family in FAMILIES
        for schedule in CANDIDATE_SCHEDULES
        for depth in DEPTHS
    ]
    tests = [
        {
            "id": "preferred_rejection",
            "eligible": [value for value in all_cells if value != preferred],
            "expected": cell_key(
                "aes_affine_v1", "full_counter_reselect_v1", DEPTHS[1]
            ),
        },
        {
            "id": "schedule_priority",
            "eligible": [
                cell_key(
                    "random_fisher_yates_v1",
                    "full_counter_reselect_v1",
                    DEPTHS[-1],
                ),
                cell_key(
                    "aes_affine_v1",
                    "message_stack_counter_wrappers_v1",
                    DEPTHS[0],
                ),
            ],
            "expected": cell_key(
                "random_fisher_yates_v1",
                "full_counter_reselect_v1",
                DEPTHS[-1],
            ),
        },
        {
            "id": "family_priority",
            "eligible": [
                cell_key(
                    "random_fisher_yates_v1",
                    "full_counter_reselect_v1",
                    DEPTHS[0],
                ),
                cell_key(
                    "aes_affine_v1",
                    "full_counter_reselect_v1",
                    DEPTHS[-1],
                ),
            ],
            "expected": cell_key(
                "aes_affine_v1", "full_counter_reselect_v1", DEPTHS[-1]
            ),
        },
        {
            "id": "numeric_depth_ordering",
            "eligible": [
                cell_key(
                    "aes_affine_v1", "full_counter_reselect_v1", DEPTHS[-1]
                ),
                cell_key(
                    "aes_affine_v1", "full_counter_reselect_v1", DEPTHS[1]
                ),
            ],
            "expected": cell_key(
                "aes_affine_v1", "full_counter_reselect_v1", DEPTHS[1]
            ),
        },
    ]
    for test in tests:
        test["actual"] = choose_research_baseline(test["eligible"])
        test["pass"] = test["actual"] == test["expected"]
    result = {"tests": tests, "pass": all(test["pass"] for test in tests)}
    if not result["pass"]:
        raise AssertionError("structured baseline ranking self-test failed")
    return result


def select(
    results: dict,
    key_flips: dict,
    interpretation_gate: dict,
) -> dict:
    if not interpretation_gate["pass"]:
        return {
            "verdict": "INVALID_CONTROLS",
            "eligible_cells": [],
            "rejected_cells": {},
            "security_selected_depth": None,
            "next_research_baseline": None,
            "baseline_scope": "none; interpretation gate failed closed",
            "production_result": "AEAD-only remains the production baseline; no byte-local rotor candidate is authorized for production.",
        }

    eligible = []
    rejections = {}
    for family in FAMILIES:
        for schedule in CANDIDATE_SCHEDULES:
            arm_key = f"{family}|{schedule}"
            key_flip_collisions = key_flips["collisions_by_arm"].get(arm_key, 0)
            for depth in DEPTHS:
                key = cell_key(family, schedule, depth)
                cell = results["cells"][key]
                reasons = candidate_rejection_reasons(
                    cell,
                    schedule,
                    key_flip_collisions=key_flip_collisions,
                    require_coverage=True,
                )
                if reasons:
                    rejections[key] = reasons
                else:
                    eligible.append(key)

    if not eligible:
        verdict = "ALL_CANDIDATES_REJECTED"
        baseline = None
    else:
        verdict = "NO_BYTE_LOCAL_PRODUCTION_CANDIDATE_RESEARCH_BASELINE_RETAINED"
        baseline = choose_research_baseline(eligible)

    required_factor = float(
        PREREG_DATA["depth_selection_rule"]["required_normalized_improvement_factor"]
    )
    depth_attack_table = {}
    for depth in DEPTHS:
        depth_attack_table[f"{depth}+{depth}"] = {
            "honest_rotor_evaluations_per_byte": 2 * depth,
            "two_query_involution_detector_queries": 2,
            "common_endpoint_quotient_detector_codebooks": 2,
            "repeated_state_complete_codebook_queries": 255,
            "normalized_improvement_over_1+1": 1.0 / depth,
            "required_normalized_improvement_factor": required_factor,
            "clears_required_factor": False,
        }

    return {
        "verdict": verdict,
        "eligible_cells": sorted(eligible, key=structured_cell_rank),
        "rejected_cells": rejections,
        "security_selected_depth": None,
        "depth_attack_table": depth_attack_table,
        "depth_rule_result": "No tested depth improves a bounded attack beyond linear honest cost; no depth is security-selected.",
        "next_research_baseline": baseline,
        "baseline_rank": list(structured_cell_rank(baseline)) if baseline else None,
        "baseline_scope": "next model/attack target only; not a suite, implementation, or security claim",
        "production_result": "AEAD-only remains the production baseline; no byte-local rotor candidate is authorized for production.",
    }


# ---------------------------------------------------------------------------
# Frozen-contract validation, receipt construction, checking, and output


def require_equal(actual, expected, label: str) -> None:
    if actual != expected:
        raise AssertionError(f"{label} mismatch: expected {expected!r}, got {actual!r}")


def operational_contract() -> dict:
    return {key: PREREG_DATA[key] for key in OPERATIONAL_KEYS}


def architecture_authorization_record() -> dict:
    raw = ARCHITECTURE.read_bytes()
    start = b"### 0.1 Accepted research constraints"
    end = b"### 0.2 Choices deliberately left OPEN"
    if raw.count(start) != 1 or raw.count(end) != 1:
        raise AssertionError("architecture authorization headings are not unique")
    start_index = raw.index(start)
    end_index = raw.index(end)
    if start_index >= end_index:
        raise AssertionError("architecture authorization headings are out of order")
    section = raw[start_index:end_index]
    text = section.decode("utf-8")
    required_header = (
        "| ID | Proposed decision | Rationale and consequence |\n"
        "|---|---|---|"
    )
    if required_header not in text:
        raise AssertionError("architecture authorization table header mismatch")
    pattern = re.compile(
        r"^\| \*\*(D(?:[0-9]|1[01])) — ([^|*\r\n]+)\*\* \| "
        r"([^|\r\n]+) \| ([^|\r\n]+) \|$",
        re.MULTILINE,
    )
    rows = pattern.findall(text)
    row_ids = tuple(row[0] for row in rows)
    require_equal(row_ids, ACCEPTED_CONSTRAINT_IDS, "architecture D-row IDs")
    return {
        "section_start_heading": start.decode("ascii"),
        "section_end_heading_exclusive": end.decode("ascii"),
        "section_sha256": sha256_bytes(section),
        "row_ids": list(row_ids),
        "row_titles": {row[0]: row[1] for row in rows},
        "row_manifest_sha256": sha256_bytes(canonical_json_bytes(rows)),
    }


def validate_exact_operational_records() -> None:
    """Require the authenticated JSON to match every implemented formula/rule."""
    require_equal(
        ACCEPTED_CONSTRAINT_DEFINITIONS,
        {
            "D0": "A reviewed standard nonce-misuse-resistant AEAD with independent directional keys is the external security boundary; AEAD-only remains the baseline.",
            "D1": "Replace reciprocal mirror traversal with independently derived ingress and egress stacks B_i(A_i(P_i) XOR M_i).",
            "D2": "Remove fixed-point-free involutive plugboard requirements; use arbitrary validated bijections or fold boundaries into independent stacks.",
            "D3": "Permit 256 logical rotor IDs but derive/cache selected material; select depth only from attack scaling, never from the number 256.",
            "D4": "Remove LFSR/NLFF from the security-critical schedule; use a standard counter-bound PRF/XOF schedule with exact context and limits.",
            "D5": "Use one explicit extract and domain-separated ingress, egress, schedule, mask, directional AEAD, and confirmation/export keys bound to suite/profile/transcript.",
            "D6": "Bind suite/profile, session, role, direction, sequence, nonce/tweak, and counter; define durable uniqueness, rollback/replay handling, and limits.",
            "D7": "Authenticate canonical metadata and lengths with standard AEAD; parse strictly and release no plaintext before verification.",
            "D8": "Require constant-time/oblivious rotor evaluation or an explicit exclusion, trusted-boundary schedule/mask generation where needed, atomic load, integrity, lifecycle, fault, and leakage evidence.",
            "D9": "Evolution is deterministic, immutable, versioned, offline, control-calibrated, holdout-graded, and human-promoted; deployed mutation is forbidden.",
            "D10": "Byte-local topology is only an AEAD-protected research transform; standalone-security research requires a separately specified wide-state design with cross-byte diffusion.",
            "D11": "Promotion requires a new incompatible identity, byte-exact spec, independent implementations and KATs, calibrated attacks, protocol/hardware evidence, external review, and human claim review.",
        },
        "accepted constraint definitions",
    )
    require_equal(
        PREREG_DATA["questions"],
        [
            {
                "id": "Q1",
                "text": "Do common ingress/egress endpoints across counters create an exact related-position quotient even after the reflector is removed?",
            },
            {
                "id": "Q2",
                "text": "Does full-counter state reselection remove the tested exact related-state invariants for key-derived random and affine-AES rotor families?",
            },
            {
                "id": "Q3",
                "text": "Does any active depth from 1+1 through 16+16 improve a bounded attack beyond the linear lookup cost paid by the honest path?",
            },
            {
                "id": "Q4",
                "text": "Does any byte-local candidate justify retention over PRF-mask-only or AEAD-only under a stated compromise model?",
            },
        ],
        "research questions",
    )
    require_equal(
        PREREG_DATA["non_claims"],
        [
            "Passing this gate is not IND-CPA, IND-CCA, AEAD, PRF, or standalone-cipher security.",
            "DDT, LAT, ANF, cycle, and ideal-control similarity are diagnostics, not security proofs.",
            "Every frozen byte state has 256 inputs and a complete map requires at most 255 chosen-input queries by elimination.",
            "The outer reviewed standard AEAD remains the only production security boundary.",
            "No security-bit value, quantum resistance, side-channel resistance, or production readiness is computed.",
            "The disjoint holdout labels are visible in this file and are not described as sealed or blind.",
        ],
        "non-claims",
    )
    require_equal(
        PREREG_DATA["rotor_families"],
        [
            {
                "id": "random_fisher_yates_v1",
                "candidate": True,
                "logical_ids_per_bank": 256,
                "banks": ["ingress", "egress"],
                "construction": "independent unbiased Fisher-Yates permutation for each bank and logical ID",
                "inverse": "exact inverse table",
                "quality_rejection": "none; retain the complete derived distribution and report intrinsic spectra",
                "implementation_warning": "arbitrary secret table input addresses have no efficient generic constant-time lookup path",
            },
            {
                "id": "aes_affine_v1",
                "candidate": True,
                "logical_ids_per_bank": 256,
                "banks": ["ingress", "egress"],
                "construction": "R(x) = L_out(AES_SBOX(L_in(x) XOR c_in)) XOR c_out with independently derived invertible 8x8 GF(2) matrices and constants",
                "matrix_convention": "bit 0 is LSB; output bit r is parity(row_r AND x); reject matrices with GF(2) rank below 8 using a domain-separated attempt counter",
                "aes_sbox_derivation": "GF(2^8) inverse under x^8+x^4+x^3+x+1 followed by the Rijndael affine map and XOR 0x63",
                "aes_sbox_sha256": AES_SBOX_SHA256,
                "inverse": "exact inverse table",
                "quality_rejection": "invertible affine wrappers only; no post-result DDT/LAT cherry-picking",
                "implementation_note": "a tableless bitwise implementation path exists in principle but is not side-channel evidence",
            },
        ],
        "rotor family records",
    )
    require_equal(
        PREREG_DATA["schedule_arms"],
        [
            {
                "id": "full_counter_reselect_v1",
                "candidate": True,
                "selection": "derive independent ordered 16-of-256 ingress and egress ID lists from the full canonical context for every counter",
                "wrappers": "derive independent XOR pre/post byte wrappers for every selected rotor and counter",
                "mask": "derive one byte from the independent mask domain and full canonical context",
            },
            {
                "id": "message_stack_counter_wrappers_v1",
                "candidate": True,
                "selection": "derive ordered 16-of-256 lists without the counter, fixed for a stream/direction/sequence",
                "wrappers": "derive independent XOR pre/post byte wrappers from the full counter for every selected rotor",
                "mask": "derive one byte from the independent mask domain and full canonical context",
            },
            {
                "id": "common_endpoint_mask_only_control",
                "candidate": False,
                "selection": "derive stack and wrappers without the counter",
                "wrappers": "fixed across counters",
                "mask": "derive one byte from the full counter",
                "expected": "for unequal masks, F_s composed with inverse(F_t) is a fixed-point-free involution with 128 two-cycles",
            },
        ],
        "schedule formulas",
    )
    require_equal(
        PREREG_DATA["depth_pairing"],
        "Each state derives one ordered 16-ID list per bank; depth d uses the nested prefix of length d. A domain-separated replication derives an independent ordering to expose prefix artifacts.",
        "depth pairing formula",
    )
    require_equal(
        PREREG_DATA["ideal_controls"],
        [
            {
                "id": "ideal_independent_state",
                "construction": "fresh deterministic unbiased 256-point permutation for each complete context and counter; no shared rotor bank",
                "purpose": "null distribution for exact state and related-state metrics; never a candidate",
            },
            {
                "id": "prf_mask_only",
                "construction": "plaintext XOR independent full-context mask byte",
                "purpose": "ablation showing which confidentiality behavior is supplied by the mask rather than rotors; never a production proposal by itself",
            },
            {
                "id": "aead_only",
                "construction": "no inner transform",
                "purpose": "mandatory production complexity and security-boundary baseline",
            },
        ],
        "ideal controls and baselines",
    )
    require_equal(
        PREREG_DATA["baseline_execution_contract"],
        {
            "prf_mask_only": "Execute the same canonical mask derivation over every corpus context; report repeated-state known/chosen-input recovery cost and deterministic inner-operation cost.",
            "aead_only": "Record the zero-inner-transform complexity and mark byte-map/codebook metrics not applicable; it remains the production policy baseline rather than a simulated AEAD security experiment.",
            "comparison": "No rotor family is production-retained unless a later independent-key compromise experiment beats both baselines under the same model and cost accounting.",
        },
        "baseline execution formulas",
    )
    require_equal(
        PREREG_DATA["planted_controls"],
        [
            {
                "id": "mirrored_endpoints",
                "defect": "B equals inverse(A)",
                "detector": "full map involution at nonzero mask",
                "required_result": "detected",
            },
            {
                "id": "identity_affine",
                "defect": "identity/affine rotor map",
                "detector": "exact affine identity, DDT maximum 256, and LAT maximum 256",
                "required_result": "detected",
            },
            {
                "id": "duplicate_rotor_bank",
                "defect": "all logical IDs alias one permutation",
                "detector": "canonical table digest duplicate count",
                "required_result": "detected",
            },
            {
                "id": "common_endpoint_mask_only",
                "defect": "A and B fixed while only masks vary",
                "detector": "relative permutation is an involution with 128 two-cycles for every unequal-mask tested pair",
                "required_result": "detected",
            },
            {
                "id": "truncated_counter_8",
                "defect": "schedule and mask use only the low counter byte",
                "detector": "complete state/map collision at counters 0 and 256",
                "required_result": "detected",
            },
            {
                "id": "direction_omitted",
                "defect": "direction is absent from schedule and mask inputs",
                "detector": "complete state/map collision between directions 0 and 1",
                "required_result": "detected",
            },
            {
                "id": "ignored_key_bit",
                "defect": "bit 255 is cleared before derivation",
                "detector": "canonical derivation transcript collision between paired test keys",
                "required_result": "detected",
            },
            {
                "id": "modulo_sampler",
                "defect": "UInt16 value reduced modulo 255 without rejection",
                "detector": "exact residue multiplicities over all 65536 inputs are unequal",
                "required_result": "detected",
            },
        ],
        "planted control formulas",
    )
    require_equal(
        PREREG_DATA["control_execution_contract"],
        {
            "requirement": "Each planted defect must be injected through the same rotor/schedule/state serialization, cell summarization, and rejection-reason functions used for candidates wherever that defect applies.",
            "standalone_exact_exception": "The modulo-sampler control uses the same bounded-sampler multiplicity validator because it is a primitive-level defect rather than a state-map candidate.",
            "null_requirement": "Ideal independent controls must traverse the same cell rejection function and produce no exact rejection reason; clean KDF/domain controls must traverse the same reset, direction, and key-flip collision checks.",
        },
        "control execution formulas",
    )
    require_equal(
        PREREG_DATA["metrics"],
        {
            "functional": [
                "every rotor and state map is a bijection",
                "every stored inverse is exact",
                "encrypt/decrypt round trip over all 256 inputs",
                "nested-prefix depth construction matches literal composition",
            ],
            "intrinsic_rotor_diagnostics": [
                "cycle histogram and fixed points",
                "exact differential uniformity and DDT spectrum hash on the pinned ID subset",
                "exact maximum absolute LAT coefficient and LAT spectrum hash on the pinned ID subset",
                "coordinate and inverse ANF degree",
                "exact affine identity",
            ],
            "state_map_diagnostics": [
                "complete map digest",
                "cycle histogram, fixed points, two-cycles, longest cycle, and involution",
                "exact DDT/LAT/ANF diagnostics on the pinned spectrum subset",
                "255-query complete-codebook ceiling",
            ],
            "related_state": [
                "map agreement count",
                "relative permutation F_s composed with inverse(F_t): cycle data and involution",
                "reverse relative permutation inverse(F_s) composed with F_t",
                "cross-map XOR image size and maximum preimage",
                "commutator identity/fixed-point count on pinned adjacent triples",
                "exact cross-state differential maximum on the pinned spectrum subset",
                "complete-state and complete-map collision counts",
            ],
            "schedule": [
                "selected ID/order digest",
                "adjacent ID overlap",
                "domain and direction separation",
                "counter-boundary collision checks",
                "base-key versus pinned one-bit-flip transcript collisions",
            ],
            "deterministic_cost": [
                "logical rotor evaluations per byte",
                "derived/cached table bytes",
                "secret-dependent lookup classification",
                "candidate depth cost ratio",
            ],
        },
        "metric formulas",
    )
    require_equal(
        PREREG_DATA["hard_rejection_rules"],
        [
            "Abort interpretation unless every planted control is detected and the ideal-independent-state null triggers none of the exact structural detectors.",
            "Reject a candidate arm on any tested complete state/map collision across unequal canonical contexts.",
            "Reject a candidate arm on any direction-domain collision or pinned key-bit-flip transcript collision.",
            "Reject a candidate arm if any tested full state map is affine, identity, or an involution by construction rather than a separately reported chance event.",
            "Reject full_counter_reselect_v1 if any tested unequal-state relative permutation repeatedly exhibits the exact common-endpoint 128-transposition signature.",
            "Reject any schedule that aliases the tested 32-bit or 16-bit counter boundaries, reset contexts, or directions.",
            "Do not reject or select solely from DDT, LAT, ANF, cycles, p-values, avalanche, or resemblance to the ideal control.",
        ],
        "hard rejection rules",
    )
    require_equal(
        PREREG_DATA["depth_selection_rule"],
        {
            "principle": "Choose the smallest depth only if a preregistered bounded attack improves in data/time/memory scaling after dividing by the honest rotor-evaluation cost ratio, on both train and disjoint holdout corpora.",
            "required_normalized_improvement_factor": 2.0,
            "bounded_attacks_in_this_gate": [
                "two-query involution detector",
                "common-endpoint related-state quotient detector",
                "complete-state collision detector",
                "255-query repeated-state codebook recovery",
            ],
            "fallback": "If no depth clears the normalized factor, no depth is security-selected; retain at most the smallest non-rejected depth as a research baseline.",
        },
        "depth selection rule",
    )
    require_equal(
        PREREG_DATA["family_retention_rule"],
        {
            "production": "No byte-local family may displace AEAD-only in this gate. Production retention additionally requires a precise independent-key compromise model, a constant-time implementation receipt, and an advantage over a separately keyed standard primitive, none of which this gate supplies.",
            "next_research_baseline": "Among non-rejected arms, prefer full_counter_reselect_v1; prefer a family with a plausible tableless implementation path; then choose the smallest non-rejected depth. This tie-break selects only the next attack target, not a suite.",
            "valid_verdicts": [
                "INVALID_CONTROLS",
                "ALL_CANDIDATES_REJECTED",
                "NO_BYTE_LOCAL_PRODUCTION_CANDIDATE_RESEARCH_BASELINE_RETAINED",
            ],
        },
        "family retention rule",
    )
    require_equal(
        PREREG_DATA["receipt_contract"],
        {
            "schema": "E256-VNEXT-ROTOR-SCHEDULE-BAKEOFF-1",
            "status": "OPEN_PROGRESS",
            "output": "logs/e256-vnext-rotor-schedule-bakeoff.json",
            "runner": "Scripts/e256_vnext_bakeoff.py",
            "deterministic_payload": [
                "schema",
                "status",
                "predecessor",
                "preregistration path and SHA-256",
                "input hashes",
                "pinned parameters",
                "candidate manifest",
                "control outcomes",
                "results",
                "selection",
                "limitations",
            ],
            "check": "recompute input hashes and deterministic payload; require controls; compare the complete deterministic payload byte-for-byte",
            "excluded": "wall-clock timing, platform string, and other explicitly advisory environment fields only",
            "write": "canonical sorted JSON with final newline and atomic replacement",
        },
        "receipt contract",
    )


def verify_frozen_inputs() -> dict:
    validate_exact_operational_records()
    actual = {
        "preregistration_sha256": sha256_file(PREREG),
        "predecessor_receipt_sha256": sha256_file(PREDECESSOR_RECEIPT),
        "predecessor_harness_sha256": sha256_file(PREDECESSOR_HARNESS),
    }
    expected = {
        "preregistration_sha256": PREREG_SHA256,
        "predecessor_receipt_sha256": PREDECESSOR_RECEIPT_SHA256,
        "predecessor_harness_sha256": PREDECESSOR_HARNESS_SHA256,
    }
    require_equal(actual, expected, "frozen input hashes")
    reread_prereg = json.loads(PREREG.read_text(encoding="utf-8"))
    require_equal(reread_prereg, PREREG_DATA, "loaded preregistration")
    predecessor = json.loads(PREDECESSOR_RECEIPT.read_text(encoding="utf-8"))
    require_equal(
        predecessor.get("results_sha256"),
        PREDECESSOR_RESULTS_SHA256,
        "predecessor results digest",
    )

    require_equal(
        tuple(PREREG_DATA),
        (
            "schema",
            "status",
            "revision",
            "date_basis",
            "authorization",
            "predecessor",
            "questions",
            "non_claims",
            "experimental_kdf",
            "rotor_families",
            "schedule_arms",
            "active_depths_per_bank",
            "depth_pairing",
            "corpus",
            "ideal_controls",
            "baseline_execution_contract",
            "planted_controls",
            "control_execution_contract",
            "metrics",
            "hard_rejection_rules",
            "depth_selection_rule",
            "family_retention_rule",
            "receipt_contract",
        ),
        "preregistration top-level sections",
    )
    require_equal(
        PREREG_DATA["schema"],
        "E256-VNEXT-ROTOR-SCHEDULE-PREREGISTRATION-1",
        "preregistration schema",
    )
    require_equal(PREREG_DATA["status"], "FROZEN_FOR_EXECUTION", "status")

    authorization = PREREG_DATA["authorization"]
    require_equal(
        authorization["architecture_record"],
        str(ARCHITECTURE.relative_to(REPO)),
        "architecture path",
    )
    require_equal(
        ACCEPTED_CONSTRAINT_IDS,
        tuple(f"D{index}" for index in range(12)),
        "accepted constraint IDs",
    )
    require_equal(
        tuple(ACCEPTED_CONSTRAINT_DEFINITIONS),
        ACCEPTED_CONSTRAINT_IDS,
        "accepted constraint definition IDs",
    )
    if not all(
        isinstance(value, str) and value
        for value in ACCEPTED_CONSTRAINT_DEFINITIONS.values()
    ):
        raise AssertionError("accepted constraint definition is empty")
    require_equal(
        authorization["allowed"],
        "deterministic model and attack-harness research",
        "authorization scope",
    )
    require_equal(
        tuple(authorization["blocked"]),
        (
            "cipher-suite promotion",
            "production software",
            "fixture or profile promotion",
            "RTL implementation",
            "protocol deployment",
            "C/H/N claim movement",
            "security-bit or production-readiness claim",
        ),
        "blocked authorization list",
    )
    architecture_record = architecture_authorization_record()

    predecessor_contract = PREREG_DATA["predecessor"]
    require_equal(
        predecessor_contract["receipt"],
        str(PREDECESSOR_RECEIPT.relative_to(REPO)),
        "predecessor receipt path",
    )
    require_equal(
        predecessor_contract["receipt_sha256"],
        PREDECESSOR_RECEIPT_SHA256,
        "predecessor receipt prereg hash",
    )
    require_equal(
        predecessor_contract["results_sha256"],
        PREDECESSOR_RESULTS_SHA256,
        "predecessor results prereg hash",
    )
    require_equal(
        predecessor_contract["harness"],
        str(PREDECESSOR_HARNESS.relative_to(REPO)),
        "predecessor harness path",
    )
    require_equal(
        predecessor_contract["harness_sha256"],
        PREDECESSOR_HARNESS_SHA256,
        "predecessor harness prereg hash",
    )
    require_equal(
        predecessor_contract["git_head_at_preregistration"],
        "a8e192a446ce2efca73998fdb54c7e1c44bd7579",
        "predecessor preregistration git head",
    )
    require_equal(QUESTION_IDS, ("Q1", "Q2", "Q3", "Q4"), "question IDs")
    require_equal(len(PREREG_DATA["non_claims"]), 6, "non-claim count")

    kdf = PREREG_DATA["experimental_kdf"]
    require_equal(
        kdf["status"], "model-only baseline, not a suite decision", "KDF status"
    )
    require_equal(kdf["hash"], "SHA-512", "experimental KDF hash")
    require_equal(
        kdf["extract"],
        "PRK = HMAC-SHA512(key = ASCII 'E256-vNext/bakeoff/extract/v1', data = deterministic 32-byte test IKM)",
        "extract formula",
    )
    require_equal(
        kdf["expand_stream"],
        "HMAC-SHA512(PRK_subkey, domain || 0x00 || u64be(block_counter))",
        "expand formula",
    )
    require_equal(
        tuple(kdf["subkeys"]),
        ("rotor/in", "rotor/out", "schedule", "mask", "controls"),
        "KDF subkey domains",
    )
    require_equal(
        kdf["bounded_sampler"],
        "u16be rejection of the high incomplete interval",
        "bounded sampler formula",
    )
    canonical_context = kdf["canonical_context"]
    require_equal(
        canonical_context["prefix"],
        "E256-vNext/bakeoff/context/v1",
        "context prefix",
    )
    require_equal(
        canonical_context["encoding"],
        "prefix || repeated(u16be(byte_length) || UTF-8/opaque bytes) || u8(direction) || u64be(sequence) || u64be(counter)",
        "context encoding",
    )
    require_equal(
        tuple(canonical_context["ordered_fields"]),
        (
            "corpus",
            "rotor_family",
            "schedule_arm",
            "stream_id",
            "direction",
            "sequence",
            "absolute_byte_counter",
        ),
        "context field order",
    )
    require_equal(ROTOR_BANK_DOMAINS, {"ingress": "rotor/in", "egress": "rotor/out"}, "rotor domains")
    require_equal(CONTROL_DOMAIN, "controls", "control domain")

    require_equal(
        FAMILIES,
        ("random_fisher_yates_v1", "aes_affine_v1"),
        "rotor family IDs",
    )
    for record in FAMILY_RECORDS:
        require_equal(record["candidate"], True, f"{record['id']} candidate flag")
        require_equal(
            record["logical_ids_per_bank"], 256, f"{record['id']} logical IDs"
        )
        require_equal(tuple(record["banks"]), ("ingress", "egress"), "bank IDs")
        require_equal(record["inverse"], "exact inverse table", "inverse formula")
    require_equal(
        FAMILY_RECORDS[0]["construction"],
        "independent unbiased Fisher-Yates permutation for each bank and logical ID",
        "random family construction",
    )
    require_equal(
        FAMILY_RECORDS[1]["construction"],
        "R(x) = L_out(AES_SBOX(L_in(x) XOR c_in)) XOR c_out with independently derived invertible 8x8 GF(2) matrices and constants",
        "affine family construction",
    )
    require_equal(
        FAMILY_RECORDS[1]["matrix_convention"],
        "bit 0 is LSB; output bit r is parity(row_r AND x); reject matrices with GF(2) rank below 8 using a domain-separated attempt counter",
        "affine matrix convention",
    )
    require_equal(
        FAMILY_RECORDS[1]["aes_sbox_sha256"],
        AES_SBOX_SHA256,
        "frozen AES S-box hash",
    )
    require_equal(
        sha256_bytes(AES_SBOX.tobytes()), AES_SBOX_SHA256, "derived AES S-box hash"
    )

    require_equal(
        SCHEDULES,
        (
            "full_counter_reselect_v1",
            "message_stack_counter_wrappers_v1",
            "common_endpoint_mask_only_control",
        ),
        "schedule IDs",
    )
    require_equal(
        CANDIDATE_SCHEDULES,
        ("full_counter_reselect_v1", "message_stack_counter_wrappers_v1"),
        "candidate schedule IDs",
    )
    require_equal(
        CONTROL_SCHEDULES,
        ("common_endpoint_mask_only_control",),
        "control schedule IDs",
    )
    require_equal(
        tuple(record["candidate"] for record in SCHEDULE_RECORDS),
        (True, True, False),
        "schedule candidate flags",
    )
    require_equal(DEPTHS, (1, 2, 4, 8, 16), "active depths")
    require_equal(STACK_WIDTH, 16, "derived stack width")
    if "depth d uses the nested prefix of length d" not in PREREG_DATA["depth_pairing"]:
        raise AssertionError("nested-prefix depth formula mismatch")

    corpus = PREREG_DATA["corpus"]
    require_equal(TRAIN_KEY_LABELS, tuple(range(8)), "train key labels")
    require_equal(HOLDOUT_KEY_LABELS, tuple(range(8, 16)), "holdout key labels")
    if set(TRAIN_KEY_LABELS) & set(HOLDOUT_KEY_LABELS):
        raise AssertionError("train/holdout labels overlap")
    require_equal(
        corpus["test_ikm"],
        "first 32 bytes of SHA-512(ASCII 'E256-vNext/bakeoff/key/v1/' || u16be(key_label))",
        "test IKM formula",
    )
    require_equal(
        corpus["stream_id"],
        "first 16 bytes of SHA-256(ASCII 'E256-vNext/bakeoff/stream/v1/' || u16be(key_label) || u8(stream_index))",
        "stream ID formula",
    )
    require_equal(STREAM_IDS_PER_KEY, 2, "streams per key")
    require_equal(DIRECTIONS, (0, 1), "directions")
    require_equal(REPLICATIONS, ("primary", "independent"), "replications")
    require_equal(SEQUENCE, 7, "sequence")
    require_equal(
        COUNTERS,
        (0, 1, 2, 31, 32, 255, 256, 257, 65535, 65536, 4294967295, 4294967296),
        "ordinary counters",
    )
    require_equal(
        ADJACENT_PAIRS,
        (
            (0, 1),
            (1, 2),
            (31, 32),
            (255, 256),
            (256, 257),
            (65535, 65536),
            (4294967295, 4294967296),
        ),
        "adjacent pairs",
    )
    require_equal(
        RESET_CONTEXT_PAIRS,
        ({"before": {"sequence": 7, "counter": 65536}, "after": {"sequence": 8, "counter": 0}},),
        "reset context pairs",
    )
    require_equal(corpus["all_inputs_per_state"], 256, "inputs per state")
    require_equal(
        SPECTRUM_KEY_LABELS, (0, 8), "spectrum subset key labels"
    )
    require_equal(
        int(SPECTRUM_SUBSET["stream_index"]), 0, "spectrum stream index"
    )
    require_equal(int(SPECTRUM_SUBSET["direction"]), 0, "spectrum direction")
    require_equal(SPECTRUM_COUNTERS, (0, 1, 255, 256), "spectrum counters")
    require_equal(
        SPECTRUM_SCHEDULES, CANDIDATE_SCHEDULES, "spectrum schedules"
    )
    require_equal(
        INTRINSIC_ROTOR_IDS,
        (0, 1, 2, 3, 16, 17, 63, 64, 127, 128, 191, 192, 252, 253, 254, 255),
        "intrinsic rotor IDs",
    )
    require_equal(
        KEY_BIT_FLIP_INDICES,
        (0, 1, 7, 8, 15, 16, 31, 32, 63, 64, 95, 127, 128, 159, 191, 255),
        "key-bit flip indices",
    )

    require_equal(
        IDEAL_CONTROL_IDS,
        ("ideal_independent_state", "prf_mask_only", "aead_only"),
        "baseline IDs",
    )
    baseline_contract = PREREG_DATA["baseline_execution_contract"]
    require_equal(
        tuple(baseline_contract),
        ("prf_mask_only", "aead_only", "comparison"),
        "baseline execution contract sections",
    )
    require_equal(
        PLANTED_CONTROL_IDS,
        (
            "mirrored_endpoints",
            "identity_affine",
            "duplicate_rotor_bank",
            "common_endpoint_mask_only",
            "truncated_counter_8",
            "direction_omitted",
            "ignored_key_bit",
            "modulo_sampler",
        ),
        "planted control IDs",
    )
    if any(
        item["required_result"] != "detected"
        or not item["defect"]
        or not item["detector"]
        for item in PREREG_DATA["planted_controls"]
    ):
        raise AssertionError("planted control formula/result mismatch")
    require_equal(
        tuple(PREREG_DATA["control_execution_contract"]),
        ("requirement", "standalone_exact_exception", "null_requirement"),
        "control execution contract",
    )
    require_equal(
        tuple(PREREG_DATA["metrics"]),
        (
            "functional",
            "intrinsic_rotor_diagnostics",
            "state_map_diagnostics",
            "related_state",
            "schedule",
            "deterministic_cost",
        ),
        "metric sections",
    )
    if any(not values for values in PREREG_DATA["metrics"].values()):
        raise AssertionError("empty frozen metric section")
    require_equal(len(PREREG_DATA["hard_rejection_rules"]), 7, "hard rejection rules")
    hard_rules_text = "\n".join(PREREG_DATA["hard_rejection_rules"])
    for required_text in (
        "every planted control",
        "complete state/map collision",
        "direction-domain collision",
        "affine, identity, or an involution",
        "128-transposition signature",
        "32-bit or 16-bit counter boundaries, reset contexts, or directions",
        "Do not reject or select solely",
    ):
        if required_text not in hard_rules_text:
            raise AssertionError(f"missing hard-rejection rule: {required_text}")

    depth_rule = PREREG_DATA["depth_selection_rule"]
    require_equal(depth_rule["required_normalized_improvement_factor"], 2.0, "depth factor")
    require_equal(
        tuple(depth_rule["bounded_attacks_in_this_gate"]),
        (
            "two-query involution detector",
            "common-endpoint related-state quotient detector",
            "complete-state collision detector",
            "255-query repeated-state codebook recovery",
        ),
        "bounded attacks",
    )
    if "no depth is security-selected" not in depth_rule["fallback"]:
        raise AssertionError("depth fallback semantics mismatch")
    family_rule = PREREG_DATA["family_retention_rule"]
    if "AEAD-only" not in family_rule["production"]:
        raise AssertionError("production retention boundary mismatch")
    if (
        "prefer full_counter_reselect_v1" not in family_rule["next_research_baseline"]
        or "tableless implementation path" not in family_rule["next_research_baseline"]
    ):
        raise AssertionError("research baseline rank rule mismatch")
    require_equal(
        tuple(family_rule["valid_verdicts"]),
        (
            "INVALID_CONTROLS",
            "ALL_CANDIDATES_REJECTED",
            "NO_BYTE_LOCAL_PRODUCTION_CANDIDATE_RESEARCH_BASELINE_RETAINED",
        ),
        "valid verdicts",
    )

    receipt_contract = PREREG_DATA["receipt_contract"]
    require_equal(
        receipt_contract["schema"],
        "E256-VNEXT-ROTOR-SCHEDULE-BAKEOFF-1",
        "receipt schema",
    )
    require_equal(receipt_contract["status"], "OPEN_PROGRESS", "receipt status")
    require_equal(
        receipt_contract["output"], str(RECEIPT.relative_to(REPO)), "receipt output"
    )
    require_equal(
        receipt_contract["runner"],
        str(Path(__file__).resolve().relative_to(REPO)),
        "receipt runner",
    )
    require_equal(MAIN_MAP_COUNT, 46080, "main map count")
    require_equal(RESET_MAP_COUNT, 7680, "reset endpoint map count")
    require_equal(RESET_COMPARISON_COUNT, 3840, "reset comparison count")

    operational = operational_contract()
    accepted_definitions_hash = sha256_bytes(
        canonical_json_bytes(ACCEPTED_CONSTRAINT_DEFINITIONS)
    )
    operational_hash = sha256_bytes(canonical_json_bytes(operational))
    complete_prereg_hash = sha256_bytes(canonical_json_bytes(PREREG_DATA))
    return {
        **actual,
        "architecture_authorization": architecture_record,
        "architecture_authorization_section_sha256": architecture_record[
            "section_sha256"
        ],
        "accepted_constraint_definitions_sha256": accepted_definitions_hash,
        "operational_contract_sha256": operational_hash,
        "complete_preregistration_canonical_sha256": complete_prereg_hash,
    }


def toolchain_advisory(elapsed_seconds: float) -> dict:
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
        "python": sys.version.split()[0],
        "numpy": np.__version__,
        "platform": platform.platform(),
        "git_head": head.splitlines()[0] if head_ok and head else "unavailable",
        "git_dirty": bool(status) if status_ok else "unavailable",
        "elapsed_seconds_single_run_not_a_claim": round(elapsed_seconds, 3),
    }


def build_receipt() -> dict:
    started = time.perf_counter()
    frozen_inputs = verify_frozen_inputs()
    rank_self_tests = run_rank_self_tests()
    candidate_results = run_candidates()
    key_flips = key_flip_collision_check()
    baselines = run_baselines()
    controls = run_controls(candidate_results, key_flips)
    intrinsic = run_intrinsic_rotor_diagnostics()

    executed_baseline_ids = (
        "ideal_independent_state",
        *tuple(baselines["records"]),
    )
    baselines["frozen_ids"] = list(IDEAL_CONTROL_IDS)
    baselines["executed_ids"] = list(executed_baseline_ids)
    baselines["ids_exact"] = executed_baseline_ids == IDEAL_CONTROL_IDS
    baselines["pass"] = bool(
        baselines["pass"]
        and baselines["ids_exact"]
        and controls["ideal_null_no_exact_false_positive"]
    )

    interpretation_checks = {
        "frozen_contract_validated": True,
        "controls_complete_and_valid": controls["pass"],
        "baselines_complete": baselines["pass"],
        "campaign_coverage_complete": candidate_results["coverage"]["pass"],
        "common_endpoint_control_complete": candidate_results[
            "common_endpoint_control_execution"
        ]["pass"],
        "clean_key_flip_checks": key_flips["pass"],
        "rank_self_tests": rank_self_tests["pass"],
    }
    interpretation_gate = {
        "checks": interpretation_checks,
        "pass": all(interpretation_checks.values()),
        "failure_mode": "fail closed; emit/check is refused and selection verdict is INVALID_CONTROLS",
    }
    selection = select(candidate_results, key_flips, interpretation_gate)

    limitations = [
        "This is a bounded deterministic rejection campaign, not a proof of pseudorandomness, IND-CPA, IND-CCA, AEAD security, or production suitability.",
        "All frozen state maps have an 8-bit domain and a 255-query complete-codebook ceiling under a repeated-state chosen-input oracle.",
        "DDT, LAT, ANF, cycle, related-state, and ideal-control results are diagnostics and may miss untested attacks or rare keys.",
        "The visible holdout is disjoint but not sealed or blind.",
        "The experimental HMAC-SHA512 derivation is a model baseline, not a selected suite KDF or PRF/XOF.",
        "A tableless path for affine-AES rotors is only a construction observation; no constant-time, TVLA, power, EM, cache, or fault evidence exists.",
        "No externally held KAT, independent implementation, external cryptanalysis, RTL, protocol, or standard AEAD integration lands here.",
        "No C/H/N row, E256-003, E256-061, release gate, suite, fixture, or profile is closed or promoted.",
        "AEAD-only remains the production baseline and reviewed standard AEAD remains mandatory for real data.",
    ]

    deterministic_payload = {
        "schema": PREREG_DATA["receipt_contract"]["schema"],
        "status": PREREG_DATA["receipt_contract"]["status"],
        "predecessor": {
            "receipt": str(PREDECESSOR_RECEIPT.relative_to(REPO)),
            "receipt_sha256": PREDECESSOR_RECEIPT_SHA256,
            "results_sha256": PREDECESSOR_RESULTS_SHA256,
            "harness": str(PREDECESSOR_HARNESS.relative_to(REPO)),
            "harness_sha256": PREDECESSOR_HARNESS_SHA256,
        },
        "preregistration": {
            "path": str(PREREG.relative_to(REPO)),
            "sha256": PREREG_SHA256,
            "schema": PREREG_DATA["schema"],
        },
        "inputs": {
            **frozen_inputs,
            "runner": str(Path(__file__).resolve().relative_to(REPO)),
            "runner_sha256": sha256_file(Path(__file__).resolve()),
            "architecture_record": str(ARCHITECTURE.relative_to(REPO)),
            "accepted_research_constraints": list(ACCEPTED_CONSTRAINT_IDS),
            "accepted_constraint_definitions": ACCEPTED_CONSTRAINT_DEFINITIONS,
            "aes_sbox_sha256": sha256_bytes(AES_SBOX.tobytes()),
        },
        "pinned_parameters": {
            "families": list(FAMILIES),
            "schedule_arms": list(SCHEDULES),
            "candidate_schedule_arms": list(CANDIDATE_SCHEDULES),
            "control_schedule_arms": list(CONTROL_SCHEDULES),
            "active_depths_per_bank": list(DEPTHS),
            "replications": list(REPLICATIONS),
            "train_key_labels": list(TRAIN_KEY_LABELS),
            "disjoint_holdout_key_labels": list(HOLDOUT_KEY_LABELS),
            "key_labels": list(KEY_LABELS),
            "stream_ids_per_key": STREAM_IDS_PER_KEY,
            "directions": list(DIRECTIONS),
            "sequence": SEQUENCE,
            "counters": list(COUNTERS),
            "adjacent_pairs": [list(pair) for pair in ADJACENT_PAIRS],
            "reset_context_pairs": list(RESET_CONTEXT_PAIRS),
            "exact_spectrum_subset": SPECTRUM_SUBSET,
            "intrinsic_rotor_spectrum_ids": list(INTRINSIC_ROTOR_IDS),
            "key_bit_flip_indices": list(KEY_BIT_FLIP_INDICES),
            "all_inputs_per_state": PREREG_DATA["corpus"]["all_inputs_per_state"],
            "accepted_constraint_definitions": ACCEPTED_CONSTRAINT_DEFINITIONS,
            "accepted_constraint_definitions_sha256": frozen_inputs[
                "accepted_constraint_definitions_sha256"
            ],
            "operational_contract_sha256": frozen_inputs[
                "operational_contract_sha256"
            ],
            "architecture_authorization_section_sha256": frozen_inputs[
                "architecture_authorization_section_sha256"
            ],
            "baseline_ids": list(IDEAL_CONTROL_IDS),
            "planted_control_ids": list(PLANTED_CONTROL_IDS),
            "question_ids": list(QUESTION_IDS),
            "main_canonical_contexts": MAIN_CONTEXT_COUNT,
            "main_map_count": MAIN_MAP_COUNT,
            "ordinary_counter_count": len(COUNTERS),
            "reset_map_count_separately_counted": RESET_MAP_COUNT,
            "reset_comparison_count": RESET_COMPARISON_COUNT,
        },
        "candidate_manifest": {
            "topology": "F_i = B_i(A_i(P_i) XOR M_i)",
            "logical_rotor_ids_per_bank": FAMILY_RECORDS[0][
                "logical_ids_per_bank"
            ],
            "random_family": "unbiased Fisher-Yates, no quality rejection",
            "affine_family": "independent invertible GF(2)^8 wrappers around the derived AES S-box",
            "schedule": "nested 16-ID prefixes with full-counter, counter-wrapper, and common-endpoint arms",
            "candidate_manifest_sha256": candidate_results[
                "candidate_manifest_sha256"
            ],
        },
        "controls": controls,
        "baselines": baselines,
        "rank_self_tests": rank_self_tests,
        "coverage": candidate_results["coverage"],
        "results": {
            "cells": candidate_results["cells"],
            "common_endpoint_control_execution": candidate_results[
                "common_endpoint_control_execution"
            ],
            "key_bit_flip_check": key_flips,
            "rotor_bank_digest_records": candidate_results[
                "rotor_bank_digest_records"
            ],
            "rotor_bank_digest_records_sha256": candidate_results[
                "rotor_bank_digest_records_sha256"
            ],
            "intrinsic_rotor_diagnostics": intrinsic,
            "intrinsic_rotor_diagnostics_sha256": sha256_bytes(
                canonical_json_bytes(intrinsic)
            ),
            "state_spectrum_records": candidate_results[
                "state_spectrum_records"
            ],
            "state_spectrum_records_sha256": candidate_results[
                "state_spectrum_records_sha256"
            ],
            "cross_spectrum_records": candidate_results[
                "cross_spectrum_records"
            ],
            "cross_spectrum_records_sha256": candidate_results[
                "cross_spectrum_records_sha256"
            ],
        },
        "interpretation_gate": interpretation_gate,
        "selection": selection,
        "limitations": limitations,
    }
    deterministic_digest = sha256_bytes(canonical_json_bytes(deterministic_payload))
    elapsed = time.perf_counter() - started
    return {
        "deterministic_payload": deterministic_payload,
        "deterministic_payload_sha256": deterministic_digest,
        "environment_advisory_excluded_from_digest": toolchain_advisory(elapsed),
        "no_wall_clock": "No wall-clock timestamp is asserted; only deterministic inputs and outputs are graded.",
    }


def atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_bytes(data)
    os.replace(temporary, path)


def print_summary(receipt: dict) -> None:
    payload = receipt["deterministic_payload"]
    controls = payload["controls"]
    selection = payload["selection"]
    print("=" * 78)
    print("E256 vNEXT ROTOR/SCHEDULE BAKE-OFF  (OPEN_PROGRESS)")
    print("=" * 78)
    print(
        f"controls: planted={controls['all_planted_controls_detected']} "
        f"ideal_null={controls['ideal_null_no_exact_false_positive']}"
    )
    print(f"interpretation gate: {payload['interpretation_gate']['pass']}")
    print(f"verdict: {selection['verdict']}")
    print(f"eligible cells: {len(selection['eligible_cells'])}")
    print(f"security-selected depth: {selection['security_selected_depth']}")
    print(f"next research baseline: {selection['next_research_baseline']}")
    print(f"deterministic_payload_sha256: {receipt['deterministic_payload_sha256']}")
    print("production boundary: AEAD-only; no byte-local suite authorized")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--json", default=str(RECEIPT.relative_to(REPO)))
    args = parser.parse_args()
    output = REPO / args.json

    try:
        receipt = build_receipt()
    except Exception as error:
        print(f"BAKE-OFF FAILED: {error}", file=sys.stderr)
        return 1

    print_summary(receipt)
    gate_pass = receipt["deterministic_payload"]["interpretation_gate"]["pass"]
    if not gate_pass:
        print(
            "INTERPRETATION GATE FAILED — refusing to emit or accept receipt",
            file=sys.stderr,
        )
        return 1

    if args.check:
        if not output.exists():
            print(f"CHECK FAILED: {args.json} does not exist")
            return 1
        prior = json.loads(output.read_text(encoding="utf-8"))
        same_hash = prior.get("deterministic_payload_sha256") == receipt[
            "deterministic_payload_sha256"
        ]
        same_payload = prior.get("deterministic_payload") == receipt[
            "deterministic_payload"
        ]
        print(f"reproducibility: digest_match={same_hash} payload_match={same_payload}")
        print("CHECK PASS" if same_hash and same_payload else "CHECK FAIL")
        return 0 if same_hash and same_payload else 1

    atomic_write(
        output,
        json.dumps(receipt, indent=2, sort_keys=True).encode("utf-8") + b"\n",
    )
    print(f"wrote {output.relative_to(REPO)}")
    print("STATUS: OPEN_PROGRESS; no claim, suite, profile, fixture, or release gate moved")
    return 0


if __name__ == "__main__":
    sys.exit(main())
