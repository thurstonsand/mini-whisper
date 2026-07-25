import CryptoKit
import Foundation

struct PinnedModelStore: Sendable {
  static let asrRepository = "FluidInference/parakeet-tdt-0.6b-v2-coreml"
  static let asrRevision = "ee09c569f73759e6d44c9bd16766f477b2b36d39"
  static let vadRepository = "FluidInference/silero-vad-coreml"
  static let vadRevision = "b419383c55c110e2c9271fa6ee0ea83d03c70d96"

  private static let asrFolder = "parakeet-tdt-0.6b-v2"
  private static let vadFolder = "silero-vad"
  private static let expectedASRRoots = [
    "Preprocessor.mlmodelc/", "Encoder.mlmodelc/", "Decoder.mlmodelc/", "JointDecision.mlmodelc/",
  ]
  private static let expectedVADRoots = ["silero-vad-unified-256ms-v6.2.1.mlmodelc/"]

  let root: URL
  let session: URLSession

  init(root: URL = Self.defaultRoot(), session: URLSession = .shared) {
    self.root = root
    self.session = session
  }

  var modelsDirectory: URL { root.appending(path: "Models", directoryHint: .isDirectory) }
  var asrDirectory: URL {
    modelsDirectory.appending(path: Self.asrFolder, directoryHint: .isDirectory)
  }
  var vadBaseDirectory: URL { root }

