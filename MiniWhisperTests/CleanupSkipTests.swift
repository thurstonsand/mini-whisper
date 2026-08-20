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
import TranscriptCleanup

// MARK: - CleanupSkipTests

/// The interruption grammar: one rule, that any activation press resolves a pending cleanup as a
/// skip, plus Escape keeping the meaning it has everywhere else.
@MainActor struct CleanupSkipTests {
  @Test func `a hold while polishing delivers as heard and starts the next recording`(
  ) async throws {
    let delivered = StringRecorder()
    let store = skipStore {
      $0.delivery.deliver = { text in
        await delivered.record(text)
        return .pasted(.restored)
      }
    }

    await store.send(.hotkeyListenerEvent(.gestureInput(.activation(at: .zero))))
    await store.receive(.hotkeyListenerEvent(.gesture(.skipCleanupAndRecord)))
    await store.skipReceivedActions()
    await store.skipInFlightEffects()

    // An empty field is the start of a sentence, so the join capitalises what it pastes.
    #expect(await delivered.values == ["Deliver me as heard"])
    #expect(store.state.gestureMachine.phase == .holding(startedAt: .zero))
    #expect(store.state.transcriptionGeneration == 2)
    #expect(store.state.dictationInFlight)
    #expect(store.state.recording.phase != .idle)
    let entry = try #require(store.state.history.entries.first)
    #expect(entry.delivery?.text == "Deliver me as heard")
    #expect(entry.original?.cleanup?.disposition == .skipped)
    #expect(entry.original?.cleanup?.model == "gpt-oss-120b")
  }

  @Test func `a tap while polishing skips without leaving a recording behind`() async throws {
    let delivered = StringRecorder()
    let clock = TestClock()
    let store = skipStore {
      $0.continuousClock = clock
      $0.delivery.deliver = { text in
        await delivered.record(text)
        return .pasted(.restored)
      }
    }

    await store.send(.hotkeyListenerEvent(.gestureInput(.activation(at: .zero))))
    await store.send(
      .hotkeyListenerEvent(.gestureInput(.release(at: .milliseconds(80)))),
    )
    await clock.advance(by: .milliseconds(300))
    await store.skipReceivedActions()
    await store.skipInFlightEffects()

    // The press started a recording, as every press does; the tap is what discards it.
    #expect(store.state.gestureMachine.phase == .idle)
    #expect(store.state.recording.phase == .idle)
    #expect(!store.state.dictationInFlight)
    #expect(await delivered.values == ["Deliver me as heard"])
    let entry = try #require(store.state.history.entries.first)
    #expect(entry.original?.cleanup?.disposition == .skipped)
  }

  @Test func `escape while polishing archives the transcript and delivers nothing`() async throws {
    let store = skipStore {
      $0.delivery.deliver = { _ in
        Issue.record("Escape revokes delivery, during cleanup as everywhere else")
        return .pasted(.restored)
      }
    }

    await store.send(.hotkeyListenerEvent(.gestureInput(.escape)))
    await store.receive(.hotkeyListenerEvent(.gesture(.cancelAndArchive)))
    await store.receive(.pill(.cancelledSavedToHistory)) {
      $0.pill.noticeGeneration = 1
      $0.pill.presentation = .notice(.cancelledSavedToHistory)
    }
    await store.skipReceivedActions()
    await store.finish()

    #expect(store.state.pendingDictation == nil)
    let entry = try #require(store.state.history.entries.first)
    #expect(entry.delivery == nil)
    #expect(entry.original?.text == "deliver me as heard")
    // Escape resolved the wait rather than failing it; nothing about the endpoint went wrong.
    #expect(entry.original?.cleanup?.disposition == .skipped)
  }

  /// Two tails in flight at once used to share one slot in state, which meant the second one's
  /// entry could be archived with the first one's delivery. Each now carries its own.
  @Test func `two skipped tails finish as themselves`() async {
    let store = skipStore(
      skippedTails: [7: skippedTail("first"), 8: skippedTail("second")],
    ) { $0.uuid = .incrementing }

    await store.send(.skippedDeliveryCompleted(7, pasted("first")))
    await store.send(.skippedDeliveryCompleted(8, pasted("second")))
    await store.skipReceivedActions()
    await store.finish()

    let texts = store.state.history.entries.compactMap(\.original?.text)
    #expect(Set(texts) == ["first", "second"])
    for entry in store.state.history.entries {
      #expect(entry.delivery?.text == entry.original?.text)
      #expect(entry.original?.cleanup?.disposition == .skipped)
    }
  }

