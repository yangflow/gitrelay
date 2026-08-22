import Foundation

/// User-facing copy for the org-discovery quiet sheet (#108).
enum OrgDiscoverySheetCopy {
  static var title: String {
    String(localized: "New Repository Found")
  }

  static var sourceLabel: String {
    String(localized: "Source")
  }

  static var targetLabel: String {
    String(localized: "Target")
  }

  static var targetFromTemplatePlaceholder: String {
    String(localized: "Will be filled from the template")
  }

  static var ignoreTitle: String {
    String(localized: "Ignore")
  }

  static var laterTitle: String {
    String(localized: "Later")
  }

  static var joinAndSyncTitle: String {
    String(localized: "Join and Sync")
  }

  static func discoverySentence(organizationName: String, repoName: String) -> String {
    String(
      format: String(localized: "%1$@ has %2$@, not yet mirrored."),
      organizationName,
      repoName
    )
  }

  static func sourceHostPath(
    provider: GitProvider,
    fullName: String,
    customHost: String?
  ) -> String {
    let host = resolvedHost(provider: provider, customHost: customHost)
    return "\(host)/\(fullName)"
  }

  /// Destination label shown on the sheet; uses the subscription template when valid.
  static func targetPreview(
    for repo: RemoteRepo,
    template: OrgSubscriptionTemplate
  ) -> String {
    guard OrgSubscriptionTemplateApplier.isValidTemplate(template),
          let destinationURL = OrgSubscriptionTemplateApplier.destinationURL(for: repo, template: template)
    else {
      return targetFromTemplatePlaceholder
    }
    return gitRemoteDisplayLabel(for: destinationURL)
  }

  static func gitRemoteDisplayLabel(for remoteURL: String) -> String {
    let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let path = GitRemoteRepoPath.parse(from: trimmed) else { return trimmed }
    guard let host = GitRemoteHost.host(from: trimmed) else { return path.pathWithNamespace }
    return "\(host)/\(path.pathWithNamespace)"
  }

  private static func resolvedHost(provider: GitProvider, customHost: String?) -> String {
    if let customHost {
      let trimmed = customHost.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty {
        return normalizedHostOnly(trimmed)
      }
    }
    return ProviderAccountSummary.defaultHost(for: provider)
  }

  private static func normalizedHostOnly(_ raw: String) -> String {
    var host = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if host.hasPrefix("https://") { host.removeFirst("https://".count) }
    else if host.hasPrefix("http://") { host.removeFirst("http://".count) }
    while host.hasSuffix("/") { host.removeLast() }
    if host.hasSuffix("/api/v4") { host = String(host.dropLast("/api/v4".count)) }
    while host.hasSuffix("/") { host.removeLast() }
    return host
  }
}
