import Foundation
import Network
import Observation

/// Observes Low Power Mode and expensive / hotspot network paths so scheduled
/// syncs can pause without touching credentials or the mirror model.
@MainActor
@Observable
final class SyncEnvironmentMonitor {
    private(set) var isLowPowerModeEnabled: Bool
    private(set) var isExpensiveNetwork: Bool

    private let pathMonitor: NWPathMonitor
    private let pathQueue = DispatchQueue(label: "com.yangflow.gitrelay.path-monitor")
    private var powerObserver: NSObjectProtocol?
    private var didStart = false

    /// Called on the main actor when power or network pause inputs change.
    var onEnvironmentChange: (() -> Void)?

    init(
        pathMonitor: NWPathMonitor = NWPathMonitor(),
        isLowPowerModeEnabled: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled,
        isExpensiveNetwork: Bool = false
    ) {
        self.pathMonitor = pathMonitor
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
        self.isExpensiveNetwork = isExpensiveNetwork
    }

    func start() {
        guard !didStart else { return }
        didStart = true

        isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        powerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let previous = self.isLowPowerModeEnabled
                self.isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
                if previous != self.isLowPowerModeEnabled {
                    self.onEnvironmentChange?()
                }
            }
        }

        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let previous = self.isExpensiveNetwork
                self.isExpensiveNetwork = path.isExpensive
                if previous != self.isExpensiveNetwork {
                    self.onEnvironmentChange?()
                }
            }
        }
        pathMonitor.start(queue: pathQueue)
    }

    func stop() {
        guard didStart else { return }
        didStart = false
        pathMonitor.cancel()
        if let powerObserver {
            NotificationCenter.default.removeObserver(powerObserver)
            self.powerObserver = nil
        }
    }

    func pauseReason(using policy: SyncPausePolicy, date: Date = Date(), calendar: Calendar = .current) -> SyncPauseReason? {
        policy.pauseReason(
            isLowPowerMode: isLowPowerModeEnabled,
            isExpensiveNetwork: isExpensiveNetwork,
            date: date,
            calendar: calendar
        )
    }

    func shouldPauseScheduledSyncs(using policy: SyncPausePolicy, date: Date = Date(), calendar: Calendar = .current) -> Bool {
        pauseReason(using: policy, date: date, calendar: calendar) != nil
    }
}
