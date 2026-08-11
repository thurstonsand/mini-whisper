import ComposableArchitecture
import HotkeyListener

// MARK: - HotkeyListenerClient

@DependencyClient struct HotkeyListenerClient {
  var events: @Sendable ([HotkeyBinding]) async throws -> AsyncStream<HotkeyListenerEvent>
  var record: @Sendable () async throws -> AsyncStream<HotkeyRecorderEvent>
}

// MARK: DependencyKey

extension HotkeyListenerClient: DependencyKey {
  static let liveValue = Self(
    events: { bindings in try await HotkeyListener.events(bindings: bindings) },
    record: { try await HotkeyRecorder.events() },
  )
}

extension DependencyValues {
  var hotkeyListener: HotkeyListenerClient {
    get { self[HotkeyListenerClient.self] }
    set { self[HotkeyListenerClient.self] = newValue }
  }
}
