#!/usr/bin/env bash
# Yosys LUT6 synth → scratch TensorLUT emit + NLFF cold-start (gentle polish).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TENSOR_BUILD="build/hardware/Enigma256"
mkdir -p "$TENSOR_BUILD" logs

read -r PROFILE_SUITE PROFILE_GENERATION PROFILE_SCHEMA PROFILE_HASH < <(
  python3 -c 'import json; d=json.load(open("Fixtures/enigma256_generation.json")); print(d["suite_version"], d["generation"], d["fixture_schema_version"], d["profile_sha256"])'
)
PROFILE_TAG="v${PROFILE_SUITE}-gen${PROFILE_GENERATION}-fixture${PROFILE_SCHEMA}-${PROFILE_HASH:0:12}"

./Scripts/enigma256_tensorlut_synth.sh

swift run -c release helut --enigma256-tensorlut \
  --enigma256-tensorlut-emit-only \
  --enigma256-netlist build/enigma_256_step_cone_netlist.json \
  --enigma256-emit-out "$TENSOR_BUILD/enigma_256_step_cone_tensorlut.v"

set +e
swift run -c release helut --enigma256-tensorlut \
  --enigma256-netlist build/enigma_256_nlff_combo_netlist.json \
  --enigma256-emit-out "$TENSOR_BUILD/enigma_256_tensorlut_baseline.v" \
  --enigma256-tensorlut-log "logs/tensorlut-enigma256-nlff-${PROFILE_TAG}.log" \
  --enigma256-tensorlut-gens 80 \
  --enigma256-tensorlut-pop 32 \
  --enigma256-tensorlut-polish 48 \
  "$@"
TENSOR_RC=$?
set -e
exit "$TENSOR_RC"
