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
FROZEN_ROUNDS = 4
SCHEDULE_DOMAIN = b"E256-R/schedule/v1"


def schedule(key: bytes, block_index: int, rounds: int) -> list[list[int]]:
    raw = hashlib.shake_256(SCHEDULE_DOMAIN + key + block_index.to_bytes(8, "big")).digest(rounds * 32)
    return [list(raw[r * 32 : (r + 1) * 32]) for r in range(rounds)]


def encrypt(key: bytes, block_index: int, plain: list[int], rounds: int = FROZEN_ROUNDS) -> list[int]:
    return encrypt_block(plain, schedule(key, block_index, rounds))


def decrypt(key: bytes, block_index: int, cipher: list[int], rounds: int = FROZEN_ROUNDS) -> list[int]:
    return decrypt_block(cipher, schedule(key, block_index, rounds))


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
    result = {
        "minors_evaluated": minors["evaluated"],
        "zero_minors": minors["zeros"],
        "offsets_distinct": True,
        "bundle_cases_meet_five": True,
        "active_sboxes_lower_bound": 25,
        "differential_peak": peak,
        "walsh_peak": linear,
        "single_trail_differential_log2_upper": -150,
        "single_trail_linear_log2_upper": -75,
        "identity_differential_peak": identity_peak,
        "identity_bound_applies": False,
        "mix_off_zero_minors": mix_off["zeros"],
        "mix_off_byte_reach_at_frozen_rounds": no_mix_reach,
    }
    print(
        f"trail minors {minors['evaluated']} zero {minors['zeros']}  "
        f"bound 25  differential peak {peak}  walsh peak {linear}  "
        f"identity peak {identity_peak}  mix-off reach {no_mix_reach}"
    )
    return result


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
    carried, continuation, active = carry_difference(merged, ddt, rounds=2)
    if continuation == 0 or active == 0:
        raise SystemExit("ABORT — four-round continuation has no trail")
    ratio = total / best
    four_cluster = total * continuation
    four_best = best * continuation
    sboxes = 5 + active
    print(
        f"cluster 1-round extras {one_round_extra}  "
        f"2-round trails {trails}  weight {total} best {best} ratio {ratio:.3f}  "
        f"identity trails {identity_trails}  "
        f"4-round carried trails {trails}  sboxes {sboxes}  "
        f"cluster_weight {four_cluster} best_weight {four_best}"
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
        "four_round_carried_trails": trails,
        "four_round_continuation_sboxes": active,
        "four_round_sboxes_on_exhibited_trail": sboxes,
        "four_round_cluster_weight": four_cluster,
        "four_round_best_trail_weight": four_best,
        "four_round_ratio_lower_bound": ratio,
        "four_round_cluster_log2_upper_note": "ratio only; not the full differential sum",
    }


def twin_check() -> int:
    import importlib.util

    path = Path(__file__).resolve().parent / "e256_repaired_twin.py"
    spec = importlib.util.spec_from_file_location("e256_repaired_twin", path)
    twin = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(twin)
    matches = 0
    for n in range(32):
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
    real = [integral_balanced(r, SBOX, key) for r in range(1, 9)]
    planted = [integral_balanced(r, identity, key) for r in range(1, 9)]
    if planted != [32] * 8:
        raise SystemExit(f"ABORT — identity integral was not fully balanced {planted}")
    death = next((r for r, n in enumerate(real, start=1) if n != 32), None)
    if death != FROZEN_ROUNDS or real[FROZEN_ROUNDS - 2] != 32:
        raise SystemExit(f"ABORT — integral dies at {death}, counts {real}, frozen {FROZEN_ROUNDS}")
    print(f"integral balanced {real}  identity {planted}  dies at {death}")
    return real, planted


def machine() -> None:
    reach, scores = diffusion_check()
    trail = trail_check()
    cluster = cluster_check()
    twin_matches = twin_check()
    balanced, identity_balanced = integral_check()
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
        if decrypt(key_n, n, state) != plain:
            raise SystemExit(f"ABORT — hardware machine vector {n} does not round-trip")
        lines.append(words(plain))
        lines.extend(words(mask) for mask in masks)
        lines.extend(words(st) for st in states)
    (BUILD / "nvec.hex").write_text(f"{N_HW:02x}\n{FROZEN_ROUNDS:02x}\n")
    (BUILD / "vectors.hex").write_text("\n".join(lines) + "\n")
    receipt = {
        "schema": "E256-REPAIRED-MACHINE-1",
        "status": "OPEN_FUNCTIONAL",
        "frozen_rounds": FROZEN_ROUNDS,
        "trail": trail,
        "cluster": cluster,
        "twin_blocks": twin_matches,
        "integral_balanced_by_round": balanced,
        "identity_integral_balanced_by_round": identity_balanced,
        "diffusion_reach_rounds_1_to_8": reach,
        "single_flip_worst_rounds_1_to_8": scores,
        "identity_rotor_recovered": identity_hits,
        "real_rotor_affine_misses": real_misses,
        "machine_round_trips": trips,
        "hardware_blocks": N_HW,
        "schedule": "SHAKE-256(E256-R/schedule/v1 || key || block_index_be64)",
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
