import AppSettings
import ASREngine
import AudioCapture
import ComposableArchitecture
import FieldContext
import Foundation
import History
import HotkeyListener
@testable import MiniWhisper
import Sharing
import SpeechDictionary
import Testing

// MARK: - AppFeatureTests

@MainActor struct AppFeatureTests {
  @Test func `hotkey hold captures and retains A recording`() async {
    let (captureEvents, captureContinuation) = AsyncStream.makeStream(of: AudioCaptureEvent.self)
    let recording = CanonicalRecording(samples: Array(repeating: 0.1, count: 16000))
    let sessionID = UUID()
    let clock = TestClock()
    var state = AppFeature.State()
    state.$health.withLock {
      $0.hotkeyTap = .active
      $0.micStatus = .granted
      $0.engineReadiness = .ready
    }
    state.onboardingCompleted = true
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.audioCapture.start = { _ in
        AudioCaptureSession(
          id: sessionID, inputDeviceName: "Test Microphone", events: captureEvents,
        )
      }
      $0.audioCapture.stop = { id in
        #expect(id == sessionID)
        return recording
      }
      $0.audioCapture.currentInputDeviceName = { _ in "Test Microphone" }
      $0.asrEngine.submit = { _, _ in .noSpeech }
      $0.contextCapture.prewarmFrontmostApp = {}
      $0.date.now = Date(timeIntervalSince1970: 1000)
      $0.continuousClock = clock
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store
      .send(.hotkeyListenerEvent(.gesture(.startRecording))) {
        $0.transcriptionGeneration = 1
      }
    await store.receive(.pill(.recordingStarting(inputDeviceName: "Test Microphone"))) {
      $0.pill.presentation = .recording(
        PillFeature.State.Presentation.Recording(
          inputDeviceName: "Test Microphone", level: 0, isLive: false,
        ),
      )
    }
    await store.receive(.recording(.startRecording)) {
      $0.recording.captureGeneration = 1
      $0.recording.phase = .starting(nil)
    }
    await store.receive(.recording(.captureSessionStarted(1, sessionID))) {
      $0.recording.captureSessionID = sessionID
    }
    captureContinuation.yield(.captureBecameLive)
    await store.receive(.recording(.captureBecameLive(1, sessionID, "Test Microphone"))) {
      $0.recording.phase = .recording
    }
    await store.receive(
      .recording(.delegate(.recordingStarted(inputDeviceName: "Test Microphone"))),
    )
    await store.receive(.pill(.recordingStarted(inputDeviceName: "Test Microphone"))) {
      $0.pill.presentation = .recording(
        PillFeature.State.Presentation.Recording(
          inputDeviceName: "Test Microphone", level: 0, isLive: true,
        ),
      )
    }

    await store.send(.hotkeyListenerEvent(.gesture(.stopAndTranscribe)))
    await store.receive(.recording(.stopAndRetain)) { $0.recording.phase = .stopping(nil) }
    await store.receive(.recording(.captureStopped(1, recording))) {
      $0.recording.captureSessionID = nil
      $0.recording.phase = .idle
    }
    await store.receive(.recording(.delegate(.completed(recording))))
    await store.receive(.pill(.transcribingStarted)) { $0.pill.presentation = .transcribing }
    await store.receive(.transcriptionCompleted(1, .noSpeech))
    await store.receive(.pill(.noSpeechDetected)) {
      $0.pill.noticeGeneration = 1
      $0.pill.presentation = .notice(.noSpeechDetected)
    }
    await store.send(.pill(.dismiss)) { $0.pill.presentation = nil }
    captureContinuation.finish()
    await store.receive(.recording(.captureEventsFinished(1)))
    await store.finish()
  }

  @Test func `completed startup starts the listener without presenting onboarding`() async {
    let (events, continuation) = AsyncStream.makeStream(of: HotkeyListenerEvent<HotkeyAction>.self)
    let permissions = OnboardingPermissionStatuses(
      microphoneStatus: .granted, hasAccessibilityPermission: true,
    )
    let facts = AppFeature.StartupFacts(
      onboardingCompleted: true, modelDownloadConsented: true, permissions: permissions,
      engineReadiness: .ready,
    )
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.accessibilityPermission.hasPermission = { true }
      $0.hotkeyListener.events = { _ in events }
    }

