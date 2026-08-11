#!/usr/bin/env bash
# AXI-lite + AXIS table-burst golden co-sim for enigma_256_axi.
# Usage: ./Scripts/enigma256_axi_sim.sh [golden_dir]
#        LITE=1 ./Scripts/enigma256_axi_sim.sh   # legacy WR_* path
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT="${1:-Fixtures/enigma256_golden}"
swift run helut --enigma256-golden --enigma256-out "$OUT"
iverilog -g2012 -o /tmp/enigma256_axi.vvp \
  enigma_256_core.v enigma_256_axis_tables.v enigma_256_axi.v enigma_256_axi_tb.v
if [[ "${LITE:-0}" == "1" ]]; then
  vvp /tmp/enigma256_axi.vvp +LITE
else
  vvp /tmp/enigma256_axi.vvp
fi
