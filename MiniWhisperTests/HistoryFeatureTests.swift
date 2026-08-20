import AppSettings
import ASREngine
import AudioCapture
import ComposableArchitecture
import FieldContext
import Foundation
import History
import HotkeyListener
@testable import MiniWhisper
import SpeechDictionary
import Testing
import TranscriptCleanup

// MARK: - HistoryFeatureTests

@MainActor struct HistoryFeatureTests {
  @Test func `the copy confirmation clears itself and keeps the cursor`() async {
    let clock = TestClock()
    let entry = makeEntry()
    var state = makeState([entry])
    state.cursor = entry.id
    let store = TestStore(initialState: state) { HistoryFeature() } withDependencies: {
      $0.continuousClock = clock
      $0.delivery.copy = { _ in }
    }

    await store.send(.copyRequested) {
      $0.copiedEntryID = entry.id
    }
    await clock.advance(by: .seconds(1.2))
    await store.receive(.copyFinished(entry.id)) {
      $0.copiedEntryID = nil
    }
    #expect(store.state.cursor == entry.id)
  }

  @Test func `j after copy advances from the retained cursor`() async throws {
    let clock = TestClock()
    let first = makeEntry()
    let secondID = try #require(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"))
    let second = makeEntry(id: secondID)
    var state = makeState([first, second])
    state.cursor = first.id
    let store = TestStore(initialState: state) { HistoryFeature() } withDependencies: {
      $0.continuousClock = clock
      $0.delivery.copy = { _ in }
    }

    await store.send(.copyRequested) {
      $0.copiedEntryID = first.id
    }
    await store.send(.cursorMoved(.next)) {
      $0.cursor = second.id
    }
    await clock.advance(by: .seconds(1.2))
    await store.receive(.copyFinished(first.id)) {
      $0.copiedEntryID = nil
    }
  }

  @Test func `an unmoved cursor is the first row, so entering the column lands somewhere`(
  ) async throws {
    let first = makeEntry()
    let secondID = try #require(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"))
    let second = makeEntry(id: secondID)
    var state = makeWindowState([first, second])
    state.interaction.focus = .detail
    state.interaction.mode = .keyboard
    let clock = TestClock()
    let store = TestStore(initialState: state) { SettingsWindowFeature() } withDependencies: {
      $0.continuousClock = clock
      $0.delivery.copy = { _ in }
    }

    #expect(store.state.showsHistoryKeyboardCursor(first.id))
    #expect(!store.state.showsHistoryKeyboardCursor(secondID))

    // Copying settles the cursor where it already was, so j afterwards advances rather than
    // starting over.
    await store.send(.history(.copyRequested)) {
      $0.history.cursor = first.id
      $0.history.copiedEntryID = first.id
    }
    await store.send(.history(.cursorMoved(.next))) {
      $0.history.cursor = secondID
    }
    await clock.advance(by: .seconds(1.2))
    await store.receive(.history(.copyFinished(first.id))) {
      $0.history.copiedEntryID = nil
    }
  }

  @Test func `cursor outside the filtered list restarts at the first match`() async throws {
    let first = makeEntry(text: "Matching transcript")
    let hiddenID = try #require(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"))
    let hidden = makeEntry(id: hiddenID, text: "Hidden transcript")
    var state = makeState([first, hidden])
    state.cursor = hidden.id
    state.search = "Matching"
    let store = TestStore(initialState: state) { HistoryFeature() }

    await store.send(.cursorMoved(.next)) {
      $0.cursor = first.id
    }
  }

  @Test func `keyboard movement continues from the row last moved by hover`() async throws {
    let first = makeEntry()
    let secondID = try #require(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"))
    let thirdID = try #require(UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"))
    let store = TestStore(
      initialState: makeState([first, makeEntry(id: secondID), makeEntry(id: thirdID)]),
    ) { HistoryFeature() }

    await store.send(.cursorHovered(secondID)) { $0.cursor = secondID }
    await store.send(.cursorMoved(.next)) { $0.cursor = thirdID }
  }

