import Foundation
import os

/// Accumulates stderr while optionally emitting `\r`/`\n`-delimited progress lines.
///
/// Process `readabilityHandler` / `terminationHandler` call ``append`` / ``finish``
/// synchronously off the main actor. Storage is locked; this type must not be an actor.
struct GitStderrStream: Sendable {
    private struct State: Sendable {
        var accumulated = Data()
        var pending = Data()
    }

    private let lock: OSAllocatedUnfairLock<State>
    private let onProgressLine: (@Sendable (String) -> Void)?

    nonisolated init(onProgressLine: (@Sendable (String) -> Void)?) {
        self.lock = OSAllocatedUnfairLock(initialState: State())
        self.onProgressLine = onProgressLine
    }

    nonisolated func append(_ chunk: Data) {
        let callback = onProgressLine
        var linesToEmit: [String] = []

        lock.withLock { state in
            state.accumulated.append(chunk)
            guard callback != nil else { return }

            state.pending.append(chunk)
            while let separator = state.pending.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
                let lineData = state.pending.subdata(in: state.pending.startIndex..<separator)
                let separatorByte = state.pending[separator]
                let afterSeparator = state.pending.index(after: separator)
                // Treat `\r\n` as one separator.
                if separatorByte == 0x0D,
                   afterSeparator < state.pending.endIndex,
                   state.pending[afterSeparator] == 0x0A {
                    state.pending.removeSubrange(state.pending.startIndex...afterSeparator)
                } else {
                    state.pending.removeSubrange(state.pending.startIndex...separator)
                }
                if let line = decodedProgressLine(lineData) {
                    linesToEmit.append(line)
                }
            }
        }

        for line in linesToEmit {
            callback?(line)
        }
    }

    nonisolated func finish() -> String {
        let callback = onProgressLine
        var trailingLine: String?
        let accumulated: Data = lock.withLock { state in
            if !state.pending.isEmpty {
                trailingLine = decodedProgressLine(state.pending)
                state.pending.removeAll(keepingCapacity: false)
            }
            return state.accumulated
        }
        if let trailingLine {
            callback?(trailingLine)
        }
        return String(data: accumulated, encoding: .utf8) ?? ""
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
