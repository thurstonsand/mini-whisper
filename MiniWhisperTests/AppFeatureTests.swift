import AudioCapture
import ComposableArchitecture
import HotkeyListener
import Testing

@testable import MiniWhisper

@MainActor @Suite struct AppFeatureTests {
  @Test func taskListensForHotkeyEvents() async {
    let (events, continuation) = AsyncStream.makeStream(of: HotkeyListenerEvent.self)
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.hotkeyListener.events = { events }
      $0.microphonePermission.status = { .granted }
    }

    await store.send(.task)
    await store.receive(.recording(.task))
    await store.receive(.recording(.micStatusUpdated(.granted))) {
      $0.recording.micStatus = .granted
    }

    continuation.yield(.monitoringStarted)
    await store.receive(.hotkeyListenerEvent(.monitoringStarted))
    continuation.yield(.gesture(.startRecording))
    await store.receive(.hotkeyListenerEvent(.gesture(.startRecording)))
    continuation.yield(.monitoringInterrupted(.timeout))
    await store.receive(.hotkeyListenerEvent(.monitoringInterrupted(.timeout)))
    continuation.finish()
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
