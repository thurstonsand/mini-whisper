import ComposableArchitecture
import Foundation
import OSLog
import SpeechDictionary

private let dictionaryLogger = Logger(
  subsystem: "com.thurstonsand.MiniWhisper", category: "dictionary",
)

// MARK: - DictionaryFieldCopy

enum DictionaryFieldCopy {
  static let word = "Word or phrase"
  static let correction = "Correct spelling"
  static let misspelling = "Misspelling"
}

// MARK: - DictionaryFeature

@Reducer struct DictionaryFeature {
  // MARK: Internal

  enum Sort: String, CaseIterable, Equatable {
    case newestFirst = "Newest First"
    case alphabetical = "Alphabetical"
  }

  enum EntryID: Hashable {
    case vocabulary(String)
    case correction(String)
  }

  struct Entry: Equatable, Identifiable {
    enum Kind: Equatable {
      case vocabulary
      case correction(misspelling: String)
    }

    var id: EntryID
    var text: String
    var addedAt: Date
    var kind: Kind
  }

  struct Draft: Equatable {
    var originalID: EntryID?
    var text = ""
    var misspelling = ""
    var isCorrection = false

    var canSave: Bool {
      !trimmedText.isEmpty && (!isCorrection || !trimmedMisspelling.isEmpty)
    }

    var trimmedText: String {
      text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedMisspelling: String {
      misspelling.trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }

  @ObservableState struct State: Equatable {
    // MARK: Lifecycle

    init(dictionary: Shared<DictionaryContents>) {
      _dictionary = dictionary
    }

    // MARK: Internal

    @Shared var dictionary: DictionaryContents
    var sort = Sort.newestFirst
    var cursor: EntryID?
    var draft: Draft?
    var persistenceFailure: String?

    var loadFailure: String? {
      $dictionary.loadError?.localizedDescription
    }

    var refusalReason: String? {
      loadFailure.map {
        "dictionary.json could not be loaded. Fix or remove it before making changes. \($0)"
      }
    }

    var entries: [Entry] {
      let vocabulary = dictionary.vocabulary.map {
        Entry(id: .vocabulary($0.text), text: $0.text, addedAt: $0.addedAt, kind: .vocabulary)
      }
      let corrections = dictionary.corrections.map {
        Entry(
          id: .correction($0.misspelling), text: $0.text, addedAt: $0.addedAt,
          kind: .correction(misspelling: $0.misspelling),
        )
      }
      switch sort {
      case .newestFirst:
        return (vocabulary + corrections).sorted {
          if $0.addedAt != $1.addedAt {
            return $0.addedAt > $1.addedAt
          }
          return $0.text.localizedCaseInsensitiveCompare($1.text) == .orderedAscending
        }
      case .alphabetical:
        return (vocabulary + corrections).sorted {
          let comparison = $0.text.localizedCaseInsensitiveCompare($1.text)
          if comparison != .orderedSame {
            return comparison == .orderedAscending
          }
          return $0.addedAt > $1.addedAt
        }
      }
    }

    var cursorEntry: Entry? {
      entries.first { $0.id == cursor } ?? entries.first
    }

    mutating func advanceCursor(past id: EntryID) {
      guard cursorEntry?.id == id,
            let index = entries.firstIndex(where: { $0.id == id })
      else {
        return
      }
      let survivors = entries.filter { $0.id != id }
      cursor = survivors.isEmpty ? nil : survivors[min(index, survivors.count - 1)].id
    }
  }

  enum CursorMovement: Equatable {
    case previous
    case next
  }

  enum Action: Equatable {
    case sortChanged(Sort)
    case cursorMoved(CursorMovement)
    case cursorHovered(EntryID)
    case addRequested
    case addShortcutPressed
    case editRequested(EntryID)
    case deleteRequested(EntryID)
    case cursorDeleteShortcutPressed
    case draftTextChanged(String)
    case draftMisspellingChanged(String)
    case draftCorrectionChanged(Bool)
    case draftCancelled
    case draftDeleteRequested
    case draftSaveRequested
    case draftSaveCompleted
    case quickAddSubmitted(word: String, misspelling: String)
    case persistenceFailed(PersistenceContext, String)
    case persistenceFailureDismissed
    case delegate(Delegate)

    // MARK: Internal

    enum Delegate: Equatable {
      case quickAddPersistenceFailed(String)
    }
  }

  enum PersistenceContext: Equatable {
    case pane
    case quickAdd
  }

  @Dependency(\.date.now) var now

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case let .sortChanged(sort):
        state.sort = sort
        return .none
      case let .cursorMoved(movement):
        let entries = state.entries
        guard let place = state.cursorEntry,
              let index = entries.firstIndex(where: { $0.id == place.id })
        else {
          return .none
        }
        let offset = movement == .next ? 1 : -1
        state.cursor = entries[min(max(index + offset, 0), entries.count - 1)].id
        return .none
      case let .cursorHovered(id):
        guard state.entries.contains(where: { $0.id == id }) else {
          return .none
        }
        state.cursor = id
        return .none
      case .addRequested,
           .addShortcutPressed:
        if let refusal = mutationsAreAllowed(&state, context: .pane).refusal {
          return refusal
        }
        state.draft = Draft()
        return .none
      case let .editRequested(id):
        if let refusal = mutationsAreAllowed(&state, context: .pane).refusal {
          return refusal
        }
        guard let entry = state.entries.first(where: { $0.id == id }) else {
          return .none
        }
        switch entry.kind {
        case .vocabulary:
          state.draft = Draft(originalID: id, text: entry.text)
        case let .correction(misspelling):
          state.draft = Draft(
            originalID: id, text: entry.text, misspelling: misspelling, isCorrection: true,
          )
        }
        return .none
      case let .deleteRequested(id):
        return delete(id, state: &state)
      case .cursorDeleteShortcutPressed:
        guard let id = state.cursorEntry?.id else {
          return .none
        }
        return delete(id, state: &state)
      case let .draftTextChanged(text):
        state.draft?.text = text
        return .none
      case let .draftMisspellingChanged(misspelling):
        state.draft?.misspelling = misspelling
        return .none
      case let .draftCorrectionChanged(isCorrection):
        state.draft?.isCorrection = isCorrection
        return .none
      case .draftCancelled:
        state.draft = nil
        return .none
      case .draftDeleteRequested:
        guard let id = state.draft?.originalID else {
          return .none
        }
        state.draft = nil
        return delete(id, state: &state)
      case .draftSaveRequested:
        if let refusal = mutationsAreAllowed(&state, context: .pane).refusal {
          return refusal
        }
        guard let draft = state.draft, draft.canSave else {
          return .none
        }
        state.$dictionary.withLock { dictionary in
          if let originalID = draft.originalID {
            remove(originalID, from: &dictionary)
          }
          upsert(draft, addedAt: addedAt(for: draft, state: state), in: &dictionary)
        }
        // An empty List must lay out its first hosted row before the sheet disappears. Combining
        // both structural changes leaves AppKit's cached first-cell height clipped until rebuild.
        return .merge(
          save(state.$dictionary, context: .pane),
          .run { send in
            await Task.yield()
            await send(.draftSaveCompleted)
          },
        )
      case .draftSaveCompleted:
        state.draft = nil
        return .none
      case let .quickAddSubmitted(word, misspelling):
        if let refusal = mutationsAreAllowed(&state, context: .quickAdd).refusal {
          return refusal
        }
        let draft = Draft(
          text: word, misspelling: misspelling,
          isCorrection: !misspelling.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        )
        guard draft.canSave else {
          return .none
        }
        state.$dictionary.withLock { upsert(draft, addedAt: now, in: &$0) }
        return save(state.$dictionary, context: .quickAdd)
      case let .persistenceFailed(context, message):
        dictionaryLogger.error("Dictionary failed to persist: \(message, privacy: .public)")
        switch context {
        case .pane:
          state.persistenceFailure = message
          return .none
        case .quickAdd:
          return .send(.delegate(.quickAddPersistenceFailed(message)))
        }
      case .persistenceFailureDismissed:
        state.persistenceFailure = nil
        return .none
      case .delegate:
        return .none
      }
    }
  }

  // MARK: Private

  private enum MutationPermission {
    case allowed
    case refused(Effect<Action>)

    // MARK: Internal

    var refusal: Effect<Action>? {
      switch self {
      case .allowed:
        nil
      case let .refused(effect):
        effect
      }
    }
  }

  private func delete(_ id: EntryID, state: inout State) -> Effect<Action> {
    if let refusal = mutationsAreAllowed(&state, context: .pane).refusal {
      return refusal
    }
    state.advanceCursor(past: id)
    state.$dictionary.withLock { dictionary in remove(id, from: &dictionary) }
    return save(state.$dictionary, context: .pane)
  }

  private func mutationsAreAllowed(
    _ state: inout State, context: PersistenceContext,
  ) -> MutationPermission {
    guard let refusalReason = state.refusalReason else {
      return .allowed
    }
    switch context {
    case .pane:
      state.persistenceFailure = refusalReason
      return .refused(.none)
    case .quickAdd:
      return .refused(.send(.delegate(.quickAddPersistenceFailed(refusalReason))))
    }
  }

  private func addedAt(for draft: Draft, state: State) -> Date {
    guard let originalID = draft.originalID,
          let original = state.entries.first(where: { $0.id == originalID })
    else {
      return now
    }
    return original.addedAt
  }

  private func save(
    _ dictionary: Shared<DictionaryContents>, context: PersistenceContext,
  ) -> Effect<Action> {
    .run { send in
      do { try await dictionary.save() } catch {
        await send(.persistenceFailed(context, error.localizedDescription))
      }
    }
  }
}

