#!/usr/bin/env python3
"""E256-v6 research round. Not v5, not fixture-v4.

32 bytes, read as 16 words of 16 bits. Each word is multiplied by a nonzero
field element and inverted in GF(2^16). Then a 4x4 row shift and MixColumns
over that field. There is no XOR mask. Decrypt is the inverse path. The block
index and the key are inside the multiplier.
"""

from __future__ import annotations

import hashlib
import subprocess
import sys
from pathlib import Path

POLY = 0x1100B
BITS = 16
WORDS = 16
BLOCK = 32
OFFSETS = (0, 1, 2, 3)
ROUNDS = 4
WIDTHS = (4, 8, 25)
HW_ROUNDS = 25
N_HW = 2
AFFINE = 0x1
DOMAIN = b"E256-v6/schedule/v2"
REPO = Path(__file__).resolve().parents[1]
RTL = REPO / "Hardware/RTL/Research/E256H/e256v6_round.v"
TB = REPO / "Hardware/Testbenches/Research/E256H/e256v6_round_tb.v"
BUILD = REPO / "build/e256v6"
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
    top = 1 << (BITS - 1)
    mod = POLY ^ (1 << BITS)
    acc = 0
    for _ in range(BITS):
        if b & 1:
            acc ^= a
        b >>= 1
        carry = a & top
        a = (a << 1) & ((1 << BITS) - 1)
        if carry:
            a ^= mod
    return acc


def inverse_table() -> list[int]:
    table = [0] * (1 << BITS)
    for value in range(1, 1 << BITS):
        base, exp, acc = value, (1 << BITS) - 2, 1
        while exp:
            if exp & 1:
                acc = gf_mul(acc, base)
            base = gf_mul(base, base)
            exp >>= 1
        table[value] = acc
    return table


INV_TABLE = inverse_table()


def words_of(data: list[int]) -> list[int]:
    return [data[2 * i] | (data[2 * i + 1] << 8) for i in range(WORDS)]


def bytes_of(words: list[int]) -> list[int]:
    out: list[int] = []
    for word in words:
        out.append(word & 0xFF)
        out.append((word >> 8) & 0xFF)
    return out


def field_inv(value: int) -> int:
    if value == 0:
        raise SystemExit("ABORT — zero has no field inverse")
    return INV_TABLE[value]


def masks_for(
    key: bytes, block: int, rounds: int, bind_key: bool = True, bind_block: bool = True
) -> list[list[int]]:
    label = DOMAIN
    if bind_key:
        label += key
    if bind_block:
        label += block.to_bytes(8, "big")
    raw = hashlib.shake_256(label).digest(rounds * WORDS * 2)
    scale = []
    cursor = 0
    for _ in range(rounds):
        row = []
        for _word in range(WORDS):
            word = int.from_bytes(raw[cursor : cursor + 2], "little")
            cursor += 2
            row.append(word or 1)
        scale.append(row)
    return scale


def rotor(words: list[int], scale: list[int]) -> list[int]:
    return [INV_TABLE[gf_mul(scale[i], word)] ^ AFFINE for i, word in enumerate(words)]


def unrotor(words: list[int], scale: list[int]) -> list[int]:
    return [gf_mul(field_inv(scale[i]), INV_TABLE[word ^ AFFINE]) for i, word in enumerate(words)]


def shift(words: list[int], sign: int) -> list[int]:
    out = [0] * WORDS
    for column in range(4):
        for row in range(4):
            src = (column + sign * OFFSETS[row]) % 4
            out[4 * column + row] = words[4 * src + row]
    return out


def mix(words: list[int], matrix) -> list[int]:
    out = [0] * WORDS
    for column in range(4):
        lanes = [words[4 * column + row] for row in range(4)]
        for row in range(4):
            acc = 0
            for src, coeff in enumerate(matrix[row]):
                acc ^= gf_mul(coeff, lanes[src])
            out[4 * column + row] = acc
    return out


def encrypt_round(words: list[int], scale: list[int]) -> list[int]:
    return mix(shift(rotor(words, scale), +1), MIX)


def decrypt_round(words: list[int], scale: list[int]) -> list[int]:
    return unrotor(shift(mix(words, INV), -1), scale)


def encrypt_words(key: bytes, block: int, words: list[int], rounds: int = ROUNDS) -> list[int]:
    scale = masks_for(key, block, rounds)
    state = list(words)
    for rnd in range(rounds):
        state = encrypt_round(state, scale[rnd])
    return state


