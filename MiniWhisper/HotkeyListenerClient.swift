import ComposableArchitecture
import HotkeyListener

@DependencyClient struct HotkeyListenerClient: Sendable {
  var events: @Sendable () async throws -> AsyncStream<HotkeyListenerEvent>
  var eventsWithoutPrompting: @Sendable () async throws -> AsyncStream<HotkeyListenerEvent>
}

extension HotkeyListenerClient: DependencyKey {
  static let liveValue = Self(
    events: {
      let settings = try SettingsStore().load()
      return try await HotkeyListener.events(hotkey: settings.hotkey)
    },
    eventsWithoutPrompting: {
      let settings = try SettingsStore().load()
      return try await HotkeyListener.eventsWithoutPrompting(hotkey: settings.hotkey)
    })
}

extension DependencyValues {
  var hotkeyListener: HotkeyListenerClient {
    get { self[HotkeyListenerClient.self] }
    set { self[HotkeyListenerClient.self] = newValue }
  }
}
