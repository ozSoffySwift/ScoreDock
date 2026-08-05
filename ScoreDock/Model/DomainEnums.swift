import Foundation

// MARK: - The stored-enum pattern
//
// Every enum persisted by SwiftData lives on its model as a `…Raw: String` property with a typed
// computed accessor over the top (§7.1).
//
// SwiftData *can* persist a Codable enum directly, but it lands as an opaque blob: no `#Predicate`
// filtering against it, and a hard decode failure the moment a case is renamed. Raw strings stay
// queryable, survive a device on an older build receiving an unknown case over sync, and degrade
// to a documented default instead of throwing.
//
// `DefaultingRawEnum` makes that degradation a property of the type rather than a scattering of
// `?? .something` at each call site — so "what happens on an unknown value" is answered once,
// next to the cases, and is unit-testable.

protocol DefaultingRawEnum: RawRepresentable, CaseIterable, Codable, Hashable, Sendable
where RawValue == String {
    /// Where an unrecognised stored value lands. Chosen so a wrong guess is inert, never damaging.
    static var fallback: Self { get }
}

extension DefaultingRawEnum {
    /// Decodes a stored raw string without trapping on a case this build has never heard of.
    init(storedRaw: String?) {
        guard let storedRaw, let value = Self(rawValue: storedRaw) else {
            self = Self.fallback
            return
        }
        self = value
    }
}

// MARK: - Identity

/// Which mark a record prefers to show when more than one is set (§7.1a).
///
/// This is a *preference*, not a guarantee — the record may prefer `.image` and have no image.
/// `IdentityBearing.resolvedMark` handles that, and always terminates at `.initials`.
enum IdentityMark: String, DefaultingRawEnum {
    case emoji, image, initials

    static var fallback: Self { .initials }
}

// MARK: - Engines and catalog

/// Which of the four rule engines drives a preset (§6).
enum EngineKind: String, DefaultingRawEnum {
    /// 20 presets. Period clock, fouls, timeouts, shot clock, possession (§6.1).
    case team
    /// 8 presets. Rally scoring, sets, tennis/darts notation (§6.2).
    case setMatch
    /// 4 presets. Leaderboard, standings, bracket, score sheet (§6.5).
    case list
    /// 5 bespoke boards that fit no generic template (§6.3).
    case specialised

    static var fallback: Self { .team }
}

/// Which section of the sport picker a preset files under (§8).
///
/// Distinct from `EngineKind` on purpose, even though the 37 built-ins currently align 1:1 with it.
/// Engine is *how the rules execute*; category is *where the user looks for it*. A user preset can
/// reasonably run the team engine while being filed somewhere else, and keeping the two separate
/// means that never requires a schema change.
enum PresetCategory: String, DefaultingRawEnum {
    case team, setMatch, specialised, list

    static var fallback: Self { .team }
}

// MARK: - Match lifecycle

enum MatchStatus: String, DefaultingRawEnum {
    /// Configured but never started. Carries no events.
    case setup
    /// In progress. At most one match should be `live`; this is what crash recovery looks for (§12).
    case live
    /// Played to its natural end, with an outcome.
    case finished
    /// Ended early. Still keeps a complete log up to the last action taken (§13.1).
    case abandoned

    static var fallback: Self { .setup }
}

/// What happened to one side. Denormalised onto `MatchSide` at match end for cheap stats queries (§7.2).
enum SideOutcome: String, DefaultingRawEnum {
    case win, loss, draw
    /// The match never reached a result — still in progress, or abandoned.
    case unfinished

    static var fallback: Self { .unfinished }
}

// MARK: - Event log

/// Every state mutation is recorded as one of these (§6.6, §13.3).
///
/// §13.3 says *everything, without exception* gets logged, and names several things the §7.1 list
/// cannot express, so this set extends it:
///
/// - `breakEnd` — §13.3 requires break start **and** end.
/// - `periodLabel` — §13.3 names "period advances **and label overrides**" as distinct.
/// - `clockSet`, `shotClockToggle`, `matchFinish` — otherwise these collapse into `correction` and
///   become unreplayable, which would silently break undo and crash recovery.
/// - `undo` — an undo appends a compensating event rather than erasing history. A log that hides
///   operator mistakes is worthless in exactly the dispute it exists to settle.
enum EventKind: String, DefaultingRawEnum {
    case score
    case foul
    case timeout
    case periodAdvance
    /// An OT / SO / HT / F override, or its removal.
    case periodLabel
    case possession
    case shotClockReset
    case shotClockToggle
    case breakStart
    case breakEnd
    case clockToggle
    /// The main clock set to an explicit value — a reset, or a manual correction.
    case clockSet
    /// A bracket match resolved to a winner (§6.5).
    case bracketResult
    /// One column of a league record adjusted (§6.5).
    case recordAdjust

    // MARK: Specialised boards (§6.3)
    //
    // Each bespoke action gets its own kind rather than collapsing into `correction`, because §13.3
    // wants a play-by-play someone can read — "W · 4 · 1nb" beats sixteen rows of "correction".

    /// A chess clock pressed: one move completed.
    case clockPress
    /// A race timer split recorded for one racer.
    case lap
    case racerFinish
    /// American football down and distance set.
    case downSet
    /// American football ball spotted on a yard line.
    case ballOn
    /// One cricket delivery.
    case delivery
    case wicket
    case inningsEnd
    /// One baseball pitch, or what followed it.
    case pitch
    case baseRunners
    case halfInning

    case matchFinish
    /// An operator correction that is not a plain score change (e.g. fixing a mis-entered foul).
    case correction
    /// The compensating record written when the operator undoes an earlier event. Its `value`
    /// carries the `index` of the event being undone.
    case undo

    static var fallback: Self { .correction }
}
