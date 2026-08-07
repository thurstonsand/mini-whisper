import AppSettings
import ASREngine
import AudioCapture
import ComposableArchitecture
import Foundation
import HotkeyListener
@testable import MiniWhisper
import ServiceManagement
import Testing

// MARK: - MenuBarDerivationTests

struct MenuBarDerivationTests {
  // MARK: Internal

  @Test func `healthy shows the static mic and the passive status line`() {
    let state = viewState()

    #expect(state.degradation == nil)
    #expect(state.iconSymbolName == "mic")
    #expect(state.statusText == "Ready · Parakeet v2 · Shure MV7")
    #expect(state.accessibilityStatusText == "Ready; Parakeet v2; Shure MV7")
    #expect(state.repair == nil)
    #expect(state.repairTitle == nil)
  }

  @Test func `model setup progress is not degraded`() {
    for readiness in [EngineReadiness.downloading(0.42), .compiling, .prewarming] {
      let state = viewState(engineReadiness: readiness)
      #expect(state.degradation == nil)
      #expect(state.iconSymbolName == "mic")
    }
    let downloading = viewState(engineReadiness: .downloading(0.42))
    #expect(downloading.statusText == "Downloading Parakeet v2 · 42% · Shure MV7")
    #expect(downloading.accessibilityStatusText == "Downloading Parakeet v2; 42%; Shure MV7")
  }

