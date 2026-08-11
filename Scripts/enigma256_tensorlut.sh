#!/usr/bin/env bash
# Yosys LUT6 synth → TensorLUT baseline emit + NLFF cold-start (gentle polish).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

./Scripts/enigma256_tensorlut_synth.sh

swift run -c release helut --enigma256-tensorlut \
  --enigma256-tensorlut-emit-only \
  --enigma256-netlist build/enigma_256_step_cone_netlist.json \
  --enigma256-emit-out enigma_256_step_cone_tensorlut.v

swift run -c release helut --enigma256-tensorlut \
  --enigma256-netlist build/enigma_256_nlff_combo_netlist.json \
  --enigma256-emit-out enigma_256_tensorlut_baseline.v \
  --enigma256-tensorlut-log logs/tensorlut-enigma256-nlff.log \
  --enigma256-tensorlut-gens 80 \
  --enigma256-tensorlut-pop 32 \
  --enigma256-tensorlut-polish 48 \
  "$@"
