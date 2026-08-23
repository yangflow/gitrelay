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

    static var mirrorPlansFile: URL {
        baseDirectory.appendingPathComponent("mirrors.json")
    }

    static var mirrorStateFile: URL {
        baseDirectory.appendingPathComponent("mirror-state.json")
    }

    static var mirrorLogsDirectory: URL {
        baseDirectory.appendingPathComponent("logs")
    }

    static var mirrorCacheDirectory: URL {
        baseDirectory.appendingPathComponent("mirrors")
    }

    static var verificationScratchDirectory: URL {
        baseDirectory.appendingPathComponent("verify-scratch")
    }

    #if DEBUG
    static func setBaseDirectoryForTesting(_ url: URL?) {
        testingBaseDirectory = url
    }
    #endif
}
