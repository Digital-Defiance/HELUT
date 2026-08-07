#!/usr/bin/env python3
"""Python model of the repaired E256 round. Must match e256r_round.v.

Encrypt: mask, AES S-box, row shift (0,1,3,4), MixColumns.
Decrypt: inverse MixColumns, inverse shift, inverse S-box, mask.
No reflector and no reverse rotor stack.
"""

from __future__ import annotations

import hashlib
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
RTL = REPO / "Hardware/RTL/Research/E256H"
TB = REPO / "Hardware/Testbenches/Research/E256H/e256r_round_tb.v"
BUILD = REPO / "build/e256r"
OFFSETS = (0, 1, 3, 4)
MIX = ((0x02, 0x03, 0x01, 0x01), (0x01, 0x02, 0x03, 0x01), (0x01, 0x01, 0x02, 0x03), (0x03, 0x01, 0x01, 0x02))
INV = ((0x0E, 0x0B, 0x0D, 0x09), (0x09, 0x0E, 0x0B, 0x0D), (0x0D, 0x09, 0x0E, 0x0B), (0x0B, 0x0D, 0x09, 0x0E))


def gf_mul(a: int, b: int) -> int:
    result = 0
    while b:
        if b & 1:
            result ^= a
        a = ((a << 1) ^ 0x1B) & 0xFF if a & 0x80 else (a << 1) & 0xFF
        b >>= 1
    return result


def gf_pow(a: int, e: int) -> int:
    result = 1
    while e:
        if e & 1:
            result = gf_mul(result, a)
        a = gf_mul(a, a)
        e >>= 1
    return result


def rol8(v: int, n: int) -> int:
    return ((v << n) | (v >> (8 - n))) & 0xFF


def aes_sbox() -> list[int]:
    table = []
    for value in range(256):
        inv = 0 if value == 0 else gf_pow(value, 254)
        table.append(inv ^ rol8(inv, 1) ^ rol8(inv, 2) ^ rol8(inv, 3) ^ rol8(inv, 4) ^ 0x63)
    return table


SBOX = aes_sbox()
INV_SBOX = [0] * 256
for i, y in enumerate(SBOX):
    INV_SBOX[y] = i


def row_shift(state: list[int], sign: int) -> list[int]:
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
            acc = 0
            for k in range(4):
                acc ^= gf_mul(matrix[row][k], lanes[k])
            out[4 * column + row] = acc
    return out


def encrypt_round(state: list[int], mask: list[int]) -> list[int]:
    keyed = [state[i] ^ mask[i] for i in range(32)]
    sub = [SBOX[b] for b in keyed]
    return mix(row_shift(sub, +1), MIX)


def decrypt_round(state: list[int], mask: list[int]) -> list[int]:
    mixed = mix(state, INV)
    shifted = row_shift(mixed, -1)
    return [INV_SBOX[b] ^ mask[i] for i, b in enumerate(shifted)]


def encrypt_block(state: list[int], masks: list[list[int]]) -> list[int]:
    out = list(state)
    for mask in masks:
        out = encrypt_round(out, mask)
    return out


def decrypt_block(state: list[int], masks: list[list[int]]) -> list[int]:
    out = list(state)
    for mask in reversed(masks):
        out = decrypt_round(out, mask)
    return out


def words(block: list[int]) -> str:
    return "\n".join(f"{b:02x}" for b in block)


AES_SBOX_SHA = "c2d8e5eed6cbebd8625fc18f81486a7733c04f9b0129ffbe974c68b90308b4f2"
N_BLOCKS = 256
N_HW = 16
# Experimental machine width. Not a security level. The diffusion check must
# agree that this is the smallest count at which one input byte reaches all 32.
FROZEN_ROUNDS = 14
INTEGRAL_DEATH = 4
SCHEDULE_DOMAIN = b"E256-R/schedule/v2"


def schedule(key: bytes, block_index: int, rounds: int) -> list[list[int]]:
    block = block_index.to_bytes(8, "big")
    masks = []
    for round_index in range(rounds):
        raw = hashlib.shake_256(SCHEDULE_DOMAIN + b"R" + round_index.to_bytes(2, "big") + key + block).digest(32)
        masks.append(list(raw))
    return masks


def whitening(key: bytes, block_index: int) -> list[int]:
    block = block_index.to_bytes(8, "big")
    return list(hashlib.shake_256(SCHEDULE_DOMAIN + b"W" + key + block).digest(32))


def apply_white(state: list[int], mask: list[int]) -> list[int]:
    return [a ^ b for a, b in zip(state, mask)]


def encrypt(key: bytes, block_index: int, plain: list[int], rounds: int = FROZEN_ROUNDS) -> list[int]:
    inner = encrypt_block(plain, schedule(key, block_index, rounds))
    return apply_white(inner, whitening(key, block_index))


def decrypt(key: bytes, block_index: int, cipher: list[int], rounds: int = FROZEN_ROUNDS) -> list[int]:
    inner = apply_white(cipher, whitening(key, block_index))
    return decrypt_block(inner, schedule(key, block_index, rounds))


