#!/usr/bin/env python3
"""Derive an empirical garble model from the U-534 archive's own inconsistencies.

The Ostwald preflight found that only 32 of 48 published U-534 keys reproduce their own
recorded plaintext when their own recorded ciphertext is decrypted under their own recorded
key. The other 16 miss by one to nine letters. That is transcription error in the archive,
and it is *measurable* — which makes it a prior rather than a hunch.

This matters for P1030680 because the Welchman board is a contradiction engine: a single
mis-transcribed ciphertext letter can kill a true menu outright, so every exact-crib clean
negative in the campaign is a negative about the *recorded* ciphertext rather than the
transmitted one. Girard and Hoerenberg needed dual transcripts to degarble the sister message
P1030681, including a missing four-letter group.

The decisive question this answers is **substitutions versus indels**:

  * If the failures are pure substitutions, a small family of ciphertext variants drawn from
    the measured confusion classes is enough, and each variant is one bombe sweep.
  * If they are insertions or deletions, substitution variants are useless — everything after
    the indel is shifted, so the repair has to be an alignment search instead.

Getting that backwards would waste GPU-weeks, so it is worth measuring before building.

    python3 Scripts/garble_model.py Fixtures/u534_corpus.json
"""
from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path

ALPHA = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
NOTCH = {"I": {16}, "II": {4}, "III": {21}, "IV": {9}, "V": {25},
         "VI": {12, 25}, "VII": {12, 25}, "VIII": {12, 25}}
WIRING = {
    "I": "EKMFLGDQVZNTOWYHXUSPAIBRCJ", "II": "AJDKSIRUXBLHWTMCQGZNPYFVOE",
    "III": "BDFHJLCPRTXVZNYEIWGAKMUSQO", "IV": "ESOVPZJAYQUIRHXLNFTGKDCMWB",
    "V": "VZBRGITYUPSDNHLXAWMJQOFECK", "VI": "JPGVOUMFYQBENHZRDKASXLICTW",
    "VII": "NZJHGRCXMYSWBOUFAIVLPEKQDT", "VIII": "FKQHTLXOCBJSPDZRAMEWNIUYGV",
}
GREEK = {"B": "LEYJVCNIXWPBQMDRTAKZGFUHOS", "C": "FSOKANUERHMBTIYCWLQPZXVGJD"}
THIN = {"B": "ENKQAUYWJICOPBLMDXZVFTHRGS", "C": "RDOBJNTKVEHMLFCWZAXGYIPSUQ"}
ROMAN = {"1": "I", "2": "II", "3": "III", "4": "IV", "5": "V",
         "6": "VI", "7": "VII", "8": "VIII"}


def idx(ch: str) -> int:
    return ALPHA.index(ch)


class M4:
    """Minimal M4 for decrypting a recorded message under a recorded key."""

    def __init__(self, reflector, greek, wheels, rings, positions, plugs):
        self.refl = [idx(c) for c in THIN[reflector]]
        self.greek = [idx(c) for c in GREEK[greek]]
        names = [ROMAN[c] for c in wheels]
        self.w = [[idx(c) for c in WIRING[n]] for n in names]
        self.inv = [[0] * 26 for _ in range(3)]
        for r in range(3):
            for i, v in enumerate(self.w[r]):
                self.inv[r][v] = i
        self.ginv = [0] * 26
        for i, v in enumerate(self.greek):
            self.ginv[v] = i
        self.notch = [NOTCH[n] for n in names]
        self.rings = [idx(c) for c in rings]
        self.pos = [idx(c) for c in positions]
        self.plug = list(range(26))
        for token in plugs.split():
            if len(token) == 2:
                a, b = idx(token[0]), idx(token[1])
                self.plug[a], self.plug[b] = b, a

    def step(self):
        g, l, m, r = self.pos
        mid = m in self.notch[1]
        right = r in self.notch[2]
        if mid:
            l = (l + 1) % 26
        if mid or right:
            m = (m + 1) % 26
        r = (r + 1) % 26
        self.pos = [g, l, m, r]

    def process(self, ch: int) -> int:
        self.step()
        g, l, m, r = self.pos
        off = [(g - self.rings[0]) % 26, (l - self.rings[1]) % 26,
               (m - self.rings[2]) % 26, (r - self.rings[3]) % 26]
        v = self.plug[ch]
        for k, o in ((2, off[3]), (1, off[2]), (0, off[1])):
            v = (self.w[k][(v + o) % 26] - o) % 26
        v = (self.greek[(v + off[0]) % 26] - off[0]) % 26
        v = self.refl[v]
        v = (self.ginv[(v + off[0]) % 26] - off[0]) % 26
        for k, o in ((0, off[1]), (1, off[2]), (2, off[3])):
            v = (self.inv[k][(v + o) % 26] - o) % 26
        return self.plug[v]

    def decrypt(self, text: str) -> str:
        return "".join(ALPHA[self.process(idx(c))] for c in text)


