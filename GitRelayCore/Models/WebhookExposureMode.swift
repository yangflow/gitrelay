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
        case .off: return "仅本机 (127.0.0.1)"
        case .cloudflareTunnel: return "Cloudflare Tunnel"
        case .tailscaleFunnel: return "Tailscale Funnel"
        case .relaySketch: return "中继回落 (示意)"
        }
    }

    var helpText: String {
        switch self {
        case .off:
            return "Webhook 仅监听本机回环地址。可用 curl 本地验证；外网需要开启下方暴露模式。"
        case .cloudflareTunnel:
            return "需本机已安装 cloudflared。示例：cloudflared tunnel --url http://127.0.0.1:<port>，再把生成的 https 主机填入公共 Base URL。"
        case .tailscaleFunnel:
            return "需本机已安装 tailscale 并启用 Funnel。示例：tailscale funnel <port>，再把 Funnel HTTPS 主机填入公共 Base URL。"
        case .relaySketch:
            return "未来可由 Cloudflare Worker / GitHub App 长轮询中继到本机；本版本仅保留配置入口，不部署托管基础设施。"
        }
    }
}
