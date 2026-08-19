import Foundation

nonisolated enum GitRemoteHost {
    static func host(from remoteURL: String) -> String? {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("git@") {
            let remainder = trimmed.dropFirst("git@".count)
            guard let separator = remainder.firstIndex(where: { $0 == ":" || $0 == "/" }) else {
                return nil
            }
            return String(remainder[..<separator]).lowercased()
        }

        guard let components = URLComponents(string: trimmed), let host = components.host else {
            return nil
        }
        return host.lowercased()
    }

    static func inferredProvider(from host: String) -> GitProvider {
        let normalized = host.lowercased()
        if normalized == "github.com" || normalized.hasSuffix(".github.com") {
            return .github
        }
        if normalized == "gitlab.com"
            || normalized.hasSuffix(".gitlab.com")
            || normalized.contains("gitlab") {
            return .gitlab
        }
        return .gitea
    }

    static func inferredProvider(fromRemoteURL remoteURL: String) -> GitProvider? {
        guard let host = host(from: remoteURL) else { return nil }
        return inferredProvider(from: host)
    }

    static func sshKeysSettingsURL(for provider: GitProvider, host: String) -> URL {
        let normalizedHost = host.lowercased()
        switch provider {
        case .github:
            return URL(string: "https://github.com/settings/keys")!
        case .gitlab:
            if normalizedHost == "gitlab.com" {
                return URL(string: "https://gitlab.com/-/user_settings/ssh_keys")!
            }
            return URL(string: "https://\(normalizedHost)/-/user_settings/ssh_keys")!
        case .gitea:
            return URL(string: "https://\(normalizedHost)/user/settings/keys")!
        }
    }

    static func sshKeysSettingsURL(forRemoteURL remoteURL: String) -> URL? {
        guard let host = host(from: remoteURL) else { return nil }
        let provider = inferredProvider(from: host)
        return sshKeysSettingsURL(for: provider, host: host)
    }

    static func sshKeysSettingsLabel(for provider: GitProvider) -> String {
        switch provider {
        case .github: "GitHub"
        case .gitlab: "GitLab"
        case .gitea:  "Gitea"
        }
    }
}
