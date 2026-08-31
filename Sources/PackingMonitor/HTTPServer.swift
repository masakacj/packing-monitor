import Foundation
import Network

struct HTTPRequest {
    let method: String
    let path: String
}

struct HTTPResponse {
    let statusCode: Int
    let contentType: String
    let body: Data

    static func text(_ text: String, statusCode: Int = 200, contentType: String = "text/plain; charset=utf-8") -> HTTPResponse {
        return HTTPResponse(
            statusCode: statusCode,
            contentType: contentType,
            body: text.data(using: .utf8) ?? Data()
        )
    }

    static func data(_ data: Data, statusCode: Int = 200, contentType: String) -> HTTPResponse {
        return HTTPResponse(statusCode: statusCode, contentType: contentType, body: data)
    }

    static func json<T: Encodable>(_ value: T, statusCode: Int = 200) -> HTTPResponse {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            return HTTPResponse(
                statusCode: statusCode,
                contentType: "application/json; charset=utf-8",
                body: try encoder.encode(value)
            )
        } catch {
            let message = "{\"error\":\"json_encoding_failed\"}"
            return HTTPResponse.text(message, statusCode: 500, contentType: "application/json; charset=utf-8")
        }
    }

    static func empty(statusCode: Int) -> HTTPResponse {
        return HTTPResponse(statusCode: statusCode, contentType: "text/plain; charset=utf-8", body: Data())
    }
}

final class HTTPServer {
    typealias Handler = (HTTPRequest, @escaping (HTTPResponse) -> Void) -> Void

    private let listener: NWListener
    private let queue = DispatchQueue(label: "packing-monitor.http")
    private let handler: Handler

    init(host: String, port: Int, handler: @escaping Handler) throws {
        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw HTTPServerError.invalidPort
        }

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(host), port: endpointPort)
        self.listener = try NWListener(using: parameters)
        self.handler = handler
    }

    func start() {
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                break
            case .failed(let error):
                fputs("HTTP listener failed: \(error)\n", stderr)
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, accumulated: Data())
    }

    private func receiveRequest(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 32 * 1024) { [weak self] data, _, isComplete, error in
            guard let self = self else {
                connection.cancel()
                return
            }

            var buffer = accumulated
            if let data = data {
                buffer.append(data)
            }

            if self.hasCompleteHeaders(buffer) {
                self.process(buffer, on: connection)
                return
            }

            if isComplete || error != nil || buffer.count >= 64 * 1024 {
                self.send(.text("Bad Request", statusCode: 400), on: connection)
                return
            }

            self.receiveRequest(on: connection, accumulated: buffer)
        }
    }

    private func hasCompleteHeaders(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else { return false }
        return text.range(of: "\r\n\r\n") != nil
    }

    private func process(_ data: Data, on connection: NWConnection) {
        guard
            let text = String(data: data, encoding: .utf8),
            let firstLine = text.components(separatedBy: "\r\n").first
        else {
            send(.text("Bad Request", statusCode: 400), on: connection)
            return
        }

        let parts = firstLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else {
            send(.text("Bad Request", statusCode: 400), on: connection)
            return
        }

        let method = String(parts[0]).uppercased()
        let rawPath = String(parts[1])
        let path = rawPath.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? rawPath
        let request = HTTPRequest(method: method, path: path)

        handler(request) { [weak self, weak connection] response in
            guard let self = self, let connection = connection else { return }
            self.queue.async {
                self.send(response, on: connection)
            }
        }
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        let reason = reasonPhrase(for: response.statusCode)
        let header = "HTTP/1.1 \(response.statusCode) \(reason)\r\n" +
            "Content-Type: \(response.contentType)\r\n" +
            "Content-Length: \(response.body.count)\r\n" +
            "Cache-Control: no-store\r\n" +
            "Connection: close\r\n\r\n"

        var payload = header.data(using: .utf8) ?? Data()
        payload.append(response.body)

        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func reasonPhrase(for statusCode: Int) -> String {
        switch statusCode {
        case 200: return "OK"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 500: return "Internal Server Error"
        default: return "OK"
        }
    }
}

enum HTTPServerError: Error {
    case invalidPort
}
