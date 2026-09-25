# Deploying the server

Stage 0 of [`docs/production-architecture-review.md`](../docs/production-architecture-review.md):
one VM, all state in memory, no database. Google Cloud free tier.

The one property that decides the host: **the platform must not stop the
process on its own schedule.** Games live in RAM and need a drain window, so
Cloud Run, Lambda and App Runner are out. A plain VM is in.

## A Cloud Run quirk worth knowing

Google's frontend intercepts the path **`/healthz`** on Cloud Run and answers
404 itself; the container never sees the request. Everything else works
normally. Use `/readyz` there — it is the better check anyway, since it reports
whether the server is willing to take new games rather than merely alive.

On the VM there is no such interception and `/healthz` is what Caddy polls.

## Which of the three

| | When | Cost |
| --- | --- | --- |
| `dev-tunnel.sh` | Testing on your own phones, today | **$0** |
| `setup-cloudrun.sh` | Beta and soft launch — up without your laptop | **$0** within the free tier |
| `setup-gcp.sh` | Once losing a game to a deploy is unacceptable | ~$2.90/month |

Same container image in all three. Moving between them is a different deploy
script, not a code change.

Both setups default to `STAGING_BOTS=0`. For a testers-only beta, run the
Cloud Run script with `STAGING_BOTS=5`: once a real player searches, the
server fills the group to four with clearly named bots and runs their turns.
They disappear when no real players remain, so they do not prevent scale to
zero. Never leave it on once strangers can install the app.

Cloud Run's one real cost: it decides when to stop the instance and gives it
about ten seconds, so a deploy or a scale-down ends the games in flight. They
end *cleanly* — players see the server-error screen and no loss is recorded —
but they end. The VM drains properly instead, which is the whole reason it is
worth $2.90 later.

## Before you pay for anything: dev-tunnel.sh

```sh
./deploy/dev-tunnel.sh
```

Runs the server on your machine and puts it on a public HTTPS address through
ngrok, so real phones on cellular can play against it. Costs nothing, needs no
cloud account, and is the right tool for device testing — which is what is
actually left before launch.

Deploy to GCE when the game needs to be up while your laptop is not: a closed
beta, or the store release itself. Not before.

The address changes every run, so rebuild the app against whatever it prints.

## What this costs

| | |
| --- | --- |
| `e2-micro` VM in `us-central1` | **$0** — Always Free, indefinitely |
| 20 GB standard disk | **$0** — 30 GB is Always Free |
| Artifact Registry | **$0** — 0.5 GB free, the image is 8.4 MB |
| First 1 GB/month egress | **$0** |
| **External IPv4** | **~$2.90/month** |
| Egress past 1 GB | ~$0.12/GB, at roughly 2 MB per game |

The VM really is free. The address is not: since February 2024 Google bills
every external IPv4, including one attached to a free-tier instance, and a
server nobody can reach is not a server. There is no way around it — an
IPv6-only VM would be free and unreachable from IPv4-only mobile networks.

So **~$2.90/month idle**, rising with egress once people play.
`./deploy/teardown-gcp.sh` takes it back to zero.

Latency from Israel is ~120–150 ms. Irrelevant for 15-second turns, but it is
the price of the free tier: `me-west1` (Tel Aviv) is ~5–10 ms and not free.

## Verified locally

The compose stack was run end to end before any of this was deployed: Caddy
terminating TLS, REST and a full game over `wss://` through the proxy, the
game port unreachable from outside, `/metrics` reachable only on loopback and
404 through Caddy, and the drain holding the container open until live games
finished. What has *not* been exercised is the GCP side — the `gcloud` calls
in `setup-gcp.sh` are written from the docs, not yet run against a project.

## One-time setup

```sh
./deploy/setup-gcp.sh
```

That is the whole thing: project, billing link, APIs, image registry, reserved
address, firewall, VM, Docker, the compose stack, the first image, and a wait
until `https://<host>/healthz` answers. It is idempotent — re-run it after a
failure. `./deploy/teardown-gcp.sh` deletes everything it made.

Defaults are the free-tier choices; override any of them:

| Variable | Default | |
| --- | --- | --- |
| `PROJECT` | `imposter-il-game` | Created if missing |
| `REGION` / `ZONE` | `us-central1` / `us-central1-a` | A free-tier region |
| `DOMAIN` | derived from the IP | See below |
| `BILLING_ACCOUNT` | your first open one | |

### The hostname

With no domain, the script derives one from the VM's reserved address using
**sslip.io**: `34-72-1-5.sslip.io` resolves to `34.72.1.5`. No registrar, no A
record, and Let's Encrypt issues for it normally. The address is *reserved*
rather than ephemeral precisely because the hostname is baked into app builds.

To use your own domain, point its A record at the VM and pass it:

```sh
DOMAIN=api.example.com ./deploy/setup-gcp.sh
```

The script waits for the certificate; if DNS has not propagated it will time
out and tell you to read Caddy's log.

### Then build the app against it

```sh
flutter build apk --dart-define=IMPOSTER_SERVER=https://<the host it printed>
```

Without this the app talks to `10.0.2.2:8080` / `localhost:8080`, the local
development server.

### CI credentials (only needed for tag-triggered deploys)

