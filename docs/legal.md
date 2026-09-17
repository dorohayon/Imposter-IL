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

## Operator identity

Dor Ohayon, independent developer · `imposteril36@gmail.com`.

The same address is the support, privacy and abuse-report contact. It appears in both public pages, in the matching in-app sections, and as `supportEmail` in `app/lib/screens/secondary_screens.dart`, which shows the contact row in Settings. Google Play requires the policy to name the entity it pertains to; Apple requires developer contact details reachable from the app.

## Store submission notes

**Apple: do not paste these Terms into the EULA field.** A custom EULA in App Store Connect must carry Apple's own minimum terms — scope of licence, Apple's non-liability, Apple as a third-party beneficiary, maintenance responsibility, export compliance. These Terms carry none of them, by choice. Leave the field empty so Apple's standard EULA applies, and let these Terms stand as the in-app house rules. Filling that field turns a working setup into a rejection.

**Age.** Both documents state 13 as the minimum. The App Store age rating and the Play target-audience declaration must agree with that, and with the UGC answers.

**Data safety / App Privacy.** Declare what section 3 of the privacy policy lists, and nothing else: guest identifiers, nickname, avatar, IP for abuse prevention, and the game content players write. No account, so Apple's account-deletion requirement (5.1.1(v)) does not apply. No advertising identifier, no analytics SDK, no crash-reporting SDK.

**The crash-reporting coupling.** Section 7 promises no third-party analytics or crash-reporting SDK. Adding Crashlytics or anything like it means editing that section, the Data Safety form and the App Privacy card in the same release — not afterwards.

**Distribution.** The rights section names Israeli law and the GDPR. If Play distribution stays worldwide, that stays accurate; restricting countries later does not require a change, but widening the data practices does.

## Release checklist

- Review the actual product behavior against both documents.
- Run Flutter tests, including `app/test/legal_test.dart`.
- Verify Settings opens both documents.
- Verify a clean install cannot continue without checking consent.
- Verify an old `legal.acceptedVersion` is gated again after a version bump.
- Deploy the server, then verify `/privacy/`, `/terms/` and `/legal/` answer on it, signed out.
- Confirm the App Store Connect EULA field is empty.
- Verify the public pages on mobile and desktop without authentication.
- Fill App Store Connect App Privacy and Google Play Data Safety from the implemented behavior, not from assumptions.
- Have the final legal text reviewed by a qualified professional if legal advice is required for the launch jurisdictions.
