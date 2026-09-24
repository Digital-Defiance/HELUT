#!/usr/bin/env python3
"""Score a rotor setting by the plugboard marginal, not by the best board.

Phase 56.3 killed three proxies (ablation, swap, logsumexp-along-the-climb). They only saw
boards the greedy path had already walked. This probe estimates the integral that those
proxies were standing in for.

Thermodynamic integration (the identity used since Kirkwood, and in sampling since Neal):
for Z(β) = ∫ L(board)^β d(board) over a rotor-independent plugboard prior,

    log Z(1) - log Z(0) = ∫_0^1 E_β[log L] dβ.

Z(0) is the same volume for every message key. The integral therefore ranks the marginal
likelihood. A thin ghost spike contributes only while β is near 1. A broad basin contributes
across the schedule.

The walk is Metropolis–Hastings on legal ≤10-plug involutions. Proposals are symmetric
(add a pair, delete a pair, rewire one pair), so the accept ratio is only the tempered
score ratio. Truth and every decoy get the same schedule, the same step count, and no
plugboard from the record.

Progress requires BOTH a better margin than the greedy peak AND a better scale-free z,
on more than one seed. Margin alone is the compression trap from Phase 56.3.

This script does not load P1030680 and does not claim a decrypt.

    python3 Scripts/plugboard_marginal_probe.py --controls 4 --wrong 4 --seeds 2
"""
from __future__ import annotations

import argparse
import math
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from enigma_m4 import machine_from_record, norm  # noqa: E402
from lm_margin_probe import NGram, hill_climb_plugs, load_clean  # noqa: E402

A = ord("A")
MAX_PLUGS = 10


def board_pairs(board: tuple[int, ...]) -> list[tuple[int, int]]:
    """board[i] is the partner of i. A fixed point is an unplugged letter."""
    seen: set[int] = set()
    pairs: list[tuple[int, int]] = []
    for i, j in enumerate(board):
        if i in seen or i == j:
            continue
        pairs.append((i, j) if i < j else (j, i))
        seen.add(i)
        seen.add(j)
    return pairs


def identity_board() -> tuple[int, ...]:
    return tuple(range(26))


def apply_board(board: tuple[int, ...], a: int, b: int) -> tuple[int, ...]:
    """Swap the pairing of a and b. Endpoints that were plugged come unplugged."""
    nxt = list(board)
    pa, pb = nxt[a], nxt[b]
    nxt[pa] = pa
    nxt[pb] = pb
    nxt[a] = b
    nxt[b] = a
    return tuple(nxt)


def legal(board: tuple[int, ...]) -> bool:
    if len(board) != 26 or sorted(board) != list(range(26)):
        return False
    pairs = 0
    for i, j in enumerate(board):
        if board[j] != i:
            return False
        if i < j:
            pairs += 1
    return pairs <= MAX_PLUGS


def propose(board: tuple[int, ...], rng: random.Random) -> tuple[int, ...]:
    """Symmetric proposal: add, delete, or rewire one pair. Rejects illegal results."""
    pairs = board_pairs(board)
    free = [i for i in range(26) if board[i] == i]
    kind = rng.randrange(3)
    if kind == 0 and len(free) >= 2 and len(pairs) < MAX_PLUGS:
        a, b = rng.sample(free, 2)
        return apply_board(board, a, b)
    if kind == 1 and pairs:
        a, b = pairs[rng.randrange(len(pairs))]
        nxt = list(board)
        nxt[a], nxt[b] = a, b
        return tuple(nxt)
    if pairs and len(free) >= 1:
        a, _b = pairs[rng.randrange(len(pairs))]
        c = free[rng.randrange(len(free))]
        return apply_board(board, a, c)
    if len(free) >= 2 and len(pairs) < MAX_PLUGS:
        a, b = rng.sample(free, 2)
        return apply_board(board, a, b)
    return board


def plugs_of(board: tuple[int, ...]) -> str:
    return " ".join(f"{chr(A + a)}{chr(A + b)}" for a, b in board_pairs(board))


def joint_loglik(model: NGram, text: list[int]) -> float:
    """Sum log-probability. NGram.score is a mean; the integral needs the joint."""
    n = model.order
    counted = max(len(text) - n + 1, 1)
    return model.score(text) * counted


def decrypt(rec: dict, positions: str, board: tuple[int, ...], ct: list[int]) -> list[int]:
    spec = dict(rec)
    spec["plugs"] = plugs_of(board)
    return machine_from_record(spec, positions=positions).process(ct)


def thermodynamic_integral(
    rec: dict,
    positions: str,
    ct: list[int],
    model: NGram,
    rng: random.Random,
    betas: list[float],
    steps: int,
) -> float:
    """∫_0^1 E_β[log L] dβ by a tempered walk. Prior volume cancels across settings."""
    board = identity_board()
    cached = joint_loglik(model, decrypt(rec, positions, board, ct))
    expectations: list[float] = []
    for beta in betas:
        total = 0.0
        for _ in range(steps):
            trial = propose(board, rng)
            trial_ll = joint_loglik(model, decrypt(rec, positions, trial, ct))
            delta = beta * (trial_ll - cached)
            if delta >= 0 or rng.random() < math.exp(delta):
                board, cached = trial, trial_ll
            total += cached
        expectations.append(total / steps)
    # Trapezoid over the schedule. betas must be descending from 1 toward 0.
    area = 0.0
    for i in range(len(betas) - 1):
        width = abs(betas[i] - betas[i + 1])
        area += width * 0.5 * (expectations[i] + expectations[i + 1])
    return area


