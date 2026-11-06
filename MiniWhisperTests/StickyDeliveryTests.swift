import AppSettings
import ASREngine
import AudioCapture
import ComposableArchitecture
import FieldContext
import Foundation
import History
import HotkeyListener
@testable import MiniWhisper
import Sharing
import Testing

// MARK: - StickyDeliveryTests

/// A dictation delivers to the target it started in, and one target hears its dictations in the
/// order they were spoken.
@MainActor struct StickyDeliveryTests {
  @Test func `delivery reads and writes the target captured at the press`() async {
    let pressed = DeliveryTarget.inApp(TargetApp(bundleID: "com.example.Editor", name: "Editor"))
    let frontmostAtDelivery = DeliveryTarget.inApp(
      TargetApp(bundleID: "com.example.Browser", name: "Browser"),
    )
    let readFrom = TargetRecorder()
    let deliveredTo = TargetRecorder()
    var state = AppFeature.State()
    state.$settings.withLock { $0.retention.audio = .never }
    state.transcriptionGeneration = 1
    state.pendingDictation = dictation(1, text: "delivered text", target: nil)
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.date.now = Date(timeIntervalSince1970: 200)
      $0.uuid = .incrementing
      // Where the user is by the time the transcript arrives; nothing should ask.
      $0.deliveryTarget.capture = { frontmostAtDelivery }
      $0.contextCapture.capture = { target in
        await readFrom.record(target)
        return .unavailable(.noTextRange(role: "AXTextArea"))
      }
      $0.delivery.deliver = { _, target, _ in
        await deliveredTo.record(target)
        return .pasted(.restored)
      }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.targetCaptured(1, pressed))
    await store.send(.transcriptionCompleted(1, .transcript("delivered text")))
    await store.skipReceivedActions()
    await store.finish()

    #expect(await readFrom.targets == [pressed])
    #expect(await deliveredTo.targets == [pressed])
    #expect(store.state.history.entries.first?.targetApp?.bundleID == "com.example.Editor")
  }

  @Test func `a recording ended by the submit binding delivers with Return`() async {
    let submitted = StringRecorder()
    var settings = MiniWhisperSettings.defaults
    settings.retention.audio = .never
    settings.profiles.active = .custom
    var state = AppFeature.State(
      history: Shared(value: HistoryLog()), settings: Shared(value: settings),
    )
    state.onboardingCompleted = true
    state.$health.withLock { $0 = .healthy }
    state.transcriptionGeneration = 1
    state.dictationInFlight = true
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.date.now = Date(timeIntervalSince1970: 200)
      $0.uuid = .incrementing
      $0.continuousClock = TestClock()
      $0.asrEngine.submit = { _, _, _ in .transcript("Ship it") }
      $0.contextCapture
        .capture = { _ in .unavailable(.gridSemantics(bundleID: "com.mitchellh.ghostty")) }
      $0.delivery.deliver = { text, _, submits in
        await submitted.record("\(text) submits=\(submits)")
        return .pasted(.untouched)
      }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.targetCaptured(1, agentPane))
    await store.send(.hotkeyListenerEvent(.gesture(.stopAndSubmit)))
    await store.send(.recording(.delegate(.completed(CanonicalRecording(samples: [0.25])))))
    await store.skipReceivedActions()
    await store.finish()

    #expect(await submitted.values == ["Ship it submits=true"])
    #expect(!store.state.recordingSubmits)
  }

  @Test func `Return once the recording is over submits only where the dictation lands`() async {
    let submitted = StringRecorder()
    let owedCheck = TestBox<(@Sendable () -> Bool)?>(nil)
    let userIsAtPane = TestBox(true)
    var settings = MiniWhisperSettings.defaults
    settings.retention.audio = .never
    settings.profiles.active = .custom
    var state = AppFeature.State(
      history: Shared(value: HistoryLog()), settings: Shared(value: settings),
    )
    state.onboardingCompleted = true
    state.$health.withLock { $0 = .healthy }
    state.transcriptionGeneration = 1
    state.dictationInFlight = true
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.date.now = Date(timeIntervalSince1970: 200)
      $0.uuid = .incrementing
      $0.continuousClock = TestClock()
      $0.deliveryTarget.isCurrent = { $0 == agentPane && userIsAtPane.value }
      $0.hotkeyListener.armSubmitForDictation = { owedCheck.value = $0 }
      $0.asrEngine.submit = { _, _, _ in .transcript("Ship it") }
      $0.contextCapture
        .capture = { _ in .unavailable(.gridSemantics(bundleID: "com.mitchellh.ghostty")) }
      $0.delivery.deliver = { text, _, submits in
        await submitted.record("\(text) submits=\(submits)")
        return .pasted(.untouched)
      }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    // The release has stopped the capture; the recording has not handed over yet.
    await store.send(.targetCaptured(1, agentPane))
    let check = owedCheck.value
    #expect(check?() == true)
    userIsAtPane.value = false
    #expect(check?() == false)

    await store.send(.hotkeyListenerEvent(.gestureInput(.submitKey)))
    await store.receive(.hotkeyListenerEvent(.gesture(.submitDictation)))
    await store.send(.recording(.delegate(.completed(CanonicalRecording(samples: [0.25])))))
    await store.skipReceivedActions()
    await store.finish()

    #expect(await submitted.values == ["Ship it submits=true"])
    // Once the paste is under way, Return is the field's again.
    #expect(owedCheck.value == nil)
  }

  @Test func `a destination is named by its session, or by its window without the app twice`() {
    var browser = DeliveryTarget.inApp(TargetApp(bundleID: "com.google.Chrome", name: "Chrome"))
    browser.title = "Pull request #42 - Chrome"
    var pane = agentPane
    pane.title = "~/Develop"

    #expect(browser.destination == "Chrome · Pull request #42")
    #expect(pane.destination == "Ghostty · agents")
  }

  @Test func `a later dictation to the same pane waits for the earlier one`() async {
    let delivered = StringRecorder()
    let store = orderingStore(earlier: agentPane, later: agentPane, delivered: delivered)

    // The later dictation's cleanup answers first.
    await store.send(.cleanupResolved(2, .passedThrough))
    await store.finish()
    #expect(await delivered.values.isEmpty)

    await store.send(.cleanupResolved(1, .passedThrough))
    await store.finish()
    #expect(await delivered.values == ["first", "second"])
  }

  @Test func `a dictation to another pane does not wait`() async {
    let delivered = StringRecorder()
    let store = orderingStore(earlier: agentPane, later: otherPane, delivered: delivered)

    await store.send(.cleanupResolved(2, .passedThrough))
    await store.finish()

    #expect(await delivered.values == ["second"])
  }
}

