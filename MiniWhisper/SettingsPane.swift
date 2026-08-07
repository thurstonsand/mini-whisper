import AppSettings
import AudioCapture
import ComposableArchitecture
import HotkeyListener
import SwiftUI

// MARK: - SettingsPane

struct SettingsPane: View {
  let store: StoreOf<SettingsWindowFeature>

  var body: some View {
    Form {
      Section {
        ShortcutRow(store: store)
      } header: {
        Text("Shortcuts")
      } footer: {
        Text("Hold to dictate, or double-tap to keep recording hands free.")
      }

      Section("Microphone") {
        MicrophoneRow(store: store)
      }

      Section("Sounds") {
        ForEach(SoundCue.allCases, id: \.self) { cue in
          SoundRow(store: store, cue: cue)
        }
      }
    }
    .formStyle(.grouped)
    .focusEffectDisabled()
    // Playback leaves no mark on screen, so the pane carries one probe saying what was last heard.
    .accessibilityPaintState(
      AccessibilityID.settingsSoundPlayback, label: "Sound playback",
      value: store.settingsPane.lastPlayedSound ?? "None",
    )
    .task { store.send(.settingsPane(.task)) }
    .onDisappear { store.send(.settingsPane(.paneClosed)) }
  }
}

// MARK: - MicrophoneRow

private struct MicrophoneRow: View {
  // MARK: Internal

  let store: StoreOf<SettingsWindowFeature>

  var body: some View {
    LabeledContent("Input") {
      VStack(alignment: .trailing, spacing: 4) {
        HStack(spacing: 8) {
          MicrophoneLevelMeter(level: store.settingsPane.inputLevel)
          SettingsPopUpButton(
            options: options,
            selection: store.settingsPane.microphone,
            activation: store.settingsPane.microphoneActivation,
            onSelection: { store.send(.settingsPane(.microphoneSelected($0))) },
          )
          .fixedSize()
          .focusRing(store.state.showsSettingsRing(.microphone, target: .microphone))
          .accessibilityIdentifier(AccessibilityID.settingsMicrophonePicker)
          .accessibilityLabel("Microphone input")
        }

        if let unavailableName = store.settingsPane.unavailableMicrophoneName {
          let notice = "\(unavailableName) not connected. Using system default: \(defaultDeviceName)."
          Text(notice)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityElement()
            .accessibilityIdentifier(AccessibilityID.settingsMicrophoneUnavailable)
            .accessibilityLabel(notice)
        }
      }
    }
    .modifier(SettingsFormRow(store: store, row: .microphone))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(AccessibilityID.settingsMicrophoneRow)
    .accessibilityLabel("Microphone")
    .accessibilityPaintState(
      AccessibilityID.settingsMicrophoneRowState, label: "Microphone highlight",
      value: store.state.showsSettingsBar(.microphone) ? "Bar on" : "Bar off",
    )
  }

  // MARK: Private

  private var defaultDeviceName: String {
    store.settingsPane.inputDevices.defaultDevice?.name ?? "Unavailable"
  }

  /// A selection the machine cannot currently offer still gets an entry, carrying the stored
  /// value unchanged, so the popup can show what the user chose instead of quietly showing
  /// something else.
  private var options: [SettingsPopUpButton<MicrophoneSelection>.Option] {
    typealias Option = SettingsPopUpButton<MicrophoneSelection>.Option
    var options = [
      Option(value: .systemDefault, title: "System Default (\(defaultDeviceName))"),
    ]
    options.append(contentsOf: store.settingsPane.inputDevices.devices.map {
      Option(value: .device(uid: $0.uid, lastKnownName: $0.name), title: $0.name)
    })
    if let unavailableName = store.settingsPane.unavailableMicrophoneName {
      options.append(
        Option(
          value: store.settingsPane.microphone, title: "\(unavailableName) (Unavailable)",
        ),
      )
    }
    return options
  }
}