```sh
gcloud iam service-accounts create deployer
for role in artifactregistry.writer compute.instanceAdmin.v1 iap.tunnelResourceAccessor; do
  gcloud projects add-iam-policy-binding "$PROJECT" \
    --member="serviceAccount:deployer@$PROJECT.iam.gserviceaccount.com" \
    --role="roles/$role"
done
gcloud iam service-accounts keys create key.json \
  --iam-account="deployer@$PROJECT.iam.gserviceaccount.com"
```

Put `key.json` in the `GCP_SA_KEY` GitHub secret, then delete it locally. Set
the repository variables `GCP_PROJECT`, `GCP_ZONE` and `IMPOSTER_DOMAIN`.

## Deploying

Push a tag. `.github/workflows/deploy.yml` builds the image, pushes it, and
restarts the VM's compose stack.

```sh
git tag -a server-v0.2.0 -m "server v0.2.0" && git push origin server-v0.2.0
```

By hand, from the VM:

```sh
gcloud compute ssh imposter --zone="$ZONE" --tunnel-through-iap --command "
  sudo sed -i 's|^IMPOSTER_IMAGE=.*|IMPOSTER_IMAGE=<image>|' /var/imposter/.env
  cd /var/imposter && sudo docker compose pull && sudo docker compose up -d"
```

### What a deploy costs players

With one instance there is a window. On SIGTERM the server stops accepting new
rooms, searches and games (`503 server_draining`) and waits up to
`DRAIN_TIMEOUT` for the games in progress to finish, so **nobody is dropped
mid-game** — but for that window nobody can start one either.

Removing the window needs a second instance to route to, which is Stage 1 in
the review. Until then, deploy when few people are playing:

```sh
curl -s http://localhost:9090/metrics | grep imposter_games_active
```

## Rollback

Images are tagged with the commit SHA, so rolling back is redeploying an
older one:

Or re-run the deploy workflow with `image_tag` set to an older commit SHA.

```sh
gcloud compute ssh imposter --zone="$ZONE" --tunnel-through-iap --command "
  sudo sed -i 's|^IMPOSTER_IMAGE=.*|IMPOSTER_IMAGE=<older-image>|' /var/imposter/.env
  cd /var/imposter && sudo docker compose up -d"
```

## Watching it

`/metrics` is bound to loopback and is never proxied — the counters say how
many games and players exist. Read it over SSH:

```sh
gcloud compute ssh imposter --zone="$ZONE" --tunnel-through-iap \
  --command 'curl -s localhost:9090/metrics'
```

Worth alerting on, in rough order of how much they hurt:

| Metric | Why |
| --- | --- |
| `imposter_panics_total` rising | A room is being aborted; a bug is live |
| `imposter_heap_bytes` climbing and not falling | The reaper is not keeping up |
| `imposter_games_aborted_total` rising | Players are losing games to server errors |
| `imposter_rate_limited_total` spiking | Abuse, or a limit set too tight |
| `imposter_commands_total{result="internal_error"}` | Anything unexpected |
| `imposter_ws_connections` at zero during the day | Nobody can connect |
| `imposter_publish_seconds_sum / imposter_publish_total` | The single-lock ceiling; see R6 |

Logs are JSON on stdout: `sudo docker compose -f /var/imposter/docker-compose.yml logs -f server`.

## Monetization settings

The pricing model is server configuration, so it changes without an app
release (`docs/monetization.md`). On Cloud Run, a JSON value needs a delimiter
other than the comma, and the Play key belongs in Secret Manager:

```sh
gcloud run services update imposter --region us-central1 \
  --update-env-vars='^@^MONETIZATION_CONFIG={"freeCategoryIds":["food","animals","places"]}'
gcloud run services update imposter --region us-central1 \
  --update-env-vars=APPLE_BUNDLE_ID=com.imposteril.app,GOOGLE_PLAY_PACKAGE=com.imposteril.app \
  --set-secrets=GOOGLE_PLAY_SERVICE_ACCOUNT=play-verifier:latest
```

A config that does not parse, or names a key the server does not know, stops
the server at startup instead of running on defaults. Turn on
`serverEnforcement` only with both verifiers set and `MIN_CLIENT_BUILD=4`.

## Production today: Cloud Run

Production runs on Cloud Run, deployed with `./deploy/setup-cloudrun.sh`. The
script replaces every environment variable, so pass the current ones through:
`METRICS_TOKEN` (read it from `gcloud run services describe imposter`),
`STAGING_BOTS` and `MIN_CLIENT_BUILD`.

`.github/workflows/deploy.yml` (a `server-v*` tag) is the VM path from
`setup-gcp.sh`. It needs a `GCP_SA_KEY` secret this repository does not have, so
it deploys nothing until the VM path is adopted.

## Moderation alerts

`./deploy/setup-moderation-alerts.sh` emails `imposteril36@gmail.com` whenever a
player is reported (docs/moderation.md). It is safe to re-run.

## Checklist before the first real deploy

- [ ] `DOMAIN` resolves to the VM, so Caddy can issue a certificate
- [ ] `curl https://$DOMAIN/healthz` returns `{"status":"ok"}`
- [ ] The app is built with `--dart-define=IMPOSTER_SERVER=https://$DOMAIN`
- [ ] `supportEmail` is set in `app/lib/screens/secondary_screens.dart`
- [ ] `blocked_words.txt` has been reviewed by the product owner
