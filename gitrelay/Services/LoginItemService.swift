import Foundation
import ServiceManagement

/// Testable seam over ``SMAppService`` login-item registration (macOS 14+).
protocol LoginItemManaging: AnyObject {
    var isEnabled: Bool { get }
    /// True when the user must approve the login item in System Settings.
    var requiresApproval: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

enum LoginItemServiceError: LocalizedError, Equatable {
    case requiresApproval
    case registrationDidNotEnable
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .requiresApproval:
            return String(
                localized: "Open at Login needs approval in System Settings → General → Login Items."
            )
        case .registrationDidNotEnable:
            return String(localized: "Could not enable Open at Login. Check System Settings → Login Items.")
        case .underlying(let message):
            return message
        }
    }
}

/// Registers / unregisters the main app via ``SMAppService.mainApp``.
final class LoginItemService: LoginItemManaging {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) throws {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            throw LoginItemServiceError.underlying(error.localizedDescription)
        }

        if enabled {
            switch SMAppService.mainApp.status {
            case .enabled:
                return
            case .requiresApproval:
                throw LoginItemServiceError.requiresApproval
            default:
                throw LoginItemServiceError.registrationDidNotEnable
            }
        }
    }
}

/// Observable controller so Settings toggles always reflect real ``SMAppService`` status.
@MainActor
@Observable
final class LoginItemController {
    private let service: LoginItemManaging

    private(set) var isEnabled: Bool
    private(set) var requiresApproval: Bool
    var lastErrorMessage: String?

    init(service: (any LoginItemManaging)? = nil) {
        let resolved = service ?? LoginItemService()
        self.service = resolved
        self.isEnabled = resolved.isEnabled
        self.requiresApproval = resolved.requiresApproval
    }

    func refresh() {
        isEnabled = service.isEnabled
        requiresApproval = service.requiresApproval
    }

    /// Updates the login item. On failure, leaves ``isEnabled`` matching the service (no lying toggle).
    func setEnabled(_ enabled: Bool) {
        do {
            try service.setEnabled(enabled)
            lastErrorMessage = nil
            refresh()
            if enabled && !isEnabled {
                lastErrorMessage = LoginItemServiceError.registrationDidNotEnable.errorDescription
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            refresh()
        }
    }
}
