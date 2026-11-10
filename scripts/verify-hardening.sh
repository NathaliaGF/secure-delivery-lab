#!/usr/bin/env bash
# Asserts that a running container has the hardening the project promises.
# Usage: verify-hardening.sh <container>      (or: INSPECT_JSON=file verify-hardening.sh)
set -euo pipefail

if [ -n "${INSPECT_JSON:-}" ]; then
  json=$(cat "$INSPECT_JSON")
else
  json=$(docker inspect "${1:?container name required}")
fi

fail=0
check() { # description, jq filter that must evaluate to true
  if echo "$json" | jq -e "$2" >/dev/null; then
    printf '  ok   %s\n' "$1"
  else
    printf '  FAIL %s\n' "$1"
    fail=1
  fi
}

check "runs as the unprivileged user 10001:10001" '.[0].Config.User == "10001:10001"'
check "root filesystem is read-only" '.[0].HostConfig.ReadonlyRootfs == true'
check "all capabilities are dropped" '(.[0].HostConfig.CapDrop // []) | index("ALL") != null'
check "no-new-privileges is set" '(.[0].HostConfig.SecurityOpt // []) | index("no-new-privileges:true") != null'
check "container is not privileged" '.[0].HostConfig.Privileged == false'
check "memory limit is set" '.[0].HostConfig.Memory > 0'
check "healthcheck reports healthy" '.[0].State.Health.Status == "healthy"'
check "published ports are bound to 127.0.0.1 only" \
  '[.[0].HostConfig.PortBindings // {} | to_entries[].value[].HostIp] | all(. == "127.0.0.1")'

exit "$fail"
