import ASREngine
import AudioCapture
import ComposableArchitecture
import Foundation
import HotkeyListener
import Testing

@testable import MiniWhisper

@MainActor @Suite struct AppFeatureTests {
  @Test func hotkeyHoldCapturesAndRetainsARecording() async {
    let (hotkeyEvents, hotkeyContinuation) = AsyncStream.makeStream(of: HotkeyListenerEvent.self)
    let (captureEvents, captureContinuation) = AsyncStream.makeStream(of: AudioCaptureEvent.self)
    let recording = CanonicalRecording(samples: Array(repeating: 0.1, count: 16_000))
    let sessionID = UUID()
    let debugURL = URL(fileURLWithPath: "/tmp/MiniWhisper-test.wav")
    let clock = TestClock()
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.hotkeyListener.events = { hotkeyEvents }
      $0.microphonePermission.status = { .granted }
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
      $0.sounds.loadIsEnabled = { false }
      $0.continuousClock = clock
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.task)
    await store.receive(.recording(.task))
    await store.receive(.recording(.micStatusUpdated(.granted))) {
      $0.recording.micStatus = .granted
    }

    hotkeyContinuation.yield(.monitoringStarted)
    await store.receive(.hotkeyListenerEvent(.monitoringStarted))
    hotkeyContinuation.yield(.gesture(.startRecording))
    await store.receive(.hotkeyListenerEvent(.gesture(.startRecording))) {
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

    hotkeyContinuation.yield(.gesture(.stopAndTranscribe))
    await store.receive(.hotkeyListenerEvent(.gesture(.stopAndTranscribe)))
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

    hotkeyContinuation.finish()
    await store.finish()
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
    }
  }

  @Test func latchBouncesAndEscapeImmediatelyHidesThePill() async {
    let sessionID = UUID()
    var state = AppFeature.State()
    state.recording.captureGeneration = 1
    state.recording.captureSessionID = sessionID
    state.recording.phase = .recording
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

  @Test func taskSurfacesMissingInputMonitoringPermission() async {
    let events = AsyncStream<HotkeyListenerEvent> { continuation in
      continuation.yield(.inputMonitoringPermissionMissing)
      continuation.finish()
    }
    let (micGate, micContinuation) = AsyncStream.makeStream(of: Void.self)
    let (soundsGate, soundsContinuation) = AsyncStream.makeStream(of: Void.self)
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.hotkeyListener.events = { events }
      $0.microphonePermission.status = {
        for await _ in micGate { return .granted }
        return .granted
      }
      $0.audioCapture.prepare = {}
      $0.asrEngine.prepareInstalled = { AsyncStream { $0.finish() } }
      $0.sounds.loadIsEnabled = {
        for await _ in soundsGate { return false }
        return false
      }
    }

    await store.send(.task)
    soundsContinuation.yield(())
    await store.receive(.soundsEnabledLoaded(false))
    soundsContinuation.finish()
    await store.receive(.recording(.task))
    await store.receive(.hotkeyListenerEvent(.inputMonitoringPermissionMissing))
    micContinuation.yield(())
    await store.receive(.recording(.micStatusUpdated(.granted))) {
      $0.recording.micStatus = .granted
    }
    micContinuation.finish()
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
      $0.delivery.deliver = { transcript in
        #expect(transcript == "delivered text")
        return .pasted(.restored)
      }
      $0.sounds.play = { cue in await sounds.record(cue) }
    }

    await store.send(
      .transcriptionCompleted(1, suppressNoSpeechNotice: false, .transcript("delivered text")))
    await store.receive(.deliveryCompleted(1, .pasted(.restored)))
    await store.receive(.pill(.dismiss)) { $0.pill.presentation = nil }
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
      $0.delivery.deliver = { _ in .copied(.accessibilityPermissionMissing) }
      $0.sounds.play = { cue in await sounds.record(cue) }
      $0.continuousClock = clock
    }

    await store.send(
      .transcriptionCompleted(3, suppressNoSpeechNotice: false, .transcript("copy me")))
    await store.receive(.deliveryCompleted(3, .copied(.accessibilityPermissionMissing)))
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
    var state = AppFeature.State()
    state.soundsEnabled = true
    state.recording.phase = .recording
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.audioCapture.currentInputDeviceName = { "Microphone" }
      $0.asrEngine.prepareForActivation = { AsyncStream { $0.finish() } }
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
      $0.delivery.deliver = { _ in throw DeliveryError.pasteboardWriteFailed }
      $0.sounds.play = { cue in await sounds.record(cue) }
    }
    let message = DeliveryError.pasteboardWriteFailed.localizedDescription

    await store.send(
      .transcriptionCompleted(5, suppressNoSpeechNotice: false, .transcript("undeliverable")))
    await store.receive(.deliveryFailed(5, message))
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
