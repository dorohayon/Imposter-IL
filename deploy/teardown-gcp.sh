#!/usr/bin/env bash
# Deletes everything setup-gcp.sh created, so it stops costing anything.
# The project itself is left alone unless DELETE_PROJECT=1.
set -euo pipefail

PROJECT="${PROJECT:-imposter-il-game}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"
INSTANCE="${INSTANCE:-imposter}"
REPO="${REPO:-imposter}"

echo "This deletes the VM, its reserved address, the firewall rules and the"
echo "container images in project $PROJECT. Games in progress are lost."
read -r -p "Type the project id to confirm: " confirm
[ "$confirm" = "$PROJECT" ] || { echo "aborted"; exit 1; }

gcloud config set project "$PROJECT" >/dev/null
gcloud compute instances delete "$INSTANCE" --zone="$ZONE" --quiet 2>/dev/null || true
# The address is the part that bills whether or not it is attached.
gcloud compute addresses delete "$INSTANCE" --region="$REGION" --quiet 2>/dev/null || true
gcloud compute firewall-rules delete "$INSTANCE-web" "$INSTANCE-ssh-iap" --quiet 2>/dev/null || true
gcloud artifacts repositories delete "$REPO" --location="$REGION" --quiet 2>/dev/null || true

if [ "${DELETE_PROJECT:-0}" = "1" ]; then
	gcloud projects delete "$PROJECT" --quiet
	echo "project scheduled for deletion (recoverable for 30 days)"
fi
echo "done. Check the console's billing page in a day to confirm it is at zero."
