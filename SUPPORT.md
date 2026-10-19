# ScoreDock — Support

Thanks for using ScoreDock. This page is the official support contact for the app.

## Get help

**The fastest way to reach me is to [open an issue](https://github.com/ozSoffySwift/ScoreDock/issues/new).**
You don't need to be a developer — it's just a form. Please include:

- What you were doing when the problem happened
- Which sport / preset you were scoring
- Your iPhone or iPad model and iOS version
- A screenshot, if the problem is something you can see

I read every issue.

## Common questions

**Is ScoreDock free?**
Yes, entirely. Every feature in version 1.0 is free. There is no paywall, no locked
feature, and no in-app purchase of any kind.

**Does ScoreDock collect any of my data?**
None of your match data, ever. Scores, team names, players, photos and notes stay on your
device, and the only thing that leaves is a file you explicitly choose to share.

The app does collect anonymous usage statistics — how often it is opened and which boards
get used — via Firebase Analytics. It cannot read your advertising identifier and never
tracks you across other apps, which is why you are never asked for tracking permission.
See [Privacy](#privacy) below.

**My match clock looks wrong after I locked my phone.**
It shouldn't be — the clock is anchored to real time rather than counted down by the app,
specifically so that locking the phone, taking a call, or force-quitting doesn't lose
time. If you do see a wrong clock, that's a bug and I'd like to hear about it. Please open
an issue with the sport and roughly what happened.

**I closed the app mid-match. Did I lose the game?**
No. A match left running is offered for resume next time you open the app, restored from
its full event log.

**The rules for my league are different from the built-in preset.**
Every rule is editable in Setup before you start, and the match keeps the exact rules it
was played under. If a built-in preset's defaults are wrong for the standard code of that
sport, please tell me — the defaults are meant to match the governing body's published
rules and I want to fix any that don't.

**How do I get the board onto a TV?**
Connect an Apple TV via AirPlay screen mirroring, or plug in a USB-C/Lightning-to-HDMI
adapter. The board fills the external display automatically while your phone keeps the
operator controls. The in-app "Display" button walks you through it.

**Can I get my match out of the app?**
Yes, five ways: a scorecard image, plain text, a formatted PDF, a CSV of every event, or
the whole match as a `.sdgame` file that another ScoreDock user can open as a full report.

## Privacy

All match data, players and teams stay in the app's local storage on your device and are
never uploaded. There is no account and no sync.

ScoreDock does collect anonymous usage statistics through Firebase Analytics — an app
instance ID, device model, region and which boards are opened. It links the variant that
cannot read your advertising identifier, so it never tracks you across apps and never
shows an App Tracking Transparency prompt. Nothing you score or type is ever sent.

See the [full privacy policy](PRIVACY.md).

## Feature requests

Requests are welcome — [open an issue](https://github.com/ozSoffySwift/ScoreDock/issues/new)
and describe the sport or workflow you need. Requests that come from actually running
games are the most useful kind.

## Source

ScoreDock is open source: <https://github.com/ozSoffySwift/ScoreDock>
