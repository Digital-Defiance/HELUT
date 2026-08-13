#!/usr/bin/env bash
# Sage + lattice-estimator fill-in for H1.
# Prefer native SageMath. Do not qemu linux/amd64 on Apple silicon (FLINT SIGILL).
#   ./Scripts/helut_sage_estimate.sh
#   ./Scripts/helut_sage_estimate.sh --max-n 256
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs
EST="${LATTICE_ESTIMATOR_SRC:-/tmp/lattice-estimator}"
if [[ ! -d "$EST/.git" ]]; then
  git clone --depth 1 https://github.com/malb/lattice-estimator.git "$EST"
fi

find_sage() {
  if command -v sage >/dev/null 2>&1; then
    command -v sage
    return 0
  fi
  local p
  for p in \
    /Applications/SageMath-10-9.app/Contents/MacOS/SageMath \
    /Applications/SageMath.app/Contents/MacOS/SageMath \
    "$HOME/micromamba/envs/sage/bin/sage" \
    "$HOME/miniforge3/envs/sage/bin/sage" \
    /opt/homebrew/Caskroom/sage/*/SageMath-*.app/Contents/MacOS/SageMath
  do
    if [[ -x "$p" ]]; then
      echo "$p"
      return 0
    fi
  done
  return 1
}

if [[ ! -f logs/helut-estimator-pending.json ]]; then
  if [[ -x .build/release/helut ]]; then
    .build/release/helut --estimator-export > logs/helut-estimator-pending.json
  fi
fi

if SAGE_BIN=$(find_sage); then
  echo "H1: native sage at $SAGE_BIN" | tee logs/helut-sage-estimator-run.log
  if ! "$SAGE_BIN" --pip install "$EST" >/tmp/helut-sage-pip.log 2>&1; then
    "$SAGE_BIN" -python -m pip install "$EST" | tee -a logs/helut-sage-estimator-run.log
  fi
  "$SAGE_BIN" -python Scripts/helut_lattice_estimate.py \
    --pending logs/helut-estimator-pending.json \
    --out logs/helut-estimator-results.json \
    "$@" 2>&1 | tee -a logs/helut-sage-estimator-run.log
else
  {
    echo "H1 blocked: no native SageMath on PATH / SageMath.app / conda env."
    echo "Install: brew install --cask sage  (interactive sudo) or conda-forge osx-arm64 sage."
    echo "Do not docker --platform linux/amd64 on Apple silicon (FLINT SIGILL)."
  } | tee logs/helut-sage-estimator-run.log
  exit 2
fi
