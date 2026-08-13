#!/usr/bin/env bash
# Encrypted HELUT "sing" — multi-netlist CPU lock-down + optional Metal on full_adder.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p logs
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
LOG="logs/helut-encrypted-sing-${STAMP}.log"
BIN=".build/release/helut"

swift build -c release --product helut

{
  echo "=== HELUT encrypted SING lock-down ${STAMP} ==="
  echo ""

  echo "######## Hardness + estimator export ########"
  "$BIN" --hardness-table
  echo ""
  "$BIN" --estimator-export > "logs/helut-estimator-pending-${STAMP}.json"
  python3 Scripts/helut_lattice_estimate.py \
    --pending "logs/helut-estimator-pending-${STAMP}.json" \
    --out "logs/helut-estimator-results-${STAMP}.json" \
    || true
  echo ""

  echo "######## full_adder N=8 Metal SING ########"
  "$BIN" --bench netlist.json --degree 8 --bench-encrypted --sing --vectors 8
  echo ""

  echo "######## full_adder N=16 CPU-only ########"
  "$BIN" --bench netlist.json --degree 16 --bench-encrypted --sing --cpu-only --vectors 8
  echo ""

  echo "######## full_adder N=32 CPU-only ########"
  "$BIN" --bench netlist.json --degree 32 --bench-encrypted --sing --cpu-only --vectors 8
  echo ""

  echo "######## tree_netlist N=8 CPU-only (256 exhaustive) ########"
  "$BIN" --bench tree_netlist.json --degree 8 --bench-encrypted --sing --cpu-only --vectors 256
  echo ""

  echo "######## regex_netlist N=8 CPU-only (32 samples) ########"
  "$BIN" --bench regex_netlist.json --degree 8 --bench-encrypted --sing --cpu-only --vectors 32
  echo ""

  echo "######## Unit gates ########"
  swift test --filter 'testNoisyBKDepthCertificate|testLWEHardnessCalibrationTable|testLWEEstimatorProtocolPending|testLWEHardnessCertificate128|testEncryptedTreeNetlistCPU' 2>&1 | tail -50
  echo ""

  echo "=== DONE ${STAMP} ==="
} 2>&1 | tee "$LOG"

echo "Wrote $LOG"
