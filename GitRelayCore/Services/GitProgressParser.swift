import Foundation

/// Extracts safe object/byte progress from git (and git-lfs) stderr progress lines.
/// Never returns the raw line — credentials in URLs must not reach the UI.
enum GitProgressParser {
    /// Returns a short progress caption, or `nil` when the line is not a recognized progress update.
    static func detail(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Belt-and-suspenders: never surface credential-bearing fragments.
        let safe = SyncEngine.redactCredentials(trimmed)
        if safe.contains("****@") {
            // Still try to parse after redaction; if we cannot, drop the line.
        }

        if let objects = parseObjectCounts(from: safe) {
            return objects
        }
        if let bytes = parseTransferredBytes(from: safe) {
            return bytes
        }
        return nil
    }

    // MARK: - Private

    /// Matches `Receiving objects:  45% (1234/2745), ...` and similar.
    private static func parseObjectCounts(from line: String) -> String? {
        let patterns = [
            #"Receiving objects:\s+\d+%\s+\((\d+)/(\d+)\)"#,
            #"Writing objects:\s+\d+%\s+\((\d+)/(\d+)\)"#,
            #"Counting objects:\s+\d+%\s+\((\d+)/(\d+)\)"#,
            #"Compressing objects:\s+\d+%\s+\((\d+)/(\d+)\)"#,
            #"Resolving deltas:\s+\d+%\s+\((\d+)/(\d+)\)"#,
            #"Downloading LFS objects:\s+\d+%\s+\((\d+)/(\d+)\)"#,
            #"Uploading LFS objects:\s+\d+%\s+\((\d+)/(\d+)\)"#,
            #"(?:Git LFS|LFS).*\((\d+)/(\d+)\)"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  match.numberOfRanges >= 3,
                  let doneRange = Range(match.range(at: 1), in: line),
                  let totalRange = Range(match.range(at: 2), in: line),
                  let done = Int(line[doneRange]),
                  let total = Int(line[totalRange]),
                  total > 0
            else {
                continue
            }
            return String(localized: "\(done) / \(total) objects")
        }
        return nil
    }

    /// Matches trailing size fragments like `12.50 MiB` or `150 MB` after a percent progress prefix.
    private static func parseTransferredBytes(from line: String) -> String? {
        let looksLikeProgress =
            line.localizedCaseInsensitiveContains("objects:")
            || line.localizedCaseInsensitiveContains("LFS")
            || line.localizedCaseInsensitiveContains("Downloading")
            || line.localizedCaseInsensitiveContains("Uploading")
        guard looksLikeProgress else { return nil }

        guard let regex = try? NSRegularExpression(
            pattern: #"(\d+(?:\.\d+)?)\s+(KiB|MiB|GiB|TiB|KB|MB|GB|TB|B)\b"#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let range = NSRange(line.startIndex..., in: line)
        let matches = regex.matches(in: line, range: range)
        // Prefer the first size token (transferred amount), not the rate after `|`.
        guard let match = matches.first,
              match.numberOfRanges >= 3,
              let amountRange = Range(match.range(at: 1), in: line),
              let unitRange = Range(match.range(at: 2), in: line)
        else {
            return nil
        }
        let amount = String(line[amountRange])
        let unit = String(line[unitRange])
        return "\(amount) \(unit)"
    }
}
