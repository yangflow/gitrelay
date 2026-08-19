import Foundation

enum ArchiveFilenameTemplate {
    static let defaultDateFormat = "yyyy-MM-dd"

    /// Replaces `{name}` and `{date}` placeholders in a filename template.
    static func render(
        template: String,
        repoName: String,
        date: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = defaultDateFormat
        let dateString = formatter.string(from: date)

        let sanitizedName = sanitizeFilenameComponent(repoName)
        return template
            .replacingOccurrences(of: "{name}", with: sanitizedName)
            .replacingOccurrences(of: "{date}", with: dateString)
    }

    static func sanitizeFilenameComponent(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "repo" }
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let sanitized = trimmed.unicodeScalars.map { invalid.contains($0) ? "-" : Character($0) }
        let result = String(sanitized).trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return result.isEmpty ? "repo" : result
    }
}
