#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp "${TMPDIR:-/tmp}/enigma256-lfsr.XXXXXX")"
trap 'rm -f "$OUT"' EXIT

iverilog -g2012 -I "$ROOT" -s enigma_256_lfsr_tb -o "$OUT" \
  "$ROOT/Hardware/RTL/Enigma256/enigma_256_step_cone.v" \
  "$ROOT/Hardware/Testbenches/Enigma256/enigma_256_lfsr_tb.v"
vvp "$OUT"
