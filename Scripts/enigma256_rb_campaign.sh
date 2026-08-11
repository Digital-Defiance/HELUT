#!/usr/bin/env bash
# Enigma 256 Red/Blue campaign on Apple Silicon SoftBus (no FPGA board).
# Optional: refresh TensorLUT NLFF score, then SoftBus KPA + Blue mutate under pressure.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mkdir -p logs Fixtures

RUN_TENSOR=0
MUTATE=()
EXTRA=()
for arg in "$@"; do
  case "$arg" in
    --tensorlut) RUN_TENSOR=1 ;;
    --mutate) MUTATE+=(--enigma256-campaign-mutate) ;;
    --force-mutate) MUTATE+=(--enigma256-campaign-force-mutate) ;;
    *) EXTRA+=("$arg") ;;
  esac
done

if [[ "$RUN_TENSOR" -eq 1 ]]; then
  ./Scripts/enigma256_tensorlut.sh
fi

swift run -c release helut --enigma256-campaign \
  "${MUTATE[@]}" \
  "${EXTRA[@]}"
