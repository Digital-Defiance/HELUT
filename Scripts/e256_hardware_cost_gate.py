#!/usr/bin/env python3
"""E256-H rotor-lane hardware cost gate.

Measures the marginal LUT6 cost of four rotor keying schemes for one byte lane,
holding the S-box description constant, so constraint H3 in
directives/e256-hardware-architecture.md is decided by synthesis instead of by
hand estimate.

Contract:  directives/e256-hardware-cost-preregistration.json
Receipt:   logs/e256-hardware-cost-gate.json
RTL:       Hardware/RTL/Research/E256H/e256h_cost_lanes.v
Testbench: Hardware/Testbenches/Research/E256H/e256h_cost_lanes_tb.v

Fail-closed: on any contract, coverage, functional, or validity-control failure
this builds an in-memory diagnostic, exits nonzero, and refuses to write or
accept the canonical receipt.

This gate selects no round count, authorizes no production RTL, moves no C/H/N
row, and produces no security, timing, power, or side-channel claim.
"""

from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Dict, List, Sequence, Tuple

REPO = Path(__file__).resolve().parent.parent
PREREG = REPO / "directives/e256-hardware-cost-preregistration.json"
ARCHITECTURE = REPO / "directives/e256-hardware-architecture.md"
PREDECESSOR_RECEIPT = REPO / "logs/e256-wide-state-gate.json"
RTL = REPO / "Hardware/RTL/Research/E256H/e256h_cost_lanes.v"
TESTBENCH = REPO / "Hardware/Testbenches/Research/E256H/e256h_cost_lanes_tb.v"
RECEIPT = REPO / "logs/e256-hardware-cost-gate.json"
SCRATCH = REPO / "build/e256h-cost"

PREREG_SHA256 = "cbaa5b02ca71824866d857edda838d97ceca0816bed5f5af334d8625db336e27"
ARCHITECTURE_CONTRACT_SHA256 = (
    "b64472f73be9d0fc6318ff445c5f550cb0129309313228f416599c27d3957bb1"
)
PREDECESSOR_PAYLOAD_SHA256 = (
    "21758ce220b9da469a18ea617fa7b2fd41e906add69a258f830b12843e3e495b"
)
AES_SBOX_SHA256 = "c2d8e5eed6cbebd8625fc18f81486a7733c04f9b0129ffbe974c68b90308b4f2"

EXTRACT_KEY = b"E256-W/gate/extract/v1"
ROTOR_BASE = b"E256-W/gate/rotor/v1" + bytes([0])

PREREG_DATA = json.loads(PREREG.read_text(encoding="utf-8"))
VARIANTS = tuple(PREREG_DATA["variants"])
VARIANT_IDS = tuple(item["id"] for item in VARIANTS)
PREDICTIONS = tuple(PREREG_DATA["predictions"])
PREDICTION_IDS = tuple(item["id"] for item in PREDICTIONS)


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
# Frozen E256-W model KDF, reused verbatim so the measured lane matches the
# certified construction.


class PurposeStream:
    def __init__(self, key: bytes, domain: bytes) -> None:
        self.key = key
        self.domain = domain
        self.counter = 0
        self.buffer = b""
        self.offset = 0

    def byte(self) -> int:
        if self.offset == len(self.buffer):
            if self.counter > (1 << 64) - 1:
                raise StructuralValidationError("purpose stream exhausted")
            message = self.domain + b"\x00" + self.counter.to_bytes(8, "big")
            self.buffer = hmac.new(self.key, message, hashlib.sha512).digest()
            self.counter += 1
            self.offset = 0
        value = self.buffer[self.offset]
        self.offset += 1
        return value

    def read(self, count: int) -> bytes:
        return bytes(self.byte() for _ in range(count))


def extract_prk(ikm: bytes) -> bytes:
    return hmac.new(EXTRACT_KEY, ikm, hashlib.sha512).digest()


def subkey(prk: bytes, domain: str) -> bytes:
    return hmac.new(prk, b"subkey\x00" + domain.encode("ascii"), hashlib.sha512).digest()


def test_ikm(label: int) -> bytes:
    material = b"E256-W/gate/key/v1/" + label.to_bytes(2, "big")
    return hashlib.sha512(material).digest()[:32]


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


