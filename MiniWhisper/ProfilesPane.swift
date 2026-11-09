import AppKit
import AppSettings
import ASREngine
import ComposableArchitecture
import ModelLibrary
import SwiftUI
import TranscriptCleanup

// MARK: - ProfilesPane

/// The active profile, whole: the picker that chooses it, what it runs on, and the endpoint facts
/// that can change, read-only until Edit opens them together.
struct ProfilesPane: View {
  // MARK: Internal

  let store: StoreOf<SettingsWindowFeature>

  var body: some View {
    Form {
      GroupBox {
        VStack(alignment: .leading, spacing: 16) {
          PickerRow(store: store)
          Divider()
          VStack(alignment: .leading, spacing: 12) {
            Text("Speech recognition").font(.headline)
            speechRows
          }
          Divider()
          VStack(alignment: .leading, spacing: 12) {
            Text("Cleanup").font(.headline)
            cleanupRows
          }
        }
      }

      if profiles.showsTimeout || profiles.hasPromptSurface {
        Section {
          if profiles.showsTimeout {
            TimeoutRow(store: store)
          }
          if profiles.hasPromptSurface {
            InstructionsRow(store: store)
          }
        } footer: {
          if profiles.showsTimeout {
            Text("If cleanup takes too long, the original transcript is delivered.")
          }
        }
      }
    }
    .formStyle(.grouped)
    .focusEffectDisabled()
    .keyboardCursorScroll(store: store, cursor: profiles.cursorRow)
    // Whether a field is being typed in decides whether the window's letters are the pane's
    // grammar, and nothing else on screen says which it is.
    .accessibilityPaintState(
      AccessibilityID.profilesEditing, label: "Profiles editing",
      value: profiles.editingField.map { "Editing \($0)" } ?? "Idle",
    )
    .task { store.send(.profiles(.task)) }
    .onDisappear { store.send(.profiles(.paneDisappeared)) }
  }

  // MARK: Private

  private var profiles: ProfilesFeature.State {
    store.profiles
  }

  private var profile: Profile {
    profiles.profile
  }

  @ViewBuilder private var speechRows: some View {
    LabeledContent("Engine") {
      HStack {
        Text(profile.engine.name)
        ForEach(profile.engine.assets, id: \.self) { asset in
          ProfileAssetControl(store: store, asset: asset, row: .engine)
        }
      }
    }
    .accessibilityIdentifier(AccessibilityID.profilesEngine)
    .modifier(ProfilesFormRow(store: store, row: .engine))
    if let slot = profiles.engineCredential {
      if let editor = profiles.editor {
        KeyFieldRow(
          store: store, editor: editor, field: .engineKey, row: .engineKey, slot: slot,
          text: editor.engineKeyText,
        ) { store.send(.profiles(.engineKeyEdited($0))) }
          .disabled(editor.isChecking)
      } else {
        StoredKeyRow(store: store, slot: slot, field: .engineKey)
      }
      if profiles.showsSpeechConnection {
        SpeechConnectionRows(store: store)
        Text(
          "Other speech endpoints are checked with one second of silence. The provider may charge for it.",
        )
        .font(.callout)
        .foregroundStyle(.secondary)
      } else {
        AdvancedRow(store: store, speech: true)
      }
    }
    if profile.isCustom {
      BoostsVocabularyRow(store: store)
    }
  }

  @ViewBuilder private var cleanupRows: some View {
    if profile.cleanup == .local {
      LabeledContent("Model") {
        HStack {
          Text("S1-mini")
            .accessibilityIdentifier(AccessibilityID.profilesLocalCleanup)
          ProfileAssetControl(store: store, asset: .s1Mini, row: .localCleanup)
        }
      }
      .modifier(ProfilesFormRow(store: store, row: .localCleanup))
    }
    if profile.isCustom, profiles.isSetUp {
      EnabledRow(store: store)
    }
    if profile.endpointLeg != nil {
      if let editor = profiles.editor {
        EditorRows(store: store, editor: editor)
      } else if profiles.isSetUp {
        RestingRows(store: store).disabled(profile.cleanup == .none)
      } else {
        NotSetUpRows(store: store)
      }
    }
  }
}

// MARK: - PickerRow

/// The picker names the profile and marks anything it still needs.
private struct PickerRow: View {
  // MARK: Internal

  let store: StoreOf<SettingsWindowFeature>

