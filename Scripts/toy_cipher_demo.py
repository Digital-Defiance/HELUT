#!/usr/bin/env python3
"""Two toy ciphers, same skeleton. One merely weak, one broken on purpose.

Runs anywhere python3 runs. Stdlib only: no Swift, no Metal, no numpy, no
pip install. This is the introductory module -- you do not need the rest of
the repo to read it.

    python3 Scripts/toy_cipher_demo.py

Both ciphers are 16-bit block, 16-bit key, 4-round substitution-permutation
networks. Identical wiring, identical key schedule, identical round count.
The only difference is the 4-bit S-box:

    NONLINEAR  the PRESENT S-box -- differentially 4-uniform
    AFFINE     a GF(2)-linear map plus a constant -- invertible, looks
               scrambled, and is a linear equation in disguise

Neither is a real cipher. A 16-bit key dies to exhaustive search in under a
second, and four rounds is far too few: the measured best differential for the
nonlinear version is about 2^-10 where an ideal 16-bit permutation would give
2^-16, so it is weak on its own terms. That is deliberate. The comparison is
between weak and structurally dead, which is a more useful thing to learn to
see than between strong and weak.
"""

from __future__ import annotations

import itertools
import math
import random
import sys

BLOCK_BITS = 16
NIBBLES = 4
ROUNDS = 4

# PRESENT S-box (Bogdanov et al., CHES 2007). Nonlinear, DDT max 4.
S_SOUND = [0xC, 0x5, 0x6, 0xB, 0x9, 0x0, 0xA, 0xD, 0x3, 0xE, 0xF, 0x8, 0x4, 0x7, 0x1, 0x2]

# Broken by design: output bit i is the XOR of the input bits in MASKS[i],
# then XOR a constant. Invertible, and every output bit is a parity of the
# input bits, which is exactly the property that kills it.
MASKS = [0b0011, 0b0101, 0b1010, 0b1101]
AFFINE_CONST = 0xB


def parity(x: int) -> int:
    return bin(x).count("1") & 1


def build_affine_sbox() -> list[int]:
    table = []
    for x in range(16):
        y = 0
        for i, m in enumerate(MASKS):
            y |= parity(x & m) << i
        table.append(y ^ AFFINE_CONST)
    return table


S_BROKEN = build_affine_sbox()

