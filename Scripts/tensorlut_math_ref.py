#!/usr/bin/env python3
"""TensorLUT math reference (Phase 0.95 R1–R4).

Stdlib only. No Metal, no Swift, no numpy.

Ports the C19 / C25 (structural) / C44 checks from TensorLUTFormal.swift
and the C27 practical-size clause from ggsw-public-ms-covering.md.
Plus a 4-bit involution sandwich, which is C19 clause 5 at toy scale.

The introductory example is a separate file: Scripts/toy_cipher_demo.py.

Not a new C-row. Agent-diffed against:
  Sources/HELUTCore/TensorLUTFormal.swift
  Sources/HELUTCore/HELUTCore.swift (LCG32)
  Sources/HELUTCore/AdversarialSynthesizer.swift (λ schedule)
  directives/ggsw-public-ms-covering.md (N=8 and N=128 only)

  python3 Scripts/tensorlut_math_ref.py
"""

from __future__ import annotations

import math
import sys

EPS = 1e-6


def discreteness_penalty(w: list[float]) -> float:
    return sum(x * (1.0 - x) for x in w)


def is_binary(w: list[float], eps: float = 1e-5) -> bool:
    return all(abs(x) <= eps or abs(x - 1.0) <= eps for x in w)


def emit_binary(w: list[float], threshold: float = 0.5) -> list[int]:
    return [1 if x >= threshold else 0 for x in w]


def crypto_fitness(y: list[float], t: list[float]) -> float:
    return -sum((a - b) * (a - b) for a, b in zip(y, t))


def lambda_at(current_gen: int, total_gens: int, lambda_max: float = 10.0, delay: float = 0.0) -> float:
    g = max(total_gens, 1)
    progress = min(1.0, max(0.0, current_gen / float(g)))
    if delay >= 1.0 or progress <= delay:
        delayed = 0.0
    else:
        delayed = (progress - delay) / (1.0 - delay)
    return lambda_max * delayed * delayed


def combine_fitness(fc: float, pi: float, current_gen: int, total_gens: int) -> float:
    return fc - lambda_at(current_gen, total_gens) * pi


def separable_coordinate_fitness(w: float, t: float, lam: float) -> float:
    return -(w - t) * (w - t) - lam * w * (1.0 - w)


class LCG32:
    """Numerical Recipes LCG — same constants as Sources/HELUTCore/HELUTCore.swift."""

    def __init__(self, state: int) -> None:
        self.state = 1 if state == 0 else state & 0xFFFFFFFF

    def next(self) -> int:
        self.state = (self.state * 1_664_525 + 1_013_904_223) & 0xFFFFFFFF
        return self.state


def stecker_is_valid(pairs: list[tuple[int, int]], alphabet: int = 26) -> bool:
    used: set[int] = set()
    for a, b in pairs:
        if a == b or not (0 <= a < alphabet) or not (0 <= b < alphabet) or a > b:
            return False
        if a in used or b in used:
            return False
        used.add(a)
        used.add(b)
    return True


def apply_pairs_twice(pairs: list[tuple[int, int]], n: int) -> bool:
    alphabet = list(range(n))
    for _ in range(2):
        for a, b in pairs:
            alphabet[a], alphabet[b] = alphabet[b], alphabet[a]
    return alphabet == list(range(n))


def check_discreteness(trials: int = 64, dim: int = 32, seed: int = 0x71A1) -> bool:
    rng = LCG32(seed)
    for _ in range(trials):
        w = [(rng.next() % 10_001) / 10_000 for _ in range(dim)]
        if discreteness_penalty(w) < -EPS:
            return False
    zeros = [0.0] * dim
    ones = [1.0] * dim
    if abs(discreteness_penalty(zeros)) > EPS or abs(discreteness_penalty(ones)) > EPS:
        return False
    mixed = zeros[:]
    for i in range(0, dim, 2):
        mixed[i] = 1.0
    if abs(discreteness_penalty(mixed)) > EPS:
        return False
    mid = [0.5] * dim
    return discreteness_penalty(mid) > 0


