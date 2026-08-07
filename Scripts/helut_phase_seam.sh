#!/usr/bin/env bash
# Phase / GLWE-trivial encoding + trivial PBS seam for HELUT graduation.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p logs
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
LOG="logs/helut-phase-seam-${STAMP}.log"
BIN=".build/release/helut"

swift build -c release --product helut

{
  echo "=== HELUT phase/GLWE/PBS seam ${STAMP} ==="
  echo ""

  echo "######## Phase encoding equiv (N=1024, multilinear) ########"
  "$BIN" --bench enigma_netlist.json --degree 1024 --ticks 0 \
    --encoding phase --bench-equiv
  echo ""

  echo "######## GLWE-trivial encoding equiv (N=1024, multilinear) ########"
  "$BIN" --bench enigma_netlist.json --degree 1024 --ticks 0 \
    --encoding glwe-trivial --bench-equiv
  echo ""

  echo "######## Trivial PBS-GGSW full_adder (glwe-trivial, N=64) ########"
  "$BIN" --bench netlist.json --degree 64 --ticks 0 \
    --encoding glwe-trivial --lut-backend pbs-ggsw --bench-equiv
  echo ""

  echo "######## Trivial PBS full_adder (phase, N=64) ########"
  "$BIN" --bench netlist.json --degree 64 --ticks 0 \
    --encoding phase --lut-backend pbs --bench-equiv
  echo ""

  echo "######## Packed-GLWE PBS full_adder (glwe-packed, poly N=32 → wire 64) ########"
  "$BIN" --bench netlist.json --degree 32 --ticks 0 \
    --encoding glwe-packed --lut-backend pbs --bench-equiv
  echo ""

  echo "######## Encrypted netlist full_adder (GGSW PBS per \$lut, poly N=8) ########"
  "$BIN" --bench netlist.json --degree 8 --bench-encrypted
  echo ""

  echo "=== DONE ${STAMP} ==="
} 2>&1 | tee "$LOG"

echo "Wrote $LOG"
