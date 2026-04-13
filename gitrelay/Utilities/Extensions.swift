import Foundation

extension String {
    var truncatingSHA: String {
        count > 7 ? String(prefix(7)) : self
    }
}
