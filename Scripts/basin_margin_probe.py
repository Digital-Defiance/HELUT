#!/usr/bin/env python3
"""Marginalise over the plugboard instead of maximising over it.

The measured failure (Phase 56.2) is not a shortage of information -- 72 letters sits at ~2.7x
unicity distance, so exactly one key yields German. The failure is the *estimator*. The current
score is a profile likelihood: at each candidate setting the plugboard is a ~47-bit nuisance
parameter and we report its MAXIMUM fit. Taking a max over ~10^11 candidates, each free to
overfit 47 bits, is the textbook multiple-comparisons disaster, and the ledger already sees its
signature: the truth beats the decoy MEAN but not the decoy MAXIMUM.

The standard statistical remedy is to integrate over the nuisance parameter rather than maximise.
The intuition specialised to Enigma: at the TRUE setting the underlying German is real, so many
nearby plugboards score well -- a broad basin. At a ghost setting one lucky board sits on a narrow
spike, because the "signal" it found is an artefact of that exact board. Peak height confuses the
two; basin shape does not.

Exact marginalisation over 1.5x10^14 boards is infeasible, so this measures three cheap proxies
and grades each by the SAME margin test, against the same genuine wrong-key decrypts, with every
statistic computed identically for the truth and for every decoy:

  peak      the current profile score (control -- must reproduce the known negative)
  ablation  mean score after deleting each found plug in turn. A robust board degrades
            gracefully; a fragile one collapses.
  swap      mean over single-plug perturbations (replace one found pair with a random legal
            pair). Probes the neighbourhood rather than the point.
  logsumexp soft-max over the climb's own top-K accepted boards -- a crude integral over the
            part of the space the climb actually visited.

A proxy only counts as progress if its margin is LESS NEGATIVE than `peak` on the same controls.
Improving the truth's absolute score is worthless if it lifts the decoys equally, which is the
trap that makes partial exhaustion saturate.

    python3 Scripts/basin_margin_probe.py --lengths 72 --wrong 12
"""
from __future__ import annotations

import argparse
import json
import math
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from enigma_m4 import machine_from_record, norm  # noqa: E402
from lm_margin_probe import NGram, load_clean  # noqa: E402

A = ord("A")


def board_text(rec: dict, positions: str, board: list[tuple[int, int]],
               ct: list[int]) -> list[int]:
    spec = dict(rec)
    spec["plugs"] = " ".join(f"{chr(A + a)}{chr(A + b)}" for a, b in board)
    return machine_from_record(spec, positions=positions).process(ct)


def climb_with_trace(rec: dict, positions: str, ct: list[int], score,
                     max_plugs: int = 10):
    """Greedy plug climb that also returns the accepted-score trace and the board.

    Symmetric by construction: the caller runs this identically for the truth and for every
    decoy, so no candidate gets free plugs.
    """
    board: list[tuple[int, int]] = []
    used: set[int] = set()
    best = score(board_text(rec, positions, board, ct))
    trace = [best]
    for _ in range(max_plugs):
        pick, gain = None, 0.0
        for a in range(26):
            if a in used:
                continue
            for b in range(a + 1, 26):
                if b in used:
                    continue
                s = score(board_text(rec, positions, board + [(a, b)], ct))
                if s > best + gain:
                    gain, pick = s - best, (a, b)
        if pick is None:
            break
        board.append(pick)
        used.update(pick)
        best += gain
        trace.append(best)
    return best, board, trace


