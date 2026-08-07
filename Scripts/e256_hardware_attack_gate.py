#!/usr/bin/env python3
"""E256-H hardware attack lane gate (constraint H8).

Runs two synthesizable attack arms against reduced-round E256-H, requires the
same netlist to recover two planted defects, checks the RTL bit-exactly against
an independent software model, and reports attack cost in LUT6 and cycles.

Contract:  directives/e256-hardware-attack-preregistration.json
Receipt:   logs/e256-hardware-attack-gate.json
RTL:       Hardware/RTL/Research/E256H/e256h_attack_core.v
Testbench: Hardware/Testbenches/Research/E256H/e256h_attack_core_tb.v

This gate grades the SEARCH, not the cipher. A calibrated search that finds no
distinguisher is not a security result. No round count is selected and no
production artifact is authorized.
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
from typing import Dict, List, Sequence, Tuple

REPO = Path(__file__).resolve().parent.parent
PREREG = REPO / "directives/e256-hardware-attack-preregistration.json"
ARCHITECTURE = REPO / "directives/e256-hardware-architecture.md"
RTL = REPO / "Hardware/RTL/Research/E256H/e256h_attack_core.v"
TESTBENCH = REPO / "Hardware/Testbenches/Research/E256H/e256h_attack_core_tb.v"
RECEIPT = REPO / "logs/e256-hardware-attack-gate.json"
SCRATCH = REPO / "build/e256h-attack"

PREREG_SHA256 = "15bb0b68d1f0ebb521497d4d06cc4250cf608b3a71e1f0719f3e0a7b2017fde3"
ARCHITECTURE_CONTRACT_SHA256 = (
    "b64472f73be9d0fc6318ff445c5f550cb0129309313228f416599c27d3957bb1"
)
PREDECESSOR_DIGESTS = {
    "logs/e256-wide-state-gate.json": (
        "E256-WIDE-STATE-GATE-1",
        "21758ce220b9da469a18ea617fa7b2fd41e906add69a258f830b12843e3e495b",
    ),
    "logs/e256-hardware-cost-gate.json": (
        "E256-HARDWARE-COST-GATE-1",
        "a10e001ad2c2b3de55fcc80197c059f166d5e55599c670e20b01de8f6b7d323d",
    ),
    "logs/e256-hardware-candidate-gate.json": (
        "E256-HARDWARE-CANDIDATE-GATE-1",
        "98af83ec27093787552475fce588f84a902634afcc969bed26462032dddec3cc",
    ),
}
AES_SBOX_SHA256 = "c2d8e5eed6cbebd8625fc18f81486a7733c04f9b0129ffbe974c68b90308b4f2"

PREREG_DATA = json.loads(PREREG.read_text(encoding="utf-8"))
TARGET = PREREG_DATA["construction_under_attack"]
MAX_ROUNDS = int(TARGET["max_rounds_tested"])
MATERIAL_BYTES = int(TARGET["material"]["total_bytes"])
ROW_OFFSETS = tuple(int(value) for value in TARGET["row_offsets"])
MIX_ROWS = tuple(
    tuple(int(value, 16) for value in row) for row in TARGET["mix_columns_matrix_hex_rows"]
)
DEFECT_MODES = tuple(item["id"] for item in PREREG_DATA["defect_modes"])
DEFECT_CODES = tuple(int(item["code"]) for item in PREREG_DATA["defect_modes"])
ARM_IDS = tuple(item["id"] for item in PREREG_DATA["attack_arms"])
PREDICTION_IDS = tuple(item["id"] for item in PREREG_DATA["predictions"])
COST_MODULES = tuple(PREREG_DATA["cost_contract"]["modules_measured"])

SYNTH_SCRIPT = (
    "read_verilog {rtl}; hierarchy -check -top {module}; proc; memory; "
    "opt; techmap; opt; dffunmap; zinit -all; abc -lut 6; opt_clean; "
    "check -assert; stat; ltp -noff"
)


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
# Independent software model of the construction under attack.


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


MATERIAL_DOMAIN = b"E256-H/attack/material/v1"


def derive_material() -> dict:
    if MATERIAL_DOMAIN.decode("ascii") not in TARGET["material"]["derivation"]:
        raise StructuralValidationError("material domain drift")
    raw = hashlib.shake_256(MATERIAL_DOMAIN).digest(MATERIAL_BYTES)
    if len(raw) != MATERIAL_BYTES:
        raise StructuralValidationError("material squeeze length mismatch")
    p_in = [[raw[(r * 32 + j) * 2] for j in range(32)] for r in range(12)]
    p_out = [[raw[(r * 32 + j) * 2 + 1] for j in range(32)] for r in range(12)]
    base = 12 * 32 * 2
    masks = [[raw[base + m * 32 + i] for i in range(32)] for m in range(13)]
    return {"raw": raw, "p_in": p_in, "p_out": p_out, "masks": masks}


def rotor_layer(state: List[int], round_index: int, material: dict, defect: int):
    if defect == 1:
        return list(state)
    p_in = material["p_in"][round_index]
    p_out = material["p_out"][round_index]
    return [AES_SBOX[state[j] ^ p_in[j]] ^ p_out[j] for j in range(32)]


def row_shift(state: List[int], defect: int):
    if defect == 2:
        return list(state)
    out = [0] * 32
    for column in range(8):
        for row in range(4):
            out[4 * column + row] = state[
                4 * ((column + ROW_OFFSETS[row]) % 8) + row
            ]
    return out


def mix_columns(state: List[int], defect: int):
    if defect == 2:
        return list(state)
    out = [0] * 32
    for column in range(8):
        for row in range(4):
            accumulator = 0
            for k in range(4):
                accumulator ^= gf_mul(MIX_ROWS[row][k], state[4 * column + k])
            out[4 * column + row] = accumulator
    return out


def permute(block: Sequence[int], rounds: int, material: dict, defect: int):
    masks = material["masks"]
    state = [block[i] ^ masks[0][i] for i in range(32)]
    for round_index in range(rounds):
        state = rotor_layer(state, round_index, material, defect)
        state = row_shift(state, defect)
        state = mix_columns(state, defect)
        state = [state[i] ^ masks[round_index + 1][i] for i in range(32)]
    return state


def model_integral(rounds: int, material: dict, defect: int, active_lane: int = 0):
    accumulator = [0] * 32
    for value in range(256):
        block = [0] * 32
        block[active_lane] = value
        out = permute(block, rounds, material, defect)
        for index in range(32):
            accumulator[index] ^= out[index]
    return accumulator


def model_truncated(rounds: int, material: dict, defect: int):
    base = permute([0] * 32, rounds, material, defect)
    other = [0] * 32
    other[0] = int(PREREG_DATA["attack_arms"][1]["input_difference"])
    diff = permute(other, rounds, material, defect)
    active = sum(1 for i in range(32) if base[i] != diff[i])
    return base, diff, active


def state_to_hex(state: Sequence[int]) -> str:
    """Match the testbench's %064x formatting of a 256-bit vector."""
    value = 0
    for index in range(32):
        value |= int(state[index]) << (8 * index)
    return f"{value:064x}"


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
        PREREG_DATA["schema"], "E256-HARDWARE-ATTACK-PREREGISTRATION-1", "prereg schema"
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
        ("H0", "H1", "H8"),
        "graded constraint IDs",
    )
    require_equal(DEFECT_MODES, ("candidate", "identity_rotor", "no_diffusion"), "defect IDs")
    require_equal(DEFECT_CODES, (0, 1, 2), "defect codes")
    require_equal(ARM_IDS, ("integral", "truncated_differential"), "attack arm IDs")
    require_equal(PREDICTION_IDS, ("A1", "A2", "A3", "A4", "A5", "A6"), "prediction IDs")
    require_equal(ROW_OFFSETS, (0, 1, 3, 4), "row offsets")
    require_equal(MAX_ROUNDS, 8, "max rounds tested")
    require_equal(MATERIAL_BYTES, 1184, "material byte count")
    require_equal(12 * 32 * 2 + 13 * 32, MATERIAL_BYTES, "material layout arithmetic")
    require_equal(TARGET["aes_sbox_sha256"], AES_SBOX_SHA256, "prereg AES hash")
    require_equal(
        COST_MODULES,
        ("e256h_atk_round", "e256h_atk_single", "e256h_atk_integral"),
        "cost modules",
    )
    require_equal(
        tuple(PREREG_DATA["interpretation"]["valid_emitted_verdicts"]),
        (
            "HARDWARE_ATTACK_LANE_CALIBRATED_REDUCED_ROUND_DISTINGUISHER_FOUND",
            "HARDWARE_ATTACK_LANE_CALIBRATED_NO_DISTINGUISHER_FOUND",
        ),
        "valid emitted verdicts",
    )
    require_equal(
        PREREG_DATA["receipt_contract"]["runner"],
        str(Path(__file__).resolve().relative_to(REPO)),
        "receipt runner path",
    )
    require_equal(sys.version.split()[0], "3.9.6", "running python")
    if "flatten" in SYNTH_SCRIPT or "flatten" in PREREG_DATA["cost_contract"][
        "synthesis_script"
    ]:
        raise StructuralValidationError("synthesis script must not flatten")

    predecessors = {}
    for relative, (schema, digest) in sorted(PREDECESSOR_DIGESTS.items()):
        receipt = json.loads((REPO / relative).read_text(encoding="utf-8"))
        payload = receipt["deterministic_payload"]
        require_equal(payload["schema"], schema, f"{relative} schema")
        require_equal(
            sha256_bytes(canonical_json_bytes(payload)),
            digest,
            f"{relative} recomputed digest",
        )
        require_equal(
            receipt.get("deterministic_payload_sha256"), digest, f"{relative} stored digest"
        )
        predecessors[relative] = digest

    versions = tool_versions()
    toolchain = PREREG_DATA["toolchain_contract"]
    if not versions["yosys"].startswith(toolchain["yosys_version_prefix"]):
        raise StructuralValidationError(f"yosys version drift: {versions['yosys']!r}")
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
        "predecessor_payload_digests": predecessors,
        "rtl": str(RTL.relative_to(REPO)),
        "rtl_sha256": sha256_file(RTL),
        "testbench": str(TESTBENCH.relative_to(REPO)),
        "testbench_sha256": sha256_file(TESTBENCH),
        "runner": str(Path(__file__).resolve().relative_to(REPO)),
        "runner_sha256": sha256_file(Path(__file__).resolve()),
        "aes_sbox_sha256": AES_SBOX_SHA256,
        "python": sys.version.split()[0],
        "yosys_version": versions["yosys"],
        "iverilog_version": versions["iverilog"],
    }


