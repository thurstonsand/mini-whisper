import ASREngine
import AudioCapture
import ComposableArchitecture
import FieldContext
import Foundation
import HotkeyListener
import Testing

@testable import MiniWhisper

@MainActor @Suite struct AppFeatureTests {
  @Test func hotkeyHoldCapturesAndRetainsARecording() async {
    let (captureEvents, captureContinuation) = AsyncStream.makeStream(of: AudioCaptureEvent.self)
    let recording = CanonicalRecording(samples: Array(repeating: 0.1, count: 16_000))
    let sessionID = UUID()
    let debugURL = URL(fileURLWithPath: "/tmp/MiniWhisper-test.wav")
    let clock = TestClock()
    var state = AppFeature.State()
    state.hotkeyTap = .active
    state.recording.micStatus = .granted
    state.onboardingCompleted = true
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.audioCapture.start = {
        AudioCaptureSession(
          id: sessionID, inputDeviceName: "Test Microphone", events: captureEvents)
      }
      $0.audioCapture.stop = { id in
        #expect(id == sessionID)
        return recording
      }
      $0.audioCapture.currentInputDeviceName = { "Test Microphone" }
      $0.audioCapture.writeDebugWAV = { _ in debugURL }
      $0.asrEngine.submit = { _ in .noSpeech }
      $0.contextCapture.prewarmFrontmostApp = {}
      $0.continuousClock = clock
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.hotkeyListenerEvent(.gesture(.startRecording))) {
      $0.transcriptionGeneration = 1
    }
    await store.receive(.pill(.recordingStarting(inputDeviceName: "Test Microphone"))) {
      $0.pill.presentation = .recording(
        PillFeature.State.Presentation.Recording(
          inputDeviceName: "Test Microphone", level: 0, isLive: false))
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
      .recording(.delegate(.recordingStarted(inputDeviceName: "Test Microphone"))))
    await store.receive(.pill(.recordingStarted(inputDeviceName: "Test Microphone"))) {
      $0.pill.presentation = .recording(
        PillFeature.State.Presentation.Recording(
          inputDeviceName: "Test Microphone", level: 0, isLive: true))
    }

