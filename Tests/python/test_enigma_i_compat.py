#!/usr/bin/env python3
"""Python I3 / parked-M4 identity tests.

Enigma I is not M4 with a rotor removed. β at A/A + thin B is thick B;
γ at A/A + thin C is thick C. Ciphertexts here are the same KATs as
Tests/HELUTTests/EnigmaICompatibilityTests.swift.
"""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "Scripts"))

from enigma_m4 import (  # noqa: E402
    GREEK,
    I3,
    M4,
    THICK,
    THIN,
    inverse,
    norm,
    perm,
    to_str,
)

PHRASE = "KEINEBESONDERENEREIGNISSE"
PLUGS = "AM BC DF GH IJ KL NO PQ RS TU"
I3_THICK_B_CT = "HNVUSQZJIDSUHTXLZUTMUTMLH"
I3_THICK_C_CT = "ZASFURJBLPUCBZKVHFAEMAAEL"


def greek_then_thin(greek: str, thin: str, pos: int = 0, ring: int = 0) -> list[int]:
    fwd = perm(GREEK[greek])
    rev = inverse(fwd)
    ukw = perm(THIN[thin])
    off = (pos - ring) % 26
    out = []
    for x in range(26):
        v = (fwd[(x + off) % 26] - off) % 26
        v = ukw[v]
        v = (rev[(v + off) % 26] - off) % 26
        out.append(v)
    return out


class EnigmaICompat(unittest.TestCase):
    def test_beta_thin_b_at_aa_equals_thick_b(self):
        self.assertEqual(greek_then_thin("beta", "B"), perm(THICK["B"]))

    def test_gamma_thin_c_at_aa_equals_thick_c(self):
        self.assertEqual(greek_then_thin("gamma", "C"), perm(THICK["C"]))

    def test_wrong_pair_is_not_thick(self):
        self.assertNotEqual(greek_then_thin("beta", "C"), perm(THICK["B"]))
        self.assertNotEqual(greek_then_thin("beta", "C"), perm(THICK["C"]))
        self.assertNotEqual(greek_then_thin("gamma", "B"), perm(THICK["B"]))
        self.assertNotEqual(greek_then_thin("gamma", "B"), perm(THICK["C"]))

    def test_greek_off_a_is_not_thick_b(self):
        self.assertNotEqual(greek_then_thin("beta", "B", pos=1), perm(THICK["B"]))
        self.assertNotEqual(greek_then_thin("beta", "B", ring=1), perm(THICK["B"]))

    def test_i3_thick_b_kat(self):
        ct = to_str(I3("B", "123", "AAA", "ABC", PLUGS).process(norm(PHRASE)))
        self.assertEqual(ct, I3_THICK_B_CT)

    def test_parked_m4_matches_i3_thick_b(self):
        i3 = I3("B", "123", "AAA", "ABC", PLUGS).process(norm(PHRASE))
        m4 = M4("B", "beta", "123", "AAAA", "AABC", PLUGS).process(norm(PHRASE))
        self.assertEqual(i3, m4)
        self.assertEqual(to_str(m4), I3_THICK_B_CT)

    def test_parked_m4_matches_i3_thick_c(self):
        i3 = I3("C", "123", "AAA", "ABC", PLUGS).process(norm(PHRASE))
        m4 = M4("C", "gamma", "123", "AAAA", "AABC", PLUGS).process(norm(PHRASE))
        self.assertEqual(i3, m4)
        self.assertEqual(to_str(i3), I3_THICK_C_CT)

    def test_greek_window_b_does_not_match_i3(self):
        i3 = I3("B", "123", "AAA", "ABC", PLUGS).process(norm(PHRASE))
        m4 = M4("B", "beta", "123", "AAAA", "BABC", PLUGS).process(norm(PHRASE))
        self.assertNotEqual(i3, m4)

    def test_i3_involution(self):
        ct = I3("B", "123", "AAA", "ABC", PLUGS).process(norm(PHRASE))
        pt = I3("B", "123", "AAA", "ABC", PLUGS).process(ct)
        self.assertEqual(to_str(pt), PHRASE)

    def test_norrkoping_page23_head(self):
        """Published key decrypts the Norrköping page; last letter is scrape prose."""
        rec = next(
            m
            for m in json.loads((ROOT / "Fixtures/bgnc_wider_corpus.json").read_text())["messages"]
            if m["id"] == "PAGE_23_COEW"
        )
        got = I3(
            rec["reflector"], rec["wheels"], rec["rings"], rec["wheel_positions"], rec["plugs"]
        ).process(norm(rec["ciphertext"]))
        expect = norm(rec["plaintext"])
        self.assertEqual(got[:-1], expect[:-1])
        self.assertEqual(len(got), len(expect))


if __name__ == "__main__":
    unittest.main()
