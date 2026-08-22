import Foundation

/// Builds and sends a signed local webhook ping for Settings → Send Test.
/// Secrets are used only to sign the request and are never logged or copied.
nonisolated enum WebhookLocalTestClient {
    static let pingBody = Data("{}".utf8)

    struct OutboundRequest: Equatable, Sendable {
        let url: URL
        let path: String
        let method: String
        let signatureHeader: String
        let body: Data
    }

    enum Error: Swift.Error, Equatable {
        case invalidURL
        case nonHTTPResponse
    }

    static func makePingRequest(
        port: UInt16,
        pathID: String,
        secret: String,
        body: Data = pingBody
    ) -> OutboundRequest? {
        let path = WebhookURLTemplate.hookPath(pathID: pathID)
        guard let url = URL(string: "http://127.0.0.1:\(port)\(path)") else { return nil }
        let signature = WebhookHMACVerifier.githubSignatureHeader(payload: body, secret: secret)
        return OutboundRequest(
            url: url,
            path: path,
            method: "POST",
            signatureHeader: signature,
            body: body
        )
    }

    /// Debug/logging representation that never includes the HMAC secret.
    static func redactedDescription(for request: OutboundRequest) -> String {
        "\(request.method) \(request.path) signature=\(request.signatureHeader)"
    }

    static func send(
        request: OutboundRequest,
        session: URLSession = .shared
    ) async throws -> Int {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        urlRequest.setValue(request.signatureHeader, forHTTPHeaderField: "X-Hub-Signature-256")
        urlRequest.setValue("ping", forHTTPHeaderField: "X-GitHub-Event")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw Error.nonHTTPResponse
        }
        return http.statusCode
    }
}
