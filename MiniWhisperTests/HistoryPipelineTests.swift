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

// MARK: - HistoryPipelineTests

@MainActor struct HistoryPipelineTests {
  @Test func `successful delivery appends complete history entry`() async throws {
    let createdAt = Date(timeIntervalSince1970: 100)
    let transcribedAt = Date(timeIntervalSince1970: 200)
    let id = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    let recording = CanonicalRecording(samples: Array(repeating: 0.25, count: 16000))
    let targetApp = TargetApp(bundleID: "com.example.Editor", name: "Editor")
    let metadata = AudioMetadata(durationSeconds: 1, byteCount: 64044)
    let captured = ContextCapture.available(historyContext(before: "Ready."))
    var state = historyState()
    state.transcriptionGeneration = 1
    state.pill.presentation = .transcribing
    state.pendingDictation = pendingDictation(
      generation: 1, recording: recording, createdAt: createdAt,
    )
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.contextCapture.capture = { _ in captured }
      $0.date.now = transcribedAt
      $0.delivery.deliver = { text in
        #expect(text == " Dictated text")
        return .pasted(.restored)
      }
      $0.historyClient.writeAudio = { savedRecording, savedID in
        #expect(savedRecording == recording)
        #expect(savedID == id)
        return metadata
      }
      $0.uuid = .constant(id)
      $0.workspace.frontmostApplication = {
        WorkspaceApplication(bundleID: targetApp.bundleID, name: targetApp.name)
      }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(
      .transcriptionCompleted(1, suppressNoSpeechNotice: false, .transcript("dictated text")),
    ) {
      $0.lastTranscript = "dictated text"
      $0.pendingDictation?.original = History.Transcription(
        text: "dictated text", engine: "test-engine@revision", transcribedAt: transcribedAt,
      )
    }
    await store.receive(.contextCaptured(1, captured)) { $0.currentFocusedContext = captured }
    await store.receive(
      .deliveryCompleted(
        1,
        AppFeature.DeliveryResult(
          text: " Dictated text", targetApp: targetApp, outcome: .pasted(.restored),
        ),
      ),
    ) {
      $0.currentFocusedContext = nil
      $0.pendingDictation?.isFinishing = true
    }
    await store.receive(.pill(.dismiss)) { $0.pill.presentation = nil }
    let entry = HistoryEntry(
      id: id, createdAt: createdAt, targetApp: targetApp,
      original: History.Transcription(
        text: "dictated text", engine: "test-engine@revision", transcribedAt: transcribedAt,
      ),
      delivery: Delivery(text: " Dictated text", method: .pasted, detail: nil), audio: metadata,
    )
    await store.receive(.historyEntryPrepared(1, entry))
    await store.finish()
    #expect(store.state.history.entries == [entry])
  }

  @Test func `no speech creates no history entry`() async {
    var state = historyState()
    state.transcriptionGeneration = 1
    state.pill.presentation = .transcribing
    state.pendingDictation = pendingDictation(generation: 1)
    let store = TestStore(initialState: state) { AppFeature() }

    await store.send(.transcriptionCompleted(1, suppressNoSpeechNotice: true, .noSpeech)) {
      $0.pendingDictation = nil
    }
    await store.receive(.pill(.dismiss)) { $0.pill.presentation = nil }
    #expect(store.state.history.entries.isEmpty)
  }

