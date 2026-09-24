#!/usr/bin/env python3
"""Freeze the Hörenberg published-key census.

Run the grader with: python3 Scripts/verify_horenberg_corpus.py
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "Scripts"))

from verify_horenberg_corpus import (  # noqa: E402
    WIDER_DOCUMENTED_SCRAMBLE,
    receipt,
)

U534_MISMATCH = {
    "P1030659",
    "P1030664",
    "P1030675",
    "P1030693",
    "P1030695",
    "P1030699",
    "P1030700",
    "P1030701",
    "P1030702",
    "P1030705",
    "P1030706",
    "P1030707",
    "P1030708",
    "P1030709",
    "P1030710",
    "P1030711",
}


class HorenbergCorpus(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = receipt()

    def test_u534_census(self):
        s = self.data["u534"]["summary"]
        self.assertEqual(s["rows"], 50)
        self.assertEqual(s["exact"], 31)
        self.assertEqual(s["prefix_ids"], ["P1030694"])
        self.assertEqual(s["head"], 0)
        self.assertEqual(s["clean"], 32)
        self.assertEqual(set(s["mismatch_ids"]), U534_MISMATCH)
        self.assertEqual(s["scramble_from_start"], [])
        self.assertEqual(s["skip"], 2)

    def test_u534_does_not_decrypt_the_target(self):
        row = next(r for r in self.data["u534"]["messages"] if r["id"] == "P1030680")
        self.assertEqual(row["grade"], "skip")
        self.assertEqual(row["reason"], "unbroken_placeholder")

    def test_wider_heads_and_documented_scramble(self):
        s = self.data["wider"]["summary"]
        self.assertEqual(s["scramble_from_start"], list(WIDER_DOCUMENTED_SCRAMBLE))
        self.assertEqual(s["mismatch"], 3)
        self.assertGreaterEqual(s["head"], 7)
        self.assertEqual(s["exact"] + s["prefix"] + s["head"] + s["mismatch"] + s["skip"], s["rows"])
        page23 = next(r for r in self.data["wider"]["messages"] if r["id"] == "PAGE_23_COEW")
        self.assertEqual(page23["grade"], "head")
        self.assertEqual(page23["machine"], "I3")
        self.assertEqual(page23["prefix_agree"], page23["pt_len"] - 1)

    def test_first_u534_page_is_p1030684_plus_scrape_tail(self):
        row = next(
            r
            for r in self.data["wider"]["messages"]
            if r["id"] == "First U534 Ciphertext only break"
        )
        self.assertEqual(row["machine"], "M4")
        self.assertEqual(row["grade"], "head")
        self.assertEqual(row["prefix_agree"], 120)


if __name__ == "__main__":
    unittest.main()
