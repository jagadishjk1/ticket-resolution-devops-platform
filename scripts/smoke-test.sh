#!/usr/bin/env bash
# End-to-end smoke test against a running deployment.
#   ./scripts/smoke-test.sh http://<host>[:port] [prometheus-url]
# Exit code 0 = all checks passed.
set -euo pipefail

BASE="${1:-http://localhost:8080}"
BASE="${BASE%/}"
PROM="${2:-}"
RETRIES="${RETRIES:-36}"      # x5s = 3 minutes for the app to become healthy

pass() { printf '  \033[32mPASS\033[0m %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*" >&2; exit 1; }

echo "Smoke test -> $BASE"

# 1. /health must become 200 (returns 503 until the knowledge base is loaded)
ok=0
for _ in $(seq 1 "$RETRIES"); do
  code="$(curl -s -o /tmp/smoke_health.json -w '%{http_code}' --max-time 5 "$BASE/health" || true)"
  if [ "$code" = "200" ]; then ok=1; break; fi
  sleep 5
done
[ "$ok" -eq 1 ] || fail "/health did not return 200 (last status: ${code:-none})"
pass "/health = 200 ($(tr -d '\n' < /tmp/smoke_health.json))"

# 2. API info
curl -fsS --max-time 5 "$BASE/api" >/dev/null || fail "/api unreachable"
pass "/api reachable"

# 3. Core business endpoint
resp="$(curl -fsS --max-time 60 -X POST "$BASE/api/suggest-resolution" \
  -H 'Content-Type: application/json' \
  -d '{"category":"Password Reset","priority":"Medium","description":"User cannot log in after password expiry"}')" \
  || fail "POST /api/suggest-resolution failed"
if command -v jq >/dev/null 2>&1; then
  echo "$resp" | jq -e '.suggested_resolution | length > 0' >/dev/null || fail "empty suggested_resolution"
  pass "suggest-resolution returned a resolution (confidence $(echo "$resp" | jq -r '.confidence'))"
else
  echo "$resp" | grep -q 'suggested_resolution' || fail "response missing suggested_resolution"
  pass "suggest-resolution returned a resolution"
fi

# 4. Frontend SPA is served
ctype="$(curl -s -o /dev/null -w '%{content_type}' --max-time 5 "$BASE/")"
case "$ctype" in text/html*) pass "frontend served (text/html)";; *) fail "frontend not served (content-type: $ctype)";; esac

# 5. Metrics endpoints the observability stack scrapes
curl -fsS --max-time 5 "$BASE/api/metrics" >/dev/null          || fail "/api/metrics failed"
curl -fsS --max-time 5 "$BASE/api/metrics/realtime" >/dev/null || fail "/api/metrics/realtime failed"
pass "metrics endpoints respond"

# 6. Optional: Prometheus sees its targets
if [ -n "$PROM" ]; then
  PROM="${PROM%/}"
  down="$(curl -fsS --max-time 10 "$PROM/api/v1/targets?state=active" \
    | jq '[.data.activeTargets[] | select(.health != "up")] | length')" || fail "cannot query Prometheus"
  [ "$down" -eq 0 ] && pass "all Prometheus targets are up" || fail "$down Prometheus targets are not up"
fi

echo "All smoke tests passed."
