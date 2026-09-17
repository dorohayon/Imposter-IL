# Terms, privacy and consent

The legal surface has three parts and they must stay aligned:

1. `app/lib/screens/legal_screens.dart` — the copies players can read in the app and the consent gate.
2. `server/internal/legal/site/` — public HTML copies for App Store Connect, Google Play and people without the app. `app/test/legal_test.dart` reads the section headings out of these files and fails if the app is missing one, so the alignment is checked rather than promised.
3. `legalVersion` / `legal.acceptedVersion` — the device-local acknowledgement version.

Current document version: **1.0**, effective **17 September 2026**.

## Player flow

A fresh install sees the legal gate before profile onboarding and therefore before it can create a guest session or submit a nickname. The continue button stays disabled until the checkbox is selected. The accepted version is stored in `SharedPreferences` as `legal.acceptedVersion`.

A device whose stored version differs from `legalVersion` sees the gate again. Bump `legalVersion` only for a material change for which renewed acknowledgement is intended. Editorial fixes to the public HTML that do not change the substance do not require a bump.

Terms and Privacy remain readable from Settings after acceptance.

## Public URLs

The game server serves the documents. GitHub Pages cannot publish a private repository without a paid plan, and the server already has a public HTTPS hostname and certificate, so the pages ride on it — no second host to pay for, deploy or forget to update:

- `https://imposter-eegbs6v5uq-uc.a.run.app/privacy/`
- `https://imposter-eegbs6v5uq-uc.a.run.app/terms/`
- `https://imposter-eegbs6v5uq-uc.a.run.app/legal/` links to both.

The files are compiled into the binary with `go:embed` (`server/internal/legal`), so publishing a change is the same deploy as any server change and there is no state to configure. The routes sit outside the API's gate: a browser sends no `X-Client-Build` header, and a store reviewer is not a player to rate-limit.

The app builds these URLs from whichever server it is pointed at (`--dart-define=IMPOSTER_SERVER`), so a development build shows the development server's copies rather than production's.

**The consequence to accept:** the store listings then depend on the game server staying at this address. Moving the server means updating both store listings in the same release. A custom domain in front of Cloud Run would remove that coupling and is the natural next step if the URL ever needs to outlive the host.

## What the documents describe

The v1 documents are intentionally product-specific. They reflect the current implementation:

- no account and no real-name/email/phone requirement;
- guest session/player identifiers, nickname and avatar;
- game state, categories, hints, reactions, votes, guesses and reports;
- IP processing for abuse/rate limiting;
- local wins/losses, settings, muted/reported-player ids and legal version;
- in-memory server state, 24-hour idle session TTL and 30-minute empty-room TTL;
- server operational logs and report metadata;
- no advertising SDK, sale of personal data, third-party analytics SDK or crash-reporting SDK in v1;
- UGC filtering, reporting and device-local hiding.

If any of those facts changes, review both documents and the App Store Privacy / Google Play Data Safety declarations before release.

## Required owner input before store submission

**Still blocked:** `supportEmail` in `app/lib/screens/secondary_screens.dart` is empty. Before a store build:

1. create a real support/privacy mailbox;
2. put it in `supportEmail`;
3. replace the pending-contact notice in both public HTML pages (`server/internal/legal/site/`) and in the matching in-app sections with that address and the operator/developer identity that should appear publicly;
4. make the same contact information available in the store listing;
5. verify the two public URLs while signed out/incognito.

Do not invent an address or publish a personal address accidentally. This is an owner/legal identity decision, not a code default.

## Release checklist

- Review the actual product behavior against both documents.
- Run Flutter tests, including `app/test/legal_test.dart`.
- Verify Settings opens both documents.
- Verify a clean install cannot continue without checking consent.
- Verify an old `legal.acceptedVersion` is gated again after a version bump.
- Deploy the server, then verify `/privacy/`, `/terms/` and `/legal/` answer on it.
- Verify the public pages on mobile and desktop without authentication.
- Fill App Store Connect App Privacy and Google Play Data Safety from the implemented behavior, not from assumptions.
- Have the final legal text reviewed by a qualified professional if legal advice is required for the launch jurisdictions.
