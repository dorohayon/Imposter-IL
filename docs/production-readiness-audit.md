# Production-Readiness Audit — מי המתחזה?

Audited at `4a3a6f5` (main), 25 September 2026. Fixes are on branch
`audit/production-readiness`. The production service read during
the audit was Cloud Run `imposter`, revision `imposter-00030-d5q`.

**Release gate: NOT READY FOR RELEASE.** The finite list of blocking items is in §2.

> **Update, later on 25 September — after the owner's decisions.** B5 and B6
> are resolved in code on the same branch:
>
> - A drop counts as a disconnect only after 30 s away, and online searches
>   keep their place for 30 s.
> - The turn clock never resets on reconnect, which closes turn stalling. The
>   model checker now asserts no turn outlives its 60 s.
> - During the impostor's guess only the guess decides.
> - Leaving a live game shows a warning.
> - The legal documents are 13+ (version 1.2, re-acceptance required).
> - Reporting is at the store minimum; the two-report table-wide hide was
>   removed.
> - Short secret words match only at the start of a hint.
>
> All six open code defects in §4 are fixed:
>
> - leaving just as the next game starts;
> - hints with no letters;
> - Hebrew presentation forms and invisible characters;
> - an optional App Store Server API refund check;
> - a phone bumped because the same guest identity connected elsewhere now
>   quietly becomes a new guest;
> - Android backup of the session token.
>
> Recorded in `docs/decisions.md` and `TASKS.md`. Remaining blockers: B1–B4,
> B7, B8, B9.

## How this audit was run, and what it did not cover

26 specialised audit agents were planned. The first two attempts hit the
account's usage cap, and only **8 completed**: security, Android, iOS,
WebSocket/reconnect, game engine (with a 10,000-game randomised model checker),
multiplayer lifecycle, concurrency, and the full automated-test run. The rest
was done directly and more narrowly:

- server and client purchase verification;
- ad gating;
- deploy and configuration;
- observability, including a read of production logs and alert policies;
- drain and shutdown;
- load tests;
- one independent adversarial reviewer of the final diff.

**Covered only lightly or not at all:**

- App Store and Play policy review, beyond the Android and iOS agents' findings;
- the UX/offline pass across every screen, including overflow at 320 px;
- one-device mode;
- matchmaking timing rules (4 players → 30 s, 6 → 5 s countdown, 2 min → no match);
- the full journey-by-journey trace.

§26 lists these as remaining risk. Every finding below was either reproduced by
a test or script, or traced in code, and it says which.

---

## 1. Executive summary

The core is sound. It is server-authoritative, the impostor's view never
contains the secret word on the wire, and message-id replay is idempotent.
Every product rule traced in the engine held; the ones marked in §6 are
decisions for the owner, not code defects. A randomised model checker ran
**10,000 seeded games (755k steps)** of legal and illegal commands, disconnects
and clock jumps; after the fixes in §24 no invariant was violated.

A single 1 vCPU / 512 MiB instance handles **4,800 concurrent players**
(600 games) at p99 7.6 ms (§11).

What was **not** safe for real users:

- **Two remote denial-of-service holes**, both reproduced against the real
  production image:
  - One client could OOM-kill the only instance in 11 seconds by sending
    oversized message ids, which the idempotency cache kept.
  - Any client could bypass every per-IP rate limit by forging
    `X-Forwarded-For`, including the one that stops private-room codes being
    walked.
- **One panic path froze the entire server permanently.** It held the global
  lock outside any recovery, and Cloud Run has no liveness probe to restart it.
- **One player could disconnect every other player at their table** by flooding
  no-op profile updates.

These and 16 more defects are fixed on the branch with regression tests (§24).
**They are not live**: production still runs the vulnerable build with bots on.

What still blocks release is mostly outside the code:

- signing keys, developer accounts and store products;
- a redeploy of this branch;
- two owner decisions that affect fairness and legal exposure:
  - turn-stalling via reconnect cycling;
  - the 6+ vs 13+ audience contradiction with ads.

## 2. Release blockers

Each item must be closed before real users.

