import Foundation

/// Detects optional tunnel CLIs the user may already have installed.
nonisolated enum WebhookTunnelToolDetector {
    static func isCloudflaredAvailable(
        fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> Bool {
        candidatePaths(for: "cloudflared").contains(where: fileExists)
    }

    static func isTailscaleAvailable(
        fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> Bool {
        candidatePaths(for: "tailscale").contains(where: fileExists)
    }

    static func candidatePaths(for tool: String) -> [String] {
        [
            "/opt/homebrew/bin/\(tool)",
            "/usr/local/bin/\(tool)",
            "/usr/bin/\(tool)",
            "\(NSHomeDirectory())/.local/bin/\(tool)"
        ]
    }
}
