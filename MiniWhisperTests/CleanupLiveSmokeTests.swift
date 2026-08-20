import AppSettings
import ASREngine
import AudioCapture
import CleanupTestSupport
import ComposableArchitecture
import FieldContext
import Foundation
import History
import HotkeyListener
@testable import MiniWhisper
import Sharing
import SpeechDictionary
import Testing
import TranscriptCleanup

// MARK: - CleanupLiveSmokeTests

/// The pipeline against a real socket, with the real client, the real request, and the real
/// response shaping — everything a dictation does except the microphone and the paste. The
/// reducer tests prove the decisions; this proves the wire.
@MainActor struct CleanupLiveSmokeTests {
  @Test func `a live endpoint's cleaned text is what delivers`() async throws {
    let endpoint = MockEndpoint.start()
    defer { endpoint.stop() }
    let delivered = StringRecorder()
    let store = smokeStore(endpoint: endpoint.baseURL, timeout: 5) {
      $0.delivery.deliver = { text in
        await delivered.record(text)
        return .pasted(.restored)
      }
    }

    await store.send(
      .transcriptionCompleted(
        1, .transcript("um so run swift test dash dash filter cleanup comma then uh report back"),
      ),
    )
    await store.receive(
      .cleanupResolved(
        1,
        .attempted(
          smokeConfiguration(endpoint.baseURL, timeout: 5),
          .cleaned("Run swift test --filter cleanup, then report back.", seconds: 0),
        ),
      ),
      timeout: .seconds(10),
    )
    await store.receive(.pill(.dismiss), timeout: .seconds(5))
    await store.skipReceivedActions()
    await store.finish()

    let text = try #require(await delivered.values.first)
    let entry = try #require(store.state.history.entries.first)
    // The join rules run on the cleaned text: the caret sits after a shell prompt, so the
    // sentence case the model returned is lowered back down.
    #expect(text == "run swift test --filter cleanup, then report back.")
    #expect(
      entry.original?.cleanup?
        .disposition == .cleaned("Run swift test --filter cleanup, then report back."),
    )
    #expect(entry.original?.text != text)
    #expect(store.state.pill.presentation == nil)
  }

  @Test func `a dead endpoint delivers the transcript as heard and says so`() async throws {
    // Bound, then closed: nothing is listening, which is what an outage looks like from here.
    let endpoint = MockEndpoint.start()
    let deadURL = endpoint.baseURL
    endpoint.stop()
    let delivered = StringRecorder()
    let store = smokeStore(endpoint: deadURL, timeout: 5) {
      $0.delivery.deliver = { text in
        await delivered.record(text)
        return .pasted(.restored)
      }
    }

    await store.send(.transcriptionCompleted(1, .transcript("deliver me as heard")))
    await store.receive(
      .cleanupResolved(
        1,
        .attempted(
          smokeConfiguration(deadURL, timeout: 5), .failed(reason: "unreachable", seconds: 0),
        ),
      ),
      timeout: .seconds(10),
    )
    await store.receive(.pill(.cleanupUnavailable), timeout: .seconds(5))
    await store.skipReceivedActions()
    await store.finish()

    let text = try #require(await delivered.values.first)
    let entry = try #require(store.state.history.entries.first)
    #expect(text == "deliver me as heard")
    #expect(entry.original?.cleanup?.disposition == .failed("unreachable"))
    #expect(store.state.pill.presentation == .notice(.cleanupUnavailable))
  }

  @Test func `a press against an endpoint that never answers delivers as heard`() async throws {
    let endpoint = MockEndpoint.start()
    defer { endpoint.stop() }
    let delivered = StringRecorder()
    // A timeout far past the test: what ends this wait is the user, not the backstop.
    let store = smokeStore(endpoint: endpoint.slowBaseURL, timeout: 60) {
      $0.delivery.deliver = { text in
        await delivered.record(text)
        return .pasted(.restored)
      }
    }

    await store.send(.transcriptionCompleted(1, .transcript("deliver me as heard")))
    await store.receive(
      .hotkeyListenerEvent(.gestureInput(.cleanupStarted)), timeout: .seconds(5),
    )
    #expect(store.state.gestureMachine.phase == .cleanupPending)

    await store.send(.hotkeyListenerEvent(.gestureInput(.activation(at: .zero))))
    // The skipped tail answers to nothing in the store, so it is followed by what it leaves
    // behind: the paste, then the entry.
    await store.settleSkippedTail()

    #expect(await delivered.values == ["deliver me as heard"])
    let entry = try #require(store.state.history.entries.first)
    #expect(entry.original?.cleanup?.disposition == .skipped)
  }

  /// The other half of the pipeline's promise: a re-run reaches the same socket with the same
  /// request and comes back with a record of its own, on the transcription it polished.
  @Test func `a re-transcription is polished by the same pass a dictation gets`() async throws {
    let endpoint = MockEndpoint.start()
    defer { endpoint.stop() }
    let id = try #require(UUID(uuidString: "00000000-0000-0000-0000-0000000000A9"))
    let entry = HistoryEntry(
      id: id, createdAt: Date(timeIntervalSince1970: 100),
      targetApp: TargetApp(bundleID: "com.apple.Terminal", name: "Terminal"),
      original: History.Transcription(
        text: "an older opinion", engine: "test-engine",
        transcribedAt: Date(timeIntervalSince1970: 100),
      ),
      fieldContext: smokeContext,
      delivery: nil, audio: AudioMetadata(durationSeconds: 1, byteCount: 64044),
    )
    var settings = MiniWhisperSettings.defaults
    settings.cleanup = CleanupSettings(
      enabled: true, endpoint: endpoint.baseURL, model: "mock-small", timeout: 10,
      additionalInstructions: "",
    )
    let state = HistoryFeature.State(
      log: Shared(value: HistoryLog(entries: [entry])), retention: Shared(value: .defaults),
      dictionary: Shared(value: .empty), improveRecognition: Shared(value: true),
      cleanup: Shared(value: settings.cleanup),
    )
    let store = TestStore(initialState: state) { HistoryFeature() } withDependencies: {
      $0.cleanup = .liveValue
      $0.date.now = Date(timeIntervalSince1970: 300)
      $0.historyClient.loadAudio = { _ in CanonicalRecording(samples: [0.25]) }
      $0.asrEngine.identity = { "test-engine@rerun" }
      $0.asrEngine.submit = { _, _ in
        .transcript("um so run swift test dash dash filter cleanup comma then uh report back")
      }
      $0.keychain.read = { _ in "sk-smoke" }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.retranscribeTapped(id))
    for _ in 0 ..< 20 where store.state.log.entries[0].retranscriptions.isEmpty {
      await store.skipReceivedActions(strict: false)
      await Task.yield()
    }
    await store.skipInFlightEffects(strict: false)

    let rerun = try #require(store.state.log.entries[0].currentTranscription)
    #expect(rerun.engine == "test-engine@rerun")
    #expect(
      rerun.cleanup?.disposition == .cleaned("Run swift test --filter cleanup, then report back."),
    )
    #expect(rerun.cleanup?.model == "mock-small")
    #expect(store.state.log.entries[0].original?.text == "an older opinion")
    #expect(
      store.state.log.entries[0].displayText
        == "Run swift test --filter cleanup, then report back.",
    )
  }

  @Test func `escape against an endpoint that never answers delivers nothing`() async throws {
    let endpoint = MockEndpoint.start()
    defer { endpoint.stop() }
    let store = smokeStore(endpoint: endpoint.slowBaseURL, timeout: 60) {
      $0.delivery.deliver = { _ in
        Issue.record("Escape revokes delivery, during cleanup as everywhere else")
        return .pasted(.restored)
      }
    }

    await store.send(.transcriptionCompleted(1, .transcript("never deliver me")))
    await store.receive(
      .hotkeyListenerEvent(.gestureInput(.cleanupStarted)), timeout: .seconds(5),
    )

    await store.send(.hotkeyListenerEvent(.gestureInput(.escape)))
    await store.receive(.pill(.cancelledSavedToHistory), timeout: .seconds(5))
    await store.settleSkippedTail()

    let entry = try #require(store.state.history.entries.first)
    #expect(entry.delivery == nil)
    #expect(entry.original?.text == "never deliver me")
    #expect(entry.original?.cleanup?.disposition == .skipped)
  }
}