| # | Blocker | Kind | Status |
|---|---|---|---|
| B1 | Production runs the vulnerable build: the reply-cache OOM, the X-Forwarded-For (XFF) rate-limit bypass and `STAGING_BOTS=5`. **Redeploy this branch with `STAGING_BOTS=0`.** | ops | fixed in code; deploy pending |
| B2 | Android upload key and Play App Signing do not exist. Release AABs are signed with the debug key, which Play refuses. | external | open |
| B3 | Nothing can produce an App Store build: no Xcode 26 host (this Mac runs macOS 14.7), no `DEVELOPMENT_TEAM`, no signing or archive pipeline. Apple has required Xcode 26 / the iOS 26 SDK for uploads since April 2026. | external | open |
| B4 | Developer accounts, and the store products (`category_<id>`, `premium_monthly`, `premium_lifetime`). | external | open |
| B5 | ~~**Turn stalling:** the player whose hint turn it is can hold a table of strangers forever by force-closing and reopening the app. Each return inside 30 s grants a fresh 60 s turn and cancels removal. Reproduced: 11 min 44 s still on round 1, turn 1.~~ | decision + code | **resolved** |
| B6 | ~~**Audience contradiction:** the Terms say "suitable from age 6, under 13 with parental approval", while store targeting, AdMob `maxAdContentRating=PG` and the privacy policy assume 13+. Knowingly admitting under-13s while serving ads is COPPA and Play Families exposure.~~ | decision (legal) | **resolved: 13+** |
| B7 | AdMob consent message not published: GDPR for the EU, UK and Switzerland, plus the IDFA explainer. The iOS ATT prompt depends entirely on that message. | external | open |
| B8 | Server-side entitlement enforcement is off in production. A modified client plays every paid category online for free. Turn it on (`APPLE_BUNDLE_ID`, `GOOGLE_PLAY_*`, `MIN_CLIENT_BUILD=4`, `serverEnforcement: true`), or accept the leak in writing. | config + decision | open |
| B9 | Post-deploy verification on the real service. Nothing on Cloud Run verified either point below, and they are the premises of B1's fixes and of §12. | ops | open |

B9 covers two checks:

1. Sessions created from two different networks land in different rate-limit
   buckets. This confirms Cloud Run appends the real client IP last.
2. One deploy during a test game, to see what players actually experience.

## 3. Critical / high findings

Status key: **Fixed** means fixed on the branch with a regression test.
**Open** means not fixed. **Decision** means it needs the owner.

| Sev | Finding | Evidence | Status |
|---|---|---|---|
| BLOCKER | The idempotency cache stored up to 100 full replies per session with unbounded ids (about 64 KB each), for the session's 24 h life. One IP OOM-killed the 512 Mi instance in 11 s. | `auditflood` against the prod image: `OOMKilled=true` after 31 sessions. Harness: 12.5 MiB per session. | **Fixed:** ids over 64 bytes are refused and not cached; the reaper prunes caches. Same attack after the fix: 60 sessions, 7.9 MiB, no OOM. |
| BLOCKER | `clientIP` trusted the first `X-Forwarded-For` entry, which the client controls. Every per-IP limit was bypassable, and room codes (10⁶) were enumerable in minutes. | Test: forged first hop, 1000/1000 sessions and 500/500 joins with 0 rate-limited. | **Fixed:** takes the last hop. Test `TestForgedForwardedHeaderDoesNotBypassSessionLimit`. |
| HIGH | A panic under `s.mu` outside recovery (in readLoop after dispatch, attach or detach) held the lock forever; the whole server froze. A panic in `runStagingBots` crashed the process. | `TestAuditGhostSessionDeadlocksTheServer` deadlocked; the bot-loop crash reproduced 2 times in 3. | **Fixed:** every locked block recovers under the lock. |
| HIGH | Reaper vs handshake race: a socket attached to a session the reaper had just deleted became an orphan. This was the concrete trigger for the deadlock above. | `TestAuditReaperRacesTheHandshake` | **Fixed:** 0 of 300 orphans. |
| HIGH | Table-wide disconnect by one player. `PATCH /v1/sessions/me` was unthrottled and republished the room each time, so a full 64-message send buffer disconnected every other member. | `TestAuditProfileFloodDisconnectsTheTable` | **Fixed:** profile edits are limited per session, publish only on a real change, and the buffer is 256. 53,940 PATCHes → 0 of 5 victims dropped. |
| HIGH | The app never detected a silently dead socket (no client pings). The game looked frozen while the server was already counting disconnects toward removal. | Dart probe: the client still "open" 65 s after the path died. | **Fixed:** `pingInterval` 10 s. |
| HIGH | Turn stalling via reconnect cycling. | model checker plus an API test | **Decision** (B5). The minimal fix keeps the remaining turn time on return instead of granting a fresh 60 s. |
| HIGH | The ATT prompt depends on an unpublished AdMob IDFA message, while the docs say to declare "Tracking: Yes". | static | **Open** (B7) |
| HIGH | 6+ Terms vs 13+ ad audience. | `app/lib/screens/legal_screens.dart:187` | **Decision** (B6) |
| HIGH | `serverEnforcement` is off in production. | security audit | **Decision** (B8) |
| HIGH | Production logs had no `severity` field: every entry, panics included, was DEFAULT. | `gcloud logging read` of production. The only alert policy is "player reports"; there is no uptime check. | **Fixed:** the level maps to `severity`. `msg` is kept, because the moderation alert filters on it. |

