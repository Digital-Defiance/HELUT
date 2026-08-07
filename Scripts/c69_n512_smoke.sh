#!/usr/bin/env bash
# Preserve the recovered C69 covering-KS n=512 result end to end.
#
# This is deliberately separate from the fast small-N determinism tests. Those
# guard the Dictionary-order RNG root cause; this smoke also exercises the exact
# N=1024 / n=512 covering-b2, noisy-BK, extract-to-KS, public-refresh, and adder
# path whose historical failure was withdrawn after that bug was fixed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -n "${SWIFT_DETERMINISTIC_HASHING+x}" ]]; then
  printf '%s\n' \
    'refusing to run: SWIFT_DETERMINISTIC_HASHING is set.' \
    'C69 must pass with Swift per-process hash randomisation active.' >&2
  exit 2
fi

HELUT_BIN="${HELUT_BIN:-.build/release/helut}"
if [[ ! -x "$HELUT_BIN" ]]; then
  swift build -c release --product helut
fi

TRANSCRIPT="$(mktemp "${TMPDIR:-/tmp}/helut-c69-n512.XXXXXX")"
trap 'rm -f "$TRANSCRIPT"' EXIT

set +e
env -u SWIFT_DETERMINISTIC_HASHING "$HELUT_BIN" \
  --bench netlist.json \
  --degree 1024 \
  --bench-encrypted \
  --cpu-only \
  --sing \
  --vectors 1 \
  --paths "public-ms covering-b2" \
  --bk-noise-sigma 128 \
  --bk-identity-trials 1 \
  --unsafe-noisy-bk-diagnostic \
  --lwe-dimension 512 \
  2>&1 | tee "$TRANSCRIPT"
HELUT_STATUS=${PIPESTATUS[0]}
set -e

if [[ "$HELUT_STATUS" -ne 0 ]]; then
  printf 'C69 n=512 smoke failed (helut status %d)\n' "$HELUT_STATUS" >&2
  exit "$HELUT_STATUS"
fi

required_markers=(
  'poly N=1024  LUTs='
  'paths filter: public-ms covering-b2'
  'BK noise inject Gaussian σ=128.0 (torus; identity residual is empirical, not B_bk)'
  'BK identity confidence trials=1'
  'noisy-BK policy: UNSAFE DIAGNOSTIC ONLY (functional output cannot certify ε)'
  'LWE n=512  (CMUX count; extract→KS when n<kN=1024)'
  'starting blind-rotate public-ms covering-b2  n=512'
  'identity residual trials=1  (n=512)'
  'ENCRYPTED EQUIV (blind-rotate public-ms covering-b2)'
  'functional result PASS'
  'result          DIAGNOSTIC ONLY — NO NOISY-BK CONFIDENCE CERTIFICATE'
)
for marker in "${required_markers[@]}"; do
  if ! grep -Fq "$marker" "$TRANSCRIPT"; then
    printf 'C69 n=512 smoke was vacuous: missing marker: %s\n' "$marker" >&2
    exit 2
  fi
done

START_COUNT="$(grep -Fc '  starting blind-rotate public-ms covering-b2  n=512' "$TRANSCRIPT" || true)"
EQUIV_COUNT="$(grep -Fc 'ENCRYPTED EQUIV (blind-rotate public-ms covering-b2)' "$TRANSCRIPT" || true)"
FUNCTIONAL_COUNT="$(grep -c '^  functional result PASS$' "$TRANSCRIPT" || true)"
DIAGNOSTIC_COUNT="$(grep -c '^  result          DIAGNOSTIC ONLY — NO NOISY-BK CONFIDENCE CERTIFICATE$' "$TRANSCRIPT" || true)"
if [[ "$START_COUNT" -ne 1 || "$EQUIV_COUNT" -ne 1 || "$FUNCTIONAL_COUNT" -ne 1 || "$DIAGNOSTIC_COUNT" -ne 1 ]]; then
  printf 'C69 n=512 smoke expected exactly one path/functional diagnostic receipt; found starts=%s equiv=%s functional=%s diagnostic=%s\n' \
    "$START_COUNT" "$EQUIV_COUNT" "$FUNCTIONAL_COUNT" "$DIAGNOSTIC_COUNT" >&2
  exit 2
fi
if grep -Eq '^  result[[:space:]]+PASS$' "$TRANSCRIPT"; then
  printf '%s\n' 'C69 n=512 smoke incorrectly emitted a scientific PASS without a noisy-BK confidence certificate' >&2
  exit 2
fi
if grep -Eq '^(  functional )?result[[:space:]]+FAIL' "$TRANSCRIPT"; then
  printf '%s\n' 'C69 n=512 smoke transcript contains a FAIL result' >&2
  exit 1
fi

printf '%s\n' 'PASS: C69 covering-b2 N=1024 / n=512 functional SING equivalence remains (diagnostic-only; no noisy-BK confidence certificate)'
