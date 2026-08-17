#!/usr/bin/env python3
"""Mechanical claim-integrity audit. Stdlib only, no Mac required.

    python3 Scripts/claim_audit.py          # report, exit 1 on any FAIL
    python3 Scripts/claim_audit.py --quiet  # only failures

Checks the things that silently drift between surfaces:

  1. Every C/H/N id cited in the textbook exists in directives/claim-sheet.md.
  2. Every C id in the sheet appears somewhere in the textbook, or is listed
     as a known index-only row.
  3. \\reproduced{...} / \\hedgebox{...} first arguments are real claim ids.
     A green "Reproduced" box keyed to a non-claim is how a negative gets
     laundered into a receipt.
  4. No \\cid{} / \\hid{} / \\nid{} is called with an empty argument, which
     would make claim references non-extractable.
  5. \\livingepoch in preamble.tex names the newest C row in the sheet.
  6. Every `swift test --filter NAME` cited anywhere resolves to a real
     `func testNAME` under Tests/.
  7. Every logs/*.log path cited in the sheet exists on disk.
  8. The sheet's receipt-grade column is present and self-consistent.

This is a lint, not a validation of the science. It cannot tell you whether a
number is true; only whether the thing that is supposed to prove it exists.
"""

from __future__ import annotations

import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHEET = "directives/claim-sheet.md"
PREAMBLE = "textbook/preamble.tex"
TEXBOOK_GLOBS = ["textbook/chapters", "textbook/appendices"]

# C rows that legitimately appear only in the claim index snapshot, not in a
# chapter. Keep this list short and justified; it is an exception register.
INDEX_ONLY_OK = {7, 13, 15}  # C27 got a stated theorem 2026-08-15

FAILURES: list[str] = []
NOTES: list[str] = []


def read(rel: str) -> str:
    with open(os.path.join(ROOT, rel), encoding="utf-8") as fh:
        return fh.read()


def tex_sources() -> list[tuple[str, str]]:
    out = []
    for d in TEXBOOK_GLOBS:
        full = os.path.join(ROOT, d)
        if not os.path.isdir(full):
            continue
        for name in sorted(os.listdir(full)):
            if name.endswith(".tex"):
                rel = os.path.join(d, name)
                out.append((rel, read(rel)))
    return out


def sheet_ids() -> tuple[set[int], set[int], set[int], str]:
    txt = read(SHEET)
    c = {int(m) for m in re.findall(r"^\|\s*\*\*C(\d+)\*\*\s*\|", txt, re.M)}
    h = {int(m) for m in re.findall(r"^\|\s*\*\*H(\d+)\*\*", txt, re.M)}
    n = {int(m) for m in re.findall(r"^\|\s*\*\*N(\d+)\*\*", txt, re.M)}
    return c, h, n, txt


def fail(check: str, msg: str) -> None:
    FAILURES.append(f"[{check}] {msg}")


def check_citations(c: set[int], h: set[int], n: set[int], srcs) -> None:
    # Chapter citations only. The claim-index appendix is a snapshot of the
    # sheet, so counting it would mask rows that no chapter ever discusses.
    cited_c: set[int] = set()
    for rel, txt in srcs:
        if "chapters" not in rel:
            continue
        for m in re.finditer(r"\\cid\{(\d+)\}", txt):
            cited_c.add(int(m.group(1)))
        # A \reproduced{C62}{...} box is a chapter discussing C62. Keys may be
        # lists or ranges: "C4--C6", "C8, C9", "C20/21".
        for m in re.finditer(r"\\(?:reproduced|hedgebox|negativebox|recheckbox)\{([^}]*)\}", txt):
            key = m.group(1)
            for lo, hi in re.findall(r"C(\d+)\s*-{2,}\s*C?(\d+)", key):
                cited_c.update(range(int(lo), int(hi) + 1))
            for num in re.findall(r"C(\d+)", key):
                cited_c.add(int(num))
            # "C20/21" style shorthand
            for base, tail in re.findall(r"C(\d+)/(\d+)", key):
                cited_c.add(int(tail))
    for rel, txt in srcs:
        for kind, ids in (("cid", c), ("hid", h), ("nid", n)):
            for m in re.finditer(r"\\%s\{([^}]*)\}" % kind, txt):
                arg = m.group(1).strip()
                line = txt[: m.start()].count("\n") + 1
                if arg == "":
                    fail("empty-arg", f"{rel}:{line} \\{kind}{{}} with no id")
                    continue
                # Ranges like 4--6 or lists are written as separate macros in
                # this corpus; only bare integers are expected here.
                if not arg.isdigit():
                    NOTES.append(f"{rel}:{line} \\{kind}{{{arg}}} not a bare integer")
                    continue
                num = int(arg)
                if num not in ids:
                    fail(
                        "unknown-id",
                        f"{rel}:{line} \\{kind}{{{num}}} is not in {SHEET}",
                    )
    missing = sorted(x for x in c - cited_c if x not in INDEX_ONLY_OK)
    if missing:
        fail(
            "uncited-claim",
            f"C rows in the sheet that no chapter discusses (index-only): {missing}",
        )
    stale_exceptions = sorted(INDEX_ONLY_OK & cited_c)
    if stale_exceptions:
        NOTES.append(
            f"INDEX_ONLY_OK can drop {stale_exceptions} (now cited in a chapter)"
        )