## 4. Medium / low findings

**Fixed on the branch:**

- **(MEDIUM) Silent-vote miscount.** Votes for a player who then leaves were
  deleted, so the round counted as "silent", and two in a row cancel the match
  as abandoned. `game.go` now tracks `voteCast`. Test:
  `TestVotesForALeaverDoNotMakeTheRoundSilent`, which fails without the fix.
- **(MEDIUM) Reactions after a skipped turn.** Every reaction after a skipped
  last turn failed with `invalid_hint` for the whole table. It now resolves to
  the last real hint of that round, or waits for the round's first. Two tests.
- **(MEDIUM) Socketless members.** A member who joined over REST and never
  opened a WebSocket counted as "connected" forever: every game waited out
  their turns, and the disconnect rules never applied to them. Such members are
  now marked offline.
- **(MEDIUM) Bot-loop crash.** `tickSearch`, `searchDeadline` and
  `publishSearch` dereferenced members deleted mid-walk, a bot-loop crash with
  staging bots on. Nil guards added.
- **(MEDIUM) R8 and WorkManager.** R8 stripped WorkManager `InputMerger`
  constructors, so every one-time job failed, including the Mobile Ads offline
  pings. A keep rule was added; it was verified on an emulator by the Android
  auditor.
- **(MEDIUM) Invite link vs legal gate.** An invite deep link pushed the join
  screen over the legal re-acceptance gate. The link now checks the accepted
  version, and calls `scheduleFrame` so a warm link is not delayed. Test:
  `invite_legal_gate_test.dart`.
- **(MEDIUM) Reconnect storms.** The fixed 2 s reconnect with no jitter caused a
  synchronised herd after every restart. It now backs off ×1/×2/×4 with jitter,
  with no backoff while a game holds the player's seat.
- **(MEDIUM) No abort on drain timeout.** When draining ran out, games died with
  the socket and no `game.aborted`. `AbortGames()` now sends it.
- **(MEDIUM) `game.aborted` ignored by the app.** The app had no handler for
  it, so the panic-abort path sent players home silently instead of showing
  screen 29. It is handled now. Test: `game.aborted from the server shows
  screen 29 without a loss`, which fails without the fix.
- **(MEDIUM) Bots re-enabled by redeploys.** `deploy/setup-cloudrun.sh`
  defaulted `STAGING_BOTS` to 5, so every redeploy re-enabled bots. The
  default is now 0.
- **(MEDIUM) No `GOMEMLIMIT`.** It is now `400MiB` on Cloud Run.
- **(LOW) Cached `rate_limited` replies.** They were cached, so a same-id retry
  kept failing for 5 minutes. They are no longer cached.
- **(LOW) Hebrew not declared on iOS.** It is now in `CFBundleLocalizations`.
- **(LOW) Stale model checker.** Its silent-vote model had to be updated to the
  rule. It is now a permanent test (`server/internal/room/modelcheck_test.go`),
  100 seeds by default; `AUDIT_SEEDS=10000` passes.

**Open (not fixed):**

- **Needs a decision:**
  - (MEDIUM) If a citizen leaves during the impostor's 60 s guess, the impostor
    wins on parity without guessing.
  - (MEDIUM) A voted-out spectator who taps exit gets a loss even when their
    team wins; killing the app avoids it.
  - (MEDIUM) Every transport drop, including Cloud Run's hourly 3600 s
    WebSocket cut, counts as a game disconnect and cancels an online search.
  - (MEDIUM) Two sessions (one person) can hide any player's clues from the
    whole table. The report threshold is fixed at 2.