  @Test func `transcription failure retains recoverable audio without original text`() async throws {
    let id = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
    let metadata = AudioMetadata(durationSeconds: 0.5, byteCount: 32044)
    var state = historyState()
    state.engineReadiness = .ready
    state.transcriptionGeneration = 3
    state.pill.presentation = .transcribing
    state.pendingDictation = pendingDictation(generation: 3)
    let pending = state.pendingDictation
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.historyClient.writeAudio = { _, savedID in
        #expect(savedID == id)
        return metadata
      }
      $0.uuid = .constant(id)
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.transcriptionFailed(3, "engine failed")) {
      $0.engineReadiness = .failed("engine failed")
      $0.pendingDictation?.isFinishing = true
    }
    await store.receive(.pill(.dismiss)) { $0.pill.presentation = nil }
    let entry = try HistoryEntry(
      id: id, createdAt: #require(pending?.createdAt), targetApp: nil, original: nil,
      delivery: nil,
      audio: metadata,
    )
    await store.receive(.historyEntryPrepared(3, entry))
    await store.finish()
    #expect(store.state.history.entries == [entry])
  }

  @Test func `hard delivery failure retains transcript with nil delivery`() async throws {
    let id = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000007"))
    let targetApp = TargetApp(bundleID: "com.example.Editor", name: "Editor")
    var state = historyState()
    state.$settings.withLock { $0.retention.audio = .never }
    state.transcriptionGeneration = 2
    state.pendingDictation = pendingDictation(generation: 2)
    state.pendingDictation?.original = History.Transcription(
      text: "recover me", engine: "test-engine@revision",
      transcribedAt: Date(timeIntervalSince1970: 200),
    )
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.uuid = .constant(id)
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(
      .deliveryFailed(
        2,
        AppFeature.DeliveryFailure(
          text: "recover me", targetApp: targetApp, message: "pasteboard failed",
        ),
      ),
    )
    let entry = HistoryEntry(
      id: id, createdAt: Date(timeIntervalSince1970: 100), targetApp: targetApp,
      original: History.Transcription(
        text: "recover me", engine: "test-engine@revision",
        transcribedAt: Date(timeIntervalSince1970: 200),
      ),
      delivery: nil, audio: nil,
    )
    await store.receive(.historyEntryPrepared(2, entry))
    await store.finish()
    #expect(store.state.history.entries == [entry])
  }

  @Test func `failed recovery audio write completes without an empty entry`() async {
    var state = historyState()
    state.engineReadiness = .ready
    state.transcriptionGeneration = 3
    state.pill.presentation = .transcribing
    state.pendingDictation = pendingDictation(generation: 3)
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.historyClient.writeAudio = { _, _ in throw HistoryPipelineTestError.audioWriteFailed }
      $0.uuid = .constant(UUID())
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.transcriptionFailed(3, "engine failed"))
    await store.receive(.historyEntryAbandoned(3))
    await store.finish()
    #expect(store.state.pendingDictation == nil)
    #expect(store.state.history.entries.isEmpty)
  }

  @Test func `dictation before launch maintenance completes still writes recovery audio`(
  ) async throws {
    let id = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000008"))
    let metadata = AudioMetadata(durationSeconds: 0.5, byteCount: 32044)
    var state = historyState()
    state.transcriptionGeneration = 4
    state.dictationInFlight = true
    state.historyMaintenance = .waiting
    state.pendingDictation = pendingDictation(generation: 4)
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.date.now = Date(timeIntervalSince1970: 1000)
      $0.historyClient.writeAudio = { _, savedID in
        #expect(savedID == id)
        return metadata
      }
      $0.uuid = .constant(id)
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.transcriptionFailed(4, "engine failed"))
    await store.receive(
      .historyEntryPrepared(
        4,
        HistoryEntry(
          id: id, createdAt: Date(timeIntervalSince1970: 100), targetApp: nil,
          original: nil, delivery: nil, audio: metadata,
        ),
      ),
    )
    await store.finish()

    #expect(store.state.history.entries.first?.audio == metadata)
  }

  @Test func `audio retention never skips the vault write`() async throws {
    let writes = AudioWriteCounter()
    let id = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
    var state = historyState()
    state.$settings.withLock { $0.retention.audio = .never }
    state.transcriptionGeneration = 4
    state.pill.presentation = .transcribing
    state.pendingDictation = pendingDictation(generation: 4)
    state.pendingDictation?.original = History.Transcription(
      text: "keep text", engine: "test-engine@revision",
      transcribedAt: Date(timeIntervalSince1970: 200),
    )
    let pending = try #require(state.pendingDictation)
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.historyClient.writeAudio = { _, _ in
        await writes.record()
        return AudioMetadata(durationSeconds: 1, byteCount: 1)
      }
      $0.uuid = .constant(id)
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(
      .deliveryCompleted(
        4, AppFeature.DeliveryResult(
          text: "keep text",
          targetApp: nil,
          outcome: .pasted(.restored),
        ),
      ),
    ) {
      $0.pendingDictation?.isFinishing = true
    }
    await store.receive(.pill(.dismiss)) { $0.pill.presentation = nil }
    let entry = HistoryEntry(
      id: id, createdAt: pending.createdAt, targetApp: nil, original: pending.original,
      delivery: Delivery(text: "keep text", method: .pasted, detail: nil), audio: nil,
    )
    await store.receive(.historyEntryPrepared(4, entry))
    await store.finish()
    #expect(store.state.history.entries == [entry])
    #expect(await writes.isEmpty)
  }

  @Test func `stale generation cannot write history`() async {
    let writes = AudioWriteCounter()
    var state = historyState()
    state.transcriptionGeneration = 5
    state.pendingDictation = pendingDictation(generation: 4)
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.historyClient.writeAudio = { _, _ in
        await writes.record()
        return AudioMetadata(durationSeconds: 1, byteCount: 1)
      }
    }

    await store.send(.transcriptionFailed(4, "stale failure"))
    await store.finish()
    #expect(store.state.history.entries.isEmpty)
    #expect(await writes.isEmpty)
  }

  @Test func `new dictation lets stale persistence clean up its audio`() async throws {
    let id = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000006"))
    let recording = CanonicalRecording(samples: [0.25])
    let (writeGate, openWriteGate) = AsyncStream.makeStream(of: Void.self)
    let maintenance = HistoryMaintenanceRecorder()
    var state = historyState()
    state.onboardingCompleted = true
    state.transcriptionGeneration = 1
    state.pendingDictation = pendingDictation(generation: 1, recording: recording)
    state.pendingDictation?.original = History.Transcription(
      text: "first", engine: "test-engine@revision",
      transcribedAt: Date(timeIntervalSince1970: 200),
    )
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.asrEngine.prepareForActivation = { AsyncStream { _ in } }
      $0.audioCapture.currentInputDeviceName = { "Test Microphone" }
      $0.audioCapture.start = {
        AudioCaptureSession(
          id: UUID(), inputDeviceName: "Test Microphone", events: AsyncStream { _ in },
        )
      }
      $0.contextCapture.prewarmFrontmostApp = {}
      $0.historyClient.writeAudio = { _, _ in
        for await _ in writeGate {}
        return AudioMetadata(durationSeconds: recording.durationSeconds, byteCount: 48)
      }
      $0.historyClient.deleteAudio = { ids in await maintenance.recordDeletion(ids) }
      $0.uuid = .constant(id)
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(
      .deliveryCompleted(
        1, AppFeature.DeliveryResult(text: "first", targetApp: nil, outcome: .pasted(.restored)),
      ),
    )
    await store.send(.hotkeyListenerEvent(.gesture(.startRecording))) {
      $0.transcriptionGeneration = 2
      $0.pendingDictation = nil
    }
    openWriteGate.finish()
    let entry = HistoryEntry(
      id: id, createdAt: Date(timeIntervalSince1970: 100), targetApp: nil,
      original: History.Transcription(
        text: "first", engine: "test-engine@revision",
        transcribedAt: Date(timeIntervalSince1970: 200),
      ),
      delivery: Delivery(text: "first", method: .pasted, detail: nil),
      audio: AudioMetadata(durationSeconds: recording.durationSeconds, byteCount: 48),
    )
    await store.receive(.historyEntryPrepared(1, entry))
    await store.skipInFlightEffects()
    #expect(store.state.history.entries.isEmpty)
    #expect(await maintenance.deletedIDs == [id])
  }

  @Test func `launch maintenance reconciles and applies current retention`() async throws {
    let id = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000005"))
    let now = Date(timeIntervalSince1970: 3 * 86400)
    let entry = HistoryEntry(
      id: id, createdAt: Date(timeIntervalSince1970: 86400), targetApp: nil,
      original: History.Transcription(
        text: "retained", engine: "test-engine@revision",
        transcribedAt: Date(timeIntervalSince1970: 86400),
      ),
      delivery: nil, audio: AudioMetadata(durationSeconds: 1, byteCount: 64044),
    )
    let original = HistoryLog(entries: [entry])
    var expectedEntry = entry
    expectedEntry.audio = nil
    let expected = HistoryLog(entries: [expectedEntry])
    let maintenance = HistoryMaintenanceRecorder()
    let state = AppFeature.State(
      history: Shared(value: original),
      settings: Shared(value: MiniWhisperSettings(
        hotkeys: [.rightOption], soundsEnabled: true,
        retention: RetentionPolicy(transcripts: .forever, audio: .oneDay),
      )),
    )
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.date.now = now
      $0.historyClient.reconcile = { log in
        await maintenance.recordReconcile()
        return log
      }
      $0.historyClient.deleteAudio = { ids in await maintenance.recordDeletion(ids) }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.historyMaintenanceRequested)
    await store.receive(.historyMaintenanceCompleted(expected))
    await store.finish()
    #expect(store.state.history == expected)
    #expect(await maintenance.reconcileCount == 1)
    #expect(await maintenance.deletedIDs == [id])
  }

  @Test func `maintenance requested mid recording waits for the terminal transition`() async {
    let policy = RetentionPolicy(transcripts: .forever, audio: .never)
    var state = historyState()
    state.$settings.withLock { $0.retention = policy }
    state.dictationInFlight = true
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.date.now = Date(timeIntervalSince1970: 1000)
      $0.historyClient.deleteAudio = { _ in }
      $0.historyClient.reconcile = { $0 }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.historyMaintenanceRequested) {
      $0.historyMaintenance = .waiting
    }
    await store.send(.recording(.delegate(.failed))) {
      $0.dictationInFlight = false
      $0.historyMaintenance = .running
    }
    await store.receive(.historyMaintenanceCompleted(HistoryLog()))
    await store.finish()
    #expect(store.state.settings.retention == policy)
  }

  @Test func `unreadable history is not overwritten by a completed dictation`() async throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "history-corrupt-\(UUID().uuidString)", directoryHint: .isDirectory,
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let historyURL = root.appending(path: "History/history.json")
    try FileManager.default.createDirectory(
      at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true,
    )
    let corruptHistory = Data("not history".utf8)
    try corruptHistory.write(to: historyURL)
    let id = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000005"))
    let metadata = AudioMetadata(durationSeconds: 1, byteCount: 64044)
    let entry = HistoryEntry(
      id: id, createdAt: Date(timeIntervalSince1970: 100), targetApp: nil,
      original: History.Transcription(
        text: "preserve the old file", engine: "test-engine@revision",
        transcribedAt: Date(timeIntervalSince1970: 200),
      ),
      delivery: Delivery(text: "preserve the old file", method: .pasted, detail: nil),
      audio: metadata,
    )
    var state = withDependencies {
      $0.defaultFileStorage = .fileSystem
    } operation: {
      AppFeature.State(
        history: Shared(wrappedValue: HistoryLog(), .fileStorage(historyURL)),
        settings: Shared(value: .defaults),
      )
    }
    state.transcriptionGeneration = 1
    state.dictationInFlight = true
    state.pendingDictation = pendingDictation(generation: 1)
    state.pendingDictation?.isFinishing = true
    let recorder = HistoryMaintenanceRecorder()
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.historyClient.deleteAudio = { ids in await recorder.recordDeletion(ids) }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.historyEntryPrepared(1, entry)) {
      $0.pendingDictation = nil
      $0.dictationInFlight = false
    }
    await store.finish()

    #expect(store.state.history.entries.isEmpty)
    #expect(try Data(contentsOf: historyURL) == corruptHistory)
    #expect(await recorder.deletedIDs == [id])
  }

  @Test func `history file storage and audio vault persist together`() async throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "history-pipeline-\(UUID().uuidString)", directoryHint: .isDirectory,
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let historyURL = root.appending(path: "History/history.json")
    let vault = AudioVault(directoryURL: root.appending(path: "History/audio"))
    let id = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000004"))
    let recording = CanonicalRecording(samples: Array(repeating: 0.25, count: 16000))
    var state = withDependencies {
      $0.defaultFileStorage = .fileSystem
    } operation: {
      AppFeature.State(
        history: Shared(wrappedValue: HistoryLog(), .fileStorage(historyURL)),
        settings: Shared(value: .defaults),
      )
    }
    state.transcriptionGeneration = 1
    state.pendingDictation = pendingDictation(generation: 1, recording: recording)
    state.pendingDictation?.original = History.Transcription(
      text: "persist me", engine: "test-engine@revision",
      transcribedAt: Date(timeIntervalSince1970: 200),
    )
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.historyClient.writeAudio = { recording, id in try vault.write(recording, id: id) }
      $0.historyClient.deleteAudio = { ids in try vault.delete(ids) }
      $0.historyClient.reconcile = { log in try vault.reconcile(log) }
      $0.uuid = .constant(id)
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(
      .deliveryCompleted(
        1, AppFeature.DeliveryResult(
          text: "persist me",
          targetApp: nil,
          outcome: .pasted(.restored),
        ),
      ),
    )
    await store.finish()

    let persisted = try JSONDecoder().decode(HistoryLog.self, from: Data(contentsOf: historyURL))
    #expect(persisted.entries == store.state.history.entries)
    #expect(persisted.entries.first?.audio != nil)
    #expect(FileManager.default.fileExists(atPath: vault.url(id: id).path))
  }
}

