import ComposableArchitecture
import History
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

    await store.send(.transcribingStarted(target: nil)) { $0.presentation = .transcribing }
  }

  @Test(arguments: [
    (PillFeature.Action.noSpeechDetected, PillFeature.State.Presentation.Notice.noSpeechDetected),
    (.noTranscriptToPaste, .noTranscriptToPaste),
    (.cleanupUnavailable, .cleanupUnavailable),
  ])
  func `explanatory notices remain readable before fading`(
    action: PillFeature.Action, notice: PillFeature.State.Presentation.Notice,
  ) async {
    let clock = TestClock()
    let store = TestStore(initialState: PillFeature.State()) {
      PillFeature()
    } withDependencies: {
      $0.continuousClock = clock
    }

    await store.send(action) {
      $0.noticeGeneration = 1
      $0.presentation = .notice(notice)
    }
    await clock.advance(by: .seconds(2))
    await store.send(.destinationUpdated(nil))
    #expect(!store.state.isFadingOut)
    await clock.advance(by: .seconds(1))
    await store.receive(.noticeDisplayElapsed(1)) { $0.isFadingOut = true }
    await clock.advance(by: .milliseconds(180))
    await store.receive(.noticeFadeElapsed(1)) {
      $0.presentation = nil
      $0.isFadingOut = false
    }
  }

  @Test func `no transcript notice uses the recovery message`() async {
    let store = TestStore(initialState: PillFeature.State()) {
      PillFeature()
    } withDependencies: {
      $0.continuousClock = TestClock()
    }

    await store.send(.noTranscriptToPaste) {
      $0.noticeGeneration = 1
      $0.presentation = .notice(.noTranscriptToPaste)
    }
    #expect(
      store.state.presentation
        == .notice(.noTranscriptToPaste),
    )
    #expect(
      PillFeature.State.Presentation.Notice.noTranscriptToPaste.content.text
        == "No transcript to paste yet",
    )
    await store.send(.dismiss) { $0.presentation = nil }
  }

  @Test func `withheld placement failure names recovery`() async {
    let store = TestStore(initialState: PillFeature.State()) {
      PillFeature()
    } withDependencies: {
      $0.continuousClock = TestClock()
    }

    await store.send(.noReceiver(pasteShortcut: "⌥⌘V")) {
      $0.noticeGeneration = 1
      $0.presentation = .notice(.noReceiver(pasteShortcut: "⌥⌘V"))
    }
    let bound = PillFeature.State.Presentation.Notice.noReceiver(pasteShortcut: "⌥⌘V").content
    #expect(bound.text == "Copied — ⌘V to paste")
    #expect(bound.phase == "Nowhere to paste")
    #expect(
      PillFeature.State.Presentation.Notice.noReceiver(pasteShortcut: nil).content.text
        == "Copied — ⌘V to paste",
    )
    await store.send(.dismiss) { $0.presentation = nil }
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

  @Test func `the skip affordance stays hidden until the wait is worth naming`() async {
    let clock = TestClock()
    var state = PillFeature.State()
    state.presentation = .transcribing
    let store = TestStore(initialState: state) { PillFeature() } withDependencies: {
      $0.continuousClock = clock
    }

    await store.send(.polishingStarted(skipComponents: ["⌥ Opt →"])) {
      $0.presentation = .polishing(
        PillFeature.State.Presentation.Polishing(skipComponents: ["⌥ Opt →"]),
      )
    }
    await clock.advance(by: .milliseconds(2999))
    await clock.advance(by: .milliseconds(1))
    await store.receive(.skipAffordanceRevealed) {
      $0.presentation = .polishing(
        PillFeature.State.Presentation.Polishing(
          skipComponents: ["⌥ Opt →"], isSkipRevealed: true,
        ),
      )
    }
  }

  @Test func `a cleanup that finishes first takes its reveal with it`() async {
    let clock = TestClock()
    let store = TestStore(initialState: PillFeature.State()) { PillFeature() } withDependencies: {
      $0.continuousClock = clock
    }

    await store.send(.polishingStarted(skipComponents: ["⌥ Opt →"])) {
      $0.presentation = .polishing(
        PillFeature.State.Presentation.Polishing(skipComponents: ["⌥ Opt →"]),
      )
    }
    await store.send(.dismiss) { $0.presentation = nil }
    await clock.advance(by: .seconds(5))
  }

  /// A binding the user has removed leaves nothing to press, so the chip has nothing to say.
  @Test func `an unbound activation reveals no chip`() async {
    let clock = TestClock()
    let store = TestStore(initialState: PillFeature.State()) { PillFeature() } withDependencies: {
      $0.continuousClock = clock
    }

    await store.send(.polishingStarted(skipComponents: [])) {
      $0.presentation = .polishing(PillFeature.State.Presentation.Polishing(skipComponents: []))
    }
    await clock.advance(by: .seconds(3))
    await store.receive(.skipAffordanceRevealed)
  }

  @Test func `successful dismissal hides immediately`() async {
    var state = PillFeature.State()
    state.presentation = .transcribing
    let store = TestStore(initialState: state) { PillFeature() }

    await store.send(.dismiss) { $0.presentation = nil }
  }

  /// Staying in the field is the ordinary case and changes nothing; the destination appears only
  /// once the user has gone elsewhere, and follows the dictation from engine to cleanup.
  @Test func `the destination is named only while the user is away from it`() async {
    let clock = TestClock()
    let isAtTarget = TestBox(true)
    var target = DeliveryTarget.inApp(TargetApp(bundleID: "com.google.Chrome", name: "Chrome"))
    target.title = "Pull request #42"
    let store = TestStore(initialState: PillFeature.State()) { PillFeature() } withDependencies: {
      $0.continuousClock = clock
      $0.deliveryTarget.isCurrent = { _ in isAtTarget.value }
    }

    await store.send(.transcribingStarted(target: target)) { $0.presentation = .transcribing }
    isAtTarget.value = false
    await clock.advance(by: .milliseconds(500))
    await store.receive(.destinationUpdated("Chrome · Pull request #42")) {
      $0.destination = "Chrome · Pull request #42"
    }
    await store.send(.polishingStarted(skipComponents: [])) {
      $0.presentation = .polishing(PillFeature.State.Presentation.Polishing(skipComponents: []))
    }
    isAtTarget.value = true
    await clock.advance(by: .milliseconds(500))
    await store.receive(.destinationUpdated(nil)) { $0.destination = nil }
    await store.send(.dismiss) { $0.presentation = nil }
    await clock.advance(by: .seconds(5))
  }
}
