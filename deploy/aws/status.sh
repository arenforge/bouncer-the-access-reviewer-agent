#!/usr/bin/env bash
# Shows whether the instance finished first-boot setup and everything is running.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
"$DIR/server.sh" '
test -f /var/lib/bouncer-ready && echo "setup: done" || echo "setup: still running (tail: sudo tail /var/log/cloud-init-output.log)"
echo "trueforge: $(systemctl is-active trueforge)"
cd ~/bouncer && docker compose ps --format "{{.Name}}  {{.Status}}  {{.Ports}}"
curl -sf http://127.0.0.1:8790/api/v1/agents >/dev/null && echo "trueforge api: up" || echo "trueforge api: not up yet"
echo "listening ports (must all be 127.0.0.1):"; ss -tln | awk "NR>1{print \"  \"\$4}" | sort -u
'
