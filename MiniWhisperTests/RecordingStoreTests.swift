import AppSettings
import ASREngine
import AudioCapture
import ComposableArchitecture
import Foundation
@testable import MiniWhisper
import Testing

// MARK: - RecordingFeatureTests

@MainActor struct RecordingFeatureTests {
  @Test func `task prepares audio capture for the stored microphone`() async {
    let preparations = RecordingCounter()
    var settings = MiniWhisperSettings.defaults
    settings.microphone = .device(uid: "studio", lastKnownName: "Studio Microphone")
    let microphone = settings.microphone
    let store = TestStore(initialState: recordingState(settings)) {
      RecordingFeature()
    } withDependencies: {
      $0.audioCapture.prepare = { selection in
        #expect(selection == microphone)
        preparations.increment()
      }
    }

    await store.send(.task)
    await store.finish()
    #expect(preparations.value == 1)
  }

  @Test func `committing A microphone selection prewarms that device`() async {
    let preparedSelection = MicrophoneSelectionRecorder()
    let studio = AudioInputDevice(uid: "studio", name: "Studio Microphone")
    var state = AppFeature.State()
    state.settingsWindow.settingsPane.inputDevices = AudioInputDeviceSnapshot(
      devices: [studio], defaultDevice: studio,
    )
    let selection = MicrophoneSelection.device(uid: studio.uid, lastKnownName: studio.name)
    let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
      $0.audioCapture.prepare = { preparedSelection.record($0) }
    }