# Bit permutation across the whole 16-bit block: bit j moves to position
# P[j]. Spreads each nibble's output over all four nibbles, PRESENT-style.
P = [(4 * (j % 4) + j // 4) for j in range(BLOCK_BITS)]


def permute(x: int) -> int:
    y = 0
    for j in range(BLOCK_BITS):
        if (x >> j) & 1:
            y |= 1 << P[j]
    return y


def sbox_layer(x: int, sbox: list[int]) -> int:
    y = 0
    for n in range(NIBBLES):
        nib = (x >> (4 * n)) & 0xF
        y |= sbox[nib] << (4 * n)
    return y


def rotl16(x: int, r: int) -> int:
    r %= 16
    return ((x << r) | (x >> (16 - r))) & 0xFFFF


def round_keys(key: int) -> list[int]:
    return [rotl16(key, 3 * r) for r in range(ROUNDS + 1)]


def encrypt(plain: int, key: int, sbox: list[int]) -> int:
    rk = round_keys(key)
    x = plain & 0xFFFF
    for r in range(ROUNDS):
        x ^= rk[r]
        x = sbox_layer(x, sbox)
        x = permute(x)
    return x ^ rk[ROUNDS]


# ---------------------------------------------------------------- test 1
# The S-box on its own. A cryptographer looks here first.


def ddt_max(sbox: list[int]) -> int:
    """Largest count in the difference distribution table, ignoring 0 -> 0.

    For input difference a, count how often S(x) ^ S(x^a) hits one value.
    Low is good. A linear map sends every x to the same output difference,
    so it scores the worst possible 16.
    """
    worst = 0
    for a in range(1, 16):
        counts = [0] * 16
        for x in range(16):
            counts[sbox[x] ^ sbox[x ^ a]] += 1
        worst = max(worst, max(counts))
    return worst


def is_bijection(sbox: list[int]) -> bool:
    return sorted(sbox) == list(range(16))


# ---------------------------------------------------------------- test 2
# Black-box affineness. No S-box internals, no key. Just three encryptions.


def affineness_failures(sbox: list[int], key: int, trials: int, rng: random.Random) -> int:
    """Count triples where E(x)^E(y)^E(z) != E(x^y^z).

    Any affine map over GF(2) satisfies that identity for every triple, so
    an affine cipher scores 0 failures. A sound cipher fails almost always.
    """
    bad = 0
    for _ in range(trials):
        x = rng.getrandbits(16)
        y = rng.getrandbits(16)
        z = rng.getrandbits(16)
        lhs = encrypt(x, key, sbox) ^ encrypt(y, key, sbox) ^ encrypt(z, key, sbox)
        rhs = encrypt(x ^ y ^ z, key, sbox)
        if lhs != rhs:
            bad += 1
    return bad


# ---------------------------------------------------------------- test 3
# Key-independent linear part, then one known plaintext reads everything.


def linear_part(sbox: list[int]) -> list[int]:
    """Columns of the matrix A with E_k(x) = A.x ^ c(k), assuming affine.

    A is key-independent, so we extract it with any key we like -- key 0 --
    and it stays valid against an unknown key.
    """
    base = encrypt(0, 0, sbox)
    return [encrypt(1 << j, 0, sbox) ^ base for j in range(BLOCK_BITS)]


def apply_matrix(cols: list[int], x: int) -> int:
    y = 0
    for j in range(BLOCK_BITS):
        if (x >> j) & 1:
            y ^= cols[j]
    return y


def invert_matrix(cols: list[int]) -> list[int] | None:
    """Gauss-Jordan over GF(2). Returns columns of the inverse, or None."""
    rows = []
    for i in range(BLOCK_BITS):
        row = 0
        for j in range(BLOCK_BITS):
            if (cols[j] >> i) & 1:
                row |= 1 << j
        rows.append(row | (1 << (BLOCK_BITS + i)))
    pivot_of = {}
    r = 0
    for c in range(BLOCK_BITS):
        p = next((k for k in range(r, BLOCK_BITS) if (rows[k] >> c) & 1), None)
        if p is None:
            return None
        rows[r], rows[p] = rows[p], rows[r]
        for k in range(BLOCK_BITS):
            if k != r and (rows[k] >> c) & 1:
                rows[k] ^= rows[r]
        pivot_of[c] = r
        r += 1
    inv_cols = [0] * BLOCK_BITS
    for c in range(BLOCK_BITS):
        aug = rows[pivot_of[c]] >> BLOCK_BITS
        for j in range(BLOCK_BITS):
            if (aug >> j) & 1:
                inv_cols[j] |= 1 << c
    return inv_cols


def one_known_plaintext_attack(
    sbox: list[int], key: int, samples: list[int]
) -> tuple[int, int, bool]:
    """Assume affine, recover the offset from one pair, decrypt the rest.

    Returns (correct, total, model_fitted). Zero key search: the attacker
    never guesses. If the extracted matrix is singular the affine model does
    not even get off the ground, which is itself a rejection.
    """
    cols = linear_part(sbox)
    inv = invert_matrix(cols)
    if inv is None:
        return (0, len(samples), False)
    known_p = samples[0]
    known_c = encrypt(known_p, key, sbox)
    offset = known_c ^ apply_matrix(cols, known_p)
    correct = 0
    for p in samples:
        guess = apply_matrix(inv, encrypt(p, key, sbox) ^ offset)
        if guess == p:
            correct += 1
    return (correct, len(samples), True)


def exhaustive_key_search(sbox: list[int], key: int, pairs: list[tuple[int, int]]) -> int:
    """How many candidate keys we walk before the real one fits. Toy sizes."""
    for candidate in range(1 << 16):
        if all(encrypt(p, candidate, sbox) == c for p, c in pairs):
            return candidate
    return -1


# ---------------------------------------------------------------- test 4
# Quantitative, not yes/no: how biased is the full 4-round cipher?


def _fast_round_tables(sbox: list[int]) -> list[list[int]]:
    """Fold the S-box layer and the bit permutation into nibble lookup tables."""
    tables = []
    for n in range(NIBBLES):
        col = []
        for nib in range(16):
            v = sbox[nib] << (4 * n)
            y = 0
            for j in range(BLOCK_BITS):
                if (v >> j) & 1:
                    y |= 1 << P[j]
            col.append(y)
        tables.append(col)
    return tables


def _encrypt_fast(x: int, rk: list[int], t: list[list[int]]) -> int:
    for r in range(ROUNDS):
        x ^= rk[r]
        x = t[0][x & 0xF] | t[1][(x >> 4) & 0xF] | t[2][(x >> 8) & 0xF] | t[3][(x >> 12) & 0xF]
    return x ^ rk[ROUNDS]


def low_weight_differences() -> list[int]:
    """All one- and two-bit input differences: 136 of them, where characteristics live."""
    single = [1 << i for i in range(BLOCK_BITS)]
    double = [(1 << i) | (1 << j) for i, j in itertools.combinations(range(BLOCK_BITS), 2)]
    return single + double


def best_differential(sbox: list[int], key: int) -> tuple[int, int, int]:
    """Exact best differential over the whole codebook, for each sampled difference.

    Counts are exact, not sampled: every one of the 2^16 plaintexts is used.
    Only the set of input differences is restricted. A perfect 16-bit
    permutation would score about 1/65536 for every pair.
    """
    tables = _fast_round_tables(sbox)
    rk = round_keys(key)
    cipher = [_encrypt_fast(x, rk, tables) for x in range(1 << BLOCK_BITS)]
    best = (0, 0, 0)
    for a in low_weight_differences():
        counts: dict[int, int] = {}
        for x in range(1 << BLOCK_BITS):
            d = cipher[x] ^ cipher[x ^ a]
            counts[d] = counts.get(d, 0) + 1
        out, hits = max(counts.items(), key=lambda kv: kv[1])
        if hits > best[0]:
            best = (hits, a, out)
    return best


# ---------------------------------------------------------------- test 5
# The same test as 2, one level down, on the object HELUT actually manipulates.


def lut_inits(sbox: list[int]) -> list[int]:
    """Each S-box output bit as a 4-input truth table.

    Bit i of the constant is output bit b evaluated on input pattern i. This
    is the truth table a `$lut` cell carries in a synthesised netlist, called
    the INIT in this repo, and in the continuous-LUT work it is the vector of
    sliders the optimiser moves.
    """
    inits = []
    for b in range(4):
        init = 0
        for x in range(16):
            init |= ((sbox[x] >> b) & 1) << x
        inits.append(init)
    return inits


def init_is_affine(init: int) -> bool:
    """f(x)^f(y)^f(z)^f(x^y^z) == 0 for all triples -- same identity as test 2."""

    def f(x: int) -> int:
        return (init >> x) & 1

    return all(
        f(x) ^ f(y) ^ f(z) ^ f(x ^ y ^ z) == 0
        for x, y, z in itertools.product(range(16), repeat=3)
    )


# ---------------------------------------------------------------- report


def show(name: str, sbox: list[int], key: int, rng: random.Random) -> dict:
    print(f"--- {name} ---")
    print(f"  S-box            {[f'{v:X}' for v in sbox]}")
    print(f"  invertible       {is_bijection(sbox)}")

    ddt = ddt_max(sbox)
    print(f"  DDT max          {ddt}/16   (4 is good for a 4-bit box, 16 is a linear map)")

    trials = 200
    bad = affineness_failures(sbox, key, trials, rng)
    print(f"  affineness test  {bad}/{trials} triples broke the XOR identity")
    print(f"                   {'nonlinear, as intended' if bad else 'AFFINE -- the whole cipher is linear'}")

    hits, in_diff, out_diff = best_differential(sbox, key)
    prob = hits / 65536
    print(
        f"  best 4-round     0x{in_diff:04X} -> 0x{out_diff:04X} holds {hits}/65536 "
        f"= 2^{math.log2(prob):.1f}"
    )
    print("                   (ideal 16-bit permutation: about 2^-16)")

    inits = lut_inits(sbox)
    flags = [init_is_affine(i) for i in inits]
    print(f"  LUT4 INITs       {' '.join(f'{i:04X}' for i in inits)}")
    print(f"  INIT affine?     {flags}")

    samples = [rng.getrandbits(16) for _ in range(64)]
    correct, total, fitted = one_known_plaintext_attack(sbox, key, samples)
    print(f"  1 known pair     recovered {correct}/{total} plaintexts, 0 keys tried")
    if not fitted:
        print("                   (affine model is singular here -- it never even fits)")

    return {
        "ddt": ddt,
        "bad": bad,
        "affine_inits": flags,
        "recovered": correct,
        "total": total,
        "best_diff": hits,
    }


def main() -> int:
    rng = random.Random(20260815)
    key = rng.getrandbits(16)

    print(__doc__.strip().splitlines()[0])
    print()
    print(f"Secret key for this run: 0x{key:04X} (the attacks below never look at it)")
    print()

    sound = show("NONLINEAR S-box (sound structure, too few rounds)", S_SOUND, key, rng)
    print()
    broken = show("AFFINE S-box (broken by design)", S_BROKEN, key, rng)
    print()

    print("--- how you spot the difference ---")
    print("  1. S-box DDT:    4 vs 16. Visible without touching the cipher.")
    print("  2. XOR identity: 3 encryptions per triple, black box, no key needed.")
    print("  3. Consequence:  the affine one needs one known pair, not a key search.")
    print(
        f"  4. Best diff:    2^{math.log2(sound['best_diff'] / 65536):.0f} vs "
        f"2^{math.log2(broken['best_diff'] / 65536):.0f}. Both are weak; only one is certain."
    )
    print("  5. Netlist view: every affine INIT is a parity of its inputs.")
    print()

    print("--- cost of the honest attack, for contrast ---")
    pairs = [(p, encrypt(p, key, S_SOUND)) for p in (0x0000, 0x1234, 0xBEEF)]
    found = exhaustive_key_search(S_SOUND, key, pairs)
    print(f"  nonlinear cipher, exhaustive 16-bit search: key 0x{found:04X} after {found + 1} tries")
    print("  affine cipher: no search at all -- see above")
    print()

    ok = (
        is_bijection(S_SOUND)
        and is_bijection(S_BROKEN)
        and sound["ddt"] == 4
        and broken["ddt"] == 16
        and sound["bad"] > 0
        and broken["bad"] == 0
        and not any(sound["affine_inits"])
        and all(broken["affine_inits"])
        and broken["recovered"] == broken["total"]
        and sound["recovered"] < sound["total"]
        and broken["best_diff"] == 65536
        and sound["best_diff"] < 65536
        and found == key
    )
    print("PASS both ciphers behaved as advertised" if ok else "FAIL demo did not behave as advertised")
    print()
    print("What this shows: a deliberately broken cipher is caught by")
    print("elementary tests, at the cipher level and again at the LUT level,")
    print("and the same tests put a number on how weak its honest sibling is.")
    print("What it does not show: that HELUT found either flaw, that the")
    print("nonlinear toy is secure (it is not, see the 2^-10 above), or")
    print("anything about encrypted evaluation. Differential and linear")
    print("cryptanalysis are Biham-Shamir and Matsui, early nineties. The")
    print("only HELUT-specific part is test 5's INITs, which are the objects")
    print("the LUT optimiser moves.")
    print()
    print("Next, if you want the theorem behind that optimiser:")
    print("  python3 Scripts/tensorlut_math_ref.py")
    print("  directives/theorem-1-plain.md")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
