import ComposableArchitecture
import SwiftUI
import TranscriptCleanup

// MARK: - CleanupPane

struct CleanupPane: View {
  // MARK: Internal

  let store: StoreOf<SettingsWindowFeature>

  var body: some View {
    Form {
      Section {
        EnabledRow(store: store)
        TimeoutRow(store: store)
      }

      Section {
        EndpointRow(store: store)
        APIKeyRow(store: store)
        ModelRow(store: store)
        if cleanup.modelChoice == .custom {
          CustomModelRow(store: store)
        }
      } header: {
        Text("Endpoint")
      } footer: {
        VStack(alignment: .leading, spacing: 4) {
          SaveFailureLine(store: store)
          // The promise belongs where the address, the key, and the model were just entrusted:
          // under the button that sends them.
          Text(
            """
            Transcripts are sent to this endpoint. Recorded audio never leaves this Mac. \
            If cleanup fails or runs past the limit, the transcript is delivered as heard.
            """,
          )
        }
      }
      .disabled(!cleanup.isEnabled)

      Section("Custom prompt") {
        InstructionsRow(store: store)
      }
      .disabled(!cleanup.isEnabled)
    }
    .formStyle(.grouped)
    .focusEffectDisabled()
    .keyboardCursorScroll(store: store, cursor: cleanup.cursorRow)
    // Whether a field is being typed in decides whether the window's letters are the pane's
    // grammar, and nothing else on screen says which it is.
    .accessibilityPaintState(
      AccessibilityID.cleanupEditing, label: "Cleanup editing",
      value: cleanup.editingField.map { "Editing \($0)" } ?? "Idle",
    )
    .task { store.send(.cleanup(.task)) }
  }

  // MARK: Private

  private var cleanup: CleanupFeature.State {
    store.cleanup
  }
}

// MARK: - EnabledRow

private struct EnabledRow: View {
  let store: StoreOf<SettingsWindowFeature>

  var body: some View {
    let showsRing = store.state.showsCleanupRing(.enabled, target: .enabled)
    Toggle(
      "Clean up transcripts",
      isOn: Binding(
        get: { store.cleanup.isEnabled },
        set: { store.send(.cleanup(.enabledToggled($0))) },
      ),
    )
    .toggleStyle(.switch)
    .focusRing(showsRing)
    .accessibilityIdentifier(AccessibilityID.cleanupEnabled)
    .accessibilityLabel("Clean up transcripts")
    .modifier(CleanupFormRow(store: store, row: .enabled))
    .accessibilityPaintState(
      AccessibilityID.cleanupEnabledRing, label: "Clean up transcripts ring",
      value: showsRing ? "Ring on" : "Ring off",
    )
  }
}

// MARK: - TimeoutRow

private struct TimeoutRow: View {
  // MARK: Internal

  let store: StoreOf<SettingsWindowFeature>

  var body: some View {
    LabeledContent("Give up after") {
      SettingsPopUpButton(
        options: options, selection: store.cleanup.timeout,
        activation: store.cleanup.timeoutActivation,
        onSelection: { store.send(.cleanup(.timeoutSelected($0))) },
      )
      .fixedSize()
      .focusRing(store.state.showsCleanupRing(.timeout, target: .timeout))
      .accessibilityIdentifier(AccessibilityID.cleanupTimeout)
      .accessibilityLabel("Give up after")
    }
    .disabled(!store.cleanup.isEnabled)
    .modifier(CleanupFormRow(store: store, row: .timeout))
  }

  // MARK: Private

  private var options: [SettingsPopUpButton<TimeInterval>.Option] {
    CleanupFeature.State.timeoutPresets.map {
      .init(value: $0, title: "\(Int($0)) seconds")
    }
  }
}

// MARK: - EndpointRow

private struct EndpointRow: View {
  let store: StoreOf<SettingsWindowFeature>

