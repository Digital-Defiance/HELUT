#!/usr/bin/env python3
"""Legality and symmetry of the plugboard marginal walk. Not a campaign grade."""
from __future__ import annotations

import random
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "Scripts"))

from plugboard_marginal_probe import (  # noqa: E402
    apply_board,
    identity_board,
    legal,
    propose,
)


class PlugboardMarginalTests(unittest.TestCase):
    def test_identity_is_legal(self):
        self.assertTrue(legal(identity_board()))

    def test_add_pair_is_an_involution(self):
        board = apply_board(identity_board(), 0, 1)
        self.assertTrue(legal(board))
        self.assertEqual(board[0], 1)
        self.assertEqual(board[1], 0)
        self.assertEqual(board[2], 2)

    def test_eleven_plugs_are_illegal(self):
        board = list(range(26))
        for i in range(0, 22, 2):
            board[i], board[i + 1] = i + 1, i
        self.assertFalse(legal(tuple(board)))

    def test_proposals_stay_legal(self):
        rng = random.Random(0)
        board = identity_board()
        for _ in range(200):
            board = propose(board, rng)
            self.assertTrue(legal(board))

    def test_rewire_clears_the_old_partner(self):
        board = apply_board(identity_board(), 0, 1)
        board = apply_board(board, 0, 2)
        self.assertEqual(board[1], 1)
        self.assertEqual(board[0], 2)
        self.assertEqual(board[2], 0)
        self.assertTrue(legal(board))


if __name__ == "__main__":
    unittest.main()
