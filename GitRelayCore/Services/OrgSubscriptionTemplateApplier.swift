import Foundation

/// Builds `RepoConfig` values from org subscription templates (shared by auto-add and tests).
nonisolated enum OrgSubscriptionTemplateApplier {
    static func makeConfig(
        repo: RemoteRepo,
        template: OrgSubscriptionTemplate,
        dstURL: String
    ) -> RepoConfig {
        let id = UUID()
        let targetID = UUID()
        let name = template.namePrefix + repo.name
        let srcURL: String = {
            switch template.sourceAuthMode {
            case .sshAgent, .sshKey: repo.sshCloneURL
            case .httpsToken:        repo.httpsCloneURL
            }
        }()
        return RepoConfig(
            id: id,
            name: name,
            srcURL: srcURL,
            targets: [
                MirrorTarget(
                    id: targetID,
                    url: dstURL,
                    auth: buildAuth(
                        mode: template.targetAuthMode,
                        keyPath: template.targetKeyPath,
                        repoID: id,
                        side: "target-\(targetID.uuidString)"
                    )
                )
            ],
            srcAuth: buildAuth(
                mode: template.sourceAuthMode,
                keyPath: template.sourceKeyPath,
                repoID: id,
                side: "src"
            ),
            frequency: template.frequency
        )
    }

    static func destinationURL(
        for repo: RemoteRepo,
        template: OrgSubscriptionTemplate
    ) -> String? {
        if template.targetAutoCreate {
            let host = normalizedHostOnly(template.targetCreateHost)
            guard !host.isEmpty else { return nil }
            let owner = resolvedOwner(template: template)
            let name = template.namePrefix + repo.name
            switch template.targetAuthMode {
            case .sshAgent, .sshKey:
                return "git@\(host):\(owner)/\(name).git"
            case .httpsToken:
                return "https://\(host)/\(owner)/\(name).git"
            }
        }
        return render(template: template.targetURLTemplate, repo: repo)
    }

    static func isValidTemplate(_ template: OrgSubscriptionTemplate) -> Bool {
        if template.targetAutoCreate {
            let host = template.targetCreateHost.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !host.isEmpty else { return false }
            if template.targetNamespaceKind == .organization || template.targetNamespaceKind == .adminForUser {
                return !template.targetNamespaceOwner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return true
        }
        let trimmed = template.targetURLTemplate.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.contains("{name}") else { return false }
        if trimmed.hasPrefix("git@") { return true }
        if let url = URL(string: trimmed.replacingOccurrences(of: "{name}", with: "x")),
           url.scheme == "https" {
            return true
        }
        return false
    }

    private static func buildAuth(
        mode: AuthMode,
        keyPath: String,
        repoID: UUID,
        side: String
    ) -> AuthConfig {
        switch mode {
        case .sshAgent:   .sshAgent
        case .sshKey:     .sshKey(privateKeyPath: keyPath)
        case .httpsToken: .httpsToken(keychainTag: "\(repoID.uuidString)-\(side)")
        }
    }

    private static func render(template: String, repo: RemoteRepo) -> String {
        template.replacingOccurrences(of: "{name}", with: repo.name)
    }

    private static func normalizedHostOnly(_ raw: String) -> String {
        var host = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.hasPrefix("https://") { host.removeFirst("https://".count) }
        else if host.hasPrefix("http://") { host.removeFirst("http://".count) }
        while host.hasSuffix("/") { host.removeLast() }
        if host.hasSuffix("/api/v1") { host = String(host.dropLast("/api/v1".count)) }
        while host.hasSuffix("/") { host.removeLast() }
        return host
    }

    private static func resolvedOwner(template: OrgSubscriptionTemplate) -> String {
        switch template.targetNamespaceKind {
        case .currentUser:  return "<user>"
        case .organization: return template.targetNamespaceOwner.isEmpty ? "<org>" : template.targetNamespaceOwner
        case .adminForUser: return template.targetNamespaceOwner.isEmpty ? "<user>" : template.targetNamespaceOwner
        }
    }
}
