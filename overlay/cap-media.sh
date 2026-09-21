#!/usr/bin/env bash
# cap-media.sh <image-file> [title] -> echoes object id on success
set -euo pipefail
IMG="${1:?usage: cap-media.sh <image-file> [title]}"
TITLE="${2:-}"
TOKEN_FILE="${CAP_TOKEN_FILE:-$HOME/.config/cap-quick/token}"
API="https://api.capacities.io"
TOKEN=""
if [[ -s "$TOKEN_FILE" ]]; then
  TOKEN="$(tr -d '[:space:]' < "$TOKEN_FILE")"
elif [[ -s "$HOME/.hermes/.env" ]]; then
  TOKEN="$(grep '^CAPACITIES_API_TOKEN=' "$HOME/.hermes/.env" | head -1 | cut -d= -f2- | tr -d '[:space:]')"
fi
[[ -n "$TOKEN" ]] || { echo "no token" >&2; exit 3; }
EXT="${IMG##*.}"
case "${EXT,,}" in
  png) MIME="image/png" ;;
  jpg|jpeg) MIME="image/jpeg" ;;
  gif) MIME="image/gif" ;;
  webp) MIME="image/webp" ;;
  *) MIME="application/octet-stream" ;;
esac
SIZE=$(stat -c %s "$IMG")
NAME="$(basename "$IMG")"
INIT_JSON="$(jq -n --arg n "$NAME" --argjson s "$SIZE" --arg t "$MIME" --arg title "${TITLE:-$NAME}" '{fileName:$n, fileSize:$s, fileType:$t, title:$title}')"
RESP="$(curl -sS --max-time 20 -X POST "$API/object/media/upload" -H "Authorization: Bearer $TOKEN" -H "X-Capacities-Api-Version: 1.0.0" -H "Content-Type: application/json" -d "$INIT_JSON")"
ID="$(echo "$RESP" | jq -r '.id // empty')"
[[ -n "$ID" ]] || { echo "init failed: $RESP" >&2; exit 1; }
curl -sS --max-time 60 -X PUT "$API/object/media/upload/part?id=$ID&partNumber=1" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/octet-stream" --data-binary "@$IMG" >/dev/null
curl -sS --max-time 20 -X POST "$API/object/media/upload/complete" -H "Authorization: Bearer $TOKEN" -H "X-Capacities-Api-Version: 1.0.0" -H "Content-Type: application/json" -d "{"id":"$ID"}" >/dev/null
echo "$ID"