def check_crypto_mse() -> bool:
    y = [0.0, 1.0, 0.5]
    t = [0.0, 1.0, 0.5]
    if abs(crypto_fitness(y, t)) > EPS:
        return False
    bad = crypto_fitness([1.0, 0.0, 0.0], t)
    return bad < -0.5


def check_combined() -> bool:
    fc, pi = -1.0, 2.0
    f0 = combine_fitness(fc, pi, 0, 100)
    f1 = combine_fitness(fc, pi, 100, 100)
    if abs(f0 - fc) > 1e-5:
        return False
    return f1 < fc - 1.0


def check_emitter() -> bool:
    w = [0.0, 0.49, 0.5, 0.51, 1.0]
    b = emit_binary(w)
    if b != [0, 0, 1, 1, 1]:
        return False
    return emit_binary([float(x) for x in b]) == b


def check_involution() -> bool:
    ok = [(0, 1), (2, 3)]
    if not stecker_is_valid(ok):
        return False
    if stecker_is_valid([(0, 1), (1, 2)]):
        return False
    return apply_pairs_twice(ok, 26)


def check_freeze() -> bool:
    w = [0.5] * 128
    full = discreteness_penalty(w)
    for i in range(64, 128):
        w[i] = 0.0
    frozen = discreteness_penalty(w)
    return abs(frozen - full / 2) < 1e-3


def check_analytic_identities() -> bool:
    """Closed-form facts C19 assumes; not Monte Carlo."""
    grid = [i / 20.0 for i in range(21)]
    for x in grid:
        p = x * (1.0 - x)
        if p < -1e-12:
            return False
        at_end = abs(x) < 1e-12 or abs(x - 1.0) < 1e-12
        if at_end and abs(p) > 1e-12:
            return False
        if (not at_end) and p <= 0:
            return False
    # Same w, raise λ ⇒ F drops iff π>0. (C19 clause 3 — not “snap is better”.)
    w = [0.3, 0.7]
    pi = discreteness_penalty(w)
    fc = -1.0
    if not (combine_fitness(fc, pi, 100, 100) < combine_fitness(fc, pi, 0, 100) - EPS):
        return False
    if abs(combine_fitness(fc, 0.0, 100, 100) - fc) > 1e-9:
        return False
    # π([1/2]^n) = n/4
    n = 8
    if abs(discreteness_penalty([0.5] * n) - n / 4.0) > 1e-12:
        return False
    return True


def check_emitter_discrete_agreement(trials: int = 32, dim: int = 64, seed: int = 0xE1D1) -> bool:
    rng = LCG32(seed)
    for _ in range(trials):
        bits = [rng.next() & 1 for _ in range(dim)]
        w = [float(b) for b in bits]
        if not is_binary(w):
            return False
        if abs(discreteness_penalty(w)) > EPS:
            return False
        if emit_binary(w) != bits:
            return False
    soft = [0.1, 0.9, 0.5]
    return not is_binary(soft)


def check_involution_under_freeze_structural() -> bool:
    """C25 freeze clauses that do not need Swift's mutatedPreserving RNG."""
    frozen = [(0, 1), (2, 3)]
    if not stecker_is_valid(frozen):
        return False
    if stecker_is_valid(frozen + [(0, 7)]):
        return False
    merged = frozen + [(4, 5)]
    if not stecker_is_valid(merged):
        return False
    frozen_set = set(frozen)
    return frozen_set <= set(merged)


def check_separable_unique_maximizer(trials: int = 64, dim: int = 16, seed: int = 0x5A9) -> bool:
    rng = LCG32(seed)
    lambdas = [0.0, 0.5, 1.0, 8.0]
    for _ in range(trials):
        t = [float(rng.next() & 1) for _ in range(dim)]
        at_target = [separable_coordinate_fitness(ti, ti, 0.0) for ti in t]
        if any(abs(x) > EPS for x in at_target):
            return False
        for lam in lambdas:
            f_star = sum(separable_coordinate_fitness(ti, ti, lam) for ti in t)
            if abs(f_star) > 1e-5:
                return False
            w = []
            for i in range(dim):
                u = (rng.next() % 10_001) / 10_000
                if abs(u - t[i]) < 1e-4:
                    w.append(0.3 if t[i] == 0 else 0.7)
                else:
                    w.append(u)
            f_w = sum(separable_coordinate_fitness(wi, ti, lam) for wi, ti in zip(w, t))
            if not (f_w < f_star - EPS):
                return False
    return True


