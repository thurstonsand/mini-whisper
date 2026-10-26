import Foundation

// MARK: - ModelLibrary

/// Every pinned model on disk, as assets with their own lifecycle. A download belongs to the
/// library, not to whoever asked for it: a second caller joins the one already running, and it
/// stops only when nobody is waiting on it any more.
public actor ModelLibrary {
  // MARK: Lifecycle

  public init(root: URL, session: URLSession = .shared) {
    self.root = root
    self.session = session
    current = Dictionary(
      uniqueKeysWithValues: ModelAsset.allCases.map { ($0, Self.restingState($0, root: root)) },
    )
  }

  // MARK: Public

  public nonisolated let root: URL

  public nonisolated func directory(_ repository: PinnedRepository) -> URL {
    root.appending(path: "Models/\(repository.folder)", directoryHint: .isDirectory)
  }

  /// Existence and size only, returning the bytes installed: every file is SHA-256 verified
  /// against the pinned manifest as it is written, and rehashing half a gigabyte costs ~200 ms of
  /// launch for a check that Core ML compile and prewarm would fail on anyway. A revision other
  /// than the pin is an asset that is not installed: the ordinary download is the whole remedy.
  public nonisolated func validate(_ asset: ModelAsset) throws -> Int {
    try Self.validate(asset, root: root)
  }

  /// Installs several assets at once behind one bar, weighted by what each one weighs.
  public nonisolated func install(
    _ assets: [ModelAsset], progress: @escaping @Sendable (Double) -> Void,
  ) async throws {
    let combined = CombinedProgress(assets: assets, progress: progress)
    try await withThrowingTaskGroup(of: Void.self) { group in
      for asset in assets {
        group.addTask { try await self.install(asset) { combined.report($0, for: asset) } }
      }
      try await group.waitForAll()
    }
  }

  public func install(
    _ asset: ModelAsset, progress: @escaping @Sendable (Double) -> Void,
  ) async throws {
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        attach(Waiter(id: id, progress: progress, continuation: continuation), to: asset)
      }
    } onCancel: {
      Task { await self.detach(id, from: asset) }
    }
  }

  /// A repository outside every asset, such as a speech model under evaluation: validated like an
  /// asset, but no part of `states()`, since nothing in the app offers it.
  public nonisolated func validate(_ repositories: [PinnedRepository]) throws -> Int {
    try Self.validate(repositories, root: root) { .missingRepository($0.repository) }
  }

  /// Installs repositories outside every asset, under `name`. Unlike an asset's download it is
  /// not shared: the one caller is the one waiting.
  public nonisolated func install(
    _ repositories: [PinnedRepository], name: String,
    progress: @escaping @Sendable (Double) -> Void,
  ) async throws {
    try await AssetInstaller(name: name, repositories: repositories, root: root, session: session)
      .install(progress: progress)
  }

  public func delete(_ asset: ModelAsset) throws {
    guard downloads[asset] == nil else {
      throw ModelLibraryError.downloading(asset)
    }
    // Provenance first: a folder that outlives its entry is clutter, but an entry that outlives
    // its folder would be an install that is not there.
    try Provenance.update(root: root) { $0.remove(asset.repositories.map(\.repository)) }
    let fileManager = FileManager.default
    for repository in asset.repositories
      where fileManager.fileExists(atPath: directory(repository).path)
    {
      try fileManager.removeItem(at: directory(repository))
    }
    let staging = AssetInstaller(asset: asset, root: root, session: session).stagingRoot
    if fileManager.fileExists(atPath: staging.path) {
      try fileManager.removeItem(at: staging)
    }
    publish(.missing, for: asset)
  }

  /// The current state of every asset, then each change as it happens.
  public nonisolated func states() -> AsyncStream<[ModelAsset: AssetState]> {
    AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      let id = UUID()
      Task { await self.observe(id, continuation) }
      continuation.onTermination = { _ in Task { await self.stopObserving(id) } }
    }
  }

  // MARK: Private

  private struct Waiter {
    let id: UUID
    let progress: @Sendable (Double) -> Void
    let continuation: CheckedContinuation<Void, Error>
  }

  private struct Download {
    let token: UUID
    let task: Task<Void, Never>
    var fraction = 0.0
    var waiters: [UUID: Waiter] = [:]
  }

  private let session: URLSession
  private var current: [ModelAsset: AssetState]
  private var downloads: [ModelAsset: Download] = [:]
  private var observers: [UUID: AsyncStream<[ModelAsset: AssetState]>.Continuation] = [:]

  private static func validate(_ asset: ModelAsset, root: URL) throws -> Int {
    try validate(asset.repositories, root: root) { _ in .missing(asset) }
  }

  private static func validate(
    _ repositories: [PinnedRepository], root: URL,
    missing: (PinnedRepository) -> ModelLibraryError,
  ) throws -> Int {
    let provenance = try Provenance.read(root: root)
    var bytes = 0
    for repository in repositories {
      guard let entry = provenance?.entry(repository), entry.revision == repository.revision else {
        throw missing(repository)
      }
      for file in entry.files {
        let url = root.appending(
          path: "Models/\(repository.folder)/\(repository.localPath(of: file.path))",
        )
        guard FileManager.default.fileExists(atPath: url.path) else {
          throw ModelLibraryError.invalidArtifact("missing \(file.path)")
        }
        guard try fileSize(at: url) == file.size else {
          throw ModelLibraryError.invalidArtifact("size mismatch for \(file.path)")
        }
        bytes += file.size
      }
    }
    return bytes
  }

  private static func restingState(_ asset: ModelAsset, root: URL) -> AssetState {
    do {
      return try .installed(bytes: validate(asset, root: root))
    } catch ModelLibraryError.missing {
      return .missing
    } catch {
      return .failed(error.localizedDescription)
    }
  }

  private func attach(_ waiter: Waiter, to asset: ModelAsset) {
    guard !Task.isCancelled else {
      waiter.continuation.resume(throwing: CancellationError())
      return
    }
    // A download whose last waiter left is winding down; a new waiter starts a fresh one behind
    // it, and the staging lock keeps the two from writing at once.
    if downloads[asset] == nil || downloads[asset]!.task.isCancelled {
      let installer = AssetInstaller(asset: asset, root: root, session: session)
      let token = UUID()
      let task = Task {
        let result: Result<Void, Error>
        do {
          try await installer.install { fraction in
            Task { await self.report(fraction, for: asset, token: token) }
          }
          result = .success(())
        } catch {
          result = .failure(error)
        }
        finish(asset, token: token, result)
      }
      downloads[asset] = Download(token: token, task: task)
      publish(.downloading(0), for: asset)
    }
    downloads[asset]!.waiters[waiter.id] = waiter
    waiter.progress(downloads[asset]!.fraction)
  }

  private func detach(_ id: UUID, from asset: ModelAsset) {
    guard let waiter = downloads[asset]?.waiters.removeValue(forKey: id) else {
      return
    }
    waiter.continuation.resume(throwing: CancellationError())
    if downloads[asset]?.waiters.isEmpty == true {
      downloads[asset]?.task.cancel()
    }
  }

  private func report(_ fraction: Double, for asset: ModelAsset, token: UUID) {
    guard var download = downloads[asset], download.token == token, fraction > download.fraction
    else {
      return
    }
    let percent = Int(download.fraction * 100)
    download.fraction = fraction
    downloads[asset] = download
    for waiter in download.waiters.values {
      waiter.progress(fraction)
    }
    // Every received chunk reports; observers only need to hear a percent.
    if Int(fraction * 100) != percent {
      publish(.downloading(fraction), for: asset)
    }
  }

  private func finish(_ asset: ModelAsset, token: UUID, _ result: Result<Void, Error>) {
    guard let download = downloads[asset], download.token == token else {
      return
    }
    downloads[asset] = nil
    for waiter in download.waiters.values {
      // The last chunk's report hops here on its own task and can land after this; a finished
      // download is whole regardless.
      if case .success = result {
        waiter.progress(1)
      }
      waiter.continuation.resume(with: result)
    }
    // Staging is a sibling of the install, so a cancelled download leaves whatever was installed
    // exactly as it was.
    if case let .failure(error) = result, !download.task.isCancelled {
      publish(.failed(error.localizedDescription), for: asset)
    } else {
      publish(Self.restingState(asset, root: root), for: asset)
    }
  }

  private func publish(_ state: AssetState, for asset: ModelAsset) {
    current[asset] = state
    for observer in observers.values {
      observer.yield(current)
    }
  }

  private func observe(
    _ id: UUID, _ continuation: AsyncStream<[ModelAsset: AssetState]>.Continuation,
  ) {
    observers[id] = continuation
    continuation.yield(current)
  }

  private func stopObserving(_ id: UUID) {
    observers[id] = nil
  }
}

// MARK: - CombinedProgress

private final class CombinedProgress: @unchecked Sendable {
  // MARK: Lifecycle

  init(assets: [ModelAsset], progress: @escaping @Sendable (Double) -> Void) {
    totalBytes = assets.reduce(0) { $0 + $1.pinnedBytes }
    self.progress = progress
  }

  // MARK: Internal

  func report(_ fraction: Double, for asset: ModelAsset) {
    let combined = lock.withLock {
      fractions[asset] = fraction
      let bytes = fractions.reduce(0.0) { $0 + $1.value * Double($1.key.pinnedBytes) }
      return totalBytes == 0 ? 1 : bytes / Double(totalBytes)
    }
    progress(combined)
  }

  // MARK: Private

  private let totalBytes: Int
  private let progress: @Sendable (Double) -> Void
  private let lock = NSLock()
  private var fractions: [ModelAsset: Double] = [:]
}
