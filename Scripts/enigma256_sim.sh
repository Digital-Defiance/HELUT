#!/usr/bin/env bash
# Generate golden vectors and co-sim enigma_256_core against them.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT="${1:-Fixtures/enigma256_golden}"
swift run helut --enigma256-golden --enigma256-out "$OUT"
iverilog -g2012 -o /tmp/enigma256.vvp enigma_256_core.v enigma_256_tb.v
vvp /tmp/enigma256.vvp
