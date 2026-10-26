import CryptoKit
import Darwin
import Foundation
import OSLog

private let downloadLogger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "engine")

// MARK: - AssetDownloadError

private enum AssetDownloadError: Error { case restartFromZero }

// MARK: - AssetInstaller

/// Downloads one asset into its own staging directory, verifies every file against the pinned
/// manifest, then swaps its folders into the library and records them in the shared provenance.
struct AssetInstaller {
  // MARK: Lifecycle

  init(asset: ModelAsset, root: URL, session: URLSession) {
    self.init(name: asset.rawValue, repositories: asset.repositories, root: root, session: session)
  }

  /// `name` keeps a staging directory and lock apart from every other install's.
  init(name: String, repositories: [PinnedRepository], root: URL, session: URLSession) {
    self.name = name
    self.repositories = repositories
    self.root = root
    self.session = session
  }

  // MARK: Internal

  let name: String
  let repositories: [PinnedRepository]
  let root: URL
  let session: URLSession

  /// A sibling of the library rather than a child, so nothing half-written ever sits where
  /// validation looks.
  var stagingRoot: URL {
    root.deletingLastPathComponent().appending(
      path: "\(root.lastPathComponent)-\(name).partial", directoryHint: .isDirectory,
    )
  }

  var stagingPinsURL: URL {
    stagingRoot.appending(path: ".pins")
  }

  @concurrent func install(progress: @escaping @Sendable (Double) -> Void) async throws {
    let fileManager = FileManager.default
    let parent = root.deletingLastPathComponent()
    try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
    let downloadLock = try FileLock(
      at: parent.appending(path: ".\(root.lastPathComponent)-\(name)-download.lock"),
    )
    defer { withExtendedLifetime(downloadLock) {} }

    try prepareStagingRoot()
    var plan: [PlannedFile] = []
    for repository in repositories {
      let files = try await listFiles(repository)
      try validateTree(files, repository: repository)
      plan.append(
        contentsOf: files.map {
          PlannedFile(
            repository: repository, file: $0,
            destination: stagingRoot.appending(path: repository.folder, directoryHint: .isDirectory)
              .appending(path: repository.localPath(of: $0.path)),
          )
        },
      )
    }

    for index in plan.indices {
      plan[index].resolvedHash = try reusableHash(for: plan[index])
    }

    let totalBytes = plan.reduce(0) { $0 + $1.file.size }
    var completedBytes = plan.reduce(0) { $0 + ($1.resolvedHash == nil ? 0 : $1.file.size) }
    let aggregateProgress = AggregateDownloadProgress(totalBytes: totalBytes, progress: progress)
    aggregateProgress.report(completedBytes)

    for index in plan.indices where plan[index].resolvedHash == nil {
      try Task.checkCancellation()
      let planned = plan[index]
      try fileManager.createDirectory(
        at: planned.destination.deletingLastPathComponent(), withIntermediateDirectories: true,
      )
      let completedBytesBeforeFile = completedBytes
      plan[index].resolvedHash = try await download(
        planned.file, repository: planned.repository, to: planned.destination,
        progress: { transferredBytes in
          aggregateProgress.report(
            completedBytesBeforeFile + min(transferredBytes, planned.file.size),
          )
        },
      )
      completedBytes += planned.file.size
      aggregateProgress.report(completedBytes)
    }
    downloadLogger.notice(
      "\(name, privacy: .public) staging complete and SHA-256 verified",
    )

    let modelsDirectory = root.appending(path: "Models", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
    for repository in repositories {
      let staged = stagingRoot.appending(path: repository.folder, directoryHint: .isDirectory)
      let installed = modelsDirectory.appending(
        path: repository.folder,
        directoryHint: .isDirectory,
      )
      if fileManager.fileExists(atPath: installed.path) {
        let backupName = ".\(repository.folder)-backup-\(UUID().uuidString)"
        _ = try fileManager.replaceItemAt(
          installed, withItemAt: staged, backupItemName: backupName, options: [],
        )
        try? fileManager.removeItem(at: modelsDirectory.appending(path: backupName))
      } else {
        try fileManager.moveItem(at: staged, to: installed)
      }
    }
    try Provenance.update(root: root) { provenance in
      provenance.replace(
        repositories.map { repository in
          Provenance.Repository(
            repository: repository.repository, revision: repository.revision,
            files: plan.filter { $0.repository == repository }.map {
              Provenance.File(path: $0.file.path, size: $0.file.size, sha256: $0.resolvedHash)
            },
          )
        },
      )
    }
    try fileManager.removeItem(at: stagingRoot)
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
    let pins = Data((repositories.map { "\($0.identity)\n" }.joined()).utf8)
    if fileManager.fileExists(atPath: stagingRoot.path),
       (try? Data(contentsOf: stagingPinsURL)) != pins
    {
      try fileManager.removeItem(at: stagingRoot)
    }
    try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
    try pins.write(to: stagingPinsURL, options: .atomic)
  }

  // MARK: Private

  private func listFiles(_ repository: PinnedRepository) async throws -> [RemoteFile] {
    var components = URLComponents(
      string:
      "https://huggingface.co/api/models/\(repository.repository)/tree/\(repository.revision)",
    )!
    components.queryItems = [URLQueryItem(name: "recursive", value: "true")]
    let (data, response) = try await session.data(from: components.url!)
    try validate(response: response, data: data)
    let items = try JSONDecoder().decode([RemoteFile].self, from: data)
    return items.filter { item in
      item.type == "file"
        && (repository.expectedFiles.contains(item.path)
          || repository.expectedDirectoryRoots.contains { item.path.hasPrefix($0) })
    }
  }

  private func validateTree(_ files: [RemoteFile], repository: PinnedRepository) throws {
    guard !files.isEmpty else {
      throw ModelLibraryError.invalidDownload("empty tree for \(repository.repository)")
    }
    for root in repository.expectedDirectoryRoots
      where !files.contains(where: { $0.path.hasPrefix(root) })
    {
      throw ModelLibraryError.invalidDownload("missing \(root) in \(repository.repository)")
    }
    for file in repository.expectedFiles where !files.contains(where: { $0.path == file }) {
      throw ModelLibraryError.invalidDownload("missing \(file) in \(repository.repository)")
    }
    guard files.allSatisfy({ !$0.path.split(separator: "/").contains("..") }) else {
      throw ModelLibraryError.invalidDownload("unsafe model path")
    }
  }

  private func download(
    _ file: RemoteFile, repository: PinnedRepository, to destination: URL,
    progress: @escaping @Sendable (Int) -> Void,
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
    if file.lfs == nil {
      try? fileManager.removeItem(at: partialURL)
    }

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
        "Pinned model partial failed SHA-256; restarting \(file.path, privacy: .public)",
      )
      try fileManager.removeItem(at: partialURL)
      resumeOffset = 0
    }

