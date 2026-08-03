import ComposableArchitecture
import HotkeyListener

// MARK: - HotkeyListenerClient

@DependencyClient struct HotkeyListenerClient {
  var hasInputMonitoringPermission: @Sendable () -> Bool = { false }
  var requestInputMonitoringPermission: @Sendable () async -> Bool = { false }
  var events: @Sendable () async throws -> AsyncStream<HotkeyListenerEvent>
}

// MARK: DependencyKey

extension HotkeyListenerClient: DependencyKey {
  static let liveValue = Self(
    hasInputMonitoringPermission: { HotkeyListener.hasInputMonitoringPermission() },
    requestInputMonitoringPermission: { await HotkeyListener.requestInputMonitoringPermission() },
    events: {
      let settings = try SettingsStore().load()
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
