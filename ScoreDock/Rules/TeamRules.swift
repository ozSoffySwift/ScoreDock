import Foundation

/// Decoding helper used by every rule struct.
///
/// Rule types decode field-by-field with a documented default rather than relying on synthesized
/// `Codable`, which fails outright on a missing key. That is the whole mechanism behind §7.3:
/// a blob written by an older build decodes cleanly into a newer struct, so adding a rule is a
/// decoder change and never a store migration.
extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, or fallback: T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? fallback
    }
}

/// How periods are named on the board (§6.1).
enum PeriodLabelStyle: String, DefaultingRawEnum {
    case quarter, half, period, round, inning, custom

    static var fallback: Self { .period }

    /// The short prefix shown beside the period number. Localised at the view layer; DSEG7 cannot
    /// render these anyway, so they always use the app's text face (§9.2).
    var prefix: String {
        switch self {
        case .quarter: "Q"
        case .half: "H"
        case .period: "P"
        case .round: "R"
        case .inning: "I"
        case .custom: ""
        }
    }
}

/// Rules for the team engine — 20 of the 37 presets, and the workhorse of the app (§6.1).
struct TeamRules: Codable, Hashable, Sendable {
    /// Two for almost everything; more for free-for-all counters.
    var sideCount: Int = 2

    // MARK: Clock
    var periodCount: Int = 4
    /// Seconds. Stored as `TimeInterval` throughout — the engine never sees minutes.
    var periodLength: TimeInterval = 600
    /// Count up towards `periodLength` (soccer) or down towards zero (basketball).
    var countsUp: Bool = false
    var showTenths: Bool = true
    /// Tenths appear only below this many seconds remaining, so the board is calm for most of a period.
    var tenthsThreshold: TimeInterval = 60
    /// Seconds. Replaces the main timer during half-time, then hands control back to regulation
    /// time at exactly the paused value (§6.1).
    var breakDuration: TimeInterval = 900

    // MARK: Period labelling
    var periodLabelStyle: PeriodLabelStyle = .quarter
    /// Used only when `periodLabelStyle == .custom`.
    var customPeriodLabels: [String] = []

    // MARK: Scoring
    /// Which increment buttons the control panel offers, e.g. `[1, 2, 3]` for basketball or
    /// `[1, 6]` for American football (§4.2). Always includes at least 1.
    var scoreIncrements: [Int] = [1]

    // MARK: Fouls
    var foulTrackingEnabled: Bool = false
    var foulLimit: Int = 5
    var foulsResetPerPeriod: Bool = true
    /// Team fouls at which the bonus indicator lights. Nil disables the indicator.
    /// Colour is never the only signal — the bonus state carries an icon too (§15).
    var bonusThreshold: Int?

    // MARK: Timeouts
    var timeoutCount: Int = 0
    var timeoutsResetAtHalf: Bool = false

    // MARK: Shot clock
    var shotClockEnabled: Bool = false
    /// Seconds. Tap resets to full (§4.2).
    var shotClockFull: TimeInterval = 24
    /// Seconds. Long-press resets to short — the offensive-rebound reset.
    var shotClockShort: TimeInterval = 14

    // MARK: Possession
    var possessionArrowEnabled: Bool = false
    /// Optional text beside the arrow. Possession carries an arrow *and* a label so colour is never
    /// the only signal (§15).
    var possessionLabel: String?

    init() {}

    /// Label for a 1-based period number, including the extra-period case.
    ///
    /// Periods beyond `periodCount` are overtime. The operator can still override the label
    /// entirely (OT / SO / HT / F) from the control panel (§4.2) — that override is match state,
    /// not a rule, so it does not live here.
    func label(forPeriod period: Int) -> String {
        if periodLabelStyle == .custom, customPeriodLabels.indices.contains(period - 1) {
            return customPeriodLabels[period - 1]
        }
        if period > periodCount { return "OT" }
        return "\(periodLabelStyle.prefix)\(period)"
    }

    /// Whether tenths should render at this many seconds remaining.
    func showsTenths(atRemaining remaining: TimeInterval) -> Bool {
        showTenths && remaining < tenthsThreshold
    }
}

