import AppSettings
import ComposableArchitecture
import SpeechDictionary
import SwiftUI

// MARK: - DictionaryPane

struct DictionaryPane: View {
  // MARK: Internal

  @Bindable var store: StoreOf<SettingsWindowFeature>

  var body: some View {
    Form {
      Section {
        ForEach(store.dictionary.entries) { entry in
          DictionaryRow(store: store, entry: entry)
        }
      } footer: {
        if !store.dictionary.profiles.activeProfile.usesVocabulary,
           !store.dictionary.dictionary.vocabulary.isEmpty
        {
          VStack(alignment: .leading, spacing: 8) {
            Text(
              "Vocabulary isn’t used by \(store.dictionary.profiles.activeProfile.name). Corrections still apply.",
            )
            .font(.callout.weight(.regular))
            .foregroundStyle(.secondary)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            Button("Open Vocabulary Settings…") {
              store.send(.dictionary(.showVocabularySettings))
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("miniwhisper.dictionary.vocabulary-settings")
          }
        }
      }
    }
    .formStyle(.grouped)
    .focusEffectDisabled()
    .keyboardCursorScroll(store: store, cursor: store.dictionary.cursor)
    .overlay { emptyState }
    .toolbar {
      Picker("Sort", selection: $store.dictionary.sort.sending(\.dictionary.sortChanged)) {
        ForEach(DictionaryFeature.Sort.allCases, id: \.self) { sort in
          Text(sort.rawValue).tag(sort)
        }
      }
      .labelsHidden()
      .pickerStyle(.menu)

      Button("Add Entry", systemImage: "plus") {
        store.send(.dictionary(.addRequested))
      }
      .disabled(store.dictionary.refusalReason != nil)
      .accessibilityIdentifier(AccessibilityID.dictionaryAdd)
    }
    .sheet(isPresented: draftPresented) {
      DictionaryEditSheet(store: store)
    }
    .safeAreaBar(edge: .bottom) {
      if let failure = store.dictionary.persistenceFailure, store.dictionary.loadFailure == nil {
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text("Changes haven’t been saved.")
            Text(failure).font(.callout).foregroundStyle(.secondary)
          }
          Spacer()
          Button("Retry Save") { store.send(.dictionary(.retrySaveRequested)) }
        }
        .padding()
      }
    }
  }

  // MARK: Private

  private var draftPresented: Binding<Bool> {
    Binding(
      get: { store.dictionary.draft != nil },
      set: {
        if !$0 {
          store.send(.dictionary(.draftCancelled))
        }
      },
    )
  }

  @ViewBuilder private var emptyState: some View {
    if store.dictionary.loadFailure != nil {
      ContentUnavailableView {
        Label("Dictionary Unavailable", systemImage: "exclamationmark.triangle")
      } description: {
        Text(
          "dictionary.json couldn’t be read. Back it up before repairing or removing it. Removing it resets saved words and corrections.",
        )
      } actions: {
        Button("Show in Finder") { store.send(.dictionary(.revealFileRequested)) }
        Button("Try Again") { store.send(.dictionary(.reloadRequested)) }
      }
    } else if store.dictionary.entries.isEmpty {
      ContentUnavailableView(
        "No Dictionary Entries", systemImage: "character.book.closed",
        description: Text("Add words and corrections to improve your transcripts."),
      )
    }
  }
}

// MARK: - DictionaryRow

private struct DictionaryRow: View {
  // MARK: Internal

  let store: StoreOf<SettingsWindowFeature>
  let entry: DictionaryFeature.Entry

