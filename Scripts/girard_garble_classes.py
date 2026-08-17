#!/usr/bin/env python3
"""Measure transcription error classes from Girard's P1030681 degarbling.

Source: Dan Girard, "Degarbling the Doenitz Message P1030681", on Michael Hoerenberg's
Enigma site. That page is unusually valuable because it publishes *four* versions of the same
ciphertext plus a reconstructed ground truth:

  v1     first transcription (the badly garbled one)
  sz     re-checked Schluesselzettel copy      (message form, P1030681)
  pp     re-checked plain-paper copy           (P1030714)
  true   theoretical correct ciphertext, obtained by enciphering the reconstructed plaintext
  final  Girard's final proofed ciphertext (consensus of sz and pp)

Diffing each transcript against `true` therefore yields a *ground-truthed* error model for
this exact hand, boat, day and signals office — which is the right prior for P1030680 and far
better evidence than the 8 isolated substitution events recoverable from the corpus JSON.

Girard states the confusion classes he observed while re-reading the originals (U with N, Q
with G, H with F, "etc.") and one structural fact that matters enormously here: the
Schluesselzettel "becomes very disarranged after the first 40 groups". P1030680 is 72 letters
== 18 groups. If errors really do concentrate past group 40, a short message sits in the
reliable zone and the garble hypothesis for our target gets *weaker*, not stronger. That is
testable, so this script tests it.

    python3 Scripts/girard_garble_classes.py
"""
from __future__ import annotations

from collections import Counter

V1 = ("LANOTCTOUARBBFPMHPHGCZXTDYGAHGUFXGEWKBLKGJWLQXXTGPJJAVTOCKZFSLPPGIHZFXOBBWIIEKFZL"
      "CLOAQJULJOYFSSMBBGWHZAMVOIIPCRBRTDJQDJJOQCHXPDNBBFYVXLYTAPGVERTXSONPNYNQFUDBBHHVW"
      "EPYEYDOHNLXKZDNWRHDUWUJUMPWVIIWZBIVI.KDRHYMNCYEFUAPNHOTKHKGDNPSAKNUAGHJZSMJBMHVTR"
      "EQEDGXHLZWIFUSKDQVELNMIMITHBSBBWVSDFYHJOQIFORTDJDBWXEMEAYXGYQXOHFDMUWXXNOJAZRHGRP"
      "LWMLRCLALLRTRTTVLBFYOORZLGOWUNUXFAACQEKRHSJW")

SZ = ("LANOTCTOUARBBFPMHPHGCZXTDYGAHGUFXGEWKBLKGJWLQXXTGPJJAVTOCKZFSLPPQIHZFXOEBWIIEKFZL"
      "CLOAQJULJOYFSSMBBGWHZANVOIIPCRBRTDJQDJJOQCHXPDNBBTYVXLYTAPGVEATXSONPNYNQFUDBBHHVW"
      "EPYEYDOHNLXKZDNWRHDUWUJUOWWVIIWZXIVIUQDRHYMNCYEFUAPNHOTKHKGDNPSAKNUAGHJZSMJBMHVTR"
      "EQEDGXHLZWIFUSKDQVELNMIMITHBHDBWVHDFYHJOQIHORTDJDBWVEMEAYXGYQXOHFDMYUXXNOJAZRSGHP"
      "LWOLRECWWUTLRTTVLBHYOORGLGOWUXNXHMHYFAACQEKTHSJW")

PP = ("LANOTCTOUARBBFPMHPHGCZXTDYGAHGUFXGEWKBLKGJWLQXXTGPJJAVTOYJFGSLPPQIHZFXOEBWIIEKB.L"
      "CLOAQJULJOYHSSMBBGWHZANVOIIPYRBRTDJQDJJOQKCXWDNBBTYVXLYTAPGVERTXSONPNYNQFUDBBHHVW"
      "EPYEYDOHNLXKZDNWRHDUWUJUMPWVIIWZBIVI.KDRHYMNCYEFUAPNHOTKHKGDNPSAKNUAGHJZSMJBMHVTR"
      "EQEDGXHLZWIFUSKDQVELNMIMITHBSBBWVSDFYHJOQIHORTDJDBWXEMEAYXGYQXOH.DMYUXXNOJAZRHGRP"
      "LWMLRCL.CLRTRTTVLBHYOORZLGOWUNNX....FAACQEKRHSJW")