def median(xs: list[float]) -> float:
    s = sorted(xs)
    return s[len(s) // 2] if s else float("nan")


def summarize(truth: list[float], decoys: list[list[float]]) -> tuple[float, float, float, int]:
    """Median margin, median decoy sd, median z, wins. One entry per control."""
    margins, sds, zs, wins = [], [], [], 0
    for t, row in zip(truth, decoys):
        best = max(row)
        mean = sum(row) / len(row)
        var = sum((v - mean) ** 2 for v in row) / len(row)
        sd = math.sqrt(var)
        margins.append(t - best)
        sds.append(sd)
        if sd > 0:
            zs.append((t - mean) / sd)
        if t > best:
            wins += 1
    return median(margins), median(sds), median(zs), wins


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", type=Path, default=Path("Fixtures/u534_corpus.json"))
    ap.add_argument("--length", type=int, default=72)
    ap.add_argument("--order", type=int, default=4)
    ap.add_argument("--wrong", type=int, default=4)
    ap.add_argument("--controls", type=int, default=6, help="cap the clean-key pool; 0 = all")
    ap.add_argument("--seeds", type=int, default=2)
    ap.add_argument("--seed", type=int, default=20260924)
    ap.add_argument("--steps", type=int, default=24, help="MH steps at each temperature")
    ap.add_argument(
        "--betas",
        default="1,0.5,0.25,0.1,0.05,0.01,0",
        help="descending inverse temperatures for the thermodynamic path",
    )
    args = ap.parse_args()
    betas = [float(x) for x in args.betas.split(",")]
    if betas[0] != 1.0 or betas[-1] != 0.0 or any(betas[i] < betas[i + 1] for i in range(len(betas) - 1)):
        print("betas must descend from 1 to 0", file=sys.stderr)
        return 2

    clean = load_clean(args.corpus)
    pool = [r for r in clean
            if len(norm(r["ciphertext"])) >= args.length and len(norm(r["plaintext"])) >= args.length]
    if args.controls > 0:
        pool = pool[: args.controls]
    print(f"clean-key controls : {len(pool)} (72-letter capable pool {len(clean)} clean)")
    print(f"n-gram order       : {args.order} leave-one-out")
    print(f"wrong-key samples  : {args.wrong} per control, same shell")
    print(f"schedule           : {betas} × {args.steps} MH steps")
    print("truth and decoys walk the same prior. No record plugboard is loaded.")
    print()

    header = (f"{'seed':>6} {'method':>8} {'ctrls':>6} {'win%':>6} "
              f"{'med margin':>12} {'decoy sd':>10} {'med z':>8}  verdict")
    print(header)
    print("-" * len(header))

    for s in range(args.seeds):
        rng = random.Random(args.seed + s * 7919)
        peak_t, peak_d = [], []
        marg_t, marg_d = [], []
        for rec in pool:
            train = [norm(o["plaintext"]) for o in clean if o["id"] != rec["id"]]
            model = NGram(args.order).train(train)
            ct = norm(rec["ciphertext"])[: args.length]
            truth_pos = rec["wheel_positions"].upper()
            positions = [truth_pos] + _wrong(rec, args.wrong, rng)
            peaks, integrals = [], []
            for pos in positions:
                peak, _ = hill_climb_plugs(rec, pos, ct, model.score)
                # Joint scale, so peak and integral are comparable log-probabilities.
                counted = max(args.length - args.order + 1, 1)
                peaks.append(peak * counted)
                integrals.append(thermodynamic_integral(
                    rec, pos, ct, model, rng, betas, args.steps))
            peak_t.append(peaks[0])
            peak_d.append(peaks[1:])
            marg_t.append(integrals[0])
            marg_d.append(integrals[1:])

        base_m, base_sd, base_z, base_w = summarize(peak_t, peak_d)
        marg_m, marg_sd, marg_z, marg_w = summarize(marg_t, marg_d)
        n = len(peak_t)
        print(f"{args.seed + s * 7919:>6} {'peak':>8} {n:>6} {100 * base_w / n:>5.0f}% "
              f"{base_m:>12.4f} {base_sd:>10.4f} {base_z:>8.3f}  baseline")
        better_m = marg_m > base_m
        better_z = marg_z > base_z
        if better_m and better_z:
            verdict = "REAL separation gain"
        elif better_m and not better_z:
            verdict = "COMPRESSION ONLY — margin up, z down; not progress"
        elif better_z:
            verdict = "z up, margin not"
        else:
            verdict = "no better"
        print(f"{args.seed + s * 7919:>6} {'integral':>8} {n:>6} {100 * marg_w / n:>5.0f}% "
              f"{marg_m:>12.4f} {marg_sd:>10.4f} {marg_z:>8.3f}  {verdict}")
    print()
    print("A method counts only when margin AND z both beat peak, on more than one seed.")
    print("Single-seed movement is the Phase 56.3 failure mode.")
    return 0


def _wrong(rec: dict, samples: int, rng: random.Random) -> list[str]:
    truth = rec["wheel_positions"].upper()
    seen, out, guard = {truth}, [], 0
    while len(out) < samples and guard < samples * 50:
        guard += 1
        pos = "".join(chr(A + rng.randrange(26)) for _ in range(4))
        if pos not in seen:
            seen.add(pos)
            out.append(pos)
    return out


if __name__ == "__main__":
    raise SystemExit(main())
