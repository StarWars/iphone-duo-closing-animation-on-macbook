import Foundation

// Desired operation survives a temporary safety stop. Actual overlays never
// survive sleep/lock, and resumption requires a fresh, open-lid reading.
struct BackgroundState: Sendable {
    enum Event: Sendable {
        case sleep, wake, displaySleep, displayWake, resignSession, activateSession, lock, unlock
    }

    var requested = false
    private var asleep = false
    private var displayAsleep = false
    private var sessionInactive = false
    private var locked = false
    var suspended: Bool { asleep || displayAsleep || sessionInactive || locked }

    mutating func receive(_ event: Event) {
        switch event {
        case .sleep: asleep = true
        case .wake: asleep = false
        case .displaySleep: displayAsleep = true
        case .displayWake: displayAsleep = false
        case .resignSession: sessionInactive = true
        case .activateSession: sessionInactive = false
        case .lock: locked = true
        case .unlock: locked = false
        }
    }

    func canArm(angle: Double?, fresh: Bool, permission: Bool, shortcut: Bool, display: Bool,
                trigger: LidTrigger = LidTrigger()) -> Bool {
        guard requested, !suspended, fresh, permission, shortcut, display,
              let angle, angle.isFinite else { return false }
        return trigger.isOpen(angle)
    }
}