private let agentPane = paneTarget("%3")
private let otherPane = paneTarget("%7")

private func paneTarget(_ paneID: String) -> DeliveryTarget {
  DeliveryTarget(
    app: TargetApp(bundleID: "com.mitchellh.ghostty", name: "Ghostty"), processID: 512,
    window: nil, element: nil,
    pane: TmuxPane(
      executable: "/opt/homebrew/bin/tmux", socket: "/private/tmp/tmux-501/swb", paneID: paneID,
      panePID: 900, session: "agents", command: "pi",
    ),
  )
}

private func dictation(
  _ generation: Int, text _: String, target: DeliveryTarget?,
) -> AppFeature.PendingDictation {
  var dictation = AppFeature.PendingDictation(
    generation: generation, recording: CanonicalRecording(samples: [0.25]),
    createdAt: Date(timeIntervalSince1970: 100), engine: "test-engine", original: nil,
  )
  dictation.target = target
  return dictation
}

/// Two dictations past transcription and field capture, both waiting on cleanup: the earlier one
/// in the background, the later one in the pill.
@MainActor private func orderingStore(
  earlier: DeliveryTarget, later: DeliveryTarget, delivered: StringRecorder,
) -> TestStoreOf<AppFeature> {
  func transcribed(_ generation: Int, _ text: String, _ target: DeliveryTarget) -> AppFeature
    .PendingDictation
  {
    var pending = dictation(generation, text: text, target: target)
    pending.original = History.Transcription(
      text: text, engine: "test-engine", transcribedAt: Date(timeIntervalSince1970: 150),
    )
    pending.capture = .unavailable(.gridSemantics(bundleID: "com.mitchellh.ghostty"))
    return pending
  }

  var state = AppFeature.State(history: Shared(value: HistoryLog()))
  state.$settings.withLock { $0.retention.audio = .never }
  state.transcriptionGeneration = 2
  state.dictationInFlight = true
  state.backgroundDictations[1] = transcribed(1, "first", earlier)
  state.pendingDictation = transcribed(2, "second", later)
  let store = TestStore(initialState: state) {
    AppFeature()
  } withDependencies: {
    $0.date.now = Date(timeIntervalSince1970: 200)
    $0.uuid = .incrementing
    $0.delivery.deliver = { text, _, _ in
      await delivered.record(text)
      return .pasted(.untouched)
    }
  }
  store.exhaustivity = .off(showSkippedAssertions: false)
  return store
}
