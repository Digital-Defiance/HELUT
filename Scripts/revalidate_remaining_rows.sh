#!/usr/bin/env bash
# Re-run the nine claim rows that were NOT re-run after the 2026-08-15
# determinism fix: C26, C30, C33, C34, C36, C37, C41, C55, C56.
#
# Why they were skipped, and why they are being done now.
#
# The determinism bug lived in EncryptedNetlistSimulator.tick, which encrypted
# primary inputs while iterating a Dictionary and drawing from the shared RNG.
# Two consequences:
#
#   * `--measure-bk-noise` rows never touch that code. They call
#     TFHENoisyBKMeasurement.identity, which encrypts a single LWE sample
#     directly. Structurally unaffected -- re-run here for completeness, not
#     because there is reason to doubt them.
#   * `--bench-encrypted --sing` rows DO go through tick(). These are the ones
#     that could in principle have been decided by a mask permutation, and they
#     are the point of this run.
#
# Timing note: several of these are N=1024 covering runs at ~78-155 s per trial.
# Expect hours, not minutes. Logs are written per row so a partial run is still
# useful, and every row prints a PASS/FAIL banner.
#
# Usage:
#   ./Scripts/revalidate_remaining_rows.sh [outdir]
#
# Default outdir: logs/revalidate-2026-08-16

set -uo pipefail

OUT="${1:-logs/revalidate-2026-08-16}"
mkdir -p "$OUT"
SUMMARY="$OUT/SUMMARY.txt"
BENCH=.build/release/helut-bench
: > "$SUMMARY"

note() { printf '%s\n' "$*" | tee -a "$SUMMARY"; }

note "Re-validation of rows not covered after the determinism fix"
note "started: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
note "commit:  $(git rev-parse --short HEAD)"
note ""

# run <label> <logfile> <command...>
run() {
  local label="$1"; shift
  local log="$1"; shift
  local start end rc
  start=$(date +%s)
  printf '  %-42s ' "$label"
  "$@" > "$OUT/$log" 2>&1
  rc=$?
  end=$(date +%s)
  if [ $rc -eq 0 ]; then
    printf 'ok   %5ds\n' "$((end - start))"
    note "PASS $label  ($((end - start))s)  $log"
  else
    printf 'FAIL %5ds (rc=%d)\n' "$((end - start))" "$rc"
    note "FAIL $label  ($((end - start))s, rc=$rc)  $log"
  fi
  return 0
}

note "-- noise measurements (do not exercise tick(); completeness only) --"

# C26: product-shaped N=1024 residual, both inject levels.
run "C26 measure-bk-noise N=1024 B=64" "c26-b64.log" \
  "$BENCH" --measure-bk-noise --degree 1024 --trials 2 --bk-noise 64
run "C26 measure-bk-noise N=1024 B=4" "c26-b4.log" \
  "$BENCH" --measure-bk-noise --degree 1024 --trials 2 --bk-noise 4

# C30: eps vs inject B ladder at N=128.
{
  for B in 1 2 4 8 16 32 64; do
    "$BENCH" --measure-bk-noise --degree 128 --trials 8 --bk-noise "$B"
  done
} > "$OUT/c30-eps-sweep-n128.log" 2>&1 \
  && note "PASS C30 eps-vs-B ladder N=128           c30-eps-sweep-n128.log" \
  || note "FAIL C30 eps-vs-B ladder N=128           c30-eps-sweep-n128.log"

# C34 / C36 / C37 / C41 / C55 / C56 noise halves.
run "C34 covering-b4 N=1024 B=1" "c34-noise.log" \
  "$BENCH" --measure-bk-noise --degree 1024 --trials 8 --bk-noise 1 --covering-base-log 4
run "C36 covering-b1 N=1024 B=32" "c36-noise.log" \
  "$BENCH" --measure-bk-noise --degree 1024 --trials 4 --bk-noise 32 --covering-base-log 1
run "C37 covering-b1 N=1024 sigma=24" "c37-noise.log" \
  "$BENCH" --measure-bk-noise --degree 1024 --trials 4 --bk-noise-sigma 24 --covering-base-log 1
run "C41 covering-b1 N=256 sigma=128" "c41-noise-n256.log" \
  "$BENCH" --measure-bk-noise --degree 256 --trials 2 --bk-noise-sigma 128 --covering-base-log 1
run "C41 covering-b1 N=512 sigma=128" "c41-noise-n512.log" \
  "$BENCH" --measure-bk-noise --degree 512 --trials 4 --bk-noise-sigma 128 --covering-base-log 1
run "C55 covering-b1 N=1024 sigma=128 lwe=256" "c55-noise.log" \
  "$BENCH" --measure-bk-noise --degree 1024 --trials 8 --bk-noise-sigma 128 \
  --covering-base-log 1 --lwe-dimension 256
run "C56 cryptoPublicMS N=1024 B=1 k=7" "c56-noise.log" \
  "$BENCH" --measure-bk-noise --degree 1024 --trials 4 --bk-noise 1 --boolean-scale-mul 7

note ""
note "-- encrypted SING (these DO exercise the fixed tick() path) --"

run "C33 SING N=1024 covering-crypto B=1" "c33-sing.log" \
  "$BENCH" --bench netlist.json --degree 1024 --bench-encrypted --sing --vectors 2 \
  --bk-noise 1 --paths 'blind-rotate-metal secret crypto'
run "C34 SING N=1024 covering-b4 B=1" "c34-sing.log" \
  "$BENCH" --bench netlist.json --degree 1024 --bench-encrypted --sing --vectors 2 \
  --bk-noise 1 --paths covering-b4
run "C36 SING N=1024 covering-b1 B=32" "c36-sing.log" \
  "$BENCH" --bench netlist.json --degree 1024 --bench-encrypted --sing --vectors 2 \
  --bk-noise 32 --paths covering-b1
run "C37 SING N=1024 covering-b1 sigma=24" "c37-sing.log" \
  "$BENCH" --bench netlist.json --degree 1024 --bench-encrypted --sing --vectors 2 \
  --bk-noise-sigma 24 --paths covering-b1
run "C41 SING N=512 covering-b1 sigma=128" "c41-sing.log" \
  "$BENCH" --bench netlist.json --degree 512 --bench-encrypted --sing --vectors 2 \
  --bk-noise-sigma 128 --paths covering-b1
run "C56 SING N=1024 publicMS B=1 k=7" "c56-sing.log" \
  "$BENCH" --bench netlist.json --degree 1024 --bench-encrypted --sing --vectors 2 \
  --bk-noise 1 --boolean-scale-mul 7 --paths 'blind-rotate-metal public-ms crypto'

note ""
note "finished: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
note "PASS rows: $(grep -c '^PASS' "$SUMMARY")"
note "FAIL rows: $(grep -c '^FAIL' "$SUMMARY")"
note ""
note "A nonzero exit is not automatically a broken claim -- some rows are graded"
note "negatives and some flags may have moved. Read the log before concluding."