- **Code, not fixed yet:**
  - (MEDIUM) `game.leave` racing the host's `room.start` can leave a player an
    invisible member of the new game. This one is client-side.
  - (MEDIUM) Release builds silently fall back to the debug key; Play would
    refuse the upload anyway.
  - (LOW) Hints made only of emoji or punctuation are accepted, and later ones
    are then rejected as duplicates.
  - (LOW) Hebrew presentation-form characters bypass the blocklist and the
    secret-word check. NFKC folding would need `golang.org/x/text`.
  - (LOW) Concurrent `POST /v1/entitlements`: the last one to finish wins.
  - (LOW) The client ignores close code 1008, so two holders of the same token
    ping-pong. Android Auto Backup can create exactly that situation (below).
- **Hygiene:**
  - (LOW) `ITSAppUsesNonExemptEncryption` is missing, a legal declaration for
    the owner.
  - (LOW) Swift packages are unpinned.
  - (LOW) Android Auto Backup copies the session token and entitlement cache to
    a new device.
  - (LOW) Workflow actions are not SHA-pinned, and CI does not run
    `govulncheck`.
  - (LOW) `docs/protocol.md` values drift from the code.
  - (LOW) An invite link is dropped rather than kept when the Terms must be
    re-accepted.
  - (LOW) When the host creates a room while their socket is reconnecting, they
    briefly see their own "host disconnected" notice.

## 5. Questionable decisions / architecture challenges

| Decision | Why it deserves reconsideration | Recommendation |
|---|---|---|
| Cloud Run, `max-instances=1` | The binding capacity limit is the platform's per-instance concurrency (800 configured, 1,000 maximum), not the server, which measured 6× more (§11). Every deploy ends or strands every in-memory game. WebSockets are cut at 60 min. The service also carries a stray service-level `maxScale: 12` next to the revision's 1. | See §13. |
| Everything in one process's memory | Fine for launch. It makes deploys, crashes and OOMs full-table events. Written down as an SLO it stops being an accident. | Keep. State "a restart ends games, no loss" as the SLO. |
| One global mutex | Measured: 14.7 s of lock time over 180 s at 4,800 players. It is not the bottleneck; memory and GC are (§11). | Keep. |
| Full snapshot on every change, disconnect on a full buffer | This design turned one abusive or merely bursty player into disconnects for the whole table. | Mitigated. Later: coalesce the latest snapshot per connection. |
| Fresh 60 s on reconnect in your own turn | Enables indefinite stalling (B5). | Resume the remaining time, with a minimum of about 10 s. |
| Every socket drop counts as a strike | With the hourly Cloud Run cut and Wi-Fi/cellular handovers, honest players accumulate strikes; the third removes them with a loss. | Count a drop only if the player is not back within about 5 s. |
| No leave warning + leaving = loss | A stray Android back gesture is a recorded loss. | Owner UX decision. |
| `STAGING_BOTS` as a production feature | Real strangers were being matched against server actors. The deploy script silently re-enabled them. | Default is now 0. Bots are beta-only. |
| `serverEnforcement` off at launch | Paid content is free to anyone with a modified client. | Decide explicitly (B8). |
| Offline Apple JWS verification | A lifetime purchase refunded after signing stays valid for a client that keeps replaying the old JWS. Proofs are not bound to an install, so one JWS can be shared. | Add App Store Server Notifications, and cap the number of sessions per `originalTransactionId`. |
| No crash reporting, and a privacy policy that promises none | You cannot see client crashes after launch; adding Crashlytics later needs a policy, Data safety and App Privacy update in the same release. | Decide before launch, not after the first crash wave. |
| Report threshold fixed at 2 | One person with two sessions can hide anyone. | Make it relative to table size. |
| `us-central1` for an Israeli audience | About 150 ms round trip, irrelevant for 60 s turns. Only a VM offers Tel Aviv (`me-west1`). | Low priority. |
| `/metrics` behind a token, but nothing scrapes it | On Cloud Run the counters are never collected, so they alert on nothing. | Add an uptime check and log-based metrics (§21). |

## 6. Game correctness

- **Engine rules:**
  - no self-vote;
  - turn order;
  - spectators cannot act;
  - parity win;
  - a second tie eliminates nobody;
  - two silent votes abandon the match;
  - the impostor never receives the word;
  - 60 s guess;
  - the elimination reveal.

  All were verified by table and model checking. The concrete bugs found
  (silent-vote miscount, reactions after a skipped turn) are fixed.
- **Rule-level questions for the owner:**
  - B5, turn stalling;
  - a leaver during the guess handing the impostor a parity win;
  - the spectator's exit loss;
  - substring matching of 2-letter secret words;
  - whether a silent runoff counts toward the two-silent rule.
- **Not re-verified:** one-device mode parity with the server.

## 7. Edge cases