# ---------------------------------------------------------------------------
# Simulation and equivalence


def run_simulation(material: dict) -> List[str]:
    if SCRATCH.exists():
        shutil.rmtree(SCRATCH)
    SCRATCH.mkdir(parents=True, exist_ok=True)
    (SCRATCH / "material.hex").write_text(
        "".join(f"{value:02x}\n" for value in material["raw"]), encoding="utf-8"
    )

    binary = SCRATCH / "e256h_attack_core_tb.vvp"
    compile_process = subprocess.run(
        ["iverilog", "-g2012", "-o", str(binary), str(TESTBENCH), str(RTL)],
        capture_output=True,
        text=True,
        timeout=600,
        check=False,
        cwd=str(REPO),
    )
    if compile_process.returncode != 0:
        raise StructuralValidationError(
            f"iverilog compile failed: {compile_process.stderr.strip()[:600]}"
        )
    run_process = subprocess.run(
        ["vvp", str(binary)],
        capture_output=True,
        text=True,
        timeout=3600,
        check=False,
        cwd=str(REPO),
    )
    output = (run_process.stdout or "") + (run_process.stderr or "")
    if run_process.returncode != 0 or "E256H_ATTACK_TB DONE" not in output:
        raise StructuralValidationError(f"simulation failed: {output.strip()[-600:]}")
    results = (SCRATCH / "results.txt").read_text(encoding="utf-8").splitlines()
    if not results:
        raise StructuralValidationError("simulation produced no results")
    return results