  var body: some View {
    LabeledContent("Profile") {
      SettingsPopUpButton(
        options: options, selection: store.profiles.profile.id,
        activation: store.profiles.profileActivation,
        isRinged: store.state.showsProfilesRing(.profile, target: .profile),
        onSelection: { store.send(.profiles(.profileSelected($0))) },
      )
      .fixedSize()
      .accessibilityIdentifier(AccessibilityID.profilesPicker)
      .accessibilityLabel("Profile")
      .accessibilityValue(summary(store.profiles.profile))
    }
    .modifier(ProfilesFormRow(store: store, row: .profile))
  }

  // MARK: Private

  private var options: [SettingsPopUpButton<ProfileID>.Option] {
    store.profiles.settings.profiles.lineup.map { profile in
      .init(
        value: profile.id, title: profile.name, symbol: profile.symbol,
        status: store.profiles.status(of: profile).option,
      )
    }
  }

  private func summary(_ profile: Profile) -> String {
    switch store.profiles.status(of: profile) {
    case .ready:
      profile.name
    case let .problem(text),
         let .note(text):
      "\(profile.name); \(text)"
    }
  }
}

private extension ProfilesFeature.Status {
  var option: SettingsPopUpButton<ProfileID>.Option.Status? {
    switch self {
    case .ready:
      nil
    case let .problem(text):
      .init(text: text, isProblem: true)
    case let .note(text):
      .init(text: text, isProblem: false)
    }
  }
}

// MARK: - ProfileAssetControl

private struct ProfileAssetControl: View {
  let store: StoreOf<SettingsWindowFeature>
  let asset: ModelAsset
  let row: ProfilesFeature.Row

  var body: some View {
    switch store.profiles.assets[asset] {
    case let .downloading(fraction):
      ProgressView(value: fraction)
        .frame(width: 100)
        .accessibilityLabel("Downloading \(asset.name)")
    case .missing,
         .failed:
      Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
      Button(asset == .gate ? "Download Speech Gate" : "Download") {
        store.send(.profiles(.downloadTapped(asset)))
      }
      .focusRing(store.state.showsProfilesRing(row, target: .download(asset)))
      .accessibilityIdentifier("miniwhisper.profiles.\(asset.rawValue).download")
    case .installed,
         nil:
      EmptyView()
    }
  }
}

// MARK: - RestingRows

/// The endpoint as it is saved. Every value is read-only, and every button opens the same editor
/// with its own field focused.
private struct RestingRows: View {
  let store: StoreOf<SettingsWindowFeature>

  var body: some View {
    if let leg = store.profiles.profile.endpointLeg {
      if !store.profiles.profile.isCustom {
        StoredKeyRow(store: store, slot: leg.credential, field: .apiKey)
      }
      ConnectionRows(store: store) {
        ValueRow(
          store: store, field: .endpoint, label: "Address",
          value: EndpointAddress.display(leg.endpoint), edit: "Edit",
          isOverridden: store.profiles.profile.isEndpointOverridden,
        )
        if store.profiles.profile.isCustom {
          StoredKeyRow(store: store, slot: leg.credential, field: .apiKey)
        }
        ValueRow(
          store: store, field: .model, label: "Model", value: leg.model ?? "", edit: "Edit",
          isOverridden: store.profiles.profile.isModelOverridden,
        )
      }
    }
  }
}

// MARK: - ConnectionRows

/// Factory profiles already know their endpoint and model; Custom asks for both up front.
private struct ConnectionRows<Content: View>: View {
  let store: StoreOf<SettingsWindowFeature>
  @ViewBuilder let content: Content

  var body: some View {
    if store.profiles.showsCleanupConnection {
      content
    } else {
      AdvancedRow(store: store, speech: false)
    }
  }
}

// MARK: - AdvancedRow

private struct AdvancedRow: View {
  let store: StoreOf<SettingsWindowFeature>
  let speech: Bool

  var body: some View {
    HStack {
      Spacer()
      Button("Advanced") {
        store.send(.profiles(speech ? .speechAdvancedRevealed : .advancedRevealed))
      }
      .buttonStyle(.bordered)
      .accessibilityIdentifier(speech ? "miniwhisper.profiles.speech-advanced" : AccessibilityID
        .profilesAdvanced)
      .focusRing(store.state.showsProfilesRing(
        speech ? .speechAdvanced : .advanced,
        target: speech ? .speechAdvanced : .advanced,
      ))
    }
    .accessibilityElement(children: .contain)
    .modifier(ProfilesFormRow(store: store, row: speech ? .speechAdvanced : .advanced))
  }
}