    await store.send(.hotkeyListenerEvent(.gesture(.stopAndTranscribe)))
    await store.receive(.recording(.stopAndRetain)) { $0.recording.phase = .stopping(nil) }
    await store.receive(.recording(.captureStopped(1, recording))) {
      $0.recording.captureSessionID = nil
      $0.recording.phase = .idle
    }
    await store.receive(.recording(.delegate(.completed(recording))))
    await store.receive(.pill(.transcribingStarted)) { $0.pill.presentation = .transcribing }
    await store.receive(.transcriptionCompleted(1, suppressNoSpeechNotice: false, .noSpeech))
    await store.receive(.pill(.noSpeechDetected)) {
      $0.pill.noticeGeneration = 1
      $0.pill.presentation = .notice(.noSpeechDetected)
    }
    await store.send(.pill(.dismiss)) { $0.pill.presentation = nil }
    captureContinuation.finish()
    await store.receive(.recording(.captureEventsFinished(1)))
    await store.finish()
  }

  @Test func completedStartupStartsTheListenerWithoutPresentingOnboarding() async {
    let (events, continuation) = AsyncStream.makeStream(of: HotkeyListenerEvent.self)
    let permissions = OnboardingPermissionStatuses(
      hasInputMonitoringPermission: true, microphoneStatus: .granted, hasPasteAccess: true)
    let facts = AppFeature.StartupFacts(
      onboardingCompleted: true, modelDownloadConsented: true, permissions: permissions,
      engineReadiness: .ready)
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.hotkeyListener.events = { events }
    }

    await store.send(.startupResolved(facts)) {
      $0.onboardingCompleted = true
      $0.modelDownloadConsented = true
      $0.pasteAccessGranted = true
      $0.recording.micStatus = .granted
      $0.engineReadiness = .ready
    }
    #expect(!store.state.onboarding.isPresented)
    continuation.yield(.monitoringStarted)
    await store.receive(.hotkeyListenerEvent(.monitoringStarted)) { $0.hotkeyTap = .active }
    continuation.finish()
    await store.receive(.hotkeyListenerFinished) { $0.hotkeyTap = .dead }
  }

  @Test func startupJoinForwardsEngineReadinessAfterItsInitialSnapshot() async {
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.audioCapture.prepare = {}
      $0.asrEngine.prepareInstalled = {
        AsyncStream { continuation in
          continuation.yield(.compiling)
          continuation.yield(.ready)
          continuation.finish()
        }
      }
      $0.hotkeyListener.hasInputMonitoringPermission = { false }
      $0.microphonePermission.status = { .granted }
      $0.delivery.hasPasteAccess = { false }
      $0.onboardingCompletion.isCompleted = { true }
      $0.modelDownloadConsent.isConsented = { true }
      $0.sounds.loadIsEnabled = { false }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    let facts = AppFeature.StartupFacts(
      onboardingCompleted: true, modelDownloadConsented: true,
      permissions: OnboardingPermissionStatuses(
        hasInputMonitoringPermission: false, microphoneStatus: .granted, hasPasteAccess: false),
      engineReadiness: .compiling)

    await store.send(.task)
    await store.receive(.startupResolved(facts)) {
      $0.onboardingCompleted = true
      $0.modelDownloadConsented = true
      $0.hotkeyTap = .inputMonitoringMissing
      $0.recording.micStatus = .granted
      $0.engineReadiness = .compiling
    }
    await store.receive(.engineReadinessUpdated(.ready)) { $0.engineReadiness = .ready }
    #expect(!store.state.onboarding.isPresented)
    await store.finish()
  }

  @Test func incompleteStartupPresentsBeforeForwardingLaterReadiness() async {
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.audioCapture.prepare = {}
      $0.asrEngine.prepareInstalled = {
        AsyncStream { continuation in
          continuation.yield(.compiling)
          continuation.yield(.ready)
          continuation.finish()
        }
      }
      $0.hotkeyListener.hasInputMonitoringPermission = { false }
      $0.hotkeyListener.events = { AsyncStream { $0.finish() } }
      $0.microphonePermission.status = { .undetermined }
      $0.delivery.hasPasteAccess = {
        Issue.record("Accessibility must remain untouched before the IOHID request")
        return false
      }
      $0.onboardingCompletion.isCompleted = { false }
      $0.modelDownloadConsent.isConsented = { false }
      $0.sounds.loadIsEnabled = { false }
      $0.continuousClock = TestClock()
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    let permissions = OnboardingPermissionStatuses(
      hasInputMonitoringPermission: false, microphoneStatus: .undetermined, hasPasteAccess: false)
    let facts = AppFeature.StartupFacts(
      onboardingCompleted: false, modelDownloadConsented: false, permissions: permissions,
      engineReadiness: .compiling)
    let snapshot = OnboardingSnapshot(
      permissions: permissions, engineReadiness: .compiling, hasModelDownloadConsent: false,
      isCompleted: false)

    await store.send(.task)
    await store.receive(.startupResolved(facts)) { $0.hotkeyTap = .inputMonitoringMissing }
    await store.receive(.onboarding(.present(snapshot))) {
      $0.onboarding.isPresented = true
      $0.onboarding.snapshot = snapshot
      $0.onboarding.isShowingWelcome = true
    }
    await store.receive(.engineReadinessUpdated(.ready)) { $0.engineReadiness = .ready }
    await store.receive(.onboarding(.engineReadinessUpdated(.ready))) {
      $0.onboarding.snapshot.engineReadiness = .ready
    }
    #expect(store.state.onboarding.step == .permissions)

    let granted = OnboardingPermissionStatuses(
      hasInputMonitoringPermission: true, microphoneStatus: .granted, hasPasteAccess: true)
    await store.send(
      .onboarding(
        .permissionStatusesObserved(
          OnboardingPermissionObservation(
            hasInputMonitoringPermission: true, microphoneStatus: .granted, hasPasteAccess: true)))
    ) { $0.onboarding.snapshot.permissions = granted }
    await store.finish()
  }

  @Test func firstRunPresentsOnboardingFromResolvedSystemState() async {
    let (hotkeyEvents, hotkeyContinuation) = AsyncStream.makeStream(of: HotkeyListenerEvent.self)
    var state = AppFeature.State()
    state.hotkeyTap = .inputMonitoringMissing
    state.recording.micStatus = .undetermined
    state.onboardingCompleted = false
    state.modelDownloadConsented = false
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.continuousClock = TestClock()
      $0.hotkeyListener.events = { hotkeyEvents }
      $0.modelDownloadConsent.markConsented = {}
      $0.asrEngine.installAndPrepare = { AsyncStream { $0.finish() } }
    }
    let snapshot = OnboardingSnapshot(
      permissions: OnboardingPermissionStatuses(
        hasInputMonitoringPermission: false, microphoneStatus: .undetermined, hasPasteAccess: false),
      engineReadiness: .modelMissing, hasModelDownloadConsent: false, isCompleted: false)

    await store.send(
      .startupResolved(
        AppFeature.StartupFacts(
          onboardingCompleted: false, modelDownloadConsented: false,
          permissions: snapshot.permissions, engineReadiness: .modelMissing)))
    await store.receive(.onboarding(.present(snapshot))) {
      $0.onboarding.isPresented = true
      $0.onboarding.snapshot = snapshot
      $0.onboarding.isShowingWelcome = true
    }
    await store.send(.onboarding(.downloadModel)) {
      $0.onboarding.isRecordingModelDownloadConsent = true
    }
    await store.receive(.onboarding(.modelDownloadConsented)) {
      $0.onboarding.snapshot.hasModelDownloadConsent = true
      $0.onboarding.isShowingWelcome = false
      $0.onboarding.isRecordingModelDownloadConsent = false
    }
    #expect(store.state.onboarding.step == .permissions)

    // Observed grants advance the flow in place when macOS exposes them to the running process.
    let granted = OnboardingPermissionStatuses(
      hasInputMonitoringPermission: true, microphoneStatus: .granted, hasPasteAccess: true)
    await store.send(
      .onboarding(
        .permissionStatusesObserved(
          OnboardingPermissionObservation(
            hasInputMonitoringPermission: true, microphoneStatus: .granted, hasPasteAccess: true)))
    ) { $0.onboarding.snapshot.permissions = granted }
    await store.receive(.onboarding(.delegate(.permissionsUpdated(granted)))) {
      $0.hotkeyTap = .starting
      $0.pasteAccessGranted = true
    }
    await store.receive(.recording(.micStatusUpdated(.granted))) {
      $0.recording.micStatus = .granted
    }
    hotkeyContinuation.yield(.monitoringStarted)
    await store.receive(.hotkeyListenerEvent(.monitoringStarted)) { $0.hotkeyTap = .active }
    #expect(store.state.onboarding.step == .model)

    hotkeyContinuation.finish()
    await store.receive(.hotkeyListenerFinished) { $0.hotkeyTap = .dead }
  }

  @Test func gesturesCannotRaisePermissionPromptsBeforeTheTryItStep() async {
    var state = AppFeature.State()
    state.onboardingCompleted = false
    state.onboarding.isPresented = true
    state.onboarding.snapshot = OnboardingSnapshot(
      permissions: OnboardingPermissionStatuses(
        hasInputMonitoringPermission: true, microphoneStatus: .undetermined, hasPasteAccess: false),
      engineReadiness: .modelMissing, hasModelDownloadConsent: true, isCompleted: false)
    let store = TestStore(initialState: state) { AppFeature() }

    await store.send(.hotkeyListenerEvent(.gesture(.startRecording)))
    #expect(store.state.recording.phase == .idle)
  }

  @Test func liveCaptureLevelsDriveTheRecordingPill() async {
    let sessionID = UUID()
    var state = AppFeature.State()
    state.recording.captureGeneration = 1
    state.recording.captureSessionID = sessionID
    state.recording.phase = .recording
    state.pill.presentation = .recording(
      PillFeature.State.Presentation.Recording(
        inputDeviceName: "Test Microphone", level: 0, isLive: true))
    let store = TestStore(initialState: state) { AppFeature() }
    let level = AudioLevel(decibels: -12, normalizedPower: 0.8)

    await store.send(.recording(.levelUpdated(1, level))) { $0.recording.latestLevel = 0.8 }
    await store.receive(.recording(.delegate(.levelChanged(0.8))))
    await store.receive(.pill(.levelUpdated(0.8))) {
      $0.pill.presentation = .recording(
        PillFeature.State.Presentation.Recording(
          inputDeviceName: "Test Microphone", level: 0.8, isLive: true))
      $0.pill.accessibilityLevel = 80
    }
  }

  @Test func latchBouncesAndEscapeImmediatelyHidesThePill() async {
    let sessionID = UUID()
    var state = AppFeature.State()
    state.recording.captureGeneration = 1
    state.recording.captureSessionID = sessionID
    state.recording.phase = .recording
    state.onboardingCompleted = true
    state.pill.presentation = .recording(
      PillFeature.State.Presentation.Recording(
        inputDeviceName: "Test Microphone", level: 0.5, isLive: true))
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.audioCapture.cancel = { id in #expect(id == sessionID) }
    }

    await store.send(.hotkeyListenerEvent(.gesture(.latchEngaged)))
    await store.receive(.pill(.latchEngaged)) { $0.pill.bounceCount = 1 }
    await store.send(.hotkeyListenerEvent(.gesture(.cancel)))
    await store.receive(.recording(.cancelRecording)) { $0.recording.phase = .cancelling }
    await store.receive(.recording(.delegate(.discarded)))
    await store.receive(.pill(.cancel)) { $0.pill.presentation = nil }
    await store.receive(.recording(.captureCancelled(1))) {
      $0.recording.captureSessionID = nil
      $0.recording.phase = .idle
      $0.recording.latestLevel = 0
    }
  }

  @Test func loneTapGateRejectionDismissesWithoutANotice() async {
    var state = AppFeature.State()
    state.transcriptionGeneration = 1
    state.pill.presentation = .transcribing
    let store = TestStore(initialState: state) { AppFeature() }

    await store.send(.transcriptionCompleted(1, suppressNoSpeechNotice: true, .noSpeech))
    await store.receive(.pill(.dismiss)) { $0.pill.presentation = nil }
  }

  @Test func transcriptionFailureDegradesEngineAndDoesNotClaimNoSpeech() async {
    var state = AppFeature.State()
    state.engineReadiness = .ready
    state.transcriptionGeneration = 2
    state.pill.presentation = .transcribing
    let store = TestStore(initialState: state) { AppFeature() }

    await store.send(.transcriptionFailed(2, "model failure")) {
      $0.engineReadiness = .failed("model failure")
    }
    await store.receive(.pill(.dismiss)) { $0.pill.presentation = nil }
  }

  @Test func repeatedEngineFailurePlaysTheErrorCueOnlyOnce() async {
    let sounds = SoundRecorder()
    var state = AppFeature.State()
    state.engineReadiness = .ready
    state.soundsEnabled = true
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.sounds.play = { cue in await sounds.record(cue) }
    }

    await store.send(.engineReadinessUpdated(.failed("first failure"))) {
      $0.engineReadiness = .failed("first failure")
    }
    await store.send(.engineReadinessUpdated(.failed("second failure"))) {
      $0.engineReadiness = .failed("second failure")
    }
    await store.finish()
    #expect(await sounds.recorded == [.error])
  }

  @Test func staleTranscriptionCannotDismissANewerRecording() async {
    var state = AppFeature.State()
    state.transcriptionGeneration = 3
    state.pill.presentation = .recording(
      PillFeature.State.Presentation.Recording(
        inputDeviceName: "New Microphone", level: 0, isLive: true))
    let store = TestStore(initialState: state) { AppFeature() }

    await store.send(
      .transcriptionCompleted(2, suppressNoSpeechNotice: false, .transcript("stale")))
  }

  @Test func startupJoinDoesNotProbePasteAccessBeforeInputMonitoring() async {
    let (micGate, micContinuation) = AsyncStream.makeStream(of: Void.self)
    let (hotkeyEvents, hotkeyContinuation) = AsyncStream.makeStream(of: HotkeyListenerEvent.self)
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.hotkeyListener.hasInputMonitoringPermission = { false }
      $0.hotkeyListener.events = { hotkeyEvents }
      $0.microphonePermission.status = {
        for await _ in micGate { return .granted }
        return .granted
      }
      $0.audioCapture.prepare = {}
      $0.asrEngine.prepareInstalled = {
        AsyncStream { continuation in
          continuation.yield(.modelMissing)
          continuation.finish()
        }
      }
      $0.asrEngine.installAndPrepare = { AsyncStream { $0.finish() } }
      $0.delivery.hasPasteAccess = {
        Issue.record("Accessibility must not be preflighted before Input Monitoring is requested")
        return true
      }
      $0.onboardingCompletion.isCompleted = { false }
      $0.modelDownloadConsent.isConsented = { false }
      $0.sounds.loadIsEnabled = { false }
      $0.continuousClock = TestClock()
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.task)
    await store.receive(.recording(.task))
    micContinuation.yield(())
    let facts = AppFeature.StartupFacts(
      onboardingCompleted: false, modelDownloadConsented: false,
      permissions: OnboardingPermissionStatuses(
        hasInputMonitoringPermission: false, microphoneStatus: .granted, hasPasteAccess: false),
      engineReadiness: .modelMissing)
    await store.receive(.startupResolved(facts)) {
      $0.hotkeyTap = .inputMonitoringMissing
      $0.recording.micStatus = .granted
    }
    await store.receive(
      .onboarding(
        .present(
          OnboardingSnapshot(
            permissions: facts.permissions, engineReadiness: .modelMissing,
            hasModelDownloadConsent: false, isCompleted: false)))
    ) {
      $0.onboarding.isPresented = true
      $0.onboarding.snapshot.permissions = facts.permissions
      $0.onboarding.snapshot.engineReadiness = .modelMissing
      $0.onboarding.isShowingWelcome = true
    }
    micContinuation.finish()

    let granted = OnboardingPermissionStatuses(
      hasInputMonitoringPermission: true, microphoneStatus: .granted, hasPasteAccess: true)
    await store.send(
      .onboarding(
        .permissionStatusesObserved(
          OnboardingPermissionObservation(
            hasInputMonitoringPermission: true, microphoneStatus: .granted, hasPasteAccess: true)))
    ) { $0.onboarding.snapshot.permissions = granted }
    await store.receive(.onboarding(.delegate(.permissionsUpdated(granted)))) {
      $0.hotkeyTap = .starting
      $0.pasteAccessGranted = true
    }
    hotkeyContinuation.finish()
    await store.finish()
  }

  @Test func transcriptDeliveryRestoresClipboardAndCommits() async {
    let sounds = SoundRecorder()
    var state = AppFeature.State()
    state.transcriptionGeneration = 1
    state.soundsEnabled = true
    state.pill.presentation = .transcribing
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      // The captured field ends in a sentence, so the joined paste gains a space and a capital.
      $0.contextCapture.capture = { .available(context(before: "We arrived at noon.")) }
      $0.delivery.deliver = { transcript in
        #expect(transcript == " Delivered text")
        return .pasted(.restored)
      }
      $0.sounds.play = { cue in await sounds.record(cue) }
    }

    await store.send(
      .transcriptionCompleted(1, suppressNoSpeechNotice: false, .transcript("delivered text"))
    ) { $0.lastTranscript = "delivered text" }
    await store.receive(.contextCaptured(1, .available(context(before: "We arrived at noon.")))) {
      $0.currentFocusedContext = .available(context(before: "We arrived at noon."))
    }
    await store.receive(.deliveryCompleted(1, .pasted(.restored))) {
      $0.currentFocusedContext = nil
    }
    await store.receive(.pill(.dismiss)) { $0.pill.presentation = nil }
    await store.finish()
    #expect(await sounds.recorded == [.commit])
  }

  @Test func aStalledCaptureCannotPasteIntoTheDictationThatReplacedIt() async {
    let (gate, openGate) = AsyncStream.makeStream(of: Void.self)
    let deliveries = PrewarmCounter()
    var state = AppFeature.State()
    state.transcriptionGeneration = 1
    state.onboardingCompleted = true
    state.pill.presentation = .transcribing
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.contextCapture.capture = {
        for await _ in gate {}
        return .unavailable(.noFocusedElement)
      }
      $0.contextCapture.prewarmFrontmostApp = {}
      $0.delivery.deliver = { _ in
        await deliveries.record()
        return .pasted(.restored)
      }
      $0.audioCapture.start = {
        AudioCaptureSession(
          id: UUID(), inputDeviceName: "Test Microphone", events: AsyncStream { $0.finish() })
      }
      $0.audioCapture.cancel = { _ in }
      $0.audioCapture.currentInputDeviceName = { "Test Microphone" }
      $0.asrEngine.prepareForActivation = { AsyncStream { $0.finish() } }
      $0.continuousClock = TestClock()
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(
      .transcriptionCompleted(1, suppressNoSpeechNotice: false, .transcript("late arrival")))
    await store.send(.hotkeyListenerEvent(.gesture(.startRecording)))
    openGate.finish()
    await store.finish()
    #expect(await deliveries.count == 0)
    #expect(store.state.currentFocusedContext == nil)
  }

  @Test func unavailableContextPastesBlindAndSaysSo() async {
    let sounds = SoundRecorder()
    let clock = TestClock()
    var state = AppFeature.State()
    state.transcriptionGeneration = 1
    state.soundsEnabled = true
    state.pill.presentation = .transcribing
    let unavailable = ContextCapture.unavailable(.gridSemantics(bundleID: "com.mitchellh.ghostty"))
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.contextCapture.capture = { unavailable }
      $0.delivery.deliver = { transcript in
        #expect(transcript == "delivered text")
        return .pasted(.restored)
      }
      $0.sounds.play = { cue in await sounds.record(cue) }
      $0.continuousClock = clock
    }

    await store.send(
      .transcriptionCompleted(1, suppressNoSpeechNotice: false, .transcript("delivered text"))
    ) { $0.lastTranscript = "delivered text" }
    await store.receive(.contextCaptured(1, unavailable)) { $0.currentFocusedContext = unavailable }
    await store.receive(.deliveryCompleted(1, .pasted(.restored))) {
      $0.currentFocusedContext = nil
    }
    await store.receive(.pill(.fieldContextUnavailable)) {
      $0.pill.noticeGeneration = 1
      $0.pill.presentation = .notice(.fieldContextUnavailable)
    }
    await store.send(.pill(.dismiss)) { $0.pill.presentation = nil }
    await store.finish()
    #expect(await sounds.recorded == [.commit])
  }

  @Test func changedClipboardSkipsRestoreWithoutTurningPasteIntoFailure() async {
    let sounds = SoundRecorder()
    var state = AppFeature.State()
    state.transcriptionGeneration = 2
    state.soundsEnabled = true
    state.pill.presentation = .transcribing
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.sounds.play = { cue in await sounds.record(cue) }
    }

    await store.send(.deliveryCompleted(2, .pasted(.skipped)))
    await store.receive(.pill(.dismiss)) { $0.pill.presentation = nil }
    await store.finish()
    #expect(await sounds.recorded == [.commit])
  }

  @Test func missingAccessibilityKeepsTranscriptCopiedAndShowsFallback() async {
    let sounds = SoundRecorder()
    let clock = TestClock()
    var state = AppFeature.State()
    state.transcriptionGeneration = 3
    state.soundsEnabled = true
    state.pill.presentation = .transcribing
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.contextCapture.capture = { .unavailable(.accessibilityPermissionMissing) }
      $0.delivery.deliver = { _ in .copied(.accessibilityPermissionMissing) }
      $0.sounds.play = { cue in await sounds.record(cue) }
      $0.continuousClock = clock
    }

    await store.send(
      .transcriptionCompleted(3, suppressNoSpeechNotice: false, .transcript("copy me"))
    ) { $0.lastTranscript = "copy me" }
    await store.receive(.contextCaptured(3, .unavailable(.accessibilityPermissionMissing))) {
      $0.currentFocusedContext = .unavailable(.accessibilityPermissionMissing)
    }
    await store.receive(.deliveryCompleted(3, .copied(.accessibilityPermissionMissing))) {
      $0.currentFocusedContext = nil
    }
    await store.receive(.pill(.copiedToClipboard)) {
      $0.pill.noticeGeneration = 1
      $0.pill.presentation = .notice(.copiedToClipboard)
    }
    await store.send(.pill(.dismiss)) { $0.pill.presentation = nil }
    await store.finish()
    #expect(await sounds.recorded == [.error])
  }

  @Test func recordingStartAndDiscardUseTheirDistinctCues() async {
    let sounds = SoundRecorder()
    let prewarms = PrewarmCounter()
    var state = AppFeature.State()
    state.soundsEnabled = true
    state.recording.phase = .recording
    state.onboardingCompleted = true
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.audioCapture.currentInputDeviceName = { "Microphone" }
      $0.asrEngine.prepareForActivation = { AsyncStream { $0.finish() } }
      $0.contextCapture.prewarmFrontmostApp = { await prewarms.record() }
      $0.sounds.play = { cue in await sounds.record(cue) }
    }

    await store.send(.hotkeyListenerEvent(.gesture(.startRecording))) {
      $0.transcriptionGeneration = 1
    }
    await store.receive(.pill(.recordingStarting(inputDeviceName: "Microphone"))) {
      $0.pill.presentation = .recording(
        PillFeature.State.Presentation.Recording(
          inputDeviceName: "Microphone", level: 0, isLive: false))
    }
    await store.receive(.recording(.startRecording))
    await store.send(.recording(.delegate(.discarded)))
    await store.receive(.pill(.cancel)) { $0.pill.presentation = nil }
    await store.finish()
    let recorded = await sounds.recorded
    #expect(recorded.count == 2)
    #expect(recorded.contains(.recordStart))
    #expect(recorded.contains(.cancel))
    // Chromium's wake walk belongs to recording start, never to delivery.
    #expect(await prewarms.count == 1)
  }

  @Test func secureInputUsesTheCopiedFallback() async {
    let sounds = SoundRecorder()
    let clock = TestClock()
    var state = AppFeature.State()
    state.transcriptionGeneration = 4
    state.soundsEnabled = true
    state.pill.presentation = .transcribing
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.sounds.play = { cue in await sounds.record(cue) }
      $0.continuousClock = clock
    }

    await store.send(.deliveryCompleted(4, .copied(.secureInput)))
    await store.receive(.pill(.copiedToClipboard)) {
      $0.pill.noticeGeneration = 1
      $0.pill.presentation = .notice(.copiedToClipboard)
    }
    await store.send(.pill(.dismiss)) { $0.pill.presentation = nil }
    await store.finish()
    #expect(await sounds.recorded == [.error])
  }

  @Test func deliveryFailureDismissesThePillAndPlaysTheErrorCue() async {
    let sounds = SoundRecorder()
    var state = AppFeature.State()
    state.transcriptionGeneration = 5
    state.soundsEnabled = true
    state.pill.presentation = .transcribing
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.contextCapture.capture = { .unavailable(.noFocusedElement) }
      $0.delivery.deliver = { _ in throw DeliveryError.pasteboardWriteFailed }
      $0.sounds.play = { cue in await sounds.record(cue) }
    }
    let message = DeliveryError.pasteboardWriteFailed.localizedDescription

    await store.send(
      .transcriptionCompleted(5, suppressNoSpeechNotice: false, .transcript("undeliverable"))
    ) { $0.lastTranscript = "undeliverable" }
    await store.receive(.contextCaptured(5, .unavailable(.noFocusedElement))) {
      $0.currentFocusedContext = .unavailable(.noFocusedElement)
    }
    await store.receive(.deliveryFailed(5, message)) { $0.currentFocusedContext = nil }
    await store.receive(.pill(.dismiss)) { $0.pill.presentation = nil }
    await store.finish()
    #expect(await sounds.recorded == [.error])
  }

  @Test func disabledSoundsSuppressEveryDeliveryCue() async {
    let sounds = SoundRecorder()
    var state = AppFeature.State()
    state.transcriptionGeneration = 4
    state.pill.presentation = .transcribing
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.sounds.play = { cue in await sounds.record(cue) }
    }

    await store.send(.deliveryCompleted(4, .pasted(.restored)))
    await store.receive(.pill(.dismiss)) { $0.pill.presentation = nil }
    await store.finish()
    #expect(await sounds.recorded.isEmpty)
  }
}

private actor SoundRecorder {
  private(set) var recorded: [SoundCue] = []

  func record(_ cue: SoundCue) { recorded.append(cue) }
}

private actor PrewarmCounter {
  private(set) var count = 0

  func record() { count += 1 }
}

private func context(before: String) -> FocusedTextContext {
  FocusedTextContext(
    role: "AXTextArea", before: before, selected: "", after: "",
    selectedRange: before.utf16.count..<before.utf16.count, beforeWasTruncated: false,
    selectionWasTruncated: false, afterWasTruncated: false)
}
