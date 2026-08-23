import Foundation

nonisolated enum ArchiveError: LocalizedError {
    case toolNotFound(String)
    case invalidOutputDirectory(String)
    case processError(Int32, String)

    var errorDescription: String? {
        switch self {
        case .toolNotFound(let tool):
            return "\(tool) not found in PATH"
        case .invalidOutputDirectory(let path):
            return "Archive directory is not writable: \(path)"
        case .processError(let code, let message):
            return "Archive command exited \(code): \(message)"
        }
    }
}

actor ArchiveRunner {
    private var activeProcess: Process?

    func createArchive(plan: ArchiveCommandPlan) async throws {
        let executable = plan.executableCandidates.first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
        guard let executable else {
            throw ArchiveError.toolNotFound(plan.tool.rawValue)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = plan.arguments
        if let cwd = plan.workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        let stderrPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderrPipe
        activeProcess = process

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { [weak self] proc in
                Task { await self?.clearProcess() }
                let err = String(
                    data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""

                if proc.terminationReason == .uncaughtSignal {
                    continuation.resume(throwing: GitError.cancelled)
                } else if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ArchiveError.processError(proc.terminationStatus, err))
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
}

struct FilesystemArchiveService {
    let archiveRunner: ArchiveRunner
    let fileManager: FileManager

    init(archiveRunner: ArchiveRunner = ArchiveRunner(), fileManager: FileManager = .default) {
        self.archiveRunner = archiveRunner
        self.fileManager = fileManager
    }

    func cancel() async {
        await archiveRunner.cancel()
    }

    func archiveMirror(
        mirrorName: String,
        destination: ArchiveDestination,
        mirrorPath: String,
        log: @Sendable (String) -> Void
    ) async throws -> URL {
        let outputDirectory = destination.directoryPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !outputDirectory.isEmpty else {
            throw ArchiveError.invalidOutputDirectory("(empty)")
        }

        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: outputDirectory, isDirectory: &isDirectory)
        if exists && !isDirectory.boolValue {
            throw ArchiveError.invalidOutputDirectory(outputDirectory)
        }
        if !exists {
            try fileManager.createDirectory(
                atPath: outputDirectory,
                withIntermediateDirectories: true
            )
        }

        let format = destination.format
        let filename = ArchiveFilenameTemplate.render(
            template: destination.filenameTemplate,
            repoName: mirrorName
        )
        guard ArchiveFilenameTemplate.isSafe(filename) else {
            throw ArchiveError.invalidOutputDirectory(outputDirectory)
        }
        let outputURL = URL(fileURLWithPath: outputDirectory, isDirectory: true)
            .appendingPathComponent(filename)

        log("Creating \(format.displayName) archive at \(outputURL.path)...")
        let plan = ArchiveCommandBuilder.plan(
            format: format,
            mirrorPath: mirrorPath,
            outputPath: outputURL.path
        )
        try await archiveRunner.createArchive(plan: plan)
        log("Archive created: \(outputURL.lastPathComponent)")

        if let retentionCount = destination.retentionCount, retentionCount > 0 {
            let prefix = Self.archivePrefix(
                from: destination.filenameTemplate,
                repoName: mirrorName
            )
            let stale = ArchiveRetention.archivesToDelete(
                in: URL(fileURLWithPath: outputDirectory, isDirectory: true),
                matchingPrefix: prefix,
                keepCount: retentionCount,
                fileManager: fileManager
            )
            for url in stale {
                try? fileManager.removeItem(at: url)
                log("Removed old archive: \(url.lastPathComponent)")
            }
        }

        return outputURL
    }

    static func archivePrefix(from template: String, repoName: String) -> String {
        let rendered = ArchiveFilenameTemplate.render(
            template: template,
            repoName: repoName,
            date: Date(timeIntervalSince1970: 0)
        )
        if let dateRange = rendered.range(
            of: #"\d{4}-\d{2}-\d{2}"#,
            options: .regularExpression
        ) {
            return String(rendered[..<dateRange.lowerBound])
        }
        return ArchiveFilenameTemplate.sanitizeFilenameComponent(repoName) + "-"
    }
}
