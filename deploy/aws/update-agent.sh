#!/usr/bin/env bash
# Pulls the latest repo on the server and updates the bouncer agent from agent/instructions.md.
# Run after pushing a change. New chats use the new instructions; nothing needs a restart.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
"$DIR/server.sh" 'cd ~/bouncer && git pull --ff-only && docker compose up -d && ./scripts/setup-trueforge.sh'
