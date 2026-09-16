# Deploying the server

Stage 0 of [`docs/production-architecture-review.md`](../docs/production-architecture-review.md):
one VM, all state in memory, no database. Google Cloud free tier.

The one property that decides the host: **the platform must not stop the
process on its own schedule.** Games live in RAM and need a drain window, so
Cloud Run, Lambda and App Runner are out. A plain VM is in.

## What this costs

An `e2-micro` in `us-central1` is on GCP's Always Free tier. The external IPv4
is not free (~$3/month), and free egress is 1 GB/month — about 500 games. Past
that, egress is ~$0.12/GB and becomes the largest line item.

Latency from Israel is ~120–150 ms. Irrelevant for 15-second turns, but it is
the price of the free tier: `me-west1` (Tel Aviv) is ~5–10 ms and not free.

## One-time setup

```sh
PROJECT=imposter-il           # your project id
ZONE=us-central1-a            # a free-tier zone: us-west1, us-central1, us-east1
DOMAIN=api.example.com        # a hostname you control

gcloud config set project "$PROJECT"
gcloud services enable compute.googleapis.com artifactregistry.googleapis.com

# Image registry.
gcloud artifacts repositories create imposter \
  --repository-format=docker --location=us-central1

# The VM. Container-Optimized OS already has Docker and is the smallest
# thing that boots with a container runtime.
gcloud compute instances create imposter \
  --zone="$ZONE" --machine-type=e2-micro \
  --image-family=cos-stable --image-project=cos-cloud \
  --boot-disk-size=10GB --boot-disk-type=pd-standard \
  --tags=http-server,https-server \
  --scopes=https://www.googleapis.com/auth/cloud-platform

gcloud compute firewall-rules create imposter-web \
  --allow=tcp:80,tcp:443 --target-tags=http-server,https-server

# Point DOMAIN's A record at this address, or Caddy cannot get a certificate.
gcloud compute instances describe imposter --zone="$ZONE" \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)'
```

Deploy credentials for CI: a service account that can push images and SSH.

```sh
gcloud iam service-accounts create deployer
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="serviceAccount:deployer@$PROJECT.iam.gserviceaccount.com" \
  --role=roles/artifactregistry.writer
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="serviceAccount:deployer@$PROJECT.iam.gserviceaccount.com" \
  --role=roles/compute.instanceAdmin.v1
gcloud iam service-accounts keys create key.json \
  --iam-account="deployer@$PROJECT.iam.gserviceaccount.com"
```

Put `key.json` in the `GCP_SA_KEY` GitHub secret, then delete it locally.
Also set the repository variables `GCP_PROJECT`, `GCP_ZONE` and
`IMPOSTER_DOMAIN`.

## Deploying

Push a tag. `.github/workflows/deploy.yml` builds the image, pushes it, and
restarts the VM's compose stack.

```sh
git tag -a server-v0.2.0 -m "server v0.2.0" && git push origin server-v0.2.0
```

By hand, from the VM:

```sh
gcloud compute ssh imposter --zone="$ZONE"
cd /var/imposter && sudo docker compose pull && sudo docker compose up -d
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

```sh
gcloud compute ssh imposter --zone="$ZONE" --command \
  'cd /var/imposter && sudo IMPOSTER_IMAGE=<older-image> docker compose up -d'
```

## Watching it

`/metrics` is bound to loopback and is never proxied — the counters say how
many games and players exist. Read it over SSH:

```sh
gcloud compute ssh imposter --zone="$ZONE" --command 'curl -s localhost:9090/metrics'
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

Logs are JSON on stdout: `sudo docker compose logs -f server`.

## Checklist before the first real deploy

- [ ] `DOMAIN` resolves to the VM, so Caddy can issue a certificate
- [ ] `curl https://$DOMAIN/healthz` returns `{"status":"ok"}`
- [ ] The app is built with `--dart-define=IMPOSTER_SERVER=https://$DOMAIN`
- [ ] `supportEmail` is set in `app/lib/screens/secondary_screens.dart`
- [ ] `blocked_words.txt` has been reviewed by the product owner