def build_aes_sbox() -> Tuple[int, ...]:
    table = []
    for value in range(256):
        inverse = 0 if value == 0 else gf_pow(value, 254)
        table.append(
            inverse
            ^ rol8(inverse, 1)
            ^ rol8(inverse, 2)
            ^ rol8(inverse, 3)
            ^ rol8(inverse, 4)
            ^ 0x63
        )
    result = tuple(table)
    require_equal(sha256_bytes(bytes(result)), AES_SBOX_SHA256, "derived AES S-box")
    return result


AES_SBOX = build_aes_sbox()


def popcount(value: int) -> int:
    return bin(value & 0xFF).count("1")


def gf2_rank(rows: Sequence[int]) -> int:
    work = [int(row) for row in rows]
    rank = 0
    for column in range(7, -1, -1):
        pivot = next(
            (index for index in range(rank, 8) if (work[index] >> column) & 1), None
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
        stream = PurposeStream(key, label + attempt.to_bytes(2, "big"))
        rows = tuple(stream.byte() for _ in range(8))
        if gf2_rank(rows) == 8:
            return rows
    raise StructuralValidationError("no invertible matrix within frozen attempts")


def apply_linear(rows: Sequence[int], value: int) -> int:
    output = 0
    for bit, row in enumerate(rows):
        output |= (popcount(int(row) & value) & 1) << bit
    return output


def frozen_key_material() -> dict:
    prk = extract_prk(test_ikm(0))
    rotor_key = subkey(prk, "rotor")
    matrix_in = derive_matrix(rotor_key, ROTOR_BASE + b"/matrix/in/attempt/")
    matrix_out = derive_matrix(rotor_key, ROTOR_BASE + b"/matrix/out/attempt/")
    constants = PurposeStream(rotor_key, ROTOR_BASE + b"/constants").read(2)
    c_in, c_out = constants[0], constants[1]

    fixed = [AES_SBOX[x] for x in range(256)]
    offset = [AES_SBOX[x ^ c_in] ^ c_out for x in range(256)]
    affine = [
        apply_linear(matrix_out, AES_SBOX[apply_linear(matrix_in, x) ^ c_in]) ^ c_out
        for x in range(256)
    ]

    identity_rows = tuple(1 << bit for bit in range(8))
    for x in range(256):
        if apply_linear(identity_rows, x) != x:
            raise StructuralValidationError("identity matrix convention mismatch")

    # Frozen equivalence obligation: the offset lane is exactly the affine lane
    # with both matrices set to the identity.
    affine_with_identity = [
        apply_linear(identity_rows, AES_SBOX[apply_linear(identity_rows, x) ^ c_in])
        ^ c_out
        for x in range(256)
    ]
    require_equal(
        affine_with_identity, offset, "offset equals affine at identity matrices"
    )
    if len(set(affine)) != 256 or len(set(offset)) != 256:
        raise StructuralValidationError("rotor lane table is not a bijection")

    return {
        "matrix_in": matrix_in,
        "matrix_out": matrix_out,
        "c_in": c_in,
        "c_out": c_out,
        "identity_rows": identity_rows,
        "tables": {"fixed": fixed, "offset": offset, "affine": affine},
    }


# ---------------------------------------------------------------------------
# Frozen contract validation


def architecture_contract_digest() -> str:
    raw = ARCHITECTURE.read_bytes()
    start = PREREG_DATA["authorization"]["contract_start_marker"].encode("ascii")
    end = PREREG_DATA["authorization"]["contract_end_marker"].encode("ascii")
    if raw.count(start) != 1 or raw.count(end) != 1:
        raise StructuralValidationError("architecture contract markers are not unique")
    if raw.index(start) >= raw.index(end):
        raise StructuralValidationError("architecture contract markers out of order")
    slice_bytes = raw[raw.index(start) + len(start) : raw.index(end)]
    return sha256_bytes(slice_bytes)


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


def validate_frozen_inputs() -> dict:
    require_equal(
        PREREG_DATA["schema"], "E256-HARDWARE-COST-PREREGISTRATION-1", "prereg schema"
    )
    require_equal(PREREG_DATA["status"], "FROZEN_FOR_EXECUTION", "prereg status")
    require_equal(sha256_file(PREREG), PREREG_SHA256, "raw preregistration SHA-256")

    authorization = PREREG_DATA["authorization"]
    require_equal(
        authorization["contract_sha256"],
        ARCHITECTURE_CONTRACT_SHA256,
        "pinned architecture contract hash",
    )
    require_equal(
        architecture_contract_digest(),
        ARCHITECTURE_CONTRACT_SHA256,
        "recomputed architecture contract hash",
    )
    require_equal(
        tuple(authorization["graded_constraints"]),
        ("H0", "H1", "H2", "H3", "H7"),
        "graded constraint IDs",
    )
    require_equal(
        tuple(authorization["blocked"]),
        (
            "production RTL or bitstream",
            "cipher-suite or profile promotion",
            "fixture or protocol promotion",
            "C/H/N claim movement",
            "security-bit, timing-closure, power, or side-channel claim",
            "round-count selection",
        ),
        "blocked authorization list",
    )

    predecessor = PREREG_DATA["predecessor"]
    require_equal(
        predecessor["deterministic_payload_sha256"],
        PREDECESSOR_PAYLOAD_SHA256,
        "pinned predecessor payload digest",
    )
    receipt = json.loads(PREDECESSOR_RECEIPT.read_text(encoding="utf-8"))
    require_equal(
        receipt["deterministic_payload"]["schema"],
        "E256-WIDE-STATE-GATE-1",
        "predecessor schema",
    )
    require_equal(
        sha256_bytes(canonical_json_bytes(receipt["deterministic_payload"])),
        PREDECESSOR_PAYLOAD_SHA256,
        "recomputed predecessor payload digest",
    )
    require_equal(
        receipt.get("deterministic_payload_sha256"),
        PREDECESSOR_PAYLOAD_SHA256,
        "stored predecessor payload digest",
    )
    require_equal(
        receipt["deterministic_payload"]["interpretation"]["verdict"],
        "STRUCTURAL_WIDE_STATE_CANDIDATE_RETAINED_FOR_ATTACK_ONLY",
        "inherited predecessor verdict",
    )

    require_equal(
        VARIANT_IDS,
        (
            "identity",
            "xor_only",
            "fixed",
            "offset",
            "offset_alt",
            "affine",
            "table",
        ),
        "frozen variant IDs",
    )
    require_equal(
        tuple(sorted(PREDICTION_IDS)),
        ("P1", "P2", "P3", "P4", "P5", "P6", "P7", "P8"),
        "frozen prediction IDs",
    )
    if "flatten" in PREREG_DATA["synthesis_contract"]["script"]:
        raise StructuralValidationError("frozen synthesis script must not flatten")
    require_equal(
        PREREG_DATA["shared_sbox"]["aes_sbox_sha256"], AES_SBOX_SHA256, "prereg AES hash"
    )
    require_equal(
        PREREG_DATA["functional_verification"]["expected_total_checks"],
        1792,
        "expected functional checks",
    )
    require_equal(
        tuple(PREREG_DATA["interpretation"]["valid_emitted_verdicts"]),
        ("H3_OFFSET_KEYING_SUPPORTED", "H3_OFFSET_KEYING_NOT_SUPPORTED"),
        "valid emitted verdicts",
    )
    require_equal(
        PREREG_DATA["receipt_contract"]["schema"],
        "E256-HARDWARE-COST-GATE-1",
        "receipt schema",
    )
    require_equal(
        PREREG_DATA["receipt_contract"]["runner"],
        str(Path(__file__).resolve().relative_to(REPO)),
        "receipt runner path",
    )
    require_equal(
        PREREG_DATA["receipt_contract"]["rtl"],
        str(RTL.relative_to(REPO)),
        "receipt RTL path",
    )
    require_equal(
        PREREG_DATA["receipt_contract"]["testbench"],
        str(TESTBENCH.relative_to(REPO)),
        "receipt testbench path",
    )

    versions = tool_versions()
    toolchain = PREREG_DATA["toolchain_contract"]
    if not versions["yosys"].startswith(toolchain["yosys_version_prefix"]):
        raise StructuralValidationError(
            f"yosys version drift: {versions['yosys']!r}"
        )
    if toolchain["yosys_git_sha1"] not in versions["yosys"]:
        raise StructuralValidationError("yosys git sha1 drift")
    if not versions["iverilog"].startswith(toolchain["iverilog_version_prefix"]):
        raise StructuralValidationError(
            f"iverilog version drift: {versions['iverilog']!r}"
        )

    return {
        "preregistration": str(PREREG.relative_to(REPO)),
        "preregistration_sha256": PREREG_SHA256,
        "architecture_record": str(ARCHITECTURE.relative_to(REPO)),
        "architecture_contract_sha256": ARCHITECTURE_CONTRACT_SHA256,
        "predecessor_receipt": str(PREDECESSOR_RECEIPT.relative_to(REPO)),
        "predecessor_payload_sha256": PREDECESSOR_PAYLOAD_SHA256,
        "rtl": str(RTL.relative_to(REPO)),
        "rtl_sha256": sha256_file(RTL),
        "testbench": str(TESTBENCH.relative_to(REPO)),
        "testbench_sha256": sha256_file(TESTBENCH),
        "runner": str(Path(__file__).resolve().relative_to(REPO)),
        "runner_sha256": sha256_file(Path(__file__).resolve()),
        "aes_sbox_sha256": AES_SBOX_SHA256,
        "yosys_version": versions["yosys"],
        "iverilog_version": versions["iverilog"],
    }


# ---------------------------------------------------------------------------
# Functional verification and synthesis


def write_vectors(material: dict) -> None:
    if SCRATCH.exists():
        shutil.rmtree(SCRATCH)
    SCRATCH.mkdir(parents=True, exist_ok=True)

    params: List[int] = [
        material["c_in"],
        material["c_out"],
        material["c_in"],
        material["c_out"],
    ]
    # Slots 0..3 are p_in, p_out, c_in, c_out. Slots 4..11 are matrix_in rows
    # 0..7 and slots 12..19 are matrix_out rows 0..7, matching the frozen
    # row-order convention. The offset lane needs no matrix: it is the affine
    # lane with both matrices set to identity, which is asserted separately.
    params.extend(material["matrix_in"])
    params.extend(material["matrix_out"])
    if len(params) != 20:
        raise StructuralValidationError("parameter vector length drift")

    (SCRATCH / "params.hex").write_text(
        "".join(f"{value:02x}\n" for value in params), encoding="utf-8"
    )
    for name in ("fixed", "offset", "affine"):
        (SCRATCH / f"expect_{name}.hex").write_text(
            "".join(f"{value:02x}\n" for value in material["tables"][name]),
            encoding="utf-8",
        )


def run_functional(material: dict) -> dict:
    write_vectors(material)
    binary = SCRATCH / "e256h_cost_lanes_tb.vvp"
    compile_process = subprocess.run(
        ["iverilog", "-g2012", "-o", str(binary), str(TESTBENCH), str(RTL)],
        capture_output=True,
        text=True,
        timeout=300,
        check=False,
        cwd=str(REPO),
    )
    if compile_process.returncode != 0:
        raise StructuralValidationError(
            f"iverilog compile failed: {compile_process.stderr.strip()[:400]}"
        )
    run_process = subprocess.run(
        ["vvp", str(binary)],
        capture_output=True,
        text=True,
        timeout=300,
        check=False,
        cwd=str(REPO),
    )
    output = (run_process.stdout or "") + (run_process.stderr or "")
    if run_process.returncode != 0:
        raise StructuralValidationError(
            f"vvp run failed: {output.strip()[:400]}"
        )
    match = re.search(r"E256H_COST_TB checks=(\d+) failures=(\d+)", output)
    if match is None:
        raise StructuralValidationError("testbench summary line missing")
    checks = int(match.group(1))
    failures = int(match.group(2))
    require_equal(
        checks,
        PREREG_DATA["functional_verification"]["expected_total_checks"],
        "functional check count",
    )
    if failures:
        raise StructuralValidationError(f"{failures} functional mismatches")
    if "E256H_COST_TB PASS" not in output:
        raise StructuralValidationError("testbench did not report PASS")
    return {
        "expected_checks": checks,
        "executed_checks": checks,
        "failures": failures,
        "checks_per_variant": (
            PREREG_DATA["functional_verification"]["expected_checks_per_variant"]
        ),
        "equivalence_obligations": list(
            PREREG_DATA["functional_verification"]["equivalence_obligations"]
        ),
        "pass": True,
    }


SBOX_MODULE = "e256h_aes_sbox"

# `flatten` is deliberately absent: flattening lets ABC re-synthesize the shared
# S-box together with the keying logic, which destroys the structural boundary
# the marginal measurement depends on. A prior flatten-based draft was rejected
# by its own P3 metric-stability control.
SYNTH_SCRIPT = (
    "read_verilog {rtl}; hierarchy -check -top {module}; proc; memory; "
    "opt; techmap; opt; dffunmap; zinit -all; abc -lut 6; opt_clean; "
    "check -assert; stat; ltp -noff"
)


def stat_sections(output: str) -> Dict[str, str]:
    return dict(
        re.findall(
            r"=== (\S+) ===\n(.*?)(?=\n=== |\nEnd of script|\Z)", output, re.DOTALL
        )
    )


def section_lut6(sections: Dict[str, str], module: str) -> int:
    text = sections.get(module)
    if text is None:
        return 0
    match = re.search(r"^\s*(\d+)\s+\$lut\s*$", text, re.MULTILINE)
    return int(match.group(1)) if match else 0


def synthesize(module: str) -> dict:
    if "flatten" in SYNTH_SCRIPT:
        raise StructuralValidationError("synthesis script must not flatten")
    script = SYNTH_SCRIPT.format(rtl=str(RTL.relative_to(REPO)), module=module)
    process = subprocess.run(
        ["yosys", "-Q", "-p", script],
        capture_output=True,
        text=True,
        timeout=1800,
        check=False,
        cwd=str(REPO),
    )
    output = (process.stdout or "") + (process.stderr or "")
    if process.returncode != 0:
        raise StructuralValidationError(
            f"yosys failed for {module}: {output.strip()[-400:]}"
        )

    sections = stat_sections(output)
    if module not in sections:
        raise StructuralValidationError(f"no stat section for {module}")

    stat_text = sections[module]
    keying_lut6 = section_lut6(sections, module)
    shared_sbox_lut6 = section_lut6(sections, SBOX_MODULE)

    memory_bits = 0
    memory_match = re.search(r"^\s*Memory bits:\s*(\d+)", stat_text, re.MULTILINE)
    if memory_match:
        memory_bits = int(memory_match.group(1))

    local_cells = 0
    cells_match = re.search(r"^\s*(\d+)\s+cells\s*$", stat_text, re.MULTILINE)
    if cells_match:
        local_cells = int(cells_match.group(1))

    depth = 0
    depth_match = re.search(
        rf"Longest topological path in {re.escape(module)}[^(]*\(length=(\d+)\)",
        output,
    )
    if depth_match:
        depth = int(depth_match.group(1))

    cell_types: Dict[str, int] = {}
    for count, name in re.findall(r"^\s*(\d+)\s+(\$[a-z0-9_]+)\s*$", stat_text, re.M):
        cell_types[name] = int(count)

    return {
        "module": module,
        "keying_lut6": keying_lut6,
        "shared_sbox_lut6": shared_sbox_lut6,
        "total_lut6": keying_lut6 + shared_sbox_lut6,
        "local_cells": local_cells,
        "memory_bits": memory_bits,
        "longest_topological_path": depth,
        "local_cell_types": cell_types,
    }


def run_measurements() -> dict:
    records = []
    for variant in VARIANTS:
        record = synthesize(variant["module"])
        record["id"] = variant["id"]
        record["role"] = variant["role"]
        record["keyed_bits"] = int(variant["keyed_bits"])
        records.append(record)

    executed = tuple(record["id"] for record in records)
    require_equal(executed, VARIANT_IDS, "executed variant IDs")

    by_id = {record["id"]: record for record in records}
    sbox_costs = {
        record["id"]: record["shared_sbox_lut6"]
        for record in records
        if record["id"] in ("fixed", "offset", "offset_alt", "affine")
    }
    if len(set(sbox_costs.values())) != 1:
        raise StructuralValidationError(
            f"shared S-box cost is not constant across variants: {sbox_costs}"
        )
    shared_sbox_lut6 = next(iter(sbox_costs.values()))

    offset_keying = by_id["offset"]["keying_lut6"]
    ratios = {}
    for name in ("affine", "table"):
        ratios[name] = (
            round(by_id[name]["keying_lut6"] / offset_keying, 6)
            if offset_keying
            else None
        )

    return {
        "records": records,
        "executed_ids": list(executed),
        "frozen_ids": list(VARIANT_IDS),
        "ids_exact": executed == VARIANT_IDS,
        "shared_sbox_lut6": shared_sbox_lut6,
        "shared_sbox_lut6_constant_across_variants": True,
        "keying_lut6_by_variant": {
            record["id"]: record["keying_lut6"] for record in records
        },
        "depth_by_variant": {
            record["id"]: record["longest_topological_path"] for record in records
        },
        "keying_lut6_ratio_over_offset": ratios,
    }


def grade_predictions(measurements: dict) -> dict:
    by_id = {record["id"]: record for record in measurements["records"]}
    keying = measurements["keying_lut6_by_variant"]
    shared_sbox = measurements["shared_sbox_lut6"]

    outcomes = {
        "P1": {
            "role": "validity_control",
            "statement": "identity keying_lut6 is exactly 0",
            "observed": keying["identity"],
            "pass": keying["identity"] == 0,
        },
        "P2": {
            "role": "validity_control",
            "statement": "xor_only keying_lut6 is at most 8",
            "observed": keying["xor_only"],
            "pass": keying["xor_only"] <= 8,
        },
        "P3": {
            "role": "validity_control",
            "statement": "offset_alt equals offset in keying_lut6 and depth",
            "observed": {
                "offset_keying_lut6": keying["offset"],
                "offset_alt_keying_lut6": keying["offset_alt"],
                "offset_depth": by_id["offset"]["longest_topological_path"],
                "offset_alt_depth": by_id["offset_alt"]["longest_topological_path"],
            },
            "pass": (
                keying["offset"] == keying["offset_alt"]
                and by_id["offset"]["longest_topological_path"]
                == by_id["offset_alt"]["longest_topological_path"]
            ),
        },
        "P7": {
            "role": "validity_control",
            "statement": "fixed keying_lut6 is 0 and its shared S-box cost is positive",
            "observed": {
                "fixed_keying_lut6": keying["fixed"],
                "shared_sbox_lut6": shared_sbox,
            },
            "pass": keying["fixed"] == 0 and shared_sbox > 0,
        },
        "P4": {
            "role": "graded_finding",
            "statement": "affine keying_lut6 is at least 4x offset keying_lut6",
            "observed": {
                "offset_keying_lut6": keying["offset"],
                "affine_keying_lut6": keying["affine"],
                "ratio": measurements["keying_lut6_ratio_over_offset"]["affine"],
            },
            "pass": keying["affine"] >= 4 * keying["offset"],
        },
        "P5": {
            "role": "graded_finding",
            "statement": "table keying_lut6 exceeds the shared S-box cost",
            "observed": {
                "table_keying_lut6": keying["table"],
                "shared_sbox_lut6": shared_sbox,
            },
            "pass": keying["table"] > shared_sbox,
        },
        "P6": {
            "role": "graded_finding",
            "statement": "offset keying_lut6 is at most 32",
            "observed": keying["offset"],
            "pass": keying["offset"] <= 32,
        },
        "P8": {
            "role": "graded_finding",
            "statement": "offset depth is strictly less than affine depth",
            "observed": {
                "offset_depth": by_id["offset"]["longest_topological_path"],
                "affine_depth": by_id["affine"]["longest_topological_path"],
            },
            "pass": (
                by_id["offset"]["longest_topological_path"]
                < by_id["affine"]["longest_topological_path"]
            ),
        },
    }
    require_equal(
        tuple(sorted(outcomes)), tuple(sorted(PREDICTION_IDS)), "graded prediction IDs"
    )
    validity_ids = tuple(
        item["id"] for item in PREDICTIONS if item["role"] == "validity_control"
    )
    require_equal(validity_ids, ("P1", "P2", "P3", "P7"), "validity control IDs")
    return {
        "outcomes": outcomes,
        "validity_control_ids": list(validity_ids),
        "validity_controls_pass": all(
            outcomes[pid]["pass"] for pid in validity_ids
        ),
    }


# ---------------------------------------------------------------------------
# Receipt


def build_receipt() -> dict:
    started = time.perf_counter()
    inputs = validate_frozen_inputs()
    material = frozen_key_material()
    functional = run_functional(material)
    measurements = run_measurements()
    predictions = grade_predictions(measurements)

    validity_checks = {
        "frozen_contract_validated": True,
        "variant_coverage_exact": measurements["ids_exact"],
        "functional_verification_pass": functional["pass"],
        "validity_controls_pass": predictions["validity_controls_pass"],
    }
    harness_valid = all(validity_checks.values())

    verdict = (
        "H3_OFFSET_KEYING_SUPPORTED"
        if predictions["outcomes"]["P4"]["pass"]
        else "H3_OFFSET_KEYING_NOT_SUPPORTED"
    )

    interpretation = {
        "harness_validity_checks": validity_checks,
        "harness_valid": harness_valid,
        "internal_invalid_status": PREREG_DATA["interpretation"][
            "internal_invalid_status"
        ],
        "verdict": verdict if harness_valid else "INVALID_COST_HARNESS",
        "production_round_count": None,
        "production_keying_scheme": None,
        "scope": PREREG_DATA["interpretation"]["scope"],
        "next": PREREG_DATA["interpretation"]["next"],
        "structural_certificates_unaffected": (
            "MDS, branch number, DDT/LAT, degree, and dependency certificates come "
            "from E256-062 and are untouched by any cost figure here."
        ),
        "production_boundary": (
            "Reviewed standard AEAD remains the production boundary; AEAD-only "
            "remains a valid final outcome."
        ),
    }

    deterministic_payload = {
        "schema": PREREG_DATA["receipt_contract"]["schema"],
        "status": PREREG_DATA["receipt_contract"]["status"],
        "inputs": inputs,
        "pinned_parameters": {
            "graded_constraints": list(
                PREREG_DATA["authorization"]["graded_constraints"]
            ),
            "variants": [
                {
                    "id": item["id"],
                    "module": item["module"],
                    "role": item["role"],
                    "function": item["function"],
                    "keyed_bits": int(item["keyed_bits"]),
                }
                for item in VARIANTS
            ],
            "synthesis_script": SYNTH_SCRIPT.format(
                rtl=str(RTL.relative_to(REPO)), module="<module>"
            ),
            "keying_lut6_metric": PREREG_DATA["synthesis_contract"][
                "keying_lut6_metric"
            ],
            "shared_sbox_lut6_metric": PREREG_DATA["synthesis_contract"][
                "shared_sbox_lut6_metric"
            ],
            "depth_metric": PREREG_DATA["synthesis_contract"]["depth_metric"],
            "flatten_prohibited": PREREG_DATA["synthesis_contract"][
                "flatten_prohibited"
            ],
            "rotor_matrix_in": list(material["matrix_in"]),
            "rotor_matrix_out": list(material["matrix_out"]),
            "rotor_c_in": material["c_in"],
            "rotor_c_out": material["c_out"],
            "offset_p_in": material["c_in"],
            "offset_p_out": material["c_out"],
            "fixed_table_sha256": sha256_bytes(bytes(material["tables"]["fixed"])),
            "offset_table_sha256": sha256_bytes(bytes(material["tables"]["offset"])),
            "affine_table_sha256": sha256_bytes(bytes(material["tables"]["affine"])),
        },
        "coverage": {
            "frozen_variant_ids": list(VARIANT_IDS),
            "executed_variant_ids": measurements["executed_ids"],
            "variant_coverage_exact": measurements["ids_exact"],
            "frozen_prediction_ids": list(PREDICTION_IDS),
            "graded_prediction_ids": list(predictions["outcomes"]),
            "syntheses_executed": len(measurements["records"]),
        },
        "functional": functional,
        "measurements": measurements,
        "predictions": predictions,
        "interpretation": interpretation,
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
            "python": sys.version.split()[0],
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
    measurements = payload["measurements"]
    outcomes = payload["predictions"]["outcomes"]
    print("=" * 78)
    print("E256-H ROTOR-LANE HARDWARE COST GATE  (OPEN_PROGRESS)")
    print("=" * 78)
    print(f"harness valid: {payload['interpretation']['harness_valid']}")
    print(
        f"functional: {payload['functional']['executed_checks']} checks, "
        f"{payload['functional']['failures']} failures"
    )
    print(
        f"{'variant':<12}{'role':<26}{'keyLUT6':>8}{'depth':>7}{'keybits':>9}"
    )
    for record in measurements["records"]:
        print(
            f"{record['id']:<12}{record['role']:<26}"
            f"{record['keying_lut6']:>8}{record['longest_topological_path']:>7}"
            f"{record['keyed_bits']:>9}"
        )
    print(f"shared S-box LUT6 (excluded from keying): {measurements['shared_sbox_lut6']}")
    for name, value in sorted(measurements["keying_lut6_ratio_over_offset"].items()):
        print(f"  {name} keying / offset keying = {value}x")
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
        print(f"COST GATE FAILED: {error}", file=sys.stderr)
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
        "round count, or production keying scheme moved"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
