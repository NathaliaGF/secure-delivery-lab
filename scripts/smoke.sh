#!/usr/bin/env bash
# shellcheck disable=SC2329  # the check functions are invoked indirectly through check()
# Black-box checks against a running stack.
# Usage: smoke.sh <app-url> [prometheus-url]
set -euo pipefail

app=${1:?app url required}
prom=${2:-}
fail=0

# check <description> <command...>: runs the command and records ok or FAIL.
check() {
  local desc=$1
  shift
  if "$@"; then
    printf '  ok   %s\n' "$desc"
  else
    printf '  FAIL %s\n' "$desc"
    fail=1
  fi
}

json_field() { # url jq-filter expected
  [ "$(curl -fsS "$1" | jq -r "$2")" = "$3" ]
}

post_echo() { # body -> prints the HTTP status code
  curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "$1" "$app/api/echo"
}

has_header() { curl -fsSI "$app/healthz" | grep -qi "^$1"; }

# wait for the app (up to 60 s)
for _ in $(seq 1 30); do
  curl -fsS "$app/healthz" >/dev/null 2>&1 && break
  sleep 2
done

check "/healthz is ok" json_field "$app/healthz" .status ok
check "/readyz is ready" json_field "$app/readyz" .status ready
check "/ identifies the service" json_field "$app/" .service secure-delivery-lab
if [ -n "${EXPECTED_VERSION:-}" ]; then
  check "version is $EXPECTED_VERSION" json_field "$app/" .version "$EXPECTED_VERSION"
fi

echo_ok() { [ "$(curl -fsS -X POST -H 'Content-Type: application/json' -d '{"message":"smoke"}' "$app/api/echo" | jq -r .message)" = "smoke" ]; }
check "POST /api/echo works" echo_ok
check "invalid input is rejected with 422" test "$(post_echo '{"message":""}')" = 422
check "wrong JSON shape is rejected with 400" test "$(post_echo '{"msg":"x"}')" = 400
check "security headers present" has_header "x-content-type-options: nosniff"
check "CSP header present" has_header "content-security-policy:"
metrics_ok() { curl -fsS "$app/metrics" | grep -q '^app_http_requests_total'; }
check "/metrics exposes request counters" metrics_ok

if [ -n "$prom" ]; then
  prom_up() {
    local v
    for _ in $(seq 1 24); do   # Prometheus scrapes every 15 s; allow up to 2 min
      v=$(curl -fsS --get "$prom/api/v1/query" --data-urlencode 'query=up{job="app"}' \
          | jq -r '.data.result[0].value[1] // "0"' 2>/dev/null || echo 0)
      [ "$v" = "1" ] && return 0
      sleep 5
    done
    return 1
  }
  check "Prometheus scrapes the app (up == 1)" prom_up
fi

exit "$fail"