def check_snap_basin(trials: int = 48, dim: int = 32, seed: int = 0x5A10) -> bool:
    rng = LCG32(seed)
    for _ in range(trials):
        t = [rng.next() & 1 for _ in range(dim)]
        w = []
        for bit in t:
            interior = ((rng.next() % 4_000) + 1) / 10_000
            w.append(0.5 + interior if bit == 1 else 0.5 - interior)
        if emit_binary(w) != t:
            return False
        if abs(discreteness_penalty([float(b) for b in t])) > EPS:
            return False
        crossed = w[:]
        crossed[0] = 0.49 if t[0] == 1 else 0.51
        if emit_binary(crossed) == t:
            return False
    return True


def check_freeze_preserves_maximizer() -> bool:
    t = [0.0, 1.0, 0.0, 1.0]
    frozen_ok = [0.0, 1.0, 0.4, 0.6]
    lam = 4.0
    f_ok = sum(
        separable_coordinate_fitness(frozen_ok[i], t[i], lam) for i in range(2, 4)
    )
    f_star_free = separable_coordinate_fitness(0.0, 0.0, lam) + separable_coordinate_fitness(
        1.0, 1.0, lam
    )
    if not (f_ok < f_star_free - EPS):
        return False
    snapped = [0.0, 1.0, 0.0, 1.0]
    f_snapped = sum(separable_coordinate_fitness(snapped[i], t[i], lam) for i in range(2, 4))
    if abs(f_snapped) > EPS:
        return False
    wrong = [1.0, 1.0, 0.0, 1.0]
    f_wrong = sum(separable_coordinate_fitness(wi, ti, 0.0) for wi, ti in zip(wrong, t))
    return f_wrong < -0.5


def exact_public_ms_covering(n: int, word: int = 32) -> bool:
    """C27: (1+log2 N) | word, N power of two."""
    if n <= 0 or (n & (n - 1)) != 0:
        return False
    v = int(math.log2(n))
    base = 1 + v
    return word % base == 0


def check_c27_practical_sizes() -> bool:
    degrees = [2**v for v in range(3, 12)]  # 8..2048
    exact = [n for n in degrees if exact_public_ms_covering(n)]
    if exact != [8, 128]:
        return False
    if exact_public_ms_covering(1024):
        return False
    # q=2 (word=1): only N=1 would have 1+log2 N = 1. Not a HELUT FHE claim.
    if exact_public_ms_covering(8, word=1) or exact_public_ms_covering(1024, word=1):
        return False
    return True


C19 = [
    ("analyticIdentities", check_analytic_identities),
    ("cryptoFitnessMSE", check_crypto_mse),
    ("discretenessPenalty", check_discreteness),
    ("combinedObjective", check_combined),
    ("emitterThreshold", check_emitter),
    ("involutionSandwich", check_involution),
    ("freezeMask", check_freeze),
]

C25 = [
    ("emitterDiscreteAgreement", check_emitter_discrete_agreement),
    ("involutionUnderFreezeStructural", check_involution_under_freeze_structural),
]

C44 = [
    ("separableMeltUniqueMaximizer", check_separable_unique_maximizer),
    ("snapBasinCompleteness", check_snap_basin),
    ("freezePreservesMaximizer", check_freeze_preserves_maximizer),
]


def sbox_from_pairs(pairs: list[tuple[int, int]], n: int = 16) -> list[int]:
    s = list(range(n))
    for a, b in pairs:
        s[a], s[b] = s[b], s[a]
    return s


def is_involution_map(s: list[int]) -> bool:
    return all(s[s[x]] == x for x in range(len(s)))


def pairs_realize_map(pairs: list[tuple[int, int]], s: list[int]) -> bool:
    got = sbox_from_pairs(pairs, len(s))
    return got == s