    let url = remoteURL(for: file, repository: repository)
    let fetch: @Sendable (Int) async throws -> Void = { offset in
      if offset > 0 {
        downloadLogger.notice(
          "Resuming pinned model file \(file.path, privacy: .public) from byte offset \(offset, privacy: .public)",
        )
      }
      let downloader = ProgressDownload(
        configuration: session.configuration, destination: partialURL, expectedBytes: file.size,
        resumeOffset: offset, progress: progress,
      )
      do { try await downloader.download(from: url) } catch ProgressDownloadError.restartRequired {
        guard offset > 0 else {
          throw ModelLibraryError.invalidDownload("server rejected download for \(file.path)")
        }
        throw AssetDownloadError.restartFromZero
      } catch let ProgressDownloadError.invalidResponse(message) {
        throw ModelLibraryError.invalidDownload("\(message) for \(file.path)")
      }
    }

    let hash: String
    do {
      try await fetch(resumeOffset)
      hash = try verifiedHash(of: partialURL, for: file, resumed: resumeOffset > 0)
    } catch AssetDownloadError.restartFromZero {
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
      throw ModelLibraryError.invalidDownload("size mismatch for \(file.path)")
    }
    let hash = try sha256(url)
    if let expectedHash = file.lfs?.oid, hash != expectedHash {
      guard resumed else {
        throw ModelLibraryError.invalidDownload("SHA-256 mismatch for \(file.path)")
      }
      downloadLogger.error(
        "Pinned model partial failed SHA-256; restarting \(file.path, privacy: .public)",
      )
      throw AssetDownloadError.restartFromZero
    }
    return hash
  }

  private func promote(_ partial: URL, to destination: URL) throws {
    try? FileManager.default.removeItem(at: destination)
    try FileManager.default.moveItem(at: partial, to: destination)
  }

  private func remoteURL(for file: RemoteFile, repository: PinnedRepository) -> URL {
    let encodedPath = file.path
      .split(separator: "/")
      .map {
        String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
      }
      .joined(separator: "/")
    return URL(
      string:
      "https://huggingface.co/\(repository.repository)/resolve/\(repository.revision)/\(encodedPath)",
    )!
  }

  private func validate(response: URLResponse, data: Data?) throws {
    guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
      let status = (response as? HTTPURLResponse)?.statusCode ?? -1
      let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
      throw ModelLibraryError.invalidDownload("HTTP \(status): \(body.prefix(200))")
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
}

