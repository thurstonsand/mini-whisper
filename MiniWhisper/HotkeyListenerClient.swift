import AppSettings
import ComposableArchitecture
import HotkeyListener

// MARK: - HotkeyListenerClient

@DependencyClient struct HotkeyListenerClient {
  var events: @Sendable ([HotkeyBinding<HotkeyAction>]) async throws
    -> AsyncStream<HotkeyListenerEvent<HotkeyAction>>
  var record: @Sendable () async throws -> AsyncStream<HotkeyRecorderEvent>
  /// Whether Return, wherever the user is typing, ends the live recording and submits it.
  var armSubmitKey: @Sendable (Bool) -> Void
}

// MARK: DependencyKey

extension HotkeyListenerClient: DependencyKey {
  static let liveValue = {
    let submitKey = SubmitKeyGate()
    return Self(
      events: { bindings in
        try await HotkeyListener.events(bindings: bindings, submitKey: submitKey)
      },
      record: { try await HotkeyRecorder.events() },
      armSubmitKey: { submitKey.isArmed = $0 },
    )
  }()

  /// Every recording arms and disarms the key, so tests that never look at it should not have
  /// to say so.
  static let testValue = {
    var client = Self()
    client.armSubmitKey = { _ in }
    return client
  }()
}

extension DependencyValues {
  var hotkeyListener: HotkeyListenerClient {
    get { self[HotkeyListenerClient.self] }
    set { self[HotkeyListenerClient.self] = newValue }
  }
}