**Multiplayer lifecycle.** It never deadlocks a phase: every phase has a
deadline, and every command ticks first. Everyone disconnecting, the impostor
removed on a third disconnect, an exact-boundary reconnect, a duplicate
socket, a runoff candidate leaving, and a public match where all drop all end
correctly. The invalid or unfair outcomes are listed in §3 and §4.

**Idempotency.** Double-tap and retry after a cut never double-execute. The
reply cache survives reconnects.

## 8. Network loss and reconnection

Measured with a fault-injection proxy by the WebSocket auditor:

- The WebSocket token is in a header, so it is never logged in URLs.
- The client-build gate also applies to `/v1/ws`.
- `stateVersion` handling is safe across restarts.
- A replacement connection is not counted as a disconnect.
- The server detects a dead path in about 30 s.
- **Before the fix, the client never noticed one.** It now pings every 10 s
  and reconnects with jitter.
- **Still open:** every drop counts toward the 3-strike removal (§5).
- The per-stage internet-loss matrix across every screen was **not** completed
  (§26).

## 9. Concurrency

- `go test -race`: 0 races over repeated runs.
- The single lock gives race-free memory access.
- No network write, channel send or outbound HTTP blocks under the lock.
- No double close.
- Goroutines return to baseline after load (9 before, 9 after 6,400
  connections).
- The defects were in failure handling, and are fixed (§3).
- The stress regression's goroutine-leak check needed a 30 s settle window
  under `GOMAXPROCS=1 -race`. With 10 s it failed about 1 run in 8 on timing,
  not on a leak.

## 10. Security

**Server-side checks:** identity, room membership, host privileges, turn, role
and voting eligibility are all enforced; no exploit was found.
`TestAuditOKGameAndRoomAuthorization` covers them.

**Tokens:** session tokens and player ids use `crypto/rand` (130 bits).

**Exposed endpoints:** no pprof or `DefaultServeMux`. `/metrics` is
token-gated, with a constant-time compare.

**Store verification:** Apple JWS is verified against a pinned G3 root, with
both OIDs required, ES256 only, and bundle, product and revocation checks.
Google verification refuses pending, on-hold, paused and expired states, and
never turns an outage into a lost purchase.

**Open:**

- **Enforcement off (B8).**
- **Proof sharing and refund replay** (§5).
- **Sandbox receipts** are accepted in production. This is deliberate, for App
  Review, but TestFlight testers' free purchases unlock categories online too.
- **`METRICS_TOKEN`** is a plain environment variable, not Secret Manager.
- **Service account:** the service runs as the default compute account, which
  typically has Editor. Use a dedicated account with no roles.

## 11. Scalability / load-test results

Setup:

- **Server:** Docker, `--cpus=1 --memory=512m`, `GOMEMLIMIT=400MiB`,
  `RATE_LIMITS=off`.
- **Load generator:** the load bot in a separate 4-CPU container on the same
  network. Real online matchmaking over REST and WebSocket, 8-player tables,
  bots thinking 2–7 s.

| Players (concurrent) | Duration | Games ended | p50 / p95 / p99 / max | Peak CPU (of 1 vCPU) | Peak memory | Panics |
|---|---|---|---|---|---|---|
| 400 | 60 s | — | 1.9 / 5.9 / 8.8 / 47 ms | 9 % | 40 MiB | 0 |
| 800 | 180 s | 112 | 1.9 / 5.3 / 8.1 / 16 ms | 10 % | 81 MiB | 0 |
| 1,600 | 180 s | 296 | 1.7 / 5.0 / 7.9 / 28 ms | 9 % | 156 MiB | 0 |
| 3,200 | 180 s | 584 | 1.4 / 4.6 / 7.3 / 34 ms | 38 % | 309 MiB | 0 |
| 4,800 | 180 s | 736 | 1.2 / 4.3 / 7.6 / 61 ms | 53 % | 385 MiB | 0 |
| **6,400** | 180 s | 928 | 1.8 / **68 / 118** / 361 ms | **100 %** | 413 MiB | 0 |
| Spike: 3,200 within 1 s | 90 s | 144 | 3.9 / 77 / 158 / 262 ms | 90 % | 294 MiB | 0 |

The 400-player row ran for only 60 s, too short for any game to finish.

- **Knee:** between 4,800 and 6,400 concurrent players. Past it, GC pressure
  against the memory limit saturates the CPU. It degrades gracefully: no OOM,
  no errors.
