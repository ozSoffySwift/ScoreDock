# ScoreDock

Native iOS/iPadOS scoreboard app. Implementation of the ScoreDock product specification v1.0.

**Milestone status: M0–M8 complete.** M2's exit criterion was confirmed on physical hardware on
5 August 2026 — see "M2" below.

Every milestone the spec defines is now done. What remains before submission is content that needs
human authority — a referee for the rule defaults, a native speaker for the Hebrew, a trademark
check on the name. All of it is listed and counted below.

§18 recommends shipping at M3, and the app now does what that milestone asks: *"runs a great game,
logs it, and lets you share it."*

> **Naming — §17 risk 1 is now closed.** The product was renamed from *ScoreCounter* to
> **ScoreDock** on 30 July 2026, and the name is committed to throughout: target, scheme, module,
> bundle identifier (`com.ozsoffy.scoredock`), CloudKit container, exported UTI and the `.sdgame`
> file extension.
>
> That risk existed because the App Store already carried *Scoreboard – Score Counter*, *Score
> Counter – Point Counter*, *Score Count*, *Score Keeper Point Counter* and *Point Counter –
> Scoreboard*, alongside the established scorecounter.com brand — a collision on every axis that
> matters, from trademark to ASO. Renaming resolves it by not competing for that phrase at all.
>
> **Two checks still belong to a human**, and no amount of renaming substitutes for them: search the
> App Store for *ScoreDock*, and check the US/EU/IL trademark registries before reserving it.
>
> Three things were deliberately **not** renamed:
>
> - **`scorecounter.com`** in this file, `Submission/listing.md` and `ScoreDockApp.swift` — that is a
>   different company's brand and the subject of the risk, not a reference to this app.
> - **The preset slug `custom-scoreboard`**, and the word "scoreboard" wherever it is a domain noun
>   ("Team scoreboards", "Custom scoreboard", `ScoreboardView`). Slugs are persisted in
>   `Match.presetSlug` and `PresetPreference.slug`, so changing one silently orphans saved history —
>   and "scoreboard" is what the thing *is*, independent of what the app is called.
> - **Anything a user has already saved.** Nothing had shipped, so the bundle-identifier change cost
>   nothing; on a shipped app it would have stranded every install's local store.

## Build and run

```bash
xcodebuild -scheme ScoreDock -destination 'platform=iOS Simulator,name=iPhone 17' build
```

```bash
xcodebuild test -scheme ScoreDock -destination 'platform=iOS Simulator,name=iPhone 17'
```

**The build is warning-free, and it has to stay that way.** Check with a *clean* build — an
incremental one recompiles nothing and therefore re-emits nothing, so it will happily report silence
it has not earned:

```bash
xcodebuild clean build -scheme ScoreDock -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | grep warning:
```

### Validating the schema against CloudKit (§7.5)

v1 ships with `cloudKitDatabase: .none`. To validate the schema against the CloudKit development
environment, launch with the debug argument — the container opens with `.automatic` and refuses on
any violation:

```bash
xcrun simctl launch booted com.ozsoffy.scoredock -validate-cloudkit-schema
```

Success is a normal launch. Failure shows a yellow "Saved data is unavailable" banner and falls back
to an in-memory store. `ScoreDockTests/CloudKitSchemaTests` covers the same rules statically with no
entitlement or account, which is what runs in CI; both halves are needed, neither is sufficient.

## Layout

| Path | Contents |
|---|---|
| `Config/` | `Info.plist`, entitlements. Outside the synchronized group so they are not copied as resources. |
| `Submission/` | App Store listing copy and the answers App Store Connect asks for (§18 M8). |
| `ScoreDock/Model/` | The nine `@Model` types and the stored-enum pattern (§7.1). |
| `ScoreDock/Rules/` | `AnyRuleSet` and the four engines' rule structs (§7.3), plus `RuleSummary`. |
| `ScoreDock/Catalog/` | `catalog.json` (37 built-ins) and the `GameCatalog` merge layer (§7.4). |
| `ScoreDock/Theme/` | 12 themes, WCAG maths, `BoardFont`, `BoardSpecimenView` (§9). |
| `ScoreDock/Engine/` | Clock, team engine, event replay (§6). |
| `ScoreDock/Feedback/` | Audio, haptics, cue scheduling (§11). |
| `ScoreDock/Identity/` | Emoji and image marks, EXIF stripping (§7.1a). |
| `ScoreDock/Report/` | Statistics, Match Report, five share formats (§13). |
| `ScoreDock/Features/` | One folder per tab, plus `Match/` (§3). |
| `ScoreDockTests/` | 333 tests in 25 suites. |

The project uses Xcode 16+ **synchronized folder groups**: files added under `ScoreDock/` and
`ScoreDockTests/` are picked up automatically, with no `project.pbxproj` edit.

## M0 exit criteria

| Criterion | Status |
|---|---|
| All 37 presets browsable | ✅ 20 team · 8 set-match · 5 specialised · 4 list, grouped, searchable, favouritable |
| Board font correct on device | ✅ DSEG7 Classic bundled and verified by PostScript name; ghost segments render on all 12 themes. Settings → Board appearance |
| Schema verified against CloudKit | ✅ Positive and negative control both confirmed on device (see below) |

The CloudKit check was verified with a **negative control**: temporarily adding `@Attribute(.unique)`
made the `.automatic` container throw `SwiftDataError error 1`, confirming the validation has teeth
rather than silently passing. That control also caught a real bug — the in-memory fallback was
reusing the same CloudKit mode, so a schema failure took the fallback down too. Fixed in
`AppModelContainer.make(inMemory:)`.

## M1 exit criteria

> *"A full basketball game runs, and its complete timestamped log is saved."*

