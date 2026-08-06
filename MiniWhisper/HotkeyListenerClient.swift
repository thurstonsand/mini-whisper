import ComposableArchitecture
import HotkeyListener

// MARK: - HotkeyListenerClient

@DependencyClient struct HotkeyListenerClient {
  var events: @Sendable ([Hotkey]) async throws -> AsyncStream<HotkeyListenerEvent>
  var record: @Sendable () async throws -> AsyncStream<HotkeyRecorderEvent>
}

// MARK: DependencyKey

extension HotkeyListenerClient: DependencyKey {
  static let liveValue = Self(
    events: { hotkeys in try await HotkeyListener.events(hotkeys: hotkeys) },
    record: { try await HotkeyRecorder.events() },
  )
}

extension DependencyValues {
  var hotkeyListener: HotkeyListenerClient {
    get { self[HotkeyListenerClient.self] }
    set { self[HotkeyListenerClient.self] = newValue }
  }
}
