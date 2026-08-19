import Foundation

/// Builds webhook URL templates for local listeners and optional tunnel exposure modes.
nonisolated enum WebhookURLTemplate {
    static func localURL(port: UInt16, pathID: String) -> String {
        "http://127.0.0.1:\(port)/hook/\(pathID.lowercased())"
    }

    static func publicURL(baseURL: String, pathID: String) -> String? {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return nil }
        var normalized = base
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return "\(normalized)/hook/\(pathID.lowercased())"
    }

    static func displayURL(
        preferences: WebhookPreferences,
        port: UInt16?,
        pathID: String
    ) -> String {
        if let publicURL = publicURL(baseURL: preferences.normalizedPublicBaseURL, pathID: pathID) {
            return publicURL
        }

        switch preferences.exposureMode {
        case .off:
            if let port {
                return localURL(port: port, pathID: pathID)
            }
            return "http://127.0.0.1:<port>/hook/\(pathID.lowercased())"
        case .cloudflareTunnel:
            return "https://<your-cloudflare-tunnel-host>/hook/\(pathID.lowercased())"
        case .tailscaleFunnel:
            return "https://<your-tailscale-funnel-host>/hook/\(pathID.lowercased())"
        case .relaySketch:
            return "https://<relay-worker-host>/hook/\(pathID.lowercased())"
        }
    }

    static func cloudflaredCommand(port: UInt16) -> String {
        "cloudflared tunnel --url http://127.0.0.1:\(port)"
    }

    static func tailscaleFunnelCommand(port: UInt16) -> String {
        "tailscale funnel \(port)"
    }
}