  var body: some View {
    LabeledContent("Address") {
      CleanupTextField(
        value: store.cleanup.endpointText, prompt: "https://gateway.example/v1",
        identifier: AccessibilityID.cleanupEndpoint, label: "Endpoint address",
        activation: store.cleanup.endpointActivation,
        isRinged: store.state.showsCleanupRing(.endpoint, target: .endpoint),
        onChange: { store.send(.cleanup(.endpointEdited($0))) },
        onFocusChange: { store.send(.cleanup(.fieldFocusChanged(.endpoint, $0))) },
      )
    }
    .modifier(CleanupFormRow(store: store, row: .endpoint))
  }
}

// MARK: - APIKeyRow

/// Replacing a stored key is a fresh field rather than an editable one, so selection, ⌘A, and
/// paste all behave; Save is what stores it.
private struct APIKeyRow: View {
  // MARK: Internal

  let store: StoreOf<SettingsWindowFeature>

  var body: some View {
    LabeledContent("API key") {
      switch store.cleanup.key {
      case let .stored(prefix):
        HStack {
          SemanticText(
            masked(prefix), identifier: AccessibilityID.cleanupKeyStored, label: "Stored API key",
          )
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          Button("Replace") { store.send(.cleanup(.replaceKeyTapped)) }
            .focusRing(store.state.showsCleanupRing(.apiKey, target: .replaceKey))
            .accessibilityIdentifier(AccessibilityID.cleanupKeyReplace)
        }
      case let .editing(text):
        keyField(text)
      case .missing,
           .unknown:
        keyField("")
      }
    }
    .modifier(CleanupFormRow(store: store, row: .apiKey))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(AccessibilityID.cleanupKeyRow)
    .accessibilityLabel("API key")
  }

  // MARK: Private

  private func keyField(_ text: String) -> some View {
    CleanupTextField(
      value: text, prompt: "Paste your key", identifier: AccessibilityID.cleanupKeyField,
      label: "API key", activation: store.cleanup.keyActivation,
      claimsFocus: store.cleanup.keyActivation > 0,
      isRinged: store.state.showsCleanupRing(.apiKey, target: .apiKey),
      onChange: { store.send(.cleanup(.keyEdited($0))) },
      onFocusChange: { store.send(.cleanup(.fieldFocusChanged(.apiKey, $0))) },
    )
  }

  private func masked(_ prefix: String) -> String {
    prefix + String(repeating: "•", count: 12)
  }
}

// MARK: - ModelRow

/// Listing is best effort: plenty of gateways never implement `/v1/models`, so a failed listing
/// says so beside a Custom field that is already open, rather than leaving an empty menu that
/// reads as "you may not enter a model".
private struct ModelRow: View {
  // MARK: Internal

  let store: StoreOf<SettingsWindowFeature>

  var body: some View {
    LabeledContent("Model") {
      HStack(spacing: 8) {
        if let caption {
          SemanticText(
            caption, identifier: AccessibilityID.cleanupModelListing, label: "Model listing",
          )
          .font(.callout)
          .foregroundStyle(.secondary)
          Spacer(minLength: 0)
        }
        SettingsPopUpButton(
          options: options, selection: store.cleanup.modelChoice,
          activation: store.cleanup.modelActivation,
          onSelection: { store.send(.cleanup(.modelSelected($0))) },
        )
        .fixedSize()
        .focusRing(store.state.showsCleanupRing(.model, target: .model))
        .accessibilityIdentifier(AccessibilityID.cleanupModel)
        .accessibilityLabel("Model")

        Button("Load Models") { store.send(.cleanup(.loadModelsTapped)) }
          .disabled(store.cleanup.listing == .loading)
          .focusRing(store.state.showsCleanupRing(.model, target: .loadModels))
          .accessibilityIdentifier(AccessibilityID.cleanupLoadModels)

        SaveButton(store: store)
      }
    }
    .modifier(CleanupFormRow(store: store, row: .model))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(AccessibilityID.cleanupModelRow)
    .accessibilityLabel("Model")
  }

