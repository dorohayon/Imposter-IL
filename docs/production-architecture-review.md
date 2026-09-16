# Production Architecture Review — מי המתחזה?

Reviewed at `94b19fd` (main). Scope: Flutter app, Go server, realtime protocol, matchmaking,
state, persistence, infra, CI/CD, security, observability, testing, store readiness.

This document is a review and a plan. It changes no code and no product rule.
Where it disagrees with an approved decision, it says so explicitly in
[§7 Decisions I am challenging](#7-decisions-i-am-challenging) — those are product owner calls, not mine.

---

## 1. Current architecture assessment

### What exists

| Layer | State |
| --- | --- |
| Client | Flutter 3.44, `dart:io` only (no `http`/`dio`/`web_socket_channel`), `ChangeNotifier` + `InheritedNotifier`, no state-management dep |
| Transport | REST `/v1/*` for identity and room entry; one WebSocket per session for everything live |
| Server | Single Go binary, `net/http` + `github.com/coder/websocket` — one non-stdlib dependency total |
| Game state | Pure state machines in `internal/game` and `internal/room`, clock and RNG injected, no I/O |
| Persistence | **None.** Everything in process memory. Wins/losses in `shared_preferences` on device |
| Infra | None. No Dockerfile, no IaC, no deploy target chosen |
| CI | Go: gofmt, vet, golangci-lint, `go test -race`. Flutter: analyze, format, test on two SDK versions, Android+iOS builds, and an end-to-end job that plays real games against a real server binary |

### What is genuinely good — do not redesign this

These are the load-bearing decisions, and they are right. Most projects at this stage have
none of them.

1. **The engine is pure.** `internal/game/game.go` and `internal/room/room.go` take `now
   time.Time` and a `*rand.Rand` as arguments and do no I/O. This single property is what
   makes the entire scaling plan in §3 cheap: every transport, sharding and persistence change
   below leaves these two files untouched. It also makes the 700 lines of table-driven tests
   possible without mocks.

2. **Server-authoritative, with per-player filtering at the boundary.** The client sends
   intents and renders snapshots; it computes no rule and no timer. Filtering happens in
   `Game.View(playerID)`, so the impostor's client never receives the secret word — it is not
   hidden in the UI, it is absent from the wire. Correct by construction.

3. **Monotonic `stateVersion` per room, shared across `room.state` and `game.state`.** Late or
   reordered snapshots are dropped by the client (`GameSession._isNewer`). This is the correct
   answer to mobile networks and it is already implemented on both sides.

4. **"Timers before commands."** Every command applies expired deadlines first, so a hint that
   left the phone in time but arrived late is rejected *and* the state it should have advanced
   is advanced. The `sync`/`published` mark in `internal/api/ws.go` republishes even when the
   command itself failed. This is subtle and most implementations get it wrong.

5. **Idempotency by message id** with a bounded per-session reply cache (100 entries / 5 min).
   Double-tap and network retry cannot double-send a hint or a vote. Belt and braces: the
   engine independently rejects a second hint in a turn.

6. **Online matches are private rooms.** `internal/api/matchmaking.go` models a forming match
   as a public `room.Room` with no code and no host commands. Disconnects, removals, snapshots
   and lifecycle are therefore one code path instead of two. Excellent reuse.

7. **Protocol versioning is designed, not improvised.** `v` major in the envelope, additive
   changes don't bump, breaking changes bump `v` and the REST path. The client already ignores
   unknown fields and message types.

8. **The end-to-end CI job.** Four Flutter clients playing a full private game and a full
   online match against a compiled server, on every PR. This is a better safety net than most
   production multiplayer projects have.

### What is missing

Everything between "works on my laptop" and "runs unattended with real users on it":
persistence, process lifecycle, resource bounds, rate limiting, observability, deployment, and
store identity. These are listed as risks below.

---

## 2. Production and scaling risks

Ranked by expected damage. Each states the problem and why it matters here specifically.

### R1 — A deploy kills every game in flight · **blocker**

`main.go` does a 10-second `srv.Shutdown`. All sessions, rooms and games are in the process.
Restarting the binary means every player in every game gets `session_not_found`, screen 29, and
a brand new `playerId`.

Why it matters: a game lasts roughly 3–5 minutes. With no drain you cannot ship a fix during
waking hours, which means you will ship fixes at 03:00, which means you will ship bad fixes.
This is the single biggest day-to-day operational constraint of an in-memory design, and it is
solvable without persistence (see §3, Stage 0).

### R2 — One panic takes down every game on the box · **blocker**

There is no `recover()` anywhere in the server. `net/http` shields handler panics, but the two
places that actually run game logic are not handlers:

- `time.AfterFunc` in `Server.schedule` ([`ws.go`](../server/internal/api/ws.go)) — a panic in
  `tickRoom` → `room.Tick` → the engine crashes the process.
- `writeLoop` / `pingLoop` goroutines.

Why it matters: in a stateless service a panic costs one request. Here it costs every concurrent
game on the instance, plus everyone's session. A single unhandled nil in an edge case that the
tests did not reach becomes a total outage. The fix is three `defer recover()` blocks plus a
counter, not an architecture change.

### R3 — Unbounded memory growth, reachable by an unauthenticated stranger · **blocker**

Nothing is ever deleted:

- `s.sessions` and `s.players` grow forever. No TTL, no GC (grep for `delete(s.sessions` — no hits).
- Each session's `replyCache` retains up to 100 marshalled messages, and the TTL is only
  enforced on `put` — an idle session keeps its cache forever.
- `sess.game`, `sess.gameRoom` pin finished `*game.Game` objects (hints, votes, results) after
  the game ends.
- Empty private rooms are never closed — flagged in the code as an open decision
  (`ponytail: empty rooms are kept`) and in `docs/open-decisions.md`.

`POST /v1/sessions` needs no authentication and no proof of anything. A one-line `curl` loop
creates sessions at line rate, each allocating a session + reply cache that is never freed.

Why it matters: this is an OOM kill with no attacker skill required, and given R1/R2 an OOM kill
is a full outage. Even with no attacker, organic churn leaks: every reinstall, every server-side
session replacement in `GameSession._replaceLostSession` creates a session that lives forever.

### R4 — No rate limiting at all · **blocker**

`docs/protocol.md` defines a `rate_limited` error code. It is not implemented anywhere. Concretely:

- Session creation: unlimited (see R3).
- `POST /v1/rooms/join`: room codes are 6 digits — a 10⁶ space. An attacker can enumerate the
  whole space in minutes and join arbitrary strangers' private rooms. Private rooms are the
  "play with my kids" feature; this is the one place where an intrusion is genuinely upsetting.
- `game.react` is unlimited **by product decision** ("אפשר להגיב ללא הגבלה"). Unlimited means a
  client can emit reactions as fast as it can write, and each one fans out `game.reaction` **and
  a full `publish`** to 8 players, under the global lock. This is an amplification primitive —
  and a **billing** one: ~21 KB of egress per reaction, so a single client at ~100/s sustains
  ~2 MB/s ≈ 5 TB/month ≈ **$100/mo on Fly or $600/mo on GCP, from one connection**. The rate
  limiter pays for itself directly.
- WebSocket connections: no per-IP cap.

Why it matters: the product intentionally has no accounts, so there is no identity to ban. Rate
limits are the *only* abuse control available. Without them the first bored teenager on a Discord
server is a production incident.

### R5 — Matchmaking is process-local: the hard scaling wall · **architectural**

`s.publicRooms` is a slice in one process. The moment a second instance runs, two players who
tap "חפש משחק" at the same moment land on different instances and never see each other. The
practical effect: matchmaking quality degrades by the number of instances, exactly at the moment
traffic justifies a second instance.

Why it matters: this is *the* thing that forces horizontal scaling to be designed before it is
needed, because the failure is silent and product-visible ("nobody is ever online") rather than
a crash. It is also the reason §3 puts room-affinity routing before anything else.

### R6 — One global mutex, with JSON marshalling inside it · **measured; no action needed yet**

`Server.mu` covers every session, room, game, timer and snapshot. `publish` → `publishGame`
marshals one filtered `game.state` **per player** while holding it.

**Measured** with `server/cmd/loadbot`, 240 simulated players for 60 s on one laptop core:

| | |
| --- | --- |
| Concurrent players / games | 240 / 30 |
| Command latency | p50 2.1 ms, p95 11.2 ms, p99 14.4 ms, max 19.3 ms |
| Publishes | 9,973 — mean **143 µs** each |
| Total time holding the lock | 1.43 s of 60 s = **2.4 % of one core** |
| Heap | 10.4 MB, ≈ 43 KB per connected player |
| Panics, goroutine leaks | none; goroutines returned to baseline after disconnect |

Extrapolating the lock alone: 30 games cost 2.4 % of a core, so publish contention only
becomes the bottleneck somewhere near a thousand concurrent games per core. Memory is not the
binding constraint either — 43 KB per player means a 1 GB instance runs out of CPU long before
RAM.

Why it matters: it now demonstrably does not, at any traffic this game will see at launch. The
escape hatch stays documented in the code ("ponytail: one lock for everything … move each room
into its own actor goroutine"); do not take it until production metrics say so.

Two things the harness found, both in the harness rather than the server: a client that writes
from its read loop gets dropped by the server's slow-consumer guard (correct behaviour), and
reacting to every snapshot rather than once per hint is a feedback loop — a reaction publishes a
snapshot, which prompts another reaction. The second is worth remembering as a shape of abuse
the reaction rate limit has to cover.

### R7 — Zero observability · **blocker**

One `log.Printf("listening on %s")`. No structured logs, no request/trace id, no metrics
endpoint, no error aggregation, no client crash reporting (no Sentry / Crashlytics in
`app/pubspec.yaml`).

Why it matters: with in-memory state and no logs, a report of "the game froze" is
unfalsifiable and uninvestigable — the evidence died with the process. You cannot run this
service without knowing concurrent games, WS connections, command error-code rates, publish
latency and goroutine count. This is not "nice for later"; it is how you find R2 and R3 before
users do.

### R8 — No minimum-client-version gate · **blocker for the store specifically**

Once a build is on the App Store it exists forever; users on iOS routinely run year-old
versions. The protocol is well versioned but there is no mechanism to *refuse* an old client or
to tell it to update — and nothing tells the server which app version is talking to it.

Why it matters: the day you need to bump `v` to 2, every un-upgraded install becomes a crash
loop or a silently broken game, with no way to show "עדכנו את האפליקציה". Adding a version
header and a `minClientVersion` in `session.state` costs an hour now and is impossible to
retrofit later — old clients don't know to look for it.

### R9 — User-generated content with no filtering, reporting or blocking · **store rejection risk**

Hints are free text shown to up to 7 strangers. Nicknames are free text shown to strangers.
Approved product decisions: no inappropriate-content blocking (`content.Policy()` returns
`func(string) bool { return false }`), no reporting, no blocking, no accounts.

App Store Review Guideline 1.2 (User-Generated Content) requires apps with UGC to have: a
filtering method for objectionable material, a mechanism to report offensive content, the
ability to block abusive users, and published developer contact information. Google Play's
UGC policy is materially the same. One-word Hebrew hints typed by a stranger and shown to a
child are squarely in scope.

Why it matters: this is the most likely cause of a rejection, and rejections cost review cycles
(days each). See §7 for the minimum compliant design that preserves the "no chat, no reports"
product intent.

### R10 — Orientation is unlocked but the design is portrait-only · **polish, cheap**

`Info.plist` allows `LandscapeLeft`/`LandscapeRight` on iPhone; the Android manifest sets
`configChanges` for orientation but no `screenOrientation`. All 29 designed screens are
390×844 portrait. Rotating the phone mid-game produces unreviewed layouts.

### R11 — `game.aborted` is specified but not implemented

`docs/protocol.md` defines it; grep finds no `aborted` in the server. Screen 29 is currently
only reachable via `401 session_not_found` on reconnect. So a server-side abort that is *not* a
full restart (R2's recover path, a drain, a corrupt room) has no way to tell players "תקלה
בשרת, לא נרשם הפסד". Implementing R2's recover without this leaves players staring at a frozen
timer.

### R12 — Identity is a device-local token, with no recovery

`sessionToken` lives in `shared_preferences`; wins/losses live on the device. Reinstall, device
change or a server restart = new player, stats gone. This is a coherent consequence of the
"no accounts" decision and I am **not** recommending accounts for the MVP. Flag it as a known
product property and make sure support/store copy does not promise otherwise.

### R13 — Cleartext transport is enabled in debug only (this one is already right)

`usesCleartextTraffic` is in the debug manifest only; iOS uses `NSAllowsLocalNetworking`, not
`NSAllowsArbitraryLoads`. Release builds will refuse plain HTTP. Verify once against the real
release build (§4) and then stop worrying about it.

---

## 3. Recommended target architecture

**Principle: the engine never changes. Everything below is transport and routing.**

The three stages are separated by a trigger, not by a date. Do not enter a stage before its
trigger fires.

### Stage 0 — Launch: one process, no database

```
        iOS / Android
              │  HTTPS + WSS
              ▼
   ┌──────────────────────┐
   │  TLS + HTTP/2 edge   │   (managed by the host)
   └──────────┬───────────┘
              ▼
   ┌──────────────────────┐
   │   imposter-server    │   one instance, all state in RAM
   │  sessions │ rooms    │   + drain, GC, limits, metrics
   └──────────────────────┘
              │
              ▼  logs / metrics / traces → hosted backend
```

**Explicitly not included: no PostgreSQL, no Redis, no message bus, no Kubernetes.** There is
nothing durable to store — stats are on the device by decision, and an in-flight game is
worthless after a restart anyway. Adding a database now buys nothing and costs a schema, a
migration story, a backup story and a second failure mode.

What Stage 0 must add to today's code:

| Addition | Solves |
| --- | --- |
| Graceful drain: `/readyz` flips false → stop new matches and room creation → wait for in-flight games (cap ~10 min) → exit | R1 |
| `recover()` in the timer callback, read loop and write loop; on recover, end the room's game with `game.aborted{reason:"server_error", lossRecorded:false}` | R2, R11 |
| Reaper goroutine: sessions idle > 24 h, empty rooms > 30 min, finished-game references on `game.leave` | R3 |
| Per-IP token buckets on `POST /v1/sessions` and `/v1/rooms/join`; per-session bucket on WS commands with a cheap allowance for `game.react` | R4 |
| Structured `log/slog` JSON with `playerId`/`roomId`/`gameId`; `/metrics` (Prometheus text format, stdlib-friendly) with games, connections, command error codes, publish latency, goroutines | R7 |
| `X-Client-Version` from the app; `minClientVersion` in `session.state` | R8 |
| Crash reporting in the app (Sentry or Crashlytics — one dependency) | R7 |

**Hosting.** The requirement that decides it: long-lived WebSockets on an instance whose
*identity matters* (state is in RAM), with cheap TLS and a controllable drain.

**The property that matters is a behaviour, not a vendor: does the platform decide on its own
when to stop the process?** Games live in RAM, so a runtime that reclaims instances on its own
schedule with a ~10-second SIGTERM grace ends games in flight.

That is a **cost, not a disqualification**, and an earlier draft of this document was wrong to
state it as one. With `game.aborted` implemented, an instance that disappears is handled
correctly: players see the server-error screen and **no loss is recorded**. So the question is
only how often it happens and whether that is tolerable at the current stage.

| | Cloud Run | VM (Compute Engine) |
| --- | --- | --- |
| Cost at low traffic | **$0** — no external IPv4 to bill | ~$2.90/month for the address |
| HTTPS | included, no domain needed | Caddy + a hostname |
| Games survive a deploy | no — ~10 s grace | yes — full drain |
| Instances | must be capped at 1 | 1, addressable at Stage 1 |
| Operational surface | none | a box to patch |

So: **Cloud Run for beta and soft launch**, where free and zero-maintenance beats losing the
occasional game to a deploy. **Move to the VM when losing games to a deploy stops being
acceptable** — same container image, a different deploy script, no code change.

Measured on the deployed service (`imposter-il-game`, us-central1), 16 simulated players from
Israel: **16 games played to completion, p50 158 ms, p99 320 ms, 0 panics, 0 aborts, 1.6 MB
heap.** The latency is the Israel↔Iowa round trip, not the server — it spent 0.42 s of lock time
across 780 publishes (538 µs each including TLS and the proxy hop).

Three Cloud Run specifics that decide whether it works at all:

- `--max-instances=1` is **mandatory**. Every session, room and game is in one process's memory
  and matchmaking is a slice in it, so a second instance means two players searching at the same
  moment never meet (R5). Cloud Run's cookie-based session affinity does not fix this for a
  mobile client opening a raw WebSocket with a Bearer header — it is the same Stage 1 problem.
- CPU throttling outside request handling would freeze the game's `time.AfterFunc` timers.
  **Open WebSockets count as in-flight requests**, so CPU stays allocated whenever any player is
  connected, which is the only time the timers matter.
- Google's frontend **intercepts the path `/healthz`** and answers 404 before the container sees
  it. Health checks there must use `/readyz`.

**Cost shape is the opposite of the VM's**, and this is the real reason to move later: Cloud Run
bills instance time, and every connected player holds a WebSocket that keeps the instance alive.
Intermittent play is free; an instance up around the clock is ~$61/month against the VM's flat
$2.90. Break-even is about **50 instance-hours per month** — that, or the first deploy that kills
games you cannot afford to lose, is the trigger to run `deploy/setup-gcp.sh` instead.

Lambda and App Runner remain unsuitable: neither holds long-lived WebSockets the way this needs.

Three options, in the order they become right:

- **Cloud Run** (`us-central1`), while the game is in beta: free within the Always Free tier,
  no VM, no address to pay for, HTTPS and a hostname supplied. `deploy/setup-cloudrun.sh`.
- **Fly.io**, single region (`fra`/`cdg`; ~60–80 ms RTT, gameplay-irrelevant for 15-second turns).
  Managed TLS, first-class WebSockets, rolling deploys from one config file, and `fly-replay`
  gives you Stage 1's room→instance routing as an HTTP header instead of a router you build.
  ~$5–15/month at launch. This is the default recommendation *because of `fly-replay`* — it
  removes the most annoying part of Stage 1.
- **One VM + Caddy**, on GCE (`me-west1`, Tel Aviv — the only option here with an Israeli region,
  ~5–10 ms), Hetzner or EC2. Equivalent Stage 0, full control, ~$15–25/month; you write the
  room-affinity router yourself when the Stage 1 trigger fires. Choose this if you already have
  GCP credits or familiarity, or want Tel Aviv latency.

**Avoid:** Lambda and App Runner (above). GKE and similar are not wrong, just a control-plane
fee and a learning curve to run one stateful process.

#### Cost

Verify against current pricing pages before committing; the shape is stable, the digits drift.

| | Fly.io | GCE `me-west1` (Tel Aviv) |
| --- | --- | --- |
| Compute | shared-cpu-1x / 1 GB ~$5.70 | e2-small (2 GB) ~$14 |
| External IPv4 | $0 shared / $2 dedicated | ~$3 (GCP bills all external IPv4) |
| Disk | — | 10 GB balanced ~$1 |
| TLS / LB | included | free with Caddy on the box; **+$18–25/mo** with a GCLB |
| **Stage 0 total** | **~$6–8/mo** | **~$18/mo** |

Tel Aviv runs 10–20% above `us-central1`, and GCP's e2-micro free tier is US-regions-only, so
choosing `me-west1` forfeits it. At Stage 0 the delta is noise — decide on operational fit.

**Egress is the real cost driver, and it is a consequence of the snapshot design.** Fly bills
outbound at ~$0.02/GB; GCP internet egress is ~$0.12/GB premium, ~$0.085/GB standard — 4–6x.
Every state change sends a full filtered snapshot to every player (correct, and not worth
changing): a `game.state` with 8 players and 8 hints is ~3 KB, and a typical game produces
~70–80 publishes × 8 recipients ≈ **~2 MB per game** (~250 KB per player, fine on cellular).

| Volume | Egress | Fly | GCP premium |
| --- | --- | --- | --- |
| 1k games/day | ~60 GB/mo | ~$1 | ~$7 |
| 10k games/day | ~600 GB/mo | ~$12 | ~$72 |
| 100k games/day | ~6 TB/mo | ~$120 | ~$720 |

Stage 1 widens it: Memorystore's smallest Basic tier is ~$35–50/mo against ~$0–10 for Upstash
pay-as-you-go — or $0 for Redis on the same box, which is fine for a directory holding no game
state.

**Free tiers change the pre-launch answer.** GCP has a genuinely free path and Fly does not,
so the cheapest option differs by phase:

| Phase | Cheapest | Why |
| --- | --- | --- |
| Now → store submission | **GCP** free tier, or the $300 / 90-day new-account credit | A dev server with no traffic; paying anyone for it is pointless |
| Launch onward | **Fly** | The free tier cannot carry a launched game; once paying, Fly is ~2x on compute and ~5x on egress |

Three catches on GCP's Always Free e2-micro, all of which push it to pre-launch only:

1. It exists **only in `us-west1` / `us-central1` / `us-east1`** — not `me-west1`. Taking the free
   tier forfeits the Tel Aviv latency that was GCP's advantage, serving Israeli players from Iowa
   at ~120–150 ms, worse than Fly's Frankfurt at ~60–80 ms.
2. Free egress is **1 GB/month** — about 500 games, total. A launch day exhausts it.
3. External IPv4 is billed even on free-tier instances (~$3/mo), so "free" is really ~$3/mo.

e2-micro is also 1 GB RAM on a 0.25 vCPU baseline: fine for testing, it will throttle under real
WebSocket load. The $300 credit is the stronger offer — it covers a proper e2-small in Tel Aviv
through pre-launch and into the first weeks of traffic. Take it if eligible; just diary the
90-day expiry.

**Avoid Oracle Always Free** despite the headline numbers (4 ARM cores, 24 GB RAM, 10 TB egress):
it reclaims instances it judges idle, which is the exact property that disqualifies Cloud Run.

Lock-in is negligible either way (one Go binary in a container), so none of this is permanent.
Rule: free tier or credits until launch, Fly once real traffic starts, revisit if egress crosses
~$50/mo.

Stage 0 capacity, to be confirmed by the load harness: a 1–2 GB instance should carry
thousands of concurrent games. That is far beyond any realistic launch.

### Stage 1 — Horizontal: room affinity + a shared directory

**Trigger:** any one of — sustained CPU > 60 % on one instance; measured lock contention;
p99 command latency > 150 ms; or you want zero-downtime deploys without a drain window.

The insight the current code already gives you for free: **rooms are independent.** No room
ever reads another room's state. So the shard key is the room, and the only genuinely global
things are (a) which instance owns which room and (b) the matchmaking queue.

```
                 iOS / Android
                       │
              ┌────────▼────────┐
              │   edge router   │  (fly-replay header, or a tiny proxy)
              └───┬────────┬────┘
      room r_A    │        │   room r_B
              ┌───▼───┐ ┌──▼────┐
              │ inst-1│ │ inst-2│   each owns a disjoint set of rooms;
              └───┬───┘ └──┬────┘   engine code identical to Stage 0
                  └────┬───┘
                  ┌────▼─────┐
                  │  Redis   │  directory only, no game state:
                  │          │   roomCode → instance
                  │          │   sessionToken → instance
                  │          │   matchmaking queue (per category set)
                  └──────────┘
```

- REST `join`/`create` resolves or claims the owning instance in Redis and tells the client
  which instance to open its WebSocket against (on Fly: a `fly-replay` header, so the client
  does not even need to know).
- Matchmaking becomes a Redis sorted set per category-intersection; one instance wins a short
  lock, forms the group, claims ownership, and writes the room→instance mapping.
- **Redis holds pointers, never game state.** If Redis is lost, in-flight games on each instance
  keep running; only new matchmaking and new joins pause. That is a much better blast radius
  than "game state in Redis".

What to do **now** so Stage 1 is not a rewrite — three small, non-speculative things:

1. Keep every lookup of `roomsByID` / `roomsCode` / `publicRooms` inside `internal/api`, behind
   the handful of helpers that already exist (`currentRoom`, `joinSearch`, …). Today they are
   map reads; at Stage 1 they become directory lookups. Do not let room lookups spread.
2. Make the server's own instance identity available (env var) and include it in logs, so
   "which box had that game" is answerable from day one.
3. Let the client accept a per-connection WebSocket host from the REST response instead of
   deriving it from `IMPOSTER_SERVER` (`app/lib/data/server.dart:connect`). One nullable field,
   ignored at Stage 0.

That is the whole preparation. No abstraction layer, no interfaces with one implementation.

### Stage 2 — Durability and product growth

**Trigger:** a product decision that needs data to survive the process — server-side stats,
accounts, leaderboards, friends, purchases, or an anti-cheat/abuse history.

- PostgreSQL (managed: Fly Postgres / Neon / RDS) for accounts and durable stats.
- The `internal/store` package the architecture doc already reserves — added then, not now.
- Game state stays in memory even here. Persisting a live game to survive a crash is a large
  cost for a 4-minute game that players will happily restart.
- Multi-region only if you get non-Israeli traffic; a second region before that is pure cost.

---

## 4. Required before App Store / Google Play launch

### Store identity and compliance

- [ ] **Real application id / bundle id.** `com.example.imposter_il` is a placeholder; Google
      Play **rejects** `com.example.*` outright. Pick e.g. `il.imposter.game` and set it on both
      platforms. This is irreversible after first publish.
- [ ] **Release signing.** `app/android/app/build.gradle.kts` signs release with the *debug* key.
      Create an upload keystore, enrol in Play App Signing, store the keystore + password in a
      password manager and in CI secrets (losing it means never updating the app again).
- [ ] **UGC compliance** (R9) — see §7 for the minimal design.
- [ ] **Privacy policy and terms URLs**, publicly hosted. Both stores require a privacy policy
      URL even when you collect nothing.
- [ ] **App Privacy / Data Safety answers.** Nickname + avatar go to a server; answer honestly
      ("not linked to identity", "not used for tracking"), do not claim "no data collected".
- [ ] **`PrivacyInfo.xcprivacy`** in the iOS runner — required by Apple; `shared_preferences`
      uses `UserDefaults`, a required-reason API.
- [ ] **Age rating.** Do **not** opt into Apple's Kids Category or Google Play Families — they
      pull in COPPA/GDPR-K obligations that conflict with anonymous online matchmaking with
      strangers. Rate 12+ / Teen and say "מתאים למשפחות" in the description instead.
- [ ] **Store listing in Hebrew**, RTL screenshots from real devices, both phone sizes.
- [ ] **Target SDK / iOS deployment target** at the current store minimums.
- [ ] Verify a **release** build reaches only `https`/`wss` (R13).
- [ ] Lock orientation to portrait (R10).
- [ ] Final icon, splash and logo (already tracked in `TASKS.md`).

### Backend production readiness

- [ ] TLS at the edge, HSTS.
- [ ] Graceful drain + `/readyz` (R1).
- [ ] Panic recovery + `game.aborted` (R2, R11).
- [ ] Session/room/game reaper (R3).
- [ ] Rate limits on session creation, room join, and WS commands (R4).
- [ ] Structured logs + metrics + alerting on: process restarts, panic counter, memory,
      WS connections, `internal_error` rate (R7).
- [ ] Crash reporting in the app (R7).
- [ ] `minClientVersion` handshake (R8).
- [ ] Deploy pipeline: tag → build → deploy, with a one-command rollback.
- [ ] Load test executed once, with a written capacity number (§6).
- [ ] A one-page runbook: how to deploy, how to roll back, how to read the dashboards, what to
      do when memory climbs.

### Testing

- [ ] Keep the existing suites — they are good.
- [ ] Add: load harness (§6), a fuzz test on the WS envelope decoder (`go test -fuzz`, ~15 lines),
      and one test per new limit (rate limiter, reaper, drain).

---

## 5. Now vs later

| Item | When | Why |
| --- | --- | --- |
| Panic recovery, drain, reaper, rate limits | **Now** | Each is a full outage or a rejection; all are small and local |
| Logs, metrics, crash reporting | **Now** | You cannot operate blind, and they are how you discover everything else |
| `minClientVersion` + client version header | **Now** | Impossible to retrofit once builds are in the wild |
| Store identity: bundle id, signing, privacy, UGC | **Now** | Irreversible or rejection-blocking |
| Load harness + one capacity number | **Now** | Cheap, and it turns R6 from a worry into a number |
| `game.aborted` | **Now** | Needed to make panic recovery visible to players |
| PostgreSQL | **Later** (Stage 2) | Nothing durable exists yet; a schema now is pure cost |
| Redis | **Later** (Stage 1) | Only needed when a second instance exists |
| Multi-instance routing / room directory | **Later** (Stage 1) | Prepare the three seams now, build when the trigger fires |
| Per-room actor goroutines | **Later** (only if measured) | The global lock is documented and adequate; measure first |
| Multi-region, Kubernetes, service mesh | **Not planned** | No requirement in sight for a turn-based game with 8-player rooms |
| Accounts, cross-device stats, leaderboards | **Product decision** | Out of MVP scope by decision; Stage 2 supports them when asked |
| Anti-cheat beyond server authority | **Later** | Server authority already prevents the cheats that matter |

---

## 6. Prioritized implementation roadmap

Effort is one focused engineer. Each item names the risk it closes.

### P0 — Before store submission

Most of this is implemented; what is left needs decisions or accounts that are the owner's,
not the code's.

| # | Work | Closes | Effort |
| --- | --- | --- | --- |
| ~~1~~ | ~~`recover()` in timer callback + read/write loops; panic counter; `game.aborted`~~ **done** | R2, R11 | — |
| ~~2~~ | ~~Reaper: idle sessions (24 h), empty rooms (30 min)~~ **done** | R3 | — |
| ~~3~~ | ~~Rate limits per IP and per session, returning `rate_limited`~~ **done** | R4 | — |
| ~~4~~ | ~~Graceful drain: `/readyz`, refuse new activity, wait out live games~~ **done** | R1 | — |
| 5 | `log/slog` JSON logs and `/metrics` **done**; dashboard and alerts still open (`deploy/README.md` lists what to alert on) | R7 | 1 d |
| 6 | Crash reporting in the Flutter app — **not started**, needs a vendor account | R7 | 0.5 d |
| ~~7~~ | ~~`X-Client-Build` + `MIN_CLIENT_BUILD` + an update screen~~ **done** | R8 | — |
| 8 | Portrait lock and `PrivacyInfo.xcprivacy` **done**; bundle id, keystore and Play App Signing still open (owner's call) | §4 | 0.5 d |
| 9 | Privacy policy + terms, hosted; store listings; App Privacy / Data Safety answers | §4 | 1–2 d |
| 10 | ~~UGC: blocklist, `game.report`, per-device hiding~~ **done**; the word list and `supportEmail` need the owner | R9 | — |
| ~~11~~ | ~~Deploy: Dockerfile, GCE free-tier runbook, tag-triggered Action, rollback~~ **done** (`deploy/`) | — | — |
| ~~12~~ | ~~Load harness `cmd/loadbot`~~ **done**; capacity number in R6 | R6 | — |

### P1 — First 90 days, or on the first scale signal

| # | Work | Closes | Trigger |
| --- | --- | --- | --- |
| 13 | Three Stage-1 seams: choke-pointed room lookups, instance id in logs, client accepts a per-connection WS host | R5 | Do during a quiet week |
| 14 | Redis directory: `roomCode → instance`, `sessionToken → instance` | R5 | Stage 1 trigger |
| 15 | Global matchmaking queue in Redis + ownership claim | R5 | Stage 1 trigger |
| 16 | Edge routing (`fly-replay` or a thin proxy); run 2 instances; rolling deploys without a drain window | R1, R5 | Stage 1 trigger |
| 17 | Content pool expansion — 120 words across 6 categories will repeat fast for a returning player | Product | Before marketing spend |
| 18 | Per-room actor goroutines | R6 | **Only** if the load harness or production metrics show lock contention |

### P2 — When the product asks

| # | Work | Trigger |
| --- | --- | --- |
| 19 | PostgreSQL + `internal/store`; server-side stats | A product decision that needs durable data |
| 20 | Accounts / cross-device identity | Same |
| 21 | Second region | Meaningful non-Israeli traffic |
| 22 | Questions mode | Explicitly gated on MVP completion in `TASKS.md` |

---

## 7. Decisions I am challenging

Four. Everything else in `docs/decisions.md` I would keep as-is.

### 7.1 "No inappropriate-content blocking, no reporting, no blocking" — must change before submission

The decision is coherent as *product* design: no chat, no reports, keep it light. But hints and
nicknames are user-generated content shown to strangers, and both stores require filtering +
reporting + blocking for that. This is a likely rejection, and each rejection costs a review cycle.

The minimum compliant design that preserves the product intent (no chat, no report queue, no moderation team):

1. **Filter** — a Hebrew blocklist checked server-side on nicknames and hints. The seam already
   exists and is documented: `game.Policy.HintInappropriate` currently returns `false` for
   everything; the error code `hint_inappropriate` and screen 11 are already built. This is
   plugging in a word list, not building a feature. It also closes the open decision in
   `docs/open-decisions.md`.
2. **Report** — one long-press on a hint → "דיווח". Server-side it can be a log line and a
   counter; it does not need a moderation UI to satisfy the requirement. Guideline 1.2 asks for
   a mechanism, not a team.
3. **Block** — the lightest form that satisfies it: a reported player is never matched with the
   reporter again (a small per-device list is enough; it needs no accounts).
4. **Contact** — a support email in the store listing and in the app's settings screen.

Total: a word list, one long-press menu, one list in `shared_preferences`, one email address.
Roughly the 2–3 days in P0 #10, against a multi-week rejection loop.

### 7.2 "Empty private rooms are kept" (open decision) — answer it: 30 minutes

It is listed as open in `docs/open-decisions.md` and marked in the code. Left open it is a slow
memory leak with a room-code-space exhaustion tail. 30 minutes covers "everyone dropped, we're
coming back", and the room code is short enough that reuse is fine afterwards.

### 7.3 "Everything in memory" — keep it, but make it a stated SLO, not an accident

I am **not** recommending persistence. I am recommending you write down what it means, because
right now it is implicit: *"a server restart ends all games in progress; no loss is recorded."*
Once written, drain (P0 #4) is obviously required, and "should we persist games?" stops being
re-litigated every time someone is nervous.

### 7.4 The single global mutex — keep it, but measure it

`ponytail: one lock for everything` is the right call and the escape hatch is documented. The
only thing wrong is that its ceiling is unknown. P0 #12 turns it into a number; P1 #18 acts on
that number only if it is low. Do not touch the lock before then.

---

## 8. One-paragraph summary

The hard parts are already right: the game engine is pure and server-authoritative, snapshots
are per-player filtered and versioned, idempotency and timer ordering are correctly designed,
and online matches reuse the private-room machinery instead of duplicating it. Nothing in the
domain layer needs redesigning, and the scaling path in §3 leaves it untouched. What is missing
is everything around it — process lifecycle (drain, panic recovery), resource bounds (GC, rate
limits), observability, deployment, and store identity — plus one product-level compliance gap
(UGC filtering and reporting) that is the most likely cause of a store rejection. Ship Stage 0
as a single instance with no database; add the Redis room directory only when a measured trigger
fires; add PostgreSQL only when the product asks for durable data.
