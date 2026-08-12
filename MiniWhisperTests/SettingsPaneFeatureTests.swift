import AppSettings
import ASREngine
import AudioCapture
import ComposableArchitecture
import Dictionary
import Foundation
import History
import HotkeyListener
@testable import MiniWhisper
import Testing

// MARK: - SettingsPaneFeatureTests

@MainActor struct SettingsPaneFeatureTests {
  // MARK: Internal

  @Test func `focused detail always paints A row and keyboard mode also paints its target`() async {
    let store = TestStore(initialState: makeWindowState()) { SettingsWindowFeature() }

    await store.send(.focusChanged(.detail)) { $0.interaction.focus = .detail }
    #expect(store.state.showsSettingsBar(.shortcut(.activate)))
    #expect(
      !store.state.showsSettingsRing(
        .shortcut(.activate), target: .binding(.activate, 0),
      ),
    )

    await store.send(.keyboardModeEntered) { $0.interaction.mode = .keyboard }
    #expect(store.state.showsSettingsBar(.shortcut(.activate)))
    #expect(
      store.state.showsSettingsRing(
        .shortcut(.activate), target: .binding(.activate, 0),
      ),
    )

    await store.send(.focusChanged(.sidebar)) { $0.interaction.focus = .sidebar }
    #expect(!store.state.showsSettingsBar(.shortcut(.activate)))
    await store.send(.focusChanged(.detail)) { $0.interaction.focus = .detail }
    #expect(store.state.showsSettingsBar(.shortcut(.activate)))

    await store.send(.pointerMoved) { $0.interaction.mode = .mouse }
    #expect(store.state.showsSettingsBar(.shortcut(.activate)))
    #expect(
      !store.state.showsSettingsRing(
        .shortcut(.activate), target: .binding(.activate, 0),
      ),
    )
  }

  @Test func `target movement clamps and left ascends past the first target`() async throws {
    let second = try Hotkey(keyCode: 15, modifiers: [.rightControl])
    let store = TestStore(initialState: makeState(hotkeys: [.testRightOption, second])) {
      SettingsPaneFeature()
    }

    await store.send(.rightPressed) { $0.cursor.target = 1 }
    await store.send(.rightPressed)
    await store.send(.leftPressed) { $0.cursor.target = 0 }
    await store.send(.leftPressed)
  }

  @Test func `row movement resets the target to the first control`() async throws {
    let second = try Hotkey(keyCode: 15, modifiers: [.rightControl])
    var state = makeState(hotkeys: [.testRightOption, second])
    state.cursor.target = 1
    let store = TestStore(initialState: state) { SettingsPaneFeature() }

    await store.send(.rowMoved(.next)) {
      $0.cursor.row = .shortcut(.pasteLastTranscript)
      $0.cursor.target = 0
    }
    await store.send(.rightPressed)
    await store.send(.rowMoved(.previous)) { $0.cursor.row = .shortcut(.activate) }
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
      $0.launchAtLogin.isRegistered = { false }
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
      $0.launchAtLogin.isRegistered = { false }
    }

    await store.send(.task)
    await store.receive(.soundNamesLoaded([]))
    await store.receive(.inputLevelUpdated(nil))
    await store.finish()
    #expect(store.state.inputLevel == nil)
  }

  @Test func `microphone row joins keyboard movement and Return activation`() async {
    let store = TestStore(initialState: makeState()) { SettingsPaneFeature() }

    await store.send(.rowMoved(.next)) {
      $0.cursor.row = .shortcut(.pasteLastTranscript)
    }
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
      initialState: SettingsPaneFeature.State(
        settings: Shared(value: settings),
        health: Shared(value: .healthy),
      ),
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
      $0.$settings.withLock { $0.microphone = selection }
    }
    await store.receive(.delegate(.microphoneChanged(selection)))
    await store.receive(.inputLevelUpdated(nil))
  }

  /// Re-picking the entry that stands in for an absent device must not be mistaken for a change.
  @Test func `reselecting the current microphone changes nothing`() async {
    var settings = MiniWhisperSettings.defaults
    settings.microphone = .device(uid: "missing", lastKnownName: "Studio Microphone")
    let store = TestStore(
      initialState: SettingsPaneFeature.State(
        settings: Shared(value: settings),
        health: Shared(value: .healthy),
      ),
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

    await store.send(.rowMoved(.next)) {
      $0.cursor.row = .shortcut(.pasteLastTranscript)
    }
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
    await store.send(.rowMoved(.next)) { $0.cursor.row = .launchAtLogin }
    await store.send(.rowMoved(.next))
  }

  @Test func `launch at login joins movement and Return flips it`() async {
    let registered = Collector<Bool>()
    var state = makeState()
    state.cursor.row = .sound(.error)
    let store = TestStore(initialState: state) { SettingsPaneFeature() } withDependencies: {
      $0.launchAtLogin.setRegistered = { registered.append($0) }
      $0.launchAtLogin.isRegistered = { registered.last ?? false }
    }

    await store.send(.rowMoved(.next)) { $0.cursor.row = .launchAtLogin }
    #expect(store.state.cursorTarget == .launchAtLogin)
    await store.send(.pressRequested)
    await store.receive(.launchAtLoginToggled(true))
    await store.receive(.launchAtLoginUpdated(true)) { $0.launchAtLoginRegistered = true }
    #expect(registered.values == [true])
  }

  @Test func `a refused login item registration leaves the toggle where it was`() async {
    let store = TestStore(initialState: makeState()) { SettingsPaneFeature() } withDependencies: {
      $0.launchAtLogin.setRegistered = { _ in throw LaunchAtLoginFailure() }
      $0.launchAtLogin.isRegistered = { false }
    }

    await store.send(.launchAtLoginToggled(true))
    await store.receive(
      SettingsPaneFeature.Action.launchAtLoginFailed("the login item was refused"),
    )
    await store.receive(.launchAtLoginUpdated(false))
    #expect(!store.state.launchAtLoginRegistered)
  }

  @Test func `opening the pane reads the login item back`() async {
    let store = TestStore(initialState: makeState()) { SettingsPaneFeature() } withDependencies: {
      $0.audioInputDevices.snapshots = { AsyncStream { $0.finish() } }
      $0.audioInputLevels.levels = { _ in AsyncStream { $0.finish() } }
      $0.launchAtLogin.isRegistered = { true }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.task) { $0.launchAtLoginRegistered = true }
  }

  @Test func `repair rows pin to the top and each delegates its own door`() async {
    let state = makeState(
      health: AppHealth(micStatus: .denied, engineReadiness: .failed("nope")),
    )
    let store = TestStore(initialState: state) { SettingsPaneFeature() }

    #expect(store.state.rows.first == .repair(.accessibilityDenied))
    #expect(store.state.cursorRow == .repair(.accessibilityDenied))
    await store.send(.pressRequested)
    await store.receive(.repairTapped(.accessibilityDenied))
    await store.receive(.delegate(.repair(.accessibilityDenied)))
    await store.send(.rowMoved(.next)) { $0.cursor.row = .repair(.microphoneAccessDenied) }
    await store.send(.rowMoved(.next)) { $0.cursor.row = .repair(.modelSetupFailed) }
    await store.send(.pressRequested)
    await store.receive(.repairTapped(.modelSetupFailed))
    await store.receive(.delegate(.repair(.modelSetupFailed)))
  }

  @Test func `A healthy app contributes no repair rows`() {
    #expect(makeState().health.degradations.isEmpty)
    #expect(!makeState().rows.contains {
      if case .repair = $0 {
        true
      } else {
        false
      }
    })
  }

  @Test func `a repaired permission moves the cursor off the row that is gone`() {
    var state = makeState(health: AppHealth(
      micStatus: .denied, accessibilityGranted: true, engineReadiness: .ready,
    ))
    state.cursor = SettingsPaneFeature.Cursor(row: .repair(.microphoneAccessDenied))

    state.$health.withLock { $0.micStatus = .granted }

    #expect(state.health.degradations.isEmpty)
    #expect(state.cursorRow == .shortcut(.activate))
    #expect(state.cursorTarget == .binding(.activate, 0))
  }

  @Test func `choosing A sound commits it and plays it once`() async {
    let sounds = SoundRecorder()
    let store = TestStore(initialState: makeState()) { SettingsPaneFeature() } withDependencies: {
      $0.sounds.play = { name in await sounds.record(name) }
    }

    await store.send(.soundSelected(.complete, "Glass")) {
      $0.$settings.withLock { $0.sounds.complete = "Glass" }
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
      $0.$settings.withLock { $0.sounds.cancel = nil }
    }
    await store.send(.soundReplayRequested(.cancel))
    #expect(await sounds.recorded.isEmpty)
  }

  @Test func `press records the selected binding`() async throws {
    let second = try Hotkey(keyCode: 15, modifiers: [.rightControl])
    var state = makeState(hotkeys: [.testRightOption, second])
    state.cursor.target = 1
    let store = TestStore(initialState: state) { SettingsPaneFeature() }

    await store.send(.pressRequested)
    await store.receive(bindingAction(.activate, .bindingTapped(1))) {
      $0.bindingEditors[id: .activate]?.$recordingCommand.withLock { $0 = .activate }
      $0.bindingEditors[id: .activate]?.target = .existing(1)
    }
    await store.receive(bindingAction(.activate, .delegate(.recordingStarted)))
  }

  @Test func `press records the paste last binding through its own child`() async {
    var state = makeState()
    state.cursor.row = .shortcut(.pasteLastTranscript)
    let store = TestStore(initialState: state) { SettingsPaneFeature() }

    await store.send(.pressRequested)
    await store.receive(bindingAction(.pasteLastTranscript, .bindingTapped(0))) {
      $0.bindingEditors[id: .pasteLastTranscript]?.$recordingCommand.withLock {
        $0 = .pasteLastTranscript
      }
      $0.bindingEditors[id: .pasteLastTranscript]?.target = .existing(0)
    }
    await store.receive(bindingAction(.pasteLastTranscript, .delegate(.recordingStarted)))
  }

  @Test func `another shortcut cannot record while one is already recording`() async {
    var state = makeState()
    state.cursor.row = .shortcut(.pasteLastTranscript)
    let store = TestStore(initialState: state) { SettingsPaneFeature() }

    await store.send(bindingAction(.activate, .bindingTapped(0))) {
      $0.bindingEditors[id: .activate]?.$recordingCommand.withLock { $0 = .activate }
      $0.bindingEditors[id: .activate]?.target = .existing(0)
    }
    await store.receive(bindingAction(.activate, .delegate(.recordingStarted)))
    await store.send(.pressRequested)
    await store.receive(bindingAction(.pasteLastTranscript, .bindingTapped(0)))
    #expect(store.state.bindingEditors[id: .pasteLastTranscript]?.target == nil)

    await store.send(bindingAction(.activate, .cancelRecording)) {
      $0.bindingEditors[id: .activate]?.$recordingCommand.withLock { $0 = nil }
      $0.bindingEditors[id: .activate]?.target = nil
    }
    await store.receive(bindingAction(.activate, .delegate(.recordingStopped)))
  }

  @Test func `press sets an empty binding`() async {
    let store = TestStore(initialState: makeState(hotkeys: [])) { SettingsPaneFeature() }

    await store.send(.pressRequested)
    await store.receive(bindingAction(.activate, .addTapped)) {
      $0.bindingEditors[id: .activate]?.$recordingCommand.withLock { $0 = .activate }
      $0.bindingEditors[id: .activate]?.target = .new
    }
    await store.receive(bindingAction(.activate, .delegate(.recordingStarted)))
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
    var state = makeState(hotkeys: [.testRightOption, second])
    state.cursor.target = 1
    let store = TestStore(initialState: state) { SettingsPaneFeature() }

    await store.send(bindingAction(.activate, .removeTapped(1))) {
      $0.$settings.withLock { $0.bindings.set([.testRightOption], for: .activate) }
    }
    await store.receive(bindingAction(.activate, .delegate(.bindingsChanged))) {
      $0.cursor.target = 0
    }
    #expect(store.state.cursorTarget == .binding(.activate, 0))

    await store.send(bindingAction(.activate, .removeTapped(0))) {
      $0.$settings.withLock { $0.bindings.set([], for: .activate) }
    }
    await store.receive(bindingAction(.activate, .delegate(.bindingsChanged)))
    #expect(store.state.cursorTarget == .set(.activate))
  }

  @Test func `A new binding is recorded in its own chip rather than the set button`() async {
    let store = TestStore(initialState: makeState()) { SettingsPaneFeature() }

    await store.send(bindingAction(.activate, .addTapped)) {
      $0.bindingEditors[id: .activate]?.$recordingCommand.withLock { $0 = .activate }
      $0.bindingEditors[id: .activate]?.target = .new
    }
    await store.receive(bindingAction(.activate, .delegate(.recordingStarted)))
    #expect(store.state.targets == [.binding(.activate, 0), .recording(.activate)])
  }

  // MARK: Private

  private func makeState(
    hotkeys: [Hotkey] = [.testRightOption],
    health: AppHealth = .healthy,
  ) -> SettingsPaneFeature.State {
    var settings = MiniWhisperSettings.defaults
    settings.bindings.set(hotkeys, for: .activate)
    return SettingsPaneFeature.State(
      settings: Shared(value: settings), health: Shared(value: health),
    )
  }

  private func bindingAction(
    _ command: HotkeyCommand, _ action: HotkeyBindingsFeature.Action,
  ) -> SettingsPaneFeature.Action {
    .bindingEditors(.element(id: command, action: action))
  }

  private func makeWindowState() -> SettingsWindowFeature.State {
    SettingsWindowFeature.State(
      history: Shared(value: HistoryLog()), settings: Shared(value: .defaults),
      dictionary: Shared(value: .empty), health: Shared(value: .healthy),
    )
  }
}

// MARK: - LaunchAtLoginFailure

private struct LaunchAtLoginFailure: LocalizedError {
  var errorDescription: String? {
    "the login item was refused"
  }
}

// MARK: - Collector

private final class Collector<Value: Sendable>: @unchecked Sendable {
  // MARK: Internal

  var values: [Value] {
    lock.withLock { storage }
  }

  var last: Value? {
    lock.withLock { storage.last }
  }

  func append(_ value: Value) {
    lock.withLock { storage.append(value) }
  }

  // MARK: Private

  private let lock = NSLock()
  private var storage: [Value] = []
}