def check_box_keys(c: set[int], h: set[int], srcs) -> None:
    """\\reproduced / \\hedgebox must be keyed to claim ids, not free text."""
    pat = re.compile(r"\\(reproduced|hedgebox|negativebox|recheckbox)\{([^}]*)\}")
    for rel, txt in srcs:
        for m in pat.finditer(txt):
            box, key = m.group(1), m.group(2)
            line = txt[: m.start()].count("\n") + 1
            ids = re.findall(r"\\?[ChN]?[a-z]*id?\{?(\d+)\}?|(?:^|[^A-Za-z])([CHN])(\d+)", key)
            found = re.findall(r"\b([CHN])\s*(\d+)", key) + [
                (k.upper(), num) for k, num in re.findall(r"\\([chn])id\{(\d+)\}", key)
            ]
            if box == "reproduced":
                if not found:
                    fail(
                        "box-key",
                        f"{rel}:{line} \\reproduced{{{key}}} names no C id "
                        f"(green box with no receipt)",
                    )
                    continue
                kinds = {k for k, _ in found}
                if kinds == {"H"}:
                    fail(
                        "box-key",
                        f"{rel}:{line} \\reproduced{{{key}}} keyed only to an H id; "
                        f"use the C row that closed it",
                    )
                for k, num in found:
                    pool = c if k == "C" else (h if k == "H" else set())
                    if pool and int(num) not in pool:
                        fail("box-key", f"{rel}:{line} \\{box}{{{key}}} unknown {k}{num}")
            elif box in ("hedgebox", "negativebox", "recheckbox") and not found:
                NOTES.append(f"{rel}:{line} \\{box}{{{key}}} has no claim id")


def check_epoch(c: set[int]) -> None:
    txt = read(PREAMBLE)
    m = re.search(r"\\newcommand\{\\livingepoch\}\{([^}]*)\}", txt)
    if not m:
        fail("epoch", f"{PREAMBLE} has no \\livingepoch")
        return
    epoch = m.group(1)
    em = re.search(r"C(\d+)\s*$", epoch.strip())
    if not em:
        fail("epoch", f"\\livingepoch {epoch!r} does not end in a C id")
        return
    if int(em.group(1)) != max(c):
        fail(
            "epoch",
            f"\\livingepoch names C{em.group(1)} but newest sheet row is C{max(c)}",
        )


def check_test_filters() -> None:
    """Every `--filter X` cited in the docs must resolve to something runnable.

    `swift test --filter` accepts a test-function name, a suite/class name, or
    `Suite/testFunc`. The lint originally recognised only function names, so a
    legitimate class-level filter was reported as missing. Collect both, and
    accept either side of a `Suite/testFunc` pair.
    """
    funcs: set[str] = set()
    suites: set[str] = set()
    tests_dir = os.path.join(ROOT, "Tests")
    for dirpath, _, names in os.walk(tests_dir):
        for nm in names:
            if nm.endswith(".swift"):
                with open(os.path.join(dirpath, nm), encoding="utf-8") as fh:
                    body = fh.read()
                funcs |= set(re.findall(r"func\s+(test[A-Za-z0-9_]+)", body))
                # `final class Foo: XCTestCase`, `class Foo: XCTestCase`,
                # and swift-testing `@Suite struct Foo`.
                suites |= set(
                    re.findall(r"(?:final\s+)?class\s+([A-Za-z0-9_]+)\s*:\s*XCTestCase", body)
                )
                suites |= set(re.findall(r"@Suite[^\n]*\n\s*struct\s+([A-Za-z0-9_]+)", body))
    runnable = funcs | suites

    scanned = [SHEET, "REPRODUCE.md", "REVIEWER.md"] + [r for r, _ in tex_sources()]
    seen: set[str] = set()
    for rel in scanned:
        path = os.path.join(ROOT, rel)
        if not os.path.exists(path):
            continue
        txt = read(rel)
        # Optional quoting, and an optional `/testFunc` tail.
        pattern = r"--filter\s+['\"]?\\?([A-Za-z0-9_]+)(?:/([A-Za-z0-9_]+))?"
        for m in re.finditer(pattern, txt):
            head, tail = m.group(1), m.group(2)
            cited = f"{head}/{tail}" if tail else head
            seen.add(cited)
            if tail:
                # Suite/func form: both halves must exist.
                if head not in suites:
                    fail("test-filter", f"{rel} cites --filter {cited}, no suite {head} in Tests/")
                if tail not in funcs:
                    fail("test-filter", f"{rel} cites --filter {cited}, no func {tail} in Tests/")
            elif head not in runnable:
                fail(
                    "test-filter",
                    f"{rel} cites --filter {head}, no such func or suite in Tests/",
                )
    NOTES.append(
        f"test filters cited: {len(seen)}; "
        f"test funcs found: {len(funcs)}; suites found: {len(suites)}"
    )


