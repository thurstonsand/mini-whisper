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

    await store.send(.pressRequested) { $0.recordingTarget = .existing(1) }
    await store.receive(.delegate(.recordingStarted))
  }

  @Test func `press sets an empty binding`() async {
    let store = TestStore(initialState: makeState(hotkeys: [])) { SettingsPaneFeature() }

    await store.send(.pressRequested) { $0.recordingTarget = .new }
    await store.receive(.delegate(.recordingStarted))
  }

  @Test func `recording replaces a binding on commit`() async throws {
    let (events, continuation) = AsyncStream.makeStream(of: HotkeyRecorderEvent.self)
    let replacement = try Hotkey(keyCode: 15, modifiers: [.rightControl])
    let store = TestStore(initialState: makeState()) { SettingsPaneFeature() } withDependencies: {
      $0.hotkeyListener.record = { events }
    }

    await store.send(.bindingTapped(0)) { $0.recordingTarget = .existing(0) }
    await store.receive(.delegate(.recordingStarted))
    await store.send(.recorderReady)
    continuation.yield(
      .chordChanged(HotkeyRecordingChord(keyCodes: [15], modifiers: [.rightControl])),
    )
    await store.receive(
      .recorderEvent(
        .chordChanged(HotkeyRecordingChord(keyCodes: [15], modifiers: [.rightControl])),
      ),
    ) {
      $0.liveChord = HotkeyRecordingChord(keyCodes: [15], modifiers: [.rightControl])
    }
    continuation.yield(.committed(replacement))
    await store.receive(.recorderEvent(.committed(replacement))) {
      $0.$settings.withLock { $0.hotkeys = [replacement] }
      $0.recordingTarget = nil
      $0.liveChord = nil
    }
    await store.receive(.delegate(.recordingStopped))
    continuation.finish()
    await store.receive(.recorderFinished)
  }

  @Test func `add and remove mutate the ordered bindings`() async throws {
    let added = try Hotkey(keyCode: 0, modifiers: [.leftCommand])
    let state = makeState()
    let store = TestStore(initialState: state) { SettingsPaneFeature() }

    await store.send(.addTapped) { $0.recordingTarget = .new }
    await store.receive(.delegate(.recordingStarted))
    await store.send(.recorderEvent(.committed(added))) {
      $0.$settings.withLock { $0.hotkeys.append(added) }
      $0.recordingTarget = nil
    }
    await store.receive(.delegate(.recordingStopped))
    await store.send(.removeTapped(0)) {
      $0.$settings.withLock { _ = $0.hotkeys.remove(at: 0) }
    }
    await store.receive(.delegate(.bindingsChanged))
    #expect(store.state.settings.hotkeys == [added])
  }

  @Test func `adding an existing binding commits as A no-op`() async {
    let store = TestStore(initialState: makeState()) { SettingsPaneFeature() }

    await store.send(.addTapped) { $0.recordingTarget = .new }
    await store.receive(.delegate(.recordingStarted))
    await store.send(.recorderEvent(.committed(.rightOption))) {
      $0.recordingTarget = nil
    }
    await store.receive(.delegate(.recordingStopped))
    #expect(store.state.settings.hotkeys == [.rightOption])
  }

  @Test func `a missing replacement target drops the commit safely`() async throws {
    var state = makeState()
    state.recordingTarget = .existing(7)
    let replacement = try Hotkey(keyCode: 15, modifiers: [.rightControl])
    let store = TestStore(initialState: state) { SettingsPaneFeature() }

    await store.send(.recorderEvent(.committed(replacement))) {
      $0.recordingTarget = nil
    }
    await store.receive(.delegate(.recordingStopped))
    #expect(store.state.settings.hotkeys == [.rightOption])
  }

  @Test func `escape cancellation preserves bindings`() async {
    let store = TestStore(initialState: makeState()) { SettingsPaneFeature() }

    await store.send(.bindingTapped(0)) { $0.recordingTarget = .existing(0) }
    await store.receive(.delegate(.recordingStarted))
    await store.send(.cancelRecording) { $0.recordingTarget = nil }
    await store.receive(.delegate(.recordingStopped))
    #expect(store.state.settings.hotkeys == [.rightOption])
  }

  @Test func `invalid chords show why and remain recording`() async {
    let store = TestStore(initialState: makeState()) { SettingsPaneFeature() }

    await store.send(.addTapped) { $0.recordingTarget = .new }
    await store.receive(.delegate(.recordingStarted))
    await store.send(.recorderEvent(.validationFailed(.multipleKeys))) {
      $0.validationMessage = "Use at most one non-modifier key."
    }
    #expect(store.state.recordingTarget == .new)
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

    await store.send(.removeTapped(1)) {
      $0.$settings.withLock { $0.hotkeys = [.rightOption] }
      $0.cursor.target = 0
    }
    await store.receive(.delegate(.bindingsChanged))
    #expect(store.state.cursorTarget == .binding(0))

    await store.send(.removeTapped(0)) {
      $0.$settings.withLock { $0.hotkeys = [] }
    }
    await store.receive(.delegate(.bindingsChanged))
    #expect(store.state.cursorTarget == .set)
  }

  @Test func `A new binding is recorded in its own chip rather than the set button`() async {
    let store = TestStore(initialState: makeState()) { SettingsPaneFeature() }

    await store.send(.addTapped) { $0.recordingTarget = .new }
    await store.receive(.delegate(.recordingStarted))
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
