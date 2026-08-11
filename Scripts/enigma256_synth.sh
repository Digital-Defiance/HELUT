#!/usr/bin/env bash
# Synthesize enigma_256_core.v → Yosys JSON (future TensorLUT melt input).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/build/enigma_256_netlist.json}"
mkdir -p "$(dirname "$OUT")"
cd "$ROOT"

yosys -Q -p "
  read_verilog -sv enigma_256_core.v
  hierarchy -check -top enigma_256_core
  proc; opt; memory; opt
  techmap; opt
  abc -g AND,NAND,OR,NOR,XOR,XNOR,MUX
  opt_clean
  write_json $OUT
  stat
"

echo "Wrote $OUT"
