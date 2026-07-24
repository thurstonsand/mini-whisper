import AudioCapture
import ComposableArchitecture
import Foundation
import Testing

@testable import MiniWhisper

@MainActor @Suite struct RecordingFeatureTests {
  @Test func taskLoadsPermissionStatus() async {
    let store = TestStore(initialState: RecordingFeature.State()) {
      RecordingFeature()
    } withDependencies: {
      $0.microphonePermission.status = { .granted }
    }

    await store.send(.task)
    await store.receive(.micStatusUpdated(.granted)) { $0.micStatus = .granted }
  }

  @Test func cancelDiscardsTheActiveRecording() async {
    let (events, continuation) = AsyncStream.makeStream(of: AudioCaptureEvent.self)
    let sessionID = UUID()
    let store = TestStore(initialState: RecordingFeature.State()) {
      RecordingFeature()
    } withDependencies: {
      $0.audioCapture.start = { AudioCaptureSession(id: sessionID, events: events) }
      $0.audioCapture.cancel = { id in #expect(id == sessionID) }
    }

    await store.send(.startRecording) {
      $0.captureGeneration = 1
      $0.phase = .starting(nil)
    }
    await store.receive(.captureStarted(1, sessionID)) {
      $0.captureSessionID = sessionID
      $0.phase = .recording
    }
    await store.send(.cancelRecording) { $0.phase = .cancelling }
    await store.receive(.captureCancelled(1)) {
      $0.captureSessionID = nil
      $0.phase = .idle
    }
    continuation.finish()
    await store.receive(.captureEventsFinished(1))
  }

  @Test func stopRequestedWhilePermissionIsPendingCompletesAfterCaptureStarts() async {
    let (startGate, startContinuation) = AsyncStream.makeStream(of: Void.self)
    let (events, eventsContinuation) = AsyncStream.makeStream(of: AudioCaptureEvent.self)
    let recording = CanonicalRecording(samples: [0.1, 0.2])
    let sessionID = UUID()
    let store = TestStore(initialState: RecordingFeature.State()) {
      RecordingFeature()
    } withDependencies: {
      $0.audioCapture.start = {
        for await _ in startGate { break }
        return AudioCaptureSession(id: sessionID, events: events)
      }
      $0.audioCapture.stop = { id in
        #expect(id == sessionID)
        return recording
      }
      $0.audioCapture.writeDebugWAV = { _ in URL(fileURLWithPath: "/tmp/test.wav") }
    }

    await store.send(.startRecording) {
      $0.captureGeneration = 1
      $0.phase = .starting(nil)
    }
    await store.send(.stopAndRetain) { $0.phase = .starting(.stop) }
    startContinuation.yield(())
    startContinuation.finish()
    await store.receive(.captureStarted(1, sessionID)) {
      $0.captureSessionID = sessionID
      $0.phase = .recording
    }
    await store.receive(.stopAndRetain) { $0.phase = .stopping }
    await store.receive(.captureStopped(1, recording)) {
      $0.captureSessionID = nil
      $0.phase = .idle
      $0.completedRecording = recording
    }
    await store.receive(.debugWAVWritten("/tmp/test.wav"))
    eventsContinuation.finish()
    await store.receive(.captureEventsFinished(1))
  }

  @Test func cancelDominatesAStopWhileCaptureIsStarting() async {
    let (startGate, startContinuation) = AsyncStream.makeStream(of: Void.self)
    let (events, eventsContinuation) = AsyncStream.makeStream(of: AudioCaptureEvent.self)
    let sessionID = UUID()
    let store = TestStore(initialState: RecordingFeature.State()) {
      RecordingFeature()
    } withDependencies: {
      $0.audioCapture.start = {
        for await _ in startGate { break }
        return AudioCaptureSession(id: sessionID, events: events)
      }
      $0.audioCapture.cancel = { _ in }
    }

    await store.send(.startRecording) {
      $0.captureGeneration = 1
      $0.phase = .starting(nil)
    }
    await store.send(.cancelRecording) { $0.phase = .starting(.cancel) }
    await store.send(.stopAndRetain)
    startContinuation.yield(())
    startContinuation.finish()
    await store.receive(.captureStarted(1, sessionID)) {
      $0.captureSessionID = sessionID
      $0.phase = .recording
    }
    await store.receive(.cancelRecording) { $0.phase = .cancelling }
    await store.receive(.captureCancelled(1)) {
      $0.captureSessionID = nil
      $0.phase = .idle
    }
    eventsContinuation.finish()
    await store.receive(.captureEventsFinished(1))
  }

  @Test func deniedCaptureUpdatesThePermissionBoundary() async {
    let store = TestStore(initialState: RecordingFeature.State()) {
      RecordingFeature()
    } withDependencies: {
      $0.audioCapture.start = { throw AudioCaptureError.microphonePermission(.denied) }
    }

    await store.send(.startRecording) {
      $0.captureGeneration = 1
      $0.phase = .starting(nil)
    }
    await store.receive(.captureFailed(1, .microphonePermission(.denied))) {
      $0.phase = .cancelling
      $0.micStatus = .denied
      $0.captureError = .microphonePermission(.denied)
    }
    await store.receive(.captureCancelled(1)) { $0.phase = .idle }
  }

  @Test func runtimePermissionErrorUpdatesStructuralStatus() async {
    let sessionID = UUID()
    var state = RecordingFeature.State()
    state.micStatus = .granted
    state.captureGeneration = 1
    state.captureSessionID = sessionID
    state.phase = .recording
    let store = TestStore(initialState: state) {
      RecordingFeature()
    } withDependencies: {
      $0.audioCapture.cancel = { _ in }
    }

    await store.send(.captureFailed(1, .microphonePermission(.denied))) {
      $0.phase = .cancelling
      $0.micStatus = .denied
      $0.captureError = .microphonePermission(.denied)
    }
    await store.receive(.captureCancelled(1)) {
      $0.captureSessionID = nil
      $0.phase = .idle
    }
  }

  @Test func cancellationDoesNotInferPermissionChanges() async {
    let sessionID = UUID()
    var state = RecordingFeature.State()
    state.micStatus = .granted
    state.captureGeneration = 1
    state.captureSessionID = sessionID
    state.phase = .recording
    let store = TestStore(initialState: state) {
      RecordingFeature()
    } withDependencies: {
      $0.audioCapture.cancel = { _ in }
    }

    await store.send(.cancelRecording) { $0.phase = .cancelling }
    await store.receive(.captureCancelled(1)) {
      $0.captureSessionID = nil
      $0.phase = .idle
    }
  }

  @Test func stopFailureUsesCaptureFailureCleanup() async {
    let sessionID = UUID()
    var state = RecordingFeature.State()
    state.captureGeneration = 1
    state.captureSessionID = sessionID
    state.phase = .recording
    let store = TestStore(initialState: state) {
      RecordingFeature()
    } withDependencies: {
      $0.audioCapture.stop = { _ in throw AudioCaptureError.engineConfigurationChanged }
      $0.audioCapture.cancel = { _ in }
    }

    await store.send(.stopAndRetain) { $0.phase = .stopping }
    await store.receive(.captureFailed(1, .engineConfigurationChanged)) {
      $0.phase = .cancelling
      $0.captureError = .engineConfigurationChanged
    }
    await store.receive(.captureCancelled(1)) {
      $0.captureSessionID = nil
      $0.phase = .idle
    }
  }

  @Test func cancelWhileStoppingDiscardsAnyLateStopResult() async {
    let sessionID = UUID()
    let recording = CanonicalRecording(samples: [0.1])
    var state = RecordingFeature.State()
    state.captureGeneration = 1
    state.captureSessionID = sessionID
    state.phase = .stopping
    let store = TestStore(initialState: state) {
      RecordingFeature()
    } withDependencies: {
      $0.audioCapture.cancel = { _ in }
    }

    await store.send(.cancelRecording) { $0.phase = .cancelling }
    await store.receive(.captureCancelled(1)) {
      $0.captureSessionID = nil
      $0.phase = .idle
    }
    await store.send(.captureStopped(1, recording))
  }

  @Test func staleCaptureActionsCannotMutateTheCurrentCapture() async {
    let sessionID = UUID()
    var state = RecordingFeature.State()
    state.captureGeneration = 2
    state.captureSessionID = sessionID
    state.phase = .recording
    let store = TestStore(initialState: state) { RecordingFeature() }

    await store.send(.captureCancelled(1))
    await store.send(.captureStopped(1, CanonicalRecording(samples: [1])))
    await store.send(.levelUpdated(1, AudioLevel(decibels: 0, normalizedPower: 1)))
  }
}

@Suite struct MenuBarViewStateTests {
  @Test func grantedPermissionIsReady() {
    let state = MenuBarViewState(micStatus: .granted)

    #expect(state.iconSymbolName == "mic")
    #expect(state.statusText == "Ready")
  }

  @Test func deniedPermissionIsDegraded() {
    let state = MenuBarViewState(micStatus: .denied)

    #expect(state.iconSymbolName == "mic.slash")
    #expect(state.statusText == "Microphone permission required")
  }

  @Test func restrictedPermissionIsDegradedDistinctly() {
    let state = MenuBarViewState(micStatus: .restricted)

    #expect(state.iconSymbolName == "mic.slash")
    #expect(state.statusText == "Microphone access restricted")
  }

  @Test func undeterminedPermissionHasNotBeenRequested() {
    let state = MenuBarViewState(micStatus: .undetermined)

    #expect(state.iconSymbolName == "mic")
    #expect(state.statusText == "Microphone permission not yet requested")
  }

  @Test func unknownPermissionFailsClosed() {
    let state = MenuBarViewState(micStatus: .unknown)

    #expect(state.iconSymbolName == "mic.slash")
    #expect(state.statusText == "Microphone permission unavailable")
  }
}
