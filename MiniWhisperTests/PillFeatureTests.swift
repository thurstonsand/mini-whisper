import ComposableArchitecture
import Testing

@testable import MiniWhisper

@MainActor @Suite struct PillFeatureTests {
  @Test func recordingShowsDeviceAndTracksLiveLevels() async {
    let store = TestStore(initialState: PillFeature.State()) { PillFeature() }

    await store.send(.recordingStarted(inputDeviceName: "Shure MV7")) {
      $0.presentation = .recording(
        PillFeature.State.Presentation.Recording(inputDeviceName: "Shure MV7", level: 0))
    }
    await store.send(.levelUpdated(0.72)) {
      $0.presentation = .recording(
        PillFeature.State.Presentation.Recording(inputDeviceName: "Shure MV7", level: 0.72))
    }
    await store.send(.latchEngaged) { $0.bounceCount = 1 }
  }

  @Test func latchWaitsForCaptureWhenRecordingHasNotAppearedYet() async {
    let store = TestStore(initialState: PillFeature.State()) { PillFeature() }

    await store.send(.latchEngaged) { $0.isLatchBouncePending = true }
    await store.send(.levelUpdated(1))
    await store.send(.recordingStarted(inputDeviceName: "Test Microphone")) {
      $0.presentation = .recording(
        PillFeature.State.Presentation.Recording(inputDeviceName: "Test Microphone", level: 0))
      $0.bounceCount = 1
      $0.isLatchBouncePending = false
    }
  }

  @Test func transcribingReplacesRecordingContent() async {
    var state = PillFeature.State()
    state.presentation = .recording(
      PillFeature.State.Presentation.Recording(inputDeviceName: "Studio Display", level: 0.4))
    let store = TestStore(initialState: state) { PillFeature() }

    await store.send(.transcribingStarted) { $0.presentation = .transcribing }
  }

  @Test func noSpeechNoticeFadesAndDismissesAfterItsDelay() async {
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
    await clock.advance(by: .milliseconds(1_500))
    await store.receive(.noticeDisplayElapsed(1)) { $0.isFadingOut = true }
    await clock.advance(by: .milliseconds(180))
    await store.receive(.noticeFadeElapsed(1)) {
      $0.presentation = nil
      $0.isFadingOut = false
    }
  }

  @Test func copiedNoticeLingersForThreeSeconds() async {
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
    await clock.advance(by: .milliseconds(2_999))
    await clock.advance(by: .milliseconds(1))
    await store.receive(.noticeDisplayElapsed(1)) { $0.isFadingOut = true }
    await clock.advance(by: .milliseconds(180))
    await store.receive(.noticeFadeElapsed(1)) {
      $0.presentation = nil
      $0.isFadingOut = false
    }
  }

  @Test func newerNoticeSupersedesAnEarlierDismissal() async {
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
    await clock.advance(by: .milliseconds(2_500))
    await store.receive(.noticeDisplayElapsed(2)) { $0.isFadingOut = true }
    await clock.advance(by: .milliseconds(180))
    await store.receive(.noticeFadeElapsed(2)) {
      $0.presentation = nil
      $0.isFadingOut = false
    }
  }

  @Test func cancelHidesImmediatelyAndCancelsNoticeTiming() async {
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

  @Test func successfulDismissalHidesImmediately() async {
    var state = PillFeature.State()
    state.presentation = .transcribing
    let store = TestStore(initialState: state) { PillFeature() }

    await store.send(.dismiss) { $0.presentation = nil }
  }
}
