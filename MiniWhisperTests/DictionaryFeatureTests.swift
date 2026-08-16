import AppSettings
import ComposableArchitecture
import Foundation
import History
@testable import MiniWhisper
import SpeechDictionary
import Testing

@MainActor struct DictionaryFeatureTests {
  @Test func `one sorted list presents vocabulary and corrections`() {
    let older = Date(timeIntervalSince1970: 100)
    let newer = Date(timeIntervalSince1970: 200)
    var state = DictionaryFeature.State(
      dictionary: Shared(
        value: DictionaryContents(
          vocabulary: [VocabularyEntry(text: "Zebra", addedAt: newer)],
          corrections: [CorrectionEntry(misspelling: "alpha", text: "Alpha", addedAt: older)],
        ),
      ),
    )

    #expect(state.entries.map(\.text) == ["Zebra", "Alpha"])
    state.sort = .alphabetical
    #expect(state.entries.map(\.text) == ["Alpha", "Zebra"])
  }

  @Test func `sheet refuses whitespace-only vocabulary and correction fields`() async {
    let store = TestStore(
      initialState: DictionaryFeature.State(dictionary: Shared(value: .empty)),
    ) { DictionaryFeature() }

    await store.send(.addRequested) { $0.draft = DictionaryFeature.Draft() }
    await store.send(.draftTextChanged("   ")) { $0.draft?.text = "   " }
    await store.send(.draftSaveRequested)
    #expect(store.state.dictionary == .empty)

    await store.send(.draftCorrectionChanged(true)) { $0.draft?.isCorrection = true }
    await store.send(.draftTextChanged("MiniWhisper")) { $0.draft?.text = "MiniWhisper" }
    await store.send(.draftMisspellingChanged("\n")) { $0.draft?.misspelling = "\n" }
    await store.send(.draftSaveRequested)
    #expect(store.state.dictionary == .empty)
  }

  @Test func `quick add deduplicates vocabulary and updates a correction`() async {
    let date = Date(timeIntervalSince1970: 300)
    let store = TestStore(
      initialState: DictionaryFeature.State(
        dictionary: Shared(
          value: DictionaryContents(
            vocabulary: [VocabularyEntry(text: "TCA", addedAt: date)],
            corrections: [
              CorrectionEntry(misspelling: "mini whisper", text: "Miniwhisper", addedAt: date),
            ],
          ),
        ),
      ),
    ) { DictionaryFeature() } withDependencies: {
      $0.date.now = Date(timeIntervalSince1970: 400)
    }

    await store.send(.quickAddSubmitted(word: " tca ", misspelling: ""))
    await store.send(.quickAddSubmitted(word: "MiniWhisper", misspelling: " MINI WHISPER ")) {
      $0.$dictionary.withLock {
        $0.corrections[0].misspelling = "MINI WHISPER"
        $0.corrections[0].text = "MiniWhisper"
      }
    }
    #expect(store.state.dictionary.vocabulary.count == 1)
    #expect(store.state.dictionary.corrections.count == 1)
    #expect(store.state.dictionary.corrections[0].addedAt == date)
  }

  @Test func `quick add degrades an empty misspelling to vocabulary`() async {
    let date = Date(timeIntervalSince1970: 400)
    let store = TestStore(
      initialState: DictionaryFeature.State(dictionary: Shared(value: .empty)),
    ) { DictionaryFeature() } withDependencies: {
      $0.date.now = date
    }

    await store.send(.quickAddSubmitted(word: " AcmeOS ", misspelling: " \n ")) {
      $0.$dictionary.withLock {
        $0.vocabulary = [VocabularyEntry(text: "AcmeOS", addedAt: date)]
      }
    }
    #expect(store.state.dictionary.corrections.isEmpty)
  }

  @Test func `editing preserves the original date and can change entry kind`() async {
    let date = Date(timeIntervalSince1970: 300)
    let entry = VocabularyEntry(text: "Miniwhisper", addedAt: date)
    let state = DictionaryFeature.State(
      dictionary: Shared(value: DictionaryContents(vocabulary: [entry])),
    )
    let id = DictionaryFeature.EntryID.vocabulary("Miniwhisper")
    let store = TestStore(initialState: state) { DictionaryFeature() }

    await store.send(.editRequested(id)) {
      $0.draft = DictionaryFeature.Draft(originalID: id, text: "Miniwhisper")
    }
    await store.send(.draftCorrectionChanged(true)) { $0.draft?.isCorrection = true }
    await store.send(.draftTextChanged("MiniWhisper")) { $0.draft?.text = "MiniWhisper" }
    await store.send(.draftMisspellingChanged("mini whisperer")) {
      $0.draft?.misspelling = "mini whisperer"
    }
    await store.send(.draftSaveRequested) {
      $0.$dictionary.withLock {
        $0.vocabulary = []
        $0.corrections = [
          CorrectionEntry(misspelling: "mini whisperer", text: "MiniWhisper", addedAt: date),
        ]
      }
    }
    await store.receive(.draftSaveCompleted) {
      $0.draft = nil
    }
  }

