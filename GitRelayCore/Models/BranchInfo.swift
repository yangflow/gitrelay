import Foundation

struct BranchInfo: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let tipSHA: String
    let isDefault: Bool
}