private func remove(_ id: DictionaryFeature.EntryID, from dictionary: inout DictionaryContents) {
  switch id {
  case let .vocabulary(text):
    dictionary.vocabulary.removeAll { $0.text.caseInsensitiveCompare(text) == .orderedSame }
  case let .correction(misspelling):
    dictionary.corrections.removeAll {
      $0.misspelling.caseInsensitiveCompare(misspelling) == .orderedSame
    }
  }
}

private func upsert(
  _ draft: DictionaryFeature.Draft, addedAt: Date, in dictionary: inout DictionaryContents,
) {
  if draft.isCorrection {
    if let index = dictionary.corrections.firstIndex(where: {
      $0.misspelling.caseInsensitiveCompare(draft.trimmedMisspelling) == .orderedSame
    }) {
      dictionary.corrections[index].misspelling = draft.trimmedMisspelling
      dictionary.corrections[index].text = draft.trimmedText
    } else {
      dictionary.corrections.append(
        CorrectionEntry(
          misspelling: draft.trimmedMisspelling, text: draft.trimmedText, addedAt: addedAt,
        ),
      )
    }
  } else if !dictionary.vocabulary.contains(where: {
    $0.text.caseInsensitiveCompare(draft.trimmedText) == .orderedSame
  }) {
    dictionary.vocabulary.append(VocabularyEntry(text: draft.trimmedText, addedAt: addedAt))
  }
}
