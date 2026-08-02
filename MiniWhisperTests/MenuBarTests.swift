import ASREngine
import AudioCapture
import ComposableArchitecture
import Foundation
import HotkeyListener
import ServiceManagement
import Testing

@testable import MiniWhisper

@Suite struct MenuBarDerivationTests {
  private func viewState(
    hotkeyTap: HotkeyTapStatus = .active, micStatus: MicPermissionStatus = .granted,
    pasteAccessGranted: Bool? = true, engineReadiness: EngineReadiness = .ready,
    inputDeviceName: String? = "Shure MV7", hasLastTranscript: Bool = false,
    soundsEnabled: Bool = true, launchAtLoginRegistered: Bool = false
  ) -> MenuBarViewState {
    MenuBarViewState(
      hotkeyTap: hotkeyTap, micStatus: micStatus, pasteAccessGranted: pasteAccessGranted,
      engineReadiness: engineReadiness, inputDeviceName: inputDeviceName,
      hasLastTranscript: hasLastTranscript, soundsEnabled: soundsEnabled,
      launchAtLoginRegistered: launchAtLoginRegistered)
  }

  @Test func healthyShowsTheStaticMicAndThePassiveStatusLine() {
    let state = viewState()

    #expect(state.degradation == nil)
    #expect(state.iconSymbolName == "mic")
    #expect(state.statusText == "Ready · Parakeet v2 · Shure MV7")
    #expect(state.accessibilityStatusText == "Ready; Parakeet v2; Shure MV7")
    #expect(state.repair == nil)
    #expect(state.repairTitle == nil)
  }

  @Test func modelSetupProgressIsNotDegraded() {
    for readiness in [EngineReadiness.downloading(0.42), .compiling, .prewarming] {
      let state = viewState(engineReadiness: readiness)
      #expect(state.degradation == nil)
      #expect(state.iconSymbolName == "mic")
    }
    let downloading = viewState(engineReadiness: .downloading(0.42))
    #expect(downloading.statusText == "Downloading Parakeet v2 · 42% · Shure MV7")
    #expect(downloading.accessibilityStatusText == "Downloading Parakeet v2; 42%; Shure MV7")
  }

  @Test func missingInputMonitoringDegradesToTheSettingsDeepLink() {
    let state = viewState(hotkeyTap: .inputMonitoringMissing)

    #expect(state.degradation == .inputMonitoringMissing)
    #expect(state.iconSymbolName == "mic.slash")
    #expect(state.statusText == "Input Monitoring is off, so MiniWhisper can't see your hotkey")
    #expect(state.repair == .openInputMonitoringSettings)
    #expect(state.repairTitle == "Open Input Monitoring Settings…")
  }

  @Test func deadEventTapDegradesToARestart() {
    let state = viewState(hotkeyTap: .dead)

    #expect(state.degradation == .hotkeyTapDead)
    #expect(state.statusText == "Hotkey listening stopped")
    #expect(state.repair == .restartHotkeyListening)
  }

  @Test(arguments: [MicPermissionStatus.denied, .restricted, .unknown])
  func blockedMicrophoneDegradesToTheSettingsDeepLink(status: MicPermissionStatus) {
    let state = viewState(micStatus: status)

    #expect(state.degradation == .microphoneAccessDenied)
    #expect(state.statusText == "Microphone access is off, so nothing can be recorded")
    #expect(state.repair == .openMicrophoneSettings)
  }

  @Test func anUnrequestedMicrophoneIsLeftToOnboarding() {
    #expect(viewState(micStatus: .undetermined).degradation == nil)
  }

  @Test func missingPasteAccessDegradesToAccessibilitySettings() {
    let state = viewState(pasteAccessGranted: false)

    #expect(state.degradation == .pasteAccessDenied)
    #expect(state.statusText == "Paste access is off, so transcripts can only be copied")
    #expect(state.repair == .openAccessibilitySettings)
    #expect(state.repairTitle == "Open Accessibility Settings…")
  }