    await store.send(.settingsWindow(.settingsPane(.microphoneSelected(selection)))) {
      $0.$settings.withLock { $0.microphone = selection }
    }
    await store.receive(
      .settingsWindow(.settingsPane(.delegate(.microphoneChanged(selection)))),
    )
    await store.receive(.recording(.microphoneChanged(selection)))
    await store.receive(.settingsWindow(.settingsPane(.inputLevelUpdated(nil))))
    await store.finish()
    #expect(preparedSelection.value == selection)
  }

  @Test func `cancel discards the active recording`() async {
    let (events, continuation) = AsyncStream.makeStream(of: AudioCaptureEvent.self)
    let sessionID = UUID()
    let store = TestStore(initialState: recordingState()) {
      RecordingFeature()
    } withDependencies: {
      $0.audioCapture.start = { _ in
        AudioCaptureSession(id: sessionID, inputDeviceName: "Test Microphone", events: events)
      }
      $0.audioCapture.cancel = { id in #expect(id == sessionID) }
    }

    await store.send(.startRecording) {
      $0.captureGeneration = 1
      $0.phase = .starting(nil)
    }
    await store.receive(.captureSessionStarted(1, sessionID)) { $0.captureSessionID = sessionID }
    continuation.yield(.captureBecameLive)
    await store.receive(.captureBecameLive(1, sessionID, "Test Microphone")) {
      $0.phase = .recording
    }
    await store.receive(.delegate(.recordingStarted(inputDeviceName: "Test Microphone")))
    await store.send(.cancelRecording) { $0.phase = .cancelling }
    await store.receive(.delegate(.discarded))
    await store.receive(.captureCancelled(1)) {
      $0.captureSessionID = nil
      $0.phase = .idle
    }
    continuation.finish()
    await store.receive(.captureEventsFinished(1))
  }

  @Test func `stop completes an empty capture that never receives A buffer`() async {
    let (events, continuation) = AsyncStream.makeStream(of: AudioCaptureEvent.self)
    let sessionID = UUID()
    let recording = CanonicalRecording(samples: [])
    let store = TestStore(initialState: recordingState()) {
      RecordingFeature()
    } withDependencies: {
      $0.audioCapture.start = { _ in
        AudioCaptureSession(id: sessionID, inputDeviceName: "Idle Loopback", events: events)
      }
      $0.audioCapture.stop = { id in
        #expect(id == sessionID)
        return recording
      }
    }

    await store.send(.startRecording) {
      $0.captureGeneration = 1
      $0.phase = .starting(nil)
    }
    await store.receive(.captureSessionStarted(1, sessionID)) { $0.captureSessionID = sessionID }
    await store.send(.stopAndRetain) { $0.phase = .stopping(nil) }
    await store.receive(.captureStopped(1, recording)) {
      $0.captureSessionID = nil
      $0.phase = .idle
    }
    await store.receive(.delegate(.completed(recording)))
    continuation.finish()
    await store.receive(.captureEventsFinished(1))
  }

  @Test func `A stop that beats the session ID still ends the capture`() async {
    let (startGate, startContinuation) = AsyncStream.makeStream(of: Void.self)
    let (events, continuation) = AsyncStream.makeStream(of: AudioCaptureEvent.self)
    let sessionID = UUID()
    let recording = CanonicalRecording(samples: [])
    let store = TestStore(initialState: recordingState()) {
      RecordingFeature()
    } withDependencies: {
      $0.audioCapture.start = { _ in
        for await _ in startGate {
          break
        }
        return AudioCaptureSession(id: sessionID, inputDeviceName: "Idle Loopback", events: events)
      }
      $0.audioCapture.stop = { _ in recording }
    }

    await store.send(.startRecording) {
      $0.captureGeneration = 1
      $0.phase = .starting(nil)
    }
    await store.send(.stopAndRetain) { $0.phase = .starting(.stop) }
    startContinuation.yield(())
    startContinuation.finish()
    // The session never goes live, so the pending stop is spent the moment its ID lands rather
    // than waiting for a first buffer that is not coming.
    await store.receive(.captureSessionStarted(1, sessionID)) {
      $0.captureSessionID = sessionID
      $0.phase = .stopping(nil)
    }
    await store.receive(.captureStopped(1, recording)) {
      $0.captureSessionID = nil
      $0.phase = .idle
    }
    await store.receive(.delegate(.completed(recording)))
    continuation.finish()
    await store.receive(.captureEventsFinished(1))
  }

  @Test func `cancel dominates A stop while capture is starting`() async {
    let (startGate, startContinuation) = AsyncStream.makeStream(of: Void.self)
    let (events, eventsContinuation) = AsyncStream.makeStream(of: AudioCaptureEvent.self)
    let sessionID = UUID()
    let store = TestStore(initialState: recordingState()) {
      RecordingFeature()
    } withDependencies: {
      $0.audioCapture.start = { _ in
        for await _ in startGate {
          break
        }
        return AudioCaptureSession(
          id: sessionID, inputDeviceName: "Test Microphone", events: events,
        )
      }
      $0.audioCapture.cancel = { _ in }
    }

    await store.send(.startRecording) {
      $0.captureGeneration = 1
      $0.phase = .starting(nil)
    }
    await store.send(.cancelRecording) { $0.phase = .starting(.cancel) }
    await store.receive(.delegate(.discarded))
    await store.send(.stopAndRetain)
    startContinuation.yield(())
    startContinuation.finish()
    await store.receive(.captureSessionStarted(1, sessionID)) {
      $0.captureSessionID = sessionID
      $0.phase = .cancelling
    }
    await store.receive(.captureCancelled(1)) {
      $0.captureSessionID = nil
      $0.phase = .idle
    }
    eventsContinuation.finish()
    await store.receive(.captureEventsFinished(1))
  }

  @Test func `second activation keeps A still starting capture alive for latch`() async {
    var state = recordingState()
    state.captureGeneration = 1
    state.phase = .starting(.stop)
    let store = TestStore(initialState: state) { RecordingFeature() }

    await store.send(.startRecording) { $0.phase = .starting(nil) }
  }

  @Test func `second activation restarts capture if the first stop already began`() async {
    let firstSessionID = UUID()
    let secondSessionID = UUID()
    let firstRecording = CanonicalRecording(samples: [0.1])
    let (events, eventsContinuation) = AsyncStream.makeStream(of: AudioCaptureEvent.self)
    var state = recordingState()
    state.captureGeneration = 1
    state.captureSessionID = firstSessionID
    state.phase = .stopping(nil)
    let store = TestStore(initialState: state) {
      RecordingFeature()
    } withDependencies: {
      $0.audioCapture.start = { _ in
        AudioCaptureSession(id: secondSessionID, inputDeviceName: "Test Microphone", events: events)
      }
      $0.audioCapture.cancel = { id in #expect(id == secondSessionID) }
    }

    await store.send(.startRecording) { $0.phase = .stopping(.restart) }
    await store.send(.captureStopped(1, firstRecording)) {
      $0.captureGeneration = 2
      $0.captureSessionID = nil
      $0.phase = .starting(nil)
    }
    await store.receive(.captureSessionStarted(2, secondSessionID)) {
      $0.captureSessionID = secondSessionID
    }
    eventsContinuation.yield(.captureBecameLive)
    await store.receive(.captureBecameLive(2, secondSessionID, "Test Microphone")) {
      $0.phase = .recording
    }
    await store.receive(.delegate(.recordingStarted(inputDeviceName: "Test Microphone")))
    await store.send(.cancelRecording) { $0.phase = .cancelling }
    await store.receive(.delegate(.discarded))
    await store.receive(.captureCancelled(2)) {
      $0.captureSessionID = nil
      $0.phase = .idle
    }
    eventsContinuation.finish()
    await store.receive(.captureEventsFinished(2))
  }

  @Test func `denied capture updates the permission boundary`() async {
    let store = TestStore(initialState: recordingState()) {
      RecordingFeature()
    } withDependencies: {
      $0.audioCapture.start = { _ in throw AudioCaptureError.microphonePermission(.denied) }
    }

    await store.send(.startRecording) {
      $0.captureGeneration = 1
      $0.phase = .starting(nil)
    }
    await store.receive(.captureFailed(1, .microphonePermission(.denied))) {
      $0.phase = .cancelling
      $0.$health.withLock { $0.micStatus = .denied }
      $0.captureError = .microphonePermission(.denied)
    }
    await store.receive(.delegate(.failed))
    await store.receive(.captureCancelled(1)) { $0.phase = .idle }
  }

  @Test func `runtime permission error updates structural status`() async {
    let sessionID = UUID()
    var state = recordingState()
    state.$health.withLock { $0.micStatus = .granted }
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
      $0.$health.withLock { $0.micStatus = .denied }
      $0.captureError = .microphonePermission(.denied)
    }
    await store.receive(.delegate(.failed))
    await store.receive(.captureCancelled(1)) {
      $0.captureSessionID = nil
      $0.phase = .idle
    }
  }

  @Test func `cancellation does not infer permission changes`() async {
    let sessionID = UUID()
    var state = recordingState()
    state.$health.withLock { $0.micStatus = .granted }
    state.captureGeneration = 1
    state.captureSessionID = sessionID
    state.phase = .recording
    let store = TestStore(initialState: state) {
      RecordingFeature()
    } withDependencies: {
      $0.audioCapture.cancel = { _ in }
    }

    await store.send(.cancelRecording) { $0.phase = .cancelling }
    await store.receive(.delegate(.discarded))
    await store.receive(.captureCancelled(1)) {
      $0.captureSessionID = nil
      $0.phase = .idle
    }
  }

  @Test func `stop failure uses capture failure cleanup`() async {
    let sessionID = UUID()
    var state = recordingState()
    state.captureGeneration = 1
    state.captureSessionID = sessionID
    state.phase = .recording
    let store = TestStore(initialState: state) {
      RecordingFeature()
    } withDependencies: {
      $0.audioCapture.stop = { _ in throw AudioCaptureError.engineConfigurationChanged }
      $0.audioCapture.cancel = { _ in }
    }

    await store.send(.stopAndRetain) { $0.phase = .stopping(nil) }
    await store.receive(.captureFailed(1, .engineConfigurationChanged)) {
      $0.phase = .cancelling
      $0.captureError = .engineConfigurationChanged
    }
    await store.receive(.delegate(.failed))
    await store.receive(.captureCancelled(1)) {
      $0.captureSessionID = nil
      $0.phase = .idle
    }
  }

  @Test func `cancel while stopping discards any late stop result`() async {
    let sessionID = UUID()
    let recording = CanonicalRecording(samples: [0.1])
    var state = recordingState()
    state.captureGeneration = 1
    state.captureSessionID = sessionID
    state.phase = .stopping(nil)
    let store = TestStore(initialState: state) {
      RecordingFeature()
    } withDependencies: {
      $0.audioCapture.cancel = { _ in }
    }

    await store.send(.cancelRecording) { $0.phase = .cancelling }
    await store.receive(.delegate(.discarded))
    await store.receive(.captureCancelled(1)) {
      $0.captureSessionID = nil
      $0.phase = .idle
    }
    await store.send(.captureStopped(1, recording))
  }

  @Test func `stale capture actions cannot mutate the current capture`() async {
    let sessionID = UUID()
    var state = recordingState()
    state.captureGeneration = 2
    state.captureSessionID = sessionID
    state.phase = .recording
    let store = TestStore(initialState: state) { RecordingFeature() }

    await store.send(.captureCancelled(1))
    await store.send(.captureStopped(1, CanonicalRecording(samples: [1])))
    await store.send(.levelUpdated(1, AudioLevel(decibels: 0, normalizedPower: 1)))
  }
}

private func recordingState(
  _ settings: MiniWhisperSettings = .defaults,
) -> RecordingFeature.State {
  RecordingFeature.State(
    settings: Shared(value: settings),
    health: Shared(value: AppHealth()),
  )
}

// MARK: - MicrophoneSelectionRecorder

private final class MicrophoneSelectionRecorder: @unchecked Sendable {
  // MARK: Internal

  var value: MicrophoneSelection? {
    lock.withLock { selection }
  }

  func record(_ selection: MicrophoneSelection) {
    lock.withLock { self.selection = selection }
  }

  // MARK: Private

  private let lock = NSLock()
  private var selection: MicrophoneSelection?
}

// MARK: - RecordingCounter

private final class RecordingCounter: @unchecked Sendable {
  // MARK: Internal

  var value: Int {
    lock.withLock { count }
  }

  func increment() {
    lock.withLock { count += 1 }
  }

  // MARK: Private

  private let lock = NSLock()
  private var count = 0
}
