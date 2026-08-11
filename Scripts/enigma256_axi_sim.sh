#!/usr/bin/env bash
# AXI-lite golden co-sim for enigma_256_axi.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT="${1:-Fixtures/enigma256_golden}"
swift run helut --enigma256-golden --enigma256-out "$OUT"
iverilog -g2012 -o /tmp/enigma256_axi.vvp enigma_256_core.v enigma_256_axi.v enigma_256_axi_tb.v
vvp /tmp/enigma256_axi.vvp