// MARK: - SpeechConnectionRows

private struct SpeechConnectionRows: View {
  // MARK: Internal

  let store: StoreOf<SettingsWindowFeature>

  var body: some View {
    if let editor = store.profiles.editor {
      field(.engineEndpoint, row: .engineEndpoint, label: "Speech URL",
            value: editor.engineEndpointText, editor: editor)
      {
        store.send(.profiles(.engineEndpointEdited($0)))
      }
      field(.engineModel, row: .engineModel, label: "Speech model",
            value: editor.engineModel, editor: editor)
      {
        store.send(.profiles(.engineModelEdited($0)))
      }
    } else {
      ValueRow(store: store, field: .engineEndpoint, label: "Speech URL",
               value: store.profiles.settings.profiles.scribeConfiguration.endpoint.absoluteString,
               edit: "Edit",
               isOverridden: store.profiles.settings.profiles.scribeOverride?.endpoint != nil)
      ValueRow(store: store, field: .engineModel, label: "Speech model",
               value: store.profiles.settings.profiles.scribeConfiguration.model,
               edit: "Edit",
               isOverridden: store.profiles.settings.profiles.scribeOverride?.model != nil)
    }
  }

  // MARK: Private

  private func field(_ field: ProfilesFeature.Field, row: ProfilesFeature.Row, label: String,
                     value: String, editor: ProfilesFeature.Editor,
                     onChange: @escaping (String) -> Void) -> some View
  {
    LabeledContent(label) {
      VStack(alignment: .leading, spacing: 4) {
        ProfilesTextField(
          value: value, prompt: "", identifier: AccessibilityID.profilesField(field), label: label,
          focus: .init(request: editor.focusRequest, isRequested: editor.focus == field),
          isRinged: store.state.showsProfilesRing(row, target: .field(field)),
          onChange: onChange,
          onFocusChange: { store.send(.profiles(.fieldFocusChanged(row, $0))) },
        )
        FailureLine(editor: editor, field: field)
      }
    }
    .disabled(editor.isChecking)
    .modifier(ProfilesFormRow(store: store, row: row))
  }
}

// MARK: - StoredKeyRow

private struct StoredKeyRow: View {
  // MARK: Internal

  let store: StoreOf<SettingsWindowFeature>
  let slot: CredentialSlot
  let field: ProfilesFeature.Field

  var body: some View {
    ValueRow(
      store: store, field: field, label: keyLabel(slot), value: value,
      edit: store.profiles.storedKeys?[slot] == nil ? "Add" : "Replace", isOverridden: false,
    )
    if store.profiles.health.rejectedKeys.contains(slot) {
      Text("\(slot.provider.displayName) rejected this key.")
        .font(.callout)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("miniwhisper.profiles.key-rejection")
    }
  }

  // MARK: Private

  private var value: String {
    guard let prefix = store.profiles.storedKeys?[slot] else {
      return store.profiles.storedKeys == nil ? "" : "None"
    }
    return prefix + String(repeating: "•", count: 12)
  }
}

// MARK: - ValueRow

/// A saved value, the button that changes it, and, only while it differs from the factory's, the
/// icon that puts it back. The icon sits after the button so Edit never moves.
private struct ValueRow: View {
  // MARK: Internal

  let store: StoreOf<SettingsWindowFeature>
  let field: ProfilesFeature.Field
  let label: String
  let value: String
  let edit: String
  let isOverridden: Bool