- **Cleanup:** after load, goroutines returned to 9 and WebSockets to 0. After
  GC the heap was 62 MB, holding 6,400 idle sessions (kept 24 h by design) and
  games winding down on timeouts. No leak.
- **Attack after the fix:** the reply-cache OOM attack peaked at 7.9 MiB, with
  no OOM.
- **Not measured:**
  - a true reconnect storm (the load bot does not reconnect; the spike row is
    the closest proxy);
  - a multi-hour soak;
  - slow-reader or non-reader clients at scale (covered by unit tests only).

## 12. Cloud Run single-instance assessment

Can it launch? **Yes, for a soft launch, with known limits:**

- **Capacity ceiling:** `containerConcurrency=800` means at most 800
  concurrent connections, about 100 full tables. REST calls take slots too.
  Raise it to 1,000, the platform maximum. Beyond that, new players get 429
  with `max-instances=1`. The code itself was measured at 4,800 players.
- **Deploys:** every deploy ends or strands in-flight games. Google's docs say
  in-flight requests are allowed to finish while new ones go to the new
  revision ([WebSockets][ws], [container contract][cc]). So the old and new
  instances may briefly coexist with split matchmaking. A player who
  reconnects lands on the new instance, gets `session_not_found`, then
  screen 29. The drain gets 8 s, then `AbortGames` (new). **Verify with one
  real deploy (B9).**
- **60-minute WebSocket cut:** a forced reconnect every hour, counted as a
  strike (§5).
- **Cold start:** with `min-instances=0`, the first player after an idle
  period waits for the instance to start.
- **Memory:** 512 MiB suffices up to the concurrency cap, with `GOMEMLIMIT`
  set.
- **Service-level scaling annotation:** the stray service-level
  `maxScale: 12` should be aligned to 1 in the console (Service → Edit →
  Scaling). Its effect is unverified.
- **Cost:** request-based billing while any WebSocket is open. The earlier
  review's estimate of about $61/month for an instance up around the clock was
  not re-verified.

## 13. Cloud Run vs Compute Engine

| | Cloud Run (`max=1`) | GCE e2-small VM, Caddy (`deploy/setup-gcp.sh`) |
|---|---|---|
| Concurrent players | ≤ 800–1,000 (platform cap) | Measured about 4,800 per vCPU; the VM's 2 GB allows more |
| Deploy during play | ends or strands games | drain up to 10 min, games finish |
| WebSocket lifetime | cut at 60 min | unlimited |
| Region | us-central1 (about 150 ms to Israel) | me-west1 Tel Aviv possible |
| Operations | none | a VM to patch, Caddy TLS |
| Cost at low traffic | about $0 | about $15–18/month |

**Recommendation:** Cloud Run is justified for a small soft launch *if* deploys
happen only at quiet hours. Move to the VM, same image and no code change,
when any trigger below fires:

1. Peak concurrent WebSockets above 500, which is 60% of the cap.
2. A deploy has to happen while games are live.
3. More than about 50 instance-hours a month, the cost break-even.
4. p99 command latency above 150 ms.

**Horizontal scaling**, when one VM is not enough, needs:

- room-to-instance affinity routing, via a directory, `fly-replay` or a thin
  proxy;
- a shared matchmaking queue, such as Redis holding pointers, never game state;
- sessions resolvable to their instance.

The pure engine needs no change for any of this.

## 14. Flutter / mobile

- **Architecture:** `ChangeNotifier`, the server offset is applied to
  countdowns (so device clock skew does not matter), and the reconnect loop is
  now backed off with jitter.
- **Fixed:** client pings, `game.aborted` handling, the invite legal gate, and
  reconnect jitter.
- **Not deeply audited:** lifecycle on iOS background (the socket is killed
  after about 30 s, so resume relies on the reconnect loop), and 320 px
  overflow.

## 15. Android

- targetSdk 36 and minSdk 24; this meets Play's API 36 requirement.
- Play Billing Library 8.0.0 meets the PBL 8 minimum.
- All `.so` files are 16 KB aligned.
- No cleartext traffic in release.
- A release APK cold-starts on an API-35 emulator.
- **Blockers:** the upload key (B2).
- **Fixed:** the R8 `InputMerger` rule.
- **Open:** silent debug-key fallback, Auto Backup of the token, and the
  portrait lock being ignored at 600 dp and wider on Android 16.

## 16. iOS

- Bundle id, version and build 4, deployment target 15.0, iPhone-only, and
  portrait-only are all correct.
