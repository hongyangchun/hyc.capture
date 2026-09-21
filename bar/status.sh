#!/usr/bin/env bash
STATE_DIR="${HOME}/.local/state/cap-quick"
TODAY="$(date +%F)"
SENT_N=0
[[ -f "$STATE_DIR/sent.log" ]] && SENT_N=$(grep -c "^$TODAY$" "$STATE_DIR/sent.log" 2>/dev/null || echo 0)
QUEUE_N=$(find "$STATE_DIR/queue" -name "*.md" 2>/dev/null | wc -l)
echo "${SENT_N:-0} ${QUEUE_N:-0}"