def main() -> int:
    path = Path(sys.argv[1] if len(sys.argv) > 1 else "Fixtures/u534_corpus.json")
    data = json.loads(path.read_text())

    ok, failures = 0, []
    for m in data["messages"]:
        if not m.get("broken"):
            continue
        need = ("ciphertext", "plaintext", "reflector", "greek", "wheels",
                "rings", "wheel_positions", "plugs")
        if any(not m.get(k) for k in need):
            continue
        got = M4(m["reflector"], m["greek"], m["wheels"], m["rings"],
                 m["wheel_positions"], m["plugs"]).decrypt(m["ciphertext"])
        want = m["plaintext"]
        n = min(len(got), len(want))
        bad = [i for i in range(n) if got[i] != want[i]]
        if not bad and len(got) == len(want):
            ok += 1
        else:
            failures.append((m["id"], got, want, bad, n))

    print(f"controls round-tripping cleanly : {ok}")
    print(f"controls with discrepancies     : {len(failures)}")
    print()

    print("=== substitution vs indel: does the mismatch run to the end of the message? ===")
    print("A run of errors starting at position p and continuing to the end is the signature")
    print("of an insertion or deletion. Scattered isolated errors are substitutions.")
    print()
    print(f"{'id':<11}{'len':>5}{'errs':>6}{'first':>7}{'last':>6}{'tail?':>7}  verdict")
    subs, indels = [], []
    for mid, got, want, bad, n in sorted(failures, key=lambda f: -len(f[3])):
        first, last = bad[0], bad[-1]
        # Density of errors after the first one: near 1.0 means everything downstream broke.
        span = last - first + 1
        density = len(bad) / span if span else 0
        tail = last >= n - 2 and density > 0.5 and len(bad) > 4
        verdict = "INDEL (shifted)" if tail else "substitution(s)"
        (indels if tail else subs).append((mid, got, want, bad, n))
        print(f"{mid:<11}{n:>5}{len(bad):>6}{first:>7}{last:>6}{str(tail):>7}  {verdict}")

    print()
    print(f"substitution-type : {len(subs)}")
    print(f"indel-type        : {len(indels)}")
    print()

    if subs:
        print("=== confusion classes, substitution-type controls only ===")
        print("(recorded plaintext letter -> letter the published key actually produces)")
        conf = Counter()
        for _, got, want, bad, _ in subs:
            for i in bad:
                conf[(want[i], got[i])] += 1
        total = sum(conf.values())
        print(f"{total} substitution events across {len(subs)} messages")
        print()
        # Fold A->B and B->A together: a transcription confusion is symmetric.
        sym = Counter()
        for (a, b), c in conf.items():
            sym[tuple(sorted((a, b)))] += c
        print("most common confusions (unordered pair : count):")
        for pair, count in sym.most_common(15):
            print(f"   {pair[0]}<->{pair[1]} : {count}")
        print()
        print("letters most often involved:")
        letters = Counter()
        for (a, b), c in conf.items():
            letters[a] += c
            letters[b] += c
        for ch, count in letters.most_common(12):
            print(f"   {ch} : {count}")
        print()
        print("errors per message:", sorted(len(b) for _, _, _, b, _ in subs))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