  var body: some View {
    let row = store.profiles.row(for: field)
    LabeledContent(label) {
      HStack(spacing: 8) {
        if isProblem {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .accessibilityHidden(true)
        }
        SemanticText(value, identifier: AccessibilityID.profilesValue(field), label: label)
          .foregroundStyle(isProblem ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
          .lineLimit(1)
          .truncationMode(.middle)
        Button(edit) { store.send(.profiles(.editTapped(field))) }
          .focusRing(store.state.showsProfilesRing(row, target: .edit(field)))
          .accessibilityIdentifier(AccessibilityID.profilesEdit(field))
          .accessibilityLabel("\(edit) \(label)")
        if isOverridden {
          Button {
            store.send(.profiles(.resetTapped(field)))
          } label: {
            Image(systemName: "arrow.counterclockwise")
          }
          .buttonStyle(.borderless)
          .help("Reset to Default")
          .focusRing(store.state.showsProfilesRing(row, target: .reset(field)))
          .accessibilityIdentifier(AccessibilityID.profilesReset(field))
          .accessibilityLabel("Reset to Default")
        }
      }
    }
    .modifier(ProfilesFormRow(store: store, row: row))
  }

  // MARK: Private

  /// A key the endpoint refused reads invalid where it is stored, as well as in the picker.
  private var isProblem: Bool {
    field == .apiKey && store.profiles.credential.map(store.profiles.health.rejectedKeys.contains)
      == true
  }
}

// MARK: - NotSetUpRows

/// Custom before its first Save: nothing to show, and one way to start.
private struct NotSetUpRows: View {
  let store: StoreOf<SettingsWindowFeature>

  var body: some View {
    // Labelled, because a form row holding nothing but a button is made that button, frame and
    // all, and the click lands in the middle of the row.
    LabeledContent("Clean up transcripts") {
      Button("Set Up…") { store.send(.profiles(.editTapped(.endpoint))) }
        .focusRing(store.state.showsProfilesRing(.actions, target: .setUp))
        .accessibilityIdentifier(AccessibilityID.profilesSetUp)
    }
    .modifier(ProfilesFormRow(store: store, row: .actions))
  }
}

// MARK: - EditorRows

/// Save proves the whole draft, including any factory overrides hidden under Advanced.
/// While the check runs the fields hold still; Cancel stays live to stop it.
private struct EditorRows: View {
  // MARK: Internal

  let store: StoreOf<SettingsWindowFeature>
  let editor: ProfilesFeature.Editor

  var body: some View {
    Group {
      if !store.profiles.profile.isCustom {
        key
      }
      ConnectionRows(store: store) {
        LabeledContent("Address") {
          VStack(alignment: .leading, spacing: 4) {
            ProfilesTextField(
              value: editor.endpointText, prompt: "https://gateway.example/v1",
              identifier: AccessibilityID.profilesField(.endpoint), label: "Address",
              focus: focus(.endpoint),
              isRinged: store.state.showsProfilesRing(.endpoint, target: .field(.endpoint)),
              onChange: { store.send(.profiles(.endpointEdited($0))) },
              onFocusChange: { store.send(.profiles(.fieldFocusChanged(.endpoint, $0))) },
            )
            FailureLine(editor: editor, field: .endpoint)
          }
        }
        .modifier(ProfilesFormRow(store: store, row: .endpoint))
        if store.profiles.profile.isCustom {
          key
        }
        ModelRow(store: store, editor: editor)
        if editor.modelChoice == .custom {
          LabeledContent("Model ID") {
            VStack(alignment: .leading, spacing: 4) {
              ProfilesTextField(
                value: editor.customModel, prompt: "gpt-oss-120b",
                identifier: AccessibilityID.profilesCustomModel, label: "Model ID",
                focus: focus(.model),
                isRinged: store.state.showsProfilesRing(.customModel, target: .customModel),
                onChange: { store.send(.profiles(.customModelEdited($0))) },
                onFocusChange: { store.send(.profiles(.fieldFocusChanged(.customModel, $0))) },
              )
              FailureLine(editor: editor, field: .model)
            }
          }
          .modifier(ProfilesFormRow(store: store, row: .customModel))
        }
      }
    }
    .disabled(editor.isChecking)
    ActionsRow(store: store, editor: editor)
  }

  // MARK: Private

  @ViewBuilder private var key: some View {
    if let slot = store.profiles.credential {
      KeyFieldRow(
        store: store, editor: editor, field: .apiKey, row: .apiKey, slot: slot,
        text: editor.keyText,
      ) { store.send(.profiles(.keyEdited($0))) }
    }
  }

  private func focus(_ field: ProfilesFeature.Field) -> ProfilesTextField.Focus {
    .init(request: editor.focusRequest, isRequested: editor.focus == field)
  }
}

// MARK: - KeyFieldRow

/// A key is typed fresh rather than edited in place, because a half-edited secret is a secret that
/// no longer works. Left empty, the stored key stays.
private struct KeyFieldRow: View {
  let store: StoreOf<SettingsWindowFeature>
  let editor: ProfilesFeature.Editor
  let field: ProfilesFeature.Field
  let row: ProfilesFeature.Row
  let slot: CredentialSlot
  let text: String
  let onChange: (String) -> Void

