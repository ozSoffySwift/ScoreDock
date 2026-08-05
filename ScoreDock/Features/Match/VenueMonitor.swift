import Foundation
import SwiftUI
import UIKit

/// Watches the practical hazards of a device sitting on a table for three hours with the screen on
/// and a TV attached (§12).
///
/// Both signals exist because "screen-on plus AirPlay" is a genuinely heavy draw, and a scoreboard
/// that dies or throttles mid-match without explanation looks like a broken app rather than a flat
/// battery.
@Observable
@MainActor
final class VenueMonitor {
    private(set) var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    private(set) var batteryLevel: Float = UIDevice.current.batteryLevel
    private(set) var batteryState: UIDevice.BatteryState = UIDevice.current.batteryState

    private var observers: [any NSObjectProtocol] = []

    /// At `.serious` the system is already throttling the CPU and GPU. Dropping the board from
    /// 10 Hz to 1 Hz — which also drops tenths — gives that budget back to the thing that matters,
    /// which is the display staying lit and correct (§12).
    var isThermallyThrottled: Bool {
        thermalState == .serious || thermalState == .critical
    }

    var isCharging: Bool {
        batteryState == .charging || batteryState == .full
    }

    /// §12: warn at 20% during a live match, with a plug-in prompt.
    var showsLowBatteryWarning: Bool {
        !isCharging && batteryLevel >= 0 && batteryLevel <= 0.20
    }

    /// Nil when the level is unknown (the simulator reports -1).
    var batteryPercent: Int? {
        batteryLevel < 0 ? nil : Int((batteryLevel * 100).rounded())
    }

    func start() {
        guard observers.isEmpty else { return }
        UIDevice.current.isBatteryMonitoringEnabled = true
        refresh()

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        for name in [UIDevice.batteryLevelDidChangeNotification, UIDevice.batteryStateDidChangeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
    }

    func stop() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        // Left enabled would keep the device reporting battery changes app-wide for no reason.
        UIDevice.current.isBatteryMonitoringEnabled = false
    }

    private func refresh() {
        thermalState = ProcessInfo.processInfo.thermalState
        batteryLevel = UIDevice.current.batteryLevel
        batteryState = UIDevice.current.batteryState
    }
}

extension ProcessInfo.ThermalState {
    var operatorExplanation: String? {
        switch self {
        case .serious:
            String(
                localized: "Your device is running hot, so the board is updating once a second instead of ten. Tenths of a second are hidden until it cools.",
                comment: "Thermal warning"
            )
        case .critical:
            String(
                localized: "Your device is too hot and is limiting performance. Unplug from direct sun, or take it out of a case.",
                comment: "Thermal warning"
            )
        case .nominal, .fair:
            nil
        @unknown default:
            nil
        }
    }
}
