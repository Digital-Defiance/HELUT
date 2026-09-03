#!/usr/bin/env bash
# E256-v3/gen0 zero-state/NLFF and fixture-v5 direct-core parity.
# Usage: ./Scripts/enigma256_v3_sim.sh [fixture_v5_dir]
# This runner is read-only: it consumes a staged fixture and writes only
# temporary simulator binaries.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FIXTURE="${1:-Fixtures/Staging/Enigma256/E256-v3-gen0-0206c00e5084ebafe1f841708d2af3f4a029bcf160f7b22ed63bb5078d376e16-fixture-v5}"
if [[ ! -f "$FIXTURE/fixture-v5.json" ]]; then
  printf 'validated E256-v3 fixture-v5 bundle is missing manifest: %s\n' "$FIXTURE" >&2
  exit 2
fi

# Bind path-based RTL inputs to the same strict manifest/artifact semantics used
# by the portable verifier before the simulator can consume a single byte.
CARGO_TARGET_DIR="$ROOT/build/rust-reference" \
RUSTUP_TOOLCHAIN="${RUSTUP_TOOLCHAIN:-1.97.1}" \
  cargo run --locked --manifest-path "$ROOT/Reference/Rust/Cargo.toml" -- \
  e256-v3-kat --bundle "$FIXTURE"

ZERO_VVP="$(mktemp "${TMPDIR:-/tmp}/enigma256-v3-zero.XXXXXX")"
FIXTURE_VVP="$(mktemp "${TMPDIR:-/tmp}/enigma256-v3-fixture.XXXXXX")"
trap 'rm -f "$ZERO_VVP" "$FIXTURE_VVP"' EXIT

iverilog -g2012 -I "$ROOT" -s enigma_256_v3_tb -o "$ZERO_VVP" \
  "$ROOT/Hardware/RTL/Enigma256/enigma_256_core.v" \
  "$ROOT/Hardware/RTL/Enigma256/enigma_256_core_v3.v" \
  "$ROOT/Hardware/RTL/Enigma256/enigma_256_nlff_combo.v" \
  "$ROOT/Hardware/RTL/Enigma256/enigma_256_nlff_v3_combo.v" \
  "$ROOT/Hardware/Testbenches/Enigma256/enigma_256_v3_tb.v"
vvp "$ZERO_VVP"

iverilog -g2012 -I "$ROOT" -s enigma_256_v3_fixture_tb \
  -P "enigma_256_v3_fixture_tb.FIXTURE=\"$FIXTURE\"" \
  -o "$FIXTURE_VVP" \
  "$ROOT/Hardware/RTL/Enigma256/enigma_256_core.v" \
  "$ROOT/Hardware/RTL/Enigma256/enigma_256_core_v3.v" \
  "$ROOT/Hardware/Testbenches/Enigma256/enigma_256_v3_fixture_tb.v"
vvp "$FIXTURE_VVP"
