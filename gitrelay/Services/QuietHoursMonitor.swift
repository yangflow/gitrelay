import Foundation
import Observation

/// Tracks whether the global quiet-hours window is currently active and
/// schedules the next local-time transition so the menu bar can update.
@MainActor
@Observable
final class QuietHoursMonitor {
    private(set) var isActive: Bool = false

    /// Injected clock for tests. Production uses `Date()`.
    var now: () -> Date = { Date() }
    var calendar: Calendar = .current

    private var settings: QuietHoursSettings = .default
    private var transitionTimer: Timer?
    private var didStart = false
    var onTransition: (() -> Void)?

    func start(settings: QuietHoursSettings) {
        didStart = true
        update(settings: settings)
    }

    func stop() {
        didStart = false
        transitionTimer?.invalidate()
        transitionTimer = nil
        isActive = false
    }

    func update(settings: QuietHoursSettings) {
        self.settings = settings
        refresh()
    }

    func refresh() {
        let previouslyActive = isActive
        let active = settings.contains(now(), calendar: calendar)
        isActive = active
        scheduleNextTransition()
        if previouslyActive != active {
            onTransition?()
        }
    }

    private func scheduleNextTransition() {
        transitionTimer?.invalidate()
        transitionTimer = nil
        guard didStart, settings.isEnabled else { return }
        guard let next = settings.nextTransitionDate(after: now(), calendar: calendar) else { return }
        let interval = max(next.timeIntervalSince(now()), 0.05)
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
        transitionTimer = timer
    }
}
