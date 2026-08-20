import AppSettings
import ASREngine
import AudioCapture
import ComposableArchitecture
import FieldContext
import Foundation
import History
@testable import MiniWhisper
import Sharing
import Testing
import TranscriptCleanup

// MARK: - CleanupPipelineTests

@MainActor struct CleanupPipelineTests {
  @Test func `the cleaned text is what delivers, and the entry records the pass`() async throws {
    let id = try #require(UUID(uuidString: "00000000-0000-0000-0000-0000000000C1"))
    let store = cleanupStore(cleanup: .configured) {
      $0.cleanup.clean = { request, configuration, apiKey in
        #expect(request.transcript == "dash dash help")
        #expect(request.targetBundleID == "com.mitchellh.ghostty")
        #expect(request.focusedTextContext?.before == "$ ")
        #expect(configuration.model == "gpt-oss-120b")
        #expect(apiKey == "sk-test")
        return .cleaned("--help")
      }
      $0.delivery.deliver = { text in
        #expect(text == "--help")
        return .pasted(.restored)
      }
      $0.uuid = .constant(id)
    }

    await store.send(.transcriptionCompleted(1, .transcript("dash dash help")))
    await store.receive(.contextCaptured(1, .available(fieldContext), ghostty))
    await store.receive(.pill(.polishingStarted(skipComponents: skipChord))) {
      $0.pill.presentation = .polishing(
        PillFeature.State.Presentation.Polishing(skipComponents: skipChord),
      )
    }
    await store.receive(
      .cleanupResolved(1, .attempted(configuration, .cleaned("--help", seconds: 0))),
    )
    await store.receive(
      .deliveryCompleted(
        1,
        AppFeature.DeliveryResult(
          text: "--help", targetApp: ghostty, outcome: .pasted(.restored),
        ),
      ),
    )
    await store.receive(.pill(.dismiss)) { $0.pill.presentation = nil }
    await store.finish()

    let entry = try #require(store.state.history.entries.first)
    #expect(entry.original?.text == "dash dash help")
    #expect(entry.delivery?.text == "--help")
    #expect(entry.fieldContext == fieldContext)
    #expect(
      entry.original?.cleanup
        == CleanupRecord(
          disposition: .cleaned("--help"), model: "gpt-oss-120b", endpoint: endpoint,
          durationSeconds: 0,
        ),
    )
  }

  @Test(arguments: [
    CleanupFailure.unreachable("connection refused"),
    .timedOut(10),
    .httpStatus(code: 503, message: "overloaded"),
    .degenerateResponse(.empty),
  ])
  func `a cleanup that cannot answer delivers the transcript as heard`(
    _ failure: CleanupFailure,
  ) async throws {
    let store = cleanupStore(cleanup: .configured) {
      $0.cleanup.clean = { _, _, _ in .failed(failure) }
      $0.delivery.deliver = { text in
        #expect(text == "dash dash help")
        return .pasted(.restored)
      }
    }

    await store.send(.transcriptionCompleted(1, .transcript("dash dash help")))
    await store.receive(.contextCaptured(1, .available(fieldContext), ghostty))
    await store.receive(.pill(.polishingStarted(skipComponents: skipChord))) {
      $0.pill.presentation = .polishing(
        PillFeature.State.Presentation.Polishing(skipComponents: skipChord),
      )
    }
    await store.receive(
      .cleanupResolved(
        1, .attempted(configuration, .failed(reason: failure.historyDetail, seconds: 0)),
      ),
    )
    await store.receive(
      .deliveryCompleted(
        1,
        AppFeature.DeliveryResult(
          text: "dash dash help", targetApp: ghostty, outcome: .pasted(.restored),
        ),
      ),
    )
    await store.receive(.pill(.cleanupUnavailable)) {
      $0.pill.noticeGeneration = 1
      $0.pill.presentation = .notice(.cleanupUnavailable)
    }
    await store.finish()

    let entry = try #require(store.state.history.entries.first)
    #expect(entry.delivery?.text == "dash dash help")
    #expect(entry.original?.cleanup?.disposition == .failed(failure.historyDetail))
  }

  /// The pill says what it can promise: delivery happened, the polish did not.
  @Test func `the failure notice is subdued, like the other degraded successes`() {
    let content = PillFeature.State.Presentation.Notice.cleanupUnavailable.content
    #expect(content.text == "Cleanup unavailable — pasted as heard")
    #expect(content.isSubdued)
    #expect(
      content.duration
        == PillFeature.State.Presentation.Notice.fieldContextUnavailable.content.duration,
    )
  }

  @Test func `an unreadable keychain is a cleanup failure, not a dead dictation`() async throws {
    let store = cleanupStore(cleanup: .configured) {
      $0.keychain.read = { _ in throw KeychainError(operation: .read, status: -25300) }
      $0.cleanup.clean = { _, _, _ in
        Issue.record("A key that cannot be read must never reach the endpoint")
        return .cancelled
      }
      $0.delivery.deliver = { text in
        #expect(text == "dash dash help")
        return .pasted(.restored)
      }
    }

    await store.send(.transcriptionCompleted(1, .transcript("dash dash help")))
    await store.receive(.contextCaptured(1, .available(fieldContext), ghostty))
    await store.receive(
      .cleanupResolved(
        1, .attempted(configuration, .failed(reason: "keyUnreadable", seconds: 0)),
      ),
    )
    await store.skipReceivedActions()
    await store.finish()

    let entry = try #require(store.state.history.entries.first)
    #expect(entry.original?.cleanup?.disposition == .failed("keyUnreadable"))
  }

  @Test(arguments: [CleanupConfigurationCase.disabled, .unconfigured, .keyless])
  func `cleanup that cannot run is a pass-through, not a phase`(
    _ configuration: CleanupConfigurationCase,
  ) async throws {
    let store = cleanupStore(cleanup: configuration) {
      $0.cleanup.clean = { _, _, _ in
        Issue.record("An incomplete cleanup configuration must never send a request")
        return .cancelled
      }
      $0.delivery.deliver = { text in
        #expect(text == "dash dash help")
        return .pasted(.restored)
      }
    }

    await store.send(.transcriptionCompleted(1, .transcript("dash dash help")))
    await store.receive(.contextCaptured(1, .available(fieldContext), ghostty))
    await store.receive(.cleanupResolved(1, .passedThrough))
    await store.receive(
      .deliveryCompleted(
        1,
        AppFeature.DeliveryResult(
          text: "dash dash help", targetApp: ghostty, outcome: .pasted(.restored),
        ),
      ),
    )
    await store.receive(.pill(.dismiss)) { $0.pill.presentation = nil }
    await store.finish()

    #expect(store.state.pill.presentation == nil)
    let entry = try #require(store.state.history.entries.first)
    #expect(entry.original?.cleanup == nil)
  }

  /// Paste-last and Copy Last Transcript recover what was delivered, and after a cleaned
  /// dictation that is the rewrite — the transcript as heard is history's business, not theirs.
  @Test func `paste last recovers the cleaned text the dictation delivered`() async {
    let delivered = DeliveredTexts()
    let store = cleanupStore(cleanup: .configured) {
      $0.cleanup.clean = { _, _, _ in .cleaned("--help") }
      $0.delivery.deliver = { text in
        await delivered.record(text)
        return .pasted(.restored)
      }
    }

    await store.send(.transcriptionCompleted(1, .transcript("dash dash help")))
    await store.skipReceivedActions()
    await store.finish()
    #expect(store.state.lastTranscript == "--help")

    await store.send(.pasteLastTranscript)
    await store.skipReceivedActions()
    await store.finish()

    #expect(await delivered.texts == ["--help", "--help"])
    #expect(store.state.history.entries.count == 1)
  }

  @Test func `a resolution from a superseded dictation delivers nothing`() async {
    let store = cleanupStore(cleanup: .configured) {
      $0.delivery.deliver = { _ in
        Issue.record("A superseded dictation must not deliver into the new one's field")
        return .pasted(.restored)
      }
    }

    await store.send(
      .cleanupResolved(0, .attempted(configuration, .cleaned("--help", seconds: 1))),
    )
    await store.finish()
    #expect(store.state.history.entries.isEmpty)
  }
}