  var body: some View {
    HStack(spacing: 8) {
      switch entry.kind {
      case .vocabulary:
        Text(entry.text)
          .foregroundStyle(usesReducedEmphasis ? .secondary : .primary)
          .lineLimit(1)
      case let .correction(misspelling):
        Text(misspelling)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        Image(systemName: "arrow.right")
          .foregroundStyle(.tertiary)
          .accessibilityHidden(true)
        Text(entry.text).lineLimit(1)
      }

      Spacer(minLength: 8)

      if isPointed || showsKeyboardCursor {
        Button("Delete", systemImage: "trash", role: .destructive) {
          store.send(.dictionary(.deleteRequested(entry.id)))
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .help("Delete")
        .accessibilityIdentifier(AccessibilityID.dictionaryDelete(entry.id))
      }
    }
    .settingsListRowHeight()
    .background {
      RoundedRectangle(cornerRadius: 8)
        .fill(.quaternary)
        .opacity(showsGrey ? 1 : 0)
    }
    .contentShape(.rect)
    .onTapGesture {
      store.send(.pointerMoved)
      store.send(.dictionary(.editRequested(entry.id)))
    }
    .windowPointerMovement(store: store) {
      store.send(.dictionary(.cursorHovered(entry.id)))
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(AccessibilityID.dictionaryRow(entry.id))
    .accessibilityLabel(accessibilityLabel)
    .accessibilityPaintState(
      AccessibilityID.dictionaryRowState(entry.id), label: "Dictionary row highlight",
      value: "Grey \(showsGrey ? "on" : "off"); Cursor \(showsKeyboardCursor ? "on" : "off"); Emphasis \(usesReducedEmphasis ? "reduced" : "normal")",
    )
  }

  // MARK: Private

  private var usesReducedEmphasis: Bool {
    store.dictionary.usesReducedEmphasis(entry)
  }

  private var isPointed: Bool {
    store.interaction.mode == .mouse && store.interaction.focus == .detail
      && store.dictionary.cursor == entry.id
  }

  private var showsGrey: Bool {
    isPointed || showsKeyboardCursor
  }

  private var showsKeyboardCursor: Bool {
    store.state.showsDictionaryKeyboardCursor(entry.id)
  }

  private var accessibilityLabel: String {
    switch entry.kind {
    case .vocabulary:
      entry.text
    case let .correction(misspelling):
      "\(misspelling), corrected to \(entry.text)"
    }
  }
}

// MARK: - DictionaryEditSheet

private struct DictionaryEditSheet: View {
  // MARK: Internal

  @Bindable var store: StoreOf<SettingsWindowFeature>

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Picker("Entry type", selection: correctionBinding) {
        Text("Word").tag(false)
        Text("Correction").tag(true)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .accessibilityIdentifier("miniwhisper.dictionary.entry-type")
      if store.dictionary.draft?.isCorrection == true {
        VStack(alignment: .leading) {
          Text("Replace")
          TextField("Replace", text: misspellingBinding)
            .labelsHidden()
            .onSubmit { save() }
            .focused($focus, equals: .misspelling)
            .task {
              await Task.yield()
              focus = .misspelling
            }
            .accessibilityIdentifier(AccessibilityID.dictionaryMisspelling)
        }
        VStack(alignment: .leading) {
          Text("With")
          TextField("With", text: textBinding)
            .labelsHidden()
            .onSubmit { save() }
            .accessibilityIdentifier(AccessibilityID.dictionaryText)
        }
      } else {
        VStack(alignment: .leading) {
          Text(DictionaryFieldCopy.word)
          TextField(DictionaryFieldCopy.word, text: textBinding)
            .labelsHidden()
            .onSubmit { save() }
            .focused($focus, equals: .word)
            .task {
              await Task.yield()
              focus = .word
            }
            .accessibilityIdentifier(AccessibilityID.dictionaryText)
        }
      }
    }
    .textFieldStyle(.roundedBorder)
    .multilineTextAlignment(.leading)
    .padding(20)
    .frame(width: 420)
    .fixedSize(horizontal: false, vertical: true)
    .safeAreaBar(edge: .top) {
      Text(title)
        .font(.headline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
    .safeAreaBar(edge: .bottom) {
      HStack {
        if store.dictionary.draft?.originalID != nil {
          Button("Delete", systemImage: "trash", role: .destructive) {
            store.send(.dictionary(.draftDeleteRequested))
          }
        }
        Spacer()
        Button("Cancel", role: .cancel) { store.send(.dictionary(.draftCancelled)) }
          .keyboardShortcut(.cancelAction)
        Button("Save") { store.send(.dictionary(.draftSaveRequested)) }
          .keyboardShortcut(.defaultAction)
          .disabled(store.dictionary.draft?.canSave != true)
          .accessibilityIdentifier(AccessibilityID.dictionarySave)
          .accessibilityLabel("Save dictionary entry")
      }
      .padding(.horizontal)
      .padding(.vertical, 10)
    }
  }

  // MARK: Private

  private enum Field: Hashable {
    case word
    case misspelling
  }

  @FocusState private var focus: Field?

  private var title: String {
    store.dictionary.draft?.originalID == nil ? "Add Entry" : "Edit Entry"
  }

  private var textBinding: Binding<String> {
    Binding(
      get: { store.dictionary.draft?.text ?? "" },
      set: { store.send(.dictionary(.draftTextChanged($0))) },
    )
  }

  private var misspellingBinding: Binding<String> {
    Binding(
      get: { store.dictionary.draft?.misspelling ?? "" },
      set: { store.send(.dictionary(.draftMisspellingChanged($0))) },
    )
  }

  private var correctionBinding: Binding<Bool> {
    Binding(
      get: { store.dictionary.draft?.isCorrection ?? false },
      set: { store.send(.dictionary(.draftCorrectionChanged($0))) },
    )
  }

  private func save() {
    store.send(.dictionary(.draftSaveRequested))
  }
}