  // MARK: Private

  private var caption: String? {
    switch store.cleanup.listing {
    case .loading:
      "Loading…"
    case let .unavailable(reason):
      reason
    case .loaded,
         .notLoaded:
      nil
    }
  }

  private var options: [SettingsPopUpButton<CleanupFeature.ModelChoice>.Option] {
    store.cleanup.listedModels.map { .init(value: .listed($0), title: $0) }
      + [.init(value: .custom, title: "Custom…")]
  }
}

// MARK: - CustomModelRow

private struct CustomModelRow: View {
  // MARK: Internal

  let store: StoreOf<SettingsWindowFeature>

  var body: some View {
    LabeledContent("Model ID") {
      TextField(
        "", text: Binding(
          get: { store.cleanup.customModel },
          set: { store.send(.cleanup(.customModelEdited($0))) },
        ),
        prompt: Text("gpt-oss-120b"),
      )
      .labelsHidden()
      .focused($isFocused)
      .focusRing(store.state.showsCleanupRing(.customModel, target: .customModel))
      .accessibilityIdentifier(AccessibilityID.cleanupCustomModel)
      .accessibilityLabel("Model ID")
      .onChange(of: store.cleanup.modelActivation) { isFocused = true }
    }
    .modifier(CleanupFormRow(store: store, row: .customModel))
  }

  // MARK: Private

  @FocusState private var isFocused: Bool
}

// MARK: - SaveButton

/// One button, one place, three meanings: nothing to save, something to save, saved. The slot is
/// as wide as its widest word, so the row it sits in never moves — the state changes, the layout
/// does not. A failure is not a state of the button: there is still something to save, so it
/// stays armed and the sentence goes under the table.
private struct SaveButton: View {
  // MARK: Internal

  let store: StoreOf<SettingsWindowFeature>

  var body: some View {
    // Prominent is a claim on the user's attention, and only an unsaved edit has one to make.
    if button.isPressable {
      base.buttonStyle(.borderedProminent)
    } else {
      base.buttonStyle(.bordered)
    }
  }

  // MARK: Private

  private var button: CleanupFeature.SaveButton {
    store.cleanup.saveButton
  }

  private var base: some View {
    Button(button.title) { store.send(.cleanup(.saveTapped)) }
      .frame(minWidth: 76)
      .disabled(!button.isPressable)
      .focusRing(store.state.showsCleanupRing(.model, target: .save))
      .accessibilityIdentifier(AccessibilityID.cleanupSave)
  }
}

// MARK: - SaveFailureLine

/// What Save answered when it could not finish, under the table it answers for and above the
/// promises it belongs with. Red, trailing, and absent whenever there is nothing to report.
private struct SaveFailureLine: View {
  let store: StoreOf<SettingsWindowFeature>

  var body: some View {
    if case let .failed(reason) = store.cleanup.save {
      SemanticText(reason, identifier: AccessibilityID.cleanupSaveResult, label: "Save result")
        .foregroundStyle(.red)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
  }
}

// MARK: - InstructionsRow

private struct InstructionsRow: View {
  // MARK: Internal

  /// Written the way it asks to be written: plain sentences about how the text should read, not
  /// instructions to a machine.
  static let example = "keep it casual — lowercase greetings, don’t expand my contractions"

  let store: StoreOf<SettingsWindowFeature>

