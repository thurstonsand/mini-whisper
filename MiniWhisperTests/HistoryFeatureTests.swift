import AppSettings
import ASREngine
import AudioCapture
import ComposableArchitecture
import Foundation
import History
import HotkeyListener
@testable import MiniWhisper
import Testing

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
    state.focus = .detail
    state.inputMode = .keyboard
    let clock = TestClock()
    let store = TestStore(initialState: state) { SettingsWindowFeature() } withDependencies: {
      $0.continuousClock = clock
      $0.delivery.copy = { _ in }
    }

    #expect(store.state.showsKeyboardCursor(first.id))
    #expect(!store.state.showsKeyboardCursor(secondID))

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

  @Test func `the keyboard cursor needs keyboard input and a focused detail column`() async {
    let entry = makeEntry()
    var state = makeWindowState([entry])
    state.history.cursor = entry.id
    state.focus = .detail
    let store = TestStore(initialState: state) { SettingsWindowFeature() }

    #expect(!store.state.showsKeyboardCursor(entry.id))
    await store.send(.keyboardModeEntered) {
      $0.inputMode = .keyboard
    }
    #expect(store.state.showsKeyboardCursor(entry.id))
    await store.send(.focusChanged(.sidebar)) {
      $0.focus = .sidebar
    }
    #expect(!store.state.showsKeyboardCursor(entry.id))
    await store.send(.focusChanged(.detail)) {
      $0.focus = .detail
    }
    await store.send(.pointerMoved) {
      $0.inputMode = .mouse
    }
    #expect(!store.state.showsKeyboardCursor(entry.id))
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

  @Test func `re-transcription appends without replacing the original`() async {
    let entry = makeEntry(text: "Original text")
    let date = Date(timeIntervalSince1970: 1_700_000_100)
    let store = TestStore(initialState: makeState([entry])) { HistoryFeature() } withDependencies: {
      $0.date.now = date
      $0.historyClient.loadAudio = { _ in CanonicalRecording(samples: [0]) }
      $0.asrEngine.identity = { "second-engine" }
      $0.asrEngine.submit = { _ in .transcript("Second opinion") }
    }

    await store.send(.retranscribeTapped(entry.id)) {
      $0.retranscribingEntryIDs.insert(entry.id)
    }
    await store.receive(.retranscriptionCompleted(entry.id, .transcript("Second opinion"))) {
      $0.retranscribingEntryIDs.remove(entry.id)
      $0.$log.withLock {
        $0.entries[0].addRetranscription(
          Transcription(text: "Second opinion", engine: "second-engine", transcribedAt: date),
        )
      }
    }
    #expect(store.state.log.entries[0].original?.text == "Original text")
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
      hotkey: Hotkey(keyCode: 0, modifiers: [.leftCommand]), soundsEnabled: false,
      retention: .defaults,
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
    #expect(persisted.hotkey == stored.hotkey)
    #expect(persisted.soundsEnabled == false)
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

// MARK: - DeletedAudioRecorder

private actor DeletedAudioRecorder {
  private(set) var ids: [UUID] = []

  func record(_ ids: [UUID]) {
    self.ids.append(contentsOf: ids)
  }
}

private func makeState(_ entries: [HistoryEntry]) -> HistoryFeature.State {
  HistoryFeature.State(
    log: Shared(value: HistoryLog(entries: entries)), retention: Shared(value: .defaults),
  )
}

private func makeWindowState(_ entries: [HistoryEntry]) -> SettingsWindowFeature.State {
  SettingsWindowFeature.State(
    selection: .history, history: Shared(value: HistoryLog(entries: entries)),
    retention: Shared(value: .defaults),
  )
}

private func makeEntry(
  id: UUID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
  text: String = "A saved transcript",
) -> HistoryEntry {
  let date = Date(timeIntervalSince1970: 1_700_000_000)
  return HistoryEntry(
    id: id,
    createdAt: date,
    targetApp: TargetApp(bundleID: "com.apple.dt.Xcode", name: "Xcode"),
    original: Transcription(text: text, engine: "original-engine", transcribedAt: date),
    delivery: Delivery(text: text, method: .pasted, detail: nil),
    audio: AudioMetadata(durationSeconds: 4.2, byteCount: 268_800),
  )
}