Verified on device end-to-end: Basketball — FIBA, played to **Home 6 – Guest 2**, finished, and
persisted. Reading the SQLite store directly shows five contiguous events, each carrying **both**
clocks required by §13.2 — `matchClock` counting down 600.0 → 534.6 while wall-clock ran
16:16:29 → 16:17:34:

```
idx kind             val slot per matchClock  wall-clock
  0 clockToggle        0 None   1      600.0  16:16:29
  1 score              3    0   1      591.6  16:16:37
  2 score              3    0   1      584.4  16:16:45
  3 score              2    1   1      577.7  16:16:51
  4 matchFinish        0 None   1      534.6  16:17:34
```

| Piece | Where |
|---|---|
| Date-anchored clock (§6.4) | `Engine/MatchClock.swift` |
| Pure team engine (§6.1) | `Engine/TeamEngine.swift`, `TeamState.swift` |
| Event sourcing + undo/redo (§6.6) | `Engine/MatchReplay.swift`, `EventCoding.swift` |
| Live store, log written continuously (§13.1) | `Features/Match/LiveMatchStore.swift` |
| Board + interactive preview (§4.2, §4.3) | `Features/Match/ScoreboardView.swift`, `BoardView.swift`, `ControlPanelView.swift` |
| Setup (§4.1) | `Features/Match/MatchSetupView.swift` |
| Rotate-to-board + forced landscape (§5.1) | `Features/Match/MatchContainerView.swift`, `OrientationReader.swift`, `App/AppDelegate.swift` |

### Four bugs worth remembering

1. **SwiftData cannot store `AnyRuleSet` directly.** It treats a `Codable` enum with associated
   values as a *composite attribute*, compiles fine, opens the store fine, validates against
   CloudKit fine — then traps on the first save with `unknown property payload for composite
   description`. Rules and themes are now `Data` via `Model/CodableBlob.swift`, which is what §7.3
   asked for anyway. `CloudKitSchemaTests.codableBlobsRoundTrip` writes real values so this cannot
   regress; "the container opens" was never sufficient.
2. **`Info.plist` alone does not permit rotation.** The SwiftUI hosting controller narrows the
   supported set, and `requestGeometryUpdate` is refused with *"Supported: portrait"*. `AppDelegate`
   implements `supportedInterfaceOrientationsFor` to widen it. Since §5.1 makes the full-screen
   button the *mandatory* mitigation for rotation lock, this had to actually work.
3. **Order matters in that request.** `setNeedsUpdateOfSupportedInterfaceOrientations()` only marks
   the controller dirty; requesting geometry in the same turn is evaluated against the stale mask,
   refused, and then usually applied on the next pass anyway — so it appears to work while logging
   an error every time. The request is deferred one main-actor hop.
4. **`ScoreboardView` sized everything from height.** In a portrait container that produced 350 pt
   digits overflowing the screen. It now letterboxes to a board aspect, so the full-screen board is
   correct in both orientations and degrades sanely if a forced rotation is ever refused.

## M2 — external display, sound, haptics

> *"Board runs on an Apple TV while the panel stays live on the phone."*

**Signed off on physical hardware, 5 August 2026.** The board runs on the external display while
the control panel stays live on the phone, confirmed by the author on a real device.

This could not be verified from the development environment: §5.5 states plainly that the iOS
Simulator does not faithfully reproduce external-display scene-role behaviour or AirPlay latency,
and `simctl` has no external-display command. Everything below was built and unit-tested first; the
"Verified how" column records the state *before* hardware confirmation, and is kept as written
because it is an accurate account of what automated testing could and could not reach.

| Built | Where | Verified how |
|---|---|---|
| Audio, `.playback` + `.mixWithOthers` (§11.1) | `Feedback/MatchAudio.swift` | Previewed on device; CoreAudio converters confirmed in the log |
| Five synthesised sounds | `Resources/Sounds/` | Generated, bundled, load-checked at runtime |
| Haptics incl. sustained buzzer (§11.2) | `Feedback/MatchHaptics.swift` | Compiles and wires; no haptics hardware in the simulator |
| Wall-clock sound scheduling (§6.4) | `Feedback/MatchFeedback.swift` | 10 unit tests over the pure `cues(...)` function |
| External scene + delegate (§5.2) | `Features/Match/ExternalDisplayScene.swift` | Routing and shared-store unit tests |
| Board modes (§6.1) | `Features/Match/ExternalBoardView.swift` | Unit tested; rendering unverified on a real panel |
| Casting sheet (§5.4) | `Features/Match/CastingSheet.swift` | Verified on device |
| Behaviour matrix (§5.3) | `MatchSurface`, `MatchContainerView` | 4-case unit test |
| Battery + thermal guards (§12) | `Features/Match/VenueMonitor.swift` | Compiles; simulator reports no real battery or thermal state |

### Notes

- **Sounds are scheduled, not observed.** §6.4 requires the period buzzer to fire against the
  wall-clock instant the clock reaches zero, so it stays accurate when the UI is throttled. The
  schedule is computed by a pure, time-injected function, which is why it can be tested at all.
- **A break suppresses the period buzzer**, so half-time never triggers an end-of-period horn.
- **The scene delegate is assigned in code, not in `Info.plist`.** A plist entry has to name the
  class as `"$(PRODUCT_MODULE_NAME).ExternalDisplaySceneDelegate"`, which breaks silently on a
  module rename — and this project has already been renamed once.
- **`AppSettings` and `ActiveMatch` are shared instances.** The external scene delegate is created
  by UIKit outside any SwiftUI hierarchy, so it cannot read `@Environment`; §5.2's "one store,
  injected into both scenes" needs a reachable holder.

## M3 — library, report, sharing 🚢

> *"Shippable v1.0 — runs a great game, logs it, and lets you share it."*