def check_equivalence(results: List[str], material: dict) -> dict:
    integral_rows: Dict[Tuple[int, int], dict] = {}
    truncated_rows: Dict[Tuple[int, int], dict] = {}

    for line in results:
        parts = line.split()
        if parts[0] == "integral":
            defect, rounds, balanced = int(parts[1]), int(parts[2]), int(parts[3])
            integral_rows[(defect, rounds)] = {
                "balanced_bytes": balanced,
                "accumulator_hex": parts[4],
                "cycles": int(parts[5]),
            }
        elif parts[0] == "truncated":
            defect, rounds, active = int(parts[1]), int(parts[2]), int(parts[3])
            truncated_rows[(defect, rounds)] = {
                "active_bytes": active,
                "base_hex": parts[4],
                "diff_hex": parts[5],
            }
        else:
            raise StructuralValidationError(f"unknown result row: {parts[0]}")

    expected_keys = {
        (defect, rounds)
        for defect in DEFECT_CODES
        for rounds in range(1, MAX_ROUNDS + 1)
    }
    if set(integral_rows) != expected_keys or set(truncated_rows) != expected_keys:
        raise StructuralValidationError("simulation coverage does not match the contract")

    comparisons = 0
    mismatches: List[dict] = []
    for defect in DEFECT_CODES:
        for rounds in range(1, MAX_ROUNDS + 1):
            model_acc = model_integral(rounds, material, defect)
            row = integral_rows[(defect, rounds)]
            comparisons += 1
            if state_to_hex(model_acc) != row["accumulator_hex"] or row[
                "balanced_bytes"
            ] != sum(1 for v in model_acc if v == 0):
                mismatches.append(
                    {"arm": "integral", "defect": defect, "rounds": rounds}
                )

            base, diff, active = model_truncated(rounds, material, defect)
            trow = truncated_rows[(defect, rounds)]
            comparisons += 1
            if (
                state_to_hex(base) != trow["base_hex"]
                or state_to_hex(diff) != trow["diff_hex"]
                or active != trow["active_bytes"]
            ):
                mismatches.append(
                    {"arm": "truncated_differential", "defect": defect, "rounds": rounds}
                )

    expected = int(PREREG_DATA["control_execution_contract"]["expected_rtl_model_comparisons"])
    require_equal(comparisons, expected, "RTL/model comparison count")
    return {
        "expected_comparisons": expected,
        "executed_comparisons": comparisons,
        "mismatches": mismatches,
        "rtl_matches_model": not mismatches,
        "integral_rows": {f"{d}:{r}": v for (d, r), v in sorted(integral_rows.items())},
        "truncated_rows": {
            f"{d}:{r}": v for (d, r), v in sorted(truncated_rows.items())
        },
    }


