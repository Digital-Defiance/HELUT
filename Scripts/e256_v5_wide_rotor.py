#!/usr/bin/env python3
"""16-bit inverse rotor against the AES 8-bit S-box.

The map is x -> x^{2^n-2} in GF(2^n). n=8 calibrates the checker.
n=16 is the wider rotor. Not installed in E256-v5.
"""

from __future__ import annotations

import numpy as np

POLY8 = 0x11B
POLY16 = 0x1100B


def gf_mul(a: int, b: int, poly: int, bits: int) -> int:
    top = 1 << (bits - 1)
    mod = poly ^ (1 << bits)
    acc = 0
    for _ in range(bits):
        if b & 1:
            acc ^= a
        b >>= 1
        carry = a & top
        a = (a << 1) & ((1 << bits) - 1)
        if carry:
            a ^= mod
    return acc


def inverse_table(bits: int, poly: int) -> np.ndarray:
    size = 1 << bits
    table = np.zeros(size, dtype=np.uint32)
    for value in range(1, size):
        base, exp, acc = value, (1 << bits) - 2, 1
        while exp:
            if exp & 1:
                acc = gf_mul(acc, base, poly, bits)
            base = gf_mul(base, base, poly, bits)
            exp >>= 1
        table[value] = acc
    return table


def differential_peak(table: np.ndarray) -> int:
    size = table.shape[0]
    xs = np.arange(size, dtype=np.uint32)
    peak = 0
    for delta in range(1, size):
        image = table[xs] ^ table[xs ^ delta]
        counts = np.bincount(image, minlength=size)
        peak = max(peak, int(counts.max()))
    return peak


def output_degree(table: np.ndarray, bits: int) -> int:
    size = 1 << bits
    coeffs = (table & 1).astype(np.uint8).copy()
    for bit in range(bits):
        step = 1 << bit
        for mask in range(size):
            if mask & step:
                coeffs[mask] ^= coeffs[mask ^ step]
    degree = 0
    for mask, coeff in enumerate(coeffs.tolist()):
        if coeff:
            degree = max(degree, bin(mask).count("1"))
    return degree


def coordinate_walsh(table: np.ndarray, bits: int) -> int:
    size = 1 << bits
    peak = 0
    for bit in range(bits):
        values = np.where((table >> bit) & 1, -1, 1).astype(np.int32)
        step = 1
        while step < size:
            for start in range(0, size, step * 2):
                left = values[start : start + step].copy()
                right = values[start + step : start + 2 * step].copy()
                values[start : start + step] = left + right
                values[start + step : start + 2 * step] = left - right
            step *= 2
        local = int(np.max(np.abs(values[1:])))
        peak = max(peak, local)
    return peak


def main() -> None:
    small = inverse_table(8, POLY8)
    small_peak = differential_peak(small)
    small_degree = output_degree(small, 8)
    small_walsh = coordinate_walsh(small, 8)
    print(
        f"GF(2^8) inverse  differential {small_peak}/256 = 2^{np.log2(small_peak / 256):.0f}  "
        f"degree {small_degree}  coordinate walsh {small_walsh}"
    )
    if small_peak != 4 or small_degree != 7:
        raise SystemExit("ABORT — 8-bit inverse calibration failed")

    wide = inverse_table(16, POLY16)
    if int(wide[1]) != 1 or int(wide[wide[2]]) != 2:
        raise SystemExit("ABORT — 16-bit inverse is not an involution on the nonzero field")
    wide_degree = output_degree(wide, 16)
    wide_walsh = coordinate_walsh(wide, 16)
    print(f"GF(2^16) inverse  degree {wide_degree}  coordinate walsh {wide_walsh}")
    print("differential scan running")
    wide_peak = differential_peak(wide)
    prob = wide_peak / 65536
    print(
        f"GF(2^16) inverse  differential {wide_peak}/65536 = 2^{np.log2(prob):.0f}  "
        f"AES box is 4/256 = 2^-6"
    )


if __name__ == "__main__":
    main()
