#!/usr/bin/env python3
"""Quantify what the VROL NMKA indicators actually constrain for P1030680.

Naval M4 indicator procedure (Hoerenberg, "The Kenngruppen System"):

    indicator groups -> bigram table "Quelle" A -> Schluesselkenngruppe (net id)
                                               -> Verfahrenkenngruppe  (enciphered
                                                  message key)
    message key = decipher(Verfahrenkenngruppe) at the Grundstellung, on the
                  daily key of that net.

For P1030680 the archival record gives Schluesselkenngruppe ACH (= M-Thetis) and
Verfahrenkenngruppe SEDM (or OEDM on the garbled VA reading). The Grundstellung
came from a printed Grund table that has not survived, so it is unknown.

That leaves message key = f(daily key, Grund). This script measures whether that
substitution buys anything: if Grund -> message key is a bijection, trading an
unknown message key for an unknown Grund reduces the search space by exactly
nothing. The reachable-image size is measured on the recovered Potsdam key.

A second mode replays the 48 broken messages to validate the machine and corpus.

Usage:
    Scripts/indicator_constraints.py --validate Fixtures/u534_corpus.json
    Scripts/indicator_constraints.py --grund-image
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

A = ord("A")

WIRING = {
    "1": ("EKMFLGDQVZNTOWYHXUSPAIBRCJ", "Q"),
    "2": ("AJDKSIRUXBLHWTMCQGZNPYFVOE", "E"),
    "3": ("BDFHJLCPRTXVZNYEIWGAKMUSQO", "V"),
    "4": ("ESOVPZJAYQUIRHXLNFTGKDCMWB", "J"),
    "5": ("VZBRGITYUPSDNHLXAWMJQOFECK", "Z"),
    "6": ("JPGVOUMFYQBENHZRDKASXLICTW", "ZM"),
    "7": ("NZJHGRCXMYSWBOUFAIVLPEKQDT", "ZM"),
    "8": ("FKQHTLXOCBJSPDZRAMEWNIUYGV", "ZM"),
}
GREEK = {"B": "LEYJVCNIXWPBQMDRTAKZGFUHOS", "C": "FSOKANUERHMBTIYCWLQPZXVGJD"}
UKW = {"B": "ENKQAUYWJICOPBLMDXZVFTHRGS", "C": "RDOBJNTKVEHMLFCWZAXGYIPSUQ"}


def to_nums(text: str) -> list[int]:
    return [ord(c) - A for c in text]


def inverse(perm: list[int]) -> list[int]:
    out = [0] * 26
    for index, value in enumerate(perm):
        out[value] = index
    return out


class M4:
    """Enigma M4. Positions are [greek, left, middle, right]; the greek wheel is static."""

    def __init__(self, greek: str, wheels: str, reflector: str,
                 rings: str, plugs: str = "") -> None:
        left, middle, right = wheels[0], wheels[1], wheels[2]
        self.fwd = [to_nums(GREEK[greek])] + [to_nums(WIRING[w][0]) for w in (left, middle, right)]
        self.rev = [inverse(p) for p in self.fwd]
        self.notch = [set()] + [{ord(c) - A for c in WIRING[w][1]} for w in (left, middle, right)]
        self.ukw = to_nums(UKW[reflector])
        self.ring = to_nums(rings)
        self.plug = list(range(26))
        for pair in plugs.split():
            if len(pair) == 2:
                x, y = ord(pair[0]) - A, ord(pair[1]) - A
                self.plug[x], self.plug[y] = y, x

    def _step(self, pos: list[int]) -> None:
        if pos[2] in self.notch[2]:
            pos[1] += 1
            pos[2] += 1
        elif pos[3] in self.notch[3]:
            pos[2] += 1
        pos[3] += 1
        for i in (1, 2, 3):
            pos[i] %= 26

    def process(self, text: str, positions: str) -> str:
        pos = to_nums(positions)
        ring, fwd, rev, plug, ukw = self.ring, self.fwd, self.rev, self.plug, self.ukw
        out = []
        for ch in text:
            self._step(pos)
            c = plug[ord(ch) - A]
            for i in (3, 2, 1, 0):
                shift = pos[i] - ring[i]
                c = (fwd[i][(c + shift) % 26] - shift) % 26
            c = ukw[c]
            for i in (0, 1, 2, 3):
                shift = pos[i] - ring[i]
                c = (rev[i][(c + shift) % 26] - shift) % 26
            out.append(chr(plug[c] + A))
        return "".join(out)


def build(record: dict) -> M4:
    return M4(record["greek"], record["wheels"].strip(),
              record["reflector"], record["rings"], record.get("plugs", ""))


def validate(corpus: Path) -> int:
    data = json.loads(corpus.read_text(encoding="utf-8"))
    ok = bad = 0
    for record in data["messages"]:
        if not record.get("broken"):
            continue
        machine = build(record)
        got = machine.process(record["ciphertext"], record["wheel_positions"])
        if got == record["plaintext"]:
            ok += 1
        else:
            bad += 1
            same = sum(1 for a, b in zip(got, record["plaintext"]) if a == b)
            print(f"  MISMATCH {record['id']}: {same}/{len(got)} letters agree")
            print(f"    want {record['plaintext'][:60]}")
            print(f"    got  {got[:60]}")
    print(f"\nreplayed {ok + bad} broken messages: {ok} exact, {bad} mismatched")
    return 0 if bad == 0 else 1


# Recovered Potsdam daily key for 1 May 1945 (original ring setting).
POTSDAM = {"greek": "C", "wheels": "438", "reflector": "B", "rings": "VCCH",
           "plugs": "CH EJ NV OU TY LG SZ PK DI QB"}


def grund_image(verfahren: str) -> int:
    machine = M4(**POTSDAM)
    seen = set()
    for a in range(26):
        for b in range(26):
            for c in range(26):
                prefix = chr(a + A) + chr(b + A) + chr(c + A)
                for d in range(26):
                    seen.add(machine.process(verfahren, prefix + chr(d + A)))
    total = 26 ** 4
    print(f"Verfahrenkenngruppe {verfahren} on the Potsdam key")
    print(f"  Grundstellungen tried      : {total}")
    print(f"  distinct message keys hit  : {len(seen)}  ({100 * len(seen) / total:.1f}%)")
    print(f"  search-space reduction     : {total / len(seen):.2f}x")
    print()
    if total / len(seen) < 2:
        print("  VERDICT: the indicator does NOT collapse the message-key space.")
        print("  Grund -> message key is essentially a bijection, so an unknown Grund")
        print("  costs exactly what an unknown message key costs. Without the lost")
        print("  Grund table the indicators are a net identifier, not a key constraint.")
    return 0


TARGET_CT = ("JCRSAJTGSJEYEXYKKZZSHVUOCTRFRCRPFVYPLKPPLGRHVVBBTBRSXSWXGGT"
             "YTVKQNGSCHVGF")


def load_bigrams(path: Path) -> list[float]:
    import math

    counts = [0] * 676
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("#") or not line.strip():
            continue
        pair, value = line.split()
        counts[(ord(pair[0]) - A) * 26 + (ord(pair[1]) - A)] = int(value)
    total = sum(counts) + 676
    return [math.log10((c + 1) / total) for c in counts]


def try_known_keys(corpus: Path, bigrams: Path, top: int = 5) -> int:
    """Exhaust all 26^4 message keys under each recovered U-534 daily key.

    Girard's operator only tried two message keys before giving up. This tries
    every one, on every key we hold, and either finds the message or eliminates
    all three nets outright.
    """
    import heapq

    table = load_bigrams(bigrams)
    data = json.loads(corpus.read_text(encoding="utf-8"))

    keys = {}
    for record in data["messages"]:
        signature = (record.get("reflector"), record.get("greek"),
                     record.get("wheels", "").strip(), record.get("rings"),
                     record.get("plugs"))
        if all(signature) and signature not in keys:
            keys[signature] = record["id"]
    # The Potsdam sheet also has an original-ring parameterisation.
    keys[("B", "C", "438", "VCCH", POTSDAM["plugs"])] = "P1030684 (original rings)"

    print(f"Exhausting 26^4 message keys against P1030680 on {len(keys)} recovered keys\n")
    for (reflector, greek, wheels, rings, plugs), example in keys.items():
        machine = M4(greek, wheels, reflector, rings, plugs)
        best: list = []
        for a in range(26):
            for b in range(26):
                for c in range(26):
                    prefix = chr(a + A) + chr(b + A) + chr(c + A)
                    for d in range(26):
                        text = machine.process(TARGET_CT, prefix + chr(d + A))
                        score = 0.0
                        prev = ord(text[0]) - A
                        for ch in text[1:]:
                            cur = ord(ch) - A
                            score += table[prev * 26 + cur]
                            prev = cur
                        item = (score, prefix + chr(d + A), text)
                        if len(best) < top:
                            heapq.heappush(best, item)
                        elif score > best[0][0]:
                            heapq.heapreplace(best, item)
        print(f"key {reflector}/{greek}/{wheels}/{rings}  [{example}]")
        for score, position, text in sorted(best, reverse=True):
            print(f"  {score:9.2f}  {position}  {text[:56]}")
        print()
    print("A genuine break reads as German. Anything else is the noise floor.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--validate", type=Path)
    parser.add_argument("--grund-image", action="store_true")
    parser.add_argument("--verfahren", default="SEDM")
    parser.add_argument("--try-known-keys", type=Path, metavar="CORPUS")
    parser.add_argument("--bigrams", type=Path, default=Path("Fixtures/german_bigrams.txt"))
    args = parser.parse_args()

    status = 0
    if args.validate:
        status |= validate(args.validate)
    if args.grund_image:
        status |= grund_image(args.verfahren)
    if args.try_known_keys:
        status |= try_known_keys(args.try_known_keys, args.bigrams)
    if not (args.validate or args.grund_image or args.try_known_keys):
        parser.error("choose --validate, --grund-image and/or --try-known-keys")
    return status


if __name__ == "__main__":
    sys.exit(main())
