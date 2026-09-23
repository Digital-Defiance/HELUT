#!/usr/bin/env python3
"""Does a better language model move the 72-letter margin, or is the wall informational?

The ledger's central negative (Phase 50, 54.4) is that the crib-free attack's *margin*

    margin = score(true setting) - max score(wrong settings)

is negative at 72 letters, so a sweep ranks noise above signal and no amount of compute
finds the key. Better scorers have moved recovery before: bigram -> staged IC/bi/tri took
472 letters from 0/10 to 8/10 plugs, and the dense 28.5M-letter table took 72-letter
recovery from 4 to 21 correct letters. So "a better model helps" is measured fact, and the
open question is narrow and falsifiable: does a better model make the *margin* at 72
letters positive, or does it only help where the attack already wins?

This measures that, honestly:

  * Decoys are GENUINE wrong-setting decrypts produced by the verified Scripts/enigma_m4.py,
    drawn from the same shell as the truth and differing only in message key -- the same
    hardest-case control OstwaldCurve uses. Not shuffles, not other messages' plaintext.
  * The model is trained LEAVE-ONE-OUT: when grading message X, X is excluded from training.
    A model graded on its own training text will look brilliant and mean nothing.
  * Orders 2..5 are compared on identical data so "more context" is a measured axis rather
    than an assumption. Higher order on 7.5k letters is exactly where overfitting lives.
  * Truncation is applied to the CIPHERTEXT before decryption, so a length-L cell is a real
    L-letter message, not an L-letter slice of a longer decrypt.

It evaluates no rotor settings against P1030680 and asserts nothing about it. It is a
measurement of our scorer's discriminating power, nothing more.

    python3 Scripts/lm_margin_probe.py
    python3 Scripts/lm_margin_probe.py --lengths 72,100,140 --wrong 64 --orders 3,4,5
"""
from __future__ import annotations

import argparse
import json
import math
import random
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from enigma_m4 import machine_from_record, norm, to_str  # noqa: E402

A = ord("A")


# ---------------------------------------------------------------- model

class NGram:
    """Add-k smoothed character n-gram over A-Z, trained on a list of letter lists."""

    def __init__(self, order: int, k: float = 0.5):
        self.order = order
        self.k = k
        self.counts: dict[tuple, list[float]] = {}
        self.totals: dict[tuple, float] = {}
        self.uniform = -math.log(26.0)

    def train(self, texts: list[list[int]]) -> "NGram":
        n = self.order
        for text in texts:
            if len(text) < n:
                continue
            for i in range(len(text) - n + 1):
                ctx = tuple(text[i:i + n - 1])
                nxt = text[i + n - 1]
                row = self.counts.get(ctx)
                if row is None:
                    row = [0.0] * 26
                    self.counts[ctx] = row
                row[nxt] += 1.0
        for ctx, row in self.counts.items():
            self.totals[ctx] = sum(row) + self.k * 26.0
        return self

    def score(self, text: list[int]) -> float:
        """Mean log-probability per scored position. Unseen contexts fall back to uniform,
        which is deliberately uninformative rather than impossible -- an unseen context must
        not be able to veto a candidate."""
        n = self.order
        if len(text) < n:
            return self.uniform
        total = 0.0
        count = 0
        for i in range(len(text) - n + 1):
            ctx = tuple(text[i:i + n - 1])
            nxt = text[i + n - 1]
            row = self.counts.get(ctx)
            if row is None:
                total += self.uniform
            else:
                total += math.log((row[nxt] + self.k) / self.totals[ctx])
            count += 1
        return total / count if count else self.uniform


def index_of_coincidence(text: list[int]) -> float:
    if len(text) < 2:
        return 0.0
    freq = [0] * 26
    for c in text:
        freq[c] += 1
    n = len(text)
    return sum(f * (f - 1) for f in freq) / (n * (n - 1))


# ---------------------------------------------------------------- corpus

