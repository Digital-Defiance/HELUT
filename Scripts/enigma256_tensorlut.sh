#!/usr/bin/env bash
# Yosys LUT6 synth → TensorLUT baseline emit + NLFF cold-start smoke.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

./Scripts/enigma256_tensorlut_synth.sh

# Emit sequential cone baseline (emit-only — DFF tick model not used for smoke).
swift run -c release helut --enigma256-tensorlut \
  --enigma256-tensorlut-emit-only \
  --enigma256-netlist build/enigma_256_step_cone_netlist.json \
  --enigma256-emit-out enigma_256_step_cone_tensorlut.v

# Attack surface: combinational NLFF (4 LUT6).
swift run -c release helut --enigma256-tensorlut \
  --enigma256-netlist build/enigma_256_nlff_combo_netlist.json \
  --enigma256-emit-out enigma_256_tensorlut_baseline.v \
  --enigma256-tensorlut-log logs/tensorlut-enigma256-nlff.log \
  "$@"