  var body: some View {
    let stored = store.profiles.storedKeys?[slot]
    LabeledContent {
      VStack(alignment: .leading, spacing: 4) {
        ProfilesTextField(
          value: text,
          prompt: stored.map { $0 + String(repeating: "•", count: 12) } ?? slot.provider.keyPrompt,
          identifier: AccessibilityID.profilesField(field), label: keyLabel(slot),
          focus: .init(request: editor.focusRequest, isRequested: editor.focus == field),
          isRinged: store.state.showsProfilesRing(row, target: .field(field)),
          onChange: onChange,
          onFocusChange: { store.send(.profiles(.fieldFocusChanged(row, $0))) },
        )
        FailureLine(editor: editor, field: field)
      }
    } label: {
      Text(keyLabel(slot))
      if stored != nil {
        Text("Leave empty to keep")
      } else if slot.provider == .endpoint {
        Text("Optional")
      }
    }
    .modifier(ProfilesFormRow(store: store, row: row))
  }
}

// MARK: - ModelRow

/// Listing is best effort: plenty of gateways never implement `/v1/models`, so a failed listing
/// says so beside a Custom field that is already open, rather than leaving an empty menu that
/// reads as "you may not enter a model".
private struct ModelRow: View {
  // MARK: Internal

  let store: StoreOf<SettingsWindowFeature>
  let editor: ProfilesFeature.Editor

  var body: some View {
    LabeledContent("Model") {
      VStack(alignment: .trailing, spacing: 4) {
        HStack(spacing: 8) {
          if let caption {
            SemanticText(
              caption, identifier: AccessibilityID.profilesModelListing, label: "Model listing",
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            Spacer(minLength: 0)
          }
          SettingsPopUpButton(
            options: options, selection: editor.modelChoice,
            activation: store.profiles.modelActivation,
            isRinged: store.state.showsProfilesRing(.model, target: .field(.model)),
            onSelection: { store.send(.profiles(.modelSelected($0))) },
          )
          .fixedSize()
          .accessibilityIdentifier(AccessibilityID.profilesModel)
          .accessibilityLabel("Model")
          Button("Load Models") { store.send(.profiles(.loadModelsTapped)) }
            .disabled(editor.listing == .loading)
            .focusRing(store.state.showsProfilesRing(.model, target: .loadModels))
            .accessibilityIdentifier(AccessibilityID.profilesLoadModels)
        }
        if editor.modelChoice != .custom {
          FailureLine(editor: editor, field: .model)
        }
      }
    }
    .modifier(ProfilesFormRow(store: store, row: .model))
  }

  // MARK: Private

  private var caption: String? {
    switch editor.listing {
    case .loading:
      "Loading…"
    case let .unavailable(reason):
      reason
    case .loaded,
         .notLoaded:
      nil
    }
  }

  private var options: [SettingsPopUpButton<ProfilesFeature.ModelChoice>.Option] {
    editor.listedModels.map { .init(value: .listed($0), title: $0) }
      + [.init(value: .custom, title: "Custom…")]
  }
}

// MARK: - ActionsRow

private struct ActionsRow: View {
  let store: StoreOf<SettingsWindowFeature>
  let editor: ProfilesFeature.Editor

  var body: some View {
    HStack(spacing: 8) {
      Spacer()
      if editor.isChecking {
        ProgressView()
          .controlSize(.small)
        SemanticText(
          "Checking…", identifier: AccessibilityID.profilesChecking, label: "Checking",
        )
        .foregroundStyle(.secondary)
      }
      Button("Cancel") { store.send(.profiles(.cancelTapped)) }
        .focusRing(store.state.showsProfilesRing(.actions, target: .cancel))
        .accessibilityIdentifier(AccessibilityID.profilesCancel)
      Button("Save") { store.send(.profiles(.saveTapped)) }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .disabled(editor.isChecking)
        .focusRing(store.state.showsProfilesRing(.actions, target: .save))
        .accessibilityIdentifier(AccessibilityID.profilesSave)
    }
    .modifier(ProfilesFormRow(store: store, row: .actions))
  }
}

// MARK: - FailureLine

/// What Save could not prove, under the one field it blames.
private struct FailureLine: View {
  let editor: ProfilesFeature.Editor
  let field: ProfilesFeature.Field

