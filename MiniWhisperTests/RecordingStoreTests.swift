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

  @Test func undeterminedPermissionIsBeingChecked() {
    let state = MenuBarViewState(micStatus: .undetermined)

    #expect(state.iconSymbolName == "mic")
    #expect(state.statusText == "Checking microphone permission")
  }
}
