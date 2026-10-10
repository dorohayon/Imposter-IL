#!/usr/bin/env bash
# Emails the operator when the game server stops answering. Safe to re-run:
# existing pieces are reused.
#
#   ./deploy/setup-uptime-alert.sh
#
# In October 2026 Cloud Run's spend cap switched the server off and nobody
# noticed for six days. An uptime check asks /readyz every five minutes from
# Google's regions; two failed rounds email EMAIL. The checks are requests
# like any other, a few milliseconds of CPU each, well inside the free tier.
set -euo pipefail
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

PROJECT="${PROJECT:-imposter-il-game}"
REGION="${REGION:-us-central1}"
SERVICE="${SERVICE:-imposter}"
EMAIL="${EMAIL:-imposteril36@gmail.com}"
NAME="Imposter IL — server not answering"
CHECK="Imposter IL readyz"

gcloud config set project "$PROJECT" >/dev/null
gcloud services enable monitoring.googleapis.com
gcloud components install alpha beta --quiet >/dev/null 2>&1 || true

host="$(gcloud run services describe "$SERVICE" --region="$REGION" --format='value(status.url)')"
host="${host#https://}"
[ -n "$host" ] || { echo "no URL for service $SERVICE" >&2; exit 1; }

# Same channel lookup as setup-moderation-alerts.sh: one email channel per address.
channel="$(gcloud beta monitoring channels list --format='value(name,labels.email_address)' 2>/dev/null |
	awk -v email="$EMAIL" '$2 == email { print $1; exit }')"
if [ -z "$channel" ]; then
	channel="$(gcloud beta monitoring channels create --type=email \
		--display-name="Imposter IL ($EMAIL)" \
		--channel-labels="email_address=$EMAIL" --format='value(name)')"
fi
case "$channel" in projects/*/notificationChannels/*) ;; *) echo "no notification channel: $channel" >&2; exit 1 ;; esac
echo "notification channel: $channel"

check="$(gcloud monitoring uptime list-configs --format='value(name,displayName)' 2>/dev/null |
	awk -F'\t' -v name="$CHECK" '$2 == name { print $1; exit }')"
if [ -z "$check" ]; then
	check="$(gcloud monitoring uptime create "$CHECK" --resource-type=uptime-url \
		--resource-labels="host=$host,project_id=$PROJECT" \
		--protocol=https --path=/readyz --period=5 --timeout=10 --format='value(name)')"
fi
case "$check" in projects/*/uptimeCheckConfigs/*) ;; *) echo "no uptime check: $check" >&2; exit 1 ;; esac
echo "uptime check: $check"

policy="$(mktemp)"
trap 'rm -f "$policy"' EXIT
python3 - "$policy" "$NAME" "${check##*/}" "$channel" <<'EOF'
import json, sys
path, name, check_id, channel = sys.argv[1:]
json.dump({
    "displayName": name,
    "documentation": {
        "mimeType": "text/markdown",
        "content": "The game server's /readyz has failed for 10 minutes. Check the Cloud Run "
                   "spend cap (Billing → Budgets) first, then the service's logs.",
    },
    "combiner": "OR",
    "conditions": [{
        "displayName": "readyz failing",
        "conditionThreshold": {
            "filter": 'metric.type="monitoring.googleapis.com/uptime_check/check_passed" '
                      f'AND resource.type="uptime_url" AND metric.label.check_id="{check_id}"',
            "aggregations": [{
                "alignmentPeriod": "600s",
                "perSeriesAligner": "ALIGN_NEXT_OLDER",
                "crossSeriesReducer": "REDUCE_COUNT_FALSE",
                "groupByFields": ["resource.label.*"],
            }],
            "comparison": "COMPARISON_GT",
            "thresholdValue": 1,
            "duration": "0s",
            "trigger": {"count": 1},
        },
    }],
    "alertStrategy": {"autoClose": "86400s"},
    "notificationChannels": [channel],
    "enabled": True,
}, open(path, "w"))
EOF
existing="$(gcloud alpha monitoring policies list --format='value(name,displayName)' 2>/dev/null |
	awk -F'\t' -v name="$NAME" '$2 == name { print $1; exit }')"
if [ -n "$existing" ]; then
	gcloud alpha monitoring policies update "$existing" --policy-from-file="$policy" --format='value(name)'
	echo "alert policy updated"
else
	gcloud alpha monitoring policies create --policy-from-file="$policy" --format='value(name)'
	echo "alert policy created"
fi

echo
echo "  $EMAIL is emailed when https://$host/readyz stops answering."
