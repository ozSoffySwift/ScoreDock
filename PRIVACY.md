# ScoreDock — Privacy Policy

**Last updated: 19 October 2026**

## The short version

Everything you score stays on your device. ScoreDock never uploads your matches, teams, or
players anywhere, and there is no account to create.

The app does collect **anonymous usage statistics** — roughly, how many people open it and
which boards they use — through Google Firebase Analytics. That data is not linked to you,
does not include anything you type or score, and is never used to track you across other
apps or websites.

## What stays on your device

When you use ScoreDock, the following is stored **locally, and only locally**:

- Matches you score, including the full timestamped event log for each one
- Teams and players you save, including any name, nickname, colour, emoji, or photo
- Custom sports presets you create or duplicate
- Your app settings — theme, board font, sound and haptic preferences

This lives in the app's own storage on your iPhone or iPad. It is included in your device
backup (iCloud or local) according to your own iOS backup settings, which are under your
control, not the app's. None of it is sent to us or to anyone else.

## What is shared, and only when you ask

ScoreDock can export a match as an image, plain text, PDF, CSV, or a `.sdgame` file. These
are created **only when you tap Share**, and they go wherever you send them via the standard
iOS share sheet. The app has no say in the destination and keeps no copy.

Photos you add to a player or team are stripped of EXIF metadata — including GPS location,
capture timestamps, and camera make and model — before they are stored or included in any
export.

## The analytics, in detail

ScoreDock uses **Firebase Analytics** (Google), deliberately configured without access to
your device's advertising identifier. Reading that identifier requires an additional
Firebase component that ScoreDock does not include. That choice keeps the app outside
Apple's definition of *tracking*, which is why ScoreDock never shows an App Tracking
Transparency prompt.

**What is collected:**

- A Firebase app-instance ID — random, specific to this app, and reset if you delete it
- Device model, iOS version, and app version
- Your country or region, derived from your IP address by Google and not stored as an IP
- App language
- Events such as first launch, session start, and which board types are opened

**What is never collected:**

- Your advertising identifier (IDFA) — the component that would read it is not included
- Any match data: scores, team names, player names, photos, venues, or notes
- Your name, email, or any account identifier — there is no account
- Your precise location
- Anything that identifies you personally

This data is processed by Google under their
[Firebase privacy terms](https://firebase.google.com/support/privacy). We use it only to
understand how much the app is used and which sports to improve next.

## What the app does not do

- It does not track you across other apps or websites.
- It does not show advertising.
- It does not require or offer an account, login, or registration.
- It does not make in-app purchases or process payments.
- It does not upload, sync, or back up your matches to any server.

## Permissions

ScoreDock requests access to your photo library **only** if you choose to add a photo to a
player or team. This uses the standard iOS photo picker, which runs outside the app and
returns only the single image you select — the app never gets access to your wider library.

## Children

ScoreDock is rated 4+ and contains no advertising, no purchasing, no web browsing, and no
user-generated content shared through the app.

It does collect the anonymous usage statistics described above, which are not linked to any
individual and contain nothing a child could enter. No match data, team names, or player
names are ever transmitted.

The app includes an **Anonymise** option for exports, which replaces player names with
initials and removes photos and crests. This is intended for youth sport, where sharing
identifying details of minors may be inappropriate.

## Changes to this policy

If this policy ever changes, the updated version will be published at this address and the
"Last updated" date above will change.

## Contact

Questions about privacy: [open an issue](https://github.com/ozSoffySwift/ScoreDock/issues/new)
on the ScoreDock repository.
