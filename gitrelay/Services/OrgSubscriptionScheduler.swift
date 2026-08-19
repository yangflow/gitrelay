import Foundation

@MainActor
final class OrgSubscriptionScheduler {
    private var timer: Timer?
    var onFire: (() -> Void)?

    func schedule(frequency: OrgSubscriptionPollFrequency) {
        invalidate()
        guard let interval = frequency.interval else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.onFire?() }
        }
        self.timer = timer
    }

    func reschedule(frequency: OrgSubscriptionPollFrequency) {
        schedule(frequency: frequency)
    }

    func nextFireDate() -> Date? {
        timer?.fireDate
    }

    func invalidate() {
        timer?.invalidate()
        timer = nil
    }
}
