import ComposableArchitecture
import ModelLibrary

// MARK: - ModelLibraryClient

@DependencyClient struct ModelLibraryClient {
  var states: @Sendable () -> AsyncStream<[ModelAsset: AssetState]> = {
    AsyncStream { $0.finish() }
  }

  var delete: @Sendable (ModelAsset) async throws -> Void
  var install: @Sendable (ModelAsset) async throws -> Void
  var isInstalled: @Sendable (ModelAsset) -> Bool = { _ in false }
}

// MARK: DependencyKey

extension ModelLibraryClient: DependencyKey {
  /// A store that never opens the Profiles pane still never hears from the library.
  static let testValue: Self = {
    var client = Self()
    client.states = { AsyncStream { $0.finish() } }
    return client
  }()

  static let liveValue = Self(
    states: { ModelLibrary.live.states() },
    delete: { try await ModelLibrary.live.delete($0) },
    install: { try await ModelLibrary.live.install($0) { _ in } },
    isInstalled: { (try? ModelLibrary.live.validate($0)) != nil },
  )
}

extension ModelLibrary {
  /// One library per process: the engine downloads into it and the Profiles pane reads and
  /// deletes from it, so both have to be talking about the same downloads.
  static let live = ModelLibrary(root: Channel.engineRoot)
}

extension DependencyValues {
  var modelLibrary: ModelLibraryClient {
    get { self[ModelLibraryClient.self] }
    set { self[ModelLibraryClient.self] = newValue }
  }
}
