#!/usr/bin/env bash
# Run any command while advertising a live turing.helut.org session.
#
#   ./Scripts/turing_run.sh -- ./Scripts/p1030680_campaign.sh
#   ./Scripts/turing_run.sh -- .build/release/helut --campaign --from 2
#   TURING_HEARTBEAT_SEC=600 ./Scripts/turing_run.sh -- long-job
#
# Lifecycle:
#   start  → turing_status on
#   every TURING_HEARTBEAT_SEC (default 300 = 5 min) → heartbeat
#   any exit (0, error, Ctrl-C, SIGTERM) → kill heartbeat, turing_status off
#
# Requires: Scripts/turing_status.sh + authenticated gh.
# Does not start ttyd/cloudflared — wrap whatever you already use to broadcast.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATUS="${ROOT}/Scripts/turing_status.sh"
HEARTBEAT_SEC="${TURING_HEARTBEAT_SEC:-300}"

usage() {
  sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" || "$1" == "help" ]]; then
  usage
fi

if [[ "$1" == "--" ]]; then
  shift
fi

if [[ $# -eq 0 ]]; then
  usage
fi

if [[ ! -x "$STATUS" ]]; then
  echo "error: missing executable ${STATUS}" >&2
  exit 1
fi

if ! [[ "$HEARTBEAT_SEC" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: TURING_HEARTBEAT_SEC must be a positive integer (got: ${HEARTBEAT_SEC})" >&2
  exit 1
fi

hb_pid=""
cleaning=0

cleanup() {
  local rc=$?
  [[ "$cleaning" -eq 1 ]] && return
  cleaning=1

  if [[ -n "$hb_pid" ]] && kill -0 "$hb_pid" 2>/dev/null; then
    kill "$hb_pid" 2>/dev/null || true
    wait "$hb_pid" 2>/dev/null || true
  fi

  if ! "$STATUS" off >/dev/null; then
    echo "warning: turing_status off failed — set live=false manually" >&2
  else
    echo "turing: offline" >&2
  fi

  exit "$rc"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

heartbeat_loop() {
  while true; do
    sleep "$HEARTBEAT_SEC" || exit 0
    if ! "$STATUS" heartbeat >/dev/null; then
      echo "warning: turing_status heartbeat failed" >&2
    fi
  done
}

echo "turing: going live (heartbeat every ${HEARTBEAT_SEC}s)" >&2
if ! "$STATUS" on >/dev/null; then
  echo "error: turing_status on failed — not starting command" >&2
  cleaning=1
  exit 1
fi

heartbeat_loop &
hb_pid=$!

echo "turing: running: $*" >&2
"$@"