  @Test func `a cleanup that answers after the skip cannot deliver twice`() async {
    let deliveries = PrewarmCounter()
    let store = skipStore {
      $0.delivery.deliver = { _ in
        await deliveries.record()
        return .pasted(.restored)
      }
    }

    await store.send(.hotkeyListenerEvent(.gestureInput(.activation(at: .zero))))
    await store.skipReceivedActions()
    // The endpoint's answer arrives late, for a dictation nothing is waiting on any more.
    await store.send(
      .cleanupResolved(
        1, .attempted(skipConfiguration, .cleaned("Deliver me as heard.", seconds: 2)),
      ),
    )
    await store.skipInFlightEffects()

    #expect(await deliveries.count == 1)
  }
}

private let skipConfiguration = CleanupConfiguration(
  endpoint: URL(string: "https://gateway.example/v1")!, model: "gpt-oss-120b", timeout: 10,
  additionalInstructions: "",
)

private func skippedTail(_ text: String) -> AppFeature.PendingDictation {
  var dictation = AppFeature.PendingDictation(
    generation: 1, recording: CanonicalRecording(samples: [0.25]),
    createdAt: Date(timeIntervalSince1970: 100), engine: "test-engine@revision",
    original: History.Transcription(
      text: text, engine: "test-engine@revision", transcribedAt: Date(timeIntervalSince1970: 150),
    ),
  )
  dictation.capture = .unavailable(.noFocusedElement)
  dictation.cleanup = skipConfiguration
  dictation.cleanupRecord = CleanupRecord(.attempted(skipConfiguration, .skipped(seconds: 2)))
  return dictation
}

private func pasted(_ text: String) -> AppFeature.DeliveryResult {
  AppFeature.DeliveryResult(text: text, targetApp: nil, outcome: .pasted(.restored))
}

@MainActor private func skipStore(
  skippedTails: [Int: AppFeature.PendingDictation] = [:],
  _ dependencies: (inout DependencyValues) -> Void,
) -> TestStoreOf<AppFeature> {
  var settings = MiniWhisperSettings.defaults
  settings.retention.audio = .never
  settings.cleanup = CleanupSettings(
    enabled: true, endpoint: URL(string: "https://gateway.example/v1")!, model: "gpt-oss-120b",
    timeout: 10, additionalInstructions: "",
  )
  let captureSessionID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
  // A capture that stays open: a stream that ends is a microphone failure, and the next dictation
  // is supposed to still be recording when these tests look at it.
  let (captureEvents, captureContinuation) = AsyncStream.makeStream(of: AudioCaptureEvent.self)
  let capture = ContextCapture.available(
    FocusedTextContext(
      role: "AXTextArea", before: "", selected: "", after: "", selectedRange: 0 ..< 0,
      beforeWasTruncated: false, selectionWasTruncated: false, afterWasTruncated: false,
    ),
  )
  var state = AppFeature.State(
    history: Shared(value: HistoryLog()), settings: Shared(value: settings),
  )
  state.onboardingCompleted = true
  state.$health.withLock { $0 = .healthy }
  state.transcriptionGeneration = 1
  state.dictationInFlight = true
  state.skippedDictations = skippedTails
  state.pill.presentation = .polishing(
    PillFeature.State.Presentation.Polishing(skipComponents: ["⌥ Opt →"]),
  )
  // The dictation exactly as the cleanup effect left it: transcribed, captured, and waiting on a
  // request that has already gone out.
  var pending = AppFeature.PendingDictation(
    generation: 1, recording: CanonicalRecording(samples: [0.25]),
    createdAt: Date(timeIntervalSince1970: 100), engine: "test-engine@revision",
    original: History.Transcription(
      text: "deliver me as heard", engine: "test-engine@revision",
      transcribedAt: Date(timeIntervalSince1970: 150),
    ),
  )
  pending.capture = capture
  pending.cleanup = settings.cleanup.configuration
  pending.cleanupStartedAt = Date(timeIntervalSince1970: 198)
  state.pendingDictation = pending
  // The machine is waiting on the endpoint, exactly as the cleanup effect left it.
  _ = state.gestureMachine.receive(.cleanupStarted)
  let store = TestStore(initialState: state) {
    AppFeature()
  } withDependencies: {
    $0.audioCapture.currentInputDeviceName = { _ in "Test Microphone" }
    $0.audioCapture.start = { _ in
      captureContinuation.yield(.captureBecameLive)
      return AudioCaptureSession(
        id: captureSessionID, inputDeviceName: "Test Microphone", events: captureEvents,
      )
    }
    $0.audioCapture.cancel = { _ in }
    $0.audioCapture.stop = { _ in CanonicalRecording(samples: [0.1]) }
    $0.asrEngine.prepareForActivation = { AsyncStream { $0.finish() } }
    $0.contextCapture.capture = { _ in .unavailable(.noFocusedElement) }
    $0.contextCapture.prewarmFrontmostApp = {}
    $0.continuousClock = TestClock()
    $0.date.now = Date(timeIntervalSince1970: 200)
    $0.uuid = .incrementing
    dependencies(&$0)
  }
  store.exhaustivity = .off(showSkippedAssertions: false)
  return store
}