# ---------------------------------------------------------------------------
# Cost measurement


def stat_sections(output: str) -> Dict[str, str]:
    return dict(
        re.findall(
            r"=== (\S+) ===\n(.*?)(?=\n=== |\nEnd of script|\Z)", output, re.DOTALL
        )
    )


def synthesize(module: str) -> dict:
    script = SYNTH_SCRIPT.format(rtl=str(RTL.relative_to(REPO)), module=module)
    process = subprocess.run(
        ["yosys", "-Q", "-p", script],
        capture_output=True,
        text=True,
        timeout=3600,
        check=False,
        cwd=str(REPO),
    )
    output = (process.stdout or "") + (process.stderr or "")
    if process.returncode != 0:
        raise StructuralValidationError(
            f"yosys failed for {module}: {output.strip()[-500:]}"
        )
    sections = stat_sections(output)
    if module not in sections:
        raise StructuralValidationError(f"no stat section for {module}")
    text = sections[module]

    def count(pattern: str) -> int:
        match = re.search(pattern, text, re.MULTILINE)
        return int(match.group(1)) if match else 0

    depth = 0
    depth_match = re.search(
        rf"Longest topological path in {re.escape(module)}[^(]*\(length=(\d+)\)", output
    )
    if depth_match:
        depth = int(depth_match.group(1))

    cell_types = {
        name: int(value)
        for value, name in re.findall(r"^\s*(\d+)\s+(\$[a-z0-9_]+)\s*$", text, re.M)
    }
    return {
        "module": module,
        "local_lut6": count(r"^\s*(\d+)\s+\$lut\s*$"),
        "local_cells": count(r"^\s*(\d+)\s+cells\s*$"),
        "flip_flops": sum(
            value for name, value in cell_types.items() if name.startswith("$_DFF")
        )
        or count(r"^\s*(\d+)\s+\$_DFF_P_\s*$"),
        "longest_topological_path": depth,
        "local_cell_types": cell_types,
    }


