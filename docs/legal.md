# Terms, privacy and consent

The legal surface has three parts and they must stay aligned:

1. `app/lib/screens/legal_screens.dart` — the copies players can read in the app and the consent gate.
2. `server/internal/legal/site/` — public HTML copies for App Store Connect, Google Play and people without the app. `app/test/legal_test.dart` reads the section headings out of these files and fails if the app is missing one, so the alignment is checked rather than promised.
3. `legalVersion` / `legal.acceptedVersion` — the device-local acknowledgement version.

Current document version: **1.1**, effective **23 September 2026**. 1.1 added purchases, subscriptions and ads (Terms §5, Privacy §2–4, §6–9), which is a material change, so every install is asked to accept again.

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
- purchases through the App Store and Google Play only; the server verifies the store's proof (StoreKit 2 signed transaction or Play purchase token) and keeps the result in memory with the session; no payment details reach us;
- Google AdMob for players without Premium, with Google UMP consent where the law requires it (EEA, UK) and Apple's tracking permission before the advertising identifier is used;
- no sale of personal data, no third-party analytics SDK and no crash-reporting SDK;
- UGC filtering, reporting and device-local hiding.

If any of those facts changes, review both documents and the App Store Privacy / Google Play Data Safety declarations before release.

## Operator identity

`Imposter IL` · `imposteril36@gmail.com`.

The documents name the service, not a person. Play's User Data policy asks the policy to name the entity it pertains to, and this matches the Play developer display name. **It does not keep the owner's legal name private:** on an individual developer account both stores publish the verified legal name as the seller on the store listing, and Play's EU trader disclosure shows name, address and email there. Registering a business is the only thing that changes that, and if one is registered later its legal name replaces `Imposter IL` in both documents.

The same address is the support, privacy and abuse-report contact. It appears in both public pages, in the matching in-app sections, and as `supportEmail` in `app/lib/screens/secondary_screens.dart`, which shows the contact row in Settings. Google Play requires the policy to name the entity it pertains to; Apple requires developer contact details reachable from the app.

## Store submission notes

**Apple: do not paste these Terms into the EULA field.** A custom EULA in App Store Connect must carry Apple's own minimum terms — scope of licence, Apple's non-liability, Apple as a third-party beneficiary, maintenance responsibility, export compliance. These Terms carry none of them, by choice. Leave the field empty so Apple's standard EULA applies, and let these Terms stand as the in-app house rules. Filling that field turns a working setup into a rejection.

**Age — read this before filling the console forms.** The documents say the content suits ages 6 and up, and that under-13s may play only with a parent's permission and supervision, the parent accepting on their behalf.

Declaring an audience that includes under-13s has consequences a blocklist does not satisfy on its own:

- Google Play's **Families policy** applies. It expects apps with player-written content aimed at children to moderate it, and it restricts what may be collected from a child.
- **COPPA** treats an IP address as personal information, so collecting one from a child needs verifiable parental consent — a checkbox on the child's own device is not that.
- Apple's age-rating questionnaire raises the rating for user-generated content regardless of what the documents say.

**Decided: declare the target audience as 13+ in both consoles.** The documents stay as they are — the content suits 6 and up, and a younger child plays with a parent. The console field is the target audience, not who is allowed to play, so the two do not conflict.

The reasoning, so it is not re-argued: promising a child audience would mean promising moderation of player-written text that we do not operate, and verifiable parental consent for the IP addresses we rate-limit on — a credit card or ID check, not a checkbox on the child's own phone. A 13+ rating costs a badge and stops nobody from installing or playing. Declaring 6 and being wrong costs removal from Play and a strike on the developer account.

Revisit only if moderation and verifiable parental consent are actually built.

**Data safety / App Privacy.** Declare what sections 3 and 7 of the privacy policy list, and nothing else:

- Ours: guest identifiers, nickname, avatar, IP for abuse prevention, the game content players write, and purchase history (the store's proof, for app functionality, not linked to an identity).
- Google Mobile Ads SDK, per Google's disclosure guides ([iOS](https://developers.google.com/admob/ios/privacy/data-disclosure), [Android](https://developers.google.com/admob/android/privacy/play-data-disclosure)): IP address / approximate location, device and advertising identifiers, product interaction, advertising data, diagnostics and performance. On iOS, device ID, advertising data and product interaction are marked "used for tracking"; that is only true after the player grants tracking permission, but the label is per app, not per player.
- In App Store Connect, "Tracking: Yes" with Google's tracking domains, as the SDK's own privacy manifest declares. In Play, "Data is shared" for the advertising ID and device identifiers.

No account, so Apple's account-deletion requirement (5.1.1(v)) does not apply. No analytics SDK, no crash-reporting SDK.

**Subscriptions.** App Store Connect metadata must link the Terms of Use and the Privacy Policy. With the EULA field empty, the Terms of Use link for Apple is the [standard EULA](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/); put it in the app description. The in-app purchase popup already links both documents.

**The SDK coupling.** Section 7 names Google AdMob and promises no third-party analytics or crash-reporting SDK. Adding Crashlytics or anything like it means editing that section, the Data Safety form and the App Privacy card in the same release — not afterwards.

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
- Fill App Store Connect App Privacy and Google Play Data Safety from the implemented behavior, not from assumptions, including the Google Mobile Ads SDK.
- Configure the AdMob consent message (UMP) for the EEA, the UK and Switzerland, and the IDFA explainer for iOS.
- Have the final legal text reviewed by a qualified professional if legal advice is required for the launch jurisdictions.
