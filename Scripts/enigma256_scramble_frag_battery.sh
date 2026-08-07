#!/usr/bin/env bash
# Profile-bound E256-v2 scramble-fragment controls + current-profile arms.
# Full historical budgets are the default; pass --budget-profile bounded for a checkpoint receipt.
# The cone uses frozen Red stand-in bijections; it is not the full E256 core.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 "$ROOT/Scripts/enigma256_tensorlut_battery.py" --cone scramble-frag "$@"
