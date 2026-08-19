import Foundation

extension String {
    var truncatingSHA: String {
        count > 7 ? String(prefix(7)) : self
    }
}

extension Notification.Name {
    /// Posted when the app needs the main window frontmost (e.g. destructive push confirm).
    static let gitrelayOpenMainWindow = Notification.Name("gitrelay.openMainWindow")
}
