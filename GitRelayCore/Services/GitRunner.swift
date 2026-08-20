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
        _ = try await run(args: GitSyncArguments.cloneMirrorArgs(srcURL: srcURL, mirrorPath: mirrorPath), env: env)
    }

    func initBareMirror(at path: String, env: [String: String] = [:]) async throws {
        try FileManager.default.createDirectory(
            atPath: path,
            withIntermediateDirectories: true
        )
        _ = try await run(args: ["init", "--bare", path], env: env)
    }

    func addRemote(
        mirrorPath: String,
        name: String,
        url: String,
        env: [String: String] = [:]
    ) async throws {
        _ = try await run(
            args: ["remote", "add", name, url],
            env: env,
            cwd: mirrorPath
        )
    }

    func fetchSource(
        mirrorPath: String,
        depth: Int?,
        refSpecs: [String],
        env: [String: String] = [:]
    ) async throws {
        _ = try await run(
            args: GitSyncArguments.fetchArgs(depth: depth, refSpecs: refSpecs),
            env: env,
            cwd: mirrorPath
        )
    }

    func fetchPrune(mirrorPath: String, env: [String: String] = [:]) async throws {
        _ = try await run(args: ["fetch", "--prune", "origin"], env: env, cwd: mirrorPath)
    }

    func gcAggressive(mirrorPath: String, env: [String: String] = [:]) async throws {
        _ = try await run(
            args: ["gc", "--aggressive", "--prune=now"],
            env: env,
            cwd: mirrorPath
        )
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
            args: GitSyncArguments.pushMirrorArgs(dstURL: dstURL),
            env: env,
            cwd: mirrorPath
        )
    }

    func pushSelectiveRefs(
        mirrorPath: String,
        dstURL: String,
        refSpecs: [String],
        env: [String: String] = [:]
    ) async throws {
        _ = try await run(
            args: GitSyncArguments.pushSelectiveArgs(dstURL: dstURL, refSpecs: refSpecs),
            env: env,
            cwd: mirrorPath
        )
    }

    func pushMirrorDryRun(mirrorPath: String, dstURL: String, env: [String: String] = [:]) async throws -> DestructivePushPlan {
        let (stdout, stderr) = try await run(
            args: GitSyncArguments.pushMirrorDryRunArgs(dstURL: dstURL),
            env: env,
            cwd: mirrorPath
        )
        return DestructivePushPlan.parse(gitOutput: [stdout, stderr].joined(separator: "\n"))
    }

    func pushSelectiveRefsDryRun(
        mirrorPath: String,
        dstURL: String,
        refSpecs: [String],
        env: [String: String] = [:]
    ) async throws -> DestructivePushPlan {
        let (stdout, stderr) = try await run(
            args: GitSyncArguments.pushSelectiveArgs(dstURL: dstURL, refSpecs: refSpecs, dryRun: true),
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

    /// Returns the tip commit SHA for `refs/heads/<branch>`, or nil if the ref is absent.
    func lsRemoteTipSHA(
        url: String,
        branch: String,
        env: [String: String] = [:]
    ) async throws -> String? {
        let ref = branch.hasPrefix("refs/") ? branch : "refs/heads/\(branch)"
        let (stdout, _) = try await run(args: ["ls-remote", url, ref], env: env)
        return Self.parseLSRemoteSHA(stdout, matchingRef: ref)
    }

    /// Fetches a specific commit (and its tree) into a local repo without updating local branch tips.
    func fetchCommit(
        repoPath: String,
        remoteURL: String,
        commitSHA: String,
        env: [String: String] = [:]
    ) async throws {
        _ = try await run(
            args: ["fetch", "--no-tags", remoteURL, commitSHA],
            env: env,
            cwd: repoPath
        )
    }

    func treeHash(repoPath: String, commitSHA: String) async throws -> String {
        let (stdout, _) = try await run(
            args: ["rev-parse", "\(commitSHA)^{tree}"],
            cwd: repoPath
        )
        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func ensureBareRepo(at path: String) async throws {
        let headPath = URL(fileURLWithPath: path).appendingPathComponent("HEAD").path
        if FileManager.default.fileExists(atPath: headPath) {
            return
        }
        try FileManager.default.createDirectory(
            atPath: path,
            withIntermediateDirectories: true
        )
        _ = try await run(args: ["init", "--bare", path])
    }

    nonisolated static func parseLSRemoteSHA(_ output: String, matchingRef: String) -> String? {
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(whereSeparator: { $0 == "\t" || $0 == " " }).map(String.init)
            guard parts.count >= 2 else { continue }
            if parts[1] == matchingRef {
                return parts[0]
            }
        }
        return nil
    }

    // MARK: - Git LFS

    /// Ensures Homebrew / local bins are on PATH so `git lfs` can resolve `git-lfs`.
    private func environmentWithGitLFSPath(_ env: [String: String]) -> [String: String] {
        var merged = env
        let existing = merged["PATH"]
            ?? ProcessInfo.processInfo.environment["PATH"]
            ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let extras = GitLFSTool.pathDirectories()
        var parts = existing.split(separator: ":").map(String.init)
        for dir in extras.reversed() where !parts.contains(dir) {
            parts.insert(dir, at: 0)
        }
        merged["PATH"] = parts.joined(separator: ":")
        return merged
    }

    func isGitLFSAvailable() async throws -> Bool {
        if GitLFSTool.isAvailable() {
            return true
        }
        do {
            _ = try await run(args: GitLFSArguments.versionArgs, env: environmentWithGitLFSPath([:]))
            return true
        } catch GitError.cancelled {
            throw GitError.cancelled
        } catch {
            return false
        }
    }

    /// Detects LFS on a bare `--mirror` clone via `.gitattributes` (`filter=lfs`), then `git lfs ls-files`.
    func repositoryUsesLFS(mirrorPath: String) async throws -> Bool {
        if try await attributesIndicateLFS(mirrorPath: mirrorPath) {
            return true
        }
        guard try await isGitLFSAvailable() else { return false }
        do {
            let (stdout, _) = try await run(
                args: GitLFSArguments.lsFilesArgs,
                env: environmentWithGitLFSPath([:]),
                cwd: mirrorPath
            )
            return stdout.split(whereSeparator: \.isNewline).contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        } catch GitError.cancelled {
            throw GitError.cancelled
        } catch {
            return false
        }
    }

    func lfsFetchAll(mirrorPath: String, env: [String: String] = [:]) async throws {
        _ = try await run(
            args: GitLFSArguments.fetchAllArgs,
            env: environmentWithGitLFSPath(env),
            cwd: mirrorPath
        )
    }

    func lfsPushAll(mirrorPath: String, remoteURL: String, env: [String: String] = [:]) async throws {
        _ = try await run(
            args: GitLFSArguments.pushAllArgs(remoteURL: remoteURL),
            env: environmentWithGitLFSPath(env),
            cwd: mirrorPath
        )
    }

    private func attributesIndicateLFS(mirrorPath: String) async throws -> Bool {
        let treeCandidates = ["HEAD", "refs/heads/main", "refs/heads/master"]
        for treeIsh in treeCandidates {
            let paths: [String]
            do {
                let (stdout, _) = try await run(
                    args: ["ls-tree", "-r", "--name-only", treeIsh],
                    cwd: mirrorPath
                )
                paths = stdout
                    .split(separator: "\n")
                    .map(String.init)
                    .filter(LFSAttributesDetector.isGitAttributesPath)
            } catch GitError.cancelled {
                throw GitError.cancelled
            } catch {
                continue
            }

            for path in paths {
                do {
                    let (content, _) = try await run(
                        args: ["show", "\(treeIsh):\(path)"],
                        cwd: mirrorPath
                    )
                    if LFSAttributesDetector.containsLFSFilter(content) {
                        return true
                    }
                } catch GitError.cancelled {
                    throw GitError.cancelled
                } catch {
                    continue
                }
            }
        }
        return false
    }
}

extension GitRunner: LFSCommandRunning {}
