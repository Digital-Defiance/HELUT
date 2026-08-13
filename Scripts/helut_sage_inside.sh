#!/usr/bin/env bash
# Run inside sagemath/sagemath container. Host mounts:
#   /est  = malb/lattice-estimator checkout
#   /work = HELUT repo
set -euo pipefail
sage --pip install /est
sage -python /work/Scripts/helut_lattice_estimate.py \
  --pending /work/logs/helut-estimator-pending.json \
  --out /work/logs/helut-estimator-results.json \
  "$@"