  @Test func `the keyboard cursor needs keyboard input and a focused detail column`() async {
    let entry = makeEntry()
    var state = makeWindowState([entry])
    state.history.cursor = entry.id
    state.interaction.focus = .detail
    let store = TestStore(initialState: state) { SettingsWindowFeature() }

    #expect(!store.state.showsHistoryKeyboardCursor(entry.id))
    await store.send(.keyboardModeEntered) {
      $0.interaction.mode = .keyboard
    }
    #expect(store.state.showsHistoryKeyboardCursor(entry.id))
    await store.send(.focusChanged(.sidebar)) {
      $0.interaction.focus = .sidebar
    }
    #expect(!store.state.showsHistoryKeyboardCursor(entry.id))
    await store.send(.focusChanged(.detail)) {
      $0.interaction.focus = .detail
    }
    await store.send(.pointerMoved) {
      $0.interaction.mode = .mouse
    }
    #expect(!store.state.showsHistoryKeyboardCursor(entry.id))
  }

  @Test func `deleting the cursor moves it to the next entry`() async throws {
    let entry = makeEntry()
    let nextID = try #require(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"))
    let next = makeEntry(id: nextID)
    let deleted = DeletedAudioRecorder()
    var state = makeState([entry, next])
    state.cursor = entry.id
    let store = TestStore(initialState: state) { HistoryFeature() } withDependencies: {
      $0.historyClient.deleteAudio = { ids in await deleted.record(ids) }
    }

    await store.send(.deleteTapped(entry.id))
    await store.receive(.deleteCompleted(entry.id)) {
      $0.cursor = next.id
      $0.$log.withLock { $0.entries = [next] }
    }
    #expect(await deleted.ids == [entry.id])
  }

  @Test func `deleting the last entry leaves the cursor on the one above`() async throws {
    let previousID = try #require(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"))
    let previous = makeEntry(id: previousID)
    let last = makeEntry()
    var state = makeState([previous, last])
    state.cursor = last.id
    let store = TestStore(initialState: state) { HistoryFeature() }

    await store.send(.deleteTapped(last.id))
    await store.receive(.deleteCompleted(last.id)) {
      $0.cursor = previous.id
      $0.$log.withLock { $0.entries = [previous] }
    }
  }

  @Test func `player completion clears the playing row`() async {
    let entry = makeEntry()
    let store = TestStore(initialState: makeState([entry])) { HistoryFeature() }

    await store.send(.playTapped(entry.id)) {
      $0.playingEntryID = entry.id
    }
    await store.receive(.playbackEnded(entry.id)) {
      $0.playingEntryID = nil
    }
  }

  @Test func `an interrupted player reports nothing back`() async {
    let entry = makeEntry()
    let store = TestStore(initialState: makeState([entry])) { HistoryFeature() } withDependencies: {
      $0.historyPlayback.play = { _ in .interrupted }
    }

    await store.send(.playTapped(entry.id)) {
      $0.playingEntryID = entry.id
    }
  }

  @Test func `search filters transcript text without changing history`() {
    let matching = makeEntry(text: "Deploy the history pane")
    let other = makeEntry(id: UUID(), text: "Review the model")
    var state = makeState([matching, other])

    state.search = "HISTORY"

    #expect(state.filteredEntries.map(\.id) == [matching.id])
    #expect(state.log.entries.count == 2)
  }

  @Test func `a cleaned row copies what it shows`() async {
    let copied = CopiedTextRecorder()
    let clock = TestClock()
    let entry = makeEntry(text: "dash dash help", cleaned: "Use --help.")
    let store = TestStore(initialState: makeState([entry])) { HistoryFeature() } withDependencies: {
      $0.continuousClock = clock
      $0.delivery.copy = { await copied.record($0) }
    }

    await store.send(.rowTapped(entry.id)) {
      $0.cursor = entry.id
      $0.copiedEntryID = entry.id
    }
    await clock.advance(by: .seconds(1.2))
    await store.receive(.copyFinished(entry.id)) {
      $0.copiedEntryID = nil
    }
    #expect(await copied.texts == ["Use --help."])
  }

  @Test func `search matches the text the pane shows`() {
    let cleaned = makeEntry(text: "dash dash help", cleaned: "Use --help.")
    let other = makeEntry(id: UUID(), text: "Review the model")
    var state = makeState([cleaned, other])

    state.search = "--help"

    #expect(state.filteredEntries.map(\.id) == [cleaned.id])
  }

