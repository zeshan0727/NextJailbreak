import Foundation
import Network
import Darwin

/// Local-only HTTP range server.
/// Chromecast fetches video bytes from the iPhone's LAN address.
/// Nothing is uploaded to any cloud or remote host.
final class LocalMediaServer {
    typealias Completion = (Result<URL, Error>) -> Void
    private struct Entry {
        let url: URL
        let mimeType: String
    }
    private struct Waiting {
        let id: UUID
        let callback: Completion
    }
    private let queue = DispatchQueue(label: "uk.zeshanbarvi.nextcast.http", qos: .userInitiated)
    private var entries: [UUID: Entry] = [:]
    private var waiting: [Waiting] = []
    private var listener: NWListener?
    private var currentPort: UInt16?

    func makeURL(for movie: Movie, completion: @escaping Completion) {
        queue.async {
            self.entries[movie.id] = Entry(url: movie.localURL, mimeType: movie.mimeType)
            if let port = self.currentPort {
                self.deliver(movie.id, port: port, completion: completion)
                return
            }
            self.waiting.append(Waiting(id: movie.id, callback: completion))
            guard self.listener == nil else { return }
            do {
                let listener = try NWListener(using: .tcp, on: .any)
                self.listener = listener
                listener.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        if let port = listener.port?.rawValue {
                            self.currentPort = port
                            let callbacks = self.waiting
                            self.waiting.removeAll()
                            for waiting in callbacks {
                                self.deliver(waiting.id, port: port, completion: waiting.callback)
                            }
                        }
                    case .failed(let error):
                        self.failWaiting(error)
                        listener.cancel()
                        self.listener = nil
                        self.currentPort = nil
                    default:
                        break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    guard let self else { connection.cancel(); return }
                    self.handle(connection)
                }
                listener.start(queue: self.queue)
            } catch {
                self.failWaiting(error)
            }
        }
    }

    func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
            self.currentPort = nil
            self.entries.removeAll()
            self.failWaiting(NSError(domain: "NextCast", code: -1,
                                     userInfo: [NSLocalizedDescriptionKey: "Local streaming ended"]))
        }
    }

    private func failWaiting(_ error: Error) {
        let callbacks = waiting
        waiting.removeAll()
        for item in callbacks {
            DispatchQueue.main.async { item.callback(.failure(error)) }
        }
    }

    private func deliver(_ id: UUID, port: UInt16, completion: @escaping Completion) {
        guard let ip = Self.wifiIPv4() else {
            let error = NSError(domain: "NextCast", code: -2,
                userInfo: [NSLocalizedDescriptionKey: "No Wi-Fi address found. Connect both devices to the same Wi-Fi."])
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }
        let url = URL(string: "http://\(ip):\(port)/media/\(id.uuidString)")!
        DispatchQueue.main.async { completion(.success(url)) }
    }

    private static func wifiIPv4() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let head = list else { return nil }
        defer { freeifaddrs(list) }
        for item in sequence(first: head, next: { $0.pointee.ifa_next }) {
            let address = item.pointee.ifa_addr
            guard let address, address.pointee.sa_family == sa_family_t(AF_INET),
                  String(cString: item.pointee.ifa_name) == "en0" else { continue }
            var addr = UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            let result = buffer.withUnsafeMutableBufferPointer { ptr in
                inet_ntop(AF_INET, &addr, ptr.baseAddress, socklen_t(INET_ADDRSTRLEN))
            }
            if result != nil { return String(cString: buffer) }
        }
        return nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHeaders(connection, accumulated: Data())
    }

    private func receiveHeaders(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) {
            [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            if error != nil || isComplete { connection.cancel(); return }
            var collected = accumulated
            if let data { collected.append(data) }
            guard collected.count <= 32768 else {
                self.sendSimple(connection, code: 431, reason: "Request Header Fields Too Large")
                return
            }
            if collected.range(of: Data("\r\n\r\n".utf8)) != nil {
                self.respond(to: collected, connection: connection)
            } else {
                self.receiveHeaders(connection, accumulated: collected)
            }
        }
    }

    private func respond(to headerData: Data, connection: NWConnection) {
        guard let header = String(data: headerData, encoding: .utf8) else {
            sendSimple(connection, code: 400, reason: "Bad Request")
            return
        }
        let lines = header.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ")
        guard parts.count >= 2 else {
            sendSimple(connection, code: 400, reason: "Bad Request")
            return
        }
        let method = String(parts[0]).uppercased()
        if method == "OPTIONS" {
            sendSimple(connection, code: 204, reason: "No Content")
            return
        }
        guard method == "GET" || method == "HEAD" else {
            sendSimple(connection, code: 405, reason: "Method Not Allowed")
            return
        }
        let uri = String(parts[1]).components(separatedBy: "?")[0]
        let pathParts = uri.split(separator: "/")
        guard pathParts.count == 2, pathParts[0] == "media",
              let id = UUID(uuidString: String(pathParts[1])),
              let entry = entries[id] else {
            sendSimple(connection, code: 404, reason: "Not Found")
            return
        }
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: entry.url.path)
            let length = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            guard length > 0 else {
                sendSimple(connection, code: 404, reason: "Empty File")
                return
            }
            var start: Int64 = 0
            var end = length - 1
            var partial = false
            if let rangeLine = lines.first(where: { $0.lowercased().hasPrefix("range:") }) {
                let field = rangeLine.dropFirst("range:".count)
                    .trimmingCharacters(in: .whitespaces)
                guard field.lowercased().hasPrefix("bytes=") else {
                    sendRangeInvalid(connection, length: length)
                    return
                }
                let spec = String(field.dropFirst(6))
                let bounds = spec.split(separator: "-", omittingEmptySubsequences: false)
                guard bounds.count == 2 else {
                    sendRangeInvalid(connection, length: length)
                    return
                }
                if bounds[0].isEmpty {
                    guard let suffix = Int64(bounds[1]), suffix > 0 else {
                        sendRangeInvalid(connection, length: length); return
                    }
                    start = max(0, length - suffix)
                } else {
                    guard let first = Int64(bounds[0]), first >= 0 else {
                        sendRangeInvalid(connection, length: length); return
                    }
                    start = first
                    if !bounds[1].isEmpty {
                        guard let last = Int64(bounds[1]) else {
                            sendRangeInvalid(connection, length: length); return
                        }
                        end = min(last, length - 1)
                    }
                }
                guard start < length, end >= start else {
                    sendRangeInvalid(connection, length: length); return
                }
                partial = true
            }
            let size = end - start + 1
            let status = partial ? "206 Partial Content" : "200 OK"
            var headers = "HTTP/1.1 \(status)\r\n"
            headers += "Content-Type: \(entry.mimeType)\r\n"
            headers += "Content-Length: \(size)\r\n"
            headers += "Accept-Ranges: bytes\r\n"
            headers += "Access-Control-Allow-Origin: *\r\n"
            headers += "Access-Control-Allow-Headers: Range, Content-Type, Accept-Encoding\r\n"
            headers += "Access-Control-Expose-Headers: Content-Length, Content-Range, Accept-Ranges\r\n"
            headers += "Connection: close\r\n"
            if partial { headers += "Content-Range: bytes \(start)-\(end)/\(length)\r\n" }
            headers += "\r\n"

            if method == "HEAD" {
                connection.send(content: Data(headers.utf8), isComplete: true,
                                completion: .contentProcessed { _ in connection.cancel() })
                return
            }
            let file = try FileHandle(forReadingFrom: entry.url)
            try file.seek(toOffset: UInt64(start))
            connection.send(content: Data(headers.utf8),
                            completion: .contentProcessed { [weak self] error in
                guard let self, error == nil else {
                    try? file.close()
                    connection.cancel()
                    return
                }
                self.sendChunks(file: file, remaining: size, connection: connection)
            })
        } catch {
            sendSimple(connection, code: 500, reason: "Internal Server Error")
        }
    }

    private func sendChunks(file: FileHandle, remaining: Int64, connection: NWConnection) {
        guard remaining > 0 else {
            try? file.close()
            connection.send(content: nil, isComplete: true,
                            completion: .contentProcessed { _ in connection.cancel() })
            return
        }
        do {
            let block = try file.read(upToCount: Int(min(remaining, 128 * 1024))) ?? Data()
            guard !block.isEmpty else {
                try? file.close()
                connection.cancel()
                return
            }
            connection.send(content: block, completion: .contentProcessed { [weak self] error in
                guard let self, error == nil else {
                    try? file.close()
                    connection.cancel()
                    return
                }
                self.sendChunks(file: file, remaining: remaining - Int64(block.count),
                                connection: connection)
            })
        } catch {
            try? file.close()
            connection.cancel()
        }
    }

    private func sendRangeInvalid(_ connection: NWConnection, length: Int64) {
        let header = "HTTP/1.1 416 Range Not Satisfiable\r\n" +
            "Content-Range: bytes */\(length)\r\n" +
            "Access-Control-Allow-Origin: *\r\n" +
            "Content-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8), isComplete: true,
                        completion: .contentProcessed { _ in connection.cancel() })
    }

    private func sendSimple(_ connection: NWConnection, code: Int, reason: String) {
        let header = "HTTP/1.1 \(code) \(reason)\r\n" +
            "Access-Control-Allow-Origin: *\r\n" +
            "Access-Control-Allow-Methods: GET, HEAD, OPTIONS\r\n" +
            "Access-Control-Allow-Headers: Range, Content-Type, Accept-Encoding\r\n" +
            "Content-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8), isComplete: true,
                        completion: .contentProcessed { _ in connection.cancel() })
    }
}
