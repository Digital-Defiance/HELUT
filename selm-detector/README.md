# M-Thetis detector v2 — reconstructed + patched

Historical classification/discovery sieve; **not** an Enigma decryptor.

## Jess review applied
- No Quelle/Tafel A default without dated Kennwort + Tauschtafelplan.
- K-Buch column/row is the stable output; network names are conditional allocation outputs.
- Garbled indicators branch as explicit near-matches instead of being rejected/corrected silently.
- P1030680 is a positive control and never a discovery.
- First blind target: original 3 May 1945 indicators, independent of P1030680.

## 1 May 1945 table selection (documentary)

Tauschtafelplan Bruno, Prüfnr. 1772a, Kennwort Quelle (Hörenberg scan, Selm 2026-09-24):
column sechs is annotated **Mai 45**; day 1 is a clean printed **A**.

So P1030680's *which Tafel* is DIRECT:

`VROL NMKA → Quelle/A → EACH/SEDM → ACH → K-Buch 645/14`

## Quelle Tafel A pair contents (photographed, other edition)

Crypto Museum copy of the Doppelbuchstabentauschtafeln, Prüfnr. **2499**, Kennwort Quelle,
Tafel A on pp. 3–4:

https://www.cryptomuseum.com/crypto/enigma/files/DoppelTafeln_2499.pdf

Photographed pairs used by this package:

- `VR → ES`, `OL → AE`, `NM → CD`, `KA → HM` (P1030680)
- `FN → KY`, `HC → DM`, `GV → UU`, `ET → ZZ` (P1030690 control)
- `QQ → MS`, `GK → ZU`, `EC → PD`, `LZ → TN` (P1030670 control)

The 2499 cover states that that Ausgabe's Tauschtafelplan carries the **same**
Prüfnummer (2499). The May plan in hand is **1772a**. Edition compatibility is
**not** demonstrated. Do not silently promote the whole chain to DIRECT.

Still undated: the surviving `621–653 = M-Thetis` Zuteilungsliste crop. That is why
`discovery_eligible` stays false even for this path, and why M-Thetis is not promoted.

3 May is a different cell in the same column and carries a handwritten mark. It is **not**
encoded. A 3 May classify against this package must fail closed rather than inherit Tafel A.

The plan itself is headed *Tritt erst auf besonderen Befehl in Kraft*. The May annotation is
the evidence of use.

## Preserved v1 regression fixtures
- P1030680: `VROL NMKA -> ES AE CD HM -> EACH/SEDM -> ACH -> 645/14`
- P1030670: `QQGK ECLZ -> MS ZU PD TN -> MZPT/SUDN -> ZPT -> 211/16`
- P1030690: `FNHC GVET -> KY DM UU ZZ -> KDUZ/YMUZ -> DUZ -> 12/9`

P1030670 / P1030690 remain transform regressions on the photographed pair map, not a claim that
those sheets used Quelle.

## Fail-closed gaps
The package does not invent missing Tafel I, 1772a↔2499 edition identity, the 3 May letter, a
complete K-Buch transcription, or the exact issue/date of the late-war `621–653 = M-Thetis`
crop.

A future M-Thetis classification becomes `discovery_eligible` only when both table assignment
and allocation are DIRECT and the record is not P1030680.

Run: `python -m unittest -v test_detector.py` (Python 3.10+; `uv run --python 3.12 python -m unittest -v test_detector.py`)
