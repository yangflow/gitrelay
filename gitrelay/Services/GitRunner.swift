import Foundation

enum GitError: LocalizedError {
    case gitNotFound
    case processError(Int32, String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .gitNotFound:                   return "git not found in PATH"
        case .processError(let code, let m): return "git exited \(code): \(m)"
        case .cancelled:                     return "Operation cancelled"
        }
    }
}

actor GitRunner {
    private var activeProcess: Process?

    private static let gitPath: String? = {
        let candidates = ["/usr/bin/git", "/usr/local/bin/git", "/opt/homebrew/bin/git"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    // MARK: - Core runner

    func run(args: [String], env: [String: String] = [:], cwd: String? = nil) async throws -> (stdout: String, stderr: String) {
        guard let gitPath = Self.gitPath else { throw GitError.gitNotFound }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = args

        var environment = ProcessInfo.processInfo.environment
        env.forEach { environment[$0] = $1 }
        process.environment = environment

        if let cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError  = stderrPipe

        activeProcess = process

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { [weak self] proc in
                Task { await self?.clearProcess() }
                let out = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

                if proc.terminationReason == .uncaughtSignal {
                    continuation.resume(throwing: GitError.cancelled)
                } else if proc.terminationStatus == 0 {
                    continuation.resume(returning: (out, err))
                } else {
                    continuation.resume(throwing: GitError.processError(proc.terminationStatus, err))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func cancel() {
        activeProcess?.terminate()
    }

    private func clearProcess() {
        activeProcess = nil
    }

    // MARK: - Git operations

    func cloneMirror(srcURL: String, mirrorPath: String, env: [String: String] = [:]) async throws {
        _ = try await run(args: ["clone", "--mirror", srcURL, mirrorPath], env: env)
    }

    func fetchPrune(mirrorPath: String, env: [String: String] = [:]) async throws {
        _ = try await run(args: ["fetch", "--prune", "origin"], env: env, cwd: mirrorPath)
    }

    func fetchDstRefs(mirrorPath: String, dstURL: String, env: [String: String] = [:]) async throws {
        _ = try await run(
            args: ["fetch", dstURL, "+refs/*:refs/dst/*", "--prune"],
            env: env,
            cwd: mirrorPath
        )
    }

    func pushMirror(mirrorPath: String, dstURL: String, env: [String: String] = [:]) async throws {
        _ = try await run(
            args: ["push", "--mirror", dstURL],
            env: env,
            cwd: mirrorPath
        )
    }

    func pushMirrorDryRun(mirrorPath: String, dstURL: String, env: [String: String] = [:]) async throws -> DestructivePushPlan {
        let (stdout, stderr) = try await run(
            args: ["push", "--mirror", "--dry-run", dstURL],
            env: env,
            cwd: mirrorPath
        )
        return DestructivePushPlan.parse(gitOutput: [stdout, stderr].joined(separator: "\n"))
    }

    func countCommitsAhead(mirrorPath: String) async throws -> Int {
        let (stdout, _) = try await run(
            args: ["rev-list", "--count", "refs/dst/HEAD..HEAD"],
            cwd: mirrorPath
        )
        return Int(stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    func listRefs(repoPath: String, env: [String: String] = [:]) async throws -> [BranchInfo] {
        let (stdout, _) = try await run(
            args: ["for-each-ref",
                   "--format=%(refname:short) %(objectname) %(HEAD)",
                   "refs/heads/"],
            env: env,
            cwd: repoPath
        )
        return stdout
            .split(separator: "\n")
            .compactMap { line -> BranchInfo? in
                let parts = line.split(separator: " ", maxSplits: 2).map(String.init)
                guard parts.count >= 2 else { return nil }
                let isDefault = parts.count == 3 && parts[2].trimmingCharacters(in: .whitespaces) == "*"
                return BranchInfo(name: parts[0], tipSHA: parts[1], isDefault: isDefault)
            }
    }
}
