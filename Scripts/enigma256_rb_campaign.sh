#!/usr/bin/env bash
# Enigma 256 Red/Blue campaign on Apple Silicon SoftBus (no FPGA board).
#
# Default gates (fail-closed): SoftBus `ent` + structured KPA (incl. day-only joint).
# Optional: TensorLUT score (--tensorlut / --hard-red), Blue mutate under pressure.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mkdir -p logs Fixtures build

RUN_TENSOR=0
HARD_RED=0
WIDE_RED=0
WIDE_OFFSET_RED=0
WIDE_LFSR_RED=0
RUN_GATES=1
ARGS=(--enigma256-campaign)
for arg in "$@"; do
  case "$arg" in
    --tensorlut) RUN_TENSOR=1 ;;
    --hard-red) HARD_RED=1; RUN_TENSOR=1 ;;
    --wide) WIDE_RED=1; HARD_RED=1; RUN_TENSOR=1 ;;
    --wide-offset) WIDE_OFFSET_RED=1; HARD_RED=1; RUN_TENSOR=1 ;;
    --wide-lfsr) WIDE_LFSR_RED=1; HARD_RED=1; RUN_TENSOR=1 ;;
    --no-gates) RUN_GATES=0 ;;
    --mutate) ARGS+=(--enigma256-campaign-mutate) ;;
    --force-mutate) ARGS+=(--enigma256-campaign-force-mutate) ;;
    *) ARGS+=("$arg") ;;
  esac
done

HELUT_BIN="${HELUT_BIN:-.build/release/helut}"
if [[ ! -x "$HELUT_BIN" ]]; then
  swift build -c release --product helut
fi

if [[ "$RUN_GATES" -eq 1 ]]; then
  echo "=== GATE: SoftBus ent (PRNG plaintext, fail-closed) ==="
  ENT_BYTES="${ENT_BYTES:-1048576}" ./Scripts/enigma256_ent.sh

  echo "=== GATE: scramble bijection / reciprocity (fail-closed) ==="
  ./Scripts/enigma256_bijection.sh

  echo "=== GATE: structured SoftBus KPA (partial-leak + day-only joint) ==="
  "$HELUT_BIN" --enigma256-structured-kpa \
    --enigma256-kpa-rounds "${KPA_ROUNDS:-16384}"
fi

if [[ "$RUN_TENSOR" -eq 1 ]]; then
  ./Scripts/enigma256_tensorlut_synth.sh
  if [[ "$HARD_RED" -eq 1 ]]; then
    NETLIST=build/enigma_256_nlff_combo_netlist.json
    EMIT=enigma_256_tensorlut_baseline.v
    LOG=logs/tensorlut-enigma256-nlff.log
    if [[ "$WIDE_RED" -eq 1 ]]; then
      # Past-NLFF: scramble fragment + NLFF + offset next (+ lfsr_next_hi)
      NETLIST=build/enigma_256_scramble_frag_combo_netlist.json
      EMIT=build/enigma_256_scramble_frag_tensorlut.v
      LOG=logs/tensorlut-wide-scramble-frag-g5-hard.log
    elif [[ "$WIDE_OFFSET_RED" -eq 1 ]]; then
      NETLIST=build/enigma_256_nlff_offset_combo_netlist.json
      EMIT=build/enigma_256_nlff_offset_tensorlut.v
      LOG=logs/tensorlut-wide-offset-g5-hard.log
    elif [[ "$WIDE_LFSR_RED" -eq 1 ]]; then
      NETLIST=build/enigma_256_nlff_lfsr_combo_netlist.json
      EMIT=build/enigma_256_nlff_lfsr_tensorlut.v
      LOG=logs/tensorlut-wide-g5-hard.log
    fi
    echo "=== Red: TensorLUT hard (${NETLIST}) ==="
    "$HELUT_BIN" --enigma256-tensorlut \
      --enigma256-netlist "$NETLIST" \
      --enigma256-emit-out "$EMIT" \
      --enigma256-tensorlut-gens 240 \
      --enigma256-tensorlut-pop 64 \
      --enigma256-tensorlut-polish 160 \
      --enigma256-tensorlut-log "$LOG" \
      --enigma256-tensorlut-expect-hold
  else
    ./Scripts/enigma256_tensorlut.sh
  fi
fi

echo "=== Campaign ledger / SoftBus stochastic KPA ==="
"$HELUT_BIN" "${ARGS[@]}"
