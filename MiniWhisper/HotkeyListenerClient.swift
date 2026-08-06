import ComposableArchitecture
import HotkeyListener

// MARK: - HotkeyListenerClient

@DependencyClient struct HotkeyListenerClient {
  var events: @Sendable (Hotkey) async throws -> AsyncStream<HotkeyListenerEvent>
}

// MARK: DependencyKey

extension HotkeyListenerClient: DependencyKey {
  static let liveValue = Self(
    events: { hotkey in try await HotkeyListener.events(hotkey: hotkey) },
  )
}

extension DependencyValues {
  var hotkeyListener: HotkeyListenerClient {
    get { self[HotkeyListenerClient.self] }
    set { self[HotkeyListenerClient.self] = newValue }
  }
}