def increment_has_valid_pair_encoding(n: int = 16) -> bool:
    """Broken S(x)=x+1 cannot be a partial involution of disjoint transpositions."""
    broken = [(x + 1) % n for x in range(n)]
    # Any valid pair list is an involution; increment is not.
    if is_involution_map(broken):
        return True
    return False


def toy_cipher() -> int:
    good_pairs = [(i, i + 1) for i in range(0, 16, 2)]
    good = sbox_from_pairs(good_pairs, 16)
    broken = [(x + 1) % 16 for x in range(16)]
    faults = sum(1 for x in range(16) if broken[broken[x]] != x)

    print("=== R2 toy cipher (4-bit S-box) ===")
    print(f"  good  involution: S(S(x))=x for all 16  pairs={good_pairs}")
    print(f"  good  sandwich valid: {stecker_is_valid(good_pairs, alphabet=16)}")
    print(f"  good  is_involution: {is_involution_map(good)}")
    print(f"  broken S(x)=x+1 (mod 16): S(S(x))=x+2 ≠ x on {faults}/16 letters")
    print(f"  broken is_involution: {is_involution_map(broken)}")
    fake_pairs = [(0, 1), (1, 2)]
    print(
        f"  architecture catch: overlapping encoding {fake_pairs} valid="
        f"{stecker_is_valid(fake_pairs, alphabet=16)}"
    )
    print(f"  increment has valid pair encoding: {increment_has_valid_pair_encoding()}")
    print("  (GA cannot propose a non-reciprocal map; the sandwich rejects it.)")

    t = [float((i & 1) ^ ((i >> 1) & 1)) for i in range(16)]
    w = [0.5] * 16
    lam = 4.0

    def f(weights: list[float]) -> float:
        return crypto_fitness(weights, t) - lam * discreteness_penalty(weights)

    f0 = f(w)
    w_snap = [0.2 if ti < 0.5 else 0.8 for ti in t]
    f1 = f(w_snap)
    emitted = emit_binary(w_snap)
    print(
        f"  XOR LUT4 λ-squeeze (separable, C44-shaped): F(½)={f0:.4f}  "
        f"F(near t)={f1:.4f}  emit==t {emitted == [int(x) for x in t]}"
    )
    if not is_involution_map(good) or is_involution_map(broken) or faults != 16:
        print("FAIL toy cipher")
        return 1
    if stecker_is_valid(fake_pairs, alphabet=16) or increment_has_valid_pair_encoding():
        print("FAIL sandwich did not catch broken map")
        return 1
    if f1 <= f0 or emitted != [int(x) for x in t]:
        print("FAIL λ-squeeze")
        return 1
    print("PASS toy cipher")
    return 0


def run_named(title: str, checks: list) -> int:
    print(f"=== {title} ===")
    failed = 0
    for name, fn in checks:
        ok = fn()
        print(f"  {'PASS' if ok else 'FAIL'}  {name}")
        if not ok:
            failed += 1
    print(f"{'PASS' if failed == 0 else 'FAIL'} {title}")
    return failed


def main() -> int:
    rc = 0
    rc += run_named("R1 C19 (Swift certificate + analytic)", C19)
    rc += run_named("C25 structural (no mutatedPreserving RNG)", C25)
    rc += run_named("C44 separable interpolant", C44)
    print("=== R4 C27 practical sizes (q=2^32 covering) ===")
    ok27 = check_c27_practical_sizes()
    print(f"  {'PASS' if ok27 else 'FAIL'}  exact covering N in {{8,16,...,2048}} = {{8,128}}")
    print("PASS C27 sizes" if ok27 else "FAIL C27 sizes")
    if not ok27:
        rc += 1
    rc += toy_cipher()
    print()
    print("Not a C-row. C25 omits mutatedPreserving (Swift RNG).")
    print("C19 uniqueness-of-w is NOT claimed — that is C44 (separable y=w).")
    print("q=2 FHE is NOT claimed — C27 at word=1 is a negative.")
    print("Statement: directives/tensorlut-theorem.md  plain: directives/theorem-1-plain.md")
    print("q-split: directives/q-32-vs-q-2.md")
    print("Start here instead, if this was your first file: INTRO.md and")
    print("  python3 Scripts/toy_cipher_demo.py")
    return 0 if rc == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