    await store.send(.startupResolved(facts)) {
      $0.onboardingCompleted = true
      $0.$health.withLock { $0.accessibilityGranted = true }
      $0.$health.withLock { $0.micStatus = .granted }
      $0.$health.withLock { $0.engineReadiness = .ready }
      $0.$health.withLock { $0.hotkeyTap = .starting }
    }
    #expect(!store.state.onboarding.isPresented)
    continuation.yield(.monitoringStarted)
    await store
      .receive(.hotkeyListenerEvent(.monitoringStarted)) {
        $0.$health.withLock { $0.hotkeyTap = .active }
      }
    continuation.finish()
    await store.receive(.hotkeyListenerFinished) { $0.$health.withLock { $0.hotkeyTap = .dead } }
  }

  @Test func `opening settings refreshes an out of band microphone denial`() async {
    var state = AppFeature.State()
    state.$health.withLock {
      $0.hotkeyTap = .idle
      $0.micStatus = .granted
      $0.engineReadiness = .ready
    }
    let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
      $0.audioInputDevices.snapshots = { AsyncStream { $0.finish() } }
      $0.audioInputLevels.levels = { _ in AsyncStream { $0.finish() } }
      $0.launchAtLogin.isRegistered = { false }
      $0.microphonePermission.status = { .denied }
      $0.sounds.availableNames = { [] }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.settingsWindow(.settingsPane(.task))) {
      $0.$health.withLock { $0.micStatus = .denied }
    }
    #expect(
      store.state.settingsWindow.settingsPane.health.degradations
        == [.accessibilityDenied, .microphoneAccessDenied],
    )
  }

  @Test func `settings build the listener routes in the application layer`() {
    let defaults = HotkeyBindingsSettings.defaults

    #expect(defaults.listenerBindings == [
      HotkeyBinding(hotkey: defaults.hotkeys(for: .activate)[0], route: .gesture),
      HotkeyBinding(
        hotkey: defaults.hotkeys(for: .pasteLastTranscript)[0],
        route: .action(.pasteLastTranscript),
      ),
    ])
  }

  @Test func `recording A binding stops activation before capture and restarts with the commit`(
  ) async throws {
    let (recorderEvents, recorderContinuation) = AsyncStream.makeStream(
      of: HotkeyRecorderEvent.self,
    )
    let (listenerEvents, listenerContinuation) = AsyncStream.makeStream(
      of: HotkeyListenerEvent<HotkeyAction>.self,
    )
    let replacement = try Hotkey(keyCode: 15, modifiers: [.rightControl])
    var state = AppFeature.State()
    state.$health.withLock {
      $0.accessibilityGranted = true
      $0.hotkeyTap = .active
      $0.engineReadiness = .ready
    }
    let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
      $0.accessibilityPermission.hasPermission = { true }
      $0.hotkeyListener.record = { recorderEvents }
      $0.hotkeyListener.events = { bindings in
        #expect(bindings == [
          HotkeyBinding(hotkey: replacement, route: .gesture),
          HotkeyBinding(hotkey: .testPasteLastTranscript, route: .action(.pasteLastTranscript)),
        ])
        return listenerEvents
      }
    }

    await store.send(settingsBindingAction(.activate, .bindingTapped(0))) {
      $0.settingsWindow
        .settingsPane
        .bindingEditors[id: .activate]?
        .$recordingCommand
        .withLock { $0 = .activate }
      $0.settingsWindow.settingsPane.bindingEditors[id: .activate]?.target = .existing(0)
      $0.$health.withLock { $0.hotkeyTap = .idle }
    }
    await store.receive(settingsBindingAction(.activate, .delegate(.recordingStarted)))
    await store.receive(settingsBindingAction(.activate, .recorderReady))
    recorderContinuation.yield(.committed(replacement))
    await store.receive(
      settingsBindingAction(.activate, .recorderEvent(.committed(replacement))),
    ) {
      $0.$settings.withLock { $0.bindings.set([replacement], for: .activate) }
      $0.settingsWindow
        .settingsPane
        .bindingEditors[id: .activate]?
        .$recordingCommand
        .withLock { $0 = nil }
      $0.settingsWindow.settingsPane.bindingEditors[id: .activate]?.target = nil
      $0.$health.withLock { $0.hotkeyTap = .starting }
    }
    await store.receive(settingsBindingAction(.activate, .delegate(.recordingStopped)))
    listenerContinuation.yield(.monitoringStarted)
    await store
      .receive(.hotkeyListenerEvent(.monitoringStarted)) {
        $0.$health.withLock { $0.hotkeyTap = .active }
      }
    recorderContinuation.finish()
    await store.receive(settingsBindingAction(.activate, .recorderFinished))
    listenerContinuation.finish()
    await store.receive(.hotkeyListenerFinished) { $0.$health.withLock { $0.hotkeyTap = .dead } }
  }

  @Test func `recording paste last stops the listener and restarts with the new chord`(
  ) async throws {
    let (recorderEvents, recorderContinuation) = AsyncStream.makeStream(
      of: HotkeyRecorderEvent.self,
    )
    let (listenerEvents, listenerContinuation) = AsyncStream.makeStream(
      of: HotkeyListenerEvent<HotkeyAction>.self,
    )
    let replacement = try Hotkey(keyCode: 15, modifiers: [.rightControl, .rightCommand])
    var state = AppFeature.State()
    state.$health.withLock {
      $0.accessibilityGranted = true
      $0.hotkeyTap = .active
      $0.engineReadiness = .ready
    }
    let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
      $0.accessibilityPermission.hasPermission = { true }
      $0.hotkeyListener.record = { recorderEvents }
      $0.hotkeyListener.events = { bindings in
        #expect(bindings == [
          HotkeyBinding(hotkey: .testRightOption, route: .gesture),
          HotkeyBinding(hotkey: replacement, route: .action(.pasteLastTranscript)),
        ])
        return listenerEvents
      }
    }

    await store.send(settingsBindingAction(.pasteLastTranscript, .bindingTapped(0))) {
      $0.settingsWindow
        .settingsPane
        .bindingEditors[id: .pasteLastTranscript]?
        .$recordingCommand
        .withLock { $0 = .pasteLastTranscript }
      $0.settingsWindow.settingsPane.bindingEditors[id: .pasteLastTranscript]?.target = .existing(0)
      $0.$health.withLock { $0.hotkeyTap = .idle }
    }
    await store.receive(
      settingsBindingAction(.pasteLastTranscript, .delegate(.recordingStarted)),
    )
    await store.receive(settingsBindingAction(.pasteLastTranscript, .recorderReady))
    recorderContinuation.yield(.committed(replacement))
    await store.receive(
      settingsBindingAction(
        .pasteLastTranscript, .recorderEvent(.committed(replacement)),
      ),
    ) {
      $0.$settings.withLock {
        $0.bindings.set([replacement], for: .pasteLastTranscript)
      }
      $0.settingsWindow
        .settingsPane
        .bindingEditors[id: .pasteLastTranscript]?
        .$recordingCommand
        .withLock { $0 = nil }
      $0.settingsWindow.settingsPane.bindingEditors[id: .pasteLastTranscript]?.target = nil
      $0.$health.withLock { $0.hotkeyTap = .starting }
    }
    await store.receive(
      settingsBindingAction(.pasteLastTranscript, .delegate(.recordingStopped)),
    )
    listenerContinuation.yield(.monitoringStarted)
    await store.receive(.hotkeyListenerEvent(.monitoringStarted)) {
      $0.$health.withLock { $0.hotkeyTap = .active }
    }
    recorderContinuation.finish()
    await store.receive(settingsBindingAction(.pasteLastTranscript, .recorderFinished))
    listenerContinuation.finish()
    await store.receive(.hotkeyListenerFinished) {
      $0.$health.withLock { $0.hotkeyTap = .dead }
    }
  }

  @Test func `recording the onboarding shortcut suppresses and restarts activation listening`(
  ) async throws {
    let (recorderEvents, recorderContinuation) = AsyncStream.makeStream(
      of: HotkeyRecorderEvent.self,
    )
    let (listenerEvents, listenerContinuation) = AsyncStream.makeStream(
      of: HotkeyListenerEvent<HotkeyAction>.self,
    )
    let extra = try Hotkey(keyCode: 15, modifiers: [.rightControl])
    let replacement = try Hotkey(keyCode: 0, modifiers: [.leftCommand])
    var settings = MiniWhisperSettings.defaults
    settings.bindings.set([.testRightOption, extra], for: .activate)
    var state = AppFeature.State(
      history: Shared(value: HistoryLog()), settings: Shared(value: settings),
    )
    state.$health.withLock {
      $0.accessibilityGranted = true
      $0.hotkeyTap = .active
      $0.engineReadiness = .ready
    }
    state.onboarding.isPresented = true
    state.onboarding.snapshot.permissions = OnboardingPermissionStatuses(
      microphoneStatus: .granted, hasAccessibilityPermission: true,
    )
    state.onboarding.selectedStep = .shortcut
    let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
      $0.accessibilityPermission.hasPermission = { true }
      $0.hotkeyListener.record = { recorderEvents }
      $0.hotkeyListener.events = { bindings in
        #expect(bindings == [
          HotkeyBinding(hotkey: replacement, route: .gesture),
          HotkeyBinding(hotkey: extra, route: .gesture),
          HotkeyBinding(hotkey: .testPasteLastTranscript, route: .action(.pasteLastTranscript)),
        ])
        return listenerEvents
      }
    }

    await store.send(.onboarding(.shortcutBindings(.primaryBindingTapped))) {
      $0.onboarding.shortcutBindings.$recordingCommand.withLock { $0 = .activate }
      $0.onboarding.shortcutBindings.target = .existing(0)
      $0.$health.withLock { $0.hotkeyTap = .idle }
    }
    await store.receive(.onboarding(.shortcutBindings(.delegate(.recordingStarted))))
    await store.receive(.onboarding(.shortcutBindings(.recorderReady)))
    recorderContinuation.yield(.committed(replacement))
    await store.receive(
      .onboarding(.shortcutBindings(.recorderEvent(.committed(replacement)))),
    ) {
      $0.$settings.withLock {
        $0.bindings.set([replacement, extra], for: .activate)
      }
      $0.onboarding.shortcutBindings.$recordingCommand.withLock { $0 = nil }
      $0.onboarding.shortcutBindings.target = nil
      $0.$health.withLock { $0.hotkeyTap = .starting }
    }
    await store.receive(.onboarding(.shortcutBindings(.delegate(.recordingStopped))))
    listenerContinuation.yield(.monitoringStarted)
    await store
      .receive(.hotkeyListenerEvent(.monitoringStarted)) {
        $0.$health.withLock { $0.hotkeyTap = .active }
      }
    recorderContinuation.finish()
    await store.receive(.onboarding(.shortcutBindings(.recorderFinished)))
    listenerContinuation.finish()
    await store.receive(.hotkeyListenerFinished) { $0.$health.withLock { $0.hotkeyTap = .dead } }
  }

  @Test func `recovery binding keeps the tap active without activation bindings`() async {
    var settings = MiniWhisperSettings.defaults
    settings.bindings.set([], for: .activate)
    var state = AppFeature.State(
      history: Shared(value: HistoryLog()), settings: Shared(value: settings),
    )
    state.$health.withLock {
      $0.accessibilityGranted = true
      $0.hotkeyTap = .dead
    }
    let (events, continuation) = AsyncStream.makeStream(of: HotkeyListenerEvent<HotkeyAction>.self)
    let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
      $0.accessibilityPermission.hasPermission = { true }
      $0.hotkeyListener.events = { bindings in
        #expect(bindings == [
          HotkeyBinding(hotkey: .testPasteLastTranscript, route: .action(.pasteLastTranscript)),
        ])
        return events
      }
    }
    #expect(store.state.health.degradations.first == .hotkeyTapDead)

    await store.send(.repairRequested(.hotkeyTapDead)) {
      $0.$health.withLock { $0.hotkeyTap = .starting }
    }
    continuation.yield(.monitoringStarted)
    await store.receive(.hotkeyListenerEvent(.monitoringStarted)) {
      $0.$health.withLock { $0.hotkeyTap = .active }
    }
    continuation.finish()
    await store.receive(.hotkeyListenerFinished) {
      $0.$health.withLock { $0.hotkeyTap = .dead }
    }
  }

  @Test func `no configured bindings leaves the listener idle`() async {
    var settings = MiniWhisperSettings.defaults
    settings.bindings.set([], for: .activate)
    settings.bindings.set([], for: .pasteLastTranscript)
    var state = AppFeature.State(
      history: Shared(value: HistoryLog()), settings: Shared(value: settings),
    )
    state.$health.withLock {
      $0.accessibilityGranted = true
      $0.hotkeyTap = .dead
    }
    let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
      $0.hotkeyListener.events = { _ in
        Issue.record("An empty binding set must not install an event tap")
        return AsyncStream { $0.finish() }
      }
    }

    await store.send(.repairRequested(.hotkeyTapDead)) {
      $0.$health.withLock { $0.hotkeyTap = .idle }
    }
  }

  @Test func `A tap the app stood down does not report itself as lost`() async {
    var state = AppFeature.State()
    state.$health.withLock {
      $0.accessibilityGranted = true
      $0.hotkeyTap = .idle
    }
    let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
      $0.accessibilityPermission.hasPermission = {
        Issue.record("An intentionally idle tap must not be diagnosed")
        return true
      }
    }

    await store.send(.hotkeyListenerFinished)
    await store.send(.hotkeyListenerFailed("cancelled"))
  }

  @Test func `startup join forwards engine readiness after its initial snapshot`() async {
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.audioCapture.prepare = { _ in }
      $0.asrEngine.prepareInstalled = {
        AsyncStream { continuation in
          continuation.yield(.compiling)
          continuation.yield(.ready)
          continuation.finish()
        }
      }
      $0.microphonePermission.status = { .granted }
      $0.accessibilityPermission.hasPermission = { false }
      $0.onboardingCompletion.isCompleted = { true }
      $0.modelDownloadConsent.isConsented = { true }
      $0.date.now = Date(timeIntervalSince1970: 1000)
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    let facts = AppFeature.StartupFacts(
      onboardingCompleted: true, modelDownloadConsented: true,
      permissions: OnboardingPermissionStatuses(
        microphoneStatus: .granted, hasAccessibilityPermission: false,
      ),
      engineReadiness: .compiling,
    )

    await store.send(.task)
    await store.receive(.startupResolved(facts)) {
      $0.onboardingCompleted = true
      $0.$health.withLock {
        $0.hotkeyTap = .idle
        $0.micStatus = .granted
        $0.engineReadiness = .ready
      }
    }
    await store.receive(.engineReadinessUpdated(.ready))
    #expect(!store.state.onboarding.isPresented)
    await store.finish()
  }

  @Test func `incomplete startup presents before forwarding later readiness`() async {
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.audioCapture.prepare = { _ in }
      $0.asrEngine.prepareInstalled = {
        AsyncStream { continuation in
          continuation.yield(.compiling)
          continuation.yield(.ready)
          continuation.finish()
        }
      }
      $0.hotkeyListener.events = { _ in AsyncStream { $0.finish() } }
      $0.microphonePermission.status = { .undetermined }
      $0.accessibilityPermission.hasPermission = { false }
      $0.onboardingCompletion.isCompleted = { false }
      $0.modelDownloadConsent.isConsented = { false }
      $0.continuousClock = TestClock()
      $0.date.now = Date(timeIntervalSince1970: 1000)
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    let permissions = OnboardingPermissionStatuses(
      microphoneStatus: .undetermined, hasAccessibilityPermission: false,
    )
    let facts = AppFeature.StartupFacts(
      onboardingCompleted: false, modelDownloadConsented: false, permissions: permissions,
      engineReadiness: .compiling,
    )
    let snapshot = OnboardingSnapshot(
      permissions: permissions, hasModelDownloadConsent: false, isCompleted: false,
    )

    await store.send(.task)
    await store.receive(.startupResolved(facts)) { $0.$health.withLock { $0.hotkeyTap = .idle } }
    await store.receive(.onboarding(.present(snapshot))) {
      $0.onboarding.isPresented = true
      $0.onboarding.snapshot = snapshot
      $0.onboarding.isShowingWelcome = true
    }
    await store
      .receive(.engineReadinessUpdated(.ready)) {
        $0.$health.withLock { $0.engineReadiness = .ready }
      }
    #expect(store.state.onboarding.step == .permissions)

    let granted = OnboardingPermissionStatuses(
      microphoneStatus: .granted, hasAccessibilityPermission: true,
    )
    await store.send(
      .onboarding(
        .permissionStatusesObserved(
          OnboardingPermissionStatuses(
            microphoneStatus: .granted,
            hasAccessibilityPermission: true,
          ),
        ),
      ),
    ) { $0.onboarding.snapshot.permissions = granted }
    await store.finish()
  }

  @Test func `first run presents onboarding from resolved system state`() async {
    let consents = SynchronousCounter()
    let (hotkeyEvents, hotkeyContinuation) = AsyncStream
      .makeStream(of: HotkeyListenerEvent<HotkeyAction>.self)
    var state = AppFeature.State()
    state.$health.withLock {
      $0.hotkeyTap = .idle
      $0.micStatus = .undetermined
    }
    state.onboardingCompleted = false
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.accessibilityPermission.hasPermission = { true }
      $0.continuousClock = TestClock()
      $0.hotkeyListener.events = { _ in hotkeyEvents }
      $0.modelDownloadConsent.markConsented = { consents.increment() }
      $0.asrEngine.installAndPrepare = { AsyncStream { $0.finish() } }
    }
    let snapshot = OnboardingSnapshot(
      permissions: OnboardingPermissionStatuses(
        microphoneStatus: .undetermined, hasAccessibilityPermission: false,
      ),
      hasModelDownloadConsent: false, isCompleted: false,
    )

    await store.send(
      .startupResolved(
        AppFeature.StartupFacts(
          onboardingCompleted: false, modelDownloadConsented: false,
          permissions: snapshot.permissions, engineReadiness: .modelMissing,
        ),
      ),
    )
    await store.receive(.onboarding(.present(snapshot))) {
      $0.onboarding.isPresented = true
      $0.onboarding.snapshot = snapshot
      $0.onboarding.isShowingWelcome = true
    }
    await store.send(.onboarding(.downloadModel)) {
      $0.onboarding.isRecordingModelDownloadConsent = true
      $0.$health.withLock { $0.engineReadiness = .downloading(0) }
    }
    await store.receive(.onboarding(.delegate(.setupModelRequested)))
    await store.receive(.modelDownloadConsentRecorded)
    #expect(consents.value == 1)
    await store.receive(.onboarding(.modelDownloadConsented)) {
      $0.onboarding.snapshot.hasModelDownloadConsent = true
      $0.onboarding.isShowingWelcome = false
      $0.onboarding.isRecordingModelDownloadConsent = false
    }
    #expect(store.state.onboarding.step == .permissions)

    // Observed grants advance the flow in place when macOS exposes them to the running process.
    let granted = OnboardingPermissionStatuses(
      microphoneStatus: .granted, hasAccessibilityPermission: true,
    )
    await store.send(
      .onboarding(
        .permissionStatusesObserved(
          OnboardingPermissionStatuses(
            microphoneStatus: .granted,
            hasAccessibilityPermission: true,
          ),
        ),
      ),
    ) {
      $0.onboarding.snapshot.permissions = granted
      $0.$health.withLock {
        $0.hotkeyTap = .starting
        $0.micStatus = .granted
        $0.accessibilityGranted = true
      }
    }
    await store.receive(.onboarding(.delegate(.permissionsUpdated(granted))))
    hotkeyContinuation.yield(.monitoringStarted)
    await store
      .receive(.hotkeyListenerEvent(.monitoringStarted)) {
        $0.$health.withLock { $0.hotkeyTap = .active }
      }
    #expect(store.state.onboarding.step == .shortcut)

    hotkeyContinuation.finish()
    await store.receive(.hotkeyListenerFinished) { $0.$health.withLock { $0.hotkeyTap = .dead } }
  }

  @Test func `gestures cannot raise permission prompts before the try it step`() async {
    var state = AppFeature.State()
    state.onboardingCompleted = false
    state.onboarding.isPresented = true
    state.onboarding.snapshot = OnboardingSnapshot(
      permissions: OnboardingPermissionStatuses(
        microphoneStatus: .undetermined, hasAccessibilityPermission: false,
      ),
      hasModelDownloadConsent: true, isCompleted: false,
    )
    let store = TestStore(initialState: state) { AppFeature() }

    await store.send(.hotkeyListenerEvent(.gesture(.startRecording)))
    #expect(store.state.recording.phase == .idle)
  }

  @Test func `live capture levels drive the recording pill`() async {
    let sessionID = UUID()
    var state = AppFeature.State()
    state.recording.captureGeneration = 1
    state.recording.captureSessionID = sessionID
    state.recording.phase = .recording
    state.pill.presentation = .recording(
      PillFeature.State.Presentation.Recording(
        inputDeviceName: "Test Microphone", level: 0, isLive: true,
      ),
    )
    let store = TestStore(initialState: state) { AppFeature() }
    let level = AudioLevel(decibels: -12, normalizedPower: 0.8)

    await store.send(.recording(.levelUpdated(1, level))) { $0.recording.latestLevel = 0.8 }
    await store.receive(.recording(.delegate(.levelChanged(0.8))))
    await store.receive(.pill(.levelUpdated(0.8))) {
      $0.pill.presentation = .recording(
        PillFeature.State.Presentation.Recording(
          inputDeviceName: "Test Microphone", level: 0.8, isLive: true,
        ),
      )
      $0.pill.accessibilityLevel = 80
    }
  }

  @Test func `discard recording is silent and leaves no history`() async {
    let sessionID = UUID()
    let sounds = SoundRecorder()
    var state = AppFeature.State()
    state.recording.captureGeneration = 1
    state.recording.captureSessionID = sessionID
    state.recording.phase = .recording
    state.$health.withLock { $0 = .healthy }
    state.onboardingCompleted = true
    state.dictationInFlight = true
    state.pill.presentation = .recording(
      PillFeature.State.Presentation.Recording(
        inputDeviceName: "Test Microphone", level: 0.5, isLive: true,
      ),
    )
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.audioCapture.cancel = { id in #expect(id == sessionID) }
      $0.sounds.play = { name in await sounds.record(name) }
    }

    await store.send(.hotkeyListenerEvent(.gesture(.discardRecording))) {
      $0.dictationInFlight = false
    }
    await store.receive(.recording(.cancelRecording)) { $0.recording.phase = .cancelling }
    await store.receive(.pill(.dismiss)) { $0.pill.presentation = nil }
    await store.receive(.recording(.delegate(.discarded)))
    await store.receive(.pill(.dismiss))
    await store.receive(.recording(.captureCancelled(1))) {
      $0.recording.captureSessionID = nil
      $0.recording.phase = .idle
      $0.recording.latestLevel = 0
    }
    await store.finish()
    #expect(await sounds.recorded.isEmpty)
    #expect(store.state.history.entries.isEmpty)
    #expect(store.state.onboarding.failureMessage == nil)
  }

  @Test func `provisional deadline quietly discards the active capture`() async {
    let sessionID = UUID()
    let sounds = SoundRecorder()
    let clock = TestClock()
    var state = AppFeature.State()
    _ = state.gestureMachine.receive(.activation(at: .zero))
    state.recording.captureGeneration = 1
    state.recording.captureSessionID = sessionID
    state.recording.phase = .recording
    state.dictationInFlight = true
    state.pill.presentation = .recording(
      PillFeature.State.Presentation.Recording(
        inputDeviceName: "Test Microphone", level: 0.2, isLive: true,
      ),
    )
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.audioCapture.cancel = { id in #expect(id == sessionID) }
      $0.continuousClock = clock
      $0.sounds.play = { name in await sounds.record(name) }
    }

    await store.send(.hotkeyListenerEvent(.gestureInput(.release(at: .milliseconds(100))))) {
      _ = $0.gestureMachine.receive(.release(at: .milliseconds(100)))
      $0.gestureDeadlineGeneration = 1
    }
    await clock.advance(by: state.gestureMachine.timing.doubleTapWindow)
    await store.receive(.gestureDeadlineElapsed(1)) {
      _ = $0.gestureMachine.receive(.deadlineElapsed)
    }
    await store.receive(.hotkeyListenerEvent(.gesture(.discardRecording))) {
      $0.dictationInFlight = false
    }
    await store.receive(.recording(.cancelRecording)) { $0.recording.phase = .cancelling }
    await store.receive(.pill(.dismiss)) { $0.pill.presentation = nil }
    await store.receive(.recording(.delegate(.discarded)))
    await store.receive(.pill(.dismiss))
    await store.receive(.recording(.captureCancelled(1))) {
      $0.recording.captureSessionID = nil
      $0.recording.phase = .idle
      $0.recording.latestLevel = 0
    }
    await store.finish()
    #expect(await sounds.recorded.isEmpty)
  }

  @Test func `too short quietly dismisses without sound notice or onboarding failure`() async {
    let sounds = SoundRecorder()
    var state = AppFeature.State()
    state.transcriptionGeneration = 1
    state.dictationInFlight = true
    state.pill.presentation = .transcribing
    state.onboarding.isPresented = true
    state.onboarding.snapshot = OnboardingSnapshot(
      permissions: OnboardingPermissionStatuses(
        microphoneStatus: .granted, hasAccessibilityPermission: true,
      ),
      hasModelDownloadConsent: true, isCompleted: false,
    )
    state.onboarding.hasCompletedShortcut = true
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.sounds.play = { name in await sounds.record(name) }
    }

    await store.send(.transcriptionCompleted(1, .tooShort)) {
      $0.dictationInFlight = false
    }
    await store.receive(.pill(.dismiss)) { $0.pill.presentation = nil }
    await store.finish()
    #expect(await sounds.recorded.isEmpty)
    #expect(store.state.onboarding.failureMessage == nil)
  }

  @Test func `genuine no speech keeps its notice and cancel cue`() async {
    let sounds = SoundRecorder()
    let clock = TestClock()
    var state = AppFeature.State()
    state.transcriptionGeneration = 1
    state.dictationInFlight = true
    state.pill.presentation = .transcribing
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.sounds.play = { name in await sounds.record(name) }
    }

    await store.send(.transcriptionCompleted(1, .noSpeech)) {
      $0.dictationInFlight = false
    }
    await store.receive(.pill(.noSpeechDetected)) {
      $0.pill.noticeGeneration = 1
      $0.pill.presentation = .notice(.noSpeechDetected)
    }
    await store.send(.pill(.dismiss)) { $0.pill.presentation = nil }
    await store.finish()
    #expect(await sounds.recorded == ["Funk"])
  }

  @Test func `transcription failure degrades engine and does not claim no speech`() async {
    var state = AppFeature.State()
    state.$health.withLock { $0.engineReadiness = .ready }
    state.transcriptionGeneration = 2
    state.pill.presentation = .transcribing
    let store = TestStore(initialState: state) { AppFeature() }

    await store.send(.transcriptionFailed(2, "model failure")) {
      $0.$health.withLock { $0.engineReadiness = .failed("model failure") }
    }
    await store.receive(.pill(.dismiss)) { $0.pill.presentation = nil }
  }

  @Test func `repeated engine failure plays the error cue only once`() async {
    let sounds = SoundRecorder()
    var state = AppFeature.State()
    state.$health.withLock { $0.engineReadiness = .ready }
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.sounds.play = { cue in await sounds.record(cue) }
    }

    await store.send(.engineReadinessUpdated(.failed("first failure"))) {
      $0.$health.withLock { $0.engineReadiness = .failed("first failure") }
    }
    await store.send(.engineReadinessUpdated(.failed("second failure"))) {
      $0.$health.withLock { $0.engineReadiness = .failed("second failure") }
    }
    await store.finish()
    #expect(await sounds.recorded == ["Basso"])
  }

  @Test func `stale transcription cannot dismiss A newer recording`() async {
    var state = AppFeature.State()
    state.transcriptionGeneration = 3
    state.pill.presentation = .recording(
      PillFeature.State.Presentation.Recording(
        inputDeviceName: "New Microphone", level: 0, isLive: true,
      ),
    )
    let store = TestStore(initialState: state) { AppFeature() }

    await store.send(
      .transcriptionCompleted(2, .transcript("stale")),
    )
  }

  @Test func `transcript delivery restores clipboard and commits`() async {
    let sounds = SoundRecorder()
    // The captured field ends in a sentence, so the joined paste gains a space and a capital.
    let captured = ContextCapture.available(context(before: "We arrived at noon."))
    var state = AppFeature.State()
    state.transcriptionGeneration = 1
    state.pill.presentation = .transcribing
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.contextCapture.capture = { _ in captured }
      $0.delivery.deliver = { transcript in
        #expect(transcript == " Delivered text")
        return .pasted(.restored)
      }
      $0.sounds.play = { cue in await sounds.record(cue) }
    }

    await store.send(
      .transcriptionCompleted(1, .transcript("delivered text")),
    ) { $0.lastTranscript = "delivered text" }
    await store.receive(.contextCaptured(1, captured)) { $0.currentFocusedContext = captured }
    await store.receive(
      .deliveryCompleted(
        1, deliveryResult(" Delivered text", .pasted(.restored)),
      ),
    ) {
      $0.currentFocusedContext = nil
    }
    await store.receive(.pill(.dismiss)) { $0.pill.presentation = nil }
    await store.finish()
    #expect(await sounds.recorded == ["Pop"])
  }

  @Test func `release warms the field but delivery joins against A fresh read`() async {
    let captures = CaptureSequence(captures: [
      // What the release-time read saw, before the user kept typing during transcription.
      .available(context(before: "we were still typing")),
      .available(context(before: "We were still typing.")),
    ])
    var state = AppFeature.State()
    state.transcriptionGeneration = 1
    state.$health.withLock { $0 = .healthy }
    state.onboardingCompleted = true
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.contextCapture.capture = { _ in await captures.next() }
      // Only the delivery-time read can produce this joined text.
      $0.delivery.deliver = { transcript in
        #expect(transcript == " Delivered text")
        return .pasted(.restored)
      }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.hotkeyListenerEvent(.gesture(.stopAndTranscribe)))
    await store.send(
      .transcriptionCompleted(1, .transcript("delivered text")),
    )
    await store.receive(.contextCaptured(1, .available(context(before: "We were still typing.")))) {
      $0.currentFocusedContext = .available(context(before: "We were still typing."))
    }
    await store.receive(
      .deliveryCompleted(
        1, deliveryResult(" Delivered text", .pasted(.restored)),
      ),
    )
    await store.finish()
    // One warm-up read at release, one authoritative read at delivery.
    #expect(await captures.taken == 2)
  }

  @Test func `a second release replaces the warm up without delivering twice`() async {
    let deliveries = PrewarmCounter()
    let captures = CaptureSequence(captures: [
      .unavailable(.noFocusedElement), .unavailable(.noFocusedElement),
      .available(context(before: "Field text.")),
    ])
    var state = AppFeature.State()
    state.transcriptionGeneration = 1
    state.$health.withLock { $0 = .healthy }
    state.onboardingCompleted = true
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.contextCapture.capture = { _ in await captures.next() }
      $0.delivery.deliver = { _ in
        await deliveries.record()
        return .pasted(.restored)
      }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    // A key that bounces on release must not turn one dictation into two pastes.
    await store.send(.hotkeyListenerEvent(.gesture(.stopAndTranscribe)))
    await store.send(.hotkeyListenerEvent(.gesture(.stopAndTranscribe)))
    await store.send(
      .transcriptionCompleted(1, .transcript("delivered text")),
    )
    await store.receive(.contextCaptured(1, .available(context(before: "Field text."))))
    await store.receive(
      .deliveryCompleted(
        1, deliveryResult(" Delivered text", .pasted(.restored)),
      ),
    )
    await store.finish()
    #expect(await deliveries.count == 1)
  }

  @Test func `cancel and archive saves transcript without delivery`() async throws {
    let sessionID = UUID()
    let entryID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000031"))
    let recording = CanonicalRecording(samples: Array(repeating: 0.2, count: 16000))
    let sounds = SoundRecorder()
    let clock = TestClock()
    var settings = MiniWhisperSettings.defaults
    settings.retention.audio = .never
    var state = AppFeature.State(
      history: Shared(value: HistoryLog()), settings: Shared(value: settings),
    )
    state.transcriptionGeneration = 1
    state.$health.withLock { $0 = .healthy }
    state.onboardingCompleted = true
    state.dictationInFlight = true
    state.recording.captureGeneration = 1
    state.recording.captureSessionID = sessionID
    state.recording.phase = .recording
    state.currentFocusedContext = .available(context(before: "Never deliver here."))
    state.pill.presentation = .recording(
      PillFeature.State.Presentation.Recording(
        inputDeviceName: "Test Microphone", level: 0.2, isLive: true,
      ),
    )
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.asrEngine.identity = { "parakeet-tdt-0.6b-v2" }
      $0.asrEngine.submit = { _, _ in .transcript("recoverable words") }
      $0.audioCapture.stop = { id in
        #expect(id == sessionID)
        return recording
      }
      $0.contextCapture.capture = { _ in
        Issue.record("Cancelled dictation must not capture a delivery target")
        return .unavailable(.noFocusedElement)
      }
      $0.continuousClock = clock
      $0.date.now = Date(timeIntervalSince1970: 31)
      $0.delivery.deliver = { _ in
        Issue.record("Cancelled dictation must not attempt delivery")
        return .pasted(.restored)
      }
      $0.sounds.play = { name in await sounds.record(name) }
      $0.uuid = .constant(entryID)
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.hotkeyListenerEvent(.gesture(.cancelAndArchive))) {
      $0.dictationWasCancelled = true
      $0.currentFocusedContext = nil
    }
    await store.receive(.recording(.stopAndRetain)) { $0.recording.phase = .stopping(nil) }
    await store.receive(.recording(.captureStopped(1, recording))) {
      $0.recording.captureSessionID = nil
      $0.recording.phase = .idle
      $0.recording.latestLevel = 0
    }
    await store.receive(.recording(.delegate(.completed(recording)))) {
      $0.pendingDictation = AppFeature.PendingDictation(
        generation: 1, recording: recording, createdAt: Date(timeIntervalSince1970: 31),
        engine: "parakeet-tdt-0.6b-v2", original: nil,
      )
    }
    await store.receive(.pill(.transcribingStarted)) { $0.pill.presentation = .transcribing }
    await store.receive(.transcriptionCompleted(1, .transcript("recoverable words"))) {
      $0.lastTranscript = "recoverable words"
      $0.pendingDictation?.original = History.Transcription(
        text: "recoverable words", engine: "parakeet-tdt-0.6b-v2",
        transcribedAt: Date(timeIntervalSince1970: 31),
      )
      $0.pendingDictation?.isFinishing = true
    }
    await store.receive(.pill(.cancelledSavedToHistory)) {
      $0.pill.noticeGeneration = 1
      $0.pill.presentation = .notice(.cancelledSavedToHistory)
    }
    let historyEntry = HistoryEntry(
      id: entryID, createdAt: Date(timeIntervalSince1970: 31), targetApp: nil,
      original: History.Transcription(
        text: "recoverable words", engine: "parakeet-tdt-0.6b-v2",
        transcribedAt: Date(timeIntervalSince1970: 31),
      ),
      delivery: nil, audio: nil,
    )
    await store.receive(.historyEntryPrepared(1, historyEntry))
    await store.send(.pill(.dismiss)) { $0.pill.presentation = nil }
    await store.finish()
    #expect(await sounds.recorded == ["Funk"])
    #expect(store.state.history.entries == [historyEntry])
    #expect(store.state.onboarding.failureMessage == nil)
  }

  @Test(arguments: [TranscriptionOutcome.noSpeech, .tooShort])
  func `cancel and archive rejects unusable audio quietly`(_ outcome: TranscriptionOutcome) async {
    let sounds = SoundRecorder()
    var state = AppFeature.State()
    state.transcriptionGeneration = 1
    state.dictationInFlight = true
    state.onboardingCompleted = true
    state.pill.presentation = .transcribing
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.sounds.play = { name in await sounds.record(name) }
    }

    await store.send(.hotkeyListenerEvent(.gesture(.cancelAndArchive))) {
      $0.dictationWasCancelled = true
    }
    await store.receive(.recording(.stopAndRetain))
    await store.send(.transcriptionCompleted(1, outcome)) { $0.dictationInFlight = false }
    await store.receive(.pill(.dismiss)) { $0.pill.presentation = nil }
    await store.finish()
    #expect(await sounds.recorded == ["Funk"])
    #expect(store.state.history.entries.isEmpty)
    #expect(store.state.onboarding.failureMessage == nil)
  }

  @Test func `rejected audio drops A capture still in flight without delivering`() async {
    let deliveries = PrewarmCounter()
    let (gate, openGate) = AsyncStream.makeStream(of: Void.self)
    var state = AppFeature.State()
    state.transcriptionGeneration = 1
    state.$health.withLock { $0 = .healthy }
    state.onboardingCompleted = true
    state.pill.presentation = .transcribing
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.contextCapture.capture = { _ in
        for await _ in gate {}
        return .unavailable(.noFocusedElement)
      }
      $0.delivery.deliver = { _ in
        await deliveries.record()
        return .pasted(.restored)
      }
      $0.continuousClock = TestClock()
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.hotkeyListenerEvent(.gesture(.stopAndTranscribe)))
    await store.send(.transcriptionCompleted(1, .noSpeech))
    openGate.finish()
    await store.send(.pill(.dismiss))
    await store.finish()
    #expect(await deliveries.isEmpty)
    #expect(store.state.currentFocusedContext == nil)
  }

  @Test func `a failed transcription drops the capture running beside it`() async {
    let deliveries = PrewarmCounter()
    let (gate, openGate) = AsyncStream.makeStream(of: Void.self)
    var state = AppFeature.State()
    state.transcriptionGeneration = 1
    state.$health.withLock { $0 = .healthy }
    state.onboardingCompleted = true
    state.pill.presentation = .transcribing
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.contextCapture.capture = { _ in
        for await _ in gate {}
        return .unavailable(.noFocusedElement)
      }
      $0.delivery.deliver = { _ in
        await deliveries.record()
        return .pasted(.restored)
      }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.hotkeyListenerEvent(.gesture(.stopAndTranscribe)))
    await store.send(.transcriptionFailed(1, "model failure"))
    openGate.finish()
    await store.finish()
    #expect(await deliveries.isEmpty)
  }

  @Test func `a discarded recording drops the capture it started`() async {
    let deliveries = PrewarmCounter()
    let (gate, openGate) = AsyncStream.makeStream(of: Void.self)
    var state = AppFeature.State()
    state.transcriptionGeneration = 1
    state.$health.withLock { $0 = .healthy }
    state.onboardingCompleted = true
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.contextCapture.capture = { _ in
        for await _ in gate {}
        return .unavailable(.noFocusedElement)
      }
      $0.delivery.deliver = { _ in
        await deliveries.record()
        return .pasted(.restored)
      }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.hotkeyListenerEvent(.gesture(.stopAndTranscribe)))
    await store.send(.recording(.delegate(.discarded)))
    openGate.finish()
    await store.finish()
    #expect(await deliveries.isEmpty)
  }

  @Test func `a stalled capture cannot paste into the dictation that replaced it`() async {
    let (gate, openGate) = AsyncStream.makeStream(of: Void.self)
    let deliveries = PrewarmCounter()
    var state = AppFeature.State()
    state.transcriptionGeneration = 1
    state.$health.withLock { $0 = .healthy }
    state.onboardingCompleted = true
    state.pill.presentation = .transcribing
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.contextCapture.capture = { _ in
        for await _ in gate {}
        return .unavailable(.noFocusedElement)
      }
      $0.contextCapture.prewarmFrontmostApp = {}
      $0.delivery.deliver = { _ in
        await deliveries.record()
        return .pasted(.restored)
      }
      $0.audioCapture.start = { _ in
        AudioCaptureSession(
          id: UUID(), inputDeviceName: "Test Microphone", events: AsyncStream { $0.finish() },
        )
      }
      $0.audioCapture.cancel = { _ in }
      $0.audioCapture.currentInputDeviceName = { _ in "Test Microphone" }
      $0.asrEngine.prepareForActivation = { AsyncStream { $0.finish() } }
      $0.continuousClock = TestClock()
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(
      .transcriptionCompleted(1, .transcript("late arrival")),
    )
    await store.send(.hotkeyListenerEvent(.gesture(.startRecording)))
    openGate.finish()
    await store.finish()
    #expect(await deliveries.isEmpty)
    #expect(store.state.currentFocusedContext == nil)
  }

  @Test func `unavailable context pastes blind and says so`() async {
    let sounds = SoundRecorder()
    let clock = TestClock()
    var state = AppFeature.State()
    state.transcriptionGeneration = 1
    state.pill.presentation = .transcribing
    let unavailable = ContextCapture.unavailable(.gridSemantics(bundleID: "com.mitchellh.ghostty"))
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.contextCapture.capture = { _ in unavailable }
      $0.delivery.deliver = { transcript in
        #expect(transcript == "delivered text")
        return .pasted(.restored)
      }
      $0.sounds.play = { cue in await sounds.record(cue) }
      $0.continuousClock = clock
    }

    await store.send(
      .transcriptionCompleted(1, .transcript("delivered text")),
    ) { $0.lastTranscript = "delivered text" }
    await store.receive(.contextCaptured(1, unavailable)) { $0.currentFocusedContext = unavailable }
    await store.receive(
      .deliveryCompleted(
        1, deliveryResult("delivered text", .pasted(.restored)),
      ),
    ) {
      $0.currentFocusedContext = nil
    }
    await store.receive(.pill(.fieldContextUnavailable)) {
      $0.pill.noticeGeneration = 1
      $0.pill.presentation = .notice(.fieldContextUnavailable)
    }
    await store.send(.pill(.dismiss)) { $0.pill.presentation = nil }
    await store.finish()
    #expect(await sounds.recorded == ["Pop"])
  }

  @Test(arguments: [
    ContextUnavailable.noFocusedElement,
    .nonTextElement(role: "AXButton"),
  ])
  func `delivery is withheld when context proves there is no receiver`(
    _ reason: ContextUnavailable,
  ) async {
    let clock = TestClock()
    var state = AppFeature.State()
    state.transcriptionGeneration = 1
    state.pill.presentation = .transcribing
    let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
      $0.contextCapture.capture = { _ in .unavailable(reason) }
      $0.continuousClock = clock
      $0.delivery.copy = { _ in
        Issue.record("A delivery with no receiver must not change the clipboard")
      }
      $0.delivery.deliver = { _ in
        Issue.record("A delivery with no receiver must not synthesize paste")
        return .pasted(.restored)
      }
    }

    await store.send(.transcriptionCompleted(1, .transcript("copy me"))) {
      $0.lastTranscript = "copy me"
    }
    await store.receive(.contextCaptured(1, .unavailable(reason))) {
      $0.currentFocusedContext = .unavailable(reason)
    }
    let receiverReason: NoReceiverReason =
      switch reason {
      case .noFocusedElement:
        .noFocusedElement
      case let .nonTextElement(role):
        .nonTextElement(role: role)
      default:
        preconditionFailure()
      }
    await store.receive(
      .deliveryCompleted(
        1, deliveryResult("copy me", .noReceiver(receiverReason)),
      ),
    ) {
      $0.currentFocusedContext = nil
    }
    let pasteShortcut = HotkeyBindingsSettings.defaults
      .hotkeys(for: .pasteLastTranscript)
      .first?
      .compactDisplayName
    await store.receive(.pill(.noReceiver(pasteShortcut: pasteShortcut))) {
      $0.pill.noticeGeneration = 1
      $0.pill.presentation = .notice(.noReceiver(pasteShortcut: pasteShortcut))
    }
    await store.send(.pill(.dismiss)) { $0.pill.presentation = nil }
    await store.finish()
  }

  @Test func `a no receiver first delivery is observable in history`() async throws {
    let entryID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000032"))
    let recording = CanonicalRecording(samples: Array(repeating: 0.2, count: 16000))
    var settings = MiniWhisperSettings.defaults
    settings.retention.audio = .never
    var state = AppFeature.State(
      history: Shared(value: HistoryLog()), settings: Shared(value: settings),
    )
    state.transcriptionGeneration = 1
    state.dictationInFlight = true
    state.pendingDictation = AppFeature.PendingDictation(
      generation: 1, recording: recording, createdAt: Date(timeIntervalSince1970: 32),
      engine: "test-engine", original: nil,
    )
    let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
      $0.contextCapture.capture = { _ in .unavailable(.noFocusedElement) }
      $0.continuousClock = TestClock()
      $0.date.now = Date(timeIntervalSince1970: 32)
      $0.delivery.copy = { _ in
        Issue.record("A delivery with no receiver must not change the clipboard")
      }
      $0.delivery.deliver = { _ in
        Issue.record("A delivery with no receiver must not synthesize paste")
        return .pasted(.restored)
      }
      $0.uuid = .constant(entryID)
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.transcriptionCompleted(1, .transcript("recoverable")))
    await store.receive(
      .pill(
        .noReceiver(
          pasteShortcut: HotkeyBindingsSettings.defaults
            .hotkeys(for: .pasteLastTranscript)
            .first?
            .compactDisplayName,
        ),
      ),
    )
    await store.send(.pill(.dismiss))
    await store.finish()

    let entry = try #require(store.state.history.entries.first)
    #expect(entry.delivery == Delivery(
      text: "recoverable", method: .noReceiver, detail: "noFocusedElement",
    ))
  }

  @Test func `recovery prefers memory and runs the full delivery pipeline`() async {
    let deliveries = StringRecorder()
    let historyEntry = HistoryEntry(
      id: UUID(), createdAt: Date(timeIntervalSince1970: 1), targetApp: nil,
      original: History.Transcription(
        text: "persisted text", engine: "test-engine",
        transcribedAt: Date(timeIntervalSince1970: 1),
      ),
      delivery: nil, audio: nil,
    )
    var state = AppFeature.State(history: Shared(value: HistoryLog(entries: [historyEntry])))
    state.lastTranscript = "memory text"
    let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
      $0.contextCapture.capture = { _ in .available(context(before: "Finished.")) }
      $0.delivery.deliver = { transcript in
        await deliveries.record(transcript)
        return .pasted(.restored)
      }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.hotkeyListenerEvent(.action(.pasteLastTranscript)))
    await store.finish()

    #expect(await deliveries.values == [" Memory text"])
    #expect(store.state.history.entries == [historyEntry])
    #expect(store.state.pill.presentation == nil)
  }

  @Test func `recovery with no receiver withholds and names the configured chord`() async throws {
    let pasteHotkey = try Hotkey(keyCode: 15, modifiers: [.leftControl, .rightCommand])
    let sounds = SoundRecorder()
    var settings = MiniWhisperSettings.defaults
    settings.bindings.set([pasteHotkey], for: .pasteLastTranscript)
    var state = AppFeature.State(settings: Shared(value: settings))
    state.lastTranscript = "withhold me"
    let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
      $0.contextCapture.capture = { _ in .unavailable(.noFocusedElement) }
      $0.continuousClock = TestClock()
      $0.delivery.copy = { _ in
        Issue.record("Recovery with no receiver must not change the clipboard")
      }
      $0.delivery.deliver = { _ in
        Issue.record("Recovery with no receiver must not synthesize paste")
        return .pasted(.restored)
      }
      $0.sounds.play = { cue in await sounds.record(cue) }
    }

    await store.send(.hotkeyListenerEvent(.action(.pasteLastTranscript)))
    await store.receive(.pasteLastTranscript)
    await store.receive(
      .recoveryDeliveryCompleted(
        deliveryResult("withhold me", .noReceiver(.noFocusedElement)),
      ),
    )
    await store.receive(
      .pill(.noReceiver(pasteShortcut: pasteHotkey.compactDisplayName)),
    ) {
      $0.pill.noticeGeneration = 1
      $0.pill.presentation = .notice(
        .noReceiver(pasteShortcut: pasteHotkey.compactDisplayName),
      )
    }
    await store.send(.pill(.dismiss)) { $0.pill.presentation = nil }
    await store.finish()

    #expect(await sounds.recorded == ["Basso"])
    #expect(store.state.history.entries.isEmpty)
  }

  @Test func `recovery falls back to history after relaunch`() async {
    let deliveries = StringRecorder()
    let historyEntry = HistoryEntry(
      id: UUID(), createdAt: Date(timeIntervalSince1970: 1), targetApp: nil,
      original: History.Transcription(
        text: "persisted text", engine: "test-engine",
        transcribedAt: Date(timeIntervalSince1970: 1),
      ),
      delivery: nil, audio: nil,
    )
    let state = AppFeature.State(history: Shared(value: HistoryLog(entries: [historyEntry])))
    let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
      $0.contextCapture.capture = { _ in .unavailable(.noTextRange(role: "AXTextArea")) }
      $0.delivery.deliver = { transcript in
        await deliveries.record(transcript)
        return .pasted(.restored)
      }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.hotkeyListenerEvent(.action(.pasteLastTranscript)))
    await store.finish()

    #expect(await deliveries.values == ["persisted text"])
    #expect(store.state.history.entries == [historyEntry])
  }

  @Test func `recovery with no source shows its empty notice`() async {
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.continuousClock = TestClock()
    }

    await store.send(.hotkeyListenerEvent(.action(.pasteLastTranscript)))
    await store.receive(.pasteLastTranscript)
    await store.receive(.pill(.noTranscriptToPaste)) {
      $0.pill.noticeGeneration = 1
      $0.pill.presentation = .notice(.noTranscriptToPaste)
    }
    await store.send(.pill(.dismiss)) { $0.pill.presentation = nil }
    await store.finish()
  }

  @Test func `recovery is ignored while dictation is in flight`() async {
    let deliveries = StringRecorder()
    var state = AppFeature.State()
    state.lastTranscript = "do not deliver"
    state.dictationInFlight = true
    let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
      $0.delivery.deliver = { transcript in
        await deliveries.record(transcript)
        return .pasted(.restored)
      }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.hotkeyListenerEvent(.action(.pasteLastTranscript)))
    await store.finish()

    #expect(await deliveries.values.isEmpty)
  }

  @Test func `changed clipboard skips restore without turning paste into failure`() async {
    let sounds = SoundRecorder()
    var state = AppFeature.State()
    state.transcriptionGeneration = 2
    state.pill.presentation = .transcribing
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.sounds.play = { cue in await sounds.record(cue) }
    }

    await store.send(
      .deliveryCompleted(
        2, deliveryResult("", .pasted(.skipped)),
      ),
    )
    await store.receive(.pill(.dismiss)) { $0.pill.presentation = nil }
    await store.finish()
    #expect(await sounds.recorded == ["Pop"])
  }

  @Test func `missing accessibility keeps transcript copied and shows fallback`() async {
    let sounds = SoundRecorder()
    let clock = TestClock()
    var state = AppFeature.State()
    state.transcriptionGeneration = 3
    state.pill.presentation = .transcribing
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.contextCapture.capture = { _ in .unavailable(.accessibilityPermissionMissing) }
      $0.delivery.deliver = { _ in .copied(.accessibilityPermissionMissing) }
      $0.sounds.play = { cue in await sounds.record(cue) }
      $0.continuousClock = clock
    }

    await store.send(
      .transcriptionCompleted(3, .transcript("copy me")),
    ) { $0.lastTranscript = "copy me" }
    await store.receive(.contextCaptured(3, .unavailable(.accessibilityPermissionMissing))) {
      $0.currentFocusedContext = .unavailable(.accessibilityPermissionMissing)
    }
    await store.receive(
      .deliveryCompleted(
        3,
        deliveryResult("copy me", .copied(.accessibilityPermissionMissing)),
      ),
    ) {
      $0.currentFocusedContext = nil
    }
    await store.receive(.pill(.copiedToClipboard)) {
      $0.pill.noticeGeneration = 1
      $0.pill.presentation = .notice(.copiedToClipboard)
    }
    await store.send(.pill(.dismiss)) { $0.pill.presentation = nil }
    await store.finish()
    #expect(await sounds.recorded == ["Basso"])
  }

  @Test func `recording start cues while a later discard stays quiet`() async {
    let sounds = SoundRecorder()
    let prewarms = PrewarmCounter()
    var state = AppFeature.State()
    state.recording.phase = .recording
    state.$health.withLock { $0 = .healthy }
    state.onboardingCompleted = true
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.audioCapture.currentInputDeviceName = { _ in "Microphone" }
      $0.asrEngine.prepareForActivation = { AsyncStream { $0.finish() } }
      $0.contextCapture.prewarmFrontmostApp = { await prewarms.record() }
      $0.sounds.play = { cue in await sounds.record(cue) }
    }

    await store
      .send(.hotkeyListenerEvent(.gesture(.startRecording))) {
        $0.transcriptionGeneration = 1
        $0.dictationInFlight = true
      }
    await store.receive(.pill(.recordingStarting(inputDeviceName: "Microphone"))) {
      $0.pill.presentation = .recording(
        PillFeature.State.Presentation.Recording(
          inputDeviceName: "Microphone", level: 0, isLive: false,
        ),
      )
    }
    await store.receive(.recording(.startRecording))
    await store.send(.recording(.delegate(.discarded))) { $0.dictationInFlight = false }
    await store.receive(.pill(.dismiss)) { $0.pill.presentation = nil }
    await store.finish()
    #expect(await sounds.recorded == ["Tink"])
    // Chromium's wake walk belongs to recording start, never to delivery.
    #expect(await prewarms.count == 1)
  }

  @Test func `double tap keeps one continuous capture and one onset cue`() async {
    let (captureEvents, captureContinuation) = AsyncStream.makeStream(of: AudioCaptureEvent.self)
    let sessionID = UUID()
    let historyID = UUID()
    let recording = CanonicalRecording(samples: Array(repeating: 0.314, count: 16000))
    let starts = PrewarmCounter()
    let stops = PrewarmCounter()
    let sounds = SoundRecorder()
    let clock = TestClock()
    var state = AppFeature.State()
    state.$settings.withLock { $0.retention.audio = .never }
    state.$dictionary.withLock {
      $0 = DictionaryContents(
        vocabulary: [VocabularyEntry(text: "TCA", addedAt: Date(timeIntervalSince1970: 1))],
        corrections: [
          CorrectionEntry(
            misspelling: "mini whisper", text: "MiniWhisper",
            addedAt: Date(timeIntervalSince1970: 1),
          ),
        ],
      )
    }
    state.$health.withLock { $0 = .healthy }
    state.onboardingCompleted = true
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.audioCapture.start = { _ in
        await starts.record()
        return AudioCaptureSession(
          id: sessionID, inputDeviceName: "Microphone", events: captureEvents,
        )
      }
      $0.audioCapture.stop = { id in
        #expect(id == sessionID)
        await stops.record()
        return recording
      }
      $0.audioCapture.currentInputDeviceName = { _ in "Microphone" }
      $0.asrEngine.identity = { "test-engine" }
      $0.asrEngine.prepareForActivation = { AsyncStream { $0.finish() } }
      $0.asrEngine.submit = { submitted, dictionary in
        #expect(submitted == recording)
        #expect(dictionary.vocabulary.map(\.text) == ["TCA"])
        #expect(dictionary.corrections.map(\.misspelling) == ["mini whisper"])
        #expect(dictionary.corrections.map(\.text) == ["MiniWhisper"])
        return .transcript("continuous capture")
      }
      $0.contextCapture.prewarmFrontmostApp = {}
      $0.continuousClock = clock
      $0.date.now = Date(timeIntervalSince1970: 40)
      $0.delivery.deliver = { _ in .pasted(.restored) }
      $0.sounds.play = { name in await sounds.record(name) }
      $0.uuid = .constant(historyID)
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.hotkeyListenerEvent(.gestureInput(.activation(at: .zero)))) {
      $0.gestureMachine = HotkeyGestureMachine()
      _ = $0.gestureMachine.receive(.activation(at: .zero))
    }
    await store.receive(.hotkeyListenerEvent(.gesture(.startRecording))) {
      $0.transcriptionGeneration = 1
      $0.dictationInFlight = true
    }
    await store.receive(.pill(.recordingStarting(inputDeviceName: "Microphone"))) {
      $0.pill.presentation = .recording(
        PillFeature.State.Presentation.Recording(
          inputDeviceName: "Microphone", level: 0, isLive: false,
        ),
      )
    }
    await store.receive(.recording(.startRecording)) {
      $0.recording.captureGeneration = 1
      $0.recording.phase = .starting(nil)
    }
    await store.receive(.recording(.captureSessionStarted(1, sessionID))) {
      $0.recording.captureSessionID = sessionID
    }
    captureContinuation.yield(.captureBecameLive)
    await store.receive(.recording(.captureBecameLive(1, sessionID, "Microphone"))) {
      $0.recording.phase = .recording
    }
    await store.receive(.recording(.delegate(.recordingStarted(inputDeviceName: "Microphone"))))
    await store.receive(.pill(.recordingStarted(inputDeviceName: "Microphone"))) {
      $0.pill.presentation = .recording(
        PillFeature.State.Presentation.Recording(
          inputDeviceName: "Microphone", level: 0, isLive: true,
        ),
      )
    }

    await store.send(.hotkeyListenerEvent(.gestureInput(.release(at: .milliseconds(100))))) {
      $0.gestureMachine = HotkeyGestureMachine()
      _ = $0.gestureMachine.receive(.activation(at: .zero))
      _ = $0.gestureMachine.receive(.release(at: .milliseconds(100)))
      $0.gestureDeadlineGeneration = 1
    }
    #expect(
      store.state.pill.presentation == .recording(
        PillFeature.State.Presentation.Recording(
          inputDeviceName: "Microphone", level: 0, isLive: true,
        ),
      ),
    )
    await store.send(.hotkeyListenerEvent(.gestureInput(.activation(at: .milliseconds(200))))) {
      _ = $0.gestureMachine.receive(.activation(at: .milliseconds(200)))
    }
    await clock.advance(by: store.state.gestureMachine.timing.doubleTapWindow)
    await store.send(.hotkeyListenerEvent(.gestureInput(.release(at: .milliseconds(300))))) {
      _ = $0.gestureMachine.receive(.release(at: .milliseconds(300)))
    }
    await store.receive(.hotkeyListenerEvent(.gesture(.latchEngaged)))
    await store.receive(.pill(.latchEngaged)) { $0.pill.bounceCount = 1 }
    #expect(
      store.state.pill.presentation == .recording(
        PillFeature.State.Presentation.Recording(
          inputDeviceName: "Microphone", level: 0, isLive: true,
        ),
      ),
    )

    await store.send(.hotkeyListenerEvent(.gestureInput(.activation(at: .milliseconds(500))))) {
      _ = $0.gestureMachine.receive(.activation(at: .milliseconds(500)))
    }
    await store.receive(.hotkeyListenerEvent(.gesture(.stopAndTranscribe)))
    await store.receive(.recording(.stopAndRetain)) { $0.recording.phase = .stopping(nil) }
    await store.receive(.recording(.captureStopped(1, recording))) {
      $0.recording.captureSessionID = nil
      $0.recording.phase = .idle
      $0.recording.latestLevel = 0
    }
    await store.receive(.recording(.delegate(.completed(recording))))
    await store.receive(.pill(.transcribingStarted)) { $0.pill.presentation = .transcribing }
    await store.receive(.transcriptionCompleted(1, .transcript("continuous capture"))) {
      $0.lastTranscript = "continuous capture"
      $0.pendingDictation?.original = History.Transcription(
        text: "continuous capture", engine: "test-engine",
        transcribedAt: Date(timeIntervalSince1970: 40),
      )
    }
    captureContinuation.finish()
    await store.finish()
    #expect(await starts.count == 1)
    #expect(await stops.count == 1)
    let recordedSounds = await sounds.recorded
    #expect(recordedSounds.count(where: { $0 == "Tink" }) == 1)
    #expect(!recordedSounds.contains("Funk"))
  }

  @Test func `secure input uses the copied fallback`() async {
    let sounds = SoundRecorder()
    let clock = TestClock()
    var state = AppFeature.State()
    state.transcriptionGeneration = 4
    state.pill.presentation = .transcribing
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.sounds.play = { cue in await sounds.record(cue) }
      $0.continuousClock = clock
    }

    await store.send(
      .deliveryCompleted(
        4, deliveryResult("", .copied(.secureInput)),
      ),
    )
    await store.receive(.pill(.copiedToClipboard)) {
      $0.pill.noticeGeneration = 1
      $0.pill.presentation = .notice(.copiedToClipboard)
    }
    await store.send(.pill(.dismiss)) { $0.pill.presentation = nil }
    await store.finish()
    #expect(await sounds.recorded == ["Basso"])
  }

  @Test func `delivery failure dismisses the pill and plays the error cue`() async {
    let sounds = SoundRecorder()
    var state = AppFeature.State()
    state.transcriptionGeneration = 5
    state.pill.presentation = .transcribing
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.contextCapture.capture = { _ in .unavailable(.noTextRange(role: "AXTextArea")) }
      $0.delivery.deliver = { _ in throw DeliveryError.pasteboardWriteFailed }
      $0.sounds.play = { cue in await sounds.record(cue) }
    }
    let message = DeliveryError.pasteboardWriteFailed.localizedDescription

    await store.send(
      .transcriptionCompleted(5, .transcript("undeliverable")),
    ) { $0.lastTranscript = "undeliverable" }
    await store.receive(.contextCaptured(5, .unavailable(.noTextRange(role: "AXTextArea")))) {
      $0.currentFocusedContext = .unavailable(.noTextRange(role: "AXTextArea"))
    }
    await store.receive(
      .deliveryFailed(
        5, deliveryFailure("undeliverable", message: message),
      ),
    ) { $0.currentFocusedContext = nil }
    await store.receive(.pill(.dismiss)) { $0.pill.presentation = nil }
    await store.finish()
    #expect(await sounds.recorded == ["Basso"])
  }

  @Test func `a silent commit cue suppresses its delivery sound`() async {
    let sounds = SoundRecorder()
    var state = AppFeature.State()
    state.$settings.withLock { $0.sounds = .silent }
    state.transcriptionGeneration = 4
    state.pill.presentation = .transcribing
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.sounds.play = { cue in await sounds.record(cue) }
    }

    await store.send(
      .deliveryCompleted(
        4, deliveryResult("", .pasted(.restored)),
      ),
    )
    await store.receive(.pill(.dismiss)) { $0.pill.presentation = nil }
    await store.finish()
    #expect(await sounds.recorded.isEmpty)
  }
}

private func settingsBindingAction(
  _ command: HotkeyCommand, _ action: HotkeyBindingsFeature.Action,
) -> AppFeature.Action {
  .settingsWindow(
    .settingsPane(.bindingEditors(.element(id: command, action: action))),
  )
}

private func deliveryResult(
  _ text: String, _ outcome: DeliveryOutcome,
) -> AppFeature.DeliveryResult {
  AppFeature.DeliveryResult(text: text, targetApp: nil, outcome: outcome)
}

private func deliveryFailure(_ text: String, message: String) -> AppFeature.DeliveryFailure {
  AppFeature.DeliveryFailure(text: text, targetApp: nil, message: message)
}

private func context(before: String) -> FocusedTextContext {
  FocusedTextContext(
    role: "AXTextArea", before: before, selected: "", after: "",
    selectedRange: before.utf16.count ..< before.utf16.count, beforeWasTruncated: false,
    selectionWasTruncated: false, afterWasTruncated: false,
  )
}
