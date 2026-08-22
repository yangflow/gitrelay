import Foundation

/// How (if at all) the local webhook listener is exposed beyond loopback.
/// All modes are opt-in; default is `.off`.
nonisolated enum WebhookExposureMode: String, CaseIterable, Identifiable, Sendable {
    /// Local listener only (`127.0.0.1`); no public URL template.
    case off
    /// User already runs Cloudflare Tunnel (`cloudflared`); app only shows a URL template.
    case cloudflareTunnel
    /// User already runs Tailscale Funnel; app only shows a URL template.
    case tailscaleFunnel
    /// Documented sketch for a future Worker / GitHub App relay — no hosted infra in this build.
    case relaySketch

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return String.loc("Local Only (127.0.0.1)")
        case .cloudflareTunnel: return "Cloudflare Tunnel"
        case .tailscaleFunnel: return "Tailscale Funnel"
        case .relaySketch: return String.loc("Relay Fallback (Example)")
        }
    }

    var helpText: String {
        switch self {
        case .off:
            return String.loc("The webhook listens only on the local loopback address. You can verify it locally with curl; external access requires an exposure mode below.")
        case .cloudflareTunnel:
            return String.loc("cloudflared must be installed locally. Example: cloudflared tunnel --url http://127.0.0.1:<port>, then enter the generated HTTPS host in Public Base URL.")
        case .tailscaleFunnel:
            return String.loc("Tailscale must be installed locally with Funnel enabled. Example: tailscale funnel <port>, then enter the Funnel HTTPS host in Public Base URL.")
        case .relaySketch:
            return String.loc("A future Cloudflare Worker or GitHub App could relay to this Mac using long polling. This version provides configuration only and does not deploy hosted infrastructure.")
        }
    }
}
