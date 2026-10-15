# Terms, privacy and consent

The legal surface has two copies, and they must stay aligned:

1. `app/lib/screens/legal_screens.dart` — the text players read in the app, offline too.
2. `site/` — the public pages for App Store Connect, Google Play and people without the app, published to **https://imposteril.github.io** by `.github/workflows/site.yml` on every push to `main` that touches `site/`. `app/test/legal_test.dart` reads the section headings out of these files and fails if the app is missing one, so the alignment is checked rather than promised.

Plus `legalVersion`, the version shown with the documents and in Settings.

`imposteril/imposteril.github.io` is output only. Never edit it by hand: the next publish overwrites it. The workflow pushes with a write deploy key on that repository, whose private half is the `SITE_DEPLOY_KEY` secret here.

Current document version: **1.4**, effective **14 October 2026**. 1.1 added purchases, subscriptions and ads (Terms §5, Privacy §2–4, §6–9); 1.3 added Firebase Crashlytics (Privacy §7); 1.4 adds the app's recent steps and the guest player id to crash reports (Privacy §7), sends contact to the support page in the app, moves agreement to the nickname screen and says how changes take effect without a consent screen (Terms §6 and §10, Privacy §2 and §12).

## Player flow

There is no consent screen at launch: neither store requires one, and a fresh install opens on Home, where one-device play needs nothing from the server. Players agree where they first send something others will read: the nickname screen (`OnboardingScreen`) says "By tapping Continue you agree to the Terms of Use and the Privacy Policy", with both documents a tap away. That is what App Review asks of apps whose players write for each other (guideline 1.2: users agree to terms with no tolerance for objectionable content). No guest session and no nickname reaches the server before it.

Terms and Privacy are readable from Settings at any time. A material change gets a new `legalVersion`; nobody is asked to accept again in the app (builds up to 9 did, through a launch gate that stored `legal.acceptedVersion`).

## Public URLs

- `https://imposteril.github.io/` — home; the **developer website** in both store listings
- `https://imposteril.github.io/privacy/` — the **privacy policy URL** in both stores
- `https://imposteril.github.io/terms/`
- `https://imposteril.github.io/support/` — the **support URL** App Store Connect requires
- `https://imposteril.github.io/app-ads.txt` — AdMob's seller verification
- `https://imposteril.github.io/en/` and `/en/privacy/`, `/en/terms/`, `/en/support/` — the English pages, for the English listings (App Store Connect takes a privacy and support URL per language)

`site/en/` is the app's English text (`app_en.arb`), section for section; `app/test/legal_test.dart` fails if its headings drift from the app's. The Hebrew and English pages link to each other.

GitHub Pages serves the `imposteril` organization's site at the root of `imposteril.github.io`, which counts as a site of its own (`github.io` is on the public suffix list). That root is what AdMob requires for `app-ads.txt`, and the Cloud Run hostname could not offer it. The main repository stays private; only `site/` is published.

The game server no longer hosts a copy. `/privacy/`, `/terms/` and `/legal/` on it answer with a permanent redirect to the site (`server/internal/legal`), because builds up to 3 link there and older store drafts may carry those URLs.

The app links to the public copy from each document screen (`publicSite` in `legal_screens.dart`).

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
- Firebase Crashlytics in release builds (collection is off natively until Dart turns it on, so debug builds never report): crash and error reports with the stack, the app's recent steps (screens, actions, error codes: the log in `app/lib/crash_reporting.dart`), device model, OS, app version, the random guest player id and a random Crashlytics installation id; no nickname, hints, secret word or advertising id; kept 90 days;
- no sale of personal data and no third-party analytics SDK;
- UGC filtering, reporting and device-local hiding.

If any of those facts changes, review both documents and the App Store Privacy / Google Play Data Safety declarations before release.

## Operator identity

`ImposterStudio` · `imposteril36@gmail.com`.

The documents name the service, not a person. Play's User Data policy asks the policy to name the entity it pertains to, and this matches the Play developer display name. **It does not keep the owner's legal name private:** on an individual developer account both stores publish the verified legal name as the seller on the store listing, and Play's EU trader disclosure shows name, address and email there. Registering a business is the only thing that changes that, and if one is registered later its legal name replaces `ImposterStudio` in both documents.

The same address is the support, privacy and abuse-report contact. It appears on the public pages only (including `/support/`); by the owner's choice the app shows no email, and its documents point to `imposteril.github.io/support` where the public ones give the address (Terms §1 and §12, Privacy §1, §10 and §13). That is the one intended difference between the two copies. Google Play requires the policy to name the entity it pertains to and give a contact, which the public policy does; Apple's "published contact information" for UGC apps is the support URL in App Store Connect and the support page the app links to.

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
- Google Mobile Ads SDK, per Google's disclosure guides ([iOS](https://developers.google.com/admob/ios/privacy/data-disclosure), [Android](https://developers.google.com/admob/android/privacy/play-data-disclosure)): IP address / approximate location, device and advertising identifiers, product interaction, advertising data, diagnostics and performance. On iOS the device ID is marked "used for tracking"; that is only true after the player grants tracking permission, but the label is per app, not per player.
- In App Store Connect, follow the privacy manifest of the Google Mobile Ads SDK the app ships (`PrivacyInfo.xcprivacy` in the framework), not this list. In the version built in October 2026 only **Device ID** is "used for tracking"; Coarse Location, Product Interaction and Advertising Data are linked to the user but not tracking; Performance, Crash and Other Diagnostic Data are not linked. In Play, "Data is shared" for the advertising ID and device identifiers.

- Firebase Crashlytics: crash logs and diagnostics, plus the installation id and the random guest player id as identifiers, collected for app functionality (analytics of crashes), not linked to an identity, not used for tracking, not shared. In App Store Connect: Crash Data and Other Diagnostic Data, "Not Linked to You".
- App Store Connect, from 1.4: add **User ID** (the guest player id Crashlytics receives) for App Functionality, not linked to you, not used for tracking. In Play it falls under Device or other IDs, already declared for Crashlytics.

No account, so Apple's account-deletion requirement (5.1.1(v)) does not apply. No analytics SDK.

**Subscriptions.** App Store Connect metadata must link the Terms of Use and the Privacy Policy. With the EULA field empty, the Terms of Use link for Apple is the [standard EULA](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/); put it in the app description. The in-app purchase popup already links both documents.

**The SDK coupling.** Section 7 names Google AdMob and Firebase Crashlytics and promises no third-party analytics SDK. Adding analytics or anything like it means editing that section, the Data Safety form and the App Privacy card in the same release — not afterwards.

**Distribution.** The rights section names Israeli law and the GDPR. If Play distribution stays worldwide, that stays accurate; restricting countries later does not require a change, but widening the data practices does.

## Release checklist

- Review the actual product behavior against both documents.
- Run Flutter tests, including `app/test/legal_test.dart`.
- Verify Settings opens both documents.
- Verify the nickname screen shows the agreement line and opens both documents.
- After the site workflow runs, verify `https://imposteril.github.io/privacy/`, `/terms/`, `/support/` and `/app-ads.txt` answer, signed out, and that the server's old `/privacy/` redirects there.
- Confirm the App Store Connect EULA field is empty.
- Verify the public pages on mobile and desktop without authentication.
- Fill App Store Connect App Privacy and Google Play Data Safety from the implemented behavior, not from assumptions, including the Google Mobile Ads SDK.
- Configure the AdMob consent message (UMP) for the EEA, the UK and Switzerland, and the IDFA explainer for iOS.
- Have the final legal text reviewed by a qualified professional if legal advice is required for the launch jurisdictions.
