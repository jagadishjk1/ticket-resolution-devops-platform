#!/usr/bin/env bash
# Generate realistic ticket traffic so the Grafana dashboards have data.
#   ./scripts/load-test.sh http://<host>[:port] [requests=100] [concurrency=4]
# Needs bash >= 4.3 (macOS: brew install bash).
set -euo pipefail

BASE="${1:-http://localhost:8080}"; BASE="${BASE%/}"
TOTAL="${2:-100}"
CONC="${3:-4}"

categories=("Password Reset" "Network Issue" "Software Installation" "Email Problem" "VPN Access" "Printer Issue" "Hardware Failure")
priorities=("Low" "Medium" "High" "Critical")
descriptions=(
  "User cannot log in after password expiry notification"
  "Laptop cannot connect to office wifi since this morning"
  "Need Microsoft Teams installed on a new workstation"
  "Outlook keeps asking for credentials and will not sync"
  "VPN disconnects every few minutes while working from home"
  "Shared printer on floor 3 shows offline for everyone"
  "Monitor flickers and goes black randomly"
)

send() {
  local n=$1 i=$(( $1 % ${#categories[@]} ))
  local body
  body=$(printf '{"category":"%s","priority":"%s","description":"%s (case %d)"}' \
    "${categories[$i]}" "${priorities[$(( n % ${#priorities[@]} ))]}" "${descriptions[$i]}" "$n")
  curl -s -o /dev/null -w '%{http_code}\n' --max-time 60 -X POST "$BASE/api/suggest-resolution" \
    -H 'Content-Type: application/json' -d "$body" || echo "000"
}
echo "Sending $TOTAL requests (concurrency $CONC) to $BASE ..."
# Background jobs inherit the arrays above. Requires bash >= 4.3 for `wait -n`.
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
running=0
for n in $(seq 1 "$TOTAL"); do
  send "$n" >> "$tmp" &
  running=$((running + 1))
  if [ "$running" -ge "$CONC" ]; then wait -n; running=$((running - 1)); fi
done
wait

echo "Status code summary:"
sort "$tmp" | uniq -c | sort -rn
