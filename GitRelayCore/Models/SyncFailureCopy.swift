import Foundation

/// The clipboard payload behind 复制这次失败: which pair failed, when, the error,
/// and the failed run's log — every line through ``SyncEngine.redactCredentials``,
/// so a URL carrying a token cannot ride along into an issue report.
nonisolated enum SyncFailureCopy {
    /// Keeps a long clone/push log from taking over the clipboard.
    static let maxLogLines = 300

    static func text(
        repo: RepoConfig,
        message: String,
        logLines: [String] = [],
        failedAt: Date? = nil
    ) -> String {
        var lines: [String] = [String.loc("GitRelay sync failure")]
        lines.append(String.loc("Repository: \(redacted(repo.name))"))
        lines.append(String.loc("Source: \(redacted(repo.srcURL))"))
        for target in repo.targets {
            lines.append(String.loc("Target: \(redacted(target.displayLabel))"))
        }
        if let failedAt {
            lines.append(String.loc("Failed at: \(timestamp(failedAt))"))
        }
        let safeMessage = redacted(message)
        if !safeMessage.isEmpty {
            lines.append(String.loc("Error: \(safeMessage)"))
        }

        let safeLog = redactedLog(logLines)
        if !safeLog.isEmpty {
            lines.append(String.loc("Log:"))
            if logLines.count > maxLogLines {
                lines.append(String.loc("Showing the last \(maxLogLines) log lines"))
            }
            lines.append(contentsOf: safeLog)
        }

        return lines.joined(separator: "\n")
    }

    private static func redactedLog(_ logLines: [String]) -> [String] {
        logLines
            .suffix(maxLogLines)
            .map { redacted($0) }
            .filter { !$0.isEmpty }
    }

    private static func redacted(_ value: String) -> String {
        SyncEngine.redactCredentials(value).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// UTC, so a pasted report reads the same wherever it lands.
    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