  @Test func `a tap without accessibility degrades to the settings deep link`() {
    let state = viewState(hotkeyTap: .accessibilityMissing, accessibilityGranted: false)

    #expect(state.degradation == .accessibilityDenied)
    #expect(state.iconSymbolName == "mic.slash")
    #expect(
      state
        .statusText == "Accessibility is off, so the hotkey and pasting can't work · switch it on",
    )
    #expect(
      state.accessibilityStatusText
        == "Accessibility is off, so the hotkey and pasting can't work; switch it on",
    )
    #expect(state.repair == .openAccessibilitySettings)
    #expect(state.repairTitle == "Open Accessibility Settings…")
  }

  @Test func `dead event tap degrades to A restart`() {
    let state = viewState(hotkeyTap: .dead)

    #expect(state.degradation == .hotkeyTapDead)
    #expect(state.statusText == "Hotkey listening stopped")
    #expect(state.repair == .restartHotkeyListening)
  }

  @Test(arguments: [MicPermissionStatus.denied, .restricted, .unknown])
  func `blocked microphone degrades to the settings deep link`(status: MicPermissionStatus) {
    let state = viewState(micStatus: status)

    #expect(state.degradation == .microphoneAccessDenied)
    #expect(state.statusText == "Microphone access is off, so nothing can be recorded")
    #expect(state.repair == .openMicrophoneSettings)
  }

  @Test func `an unrequested microphone is left to onboarding`() {
    #expect(viewState(micStatus: .undetermined).degradation == nil)
  }

  @Test func `a revoked accessibility grant degrades even while the tap still runs`() {
    let state = viewState(accessibilityGranted: false)

    #expect(state.degradation == .accessibilityDenied)
    #expect(state.repair == .openAccessibilitySettings)
  }

  @Test func `a revoked grant outranks the dead tap it caused`() {
    let revoked = viewState(hotkeyTap: .dead, accessibilityGranted: false)
    #expect(revoked.degradation == .accessibilityDenied)
    #expect(revoked.repair == .openAccessibilitySettings)

    let died = viewState(hotkeyTap: .dead)
    #expect(died.degradation == .hotkeyTapDead)
    #expect(died.repair == .restartHotkeyListening)
  }

  @Test func `missing model degrades to setup`() {
    let state = viewState(engineReadiness: .modelMissing)

    #expect(state.degradation == .modelMissing)
    #expect(state.statusText == "Parakeet v2 isn't installed yet")
    #expect(state.repair == .installModel)
    #expect(state.repairTitle == "Download & Prepare Parakeet v2…")
  }

  @Test func `failed model setup degrades to A retry`() {
    let state = viewState(engineReadiness: .failed("compile crashed"))

    #expect(state.degradation == .modelSetupFailed)
    #expect(state.repair == .retryModelSetup)
    #expect(state.repairTitle == "Retry Parakeet v2 Setup…")
  }

  @Test func `the hotkey pipeline outranks the microphone and the model`() {
    #expect(
      viewState(
        hotkeyTap: .accessibilityMissing, micStatus: .denied, engineReadiness: .modelMissing,
        accessibilityGranted: false,
      ).degradation == .accessibilityDenied,
    )
    #expect(
      viewState(hotkeyTap: .dead, micStatus: .denied, engineReadiness: .failed("boom")).degradation
        == .hotkeyTapDead,
    )
    #expect(
      viewState(micStatus: .denied, engineReadiness: .modelMissing).degradation
        == .microphoneAccessDenied,
    )
  }

  @Test func `repairing every failure returns the healthy icon`() {
    var state = viewState(
      hotkeyTap: .accessibilityMissing, micStatus: .denied, engineReadiness: .modelMissing,
      accessibilityGranted: false,
    )
    #expect(state.degradation == .accessibilityDenied)

    state = viewState(hotkeyTap: .active, micStatus: .denied, engineReadiness: .modelMissing)
    #expect(state.degradation == .microphoneAccessDenied)

    state = viewState(hotkeyTap: .active, micStatus: .granted, engineReadiness: .modelMissing)
    #expect(state.degradation == .modelMissing)

    state = viewState(hotkeyTap: .active, micStatus: .granted, engineReadiness: .ready)
    #expect(state.degradation == nil)
    #expect(state.iconSymbolName == "mic")
    #expect(state.statusText == "Ready · Parakeet v2 · Shure MV7")
  }

  @Test func `a missing input device is named in the status line`() {
    #expect(viewState(inputDeviceName: nil).statusText == "Ready · Parakeet v2 · No input device")
  }

  @Test func `the toggle and transcript state are passed through`() {
    let state = viewState(
      hasLastTranscript: true, soundsEnabled: false, launchAtLoginRegistered: true,
    )

    #expect(state.canCopyLastTranscript)
    #expect(!state.soundsEnabled)
    #expect(state.launchAtLoginRegistered)
  }

  // MARK: Private

  private func viewState(
    hotkeyTap: HotkeyTapStatus = .active, micStatus: MicPermissionStatus = .granted,
    engineReadiness: EngineReadiness = .ready, accessibilityGranted: Bool = true,
    inputDeviceName: String? = "Shure MV7", hasLastTranscript: Bool = false,
    soundsEnabled: Bool = true, launchAtLoginRegistered: Bool = false,
  ) -> MenuBarViewState {
    MenuBarViewState(
      hotkeyTap: hotkeyTap, micStatus: micStatus, accessibilityGranted: accessibilityGranted,
      engineReadiness: engineReadiness, inputDeviceName: inputDeviceName,
      hasLastTranscript: hasLastTranscript, soundsEnabled: soundsEnabled,
      launchAtLoginRegistered: launchAtLoginRegistered,
    )
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

// MARK: - MenuActionFailure

private struct MenuActionFailure: LocalizedError {
  var errorDescription: String? {
    "menu action failed"
  }
}

// MARK: - MenuBarActionTests

@MainActor struct MenuBarActionTests {
  @Test func `opening the menu refreshes the device and the login item`() async {
    var state = AppFeature.State()
    state.onboardingCompleted = true
    state.hotkeyTap = .active
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.audioCapture.currentInputDeviceName = { _ in "Shure MV7" }
      $0.accessibilityPermission.hasPermission = { true }
      $0.launchAtLogin.isRegistered = { true }
    }

    await store.send(.menuWillOpen) {
      $0.inputDeviceName = "Shure MV7"
      $0.launchAtLoginRegistered = true
      $0.accessibilityGranted = true
    }
  }

  @Test func `opening the menu recovers A grant made while the app ran`() async {
    let (events, continuation) = AsyncStream.makeStream(of: HotkeyListenerEvent.self)
    var state = AppFeature.State()
    state.onboardingCompleted = true
    state.hotkeyTap = .accessibilityMissing
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.accessibilityPermission.hasPermission = { true }
      $0.audioCapture.currentInputDeviceName = { _ in "Shure MV7" }
      $0.hotkeyListener.events = { _ in events }
      $0.launchAtLogin.isRegistered = { false }
    }

    await store.send(.menuWillOpen) {
      $0.inputDeviceName = "Shure MV7"
      $0.accessibilityGranted = true
      $0.hotkeyTap = .starting
    }
    continuation.yield(.monitoringStarted)
    await store.receive(.hotkeyListenerEvent(.monitoringStarted)) { $0.hotkeyTap = .active }

    continuation.finish()
    await store.receive(.hotkeyListenerFinished) { $0.hotkeyTap = .dead }
  }

  @Test func `a tap without accessibility opens accessibility settings`() async {
    let opened = Collector<URL>()
    var state = AppFeature.State()
    state.hotkeyTap = .accessibilityMissing
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.workspace.open = { opened.append($0) }
    }

    await store.send(.repairDegradedState)
    #expect(opened.values == [SystemSettingsPane.accessibility])
  }

  @Test func `denied microphone opens its settings pane`() async {
    let opened = Collector<URL>()
    var state = AppFeature.State()
    state.engineReadiness = .ready
    state.hotkeyTap = .active
    state.recording.micStatus = .denied
    state.accessibilityGranted = true
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.workspace.open = { opened.append($0) }
    }

    await store.send(.repairDegradedState)
    #expect(opened.values == [SystemSettingsPane.microphone])
  }

  @Test func `a revoked accessibility grant opens accessibility settings`() async {
    let opened = Collector<URL>()
    var state = AppFeature.State()
    state.hotkeyTap = .active
    state.recording.micStatus = .granted
    state.accessibilityGranted = false
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.workspace.open = { opened.append($0) }
    }

    await store.send(.repairDegradedState)
    #expect(opened.values == [SystemSettingsPane.accessibility])
  }

  @Test func `an incomplete setup reenters onboarding at shortcut setup`() async {
    var state = AppFeature.State()
    state.hotkeyTap = .active
    state.recording.micStatus = .granted
    state.accessibilityGranted = true
    state.onboardingCompleted = false
    state.modelDownloadConsented = true
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.asrEngine.installAndPrepare = { AsyncStream { $0.finish() } }
    }
    let snapshot = OnboardingSnapshot(
      permissions: OnboardingPermissionStatuses(
        microphoneStatus: .granted, hasAccessibilityPermission: true,
      ),
      engineReadiness: .modelMissing, hasModelDownloadConsent: true, isCompleted: false,
    )

    await store.send(.repairDegradedState)
    await store.receive(.onboarding(.present(snapshot))) {
      $0.onboarding.isPresented = true
      $0.onboarding.snapshot = snapshot
    }
    #expect(store.state.onboarding.step == .shortcut)
  }

  @Test func `a dead tap is repaired by restarting the listener without prompting`() async {
    let (events, continuation) = AsyncStream.makeStream(of: HotkeyListenerEvent.self)
    var state = AppFeature.State()
    state.hotkeyTap = .dead
    state.accessibilityGranted = true
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.accessibilityPermission.hasPermission = { true }
      $0.hotkeyListener.events = { _ in events }
    }

    await store.send(.repairDegradedState) {
      $0.hotkeyTap = .starting
    }
    continuation.yield(.monitoringStarted)
    await store.receive(.hotkeyListenerEvent(.monitoringStarted)) { $0.hotkeyTap = .active }
    continuation.finish()
    await store.receive(.hotkeyListenerFinished) { $0.hotkeyTap = .dead }
  }

  @Test func `a reenabled tap interruption is not degraded`() async {
    var state = AppFeature.State()
    state.hotkeyTap = .active
    state.accessibilityGranted = true
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.accessibilityPermission.hasPermission = { true }
    }

    await store.send(.hotkeyListenerEvent(.monitoringInterrupted(.timeout)))
    await store.send(.hotkeyListenerEvent(.monitoringInterrupted(.userInput)))
    #expect(store.state.hotkeyTap == .active)
    await store.send(.hotkeyListenerEvent(.monitoringInterrupted(.invalidated))) {
      $0.hotkeyTap = .dead
    }
    #expect(store.state.menuBar.repair == .restartHotkeyListening)
  }

  @Test func `a tap invalidated by A revoked grant asks for the grant back`() async {
    var state = AppFeature.State()
    state.hotkeyTap = .active
    state.accessibilityGranted = true
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.accessibilityPermission.hasPermission = { false }
    }

    await store.send(.hotkeyListenerEvent(.monitoringInterrupted(.invalidated))) {
      $0.hotkeyTap = .accessibilityMissing
      $0.accessibilityGranted = false
    }
    #expect(store.state.menuBar.degradation == .accessibilityDenied)
    #expect(store.state.menuBar.repair == .openAccessibilitySettings)
  }

  @Test func `a later accessibility grant starts the listener without A relaunch`() async {
    let (events, continuation) = AsyncStream.makeStream(of: HotkeyListenerEvent.self)
    var state = AppFeature.State()
    state.onboardingCompleted = true
    state.hotkeyTap = .accessibilityMissing
    state.recording.micStatus = .granted
    state.engineReadiness = .ready
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.accessibilityPermission.hasPermission = { true }
      $0.hotkeyListener.events = { _ in events }
    }
    #expect(store.state.menuBar.degradation == .accessibilityDenied)

    await store.send(.applicationBecameActive)
    await store.receive(.accessibilityObserved(true)) {
      $0.accessibilityGranted = true
      $0.hotkeyTap = .starting
    }
    continuation.yield(.monitoringStarted)
    await store.receive(.hotkeyListenerEvent(.monitoringStarted)) { $0.hotkeyTap = .active }
    #expect(store.state.menuBar.degradation == nil)

    continuation.finish()
    await store.receive(.hotkeyListenerFinished) { $0.hotkeyTap = .dead }
  }

  @Test func `a finished stream keeps the permission diagnosis`() async {
    var state = AppFeature.State()
    state.hotkeyTap = .accessibilityMissing
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.accessibilityPermission.hasPermission = { false }
    }

    await store.send(.hotkeyListenerFinished)
    #expect(store.state.menuBar.degradation == .accessibilityDenied)
  }

  @Test func `copy last transcript writes the last successful transcript`() async {
    let copied = Collector<String>()
    var state = AppFeature.State()
    state.lastTranscript = "hello there"
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.delivery.copy = { transcript in copied.append(transcript) }
    }

    await store.send(.copyLastTranscript)
    #expect(copied.values == ["hello there"])
  }

  @Test func `copy last transcript is inert without A transcript`() async {
    let store = TestStore(initialState: AppFeature.State()) { AppFeature() }

    #expect(!store.state.menuBar.canCopyLastTranscript)
    await store.send(.copyLastTranscript)
  }

  @Test func `toggling sounds writes the setting straight through`() async {
    let state = AppFeature.State()
    state.$settings.withLock { $0.soundsEnabled = true }
    let store = TestStore(initialState: state) { AppFeature() }

    await store.send(.toggleSounds) {
      $0.$settings.withLock { $0.soundsEnabled = false }
    }
    #expect(!store.state.menuBar.soundsEnabled)
  }

  @Test func `toggling launch at login reads the service back`() async {
    let registered = Collector<Bool>()
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.launchAtLogin.setRegistered = { registered.append($0) }
      $0.launchAtLogin.isRegistered = { registered.last ?? false }
    }

    await store.send(.toggleLaunchAtLogin)
    await store.receive(.launchAtLoginUpdated(true)) { $0.launchAtLoginRegistered = true }
  }

  @Test func `a failed launch at login registration leaves the toggle off`() async {
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.launchAtLogin.setRegistered = { _ in throw MenuActionFailure() }
      $0.launchAtLogin.isRegistered = { false }
    }

    await store.send(.toggleLaunchAtLogin)
    await store.receive(.launchAtLoginFailed("menu action failed"))
    await store.receive(.launchAtLoginUpdated(false))
    #expect(!store.state.launchAtLoginRegistered)
  }

  @Test func `a missing accessibility grant survives A restart attempt`() async {
    var state = AppFeature.State()
    state.hotkeyTap = .accessibilityMissing
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.workspace.open = { _ in }
    }

    await store.send(.repairDegradedState)
    #expect(store.state.menuBar.repair == .openAccessibilitySettings)
  }

  @Test func `a failed open is reported rather than swallowed`() async {
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.workspace.open = { url in throw WorkspaceError.openFailed(url) }
    }

    await store.send(.openSettingsFile)
    await store.receive(
      .workspaceOpenFailed(
        WorkspaceError.openFailed(Channel.settingsFile).localizedDescription,
      ),
    )
  }

  @Test func `an approval pending login item still counts as registered`() {
    #expect(LaunchAtLoginClient.isRegistered(.enabled))
    #expect(LaunchAtLoginClient.isRegistered(.requiresApproval))
    #expect(!LaunchAtLoginClient.isRegistered(.notRegistered))
    #expect(!LaunchAtLoginClient.isRegistered(.notFound))
  }

  @Test func `settings file opens in the default editor`() async {
    let opened = Collector<URL>()
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.workspace.open = { opened.append($0) }
    }

    await store.send(.openSettingsFile)
    #expect(opened.values == [Channel.settingsFile])
  }
}
