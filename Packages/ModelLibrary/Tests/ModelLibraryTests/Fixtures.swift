import CryptoKit
import Foundation
@testable import ModelLibrary

// MARK: - LibraryFixture

enum LibraryFixture {
  static func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory.appending(
      path: "\(UUID().uuidString)/pinned-v1", directoryHint: .isDirectory,
    )
  }

  /// An install on disk as the library writes one: a file per repository folder, sized as asked,
  /// and one provenance naming them at the pinned revision unless told otherwise.
  static func install(sizes: [String: Int], revision: String? = nil) throws -> URL {
    let root = temporaryRoot()
    let repositories = ModelAsset.allCases.flatMap(\.repositories)
    var entries: [Provenance.Repository] = []
    for (folder, size) in sizes {
      let repository = try require(repositories.first { $0.folder == folder })
      let file = root.appending(path: "Models/\(folder)/weights.bin")
      try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
      )
      try Data(repeating: 0, count: size).write(to: file)
      entries.append(
        Provenance.Repository(
          repository: repository.repository, revision: revision ?? repository.revision,
          files: [Provenance.File(path: "weights.bin", size: size, sha256: nil)],
        ),
      )
    }
    try JSONEncoder()
      .encode(Provenance(repositories: entries))
      .write(to: root.appending(path: "provenance.json"))
    return root
  }
}

// MARK: - RequireError

private struct RequireError: Error {}

private func require<T>(_ value: T?) throws -> T {
  guard let value else {
    throw RequireError()
  }
  return value
}

// MARK: - Fractions

final class Fractions: @unchecked Sendable {
  // MARK: Internal

  var values: [Double] {
    lock.withLock { storage }
  }

  func append(_ value: Double) {
    lock.withLock { storage.append(value) }
  }

  // MARK: Private

  private let lock = NSLock()
  private var storage: [Double] = []
}

// MARK: - StubHub

/// Hugging Face, as far as the installer can tell: a tree listing per pinned repository and a body
/// per file, served through a `URLProtocol` so the real download path runs end to end. File bodies
/// can be held until released, which is what makes "while a download runs" a state a test can
/// stand in.
final class StubHub: @unchecked Sendable {
  // MARK: Lifecycle

  /// `extraRepositories` are served beside every asset's, for installs outside the assets.
  init(holdsFiles: Bool = false, extraRepositories: [PinnedRepository] = []) {
    self.holdsFiles = holdsFiles
    self.extraRepositories = extraRepositories
    StubHub.lock.withLock { StubHub.current = self }
  }

  // MARK: Internal

  let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubProtocol.self]
    return URLSession(configuration: configuration)
  }()

  func bytes(of asset: ModelAsset) -> Int {
    asset.repositories.flatMap(files).reduce(0) { $0 + $1.body.count }
  }

  func treeRequests(for repository: PinnedRepository) -> Int {
    lock.withLock { trees[repository.repository, default: 0] }
  }

  func waitForHeldFile() async {
    while lock.withLock({ held.isEmpty }) {
      try? await Task.sleep(for: .milliseconds(5))
    }
  }

  func release() {
    let released = lock.withLock {
      defer {
        held = []
        holdsFiles = false
      }
      return held
    }
    for (stub, body) in released where !stub.isStopped {
      stub.respond(status: 200, body: body)
    }
  }

  // MARK: Fileprivate

  fileprivate static let lock = NSLock()
  fileprivate nonisolated(unsafe) static var current: StubHub?

  fileprivate func handle(_ stub: StubProtocol) {
    let url = stub.request.url!
    let path = url.path(percentEncoded: false)
    for repository in ModelAsset.allCases.flatMap(\.repositories) + extraRepositories {
      if path == "/api/models/\(repository.repository)/tree/\(repository.revision)" {
        lock.withLock { trees[repository.repository, default: 0] += 1 }
        let listing = files(repository).map { file in
          [
            "path": file.path, "type": "file", "size": file.body.count,
            "lfs": ["oid": file.oid],
          ] as [String: Any]
        }
        stub.respond(status: 200, body: try! JSONSerialization.data(withJSONObject: listing))
        return
      }
      let prefix = "/\(repository.repository)/resolve/\(repository.revision)/"
      if path.hasPrefix(prefix),
         let file = files(repository)
         .first(where: { $0.path == String(path.dropFirst(prefix.count)) })
      {
        let holds = lock.withLock {
          if holdsFiles {
            held.append((stub, file.body))
          }
          return holdsFiles
        }
        if !holds {
          stub.respond(status: 200, body: file.body)
        }
        return
      }
    }
    stub.respond(status: 404, body: Data())
  }

  // MARK: Private

  private struct File {
    let path: String
    let body: Data

    var oid: String {
      SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
    }
  }

  private let lock = NSLock()
  private let extraRepositories: [PinnedRepository]
  private var holdsFiles: Bool
  private var trees: [String: Int] = [:]
  private var held: [(StubProtocol, Data)] = []

  private func files(_ repository: PinnedRepository) -> [File] {
    (repository.expectedDirectoryRoots.map { "\($0)weights.bin" } + repository.expectedFiles).map {
      File(path: $0, body: Data("\(repository.repository)/\($0)".utf8))
    }
  }
}

// MARK: - StubProtocol

final class StubProtocol: URLProtocol, @unchecked Sendable {
  // MARK: Internal

  var isStopped: Bool {
    lock.withLock { stopped }
  }

  override class func canInit(with _: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    StubHub.lock.withLock { StubHub.current }!.handle(self)
  }

  override func stopLoading() {
    lock.withLock { stopped = true }
  }

  func respond(status: Int, body: Data) {
    let response = HTTPURLResponse(
      url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
      headerFields: ["Content-Length": "\(body.count)"],
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: body)
    client?.urlProtocolDidFinishLoading(self)
  }

  // MARK: Private

  private let lock = NSLock()
  private var stopped = false
}