def load_clean(corpus: Path) -> list[dict]:
    """Messages whose published key reproduces their published plaintext (exactly, or as a
    perfect prefix of a longer decrypt -- a truncated transcript, not a key defect)."""
    data = json.loads(corpus.read_text(encoding="utf-8"))
    out = []
    for rec in data["messages"]:
        if not (rec.get("plaintext") and rec.get("broken") and rec.get("reflector")):
            continue
        ct, pt = norm(rec["ciphertext"]), norm(rec["plaintext"])
        got = machine_from_record(rec).process(ct)
        if got == pt or (len(got) >= len(pt) and got[:len(pt)] == pt):
            out.append(rec)
    return out


def hill_climb_plugs(rec: dict, positions: str, ct: list[int],
                     score, max_plugs: int = 10) -> tuple[float, list[int]]:
    """Greedy plugboard recovery at a FIXED rotor setting, scored by `score`.

    This is the heart of the Ostwald/Weierud attack and the reason the experiment is hard.
    An attacker does not know the plugboard: at every candidate setting the board is a ~47-bit
    nuisance parameter that must be fitted from the ciphertext itself. Handing the true board
    to the scorer -- for the truth or for a decoy -- turns the measurement into grading with
    the answer key, which is exactly the bug this function exists to avoid.

    Applied symmetrically to the truth and to every decoy. That symmetry is not optional:
    letting the truth fit 10 plugs while each decoy gets none manufactures a margin.
    """
    unplugged = dict(rec)
    unplugged["plugs"] = ""
    base = machine_from_record(unplugged, positions=positions).process(ct)
    best_score = score(base)
    board: list[tuple[int, int]] = []
    used: set[int] = set()

    for _ in range(max_plugs):
        best_pair = None
        best_gain = 0.0
        for a in range(26):
            if a in used:
                continue
            for b in range(a + 1, 26):
                if b in used:
                    continue
                trial = board + [(a, b)]
                spec = dict(rec)
                spec["plugs"] = " ".join(
                    f"{chr(A + x)}{chr(A + y)}" for x, y in trial)
                text = machine_from_record(spec, positions=positions).process(ct)
                s = score(text)
                if s > best_score + best_gain:
                    best_gain = s - best_score
                    best_pair = (a, b)
        if best_pair is None:
            break
        board.append(best_pair)
        used.update(best_pair)
        best_score += best_gain

    spec = dict(rec)
    spec["plugs"] = " ".join(f"{chr(A + x)}{chr(A + y)}" for x, y in board)
    return best_score, machine_from_record(spec, positions=positions).process(ct)


def wrong_positions(rec: dict, samples: int, rng: random.Random) -> list[str]:
    """Wrong MESSAGE KEYS in the same shell as the truth.

    Same shell is the hardest honest negative control: a real sweep also enumerates wrong
    wheel orders and rings, which are easier to reject, so a margin measured this way is
    conservative.
    """
    truth = rec["wheel_positions"].upper()
    seen = {truth}
    out: list[str] = []
    guard = 0
    while len(out) < samples and guard < samples * 50:
        guard += 1
        pos = "".join(chr(A + rng.randrange(26)) for _ in range(4))
        if pos in seen:
            continue
        seen.add(pos)
        out.append(pos)
    return out


