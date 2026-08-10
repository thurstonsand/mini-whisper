import AppSettings
import ASREngine
import AudioCapture
import ComposableArchitecture
import Foundation
import HotkeyListener
@testable import MiniWhisper
import ServiceManagement
import Testing

// MARK: - MenuBarViewStateTests

struct MenuBarViewStateTests {
  // MARK: Internal

  @Test func `a healthy menu says what the app is doing`() {
    let state = viewState()

    #expect(state.degradations.isEmpty)
    #expect(state.statusText == "Ready · Parakeet v2 · Shure MV7")
    #expect(state.accessibilityStatusText == "Ready; Parakeet v2; Shure MV7")
  }

  @Test func `model setup progress is reported in the status line`() {
    let downloading = viewState(engineReadiness: .downloading(0.42))

    #expect(downloading.statusText == "Downloading Parakeet v2 · 42% · Shure MV7")
    #expect(downloading.accessibilityStatusText == "Downloading Parakeet v2; 42%; Shure MV7")
  }

  @Test func `a degraded menu withdraws the claim that the app is ready`() {
    let denied = viewState(degradations: [.microphoneAccessDenied])

    #expect(denied.statusText == "Not ready · Shure MV7")
    #expect(denied.accessibilityStatusText == "Not ready; Shure MV7")
  }

  /// The engine's own failures keep their wording: they are the only ones with progress to report,
  /// and a download that says only "Not ready" is a menu the user has no reason to keep watching.
  @Test func `a download reports itself even while something else is wrong`() {
    let downloading = viewState(
      degradations: [.microphoneAccessDenied],
      engineReadiness: .downloading(0.42),
    )

    #expect(downloading.statusText == "Downloading Parakeet v2 · 42% · Shure MV7")
  }

  @Test func `a missing input device is named in the status line`() {
    #expect(viewState(inputDeviceName: nil).statusText == "Ready · Parakeet v2 · No input device")
  }

  @Test func `the transcript state is passed through`() {
    #expect(viewState(hasLastTranscript: true).canCopyLastTranscript)
  }

  // MARK: Private

  private func viewState(
    degradations: [Degradation] = [], engineReadiness: EngineReadiness = .ready,
    inputDeviceName: String? = "Shure MV7", hasLastTranscript: Bool = false,
  ) -> MenuBarViewState {
    MenuBarViewState(
      degradations: degradations, engineReadiness: engineReadiness,
      inputDeviceName: inputDeviceName, canCopyLastTranscript: hasLastTranscript,
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

// MARK: - MenuBarActionTests

@MainActor struct MenuBarActionTests {
  @Test func `opening the menu refreshes the device`() async {
    var state = AppFeature.State()
    state.onboardingCompleted = true
    state.$health.withLock { $0.hotkeyTap = .active }
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.audioCapture.currentInputDeviceName = { _ in "Shure MV7" }
      $0.accessibilityPermission.hasPermission = { true }
      $0.microphonePermission.status = { .undetermined }
    }

    await store.send(.menuWillOpen) {
      $0.inputDeviceName = "Shure MV7"
      $0.$health.withLock { $0.accessibilityGranted = true }
    }
  }

  /// The controller rebuilds the menu on the line after this action returns, so a status that
  /// arrives an effect later arrives behind the menu the user is already looking at.
  @Test func `opening the menu refreshes A changed microphone permission`() async {
    var state = AppFeature.State()
    state.$health.withLock {
      $0.hotkeyTap = .active
      $0.accessibilityGranted = true
      $0.micStatus = .granted
      $0.engineReadiness = .ready
    }
    let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
      $0.accessibilityPermission.hasPermission = { true }
      $0.audioCapture.currentInputDeviceName = { _ in "Shure MV7" }
      $0.microphonePermission.status = { .denied }
    }

    await store.send(.menuWillOpen) {
      $0.inputDeviceName = "Shure MV7"
      $0.$health.withLock { $0.micStatus = .denied }
    }
    #expect(store.state.menuBar.degradations == [.microphoneAccessDenied])
  }

  @Test func `opening the menu recovers A grant made while the app ran`() async {
    let (events, continuation) = AsyncStream.makeStream(of: HotkeyListenerEvent.self)
    var state = AppFeature.State()
    state.onboardingCompleted = true
    state.$health.withLock { $0.hotkeyTap = .idle }
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.accessibilityPermission.hasPermission = { true }
      $0.audioCapture.currentInputDeviceName = { _ in "Shure MV7" }
      $0.hotkeyListener.events = { _ in events }
      $0.launchAtLogin.isRegistered = { false }
      $0.microphonePermission.status = { .undetermined }
    }

    await store.send(.menuWillOpen) {
      $0.inputDeviceName = "Shure MV7"
      $0.$health.withLock { $0.accessibilityGranted = true }
      $0.$health.withLock { $0.hotkeyTap = .starting }
    }
    continuation.yield(.monitoringStarted)
    await store
      .receive(.hotkeyListenerEvent(.monitoringStarted)) {
        $0.$health.withLock { $0.hotkeyTap = .active }
      }

    continuation.finish()
    await store.receive(.hotkeyListenerFinished) { $0.$health.withLock { $0.hotkeyTap = .dead } }
  }

