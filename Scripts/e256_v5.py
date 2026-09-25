#!/usr/bin/env python3
"""E256-v5 research model. Not fixture-v4. Not staged E256-v3 fixture-v5.

32-byte state. Each round is a keyed affine rotor, row shift (0,1,3,4),
MixColumns, then a mask XOR. Four, eight, and fourteen rounds are checked. Fourteen is the Verilog width.
No production round count is selected.
"""

from __future__ import annotations

import hashlib
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
RTL = REPO / "Hardware/RTL/Research/E256H"
TB = REPO / "Hardware/Testbenches/Research/E256H/e256v5_round_tb.v"
BUILD = REPO / "build/e256v5"
OFFSETS = (0, 1, 3, 4)
ROUNDS = 14
WIDTHS = (4, 8, 14)
N_HW = 2
DOMAIN = b"E256-v5/schedule/v1"
MIX = (
    (0x02, 0x03, 0x01, 0x01),
    (0x01, 0x02, 0x03, 0x01),
    (0x01, 0x01, 0x02, 0x03),
    (0x03, 0x01, 0x01, 0x02),
)
INV = (
    (0x0E, 0x0B, 0x0D, 0x09),
    (0x09, 0x0E, 0x0B, 0x0D),
    (0x0D, 0x09, 0x0E, 0x0B),
    (0x0B, 0x0D, 0x09, 0x0E),
)


def gf_mul(a: int, b: int) -> int:
    acc = 0
    while b:
        if b & 1:
            acc ^= a
        a = ((a << 1) ^ 0x1B) & 0xFF if a & 0x80 else (a << 1) & 0xFF
        b >>= 1
    return acc


def aes_sbox() -> list[int]:
    table = []
    for x in range(256):
        inv = 0
        if x:
            base, exp, inv = x, 254, 1
            while exp:
                if exp & 1:
                    inv = gf_mul(inv, base)
                base = gf_mul(base, base)
                exp >>= 1
        y = inv
        for shift in (1, 2, 3, 4):
            y ^= ((inv << shift) | (inv >> (8 - shift))) & 0xFF
        table.append(y ^ 0x63)
    return table


SBOX = aes_sbox()
INV_SBOX = [0] * 256
for index, value in enumerate(SBOX):
    INV_SBOX[value] = index


def matvec(rows: list[int], value: int) -> int:
    out = 0
    for bit, row in enumerate(rows):
        if bin(row & value).count("1") & 1:
            out |= 1 << bit
    return out


def invertible(rows: list[int]) -> list[int] | None:
    left = [row & 0xFF for row in rows]
    right = [1 << bit for bit in range(8)]
    for col in range(8):
        pivot = next((row for row in range(col, 8) if left[row] & (1 << col)), None)
        if pivot is None:
            return None
        left[col], left[pivot] = left[pivot], left[col]
        right[col], right[pivot] = right[pivot], right[col]
        for row in range(8):
            if row != col and left[row] & (1 << col):
                left[row] ^= left[col]
                right[row] ^= right[col]
    return right


def draw_matrix(seed: bytes) -> tuple[list[int], list[int]]:
    for attempt in range(64):
        raw = hashlib.shake_256(seed + attempt.to_bytes(2, "big")).digest(8)
        inverse = invertible(list(raw))
        if inverse is not None:
            return list(raw), inverse
    raise SystemExit("ABORT — no invertible rotor matrix")


def rotor_for(
    key: bytes, block: int, round_index: int, lane: int, bind_block: bool = True, bind_key: bool = True
) -> dict:
    label = DOMAIN + b"R" + round_index.to_bytes(2, "big") + lane.to_bytes(1, "big")
    if bind_key:
        label += key
    if bind_block:
        label += block.to_bytes(8, "big")
    min_m, min_inv = draw_matrix(label + b"/in")
    mout, mout_inv = draw_matrix(label + b"/out")
    constants = hashlib.shake_256(label + b"/c").digest(2)
    return {
        "cin": constants[0],
        "cout": constants[1],
        "min": min_m,
        "mout": mout,
        "min_inv": min_inv,
        "mout_inv": mout_inv,
    }


