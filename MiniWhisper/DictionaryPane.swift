import ComposableArchitecture
import SwiftUI

// MARK: - DictionaryPane

struct DictionaryPane: View {
  // MARK: Internal

  @Bindable var store: StoreOf<SettingsWindowFeature>

  var body: some View {
    List {
      ForEach(store.dictionary.entries) { entry in
        DictionaryRow(store: store, entry: entry)
      }
    }
    .stableSettingsListRowHeight()
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
    .alert("Dictionary could not be saved", isPresented: persistenceFailurePresented) {
      Button("OK") { store.send(.dictionary(.persistenceFailureDismissed)) }
    } message: {
      Text(store.dictionary.persistenceFailure ?? "Unknown error")
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

  private var persistenceFailurePresented: Binding<Bool> {
    Binding(
      get: { store.dictionary.persistenceFailure != nil },
      set: {
        if !$0 {
          store.send(.dictionary(.persistenceFailureDismissed))
        }
      },
    )
  }

  @ViewBuilder private var emptyState: some View {
    if store.dictionary.loadFailure != nil {
      ContentUnavailableView(
        "Dictionary Unavailable", systemImage: "exclamationmark.triangle",
        description: Text(
          "dictionary.json could not be read. Fix or remove the file before editing.",
        ),
      )
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
        Text(entry.text).lineLimit(1)
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
    .padding(.horizontal, 6)
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
      value: "Grey \(showsGrey ? "on" : "off"); Cursor \(showsKeyboardCursor ? "on" : "off")",
    )
  }

  // MARK: Private

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
    Form {
      Section {
        Toggle("Correction", isOn: correctionBinding)
      }

      Section(store.dictionary.draft?.isCorrection == true ? "Correction" : "Word") {
        if store.dictionary.draft?.isCorrection == true {
          TextField(DictionaryFieldCopy.misspelling, text: misspellingBinding)
            .onSubmit { save() }
            .accessibilityIdentifier(AccessibilityID.dictionaryMisspelling)
          TextField(DictionaryFieldCopy.correction, text: textBinding)
            .onSubmit { save() }
            .accessibilityIdentifier(AccessibilityID.dictionaryText)
        } else {
          TextField(DictionaryFieldCopy.word, text: textBinding)
            .onSubmit { save() }
            .accessibilityIdentifier(AccessibilityID.dictionaryText)
        }
      }
    }
    .formStyle(.grouped)
    .frame(width: 420, height: 300)
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
