import Foundation

@MainActor
final class VerificationScheduler {
    private var timer: Timer?
    var onFire: (() -> Void)?

    func schedule(frequency: VerificationFrequency) {
        invalidate()
        guard let interval = frequency.interval else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.onFire?() }
        }
        self.timer = timer
    }

    func reschedule(frequency: VerificationFrequency) {
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
