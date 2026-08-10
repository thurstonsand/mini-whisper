import ASREngine
import ComposableArchitecture
import Foundation
import HotkeyListener
@testable import MiniWhisper
import Testing

@MainActor struct DictationReadinessTests {
  @Test func `a dictation is refused while the speech model is not ready`() async {
    let sounds = SoundRecorder()
    var state = AppFeature.State()
    state.$health.withLock {
      $0 = .healthy
      $0.engineReadiness = .modelMissing
    }
    state.onboardingCompleted = true
    let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
      $0.audioCapture.start = { _ in
        Issue.record("The microphone was opened for a dictation that cannot be transcribed")
        throw CancellationError()
      }
      $0.sounds.play = { name in await sounds.record(name) }
      $0.continuousClock = TestClock()
    }

    await store.send(.hotkeyListenerEvent(.gesture(.startRecording)))
    await store.receive(.pill(.speechModelUnavailable("Speech model not installed"))) {
      $0.pill.presentation = .notice(.speechModelUnavailable("Speech model not installed"))
      $0.pill.noticeGeneration = 1
    }
    #expect(store.state.recording.phase == .idle)
    #expect(!store.state.dictationInFlight)
    #expect(await sounds.recorded == ["Basso"])
    await store.send(.pill(.dismiss)) { $0.pill.presentation = nil }
  }

  @Test func `the refusal says what the engine is actually doing`() async {
    var state = AppFeature.State()
    state.$health.withLock {
      $0 = .healthy
      $0.engineReadiness = .downloading(0.42)
    }
    state.onboardingCompleted = true
    let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
      $0.sounds.play = { _ in }
      $0.continuousClock = TestClock()
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.hotkeyListenerEvent(.gesture(.startRecording)))
    await store.receive(
      .pill(.speechModelUnavailable("Downloading Parakeet v2 · 42%")),
    )
  }
}