# ---------------------------------------------------------------- experiment

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", type=Path, default=Path("Fixtures/u534_corpus.json"))
    ap.add_argument("--lengths", default="72,100,140,180,252",
                    help="ciphertext truncation lengths to ladder over")
    ap.add_argument("--orders", default="2,3,4,5", help="n-gram orders to compare")
    ap.add_argument("--wrong", type=int, default=48, help="wrong-key samples per control")
    ap.add_argument("--seed", type=int, default=20260923)
    ap.add_argument("--also-ic", action="store_true",
                    help="also report an IC-only scorer as a floor reference")
    args = ap.parse_args()

    lengths = [int(x) for x in args.lengths.split(",")]
    orders = [int(x) for x in args.orders.split(",")]
    clean = load_clean(args.corpus)
    print(f"corpus            : {args.corpus}")
    print(f"clean-key controls: {len(clean)}")
    print(f"wrong-key samples : {args.wrong} per control, same shell, real decrypts")
    print(f"training          : leave-one-out (the graded message is never trained on)")
    print(f"total training letters available: "
          f"{sum(len(norm(r['plaintext'])) for r in clean)}")
    print()

    rng = random.Random(args.seed)

    header = f"{'len':>5} {'order':>6} {'ctrls':>6} {'wins':>6} {'win%':>6} " \
             f"{'med margin':>12} {'med z':>8}"
    print(header)
    print("-" * len(header))

    summary: dict[tuple[int, int], tuple[float, float, float]] = {}

    for length in lengths:
        pool = [r for r in clean if len(norm(r["ciphertext"])) >= length
                and len(norm(r["plaintext"])) >= length]
        if not pool:
            continue
        for order in orders:
            margins, zs, wins = [], [], 0
            for rec in pool:
                # Leave-one-out training: everything except this message.
                train = [norm(o["plaintext"]) for o in clean if o["id"] != rec["id"]]
                model = NGram(order).train(train)
                ct = norm(rec["ciphertext"])[:length]

                # The truth gets NO free plugboard: it must be climbed, exactly as a decoy's is.
                true_score, _ = hill_climb_plugs(
                    rec, rec["wheel_positions"].upper(), ct, model.score)
                dscores = [
                    hill_climb_plugs(rec, pos, ct, model.score)[0]
                    for pos in wrong_positions(rec, args.wrong, rng)
                ]
                if not dscores:
                    continue
                best = max(dscores)
                mean = sum(dscores) / len(dscores)
                var = sum((s - mean) ** 2 for s in dscores) / len(dscores)
                sd = math.sqrt(var)
                margins.append(true_score - best)
                zs.append((true_score - mean) / sd if sd > 0 else float("inf"))
                if true_score > best:
                    wins += 1
            if not margins:
                continue
            margins.sort()
            zs.sort()
            med_m = margins[len(margins) // 2]
            med_z = zs[len(zs) // 2]
            summary[(length, order)] = (wins / len(margins), med_m, med_z)
            print(f"{length:>5} {order:>6} {len(margins):>6} {wins:>6} "
                  f"{100 * wins / len(margins):>5.0f}% {med_m:>12.4f} {med_z:>8.2f}")
        if args.also_ic:
            margins, wins = [], 0
            for rec in pool:
                ct = norm(rec["ciphertext"])[:length]
                # Same discipline: IC-climbed plugboard for the truth and every decoy.
                t, _ = hill_climb_plugs(rec, rec["wheel_positions"].upper(), ct,
                                       index_of_coincidence)
                d = [hill_climb_plugs(rec, pos, ct, index_of_coincidence)[0]
                     for pos in wrong_positions(rec, args.wrong, rng)]
                if not d:
                    continue
                margins.append(t - max(d))
                if t > max(d):
                    wins += 1
            if margins:
                margins.sort()
                print(f"{length:>5} {'IC':>6} {len(margins):>6} {wins:>6} "
                      f"{100 * wins / len(margins):>5.0f}% "
                      f"{margins[len(margins) // 2]:>12.4f} {'—':>8}")
        print()

    print("Reading this table: a NEGATIVE median margin means the best wrong setting outscores")
    print("the truth, so a full sweep would rank noise above signal at that length no matter")
    print("how much compute it is given. Positive margin is the precondition for the")
    print("ciphertext-only attack to be able to work at all.")
    print()
    at72 = [(o, summary[(72, o)]) for o in orders if (72, o) in summary]
    if at72:
        best_order, (_, best_margin, _) = max(at72, key=lambda kv: kv[1][1])
        print(f"At 72 letters the best order tested is n={best_order} with median margin "
              f"{best_margin:+.4f}.")
        if best_margin > 0:
            print("That is POSITIVE — this contradicts the standing negative and must be "
                  "re-checked with more controls and a held-out shell before it is believed.")
        else:
            print("Still NEGATIVE. Raising n-gram order does not lift the truth above the "
                  "decoy maximum at this length, which is consistent with the wall being a "
                  "shortage of information in 72 letters rather than a shortage of model.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