def masks_for(key: bytes, block: int, rounds: int = ROUNDS) -> list[list[int]]:
    raw = hashlib.shake_256(DOMAIN + b"M" + key + block.to_bytes(8, "big")).digest((rounds + 1) * 32)
    return [list(raw[i * 32 : (i + 1) * 32]) for i in range(rounds + 1)]


def rotors_for(key: bytes, block: int, rounds: int = ROUNDS) -> list[list[dict]]:
    return [[rotor_for(key, block, rnd, lane) for lane in range(32)] for rnd in range(rounds)]


def shift(state: list[int], sign: int) -> list[int]:
    out = [0] * 32
    for column in range(8):
        for row in range(4):
            src = (column + sign * OFFSETS[row]) % 8
            out[4 * column + row] = state[4 * src + row]
    return out


def mix(state: list[int], matrix) -> list[int]:
    out = [0] * 32
    for column in range(8):
        lanes = [state[4 * column + row] for row in range(4)]
        for row in range(4):
            out[4 * column + row] = 0
            for src, coeff in enumerate(matrix[row]):
                out[4 * column + row] ^= gf_mul(coeff, lanes[src])
    return out


def apply_rotor(state: list[int], rotors: list[dict], inverse: bool) -> list[int]:
    out = []
    for lane, rotor in enumerate(rotors):
        if not inverse:
            mixed = matvec(rotor["min"], state[lane]) ^ rotor["cin"]
            out.append(matvec(rotor["mout"], SBOX[mixed]) ^ rotor["cout"])
        else:
            back = matvec(rotor["mout_inv"], state[lane] ^ rotor["cout"])
            out.append(matvec(rotor["min_inv"], INV_SBOX[back] ^ rotor["cin"]))
    return out


BLOCK = 32


def pad(data: bytes) -> bytes:
    """ISO/IEC 9797-1 method 2. Always adds 0x80, then zeros out to 32 bytes."""
    framed = data + b"\x80"
    if len(framed) % BLOCK:
        framed += bytes(BLOCK - (len(framed) % BLOCK))
    return framed


def unpad(data: bytes) -> bytes:
    if len(data) == 0 or len(data) % BLOCK:
        raise SystemExit("ABORT — padded message is not a whole number of blocks")
    block = data[-BLOCK:]
    marker = block.rfind(b"\x80")
    if marker < 0 or block[marker + 1 :] != bytes(BLOCK - marker - 1):
        raise SystemExit("ABORT — padding marker is missing")
    return data[: -BLOCK + marker]


