# Constellation arm — result staging (NOT the ledger; fill from the log, then delete)

Run: `logs/campaign-wenselaers-constellation-rings.log`
Quarantine: `logs/quarantine_wenselaers_constellation.json`
Command:
```
./.build/release/helut --welchman \
  --bombe-fixture Fixtures/p1030680_wenselaers_procedure_neustadt_constellations.json \
  --bombe-menus 0 --bombe-min-crib 16 --bombe-ring-sweep \
  --bombe-quarantine logs/quarantine_wenselaers_constellation.json
```

Scope (from the launch banner, already verified):
- 24/24 constellation menus selected, all single-component, 27 edges / 7-9 loops.
- 34,944 shells/menu -> 1.6e10 settings each -> 3.83e11 total.
- Middle ring pinned A (right ring swept). Residual gap ~12% (1 notch) / ~23% (2 notch)
  on the 47-67 letter spans. This is the fast pinned-A answer; a swept follow-up
  (~5-7 days) is only justified if a soft near-miss appears.

## FILL FROM THE COMPLETED LOG (do not guess)

- [ ] total raw stops: __________ over __________ settings (____M/s mean)
- [ ] survived the 10-plug sieve: __________
- [ ] quarantine soft-band near-misses: __________
- [ ] final verdict line (verbatim): __________________________________________
- [ ] any DiscriminatedCandidate that cleared the break gate? (expect none) __________

## Victory-condition checklist — ONLY if a candidate clears the gate

Do NOT write "break" anywhere until every box is checked against the log:
- [ ] crib exact for BOTH anchors (anchorMatches = [true, true])
- [ ] IC >= 0.055
- [ ] tail > -3.600
- [ ] <= 10 plugs, physically buildable board
- [ ] key printed: UKW / Greek / WO / rings / pos / stecker
- [ ] plaintext recovered and it is German
- [ ] log path recorded

## Escalation ladder if a soft near-miss appears (in order, each gated by the prior)

1. Tolerance prequal on THIS fixture (Metal, ~minutes, needs a GPU window):
   `./.build/release/helut --bombe-tolerance-prequal \
      Fixtures/p1030680_wenselaers_procedure_neustadt_constellations.json \
      --bombe-menus 24 --bombe-garble-tolerance 1`
   -> only proceed to a tolerant re-run on menus that pass with low inflation.
2. Hybrid/Ostwald escalate on quarantine_wenselaers_constellation.json
   (host-side; the climber that finishes a true 72-letter stop given 4 plugs).
3. Middle-ring swept version of the whole fixture (~5-7 days) — LAST resort,
   only if 1-2 leave a live candidate.
Do not skip straight to the 5-7 day run on a hunch.

## Same-turn sync targets when the result lands (per .cursor/rules)

1. BREAK_P1030680.md
   - "What we know" table: the constellation row currently says "Mechanism landed,
     priced, NOT RUN" -> replace with the graded result (clean negative expected).
   - Phase 56: append a "56.1 - arm complete" subsection with the real numbers.
   - Attack plan item 11.7: STAGED -> DONE (or escalated).
2. site/src/pages/JournalPage.tsx: the STAGED card -> ELIMINATED/OPEN with the numbers.
3. writeup.tex: the constellation paragraph "No setting has been evaluated" -> the result;
   then `make writeup`.
4. claim-sheet.md: only if a C/H/N row actually moves (a clean negative here does NOT
   move N5/H6/H7 by itself; it adds a receipt to the existing campaign story).
5. selm_pronoun_check.py must stay 0 HARD after edits.

## Follow-up note to Selm (fill the numbers, then it is ready to send)

> The BLEIBTBESETZT x NEUSTADT constellation has now run. [RESULT: ____ raw stops,
> ____ survived the plug sieve, ____ near-misses]. [If clean negative:] It is another
> clean negative under right-ring coverage with the middle ring pinned A: the pairing
> does not break the message over this ~10^11-setting slice. That is a real result your
> historical model made testable, not a dead end for the model itself. [If a near-miss:]
> One or more soft near-misses came through -- we are escalating them, details to follow.
>
> Caveat we are keeping honest: this pass pins the middle ring at A, which leaves the
> ~12-23% of keys whose middle wheel turns over inside the phrase span untested. A full
> middle-ring version exists but costs 5-7 days; we will run it if the escalation or a
> source reply justifies it, and we will not quietly imply this pass was complete.