  @Test func unresolvedPasteAccessDoesNotOutrankKnownDegradation() {
    #expect(viewState(pasteAccessGranted: nil).degradation == nil)
    #expect(
      viewState(pasteAccessGranted: nil, engineReadiness: .modelMissing).degradation
        == .modelMissing)
  }

  @Test func missingModelDegradesToSetup() {
    let state = viewState(engineReadiness: .modelMissing)

    #expect(state.degradation == .modelMissing)
    #expect(state.statusText == "Parakeet v2 isn't installed yet")
    #expect(state.repair == .installModel)
    #expect(state.repairTitle == "Download & Prepare Parakeet v2…")
  }

  @Test func failedModelSetupDegradesToARetry() {
    let state = viewState(engineReadiness: .failed("compile crashed"))

    #expect(state.degradation == .modelSetupFailed)
    #expect(state.repair == .retryModelSetup)
    #expect(state.repairTitle == "Retry Parakeet v2 Setup…")
  }

  @Test func theHotkeyPipelineOutranksTheMicrophoneAndTheModel() {
    #expect(
      viewState(
        hotkeyTap: .inputMonitoringMissing, micStatus: .denied, engineReadiness: .modelMissing
      ).degradation == .inputMonitoringMissing)
    #expect(
      viewState(hotkeyTap: .dead, micStatus: .denied, engineReadiness: .failed("boom")).degradation
        == .hotkeyTapDead)
    #expect(
      viewState(micStatus: .denied, engineReadiness: .modelMissing).degradation
        == .microphoneAccessDenied)
  }

  @Test func repairingEveryFailureReturnsTheHealthyIcon() {
    var state = viewState(
      hotkeyTap: .inputMonitoringMissing, micStatus: .denied, engineReadiness: .modelMissing)
    #expect(state.degradation == .inputMonitoringMissing)

    state = viewState(hotkeyTap: .active, micStatus: .denied, engineReadiness: .modelMissing)
    #expect(state.degradation == .microphoneAccessDenied)

    state = viewState(hotkeyTap: .active, micStatus: .granted, engineReadiness: .modelMissing)
    #expect(state.degradation == .modelMissing)

    state = viewState(hotkeyTap: .active, micStatus: .granted, engineReadiness: .ready)
    #expect(state.degradation == nil)
    #expect(state.iconSymbolName == "mic")
    #expect(state.statusText == "Ready · Parakeet v2 · Shure MV7")
  }

  @Test func aMissingInputDeviceIsNamedInTheStatusLine() {
    #expect(viewState(inputDeviceName: nil).statusText == "Ready · Parakeet v2 · No input device")
  }

  @Test func theToggleAndTranscriptStateArePassedThrough() {
    let state = viewState(
      hasLastTranscript: true, soundsEnabled: false, launchAtLoginRegistered: true)

    #expect(state.canCopyLastTranscript)
    #expect(!state.soundsEnabled)
    #expect(state.launchAtLoginRegistered)
  }
}

private final class Collector<Value: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [Value] = []

  func append(_ value: Value) { lock.withLock { storage.append(value) } }

  var values: [Value] { lock.withLock { storage } }
  var last: Value? { lock.withLock { storage.last } }
}

private struct MenuActionFailure: LocalizedError {
  var errorDescription: String? { "menu action failed" }
}

@MainActor @Suite struct MenuBarActionTests {
  @Test func openingTheMenuRefreshesTheDeviceAndTheLoginItem() async {
    var state = AppFeature.State()
    state.onboardingCompleted = true
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.audioCapture.currentInputDeviceName = { "Shure MV7" }
      $0.delivery.hasPasteAccess = { true }
      $0.hotkeyListener.hasInputMonitoringPermission = { false }
      $0.launchAtLogin.isRegistered = { true }
    }

