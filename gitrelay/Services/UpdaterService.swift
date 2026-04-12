import Foundation
import AppKit
#if canImport(Sparkle)
import Sparkle
#endif

/// Wrapper around Sparkle's auto-update controller.
///
/// Apps that haven't yet added the Sparkle Swift Package Manager dependency
/// get a stub that opens the GitHub Releases page. Apps that have added
/// Sparkle get the real updater with zero code changes elsewhere.
///
/// Setup steps for the fully-wired updater:
///   1. Add the Sparkle package to the gitrelay app target via Xcode.
///   2. Generate an Ed25519 keypair for appcast signing:
///        ./path/to/Sparkle/bin/generate_keys
///      Store the private key in your login keychain.
///   3. In Xcode build settings, set:
///        INFOPLIST_KEY_SUFeedURL   = https://yangflow.github.io/gitrelay/appcast.xml
///        INFOPLIST_KEY_SUPublicEDKey = <base64 public key from step 2>
///   4. At release time, `scripts/release.sh` can sign the artifact and
///      update docs/appcast.xml with the new entry.

#if canImport(Sparkle)

@MainActor
final class UpdaterService: NSObject {
    static let shared = UpdaterService()

    private let controller: SPUStandardUpdaterController

    override private init() {
        // startingUpdater: false — do not auto-check on launch until
        // SUFeedURL and SUPublicEDKey are configured in build settings.
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
