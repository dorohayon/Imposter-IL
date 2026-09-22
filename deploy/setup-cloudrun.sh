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

# gcloud asks questions — "API not enabled, enable and retry? (y/N)" is the
# common one — and a script run from anything but a terminal has nobody to
# answer them. Once the deploy itself has succeeded, a prompt on a follow-up
# step is not a reason to sit forever, so answer no to all of them.
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

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
# Cloud Run is the beta/staging target. Three in-process bots fill an online
# search to four after the first real player arrives, but do not keep an idle
# instance awake. Override with STAGING_BOTS=0 for production behavior.
STAGING_BOTS="${STAGING_BOTS:-5}"

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
	--set-env-vars="TRUST_PROXY=1,METRICS_ADDR=,METRICS_TOKEN=$METRICS_TOKEN,DRAIN_TIMEOUT=8s,LOG_LEVEL=info,MIN_CLIENT_BUILD=${MIN_CLIENT_BUILD:-2},STAGING_BOTS=$STAGING_BOTS"

URL="$(gcloud run services describe "$SERVICE" --region="$REGION" --format='value(status.url)')"

step "budget alert"
# Cloud Run bills instance time, and every connected player holds a WebSocket
# open, which keeps the instance alive. Intermittent play stays inside the free
# tier; an instance up 24/7 is about $61/month, twenty times the VM. This is
# the tripwire for that, and for anything else unexpected.
BUDGET="${BUDGET_AMOUNT:-20}"
account="$(gcloud billing projects describe "$PROJECT" --format='value(billingAccountName)')"
# Why the reason is kept: swallowing stderr here hid a prompt the script then
# waited on, which looked exactly like a slow deploy.
budget_error="$(mktemp)"
trap 'rm -f "$budget_error"' EXIT
if gcloud billing budgets list --billing-account="${account#billingAccounts/}" \
	--filter="displayName=imposter-$PROJECT" --format='value(name)' 2>"$budget_error" | grep -q .; then
	echo "already set"
elif grep -q 'billingbudgets.googleapis.com' "$budget_error"; then
	# The tripwire may well exist already, set by hand in the console; the CLI
	# just cannot see it from here. Never a reason to fail a good deploy.
	echo "cannot check from here: the Cloud Billing Budget API is off for this project." >&2
	echo "Check or set it at https://console.cloud.google.com/billing/budgets" >&2
elif gcloud billing budgets create \
	--billing-account="${account#billingAccounts/}" \
	--display-name="imposter-$PROJECT" \
	--budget-amount="${BUDGET}ILS" \
	--filter-projects="projects/$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')" \
	--threshold-rule=percent=0.5 \
	--threshold-rule=percent=0.9 \
	--threshold-rule=percent=1.0 2>/dev/null; then
	echo "alerts at 50%, 90% and 100% of ${BUDGET} ILS"
else
	echo "could not create one (needs billing.budgets.create on the billing account)." >&2
	echo "Set it by hand: https://console.cloud.google.com/billing/budgets" >&2
fi

step "checking"
# /readyz, not /healthz: Google's frontend intercepts the path /healthz on
# Cloud Run and answers 404 itself, so the container never sees it. /readyz is
# the better check anyway — it reports whether the server will take new games.
curl -fsS "$URL/readyz" >/dev/null && echo "ready"

cat <<EOF

  server is public at $URL

  build the app against it:
    flutter build apk --dart-define=IMPOSTER_SERVER=$URL

  read the counters (save this token, it is not shown again):
    curl -H 'Authorization: Bearer $METRICS_TOKEN' $URL/metrics

  logs are already structured JSON in Cloud Logging:
    gcloud run services logs read $SERVICE --region=$REGION --limit=50

  watch the cost trigger — Cloud Run bills instance time, so once players keep
  it alive around the clock the VM (deploy/setup-gcp.sh) is both cheaper and
  better. Break-even is ~50 instance-hours/month:
    gcloud monitoring dashboards list  # or the Cloud Run console's "Instance time"

  redeploy: re-run this script. Games in flight end cleanly (no loss recorded).
  delete:   gcloud run services delete $SERVICE --region=$REGION

EOF
