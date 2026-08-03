import ComposableArchitecture
@testable import MiniWhisper
import Testing

@MainActor struct PillFeatureTests {
  @Test func `activation starts neutral until capture is live`() async {
    let store = TestStore(initialState: PillFeature.State()) { PillFeature() }

    await store.send(.recordingStarting(inputDeviceName: "Shure MV7")) {
      $0.presentation = .recording(
        PillFeature.State.Presentation.Recording(
          inputDeviceName: "Shure MV7", level: 0, isLive: false,
        ),
      )
    }
    await store.send(.levelUpdated(1))
    await store.send(.recordingStarted(inputDeviceName: "Shure MV7")) {
      $0.presentation = .recording(
        PillFeature.State.Presentation.Recording(
          inputDeviceName: "Shure MV7", level: 0, isLive: true,
        ),
      )
    }
  }

  @Test func `recording shows device and tracks live levels`() async {
    let store = TestStore(initialState: PillFeature.State()) { PillFeature() }

    await store.send(.recordingStarted(inputDeviceName: "Shure MV7")) {
      $0.presentation = .recording(
        PillFeature.State.Presentation.Recording(
          inputDeviceName: "Shure MV7", level: 0, isLive: true,
        ),
      )
    }
    await store.send(.levelUpdated(0.72)) {
      $0.presentation = .recording(
        PillFeature.State.Presentation.Recording(
          inputDeviceName: "Shure MV7", level: 0.72, isLive: true,
        ),
      )
      $0.accessibilityLevel = 70
    }
    await store.send(.levelUpdated(0.74)) {
      $0.presentation = .recording(
        PillFeature.State.Presentation.Recording(
          inputDeviceName: "Shure MV7", level: 0.74, isLive: true,
        ),
      )
    }
    await store.send(.levelUpdated(0.31)) {
      $0.presentation = .recording(
        PillFeature.State.Presentation.Recording(
          inputDeviceName: "Shure MV7", level: 0.31, isLive: true,
        ),
      )
      $0.accessibilityLevel = 30
    }
    await store.send(.latchEngaged) { $0.bounceCount = 1 }
  }

  @Test func `latch waits for capture when recording has not appeared yet`() async {
    let store = TestStore(initialState: PillFeature.State()) { PillFeature() }

    await store.send(.latchEngaged) { $0.isLatchBouncePending = true }
    await store.send(.levelUpdated(1))
    await store.send(.recordingStarted(inputDeviceName: "Test Microphone")) {
      $0.presentation = .recording(
        PillFeature.State.Presentation.Recording(
          inputDeviceName: "Test Microphone", level: 0, isLive: true,
        ),
      )
      $0.bounceCount = 1
      $0.isLatchBouncePending = false
    }
  }

  @Test func `transcribing replaces recording content`() async {
    var state = PillFeature.State()
    state.presentation = .recording(
      PillFeature.State.Presentation.Recording(
        inputDeviceName: "Studio Display", level: 0.4, isLive: true,
      ),
    )
    let store = TestStore(initialState: state) { PillFeature() }

    await store.send(.transcribingStarted) { $0.presentation = .transcribing }
  }

  @Test func `no speech notice fades and dismisses after its delay`() async {
    let clock = TestClock()
    let store = TestStore(initialState: PillFeature.State()) {
      PillFeature()
    } withDependencies: {
      $0.continuousClock = clock
    }

    await store.send(.noSpeechDetected) {
      $0.noticeGeneration = 1
      $0.presentation = .notice(.noSpeechDetected)
    }
    await clock.advance(by: .milliseconds(1500))
    await store.receive(.noticeDisplayElapsed(1)) { $0.isFadingOut = true }
    await clock.advance(by: .milliseconds(180))
    await store.receive(.noticeFadeElapsed(1)) {
      $0.presentation = nil
      $0.isFadingOut = false
    }
  }

  @Test func `field context notice is as brief as the no speech one`() async {
    let clock = TestClock()
    let store = TestStore(initialState: PillFeature.State()) {
      PillFeature()
    } withDependencies: {
      $0.continuousClock = clock
    }

    await store.send(.fieldContextUnavailable) {
      $0.noticeGeneration = 1
      $0.presentation = .notice(.fieldContextUnavailable)
    }
    await clock.advance(by: .milliseconds(1500))
    await store.receive(.noticeDisplayElapsed(1)) { $0.isFadingOut = true }
    await clock.advance(by: .milliseconds(180))
    await store.receive(.noticeFadeElapsed(1)) {
      $0.presentation = nil
      $0.isFadingOut = false
    }
  }

  @Test func `copied notice lingers for three seconds`() async {
    let clock = TestClock()
    let store = TestStore(initialState: PillFeature.State()) {
      PillFeature()
    } withDependencies: {
      $0.continuousClock = clock
    }

    await store.send(.copiedToClipboard) {
      $0.noticeGeneration = 1
      $0.presentation = .notice(.copiedToClipboard)
    }
    await clock.advance(by: .milliseconds(2999))
    await clock.advance(by: .milliseconds(1))
    await store.receive(.noticeDisplayElapsed(1)) { $0.isFadingOut = true }
    await clock.advance(by: .milliseconds(180))
    await store.receive(.noticeFadeElapsed(1)) {
      $0.presentation = nil
      $0.isFadingOut = false
    }
  }

  @Test func `newer notice supersedes an earlier dismissal`() async {
    let clock = TestClock()
    let store = TestStore(initialState: PillFeature.State()) {
      PillFeature()
    } withDependencies: {
      $0.continuousClock = clock
    }

    await store.send(.noSpeechDetected) {
      $0.noticeGeneration = 1
      $0.presentation = .notice(.noSpeechDetected)
    }
    await clock.advance(by: .seconds(1))
    await store.send(.copiedToClipboard) {
      $0.noticeGeneration = 2
      $0.presentation = .notice(.copiedToClipboard)
    }
    await clock.advance(by: .milliseconds(500))
    await store.send(.noticeDisplayElapsed(1))
    await clock.advance(by: .milliseconds(2500))
    await store.receive(.noticeDisplayElapsed(2)) { $0.isFadingOut = true }
    await clock.advance(by: .milliseconds(180))
    await store.receive(.noticeFadeElapsed(2)) {
      $0.presentation = nil
      $0.isFadingOut = false
    }
  }

  @Test func `cancel hides immediately and cancels notice timing`() async {
    let clock = TestClock()
    let store = TestStore(initialState: PillFeature.State()) {
      PillFeature()
    } withDependencies: {
      $0.continuousClock = clock
    }

    await store.send(.copiedToClipboard) {
      $0.noticeGeneration = 1
      $0.presentation = .notice(.copiedToClipboard)
    }
    await store.send(.cancel) { $0.presentation = nil }
    await clock.advance(by: .seconds(4))
  }

  @Test func `successful dismissal hides immediately`() async {
    var state = PillFeature.State()
    state.presentation = .transcribing
    let store = TestStore(initialState: state) { PillFeature() }

    await store.send(.dismiss) { $0.presentation = nil }
  }
}
