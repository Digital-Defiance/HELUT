#!/usr/bin/env bash
# Close the confidence gap on the three under-sampled ε rows: C36, C37, C41@N=512.
#
# What this is fixing. Each of these rows quotes a point estimate that clears
# 2⁻⁶⁴, but at the trial count actually used the 95% upper bound does not:
#
#   C36  covering-b1 N=1024 B=32     point −139.3   n=4   bound −23.7
#   C37  covering-b1 N=1024 σ=24     point −159.4   n=4   bound −27.3
#   C41  covering-b1 N=512  σ=128    point  −76.6   n=4   bound −12.6
#
# None of that is a code fault; σ̂ reproduces exactly. They are under-sampled, and
# the required count is a closed-form function of the margin (see
# samplesToClearFailureTarget): n≈16, n≈12, n≈256 respectively. Targets below add
# margin on top.
#
# C41 runs as a ladder rather than one shot. Its σ̂ is known sample-sensitive --
# the sheet already flags that trials=2 gave −696 against trials=4's −76.6 -- so
# if σ̂ drifts upward with more samples the point estimate worsens and no
# affordable n clears the bar. The ladder surfaces that early instead of after
# six hours.
#
# Usage: ./Scripts/close_eps_confidence.sh [outdir]

set -uo pipefail

OUT="${1:-logs/eps-confidence-2026-08-16}"
mkdir -p "$OUT"
SUMMARY="$OUT/SUMMARY.txt"
BENCH=.build/release/helut-bench
: > "$SUMMARY"

note() { printf '%s\n' "$*" | tee -a "$SUMMARY"; }

note "Closing the ε confidence gap on under-sampled rows"
note "started: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
note "commit:  $(git rev-parse --short HEAD)"
note ""

# run <label> <logfile> <command...>
run() {
  local label="$1"; shift
  local log="$1"; shift
  local start end rc verdict
  start=$(date +%s)
  printf '  %-40s ' "$label"
  "$@" > "$OUT/$log" 2>&1
  rc=$?
  end=$(date +%s)
  # Pull the decisive line straight out of the log rather than trusting rc.
  verdict=$(grep -a '95%up' "$OUT/$log" | tail -1 \
    | sed -E 's/.*(εlog2=[-0-9.]+).*(95%up=[-0-9.]+)(.*)/\1 \2\3/' | cut -c1-96)
  printf 'rc=%d %5ds\n' "$rc" "$((end - start))"
  note "$label  ($((end - start))s, rc=$rc)"
  note "    $verdict"
  note ""
  return 0
}

note "-- C36: covering-b1 N=1024 B=32, need n≈16, running n=24 --"
run "C36 n=24" "c36-n24.log" \
  "$BENCH" --measure-bk-noise --degree 1024 --trials 24 --bk-noise 32 --covering-base-log 1

note "-- C37: covering-b1 N=1024 sigma=24, need n≈12, running n=20 --"
run "C37 n=20" "c37-n20.log" \
  "$BENCH" --measure-bk-noise --degree 1024 --trials 20 --bk-noise-sigma 24 --covering-base-log 1

note "-- C41: covering-b1 N=512 sigma=128, need n≈256. Ladder, sigma-hat is"
note "   known sample-sensitive so watch it settle before paying for the big run. --"
for n in 16 64 256; do
  run "C41 N=512 n=$n" "c41-n512-n$n.log" \
    "$BENCH" --measure-bk-noise --degree 512 --trials "$n" \
    --bk-noise-sigma 128 --covering-base-log 1
done

note "finished: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
note ""
note "Read the 95%up figure, not the exit code. 'clears -64' closes the row;"
note "'under-sampled: n≈N would clear' means the margin held but needs more n;"
note "'point estimate itself fails' means sigma-hat drifted and the claim must"
note "be weakened rather than re-run."
