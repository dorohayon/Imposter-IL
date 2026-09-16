#!/usr/bin/env bash
# Prepares a fresh Ubuntu VM to run the server. Run once, from your machine:
#
#   gcloud compute ssh imposter --zone=us-central1-a --command "bash -s" < deploy/provision.sh
#
# Installs Docker and the compose plugin (Container-Optimized OS ships Docker
# but not compose, which is why this uses Ubuntu), then makes /var/imposter.
# The Caddyfile, compose file and .env are copied separately — see README.md.
set -euo pipefail

REGISTRY="${REGISTRY:-us-central1-docker.pkg.dev}"

echo "installing docker"
sudo apt-get update -qq
sudo apt-get install -y -qq ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg |
	sudo tee /etc/apt/keyrings/docker.asc >/dev/null
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" |
	sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt-get update -qq
sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin

echo "letting docker pull from Artifact Registry as the VM's service account"
sudo gcloud auth configure-docker "$REGISTRY" --quiet

echo "creating /var/imposter"
sudo mkdir -p /var/imposter
sudo systemctl enable --now docker

# Start on boot, so a VM restart brings the game back without a human.
sudo tee /etc/systemd/system/imposter.service >/dev/null <<'UNIT'
[Unit]
Description=Imposter IL server
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/var/imposter
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
# Above the server's DRAIN_TIMEOUT, so a reboot lets games finish.
TimeoutStopSec=400

[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload
sudo systemctl enable imposter.service

echo
echo "done. now copy the compose files and .env, then:"
echo "  sudo systemctl start imposter"
