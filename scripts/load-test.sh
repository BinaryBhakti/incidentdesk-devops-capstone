#!/usr/bin/env bash
# Controlled load for the HPA / Grafana demo: mixed reads and writes against the API.
#   scripts/load-test.sh http://incidentdesk.local 120     # base URL, duration in seconds
set -euo pipefail
BASE=${1:-http://localhost:8080}
DURATION=${2:-60}
CONCURRENCY=${CONCURRENCY:-8}
end=$((SECONDS + DURATION))

worker() {
  local n=0
  while [ $SECONDS -lt $end ]; do
    curl -s -o /dev/null "$BASE/api/incidents"
    curl -s -o /dev/null "$BASE/api/incidents/stats"
    if [ $((n % 10)) -eq 0 ]; then
      curl -s -o /dev/null -X POST "$BASE/api/incidents" -H 'Content-Type: application/json' \
        -d "{\"title\":\"load test $1-$n\",\"service\":\"loadgen\",\"severity\":\"SEV4\"}"
    fi
    curl -s -o /dev/null "$BASE/api/incidents/999999" # a 404, so the dashboard shows a non-2xx series
    n=$((n + 1))
  done
  echo "worker $1: $n iterations"
}

echo "load: $CONCURRENCY workers x ${DURATION}s against $BASE"
for i in $(seq 1 "$CONCURRENCY"); do worker "$i" & done
wait
