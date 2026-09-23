#!/usr/bin/env bash
# Push live / offline status to Digital-Defiance/HELUT-turing-status.
#
# Updates status.json via the GitHub Contents API (no local clone):
#   { "live": true|false, "lastStatus": <unix seconds> }
#
# Requires: gh (authenticated with write access to the status repo)
#
# Usage:
#   ./Scripts/turing_status.sh on          # broadcasting
#   ./Scripts/turing_status.sh off         # stopped
#   ./Scripts/turing_status.sh heartbeat   # refresh lastStatus while live
#   ./Scripts/turing_status.sh get         # print current JSON
#
# Env overrides:
#   TURING_STATUS_REPO    default Digital-Defiance/HELUT-turing-status
#   TURING_STATUS_PATH    default status.json
#   TURING_STATUS_BRANCH  default main

set -euo pipefail

REPO="${TURING_STATUS_REPO:-Digital-Defiance/HELUT-turing-status}"
FILE_PATH="${TURING_STATUS_PATH:-status.json}"
BRANCH="${TURING_STATUS_BRANCH:-main}"

usage() {
  sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

need_gh() {
  if ! command -v gh >/dev/null 2>&1; then
    echo "error: gh is required (https://cli.github.com/)" >&2
    exit 1
  fi
}

b64() {
  # macOS base64 wraps lines; GitHub wants a single line.
  if base64 --help 2>&1 | grep -q -- '-w'; then
    base64 -w0
  else
    base64 | tr -d '\n'
  fi
}

fetch_meta() {
  gh api "repos/${REPO}/contents/${FILE_PATH}?ref=${BRANCH}" 2>/dev/null
}

get_status() {
  need_gh
  local meta
  meta="$(fetch_meta)" || {
    echo "error: could not read ${REPO}/${FILE_PATH} on ${BRANCH}" >&2
    exit 1
  }
  printf '%s' "$meta" | python3 -c '
import json, sys, base64
print(base64.b64decode(json.load(sys.stdin)["content"]).decode(), end="")
'
}

put_status() {
  local live="$1"
  need_gh

  case "$live" in
    true|false) ;;
    *)
      echo "error: live must be true or false (got: $live)" >&2
      exit 1
      ;;
  esac

  local ts body sha message encoded payload
  ts="$(date +%s)"
  body="$(LIVE="$live" TS="$ts" python3 -c '
import json, os
print(json.dumps({"live": os.environ["LIVE"] == "true", "lastStatus": int(os.environ["TS"])}, indent=2) + "\n")
')"

  sha=""
  if meta="$(fetch_meta)"; then
    sha="$(printf '%s' "$meta" | python3 -c 'import json,sys; print(json.load(sys.stdin)["sha"])')"
  fi

  if [[ "$live" == "true" ]]; then
    message="turing: live @ ${ts}"
  else
    message="turing: offline @ ${ts}"
  fi

  encoded="$(printf '%s' "$body" | b64)"
  payload="$(
    MSG="$message" CONTENT="$encoded" BRANCH="$BRANCH" SHA="$sha" python3 -c '
import json, os
payload = {
    "message": os.environ["MSG"],
    "content": os.environ["CONTENT"],
    "branch": os.environ["BRANCH"],
}
sha = os.environ.get("SHA") or ""
if sha:
    payload["sha"] = sha
print(json.dumps(payload))
'
  )"

  gh api \
    --method PUT \
    "repos/${REPO}/contents/${FILE_PATH}" \
    --input - <<<"$payload" \
    --jq .commit.sha >/dev/null

  printf '%s' "$body"
  echo "pushed ${REPO}@${BRANCH}:${FILE_PATH}  live=${live}  lastStatus=${ts}" >&2
}

cmd="${1:-}"
case "$cmd" in
  on|live|start)
    put_status true
    ;;
  off|offline|stop)
    put_status false
    ;;
  heartbeat|ping|touch)
    put_status true
    ;;
  get|status|show)
    get_status
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    echo "error: unknown command: $cmd" >&2
    usage
    ;;
esac
