#!/bin/bash
# First-boot setup for the Bouncer EC2 instance (Ubuntu 22.04).
# Everything listens on localhost only; the security group has no inbound rules.
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update
# bubblewrap, socat and ripgrep are what TrueForge's Linux sandbox needs.
# Ubuntu 22.04 lets bubblewrap use user namespaces without extra changes.
apt-get install -y ca-certificates curl git python3 bubblewrap socat ripgrep postgresql-client

curl -fsSL https://get.docker.com | sh
usermod -aG docker ubuntu

curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs

sudo -u ubuntu git clone https://github.com/arenforge/bouncer-the-access-reviewer-agent.git /home/ubuntu/bouncer

cat > /etc/trueforge.env <<'EOF'
HOST=127.0.0.1
PORT=8790
OUTBOUND_URL_ALLOWED_HOSTS='["localhost"]'
EOF

cat > /etc/systemd/system/trueforge.service <<'EOF'
[Unit]
Description=TrueForge standalone (localhost only) + Bouncer containers
After=network-online.target docker.service
Wants=network-online.target
Requires=docker.service

[Service]
User=ubuntu
WorkingDirectory=/home/ubuntu/bouncer
EnvironmentFile=/etc/trueforge.env
ExecStartPre=/usr/bin/docker compose -f /home/ubuntu/bouncer/docker-compose.yml up -d
ExecStart=/usr/bin/npx -y @truefoundry/trueforge@0.2.1
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# No SSH: access is only through Systems Manager
systemctl disable --now ssh.socket ssh.service || true

systemctl daemon-reload
systemctl enable --now trueforge

# Wait for TrueForge, then mark the instance ready
for i in $(seq 1 120); do
  curl -sf http://127.0.0.1:8790/api/v1/agents >/dev/null && break
  sleep 5
done
touch /var/lib/bouncer-ready