def measure_cost(equivalence: dict) -> dict:
    records = [synthesize(module) for module in COST_MODULES]
    sbox = synthesize("e256h_atk_sbox")
    cycles = {
        key: value["cycles"]
        for key, value in equivalence["integral_rows"].items()
        if key.startswith("0:")
    }
    return {
        "synthesis_script": SYNTH_SCRIPT.format(
            rtl=str(RTL.relative_to(REPO)), module="<module>"
        ),
        "modules": records,
        "shared_sbox": sbox,
        "measured_integral_cycles_candidate": cycles,
        "explicit_limitation": PREREG_DATA["cost_contract"]["explicit_limitation"],
    }


# ---------------------------------------------------------------------------
# Grading


def grade(equivalence: dict, material: dict) -> dict:
    integral = equivalence["integral_rows"]
    truncated = equivalence["truncated_rows"]

    identity_balanced = [
        integral[f"1:{r}"]["balanced_bytes"] for r in range(1, MAX_ROUNDS + 1)
    ]
    nodiff_active = [
        truncated[f"2:{r}"]["active_bytes"] for r in range(1, MAX_ROUNDS + 1)
    ]
    candidate_balanced = [
        integral[f"0:{r}"]["balanced_bytes"] for r in range(1, MAX_ROUNDS + 1)
    ]
    candidate_active = [
        truncated[f"0:{r}"]["active_bytes"] for r in range(1, MAX_ROUNDS + 1)
    ]

    surviving_rounds = [
        r for r in range(1, MAX_ROUNDS + 1) if candidate_balanced[r - 1] == 32
    ]
    max_surviving = max(surviving_rounds) if surviving_rounds else 0
    first_full_active = next(
        (r for r in range(1, MAX_ROUNDS + 1) if candidate_active[r - 1] == 32), None
    )

    outcomes = {
        "A1": {
            "role": "validity_control",
            "statement": "identity_rotor defect recovered by the integral arm at every round",
            "observed": identity_balanced,
            "pass": all(value == 32 for value in identity_balanced),
        },
        "A2": {
            "role": "validity_control",
            "statement": "no_diffusion defect recovered by the truncated arm at every round",
            "observed": nodiff_active,
            "pass": all(value == 1 for value in nodiff_active),
        },
        "A3": {
            "role": "validity_control",
            "statement": "every RTL value matches the independent software model",
            "observed": {
                "comparisons": equivalence["executed_comparisons"],
                "mismatches": len(equivalence["mismatches"]),
            },
            "pass": equivalence["rtl_matches_model"],
        },
        "A4": {
            "role": "graded_finding",
            "statement": "candidate integral survives at least 3 rounds and then dies",
            "observed": {
                "balanced_bytes_by_round": candidate_balanced,
                "max_surviving_round": max_surviving,
                "dies_at_round": max_surviving + 1 if max_surviving < MAX_ROUNDS else None,
            },
            "pass": max_surviving >= 3 and max_surviving < MAX_ROUNDS,
        },
        "A5": {
            "role": "graded_finding",
            "statement": "candidate truncated differential reaches all 32 bytes by round 3",
            "observed": {
                "active_bytes_by_round": candidate_active,
                "first_full_round": first_full_active,
            },
            "pass": first_full_active is not None and first_full_active <= 3,
        },
        "A6": {
            "role": "graded_finding",
            "statement": "attack cost reported in LUT6, cells, depth, and measured cycles",
            "observed": "see cost section",
            "pass": True,
        },
    }
    require_equal(tuple(outcomes), PREDICTION_IDS, "graded prediction IDs")
    validity_ids = tuple(
        item["id"] for item in PREREG_DATA["predictions"]
        if item["role"] == "validity_control"
    )
    require_equal(validity_ids, ("A1", "A2", "A3"), "validity control IDs")
    return {
        "outcomes": outcomes,
        "validity_control_ids": list(validity_ids),
        "validity_controls_pass": all(outcomes[pid]["pass"] for pid in validity_ids),
        "candidate_integral_balanced_by_round": candidate_balanced,
        "candidate_active_bytes_by_round": candidate_active,
        "max_surviving_integral_round": max_surviving,
        "first_full_diffusion_round": first_full_active,
    }


