#!/usr/bin/env bash
# Opens the deployed TrueForge on your laptop through an encrypted Systems Manager tunnel.
# Nothing is exposed to the internet. Keep this running, then open http://localhost:8790
# (stop your local TrueForge first, or pick another port: LOCAL_PORT=18790 ./deploy/aws/connect.sh).
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ID=$(cat "$DIR/.instance-id"); REGION=$(cat "$DIR/.region")
LOCAL_PORT="${LOCAL_PORT:-8790}"
echo "Tunnel: http://localhost:$LOCAL_PORT → TrueForge on $ID. Ctrl+C to close."
aws ssm start-session --region "$REGION" --target "$ID" --document-name AWS-StartPortForwardingSession \
  --parameters "{\"portNumber\":[\"8790\"],\"localPortNumber\":[\"$LOCAL_PORT\"]}"
