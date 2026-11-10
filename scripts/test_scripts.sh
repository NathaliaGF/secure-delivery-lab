#!/usr/bin/env bash
# Tests for the shell scripts, so they are not trusted blindly: feeds verify-hardening.sh a good
# and a bad `docker inspect` document and checks the verdict.
set -euo pipefail
cd "$(dirname "$0")"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

good='[{"Config":{"User":"10001:10001"},"State":{"Health":{"Status":"healthy"}},"HostConfig":{"ReadonlyRootfs":true,"CapDrop":["ALL"],"SecurityOpt":["no-new-privileges:true"],"Privileged":false,"Memory":268435456,"PortBindings":{"8080/tcp":[{"HostIp":"127.0.0.1","HostPort":"8080"}]}}}]'
echo "$good" > "$tmp/good.json"

INSPECT_JSON="$tmp/good.json" ./verify-hardening.sh >/dev/null || { echo "good container was rejected"; exit 1; }
echo "ok   hardened container passes"

for mutation in \
  '.[0].Config.User = "root"' \
  '.[0].HostConfig.ReadonlyRootfs = false' \
  '.[0].HostConfig.CapDrop = []' \
  '.[0].HostConfig.SecurityOpt = []' \
  '.[0].HostConfig.Privileged = true' \
  '.[0].HostConfig.Memory = 0' \
  '.[0].State.Health.Status = "unhealthy"' \
  '.[0].HostConfig.PortBindings["8080/tcp"][0].HostIp = "0.0.0.0"'
do
  echo "$good" | jq "$mutation" > "$tmp/bad.json"
  if INSPECT_JSON="$tmp/bad.json" ./verify-hardening.sh >/dev/null; then
    echo "FAIL: accepted a container with: $mutation"; exit 1
  fi
  echo "ok   rejects: $mutation"
done
