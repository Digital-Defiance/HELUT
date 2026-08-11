#!/usr/bin/env bash
# Enigma 256 Red/Blue campaign on Apple Silicon SoftBus (no FPGA board).
# Optional: refresh TensorLUT NLFF score, then SoftBus KPA + Blue mutate under pressure.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mkdir -p logs Fixtures

RUN_TENSOR=0
ARGS=(--enigma256-campaign)
for arg in "$@"; do
  case "$arg" in
    --tensorlut) RUN_TENSOR=1 ;;
    --mutate) ARGS+=(--enigma256-campaign-mutate) ;;
    --force-mutate) ARGS+=(--enigma256-campaign-force-mutate) ;;
    *) ARGS+=("$arg") ;;
  esac
done

if [[ "$RUN_TENSOR" -eq 1 ]]; then
  ./Scripts/enigma256_tensorlut.sh
fi

swift run -c release helut "${ARGS[@]}"