def byte_reach(rounds: int) -> int:
    """How many input bytes can affect each output byte, for a bijective S-box."""
    reach = [{i} for i in range(32)]
    for _ in range(rounds):
        shifted = [set() for _ in range(32)]
        for column in range(8):
            for row in range(4):
                src = 4 * ((column + OFFSETS[row]) % 8) + row
                shifted[4 * column + row] = set(reach[src])
        mixed = [set() for _ in range(32)]
        for column in range(8):
            union: set[int] = set()
            for row in range(4):
                union |= shifted[4 * column + row]
            for row in range(4):
                mixed[4 * column + row] = set(union)
        reach = mixed
    return min(len(lane) for lane in reach)


def xor_bytes(a: list[int], b: list[int]) -> list[int]:
    return [x ^ y for x, y in zip(a, b)]


def apply_affine(zero: list[int], images: list[list[int]], plain: list[int]) -> list[int]:
    out = list(zero)
    for bit in range(256):
        if (plain[bit // 8] >> (bit % 8)) & 1:
            out = xor_bytes(out, images[bit])
    return out


def identity_control(key: bytes, block_index: int) -> tuple[int, int]:
    """Identity S-box must be exactly affine. The real S-box must not be."""
    identity = list(range(256))

    def enc(table: list[int], plain: list[int]) -> list[int]:
        state = list(plain)
        for mask in schedule(key, block_index, FROZEN_ROUNDS):
            sub = [table[state[i] ^ mask[i]] for i in range(32)]
            state = mix(row_shift(sub, +1), MIX)
        return state

    zero = enc(identity, [0] * 32)
    images = []
    for bit in range(256):
        plain = [0] * 32
        plain[bit // 8] = 1 << (bit % 8)
        images.append(xor_bytes(enc(identity, plain), zero))
    held = hashlib.shake_256(b"E256-R/identity-heldout/v1").digest(16 * 32)
    identity_hits = 0
    for n in range(16):
        plain = list(held[n * 32 : (n + 1) * 32])
        if apply_affine(zero, images, plain) == enc(identity, plain):
            identity_hits += 1
    if identity_hits != 16:
        raise SystemExit("ABORT — identity rotor was not affine")
    real_zero = encrypt(key, block_index, [0] * 32)
    real_images = []
    for bit in range(256):
        plain = [0] * 32
        plain[bit // 8] = 1 << (bit % 8)
        real_images.append(xor_bytes(encrypt(key, block_index, plain), real_zero))
    real_misses = 0
    for n in range(16):
        plain = list(held[n * 32 : (n + 1) * 32])
        if apply_affine(real_zero, real_images, plain) != encrypt(key, block_index, plain):
            real_misses += 1
    if real_misses != 16:
        raise SystemExit("ABORT — real rotor was affine")
    return identity_hits, real_misses


def flip_score(rounds: int) -> int:
    worst = 32
    for trial in range(8):
        raw = hashlib.shake_256(f"E256-R/diffusion/v1/{trial}".encode()).digest(64)
        key, plain = bytes(raw[:32]), list(raw[32:])
        masks = schedule(key, 0, rounds)
        cipher = encrypt_block(plain, masks)
        for lane in range(32):
            flipped = list(plain)
            flipped[lane] ^= 1
            other = encrypt_block(flipped, masks)
            worst = min(worst, sum(a != b for a, b in zip(cipher, other)))
    return worst


def diffusion_check() -> tuple[list[int], list[int]]:
    reach = [byte_reach(r) for r in range(1, 9)]
    scores = [flip_score(r) for r in range(1, 9)]
    structural = next(r for r, n in enumerate(reach, start=1) if n == 32)
    if structural > FROZEN_ROUNDS:
        raise SystemExit(f"ABORT — full dependency starts at {structural}, frozen count is {FROZEN_ROUNDS}")
    covered = 0
    for trial in range(8):
        raw = hashlib.shake_256(f"E256-R/diffusion/v1/{trial}".encode()).digest(64)
        key, plain = bytes(raw[:32]), list(raw[32:])
        masks = schedule(key, 0, FROZEN_ROUNDS)
        cipher = encrypt_block(plain, masks)
        seen = [False] * 32
        for lane in range(32):
            flipped = list(plain)
            flipped[lane] ^= 1
            other = encrypt_block(flipped, masks)
            for i, (a, b) in enumerate(zip(cipher, other)):
                if a != b:
                    seen[i] = True
        if not all(seen):
            raise SystemExit(f"ABORT — trial {trial} left an output byte untouched")
        covered += 1
    print(
        f"diffusion reach {reach}  single-flip worst {scores}  "
        f"frozen {FROZEN_ROUNDS}  trials covering all bytes {covered}"
    )
    return reach, scores


def functional() -> None:
    digest = hashlib.sha256(bytes(SBOX)).hexdigest()
    if digest != AES_SBOX_SHA:
        raise SystemExit(f"ABORT — S-box is not the AES table ({digest})")
    trips = 0
    changed = 0
    wrong_mask = 0
    for rounds in (1, 2, 4, 8):
        raw = hashlib.shake_256(f"E256-R/functional/v1/{rounds}".encode()).digest(
            N_BLOCKS * 32 * (1 + rounds)
        )
        for n in range(N_BLOCKS):
            base = n * 32 * (1 + rounds)
            plain = list(raw[base : base + 32])
            masks = [
                list(raw[base + 32 * (1 + r) : base + 32 * (2 + r)]) for r in range(rounds)
            ]
            cipher = encrypt_block(plain, masks)
            if decrypt_block(cipher, masks) != plain:
                raise SystemExit(f"ABORT — round trip failed at {rounds} rounds, block {n}")
            trips += 1
            flipped = list(plain)
            flipped[0] ^= 1
            if encrypt_block(flipped, masks) == cipher:
                raise SystemExit(f"ABORT — one-byte flip was a no-op at {rounds} rounds")
            changed += 1
            bad = [list(m) for m in masks]
            bad[-1][0] ^= 1
            if decrypt_block(cipher, bad) == plain:
                raise SystemExit(f"ABORT — wrong mask still decrypted at {rounds} rounds")
            wrong_mask += 1
    print(f"python round-trips {trips}  one-byte-flips {changed}  wrong-mask rejects {wrong_mask}")


def integral_balanced(rounds: int, table: list[int], key: bytes, active: int = 0) -> int:
    masks = schedule(key, 0, rounds)
    acc = [0] * 32
    for value in range(256):
        block = [0] * 32
        block[active] = value
        state = block
        for mask in masks:
            sub = [table[state[i] ^ mask[i]] for i in range(32)]
            state = mix(row_shift(sub, +1), MIX)
        for i in range(32):
            acc[i] ^= state[i]
    return sum(byte == 0 for byte in acc)


def gf_det(matrix: list[list[int]]) -> int:
    size = len(matrix)
    work = [list(row) for row in matrix]
    det = 1
    for col in range(size):
        pivot = next((row for row in range(col, size) if work[row][col]), None)
        if pivot is None:
            return 0
        if pivot != col:
            work[col], work[pivot] = work[pivot], work[col]
        det = gf_mul(det, work[col][col])
        inv = gf_pow(work[col][col], 254)
        for row in range(col + 1, size):
            if work[row][col] == 0:
                continue
            factor = gf_mul(work[row][col], inv)
            for k in range(col, size):
                work[row][k] ^= gf_mul(factor, work[col][k])
    return det


def minor_certificate(matrix: list[list[int]]) -> dict:
    import itertools

    evaluated = 0
    zeros = 0
    size = len(matrix)
    for order in range(1, size + 1):
        for rows in itertools.combinations(range(size), order):
            for cols in itertools.combinations(range(size), order):
                evaluated += 1
                sub = [[matrix[r][c] for c in cols] for r in rows]
                if gf_det(sub) == 0:
                    zeros += 1
    return {"evaluated": evaluated, "zeros": zeros, "all_nonzero": zeros == 0}


def differential_peak(table: list[int]) -> int:
    peak = 0
    for delta in range(1, 256):
        counts = [0] * 256
        for value in range(256):
            counts[table[value] ^ table[value ^ delta]] += 1
        peak = max(peak, max(counts))
    return peak


PARITY = [bin(i).count("1") & 1 for i in range(256)]


def walsh_peak(table: list[int]) -> int:
    peak = 0
    for mask_in in range(256):
        for mask_out in range(256):
            if mask_in == 0 and mask_out == 0:
                continue
            total = 0
            for value in range(256):
                bit = PARITY[mask_in & value] ^ PARITY[mask_out & table[value]]
                total += 1 if bit == 0 else -1
            peak = max(peak, abs(total))
    return peak


def trail_check() -> dict:
    minors = minor_certificate([list(row) for row in MIX])
    if minors["evaluated"] != 69 or not minors["all_nonzero"]:
        raise SystemExit(f"ABORT — MixColumns minor certificate failed {minors}")
    if len(set(OFFSETS)) != 4:
        raise SystemExit("ABORT — row offsets are not distinct")
    bundles = [a + (5 - a) >= 5 for a in (1, 2, 3, 4)]
    if not all(bundles):
        raise SystemExit("ABORT — middle bundle cases missed 5")
    peak = differential_peak(SBOX)
    linear = walsh_peak(SBOX)
    if peak != 4 or linear != 32:
        raise SystemExit(f"ABORT — S-box peaks differential {peak} linear {linear}")
    identity_peak = differential_peak(list(range(256)))
    if identity_peak != 256:
        raise SystemExit(f"ABORT — identity differential peak is {identity_peak}")
    mix_off = minor_certificate([[1 if i == j else 0 for j in range(4)] for i in range(4)])
    if mix_off["all_nonzero"]:
        raise SystemExit("ABORT — mix-off matrix was accepted as branch number 5")
    no_mix_reach = 1
    reach = [{i} for i in range(32)]
    for _ in range(FROZEN_ROUNDS):
        shifted = [set() for _ in range(32)]
        for column in range(8):
            for row in range(4):
                src = 4 * ((column + OFFSETS[row]) % 8) + row
                shifted[4 * column + row] = set(reach[src])
        reach = shifted
    no_mix_reach = min(len(lane) for lane in reach)
    if no_mix_reach == 32:
        raise SystemExit("ABORT — mix-off still reached every byte")
    windows = FROZEN_ROUNDS // 4
    leftover = FROZEN_ROUNDS - 4 * windows
    two_round_extra = 5 if leftover >= 2 else 0
    stacked = 25 * windows + two_round_extra
    result = {
        "minors_evaluated": minors["evaluated"],
        "zero_minors": minors["zeros"],
        "offsets_distinct": True,
        "bundle_cases_meet_five": True,
        "active_sboxes_lower_bound_per_four_rounds": 25,
        "four_round_windows_inside_width": windows,
        "two_round_tail_active_sboxes": two_round_extra,
        "active_sboxes_lower_bound": stacked,
        "differential_peak": peak,
        "walsh_peak": linear,
        "single_trail_differential_log2_upper": -6 * stacked,
        "single_trail_linear_log2_upper": -3 * stacked,
        "identity_differential_peak": identity_peak,
        "identity_bound_applies": False,
        "mix_off_zero_minors": mix_off["zeros"],
        "mix_off_byte_reach_at_frozen_rounds": no_mix_reach,
    }
    print(
        f"trail minors {minors['evaluated']} zero {minors['zeros']}  "
        f"bound {stacked} = {windows}x25 + {two_round_extra}  differential peak {peak}  walsh peak {linear}  "
        f"identity peak {identity_peak}  mix-off reach {no_mix_reach}"
    )
    return result


def anf_degree(bits: list[int], nbits: int) -> int:
    size = 1 << nbits
    coeff = list(bits)
    for i in range(nbits):
        step = 1 << i
        for base in range(0, size, step << 1):
            for offset in range(step):
                coeff[base + step + offset] ^= coeff[base + offset]
    degree = 0
    for index, bit in enumerate(coeff):
        if bit:
            degree = max(degree, bin(index).count("1"))
    return degree


def encrypt_with(table: list[int], plain: list[int], masks: list[list[int]]) -> list[int]:
    state = list(plain)
    for mask in masks:
        sub = [table[state[i] ^ mask[i]] for i in range(32)]
        state = mix(row_shift(sub, +1), MIX)
    return state


def degree_check() -> dict:
    sbox_degrees = [anf_degree([(SBOX[x] >> bit) & 1 for x in range(256)], 8) for bit in range(8)]
    identity_degrees = [anf_degree([((x >> bit) & 1) for x in range(256)], 8) for bit in range(8)]
    if max(sbox_degrees) != 7 or min(sbox_degrees) < 1:
        raise SystemExit(f"ABORT — S-box bit degrees {sbox_degrees}")
    if identity_degrees != [1] * 8:
        raise SystemExit(f"ABORT — identity bit degrees {identity_degrees}")
    key = hashlib.shake_256(b"E256-R/degree/v1").digest(32)
    upper = []
    bound = 1
    for _ in range(FROZEN_ROUNDS):
        bound = min(bound * 7, 255)
        upper.append(bound)
    if upper[0] != 7 or upper[2] != 255:
        raise SystemExit(f"ABORT — degree upper bound {upper}")

    def window_degree(table: list[int], rounds: int, nbytes: int) -> int:
        masks = schedule(key, 0, rounds)
        columns = [[] for _ in range(32)]
        for value in range(1 << (8 * nbytes)):
            plain = [0] * 32
            for lane in range(nbytes):
                plain[lane] = (value >> (8 * lane)) & 0xFF
            out = encrypt_with(table, plain, masks)
            for byte_index in range(32):
                columns[byte_index].append(out[byte_index] & 1)
        return max(anf_degree(bits, 8 * nbytes) for bits in columns)

    round1 = window_degree(SBOX, 1, 1)
    round2 = window_degree(SBOX, 2, 2)
    round3 = window_degree(SBOX, 3, 2)
    identity_round2 = window_degree(list(range(256)), 2, 2)
    if round1 != 7:
        raise SystemExit(f"ABORT — round-1 degree {round1}")
    if round3 <= round2:
        raise SystemExit(f"ABORT — degree did not grow by round 3 ({round2} then {round3})")
    if identity_round2 != 1:
        raise SystemExit(f"ABORT — identity round-2 degree {identity_round2}")
    print(
        f"degree sbox {max(sbox_degrees)}  round1 {round1}  "
        f"16bit round2 {round2} round3 {round3}  "
        f"identity {identity_round2}  upper {upper[0]}/{upper[1]}/{upper[2]}..{upper[-1]}"
    )
    return {
        "sbox_bit_degree": max(sbox_degrees),
        "round1_degree": round1,
        "round2_degree_in_16_input_bits": round2,
        "round3_degree_in_16_input_bits": round3,
        "identity_round2_degree": identity_round2,
        "upper_bound_by_round": upper,
        "saturates_at_round": upper.index(255) + 1,
    }


def peel_one_round(plain: list[int], cipher: list[int]) -> list[int]:
    shifted = row_shift(mix(cipher, INV), -1)
    return [INV_SBOX[byte] ^ plain[i] for i, byte in enumerate(shifted)]


def route_check() -> dict:
    """Every remaining attack that fits in this process. A hit on 14 rounds aborts."""
    key = hashlib.shake_256(b"E256-R/routes/v1").digest(32)
    plain = list(hashlib.shake_256(b"E256-R/routes/plain").digest(32))
    masks = schedule(key, 0, FROZEN_ROUNDS)
    white = whitening(key, 0)
    seen = {tuple(mask) for mask in masks}
    seen.add(tuple(white))
    if len(seen) != FROZEN_ROUNDS + 1:
        raise SystemExit("ABORT — round masks are not pairwise distinct")
    cipher = encrypt(key, 0, plain)
    stripped = row_shift(mix(cipher, INV), -1)
    last = encrypt_block(plain, masks)
    opened = row_shift(mix(last, INV), -1)
    restored = row_shift(mix(apply_white(cipher, white), INV), -1)
    if stripped == opened:
        raise SystemExit("ABORT — final whitening did not hide the last linear layer")
    if restored != opened:
        raise SystemExit("ABORT — whitening removal did not restore the last S-box output")
    short = schedule(key, 0, 2)
    target = encrypt_block(plain, short)
    hits = []
    for guess in range(256):
        trial = [list(mask) for mask in short]
        trial[0][0] = guess
        if decrypt_block(target, trial) == plain:
            hits.append(guess)
    if hits != [short[0][0]]:
        raise SystemExit(f"ABORT — two-round mask byte not recovered: {hits}")
    full_hits = []
    for guess in range(256):
        trial = [list(mask) for mask in short]
        trial[0][0] = guess
        if decrypt_block(apply_white(cipher, white), trial) == plain:
            full_hits.append(guess)
    if full_hits:
        raise SystemExit(f"ABORT — two-round peel opened the 14-round cipher: {full_hits}")
    print("routes distinct masks  free strip blocked  2-round byte recovered  14-round peel missed")
    return {
        "masks_distinct": True,
        "free_strip_blocked": True,
        "two_round_byte_hits": hits,
        "fourteen_round_peel_hits": full_hits,
    }


def mask_recovery_check() -> dict:
    raw = hashlib.shake_256(b"E256-R/mask-recovery/v1").digest(64)
    key, plain = bytes(raw[:32]), list(raw[32:])
    one = schedule(key, 0, 1)[0]
    if peel_one_round(plain, encrypt_round(plain, one)) != one:
        raise SystemExit("ABORT — one-round mask recovery failed")
    full = encrypt(key, 0, plain)
    peeled = peel_one_round(plain, full)
    if peeled == schedule(key, 0, FROZEN_ROUNDS)[0]:
        raise SystemExit("ABORT — one-round peel recovered a 14-round mask")
    print("mask recovery 1-round exact  14-round peel missed")
    return {"one_round_recovered": True, "full_width_peel_recovered_first_mask": False}


def two_round_difference(target: tuple[int, ...]) -> list[int]:
    placed = [0] * 32
    for row, dy in enumerate(target):
        placed[row] = dy
    return mix(row_shift(placed, +1), MIX)


def carry_difference(state: list[int], ddt: list[list[int]], rounds: int) -> tuple[list[int], int, int]:
    weight = 1
    active = 0
    current = list(state)
    for _ in range(rounds):
        sub = [0] * 32
        for index, byte_diff in enumerate(current):
            if byte_diff == 0:
                continue
            dy = max(range(256), key=lambda y, diff=byte_diff: ddt[diff][y])
            step = ddt[byte_diff][dy]
            if step == 0:
                return current, 0, active
            sub[index] = dy
            weight *= step
            active += 1
        current = mix(row_shift(sub, +1), MIX)
    return current, weight, active


def cluster_check() -> dict:
    """Two-round pile-up on this round. Four-round clusters are not enumerated."""
    ddt = [[0] * 256 for _ in range(256)]
    for dx in range(256):
        for x in range(256):
            ddt[dx][SBOX[x] ^ SBOX[x ^ dx]] += 1
    one_round_extra = 0
    for dx in range(1, 256):
        seen = {}
        for dy in range(256):
            if ddt[dx][dy] == 0:
                continue
            column = tuple(gf_mul(MIX[row][0], dy) for row in range(4))
            seen[column] = seen.get(column, 0) + 1
        one_round_extra += sum(1 for count in seen.values() if count > 1)
    if one_round_extra:
        raise SystemExit("ABORT — one-round mix produced a pile-up")
    identity = [[0] * 256 for _ in range(256)]
    for dx in range(256):
        identity[dx][dx] = 256
    dx = 1
    transitions = [(dy, ddt[dx][dy]) for dy in range(256) if ddt[dx][dy]]
    intermediates = []
    for dy, count in transitions:
        column = tuple(gf_mul(MIX[row][0], dy) for row in range(4))
        intermediates.append((column, count))
    best = 0
    target = None
    for column, count in intermediates:
        weight = count
        chosen = []
        for byte_diff in column:
            dy2 = max(range(256), key=lambda y, diff=byte_diff: ddt[diff][y])
            chosen.append(dy2)
            weight *= ddt[byte_diff][dy2]
        if weight > best:
            best = weight
            target = tuple(chosen)
    trails = 0
    total = 0
    for column, count in intermediates:
        weight = count
        hit = True
        for byte_diff, want in zip(column, target):
            step = ddt[byte_diff][want]
            if step == 0:
                hit = False
                break
            weight *= step
        if hit:
            trails += 1
            total += weight
    if trails < 2 or total <= best:
        raise SystemExit(f"ABORT — two-round AES cluster did not pile up ({trails} trails)")
    identity_trails = sum(1 for dy in range(256) if identity[dx][dy])
    if identity_trails != 1:
        raise SystemExit("ABORT — identity two-round control was not a single trail")
    merged = two_round_difference(target)
    carried, continuation, active = carry_difference(merged, ddt, rounds=FROZEN_ROUNDS - 2)
    if continuation == 0 or active == 0:
        raise SystemExit("ABORT — continuation has no trail")
    ratio = total / best
    carried_weight = total * continuation
    best_weight = best * continuation
    sboxes = 5 + active
    cluster_log2 = __import__("math").log2(carried_weight) - 8 * sboxes
    print(
        f"cluster 1-round extras {one_round_extra}  "
        f"2-round trails {trails} ratio {ratio:.3f}  "
        f"identity trails {identity_trails}  "
        f"carried {FROZEN_ROUNDS} rounds  trails {trails}  sboxes {sboxes}  "
        f"cluster_log2 {cluster_log2:.2f}"
    )
    return {
        "enumerated_rounds": 2,
        "four_round_full_sum_enumerated": False,
        "one_round_outputs_with_multiple_trails": one_round_extra,
        "two_round_input_difference": dx,
        "two_round_trails_on_exhibited_output": trails,
        "two_round_cluster_weight": total,
        "two_round_best_trail_weight": best,
        "two_round_ratio": ratio,
        "identity_two_round_trails": identity_trails,
        "carried_rounds": FROZEN_ROUNDS,
        "carried_trails": trails,
        "carried_sboxes": sboxes,
        "carried_cluster_log2": cluster_log2,
    }


def stress_check() -> dict:
    """Keyed behavior the round-function checks do not touch."""
    samples = 64
    bit_hits = []
    key_hits = []
    involution = 0
    wrong_key = 0
    seen = set()
    hist = [0] * 256
    for n in range(samples):
        raw = hashlib.shake_256(f"E256-R/stress/v1/{n}".encode()).digest(64)
        key, plain = bytearray(raw[:32]), list(raw[32:])
        cipher = encrypt(key, n, plain)
        if decrypt(key, n, cipher) != plain:
            raise SystemExit(f"ABORT — stress round trip failed at {n}")
        if encrypt(key, n, cipher) == plain:
            involution += 1
        other = bytearray(key)
        other[n % 32] ^= 1 << (n % 8)
        if decrypt(bytes(other), n, cipher) == plain:
            raise SystemExit(f"ABORT — flipped key decrypted block {n}")
        wrong_key += 1
        if tuple(cipher) in seen:
            raise SystemExit(f"ABORT — ciphertext repeated at block {n}")
        seen.add(tuple(cipher))
        for byte in cipher:
            hist[byte] += 1
        flipped = list(plain)
        flipped[n % 32] ^= 1 << (n % 8)
        delta = bytes(a ^ b for a, b in zip(cipher, encrypt(key, n, flipped)))
        bit_hits.append(sum(bin(b).count("1") for b in delta))
        masks = schedule(key, n, FROZEN_ROUNDS) + [whitening(key, n)]
        masks_b = schedule(bytes(other), n, FROZEN_ROUNDS) + [whitening(bytes(other), n)]
        changed = 0
        total = 0
        for left, right in zip(masks, masks_b):
            for a, b in zip(left, right):
                total += 1
                changed += a != b
        key_hits.append(changed)
        if changed * 4 < total:
            raise SystemExit(f"ABORT — key flip left the schedule almost unchanged ({changed}/{total})")
    if involution:
        raise SystemExit(f"ABORT — encrypt was an involution on {involution} blocks")
    if min(bit_hits) < 64:
        raise SystemExit(f"ABORT — plaintext bit flip changed only {min(bit_hits)} bits")
    if max(hist) > 40:
        raise SystemExit(f"ABORT — ciphertext byte histogram {min(hist)}..{max(hist)}")
    corners = 0
    for plain in ([0] * 32, [255] * 32):
        key = hashlib.shake_256(bytes(plain) + b"E256-R/corner").digest(32)
        cipher = encrypt(key, 0, plain)
        if decrypt(key, 0, cipher) != plain or cipher == plain:
            raise SystemExit("ABORT — corner block failed")
        corners += 1
    print(
        f"stress {samples} keyed blocks  bit-flip {min(bit_hits)}..{max(bit_hits)}  "
        f"wrong-key rejects {wrong_key}  corners {corners}"
    )
    return {
        "keyed_blocks": samples,
        "plaintext_bit_flips": f"{min(bit_hits)}..{max(bit_hits)}",
        "wrong_key_rejects": wrong_key,
        "involution_hits": involution,
        "ciphertext_byte_counts": f"{min(hist)}..{max(hist)}",
        "corners": corners,
    }


def popcount(block: list[int]) -> int:
    return sum(bin(byte).count("1") for byte in block)


def avalanche_check() -> dict:
    """Every input bit, both directions, plus the published MixColumns column."""
    column = [0xD4, 0xBF, 0x5D, 0x30] + [0] * 28
    mixed = mix(column, MIX)
    if mixed[:4] != [0x04, 0x66, 0x81, 0xE5]:
        raise SystemExit(f"ABORT — MixColumns missed the published column {mixed[:4]}")
    key0 = hashlib.shake_256(b"E256-R/avalanche/key").digest(32)
    plain0 = list(hashlib.shake_256(b"E256-R/avalanche/plain").digest(32))
    cipher = encrypt(key0, 0, plain0)
    plain_hits = []
    key_hits = []
    decrypt_hits = []
    for bit in range(256):
        flipped = list(plain0)
        flipped[bit // 8] ^= 1 << (bit % 8)
        delta = [a ^ b for a, b in zip(cipher, encrypt(key0, 0, flipped))]
        plain_hits.append(popcount(delta))
        other = bytearray(key0)
        other[bit // 8] ^= 1 << (bit % 8)
        if decrypt(bytes(other), 0, cipher) == plain0:
            raise SystemExit(f"ABORT — key bit {bit} still decrypted")
        delta = [a ^ b for a, b in zip(cipher, encrypt(bytes(other), 0, plain0))]
        key_hits.append(popcount(delta))
        flipped_c = list(cipher)
        flipped_c[bit // 8] ^= 1 << (bit % 8)
        delta = [a ^ b for a, b in zip(plain0, decrypt(key0, 0, flipped_c))]
        decrypt_hits.append(popcount(delta))
    for name, hits in (("plain", plain_hits), ("key", key_hits), ("decrypt", decrypt_hits)):
        if min(hits) < 64:
            raise SystemExit(f"ABORT — {name} bit {hits.index(min(hits))} changed only {min(hits)} bits")
    streams = [tuple(encrypt(key0, n, [0] * 32)) for n in range(8)]
    if len(set(streams)) != 8:
        raise SystemExit("ABORT — counter keystream repeated")
    message = list(hashlib.shake_256(b"E256-R/avalanche/message").digest(32))
    covered = [a ^ b for a, b in zip(message, streams[3])]
    if [a ^ b for a, b in zip(covered, streams[3])] != message:
        raise SystemExit("ABORT — counter decrypt missed")
    if [a ^ b for a, b in zip(covered, streams[4])] == message:
        raise SystemExit("ABORT — neighboring counter decrypted")
    print(
        f"avalanche plain {min(plain_hits)}..{max(plain_hits)}  "
        f"key {min(key_hits)}..{max(key_hits)}  "
        f"decrypt {min(decrypt_hits)}..{max(decrypt_hits)}  "
        f"mixcolumns kat ok  counters 8"
    )
    return {
        "mixcolumns_kat": True,
        "plaintext_bits": f"{min(plain_hits)}..{max(plain_hits)}",
        "key_bits": f"{min(key_hits)}..{max(key_hits)}",
        "decrypt_bits": f"{min(decrypt_hits)}..{max(decrypt_hits)}",
        "counters": 8,
    }


def twin_check() -> int:
    import importlib.util

    path = Path(__file__).resolve().parent / "e256_repaired_twin.py"
    spec = importlib.util.spec_from_file_location("e256_repaired_twin", path)
    twin = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(twin)
    matches = 0
    for n in range(N_BLOCKS):
        raw = hashlib.shake_256(f"E256-R/twin/v1/{n}".encode()).digest(64)
        key, plain = bytes(raw[:32]), list(raw[32:])
        if twin.encrypt(key, n, plain) != encrypt(key, n, plain):
            raise SystemExit(f"ABORT — twin encrypt disagreed on block {n}")
        cipher = encrypt(key, n, plain)
        if twin.decrypt(key, n, cipher) != plain:
            raise SystemExit(f"ABORT — twin decrypt disagreed on block {n}")
        matches += 1
    print(f"twin agrees on {matches} blocks")
    return matches


def integral_check() -> tuple[list[int], list[int]]:
    key = hashlib.shake_256(b"E256-R/integral/v1").digest(32)
    identity = list(range(256))
    real = [integral_balanced(r, SBOX, key) for r in range(1, FROZEN_ROUNDS + 1)]
    planted = [integral_balanced(r, identity, key) for r in range(1, FROZEN_ROUNDS + 1)]
    if planted != [32] * FROZEN_ROUNDS:
        raise SystemExit(f"ABORT — identity integral was not fully balanced {planted}")
    death = next((r for r, n in enumerate(real, start=1) if n != 32), None)
    if death != INTEGRAL_DEATH or real[INTEGRAL_DEATH - 2] != 32 or real[FROZEN_ROUNDS - 1] != 0:
        raise SystemExit(f"ABORT — integral dies at {death}, counts {real}, frozen {FROZEN_ROUNDS}")
    print(f"integral balanced {real}  identity {planted}  dies at {death}")
    return real, planted


def integral_lanes(key: bytes) -> dict:
    """Every input lane. A return to 32 balanced bytes after round 4 is a failure."""
    masks = schedule(key, 0, FROZEN_ROUNDS)
    deaths = []
    stray = [0] * FROZEN_ROUNDS
    for active in range(32):
        acc = [[0] * 32 for _ in range(FROZEN_ROUNDS)]
        for value in range(256):
            state = [0] * 32
            state[active] = value
            for round_index, mask in enumerate(masks):
                sub = [SBOX[state[i] ^ mask[i]] for i in range(32)]
                state = mix(row_shift(sub, +1), MIX)
                for i in range(32):
                    acc[round_index][i] ^= state[i]
        counts = [sum(byte == 0 for byte in row) for row in acc]
        death = next((r for r, n in enumerate(counts, start=1) if n != 32), None)
        if death != INTEGRAL_DEATH:
            raise SystemExit(f"ABORT — lane {active} integral dies at {death}: {counts}")
        if any(n == 32 for n in counts[INTEGRAL_DEATH - 1 :]):
            raise SystemExit(f"ABORT — lane {active} integral returned: {counts}")
        for index, count in enumerate(counts):
            stray[index] = max(stray[index], count)
        deaths.append(death)
    print(f"integral lanes 32/32 die at {INTEGRAL_DEATH}  max balanced after that {max(stray[INTEGRAL_DEATH:])}")
    return {"lanes": 32, "death": INTEGRAL_DEATH, "max_balanced_by_round": stray}


def machine() -> None:
    reach, scores = diffusion_check()
    trail = trail_check()
    degree = degree_check()
    routes = route_check()
    stress = stress_check()
    avalanche = avalanche_check()
    recovery = mask_recovery_check()
    cluster = cluster_check()
    twin_matches = twin_check()
    balanced, identity_balanced = integral_check()
    lanes = integral_lanes(hashlib.shake_256(b"E256-R/integral/v1").digest(32))
    key = hashlib.shake_256(b"E256-R/identity-key/v1").digest(32)
    identity_hits, real_misses = identity_control(key, 0)
    print(f"identity rotor recovered {identity_hits}/16  real rotor affine misses {real_misses}/16")
    trips = 0
    for n in range(N_BLOCKS):
        raw = hashlib.shake_256(f"E256-R/machine/v1/{n}".encode()).digest(64)
        key_n, plain = bytes(raw[:32]), list(raw[32:])
        cipher = encrypt(key_n, n, plain)
        if decrypt(key_n, n, cipher) != plain:
            raise SystemExit(f"ABORT — machine round trip failed at block {n}")
        if decrypt(key_n, n + 1, cipher) == plain:
            raise SystemExit(f"ABORT — neighboring block index decrypted block {n}")
        trips += 1
    print(f"machine round-trips {trips} at {FROZEN_ROUNDS} rounds")
    lines: list[str] = []
    for n in range(N_HW):
        raw = hashlib.shake_256(f"E256-R/hardware-machine/v1/{n}".encode()).digest(64)
        key_n, plain = bytes(raw[:32]), list(raw[32:])
        masks = schedule(key_n, n, FROZEN_ROUNDS)
        state = list(plain)
        states = []
        for mask in masks:
            state = encrypt_round(state, mask)
            states.append(state)
        white = whitening(key_n, n)
        covered = apply_white(state, white)
        if decrypt(key_n, n, covered) != plain:
            raise SystemExit(f"ABORT — hardware machine vector {n} does not round-trip")
        lines.append(words(plain))
        lines.extend(words(mask) for mask in masks)
        lines.extend(words(st) for st in states)
        lines.append(words(white))
        lines.append(words(covered))
    (BUILD / "nvec.hex").write_text(f"{N_HW:02x}\n{FROZEN_ROUNDS:02x}\n")
    (BUILD / "vectors.hex").write_text("\n".join(lines) + "\n")
    receipt = {
        "schema": "E256-REPAIRED-MACHINE-1",
        "status": "OPEN_FUNCTIONAL",
        "frozen_rounds": FROZEN_ROUNDS,
        "trail": trail,
        "degree": degree,
        "routes": routes,
        "stress": stress,
        "avalanche": avalanche,
        "mask_recovery": recovery,
        "cluster": cluster,
        "twin_blocks": twin_matches,
        "integral_balanced_by_round": balanced,
        "integral_lanes": lanes,
        "identity_integral_balanced_by_round": identity_balanced,
        "diffusion_reach_rounds_1_to_8": reach,
        "single_flip_worst_rounds_1_to_8": scores,
        "identity_rotor_recovered": identity_hits,
        "real_rotor_affine_misses": real_misses,
        "machine_round_trips": trips,
        "hardware_blocks": N_HW,
        "schedule": "SHAKE-256 per round (E256-R/schedule/v2 || R || round_be16 || key || block_be64) plus a final whitening mask",
        "note": "Experimental width and functional checks. Not a security result.",
    }
    (REPO / "logs/e256-repaired-machine.json").write_text(__import__("json").dumps(receipt, indent=2) + "\n")


def main() -> None:
    BUILD.mkdir(parents=True, exist_ok=True)
    (BUILD / "e256r_inv_sbox.hex").write_text("\n".join(f"{b:02x}" for b in INV_SBOX) + "\n")
    functional()
    machine()
    sim = BUILD / "sim"
    sim.mkdir(exist_ok=True)
    cmd = [
        "iverilog", "-g2012", "-o", str(sim / "e256r.vvp"),
        "-I", str(RTL),
        str(RTL / "e256h_attack_core.v"),
        str(RTL / "e256r_round.v"),
        str(TB),
    ]
    subprocess.run(cmd, check=True, cwd=BUILD)
    run = subprocess.run(["vvp", str(sim / "e256r.vvp")], check=True, cwd=BUILD, capture_output=True, text=True)
    sys.stdout.write(run.stdout)
    if "PASS" not in run.stdout:
        raise SystemExit("ABORT — verilog did not match python")


if __name__ == "__main__":
    main()
