import Foundation

/// Accumulates stderr while optionally emitting `\r`/`\n`-delimited progress lines.
///
/// Process `readabilityHandler` / `terminationHandler` call ``append`` / ``finish``
/// synchronously off the main actor. Storage is locked; this type must not be an actor.
struct GitStderrStream: Sendable {
    private let storage: GitStderrStreamStorage

    nonisolated init(onProgressLine: (@Sendable (String) -> Void)?) {
        self.storage = GitStderrStreamStorage(onProgressLine: onProgressLine)
    }

    nonisolated func append(_ chunk: Data) {
        let callback = storage.onProgressLine
        let linesToEmit = storage.takeAppendedLines(chunk)
        for line in linesToEmit {
            callback?(line)
        }
    }

    nonisolated func finish() -> String {
        let callback = storage.onProgressLine
        let result = storage.finalize()
        if let trailingLine = result.trailingLine {
            callback?(trailingLine)
        }
        return String(data: result.accumulated, encoding: .utf8) ?? ""
    }
}

/// Lock-protected mutable buffers. `NSLock` is created in ``nonisolated`` init (not a MainActor default).
private nonisolated final class GitStderrStreamStorage: @unchecked Sendable {
    private nonisolated(unsafe) let lock: NSLock
    private nonisolated(unsafe) var accumulated: Data
    private nonisolated(unsafe) var pending: Data
    let onProgressLine: (@Sendable (String) -> Void)?

    nonisolated init(onProgressLine: (@Sendable (String) -> Void)?) {
        self.lock = NSLock()
        self.accumulated = Data()
        self.pending = Data()
        self.onProgressLine = onProgressLine
    }

    nonisolated func takeAppendedLines(_ chunk: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }

        accumulated.append(chunk)
        guard onProgressLine != nil else { return [] }

        pending.append(chunk)
        var lines: [String] = []
        while let separator = pending.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let lineData = pending.subdata(in: pending.startIndex..<separator)
            let separatorByte = pending[separator]
            let afterSeparator = pending.index(after: separator)
            // Treat `\r\n` as one separator.
            if separatorByte == 0x0D,
               afterSeparator < pending.endIndex,
               pending[afterSeparator] == 0x0A {
                pending.removeSubrange(pending.startIndex...afterSeparator)
            } else {
                pending.removeSubrange(pending.startIndex...separator)
            }
            if let line = decodedProgressLine(lineData) {
                lines.append(line)
            }
        }
        return lines
    }

    nonisolated func finalize() -> (accumulated: Data, trailingLine: String?) {
        lock.lock()
        defer { lock.unlock() }

        var trailingLine: String?
        if !pending.isEmpty {
            trailingLine = decodedProgressLine(pending)
            pending.removeAll(keepingCapacity: false)
        }
        return (accumulated, trailingLine)
    }
}

nonisolated private func decodedProgressLine(_ data: Data) -> String? {
    guard let line = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
          !line.isEmpty
    else {
        return nil
    }
    return line
}
