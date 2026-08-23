import Foundation
import AppKit
#if canImport(Sparkle)
import Sparkle
#endif

/// Owns the Sparkle updater used by the About window and application commands.
/// The feed URL and Ed25519 public key live in `Info.plist`; release artifacts
/// are signed with the matching private key before `docs/appcast.xml` is published.

#if canImport(Sparkle)

@MainActor
final class UpdaterService: NSObject {
    static let shared = UpdaterService()

    private let controller: SPUStandardUpdaterController

    override private init() {
        self.controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    var canCheck: Bool {
        controller.updater.canCheckForUpdates
    }
}

#else

@MainActor
final class UpdaterService {
    static let shared = UpdaterService()

    private init() {}

    func checkForUpdates() {
        let alert = NSAlert()
        alert.messageText = "Updates not configured"
        alert.informativeText = """
            GitRelay was built without the Sparkle auto-update framework.

            To enable in-app updates:
              1. Xcode → File → Add Package Dependencies
              2. Paste https://github.com/sparkle-project/Sparkle
              3. Add the `Sparkle` library to the gitrelay app target
              4. Set SUFeedURL and SUPublicEDKey in build settings
              5. Rebuild

            See UpdaterService.swift for the full runbook.
            """
        alert.alertStyle = .informational
        alert.runModal()
    }

    var canCheck: Bool { false }
}

#endif
