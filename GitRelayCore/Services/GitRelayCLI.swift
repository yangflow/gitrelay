import Foundation

enum GitRelayCLIExitCode: Int32, Equatable, Sendable {
    case success = 0
    case failure = 1
    case usage = 2
    case repoNotFound = 3
}

enum GitRelayCLICommand: Equatable, Sendable {
    case list
    case sync(name: String)
    case status(name: String?)
    case logs(name: String, tail: Int?)
    case help
}

enum GitRelayCLIParseError: LocalizedError, Equatable {
    case missingSubcommand
    case unknownSubcommand(String)
    case missingRepoName(String)
    case invalidTailValue(String)

    var errorDescription: String? {
        switch self {
        case .missingSubcommand:
            return "Missing subcommand."
        case .unknownSubcommand(let command):
            return "Unknown subcommand \"\(command)\"."
        case .missingRepoName(let subcommand):
            return "Missing repository name for \"\(subcommand)\"."
        case .invalidTailValue(let value):
            return "Invalid value for --tail: \"\(value)\"."
        }
    }
}

enum GitRelayCLIParser {
    static let usage = """
    gitrelayctl — headless GitRelay control tool

    Usage:
      gitrelayctl list
      gitrelayctl sync <name>
      gitrelayctl status [<name>]
      gitrelayctl logs <name> [--tail N]

    Config: ~/.local/share/gitrelay/repos.json
    """

    static func parse(_ arguments: [String]) -> Result<GitRelayCLICommand, GitRelayCLIParseError> {
        var args = arguments
        if let first = args.first, (first as NSString).lastPathComponent == "gitrelayctl" {
            args.removeFirst()
        }

        guard let subcommand = args.first?.lowercased() else {
            return .failure(.missingSubcommand)
        }

        switch subcommand {
        case "-h", "--help", "help":
            return .success(.help)
        case "list":
            return .success(.list)
        case "sync":
            guard let name = args.dropFirst().first, !name.isEmpty else {
                return .failure(.missingRepoName("sync"))
            }
            return .success(.sync(name: name))
        case "status":
            let name = args.dropFirst().first
            return .success(.status(name: name))
        case "logs":
            guard let name = args.dropFirst().first, !name.isEmpty else {
                return .failure(.missingRepoName("logs"))
            }
            switch parseTail(from: Array(args.dropFirst(2))) {
            case .success(let tail):
                return .success(.logs(name: name, tail: tail))
            case .failure(let error):
                return .failure(error)
            }
        default:
            return .failure(.unknownSubcommand(subcommand))
        }
    }

    private static func parseTail(from args: [String]) -> Result<Int?, GitRelayCLIParseError> {
        var index = 0
        var tail: Int?
        while index < args.count {
            let arg = args[index]
            if arg == "--tail" {
                guard index + 1 < args.count else {
                    return .failure(.invalidTailValue(""))
                }
                guard let value = Int(args[index + 1]), value >= 0 else {
                    return .failure(.invalidTailValue(args[index + 1]))
                }
                tail = value
                index += 2
                continue
            }
            if arg.hasPrefix("--tail=") {
                let raw = String(arg.dropFirst("--tail=".count))
                guard let value = Int(raw), value >= 0 else {
                    return .failure(.invalidTailValue(raw))
                }
                tail = value
                index += 1
                continue
            }
            return .failure(.unknownSubcommand(arg))
        }
        return .success(tail)
    }
}

struct GitRelayCLIStatusDocument: Codable, Equatable, Sendable {
    var repos: [GitRelayCLIStatusEntry]
}

struct GitRelayCLIStatusEntry: Codable, Equatable, Sendable {
    var repoName: String
    var status: RepoSyncStatusKind
    var lastSyncedAt: Date?
    var message: String?
}

enum GitRelayCLIFormatter {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static func jsonString<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw GitRelayCLIExecutionError.outputEncodingFailed
        }
        return string
    }

    static func statusEntry(from snapshot: RepoSyncStatusSnapshot) -> GitRelayCLIStatusEntry {
        GitRelayCLIStatusEntry(
            repoName: snapshot.repoName,
            status: snapshot.status,
            lastSyncedAt: snapshot.lastSyncedAt,
            message: snapshot.message
        )
    }
}

enum GitRelayCLIExecutionError: LocalizedError, Equatable {
    case outputEncodingFailed

    var errorDescription: String? {
        switch self {
        case .outputEncodingFailed:
            return "Failed to encode CLI output."
        }
    }
}

enum GitRelayCLIExecutor {
    static func exitCode(for error: Error) -> GitRelayCLIExitCode {
        if let headlessError = error as? HeadlessSyncError {
            switch headlessError {
            case .repoNotFound:
                return .repoNotFound
            case .loadFailed, .saveFailed:
                return .failure
            }
        }
        if error is GitRelayCLIParseError {
            return .usage
        }
        return .failure
    }

    static func run(command: GitRelayCLICommand) async throws -> GitRelayCLIExitCode {
        switch command {
        case .help:
            print(GitRelayCLIParser.usage)
            return .success
        case .list:
            let repos = try HeadlessSyncRunner.loadRepos()
            for repo in repos {
                print(repo.name)
            }
            return .success
        case .sync(let name):
            let succeeded = try await HeadlessSyncRunner.sync(repoName: name)
            return succeeded ? .success : .failure
        case .status(let name):
            let repos = try HeadlessSyncRunner.loadRepos()
            if let name {
                guard let repo = RepoIntentSupport.repo(matchingName: name, in: repos) else {
                    throw HeadlessSyncError.repoNotFound(name)
                }
                let snapshot = RepoIntentSupport.makeSnapshot(
                    repo: repo,
                    runtimeStatus: nil,
                    isSyncInProgress: false
                )
                print(try GitRelayCLIFormatter.jsonString(GitRelayCLIFormatter.statusEntry(from: snapshot)))
            } else {
                let document = GitRelayCLIStatusDocument(
                    repos: repos.map { repo in
                        let snapshot = RepoIntentSupport.makeSnapshot(
                            repo: repo,
                            runtimeStatus: nil,
                            isSyncInProgress: false
                        )
                        return GitRelayCLIFormatter.statusEntry(from: snapshot)
                    }
                )
                print(try GitRelayCLIFormatter.jsonString(document))
            }
            return .success
        case .logs(let name, let tail):
            let repos = try HeadlessSyncRunner.loadRepos()
            guard let repo = RepoIntentSupport.repo(matchingName: name, in: repos) else {
                throw HeadlessSyncError.repoNotFound(name)
            }
            let lines = try SyncLogStore.formattedLogLines(for: repo.id, tail: tail)
            for line in lines {
                print(line)
            }
            return .success
        }
    }
}
