import SwiftUI
import UIKit

/// Physical device orientation, filtered to the three that matter.
///
/// **Do not use size classes for this (§5.1).** On iPad both orientations are regular/regular, so a
/// size class cannot detect the rotation at all — the board would simply never appear.
///
/// `.faceUp`, `.faceDown` and `.unknown` are discarded rather than mapped, because a phone laid
/// flat on the scorer's table reports `.faceUp` and must keep whatever it was showing.
@Observable
@MainActor
final class OrientationReader {
    enum Orientation {
        case portrait, landscape
    }

    private(set) var orientation: Orientation = .portrait

    /// `deinit` is nonisolated, so it cannot read main-actor state — hence taking the token out of
    /// the actor. Safe: it is written exactly once during `init`, before the instance can be shared,
    /// and read exactly once during `deinit`, when no other reference to it survives.
    ///
    /// **`@ObservationIgnored` is load-bearing, not tidiness.** `@Observable` rewrites every stored
    /// property into a computed one over its tracking storage, and `nonisolated(unsafe)` on a
    /// computed property has no effect — which is exactly what the compiler was reporting. Opting
    /// the token out of observation leaves it a plain stored property, where the annotation means
    /// what it says. No view observes it in any case.
    @ObservationIgnored private nonisolated(unsafe) var observer: (any NSObjectProtocol)?

    init() {
        update(UIDevice.current.orientation)
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        observer = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.update(UIDevice.current.orientation)
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private func update(_ deviceOrientation: UIDeviceOrientation) {
        switch deviceOrientation {
        case .portrait, .portraitUpsideDown:
            orientation = .portrait
        case .landscapeLeft, .landscapeRight:
            orientation = .landscape
        default:
            // faceUp / faceDown / unknown — keep the current value.
            break
        }
    }
}