  var body: some View {
    if let failure = editor.failure, failure.field == field {
      SemanticText(failure.message, identifier: AccessibilityID.profilesFailure, label: "Failure")
        .font(.callout)
        .foregroundStyle(.red)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

// MARK: - EnabledRow

private struct EnabledRow: View {
  let store: StoreOf<SettingsWindowFeature>

  var body: some View {
    let showsRing = store.state.showsProfilesRing(.enabled, target: .enabled)
    LabeledContent("Clean up transcripts") {
      SettingsSwitch(
        isOn: store.profiles.settings.profiles.custom.cleanupEnabled, label: "Clean up transcripts",
        identifier: AccessibilityID.profilesEnabled,
        onChange: { store.send(.profiles(.enabledToggled($0))) },
      )
      .focusRing(showsRing)
    }
    .modifier(ProfilesFormRow(store: store, row: .enabled))
    .accessibilityPaintState(
      AccessibilityID.profilesEnabledRing, label: "Clean up transcripts ring",
      value: showsRing ? "Ring on" : "Ring off",
    )
  }
}

// MARK: - BoostsVocabularyRow

/// With cleanup off the sidecar is the only way the dictionary reaches the transcript, so it says
/// nothing; with cleanup on, the model already reads the dictionary and the sidecar mostly adds
/// traps, which is worth one quiet line.
private struct BoostsVocabularyRow: View {
  let store: StoreOf<SettingsWindowFeature>

  var body: some View {
    let custom = store.profiles.settings.profiles.custom
    LabeledContent {
      SettingsSwitch(
        isOn: custom.boostsVocabulary, label: "Boost vocabulary",
        identifier: AccessibilityID.profilesBoostsVocabulary,
        onChange: { store.send(.profiles(.boostsVocabularyToggled($0))) },
      )
      .focusRing(store.state.showsProfilesRing(.boostsVocabulary, target: .boostsVocabulary))
    } label: {
      Text("Boost vocabulary")
      if custom.boostsVocabulary, store.profiles.profile.cleanup != .none {
        Label(
          "Cleanup usually handles your dictionary better without this.",
          systemImage: "exclamationmark.triangle",
        )
        .accessibilityIdentifier(AccessibilityID.profilesBoostWarning)
      }
    }
    .modifier(ProfilesFormRow(store: store, row: .boostsVocabulary))
  }
}

// MARK: - TimeoutRow

private struct TimeoutRow: View {
  // MARK: Internal

  let store: StoreOf<SettingsWindowFeature>

  var body: some View {
    LabeledContent("Cleanup timeout") {
      SettingsPopUpButton(
        options: options, selection: store.profiles.timeout,
        activation: store.profiles.timeoutActivation,
        isRinged: store.state.showsProfilesRing(.timeout, target: .timeout),
        onSelection: { store.send(.profiles(.timeoutSelected($0))) },
      )
      .fixedSize()
      .accessibilityIdentifier(AccessibilityID.profilesTimeout)
      .accessibilityLabel("Cleanup timeout")
    }
    .modifier(ProfilesFormRow(store: store, row: .timeout))
  }

  // MARK: Private

  private var options: [SettingsPopUpButton<TimeInterval>.Option] {
    ProfilesFeature.State.timeoutPresets.map {
      .init(value: $0, title: "\(Int($0)) seconds")
    }
  }
}

// MARK: - InstructionsRow

private struct InstructionsRow: View {
  let store: StoreOf<SettingsWindowFeature>

  var body: some View {
    // A growing text field rather than a `TextEditor`: only a real prompt sits exactly where the
    // cursor does, and `TextEditor` has none. Stacked rather than a `LabeledContent`, which sizes
    // the field to its text and right-aligns it, so every keystroke resized the box until the
    // first wrap flipped the row into this layout anyway.
    VStack(alignment: .leading) {
      Text("Additional instructions")
      ProfilesTextField(
        value: store.profiles.instructions, prompt: "",
        identifier: AccessibilityID.profilesInstructions, label: "Additional instructions",
        focus: .init(
          request: store.profiles.instructionsActivation, isRequested: true,
          claimsOnAppear: false,
        ),
        reservedLines: 3,
        isRinged: store.state.showsProfilesRing(.instructions, target: .instructions),
        onChange: { store.send(.profiles(.instructionsEdited($0))) },
        onFocusChange: { store.send(.profiles(.fieldFocusChanged(.instructions, $0))) },
      )
      .multilineTextAlignment(.leading)
    }
    .modifier(ProfilesFormRow(store: store, row: .instructions))
  }
}

// MARK: - ProfilesTextField

/// A field the editor owns while it is being typed in. Round-tripping every keystroke through the
/// store re-renders the field mid-edit and drops characters under fast input, so the store is told
/// what was typed and only speaks back when it changes the value itself — Save conforming an
/// address, or a listing discovering where the API lives.
private struct ProfilesTextField: View {
  // MARK: Internal

  /// A field takes the keys when the store asks for it by name, or when it is built already
  /// asked for: the press that opened the editor landed before this view existed to hear it.
  struct Focus {
    let request: Int
    let isRequested: Bool
    var claimsOnAppear = true
  }

  let value: String
  let prompt: String
  let identifier: String
  let label: String
  let focus: Focus
  /// A multiline field grows vertically, reserving this many lines and scrolling past them.
  var reservedLines: Int?
  let isRinged: Bool
  let onChange: (String) -> Void
  let onFocusChange: (Bool) -> Void

  var body: some View {
    field
      .labelsHidden()
      .textFieldStyle(.roundedBorder)
      .focused($isFocused)
      // The yield puts the assignment after AppKit has chosen its own first responder; without
      // it the field is not yet built and the assignment lands nowhere.
      .task {
        guard focus.claimsOnAppear, focus.isRequested else {
          return
        }
        await Task.yield()
        isFocused = true
      }
      .focusRing(isRinged)
      .accessibilityIdentifier(identifier)
      .accessibilityLabel(label)
      .onAppear { text = value }
      // A field handed its own stored value is not the user typing.
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
      .onChange(of: focus.request) {
        if focus.isRequested {
          isFocused = true
        }
      }
      .onChange(of: isFocused) { _, focused in onFocusChange(focused) }
      // Escape leaves the field rather than beeping at a window whose grammar it interrupted.
      .onExitCommand { isFocused = false }
  }

  // MARK: Private

  @State private var text = ""
  @FocusState private var isFocused: Bool

  @ViewBuilder private var field: some View {
    let field = TextField(
      "", text: $text, prompt: Text(prompt), axis: reservedLines == nil ? .horizontal : .vertical,
    )
    if let reservedLines {
      field
        .lineLimit(reservedLines, reservesSpace: true)
        // Return still ends the edit. ⇧↩ asks the field editor itself for a literal newline, so
        // it lands at the caret like any typed character rather than being spliced into `text`.
        .onKeyPress(.return, phases: .down) { press in
          guard press.modifiers == .shift else {
            return .ignored
          }
          NSApp.sendAction(
            #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)), to: nil, from: nil,
          )
          return .handled
        }
    } else {
      field
    }
  }
}

// MARK: - ProfilesFormRow

/// The pane's half of the cursor grammar: the accent bar for the row the cursor stands on, and a
/// hover that moves it, exactly as the Settings pane paints its own rows.
private struct ProfilesFormRow: ViewModifier {
  let store: StoreOf<SettingsWindowFeature>
  let row: ProfilesFeature.Row

  func body(content: Content) -> some View {
    content
      .overlay(alignment: .leading) {
        Capsule()
          .fill(Color.accentColor)
          .frame(width: 3)
          .padding(.vertical, 4)
          .offset(x: -10)
          .opacity(store.state.showsProfilesBar(row) ? 1 : 0)
          .animation(.easeOut(duration: 0.12), value: store.state.showsProfilesBar(row))
      }
      .contentShape(.rect)
      .id(row)
      .windowPointerMovement(store: store) {
        store.send(.profiles(.cursorHovered(row)))
      }
      .accessibilityPaintState(
        AccessibilityID.profilesRowState(row), label: "\(row) highlight",
        value: store.state.showsProfilesBar(row) ? "Bar on" : "Bar off",
      )
  }
}

/// A factory key is named for who issued it; Custom's is whatever its endpoint calls one.
private func keyLabel(_ slot: CredentialSlot) -> String {
  slot.provider == .endpoint ? "API key" : "\(slot.provider.displayName) key"
}
