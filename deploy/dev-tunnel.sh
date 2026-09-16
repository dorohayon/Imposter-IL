#!/usr/bin/env bash
# Runs the server on this machine and puts it on a public HTTPS address, so
# real phones on cellular can play against it. Costs nothing and needs no
# cloud: use this for device testing, and deploy/setup-gcp.sh only once the
# game needs to be up when your laptop is not.
#
#   ./deploy/dev-tunnel.sh
#
# The address changes every run (ngrok's free tier), so the app has to be
# rebuilt against whatever it prints.
set -euo pipefail

PORT="${PORT:-8080}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

command -v ngrok >/dev/null || { echo "ngrok is not installed: brew install ngrok" >&2; exit 1; }

cleanup() { kill "${server_pid:-}" "${ngrok_pid:-}" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

echo "==> building"
go build -C "$root/server" -o /tmp/imposter-dev ./cmd/server

echo "==> starting the server on :$PORT"
# Limits stay on: this is a real server on the public internet, and the point
# of testing is to hit what players will hit.
PORT="$PORT" METRICS_ADDR=127.0.0.1:9090 LOG_LEVEL=info /tmp/imposter-dev &
server_pid=$!

until curl -sf "http://localhost:$PORT/healthz" >/dev/null 2>&1; do sleep 1; done

echo "==> opening the tunnel"
ngrok http "$PORT" --log=stdout >/tmp/imposter-ngrok.log 2>&1 &
ngrok_pid=$!

url=""
for _ in $(seq 1 30); do
	url="$(curl -s http://localhost:4040/api/tunnels 2>/dev/null |
		python3 -c 'import sys,json; print(next((t["public_url"] for t in json.load(sys.stdin)["tunnels"] if t["public_url"].startswith("https")), ""))' 2>/dev/null || true)"
	[ -n "$url" ] && break
	sleep 1
done
[ -n "$url" ] || { echo "ngrok did not report a URL; see /tmp/imposter-ngrok.log" >&2; exit 1; }

curl -fsS "$url/healthz" >/dev/null || { echo "the tunnel is up but the server did not answer through it" >&2; exit 1; }

cat <<EOF

  server is public at $url

  build the app against it:
    flutter build apk --dart-define=IMPOSTER_SERVER=$url
    flutter run --dart-define=IMPOSTER_SERVER=$url

  metrics (this machine only):
    curl -s localhost:9090/metrics

  Ctrl-C stops both. The address changes next run.

EOF
wait "$server_pid"