  @Test func `the hold reveals every transcript until the release`() async {
    let store = TestStore(initialState: makeState([makeEntry()])) { HistoryFeature() }

    await store.send(.revealChanged(true)) {
      $0.isRevealingRawText = true
    }
    await store.send(.revealChanged(false)) {
      $0.isRevealingRawText = false
    }
  }

  @Test func `copying under the hold takes the transcript, not the rewrite`() async {
    let copied = CopiedTextRecorder()
    let clock = TestClock()
    let cleaned = makeEntry(text: "dash dash help", cleaned: "Use --help.")
    let plain = makeEntry(id: UUID(), text: "A saved transcript")
    var state = makeState([cleaned, plain])
    state.isRevealingRawText = true
    let store = TestStore(initialState: state) { HistoryFeature() } withDependencies: {
      $0.continuousClock = clock
      $0.delivery.copy = { await copied.record($0) }
    }

    await store.send(.rowTapped(cleaned.id)) {
      $0.cursor = cleaned.id
      $0.copiedEntryID = cleaned.id
    }
    await clock.advance(by: .seconds(1.2))
    await store.receive(.copyFinished(cleaned.id)) {
      $0.copiedEntryID = nil
    }
    // A row with nothing underneath copies what it always shows, held key or not.
    await store.send(.rowTapped(plain.id)) {
      $0.cursor = plain.id
      $0.copiedEntryID = plain.id
    }
    await clock.advance(by: .seconds(1.2))
    await store.receive(.copyFinished(plain.id)) {
      $0.copiedEntryID = nil
    }
    #expect(await copied.texts == ["dash dash help", "A saved transcript"])
  }

  @Test func `re-transcription appends without replacing the original`() async {
    let entry = makeEntry(text: "Original text")
    let date = Date(timeIntervalSince1970: 1_700_000_100)
    let state = makeState([entry])
    state.$dictionary.withLock {
      $0.vocabulary = [VocabularyEntry(text: "TCA", addedAt: date)]
    }
    let store = TestStore(initialState: state) { HistoryFeature() } withDependencies: {
      $0.date.now = date
      $0.historyClient.loadAudio = { _ in CanonicalRecording(samples: [0]) }
      $0.asrEngine.identity = { "second-engine" }
      $0.asrEngine.submit = { _, dictionary in
        #expect(dictionary.vocabulary == ["TCA"])
        #expect(dictionary.corrections.isEmpty)
        return .transcript("Second opinion")
      }
    }

    await store.send(.retranscribeTapped(entry.id)) {
      $0.retranscribingEntryIDs.insert(entry.id)
    }
    await store.receive(
      .retranscriptionCompleted(
        entry.id, ProcessedTranscript(outcome: .transcript("Second opinion"), cleanup: nil),
      ),
    ) {
      $0.retranscribingEntryIDs.remove(entry.id)
      $0.$log.withLock {
        $0.entries[0].addRetranscription(
          Transcription(text: "Second opinion", engine: "second-engine", transcribedAt: date),
        )
      }
    }
    #expect(store.state.log.entries[0].original?.text == "Original text")
  }

