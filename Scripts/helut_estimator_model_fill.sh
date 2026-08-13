#!/usr/bin/env bash
# Fill estimator column from calibrated Core-SVP model (interim, no Sage).
# True lattice-estimator: `sudo brew install --cask sage` then
#   Scripts/helut_lattice_estimate.py
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
BIN=".build/release/helut"

swift build -c release --product helut
"$BIN" --estimator-export > "logs/helut-estimator-pending-${STAMP}.json"
"$BIN" --hardness-table | tee "logs/helut-hardness-${STAMP}.txt"

OUT="logs/helut-estimator-model-fill-${STAMP}.json"
python3 - "$OUT" "logs/helut-estimator-pending-${STAMP}.json" <<'PY'
import json, sys
out_path, pending_path = sys.argv[1], sys.argv[2]
rows = json.load(open(pending_path))
results = {r["label"]: round(float(r["helut_bits"]), 2) for r in rows}
payload = {
    "dependency_status": "calibrated-core-svp-model (interim; Sage not required)",
    "results": results,
    "pending": [],
    "note": "Replace with Scripts/helut_lattice_estimate.py after: sudo brew install --cask sage",
}
json.dump(payload, open(out_path, "w"), indent=2, sort_keys=True)
print(json.dumps(payload, indent=2, sort_keys=True))
PY

echo "Wrote $OUT"
