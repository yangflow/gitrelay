import Foundation

/// Ingests newly discovered org repos using a subscription template.
@MainActor
enum OrgSubscriptionAutoAdder {
    static func addNewRepos(
        from result: OrgSubscriptionCheckResult,
        store: OrgSubscriptionStore
    ) async -> [RepoConfig] {
        guard result.subscription.autoAddEnabled else { return [] }
        let template = result.subscription.template
        guard OrgSubscriptionTemplateApplier.isValidTemplate(template) else { return [] }

        var configs: [RepoConfig] = []
        for repo in result.newRepos {
            if let config = await buildConfig(
                for: repo,
                template: template,
                subscription: result.subscription,
                store: store
            ) {
                configs.append(config)
            }
        }

        persistTokens(for: configs, subscription: result.subscription, template: template, store: store)
        return configs
    }

    private static func buildConfig(
        for repo: RemoteRepo,
        template: OrgSubscriptionTemplate,
        subscription: OrgSubscription,
        store: OrgSubscriptionStore
    ) async -> RepoConfig? {
        if template.targetAutoCreate {
            return await buildAutoCreateConfig(for: repo, template: template)
        }
        guard let dstURL = OrgSubscriptionTemplateApplier.destinationURL(for: repo, template: template) else {
            return nil
        }
        return OrgSubscriptionTemplateApplier.makeConfig(
            repo: repo,
            template: template,
            dstURL: dstURL
        )
    }

    private static func buildAutoCreateConfig(
        for repo: RemoteRepo,
        template: OrgSubscriptionTemplate
    ) async -> RepoConfig? {
        guard let baseURL = resolvedGiteaBaseURL(template.targetCreateHost) else { return nil }
        let token = ProviderTokenStore.load(provider: .gitea, accountLabel: ProviderAccount.defaultLabel) ?? ""
        guard !token.isEmpty else { return nil }

        let client = GiteaTargetAPIClient(baseURL: baseURL, token: token)
        let name = template.namePrefix + repo.name
        do {
            let outcome = try await client.createRepo(
                name: name,
                namespace: OrgSubscriptionTemplateApplier.targetNamespace(for: template),
                isPrivate: template.targetVisibilityPrivate,
                description: repo.description
            )
            let dstURL: String = {
                switch outcome {
                case .created(let https, let ssh):
                    switch template.targetAuthMode {
                    case .sshAgent, .sshKey: return ssh
                    case .httpsToken:        return https
                    }
                case .alreadyExists(let https, let ssh):
                    switch template.targetAuthMode {
                    case .sshAgent, .sshKey: return ssh
                    case .httpsToken:        return https
                    }
                }
            }()
            return OrgSubscriptionTemplateApplier.makeConfig(
                repo: repo,
                template: template,
                dstURL: dstURL
            )
        } catch {
            return nil
        }
    }

    private static func persistTokens(
        for configs: [RepoConfig],
        subscription: OrgSubscription,
        template: OrgSubscriptionTemplate,
        store: OrgSubscriptionStore
    ) {
        let sourceToken = ProviderTokenStore.load(
            provider: subscription.provider,
            accountLabel: subscription.accountLabel
        )
        let targetToken = store.loadTargetToken(for: subscription.id)

        for config in configs {
            if case .httpsToken(let tag) = config.srcAuth,
               template.sourceAuthMode == .httpsToken,
               let sourceToken, !sourceToken.isEmpty {
                try? KeychainService.saveToken(sourceToken, tag: tag)
            }
            for target in config.targets {
                if case .httpsToken(let tag) = target.auth,
                   template.targetAuthMode == .httpsToken,
                   let targetToken, !targetToken.isEmpty {
                    try? KeychainService.saveToken(targetToken, tag: tag)
                }
            }
        }
    }

    private static func resolvedGiteaBaseURL(_ raw: String) -> URL? {
        var host = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return nil }
        if !host.hasPrefix("http://"), !host.hasPrefix("https://") { host = "https://" + host }
        while host.hasSuffix("/") { host.removeLast() }
        if host.hasSuffix("/api/v1") { host = String(host.dropLast("/api/v1".count)) }
        return URL(string: host + "/api/v1")
    }
}
