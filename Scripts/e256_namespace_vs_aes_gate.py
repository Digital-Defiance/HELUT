#!/usr/bin/env python3
"""Keyed H4 namespace versus a fixed-AES twin, on one integral.

Contract: directives/e256-namespace-vs-aes-preregistration.json
Receipt:  logs/e256-namespace-vs-aes-gate.json

The namespace beats the twin only when the integral dies strictly earlier on
the candidate. Equal reach is a failure. This is not a round-count selection
and not a security claim.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Dict, List, Sequence, Tuple

REPO = Path(__file__).resolve().parent.parent
PREREG = REPO / "directives/e256-namespace-vs-aes-preregistration.json"
RECEIPT = REPO / "logs/e256-namespace-vs-aes-gate.json"
PREREG_SHA256 = "90c5ae3fbd4af29e37777792856ae43f5e52fadc3774977eeb7c02a89f3090b4"
AES_SBOX_SHA256 = "c2d8e5eed6cbebd8625fc18f81486a7733c04f9b0129ffbe974c68b90308b4f2"

PREREG_DATA = json.loads(PREREG.read_text(encoding="utf-8"))
SHARED = PREREG_DATA["machines"]["shared"]
TWIN = PREREG_DATA["machines"]["twin"]
CANDIDATE = PREREG_DATA["machines"]["candidate"]
ROUNDS = tuple(int(r) for r in SHARED["rounds_tested"])
MIX_ROWS = tuple(
    tuple(int(value, 16) for value in row) for row in SHARED["mix_columns_matrix_hex_rows"]
)
CATALOG = tuple(tuple(int(v) for v in row) for row in CANDIDATE["catalog"])
TWIN_OFFSETS = tuple(int(v) for v in TWIN["row_offsets_every_round"])
MONO = tuple(int(v) for v in PREREG_DATA["planted_controls"][1]["tuple"])


class GateError(RuntimeError):
    pass


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def require_equal(actual, expected, label: str) -> None:
    if actual != expected:
        raise GateError(f"{label} mismatch: expected {expected!r}, got {actual!r}")


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
    require_equal(sha256_bytes(bytes(table)), AES_SBOX_SHA256, "AES S-box")
    return table


AES_SBOX = build_aes_sbox()


def masks() -> List[List[int]]:
    raw = hashlib.shake_256(SHARED["material_domain"].encode("ascii")).digest(13 * 32)
    return [[raw[m * 32 + i] for i in range(32)] for m in range(13)]


def schedule() -> Tuple[Tuple[int, int, int, int], ...]:
    domain = CANDIDATE["selection_domain"].encode("ascii")
    chosen = []
    for round_index in range(max(ROUNDS)):
        digest = hashlib.shake_256(domain + b"\x00" + bytes([round_index])).digest(1)
        chosen.append(CATALOG[digest[0] % len(CATALOG)])
    return tuple(chosen)


def row_shift(state: Sequence[int], offsets: Sequence[int]) -> List[int]:
    out = [0] * 32
    for column in range(8):
        for row in range(4):
            out[4 * column + row] = state[4 * ((column + offsets[row]) % 8) + row]
    return out


def mix_columns(state: Sequence[int]) -> List[int]:
    out = [0] * 32
    for column in range(8):
        for row in range(4):
            acc = 0
            for k in range(4):
                acc ^= gf_mul(MIX_ROWS[row][k], state[4 * column + k])
            out[4 * column + row] = acc
    return out


def permute(
    block: Sequence[int],
    rounds: int,
    round_offsets: Sequence[Sequence[int]],
    mask_blocks: Sequence[Sequence[int]],
    identity_rotor: bool,
) -> List[int]:
    state = [block[i] ^ mask_blocks[0][i] for i in range(32)]
    for round_index in range(rounds):
        if identity_rotor:
            shifted = list(state)
        else:
            shifted = [AES_SBOX[state[j]] for j in range(32)]
        shifted = row_shift(shifted, round_offsets[round_index])
        shifted = mix_columns(shifted)
        state = [shifted[i] ^ mask_blocks[round_index + 1][i] for i in range(32)]
    return state


def integral(
    rounds: int,
    round_offsets: Sequence[Sequence[int]],
    mask_blocks: Sequence[Sequence[int]],
    identity_rotor: bool = False,
) -> int:
    acc = [0] * 32
    for value in range(256):
        block = [0] * 32
        block[0] = value
        out = permute(block, rounds, round_offsets, mask_blocks, identity_rotor)
        for index in range(32):
            acc[index] ^= out[index]
    return sum(1 for lane in acc if lane == 0)


def surviving(round_offsets: Sequence[Sequence[int]], mask_blocks, identity_rotor: bool = False) -> int:
    last = 0
    for rounds in ROUNDS:
        if integral(rounds, round_offsets, mask_blocks, identity_rotor) == 32:
            last = rounds
        else:
            break
    return last


def all_to_all(offsets: Sequence[int], rounds: int) -> bool:
    """One-bit structural probe: every output lane moves when every input lane flips."""
    zero_masks = [[0] * 32 for _ in range(rounds + 1)]
    base = permute([0] * 32, rounds, [offsets] * rounds, zero_masks, False)
    for lane in range(32):
        block = [0] * 32
        block[lane] = 1
        out = permute(block, rounds, [offsets] * rounds, zero_masks, False)
        if any(out[i] == base[i] for i in range(32)):
            return False
    return True


def deterministic_payload(results: dict) -> dict:
    return {
        "schema": "E256-NAMESPACE-VS-AES-GATE-1",
        "prereg_sha256": PREREG_SHA256,
        "twin_surviving_rounds": results["twin_surviving_rounds"],
        "candidate_surviving_rounds": results["candidate_surviving_rounds"],
        "candidate_schedule": results["candidate_schedule"],
        "identity_rotor_surviving_rounds": results["identity_rotor_surviving_rounds"],
        "mono_parity_all_to_all_by_round_12": results["mono_parity_all_to_all_by_round_12"],
        "verdict": results["verdict"],
    }


def run() -> dict:
    require_equal(sha256_bytes(PREREG.read_bytes()), PREREG_SHA256, "preregistration")
    require_equal(TWIN_OFFSETS, (0, 1, 3, 4), "twin wiring")
    mask_blocks = masks()
    chosen = schedule()
    twin_offsets = [TWIN_OFFSETS for _ in range(max(ROUNDS))]
    twin_surviving = surviving(twin_offsets, mask_blocks)
    candidate_surviving = surviving(chosen, mask_blocks)
    identity_surviving = surviving(chosen, mask_blocks, identity_rotor=True)
    mono_mixes = all_to_all(MONO, 12)
    if identity_surviving != max(ROUNDS):
        raise GateError("identity-rotor control was quiet; integral is uncalibrated")
    if mono_mixes:
        raise GateError("mono-parity wiring was not detected")
    if candidate_surviving < twin_surviving:
        verdict = "NAMESPACE_BEATS_TWIN_ON_THIS_INTEGRAL"
    else:
        verdict = "NAMESPACE_FAILS_ON_THIS_INTEGRAL"
    return {
        "twin_surviving_rounds": twin_surviving,
        "candidate_surviving_rounds": candidate_surviving,
        "candidate_schedule": [list(item) for item in chosen],
        "identity_rotor_surviving_rounds": identity_surviving,
        "mono_parity_all_to_all_by_round_12": mono_mixes,
        "verdict": verdict,
        "twin_balanced_by_round": [
            integral(r, twin_offsets, mask_blocks) for r in ROUNDS
        ],
        "candidate_balanced_by_round": [
            integral(r, chosen, mask_blocks) for r in ROUNDS
        ],
    }


def receipt_document(results: dict) -> dict:
    payload = deterministic_payload(results)
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("ascii")
    return {
        "schema": "E256-NAMESPACE-VS-AES-GATE-1",
        "status": "OPEN_PROGRESS",
        "preregistration": str(PREREG.relative_to(REPO)),
        "preregistration_sha256": PREREG_SHA256,
        "deterministic_payload_sha256": sha256_bytes(encoded),
        "deterministic_payload": payload,
        "measured": {
            "twin_balanced_by_round": results["twin_balanced_by_round"],
            "candidate_balanced_by_round": results["candidate_balanced_by_round"],
        },
        "scope": (
            "One integral, rounds 1..8, one key label, three-tuple catalog. "
            "Not the attack matrix. Not a round-count selection. Not a security result."
        ),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.check:
        if not RECEIPT.exists():
            raise GateError("receipt missing")
        document = json.loads(RECEIPT.read_text(encoding="utf-8"))
        payload = document["deterministic_payload"]
        encoded = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("ascii")
        require_equal(sha256_bytes(encoded), document["deterministic_payload_sha256"], "payload")
        require_equal(document["preregistration_sha256"], PREREG_SHA256, "prereg hash")
        print("CHECK PASS")
        return
    results = run()
    document = receipt_document(results)
    RECEIPT.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
    print(results["verdict"])
    print(f"twin surviving rounds: {results['twin_surviving_rounds']}")
    print(f"candidate surviving rounds: {results['candidate_surviving_rounds']}")
    print(f"twin balanced by round: {results['twin_balanced_by_round']}")
    print(f"candidate balanced by round: {results['candidate_balanced_by_round']}")
    print(f"identity rotor surviving: {results['identity_rotor_surviving_rounds']}")
    print(f"receipt: {RECEIPT.relative_to(REPO)}")


if __name__ == "__main__":
    try:
        main()
    except GateError as exc:
        raise SystemExit(f"ABORT — {exc}")