def build_receipt() -> dict:
    started = time.perf_counter()
    inputs = validate_frozen_inputs()
    material = derive_material()
    results = run_simulation(material)
    equivalence = check_equivalence(results, material)
    grading = grade(equivalence, material)
    cost = measure_cost(equivalence)

    defects = {
        "frozen_ids": list(DEFECT_MODES),
        "frozen_codes": list(DEFECT_CODES),
        "shared_netlist": True,
        "records": {
            "identity_rotor": {
                "arm": "integral",
                "detector": "integral balance survives at every tested round count",
                "observed_balanced_bytes_by_round": grading["outcomes"]["A1"]["observed"],
                "detected": grading["outcomes"]["A1"]["pass"],
            },
            "no_diffusion": {
                "arm": "truncated_differential",
                "detector": "exactly one active output byte at every tested round count",
                "observed_active_bytes_by_round": grading["outcomes"]["A2"]["observed"],
                "detected": grading["outcomes"]["A2"]["pass"],
            },
        },
    }
    defects["all_detected"] = all(
        record["detected"] for record in defects["records"].values()
    )

    validity_checks = {
        "frozen_contract_validated": True,
        "defect_modes_exact": tuple(DEFECT_CODES) == (0, 1, 2),
        "all_planted_defects_recovered": defects["all_detected"],
        "rtl_matches_model": equivalence["rtl_matches_model"],
        "validity_controls_pass": grading["validity_controls_pass"],
    }
    harness_valid = all(validity_checks.values())

    found = grading["max_surviving_integral_round"] > 0
    verdict = (
        "HARDWARE_ATTACK_LANE_CALIBRATED_REDUCED_ROUND_DISTINGUISHER_FOUND"
        if found
        else "HARDWARE_ATTACK_LANE_CALIBRATED_NO_DISTINGUISHER_FOUND"
    )

    squeeze_blocks = math.ceil(MATERIAL_BYTES / 136)

    deterministic_payload = {
        "schema": PREREG_DATA["receipt_contract"]["schema"],
        "status": PREREG_DATA["receipt_contract"]["status"],
        "inputs": inputs,
        "pinned_parameters": {
            "graded_constraints": list(
                PREREG_DATA["authorization"]["graded_constraints"]
            ),
            "target_identity": TARGET["identity"],
            "rotor": TARGET["rotor"],
            "row_offsets": list(ROW_OFFSETS),
            "row_offsets_provenance": TARGET["row_offsets_provenance"],
            "mix_columns_matrix_hex_rows": [
                list(row) for row in TARGET["mix_columns_matrix_hex_rows"]
            ],
            "max_rounds_tested": MAX_ROUNDS,
            "material_bytes": MATERIAL_BYTES,
            "material_sha256": sha256_bytes(material["raw"]),
            "material_shake256_squeeze_blocks": squeeze_blocks,
            "material_note": TARGET["material"]["note_on_h5_block_size"],
            "attack_arms": list(ARM_IDS),
            "defect_modes": list(DEFECT_MODES),
            "prediction_ids": list(PREDICTION_IDS),
            "exploratory_probe_disclosure": PREREG_DATA[
                "exploratory_probe_disclosure"
            ],
            "framing": PREREG_DATA["framing"],
        },
        "coverage": {
            "defect_modes": len(DEFECT_CODES),
            "rounds_per_mode": MAX_ROUNDS,
            "integral_runs": len(DEFECT_CODES) * MAX_ROUNDS,
            "integral_plaintexts_per_run": 256,
            "truncated_runs": len(DEFECT_CODES) * MAX_ROUNDS,
            "rtl_model_comparisons": equivalence["executed_comparisons"],
            "modules_synthesized": len(COST_MODULES) + 1,
        },
        "equivalence": equivalence,
        "defects": defects,
        "results": grading,
        "cost": cost,
        "interpretation": {
            "harness_validity_checks": validity_checks,
            "harness_valid": harness_valid,
            "internal_invalid_status": PREREG_DATA["interpretation"][
                "internal_invalid_status"
            ],
            "verdict": verdict if harness_valid else "INVALID_ATTACK_HARNESS",
            "reduced_round_integral_reach": grading["max_surviving_integral_round"],
            "integral_dies_at_round": (
                grading["max_surviving_integral_round"] + 1
                if grading["max_surviving_integral_round"] < MAX_ROUNDS
                else None
            ),
            "production_round_count": None,
            "search_not_cipher": PREREG_DATA["framing"]["primary_claim_direction"],
            "scope": PREREG_DATA["interpretation"]["scope"],
            "next": PREREG_DATA["interpretation"]["next"],
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
    results = payload["results"]
    outcomes = results["outcomes"]
    print("=" * 78)
    print("E256-H HARDWARE ATTACK LANE  (OPEN_PROGRESS)")
    print("=" * 78)
    print(f"harness valid: {payload['interpretation']['harness_valid']}")
    print(
        f"planted defects recovered: {payload['defects']['all_detected']} "
        f"(identity_rotor via integral, no_diffusion via truncated)"
    )
    print(
        f"RTL vs model: {payload['equivalence']['executed_comparisons']} comparisons, "
        f"{len(payload['equivalence']['mismatches'])} mismatches"
    )
    print(f"candidate integral balanced bytes by round: {results['candidate_integral_balanced_by_round']}")
    print(f"candidate active bytes by round:            {results['candidate_active_bytes_by_round']}")
    print(
        f"integral reach: {results['max_surviving_integral_round']} rounds; "
        f"first full diffusion at round {results['first_full_diffusion_round']}"
    )
    print(f"{'module':<22}{'LUT6':>8}{'cells':>8}{'depth':>7}")
    for record in payload["cost"]["modules"]:
        print(
            f"{record['module']:<22}{record['local_lut6']:>8}"
            f"{record['local_cells']:>8}{record['longest_topological_path']:>7}"
        )
    print(f"shared sbox LUT6: {payload['cost']['shared_sbox']['local_lut6']}")
    print(f"integral cycles (candidate): {payload['cost']['measured_integral_cycles_candidate']}")
    for pid in sorted(outcomes):
        print(f"{pid} [{outcomes[pid]['role']}]: {outcomes[pid]['pass']}")
    print(f"verdict: {payload['interpretation']['verdict']}")
    print("NOTE: this grades the search, not the cipher")
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
        print(f"ATTACK GATE FAILED: {error}", file=sys.stderr)
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
        "STATUS: OPEN_PROGRESS; no claim, suite, profile, fixture, release gate, or "
        "round count moved; absence of a distinguisher would not be a security result"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
