#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp "${TMPDIR:-/tmp}/enigma256-nlff.XXXXXX")"
trap 'rm -f "$OUT"' EXIT

iverilog -g2012 -I "$ROOT" -s enigma_256_nlff_tb -o "$OUT" \
  "$ROOT/Hardware/RTL/Enigma256/enigma_256_nlff_combo.v" \
  "$ROOT/Hardware/Testbenches/Enigma256/enigma_256_nlff_tb.v"
vvp "$OUT"
