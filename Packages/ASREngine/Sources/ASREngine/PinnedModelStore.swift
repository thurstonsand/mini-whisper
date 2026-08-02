import CryptoKit
import Darwin
import Foundation
import OSLog

private let downloadLogger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "engine")

private enum PinnedModelDownloadError: Error { case restartFromZero }

struct PinnedModelStore: Sendable {
  static let asrRepository = "FluidInference/parakeet-tdt-0.6b-v2-coreml"
  static let asrRevision = "ee09c569f73759e6d44c9bd16766f477b2b36d39"
  static let vadRepository = "FluidInference/silero-vad-coreml"
  static let vadRevision = "b419383c55c110e2c9271fa6ee0ea83d03c70d96"

  private static let asrFolder = "parakeet-tdt-0.6b-v2"
  private static let vadFolder = "silero-vad"
  private static let stagingPinsFilename = ".pins"
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
  var stagingRoot: URL { root.appendingPathExtension("partial") }
  var stagingPinsURL: URL { stagingRoot.appending(path: Self.stagingPinsFilename) }

  func download(progress: @escaping @Sendable (Double) -> Void) async throws {
    let fileManager = FileManager.default
    let parent = root.deletingLastPathComponent()
    try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
    let downloadLock = try ModelDownloadLock(
      at: parent.appending(path: ".\(root.lastPathComponent)-download.lock"))
    defer { withExtendedLifetime(downloadLock) {} }

    try prepareStagingRoot()
    let specifications = [
      RepositorySpecification(
        repository: Self.asrRepository, revision: Self.asrRevision, localFolder: Self.asrFolder,
        expectedDirectoryRoots: Self.expectedASRRoots, expectedFiles: ["parakeet_vocab.json"]),
      RepositorySpecification(
        repository: Self.vadRepository, revision: Self.vadRevision, localFolder: Self.vadFolder,
        expectedDirectoryRoots: Self.expectedVADRoots, expectedFiles: []),
    ]
    var plan: [PlannedFile] = []
    for specification in specifications {
      let files = try await listFiles(specification)
      try validateTree(files, specification: specification)
      plan.append(
        contentsOf: files.map {
          PlannedFile(
            specification: specification, file: $0,
            destination: destination(for: $0, specification: specification))
        })
    }

    for index in plan.indices { plan[index].resolvedHash = try reusableHash(for: plan[index]) }

    let totalBytes = plan.reduce(0) { $0 + $1.file.size }
    var completedBytes = plan.reduce(0) { $0 + ($1.resolvedHash == nil ? 0 : $1.file.size) }
    let aggregateProgress = AggregateDownloadProgress(totalBytes: totalBytes, progress: progress)
    aggregateProgress.report(completedBytes)

    for index in plan.indices where plan[index].resolvedHash == nil {
      let planned = plan[index]
      try fileManager.createDirectory(
        at: planned.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
      let completedBytesBeforeFile = completedBytes
      plan[index].resolvedHash = try await download(
        planned.file, specification: planned.specification, to: planned.destination,
        progress: { transferredBytes in
          aggregateProgress.report(
            completedBytesBeforeFile + min(transferredBytes, planned.file.size))
        })
      completedBytes += planned.file.size
      aggregateProgress.report(completedBytes)
    }

    let provenance = Provenance(
      repositories: specifications.map { specification in
        Provenance.Repository(
          repository: specification.repository, revision: specification.revision,
          files: plan.filter { $0.specification.repository == specification.repository }.map {
            Provenance.File(path: $0.file.path, size: $0.file.size, sha256: $0.resolvedHash)
          })
      })
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(provenance).write(
      to: stagingRoot.appending(path: "provenance.json"), options: .atomic)
    try validateArtifact(at: stagingRoot, provenance: provenance)
    downloadLogger.notice("Pinned model staging artifact complete and SHA-256 verified")

    if fileManager.fileExists(atPath: root.path) {
      let backupName = ".\(root.lastPathComponent)-backup-\(UUID().uuidString)"
      _ = try fileManager.replaceItemAt(
        root, withItemAt: stagingRoot, backupItemName: backupName, options: [])
      try? fileManager.removeItem(at: parent.appending(path: backupName))
    } else {
      try fileManager.moveItem(at: stagingRoot, to: root)
    }
    try? fileManager.removeItem(at: root.appending(path: Self.stagingPinsFilename))
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
    try? FileManager.default.removeItem(at: root.appending(path: Self.stagingPinsFilename))
    try? FileManager.default.removeItem(at: stagingRoot)
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
    _ file: RemoteFile, specification: RepositorySpecification, to destination: URL,
    progress: @escaping @Sendable (Int) -> Void
  ) async throws -> String {
    let fileManager = FileManager.default
    let partialURL = destination.appendingPathExtension("partial")
    if file.size == 0 {
      try Data().write(to: partialURL, options: .atomic)
      let hash = try verifiedHash(of: partialURL, for: file, resumed: false)
      try promote(partialURL, to: destination)
      return hash
    }
    // Only an LFS oid can prove a partial correct, so anything else starts from zero.
    if file.lfs == nil { try? fileManager.removeItem(at: partialURL) }

    var resumeOffset = try fileSize(at: partialURL)
    if resumeOffset > file.size {
      try fileManager.removeItem(at: partialURL)
      resumeOffset = 0
    }
    if resumeOffset == file.size {
      let hash = try sha256(partialURL)
      if hash == file.lfs?.oid {
        try promote(partialURL, to: destination)
        return hash
      }
      downloadLogger.error(
        "Pinned model partial failed SHA-256; restarting \(file.path, privacy: .public)")
      try fileManager.removeItem(at: partialURL)
      resumeOffset = 0
    }

    let url = remoteURL(for: file, specification: specification)
    let fetch: @Sendable (Int) async throws -> Void = { offset in
      if offset > 0 {
        downloadLogger.notice(
          "Resuming pinned model file \(file.path, privacy: .public) from byte offset \(offset, privacy: .public)"
        )
      }
      let downloader = ProgressDownload(
        configuration: session.configuration, destination: partialURL, expectedBytes: file.size,
        resumeOffset: offset, progress: progress)
      do { try await downloader.download(from: url) } catch ProgressDownloadError.restartRequired {
        guard offset > 0 else {
          throw ASREngineError.invalidDownload("server rejected download for \(file.path)")
        }
        throw PinnedModelDownloadError.restartFromZero
      } catch ProgressDownloadError.invalidResponse(let message) {
        throw ASREngineError.invalidDownload("\(message) for \(file.path)")
      }
    }

    let hash: String
    do {
      try await fetch(resumeOffset)
      hash = try verifiedHash(of: partialURL, for: file, resumed: resumeOffset > 0)
    } catch PinnedModelDownloadError.restartFromZero {
      try? fileManager.removeItem(at: partialURL)
      try await fetch(0)
      hash = try verifiedHash(of: partialURL, for: file, resumed: false)
    }
    try promote(partialURL, to: destination)
    return hash
  }

  /// Hashes `url` exactly once: the result is both the acceptance check and the provenance record.
  private func verifiedHash(of url: URL, for file: RemoteFile, resumed: Bool) throws -> String {
    guard try fileSize(at: url) == file.size else {
      throw ASREngineError.invalidDownload("size mismatch for \(file.path)")
    }
    let hash = try sha256(url)
    if let expectedHash = file.lfs?.oid, hash != expectedHash {
      guard resumed else {
        throw ASREngineError.invalidDownload("SHA-256 mismatch for \(file.path)")
      }
      downloadLogger.error(
        "Pinned model partial failed SHA-256; restarting \(file.path, privacy: .public)")
      throw PinnedModelDownloadError.restartFromZero
    }
    return hash
  }

  private func promote(_ partial: URL, to destination: URL) throws {
    try? FileManager.default.removeItem(at: destination)
    try FileManager.default.moveItem(at: partial, to: destination)
  }

  /// A staged file survives only when the pinned manifest can vouch for its bytes, which keeps a
  /// revision splice from smuggling stale content into the artifact.
  func reusableHash(for planned: PlannedFile) throws -> String? {
    guard let expectedHash = planned.file.lfs?.oid,
      try fileSize(at: planned.destination) == planned.file.size,
      try sha256(planned.destination) == expectedHash
    else {
      try? FileManager.default.removeItem(at: planned.destination)
      return nil
    }
    return expectedHash
  }

  func prepareStagingRoot() throws {
    let fileManager = FileManager.default
    let pins = Data(
      "\(Self.asrRepository)@\(Self.asrRevision)\n\(Self.vadRepository)@\(Self.vadRevision)\n".utf8)
    if fileManager.fileExists(atPath: stagingRoot.path),
      (try? Data(contentsOf: stagingPinsURL)) != pins
    {
      try fileManager.removeItem(at: stagingRoot)
    }
    try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
    try pins.write(to: stagingPinsURL, options: .atomic)
  }

  private func destination(for file: RemoteFile, specification: RepositorySpecification) -> URL {
    stagingRoot.appending(path: "Models", directoryHint: .isDirectory).appending(
      path: specification.localFolder, directoryHint: .isDirectory
    ).appending(path: file.path)
  }

  private func remoteURL(for file: RemoteFile, specification: RepositorySpecification) -> URL {
    let encodedPath = file.path.split(separator: "/").map {
      String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
    }.joined(separator: "/")
    return URL(
      string:
        "https://huggingface.co/\(specification.repository)/resolve/\(specification.revision)/\(encodedPath)"
    )!
  }

  private func fileSize(at url: URL) throws -> Int {
    guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
    return try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
  }

  /// Existence and size only: every file is SHA-256 verified against the pinned manifest as it is
  /// written, and rehashing the 465 MB corpus costs ~200 ms of launch for a check that CoreML
  /// compile and prewarm would fail on anyway.
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
        guard FileManager.default.fileExists(atPath: url.path) else {
          throw ASREngineError.invalidArtifact("missing \(file.path)")
        }
        guard try fileSize(at: url) == file.size else {
          throw ASREngineError.invalidArtifact("size mismatch for \(file.path)")
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

private final class ModelDownloadLock {
  private let descriptor: Int32

  init(at url: URL) throws {
    let descriptor = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
    guard flock(descriptor, LOCK_EX) == 0 else {
      close(descriptor)
      throw POSIXError(.init(rawValue: errno) ?? .EIO)
    }
    self.descriptor = descriptor
  }

  deinit {
    flock(descriptor, LOCK_UN)
    close(descriptor)
  }
}

private final class AggregateDownloadProgress: @unchecked Sendable {
  private let totalBytes: Int
  private let progress: @Sendable (Double) -> Void
  private let lock = NSLock()
  private var reportedBytes = 0

  init(totalBytes: Int, progress: @escaping @Sendable (Double) -> Void) {
    self.totalBytes = totalBytes
    self.progress = progress
  }

  func report(_ bytes: Int) {
    let fraction = lock.withLock {
      reportedBytes = max(reportedBytes, min(bytes, totalBytes))
      return totalBytes == 0 ? 1 : Double(reportedBytes) / Double(totalBytes)
    }
    progress(fraction)
  }
}

struct RepositorySpecification: Sendable {
  let repository: String
  let revision: String
  let localFolder: String
  let expectedDirectoryRoots: [String]
  let expectedFiles: [String]
}

struct PlannedFile: Sendable {
  let specification: RepositorySpecification
  let file: RemoteFile
  let destination: URL
  var resolvedHash: String?
}

struct RemoteFile: Decodable, Sendable {
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