// MARK: - MicrophoneLevelMeter

private struct MicrophoneLevelMeter: View {
  // MARK: Internal

  let level: AudioLevel?

  var body: some View {
    AudioLevelBars(level: paintedLevel)
      .opacity(level == nil ? 0.5 : 1)
      .accessibilityHidden(true)
      .accessibilityPaintState(
        AccessibilityID.settingsMicrophoneLevel,
        label: level == nil ? "Microphone input level, inactive" : "Microphone input level",
        value: String(paintedLevel),
      )
  }

  // MARK: Private

  private var paintedLevel: Float {
    level?.normalizedPower ?? 0
  }
}

// MARK: - SettingsPopUpButton

/// The pane's one bridge to `NSPopUpButton`. SwiftUI's `Picker` cannot be opened from the keyboard
/// or dim an individual row, and both are settings-window grammar, so every pop-up here is this.
private struct SettingsPopUpButton<Value: Equatable>: NSViewRepresentable {
  struct Option: Equatable {
    // MARK: Lifecycle

    init(value: Value, title: String, isSecondary: Bool = false) {
      self.value = value
      self.title = title
      self.isSecondary = isSecondary
    }

    // MARK: Internal

    let value: Value
    let title: String
    let isSecondary: Bool
  }

  @MainActor final class Coordinator: NSObject {
    // MARK: Lifecycle

    init(activation: Int, onSelection: @escaping (Value) -> Void) {
      self.activation = activation
      self.onSelection = onSelection
    }

    // MARK: Internal

    var options: [Option] = []
    var activation: Int
    var onSelection: (Value) -> Void

    @objc func selectionChanged(_ sender: NSPopUpButton) {
      guard options.indices.contains(sender.indexOfSelectedItem) else {
        return
      }
      onSelection(options[sender.indexOfSelectedItem].value)
    }
  }

  let options: [Option]
  let selection: Value
  let activation: Int
  let onSelection: (Value) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(activation: activation, onSelection: onSelection)
  }

  func makeNSView(context: Context) -> NSPopUpButton {
    let button = NSPopUpButton(frame: .zero, pullsDown: false)
    button.target = context.coordinator
    button.action = #selector(Coordinator.selectionChanged(_:))
    return button
  }

  func updateNSView(_ button: NSPopUpButton, context: Context) {
    context.coordinator.options = options
    context.coordinator.onSelection = onSelection
    if button.itemTitles != options.map(\.title) {
      button.removeAllItems()
      for option in options {
        button.addItem(withTitle: option.title)
      }
    }
    if let selectedIndex = options.firstIndex(where: { $0.value == selection }) {
      button.selectItem(at: selectedIndex)
    }
    // A secondary choice dims only while it is the selection, so the collapsed control reads
    // quiet without the open menu ever showing a greyed row that looks disabled.
    for (index, option) in options.enumerated() where option.isSecondary {
      guard let item = button.item(at: index) else {
        continue
      }
      let wanted: NSAttributedString? =
        index == button.indexOfSelectedItem
          ? NSAttributedString(
            string: option.title, attributes: [.foregroundColor: NSColor.secondaryLabelColor],
          ) : nil
      if item.attributedTitle != wanted {
        item.attributedTitle = wanted
      }
    }
    // Only a click opens a pop-up button, so Return on this row arrives as a changed count.
    guard activation != context.coordinator.activation else {
      return
    }
    context.coordinator.activation = activation
    DispatchQueue.main.async { button.performClick(nil) }
  }
}

// MARK: - SoundRow

private struct SoundRow: View {
  // MARK: Internal

  let store: StoreOf<SettingsWindowFeature>
  let cue: SoundCue