TRUE = ("LANOTCTOUARBBFPMHPHGCZXTDYGAHGUFXGEWKBLKGJWLQXXTGPJJAVTOYJFGSLPPQIHZFXOEBWIIEKFZL"
        "CROAQJULJOYHSSMMBGWHZANVOIIPYRBRTDJQDJJOQKCXWDNBBTYVXLYTAPGVEAUXSONGNYNQFUDBBHHVW"
        "EPYEYDOHNLXKZDNWRHDUWUJUMWWVIIWZXIVIUQDRHYMNCYEFUAPNHOTKHKGDNPSAKNUAGHJZSMJBMHVTR"
        "EQEDGXHLZWIFUSKDQVELNMIMITHBHDBWVHDFYHJOQIHORTDJDBWXEMEAYXGYQXOHFDMYUXXBOJAZRSGHP"
        "LWMLRECWWUTLRTTVLBHYOOLGLGOWUXNXHMHYFAACQEKIHSJW")

FINAL = ("LANOTCTOUARBBFPMHPHGCZXTDYGAHGUFXGEWKBLKGJWLQXXTGPJJAVTOYJFGSLPPQIHZFXOEBWIIEKFZL"
         "CLOAQJULJOYHSSMBBGWHZANVOIIPYRBRTDJQDJJOQKCXWDNBBTYVXLYTAPGVEATXSONPNYNQFUDBBHHVW"
         "EPYEYDOHNLXKZDNWRHDUWUJUMWWVIIWZXIVIUQDRHYMNCYEFUAPNHOTKHKGDNPSAKNUAGHJZSMJBMHVTR"
         "EQEDGXHLZWIFUSKDQVELNMIMITHBHDBWVHDFYHJOQIHORTDJDBWXEMEAYXGYQXOHFDMYUXXNOJAZRSGHP"
         "LWMLRECWWUTLRTTVLBHYOORGLGOWUXNXHMHYFAACQEKTHSJW")

GROUP = 4  # naval traffic was written in four-letter groups


def compare(name: str, text: str, truth: str):
    """Positional diff where lengths agree; report the length gap separately."""
    n = min(len(text), len(truth))
    subs, illegible = [], []
    for i in range(n):
        a, b = text[i], truth[i]
        if a == ".":
            illegible.append(i)
        elif a != b:
            subs.append((i, b, a))  # (position, truth, as-transcribed)
    return {
        "name": name, "len": len(text), "gap": len(truth) - len(text),
        "subs": subs, "illegible": illegible, "compared": n,
    }