func fileSize(at url: URL) throws -> Int {
  guard FileManager.default.fileExists(atPath: url.path) else {
    return 0
  }
  return try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
}

// MARK: - FileLock

/// An exclusive `flock` held for the object's lifetime. Locks belong to open file descriptions, so
/// two holders in one process exclude each other exactly as two processes do.
final class FileLock {
  // MARK: Lifecycle

  init(at url: URL) throws {
    let descriptor = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else {
      throw POSIXError(.init(rawValue: errno) ?? .EIO)
    }
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

  // MARK: Private

  private let descriptor: Int32
}

// MARK: - AggregateDownloadProgress

/// One bar over every repository in an asset. Bytes are the only unit all of them share, so the
/// fraction is byte-weighted across the whole plan and the clamp keeps a retried file from
/// walking it backwards.
private final class AggregateDownloadProgress: @unchecked Sendable {
  // MARK: Lifecycle

  init(totalBytes: Int, progress: @escaping @Sendable (Double) -> Void) {
    self.totalBytes = totalBytes
    self.progress = progress
  }

  // MARK: Internal

  func report(_ bytes: Int) {
    let fraction = lock.withLock {
      reportedBytes = max(reportedBytes, min(bytes, totalBytes))
      return totalBytes == 0 ? 1 : Double(reportedBytes) / Double(totalBytes)
    }
    progress(fraction)
  }

  // MARK: Private

  private let totalBytes: Int
  private let progress: @Sendable (Double) -> Void
  private let lock = NSLock()
  private var reportedBytes = 0
}

// MARK: - PlannedFile

struct PlannedFile {
  let repository: PinnedRepository
  let file: RemoteFile
  let destination: URL
  var resolvedHash: String?
}

// MARK: - RemoteFile

struct RemoteFile: Decodable {
  struct LFS: Decodable { let oid: String }

  let path: String
  let type: String
  let size: Int
  let lfs: LFS?
}

// MARK: - Provenance

/// What is installed, per repository, in one file at the library root. Every asset reads and
/// writes its own entries; the lock keeps two assets finishing at once from losing either write.
struct Provenance: Codable {
  struct Repository: Codable {
    let repository: String
    let revision: String
    let files: [File]
  }

  struct File: Codable {
    let path: String
    let size: Int
    let sha256: String?
  }

  var repositories: [Repository]

  static func url(root: URL) -> URL {
    root.appending(path: "provenance.json")
  }

  /// Nil when nothing has ever been installed, which is a different fact from a file that cannot
  /// be read.
  static func read(root: URL) throws -> Provenance? {
    let url = url(root: root)
    guard FileManager.default.fileExists(atPath: url.path) else {
      return nil
    }
    do {
      return try JSONDecoder().decode(Provenance.self, from: Data(contentsOf: url))
    } catch {
      throw ModelLibraryError.invalidArtifact(
        "unreadable provenance: \(error.localizedDescription)",
      )
    }
  }

  static func update(root: URL, _ edit: (inout Provenance) -> Void) throws {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let lock = try FileLock(
      at: root.deletingLastPathComponent().appending(
        path: ".\(root.lastPathComponent)-provenance.lock",
      ),
    )
    defer { withExtendedLifetime(lock) {} }
    // An unreadable file records nothing worth keeping; whatever it described is re-proven by the
    // next install of each asset.
    var provenance = (try? read(root: root)) ?? Provenance(repositories: [])
    edit(&provenance)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(provenance).write(to: url(root: root), options: .atomic)
  }

  func entry(_ repository: PinnedRepository) -> Repository? {
    repositories.first { $0.repository == repository.repository }
  }

  mutating func replace(_ entries: [Repository]) {
    remove(entries.map(\.repository))
    repositories += entries
  }

  mutating func remove(_ names: [String]) {
    repositories.removeAll { names.contains($0.repository) }
  }
}
