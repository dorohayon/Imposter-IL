#!/usr/bin/env bash
# Emails the operator when a player reports what another player wrote
# (docs/moderation.md). Safe to re-run: existing pieces are reused.
#
#   ./deploy/setup-moderation-alerts.sh
#
# A log-match alert on the server's "player reported" line: Cloud Monitoring
# sends the matching log entry — the clue, the nickname, how many players
# reported — at most once every five minutes. No metric, no database.
set -euo pipefail
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

PROJECT="${PROJECT:-imposter-il-game}"
SERVICE="${SERVICE:-imposter}"
EMAIL="${EMAIL:-imposteril36@gmail.com}"
NAME="Imposter IL — player reports"
# Must match reportLogMessage in server/internal/api/moderation.go.
FILTER="resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"$SERVICE\" AND jsonPayload.msg=\"player reported\""

gcloud config set project "$PROJECT" >/dev/null
gcloud services enable monitoring.googleapis.com logging.googleapis.com
# The monitoring commands live in gcloud's alpha and beta components; install
# them first, so their installer's chatter never lands in a captured value.
gcloud components install alpha beta --quiet >/dev/null 2>&1 || true

channel="$(gcloud beta monitoring channels list --format='value(name,labels.email_address)' 2>/dev/null |
	awk -v email="$EMAIL" '$2 == email { print $1; exit }')"
if [ -z "$channel" ]; then
	channel="$(gcloud beta monitoring channels create --type=email \
		--display-name="Imposter IL moderation ($EMAIL)" \
		--channel-labels="email_address=$EMAIL" --format='value(name)')"
fi
case "$channel" in projects/*/notificationChannels/*) ;; *) echo "no notification channel: $channel" >&2; exit 1 ;; esac
echo "notification channel: $channel"

if gcloud alpha monitoring policies list --format='value(displayName)' 2>/dev/null | grep -qxF "$NAME"; then
	echo "alert policy already exists"
else
	policy="$(mktemp)"
	trap 'rm -f "$policy"' EXIT
	python3 - "$policy" "$NAME" "$FILTER" "$channel" <<'EOF'
import json, sys
path, name, log_filter, channel = sys.argv[1:]
json.dump({
    "displayName": name,
    "documentation": {
        "mimeType": "text/markdown",
        "content": "A player reported a clue or nickname. Review it within 24 hours "
                   "(docs/moderation.md): read `hint` and `nickname` in the log entry, "
                   "and add what the blocklist missed to "
                   "server/internal/content/blocked_words.txt, then deploy.",
    },
    "combiner": "OR",
    "conditions": [{
        "displayName": "player reported",
        "conditionMatchedLog": {"filter": log_filter},
    }],
    "alertStrategy": {"notificationRateLimit": {"period": "300s"}, "autoClose": "86400s"},
    "notificationChannels": [channel],
}, open(path, "w"))
EOF
	gcloud alpha monitoring policies create --policy-from-file="$policy" --format='value(name)'
fi

cat <<EOF

  reports are emailed to $EMAIL (at most one email per five minutes).

  all reports of the last week:
    gcloud logging read '$FILTER' --freshness=7d \\
      --format='table(timestamp, jsonPayload.nickname, jsonPayload.hint, jsonPayload.reporters, jsonPayload.hiddenForAll)'
EOF
