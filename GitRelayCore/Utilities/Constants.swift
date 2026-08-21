import Foundation

nonisolated enum Constants {
    static let bundleID = "com.yangflow.gitrelay"

    /// Test-only override; written from test setup before concurrent work.
    nonisolated(unsafe) private static var testingBaseDirectory: URL?

    static var baseDirectory: URL {
        if let testingBaseDirectory {
            return testingBaseDirectory
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/gitrelay")
    }

    static var mirrorsDirectory: URL {
        baseDirectory.appendingPathComponent("mirrors")
    }

    static var reposFile: URL {
        baseDirectory.appendingPathComponent("repos.json")
    }

    #if DEBUG
    static func setBaseDirectoryForTesting(_ url: URL?) {
        testingBaseDirectory = url
    }
    #endif
}
