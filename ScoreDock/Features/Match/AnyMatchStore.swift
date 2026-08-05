import Foundation
import SwiftData
import SwiftUI

/// A running match, whichever engine is running it.
///
/// **Why this exists.** Two features were written at M1 against `LiveMatchStore`, the only store
/// there was, and kept using it for every match through three more engines:
///
/// - **Resume (§12).** A live tennis, league or chess match failed to reopen, and the failure path
///   *retired the match* and told the operator its rules could not be read. Pressing Resume
///   destroyed exactly what §12 exists to protect.
/// - **The external display (§5.2).** `ActiveMatch` held a `LiveMatchStore?`, so the board only ever
///   reached a TV for a team match — while every other panel still offered a Display button and a
///   set of instructions that ended in a blank screen.
///
/// Both are the same mistake, and one type fixes both. Routing by engine is what setup and the
/// control panels already do, and the compiler enforces it here: `AnyRuleSet` is exhaustive, so a
/// fifth engine cannot land without being wired in.
enum AnyMatchStore: Identifiable {
    case team(LiveMatchStore)
    case setMatch(SetMatchStore)
    case list(ListStore)
    case specialised(SpecialisedStore)

    var id: UUID {
        switch self {
        case let .team(store): store.id
        case let .setMatch(store): store.id
        case let .list(store): store.id
        case let .specialised(store): store.id
        }
    }

    /// Reopens a match, or nil when its stored rules genuinely cannot be replayed by this build.
    @MainActor
    init?(match: Match, context: ModelContext) {
        switch match.rulesSnapshot {
        case .team:
            guard let store = LiveMatchStore(match: match, context: context) else { return nil }
            self = .team(store)
        case .setMatch:
            guard let store = SetMatchStore(match: match, context: context) else { return nil }
            self = .setMatch(store)
        case .list:
            guard let store = ListStore(match: match, context: context) else { return nil }
            self = .list(store)
        case .specialised:
            guard let store = SpecialisedStore(match: match, context: context) else { return nil }
            self = .specialised(store)
        case nil:
            return nil
        }
    }
}

/// Hosts a running match in whichever container its engine needs.
struct MatchHostView: View {
    let store: AnyMatchStore
    var onFinish: () -> Void

    var body: some View {
        switch store {
        case let .team(store):
            MatchContainerView(store: store, onFinish: onFinish)
        case let .setMatch(store):
            SetMatchContainerView(store: store, onFinish: onFinish)
        case let .list(store):
            ListContainerView(store: store, onFinish: onFinish)
        case let .specialised(store):
            SpecialisedContainerView(store: store, onFinish: onFinish)
        }
    }
}
