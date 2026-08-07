#!/bin/zsh
# P1030680 Thetis campaign — host oracle only. Leave this running.
# Stops early only on a strong-crib break verdict.
#
# Default skips the expensive rings-right redo. Pass extra args through:
#   ./Scripts/p1030680_campaign.sh
#   ./Scripts/p1030680_campaign.sh --skip rings-right,potsdam
#   ./Scripts/p1030680_campaign.sh --from 3
#   ./Scripts/p1030680_campaign.sh --include-aaaa
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs
stamp=$(date +%Y%m%d-%H%M%S)
log="logs/p1030680-campaign-${stamp}.log"
echo "Logging to ${log}"
echo "Building release…"
swift build -c release

# If the user did not pass --skip, default to skipping rings-right (AAA* already optional).
extra=("$@")
if [[ "$*" != *"--skip"* ]]; then
  extra=(--skip rings-right "${extra[@]}")
  echo "Default: --skip rings-right (override by passing your own --skip …)"
fi

echo "Starting campaign: .build/release/helut --campaign ${extra[*]}"
exec .build/release/helut --campaign "${extra[@]}" 2>&1 | tee "${log}"
