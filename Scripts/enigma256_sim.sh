#!/usr/bin/env bash
# Generate (or reuse) golden vectors and co-sim enigma_256_core against them.
# Usage: ./Scripts/enigma256_sim.sh [golden_dir] [profile_json]
#        E256_REUSE_BUNDLE=1 ./Scripts/enigma256_sim.sh <validated_dir>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# The loaded golden is the 16-bit profile. This sim is the byte-walk receipt.
HIST="Fixtures/Historical/Enigma256/E256-v2-gen0-fa246e9cba9009a4799e5a81722a9b14e9a67293d9621b45985c5f3e620865d4-fixture-v4"
OUT="${1:-$HIST/enigma256_golden}"
PROFILE="${2:-${E256_PROFILE_PATH:-$HIST/enigma256_generation.json}}"
CORE="$ROOT/$HIST/enigma_256_core.v"
if [[ "${E256_REUSE_BUNDLE:-0}" != "1" ]]; then
  swift run helut --enigma256-golden --enigma256-genes "$PROFILE" --enigma256-out "$OUT"
elif [[ ! -f "$OUT/manifest.json" ]]; then
  printf 'validated E256 bundle is missing manifest: %s\n' "$OUT" >&2
  exit 2
fi
iverilog -g2012 -I "$OUT" -I "$ROOT" -o /tmp/enigma256.vvp \
  "$CORE" \
  "$ROOT/Hardware/Testbenches/Enigma256/enigma_256_tb.v"
vvp /tmp/enigma256.vvp +HEXDIR="$OUT"
iverilog -g2012 -I "$OUT" -I "$ROOT" -o /tmp/enigma256_center.vvp \
  "$CORE" \
  "$ROOT/Hardware/Testbenches/Enigma256/enigma_256_center_tb.v"
vvp /tmp/enigma256_center.vvp
