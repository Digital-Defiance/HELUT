#!/usr/bin/env python3
"""Validate an accepted native-NLFF receipt and emit frozen profile artifacts."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Dict, List, Sequence


FIXTURE_SCHEMA_VERSION = 4
LFSR_TRANSITION = "right_shift_lsb_galois_d800000000000000"
UPDATE_ORDER = "derive_prestep_mask_and_counter_mask_scramble_then_step_and_increment"
CENTER_CONSTRUCTION = "conjugated_xor_counter_prf_v1"
CENTER_MASK_KEY_KDF = "hkdf_sha512_nonce_salt_32_v1"
CENTER_MASK_PRF = "hmac_sha256_32_byte_blocks_v1"
CENTER_MASK_KEY_DOMAIN = "center-mask-key"
CENTER_MASK_BLOCK_DOMAIN = "center-mask-block"
CENTER_MASK_COUNTER = "uint64_be_block_counter_start_0"
CENTER_MASK_EXTRACTION = "digest_byte_i_mod_32_allow_zero"
CENTER_MAP_ORDER = "plugboard_forward_rotors_xor_mask_reverse_rotors_plugboard_v1"
RECEIPT_TRANSITION = "(state >> 1) xor (lsb ? 0xD800000000000000 : 0)"


def evaluate_component(component: Dict[str, object]) -> int:
    truth = 0
    gates = component["gates"]
    output = int(component["output"])
    for assignment in range(128):
        wires = [(assignment >> bit) & 1 for bit in range(7)]
        for gate in gates:
            target = int(gate["target"])
            controls = [int(value) for value in gate["controls"]]
            term = 1
            for control in controls:
                term &= wires[control]
            wires[target] ^= term
        truth |= wires[output] << assignment
    return truth


def validate(receipt: Dict[str, object]) -> None:
    if receipt.get("schema") != "E256-NATIVE-NLFF-SEARCH-1":
        raise ValueError("unsupported receipt schema")
    if receipt.get("family") != "E256" or receipt.get("suite_version") != 2:
        raise ValueError("receipt family/suite mismatch")
    if receipt.get("generation") != 0:
        raise ValueError("only E256-v2/gen0 can be promoted by this emitter")
    if receipt.get("transition") != RECEIPT_TRANSITION:
        raise ValueError("receipt transition mismatch")
    if receipt.get("formula") != "dual_balanced_reversible_nlff16":
        raise ValueError("receipt formula mismatch")
    if receipt.get("status") != "ACCEPTED_RESEARCH_PROFILE":
        raise ValueError("receipt is not an accepted research profile")
    if not receipt.get("positive_control", {}).get("detected"):
        raise ValueError("positive control did not detect the weak profile")
    if not receipt.get("train", {}).get("accepted") or not receipt.get("holdout", {}).get("accepted"):
        raise ValueError("train or holdout grade failed")

    components = receipt.get("components", [])
    folds = receipt.get("folds", [])
    if len(components) != 8 or len(folds) != 4:
        raise ValueError("expected eight components and four folds")
    for index, component in enumerate(components):
        truth_hex = str(component["truth_hex"])
        if len(truth_hex) != 32:
            raise ValueError("component %d truth table must be 128 bits" % index)
        expected = int(truth_hex, 16)
        actual = evaluate_component(component)
        if actual != expected:
            raise ValueError("component %d gate network disagrees with truth table" % index)
        if bin(expected).count("1") != 64:
            raise ValueError("component %d truth table is not balanced" % index)
        if not component.get("grade", {}).get("accepted"):
            raise ValueError("component %d grade is not accepted" % index)

    taps = [int(tap) for fold in folds for tap in fold["taps"]]
    if sorted(taps) != list(range(64)):
        raise ValueError("fold taps must partition all 64 state bits")
    for index, fold in enumerate(folds):
        if len(fold["taps"]) != 16:
            raise ValueError("fold %d must have sixteen taps" % index)
        if int(fold["left_component"]) != index * 2 or int(fold["right_component"]) != index * 2 + 1:
            raise ValueError("unexpected component assignment")


def emit_component(index: int, component: Dict[str, object], taps: Sequence[int]) -> List[str]:
    current = ["lfsr[%d]" % tap for tap in taps]
    lines: List[str] = []
    for gate_index, gate in enumerate(component["gates"]):
        target = int(gate["target"])
        controls = [int(value) for value in gate["controls"]]
        term = " & ".join("(%s)" % current[control] for control in controls)
        name = "e256_nlff_c%d_g%d" % (index, gate_index)
        lines.append("wire %s = (%s) ^ (%s);" % (name, current[target], term))
        current[target] = name
    output = int(component["output"])
    lines.append("wire e256_nlff_c%d = %s;" % (index, current[output]))
    return lines


def canonical_profile(profile: Dict[str, object]) -> bytes:
    component_text = ",".join(str(component["truth_hex"]) for component in profile["components"])
    fold_text = ",".join(
        "%s:%d:%d"
        % (
            ".".join(str(int(tap)) for tap in fold["taps"]),
            int(fold["left_component"]),
            int(fold["right_component"]),
        )
        for fold in profile["folds"]
    )
    fields = [
        str(profile["family"]),
        str(profile["suite_version"]),
        str(profile["generation"]),
        str(profile["fixture_schema_version"]),
        str(profile["lfsr_transition"]),
        str(profile["update_order"]),
        str(profile["center_construction"]),
        str(profile["center_mask_key_kdf"]),
        str(profile["center_mask_prf"]),
        str(profile["center_mask_key_domain"]),
        str(profile["center_mask_block_domain"]),
        str(profile["center_mask_counter"]),
        str(profile["center_mask_extraction"]),
        str(profile["center_map_order"]),
        str(profile["formula"]),
        component_text,
        fold_text,
    ]
    return "|".join(fields).encode("utf-8")


def concise_profile(receipt: Dict[str, object], receipt_path: str, digest: str) -> Dict[str, object]:
    profile: Dict[str, object] = {
        "family": "E256",
        "suite_version": 2,
        "generation": 0,
        "fixture_schema_version": FIXTURE_SCHEMA_VERSION,
        "lfsr_transition": LFSR_TRANSITION,
        "update_order": UPDATE_ORDER,
        "center_construction": CENTER_CONSTRUCTION,
        "center_mask_key_kdf": CENTER_MASK_KEY_KDF,
        "center_mask_prf": CENTER_MASK_PRF,
        "center_mask_key_domain": CENTER_MASK_KEY_DOMAIN,
        "center_mask_block_domain": CENTER_MASK_BLOCK_DOMAIN,
        "center_mask_counter": CENTER_MASK_COUNTER,
        "center_mask_extraction": CENTER_MASK_EXTRACTION,
        "center_map_order": CENTER_MAP_ORDER,
        "formula": "native_reversible_16",
        "components": [
            {"truth_hex": component["truth_hex"]}
            for component in receipt["components"]
        ],
        "folds": receipt["folds"],
        "research_status": "accepted_bounded_profile",
        "receipt": receipt_path,
        "receipt_sha256": digest,
    }
    profile["profile_sha256"] = hashlib.sha256(canonical_profile(profile)).hexdigest()
    return profile


def verilog_include(receipt: Dict[str, object], receipt_digest: str, profile_digest: str) -> str:
    lines = [
        "// Auto-generated by Scripts/e256_nlff_emit.py.",
        "// E256-v2/gen0 native reversible NLFF research profile.",
        "// Profile SHA-256: %s" % profile_digest,
        "// Receipt SHA-256: %s" % receipt_digest,
        "// Do not hand-edit; regenerate from logs/e256-v2-gen0-nlff-search.json.",
        "",
    ]
    components = receipt["components"]
    folds = receipt["folds"]
    for component_index, component in enumerate(components):
        fold = folds[component_index // 2]
        all_taps = [int(value) for value in fold["taps"]]
        local_taps = all_taps[1:8] if component_index % 2 == 0 else all_taps[9:16]
        lines.append("// Component %d: seven-wire reversible XOR/Toffoli network." % component_index)
        lines.extend(emit_component(component_index, component, local_taps))
        lines.append("")
    for fold_index, fold in enumerate(folds):
        taps = [int(value) for value in fold["taps"]]
        lines.append(
            "wire e256_nlff_step_r%d = lfsr[%d] ^ e256_nlff_c%d ^ lfsr[%d] ^ e256_nlff_c%d;"
            % (fold_index + 1, taps[0], fold_index * 2, taps[8], fold_index * 2 + 1)
        )
    return "\n".join(lines) + "\n"


def write_atomic(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(text, encoding="utf-8")
    temporary.replace(path)


def check_exact(path: Path, expected: str) -> None:
    if not path.exists():
        raise ValueError("missing generated artifact: %s" % path)
    if path.read_text(encoding="utf-8") != expected:
        raise ValueError("stale generated artifact: %s" % path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--receipt", default="logs/e256-v2-gen0-nlff-search.json")
    parser.add_argument("--verilog-out")
    parser.add_argument("--profile-out")
    parser.add_argument("--check", action="store_true", help="verify outputs byte-for-byte without rewriting")
    args = parser.parse_args()

    receipt_path = Path(args.receipt)
    receipt_bytes = receipt_path.read_bytes()
    receipt = json.loads(receipt_bytes.decode("utf-8"))
    validate(receipt)
    receipt_digest = hashlib.sha256(receipt_bytes).hexdigest()
    profile = concise_profile(receipt, args.receipt, receipt_digest)
    profile_digest = str(profile["profile_sha256"])
    verilog_text = verilog_include(receipt, receipt_digest, profile_digest)
    profile_text = json.dumps(profile, indent=2, sort_keys=True) + "\n"

    canonical_verilog = Path("Generated/Profiles/Enigma256/enigma_256_nlff_v2.vh")
    canonical_profile = Path("Fixtures/enigma256_generation.json")
    scratch_verilog = Path("build/hardware/Profiles/Enigma256/enigma_256_nlff_v2.vh")
    scratch_profile = Path("build/hardware/Profiles/Enigma256/enigma256_generation.json")
    verilog_path = Path(
        args.verilog_out
        or (canonical_verilog if args.check else scratch_verilog)
    )
    profile_path = Path(
        args.profile_out
        or (canonical_profile if args.check else scratch_profile)
    )
    if args.check:
        check_exact(verilog_path, verilog_text)
        check_exact(profile_path, profile_text)
        print("generated artifacts are current")
    else:
        write_atomic(verilog_path, verilog_text)
        write_atomic(profile_path, profile_text)
        print("verilog include:", verilog_path)
        print("profile:", profile_path)

    print("validated receipt:", args.receipt)
    print("receipt sha256:", receipt_digest)
    print("profile sha256:", profile_digest)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
