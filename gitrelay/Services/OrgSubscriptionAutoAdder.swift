import Foundation

/// Ingests newly discovered org repos using a subscription template.
@MainActor
enum OrgSubscriptionAutoAdder {
    static func addNewRepos(
        from result: OrgSubscriptionCheckResult,
        store: OrgSubscriptionStore
    ) async -> [MirrorPlan] {
        guard result.subscription.autoAddEnabled else { return [] }
        let template = result.subscription.template
        guard OrgSubscriptionTemplateApplier.isValidTemplate(template) else { return [] }

        var plans: [MirrorPlan] = []
        for repo in result.newRepos {
            if let plan = await addRepo(
                repo: repo,
                subscription: result.subscription,
                store: store
            ) {
                plans.append(plan)
            }
        }
        return plans
    }

    static func addRepo(
        repo: RemoteRepo,
        subscription: OrgSubscription,
        store: OrgSubscriptionStore
    ) async -> MirrorPlan? {
        let template = subscription.template
        guard OrgSubscriptionTemplateApplier.isValidTemplate(template) else { return nil }
        guard let plan = await buildPlan(
            for: repo,
            template: template,
            subscription: subscription,
            store: store
        ) else {
            return nil
        }
        persistTokens(
            for: [plan],
            subscription: subscription,
            template: template,
            store: store
        )
        return plan
    }

    private static func buildPlan(
        for repo: RemoteRepo,
        template: OrgSubscriptionTemplate,
        subscription: OrgSubscription,
        store: OrgSubscriptionStore
    ) async -> MirrorPlan? {
        if template.targetAutoCreate {
            return await buildAutoCreateConfig(for: repo, template: template)
        }
        guard let dstURL = OrgSubscriptionTemplateApplier.destinationURL(for: repo, template: template) else {
            return nil
        }
        return OrgSubscriptionTemplateApplier.makePlan(
            repo: repo,
            template: template,
            dstURL: dstURL
        )
    }

    private static func buildAutoCreateConfig(
        for repo: RemoteRepo,
        template: OrgSubscriptionTemplate
    ) async -> MirrorPlan? {
        guard let baseURL = resolvedGiteaBaseURL(template.targetCreateHost) else { return nil }
        let token = ProviderTokenStore.load(provider: .gitea, accountLabel: ProviderAccount.defaultLabel) ?? ""
        guard !token.isEmpty else { return nil }

        let client = GiteaTargetAPIClient(baseURL: baseURL, token: token)
        let name = template.namePrefix + repo.name
        do {
            let outcome = try await client.createRepo(
                name: name,
                namespace: targetNamespace(for: template),
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
            return OrgSubscriptionTemplateApplier.makePlan(
                repo: repo,
                template: template,
                dstURL: dstURL
            )
        } catch {
            return nil
        }
    }

    private static func persistTokens(
        for plans: [MirrorPlan],
        subscription: OrgSubscription,
        template: OrgSubscriptionTemplate,
        store: OrgSubscriptionStore
    ) {
        let sourceToken = ProviderTokenStore.load(
            provider: subscription.provider,
            accountLabel: subscription.accountLabel
        )
        let targetToken = store.loadTargetToken(for: subscription.id)

        for plan in plans {
            if case .httpsToken(let tag) = plan.source.auth,
               template.sourceAuthMode == .httpsToken,
               let sourceToken, !sourceToken.isEmpty {
                try? KeychainService.saveToken(sourceToken, tag: tag)
            }
            for destination in plan.destinations {
                guard case .git(let endpoint) = destination.location else { continue }
                if case .httpsToken(let tag) = endpoint.auth,
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

    private static func targetNamespace(for template: OrgSubscriptionTemplate) -> TargetNamespace {
        switch template.targetNamespaceKind {
        case .currentUser:
            return .currentUser
        case .organization:
            return .organization(
                template.targetNamespaceOwner.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        case .adminForUser:
            return .adminForUser(
                template.targetNamespaceOwner.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }
}
