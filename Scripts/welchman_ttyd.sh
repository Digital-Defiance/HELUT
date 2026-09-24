#!/bin/sh
# Stream a Welchman/campaign log into ttyd with collapsed whitespace.
#
#   ./Scripts/welchman_ttyd.sh logs/some-run.log
#   ttyd -p 7681 -t fontSize=14 ./Scripts/welchman_ttyd.sh logs/some-run.log
#
# Wrap with turing_run if you also want the site Live tile:
#   ./Scripts/turing_run.sh -- ttyd -p 7681 ./Scripts/welchman_ttyd.sh "$LOG"

set -eu

if [ "${1:-}" = "" ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
fi

LOG="$1"
if [ ! -f "$LOG" ]; then
  echo "error: log not found: $LOG" >&2
  exit 1
fi

# Pass the path as argv[1]. Do not embed $1 inside the heredoc — quoting
# breaks on spaces, and python -c does not read a heredoc.
exec ttyd -p 7681 -t scrollback=50000 python3 -u - "$LOG" <<'PY'
import re
import subprocess
import sys

log = sys.argv[1]
proc = subprocess.Popen(
    ["tail", "-c", "500k", "-F", log],
    stdout=subprocess.PIPE,
    text=True,
    errors="replace",
)
assert proc.stdout is not None

line = ""
while True:
    char = proc.stdout.read(1)
    if not char:
        break
    if char in ("\r", "\n"):
        if line.strip():
            clean = re.sub(r" +", " ", line).strip()
            sys.stdout.write(clean + "\n")
            sys.stdout.flush()
        line = ""
    else:
        line += char
PY
