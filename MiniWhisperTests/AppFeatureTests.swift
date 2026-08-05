import ASREngine
import AudioCapture
import ComposableArchitecture
import FieldContext
import Foundation
import History
import HotkeyListener
@testable import MiniWhisper
import Testing

// MARK: - AppFeatureTests

@MainActor struct AppFeatureTests {
  @Test func `hotkey hold captures and retains A recording`() async {
    let (captureEvents, captureContinuation) = AsyncStream.makeStream(of: AudioCaptureEvent.self)
    let recording = CanonicalRecording(samples: Array(repeating: 0.1, count: 16000))
    let sessionID = UUID()
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
          id: sessionID, inputDeviceName: "Test Microphone", events: captureEvents,
        )
      }
      $0.audioCapture.stop = { id in
        #expect(id == sessionID)
        return recording
      }
      $0.audioCapture.currentInputDeviceName = { "Test Microphone" }
      $0.asrEngine.submit = { _ in .noSpeech }
      $0.contextCapture.prewarmFrontmostApp = {}
      $0.date.now = Date(timeIntervalSince1970: 1000)
      $0.continuousClock = clock
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.hotkeyListenerEvent(.gesture(.startRecording))) {
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

  @Test func `completed startup starts the listener without presenting onboarding`() async {
    let (events, continuation) = AsyncStream.makeStream(of: HotkeyListenerEvent.self)
    let permissions = OnboardingPermissionStatuses(
      microphoneStatus: .granted, hasAccessibilityPermission: true,
    )
    let facts = AppFeature.StartupFacts(
      onboardingCompleted: true, modelDownloadConsented: true, permissions: permissions,
      engineReadiness: .ready,
      retentionPolicy: RetentionPolicy(transcripts: .forever, audio: .never),
    )
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.accessibilityPermission.hasPermission = { true }
      $0.hotkeyListener.events = { events }
    }

    await store.send(.startupResolved(facts)) {
      $0.onboardingCompleted = true
      $0.modelDownloadConsented = true
      $0.accessibilityGranted = true
      $0.recording.micStatus = .granted
      $0.engineReadiness = .ready
      $0.retentionPolicy = RetentionPolicy(transcripts: .forever, audio: .never)
      $0.hotkeyTap = .starting
    }
    #expect(!store.state.onboarding.isPresented)
    continuation.yield(.monitoringStarted)
    await store.receive(.hotkeyListenerEvent(.monitoringStarted)) { $0.hotkeyTap = .active }
    continuation.finish()
    await store.receive(.hotkeyListenerFinished) { $0.hotkeyTap = .dead }
  }

  @Test func `startup join forwards engine readiness after its initial snapshot`() async {
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
      $0.microphonePermission.status = { .granted }
      $0.accessibilityPermission.hasPermission = { false }
      $0.onboardingCompletion.isCompleted = { true }
      $0.modelDownloadConsent.isConsented = { true }
      $0.sounds.loadIsEnabled = { false }
      $0.date.now = Date(timeIntervalSince1970: 1000)
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    let facts = AppFeature.StartupFacts(
      onboardingCompleted: true, modelDownloadConsented: true,
      permissions: OnboardingPermissionStatuses(
        microphoneStatus: .granted, hasAccessibilityPermission: false,
      ),
      engineReadiness: .compiling, retentionPolicy: .defaults,
    )

    await store.send(.task)
    await store.receive(.startupResolved(facts)) {
      $0.onboardingCompleted = true
      $0.modelDownloadConsented = true
      $0.hotkeyTap = .accessibilityMissing
      $0.recording.micStatus = .granted
      $0.engineReadiness = .compiling
    }
    await store.receive(.engineReadinessUpdated(.ready)) { $0.engineReadiness = .ready }
    #expect(!store.state.onboarding.isPresented)
    await store.finish()
  }

  @Test func `incomplete startup presents before forwarding later readiness`() async {
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
      $0.hotkeyListener.events = { AsyncStream { $0.finish() } }
      $0.microphonePermission.status = { .undetermined }
      $0.accessibilityPermission.hasPermission = { false }
      $0.onboardingCompletion.isCompleted = { false }
      $0.modelDownloadConsent.isConsented = { false }
      $0.sounds.loadIsEnabled = { false }
      $0.continuousClock = TestClock()
      $0.date.now = Date(timeIntervalSince1970: 1000)
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    let permissions = OnboardingPermissionStatuses(
      microphoneStatus: .undetermined, hasAccessibilityPermission: false,
    )
    let facts = AppFeature.StartupFacts(
      onboardingCompleted: false, modelDownloadConsented: false, permissions: permissions,
      engineReadiness: .compiling, retentionPolicy: .defaults,
    )
    let snapshot = OnboardingSnapshot(
      permissions: permissions, engineReadiness: .compiling, hasModelDownloadConsent: false,
      isCompleted: false,
    )

    await store.send(.task)
    await store.receive(.startupResolved(facts)) { $0.hotkeyTap = .accessibilityMissing }
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
    let (hotkeyEvents, hotkeyContinuation) = AsyncStream.makeStream(of: HotkeyListenerEvent.self)
    var state = AppFeature.State()
    state.hotkeyTap = .accessibilityMissing
    state.recording.micStatus = .undetermined
    state.onboardingCompleted = false
    state.modelDownloadConsented = false
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.accessibilityPermission.hasPermission = { true }
      $0.continuousClock = TestClock()
      $0.hotkeyListener.events = { hotkeyEvents }
      $0.modelDownloadConsent.markConsented = {}
      $0.asrEngine.installAndPrepare = { AsyncStream { $0.finish() } }
    }
    let snapshot = OnboardingSnapshot(
      permissions: OnboardingPermissionStatuses(
        microphoneStatus: .undetermined, hasAccessibilityPermission: false,
      ),
      engineReadiness: .modelMissing, hasModelDownloadConsent: false, isCompleted: false,
    )

    await store.send(
      .startupResolved(
        AppFeature.StartupFacts(
          onboardingCompleted: false, modelDownloadConsented: false,
          permissions: snapshot.permissions, engineReadiness: .modelMissing,
          retentionPolicy: .defaults,
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
    }
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
    ) { $0.onboarding.snapshot.permissions = granted }
    await store.receive(.onboarding(.delegate(.permissionsUpdated(granted)))) {
      $0.hotkeyTap = .starting
      $0.accessibilityGranted = true
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

  @Test func `gestures cannot raise permission prompts before the try it step`() async {
    var state = AppFeature.State()
    state.onboardingCompleted = false
    state.onboarding.isPresented = true
    state.onboarding.snapshot = OnboardingSnapshot(
      permissions: OnboardingPermissionStatuses(
        microphoneStatus: .undetermined, hasAccessibilityPermission: false,
      ),
      engineReadiness: .modelMissing, hasModelDownloadConsent: true, isCompleted: false,
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

  @Test func `latch bounces and escape immediately hides the pill`() async {
    let sessionID = UUID()
    var state = AppFeature.State()
    state.recording.captureGeneration = 1
    state.recording.captureSessionID = sessionID
    state.recording.phase = .recording
    state.onboardingCompleted = true
    state.pill.presentation = .recording(
      PillFeature.State.Presentation.Recording(
        inputDeviceName: "Test Microphone", level: 0.5, isLive: true,
      ),
    )
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

  @Test func `lone tap gate rejection dismisses without A notice`() async {
    var state = AppFeature.State()
    state.transcriptionGeneration = 1
    state.pill.presentation = .transcribing
    let store = TestStore(initialState: state) { AppFeature() }

    await store.send(.transcriptionCompleted(1, suppressNoSpeechNotice: true, .noSpeech))
    await store.receive(.pill(.dismiss)) { $0.pill.presentation = nil }
  }

  @Test func `transcription failure degrades engine and does not claim no speech`() async {
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

  @Test func `repeated engine failure plays the error cue only once`() async {
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
      .transcriptionCompleted(2, suppressNoSpeechNotice: false, .transcript("stale")),
    )
  }

  @Test func `transcript delivery restores clipboard and commits`() async {
    let sounds = SoundRecorder()
    // The captured field ends in a sentence, so the joined paste gains a space and a capital.
    let captured = ContextCapture.available(context(before: "We arrived at noon."))
    var state = AppFeature.State()
    state.transcriptionGeneration = 1
    state.soundsEnabled = true
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
      .transcriptionCompleted(1, suppressNoSpeechNotice: false, .transcript("delivered text")),
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
    #expect(await sounds.recorded == [.commit])
  }

  @Test func `release warms the field but delivery joins against A fresh read`() async {
    let captures = CaptureSequence(captures: [
      // What the release-time read saw, before the user kept typing during transcription.
      .available(context(before: "we were still typing")),
      .available(context(before: "We were still typing.")),
    ])
    var state = AppFeature.State()
    state.transcriptionGeneration = 1
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
      .transcriptionCompleted(1, suppressNoSpeechNotice: false, .transcript("delivered text")),
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
      .transcriptionCompleted(1, suppressNoSpeechNotice: false, .transcript("delivered text")),
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

  @Test func `cancelling mid flight leaves nothing to deliver`() async {
    let deliveries = PrewarmCounter()
    let reads = PrewarmCounter()
    let (gate, openGate) = AsyncStream.makeStream(of: Void.self)
    var state = AppFeature.State()
    state.transcriptionGeneration = 1
    state.onboardingCompleted = true
    state.recording.captureGeneration = 1
    state.recording.captureSessionID = UUID()
    state.recording.phase = .recording
    state.currentFocusedContext = .available(context(before: "Left over."))
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.contextCapture.capture = { source in
        await reads.record()
        // The warm-up returns at once; the delivery read is the one left hanging.
        guard source == .delivery else {
          return .unavailable(.noFocusedElement)
        }
        for await _ in gate {}
        return .available(context(before: "Read after the escape."))
      }
      $0.audioCapture.cancel = { _ in }
      $0.delivery.deliver = { _ in
        await deliveries.record()
        return .pasted(.restored)
      }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.hotkeyListenerEvent(.gesture(.stopAndTranscribe)))
    await store.send(
      .transcriptionCompleted(1, suppressNoSpeechNotice: false, .transcript("abandoned")),
    )
    await store.send(.hotkeyListenerEvent(.gesture(.cancel))) { $0.currentFocusedContext = nil }
    openGate.finish()
    await store.finish()
    #expect(await deliveries.isEmpty)
    #expect(store.state.currentFocusedContext == nil)
  }

  @Test func `rejected audio drops A capture still in flight without delivering`() async {
    let deliveries = PrewarmCounter()
    let (gate, openGate) = AsyncStream.makeStream(of: Void.self)
    var state = AppFeature.State()
    state.transcriptionGeneration = 1
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
    await store.send(.transcriptionCompleted(1, suppressNoSpeechNotice: false, .noSpeech))
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
      $0.audioCapture.start = {
        AudioCaptureSession(
          id: UUID(), inputDeviceName: "Test Microphone", events: AsyncStream { $0.finish() },
        )
      }
      $0.audioCapture.cancel = { _ in }
      $0.audioCapture.currentInputDeviceName = { "Test Microphone" }
      $0.asrEngine.prepareForActivation = { AsyncStream { $0.finish() } }
      $0.continuousClock = TestClock()
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(
      .transcriptionCompleted(1, suppressNoSpeechNotice: false, .transcript("late arrival")),
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
    state.soundsEnabled = true
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
      .transcriptionCompleted(1, suppressNoSpeechNotice: false, .transcript("delivered text")),
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
    #expect(await sounds.recorded == [.commit])
  }

  @Test func `changed clipboard skips restore without turning paste into failure`() async {
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

    await store.send(
      .deliveryCompleted(
        2, deliveryResult("", .pasted(.skipped)),
      ),
    )
    await store.receive(.pill(.dismiss)) { $0.pill.presentation = nil }
    await store.finish()
    #expect(await sounds.recorded == [.commit])
  }

  @Test func `missing accessibility keeps transcript copied and shows fallback`() async {
    let sounds = SoundRecorder()
    let clock = TestClock()
    var state = AppFeature.State()
    state.transcriptionGeneration = 3
    state.soundsEnabled = true
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
      .transcriptionCompleted(3, suppressNoSpeechNotice: false, .transcript("copy me")),
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
    #expect(await sounds.recorded == [.error])
  }

  @Test func `recording start and discard use their distinct cues`() async {
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
    await store.receive(.pill(.cancel)) { $0.pill.presentation = nil }
    await store.finish()
    let recorded = await sounds.recorded
    #expect(recorded.count == 2)
    #expect(recorded.contains(.recordStart))
    #expect(recorded.contains(.cancel))
    // Chromium's wake walk belongs to recording start, never to delivery.
    #expect(await prewarms.count == 1)
  }

  @Test func `secure input uses the copied fallback`() async {
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
    #expect(await sounds.recorded == [.error])
  }

  @Test func `delivery failure dismisses the pill and plays the error cue`() async {
    let sounds = SoundRecorder()
    var state = AppFeature.State()
    state.transcriptionGeneration = 5
    state.soundsEnabled = true
    state.pill.presentation = .transcribing
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.contextCapture.capture = { _ in .unavailable(.noFocusedElement) }
      $0.delivery.deliver = { _ in throw DeliveryError.pasteboardWriteFailed }
      $0.sounds.play = { cue in await sounds.record(cue) }
    }
    let message = DeliveryError.pasteboardWriteFailed.localizedDescription

    await store.send(
      .transcriptionCompleted(5, suppressNoSpeechNotice: false, .transcript("undeliverable")),
    ) { $0.lastTranscript = "undeliverable" }
    await store.receive(.contextCaptured(5, .unavailable(.noFocusedElement))) {
      $0.currentFocusedContext = .unavailable(.noFocusedElement)
    }
    await store.receive(
      .deliveryFailed(
        5, deliveryFailure("undeliverable", message: message),
      ),
    ) { $0.currentFocusedContext = nil }
    await store.receive(.pill(.dismiss)) { $0.pill.presentation = nil }
    await store.finish()
    #expect(await sounds.recorded == [.error])
  }

  @Test func `disabled sounds suppress every delivery cue`() async {
    let sounds = SoundRecorder()
    var state = AppFeature.State()
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