  func download(progress: @escaping @Sendable (Double) -> Void) async throws {
    let fileManager = FileManager.default
    let parent = root.deletingLastPathComponent()
    try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
    let temporaryRoot = parent.appending(
      path: ".\(root.lastPathComponent)-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? fileManager.removeItem(at: temporaryRoot) }
    try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)

    let specifications = [
      RepositorySpecification(
        repository: Self.asrRepository, revision: Self.asrRevision, localFolder: Self.asrFolder,
        expectedDirectoryRoots: Self.expectedASRRoots, expectedFiles: ["parakeet_vocab.json"]),
      RepositorySpecification(
        repository: Self.vadRepository, revision: Self.vadRevision, localFolder: Self.vadFolder,
        expectedDirectoryRoots: Self.expectedVADRoots, expectedFiles: []),
    ]
    var preparedRepositories: [PreparedRepository] = []
    for specification in specifications {
      let files = try await listFiles(specification)
      try validateTree(files, specification: specification)
      preparedRepositories.append(PreparedRepository(specification: specification, files: files))
    }

    let totalBytes = preparedRepositories.flatMap(\.files).reduce(0) { $0 + $1.size }
    var completedBytes = 0
    var repositories: [Provenance.Repository] = []
    progress(0)
    for preparedRepository in preparedRepositories {
      let specification = preparedRepository.specification
      for file in preparedRepository.files {
        let destination = temporaryRoot.appending(path: "Models", directoryHint: .isDirectory)
          .appending(path: specification.localFolder, directoryHint: .isDirectory).appending(
            path: file.path)
        try fileManager.createDirectory(
          at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await download(file, specification: specification, to: destination)
        completedBytes += file.size
        progress(Double(completedBytes) / Double(totalBytes))
      }
      repositories.append(
        Provenance.Repository(
          repository: specification.repository, revision: specification.revision,
          files: preparedRepository.files.map {
            Provenance.File(path: $0.path, size: $0.size, sha256: $0.lfs?.oid)
          }))
    }
    let provenance = Provenance(repositories: repositories)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(provenance).write(
      to: temporaryRoot.appending(path: "provenance.json"), options: .atomic)
    try validateArtifact(at: temporaryRoot, provenance: provenance)

    if fileManager.fileExists(atPath: root.path) {
      let backupName = ".\(root.lastPathComponent)-backup-\(UUID().uuidString)"
      _ = try fileManager.replaceItemAt(
        root, withItemAt: temporaryRoot, backupItemName: backupName, options: [])
      try? fileManager.removeItem(at: parent.appending(path: backupName))
    } else {
      try fileManager.moveItem(at: temporaryRoot, to: root)
    }
  }

  func validateInstalledArtifact() throws {
    let provenanceURL = root.appending(path: "provenance.json")
    guard FileManager.default.fileExists(atPath: provenanceURL.path) else {
      throw ASREngineError.modelMissing
    }
    let provenance: Provenance
    do {
      provenance = try JSONDecoder().decode(Provenance.self, from: Data(contentsOf: provenanceURL))
    } catch {
      throw ASREngineError.invalidArtifact("unreadable provenance: \(error.localizedDescription)")
    }
    guard provenance.revision(for: Self.asrRepository) == Self.asrRevision,
      provenance.revision(for: Self.vadRepository) == Self.vadRevision
    else { throw ASREngineError.invalidArtifact("revision provenance does not match code pins") }
    try validateArtifact(at: root, provenance: provenance)
  }

  private func listFiles(_ specification: RepositorySpecification) async throws -> [RemoteFile] {
    var components = URLComponents(
      string:
        "https://huggingface.co/api/models/\(specification.repository)/tree/\(specification.revision)"
    )!
    components.queryItems = [URLQueryItem(name: "recursive", value: "true")]
    let (data, response) = try await session.data(from: components.url!)
    try validate(response: response, data: data)
    let items = try JSONDecoder().decode([RemoteFile].self, from: data)
    return items.filter { item in
      item.type == "file"
        && (specification.expectedFiles.contains(item.path)
          || specification.expectedDirectoryRoots.contains { item.path.hasPrefix($0) })
    }
  }

  private func validateTree(_ files: [RemoteFile], specification: RepositorySpecification) throws {
    guard !files.isEmpty else {
      throw ASREngineError.invalidDownload("empty tree for \(specification.repository)")
    }
    for root in specification.expectedDirectoryRoots
    where !files.contains(where: { $0.path.hasPrefix(root) }) {
      throw ASREngineError.invalidDownload("missing \(root) in \(specification.repository)")
    }
    for file in specification.expectedFiles where !files.contains(where: { $0.path == file }) {
      throw ASREngineError.invalidDownload("missing \(file) in \(specification.repository)")
    }
    guard files.allSatisfy({ !$0.path.split(separator: "/").contains("..") }) else {
      throw ASREngineError.invalidDownload("unsafe model path")
    }
  }

  private func download(
    _ file: RemoteFile, specification: RepositorySpecification, to destination: URL
  ) async throws {
    let encodedPath = file.path.split(separator: "/").map {
      String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
    }.joined(separator: "/")
    let url = URL(
      string:
        "https://huggingface.co/\(specification.repository)/resolve/\(specification.revision)/\(encodedPath)"
    )!
    let (temporaryURL, response) = try await session.download(from: url)
    try validate(response: response, data: nil)
    let attributes = try FileManager.default.attributesOfItem(atPath: temporaryURL.path)
    guard attributes[.size] as? Int == file.size else {
      throw ASREngineError.invalidDownload("size mismatch for \(file.path)")
    }
    if let expectedHash = file.lfs?.oid {
      let actualHash = try sha256(temporaryURL)
      guard actualHash == expectedHash else {
        throw ASREngineError.invalidDownload("SHA-256 mismatch for \(file.path)")
      }
    }
    try FileManager.default.moveItem(at: temporaryURL, to: destination)
  }

  private func validateArtifact(at root: URL, provenance: Provenance) throws {
    for repository in provenance.repositories {
      let folder: String
      switch repository.repository {
      case Self.asrRepository: folder = Self.asrFolder
      case Self.vadRepository: folder = Self.vadFolder
      default: throw ASREngineError.invalidArtifact("unexpected repository")
      }
      for file in repository.files {
        let url = root.appending(path: "Models/\(folder)/\(file.path)")
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.size] as? Int == file.size else {
          throw ASREngineError.invalidArtifact("size mismatch for \(file.path)")
        }
        if let expectedHash = file.sha256, try sha256(url) != expectedHash {
          throw ASREngineError.invalidArtifact("SHA-256 mismatch for \(file.path)")
        }
      }
    }
  }

  private func validate(response: URLResponse, data: Data?) throws {
    guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
      let status = (response as? HTTPURLResponse)?.statusCode ?? -1
      let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
      throw ASREngineError.invalidDownload("HTTP \(status): \(body.prefix(200))")
    }
  }

  private func sha256(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
      hasher.update(data: data)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  private static func defaultRoot() -> URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(
      path: "MiniWhisper/Engine/pinned-v1", directoryHint: .isDirectory)
  }
}

private struct RepositorySpecification: Sendable {
  let repository: String
  let revision: String
  let localFolder: String
  let expectedDirectoryRoots: [String]
  let expectedFiles: [String]
}

private struct PreparedRepository: Sendable {
  let specification: RepositorySpecification
  let files: [RemoteFile]
}

private struct RemoteFile: Decodable, Sendable {
  struct LFS: Decodable, Sendable { let oid: String }

  let path: String
  let type: String
  let size: Int
  let lfs: LFS?
}

private struct Provenance: Codable, Sendable {
  struct Repository: Codable, Sendable {
    let repository: String
    let revision: String
    let files: [File]
  }

  struct File: Codable, Sendable {
    let path: String
    let size: Int
    let sha256: String?
  }

  let repositories: [Repository]

  func revision(for repository: String) -> String? {
    repositories.first { $0.repository == repository }?.revision
  }
}
