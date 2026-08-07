#!/usr/bin/env bash
# Boolean-path HELUT re-bench (trivial torus / multilinear LUT).
# Suspends nothing; assumes catalog hunt is already parked.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p logs
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
LOG="logs/helut-boolean-bench-${STAMP}.log"

echo "Building release helut…"
swift build -c release --product helut

BIN=".build/release/helut"
{
  echo "=== HELUT boolean-path bench ${STAMP} ==="
  echo ""

  echo "######## PicoRV32 compile+boot (N=1024 B=1, 10 ticks) ########"
  "$BIN" --bench picorv32_netlist.json --batch 1 --degree 1024 --ticks 10 --warmup 1 --reset-hold 3
  echo ""

  echo "######## Enigma M3 compile+boot (N=1024 B=1, 10 ticks) ########"
  "$BIN" --bench enigma_netlist.json --batch 1 --degree 1024 --ticks 10 --warmup 1 --reset-hold 0
  echo ""

  echo "######## Enigma M3 Metal≡cleartext (N=1024) ########"
  "$BIN" --bench enigma_netlist.json --batch 1 --degree 1024 --ticks 0 --bench-equiv
  echo ""

  echo "######## Enigma M4 compile-only (N=1024 B=1) ########"
  "$BIN" --bench enigma_m4_netlist.json --batch 1 --degree 1024 --compile-only
  echo ""

  echo "=== DONE ${STAMP} ==="
} 2>&1 | tee "$LOG"

echo "Wrote $LOG"