    await store.send(.menuWillOpen) {
      $0.inputDeviceName = "Shure MV7"
      $0.launchAtLoginRegistered = true
      $0.pasteAccessGranted = true
    }
  }

  @Test func missingInputMonitoringOpensItsSettingsPane() async {
    let opened = Collector<URL>()
    var state = AppFeature.State()
    state.hotkeyTap = .inputMonitoringMissing
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.workspace.open = { opened.append($0) }
    }

    await store.send(.repairDegradedState)
    #expect(opened.values == [SystemSettingsPane.inputMonitoring])
  }

  @Test func deniedMicrophoneOpensItsSettingsPane() async {
    let opened = Collector<URL>()
    var state = AppFeature.State()
    state.engineReadiness = .ready
    state.hotkeyTap = .active
    state.recording.micStatus = .denied
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.workspace.open = { opened.append($0) }
    }

    await store.send(.repairDegradedState)
    #expect(opened.values == [SystemSettingsPane.microphone])
  }

  @Test func missingPasteAccessOpensAccessibilitySettings() async {
    let opened = Collector<URL>()
    var state = AppFeature.State()
    state.hotkeyTap = .active
    state.recording.micStatus = .granted
    state.pasteAccessGranted = false
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.workspace.open = { opened.append($0) }
    }

    await store.send(.repairDegradedState)
    #expect(opened.values == [SystemSettingsPane.accessibility])
  }

  @Test func aMissingModelReentersOnboardingAtModelSetup() async {
    var state = AppFeature.State()
    state.hotkeyTap = .active
    state.recording.micStatus = .granted
    state.pasteAccessGranted = true
    state.onboardingCompleted = false
    state.modelDownloadConsented = true
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.asrEngine.installAndPrepare = { AsyncStream { $0.finish() } }
      $0.hotkeyListener.hasInputMonitoringPermission = { true }
    }
    let snapshot = OnboardingSnapshot(
      permissions: OnboardingPermissionStatuses(
        hasInputMonitoringPermission: true, microphoneStatus: .granted, hasPasteAccess: true),
      engineReadiness: .modelMissing, hasModelDownloadConsent: true, isCompleted: false)

    await store.send(.repairDegradedState)
    await store.receive(.onboarding(.present(snapshot))) {
      $0.onboarding.isPresented = true
      $0.onboarding.snapshot = snapshot
    }
    #expect(store.state.onboarding.step == .model)
  }

  @Test func aDeadTapIsRepairedByRestartingTheListenerWithoutPrompting() async {
    let (events, continuation) = AsyncStream.makeStream(of: HotkeyListenerEvent.self)
    var state = AppFeature.State()
    state.hotkeyTap = .dead
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.hotkeyListener.events = { events }
      $0.hotkeyListener.requestInputMonitoringPermission = {
        Issue.record("A menu repair must never request Input Monitoring")
        return false
      }
    }

    await store.send(.repairDegradedState) { $0.hotkeyTap = .starting }
    continuation.yield(.monitoringStarted)
    await store.receive(.hotkeyListenerEvent(.monitoringStarted)) { $0.hotkeyTap = .active }
    continuation.finish()
    await store.receive(.hotkeyListenerFinished) { $0.hotkeyTap = .dead }
  }

  @Test func aReenabledTapInterruptionIsNotDegraded() async {
    var state = AppFeature.State()
    state.hotkeyTap = .active
    let store = TestStore(initialState: state) { AppFeature() }

    await store.send(.hotkeyListenerEvent(.monitoringInterrupted(.timeout)))
    await store.send(.hotkeyListenerEvent(.monitoringInterrupted(.userInput)))
    #expect(store.state.hotkeyTap == .active)
    await store.send(.hotkeyListenerEvent(.monitoringInterrupted(.invalidated))) {
      $0.hotkeyTap = .dead
    }
  }

  @Test func aFinishedStreamKeepsThePermissionDiagnosis() async {
    var state = AppFeature.State()
    state.hotkeyTap = .inputMonitoringMissing
    let store = TestStore(initialState: state) { AppFeature() }

    await store.send(.hotkeyListenerFinished)
    #expect(store.state.menuBar.degradation == .inputMonitoringMissing)
  }

  @Test func copyLastTranscriptWritesTheLastSuccessfulTranscript() async {
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

  @Test func copyLastTranscriptIsInertWithoutATranscript() async {
    let store = TestStore(initialState: AppFeature.State()) { AppFeature() }

    #expect(!store.state.menuBar.canCopyLastTranscript)
    await store.send(.copyLastTranscript)
  }

  @Test func togglingSoundsPersistsTheSetting() async {
    let saved = Collector<Bool>()
    var state = AppFeature.State()
    state.soundsEnabled = true
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.sounds.setIsEnabled = { enabled in saved.append(enabled) }
    }

    await store.send(.toggleSounds)
    await store.receive(.soundsEnabledSaved(false)) { $0.soundsEnabled = false }
    #expect(saved.values == [false])
  }

  @Test func aFailedSoundsSaveLeavesTheToggleUntouched() async {
    var state = AppFeature.State()
    state.soundsEnabled = true
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.sounds.setIsEnabled = { _ in throw MenuActionFailure() }
    }

    await store.send(.toggleSounds)
    await store.receive(.soundsPersistenceFailed("menu action failed"))
    #expect(store.state.soundsEnabled)
  }

  @Test func togglingLaunchAtLoginReadsTheServiceBack() async {
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

  @Test func aFailedLaunchAtLoginRegistrationLeavesTheToggleOff() async {
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

  @Test func aMissingInputMonitoringGrantSurvivesARestartAttempt() async {
    var state = AppFeature.State()
    state.hotkeyTap = .inputMonitoringMissing
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.workspace.open = { _ in }
    }

    await store.send(.repairDegradedState)
    #expect(store.state.menuBar.repair == .openInputMonitoringSettings)
  }

  @Test func aFailedOpenIsReportedRatherThanSwallowed() async {
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.workspace.open = { url in throw WorkspaceError.openFailed(url) }
    }

    await store.send(.openSettingsFile)
    await store.receive(
      .workspaceOpenFailed(
        WorkspaceError.openFailed(SettingsStore.defaultFileURL).localizedDescription))
  }

  @Test func anApprovalPendingLoginItemStillCountsAsRegistered() {
    #expect(LaunchAtLoginClient.isRegistered(.enabled))
    #expect(LaunchAtLoginClient.isRegistered(.requiresApproval))
    #expect(!LaunchAtLoginClient.isRegistered(.notRegistered))
    #expect(!LaunchAtLoginClient.isRegistered(.notFound))
  }

  @Test func settingsFileOpensInTheDefaultEditor() async {
    let opened = Collector<URL>()
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.workspace.open = { opened.append($0) }
    }

    await store.send(.openSettingsFile)
    #expect(opened.values == [SettingsStore.defaultFileURL])
  }
}
