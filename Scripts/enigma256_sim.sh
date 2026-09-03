#!/usr/bin/env bash
# Generate (or reuse) golden vectors and co-sim enigma_256_core against them.
# Usage: ./Scripts/enigma256_sim.sh [golden_dir] [profile_json]
#        E256_REUSE_BUNDLE=1 ./Scripts/enigma256_sim.sh <validated_dir>
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
iverilog -g2012 -I "$OUT" -I "$ROOT" -o /tmp/enigma256.vvp \
  "$ROOT/Hardware/RTL/Enigma256/enigma_256_core.v" \
  "$ROOT/Hardware/Testbenches/Enigma256/enigma_256_tb.v"
vvp /tmp/enigma256.vvp +HEXDIR="$OUT"
iverilog -g2012 -I "$OUT" -I "$ROOT" -o /tmp/enigma256_center.vvp \
  "$ROOT/Hardware/RTL/Enigma256/enigma_256_core.v" \
  "$ROOT/Hardware/Testbenches/Enigma256/enigma_256_center_tb.v"
vvp /tmp/enigma256_center.vvp