def encrypt_message(key: bytes, data: bytes, rounds: int = ROUNDS) -> bytes:
    framed = pad(data)
    out = bytearray()
    for index in range(0, len(framed), BLOCK):
        block = list(framed[index : index + BLOCK])
        out.extend(encrypt(key, index // BLOCK, block, rounds))
    return bytes(out)


def decrypt_message(key: bytes, data: bytes, rounds: int = ROUNDS) -> bytes:
    if len(data) == 0 or len(data) % BLOCK:
        raise SystemExit("ABORT — ciphertext is not a whole number of blocks")
    plain = bytearray()
    for index in range(0, len(data), BLOCK):
        block = list(data[index : index + BLOCK])
        plain.extend(decrypt(key, index // BLOCK, block, rounds))
    return unpad(bytes(plain))


def padding_check(key: bytes) -> None:
    for length in (0, 1, 15, 31, 32, 33):
        data = bytes(range(length)) if length else b""
        framed = pad(data)
        if len(framed) % BLOCK or len(framed) % 2 or unpad(framed) != data:
            raise SystemExit(f"ABORT — padding failed at length {length}")
        if decrypt_message(key, encrypt_message(key, data, 4), 4) != data:
            raise SystemExit(f"ABORT — padded message failed at length {length}")
    print("padding odd lengths 0,1,15,31,32,33 round-trip at 4 rounds")


def encrypt_round(state: list[int], rotors: list[dict], mask: list[int]) -> list[int]:
    return [a ^ b for a, b in zip(mix(shift(apply_rotor(state, rotors, False), +1), MIX), mask)]


def decrypt_round(state: list[int], rotors: list[dict], mask: list[int]) -> list[int]:
    unmasked = [a ^ b for a, b in zip(state, mask)]
    return apply_rotor(shift(mix(unmasked, INV), -1), rotors, True)


def encrypt(key: bytes, block: int, plain: list[int], rounds: int = ROUNDS) -> list[int]:
    masks = masks_for(key, block, rounds)
    rotors = rotors_for(key, block, rounds)
    state = [a ^ b for a, b in zip(plain, masks[0])]
    for rnd in range(rounds):
        state = encrypt_round(state, rotors[rnd], masks[rnd + 1])
    return state


def decrypt(key: bytes, block: int, cipher: list[int], rounds: int = ROUNDS) -> list[int]:
    masks = masks_for(key, block, rounds)
    rotors = rotors_for(key, block, rounds)
    state = list(cipher)
    for rnd in range(rounds - 1, -1, -1):
        state = decrypt_round(state, rotors[rnd], masks[rnd + 1])
    return [a ^ b for a, b in zip(state, masks[0])]


def xor_mask(masks: list[list[int]]) -> list[list[int]]:
    edited = [list(mask) for mask in masks]
    edited[1][0] ^= 0x01
    return edited


def run_block(plain: list[int], masks: list[list[int]], rotors: list[list[dict]]) -> list[int]:
    state = [a ^ b for a, b in zip(plain, masks[0])]
    for rnd, lanes in enumerate(rotors):
        state = encrypt_round(state, lanes, masks[rnd + 1])
    return state


def undo_block(cipher: list[int], masks: list[list[int]], rotors: list[list[dict]]) -> list[int]:
    state = list(cipher)
    for rnd in range(len(rotors) - 1, -1, -1):
        state = decrypt_round(state, rotors[rnd], masks[rnd + 1])
    return [a ^ b for a, b in zip(state, masks[0])]


def words(values: list[int]) -> str:
    return "\n".join(f"{byte:02x}" for byte in values)


def pack_round(rotor_lanes: list[dict], mask: list[int], state: list[int]) -> list[int]:
    packed: list[int] = []
    packed.extend(rotor["cin"] for rotor in rotor_lanes)
    packed.extend(rotor["cout"] for rotor in rotor_lanes)
    for name in ("min", "mout", "min_inv", "mout_inv"):
        for rotor in rotor_lanes:
            packed.extend(rotor[name])
    packed.extend(mask)
    packed.extend(state)
    if len(packed) != 1152:
        raise SystemExit(f"ABORT — round record is {len(packed)} bytes")
    return packed


def rotor_fingerprint(rotors: list[list[dict]]) -> tuple:
    return tuple(
        (lane["cin"], lane["cout"], tuple(lane["min"]), tuple(lane["mout"]))
        for lanes in rotors
        for lane in lanes
    )


def differing_lanes(left: list[list[dict]], right: list[list[dict]]) -> int:
    count = 0
    for lanes_a, lanes_b in zip(left, right):
        for lane_a, lane_b in zip(lanes_a, lanes_b):
            if rotor_fingerprint([[lane_a]]) != rotor_fingerprint([[lane_b]]):
                count += 1
    return count


def schedule_check(key: bytes) -> dict:
    """Distinct blocks must differ in a rotor. A schedule that ignores the block must not."""
    material = [rotors_for(key, block, ROUNDS) for block in range(16)]
    fingerprints = [rotor_fingerprint(rotors) for rotors in material]
    if len(set(fingerprints)) != 16:
        raise SystemExit("ABORT — two block indices shared a rotor schedule")
    round_prints = [rotor_fingerprint([lanes]) for lanes in material[0]]
    if len(set(round_prints)) != ROUNDS:
        raise SystemExit("ABORT — two rounds inside one block shared a rotor")
    neighbor = differing_lanes(material[0], material[1])
    if neighbor < 1:
        raise SystemExit("ABORT — block 0 and block 1 share every rotor")
    unbound_a = rotor_for(key, 0, 0, 0, bind_block=False)
    unbound_b = rotor_for(key, 1, 0, 0, bind_block=False)
    if rotor_fingerprint([[unbound_a]]) != rotor_fingerprint([[unbound_b]]):
        raise SystemExit("ABORT — the unbound control changed a rotor")
    print(f"schedule 16/16 blocks differ  neighbor lanes {neighbor}/{ROUNDS * 32}  unbound control collided")
    return {"blocks": 16, "neighbor_lanes": neighbor, "rounds": ROUNDS}


def key_schedule_check(key: bytes) -> int:
    other = bytearray(key)
    other[0] ^= 0x01
    left = rotors_for(key, 0, ROUNDS)
    right = rotors_for(bytes(other), 0, ROUNDS)
    changed = differing_lanes(left, right)
    if changed != ROUNDS * 32:
        raise SystemExit(f"ABORT — key bit changed {changed} lanes")
    bare_a = rotor_for(key, 0, 0, 0, bind_key=False)
    bare_b = rotor_for(bytes(other), 0, 0, 0, bind_key=False)
    if rotor_fingerprint([[bare_a]]) != rotor_fingerprint([[bare_b]]):
        raise SystemExit("ABORT — key-unbound control changed a rotor")
    print(f"key bit reselects {changed}/{ROUNDS * 32} lanes  unbound key collided")
    return changed


def rotor_table(rotor: dict) -> list[int]:
    return [
        matvec(rotor["mout"], SBOX[matvec(rotor["min"], value) ^ rotor["cin"]]) ^ rotor["cout"]
        for value in range(256)
    ]


def differential_peak(table: list[int]) -> int:
    peak = 0
    for delta in range(1, 256):
        counts = [0] * 256
        for value in range(256):
            counts[table[value] ^ table[value ^ delta]] += 1
        peak = max(peak, max(counts))
    return peak


def walsh_peak(table: list[int]) -> int:
    parity = [bin(value).count("1") & 1 for value in range(256)]
    peak = 0
    for mask_in in range(256):
        for mask_out in range(256):
            if mask_in == 0 and mask_out == 0:
                continue
            total = 0
            for value in range(256):
                bit = parity[mask_in & value] ^ parity[mask_out & table[value]]
                total += 1 if bit == 0 else -1
            peak = max(peak, abs(total))
    return peak


def output_degree(table: list[int]) -> int:
    coeffs = [table[value] & 1 for value in range(256)]
    for bit in range(8):
        step = 1 << bit
        for mask in range(256):
            if mask & step:
                coeffs[mask] ^= coeffs[mask ^ step]
    degree = 0
    for mask, coeff in enumerate(coeffs):
        if coeff:
            degree = max(degree, bin(mask).count("1"))
    return degree


def rotor_spectrum(key: bytes) -> None:
    aes_peak = differential_peak(SBOX)
    aes_walsh = walsh_peak(SBOX)
    aes_degree = output_degree(SBOX)
    if (aes_peak, aes_walsh, aes_degree) != (4, 32, 7):
        raise SystemExit(f"ABORT — AES spectrum {aes_peak} {aes_walsh} {aes_degree}")
    for lane in range(4):
        table = rotor_table(rotor_for(key, 0, 0, lane))
        peak, linear, degree = differential_peak(table), walsh_peak(table), output_degree(table)
        if (peak, linear, degree) != (4, 32, 7):
            raise SystemExit(f"ABORT — rotor lane {lane} spectrum {peak} {linear} {degree}")
    print("rotor spectrum 4 lanes match AES  differential 4  walsh 32  degree 7")


def integral_counts(key: bytes, active: int = 0) -> list[int]:
    masks = masks_for(key, 0, ROUNDS)
    rotors = rotors_for(key, 0, ROUNDS)
    acc = [[0] * 32 for _ in range(ROUNDS)]
    for value in range(256):
        state = [0] * 32
        state[active] = value
        state = [a ^ b for a, b in zip(state, masks[0])]
        for rnd in range(ROUNDS):
            state = encrypt_round(state, rotors[rnd], masks[rnd + 1])
            for lane in range(32):
                acc[rnd][lane] ^= state[lane]
    return [sum(byte == 0 for byte in row) for row in acc]


def main() -> None:
    key = hashlib.shake_256(b"E256-v5/key").digest(32)
    plain = list(hashlib.shake_256(b"E256-v5/plain").digest(32))
    padding_check(key)
    for rounds in WIDTHS:
        cipher = encrypt(key, 0, plain, rounds)
        if decrypt(key, 0, cipher, rounds) != plain:
            raise SystemExit(f"ABORT — round trip failed at {rounds}")
        if encrypt(key, 0, cipher, rounds) == plain:
            raise SystemExit(f"ABORT — v5 is an involution at {rounds}")
        if decrypt(key, 1, cipher, rounds) == plain:
            raise SystemExit(f"ABORT — neighboring block decrypted at {rounds}")
        masks = masks_for(key, 0, rounds)
        rotors = rotors_for(key, 0, rounds)
        mask_hits = 0
        rotor_hits = 0
        for index in range(8):
            block = list(hashlib.sha256(b"E256-v5/q" + bytes([index])).digest())
            left = run_block(block, masks, rotors)
            back = undo_block(left, xor_mask(masks), rotors)
            mask_hits += undo_block(run_block(back, masks, rotors), xor_mask(masks), rotors) == block
            edited = [dict(lane) for lane in rotors[0]]
            edited[0] = rotor_for(key, 99, 0, 0)
            changed = [edited] + rotors[1:]
            back = undo_block(run_block(block, masks, rotors), masks, changed)
            rotor_hits += undo_block(run_block(back, masks, rotors), masks, changed) == block
        flipped = list(plain)
        flipped[0] ^= 1
        changed_bytes = sum(a != b for a, b in zip(cipher, encrypt(key, 0, flipped, rounds)))
        if mask_hits != 8 or rotor_hits != 0 or changed_bytes < 16:
            raise SystemExit(
                f"ABORT — {rounds} rounds mask {mask_hits}/8 rotor {rotor_hits}/8 flip {changed_bytes}"
            )
        print(
            f"v5 {rounds} rounds  trip ok  mask-only {mask_hits}/8  "
            f"rotor-reselect {rotor_hits}/8  one-byte flip {changed_bytes}/32"
        )
    balanced = integral_counts(key)
    death = next((rnd for rnd, count in enumerate(balanced, start=1) if count != 32), None)
    print(f"v5 integral lane 0 {balanced}  dies at {death}")
    if death != 4:
        raise SystemExit(f"ABORT — integral died at {death}")
    stray = 0
    for lane in range(32):
        counts = integral_counts(key, lane)
        lane_death = next((rnd for rnd, count in enumerate(counts, start=1) if count != 32), None)
        if lane_death != 4 or any(count == 32 for count in counts[3:]):
            raise SystemExit(f"ABORT — lane {lane} integral {counts}")
        stray = max(stray, max(counts[3:]))
    print(f"v5 integral 32/32 lanes die at 4  max balanced after that {stray}")
    schedule_check(key)
    key_schedule_check(key)
    rotor_spectrum(key)

    lines: list[str] = []
    for n in range(N_HW):
        raw = hashlib.shake_256(f"E256-v5/hw/{n}".encode()).digest(64)
        key_n, block = bytes(raw[:32]), list(raw[32:])
        round_masks = masks_for(key_n, n)
        round_rotors = rotors_for(key_n, n)
        state = [a ^ b for a, b in zip(block, round_masks[0])]
        lines.append(words(block))
        lines.append(words(round_masks[0]))
        for rnd in range(ROUNDS):
            state = encrypt_round(state, round_rotors[rnd], round_masks[rnd + 1])
            lines.append(words(pack_round(round_rotors[rnd], round_masks[rnd + 1], state)))
        if undo_block(state, round_masks, round_rotors) != block:
            raise SystemExit(f"ABORT — hardware block {n} does not round-trip")
    BUILD.mkdir(parents=True, exist_ok=True)
    (BUILD / "e256r_inv_sbox.hex").write_text("\n".join(f"{byte:02x}" for byte in INV_SBOX) + "\n")
    (BUILD / "nvec.hex").write_text(f"{N_HW:02x}\n{ROUNDS:02x}\n")
    (BUILD / "vectors.hex").write_text("\n".join(lines) + "\n")
    sim = BUILD / "sim"
    sim.mkdir(exist_ok=True)
    subprocess.run(
        [
            "iverilog", "-g2012", "-o", str(sim / "e256v5.vvp"),
            "-I", str(RTL),
            str(RTL / "e256h_attack_core.v"),
            str(RTL / "e256r_round.v"),
            str(RTL / "e256v5_round.v"),
            str(TB),
        ],
        check=True,
        cwd=BUILD,
    )
    run = subprocess.run([ "vvp", str(sim / "e256v5.vvp")], check=True, cwd=BUILD, capture_output=True, text=True)
    sys.stdout.write(run.stdout)
    if "PASS" not in run.stdout:
        raise SystemExit(run.stderr or "ABORT — verilog failed")


if __name__ == "__main__":
    main()
