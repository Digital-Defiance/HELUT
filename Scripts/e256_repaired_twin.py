#!/usr/bin/env python3
"""Second model of the repaired 4-round machine.

State is eight columns of four rows. This file does not import the other model.
"""

from __future__ import annotations

import hashlib

OFFSETS = (0, 1, 3, 4)
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
ROUNDS = 14
DOMAIN = b"E256-R/schedule/v2"


def mask_bytes(key: bytes, block_index: int, label: bytes) -> list[int]:
    raw = hashlib.shake_256(DOMAIN + label + key + block_index.to_bytes(8, "big")).digest(32)
    return list(raw)


def masks_for(key: bytes, block_index: int) -> tuple[list[list[list[int]]], list[list[int]]]:
    rounds = [columns_of(mask_bytes(key, block_index, b"R" + index.to_bytes(2, "big"))) for index in range(ROUNDS)]
    white = columns_of(mask_bytes(key, block_index, b"W"))
    return rounds, white


def encrypt(key: bytes, block_index: int, plain: list[int]) -> list[int]:
    rounds, white = masks_for(key, block_index)
    columns = columns_of(plain)
    for mask in rounds:
        keyed = [[SBOX[columns[c][r] ^ mask[c][r]] for r in range(4)] for c in range(8)]
        columns = apply_mix(shift(keyed, +1), MIX)
    flat = flatten(columns)
    cover = flatten(white)
    return [a ^ b for a, b in zip(flat, cover)]


def decrypt(key: bytes, block_index: int, cipher: list[int]) -> list[int]:
    rounds, white = masks_for(key, block_index)
    cover = flatten(white)
    columns = columns_of([a ^ b for a, b in zip(cipher, cover)])
    for mask in reversed(rounds):
        mixed = apply_mix(columns, INV)
        shifted = shift(mixed, -1)
        columns = [[INV_SBOX[shifted[c][r]] ^ mask[c][r] for r in range(4)] for c in range(8)]
    return flatten(columns)


def mul(a: int, b: int) -> int:
    acc = 0
    while b:
        if b & 1:
            acc ^= a
        a = ((a << 1) ^ 0x1B) & 0xFF if a & 0x80 else (a << 1) & 0xFF
        b >>= 1
    return acc


def sbox_table() -> list[int]:
    table = []
    for x in range(256):
        inv = 0
        if x:
            base, exp, inv = x, 254, 1
            while exp:
                if exp & 1:
                    inv = mul(inv, base)
                base = mul(base, base)
                exp >>= 1
        y = inv
        for shift in (1, 2, 3, 4):
            y ^= ((inv << shift) | (inv >> (8 - shift))) & 0xFF
        table.append(y ^ 0x63)
    return table


SBOX = sbox_table()
INV_SBOX = [0] * 256
for index, value in enumerate(SBOX):
    INV_SBOX[value] = index


def columns_of(block: list[int]) -> list[list[int]]:
    return [[block[4 * column + row] for row in range(4)] for column in range(8)]


def flatten(columns: list[list[int]]) -> list[int]:
    return [columns[column][row] for column in range(8) for row in range(4)]


def apply_mix(columns: list[list[int]], matrix) -> list[list[int]]:
    out = []
    for column in columns:
        mixed = []
        for row in range(4):
            acc = 0
            for k in range(4):
                acc ^= mul(matrix[row][k], column[k])
            mixed.append(acc)
        out.append(mixed)
    return out


def shift(columns: list[list[int]], sign: int) -> list[list[int]]:
    out = [[0] * 4 for _ in range(8)]
    for column in range(8):
        for row in range(4):
            src = (column + sign * OFFSETS[row]) % 8
            out[column][row] = columns[src][row]
    return out