  @Test func `n shortcut opens a new entry draft`() async {
    let store = TestStore(
      initialState: DictionaryFeature.State(dictionary: Shared(value: .empty)),
    ) { DictionaryFeature() }

    await store.send(.addShortcutPressed) {
      $0.draft = DictionaryFeature.Draft()
    }
  }

  @Test func `deleting the cursor moves to the row taking its place`() async {
    let newer = VocabularyEntry(text: "Alpha", addedAt: Date(timeIntervalSince1970: 200))
    let older = VocabularyEntry(text: "Beta", addedAt: Date(timeIntervalSince1970: 100))
    var state = DictionaryFeature.State(
      dictionary: Shared(value: DictionaryContents(vocabulary: [newer, older])),
    )
    state.cursor = .vocabulary("Alpha")
    let store = TestStore(initialState: state) { DictionaryFeature() }

    await store.send(.cursorDeleteShortcutPressed) {
      $0.cursor = .vocabulary("Beta")
      $0.$dictionary.withLock { $0.vocabulary = [older] }
    }
  }

  @Test func `deleting from the edit sheet dismisses it`() async {
    let entry = VocabularyEntry(text: "Alpha", addedAt: Date(timeIntervalSince1970: 200))
    let id = DictionaryFeature.EntryID.vocabulary("Alpha")
    var state = DictionaryFeature.State(
      dictionary: Shared(value: DictionaryContents(vocabulary: [entry])),
    )
    state.draft = DictionaryFeature.Draft(originalID: id, text: "Alpha")
    let store = TestStore(initialState: state) { DictionaryFeature() }

    await store.send(.draftDeleteRequested) {
      $0.draft = nil
      $0.$dictionary.withLock { $0.vocabulary = [] }
    }
  }

  @Test func `pane persistence failures present and dismiss an alert`() async {
    let store = TestStore(
      initialState: DictionaryFeature.State(dictionary: Shared(value: .empty)),
    ) { DictionaryFeature() }

    await store.send(.persistenceFailed(.pane, "disk full")) {
      $0.persistenceFailure = "disk full"
    }
    await store.send(.persistenceFailureDismissed) {
      $0.persistenceFailure = nil
    }
  }

  @Test func `quick add persistence failures delegate to the app notice`() async {
    let clock = TestClock()
    let store = TestStore(
      initialState: AppFeature.State(
        history: Shared(value: .init()), settings: Shared(value: .defaults),
        dictionary: Shared(value: .empty),
      ),
    ) { AppFeature() } withDependencies: {
      $0.continuousClock = clock
    }

    await store.send(
      .settingsWindow(.dictionary(.persistenceFailed(.quickAdd, "disk full"))),
    )
    await store.receive(
      .settingsWindow(.dictionary(.delegate(.quickAddPersistenceFailed("disk full")))),
    )
    await store.receive(.pill(.dictionarySaveFailed)) {
      $0.pill.noticeGeneration = 1
      $0.pill.presentation = .notice(.dictionarySaveFailed)
    }
    await store.send(.pill(.dismiss)) {
      $0.pill.presentation = nil
    }
  }

  @Test func `a failed load blocks every mutation and leaves malformed bytes untouched`(
  ) async throws {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "dictionary-\(UUID().uuidString)", directoryHint: .isDirectory,
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appending(path: "dictionary.json")
    let malformed = Data("{ definitely not json".utf8)
    try malformed.write(to: url)

    let state = withDependencies {
      $0.defaultFileStorage = .fileSystem
    } operation: {
      DictionaryFeature.State(
        dictionary: Shared(
          wrappedValue: .empty,
          .fileStorage(url, decode: DictionaryCoding.decode, encode: DictionaryCoding.encode),
        ),
      )
    }
    let store = TestStore(initialState: state) { DictionaryFeature() } withDependencies: {
      $0.defaultFileStorage = .fileSystem
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    #expect(store.state.loadFailure != nil)
    let refusalReason = try #require(store.state.refusalReason)
    await store.send(.quickAddSubmitted(word: "TCA", misspelling: ""))
    await store.receive(.delegate(.quickAddPersistenceFailed(refusalReason)))
    #expect(store.state.dictionary == .empty)
    #expect(store.state.persistenceFailure == nil)
    #expect(try Data(contentsOf: url) == malformed)
  }
}
