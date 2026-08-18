import Darwin
import Foundation

// MARK: - MockEndpoint

/// A real socket on localhost speaking just enough HTTP to be an OpenAI-compatible gateway, so the
/// smoke exercises URLSession itself rather than a protocol stub. `/slow` never answers, which is
/// what a skip has to survive.
final class MockEndpoint: @unchecked Sendable {
  // MARK: Lifecycle

  private init(descriptor: Int32, port: UInt16) {
    self.descriptor = descriptor
    self.port = port
  }

  // MARK: Internal

  /// Deliberately wrapped in the debris a real model produces, so the printed outcome shows
  /// shaping doing its job.
  static let wrappedReply = """
  <think>The speaker dictated a shell command.</think>
  Cleaned transcript:
  ```
  Run swift test --filter cleanup, then report back.
  ```
  """

  var baseURL: URL {
    URL(string: "http://127.0.0.1:\(port)/v1")!
  }

  var slowBaseURL: URL {
    URL(string: "http://127.0.0.1:\(port)/slow/v1")!
  }

  static func start() -> MockEndpoint {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    precondition(descriptor >= 0, "socket() failed: \(errno)")
    var reuse: Int32 = 1
    setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = 0
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    let bound = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    precondition(bound == 0, "bind() failed: \(errno)")
    precondition(listen(descriptor, 8) == 0, "listen() failed: \(errno)")

    var assigned = sockaddr_in()
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let named = withUnsafeMutablePointer(to: &assigned) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
    }
    precondition(named == 0, "getsockname() failed: \(errno)")

    let endpoint = MockEndpoint(descriptor: descriptor, port: assigned.sin_port.bigEndian)
    Thread.detachNewThread { endpoint.acceptLoop() }
    return endpoint
  }

  func stop() {
    close(descriptor)
  }

  // MARK: Private

  private static var completionBody: Data {
    let payload = ["choices": [["message": ["role": "assistant", "content": wrappedReply]]]]
    return try! JSONSerialization.data(withJSONObject: payload)
  }

  private static var modelsBody: Data {
    let payload = ["data": [["id": "mock-small"], ["id": "mock-large"]]]
    return try! JSONSerialization.data(withJSONObject: payload)
  }

  private let descriptor: Int32
  private let port: UInt16

  private static func response(body: Data) -> Data {
    let head = """
    HTTP/1.1 200 OK\r
    Content-Type: application/json\r
    Content-Length: \(body.count)\r
    Connection: close\r
    \r

    """
    return Data(head.utf8) + body
  }

  private func acceptLoop() {
    while true {
      let connection = accept(descriptor, nil, nil)
      guard connection >= 0 else {
        return
      }
      // Each connection gets its own thread so a hung request never blocks the next one.
      Thread.detachNewThread { self.serve(connection) }
    }
  }

  private func serve(_ connection: Int32) {
    var buffer = Data()
    var chunk = [UInt8](repeating: 0, count: 4096)
    while true {
      let read = recv(connection, &chunk, chunk.count, 0)
      guard read > 0 else {
        close(connection)
        return
      }
      buffer.append(contentsOf: chunk[0 ..< read])
      guard let request = HTTPRequestHead(buffer) else {
        continue
      }
      guard !request.path.hasPrefix("/slow") else {
        // The endpoint that is still thinking when the user gives up on it.
        Thread.sleep(forTimeInterval: 30)
        close(connection)
        return
      }
      let body = request.path.hasSuffix("/models") ? Self.modelsBody : Self.completionBody
      let response = Self.response(body: body)
      response.withUnsafeBytes { _ = send(connection, $0.baseAddress, response.count, 0) }
      close(connection)
      return
    }
  }
}

// MARK: - HTTPRequestHead

/// Present only once the head and its declared body have arrived.
private struct HTTPRequestHead {
  // MARK: Lifecycle

  init?(_ buffer: Data) {
    guard let separator = buffer.range(of: Data("\r\n\r\n".utf8)),
          let head = String(data: buffer[..<separator.lowerBound], encoding: .utf8)
    else {
      return nil
    }
    let lines = head.components(separatedBy: "\r\n")
    let requestLine = lines[0].split(separator: " ")
    guard requestLine.count >= 2 else {
      return nil
    }
    let contentLength = lines.lazy
      .first { $0.lowercased().hasPrefix("content-length:") }
      .flatMap { Int($0.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) } ?? 0
    guard buffer.count - separator.upperBound >= contentLength else {
      return nil
    }
    path = String(requestLine[1])
  }

  // MARK: Internal

  let path: String
}
