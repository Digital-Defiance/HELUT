#!/usr/bin/env bash
# Multi-config Red battery against the scramble-fragment cone (past NLFF).
# Appends to logs/enigma256-scramble-frag-battery-g5.jsonl.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mkdir -p logs build
./Scripts/enigma256_tensorlut_synth.sh

HELUT_BIN="${HELUT_BIN:-.build/release/helut}"
if [[ ! -x "$HELUT_BIN" ]]; then
  swift build -c release --product helut
fi

LEDGER=logs/enigma256-scramble-frag-battery-g5.jsonl
SUMMARY=logs/enigma256-scramble-frag-battery-g5-summary.txt
NETLIST=build/enigma_256_scramble_frag_combo_netlist.json
: > "$SUMMARY"

run_one() {
  local name="$1" gens="$2" pop="$3" polish="$4" lambda="$5" seed="$6"
  local log="logs/tensorlut-battery-scramble-frag-g5-${name}.log"
  echo "=== BATTERY scramble-frag g5/${name} gens=${gens} pop=${pop} polish=${polish} λ=${lambda} seed=${seed} ===" | tee -a "$SUMMARY"
  set +e
  "$HELUT_BIN" --enigma256-tensorlut \
    --enigma256-netlist "$NETLIST" \
    --enigma256-emit-out "build/enigma_256_scramble_frag_tensorlut_g5_${name}.v" \
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
  "generation": 5,
  "cone": "scramble_frag",
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

run_one hard0 240 64 160 0 $((0xE25621))
run_one seedA 200 48 120 0 $((0xC0FFEE))
run_one seedB 200 48 120 0 $((0xBADC0DE))
run_one lam1 160 48 120 1  $((0xE25631))
run_one lam3 160 48 120 3  $((0xE25633))
run_one longex 320 48 80 0 $((0xE25641))
run_one fatpop 120 96 100 0 $((0xE25651))

echo "Battery complete → $LEDGER" | tee -a "$SUMMARY"
grep -h verdict logs/tensorlut-battery-scramble-frag-g5-*.log | sort | uniq -c | tee -a "$SUMMARY" || true