Verified on device: a match played through to the Match Report, which shows the period table,
largest lead, longest run and a live preview of the share card; the share sheet offers all five
formats, states what each contains, and reports the file size (79 KB for the image).

| Built | Where |
|---|---|
| Players, Teams, rosters (§7.1a) | `Features/Library/PlayersView.swift`, `TeamsView.swift` |
| Identity marks, EXIF stripping | `Identity/IdentityImage.swift`, `IdentityEditor.swift`, `IdentityMarkView.swift` |
| Opt-in attribution (§4.1, §4.2) | `Features/Match/AttributionSheet.swift` |
| Statistics (§13.3) | `Report/MatchStatistics.swift` |
| Match Report (§13.4) | `Report/MatchReportView.swift` |
| Five formats, batch, print, anonymise (§13.5–13.6) | `Report/MatchExport*.swift`, `ShareCardView.swift`, `MatchRenderer.swift`, `SdGameDocument.swift`, `MatchShareSheet.swift` |
| Stats tab (§7.2) | `Report/StatsAggregator.swift`, `Features/Stats/StatsView.swift` |
| iPad two-column panel (§4.2a) | `Features/Match/PadControlPanelView.swift` |

### The privacy guarantee, and how far it actually goes

§7.1a requires stripping metadata on import, "GPS especially", because these images end up inside
shared files. `IdentityImageTests` builds a JPEG that genuinely carries GPS, EXIF `UserComment` and
`DateTimeOriginal`, then asserts they are gone after import.

One honest narrowing: an earlier version of that test demanded **no metadata containers at all**,
and that is not achievable — every encoder writes a fresh structural EXIF/TIFF block (pixel
dimensions, colour space, orientation), and suppressing it via `CGImageDestination` broke PNG
output entirely. `IdentityImage.sensitiveMetadata(in:)` therefore checks what actually matters:
GPS in any form, capture timestamps, free-text comments, camera make/model/owner, IPTC and Apple
maker notes. Structural tags identify nothing and are allowed through.

### Three bugs the device found that tests did not

1. **Swipe-dismissing the player/team editor left an empty record.** Cleanup only ran in the Done
   button. It now runs from `sheet(onDismiss:)`, so it happens however the sheet closes — and is
   strict about "empty", since a player with only an emoji is a deliberate record.
