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
      $0.audioCapture.start = { AudioCaptureSession(id: sessionID, events: captureEvents) }
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
    await store.receive(.recording(.captureStarted(1, sessionID))) {
      $0.recording.captureSessionID = sessionID
      $0.recording.phase = .recording
    }

    hotkeyContinuation.yield(.gesture(.stopAndTranscribe))
    await store.receive(.hotkeyListenerEvent(.gesture(.stopAndTranscribe)))
    await store.receive(.recording(.stopAndRetain)) { $0.recording.phase = .stopping }
    await store.receive(.recording(.captureStopped(1, recording))) {
      $0.recording.captureSessionID = nil
      $0.recording.phase = .idle
      $0.recording.completedRecording = recording
    }
    await store.receive(.recording(.debugWAVWritten(debugURL.path)))
    captureContinuation.finish()
    await store.receive(.recording(.captureEventsFinished(1)))

    hotkeyContinuation.finish()
    await store.finish()
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
