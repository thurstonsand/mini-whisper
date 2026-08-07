import AppSettings
import ComposableArchitecture
import History
import HotkeyListener
@testable import MiniWhisper
import Testing

@MainActor struct SettingsPaneFeatureTests {
  // MARK: Internal

  @Test func `focused detail always paints A row and keyboard mode also paints its target`() async {
    let store = TestStore(initialState: makeWindowState()) { SettingsWindowFeature() }

    await store.send(.focusChanged(.detail)) { $0.interaction.focus = .detail }
    #expect(store.state.showsSettingsBar(.activate))
    #expect(!store.state.showsSettingsRing(.activate, target: .binding(0)))

    await store.send(.keyboardModeEntered) { $0.interaction.mode = .keyboard }
    #expect(store.state.showsSettingsBar(.activate))
    #expect(store.state.showsSettingsRing(.activate, target: .binding(0)))

    await store.send(.focusChanged(.sidebar)) { $0.interaction.focus = .sidebar }
    #expect(!store.state.showsSettingsBar(.activate))
    await store.send(.focusChanged(.detail)) { $0.interaction.focus = .detail }
    #expect(store.state.showsSettingsBar(.activate))

    await store.send(.pointerMoved) { $0.interaction.mode = .mouse }
    #expect(store.state.showsSettingsBar(.activate))
    #expect(!store.state.showsSettingsRing(.activate, target: .binding(0)))
  }

  @Test func `target movement clamps and left ascends past the first target`() async throws {
    let second = try Hotkey(keyCode: 15, modifiers: [.rightControl])
    let store = TestStore(initialState: makeState(hotkeys: [.rightOption, second])) {
      SettingsPaneFeature()
    }

    await store.send(.rightPressed) { $0.cursor.target = 1 }
    await store.send(.rightPressed)
    await store.send(.leftPressed) { $0.cursor.target = 0 }
    await store.send(.leftPressed)
  }

  @Test func `row movement resets the target to the first control`() async throws {
    let second = try Hotkey(keyCode: 15, modifiers: [.rightControl])
    var state = makeState(hotkeys: [.rightOption, second])
    state.cursor.target = 1
    let store = TestStore(initialState: state) { SettingsPaneFeature() }

    await store.send(.rowMoved(.next)) { $0.cursor.target = 0 }
    await store.send(.rightPressed) { $0.cursor.target = 1 }
    await store.send(.rowMoved(.previous)) { $0.cursor.target = 0 }
  }

  @Test func `press records the selected binding`() async throws {
    let second = try Hotkey(keyCode: 15, modifiers: [.rightControl])
    var state = makeState(hotkeys: [.rightOption, second])
    state.cursor.target = 1
    let store = TestStore(initialState: state) { SettingsPaneFeature() }

    await store.send(.pressRequested)
    await store.receive(.bindings(.bindingTapped(1))) { $0.bindings.target = .existing(1) }
    await store.receive(.bindings(.delegate(.recordingStarted)))
  }

  @Test func `press sets an empty binding`() async {
    let store = TestStore(initialState: makeState(hotkeys: [])) { SettingsPaneFeature() }

    await store.send(.pressRequested)
    await store.receive(.bindings(.addTapped)) { $0.bindings.target = .new }
    await store.receive(.bindings(.delegate(.recordingStarted)))
  }

  @Test func `leaving A row hands the bar back to the focused cursor`() async {
    var state = makeWindowState()
    state.interaction.focus = .detail
    let store = TestStore(initialState: state) { SettingsWindowFeature() }

    await store.send(.settingsPane(.rowHovered(.activate))) {
      $0.settingsPane.hoveredRow = .activate
    }
    #expect(store.state.showsSettingsBar(.activate))

    await store.send(.settingsPane(.rowExited(.activate))) {
      $0.settingsPane.hoveredRow = nil
    }
    // The pointer left, so the focused column falls back to its cursor rather than keeping the
    // bar parked on a row the pointer has long since abandoned.
    #expect(store.state.showsSettingsBar(.activate))

    await store.send(.focusChanged(nil)) { $0.interaction.focus = nil }
    #expect(!store.state.showsSettingsBar(.activate))
  }

  @Test func `removing the last binding pulls the cursor back onto the empty state`() async throws {
    let second = try Hotkey(keyCode: 15, modifiers: [.rightControl])
    var state = makeState(hotkeys: [.rightOption, second])
    state.cursor.target = 1
    let store = TestStore(initialState: state) { SettingsPaneFeature() }

    await store.send(.bindings(.removeTapped(1))) {
      $0.bindings.$settings.withLock { $0.hotkeys = [.rightOption] }
    }
    await store.receive(.bindings(.delegate(.bindingsChanged))) { $0.cursor.target = 0 }
    #expect(store.state.cursorTarget == .binding(0))

    await store.send(.bindings(.removeTapped(0))) {
      $0.bindings.$settings.withLock { $0.hotkeys = [] }
    }
    await store.receive(.bindings(.delegate(.bindingsChanged)))
    #expect(store.state.cursorTarget == .set)
  }

  @Test func `A new binding is recorded in its own chip rather than the set button`() async {
    let store = TestStore(initialState: makeState()) { SettingsPaneFeature() }

    await store.send(.bindings(.addTapped)) { $0.bindings.target = .new }
    await store.receive(.bindings(.delegate(.recordingStarted)))
    #expect(store.state.targets == [.binding(0), .recording])
  }

  // MARK: Private

  private func makeState(hotkeys: [Hotkey] = [.rightOption]) -> SettingsPaneFeature.State {
    var settings = MiniWhisperSettings.defaults
    settings.hotkeys = hotkeys
    return SettingsPaneFeature.State(settings: Shared(value: settings))
  }

  private func makeWindowState() -> SettingsWindowFeature.State {
    SettingsWindowFeature.State(
      history: Shared(value: HistoryLog()), settings: Shared(value: .defaults),
    )
  }
}
