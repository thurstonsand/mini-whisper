import AppSettings
import ComposableArchitecture
import Foundation
import History
@testable import MiniWhisper
import SpeechDictionary
import Testing

@MainActor struct SettingsWindowTests {
  @Test func `destinations follow the settled order`() {
    #expect(
      SettingsDestination.allCases == [
        .settings,
        .history,
        .dictionary,
        .profiles,
        .models,
        .about,
      ],
    )
  }

  @Test func `fine-grained store cursor queries agree with state across modes and fallbacks`(
  ) throws {
    let firstID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    let secondID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
    let missingID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000099"))
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let log = HistoryLog(entries: [
      HistoryEntry(
        id: firstID,
        createdAt: now,
        targetApp: nil,
        original: Transcription(text: "First", engine: "parakeet", transcribedAt: now),
        delivery: Delivery(text: "First", method: .pasted, detail: nil),
        audio: nil,
      ),
      HistoryEntry(
        id: secondID,
        createdAt: now.addingTimeInterval(-10),
        targetApp: nil,
        original: Transcription(text: "Second", engine: "parakeet", transcribedAt: now),
        delivery: Delivery(text: "Second", method: .pasted, detail: nil),
        audio: nil,
      ),
    ])
    let dictionary = DictionaryContents(
      vocabulary: [
        VocabularyEntry(text: "Alpha", addedAt: now),
        VocabularyEntry(text: "Beta", addedAt: now.addingTimeInterval(-10)),
      ],
      corrections: [],
    )
    let store = Store(
      initialState: SettingsWindowFeature.State(
        history: Shared(value: log),
        settings: Shared(value: .defaults),
        dictionary: Shared(value: dictionary),
        health: Shared(value: .healthy),
      ),
    ) {
      SettingsWindowFeature()
    }

    // Sidebar focus hides all detail cursors.
    store.send(.focusChanged(.sidebar))
    store.send(.keyboardModeEntered)
    #expect(!store.showsHistoryKeyboardCursor(firstID))
    #expect(!store.showsDictionaryKeyboardCursor(.vocabulary("Alpha")))
    #expect(!store.showsSettingsBar(.shortcut(.activate)))

    // Detail + keyboard falls back to the first entry when cursor is unset or stale.
    store.send(.focusChanged(.detail))
    #expect(store.showsHistoryKeyboardCursor(firstID))
    #expect(!store.showsHistoryKeyboardCursor(secondID))
    #expect(store.showsDictionaryKeyboardCursor(.vocabulary("Alpha")))
    #expect(!store.showsDictionaryKeyboardCursor(.vocabulary("Beta")))

    store.send(.history(.cursorMoved(.next)))
    #expect(!store.showsHistoryKeyboardCursor(firstID))
    #expect(store.showsHistoryKeyboardCursor(secondID))

    // Stale cursor (filtered out by search) falls back to the first matching row.
    store.send(.history(.searchChanged("First")))
    #expect(store.showsHistoryKeyboardCursor(firstID))
    #expect(!store.showsHistoryKeyboardCursor(secondID))
    #expect(!store.showsHistoryKeyboardCursor(missingID))

    // Mouse mode keeps bars on Settings but hides keyboard cursor rings/highlights.
    store.send(.pointerMoved)
    #expect(!store.showsHistoryKeyboardCursor(firstID))
    #expect(!store.showsDictionaryKeyboardCursor(.vocabulary("Alpha")))
    #expect(store.showsSettingsBar(.shortcut(.activate)))
    #expect(!store.showsSettingsRing(.shortcut(.activate), target: .binding(.activate, 0)))
  }
}
