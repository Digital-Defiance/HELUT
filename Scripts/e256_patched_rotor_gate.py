#!/usr/bin/env python3
"""One 8-bit rotor that closes the Enigma rotor holes, measured against AES.

Contract: directives/e256-patched-rotor-preregistration.json
Receipt:  logs/e256-patched-rotor-gate.json

The selected map is a research rotor. It does not replace the AES S-box.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from typing import Dict, List, Sequence, Tuple

REPO = Path(__file__).resolve().parent.parent
PREREG = REPO / "directives/e256-patched-rotor-preregistration.json"
RECEIPT = REPO / "logs/e256-patched-rotor-gate.json"
PREREG_SHA256 = "fb779d447d462f6a700a3ae2ebc04cb7b03cfc58126cecca457cf14379c08cf7"
AES_SBOX_SHA256 = "c2d8e5eed6cbebd8625fc18f81486a7733c04f9b0129ffbe974c68b90308b4f2"


class GateError(RuntimeError):
    pass


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def require_equal(actual, expected, label: str) -> None:
    if actual != expected:
        raise GateError(f"{label} mismatch: expected {expected!r}, got {actual!r}")


def gf_mul(a: int, b: int, poly: int, overflow: int) -> int:
    result = 0
    mask = overflow - 1
    while b:
        if b & 1:
            result ^= a
        a <<= 1
        if a & overflow:
            a ^= poly
        a &= mask
        b >>= 1
    return result


def gf_pow(a: int, exponent: int, poly: int, overflow: int) -> int:
    result = 1
    while exponent:
        if exponent & 1:
            result = gf_mul(result, a, poly, overflow)
        a = gf_mul(a, a, poly, overflow)
        exponent >>= 1
    return result


def rol8(value: int, amount: int) -> int:
    return ((value << amount) | (value >> (8 - amount))) & 0xFF


def build_aes_sbox() -> Tuple[int, ...]:
    values = []
    for value in range(256):
        inverse = 0 if value == 0 else gf_pow(value, 254, 0x11B, 0x100)
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


def power_map(exponent: int) -> Tuple[int, ...]:
    return tuple(0 if value == 0 else gf_pow(value, exponent, 0x11B, 0x100) for value in range(256))


def nibble_inv(value: int) -> int:
    return 0 if value == 0 else gf_pow(value, 14, 0x13, 0x10)


def feistel_map() -> Tuple[int, ...]:
    table = []
    for value in range(256):
        left, right = value >> 4, value & 0x0F
        for _ in range(4):
            left, right = right, left ^ nibble_inv(right)
        table.append((left << 4) | right)
    return tuple(table)


def ddt_histogram(table: Sequence[int]) -> Tuple[int, Tuple[int, ...]]:
    hist = [0] * 257
    peak = 0
    for dx in range(1, 256):
        counts = [0] * 256
        for x in range(256):
            counts[table[x] ^ table[x ^ dx]] += 1
        for count in counts:
            hist[count] += 1
            if count > peak:
                peak = count
    return peak, tuple(hist)


def walsh_peak(table: Sequence[int]) -> int:
    peak = 0
    for out_mask in range(1, 256):
        for in_mask in range(256):
            total = 0
            for x in range(256):
                bit = (in_mask & x) ^ (out_mask & table[x])
                bit ^= bit >> 4
                bit ^= bit >> 2
                bit ^= bit >> 1
                total += -1 if (bit & 1) else 1
            if abs(total) > peak:
                peak = abs(total)
    return peak


def algebraic_degree(table: Sequence[int]) -> int:
    best = 0
    for bit in range(8):
        anf = [((table[x] >> bit) & 1) for x in range(256)]
        for i in range(8):
            step = 1 << i
            for mask in range(256):
                if mask & step:
                    anf[mask] ^= anf[mask ^ step]
        for mask, coeff in enumerate(anf):
            if coeff:
                best = max(best, bin(mask).count("1"))
    return best


def is_involution(table: Sequence[int]) -> bool:
    return all(table[table[x]] == x for x in range(256))


def is_translation(table: Sequence[int]) -> bool:
    delta = table[0]
    return all(table[x] == (x ^ delta) for x in range(256))


def is_bijection(table: Sequence[int]) -> bool:
    return len(set(table)) == 256


AES_SBOX = build_aes_sbox()
MIX_ROWS = ((0x02, 0x03, 0x01, 0x01), (0x01, 0x02, 0x03, 0x01), (0x01, 0x01, 0x02, 0x03), (0x03, 0x01, 0x01, 0x02))


def row_shift(state: Sequence[int]) -> List[int]:
    offsets = (0, 1, 3, 4)
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
                acc ^= gf_mul(MIX_ROWS[row][k], state[4 * column + k], 0x11B, 0x100)
            out[4 * column + row] = acc
    return out


def permute(block: Sequence[int], rounds: int, sbox: Sequence[int], masks: Sequence[Sequence[int]]) -> List[int]:
    state = [block[i] ^ masks[0][i] for i in range(32)]
    for round_index in range(rounds):
        state = [sbox[state[j]] for j in range(32)]
        state = row_shift(state)
        state = mix_columns(state)
        state = [state[i] ^ masks[round_index + 1][i] for i in range(32)]
    return state


def integral_surviving(sbox: Sequence[int]) -> int:
    raw = hashlib.shake_256(b"E256-H/patched-rotor/integral/v1").digest(9 * 32)
    masks = [[raw[m * 32 + i] for i in range(32)] for m in range(9)]
    last = 0
    for rounds in range(1, 9):
        acc = [0] * 32
        for value in range(256):
            block = [0] * 32
            block[0] = value
            out = permute(block, rounds, sbox, masks)
            for index in range(32):
                acc[index] ^= out[index]
        if all(lane == 0 for lane in acc):
            last = rounds
        else:
            break
    return last


def spectrum(table: Sequence[int]) -> dict:
    peak, hist = ddt_histogram(table)
    return {
        "differential_peak": peak,
        "walsh_peak": walsh_peak(table),
        "algebraic_degree": algebraic_degree(table),
        "ddt_histogram": hist,
    }


def run() -> dict:
    require_equal(sha256_bytes(PREREG.read_bytes()), PREREG_SHA256, "preregistration")
    inverse = power_map(254)
    inverse_hist = ddt_histogram(inverse)[1]
    aes_hist = ddt_histogram(AES_SBOX)[1]
    require_equal(aes_hist, inverse_hist, "AES and inverse DDT histograms")

    pool: List[Tuple[str, Tuple[int, ...]]] = []
    for exponent in range(1, 255):
        if math.gcd(exponent, 255) != 1:
            continue
        pool.append((f"power:{exponent}", power_map(exponent)))
    pool.append(("feistel4:gf16-inv", feistel_map()))

    ranked = []
    for name, table in pool:
        if not is_bijection(table):
            raise GateError(f"{name} is not bijective")
        peak, hist = ddt_histogram(table)
        if hist == inverse_hist:
            continue
        ranked.append((peak, name, table, hist))
    if not ranked:
        raise GateError("no rotor outside the inverse DDT class")
    ranked.sort(key=lambda item: item[0])
    shortlist = [item for item in ranked if item[0] == ranked[0][0]]
    scored = []
    for peak, name, table, hist in shortlist:
        walsh = walsh_peak(table)
        degree = algebraic_degree(table)
        scored.append((peak, walsh, -degree, name, table, hist, degree))
    scored.sort()
    peak, walsh, neg_degree, name, table, hist, degree = scored[0]
    if is_involution(table) or is_translation(table):
        raise GateError("selected rotor is an involution or a translation")
    twin_reach = integral_surviving(AES_SBOX)
    rotor_reach = integral_surviving(table)
    return {
        "rotor_id": name,
        "differential_peak": peak,
        "walsh_peak": walsh,
        "algebraic_degree": degree,
        "bijective": True,
        "involution": False,
        "translation": False,
        "ddt_histogram_equals_inverse": False,
        "integral_surviving_rounds_rotor": rotor_reach,
        "integral_surviving_rounds_aes_twin": twin_reach,
        "integral_tie": rotor_reach == twin_reach,
        "candidates_outside_inverse_class": len(ranked),
        "table_sha256": sha256_bytes(bytes(table)),
    }


def payload(results: dict) -> dict:
    return {
        "schema": "E256-PATCHED-ROTOR-GATE-1",
        "prereg_sha256": PREREG_SHA256,
        **{key: results[key] for key in (
            "rotor_id",
            "differential_peak",
            "walsh_peak",
            "algebraic_degree",
            "bijective",
            "involution",
            "translation",
            "ddt_histogram_equals_inverse",
            "integral_surviving_rounds_rotor",
            "integral_surviving_rounds_aes_twin",
            "integral_tie",
            "candidates_outside_inverse_class",
            "table_sha256",
        )},
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.check:
        document = json.loads(RECEIPT.read_text(encoding="utf-8"))
        encoded = json.dumps(document["deterministic_payload"], sort_keys=True, separators=(",", ":")).encode("ascii")
        require_equal(sha256_bytes(encoded), document["deterministic_payload_sha256"], "payload")
        require_equal(document["preregistration_sha256"], PREREG_SHA256, "prereg hash")
        print("CHECK PASS")
        return
    results = run()
    body = payload(results)
    encoded = json.dumps(body, sort_keys=True, separators=(",", ":")).encode("ascii")
    document = {
        "schema": "E256-PATCHED-ROTOR-GATE-1",
        "status": "OPEN_PROGRESS",
        "preregistration_sha256": PREREG_SHA256,
        "deterministic_payload_sha256": sha256_bytes(encoded),
        "deterministic_payload": body,
        "scope": (
            "Research rotor only. Not installed in E256-H. "
            "An integral tie is the SPN bijection property, not an advantage over AES."
        ),
    }
    RECEIPT.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(body, indent=2))


if __name__ == "__main__":
    try:
        main()
    except GateError as exc:
        raise SystemExit(f"ABORT — {exc}")
