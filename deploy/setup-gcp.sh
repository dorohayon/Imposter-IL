#!/usr/bin/env bash
# One-time setup of the whole Stage 0 deployment, from nothing to a server
# answering on HTTPS. Idempotent: safe to re-run after a failure.
#
#   ./deploy/setup-gcp.sh
#
# Everything is configurable by environment variable; the defaults are the
# free-tier choices from README.md.
#
# COSTS MONEY. The e2-micro VM is on GCP's Always Free tier, but the reserved
# static IPv4 is about $3/month and egress past 1 GB/month is about $0.12/GB
# (roughly 2 MB per game). Run ./deploy/teardown-gcp.sh to stop all of it.
set -euo pipefail

PROJECT="${PROJECT:-imposter-il-game}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"
INSTANCE="${INSTANCE:-imposter}"
REPO="${REPO:-imposter}"
BILLING_ACCOUNT="${BILLING_ACCOUNT:-}"
# Hostname. Empty means derive one from the VM's address using sslip.io, which
# needs no domain and no DNS record: 34-72-1-5.sslip.io resolves to 34.72.1.5,
# and Let's Encrypt issues for it normally.
DOMAIN="${DOMAIN:-}"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$here")"
ssh() { gcloud compute ssh "$INSTANCE" --zone="$ZONE" --project="$PROJECT" --tunnel-through-iap --quiet "$@"; }
step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

# ---------------------------------------------------------------- project

step "project $PROJECT"
if gcloud projects describe "$PROJECT" >/dev/null 2>&1; then
	echo "already exists"
else
	gcloud projects create "$PROJECT" --name="Imposter IL"
fi
gcloud config set project "$PROJECT" >/dev/null

if [ -z "$(gcloud billing projects describe "$PROJECT" --format='value(billingAccountName)' 2>/dev/null)" ]; then
	if [ -z "$BILLING_ACCOUNT" ]; then
		BILLING_ACCOUNT="$(gcloud billing accounts list --filter=open=true --format='value(name)' --limit=1)"
	fi
	[ -n "$BILLING_ACCOUNT" ] || { echo "no open billing account; set BILLING_ACCOUNT=" >&2; exit 1; }
	step "linking billing $BILLING_ACCOUNT"
	gcloud billing projects link "$PROJECT" --billing-account="$BILLING_ACCOUNT"
fi

step "enabling APIs (slow the first time)"
gcloud services enable compute.googleapis.com artifactregistry.googleapis.com iap.googleapis.com

step "image registry"
gcloud artifacts repositories describe "$REPO" --location="$REGION" >/dev/null 2>&1 ||
	gcloud artifacts repositories create "$REPO" --repository-format=docker --location="$REGION"

# ------------------------------------------------------------------- vm

step "static address"
# Reserved, not ephemeral: the hostname is derived from it, and the app is
# built against that hostname. An address that changed would break installs.
gcloud compute addresses describe "$INSTANCE" --region="$REGION" >/dev/null 2>&1 ||
	gcloud compute addresses create "$INSTANCE" --region="$REGION"
IP="$(gcloud compute addresses describe "$INSTANCE" --region="$REGION" --format='value(address)')"
echo "$IP"

[ -n "$DOMAIN" ] || DOMAIN="${IP//./-}.sslip.io"
step "hostname $DOMAIN"

step "firewall"
# Web from anywhere; SSH only from Google's IAP forwarders, so port 22 is
# never open to the internet.
gcloud compute firewall-rules describe "$INSTANCE-web" >/dev/null 2>&1 ||
	gcloud compute firewall-rules create "$INSTANCE-web" --allow=tcp:80,tcp:443 --target-tags="$INSTANCE"
gcloud compute firewall-rules describe "$INSTANCE-ssh-iap" >/dev/null 2>&1 ||
	gcloud compute firewall-rules create "$INSTANCE-ssh-iap" \
		--allow=tcp:22 --source-ranges=35.235.240.0/20 --target-tags="$INSTANCE"

step "vm"
# Ubuntu LTS, not Container-Optimized OS: COS ships Docker without the compose
# plugin, and provision.sh installs both.
if gcloud compute instances describe "$INSTANCE" --zone="$ZONE" >/dev/null 2>&1; then
	echo "already exists"
else
	gcloud compute instances create "$INSTANCE" \
		--zone="$ZONE" --machine-type=e2-micro \
		--image-family=ubuntu-2404-lts-amd64 --image-project=ubuntu-os-cloud \
		--boot-disk-size=20GB --boot-disk-type=pd-standard \
		--address="$IP" --tags="$INSTANCE" \
		--scopes=https://www.googleapis.com/auth/cloud-platform
fi

step "letting the vm pull images"
NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
gcloud projects add-iam-policy-binding "$PROJECT" --condition=None \
	--member="serviceAccount:$NUMBER-compute@developer.gserviceaccount.com" \
	--role=roles/artifactregistry.reader >/dev/null

# -------------------------------------------------------------- software

step "waiting for ssh"
until ssh --command=true >/dev/null 2>&1; do sleep 5; done

step "installing docker on the vm"
ssh --command "bash -s" <"$here/provision.sh"

step "copying the compose stack"
ssh --command "sudo mkdir -p /var/imposter && sudo chown -R \$USER /var/imposter"
IMAGE="$REGION-docker.pkg.dev/$PROJECT/$REPO/server:setup"
cat >/tmp/imposter.env <<EOF
IMPOSTER_DOMAIN=$DOMAIN
IMPOSTER_IMAGE=$IMAGE
MIN_CLIENT_BUILD=0
EOF
gcloud compute scp --zone="$ZONE" --project="$PROJECT" --tunnel-through-iap --quiet \
	"$here/docker-compose.yml" "$here/Caddyfile" /tmp/imposter.env "$INSTANCE:/var/imposter/"
ssh --command "sudo mv /var/imposter/imposter.env /var/imposter/.env"
rm -f /tmp/imposter.env

step "building and pushing $IMAGE"
gcloud auth configure-docker "$REGION-docker.pkg.dev" --quiet
docker build --platform linux/amd64 -t "$IMAGE" "$root/server"
docker push "$IMAGE"

step "starting"
ssh --command "sudo systemctl start imposter"

step "waiting for the certificate"
# Let's Encrypt takes a few seconds once the address resolves; sslip.io is
# instant, a real domain waits on your DNS.
for _ in $(seq 1 60); do
	if curl -fsS "https://$DOMAIN/healthz" 2>/dev/null | grep -q '"ok"'; then
		printf '\n\033[1mserver is up: https://%s\033[0m\n\n' "$DOMAIN"
		echo "build the app against it:"
		echo "  flutter build apk --dart-define=IMPOSTER_SERVER=https://$DOMAIN"
		echo
		echo "watch it:"
		echo "  gcloud compute ssh $INSTANCE --zone=$ZONE --tunnel-through-iap --command 'curl -s localhost:9090/metrics'"
		echo
		echo "stop paying for it:"
		echo "  ./deploy/teardown-gcp.sh"
		exit 0
	fi
	sleep 5
done

echo "no answer from https://$DOMAIN/healthz yet. Caddy's log usually says why:" >&2
echo "  gcloud compute ssh $INSTANCE --zone=$ZONE --tunnel-through-iap --command 'sudo docker compose -f /var/imposter/docker-compose.yml logs caddy'" >&2
exit 1
