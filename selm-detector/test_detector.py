import unittest
from detector import *
from historical_data import *


class T(unittest.TestCase):
    def setUp(self):
        self.d = HistoricalDetector([RECOVERED_QUELLE_A], KBOOK, ALLOCATIONS)

    def runx(self, rid, a, b):
        return self.d.classify(
            rid, "1945-05-01", a, b, allowed_tables=[RECOVERED_QUELLE_A.name]
        )[0]

    def test_0670(self):
        r = self.runx("P1030670", "QQGK", "ECLZ")
        self.assertEqual(
            (r.transformed_pairs, r.transformed_eight, r.schluesselkenngruppe, r.kbuch_column, r.kbuch_row),
            (["MS", "ZU", "PD", "TN"], "MZPT/SUDN", "ZPT", 211, 16),
        )

    def test_0690(self):
        r = self.runx("P1030690", "FNHC", "GVET")
        self.assertEqual(
            (r.transformed_pairs, r.transformed_eight, r.schluesselkenngruppe, r.kbuch_column, r.kbuch_row),
            (["KY", "DM", "UU", "ZZ"], "KDUZ/YMUZ", "DUZ", 12, 9),
        )

    def test_0680(self):
        r = self.runx("P1030680", "VROL", "NMKA")
        self.assertEqual(
            (r.transformed_pairs, r.transformed_eight, r.schluesselkenngruppe, r.kbuch_column, r.kbuch_row),
            (["ES", "AE", "CD", "HM"], "EACH/SEDM", "ACH", 645, 14),
        )
        self.assertFalse(r.discovery_eligible)
        self.assertEqual(r.tauschtafel_assignment_status, "DIRECT")
        self.assertEqual(r.classification_status, "CONDITIONAL_NET_CLASSIFICATION")
        self.assertEqual(r.candidate_verfahren, "M-Thetis")
        self.assertIn("2499", r.evidence[0]["source"])
        self.assertIn("1772a", r.evidence[0]["source"])
        self.assertIn("edition compatibility is not demonstrated", r.evidence[0]["note"])

    def test_uncertainty(self):
        vs = list(expand_uncertain_indicator("VROLNMKA", {1: ["A"]}))
        self.assertTrue(any(x[0] == "VAOLNMKA" and x[1] == 1 for x in vs))

    def test_failclosed_no_tables(self):
        with self.assertRaises(DetectorError):
            HistoricalDetector([], KBOOK, ALLOCATIONS).classify("X", "1945-05-03", "ABCD", "EFGH")

    def test_may3_does_not_inherit_1_may_tafel_a(self):
        with self.assertRaises(DetectorError):
            self.d.classify("ZTPG-probe", "1945-05-03", "ABCD", "EFGH")


if __name__ == "__main__":
    unittest.main()
