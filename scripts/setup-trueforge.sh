#!/usr/bin/env bash
# Registers the two MCP servers in a running TrueForge and creates (or updates)
# the "bouncer" agent from agent/instructions.md. Safe to re-run.
#
# Prerequisites:
#   1. docker compose up -d
#   2. OUTBOUND_URL_ALLOWED_HOSTS='["localhost"]' npx @truefoundry/trueforge
#   3. A model provider added in TrueForge (Settings) with your own API key
#
# Optional: BOUNCER_MODEL=anthropic/claude-sonnet-5 ./scripts/setup-trueforge.sh
set -euo pipefail

API="${TRUEFORGE_URL:-http://localhost:8790}/api/v1"
MODEL="${BOUNCER_MODEL:-anthropic/claude-fable-5}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

curl -sf "$API/agents" >/dev/null || {
  echo "TrueForge is not reachable at $API."
  echo "Start it with: OUTBOUND_URL_ALLOWED_HOSTS='[\"localhost\"]' npx @truefoundry/trueforge"
  exit 1
}

for port in 8000 8001; do
  # The SSE stream never ends, so curl always times out; only the output matters
  sse=$(curl -s -N --max-time 2 "http://localhost:$port/sse" || true)
  echo "$sse" | grep -q endpoint || {
    echo "No MCP server on port $port. Run: docker compose up -d"
    exit 1
  }
done

register() { # name port description
  local body
  body=$(python3 -c 'import json,sys; print(json.dumps({"manifest":{"type":"remote","name":sys.argv[1],"url":f"http://localhost:{sys.argv[2]}/sse","description":sys.argv[3]}}))' "$1" "$2" "$3")
  local out
  out=$(curl -s -X PUT "$API/settings/mcp-servers" -H 'content-type: application/json' -d "$body")
  if echo "$out" | grep -q '"error"'; then
    echo "Registering $1 failed: $out"
    echo "If it says 'Outbound URL blocked', restart TrueForge with OUTBOUND_URL_ALLOWED_HOSTS='[\"localhost\"]'."
    exit 1
  fi
  echo "Registered MCP server $1 -> http://localhost:$2/sse"
}

register bouncer-reader 8000 "Read-only access to the company Postgres database (restricted mode). Use for all investigation: roles, grants, governance tables."
register bouncer-revoker 8001 "Write access to the company Postgres database (unrestricted). Use ONLY to execute an approved revoke script. Every call requires human approval."

if ! curl -s "$API/settings/model-providers" | grep -q '"model_id"'; then
  echo "WARNING: no model provider configured. Add one in TrueForge Settings with your own API key, then re-run."
fi

python3 - "$API" "$MODEL" "$ROOT/agent/instructions.md" <<'PY'
import json, sys, urllib.request

api, model, path = sys.argv[1:4]
instructions = open(path).read().split("\n---\n", 1)[1].strip()

def call(method, url, body=None):
    req = urllib.request.Request(url, method=method, headers={"content-type": "application/json"},
                                 data=None if body is None else json.dumps(body).encode())
    with urllib.request.urlopen(req) as r:
        return json.load(r)

manifest = {
    "model": {"name": model, "params": {"reasoning_effort": "low"}},
    "instructions": instructions,
    "mcp_servers": [
        # Reader: no approval needed, it cannot write
        {"name": "bouncer-reader", "enable_tools": ["@all"], "require_approval_for_tools": []},
        # Revoker: SHIELDED. Every tool pauses for a human.
        {"name": "bouncer-revoker", "enable_tools": ["@all"], "require_approval_for_tools": ["@all"]},
    ],
    "config": {
        "iteration_limit": 100,
        "sandbox": {"enabled": True, "file_downloads": True},
        "dynamic_sub_agents": {"enabled": True},
        "context_management": {"compaction": {"enabled": True}, "large_tool_response": {"enabled": True}},
        "generative_ui": {"enabled": True},
        "ask_user_questions": {"enabled": True},
    },
}
description = ("Access reviewer: finds stale database access, shows the blast radius, "
               "dry-runs the cleanup and waits for human approval before revoking.")

existing = next((a for a in call("GET", f"{api}/agents")["data"] if a["name"] == "bouncer"), None)
if existing:
    call("PUT", f"{api}/agents/{existing['id']}", {"description": description, "manifest": manifest})
    print(f"Updated agent 'bouncer' ({model}) from agent/instructions.md")
else:
    call("POST", f"{api}/agents", {"name": "bouncer", "description": description, "manifest": manifest})
    print(f"Created agent 'bouncer' ({model}) from agent/instructions.md")
print("Revoker is shielded: every call asks for approval.")
PY
