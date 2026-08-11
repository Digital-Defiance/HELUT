#!/usr/bin/env bash
# Multi-config Red battery against the live Enigma 256 NLFF cone (Apple Silicon).
# Appends machine-readable rows to logs/enigma256-red-battery.jsonl
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mkdir -p logs build
./Scripts/enigma256_tensorlut_synth.sh

LEDGER=logs/enigma256-red-battery.jsonl
SUMMARY=logs/enigma256-red-battery-summary.txt
: > "$SUMMARY"

run_one() {
  local name="$1" gens="$2" pop="$3" polish="$4" lambda="$5" seed="$6"
  local log="logs/tensorlut-battery-${name}.log"
  echo "=== BATTERY ${name} gens=${gens} pop=${pop} polish=${polish} λ=${lambda} seed=${seed} ===" | tee -a "$SUMMARY"
  set +e
  swift run -c release helut --enigma256-tensorlut \
    --enigma256-netlist build/enigma_256_nlff_combo_netlist.json \
    --enigma256-emit-out "build/enigma_256_tensorlut_${name}.v" \
    --enigma256-tensorlut-log "$log" \
    --enigma256-tensorlut-gens "$gens" \
    --enigma256-tensorlut-pop "$pop" \
    --enigma256-tensorlut-polish "$polish" \
    --enigma256-tensorlut-lambda "$lambda" \
    --enigma256-tensorlut-seed "$seed" \
    >>"$SUMMARY" 2>&1
  local rc=$?
  set -e
  local verdict squeeze crypto
  verdict=$(grep -E '^verdict:' "$log" | awk '{print $2}' || echo missing)
  squeeze=$(grep -E '^squeeze_survived:' "$log" | awk '{print $2}' || echo missing)
  crypto=$(grep -E '^final_crypto:' "$log" | awk '{print $2}' || echo missing)
  python3 - <<PY
import json, time
row = {
  "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
  "name": "${name}",
  "gens": int("${gens}"),
  "pop": int("${pop}"),
  "polish": int("${polish}"),
  "lambda": float("${lambda}"),
  "seed": int("${seed}"),
  "verdict": "${verdict}",
  "squeeze_survived": "${squeeze}",
  "final_crypto": "${crypto}",
  "rc": int("${rc}"),
  "log": "${log}",
}
open("${LEDGER}", "a").write(json.dumps(row) + "\n")
print(json.dumps(row))
PY
}

# Baseline hard (known hold)
run_one hard0 240 64 160 0 $((0xE25621))
# Alternate seeds, λ=0
run_one seedA 200 48 120 0 $((0xC0FFEE))
run_one seedB 200 48 120 0 $((0xBADC0DE))
# Gentle λ polish (may help or crush — grade either way)
run_one lam1 160 48 120 1  $((0xE25631))
run_one lam3 160 48 120 3  $((0xE25633))
# Long explore, short polish
run_one longex 320 48 80 0 $((0xE25641))
# Fat population
run_one fatpop 120 96 100 0 $((0xE25651))

echo "Battery complete → $LEDGER" | tee -a "$SUMMARY"
grep -h verdict logs/tensorlut-battery-*.log | sort | uniq -c | tee -a "$SUMMARY" || true