  var body: some View {
    TextEditor(text: $text)
      .font(.body)
      .frame(minHeight: 64)
      .focused($isFocused)
      // TextEditor has no prompt of its own, so the example is drawn behind it and takes no
      // clicks — it is a suggestion, never something the user has to clear.
      .overlay(alignment: .topLeading) {
        if text.isEmpty {
          Text(Self.example)
            .font(.body)
            .foregroundStyle(.tertiary)
            .padding(.top, 8)
            .padding(.leading, 5)
            .allowsHitTesting(false)
        }
      }
      .focusRing(store.state.showsCleanupRing(.instructions, target: .instructions))
      .accessibilityIdentifier(AccessibilityID.cleanupInstructions)
      .accessibilityLabel("Custom prompt")
      .onAppear { text = store.cleanup.instructions }
      .onChange(of: text) { _, edited in
        guard edited != store.cleanup.instructions else {
          return
        }
        store.send(.cleanup(.instructionsEdited(edited)))
      }
      .onChange(of: store.cleanup.instructionsActivation) { isFocused = true }
      .onChange(of: isFocused) { _, focused in
        store.send(.cleanup(.fieldFocusChanged(.instructions, focused)))
      }
      .onExitCommand { isFocused = false }
      .modifier(CleanupFormRow(store: store, row: .instructions))
  }

  // MARK: Private

  @State private var text = ""
  @FocusState private var isFocused: Bool
}

// MARK: - CleanupTextField

/// A field the editor owns while it is being typed in. Round-tripping every keystroke through the
/// store re-renders the field mid-edit and drops characters under fast input, so the store is told
/// what was typed and only speaks back when it changes the value itself — Save conforming an
/// address, or Replace clearing a key.
private struct CleanupTextField: View {
  // MARK: Internal

  let value: String
  let prompt: String
  let identifier: String
  let label: String
  let activation: Int
  /// A field that was opened by a press rather than merely shown: the press already meant "type
  /// here", and the activation that carried it landed before this view existed to hear it.
  var claimsFocus = false
  let isRinged: Bool
  let onChange: (String) -> Void
  let onFocusChange: (Bool) -> Void

  var body: some View {
    TextField("", text: $text, prompt: Text(prompt))
      .labelsHidden()
      .focused($isFocused)
      // The yield puts the assignment after AppKit has chosen its own first responder; without
      // it the field is not yet built and the assignment lands nowhere.
      .task {
        guard claimsFocus else {
          return
        }
        await Task.yield()
        isFocused = true
      }
      .focusRing(isRinged)
      .accessibilityIdentifier(identifier)
      .accessibilityLabel(label)
      .onAppear { text = value }
      // A field handed its own stored value is not the user typing: reporting that echo back as
      // an edit is what would arm Save the moment the pane opened.
      .onChange(of: text) { _, edited in
        guard edited != value else {
          return
        }
        onChange(edited)
      }
      .onChange(of: value) { _, stored in
        if stored != text {
          text = stored
        }
      }
      .onChange(of: activation) { isFocused = true }
      .onChange(of: isFocused) { _, focused in onFocusChange(focused) }
      // Escape leaves the field rather than beeping at a window whose grammar it interrupted.
      .onExitCommand { isFocused = false }
  }

  // MARK: Private

  @State private var text = ""
  @FocusState private var isFocused: Bool
}

// MARK: - CleanupFormRow

/// The pane's half of the cursor grammar: the accent bar for the row the cursor stands on, and a
/// hover that moves it, exactly as the Settings pane paints its own rows.
private struct CleanupFormRow: ViewModifier {
  let store: StoreOf<SettingsWindowFeature>
  let row: CleanupFeature.Row

  func body(content: Content) -> some View {
    content
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .background(alignment: .leading) {
        Capsule()
          .fill(Color.accentColor)
          .frame(width: 3)
          .padding(.vertical, 4)
          .padding(.leading, 4)
          .opacity(store.state.showsCleanupBar(row) ? 1 : 0)
          .animation(.easeOut(duration: 0.12), value: store.state.showsCleanupBar(row))
      }
      .listRowInsets(EdgeInsets())
      .contentShape(.rect)
      .id(row)
      .windowPointerMovement(store: store) {
        store.send(.cleanup(.cursorHovered(row)))
      }
      .accessibilityPaintState(
        AccessibilityID.cleanupRowState(row), label: "\(row) highlight",
        value: store.state.showsCleanupBar(row) ? "Bar on" : "Bar off",
      )
  }
}
