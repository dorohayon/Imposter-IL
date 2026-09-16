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

You need: a GCP project with billing enabled (the free tier still requires a
billing account), and a hostname you control.

### 1. Project and registry

```sh
PROJECT=imposter-il           # your project id
ZONE=us-central1-a            # a free-tier zone: us-west1, us-central1, us-east1
REGION=us-central1
DOMAIN=api.example.com        # a hostname you control

gcloud config set project "$PROJECT"
gcloud services enable compute.googleapis.com artifactregistry.googleapis.com iap.googleapis.com

gcloud artifacts repositories create imposter \
  --repository-format=docker --location="$REGION"
```

### 2. The VM

Ubuntu LTS, not Container-Optimized OS: COS ships Docker but not the compose
plugin, and `provision.sh` installs both.

```sh
gcloud compute instances create imposter \
  --zone="$ZONE" --machine-type=e2-micro \
  --image-family=ubuntu-2404-lts-amd64 --image-project=ubuntu-os-cloud \
  --boot-disk-size=20GB --boot-disk-type=pd-standard \
  --tags=imposter \
  --scopes=https://www.googleapis.com/auth/cloud-platform
```

Firewall: web traffic from anywhere, SSH only through IAP (the
`35.235.240.0/20` range is Google's IAP forwarder, so port 22 is never open to
the internet).

```sh
gcloud compute firewall-rules create imposter-web \
  --allow=tcp:80,tcp:443 --target-tags=imposter
gcloud compute firewall-rules create imposter-ssh-iap \
  --allow=tcp:22 --source-ranges=35.235.240.0/20 --target-tags=imposter
```

Let the VM pull images:

```sh
NUMBER=$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="serviceAccount:$NUMBER-compute@developer.gserviceaccount.com" \
  --role=roles/artifactregistry.reader
```

### 3. DNS

Point `$DOMAIN`'s A record at the VM, and wait for it to resolve. Caddy cannot
get a certificate before this works.

```sh
gcloud compute instances describe imposter --zone="$ZONE" \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)'
dig +short "$DOMAIN"    # must return that address
```

### 4. Provision and configure the VM

```sh
gcloud compute ssh imposter --zone="$ZONE" --tunnel-through-iap \
  --command "bash -s" < deploy/provision.sh

# The compose stack and its settings.
gcloud compute ssh imposter --zone="$ZONE" --tunnel-through-iap \
  --command "sudo chown -R \$USER /var/imposter"
gcloud compute scp --zone="$ZONE" --tunnel-through-iap \
  deploy/docker-compose.yml deploy/Caddyfile imposter:/var/imposter/

# .env holds the domain and the image tag; compose reads it automatically.
sed -e "s|api.example.com|$DOMAIN|" \
    -e "s|PROJECT|$PROJECT|" deploy/env.example > /tmp/imposter.env
gcloud compute scp --zone="$ZONE" --tunnel-through-iap \
  /tmp/imposter.env imposter:/var/imposter/.env
```

### 5. First image, first start

```sh
gcloud auth configure-docker "$REGION-docker.pkg.dev" --quiet
docker build -t "$REGION-docker.pkg.dev/$PROJECT/imposter/server:first" server
docker push "$REGION-docker.pkg.dev/$PROJECT/imposter/server:first"

gcloud compute ssh imposter --zone="$ZONE" --tunnel-through-iap --command "
  sudo sed -i 's|^IMPOSTER_IMAGE=.*|IMPOSTER_IMAGE=$REGION-docker.pkg.dev/$PROJECT/imposter/server:first|' /var/imposter/.env
  sudo systemctl start imposter"

curl -s "https://$DOMAIN/healthz"     # {"status":"ok"} once Caddy has a cert
```

If `healthz` does not answer, the certificate is the usual cause:
`gcloud compute ssh imposter --zone=$ZONE --tunnel-through-iap --command 'sudo docker compose -f /var/imposter/docker-compose.yml logs caddy'`.

### 6. Point the app at it

```sh
flutter build apk --dart-define=IMPOSTER_SERVER=https://$DOMAIN
```

Without this the app uses `10.0.2.2:8080` / `localhost:8080`, which is the
local development server.

### 7. CI credentials

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

Put `key.json` in the `GCP_SA_KEY` GitHub secret, then delete it locally.
Set the repository variables `GCP_PROJECT`, `GCP_ZONE` and `IMPOSTER_DOMAIN`.

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

## Checklist before the first real deploy

- [ ] `DOMAIN` resolves to the VM, so Caddy can issue a certificate
- [ ] `curl https://$DOMAIN/healthz` returns `{"status":"ok"}`
- [ ] The app is built with `--dart-define=IMPOSTER_SERVER=https://$DOMAIN`
- [ ] `supportEmail` is set in `app/lib/screens/secondary_screens.dart`
- [ ] `blocked_words.txt` has been reviewed by the product owner