def check_logs() -> None:
    txt = read(SHEET)
    missing = []
    for m in re.finditer(r"`(logs/[A-Za-z0-9_.\-*]+\.(?:log|json))`", txt):
        rel = m.group(1)
        if "*" in rel:
            import glob

            if not glob.glob(os.path.join(ROOT, rel)):
                missing.append(rel + " (glob matched nothing)")
            continue
        if not os.path.exists(os.path.join(ROOT, rel)):
            missing.append(rel)
    for rel in missing:
        fail("missing-log", f"{SHEET} cites {rel}, not on disk")


def check_quoted_numbers(txt: str, strict: bool = False) -> None:
    """Every σ̂ / εlog2 / bound figure quoted in a row must appear in a log that
    row cites.

    Why this exists. The lint checked that cited logs *exist* and that `--filter`
    names *resolve*, but never that a number in the prose matched the measurement
    behind it. Two things got through that gap:

      * C30 carried `εlog2 = −∞` for inject B ≤ 8. That was the Gaussian tail
        underflowing, not zero failure probability, and it sat in the sheet
        unchallenged because nothing compared it to anything.
      * A `k²` scaling law was written up as holding "to ~1%" when the real
        exponent is 1.94–1.97. Caught only because it was also written as a test,
        which failed on first run.

    Deliberately narrow. It only checks figures printed in a form the tools emit
    verbatim -- `σ̂=NNN`, `εlog2=−NN.N`, `bound −NN.N` -- because those are
    machine-comparable. Rounded prose (`σ̂≈2.95×10⁴`), derived quantities, and
    ratios are skipped: flagging those would bury a real finding in noise.

    Advisory by default: reports coverage and misses as notes. `--strict` turns a
    miss into a failure, for use when the sheet has been freshly re-measured and
    every quoted figure should be traceable.
    """
    rows = [ln for ln in txt.split("\n") if re.match(r"\|\s*\*\*[CHN]\d+\*\*", ln)]
    checked = matched = 0
    misses: list[str] = []

    # Narrow no-break space and friends appear inside grouped digits in the sheet.
    def norm(s: str) -> str:
        for ch in ("\u202f", "\u00a0", "\u2009", " ", ","):
            s = s.replace(ch, "")
        return s.replace("\u2212", "-")

    for ln in rows:
        rid = re.match(r"\|\s*\*\*([CHN]\d+)\*\*", ln).group(1)
        cited = re.findall(r"`(logs/[A-Za-z0-9_.\-*{},/]+\.(?:log|json))`", ln)
        if not cited:
            continue
        # Expand brace sets, e.g. c41-n512-n{16,64,256}.log
        paths: list[str] = []
        for rel in cited:
            m = re.search(r"\{([^}]*)\}", rel)
            if m:
                for alt in m.group(1).split(","):
                    paths.append(rel[: m.start()] + alt.strip() + rel[m.end():])
            else:
                paths.append(rel)
        blob = ""
        for rel in paths:
            for cand in glob.glob(os.path.join(ROOT, rel)) or [os.path.join(ROOT, rel)]:
                if os.path.exists(cand):
                    with open(cand, encoding="utf-8", errors="replace") as fh:
                        blob += fh.read()
        if not blob:
            continue
        nblob = norm(blob)

        # Only the exact machine-printed forms.
        wanted: list[tuple[str, str]] = []
        # Plain decimal only. Scientific-notation forms (`σ̂=1.47×10⁵`) are
        # deliberately-rounded prose. A negative lookahead does not work here:
        # the regex simply backtracks to a shorter digit run and satisfies it.
        # So capture, then inspect what follows.
        for m in re.finditer(r"σ̂\s*=\s*([\d\u202f\u00a0, ]+(?:\.\d+)?)", ln):
            tail = ln[m.end():m.end() + 4]
            if re.match(r"\s*[×xe]\s*10", tail):
                continue
            wanted.append(("σ̂", m.group(1)))
        for m in re.finditer(r"εlog2\s*=\s*(\u2212?-?\d+\.\d+)", ln):
            wanted.append(("εlog2", m.group(1)))
        for m in re.finditer(r"bound\s+\*{0,2}(\u2212?-?\d+\.\d+)", ln):
            wanted.append(("bound", m.group(1)))

        # Pull the typed figures the tools actually print, so comparison is
        # numeric rather than textual. String matching failed on legitimate prose
        # rounding: the sheet writes "σ̂=73 026" for a logged 73025.9.
        logged = {
            "σ̂": [float(x) for x in re.findall(r"σ̂=([\d.]+)", blob)],
            "εlog2": [float(x) for x in re.findall(r"εlog2=(-?\d+\.\d+)", blob)],
            "bound": [float(x) for x in re.findall(r"95%up=(-?\d+\.\d+)", blob)],
        }

        for kind, raw in wanted:
            checked += 1
            v = norm(raw).rstrip(".").rstrip(",")
            try:
                quoted = float(v)
            except ValueError:
                misses.append(f"{rid} {kind}={raw.strip()} unparseable")
                continue
            decimals = len(v.split(".")[1]) if "." in v else 0
            # A quoted figure matches if rounding the logged value to the quoted
            # precision reproduces it. Also accept sign-flipped forms, since rows
            # sometimes write a magnitude where the tool prints a negative.
            pool = logged.get(kind, [])
            if kind == "bound":
                pool = pool + logged["εlog2"]  # some rows quote the point as a bound
            # Half-a-unit-in-the-last-place, not round(): Python rounds
            # 110586.5 to 110586 (banker's), so a sheet legitimately quoting
            # 110587 read as untraced.
            tol = 0.5 * (10 ** -decimals) + 1e-9
            hit = any(
                abs(cand - quoted) <= tol or abs(-cand - quoted) <= tol
                for cand in pool
            )
            if hit:
                matched += 1
            else:
                misses.append(f"{rid} {kind}={raw.strip()} not in its cited log(s)")

    NOTES.append(
        f"quoted figures traced to logs: {matched}/{checked}"
        + (f"; {len(misses)} untraced" if misses else "")
    )
    for msg in misses:
        if strict:
            fail("untraced-number", msg)
        else:
            NOTES.append(f"untraced: {msg}")