def main() -> int:
    print("=== Girard's P1030681 transcripts vs reconstructed ground truth ===")
    print(f"ground-truth ciphertext length: {len(TRUE)}")
    print()
    reports = [compare(n, t, TRUE) for n, t in
               (("v1 (first)", V1), ("sz (Schluesselzettel)", SZ),
                ("pp (plain paper)", PP), ("final (proofed)", FINAL))]

    print(f"{'transcript':<24}{'len':>5}{'gap':>5}{'subs':>6}{'illeg':>7}{'err/100':>9}")
    for r in reports:
        rate = len(r["subs"]) / r["compared"] * 100
        print(f"{r['name']:<24}{r['len']:>5}{r['gap']:>5}{len(r['subs']):>6}"
              f"{len(r['illegible']):>7}{rate:>8.1f}%")
    print()
    print("The 4-letter length gap on v1 is the missing group HMHY that Girard found: present")
    print("on the Schluesselzettel, left blank on the plain-paper copy, absent from the first")
    print("transcription entirely. An indel, not a substitution — and the reason a positional")
    print("diff of v1 past that point is meaningless.")
    print()

    # --- confusion classes, from the two re-checked transcripts against truth -------------
    print("=== confusion classes (re-checked sz + pp vs truth) ===")
    print("Girard names U/N, Q/G, H/F from re-reading the originals. Measured:")
    conf = Counter()
    for r in reports:
        if r["name"].startswith(("sz", "pp")):
            for _, truth_ch, seen_ch in r["subs"]:
                conf[tuple(sorted((truth_ch, seen_ch)))] += 1
    total = sum(conf.values())
    print(f"  {total} substitution events over {len(TRUE)} letters x 2 transcripts")
    for pair, count in conf.most_common(20):
        star = "  <-- named by Girard" if set(pair) in ({"U", "N"}, {"Q", "G"}, {"H", "F"}) else ""
        print(f"    {pair[0]}<->{pair[1]} : {count}{star}")
    print()
    letters = Counter()
    for (a, b), c in conf.items():
        letters[a] += c
        letters[b] += c
    print("  letters most often involved:",
          " ".join(f"{ch}({n})" for ch, n in letters.most_common(10)))
    print()

    # --- positional structure: is the tail worse? ----------------------------------------
    print("=== positional structure — does error rate rise with group number? ===")
    print("Girard: the Schluesselzettel 'becomes very disarranged after the first 40 groups'.")
    print("P1030680 is 72 letters = 18 groups, so this decides whether our target sits in")
    print("the reliable zone or the disarranged one.")
    print()
    groups = len(TRUE) // GROUP
    buckets = [(0, 10), (10, 20), (20, 30), (30, 40), (40, 60), (60, groups + 1)]
    print(f"{'groups':<12}{'letters':>9}{'sz errs':>9}{'pp errs':>9}{'combined/100':>14}")
    for lo, hi in buckets:
        a, b = lo * GROUP, min(hi * GROUP, len(TRUE))
        if a >= len(TRUE):
            continue
        span = b - a
        sz_e = sum(1 for p, _, _ in reports[1]["subs"] if a <= p < b)
        pp_e = sum(1 for p, _, _ in reports[2]["subs"] if a <= p < b)
        rate = (sz_e + pp_e) / (2 * span) * 100
        mark = "   <-- P1030680 is 18 groups long" if lo == 10 else ""
        print(f"{f'{lo}-{hi}':<12}{span:>9}{sz_e:>9}{pp_e:>9}{rate:>13.1f}%{mark}")
    print()

    first40 = 40 * GROUP
    for r in reports[1:3]:
        early = sum(1 for p, _, _ in r["subs"] if p < first40)
        late = sum(1 for p, _, _ in r["subs"] if p >= first40)
        early_rate = early / min(first40, r["compared"]) * 100
        late_span = max(r["compared"] - first40, 1)
        late_rate = late / late_span * 100
        print(f"  {r['name']:<24} groups 1-40: {early:>3} errs ({early_rate:.1f}%)   "
              f"past 40: {late:>3} errs ({late_rate:.1f}%)")
    print()

    # --- what a short message would inherit ---------------------------------------------
    print("=== implication for a 72-letter message ===")
    for r in reports[1:3]:
        e = sum(1 for p, _, _ in r["subs"] if p < 72)
        print(f"  {r['name']:<24} errors in its own first 72 letters: {e}")
    combined = sum(1 for p, _, _ in FINAL_SUBS if p < 72) if (FINAL_SUBS := reports[3]["subs"]) else 0
    print(f"  final proofed copy       errors in first 72 letters: {combined}")
    print()
    print("Note the consensus rule Girard used: accept a letter if it matches EITHER re-proofed")
    print("transcript, else fall back to the Schluesselzettel. With two transcripts that")
    print("removes most single-copy errors. P1030680 has no second copy in the corpus, so it")
    print("inherits a single transcript's error rate, not the consensus rate.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