2. **The share-card preview rendered blank.** `scaleEffect` is a rendering transform and does not
   change layout size, so a 1920 × 1080 card stayed laid out at full size inside a zero-height
   `GeometryReader`. Fixed by establishing the frame first (`Color.clear` at the card's aspect) and
   drawing the card into it as an overlay.
3. **The emoji score line read `🐺 Wolves 62 – 🦅 Eagles 58`.** §7.1a's example mirrors the away
   side — `🐺 Wolves 62 – 58 Eagles 🦅` — so the scores meet in the middle and each mark sits on its
   own outer edge. It reads like a result rather than a list.

## M4 — set-match engine

> *"Tennis and volleyball matches run correctly."*

Verified on device: a tennis match scored to deuce and on to **Ad – 40**, with the board leading on
sets and showing games and points alongside. Volleyball is covered by the engine tests, including
the 24-all run-on and the deciding set to 15.

All three notations share one engine, because they share one shape — points roll into a unit, units
roll into sets, sets decide the match. Only the size of each rung differs:

| Notation | Point → | → Set |
|---|---|---|
| `numeric` | points accumulate in the set directly | first to `pointsPerSet`, win by two, hard cap |
| `tennis` | 0/15/30/40/Ad → a game | six games by two, or a tiebreak at 6–6 |
| `dartsCountdown` | a visit subtracts from 501 → a leg | `legsPerSet` legs |

Deuce and advantage are **not** special-cased: they fall out of "win by two", because at 3–3 neither
side can reach a two-point gap without first going to advantage. That is why the same code path
serves tennis games, tiebreaks and volleyball sets.

| Built | Where |
|---|---|
| Engine and state | `Engine/SetMatchEngine.swift`, `SetMatchState.swift` |
| Darts checkouts | `Engine/DartsCheckout.swift` |
| Board, panel, setup, container | `Features/Match/SetMatch*.swift` |
| Store | `Features/Match/SetMatchStore.swift` |

### Notes

- **`ScoreEngine` gained an associated `Board` type.** A team board leads with a clock, a set-match
  board leads with sets won. Forcing both through one struct would mean a pile of properties that
  are nil most of the time — the shape §7.3 rejects for rules, for the same reason.
- **Checkouts are solved, not tabulated.** A hardcoded 2–170 table is 169 rows to type correctly
  once; a search over the board's real segments cannot contain a transcription error and adapts for
  free when `doubleOut` is off. A test walks every score from 2 to 170 and checks each suggestion
  genuinely sums to its target and finishes on a double.
- **`SetMatchStore` is a sibling of `LiveMatchStore`, not a generic over both.** The hard parts —
  undo resolution, snapshot validity, action coding — already live in `MatchReplay` and
  `EventCoding` and are shared; only thin orchestration is duplicated. Abstracting on the second
  instance would mean guessing at what the specialised engines (§6.3) need, and they are the most
  likely to break the guess. Revisit at M6.
- **Darts is entered as a visit total, not per dart** — which is how a scorer works, and why a bust
  reverts the whole visit.

## M5 — list and table engine

> *"Leaderboard, standings, bracket, score sheet."*

All four verified on device. The standings table computes points from records (5 W = 15) and derives
goal difference, and six teams tied on nothing all show **rank 3** rather than 3-through-8. The
bracket lays out an 8-seed draw as QUARTER → SEMI → FINAL and advances the winner. The score sheet
sums R1–R10 into Σ per row and per round (30 + 26 = 56 = 23 + 17 + 11 + 5). The leaderboard ranks
highest-first with the seven-segment totals.

This is the engine that uses **N participants** rather than two sides — `MatchSide.slotIndex` was
always specified as "0 = home, 1 = visitor, n for leaderboards" (§7.1), and this is where the *n*
finally gets used. Nothing here assumes a sport, so §19.2 question 1 (board-game portfolio
integration) stays a data question rather than a rewrite.

| Built | Where |
|---|---|
| Engine and state | `Engine/ListEngine.swift`, `ListState.swift` |
| Board, panel, setup, container | `Features/Match/List*.swift` |
| Store | `Features/Match/ListStore.swift` |
| Per-engine preset preview | `Features/Play/PresetPreviewView.swift` |
| Shared summary line | `Report/MatchSummaryLine.swift` |

### Notes

- **Ranking is standard competition ranking, and ties are marked as well as shared.** §6.5 asks for
  ties to be "handled explicitly"; a board that silently orders equal scores invites an argument.
- **A score sheet's total is always the sum of its rounds**, never a separate number that could
  drift away from them.
- **A bracket is a flat breadth-first array of `size - 1` matches.** Setting an earlier result clears
  everything downstream of it — a stale finalist would be worse than an empty later round.
- **`ListStore` is the third sibling store, still not a generic.** The pattern has now repeated three
  times and is stable, which is the argument *for* extracting a base — but M6's specialised engines
  are the most likely to break a guess at the right shape, so it stays a fourth-case decision. See
  the M4 note above.

### Bugs worth remembering

1. **Every preset was previewed with the same team scoreboard.** A league table was advertised as
   HOME 1 / 05:00 / GUEST 2. The preview is the main thing the detail screen is *for*, so
   `PresetPreviewView` now renders through the same views the live board uses, switching on the
   engine — and supplies a full 8 seeds for a bracket, because half an empty draw reads as broken.
2. **An empty half of an oversized bracket was labelled "BYE".** A bye is *exactly one* entrant with
   no opponent, who then advances unplayed; a place with neither entrant is just an unused half and
   nobody advances out of it. Same reasoning removed the "x of y decided" denominator from the
   bracket summary: in an oversized bracket some places can never be decided, so any denominator
   drawn from the bracket size is a target the tournament cannot reach.
3. **An eight-team league summarised as `Team 1 0 – Team 2 0 – Team 3 0 – …`.** Two independent
   faults: the wrong *shape* (a two-side score line joined across eight participants) carrying the
   wrong *number* (`Match.displayScores` sums `.score` events, but a standings figure is points
   derived from win/draw records, so every row was structurally 0). Both call sites — the Play resume
   row and History — now go through `MatchSummaryLine`, which is engine-aware and reads
   `1. Team 1 3 · 2. Team 2 1 · 3. Team 3 0 · +5 more`.

## M6 — specialised boards

> *"The five bespoke boards."*

§18 sequences these deliberately, easiest first, and §17 risk 2 calls them "five small apps" — the
most likely part of the backlog to slip. They landed **one at a time**, each verified running before
the next was started, and a preset whose board did not exist yet said so rather than opening an empty
scoreboard. `SpecialisedEngine.implementedBoards` is the single source of that truth, read by both
the router and the store; it now holds all five, and stays for a match synced from a build that knows
a board this one does not.

| Board | State |
|---|---|
| Chess clock | **Done** — verified on device |
| Race timer | **Done** — verified on device |
| American football | **Done** — verified on device |
| Cricket | **Done** — verified on device |
| Baseball | **Done** — verified on device |

### Structure

One `SpecialisedEngine` and one `SpecialisedStore` own the plumbing; five pure sub-engines own the
rules. The engine routes on a discriminator and holds no rules of its own.

That split is the hedge against risk 2. The five games share **nothing** in their rules — which is
why `SpecialisedRules` was already a discriminator plus optional sub-structs — but they share *all*
of the plumbing: event log, undo resolution, snapshots, crash recovery, the container, the surface
rules. Five stores would have duplicated that to buy nothing, and one abstract engine would have
forced each sport to accommodate the others.

`SpecialisedStore` is the fourth sibling store, and the fourth case the M4 note said to wait for.
Having now seen all four: the duplication is about thirty lines of orchestration differing only in
engine type, and a generic base would trade that for a protocol with four associated types and no
behaviour. The sibling shape stays.

### The action vocabulary

`EngineAction` gained **one** case, `.specialised(SpecialisedAction)`, rather than eleven flat ones.
`EngineAction` is the *cross-engine* vocabulary — which is why `TeamEngine` switches over it with no
`default`, so that adding a case forces every engine to decide what it means. Pressing a chess clock
has no meaning on a basketball board and never will, so eleven flat cases would have added eleven
dismissals to every engine and diluted exactly the signal that check exists to give.

Each bespoke action still earns its own `EventKind`, because §13.3 wants a play-by-play a person can
read: `4`, `1NB`, `Wicket — LBW`, `Down 3 & 7`.

### Chess clock

Each side stores **time spent**, counting up, and remaining is derived — `baseTime + bonus − spent`
— so nothing ever decrements and a backgrounded app returns with both clocks correct (§6.4).

- **Fischer and Bronstein are one code path.** A Bronstein delay is exactly "return the lesser of the
  delay and the time the move used", so both modes are a single `bonus` accumulator rather than two
  implementations. A pause mid-move does not fool it: `spent` stops accruing while paused, so the
  move time it reads back already excludes the interruption.
- **A flag decides the game; nothing else can.** ScoreDock is a clock, not an arbiter — it has no
  idea whether a position was mated, resigned or agreed drawn. A game that ends without a flag
  returns **no outcome**, and every side is recorded `.unfinished`, which is the truth. Inventing a
  draw would put a made-up result into the player's history.
- **A flag is the only state change in the app with no tap behind it**, so `checkForTimeExpiry` is
  the one thing `SpecialisedStore` does that its three siblings do not. The board's tick calls it,
  and it appends a real `.finishMatch` event — keeping undo and the play-by-play honest.
- **Pressing out of turn does nothing**, the same as a physical clock where the opponent's button is
  already down. That is what stops a fumbled double-tap from banking a second increment.
- **Nobody is charged for time before the game starts.** The app cannot bill a player for time it was
  never asked to measure, which is why the board leads with Start rather than with two clock faces.

### Race timer

One clock serves the whole field — a race has a single start gun, and every racer's time is a
position on that one timeline.

- **Crossing times are stored, not lap durations.** That is what makes undo work: removing a
  mis-tapped lap leaves the neighbouring durations correct with nothing to recompute. A test drives
  exactly that case.
- **Nobody is placed until they have crossed something.** Handing out 1st through 4th at the start
  line would be inventing a result; the field is in slot order at that point purely by accident.
- **A lap before the gun is refused** rather than recorded as a 0.000 split the operator then has to
  find and undo.
- **A fixed-distance race finishes a racer on their final lap** without a second tap; an open race
  finishes them on a long-press.

### American football

Most of this board was already in the shared vocabulary — score, timeout, period, clock, possession
— and the play clock maps exactly onto the shot-clock actions, tap for 40 and long-press for 25
(§4.2). Only two things are genuinely new, and both are about *where the ball is*.

- **`ballOn` is measured from the possessing team's own goal line, not as a painted field number.**
  That is the frame in which a first down and "and goal" are decided. The number a board shows —
  counting up to midfield and back down — is derived from it, which is why an offence-frame 62 reads
  `BALL ON 38`.
- **A turnover mirrors the spot.** The ball does not move when possession changes, but the frame
  does, so `ballOn` flips to `fieldLength − ballOn` and a fresh set of downs starts. Verified on
  device: flipping possession on the 26 left `BALL ON 26` and reset 3RD & 10 to 1ST & 10. Without
  the mirror, a change of possession on the 30 would have read as the other team's 30 — and a
  first-and-ten near a goal line would silently become first-and-goal.
- **"And goal" is not a distance of ten or less.** It is the line to gain *being* the goal line, so
  it is computed from the spot rather than from the yardage, and six yards to go from midfield still
  reads `1ST & 6`.

### Cricket — and §17 risk 12

Risk 12 is real and it lives here: every delivery is an event, so a T20 innings is 120-odd events
before extras and a Test is thousands — by a wide margin the largest log the app produces. Two things
already in the shared plumbing keep it manageable, and neither is special-cased for cricket:
`SpecialisedStore` snapshots every 50 events, so a replay never walks more than fifty deliveries, and
each event is four small columns rather than a serialised state. A test bowls a full 128-delivery
innings and checks it replays identically.

The rule the whole board hangs off: **a wide is a delivery but not a ball.** So `legalBalls` is
tracked explicitly and never derived by counting events. Verified on device — 4, then a wide, then 1
gives `6-0` in **0.2** overs with 1 extra.

- **`runs` on a delivery is what was scored *in addition to* the extra's own penalty.** A wide with
  nothing run is `runs: 0` and adds one; a no-ball hit for four is `runs: 4` and adds five.
- **Overs are base-`ballsPerOver`, not decimal.** 12.5 plus one ball is 13.0.
- **A chase ends the moment the target is passed** — the remaining balls are not bowled.
- **A Test's fourth-innings target is an aggregate**, because the chasing side has already batted
  once and that innings counts. Written as `opponent − own earlier + 1` rather than "their total plus
  one", which is only right for a two-innings match.

### Baseball

**The line score is the board.** Every other sport here has a score; baseball has a *table* — runs by
inning, then R / H / E — and that grid is what a ballpark scoreboard shows.

- **A blank cell and a zero are different facts.** The home side leading after the top of the ninth
  never bats, and a line score printing 0 there would be lying. `lineScore` is `[Int?]`, and the
  board draws an en-dash for nil. Verified on device: at the start of a game the visitors show `0` in
  the first and the home side shows `–`.
- **The score changes only when the operator says so, or when the rules leave no choice.** A pitch
  moves the count, the outs and the bases; runs come from the explicit Run control or from a *forced*
  runner crossing the plate. A forced run is not a judgement call — everything else (a runner taking
  an extra base, a double, a runner thrown out stretching) is set through the bases control, because
  guessing at baserunning would put invented runs into a game decided by them.
- **A foul can never be the third strike**, which is the one rule that makes it not simply a strike.
- **The end of a game is reported, not enforced.** A walk-off ends play mid-inning and the home side
  never bats the bottom of the ninth when it is already ahead, so `isComplete` tells the panel and
  the operator decides.
- Bases are three flags rather than a count, because a force play depends on *which* bases are
  occupied. The board draws them where they are — a runner on second is at the far corner, not
  second in a row of three lights.

### Bugs worth remembering

0. **The race board re-sorted under the operator's finger.** Recording a lap promoted that racer to
   first, so the next tap in the same place landed on somebody else — with a field crossing the line
   seconds apart, a mis-tap waiting to happen. The rule now is **if you can tap it, it does not
   move**: the interactive surface keeps a fixed entry order and shows the placing as a number, and
   only the display surface sorts into running order. Found by running a race, not by reading the
   code.
1. **Two clocks rendered as `05:0005:00`.** The face was sized from height alone, so side by side the
   digits overran their half and collided. `MM:SS` is five glyphs and a seven-segment glyph is about
   0.62 em, so a face needs roughly 3.2 × the point size — and the `.fixedSize()` I had put on the
   number was defeating `LEDNumber`'s own scale-down-rather-than-truncate rule.
2. **`^[\(count) move](inflect: true)` rendered literally.** Automatic grammar agreement resolves only
   against a localisation *catalog* entry; these in-source `String(localized:)` keys have none, so the
   board read `[1 move](inflect: true)`. Replaced with a static uppercase label and the number after
   it — `MOVES 12` — which matches SETS / GAMES / LEGS on the other boards and needs no pluralisation
   in any language.
3. **The Set-time sheet always opened at 5:00** regardless of what was on the clock, so pressing Set
   without touching anything moved time. Seeded from the running clock instead.
4. **Two adjacent setup rows both read "Increment"** — the mode picker and the seconds stepper.
5. **The share card printed the move count as the score.** `finalScore` is what §13.5 prints, so a
   12-move game each way produced a card reading "12 – 12", which looks like a drawn score. It is now
   the result, written the way chess writes it: 1–0, and 0–0 for a game with no flag whose sides are
   `.unfinished`.

### Also

`ThemePickerRow` was extracted on its fourth copy; the three existing setup screens now share it.

## M7 — Hebrew, RTL and accessibility

> *"The Hebrew and accessibility pass."*

### The string catalog had silently stopped growing

The headline finding, and it had been true for four milestones. `xcodebuild` extracts every
`String(localized:)` into the build directory but **never writes back to the source `.xcstrings`** —
only Xcode's own build does that. So the catalog was populated at M0 with 83 keys and stayed there
while the app grew to 622. **87% of the interface fell back to English in Hebrew**, with nothing
failing, nothing logged, and nothing to see from the English side.

Fixed by syncing the compiler's own `.stringsdata` back into the catalog with `xcstringstool sync`,
then translating. The catalog now covers every key: 54 marked `shouldTranslate: false` (bare format
specifiers, punctuation, numerals, and the Latin abbreviations cricket uses in every language), and
the rest translated and marked `needs_review` — written to be correct, but no native reviewer has
seen them, and the catalog has a word for exactly that state.

`LocalizationTests` is the guard that was missing. It reads the catalog **from the source tree**,
because the bundle only ships the translated half and cannot tell you what is absent. It asserts
full coverage, that no value is blank, that every format specifier survives translation, and that
the shipped `he.lproj` actually resolves.

### One Hebrew word cannot mean three things

Caught by running the app in Hebrew, not by any amount of reading. `OVERS` was translated *מחזורים*
— which the catalog already used for both "periods" and "innings". A cricket board therefore read
*מחזורים* directly beneath a rules row reading *אוברים*. Aligned to the reviewed entries
(over → *אובר*, wicket → *שער*), and `terminologyIsConsistent` now pins each concept to one root
across every key that names it.

### Resume was broken for three engines out of four

**The most serious bug in the project so far**, and M7 found it only because the Hebrew pass
happened to press Resume. `SportPickerView` was written at M1 when `LiveMatchStore` was the only
store, and kept constructing one for every match through three more engines. A live tennis, league
or chess match hit the "cannot decode" path — which *retired the match* and told the operator its
rules could not be read. Pressing Resume destroyed exactly what §12 exists to protect, and nothing
caught it for three milestones because no test ever resumed a non-team match.

`ResumedMatch` routes by engine the way setup and the panels already do, and `ResumeTests` runs one
live match per engine through it — eight cases, so a ninth engine cannot land without wiring itself
in.

### Accessibility

- **Dense control rows were clipping at accessibility text sizes.** Cricket's 0–6, baseball's pitch
  outcomes and football's scoring plays were `HStack`s with a fixed `minHeight`: the label grew, the
  frame did not, and a `0` rendered as two disconnected arcs. `ControlButtonGrid` scales the minimum
  target with `@ScaledMetric` and **wraps to fewer columns** past `.accessibility1`, because six
  buttons across a phone at that size cannot hold a legible label however tall they are.
- Boards are deliberately **never mirrored** in RTL (§9.2) — verified on device, the Hebrew cricket
  board is laid out identically to the English one. Only the chrome flips.
- Contrast is asserted at 7:1 by `ThemeContrastTests`; Reduce Motion suppresses non-essential
  feedback; no state is signalled by colour alone — possession, at-bat, serve, out counts and
  finished racers all carry a shape or a word as well.

## M8 — submission readiness

> *"App Store assets, privacy manifest."*

Everything here is invisible while developing and fatal at upload, which is the worst combination a
check can have — so all of it is asserted by `SubmissionTests` against the **built bundle**, not the
source. A file that exists but never gets copied still fails.

| Item | State |
|---|---|
| Privacy manifest | `ScoreDock/Resources/PrivacyInfo.xcprivacy` — no tracking, no collected data, one required-reason API |
| App icon | 1024², opaque, rendered from the app's own board font |
| Export compliance | `ITSAppUsesNonExemptEncryption = false` in the bundle |
| Open-in-place | `LSSupportsOpeningDocumentsInPlace` — a shared `.sdgame` no longer copies into an Inbox |
| Store listing | `Submission/listing.md` |
| Screenshots | **Not captured** — needs a 6.9" and a 13" set |
| `DEVELOPMENT_TEAM` | **Unset** — needs the developer's Apple ID; cannot be filled in from here |

### The privacy manifest

`NSPrivacyTracking` is false and stays false — that is the invariant the tests defend.

The app links **`FirebaseAnalytics` alone**. Since Firebase 11 the advertising identifier is
*opt-in*: `FirebaseAnalyticsIdentitySupport` is the library that enables IDFA collection, and
Firebase's own `Package.swift` says *"adding this library to your project is enough for it to take
effect — the module does not need to be imported into any source files."* Collecting the IDFA would
be *tracking* under Apple's definition, obliging an ATT prompt and contradicting the store listing.

Because it takes effect purely by being linked, no amount of application code can prevent it —
which is why the guard lives in the project file instead.

`NSPrivacyCollectedDataTypes` therefore declares two entries — product interaction and the Firebase
app-instance ID — both unlinked, both non-tracking, both for analytics only. Firebase ships its own
manifest that Apple aggregates; these are declared here as well because the collection happens at
this app's instigation, and under-declaring is a review risk while over-declaring is not.

One required-reason API is declared — `UserDefaults`, reason CA92.1, because `AppSettings` keeps
board font, theme, sound and haptics there and nothing else reads them.

Deliberately absent: file timestamps, disk space, boot time, active keyboards. Photos reach the app
through `PhotosPicker`, which runs out of process and hands back only the chosen image, so no
photo-library permission is requested and none is declared.

`SubmissionTests.privacyManifestDeclaresNoTracking` re-asserts this from the shipped manifest, so
App Store Connect's questionnaire and the binary cannot drift apart. It checks the property that
actually matters now: every declared data type must be unlinked, non-tracking and analytics-only.
Swapping in plain `FirebaseAnalytics` fails it.

`GoogleService-Info.plist` is **not committed** — the repository is public and the file carries the
project's client API key. `AppDelegate` skips `FirebaseApp.configure()` when it is absent, because
Firebase otherwise terminates the app at launch, so a fresh clone still runs with analytics off.

### The icon

Drawn rather than designed in a tool, so it can be regenerated and reasoned about: the same
seven-segment face and ghost-segment layer the app draws on every board, in the dark theme's
colours. Two things were found by looking at it rather than by writing it:

1. **A DSEG7 `1` lights two segments** and reads as a rendering fault at 40 pt. The icon shows `24` —
   both digits light most of their segments, and it is the shot-clock value, which is the app's
   signature feature.
2. **The renderer produced an alpha channel by default**, which App Store Connect rejects outright.
   Now `CGImageAlphaInfo.noneSkipLast`, and `appIconIsOpaque` checks the source PNG — the 1024 is
   what the store inspects, and the smaller variants are re-encoded by `actool`.

It is a placeholder in the sense that no designer has seen it, and not a placeholder in the sense of
being wrong or off-brand.

## AirPlay was mirroring the phone instead of showing the board

Reported from hardware, and it is §5.2's entire reason for existing: turning on Screen Mirroring put
the *phone* on the television, not the scoreboard.

The external-display scene was configured in
`AppDelegate.application(_:configurationForConnecting:options:)` rather than as a
`UISceneConfigurations` entry in `Info.plist`, deliberately: the plist has to name the delegate as
the string `"$(PRODUCT_MODULE_NAME).ExternalDisplaySceneDelegate"`, and a string like that breaks
silently on a module rename. **The reasoning was sound and the conclusion was wrong.** In a
SwiftUI-lifecycle app SwiftUI installs its own delegate for scene management, and that method is
never called — so the app never created a window on the external scene, and iOS kept doing the only
thing it can when an app declines the display: mirror.

Reproduced without hardware by attaching a simulated external display (Simulator → I/O → External
Displays → 1080p) and confirming `ExternalDisplaySceneDelegate.scene(_:willConnectTo:)` had never
run: the TV window was blank and the log was empty.

The configuration moved to the plist, where it works — verified end to end, with the cricket board
filling the external display while the phone kept the controls. The string risk did not disappear; it
moved to where it belonged. `ExternalDisplayTests.sceneConfigurationResolves` reads the value the
bundle actually ships and resolves it with `NSClassFromString`, so a rename now fails a test instead
of silently disabling the feature. A second test asserts the *application* role is **not** declared
there, because taking the main window away from SwiftUI would break the app in a different way.

> The lesson generalises: the earlier decision traded a visible failure (a rename breaks the string)
> for an invisible one (the feature never runs). That is the wrong direction, and a test on the
> fragile thing would have let us keep both.

## Six warnings that hid for eight milestones

Not found by a test or by using the app — found by opening Xcode and looking at the issue navigator.
Every build here had been filtered with `grep error:`, which is a filter that answers "did it
compile" and quietly discards everything else. Five Swift 6 concurrency warnings and one
exhaustiveness warning accumulated behind it.

They mattered:

- **`AppDelegate` (×3).** `configurationForConnecting` touched `UISceneSession.role`,
  `UISceneConfiguration.init` and `delegateClass` — all main-actor isolated — from a `nonisolated`
  protocol requirement. UIKit does call it on the main thread, so the fix is the same
  `MainActor.assumeIsolated` the orientation callback two methods above already used. Under Swift 6
  these become errors, and this is the wiring §5.2 depends on.
- **`IdentityImage`.** `CGImageAlphaInfo` has **eight** cases, not seven: `.alphaOnly` was missing,
  and `@unknown default` correctly refused to hide a case that exists today. A mask image would have
  fallen through to "no alpha" and been flattened to JPEG. Also changed the unknown-case answer from
  `false` to `true`, so a future alpha format costs a larger file rather than silently flattening
  the transparency out of somebody's crest.
- **`OrientationReader`.** `nonisolated(unsafe)` "has no effect" because `@Observable` rewrites every
  stored property into a computed one over its tracking storage — the annotation was landing on
  generated code. `@ObservationIgnored` makes it a plain stored property again, where it means what
  it says. (The compiler's own suggestion, plain `nonisolated`, does not compile on a mutable stored
  property.)
- **`IdentityEditor`.** `PhotosPicker`'s label builder is `@Sendable`, so reading the binding inside
  it warned. The label text is resolved before the call.

## Cross-engine audit

M7 found that Resume had been building a `LiveMatchStore` for every match since M1, three engines
after that stopped being true. That is a *class* of bug, not a one-off — a feature written when there
was one engine, never revisited when there were four — so after M8 the whole app was swept for the
same shape. Three more instances, all found by asking one question of every file: **does this name a
concrete store?**

### 1. The external display reached a TV for team matches only (§5.2)

Worse than the Resume bug, because §5.2 is the app's headline feature and the reason it beats a
scoreboard website. `ActiveMatch` held a `LiveMatchStore?`, so casting worked for basketball and
silently did nothing for tennis, a league table or any of the five bespoke boards — **while every one
of those panels still offered a Display button** and walked the operator through connecting an Apple
TV, ending at a blank screen.

`AnyMatchStore` (the enum `ResumedMatch` grew into, since it turned out to be the same fix) now backs
both features, and `ExternalBoardView` renders all four engines.

### 2. Board modes were offered that the board could not fill (§6.1)

Both mode pickers listed `BoardMode.allCases`, so a basketball match with the shot clock switched
*off* still offered "Shot clock only" — and the television answered with a dash. Extending the
display to every engine would have made that much worse: a chess clock offering a shot clock.

`BoardMode.available(for:)` now answers per board — a play clock **is** a shot clock, a chess clock
has two clocks that mean nothing apart, and cricket and baseball have none — and `BoardModePicker`
renders nothing at all when there is only one mode, because a picker with one option is a label that
looks like a control. It also moved into the casting sheet, so every panel can reach it rather than
just the two that happened to have an inline strip.

### 3. Football quarters and chess flags expired in silence (§11.1)

`MatchFeedback.rearm` took a `LiveMatchStore`, so only team matches ever scheduled a sound. A
football quarter ran out with no buzzer and a chess flag fell with no buzzer — on precisely the path
§11.1 exists for, since it wants the buzzer armed against an *absolute instant* so it lands when the
UI is throttled and nobody is watching the screen.

Now armed for both. The other three bespoke boards schedule nothing and that is correct: a race clock
counts up with nothing to expire, and cricket and baseball have no clock at all — which the tests
assert rather than leave implied.

### What the sweep did not find

Statistics, the Match Report, the five share formats, History and the Stats tab all read `Match` and
its denormalised `MatchSide` fields rather than a store, so they were engine-agnostic already. That
is why `finalScore` is worth the care each store puts into it: it is the seam every downstream
feature actually depends on.

## ⚠️ Open before submission

### 25 rule values await verification (§8.5)

The spec is explicit that wrong rule defaults are what makes a referee delete the app, and that these
must not be guessed. Every value in `catalog.json` carries a `sources` entry with a `status`:

- `referenceSite` — a headline parameter confirmed from the spec's §8.1–8.4 tables
- `sourced` — taken from the named governing body's published rules
- `needsReview` — **a plausible default that must be checked before submission**

There are currently **25 `needsReview` values across 16 presets**. `CatalogTests` asserts that count
so it cannot drift silently; lower it deliberately as they are cleared. The highest-consequence ones:

- `basketball-nba` — timeout allocation, and the team-foul bonus threshold
- `basketball` (FIBA) — the 2-in-first-half / 3-in-second-half timeout split is not modelled
- `waterpolo` — short shot-clock reset value and personal-foul limit
- `lacrosse` — which code the preset targets (12 vs 15 minute quarters), shot clock
- `field-hockey` — FIH moved internationals to 4×15 in 2019; this preset keeps the reference site's 2×35
- `boxing` — the 10-point must system is per-round judging, which the generic team engine cannot express

### 485 Hebrew strings await a native reviewer

Every user-visible string now has Hebrew and `LocalizationTests` keeps it that way, but 485 of them
are marked `needs_review` in the catalog rather than `translated`: they were written to be correct
and idiomatic, and no native speaker has confirmed them. Xcode's string-catalog editor surfaces the
queue. The sports vocabulary is where a reviewer matters most — cricket in particular has no settled
Hebrew terminology, and this build follows the reviewed entries in transliterating (*אובר*) rather
than inventing.

### Other flagged items

- **No screenshots.** App Store Connect needs a 6.9" and a 13" set. `Submission/listing.md` lists
  the five shots and the order to take them in. Fictional team names only — real club names and
  crests belong to somebody else.
- **No support or privacy-policy URL.** Both are required fields and both need a domain. The name is
  settled (ScoreDock), so this is now a purchase rather than a decision.
- **The name is not yet trademark-checked.** Renaming closed the *collision* (§17 risk 1); confirming
  *ScoreDock* is itself free needs an App Store search and the US/EU/IL registries.
- **`DEVELOPMENT_TEAM` is unset.** Simulator builds sign ad-hoc; device builds need a team, and the
  iCloud capability must be enabled on the App ID. This one cannot be resolved from a repository —
  it needs the developer's Apple ID.
- **§19.2 q2 is still open.** The share format is not remembered between shares. Deliberate for now:
  the five formats are genuinely different products and the picker is one tap, so persisting a
  choice would mostly serve to hide the other four.

## Notes on the spec

Two places where the implementation deliberately differs or extends:

1. **§2.1 says DSEG7 has "no full Latin alphabet".** It actually carries A–Z and a–z (69 glyphs).
   The spec's *conclusion* still holds, for a better reason: those letters are seven-segment
   approximations (`S` is indistinguishable from `5`), so they are unusable for names. It also has
   **no `/` glyph**, which matters for the cricket board's `runs/wickets` notation.
2. **§7.1's model listing omits two inverse relationships.** `MatchSide.linkedTeam` and
   `linkedPlayer` are relationships without an inverse, which CloudKit rejects. `Player` and `Team`
   therefore carry `matchAppearances` with a `.nullify` rule, so deleting a team does not delete the
   season it played. Covered by `CloudKitSchemaTests`.

`EventKind` also adds `breakEnd` and `undo` beyond the §7.1 list, because §13.3 requires break
start *and* end to be logged and requires undo to append rather than erase.
