import AudioCapture
import ComposableArchitecture
import Testing

@testable import MiniWhisper

@MainActor @Suite struct RecordingFeaturePermissionTests {
  @Test func taskLoadsPermissionStatus() async {
    let store = TestStore(initialState: RecordingFeature.State()) {
      RecordingFeature()
    } withDependencies: {
      $0.microphonePermission.status = { .granted }
    }

    await store.send(.task)
    await store.receive(.micStatusUpdated(.granted)) { $0.micStatus = .granted }
  }

  @Test func requestMicAccessUpdatesStatus() async {
    let store = TestStore(initialState: RecordingFeature.State()) {
      RecordingFeature()
    } withDependencies: {
      $0.microphonePermission.request = { .granted }
    }

    await store.send(.requestMicAccess)
    await store.receive(.micStatusUpdated(.granted)) { $0.micStatus = .granted }
  }

  @Test func requestMicAccessCanBeDenied() async {
    let store = TestStore(initialState: RecordingFeature.State()) {
      RecordingFeature()
    } withDependencies: {
      $0.microphonePermission.request = { .denied }
    }

    await store.send(.requestMicAccess)
    await store.receive(.micStatusUpdated(.denied)) { $0.micStatus = .denied }
  }
}

@MainActor @Suite struct RecordingFeatureRecordingTests {
  @Test func startsInIdleState() {
    let state = RecordingFeature.State(micStatus: .granted)
    #expect(state.status == .idle)
  }

  @Test func startRecordingTransitionsToRecording() async {
    let store = TestStore(initialState: RecordingFeature.State(micStatus: .granted)) {
      RecordingFeature()
    }

    await store.send(.startRecording) { $0.status = .recording }
  }

  @Test func startRecordingRequiresGrantedPermission() async {
    let store = TestStore(initialState: RecordingFeature.State(micStatus: .denied)) {
      RecordingFeature()
    }

    await store.send(.startRecording)
  }

  @Test func stopRecordingTransitionsToProcessing() async {
    let store = TestStore(
      initialState: RecordingFeature.State(micStatus: .granted, status: .recording)
    ) { RecordingFeature() }

    await store.send(.stopRecording) { $0.status = .processing }
  }

  @Test func stopRecordingOnlyWorksWhenRecording() async {
    let store = TestStore(initialState: RecordingFeature.State(micStatus: .granted)) {
      RecordingFeature()
    }

    await store.send(.stopRecording)
  }

  @Test func resetClearsAllState() async {
    let store = TestStore(
      initialState: RecordingFeature.State(
        micStatus: .granted, status: .recording, audioLevel: 0.5, currentTranscription: "hello",
        lastError: "boom")
    ) { RecordingFeature() }

    await store.send(.reset) {
      $0.status = .idle
      $0.audioLevel = 0
      $0.currentTranscription = nil
      $0.lastError = nil
    }
  }
}

@Suite struct IconSelectionTests {
  @Test func recordingShowsRecordIcon() {
    let symbol = MenuBarViewState.iconSymbolName(
      status: RecordingStatus.recording, micStatus: MicPermissionStatus.granted)
    #expect(symbol == "record.circle.fill")
  }

  @Test func processingShowsEllipsisIcon() {
    let symbol = MenuBarViewState.iconSymbolName(
      status: RecordingStatus.processing, micStatus: MicPermissionStatus.granted)
    #expect(symbol == "ellipsis.circle")
  }

  @Test func idleWithMicGrantedShowsWaveform() {
    let symbol = MenuBarViewState.iconSymbolName(
      status: RecordingStatus.idle, micStatus: MicPermissionStatus.granted)
    #expect(symbol == "waveform")
  }

  @Test func idleWithMicDeniedShowsWarningIcon() {
    let symbol = MenuBarViewState.iconSymbolName(
      status: RecordingStatus.idle, micStatus: MicPermissionStatus.denied)
    #expect(symbol == "waveform.badge.exclamationmark")
  }

  @Test func idleWithMicUndeterminedShowsWarningIcon() {
    let symbol = MenuBarViewState.iconSymbolName(
      status: RecordingStatus.idle, micStatus: MicPermissionStatus.undetermined)
    #expect(symbol == "waveform.badge.exclamationmark")
  }
}
