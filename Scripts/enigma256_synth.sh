#!/usr/bin/env bash
# Synthesize enigma_256_core.v → Yosys JSON for FPGA bring-up (BRAMs kept).
# Does NOT flatten tables into soft flops (that path is ~20k DFFs — TensorLUT poison).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/build/enigma_256_netlist.json}"
mkdir -p "$(dirname "$OUT")"
cd "$ROOT"

yosys -Q -p "
  read_verilog -sv enigma_256_core.v
  hierarchy -check -top enigma_256_core
  proc; opt
  memory -nomap
  opt_clean
  write_json $OUT
  stat
"

echo "Wrote $OUT (memories kept as \$mem — FPGA / Blue Team path)"
