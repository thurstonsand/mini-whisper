import AppSettings
import AudioCapture
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

    await store.send(.rowMoved(.next)) {
      $0.cursor.row = .microphone
      $0.cursor.target = 0
    }
    await store.send(.rightPressed)
    await store.send(.rowMoved(.previous)) { $0.cursor.row = .activate }
    await store.send(.rightPressed) { $0.cursor.target = 1 }
  }

  @Test func `both listeners live and die with the pane`() async {
    let (levels, continuation) = AsyncStream.makeStream(of: AudioLevel.self)
    let (snapshots, snapshotContinuation) = AsyncStream
      .makeStream(of: AudioInputDeviceSnapshot.self)
    let store = TestStore(initialState: makeState()) { SettingsPaneFeature() } withDependencies: {
      $0.audioInputDevices.snapshots = { snapshots }
      $0.audioInputLevels.levels = { selection in
        #expect(selection == .systemDefault)
        return levels
      }
    }
    let level = AudioLevel(decibels: -36, normalizedPower: 0.4)
    let builtIn = AudioInputDevice(uid: "built-in", name: "Built-in Microphone")
    let snapshot = AudioInputDeviceSnapshot(devices: [builtIn], defaultDevice: builtIn)

    await store.send(.task)
    await store.receive(.soundNamesLoaded([]))
    continuation.yield(level)
    await store.receive(.inputLevelUpdated(level)) { $0.inputLevel = level }
    snapshotContinuation.yield(snapshot)
    await store.receive(.inputDevicesUpdated(snapshot)) { $0.inputDevices = snapshot }

    await store.send(.paneClosed) { $0.inputLevel = nil }
    await store.finish()
  }

  @Test func `a monitor that cannot start remains inactive`() async {
    let store = TestStore(initialState: makeState()) { SettingsPaneFeature() } withDependencies: {
      $0.audioInputDevices.snapshots = { AsyncStream { $0.finish() } }
      $0.audioInputLevels.levels = { _ in AsyncStream { $0.finish() } }
    }

    await store.send(.task)
    await store.receive(.soundNamesLoaded([]))
    await store.receive(.inputLevelUpdated(nil))
    await store.finish()
    #expect(store.state.inputLevel == nil)
  }

  @Test func `microphone row joins keyboard movement and Return activation`() async {
    let store = TestStore(initialState: makeState()) { SettingsPaneFeature() }

    await store.send(.rowMoved(.next)) { $0.cursor.row = .microphone }
    #expect(store.state.cursorTarget == .microphone)
    await store.send(.pressRequested) { $0.microphoneActivation = 1 }
    await store.send(.leftPressed)
    #expect(store.state.cursorTarget == .microphone)
  }

  @Test func `absent microphone remains selected and reports the current fallback`() async {
    var settings = MiniWhisperSettings.defaults
    settings.microphone = .device(uid: "missing", lastKnownName: "Studio Microphone")
    let store = TestStore(
      initialState: SettingsPaneFeature.State(settings: Shared(value: settings)),
    ) { SettingsPaneFeature() }
    let builtIn = AudioInputDevice(uid: "built-in", name: "MacBook Pro Microphone")
    let snapshot = AudioInputDeviceSnapshot(devices: [builtIn], defaultDevice: builtIn)

    await store.send(.inputDevicesUpdated(snapshot)) { $0.inputDevices = snapshot }

    #expect(store.state.unavailableMicrophoneName == "Studio Microphone")
    #expect(store.state.microphone == settings.microphone)

    let returned = AudioInputDevice(uid: "missing", name: "Studio Microphone")
    let reconnected = AudioInputDeviceSnapshot(
      devices: [builtIn, returned], defaultDevice: builtIn,
    )
    await store.send(.inputDevicesUpdated(reconnected)) { $0.inputDevices = reconnected }
    await store.receive(.delegate(.microphoneChanged(settings.microphone)))
    await store.receive(.inputLevelUpdated(nil))
    #expect(store.state.unavailableMicrophoneName == nil)
  }

  @Test func `choosing A device persists its identity and rebinds the meter`() async {
    let studio = AudioInputDevice(uid: "studio", name: "Studio Microphone")
    let store = TestStore(initialState: makeState()) { SettingsPaneFeature() } withDependencies: {
      $0.audioInputLevels.levels = { selection in
        #expect(selection == .device(uid: studio.uid, lastKnownName: studio.name))
        return AsyncStream { $0.finish() }
      }
    }
    let snapshot = AudioInputDeviceSnapshot(devices: [studio], defaultDevice: studio)
    await store.send(.inputDevicesUpdated(snapshot)) { $0.inputDevices = snapshot }

    let selection = MicrophoneSelection.device(uid: studio.uid, lastKnownName: studio.name)
    await store.send(.microphoneSelected(selection)) {
      $0.bindings.$settings.withLock { $0.microphone = selection }
    }
    await store.receive(.delegate(.microphoneChanged(selection)))
    await store.receive(.inputLevelUpdated(nil))
  }

  /// Re-picking the entry that stands in for an absent device must not be mistaken for a change.
  @Test func `reselecting the current microphone changes nothing`() async {
    var settings = MiniWhisperSettings.defaults
    settings.microphone = .device(uid: "missing", lastKnownName: "Studio Microphone")
    let store = TestStore(
      initialState: SettingsPaneFeature.State(settings: Shared(value: settings)),
    ) { SettingsPaneFeature() }

    await store.send(.microphoneSelected(settings.microphone))
    await store.finish()
  }

  @Test func `an observed default change refreshes prewarm while the pane is open`() async {
    let store = TestStore(initialState: makeState()) { SettingsPaneFeature() }
    let builtIn = AudioInputDevice(uid: "built-in", name: "Built-in Microphone")
    let studio = AudioInputDevice(uid: "studio", name: "Studio Microphone")
    let initial = AudioInputDeviceSnapshot(devices: [builtIn, studio], defaultDevice: builtIn)
    let changed = AudioInputDeviceSnapshot(devices: [builtIn, studio], defaultDevice: studio)

    await store.send(.inputDevicesUpdated(initial)) { $0.inputDevices = initial }
    await store.send(.inputDevicesUpdated(changed)) { $0.inputDevices = changed }
    await store.receive(.delegate(.microphoneChanged(.systemDefault)))
    await store.receive(.inputLevelUpdated(nil))
  }

  @Test func `sound rows join movement with popup and preview targets`() async {
    let store = TestStore(initialState: makeState()) { SettingsPaneFeature() }

    await store.send(.rowMoved(.next)) { $0.cursor.row = .microphone }
    await store.send(.rowMoved(.next)) { $0.cursor.row = .sound(.activate) }
    #expect(store.state.cursorTarget == .soundPicker(.activate))
    await store.send(.leftPressed)
    await store.send(.pressRequested) { $0.soundActivations[.activate] = 1 }
    await store.send(.rightPressed) { $0.cursor.target = 1 }
    #expect(store.state.cursorTarget == .soundPreview(.activate))
    await store.send(.rowMoved(.next)) {
      $0.cursor.row = .sound(.complete)
      $0.cursor.target = 0
    }
    await store.send(.rowMoved(.next)) { $0.cursor.row = .sound(.cancel) }
    await store.send(.rowMoved(.next)) { $0.cursor.row = .sound(.error) }
    await store.send(.rowMoved(.next))
  }

  @Test func `choosing A sound commits it and plays it once`() async {
    let sounds = SoundRecorder()
    let store = TestStore(initialState: makeState()) { SettingsPaneFeature() } withDependencies: {
      $0.sounds.play = { name in await sounds.record(name) }
    }

    await store.send(.soundSelected(.complete, "Glass")) {
      $0.bindings.$settings.withLock { $0.sounds.complete = "Glass" }
    }
    await store.receive(.soundPlaybackCompleted("Glass")) { $0.lastPlayedSound = "Glass" }
    #expect(await sounds.recorded == ["Glass"])
  }

  @Test func `preview replays the selected sound`() async {
    let sounds = SoundRecorder()
    let store = TestStore(initialState: makeState()) { SettingsPaneFeature() } withDependencies: {
      $0.sounds.play = { name in await sounds.record(name) }
    }

    await store.send(.soundReplayRequested(.activate))
    await store.receive(.soundPlaybackCompleted("Tink")) { $0.lastPlayedSound = "Tink" }
    #expect(await sounds.recorded == ["Tink"])
  }

  @Test func `replaying the same sound is never deduplicated`() async {
    let sounds = SoundRecorder()
    let store = TestStore(initialState: makeState()) { SettingsPaneFeature() } withDependencies: {
      $0.sounds.play = { name in await sounds.record(name) }
    }

    await store.send(.soundReplayRequested(.activate))
    await store.receive(.soundPlaybackCompleted("Tink")) { $0.lastPlayedSound = "Tink" }
    await store.send(.soundReplayRequested(.activate))
    await store.receive(.soundPlaybackCompleted("Tink"))
    #expect(await sounds.recorded == ["Tink", "Tink"])
  }

  @Test func `choosing No audio commits silence without playback`() async {
    let sounds = SoundRecorder()
    let store = TestStore(initialState: makeState()) { SettingsPaneFeature() } withDependencies: {
      $0.sounds.play = { name in await sounds.record(name) }
    }

    await store.send(.soundSelected(.cancel, nil)) {
      $0.bindings.$settings.withLock { $0.sounds.cancel = nil }
    }
    await store.send(.soundReplayRequested(.cancel))
    #expect(await sounds.recorded.isEmpty)
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

  @Test func `hover moves the single row cursor and keyboard movement continues from it`() async {
    var state = makeWindowState()
    state.interaction.focus = .detail
    let store = TestStore(initialState: state) { SettingsWindowFeature() }

    await store.send(.settingsPane(.cursorHovered(.sound(.complete)))) {
      $0.settingsPane.cursor.row = .sound(.complete)
    }
    #expect(store.state.showsSettingsBar(.sound(.complete)))

    await store.send(.keyboardModeEntered) { $0.interaction.mode = .keyboard }
    await store.send(.settingsPane(.rowMoved(.next))) {
      $0.settingsPane.cursor.row = .sound(.cancel)
    }
    #expect(store.state.showsSettingsBar(.sound(.cancel)))
    #expect(store.state.showsSettingsRing(.sound(.cancel), target: .soundPicker(.cancel)))
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
