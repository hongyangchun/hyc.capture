#!/usr/bin/env bash
# hyc.cap-quick — send.sh
# Append markdown to today's Capacities daily note.
# Usage: send.sh <markdown-file> [date]
#   markdown-file : path to a file containing the note text (avoids argv quoting issues)
#   date          : optional ISO date (YYYY-MM-DD) to append to a specific daily note
# Env:
#   CAP_TOKEN_FILE  default ~/.config/cap-quick/token
#   CAP_TOKEN_ENV   fallback: read CAPACITIES_API_TOKEN from ~/.hermes/.env
#   CAP_QUEUE_DIR   default ~/.local/state/cap-quick/queue
# Exit codes: 0 sent | 1 queued (network/server error) | 2 bad input | 3 auth error
set -euo pipefail

NO_TS=0
if [[ "${1:-}" == "--no-ts" ]]; then
  NO_TS=1
  shift
fi
MD_FILE="${1:-}"
CAP_DATE="${2:-}"

[[ -s "$MD_FILE" ]] || { echo "empty note" >&2; exit 2; }

HOME_DIR="${HOME:?}"
TOKEN_FILE="${CAP_TOKEN_FILE:-$HOME_DIR/.config/cap-quick/token}"
QUEUE_DIR="${CAP_QUEUE_DIR:-$HOME_DIR/.local/state/cap-quick/queue}"
API="https://api.capacities.io/blocks/daily-note/append"

# ── token resolution ──
TOKEN=""
if [[ -s "$TOKEN_FILE" ]]; then
  TOKEN="$(tr -d '[:space:]' < "$TOKEN_FILE")"
elif [[ -s "$HOME_DIR/.hermes/.env" ]]; then
  TOKEN="$(grep '^CAPACITIES_API_TOKEN=' "$HOME_DIR/.hermes/.env" | head -1 | cut -d= -f2- | tr -d '[:space:]')"
fi
[[ -n "$TOKEN" ]] || { echo "no token found" >&2; exit 3; }

# ── build JSON payload (jq-safe) ──
# bullet per line: first line "- HH:MM text", following lines "- text".
# noTimeStamp:true keeps the daily note tight (our inline HH:MM is the timestamp).
  TS="$(date +%H:%M)"
  export CAP_TS="$TS"
  export CAP_NO_TS="$NO_TS"
  python3 - "$MD_FILE" "$MD_FILE.final" <<'PYEOF'
import sys, os
src, dst = sys.argv[1], sys.argv[2]
lines = [l.rstrip() for l in open(src, encoding='utf-8').read().splitlines() if l.strip()]
if not lines:
    sys.exit(2)
ts = os.environ.get('CAP_TS', '')
no_ts = os.environ.get('CAP_NO_TS') == '1'
out = []
for i, line in enumerate(lines):
    if i == 0:
        prefix = '' if no_ts else ts + ' '
    else:
        prefix = ''
    out.append('- ' + prefix + line)
open(dst, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
PYEOF

# markdown payload (optionally targeted at a specific daily note)
if [[ -n "$CAP_DATE" ]]; then
  PAYLOAD="$(jq -n --rawfile m "$MD_FILE.final" --arg d "$CAP_DATE" '{markdown:$m, date:$d, noTimeStamp:true}')"
else
  PAYLOAD="$(jq -n --rawfile m "$MD_FILE.final" '{markdown:$m, noTimeStamp:true}')"
fi

# ── send ──
HTTP_CODE="$(curl -sS -o /tmp/cap-quick-resp.json -w '%{http_code}' --max-time 15 \
  -X POST "$API" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-Capacities-Api-Version: 1.0.0" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" 2>/dev/null)" || HTTP_CODE="000"

case "$HTTP_CODE" in
  200|201|202)
    # success → try flushing any queued notes (best effort, one pass)
    if compgen -G "$QUEUE_DIR/*.md" >/dev/null 2>&1; then
      shopt -s nullglob
      for f in "$QUEUE_DIR"/*.md; do
        qdate=""
        [[ -f "$f.date" ]] && qdate="$(cat "$f.date")"
        if "$0" --no-ts "$f" "$qdate" >/dev/null 2>&1; then
          rm -f "$f" "$f.date"
        fi
        break  # one flush pass per successful send; next send continues
      done
    fi
    # log for bar widget count
    STAT_DIR="$HOME_DIR/.local/state/cap-quick"
    mkdir -p "$STAT_DIR/history"
    HIST="$STAT_DIR/history/$(date +%F).md"
    { [[ -s "$MD_FILE.final" ]] && cat "$MD_FILE.final" && echo; } >> "$HIST" || true
    printf '%s\n' "$(date +%F)" >> "$STAT_DIR/sent.log"
    exit 0
    ;;
  401|403)
    echo "auth error $HTTP_CODE: $(cat /tmp/cap-quick-resp.json 2>/dev/null | head -c 200)" >&2
    exit 3
    ;;
  000|429|5*)
    # network / rate limit / server → queue
    ;;
  *)
    # 4xx bad request etc. → queue too (don't lose user text over a bug)
    ;;
esac

# ── queue ──
mkdir -p "$QUEUE_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)-$RANDOM"
cp "$MD_FILE" "$QUEUE_DIR/$STAMP.md"
[[ -n "$CAP_DATE" ]] && printf '%s' "$CAP_DATE" > "$QUEUE_DIR/$STAMP.date"
echo "queued ($HTTP_CODE)"
exit 1