private func historyState() -> AppFeature.State {
  AppFeature.State(history: Shared(value: HistoryLog()), settings: Shared(value: .defaults))
}

private func pendingDictation(
  generation: Int, recording: CanonicalRecording = CanonicalRecording(samples: [0.25]),
  createdAt: Date = Date(timeIntervalSince1970: 100),
) -> AppFeature.PendingDictation {
  AppFeature.PendingDictation(
    generation: generation, recording: recording, createdAt: createdAt,
    engine: "test-engine@revision", original: nil,
  )
}

// MARK: - HistoryMaintenanceRecorder

private actor HistoryMaintenanceRecorder {
  private(set) var reconcileCount = 0
  private(set) var deletedIDs: [UUID] = []

  func recordReconcile() {
    reconcileCount += 1
  }

  func recordDeletion(_ ids: [UUID]) {
    deletedIDs.append(contentsOf: ids)
  }
}

// MARK: - HistoryPipelineTestError

private enum HistoryPipelineTestError: Error {
  case audioWriteFailed
}

// MARK: - AudioWriteCounter

private actor AudioWriteCounter {
  private(set) var count = 0

  var isEmpty: Bool {
    count == 0
  }

  func record() {
    count += 1
  }
}

private func historyContext(before: String) -> FocusedTextContext {
  FocusedTextContext(
    role: "AXTextArea", before: before, selected: "", after: "",
    selectedRange: before.utf16.count ..< before.utf16.count, beforeWasTruncated: false,
    selectionWasTruncated: false, afterWasTruncated: false,
  )
}
