import Foundation

nonisolated struct WebhookHTTPRequest: Equatable, Sendable {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data

    func header(_ name: String) -> String? {
        let target = name.lowercased()
        return headers.first { $0.key.lowercased() == target }?.value
    }
}

nonisolated struct WebhookHTTPResponse: Equatable, Sendable {
    var statusCode: Int
    var reason: String
    var headers: [String: String]
    var body: Data

    static func plain(_ statusCode: Int, _ reason: String, message: String) -> WebhookHTTPResponse {
        let body = Data(message.utf8)
        return WebhookHTTPResponse(
            statusCode: statusCode,
            reason: reason,
            headers: [
                "Content-Type": "text/plain; charset=utf-8",
                "Content-Length": String(body.count),
                "Connection": "close"
            ],
            body: body
        )
    }

    func serialize() -> Data {
        var header = "HTTP/1.1 \(statusCode) \(reason)\r\n"
        for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
            header += "\(key): \(value)\r\n"
        }
        header += "\r\n"
        var data = Data(header.utf8)
        data.append(body)
        return data
    }
}

nonisolated enum WebhookRoute: Equatable, Sendable {
    case hook(id: String)
    case health
    case notFound

    static func parse(method: String, path: String) -> WebhookRoute {
        let normalizedMethod = method.uppercased()
        let pathOnly = path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
        let trimmed = pathOnly.hasSuffix("/") && pathOnly.count > 1
            ? String(pathOnly.dropLast())
            : pathOnly

        if trimmed == "/health" || trimmed == "/healthz" {
            return .health
        }

        let prefix = "/hook/"
        guard trimmed.hasPrefix(prefix) else { return .notFound }
        let id = String(trimmed.dropFirst(prefix.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !id.isEmpty, !id.contains("/") else { return .notFound }
        // Method is checked by the handler; route identity is path-based.
        _ = normalizedMethod
        return .hook(id: id)
    }
}

nonisolated enum WebhookHTTPParser {
    /// Parses a single HTTP/1.1 request from raw bytes. Returns nil if incomplete or malformed.
    static func parse(_ raw: Data) -> WebhookHTTPRequest? {
        guard let headerEnd = findHeaderTerminator(in: raw) else { return nil }
        let headerData = raw.subdata(in: 0..<headerEnd)
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }

        let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let path = String(parts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let bodyStart = headerEnd + 4
        let contentLength = headers.first { $0.key.lowercased() == "content-length" }
            .flatMap { Int($0.value) } ?? 0
        guard contentLength >= 0 else { return nil }
        guard raw.count >= bodyStart + contentLength else { return nil }
        let body = contentLength == 0
            ? Data()
            : raw.subdata(in: bodyStart..<(bodyStart + contentLength))

        return WebhookHTTPRequest(method: method, path: path, headers: headers, body: body)
    }

    private static func findHeaderTerminator(in data: Data) -> Int? {
        let pattern: [UInt8] = [0x0D, 0x0A, 0x0D, 0x0A]
        guard data.count >= pattern.count else { return nil }
        for index in 0...(data.count - pattern.count) {
            if Array(data[index..<(index + pattern.count)]) == pattern {
                return index
            }
        }
        return nil
    }
}