- SKAdNetwork list (50 entries) is present.
- **Blockers:** there is no way to build for upload (B3).
- **Fixed:** Hebrew is now declared.
- **Open:**
  - `ITSAppUsesNonExemptEncryption`;
  - unpinned Swift packages;
  - the UMP/ATT form presented from `AppDelegate.window`, which is nil under
    the UIScene template (unverified without a device);
  - the privacy manifest omits the guest identifier and nickname.
- The release build itself could not be run here (§22).

## 17. Backend

- `http.Server` has `ReadHeaderTimeout`; body limit is 64 KiB; WebSocket read
  limit is set; distroless non-root image.
- **Fixed:** the items in §3 and §4.
- **Open:**
  - Neither `/livez` nor a liveness probe exists. With recovery now covering
    every locked block, the deadlock class that needed them is closed.
  - Shutdown cancels the reaper before draining; harmless for 8 s.

## 18. Monetization / IAP

**Server:** verification is correct (§10).

**Client:**

- The purchase stream is subscribed at launch, so purchases finished while the
  app was closed are delivered.
- Every non-pending purchase is completed or acknowledged, so Play's
  three-day refund does not trigger.
- Ownership is replaced from what the store lists, so refunds and lapses take
  effect.
- Server outages keep what the player already had.

**Open:**

- **B8:** enforcement is off.
- **Refund replay and proof sharing:** §5.
- **Untested:** sandbox and device flows, per `TASKS.md`.

## 19. AdMob / privacy

- Test ad units are used unless the build is release (`!kReleaseMode`).
- An interstitial shows only after a match played to a winner: not after an
  abort, and not after the impostor leaves.
- `interstitialMinIntervalSeconds` is 0, so there is an ad after every
  completed match. This is a business setting; confirm it is intended.
- **Premium:** users who own Premium never get ads.
- **Consent (UMP):** consent info is requested and the form is shown before
  `MobileAds.initialize`, and `canRequestAds` is respected (`ads.dart:49-66`).
- **Open:**
  - B6 and B7.
  - `RequestConfiguration` sets only `maxAdContentRating`. There is no
    `tagForChildDirectedTreatment` or `tagForUnderAgeOfConsent`, which B6 must
    decide.
  - `showInterstitial` has no timeout on the navigation path. If the ad SDK
    never calls dismissal, "continue" hangs. Not reproduced.

## 20. Store / compliance

- **UGC:** a blocklist, reporting, hiding reported players, a published
  contact, and a 24 h review commitment are all implemented.
- **App Review (guideline 2.1):** once bots are off, a reviewer alone cannot
  experience online play. Provide review notes and a way to play: a private
  room with the reviewer's second device, or one-device mode.
- **Play closed testing:** 12 testers for 14 days is required for this
  account type (`TASKS.md`).
- **Open:** B6 and B7. A full policy pass was not completed (§26).

## 21. Observability

| Area | State |
|---|---|
| Structured JSON logs | Present, now with `severity`. |
| Panics | Logged with stacks and counted. |
| `/metrics` | Rich, covering sessions, rooms, games, WebSocket connections, command codes, publish latency, heap and goroutines. **Nothing collects it on Cloud Run.** |
| Existing alerts | The only one is "player reports". |
| Uptime check | None. |
| Error reporting | None. |
| Client crash reporting | None. |
| Log correlation | No trace ids. |
| Deployment | No build or version info in logs or `/readyz`. |

At 02:00 an operator could see logs and nothing else. The minimum to add:

- an uptime check on `/readyz`;
- a log-based alert on `severity>=ERROR` (now possible) and on `panic recovered`;
- a log-based metric for `rate_limited`;
- Cloud Run's built-in memory and instance-count alerts;
- the build SHA in the startup log.

## 22. Tests executed

| Suite | Result |
|---|---|
| Baseline (`4a3a6f5`): Go `-race`, and 5 runs without `-race` | 229 tests, all passing; one flaky test, `TestUnusedSessionsAreReapedQuickly`, whose race is fixed by the reaper/handshake fix |
| Baseline: Flutter | 173 passed, 3 skipped (the end-to-end tests), in each of 3 runs |
| Baseline: end-to-end against a real server | 3/3, run twice |
| Baseline: `govulncheck` on the production binary | clean |
| Final: `gofmt`, `go vet`, `golangci-lint` | clean |
| Final: `go test -race ./...` | all packages ok, 3 times before the review fixes, then once after them |
| Final: `dart format`, `flutter analyze` | clean |
| Final: `flutter test` | 176 passed, 3 skipped |
| Final: end-to-end against a server built from the branch | 3/3; no ERROR logs |
| Final: model checker, `AUDIT_SEEDS=10000` | pass |
| Android release AAB | built by the Android auditor; debug-signed |
| iOS release | **not run.** There is no Xcode 26 here; the last CI unsigned build was read instead. |