  @Test func `a tap without accessibility opens accessibility settings`() async {
    let opened = Collector<URL>()
    var state = AppFeature.State()
    state.$health.withLock { $0.hotkeyTap = .idle }
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.workspace.open = { opened.append($0) }
    }

    await store.send(.repairRequested(.accessibilityDenied))
    #expect(opened.values == [SystemSettingsPane.accessibility])
  }

  @Test func `denied microphone opens its settings pane`() async {
    let opened = Collector<URL>()
    var state = AppFeature.State()
    state.$health.withLock {
      $0.engineReadiness = .ready
      $0.hotkeyTap = .active
      $0.micStatus = .denied
      $0.accessibilityGranted = true
    }
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.workspace.open = { opened.append($0) }
    }

    await store.send(.repairRequested(.microphoneAccessDenied))
    #expect(opened.values == [SystemSettingsPane.microphone])
  }

  @Test func `a revoked accessibility grant opens accessibility settings`() async {
    let opened = Collector<URL>()
    var state = AppFeature.State()
    state.$health.withLock {
      $0.hotkeyTap = .active
      $0.micStatus = .granted
      $0.accessibilityGranted = false
      $0.engineReadiness = .ready
    }
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.workspace.open = { opened.append($0) }
    }

    await store.send(.repairRequested(.accessibilityDenied))
    #expect(opened.values == [SystemSettingsPane.accessibility])
  }

  @Test func `a dead tap is repaired by restarting the listener without prompting`() async {
    let (events, continuation) = AsyncStream.makeStream(of: HotkeyListenerEvent.self)
    var state = AppFeature.State()
    state.$health.withLock {
      $0.hotkeyTap = .dead
      $0.accessibilityGranted = true
    }
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.accessibilityPermission.hasPermission = { true }
      $0.hotkeyListener.events = { _ in events }
    }

    await store.send(.repairRequested(.hotkeyTapDead)) {
      $0.$health.withLock { $0.hotkeyTap = .starting }
    }
    continuation.yield(.monitoringStarted)
    await store
      .receive(.hotkeyListenerEvent(.monitoringStarted)) {
        $0.$health.withLock { $0.hotkeyTap = .active }
      }
    continuation.finish()
    await store.receive(.hotkeyListenerFinished) { $0.$health.withLock { $0.hotkeyTap = .dead } }
  }

  @Test func `a reenabled tap interruption is not degraded`() async {
    var state = AppFeature.State()
    state.$health.withLock {
      $0.hotkeyTap = .active
      $0.accessibilityGranted = true
      $0.engineReadiness = .ready
    }
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.accessibilityPermission.hasPermission = { true }
    }

    await store.send(.hotkeyListenerEvent(.monitoringInterrupted(.timeout)))
    await store.send(.hotkeyListenerEvent(.monitoringInterrupted(.userInput)))
    #expect(store.state.health.hotkeyTap == .active)
    await store.send(.hotkeyListenerEvent(.monitoringInterrupted(.invalidated))) {
      $0.$health.withLock { $0.hotkeyTap = .dead }
    }
    #expect(store.state.health.degradations.first == .hotkeyTapDead)
  }

  @Test func `a tap invalidated by A revoked grant asks for the grant back`() async {
    var state = AppFeature.State()
    state.$health.withLock {
      $0.hotkeyTap = .active
      $0.accessibilityGranted = true
      $0.engineReadiness = .ready
    }
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.accessibilityPermission.hasPermission = { false }
    }

    await store.send(.hotkeyListenerEvent(.monitoringInterrupted(.invalidated))) {
      $0.$health.withLock { $0.hotkeyTap = .idle }
      $0.$health.withLock { $0.accessibilityGranted = false }
    }
    #expect(store.state.health.degradations.first == .accessibilityDenied)
  }

  @Test func `a later accessibility grant starts the listener without A relaunch`() async {
    let (events, continuation) = AsyncStream.makeStream(of: HotkeyListenerEvent.self)
    var state = AppFeature.State()
    state.onboardingCompleted = true
    state.$health.withLock {
      $0.hotkeyTap = .idle
      $0.micStatus = .granted
      $0.engineReadiness = .ready
    }
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.accessibilityPermission.hasPermission = { true }
      $0.hotkeyListener.events = { _ in events }
      $0.microphonePermission.status = { .granted }
    }
    #expect(store.state.health.degradations.first == .accessibilityDenied)

    await store.send(.applicationBecameActive) {
      $0.$health.withLock { $0.accessibilityGranted = true }
      $0.$health.withLock { $0.hotkeyTap = .starting }
    }
    continuation.yield(.monitoringStarted)
    await store
      .receive(.hotkeyListenerEvent(.monitoringStarted)) {
        $0.$health.withLock { $0.hotkeyTap = .active }
      }
    #expect(!store.state.health.isDegraded)

    continuation.finish()
    await store.receive(.hotkeyListenerFinished) { $0.$health.withLock { $0.hotkeyTap = .dead } }
  }

  @Test func `a finished stream keeps the permission diagnosis`() async {
    var state = AppFeature.State()
    state.$health.withLock { $0.hotkeyTap = .idle }
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.accessibilityPermission.hasPermission = { false }
    }

    await store.send(.hotkeyListenerFinished)
    #expect(store.state.health.degradations.first == .accessibilityDenied)
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

  @Test func `a missing accessibility grant survives A restart attempt`() async {
    var state = AppFeature.State()
    state.$health.withLock { $0.hotkeyTap = .idle }
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.workspace.open = { _ in }
    }

    await store.send(.repairRequested(.accessibilityDenied))
    #expect(store.state.health.degradations == [.accessibilityDenied, .modelMissing])
  }

  @Test func `a failed open is reported rather than swallowed`() async {
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.workspace.open = { url in throw WorkspaceError.openFailed(url) }
    }

    await store.send(.repairRequested(.microphoneAccessDenied))
    await store.receive(
      .workspaceOpenFailed(
        WorkspaceError.openFailed(SystemSettingsPane.microphone).localizedDescription,
      ),
    )
  }

  @Test func `an approval pending login item still counts as registered`() {
    #expect(LaunchAtLoginClient.isRegistered(.enabled))
    #expect(LaunchAtLoginClient.isRegistered(.requiresApproval))
    #expect(!LaunchAtLoginClient.isRegistered(.notRegistered))
    #expect(!LaunchAtLoginClient.isRegistered(.notFound))
  }
}
