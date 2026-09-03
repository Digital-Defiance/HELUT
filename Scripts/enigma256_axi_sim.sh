#!/usr/bin/env bash
# AXI-lite + AXIS table-burst golden co-sim for enigma_256_axi.
# Usage: ./Scripts/enigma256_axi_sim.sh [golden_dir] [profile_json]
#        LITE=1 ./Scripts/enigma256_axi_sim.sh   # legacy WR_* path
#        E256_REUSE_BUNDLE=1 ./Scripts/enigma256_axi_sim.sh <validated_dir>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT="${1:-Fixtures/enigma256_golden}"
PROFILE="${2:-${E256_PROFILE_PATH:-Fixtures/enigma256_generation.json}}"
if [[ "${E256_REUSE_BUNDLE:-0}" != "1" ]]; then
  swift run helut --enigma256-golden --enigma256-genes "$PROFILE" --enigma256-out "$OUT"
elif [[ ! -f "$OUT/manifest.json" ]]; then
  printf 'validated E256 bundle is missing manifest: %s\n' "$OUT" >&2
  exit 2
fi
iverilog -g2012 -I "$OUT" -I "$ROOT" -o /tmp/enigma256_axi.vvp \
  "$ROOT/Hardware/RTL/Enigma256/enigma_256_core.v" \
  "$ROOT/Hardware/RTL/Enigma256/enigma_256_axis_tables.v" \
  "$ROOT/Hardware/RTL/Enigma256/enigma_256_axi.v" \
  "$ROOT/Hardware/Testbenches/Enigma256/enigma_256_axi_tb.v"
VVP_ARGS=(+HEXDIR="$OUT")
if [[ -n "${NBYTES:-}" ]]; then
  VVP_ARGS+=(+NBYTES="$NBYTES")
fi
# Some simulator/tool wrappers surface `$finish` before draining the final
# transcript when errexit is active. Capture vvp explicitly so PASS/FAIL and
# its real status are both preserved; never mask a nonzero simulator result.
set +e
if [[ "${LITE:-0}" == "1" ]]; then
  vvp /tmp/enigma256_axi.vvp +LITE "${VVP_ARGS[@]}"
else
  vvp /tmp/enigma256_axi.vvp "${VVP_ARGS[@]}"
fi
VVP_STATUS=$?
set -e
if [[ "$VVP_STATUS" -ne 0 ]]; then
  printf 'enigma256 AXI simulation failed (vvp status %d)\n' "$VVP_STATUS" >&2
  exit "$VVP_STATUS"
fi
