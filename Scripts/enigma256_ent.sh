#!/usr/bin/env bash
# Blue gate: SoftBus ciphertext entropy via `ent` (John Walker).
# Samples counter plaintext (not zeros — un-reflector self-maps by design).
# Fails closed if entropy/correlation look dead. Needs a long sample (≥1MiB).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BYTES="${ENT_BYTES:-1048576}"
OUT="${ENT_OUT:-build/enigma256_keystream.bin}"
LOG="${ENT_LOG:-logs/enigma256-ent.log}"

mkdir -p "$(dirname "$OUT")" logs

if ! command -v ent >/dev/null 2>&1; then
  echo "ent not found (brew install ent)" >&2
  exit 2
fi

swift run -c release helut --enigma256-ent \
  --enigma256-ent-bytes "$BYTES" \
  --enigma256-ent-out "$OUT" \
  --enigma256-ent-log "$LOG" \
  --enigma256-ent-fail-closed
