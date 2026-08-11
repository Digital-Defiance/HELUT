#!/usr/bin/env bash
# Enigma 256 Red/Blue campaign on Apple Silicon SoftBus (no FPGA board).
# Optional: refresh TensorLUT NLFF score, then SoftBus KPA + Blue mutate under pressure.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mkdir -p logs Fixtures

RUN_TENSOR=0
HARD_RED=0
ARGS=(--enigma256-campaign)
for arg in "$@"; do
  case "$arg" in
    --tensorlut) RUN_TENSOR=1 ;;
    --hard-red) HARD_RED=1; RUN_TENSOR=1 ;;
    --mutate) ARGS+=(--enigma256-campaign-mutate) ;;
    --force-mutate) ARGS+=(--enigma256-campaign-force-mutate) ;;
    *) ARGS+=("$arg") ;;
  esac
done

if [[ "$RUN_TENSOR" -eq 1 ]]; then
  if [[ "$HARD_RED" -eq 1 ]]; then
    # Stronger Red: more explore/polish against the live NLFF cone.
    ./Scripts/enigma256_tensorlut_synth.sh
    swift run -c release helut --enigma256-tensorlut \
      --enigma256-tensorlut-gens 240 \
      --enigma256-tensorlut-pop 64 \
      --enigma256-tensorlut-polish 160 \
      --enigma256-tensorlut-log logs/tensorlut-enigma256-nlff.log
  else
    ./Scripts/enigma256_tensorlut.sh
  fi
fi

swift run -c release helut "${ARGS[@]}"