private extension TestStoreOf<AppFeature> {
  /// Drains the actions a detached tail produces — delivery, then archive — which arrive off the
  /// generation the store is still answering for.
  @MainActor func settleSkippedTail() async {
    for _ in 0 ..< 8 where state.history.entries.isEmpty {
      await skipReceivedActions(strict: false)
      await Task.yield()
    }
    await skipInFlightEffects(strict: false)
  }
}

/// What the smoke settings resolve to, and so what every resolution they produce carries.
private func smokeConfiguration(_ endpoint: URL, timeout: TimeInterval) -> CleanupConfiguration {
  CleanupConfiguration(
    endpoint: endpoint, model: "mock-small", timeout: timeout, additionalInstructions: "",
  )
}

private let smokeContext = FocusedTextContext(
  role: "AXTextArea", before: "$ ", selected: "", after: "", selectedRange: 2 ..< 2,
  beforeWasTruncated: false, selectionWasTruncated: false, afterWasTruncated: false,
)

@MainActor private func smokeStore(
  endpoint: URL, timeout: TimeInterval, _ dependencies: (inout DependencyValues) -> Void,
) -> TestStoreOf<AppFeature> {
  var settings = MiniWhisperSettings.defaults
  settings.retention.audio = .never
  settings.cleanup = CleanupSettings(
    enabled: true, endpoint: endpoint, model: "mock-small", timeout: timeout,
    additionalInstructions: "",
  )
  var state = AppFeature.State(
    history: Shared(value: HistoryLog()), settings: Shared(value: settings),
  )
  state.transcriptionGeneration = 1
  state.pill.presentation = .transcribing
  state.pendingDictation = AppFeature.PendingDictation(
    generation: 1, recording: CanonicalRecording(samples: [0.25]),
    createdAt: Date(timeIntervalSince1970: 100), engine: "test-engine@revision", original: nil,
  )
  let store = TestStore(initialState: state) {
    AppFeature()
  } withDependencies: {
    $0.cleanup = .liveValue
    $0.contextCapture.capture = { _ in
      .available(
        FocusedTextContext(
          role: "AXTextArea", before: "$ ", selected: "", after: "", selectedRange: 2 ..< 2,
          beforeWasTruncated: false, selectionWasTruncated: false, afterWasTruncated: false,
        ),
      )
    }
    $0.continuousClock = TestClock()
    $0.date.now = Date(timeIntervalSince1970: 200)
    $0.keychain.read = { _ in "sk-smoke" }
    $0.uuid = .incrementing
    $0.workspace.frontmostApplication = {
      WorkspaceApplication(bundleID: "com.apple.Terminal", name: "Terminal")
    }
    dependencies(&$0)
  }
  store.exhaustivity = .off(showSkippedAssertions: false)
  return store
}