def decrypt_words(key: bytes, block: int, words: list[int], rounds: int = ROUNDS) -> list[int]:
    scale = masks_for(key, block, rounds)
    state = list(words)
    for rnd in range(rounds - 1, -1, -1):
        state = decrypt_round(state, scale[rnd])
    return state


def pad(data: bytes) -> bytes:
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
        plain = words_of(list(framed[index : index + BLOCK]))
        out.extend(bytes_of(encrypt_words(key, index // BLOCK, plain, rounds)))
    return bytes(out)


def decrypt_message(key: bytes, data: bytes, rounds: int = ROUNDS) -> bytes:
    plain = bytearray()
    for index in range(0, len(data), BLOCK):
        words = words_of(list(data[index : index + BLOCK]))
        plain.extend(bytes_of(decrypt_words(key, index // BLOCK, words, rounds)))
    return unpad(bytes(plain))


def field_det(matrix: list[list[int]]) -> int:
    size = len(matrix)
    rows = [list(row) for row in matrix]
    sign = 1
    for col in range(size):
        pivot = next((row for row in range(col, size) if rows[row][col]), None)
        if pivot is None:
            return 0
        if pivot != col:
            rows[col], rows[pivot] = rows[pivot], rows[col]
            sign ^= 1
        inv = field_inv(rows[col][col])
        for row in range(col + 1, size):
            if rows[row][col] == 0:
                continue
            factor = gf_mul(rows[row][col], inv)
            for k in range(col, size):
                rows[row][k] ^= gf_mul(factor, rows[col][k])
    acc = 1 if sign == 0 else 1
    for col in range(size):
        acc = gf_mul(acc, rows[col][col])
    return acc


def mix_branch() -> tuple[int, int]:
    checked = 0
    for size in range(1, 5):
        rows = range(4)
        cols = range(4)

        def choose(pool: range, need: int, start: int = 0) -> list[tuple[int, ...]]:
            if need == 0:
                return [()]
            found = []
            for index in range(start, 4):
                for tail in choose(pool, need - 1, index + 1):
                    found.append((index,) + tail)
            return found

        for row_set in choose(rows, size):
            for col_set in choose(cols, size):
                minor = [[MIX[row][col] for col in col_set] for row in row_set]
                checked += 1
                if field_det(minor) == 0:
                    raise SystemExit(f"ABORT — mix minor is zero at rows {row_set} cols {col_set}")
    return checked, 5


def scale_words(scale: list[list[int]]) -> list[int]:
    return [word for row in scale for word in row]


def schedule_check(key: bytes) -> None:
    bundles = [masks_for(key, block, HW_ROUNDS) for block in range(16)]
    prints = [tuple(scale_words(bundle)) for bundle in bundles]
    if len(set(prints)) != 16:
        raise SystemExit("ABORT — two block indices shared a scale schedule")
    rounds = bundles[0]
    if len({tuple(row) for row in rounds}) != HW_ROUNDS:
        raise SystemExit("ABORT — two rounds inside one block shared a scale")
    neighbor = sum(a != b for a, b in zip(prints[0], prints[1]))
    if neighbor != HW_ROUNDS * WORDS:
        raise SystemExit(f"ABORT — block change reselected {neighbor} scales")
    bare_a = scale_words(masks_for(key, 0, HW_ROUNDS, bind_block=False))
    bare_b = scale_words(masks_for(key, 1, HW_ROUNDS, bind_block=False))
    if bare_a != bare_b:
        raise SystemExit("ABORT — the unbound block control changed a scale")
    other = bytearray(key)
    other[0] ^= 1
    flipped = scale_words(masks_for(bytes(other), 0, HW_ROUNDS))
    changed = sum(a != b for a, b in zip(prints[0], flipped))
    if changed != HW_ROUNDS * WORDS:
        raise SystemExit(f"ABORT — key bit reselected {changed} scales")
    key_a = scale_words(masks_for(key, 0, HW_ROUNDS, bind_key=False))
    key_b = scale_words(masks_for(bytes(other), 0, HW_ROUNDS, bind_key=False))
    if key_a != key_b:
        raise SystemExit("ABORT — the unbound key control changed a scale")
    print(
        f"v6 schedule 16/16 blocks differ  "
        f"neighbor scales {neighbor}/{HW_ROUNDS * WORDS}  "
        f"key bit {changed}/{HW_ROUNDS * WORDS}  unbound controls collided"
    )


def report_integral(key: bytes) -> None:
    stray = 0
    tables: dict = {}
    for lane in range(WORDS):
        balanced = integral_counts(key, HW_ROUNDS, lane, tables)
        death = next((rnd for rnd, count in enumerate(balanced, start=1) if count != WORDS), None)
        if death != 4 or any(count == WORDS for count in balanced[3:]):
            raise SystemExit(f"ABORT — word {lane} integral {balanced}")
        stray = max(stray, max(balanced[3:]))
        if lane == 0:
            print(f"v6 integral word 0 {balanced}  dies at {death}")
    print(f"v6 integral 16/16 words die at 4  max balanced after that {stray}")


def peel_and_degree(key: bytes) -> None:
    import numpy as np

    scale = masks_for(key, 0, HW_ROUNDS)
    plain_word = 0x1234
    one = encrypt_round([plain_word] + [0] * (WORDS - 1), scale[0])
    rotor = gf_mul(field_inv(2), one[0] ^ 0x03)
    recovered = gf_mul(INV_TABLE[rotor ^ AFFINE], field_inv(plain_word))
    if recovered != scale[0][0]:
        raise SystemExit(f"ABORT — one-round peel recovered {recovered:#x}")
    full = encrypt_words(key, 0, [plain_word] + [0] * (WORDS - 1), HW_ROUNDS)
    rotor = gf_mul(field_inv(2), full[0] ^ 0x03)
    guessed = gf_mul(INV_TABLE[rotor ^ AFFINE], field_inv(plain_word))
    if guessed == scale[0][0]:
        raise SystemExit("ABORT — one-round peel recovered the first scale from 25 rounds")
    for rounds in (2, 3, 4):
        short = encrypt_words(key, 0, [plain_word] + [0] * (WORDS - 1), rounds)
        guessed_short = gf_mul(
            INV_TABLE[gf_mul(field_inv(2), short[0] ^ 0x03) ^ AFFINE],
            field_inv(plain_word),
        )
        if guessed_short == scale[0][0]:
            raise SystemExit(f"ABORT — one-round peel hit at {rounds} rounds")
    print("v6 peel formula hits at 1 round and misses at 2, 3, 4, and 25")
    other = bytearray(key)
    other[0] ^= 1
    if decrypt_words(bytes(other), 0, full, HW_ROUNDS)[0] == plain_word:
        raise SystemExit("ABORT — wrong key decrypted")

    def degree(rounds: int) -> int:
        values = np.empty(1 << BITS, dtype=np.uint16)
        base = [0] * WORDS
        for value in range(1 << BITS):
            base[0] = value
            state = list(base)
            for rnd in range(rounds):
                state = encrypt_round(state, scale[rnd])
            values[value] = state[0]
        coeffs = (values & 1).astype(np.uint8)
        for bit in range(BITS):
            step = 1 << bit
            idx = np.arange(1 << BITS)
            high = (idx & step) != 0
            coeffs[high] ^= coeffs[idx[high] ^ step]
        nonzero = np.flatnonzero(coeffs)
        if len(nonzero) == 0:
            return 0
        return max(bin(int(mask)).count("1") for mask in nonzero)

    degrees = [degree(rnd) for rnd in (1, 2, 3)]
    print(f"v6 one-round peel hit  25-round peel missed  wrong key rejected  degree {degrees}")
    if degrees[0] < 15:
        raise SystemExit(f"ABORT — degree {degrees}")


def wider_measure(key: bytes) -> None:
    import numpy as np

    scale = masks_for(key, 0, HW_ROUNDS)
    table = np.asarray(INV_TABLE, dtype=np.uint16)
    top = np.uint16(0x8000)
    reduction = np.uint16(0x100B)
    tables: dict[int, np.ndarray] = {}

    def mul(coeff: int, column: np.ndarray) -> np.ndarray:
        found = tables.get(coeff)
        if found is None:
            acc = np.zeros(1 << BITS, dtype=np.uint16)
            word = np.arange(1 << BITS, dtype=np.uint16)
            bit = coeff
            for _ in range(BITS):
                if bit & 1:
                    acc ^= word
                bit >>= 1
                carry = (word & top) != 0
                word = np.left_shift(word, 1).astype(np.uint16)
                word[carry] ^= reduction
            tables[coeff] = acc
            found = acc
        return found[column]

    def rounds_of(state: np.ndarray, rounds: int) -> np.ndarray:
        for rnd in range(rounds):
            spun = np.empty_like(state)
            for lane in range(WORDS):
                spun[:, lane] = table[mul(scale[rnd][lane], state[:, lane])] ^ np.uint16(AFFINE)
            shifted = np.empty_like(spun)
            for column in range(4):
                for row in range(4):
                    src = (column + OFFSETS[row]) % 4
                    shifted[:, 4 * column + row] = spun[:, 4 * src + row]
            mixed = np.empty_like(shifted)
            for column in range(4):
                lanes = [shifted[:, 4 * column + row] for row in range(4)]
                for row in range(4):
                    acc = np.zeros(state.shape[0], dtype=np.uint16)
                    for src, coeff in enumerate(MIX[row]):
                        acc ^= mul(coeff, lanes[src])
                    mixed[:, 4 * column + row] = acc
            state = mixed
        return state

    delta = np.uint16(1)
    values = np.arange(1 << BITS, dtype=np.uint16)
    box = table[mul(int(scale[0][0]), values)] ^ np.uint16(AFFINE)
    image = box ^ box[values ^ delta]
    peak = int(np.bincount(image, minlength=1 << BITS).max())
    if peak != 4:
        raise SystemExit(f"ABORT — rotor differential peak {peak}")
    print(f"v6 rotor differential peak {peak}/65536")

    def difference(rounds: int) -> tuple[int, int, int]:
        left = np.zeros((1 << BITS, WORDS), dtype=np.uint16)
        left[:, 0] = values
        right = left.copy()
        right[:, 0] ^= delta
        diff = rounds_of(left, rounds) ^ rounds_of(right, rounds)
        packed = np.ascontiguousarray(diff).view(np.uint8).reshape(1 << BITS, BLOCK)
        _, counts = np.unique(packed, axis=0, return_counts=True)
        active = int(np.count_nonzero(np.any(diff != 0, axis=0)))
        return int(counts.max()), int(len(counts)), active

    for rounds in (1, 2, 3, HW_ROUNDS):
        heavy, distinct, active = difference(rounds)
        print(f"v6 difference round {rounds}  heaviest {heavy}  distinct {distinct}  active words {active}")
        if rounds == 1 and (heavy != 4 or active != 4):
            raise SystemExit(f"ABORT — one-round difference {heavy} words {active}")

    def degree_of(nbits: int, rounds: int) -> int:
        size = 1 << nbits
        state = np.zeros((size, WORDS), dtype=np.uint16)
        idx = np.arange(size, dtype=np.uint32)
        state[:, 0] = (idx & 0xFFFF).astype(np.uint16)
        if nbits > BITS:
            state[:, 1] = (idx >> BITS).astype(np.uint16)
        out = rounds_of(state, rounds)[:, 0] & 1
        coeffs = out.astype(np.uint8)
        for bit in range(nbits):
            step = 1 << bit
            high = (idx & step) != 0
            coeffs[high] ^= coeffs[(idx[high] ^ step)]
        nonzero = np.flatnonzero(coeffs)
        if len(nonzero) == 0:
            return 0
        weight = np.zeros(len(nonzero), dtype=np.uint8)
        for bit in range(nbits):
            weight += ((nonzero >> bit) & 1).astype(np.uint8)
        return int(weight.max())

    wider = [degree_of(nbits, 3) for nbits in (16, 17, 18, 20)]
    print(f"v6 degree at 3 rounds over 16,17,18,20 input bits {wider}")
    if wider[0] != 15 or wider[-1] <= 15:
        raise SystemExit(f"ABORT — wider degree {wider}")


def integral_counts(key: bytes, rounds: int, active: int = 0, tables: dict | None = None) -> list[int]:
    import numpy as np

    scale = masks_for(key, 0, rounds)
    table = np.asarray(INV_TABLE, dtype=np.uint16)
    state = np.zeros((1 << BITS, WORDS), dtype=np.uint16)
    state[:, active] = np.arange(1 << BITS, dtype=np.uint16)
    top = np.uint16(0x8000)
    width = np.uint16(0xFFFF)
    reduction = np.uint16(0x100B)

    tables = {} if tables is None else tables

    def mul(coeff: int, column: np.ndarray) -> np.ndarray:
        table_mul = tables.get(coeff)
        if table_mul is None:
            acc = np.zeros(1 << BITS, dtype=np.uint16)
            word = np.arange(1 << BITS, dtype=np.uint16)
            bit = coeff
            for _ in range(BITS):
                if bit & 1:
                    acc ^= word
                bit >>= 1
                carry = (word & top) != 0
                word = np.left_shift(word, 1).astype(np.uint16)
                word[carry] ^= reduction
            tables[coeff] = acc
            table_mul = acc
        return table_mul[column]

    counts = []
    for rnd in range(rounds):
        spun = np.empty_like(state)
        for lane in range(WORDS):
            spun[:, lane] = table[mul(scale[rnd][lane], state[:, lane])] ^ np.uint16(AFFINE)
        shifted = np.empty_like(spun)
        for column in range(4):
            for row in range(4):
                src = (column + OFFSETS[row]) % 4
                shifted[:, 4 * column + row] = spun[:, 4 * src + row]
        mixed = np.empty_like(shifted)
        for column in range(4):
            lanes = [shifted[:, 4 * column + row] for row in range(4)]
            for row in range(4):
                acc = np.zeros(state.shape[0], dtype=np.uint16)
                for src, coeff in enumerate(MIX[row]):
                    acc ^= mul(coeff, lanes[src])
                mixed[:, 4 * column + row] = acc
        state = mixed
        folded = np.bitwise_xor.reduce(state, axis=0)
        counts.append(int(np.count_nonzero(folded == 0)))
    return counts


def reach(rounds: int) -> int:
    deps = [{i} for i in range(WORDS)]
    for _ in range(rounds):
        shifted = [set() for _ in range(WORDS)]
        for column in range(4):
            for row in range(4):
                src = (column + OFFSETS[row]) % 4
                shifted[4 * column + row] = set(deps[4 * src + row])
        mixed = [set() for _ in range(WORDS)]
        for column in range(4):
            union = set()
            for row in range(4):
                union |= shifted[4 * column + row]
            for row in range(4):
                mixed[4 * column + row] = set(union)
        deps = mixed
    return min(len(row) for row in deps)


def main() -> None:
    if INV_TABLE[INV_TABLE[2]] != 2 or INV_TABLE[0] != 0:
        raise SystemExit("ABORT — inverse table is not the field inverse")
    minors, branch = mix_branch()
    print(f"v6 mix minors {minors} nonzero  branch number {branch}")
    key = hashlib.shake_256(b"E256-v6/key").digest(32)
    plain = list(hashlib.shake_256(b"E256-v6/plain").digest(32))
    words = words_of(plain)
    for rounds in WIDTHS:
        cipher = encrypt_words(key, 0, words, rounds)
        if decrypt_words(key, 0, cipher, rounds) != words:
            raise SystemExit(f"ABORT — round trip failed at {rounds}")
        if encrypt_words(key, 0, cipher, rounds) == words:
            raise SystemExit(f"ABORT — v6 is an involution at {rounds}")
        if decrypt_words(key, 1, cipher, rounds) == words:
            raise SystemExit(f"ABORT — neighboring block decrypted at {rounds}")
        flipped = list(words)
        flipped[0] ^= 1
        changed = sum(a != b for a, b in zip(cipher, encrypt_words(key, 0, flipped, rounds)))
        if changed != WORDS:
            raise SystemExit(f"ABORT — word flip changed {changed} at {rounds}")
        print(f"v6 {rounds} rounds  trip ok  word flip {changed}/16  reach {reach(rounds)}")
    scale = masks_for(key, 0, ROUNDS)
    rotor_hits = 0
    grafted = 0
    for index in range(8):
        block = words_of(list(hashlib.sha256(b"E256-v6/q" + bytes([index])).digest()))

        def quotient(scale_m, source: list[int], mask: int) -> list[int]:
            state = list(source)
            for rnd in range(ROUNDS):
                state = encrypt_round(state, scale[rnd])
                if rnd == 0:
                    state[0] ^= mask
            for rnd in range(ROUNDS - 1, -1, -1):
                if rnd == 0:
                    state[0] ^= mask
                state = decrypt_round(state, scale_m[rnd])
            return state

        once = quotient(scale, block, 1)
        grafted += quotient(scale, once, 1) == block
        scaled = [list(row) for row in scale]
        scaled[0][0] = 3 if scaled[0][0] != 3 else 5
        once = quotient(scaled, block, 0)
        rotor_hits += quotient(scaled, once, 0) == block
    if grafted != 8 or rotor_hits != 0:
        raise SystemExit(f"ABORT — grafted xor {grafted}/8 scale {rotor_hits}/8")
    print(f"v6 grafted xor {grafted}/8  scale-reselect {rotor_hits}/8")
    for length in (0, 1, 15, 31, 32, 33):
        data = bytes(range(length)) if length else b""
        if decrypt_message(key, encrypt_message(key, data)) != data:
            raise SystemExit(f"ABORT — padded message failed at length {length}")
    print("v6 padding odd lengths 0,1,15,31,32,33 round-trip")
    schedule_check(key)
    scale25 = masks_for(key, 0, HW_ROUNDS)
    wide_scale = 0
    for index in range(8):
        block = words_of(list(hashlib.sha256(b"E256-v6/q25" + bytes([index])).digest()))

        def wide(scale_m, source: list[int]) -> list[int]:
            state = list(source)
            for rnd in range(HW_ROUNDS):
                state = encrypt_round(state, scale25[rnd])
            for rnd in range(HW_ROUNDS - 1, -1, -1):
                state = decrypt_round(state, scale_m[rnd])
            return state

        scaled = [list(row) for row in scale25]
        scaled[0][0] = 3 if scaled[0][0] != 3 else 5
        once = wide(scaled, block)
        wide_scale += wide(scaled, once) == block
    if wide_scale != 0:
        raise SystemExit(f"ABORT — {HW_ROUNDS}-round scale {wide_scale}/8")
    print(f"v6 {HW_ROUNDS}-round scale-reselect {wide_scale}/8")
    report_integral(key)
    peel_and_degree(key)
    wider_measure(key)

    lines: list[str] = []
    for n in range(N_HW):
        raw = hashlib.shake_256(f"E256-v6/hw/{n}".encode()).digest(64)
        key_n, block = bytes(raw[:32]), words_of(list(raw[32:]))
        scale_n = masks_for(key_n, n, HW_ROUNDS)
        state = list(block)
        lines.append("\n".join(f"{byte:02x}" for byte in bytes_of(block)))
        for rnd in range(HW_ROUNDS):
            state = encrypt_round(state, scale_n[rnd])
            record = bytes_of(scale_n[rnd]) + bytes_of(state)
            if len(record) != 64:
                raise SystemExit(f"ABORT — round record is {len(record)} bytes")
            lines.append("\n".join(f"{byte:02x}" for byte in record))
        if decrypt_words(key_n, n, state, HW_ROUNDS) != block:
            raise SystemExit(f"ABORT — hardware block {n} does not round-trip")
    BUILD.mkdir(parents=True, exist_ok=True)
    witness_key = hashlib.shake_256(b"E256-v6/schedule-witness").digest(32)
    other = bytearray(witness_key)
    other[0] ^= 1
    witness = []
    for sample in (
        masks_for(witness_key, 0, HW_ROUNDS),
        masks_for(witness_key, 1, HW_ROUNDS),
        masks_for(bytes(other), 0, HW_ROUNDS),
    ):
        for word in scale_words(sample):
            witness.append(f"{word & 0xFF:02x}")
            witness.append(f"{(word >> 8) & 0xFF:02x}")
    (BUILD / "sched.hex").write_text("\n".join(witness) + "\n")
    (BUILD / "nvec.hex").write_text(f"{N_HW:02x}\n{HW_ROUNDS:02x}\n")
    (BUILD / "vectors.hex").write_text("\n".join(lines) + "\n")
    sim = BUILD / "sim"
    sim.mkdir(exist_ok=True)
    subprocess.run(
        ["iverilog", "-g2012", "-o", str(sim / "e256v6.vvp"), str(RTL), str(TB)],
        check=True,
        cwd=BUILD,
    )
    run = subprocess.run(["vvp", str(sim / "e256v6.vvp")], check=True, cwd=BUILD, capture_output=True, text=True)
    sys.stdout.write(run.stdout)
    if "PASS" not in run.stdout:
        raise SystemExit(run.stderr or "ABORT — verilog failed")


if __name__ == "__main__":
    main()
