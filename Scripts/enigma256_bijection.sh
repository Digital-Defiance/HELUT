#!/usr/bin/env bash
# Blue gate: scramble must stay a bijection (no many:1 / 1:many) and reciprocal
# under random Walzenlage + Grundstellung on one day key. Also stream round-trip.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

STATES="${BIJECTION_STATES:-1000000}"
STREAM="${BIJECTION_STREAM:-64}"
SEED="${BIJECTION_SEED:-}"
HELUT_BIN="${HELUT_BIN:-.build/release/helut}"

mkdir -p logs

if [[ ! -x "$HELUT_BIN" ]]; then
  swift build -c release --product helut
fi

ARGS=(
  --enigma256-bijection
  --enigma256-bijection-states "$STATES"
  --enigma256-bijection-stream "$STREAM"
)
if [[ -n "$SEED" ]]; then
  ARGS+=(--enigma256-bijection-seed "$SEED")
fi

"$HELUT_BIN" "${ARGS[@]}"
