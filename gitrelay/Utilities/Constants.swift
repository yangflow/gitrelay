import Foundation

enum Constants {
    static let bundleID = "com.yangflow.gitrelay"

    static let baseDirectory: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/gitrelay")
    }()

    static let mirrorsDirectory: URL = baseDirectory.appendingPathComponent("mirrors")
    static let reposFile: URL = baseDirectory.appendingPathComponent("repos.json")
}
