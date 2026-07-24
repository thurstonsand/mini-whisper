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
    let recording = CanonicalRecording(samples: [0.1, 0.2, 0.3])
    let sessionID = UUID()
    let debugURL = URL(fileURLWithPath: "/tmp/MiniWhisper-test.wav")
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
      $0.audioCapture.writeDebugWAV = { _ in debugURL }
    }

    await store.send(.task)
    await store.receive(.recording(.task))
    await store.receive(.recording(.micStatusUpdated(.granted))) {
      $0.recording.micStatus = .granted
    }

    hotkeyContinuation.yield(.monitoringStarted)
    await store.receive(.hotkeyListenerEvent(.monitoringStarted))
    hotkeyContinuation.yield(.gesture(.startRecording))
    await store.receive(.hotkeyListenerEvent(.gesture(.startRecording)))
    await store.receive(.recording(.startRecording)) {
      $0.recording.captureGeneration = 1
      $0.recording.phase = .starting(nil)
    }
    await store.receive(.recording(.captureStarted(1, sessionID, "Test Microphone"))) {
      $0.recording.captureSessionID = sessionID
      $0.recording.phase = .recording
    }
    await store.receive(
      .recording(.delegate(.recordingStarted(inputDeviceName: "Test Microphone"))))
    await store.receive(.pill(.recordingStarted(inputDeviceName: "Test Microphone"))) {
      $0.pill.presentation = .recording(
        PillFeature.State.Presentation.Recording(inputDeviceName: "Test Microphone", level: 0))
    }

    hotkeyContinuation.yield(.gesture(.stopAndTranscribe))
    await store.receive(.hotkeyListenerEvent(.gesture(.stopAndTranscribe)))
    await store.receive(.recording(.stopAndRetain)) { $0.recording.phase = .stopping(nil) }
    await store.receive(.recording(.captureStopped(1, recording))) {
      $0.recording.captureSessionID = nil
      $0.recording.phase = .idle
      $0.recording.completedRecording = recording
    }
    await store.receive(.recording(.delegate(.stopped)))
    await store.receive(.pill(.dismiss)) { $0.pill.presentation = nil }
    await store.receive(.recording(.debugWAVWritten(debugURL.path)))
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
      PillFeature.State.Presentation.Recording(inputDeviceName: "Test Microphone", level: 0))
    let store = TestStore(initialState: state) { AppFeature() }
    let level = AudioLevel(decibels: -12, normalizedPower: 0.8)

    await store.send(.recording(.levelUpdated(1, level))) { $0.recording.latestLevel = 0.8 }
    await store.receive(.recording(.delegate(.levelChanged(0.8))))
    await store.receive(.pill(.levelUpdated(0.8))) {
      $0.pill.presentation = .recording(
        PillFeature.State.Presentation.Recording(inputDeviceName: "Test Microphone", level: 0.8))
    }
  }

  @Test func latchBouncesAndEscapeImmediatelyHidesThePill() async {
    let sessionID = UUID()
    var state = AppFeature.State()
    state.recording.captureGeneration = 1
    state.recording.captureSessionID = sessionID
    state.recording.phase = .recording
    state.pill.presentation = .recording(
      PillFeature.State.Presentation.Recording(inputDeviceName: "Test Microphone", level: 0.5))
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

  @Test func taskSurfacesMissingInputMonitoringPermission() async {
    let events = AsyncStream<HotkeyListenerEvent> { continuation in
      continuation.yield(.inputMonitoringPermissionMissing)
      continuation.finish()
    }
    let (micGate, micContinuation) = AsyncStream.makeStream(of: Void.self)
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.hotkeyListener.events = { events }
      $0.microphonePermission.status = {
        for await _ in micGate { return .granted }
        return .granted
      }
    }

    await store.send(.task)
    await store.receive(.recording(.task))
    await store.receive(.hotkeyListenerEvent(.inputMonitoringPermissionMissing))
    micContinuation.yield(())
    await store.receive(.recording(.micStatusUpdated(.granted))) {
      $0.recording.micStatus = .granted
    }
    micContinuation.finish()
    await store.finish()
  }
}
