from detector import *

# Two documents, two Prüf-Nrn. Do not silently unify them.
#
# Table *selection* for 1945-05-01 is DIRECT: Tauschtafelplan Bruno, Prüfnr. 1772a,
# Kennwort Quelle, column sechs annotated "Mai 45", day 1 printed A
# (Hörenberg scan, Selm 2026-09-24). Day 3 of that column carries a handwritten
# mark and is not encoded. The plan says it enters force only on special order;
# the May annotation is the evidence of use, not a printed monthly title.
#
# Pair *contents* of Quelle Tafel A are now photographed: Crypto Museum
# Doppelbuchstabentauschtafeln Prüfnr. 2499, cover Kennwort Quelle, Tafel A on
# pp. 3–4 (Selm 2026-09-24; visual check of VR/OL/NM/KA and FN/HC/GV/ET plus the
# four remaining v1 fixture pairs). That set's matching Tauschtafelplan is
# printed as the same Prüfnr. (2499). The May plan in hand is 1772a. Edition
# compatibility is not demonstrated, so discovery_eligible stays false.
RECOVERED_QUELLE_A = Tauschtafel(
    "Quelle/Tafel-A (plan-selected 1 May 1945; pairs photographed in 2499)",
    {
        "VR": "ES", "OL": "AE", "NM": "CD", "KA": "HM",
        "QQ": "MS", "GK": "ZU", "EC": "PD", "LZ": "TN",
        "FN": "KY", "HC": "DM", "GV": "UU", "ET": "ZZ",
    },
    Validity("1945-05-01", "1945-05-01"),
    Provenance(
        "Tauschtafelplan Bruno Prüfnr. 1772a (Hörenberg scan, Selm 2026-09-24); "
        "Tafel A photograph Crypto Museum DoppelTafeln_2499.pdf pp. 3–4 "
        "(Prüfnr. 2499, Selm 2026-09-24)",
        "A_PRIMARY",
        "Column-6 day 1 is printed A. Pair mappings match the 2499 Tafel A "
        "photograph. 1772a vs 2499 edition compatibility is not demonstrated. "
        "3 May is withheld.",
    ),
    "DIRECT",
)
KBOOK = {
    "ACH": KBookEntry("ACH", 645, 14, Provenance("M.Dv.Nr.98 recovered lookup", "B_ATTESTED")),
    "ZPT": KBookEntry("ZPT", 211, 16, Provenance("M.Dv.Nr.98 recovered lookup", "B_ATTESTED")),
    "DUZ": KBookEntry("DUZ", 12, 9, Provenance("M.Dv.Nr.98 recovered lookup", "B_ATTESTED")),
}
ALLOCATIONS = [
    Allocation(
        "Forelle", Validity("1944-10-15", "1944-12-29"), 641, 670, "M-Aegir",
        Provenance("R.I.P. 401 reproduced Forelle sheet", "A_PRIMARY"), "DIRECT",
    ),
    Allocation(
        "Forelle", Validity("1944-10-15", "1944-12-29"), 671, 703, "M-Thetis",
        Provenance("R.I.P. 401 reproduced Forelle sheet", "A_PRIMARY"), "DIRECT",
    ),
    Allocation(
        "Undated late-war surviving crop", Validity(), 621, 653, "M-Thetis",
        Provenance(
            "Surviving Hörenberg crop", "A_PRIMARY",
            "621-653=M-Thetis visible; issue/date not visible.",
        ),
        "RECONSTRUCTED",
    ),
]