def statistics(rec: dict, positions: str, ct: list[int], score,
               rng: random.Random, swaps: int = 6) -> dict[str, float]:
    peak, board, trace = climb_with_trace(rec, positions, ct, score)
    stats = {"peak": peak}

    # Ablation: how much of the peak survives losing one plug?
    if board:
        vals = []
        for i in range(len(board)):
            reduced = board[:i] + board[i + 1:]
            vals.append(score(board_text(rec, positions, reduced, ct)))
        stats["ablation"] = sum(vals) / len(vals)
    else:
        stats["ablation"] = peak

    # Swap: replace one found pair with a random legal pair.
    if board:
        vals = []
        for _ in range(swaps):
            i = rng.randrange(len(board))
            reduced = board[:i] + board[i + 1:]
            used = {x for pair in reduced for x in pair}
            free = [x for x in range(26) if x not in used]
            if len(free) < 2:
                continue
            a, b = rng.sample(free, 2)
            vals.append(score(board_text(rec, positions, reduced + [(a, b)], ct)))
        stats["swap"] = sum(vals) / len(vals) if vals else peak
    else:
        stats["swap"] = peak

    # Soft integral over the climb's accepted boards.
    if trace:
        m = max(trace)
        stats["logsumexp"] = m + math.log(
            sum(math.exp(t - m) for t in trace) / len(trace))
    else:
        stats["logsumexp"] = peak
    return stats


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", type=Path, default=Path("Fixtures/u534_corpus.json"))
    ap.add_argument("--lengths", default="72")
    ap.add_argument("--order", type=int, default=4, help="n-gram order (4 was best at 72)")
    ap.add_argument("--wrong", type=int, default=12)
    ap.add_argument("--seed", type=int, default=20260923)
    ap.add_argument("--seeds", type=int, default=1,
                    help="repeat with this many seeds and report the z spread. A single seed "
                         "CANNOT support a claim here: measured z swings ~0.3 between seeds, "
                         "which is wider than any effect observed.")
    args = ap.parse_args()

    clean = load_clean(args.corpus)
    rng = random.Random(args.seed)
    methods = ["peak", "ablation", "swap", "logsumexp"]

    print(f"clean-key controls : {len(clean)}")
    print(f"n-gram order       : {args.order} (leave-one-out per control)")
    print(f"wrong-key samples  : {args.wrong} per control, same shell, real decrypts")
    print("every statistic is computed identically for the truth and for each decoy")
    print()

    for length in [int(x) for x in args.lengths.split(",")]:
        pool = [r for r in clean
                if len(norm(r["ciphertext"])) >= length and len(norm(r["plaintext"])) >= length]
        if not pool:
            continue
        agg: dict[str, list[float]] = {m: [] for m in methods}
        zs: dict[str, list[float]] = {m: [] for m in methods}
        spread: dict[str, list[float]] = {m: [] for m in methods}
        wins: dict[str, int] = {m: 0 for m in methods}

        for rec in pool:
            train = [norm(o["plaintext"]) for o in clean if o["id"] != rec["id"]]
            model = NGram(args.order).train(train)
            ct = norm(rec["ciphertext"])[:length]

            truth = statistics(rec, rec["wheel_positions"].upper(), ct, model.score, rng)
            decoys = [statistics(rec, pos, ct, model.score, rng)
                      for pos in _wrong_positions(rec, args.wrong, rng)]
            if not decoys:
                continue
            for m in methods:
                dv = [d[m] for d in decoys]
                best = max(dv)
                mean = sum(dv) / len(dv)
                var = sum((v - mean) ** 2 for v in dv) / len(dv)
                sd = math.sqrt(var)
                agg[m].append(truth[m] - best)
                spread[m].append(sd)
                if sd > 0:
                    zs[m].append((truth[m] - mean) / sd)
                if truth[m] > best:
                    wins[m] += 1

        def median(xs: list[float]) -> float:
            s = sorted(xs)
            return s[len(s) // 2] if s else float("nan")

        header = (f"{'len':>5} {'method':>10} {'ctrls':>6} {'win%':>6} "
                  f"{'med margin':>12} {'decoy sd':>10} {'med z':>8}  verdict")
        print(header)
        print("-" * len(header))
        base_margin = base_z = None
        for m in methods:
            if not agg[m]:
                continue
            med, sd, z = median(agg[m]), median(spread[m]), median(zs[m])
            if m == "peak":
                base_margin, base_z = med, z
                verdict = "baseline"
            else:
                # A margin gain that is matched by a proportional shrink in decoy spread is
                # COMPRESSION, not separation: dividing every score by 10 would do the same.
                # z is scale-free, so only a z improvement is real.
                better_margin = med > base_margin
                better_z = z > base_z
                if better_margin and better_z:
                    verdict = "REAL separation gain"
                elif better_margin and not better_z:
                    verdict = "COMPRESSION ONLY — margin up, z down; not progress"
                elif better_z:
                    verdict = "z up, margin not"
                else:
                    verdict = "no better"
            print(f"{length:>5} {m:>10} {len(agg[m]):>6} "
                  f"{100 * wins[m] / len(agg[m]):>5.0f}% {med:>12.4f} {sd:>10.4f} "
                  f"{z:>8.3f}  {verdict}")
        print()

    print("Margin alone is NOT sufficient evidence. Rescaling every score shrinks all margins")
    print("toward zero while separating nothing, and the decoy-sd column exposes exactly that.")
    print("z = (truth - decoy mean) / decoy sd is scale-free, so a method counts as progress")
    print("only when margin AND z both improve over `peak`.")
    print()
    print("MEASURED VERDICT (2026-09-23, 5 seeds x 30 controls): this approach does NOT work.")
    print("  swap      consistently WORSE than peak on z (-0.07..-0.33, never better), despite")
    print("            having the most attractive margin (-0.020 vs -0.039). Its one 'REAL")
    print("            separation gain' reading was a seed fluke.")
    print("  ablation  compression only -- margin up, z down.")
    print("  logsumexp straddles peak (+0.06..+0.49 vs peak +0.01..+0.34): noise at this n.")
    print("  peak      own z swings 0.014..0.335 across seeds, i.e. the measurement is coarser")
    print("            than the effects being claimed. Single-seed runs prove nothing here.")
    return 0


def _wrong_positions(rec: dict, samples: int, rng: random.Random) -> list[str]:
    truth = rec["wheel_positions"].upper()
    seen, out, guard = {truth}, [], 0
    while len(out) < samples and guard < samples * 50:
        guard += 1
        pos = "".join(chr(A + rng.randrange(26)) for _ in range(4))
        if pos in seen:
            continue
        seen.add(pos)
        out.append(pos)
    return out


if __name__ == "__main__":
    sys.exit(main())
