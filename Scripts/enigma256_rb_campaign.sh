#!/usr/bin/env bash
# Enigma 256 Red/Blue campaign on Apple Silicon SoftBus (no FPGA board).
#
# Default gates (fail-closed): SoftBus `ent` + structured KPA (incl. day-only joint).
# Optional TensorLUT runs record bounded evidence; profile changes require offline promotion.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mkdir -p logs Fixtures build
TENSOR_BUILD="build/hardware/Enigma256"
mkdir -p "$TENSOR_BUILD"

read -r PROFILE_SUITE PROFILE_GENERATION PROFILE_SCHEMA PROFILE_HASH < <(
  python3 -c 'import json; d=json.load(open("Fixtures/enigma256_generation.json")); print(d["suite_version"], d["generation"], d["fixture_schema_version"], d["profile_sha256"])'
)
PROFILE_COMPATIBILITY_KEY="E256/v${PROFILE_SUITE}/gen${PROFILE_GENERATION}/${PROFILE_HASH}/fixture-v${PROFILE_SCHEMA}"
PROFILE_TAG="v${PROFILE_SUITE}-gen${PROFILE_GENERATION}-fixture${PROFILE_SCHEMA}-${PROFILE_HASH:0:12}"

RUN_TENSOR=0
HARD_RED=0
WIDE_RED=0
WIDE_OFFSET_RED=0
WIDE_LFSR_RED=0
RUN_GATES=1
TENSOR_RC=0
TENSOR_LOG_ARGS=()
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --tensorlut) RUN_TENSOR=1 ;;
    --hard-red) HARD_RED=1; RUN_TENSOR=1 ;;
    --wide) WIDE_RED=1; HARD_RED=1; RUN_TENSOR=1 ;;
    --wide-offset) WIDE_OFFSET_RED=1; HARD_RED=1; RUN_TENSOR=1 ;;
    --wide-lfsr) WIDE_LFSR_RED=1; HARD_RED=1; RUN_TENSOR=1 ;;
    --no-gates) RUN_GATES=0 ;;
    --mutate|--force-mutate)
      printf '%s\n' \
        "Runtime mutation is disabled for the immutable E256-v2 profile." \
        "Run Scripts/e256_nlff_v2_search.py offline, independently validate its holdout receipt," \
        "then promote only an accepted receipt with Scripts/e256_nlff_emit.py." >&2
      exit 2
      ;;
    *) ARGS+=("$arg") ;;
  esac
done

HELUT_BIN="${HELUT_BIN:-.build/release/helut}"
if [[ ! -x "$HELUT_BIN" ]]; then
  swift build -c release --product helut
fi

echo "=== E256 profile: ${PROFILE_COMPATIBILITY_KEY} ==="

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
    EMIT="${TENSOR_BUILD}/enigma_256_tensorlut_baseline-${PROFILE_TAG}.v"
    LOG="logs/tensorlut-enigma256-nlff-${PROFILE_TAG}.log"
    if [[ "$WIDE_RED" -eq 1 ]]; then
      # Past-NLFF: scramble fragment + NLFF + offset next (+ lfsr_next_hi)
      NETLIST=build/enigma_256_scramble_frag_combo_netlist.json
      EMIT="${TENSOR_BUILD}/enigma_256_scramble_frag_tensorlut-${PROFILE_TAG}.v"
      LOG="logs/tensorlut-wide-scramble-frag-${PROFILE_TAG}-hard.log"
    elif [[ "$WIDE_OFFSET_RED" -eq 1 ]]; then
      NETLIST=build/enigma_256_nlff_offset_combo_netlist.json
      EMIT="${TENSOR_BUILD}/enigma_256_nlff_offset_tensorlut-${PROFILE_TAG}.v"
      LOG="logs/tensorlut-wide-offset-${PROFILE_TAG}-hard.log"
    elif [[ "$WIDE_LFSR_RED" -eq 1 ]]; then
      NETLIST=build/enigma_256_nlff_lfsr_combo_netlist.json
      EMIT="${TENSOR_BUILD}/enigma_256_nlff_lfsr_tensorlut-${PROFILE_TAG}.v"
      LOG="logs/tensorlut-wide-${PROFILE_TAG}-hard.log"
    fi
    echo "=== Red: TensorLUT hard (${PROFILE_COMPATIBILITY_KEY}; ${NETLIST}) ==="
    TENSOR_LOG_ARGS=(--enigma256-tensorlut-log "$LOG")
    set +e
    "$HELUT_BIN" --enigma256-tensorlut \
      --enigma256-netlist "$NETLIST" \
      --enigma256-emit-out "$EMIT" \
      --enigma256-tensorlut-gens 240 \
      --enigma256-tensorlut-pop 64 \
      --enigma256-tensorlut-polish 160 \
      --enigma256-tensorlut-log "$LOG" \
      --enigma256-tensorlut-expect-hold
    TENSOR_RC=$?
    set -e
    if [[ "$TENSOR_RC" -ne 0 ]]; then
      echo "TensorLUT returned ${TENSOR_RC}; recording its report before returning that status." >&2
    fi
  else
    # This helper writes the campaign's default untagged TensorLUT log.
    ./Scripts/enigma256_tensorlut.sh
  fi
fi

echo "=== Campaign ledger / SoftBus stochastic KPA (${PROFILE_COMPATIBILITY_KEY}) ==="
set +e
"$HELUT_BIN" --enigma256-campaign "${TENSOR_LOG_ARGS[@]}" "${ARGS[@]}"
CAMPAIGN_RC=$?
set -e
if [[ "$TENSOR_RC" -ne 0 ]]; then
  if [[ "$CAMPAIGN_RC" -ne 0 ]]; then
    echo "Campaign also returned ${CAMPAIGN_RC}; preserving TensorLUT status ${TENSOR_RC}." >&2
  fi
  exit "$TENSOR_RC"
fi
exit "$CAMPAIGN_RC"