  var body: some View {
    LabeledContent(cue.label) {
      HStack(spacing: 8) {
        SettingsPopUpButton(
          options: options, selection: selection,
          activation: store.settingsPane.soundActivations[cue, default: 0],
          onSelection: { store.send(.settingsPane(.soundSelected(cue, $0))) },
        )
        .fixedSize()
        .focusRing(store.state.showsSettingsRing(row, target: .soundPicker(cue)))
        .accessibilityIdentifier(AccessibilityID.settingsSound(cue, .picker))
        .accessibilityLabel("\(cue.label) sound")
        .accessibilityPaintState(
          AccessibilityID.settingsSound(cue, .pickerState),
          label: "\(cue.label) sound emphasis",
          value: selection == nil ? "Secondary" : "Primary",
        )

        Button("Play \(cue.label)", systemImage: "play.circle") {
          store.send(.settingsPane(.soundReplayRequested(cue)))
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .disabled(selection == nil)
        .focusRing(showsPreviewRing)
        .accessibilityIdentifier(AccessibilityID.settingsSound(cue, .preview))
        .accessibilityLabel("Preview \(cue.label.lowercased()) sound")
        .accessibilityValue(showsPreviewRing ? "Ring on" : "Ring off")
      }
    }
    .modifier(SettingsFormRow(store: store, row: row))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(AccessibilityID.settingsSound(cue, .row))
    .accessibilityLabel(cue.label)
    .accessibilityPaintState(
      AccessibilityID.settingsSound(cue, .rowState), label: "\(cue.label) highlight",
      value: store.state.showsSettingsBar(row) ? "Bar on" : "Bar off",
    )
  }

  // MARK: Private

  private var row: SettingsPaneFeature.Row {
    .sound(cue)
  }

  private var selection: String? {
    store.settingsPane.sounds[cue]
  }

  private var showsPreviewRing: Bool {
    store.state.showsSettingsRing(row, target: .soundPreview(cue))
  }

  /// The inventory is whatever the system reports, but a cue's own default and its current choice
  /// are always offered: neither returning to default nor seeing where you are may be starved.
  private var options: [SettingsPopUpButton<String?>.Option] {
    var names = Set(store.settingsPane.soundNames)
    names.insert(cue.defaultName)
    if let selection {
      names.insert(selection)
    }
    let sorted = names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    // Silence leads, dimmed: it is the absence of a choice rather than one more sound.
    return [.init(value: nil, title: "No audio", isSecondary: true)]
      + sorted.map {
        .init(value: $0, title: $0 == cue.defaultName ? "\($0) (default)" : $0)
      }
  }
}

// MARK: - ShortcutRow

private struct ShortcutRow: View {
  // MARK: Internal

  let store: StoreOf<SettingsWindowFeature>

  var body: some View {
    LabeledContent("Activate") {
      VStack(alignment: .trailing, spacing: 4) {
        HStack {
          ForEach(Array(hotkeys.enumerated()), id: \.offset) { index, hotkey in
            bindingButton(index: index, hotkey: hotkey)
          }
          if store.settingsPane.bindings.target == .new {
            recordingChip
          }
          if hotkeys.isEmpty, !store.settingsPane.bindings.isRecording {
            emptyState
          }
          ShortcutMoreMenu(store: store)
        }
        if let message = store.settingsPane.bindings.validationMessage {
          Text(message)
            .font(.caption)
            .foregroundStyle(.orange)
            .accessibilityIdentifier(AccessibilityID.settingsShortcutRecordingError)
        }
      }
    }
    .modifier(SettingsFormRow(store: store, row: .activate))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(AccessibilityID.settingsShortcutRow)
    .accessibilityLabel("Activate shortcut")
    .accessibilityPaintState(
      AccessibilityID.settingsShortcutRowState, label: "Activate shortcut highlight",
      value: store.state.showsSettingsBar(.activate) ? "Bar on" : "Bar off",
    )
  }

  // MARK: Private

  private var hotkeys: [Hotkey] {
    store.settingsPane.bindings.hotkeys
  }