// MARK: - DeliveredTexts

private actor DeliveredTexts {
  private(set) var texts: [String] = []

  func record(_ text: String) {
    texts.append(text)
  }
}

// MARK: - CleanupConfigurationCase

/// The three ways a cleanup pass has nothing to run: the toggle is off, the pane was never
/// finished, and the key is absent from the Keychain.
enum CleanupConfigurationCase {
  case configured
  case disabled
  case unconfigured
  case keyless
}

private let endpoint = URL(string: "https://gateway.example/v1")!
/// What `.configured` settings resolve to, and so what every resolution they produce carries.
private let configuration = CleanupConfiguration(
  endpoint: endpoint, model: "gpt-oss-120b", timeout: 10, additionalInstructions: "",
)
/// The default activation binding, which is what the skip chip has to speak.
private let skipChord = ["⌥ Opt →"]
private let ghostty = TargetApp(bundleID: "com.mitchellh.ghostty", name: "Ghostty")
private let fieldContext = FocusedTextContext(
  role: "AXTextArea", before: "$ ", selected: "", after: "", selectedRange: 2 ..< 2,
  beforeWasTruncated: false, selectionWasTruncated: false, afterWasTruncated: false,
)

@MainActor private func cleanupStore(
  cleanup configurationCase: CleanupConfigurationCase,
  _ dependencies: (inout DependencyValues) -> Void,
) -> TestStoreOf<AppFeature> {
  var settings = MiniWhisperSettings.defaults
  settings.retention.audio = .never
  settings.cleanup = CleanupSettings(
    enabled: configurationCase != .disabled,
    endpoint: configurationCase == .unconfigured ? nil : endpoint,
    model: configurationCase == .unconfigured ? nil : "gpt-oss-120b",
    timeout: 10, additionalInstructions: "",
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
    $0.contextCapture.capture = { _ in .available(fieldContext) }
    $0.continuousClock = TestClock()
    $0.date.now = Date(timeIntervalSince1970: 200)
    $0.uuid = .incrementing
    $0.keychain.read = { _ in configurationCase == .keyless ? nil : "sk-test" }
    $0.workspace.frontmostApplication = {
      WorkspaceApplication(bundleID: ghostty.bundleID, name: ghostty.name)
    }
    dependencies(&$0)
  }
  store.exhaustivity = .off(showSkippedAssertions: false)
  return store
}
