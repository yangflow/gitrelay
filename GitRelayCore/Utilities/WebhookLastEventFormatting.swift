import Foundation

/// Formats webhook last-event rows for Settings (relative time · repo · status).
nonisolated enum WebhookLastEventFormatting {
    static func display(_ event: WebhookLastEvent, now: Date = Date()) -> String {
        let relative = relativePhrase(for: event.receivedAt, now: now)
        return String.loc("\(relative) · \(event.repoName) · \(event.statusCode)")
    }

    /// Quiet empty line when there is no event yet.
    static func displayOrEmpty(_ event: WebhookLastEvent?) -> String {
        guard let event else { return "" }
        return display(event)
    }

    static func relativePhrase(for date: Date, now: Date) -> String {
        if now.timeIntervalSince(date) < ProviderAccountLastUsed.justNowWindow {
            return String.loc("Just now")
        }
        return date.formatted(.relative(presentation: .named))
    }
}
