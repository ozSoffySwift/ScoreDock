# App Store listing

Draft copy for App Store Connect. Everything here is a claim the app can currently back up — if a
line stops being true, the line changes, not the app.

> **§17 risk 1 resolved by rename.** The product was *ScoreCounter* until 30 July 2026. The App
> Store already carried *Scoreboard – Score Counter*, *Score Counter – Point Counter*, *Score Count*,
> *Score Keeper Point Counter* and *Point Counter – Scoreboard*, alongside the established
> scorecounter.com brand, so that name was a collision on trademark and on ASO alike. **ScoreDock**
> competes for none of it.
>
> Two checks still belong to a human before reserving the name: search the App Store for *ScoreDock*,
> and check the US/EU/IL trademark registries. Renaming is cheap now and expensive after launch.

---

## Name

    ScoreDock

30 characters max. Currently 9.

## Subtitle

    Scoreboard for 37 sports

30 characters max. Currently 24. Leads with the count because that is the one thing a browsing
referee can check at a glance, and it is literally true.

## Promotional text

*(170 characters. Editable without a review, so it carries whatever is current.)*

    Every feature free. No ads, no account, no subscription. Runs a real match on your phone and
    puts the board on your TV.

## Description

    ScoreDock is a scoreboard for the person actually running the game.

    Pick your sport, set the rules, and score. The board is big enough to read from across a hall,
    and it goes on a TV or a projector over AirPlay or a cable while the controls stay in your hand.

    37 SPORTS, OUT OF THE BOX
    Basketball, football, netball, handball, water polo, hockey, futsal and a dozen more team
    scoreboards. Tennis, volleyball, badminton, squash, table tennis and darts. League tables,
    leaderboards, knockout brackets and score sheets. Chess clocks, race timers, American football,
    cricket and baseball, each on a board built for that sport rather than a generic one.

    Every rule is editable, and every match keeps the rules it was played under.

    A BOARD PEOPLE CAN READ
    Twelve themes, each checked to a 7:1 contrast minimum between the digits and the background. A
    real seven-segment display face, with the unlit segments showing behind the score the way a
    venue board does. Turn the phone to fill the screen, or send the board to a TV and keep the
    controls on the phone.

    A CLOCK THAT IS ACTUALLY RIGHT
    The clock is anchored to real time, not counted down by the app. Lock the phone, take a call,
    force-quit — the clock is still correct when you come back, and a match left running is offered
    again next time you open the app.

    EVERY GAME, SAVED
    Every action is recorded with both the time of day and the game clock, so a disputed call lines
    up against video afterwards. Unlimited undo, and undo is itself part of the record — the log
    shows what happened, including the corrections.

    SHARE IT FIVE WAYS
    A scorecard image for group chats. Plain text that reads inline in any message. A formatted PDF
    for a league. A CSV of every event for your own analysis. Or the whole match as a file, which a
    friend with the app opens as a full report.

    PLAYERS AND TEAMS
    Save a team once with its colours and crest. Credit points to individual players if you want to —
    it is off by default, so scoring stays one tap — and their records build up across every match
    you play.

    YOUR MATCHES STAY YOURS
    Every match you score stays on your device. The only match data that ever leaves is a file you
    explicitly choose to share. There is no account, no sign-in, and nothing to sync.

    ScoreDock collects anonymous usage statistics — how often the app is opened, which boards get
    used — to understand what to build next. No advertising identifier, no cross-app tracking, and
    nothing that identifies you.

    FREE
    Every feature in this version is free. There is no paywall, no locked feature and no in-app
    purchase.

    Hebrew and English, with full right-to-left support.

## Keywords

*(100 characters, comma separated, no spaces after commas. Do not repeat words from the name or
subtitle — the store indexes those already.)*

    scoreboard,referee,basketball,tennis,volleyball,timer,shot clock,league,cricket,darts,chess,umpire

98 characters.

## Support and marketing URLs

- **Support URL** — required. Not yet chosen; needed before submission.
- **Marketing URL** — optional. Blocked on the same domain question as the name.
- **Privacy policy URL** — required even when nothing is collected. The text is short and can say so
  plainly; it still needs somewhere to live.

## App Privacy answers

The privacy manifest (`ScoreDock/Resources/PrivacyInfo.xcprivacy`) is the source of truth, and
App Store Connect's questionnaire must agree with it:

| Question | Answer |
|---|---|
| Do you collect data from this app? | **No** |
| Do you or your third-party partners use data for tracking? | **No** |
| Third-party SDKs | None |

`SubmissionTests` asserts the manifest still says exactly this, so the answers cannot drift away
from the binary.

## Age rating

4+. No user-generated content is shared through the app — files go through the system share sheet to
a destination the operator picks — and there is no web view, no advertising and no purchasing.

## Category

- Primary: **Sports**
- Secondary: **Utilities**

## Screenshots

Required at 6.9" and 13" (iPad). Not yet captured. The set should show, in order:

1. A live team board mid-game, landscape, in a strong theme — the product in one image.
2. The control panel in portrait, showing that the operator's screen and the board are different
   things.
3. A board on a TV with the phone in front of it — the feature a scoreboard website cannot match.
4. The Match Report with its play-by-play.
5. The sport picker, showing the breadth.

Every screenshot must use fictional team names. Real club names and crests are somebody else's
trademark.

## What to test (App Review notes)

    No account or login is required — every feature is available immediately.

    To see the external display feature, connect an Apple TV or an HDMI adapter and tap Display on
    the control panel. Without a second screen the app is fully functional; the board simply stays
    on the device.

    Rotating the device to landscape during a match switches from the operator's controls to the
    full board. This is intentional and is the app's primary interaction (see the Full screen button
    for the same thing without rotating).
