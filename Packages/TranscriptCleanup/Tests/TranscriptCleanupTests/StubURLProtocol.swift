import Foundation
import Synchronization

// MARK: - StubURLProtocol

/// A stand-in endpoint. Each test installs its own handler on its own session configuration, so
/// the class-wide registry never has to be shared between concurrent tests.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
  // MARK: Internal

  enum Reply {
    case response(status: Int, body: String)
    case failure(URLError.Code)
    /// Answers nothing until the request is cancelled — the shape of a slow endpoint.
    case hang
  }

  override class func canInit(with _: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    guard let identifier = request.value(forHTTPHeaderField: "X-Stub-Identifier")
      .flatMap({ UUID(uuidString: $0) }),
      let stub = Self.registry.withLock({ $0[identifier] })
    else {
      client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
      return
    }
    stub.log.record(request, body: Self.body(of: request))

    switch stub.reply {
    case let .response(status, body):
      let response = HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil,
      )!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: Data(body.utf8))
      client?.urlProtocolDidFinishLoading(self)
    case let .failure(code):
      client?.urlProtocol(self, didFailWithError: URLError(code))
    case .hang:
      break
    }
  }

  override func stopLoading() {}

  /// A session whose only reachable endpoint is `reply`. `observedRequests` collects what the
  /// client actually put on the wire, body included.
  static func session(
    reply: Reply, observedRequests: RequestLog = RequestLog(),
  ) -> (session: URLSession, log: RequestLog) {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let identifier = UUID()
    configuration.httpAdditionalHeaders = ["X-Stub-Identifier": identifier.uuidString]
    registry.withLock { $0[identifier] = Stub(reply: reply, log: observedRequests) }
    return (URLSession(configuration: configuration), observedRequests)
  }

  // MARK: Private

  private struct Stub {
    let reply: Reply
    let log: RequestLog
  }

  private static let registry = Mutex<[UUID: Stub]>([:])

  /// `URLProtocol` hands over a request whose `httpBody` was replaced by a stream.
  private static func body(of request: URLRequest) -> Data {
    if let body = request.httpBody {
      return body
    }
    guard let stream = request.httpBodyStream else {
      return Data()
    }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
      let read = stream.read(&buffer, maxLength: buffer.count)
      guard read > 0 else {
        break
      }
      data.append(contentsOf: buffer[0 ..< read])
    }
    return data
  }
}

// MARK: - RequestLog

final class RequestLog: Sendable {
  // MARK: Internal

  struct Entry {
    let url: URL
    let method: String
    let headers: [String: String]
    let body: Data

    var messages: [(role: String, content: String)] {
      guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let messages = json["messages"] as? [[String: Any]]
      else {
        return []
      }
      return messages.compactMap { message in
        guard let role = message["role"] as? String, let content = message["content"] as? String
        else {
          return nil
        }
        return (role, content)
      }
    }
  }

  var entries: [Entry] {
    storage.withLock { $0 }
  }

  func record(_ request: URLRequest, body: Data) {
    let entry = Entry(
      url: request.url!, method: request.httpMethod ?? "",
      headers: request.allHTTPHeaderFields ?? [:], body: body,
    )
    storage.withLock { $0.append(entry) }
  }

  // MARK: Private

  private let storage = Mutex<[Entry]>([])
}