## 23. Load and stress tests executed

§11 has the results. The attack replay is in §3.

The load harness is the existing `cmd/loadbot`. Its step script lives in the
session scratchpad and was not committed.

## 24. Bugs fixed during this audit

On branch `audit/production-readiness`:

- **Server:**
  - `server/internal/api/{ws.go,limits.go,api.go,reaper.go,ops.go,matchmaking.go,staging_bots.go}`
  - `server/internal/game/game.go`
  - `server/cmd/server/main.go`
- **App:**
  - `app/lib/{data/server.dart,state/game_session.dart,main.dart}`
  - Android `proguard-rules.pro`
  - iOS `Info.plist`
- **Deploy:** `deploy/setup-cloudrun.sh` and `deploy/README.md`.
- **New regression tests:**
  - `server/internal/api/regression_{concurrency,fanout,stress}_test.go`
  - `server/internal/room/modelcheck_test.go`
  - new cases in `ws_test.go`, `ops_test.go`, `api_test.go`, `game_test.go`,
    `rounds_test.go` and `main_test.go`
  - `app/test/invite_legal_gate_test.dart`, and a new case in
    `live_room_test.dart`

## 25. External / manual actions still required

1. Redeploy the branch: `STAGING_BOTS=0 ./deploy/setup-cloudrun.sh`. It now
   sets `GOMEMLIMIT`.
2. Align the service-level scaling to 1.
3. Raise concurrency to 1,000.
4. Move `METRICS_TOKEN` to Secret Manager.
5. Give the service a dedicated service account with no roles.
6. Run the B9 checks on the real service.
7. Create the Android upload key and enable Play App Signing.
8. Set up iOS: an Xcode 26 host (macOS 15.6 or later), `DEVELOPMENT_TEAM`,
   certificates, and an archive.
9. Create the developer accounts, the store products, and the Billing Grace
   Period.
10. Publish the AdMob consent message and the IDFA explainer.
11. Store listing items:
    - review notes explaining how a reviewer can play;
    - Data safety and App Privacy forms, including AdMob;
    - `ITSAppUsesNonExemptEncryption`, a legal declaration;
    - an age rating consistent with the B6 decision.
12. Monitoring: an uptime check and log-based alerts (§21).
13. Real-device tests (`TASKS.md`), including Wi-Fi to cellular handover and
    purchases in the sandbox.

## 26. Remaining risks / assumptions

- Of 26 planned domain audits, 18 did not complete (see the top of this
  document). The largest uncovered areas:
  - the network-loss matrix across every screen;
  - the UX pass, including 320 px overflow and back-gesture paths;
  - one-device mode;
  - matchmaking timing rules;
  - a full App Store and Play policy review.
- Cloud Run specifics were not observed on the platform:
  - XFF ordering;
  - revision rollover with open WebSockets;
  - which scaling annotation wins.
- No iOS build was produced in this environment.
- The load tests ran on Docker Desktop, where 1 vCPU is not identical to a
  Cloud Run vCPU. Treat the numbers as ±30%.

## 27. Pre-release checklist

- [ ] B1: redeploy this branch with `STAGING_BOTS=0`, then confirm `/readyz`
      and that logs show `severity`.
- [ ] B9: rate-limit buckets tested from two networks; one deploy during a
      test game.
- [ ] B2 / B3 / B4: signing, the build host, accounts and products.
- [ ] B5: decide turn-stall semantics, then implement and test.
- [ ] B6: decide the audience and age, and align the Terms, store rating and
      ad tagging.
- [ ] B7: AdMob consent messages published.
- [ ] B8: enforcement on, with verifiers configured, or the leak accepted in
      writing.
- [ ] Monitoring: an uptime check plus error and panic alerts.
- [ ] Review notes for Apple and Google on how to play online.
- [ ] Real-device pass (`TASKS.md`), including purchases and handovers.
- [ ] Complete the audits listed in §26.

---

**NOT READY FOR RELEASE.** Blocking items: B1–B4 and B7–B9 in §2.

[ws]: https://docs.cloud.google.com/run/docs/triggering/websockets
[cc]: https://docs.cloud.google.com/run/docs/container-contract
