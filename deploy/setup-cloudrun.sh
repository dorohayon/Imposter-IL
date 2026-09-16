#!/usr/bin/env bash
# Deploys the server to Cloud Run. Free within the Always Free tier, no VM, no
# external IPv4 to pay for, no Caddy and no domain — Cloud Run supplies the
# HTTPS hostname and certificate.
#
#   ./deploy/setup-cloudrun.sh
#
# Use this for beta and soft launch. Its one real cost is that Cloud Run
# decides when to stop the instance and gives it ~10 seconds, so a deploy or a
# scale-down ends the games in flight. They end cleanly — players see the
# server-error screen and no loss is recorded — but they do end. When that
# stops being acceptable, deploy/setup-gcp.sh puts the same image on a VM that
# drains properly.
set -euo pipefail

PROJECT="${PROJECT:-imposter-il-game}"
REGION="${REGION:-us-central1}"
SERVICE="${SERVICE:-imposter}"
REPO="${REPO:-imposter}"
BILLING_ACCOUNT="${BILLING_ACCOUNT:-}"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$here")"
step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

step "project $PROJECT"
gcloud projects describe "$PROJECT" >/dev/null 2>&1 || gcloud projects create "$PROJECT" --name="Imposter IL"
gcloud config set project "$PROJECT" >/dev/null

if [ -z "$(gcloud billing projects describe "$PROJECT" --format='value(billingAccountName)' 2>/dev/null)" ]; then
	[ -n "$BILLING_ACCOUNT" ] ||
		BILLING_ACCOUNT="$(gcloud billing accounts list --filter=open=true --format='value(name)' --limit=1)"
	[ -n "$BILLING_ACCOUNT" ] || { echo "no open billing account; set BILLING_ACCOUNT=" >&2; exit 1; }
	gcloud billing projects link "$PROJECT" --billing-account="$BILLING_ACCOUNT"
fi

step "enabling APIs"
gcloud services enable run.googleapis.com artifactregistry.googleapis.com cloudbuild.googleapis.com

step "image registry"
gcloud artifacts repositories describe "$REPO" --location="$REGION" >/dev/null 2>&1 ||
	gcloud artifacts repositories create "$REPO" --repository-format=docker --location="$REGION"

IMAGE="$REGION-docker.pkg.dev/$PROJECT/$REPO/server:$(date +%Y%m%d-%H%M%S)"
step "building $IMAGE"
gcloud auth configure-docker "$REGION-docker.pkg.dev" --quiet
docker build --platform linux/amd64 -t "$IMAGE" "$root/server"
docker push "$IMAGE"

# A token so the counters are readable: Cloud Run has no shell, so the
# loopback metrics listener the VM uses is unreachable here.
METRICS_TOKEN="${METRICS_TOKEN:-$(head -c 24 /dev/urandom | base64 | tr -d '/+=')}"

step "deploying"
# The flags that matter, and why:
#
#   max-instances=1   MANDATORY. Every session, room and game lives in one
#                     process's memory, and matchmaking is a slice in it. Two
#                     instances means two players who tap "search" at the same
#                     moment never see each other. This is the hard cap until
#                     Stage 1 of docs/production-architecture-review.md.
#   min-instances=0   Scale to zero when nobody is connected. There is no state
#                     worth keeping at that point, and it is what makes this
#                     free.
#   concurrency       A WebSocket is one long-lived request against this limit,
#                     so the default 80 would cap the whole service at ten
#                     games. 800 is ~100 full tables.
#   timeout=3600      Cloud Run's maximum. A WebSocket is cut at this age; the
#                     app reconnects, and a game lasts ~4 minutes, so this is
#                     rarely reached mid-game.
#   cpu-throttling    Left ON (the default). Cloud Run allocates CPU while a
#                     request is in flight, and every connected player holds an
#                     open WebSocket, so the game's timers keep firing whenever
#                     anyone is there to care.
gcloud run deploy "$SERVICE" \
	--image="$IMAGE" \
	--region="$REGION" \
	--platform=managed \
	--allow-unauthenticated \
	--port=8080 \
	--min-instances=0 \
	--max-instances=1 \
	--concurrency=800 \
	--timeout=3600 \
	--memory=512Mi \
	--cpu=1 \
	--set-env-vars="TRUST_PROXY=1,METRICS_ADDR=,METRICS_TOKEN=$METRICS_TOKEN,DRAIN_TIMEOUT=8s,LOG_LEVEL=info,MIN_CLIENT_BUILD=0"

URL="$(gcloud run services describe "$SERVICE" --region="$REGION" --format='value(status.url)')"

step "checking"
curl -fsS "$URL/healthz" >/dev/null && echo "healthy"

cat <<EOF

  server is public at $URL

  build the app against it:
    flutter build apk --dart-define=IMPOSTER_SERVER=$URL

  read the counters (save this token, it is not shown again):
    curl -H 'Authorization: Bearer $METRICS_TOKEN' $URL/metrics

  logs are already structured JSON in Cloud Logging:
    gcloud run services logs read $SERVICE --region=$REGION --limit=50

  redeploy: re-run this script. Games in flight end cleanly (no loss recorded).
  delete:   gcloud run services delete $SERVICE --region=$REGION

EOF