  /// A re-run is a dictation minus the delivery: the same two legs, conditioned by the facts the
  /// entry kept and by the pane as it stands today.
  @Test func `a re-run polishes what the engine heard, conditioned by the entry`() async throws {
    let date = Date(timeIntervalSince1970: 1_700_000_100)
    let entry = makeEntry(text: "Original text", fieldContext: terminalContext)
    var state = makeState([entry], cleanup: configuredCleanup)
    state.$dictionary.withLock {
      $0.vocabulary = [VocabularyEntry(text: "TCA", addedAt: date)]
    }
    let store = TestStore(initialState: state) { HistoryFeature() } withDependencies: {
      $0.date.now = date
      $0.historyClient.loadAudio = { _ in CanonicalRecording(samples: [0]) }
      $0.asrEngine.identity = { "second-engine" }
      $0.asrEngine.submit = { _, dictionary in
        #expect(dictionary.vocabulary == ["TCA"])
        return .transcript("um second opinion")
      }
      $0.keychain.read = { _ in "sk-test" }
      $0.cleanup.clean = { request, configuration, apiKey in
        #expect(request.transcript == "um second opinion")
        #expect(request.focusedTextContext == terminalContext)
        #expect(request.vocabulary == ["TCA"])
        #expect(request.targetBundleID == "com.apple.dt.Xcode")
        #expect(configuration.model == "gpt-oss-120b")
        #expect(apiKey == "sk-test")
        return .cleaned("Second opinion.")
      }
    }

    let processed = ProcessedTranscript(
      outcome: .transcript("um second opinion"),
      cleanup: CleanupRecord(
        disposition: .cleaned("Second opinion."), model: "gpt-oss-120b",
        endpoint: gatewayEndpoint, durationSeconds: 0,
      ),
    )
    await store.send(.retranscribeTapped(entry.id)) {
      $0.retranscribingEntryIDs.insert(entry.id)
    }
    await store.receive(.retranscriptionCompleted(entry.id, processed)) {
      $0.retranscribingEntryIDs.remove(entry.id)
      $0.$log.withLock {
        $0.entries[0].addRetranscription(
          Transcription(
            text: "um second opinion", engine: "second-engine", transcribedAt: date,
            cleanup: processed.cleanup,
          ),
        )
      }
    }

    let rerun = try #require(store.state.log.entries[0].currentTranscription)
    #expect(rerun.cleanup?.disposition == .cleaned("Second opinion."))
    #expect(store.state.log.entries[0].displayText == "Second opinion.")
    #expect(store.state.log.entries[0].revealedText == "um second opinion")
    #expect(store.state.log.entries[0].original?.text == "Original text")
  }

  @Test func `a re-run with cleanup off is engine-only, exactly as a dictation would be`() async {
    let date = Date(timeIntervalSince1970: 1_700_000_100)
    let entry = makeEntry(text: "Original text", fieldContext: terminalContext)
    let store = TestStore(initialState: makeState([entry])) { HistoryFeature() } withDependencies: {
      $0.date.now = date
      $0.historyClient.loadAudio = { _ in CanonicalRecording(samples: [0]) }
      $0.asrEngine.identity = { "second-engine" }
      $0.asrEngine.submit = { _, _ in .transcript("second opinion") }
      $0.cleanup.clean = { _, _, _ in
        Issue.record("A disabled cleanup pass must never send a request")
        return .cancelled
      }
    }

    await store.send(.retranscribeTapped(entry.id)) {
      $0.retranscribingEntryIDs.insert(entry.id)
    }
    await store.receive(
      .retranscriptionCompleted(
        entry.id, ProcessedTranscript(outcome: .transcript("second opinion"), cleanup: nil),
      ),
    ) {
      $0.retranscribingEntryIDs.remove(entry.id)
      $0.$log.withLock {
        $0.entries[0].addRetranscription(
          Transcription(text: "second opinion", engine: "second-engine", transcribedAt: date),
        )
      }
    }
    #expect(store.state.log.entries[0].displayText == "second opinion")
    #expect(store.state.log.entries[0].revealedText == nil)
  }

  @Test func `a lengthened limit is saved and swept immediately`() async {
    let store = TestStore(
      initialState: AppFeature.State(
        history: Shared(value: HistoryLog()), settings: Shared(value: .defaults),
      ),
    ) { AppFeature() } withDependencies: {
      $0.date.now = Date(timeIntervalSince1970: 1_700_000_000)
    }

    await store.send(.settingsWindow(.history(.retentionProposed(.audio, .ninetyDays)))) {
      $0.$settings.withLock { $0.retention.audio = .ninetyDays }
    }
    await store.receive(.settingsWindow(.history(.delegate(.retentionChanged))))
    await store.receive(.historyMaintenanceRequested) {
      $0.historyMaintenance = .running
    }
    await store.receive(.historyMaintenanceCompleted(HistoryLog())) {
      $0.historyMaintenance = .idle
    }
  }

