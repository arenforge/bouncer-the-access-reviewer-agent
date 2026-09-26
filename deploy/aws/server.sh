#!/usr/bin/env bash
# Runs a shell command on the Bouncer instance as the "ubuntu" user, via Systems Manager.
#   ./deploy/aws/server.sh "cd ~/bouncer && docker compose ps"
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ID=$(cat "$DIR/.instance-id"); REGION=$(cat "$DIR/.region")

SCRIPT=$(printf '%s' "$1" | base64 | tr -d '\n')
PARAMS=$(python3 -c 'import json,sys; print(json.dumps({"commands":[f"echo {sys.argv[1]} | base64 -d > /tmp/bouncer-cmd.sh && sudo -u ubuntu -i bash /tmp/bouncer-cmd.sh"]}))' "$SCRIPT")

CMD=$(aws ssm send-command --region "$REGION" --instance-ids "$ID" --document-name AWS-RunShellScript \
  --parameters "$PARAMS" --timeout-seconds 900 --query Command.CommandId --output text)

while true; do
  STATUS=$(aws ssm get-command-invocation --region "$REGION" --command-id "$CMD" --instance-id "$ID" \
    --query Status --output text 2>/dev/null || echo Pending)
  case "$STATUS" in Pending|InProgress|Delayed) sleep 3 ;; *) break ;; esac
done
aws ssm get-command-invocation --region "$REGION" --command-id "$CMD" --instance-id "$ID" \
  --query '[StandardOutputContent,StandardErrorContent]' --output text
[ "$STATUS" = "Success" ]