extension TeamRules {
    private enum CodingKeys: String, CodingKey {
        case sideCount, periodCount, periodLength, countsUp, showTenths, tenthsThreshold
        case breakDuration, periodLabelStyle, customPeriodLabels, scoreIncrements
        case foulTrackingEnabled, foulLimit, foulsResetPerPeriod, bonusThreshold
        case timeoutCount, timeoutsResetAtHalf
        case shotClockEnabled, shotClockFull, shotClockShort
        case possessionArrowEnabled, possessionLabel
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TeamRules()
        self.init()
        sideCount = try c.value(.sideCount, or: d.sideCount)
        periodCount = try c.value(.periodCount, or: d.periodCount)
        periodLength = try c.value(.periodLength, or: d.periodLength)
        countsUp = try c.value(.countsUp, or: d.countsUp)
        showTenths = try c.value(.showTenths, or: d.showTenths)
        tenthsThreshold = try c.value(.tenthsThreshold, or: d.tenthsThreshold)
        breakDuration = try c.value(.breakDuration, or: d.breakDuration)
        periodLabelStyle = PeriodLabelStyle(
            storedRaw: try c.decodeIfPresent(String.self, forKey: .periodLabelStyle)
        )
        customPeriodLabels = try c.value(.customPeriodLabels, or: d.customPeriodLabels)
        scoreIncrements = try c.value(.scoreIncrements, or: d.scoreIncrements)
        foulTrackingEnabled = try c.value(.foulTrackingEnabled, or: d.foulTrackingEnabled)
        foulLimit = try c.value(.foulLimit, or: d.foulLimit)
        foulsResetPerPeriod = try c.value(.foulsResetPerPeriod, or: d.foulsResetPerPeriod)
        bonusThreshold = try c.decodeIfPresent(Int.self, forKey: .bonusThreshold)
        timeoutCount = try c.value(.timeoutCount, or: d.timeoutCount)
        timeoutsResetAtHalf = try c.value(.timeoutsResetAtHalf, or: d.timeoutsResetAtHalf)
        shotClockEnabled = try c.value(.shotClockEnabled, or: d.shotClockEnabled)
        shotClockFull = try c.value(.shotClockFull, or: d.shotClockFull)
        shotClockShort = try c.value(.shotClockShort, or: d.shotClockShort)
        possessionArrowEnabled = try c.value(.possessionArrowEnabled, or: d.possessionArrowEnabled)
        possessionLabel = try c.decodeIfPresent(String.self, forKey: .possessionLabel)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sideCount, forKey: .sideCount)
        try c.encode(periodCount, forKey: .periodCount)
        try c.encode(periodLength, forKey: .periodLength)
        try c.encode(countsUp, forKey: .countsUp)
        try c.encode(showTenths, forKey: .showTenths)
        try c.encode(tenthsThreshold, forKey: .tenthsThreshold)
        try c.encode(breakDuration, forKey: .breakDuration)
        try c.encode(periodLabelStyle.rawValue, forKey: .periodLabelStyle)
        try c.encode(customPeriodLabels, forKey: .customPeriodLabels)
        try c.encode(scoreIncrements, forKey: .scoreIncrements)
        try c.encode(foulTrackingEnabled, forKey: .foulTrackingEnabled)
        try c.encode(foulLimit, forKey: .foulLimit)
        try c.encode(foulsResetPerPeriod, forKey: .foulsResetPerPeriod)
        try c.encodeIfPresent(bonusThreshold, forKey: .bonusThreshold)
        try c.encode(timeoutCount, forKey: .timeoutCount)
        try c.encode(timeoutsResetAtHalf, forKey: .timeoutsResetAtHalf)
        try c.encode(shotClockEnabled, forKey: .shotClockEnabled)
        try c.encode(shotClockFull, forKey: .shotClockFull)
        try c.encode(shotClockShort, forKey: .shotClockShort)
        try c.encode(possessionArrowEnabled, forKey: .possessionArrowEnabled)
        try c.encodeIfPresent(possessionLabel, forKey: .possessionLabel)
    }
}