  @Test func `a retention change rewrites settings json whole`() async throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "settings-\(UUID().uuidString)", directoryHint: .isDirectory,
    )
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let settingsURL = root.appending(path: "settings.json")
    let stored = try MiniWhisperSettings(
      bindings: HotkeyBindingsSettings(
        activate: [Hotkey(keyCode: 0, modifiers: [.leftCommand])],
        pasteLastTranscript: HotkeyBindingsSettings.defaults.hotkeys(for: .pasteLastTranscript),
      ),
      microphone: .systemDefault, sounds: .silent, retention: .defaults,
      improveRecognition: true, cleanup: .defaults,
    )
    try SettingsCoding.encode(stored).write(to: settingsURL)

    let state = withDependencies {
      $0.defaultFileStorage = .fileSystem
    } operation: {
      AppFeature.State(
        history: Shared(value: HistoryLog()),
        settings: Shared(
          wrappedValue: .defaults,
          .fileStorage(settingsURL, decode: SettingsCoding.decode, encode: SettingsCoding.encode),
        ),
      )
    }
    let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
      $0.date.now = Date(timeIntervalSince1970: 1_700_000_000)
      $0.defaultFileStorage = .fileSystem
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.settingsWindow(.history(.retentionProposed(.audio, .ninetyDays))))
    await store.finish()

    let persisted = try SettingsCoding.decode(Data(contentsOf: settingsURL))
    #expect(persisted.retention.audio == .ninetyDays)
    #expect(persisted.bindings == stored.bindings)
    #expect(persisted.sounds == .silent)
  }

  @Test func `a shortened limit waits for confirmation before it deletes anything`() async {
    var state = makeState([makeEntry()])
    state.$retention.withLock { $0 = .defaults }
    let store = TestStore(initialState: state) { HistoryFeature() }

    await store.send(.retentionProposed(.audio, .oneDay)) {
      $0.pendingRetentionReduction = .init(field: .audio, value: .oneDay)
    }
    #expect(store.state.retention.audio == RetentionPolicy.defaults.audio)

    await store.send(.retentionReductionConfirmed) {
      $0.pendingRetentionReduction = nil
      $0.$retention.withLock { $0.audio = .oneDay }
    }
    await store.receive(.delegate(.retentionChanged))
  }
}

// MARK: - CopiedTextRecorder

private actor CopiedTextRecorder {
  private(set) var texts: [String] = []

  func record(_ text: String) {
    texts.append(text)
  }
}

// MARK: - DeletedAudioRecorder

private actor DeletedAudioRecorder {
  private(set) var ids: [UUID] = []

  func record(_ ids: [UUID]) {
    self.ids.append(contentsOf: ids)
  }
}

private let gatewayEndpoint = URL(string: "https://gateway.example/v1")!
private let configuredCleanup = CleanupSettings(
  enabled: true, endpoint: gatewayEndpoint, model: "gpt-oss-120b", timeout: 10,
  additionalInstructions: "",
)
private let terminalContext = FocusedTextContext(
  role: "AXTextArea", before: "$ ", selected: "", after: "", selectedRange: 2 ..< 2,
  beforeWasTruncated: false, selectionWasTruncated: false, afterWasTruncated: false,
)

private func makeState(
  _ entries: [HistoryEntry], cleanup: CleanupSettings = .defaults,
) -> HistoryFeature.State {
  HistoryFeature.State(
    log: Shared(value: HistoryLog(entries: entries)), retention: Shared(value: .defaults),
    dictionary: Shared(value: .empty), improveRecognition: Shared(value: true),
    cleanup: Shared(value: cleanup),
  )
}

private func makeWindowState(_ entries: [HistoryEntry]) -> SettingsWindowFeature.State {
  SettingsWindowFeature.State(
    selection: .history, history: Shared(value: HistoryLog(entries: entries)),
    settings: Shared(value: .defaults), dictionary: Shared(value: .empty),
    health: Shared(value: AppHealth()),
  )
}

private func makeEntry(
  id: UUID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
  text: String = "A saved transcript",
  cleaned: String? = nil,
  fieldContext: FocusedTextContext? = nil,
) -> HistoryEntry {
  let date = Date(timeIntervalSince1970: 1_700_000_000)
  return HistoryEntry(
    id: id,
    createdAt: date,
    targetApp: TargetApp(bundleID: "com.apple.dt.Xcode", name: "Xcode"),
    original: Transcription(
      text: text, engine: "original-engine", transcribedAt: date,
      cleanup: cleaned.map {
        CleanupRecord(
          disposition: .cleaned($0), model: "gpt-oss-120b",
          endpoint: URL(string: "https://gateway.example/v1")!, durationSeconds: 1.2,
        )
      },
    ),
    fieldContext: fieldContext,
    delivery: Delivery(text: cleaned ?? text, method: .pasted, detail: nil),
    audio: AudioMetadata(durationSeconds: 4.2, byteCount: 268_800),
  )
}