  /// A recording in flight shows the chord as it is built, and says so before there is one.
  private var recordingComponents: [String] {
    store.settingsPane.bindings.liveChord?.displayComponents ?? ["Recording…"]
  }

  private var recordingTitle: String {
    store.settingsPane.bindings.liveChord?.displayName ?? "Recording…"
  }

  private var recordingChip: some View {
    HotkeyKeycaps(components: recordingComponents, ringed: showsRing(.recording))
      .accessibilityElement()
      .accessibilityIdentifier(AccessibilityID.settingsShortcutRecording)
      .accessibilityLabel(recordingTitle)
      .accessibilityValue(showsRing(.recording) ? "Ring on" : "Ring off")
  }

  @ViewBuilder private var emptyState: some View {
    Text("Not set").foregroundStyle(.secondary)
    Button("Set…") { store.send(.settingsPane(.bindings(.addTapped))) }
      .focusRing(showsRing(.set))
      .accessibilityIdentifier(AccessibilityID.settingsShortcutSet)
      .accessibilityValue(showsRing(.set) ? "Ring on" : "Ring off")
  }

  private func bindingButton(index: Int, hotkey: Hotkey) -> some View {
    let isRecording = store.settingsPane.bindings.isRecording(index)
    let target = SettingsPaneFeature.Target.binding(index)
    return Button {
      store.send(.settingsPane(.bindings(.bindingTapped(index))))
    } label: {
      HotkeyKeycaps(
        components: isRecording ? recordingComponents : hotkey.displayComponents,
        ringed: showsRing(target),
      )
    }
    .buttonStyle(.plain)
    .accessibilityLabel(isRecording ? recordingTitle : hotkey.displayName)
    .accessibilityIdentifier(
      isRecording
        ? AccessibilityID.settingsShortcutRecording
        : AccessibilityID.settingsShortcutBinding(index),
    )
    .accessibilityValue(showsRing(target) ? "Ring on" : "Ring off")
  }

  private func showsRing(_ target: SettingsPaneFeature.Target) -> Bool {
    store.state.showsSettingsRing(.activate, target: target)
  }
}

// MARK: - SettingsFormRow

/// The row cursor: a 3pt accent bar, moved by the keyboard and by the pointer alike. Hover is
/// reported rather than kept locally, because only the window can know that one row wearing the
/// bar means every other row is not.
private struct SettingsFormRow: ViewModifier {
  let store: StoreOf<SettingsWindowFeature>
  let row: SettingsPaneFeature.Row

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
          .opacity(store.state.showsSettingsBar(row) ? 1 : 0)
          .animation(.easeOut(duration: 0.12), value: store.state.showsSettingsBar(row))
      }
      .listRowInsets(EdgeInsets())
      .contentShape(.rect)
      .windowPointerMovement(store: store) {
        store.send(.settingsPane(.cursorHovered(row)))
      }
  }
}

// MARK: - ShortcutMoreMenu

private struct ShortcutMoreMenu: View {
  // MARK: Internal

  let store: StoreOf<SettingsWindowFeature>

  var body: some View {
    Menu {
      Button("Add Another…", systemImage: "plus") {
        store.send(.settingsPane(.bindings(.addTapped)))
      }
      if !hotkeys.isEmpty {
        Divider()
        ForEach(Array(hotkeys.enumerated()), id: \.offset) {
          index, hotkey in
          Button("Remove \(hotkey.displayName)", systemImage: "xmark", role: .destructive) {
            store.send(.settingsPane(.bindings(.removeTapped(index))))
          }
        }
      }
    } label: {
      Label("More", systemImage: "ellipsis").labelStyle(.iconOnly)
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .disabled(store.settingsPane.bindings.isRecording)
    .focusable(false)
    .accessibilityIdentifier(AccessibilityID.settingsShortcutMenu)
    .accessibilityLabel("Shortcut actions")
  }

  // MARK: Private

  private var hotkeys: [Hotkey] {
    store.settingsPane.bindings.hotkeys
  }
}
