#!/usr/bin/env bash
# Boolean-path HELUT: batch scaling + N=1 clear-shape vs N=1024 TFHE-shaped.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p logs
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
LOG="logs/helut-boolean-scale-${STAMP}.log"
BIN=".build/release/helut"

echo "Building release helut…"
swift build -c release --product helut

{
  echo "=== HELUT boolean scale ${STAMP} ==="
  echo ""

  echo "######## N=1024 vs N=1 (Enigma M3, B=1, 10 ticks) ########"
  for DEG in 1024 1; do
    echo "---- degree=$DEG ----"
    "$BIN" --bench enigma_netlist.json --batch 1 --degree "$DEG" --ticks 10 --warmup 1 --reset-hold 0
    echo ""
  done

  echo "######## Batch scaling Enigma M3 (N=1024) ########"
  for B in 1 10 100 1000; do
    echo "---- batch=$B ----"
    "$BIN" --bench enigma_netlist.json --batch "$B" --degree 1024 --ticks 8 --warmup 1 --reset-hold 0
    echo ""
  done

  echo "######## Batch scaling Enigma M3 (N=1 clear-shape) ########"
  for B in 1 10 100 1000; do
    echo "---- batch=$B degree=1 ----"
    "$BIN" --bench enigma_netlist.json --batch "$B" --degree 1 --ticks 8 --warmup 1 --reset-hold 0
    echo ""
  done

  echo "######## Clear-shape equiv (N=1) ########"
  "$BIN" --bench enigma_netlist.json --batch 1 --degree 1 --ticks 0 --bench-equiv
  echo ""

  echo "=== DONE ${STAMP} ==="
} 2>&1 | tee "$LOG"

echo "Wrote $LOG"
