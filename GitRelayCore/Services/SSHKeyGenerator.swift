import Foundation

enum SSHKeyGeneratorError: LocalizedError, Equatable {
    case sshKeygenNotFound
    case emptyKeyPath
    case keyAlreadyExists(path: String)
    case processFailed(status: Int32, message: String)
    case publicKeyMissing(path: String)

    var errorDescription: String? {
        switch self {
        case .sshKeygenNotFound:
            String(localized: "ssh-keygen was not found. Make sure the macOS Command Line Tools are installed.")
        case .emptyKeyPath:
            String(localized: "Specify a path for the private key.")
        case .keyAlreadyExists(let path):
            String(localized: "A key file already exists at: \(path)")
        case .processFailed(_, let message):
            message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? String(localized: "ssh-keygen failed.")
                : message.trimmingCharacters(in: .whitespacesAndNewlines)
        case .publicKeyMissing(let path):
            String(localized: "Public key file not found: \(path)")
        }
    }
}

struct SSHKeyGenerationResult: Equatable, Sendable {
    let privateKeyPath: String
    let publicKeyPath: String
    let publicKey: String
}

enum SSHKeyGenerator {
    static let defaultKeyFileName = "gitrelay_ed25519"
    static let defaultRelativePath = ".ssh/\(defaultKeyFileName)"
    static let defaultDisplayPath = "~/\(defaultRelativePath)"
    static let privateKeyPermissions: UInt16 = 0o600
    static let publicKeyPermissions: UInt16 = 0o644
    static let keyComment = "gitrelay"

    private static let sshKeygenCandidates = [
        "/usr/bin/ssh-keygen",
        "/usr/local/bin/ssh-keygen",
        "/opt/homebrew/bin/ssh-keygen",
    ]

    static func defaultPrivateKeyPath(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        homeDirectory.appendingPathComponent(defaultRelativePath).path
    }

    static func expandPath(
        _ path: String,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        if trimmed == "~" {
            return homeDirectory.path
        }
        if trimmed.hasPrefix("~/") {
            return homeDirectory.appendingPathComponent(String(trimmed.dropFirst(2))).path
        }
        return trimmed
    }

    static func publicKeyPath(forPrivateKeyPath privateKeyPath: String) -> String {
        privateKeyPath + ".pub"
    }

    static func makeSSHKeygenArguments(
        privateKeyPath: String,
        passphrase: String?,
        comment: String = keyComment
    ) -> [String] {
        var args = [
            "-t", "ed25519",
            "-f", privateKeyPath,
            "-C", comment,
            "-q",
        ]
        args.append(contentsOf: ["-N", passphrase ?? ""])
        return args
    }

    static func resolveSSHKeygenPath(
        fileManager: FileManager = .default
    ) -> String? {
        sshKeygenCandidates.first { fileManager.isExecutableFile(atPath: $0) }
    }

    static func readPublicKey(
        privateKeyPath: String,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) throws -> String {
        let expandedPrivatePath = expandPath(privateKeyPath, homeDirectory: homeDirectory)
        let publicPath = publicKeyPath(forPrivateKeyPath: expandedPrivatePath)
        guard fileManager.fileExists(atPath: publicPath) else {
            throw SSHKeyGeneratorError.publicKeyMissing(path: publicPath)
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: publicPath))
        guard let contents = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !contents.isEmpty else {
            throw SSHKeyGeneratorError.publicKeyMissing(path: publicPath)
        }
        return contents
    }

    static func generate(
        privateKeyPath: String,
        passphrase: String? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        sshKeygenPath: String? = nil,
        runProcess: ((String, [String]) throws -> Void)? = nil
    ) throws -> SSHKeyGenerationResult {
        let trimmedPath = privateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw SSHKeyGeneratorError.emptyKeyPath
        }

        let expandedPrivatePath = expandPath(trimmedPath, homeDirectory: homeDirectory)
        let expandedPublicPath = publicKeyPath(forPrivateKeyPath: expandedPrivatePath)

        if fileManager.fileExists(atPath: expandedPrivatePath)
            || fileManager.fileExists(atPath: expandedPublicPath) {
            throw SSHKeyGeneratorError.keyAlreadyExists(path: expandedPrivatePath)
        }

        let sshDirectory = URL(fileURLWithPath: expandedPrivatePath).deletingLastPathComponent()
        try fileManager.createDirectory(at: sshDirectory, withIntermediateDirectories: true)

        let resolvedSSHKeygenPath = sshKeygenPath ?? resolveSSHKeygenPath(fileManager: fileManager)
        guard let resolvedSSHKeygenPath else {
            throw SSHKeyGeneratorError.sshKeygenNotFound
        }

        let arguments = makeSSHKeygenArguments(
            privateKeyPath: expandedPrivatePath,
            passphrase: passphrase
        )

        if let runProcess {
            try runProcess(resolvedSSHKeygenPath, arguments)
        } else {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: resolvedSSHKeygenPath)
            process.arguments = arguments

            let stderrPipe = Pipe()
            process.standardOutput = FileHandle.nullDevice
            process.standardError = stderrPipe

            try process.run()
            process.waitUntilExit()

            let stderr = String(
                data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""

            guard process.terminationStatus == 0 else {
                throw SSHKeyGeneratorError.processFailed(
                    status: process.terminationStatus,
                    message: stderr
                )
            }
        }

        guard fileManager.fileExists(atPath: expandedPublicPath) else {
            throw SSHKeyGeneratorError.publicKeyMissing(path: expandedPublicPath)
        }

        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: privateKeyPermissions)],
            ofItemAtPath: expandedPrivatePath
        )
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: publicKeyPermissions)],
            ofItemAtPath: expandedPublicPath
        )

        let publicKey = try readPublicKey(
            privateKeyPath: expandedPrivatePath,
            homeDirectory: homeDirectory,
            fileManager: fileManager
        )

        return SSHKeyGenerationResult(
            privateKeyPath: expandedPrivatePath,
            publicKeyPath: expandedPublicPath,
            publicKey: publicKey
        )
    }
}