def check_grade_column(txt: str, c: set[int]) -> None:
    if "| ID | Grade |" not in txt:
        fail("grade-col", f"{SHEET} C table has no Grade column")
        return
    graded = {int(m.group(1)): m.group(2) for m in re.finditer(r"\|\s*\*\*C(\d+)\*\*\s*\|\s*(\*\*P\*\*|R\+L|R)\s*\|", txt)}
    ungraded = sorted(c - set(graded))
    if ungraded:
        fail("grade-col", f"C rows with no grade: {ungraded}")
    from collections import Counter

    dist = Counter(graded.values())
    NOTES.append("receipt grades: " + ", ".join(f"{k}={v}" for k, v in sorted(dist.items())))


def main() -> int:
    quiet = "--quiet" in sys.argv
    c, h, n, txt = sheet_ids()
    srcs = tex_sources()

    if not c:
        print(f"FAIL could not parse C rows from {SHEET}")
        return 1

    check_grade_column(txt, c)
    check_citations(c, h, n, srcs)
    check_box_keys(c, h, srcs)
    check_epoch(c)
    check_test_filters()
    check_logs()
    check_quoted_numbers(txt, strict="--strict" in sys.argv)

    if not quiet:
        print(f"claim sheet: C={len(c)} (max C{max(c)})  H={len(h)}  N={len(n)}")
        print(f"textbook sources scanned: {len(srcs)}")
        for note in NOTES:
            print(f"  note: {note}")
        print()

    if FAILURES:
        for f in FAILURES:
            print(f"FAIL {f}")
        print(f"\n{len(FAILURES)} failure(s)")
        return 1
    print("PASS claim integrity lint clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
