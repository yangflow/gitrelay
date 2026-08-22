import Foundation
import Network

/// Lightweight loopback HTTP/1.1 listener for `POST /hook/<id>`.
/// Binds `127.0.0.1` on a random ephemeral port. No third-party dependencies.
final class WebhookListener: @unchecked Sendable {
    private let lock = NSLock()
    private var _port: UInt16?
    private var _isRunning = false
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.yangflow.gitrelay.webhook-listener")

    /// Invoked for each fully-parsed HTTP request. Prefer hopping to MainActor inside.
    var onRequest: (@Sendable (WebhookHTTPRequest) async -> WebhookHTTPResponse)?

    var port: UInt16? {
        lock.lock(); defer { lock.unlock() }
        return _port
    }

    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isRunning
    }

    func start() throws {
        stop()

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(integerLiteral: 0)
        )

        let nwListener = try NWListener(using: parameters)
        lock.lock()
        listener = nwListener
        lock.unlock()

        let started = DispatchSemaphore(value: 0)
        var startError: Error?
        var boundPort: UInt16?

        nwListener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                boundPort = nwListener.port?.rawValue
                started.signal()
            case .failed(let error):
                startError = error
                started.signal()
            case .cancelled:
                break
            default:
                break
            }
        }

        nwListener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }

        nwListener.start(queue: queue)
        _ = started.wait(timeout: .now() + 3)

        if let startError {
            stop()
            throw startError
        }
        guard let boundPort else {
            stop()
            throw WebhookListenerError.bindFailed
        }

        lock.lock()
        _port = boundPort
        _isRunning = true
        lock.unlock()
    }

    func stop() {
        lock.lock()
        let current = listener
        listener = nil
        _isRunning = false
        _port = nil
        lock.unlock()
        current?.cancel()
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            if error != nil {
                connection.cancel()
                return
            }

            var next = buffer
            if let data, !data.isEmpty {
                next.append(data)
            }

            if let request = WebhookHTTPParser.parse(next) {
                let handler = self.onRequest
                Task {
                    let response: WebhookHTTPResponse
                    if let handler {
                        response = await handler(request)
                    } else {
                        response = .plain(500, "Internal Server Error", message: "no handler\n")
                    }
                    self.queue.async {
                        self.send(response: response, on: connection)
                    }
                }
                return
            }

            if isComplete {
                connection.cancel()
                return
            }

            if next.count > 1_048_576 {
                connection.cancel()
                return
            }
            self.receive(on: connection, buffer: next)
        }
    }

    private func send(response: WebhookHTTPResponse, on connection: NWConnection) {
        let payload = response.serialize()
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

enum WebhookListenerError: LocalizedError {
    case bindFailed

    var errorDescription: String? {
        switch self {
        case .bindFailed:
            return String.loc("Unable to bind the webhook listener port on 127.0.0.1")
        }
    }
}
