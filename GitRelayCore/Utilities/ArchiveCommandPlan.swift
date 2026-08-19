import Foundation

struct ArchiveCommandPlan: Equatable {
    enum Tool: String, Equatable {
        case tar
        case zip
        case git
    }

    let tool: Tool
    let arguments: [String]
    let workingDirectory: String?

    var executableCandidates: [String] {
        switch tool {
        case .tar:
            return ["/usr/bin/tar", "/bin/tar"]
        case .zip:
            return ["/usr/bin/zip"]
        case .git:
            return ["/usr/bin/git", "/usr/local/bin/git", "/opt/homebrew/bin/git"]
        }
    }
}

enum ArchiveCommandBuilder {
    static func plan(
        format: ArchiveFormat,
        mirrorPath: String,
        outputPath: String
    ) -> ArchiveCommandPlan {
        let mirrorURL = URL(fileURLWithPath: mirrorPath, isDirectory: true)
        let parentPath = mirrorURL.deletingLastPathComponent().path
        let directoryName = mirrorURL.lastPathComponent

        switch format {
        case .tarGz:
            return ArchiveCommandPlan(
                tool: .tar,
                arguments: ["-czf", outputPath, "-C", parentPath, directoryName],
                workingDirectory: nil
            )
        case .zip:
            return ArchiveCommandPlan(
                tool: .zip,
                arguments: ["-r", outputPath, directoryName],
                workingDirectory: parentPath
            )
        case .gitBundle:
            return ArchiveCommandPlan(
                tool: .git,
                arguments: ["bundle", "create", outputPath, "--all"],
                workingDirectory: mirrorPath
            )
        }
    }
}
