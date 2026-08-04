import ComposableArchitecture
import HotkeyListener

// MARK: - HotkeyListenerClient

@DependencyClient struct HotkeyListenerClient {
  var events: @Sendable () async throws -> AsyncStream<HotkeyListenerEvent>
}

// MARK: DependencyKey

extension HotkeyListenerClient: DependencyKey {
  static let liveValue = Self(
    events: {
      let settings = try SettingsStore(fileURL: Channel.settingsFile).load()
      return try await HotkeyListener.events(hotkey: settings.hotkey)
    },
  )
}

extension DependencyValues {
  var hotkeyListener: HotkeyListenerClient {
    get { self[HotkeyListenerClient.self] }
    set { self[HotkeyListenerClient.self] = newValue }
  }
}
