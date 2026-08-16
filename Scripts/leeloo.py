#!/usr/bin/env python3
"""Leeloo — multi-pass re-validation of the claim ledger.

    python3 Scripts/leeloo.py --tier A            # cheap rows
    python3 Scripts/leeloo.py --tier A,B          # add moderate
    python3 Scripts/leeloo.py --tier C --runs 3   # expensive, hours
    python3 Scripts/leeloo.py --row C46 --runs 5
    python3 Scripts/leeloo.py --tier A,B,C --resume

Named for the multi-pass in *The Fifth Element*, because "run it five times and
report the spread" needed a shorter name and the joke is load-bearing: a single
pass is not a pass.

Why this exists
---------------
Every timing in directives/claim-sheet.md began as one observation. A cold run
of the same command measured 2.4x a warm one, so a lone number is not
reproducible even on the same machine. Separately, rows whose claim is a FAIL
were never checked for whether the failure is deterministic — an intermittent
negative is a much weaker claim than a reliable one.

This runner handles both, unattended, and is resumable so a multi-hour Tier C
sweep can be interrupted without losing work.

Output
------
  logs/leeloo/results.json   machine-readable, merged across runs
  logs/leeloo/report.md      human-readable table, regenerated each invocation
  logs/leeloo/<row>.log      raw stdout of the last pass for that row

Each row records: n, median, spread, per-pass verdicts, and a stability field
that is one of `stable-pass`, `stable-fail`, or `FLAKY`. `FLAKY` is the finding
that matters most: it means the ledger records a verdict the machine does not
reproduce every time.

Manifest
--------
`Scripts/leeloo_manifest.json` maps a claim row to the command that produces it,
the tier, and the figure the sheet currently claims. It is data, not code, so a
future maintainer can extend coverage without touching this file.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import statistics
import subprocess
import sys
import time

# Tier C sweeps run for hours and are usually piped to tee, which makes Python
# block-buffer stdout and hides all progress. Force line buffering so a long run
# is watchable.
try:
    sys.stdout.reconfigure(line_buffering=True)
except AttributeError:  # Python < 3.7
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTDIR = os.path.join(ROOT, "logs", "leeloo")
MANIFEST = os.path.join(ROOT, "Scripts", "leeloo_manifest.json")
RESULTS = os.path.join(OUTDIR, "results.json")
REPORT = os.path.join(OUTDIR, "report.md")

# The tool prints its own elapsed time as e.g. "  wall            0.2637 s".
WALL_RE = re.compile(r"wall\s+([0-9]+\.[0-9]+)\s*s")
VERDICT_RE = re.compile(r"result\s+(PASS|FAIL|SKIP)")


def competing_processes() -> list[str]:
    """Other HELUT benchmarks or leeloo sweeps already running.

    This is the precise hazard, and load average does not catch it: a single
    `helut` bench on a 16-core box is ~26% per core, well under any sane load
    threshold, yet it contends for the GPU and memory bandwidth and will skew
    every timing in a concurrent sweep. A concurrent `swift build` is worse
    still: it replaces .build/release/helut underneath a running sweep.
    """
    me = os.getpid()
    patterns = ("release/helut", "leeloo.py", "swift build", "swift-frontend", "swift test")
    found: list[str] = []
    try:
        out = subprocess.run(
            ["ps", "-Ao", "pid=,command="], capture_output=True, text=True, timeout=10
        ).stdout
    except (OSError, subprocess.SubprocessError):
        return found
    for line in out.splitlines():
        line = line.strip()
        if not line:
            continue
        pid_s, _, cmd = line.partition(" ")
        try:
            pid = int(pid_s)
        except ValueError:
            continue
        if pid in (me, os.getppid()):
            continue
        if any(p in cmd for p in patterns):
            found.append(f"pid {pid}: {cmd[:96]}")
    return found


def machine_busy(threshold_per_core: float = 0.35) -> tuple[bool, float, float]:
    """Is something else already loading this box?

    Timing measurements are only meaningful on an otherwise-idle machine, and
    the failure is silent: a concurrent build or a second leeloo makes every
    number in the run wrong without any error. Worse, `swift build` replaces
    .build/release/helut underneath a running sweep. So check, and say so.

    Returns (busy, load1, load_per_core).
    """
    try:
        load1 = os.getloadavg()[0]
    except (OSError, AttributeError):
        return (False, 0.0, 0.0)
    cores = os.cpu_count() or 1
    per_core = load1 / cores
    return (per_core > threshold_per_core, load1, per_core)


def load_json(path: str, default):
    if not os.path.exists(path):
        return default
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except json.JSONDecodeError:
        return default


# --- epsilon sample sufficiency -------------------------------------------
#
# Repeating a measurement five times tells you whether it is *reproducible*. It
# says nothing about whether the sample size inside each pass can support the
# claim, and those are different questions. An epsilon row can be perfectly
# stable across five passes and still assert a bar its own trial count cannot
# carry -- C36 does exactly that: point estimate -139.3, but the 95% bound at
# n=4 is -23.7, so "<= -64" is unproven no matter how many times it is repeated.
#
# helut-bench already prints the diagnosis. Leeloo's job is to not let it scroll
# past: a stable row with an unsupported bar must be visible in the report.
EPS_UNDERSAMPLED_RE = re.compile(r"under-sampled: n≈(\d+) would clear")
EPS_UNREACHABLE_RE = re.compile(r"point estimate itself fails")
# The two print shapes differ: a comfortable clear reads "95%up=-311.5 — clears
# -64" with an em dash, while everything else reads "95%up=-23.7 DOES NOT CLEAR
# -64". Allow the dash, or supported rows are misread as non-epsilon rows.
EPS_BOUND_RE = re.compile(r"95%up=(-?[\d.]+)\s*(?:—|--)?\s*(DOES NOT CLEAR|clears)")


def epsilon_sufficiency(text: str) -> dict | None:
    """Classify every epsilon verdict a pass printed.

    Returns None for rows that print no bound at all, so non-epsilon rows are
    unaffected. Otherwise reports the worst case found, since one unsupported
    bar in a sweep is enough to qualify the row.

    Logs produced before 2026-08-16 carry a bound but no diagnosis (they printed
    the ±1-order cost instead). Those classify as plain `bar-unmet`: the state is
    deliberately left un-diagnosed rather than guessed, since the distinction
    between under-sampled and genuinely unmet cannot be recovered from the old
    text.
    """
    bounds = EPS_BOUND_RE.findall(text)
    if not bounds:
        return None
    failing = [b for b in bounds if b[1] == "DOES NOT CLEAR"]
    if not failing:
        return {"state": "supported", "verdicts": len(bounds)}
    need = [int(m) for m in EPS_UNDERSAMPLED_RE.findall(text)]
    unreachable = bool(EPS_UNREACHABLE_RE.search(text))
    worst = min((float(b[0]) for b in failing), default=None)
    if need:
        return {
            "state": "under-sampled",
            "verdicts": len(bounds),
            "failing": len(failing),
            "worst_bound": worst,
            "samples_needed": max(need),
        }
    if unreachable:
        # Point estimate on the wrong side of the bar. Not a sampling problem,
        # and normally means the row is a recorded negative -- which is fine.
        return {
            "state": "bar-unmet-by-design",
            "verdicts": len(bounds),
            "failing": len(failing),
            "worst_bound": worst,
        }
    return {
        "state": "bar-unmet",
        "verdicts": len(bounds),
        "failing": len(failing),
        "worst_bound": worst,
    }


def verdicts_of(text: str) -> list[str]:
    return VERDICT_RE.findall(text)


def stability(verdict_sets: list[list[str]], exits: list[int]) -> str:
    """Collapse per-pass outcomes into a stability judgement.

    A crash is an *outcome*, not a missing one. An earlier version of this
    function discarded passes that printed no verdict, and consequently reported
    `stable-pass` for a row that actually PASSed 3 times and SIGTRAPped twice
    (C69 at n=512, found 2026-08-15). Exit status is therefore part of the
    outcome tuple, and a negative exit is rendered as the signal that killed it.
    """
    outcomes: list[str] = []
    for vs, code in zip(verdict_sets, exits):
        real = [v for v in vs if v != "SKIP"]
        if code != 0:
            sig = f"signal {-code}" if code < 0 else f"exit {code}"
            # Keep any verdict printed before the crash; it is diagnostic.
            outcomes.append(f"CRASH({sig})" + (f"+{'/'.join(real)}" if real else ""))
        elif not real:
            outcomes.append("no-verdict")
        else:
            outcomes.append("/".join(real))

    if not outcomes:
        return "no-runs"
    distinct = sorted(set(outcomes))
    if len(distinct) > 1:
        return "FLAKY:" + ",".join(f"{o}x{outcomes.count(o)}" for o in distinct)
    only = distinct[0]
    if only.startswith("CRASH"):
        return f"stable-crash ({only})"
    if only == "no-verdict":
        return "no-verdict"
    if "FAIL" in only:
        return "stable-fail"
    if set(only.split("/")) == {"PASS"}:
        return "stable-pass"
    return f"stable-mixed ({only})"


def run_row(row: dict, runs: int, warmup: int, quiet: bool) -> dict:
    cmd = row["cmd"]
    if isinstance(cmd, str):
        cmd = cmd.split()
    label = row.get("label", row["id"])
    walls: list[float] = []
    tool: list[float] = []
    vsets: list[list[str]] = []
    exits: list[int] = []
    last_out = ""

    print(f"\n=== {row['id']} [{row.get('tier','?')}] {label}")
    print(f"    claims: {row.get('claims','(none recorded)')}")

    for i in range(warmup + runs):
        warm = i < warmup
        t0 = time.monotonic()
        proc = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
        wall = time.monotonic() - t0
        out = proc.stdout + proc.stderr
        last_out = out
        m = WALL_RE.search(out)
        got = float(m.group(1)) if m else None
        vs = verdicts_of(out)
        tag = "warmup" if warm else f"pass {i - warmup + 1}"
        if not quiet:
            shown = "/".join(vs) if vs else "-"
            extra = f" tool={got:.4g}s" if got is not None else ""
            print(f"    {tag:8} wall={wall:8.3f}s exit={proc.returncode} {shown}{extra}")
        if warm:
            continue
        exits.append(proc.returncode)
        walls.append(wall)
        vsets.append(vs)
        if got is not None:
            tool.append(got)

    os.makedirs(OUTDIR, exist_ok=True)
    with open(os.path.join(OUTDIR, f"{row['id']}.log"), "w", encoding="utf-8") as fh:
        fh.write(last_out)

    def stats(xs: list[float]) -> dict | None:
        if not xs:
            return None
        med = statistics.median(xs)
        return {
            "n": len(xs),
            "min": min(xs),
            "median": med,
            "mean": statistics.fmean(xs),
            "max": max(xs),
            "stdev": statistics.stdev(xs) if len(xs) > 1 else 0.0,
            "spread": (max(xs) - min(xs)) / med if med else 0.0,
        }

    stab = stability(vsets, exits)
    eps = epsilon_sufficiency(last_out)
    res = {
        "id": row["id"],
        "tier": row.get("tier"),
        "label": label,
        "claims": row.get("claims"),
        "cmd": " ".join(cmd),
        "runs": runs,
        "warmup": warmup,
        "exits": exits,
        "verdicts": vsets,
        "stability": stab,
        # None for non-epsilon rows. Reproducibility and sample sufficiency are
        # independent properties; a row can be stable and still unsupported.
        "epsilon": eps,
        "wall": stats(walls),
        "tool_wall": stats(tool),
        "when": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "host": os.uname().nodename,
        # Provenance for the timing: a number taken on a loaded box is not
        # comparable to one taken on a quiet box, and without this field a
        # future reader cannot tell which they are looking at.
        "load_per_core_at_end": machine_busy()[2],
    }
    ts = res["tool_wall"] or res["wall"]
    if ts:
        print(
            f"    -> median {ts['median']:.4g}s  spread {ts['spread']*100:.1f}%  "
            f"stability {stab}"
        )
    else:
        print(f"    -> no timing captured; stability {stab}")
    if stab.startswith("FLAKY") or "crash" in stab:
        print(f"    !! {stab}: the recorded verdict does not reproduce every pass")
    if eps and eps["state"] == "under-sampled":
        print(
            f"    !! epsilon bar unsupported at this trial count: bound "
            f"{eps['worst_bound']}, needs n≈{eps['samples_needed']}. "
            f"Repeating the pass will not fix this — the sample size inside "
            f"each pass is the problem."
        )
    return res


def write_report(results: dict) -> None:
    rows = sorted(results.values(), key=lambda r: int(re.sub(r"\D", "", r["id"]) or 0))
    lines = [
        "# Leeloo multi-pass re-validation",
        "",
        "Generated by `python3 Scripts/leeloo.py`. Timings are the tool's own",
        "reported wall where available, else process wall. Quote the median and",
        "the spread, never a single pass.",
        "",
        "| Row | Tier | Sheet claims | Median | Spread | n | Stability |",
        "|-----|------|--------------|--------|--------|---|-----------|",
    ]
    for r in rows:
        s = r.get("tool_wall") or r.get("wall")
        med = f"{s['median']:.4g} s" if s else "—"
        spread = f"{s['spread']*100:.1f}%" if s else "—"
        n = s["n"] if s else 0
        stab = r["stability"]
        flag = " **FLAKY**" if stab == "FLAKY" else ""
        lines.append(
            f"| {r['id']} | {r.get('tier','?')} | {r.get('claims') or '—'} | "
            f"{med} | {spread} | {n} | {stab}{flag} |"
        )
    # Match on prefix: stability strings carry detail, e.g.
    # "FLAKY:CRASH(signal 5)x2,PASSx3". An equality test here silently reported
    # "no flaky rows" while two rows were flaky.
    flaky = [r["id"] for r in rows if str(r["stability"]).startswith("FLAKY")]
    crashed = [r["id"] for r in rows if "crash" in str(r["stability"]).lower()
               and not str(r["stability"]).startswith("FLAKY")]
    lines += ["", f"Rows measured: {len(rows)}."]
    if flaky:
        lines.append("")
        lines.append(f"**FLAKY — recorded verdict did not reproduce on every pass: {', '.join(flaky)}**")
        lines.append("")
        lines.append("A verdict that reproduces intermittently is a weaker claim than the")
        lines.append("ledger states, in whichever direction it points. See AUDIT.md §10-11.")
    if crashed:
        lines.append(f"**Always-crashing rows: {', '.join(crashed)}**")
    if not flaky and not crashed:
        lines.append("No flaky rows in this set: every recorded verdict reproduced on every pass.")

    # Sample sufficiency is orthogonal to reproducibility, and reporting only the
    # latter is how an unsupported bar survives five passes unnoticed.
    under = [r for r in rows if (r.get("epsilon") or {}).get("state") == "under-sampled"]
    bydesign = [r["id"] for r in rows
                if (r.get("epsilon") or {}).get("state") == "bar-unmet-by-design"]
    if under:
        lines += [
            "",
            "## ε bars not supported by their own sample size",
            "",
            "These rows reproduced fine. That is a different property from having",
            "enough samples to support the bar they quote: the 95% bound scales as",
            "`σ̂·√(m/χ²₀.₀₅(m))`, so a thin margin needs a large *m* regardless of how",
            "many times the pass is repeated. Re-running Leeloo will not move these.",
            "",
            "| Row | 95% bound | samples needed |",
            "|-----|-----------|----------------|",
        ]
        for r in under:
            e = r["epsilon"]
            lines.append(f"| {r['id']} | {e['worst_bound']} | n≈{e['samples_needed']} |")
    if bydesign:
        lines += [
            "",
            f"Rows whose ε point estimate is itself past the bar (recorded negatives, "
            f"no sample size helps): {', '.join(bydesign)}.",
        ]
    os.makedirs(OUTDIR, exist_ok=True)
    with open(REPORT, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tier", default="A", help="comma list: A,B,C")
    ap.add_argument("--row", default=None, help="single row id, e.g. C46")
    ap.add_argument("--runs", type=int, default=5)
    ap.add_argument("--warmup", type=int, default=1)
    ap.add_argument("--resume", action="store_true", help="skip rows already in results.json")
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--list", action="store_true", help="show the manifest and exit")
    ap.add_argument(
        "--allow-busy",
        action="store_true",
        help="run even if the machine is loaded (timings will be wrong)",
    )
    args = ap.parse_args()

    manifest = load_json(MANIFEST, None)
    if manifest is None:
        print(f"error: no manifest at {MANIFEST}", file=sys.stderr)
        return 2
    rows = manifest["rows"]

    if args.list:
        for r in rows:
            print(f"  {r['id']:5} {r.get('tier','?')}  {r.get('claims',''):16} {r.get('label','')}")
        return 0

    if args.row:
        want = [r for r in rows if r["id"].upper() == args.row.upper()]
    else:
        tiers = {t.strip().upper() for t in args.tier.split(",")}
        want = [r for r in rows if (r.get("tier") or "").upper() in tiers]

    results = load_json(RESULTS, {})
    if args.resume:
        before = len(want)
        want = [r for r in want if r["id"] not in results]
        print(f"resume: {before - len(want)} row(s) already done, {len(want)} to go")

    if not want:
        print("nothing to run")
        write_report(results)
        return 0

    rivals = competing_processes()
    busy, load1, per_core = machine_busy()
    if (rivals or busy) and not args.allow_busy:
        print("REFUSING TO RUN.")
        if rivals:
            print("\nAlready running (would contend, and a build would swap the binary):")
            for r in rivals:
                print(f"  {r}")
        if busy:
            print(f"\nLoad average {load1:.2f} = {per_core*100:.0f}% per core.")
        print(
            "\nTimings taken against a competing HELUT process are not comparable to"
            "\nthe ledger. Note that one helut bench on this box is only ~26% per core,"
            "\nso load average alone does not catch it. Wait for the box to go quiet."
            "\nPass --allow-busy if you only care about PASS/FAIL stability, not timing."
        )
        return 2
    if rivals or busy:
        print(f"WARNING: {len(rivals)} competing process(es), load {load1:.2f}; timings untrustworthy.\n")

    est = sum(r.get("approx_seconds", 5) for r in want) * (args.runs + args.warmup)
    print(f"Leeloo: {len(want)} row(s), {args.runs} passes + {args.warmup} warmup")
    print(f"load at start: {load1:.2f} ({per_core*100:.0f}%/core)")
    print(f"rough estimate: {est/60:.1f} min\n")

    for r in want:
        try:
            results[r["id"]] = run_row(r, args.runs, args.warmup, args.quiet)
        except FileNotFoundError as e:
            print(f"    skipped: {e}")
            continue
        os.makedirs(OUTDIR, exist_ok=True)
        with open(RESULTS, "w", encoding="utf-8") as fh:
            json.dump(results, fh, indent=2, sort_keys=True)
        write_report(results)

    write_report(results)
    flaky = [k for k, v in results.items() if v["stability"] == "FLAKY"]
    print(f"\nwrote {RESULTS}")
    print(f"wrote {REPORT}")
    if flaky:
        print(f"FLAKY rows: {', '.join(sorted(flaky))}")
        return 1
    print("no flaky rows")
    return 0


if __name__ == "__main__":
    sys.exit(main())
