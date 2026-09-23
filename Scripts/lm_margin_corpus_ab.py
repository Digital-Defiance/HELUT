#!/usr/bin/env python3
"""A/B the 72-letter margin on 4,644 vs 6,348 letters of naval register.

Scripts/lm_margin_probe.py concluded that n-gram order saturates at n=4 and the margin stays
negative at 72 letters. That conclusion was confounded: it trained on 4,644 letters, so it could
not distinguish "modelling is exhausted" from "the training set is tiny". The wider BGNC scrape
(Scripts/scrape_bgnc_wider.py -> Scripts/validate_bgnc_wider.py) adds 1,704 validated German
letters, a 37% increase, which makes the confound directly testable.

The experiment is the same margin test in both arms, changing ONE variable -- the training set:

    arm A : leave-one-out over u534_corpus only          (4,644 letters)
    arm B : arm A plus the validated wider BGNC register (6,348 letters)

Everything else is held fixed: identical controls, identical wrong-key positions per control
(same seed), plugboard hill-climbed symmetrically for truth and every decoy, same n-gram order.
Margin AND the scale-free z are both reported, because Phase 56.3 established that a margin gain
unaccompanied by a z gain is compression rather than separation.

Note the arms are not perfectly comparable in one respect, and it is stated rather than hidden:
arm B's extra text is Enigma I / other-net traffic, not M-Thetis. It is the same *language and
register family*, which is what an n-gram model consumes, but it is not more of the target net.

    python3 Scripts/lm_margin_corpus_ab.py --order 4 --wrong 8 --seeds 3
"""
from __future__ import annotations

import argparse
import json
import math
import random
import re
import statistics as st
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from enigma_m4 import machine_from_record, norm  # noqa: E402
from lm_margin_probe import NGram, hill_climb_plugs, load_clean, wrong_positions  # noqa: E402


def extra_register(path: Path) -> list[list[int]]:
    if not path.exists():
        return []
    data = json.loads(path.read_text(encoding="utf-8"))
    return [norm(m["plaintext"]) for m in data["messages"] if m.get("plaintext")]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", type=Path, default=Path("Fixtures/u534_corpus.json"))
    ap.add_argument("--extra", type=Path, default=Path("Fixtures/bgnc_register_clean.json"))
    ap.add_argument("--length", type=int, default=72)
    ap.add_argument("--order", type=int, default=4)
    ap.add_argument("--wrong", type=int, default=8)
    ap.add_argument("--seeds", type=int, default=3)
    args = ap.parse_args()

    clean = load_clean(args.corpus)
    extra = extra_register(args.extra)
    base_letters = sum(len(norm(r["plaintext"])) for r in clean)
    extra_letters = sum(len(t) for t in extra)

    pool = [r for r in clean
            if len(norm(r["ciphertext"])) >= args.length
            and len(norm(r["plaintext"])) >= args.length]

    print(f"controls                : {len(pool)} at {args.length} letters")
    print(f"arm A training letters  : {base_letters}")
    print(f"arm B training letters  : {base_letters + extra_letters} "
          f"(+{extra_letters}, +{100 * extra_letters / base_letters:.0f}%)")
    print(f"n-gram order            : {args.order}")
    print(f"wrong-key samples       : {args.wrong} per control, identical across arms")
    print(f"seeds                   : {args.seeds}")
    print()

    results: dict[str, dict[str, list[float]]] = {
        "A": {"margin": [], "z": []}, "B": {"margin": [], "z": []}}

    for seed in range(args.seeds):
        # Same wrong positions for both arms: the arms must differ only in training data.
        rng_positions = random.Random(1000 + seed)
        chosen = {rec["id"]: wrong_positions(rec, args.wrong, rng_positions) for rec in pool}
        per_arm_margin = {"A": [], "B": []}
        per_arm_z = {"A": [], "B": []}

        for rec in pool:
            loo = [norm(o["plaintext"]) for o in clean if o["id"] != rec["id"]]
            models = {"A": NGram(args.order).train(loo),
                      "B": NGram(args.order).train(loo + extra)}
            ct = norm(rec["ciphertext"])[:args.length]
            for arm, model in models.items():
                truth, _ = hill_climb_plugs(
                    rec, rec["wheel_positions"].upper(), ct, model.score)
                dv = [hill_climb_plugs(rec, pos, ct, model.score)[0]
                      for pos in chosen[rec["id"]]]
                if not dv:
                    continue
                mean = st.mean(dv)
                sd = st.pstdev(dv) if len(dv) > 1 else 0.0
                per_arm_margin[arm].append(truth - max(dv))
                if sd > 0:
                    per_arm_z[arm].append((truth - mean) / sd)

        for arm in ("A", "B"):
            if per_arm_margin[arm]:
                results[arm]["margin"].append(st.median(per_arm_margin[arm]))
            if per_arm_z[arm]:
                results[arm]["z"].append(st.median(per_arm_z[arm]))
        print(f"seed {seed}: "
              f"A margin={st.median(per_arm_margin['A']):+.4f} z={st.median(per_arm_z['A']):+.3f}   "
              f"B margin={st.median(per_arm_margin['B']):+.4f} z={st.median(per_arm_z['B']):+.3f}")

    print()
    print(f"{'arm':>4} {'letters':>9} {'mean margin':>12} {'margin range':>22} "
          f"{'mean z':>8} {'z range':>20}")
    print("-" * 82)
    for arm, letters in (("A", base_letters), ("B", base_letters + extra_letters)):
        m, z = results[arm]["margin"], results[arm]["z"]
        print(f"{arm:>4} {letters:>9} {st.mean(m):>+12.4f} "
              f"[{min(m):+.4f},{max(m):+.4f}]".rjust(22)
              + f" {st.mean(z):>+8.3f} " + f"[{min(z):+.3f},{max(z):+.3f}]".rjust(20))

    dm = st.mean(results["B"]["margin"]) - st.mean(results["A"]["margin"])
    dz = st.mean(results["B"]["z"]) - st.mean(results["A"]["z"])
    overlap = (min(results["B"]["z"]) < max(results["A"]["z"])
               and min(results["A"]["z"]) < max(results["B"]["z"]))
    print()
    print(f"delta margin (B-A): {dm:+.4f}    delta z (B-A): {dz:+.3f}")
    if overlap:
        print("VERDICT: the per-seed z ranges OVERLAP, so 37% more register text does not")
        print("produce a separation gain resolvable at this sample size. Not evidence that")
        print("data does not help -- evidence that this much more data does not help THIS much.")
    elif dz > 0:
        print("VERDICT: z improves with the seed ranges disjoint. More register text is a real")
        print("lever; scale the corpus before concluding anything about model capacity.")
    else:
        print("VERDICT: z is worse with disjoint ranges -- the extra text is off-register enough")
        print("to hurt. Check that the added traffic matches the target's dialect.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
