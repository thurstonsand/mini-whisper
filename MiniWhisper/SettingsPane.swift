import AppSettings
import ASREngine
import AudioCapture
import ComposableArchitecture
import HotkeyListener
import SwiftUI

// MARK: - SettingsPane

struct SettingsPane: View {
  let store: StoreOf<SettingsWindowFeature>

  var body: some View {
    Form {
      // Only while there is something to say: an empty Section is still a box on screen, and a
      // settings window does not need a permanent row reporting that nothing is wrong.
      let health = store.settingsPane.health
      if !health.degradations.isEmpty || health.engineReadiness.isSetupInProgress {
        Section {
          ForEach(health.degradations, id: \.self) { degradation in
            RepairRow(store: store, degradation: degradation)
          }
          if health.engineReadiness != .ready {
            EngineStatusRow(store: store)
          }
        }
      }

      Section {
        ForEach(HotkeyCommand.allCases, id: \.self) { command in
          ShortcutRow(store: store, command: command)
        }
      } header: {
        Text("Shortcuts")
      } footer: {
        Text("Activation shortcuts: hold to dictate, or double-tap to keep recording hands free.")
      }

      Section("Microphone") {
        MicrophoneRow(store: store)
      }

      Section("Sounds") {
        ForEach(SoundCue.allCases, id: \.self) { cue in
          SoundRow(store: store, cue: cue)
        }
      }

      Section {
        LaunchAtLoginRow(store: store)
      }
    }
    .formStyle(.grouped)
    .focusEffectDisabled()
    .keyboardCursorScroll(store: store, cursor: store.settingsPane.cursorRow)
    // Playback leaves no mark on screen, so the pane carries one probe saying what was last heard.
    .accessibilityPaintState(
      AccessibilityID.settingsSoundPlayback, label: "Sound playback",
      value: store.settingsPane.lastPlayedSound ?? "None",
    )
    .task { store.send(.settingsPane(.task)) }
    .onDisappear { store.send(.settingsPane(.paneClosed)) }
  }
}

// MARK: - EngineStatusRow

private struct EngineStatusRow: View {
  let store: StoreOf<SettingsWindowFeature>

  var body: some View {
    LabeledContent("Speech engine") {
      SemanticText(
        store.settingsPane.health.engineReadiness.statusText,
        identifier: AccessibilityID.settingsEngineStatus, label: "Speech engine",
      )
      .foregroundStyle(.secondary)
    }
  }
}

// MARK: - RepairRow

private struct RepairRow: View {
  // MARK: Internal

  let store: StoreOf<SettingsWindowFeature>
  let degradation: Degradation

  var body: some View {
    LabeledContent {
      Button(presentation.title) {
        store.send(.settingsPane(.repairTapped(degradation)))
      }
      .focusRing(store.state.showsSettingsRing(row, target: .repair(degradation)))
      .accessibilityIdentifier(AccessibilityID.settingsRepairAction(degradation))
      .accessibilityLabel(presentation.title)
    } label: {
      Label {
        Text(presentation.reason)
      } icon: {
        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
      }
    }
    .modifier(SettingsFormRow(store: store, row: row))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(AccessibilityID.settingsRepairRow(degradation))
    .accessibilityLabel(presentation.reason)
  }

  // MARK: Private

  private var presentation: Degradation.Presentation {
    degradation.presentation
  }

  private var row: SettingsPaneFeature.Row {
    .repair(degradation)
  }
}

// MARK: - LaunchAtLoginRow

private struct LaunchAtLoginRow: View {
  let store: StoreOf<SettingsWindowFeature>

  var body: some View {
    let showsRing = store.state.showsSettingsRing(.launchAtLogin, target: .launchAtLogin)
    // A switch owns its label, and in a grouped Form that label is as wide as the row, so the
    // ring goes around the whole row rather than around the switch. Moving the label onto a
    // `LabeledContent` and hiding the switch's own fixes the ring and costs the control its
    // `AXSwitch` subrole — VoiceOver then calls it a checkbox. The ring is the cheaper thing to
    // be wrong about.
    Toggle(
      "Open at login",
      isOn: Binding(
        get: { store.settingsPane.launchAtLoginRegistered },
        set: { store.send(.settingsPane(.launchAtLoginToggled($0))) },
      ),
    )
    .toggleStyle(.switch)
    .focusRing(showsRing)
    .accessibilityIdentifier(AccessibilityID.settingsLaunchAtLogin)
    .accessibilityLabel("Open at login")
    .modifier(SettingsFormRow(store: store, row: .launchAtLogin))
    .accessibilityPaintState(
      AccessibilityID.settingsLaunchAtLoginState, label: "Open at login highlight",
      value: store.state.showsSettingsBar(.launchAtLogin) ? "Bar on" : "Bar off",
    )
    .accessibilityPaintState(
      AccessibilityID.settingsLaunchAtLoginRing, label: "Open at login ring",
      value: showsRing ? "Ring on" : "Ring off",
    )
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
  let command: HotkeyCommand

  var body: some View {
    LabeledContent(label) {
      VStack(alignment: .trailing, spacing: 4) {
        HStack {
          ForEach(Array(hotkeys.enumerated()), id: \.offset) { index, hotkey in
            bindingButton(index: index, hotkey: hotkey)
          }
          if bindings.target == .new {
            recordingChip
          }
          if hotkeys.isEmpty, !bindings.isRecording {
            emptyState
          }
          ShortcutMoreMenu(store: store, command: command)
        }
        if let message = bindings.validationMessage {
          Text(message)
            .font(.caption)
            .foregroundStyle(.orange)
            .accessibilityIdentifier(recordingErrorAccessibilityID)
        }
      }
    }
    .modifier(SettingsFormRow(store: store, row: row))
    .disabled(
      store.settingsPane.recordingCommand != nil
        && store.settingsPane.recordingCommand != command,
    )
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(rowAccessibilityID)
    .accessibilityLabel("\(label) shortcut")
    .accessibilityPaintState(
      rowStateAccessibilityID, label: "\(label) shortcut highlight",
      value: store.state.showsSettingsBar(row) ? "Bar on" : "Bar off",
    )
  }

  // MARK: Private

  private var bindings: HotkeyBindingsFeature.State {
    store.settingsPane.bindingEditor(command)
  }

  private var hotkeys: [Hotkey] {
    bindings.hotkeys
  }

  private var presentation: ShortcutPresentation {
    command.settingsPresentation
  }

  private var label: String {
    presentation.label
  }

  private var row: SettingsPaneFeature.Row {
    .shortcut(command)
  }

  private var rowAccessibilityID: String {
    presentation.rowAccessibilityID
  }

  private var rowStateAccessibilityID: String {
    presentation.rowStateAccessibilityID
  }

  private var recordingAccessibilityID: String {
    presentation.recordingAccessibilityID
  }

  private var recordingErrorAccessibilityID: String {
    presentation.recordingErrorAccessibilityID
  }

  private var setAccessibilityID: String {
    presentation.setAccessibilityID
  }

  /// A recording in flight shows the chord as it is built, and says so before there is one.
  private var recordingComponents: [String] {
    bindings.liveChord?.displayComponents ?? ["Recording…"]
  }

  private var recordingTitle: String {
    bindings.liveChord?.displayName ?? "Recording…"
  }

  private var recordingChip: some View {
    HotkeyKeycaps(components: recordingComponents, ringed: showsRing(.recording(command)))
      .accessibilityElement()
      .accessibilityIdentifier(recordingAccessibilityID)
      .accessibilityLabel(recordingTitle)
      .accessibilityValue(showsRing(.recording(command)) ? "Ring on" : "Ring off")
  }

  @ViewBuilder private var emptyState: some View {
    Text("Not set").foregroundStyle(.secondary)
    Button("Set…") { send(.addTapped) }
      .focusRing(showsRing(.set(command)))
      .accessibilityIdentifier(setAccessibilityID)
      .accessibilityValue(showsRing(.set(command)) ? "Ring on" : "Ring off")
  }

  private func bindingButton(index: Int, hotkey: Hotkey) -> some View {
    let isRecording = bindings.isRecording(index)
    let target = SettingsPaneFeature.Target.binding(command, index)
    return Button {
      send(.bindingTapped(index))
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
        ? recordingAccessibilityID
        : bindingAccessibilityID(index),
    )
    .accessibilityValue(showsRing(target) ? "Ring on" : "Ring off")
  }

  private func bindingAccessibilityID(_ index: Int) -> String {
    presentation.bindingAccessibilityID(index)
  }

  private func send(_ action: HotkeyBindingsFeature.Action) {
    store.send(
      .settingsPane(.bindingEditors(.element(id: command, action: action))),
    )
  }

  private func showsRing(_ target: SettingsPaneFeature.Target) -> Bool {
    store.state.showsSettingsRing(row, target: target)
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
      .id(row)
      .windowPointerMovement(store: store) {
        store.send(.settingsPane(.cursorHovered(row)))
      }
  }
}

// MARK: - ShortcutMoreMenu

private struct ShortcutMoreMenu: View {
  // MARK: Internal

  let store: StoreOf<SettingsWindowFeature>
  let command: HotkeyCommand

  var body: some View {
    Menu {
      Button("Add Another…", systemImage: "plus") {
        send(.addTapped)
      }
      if !hotkeys.isEmpty {
        Divider()
        ForEach(Array(hotkeys.enumerated()), id: \.offset) {
          index, hotkey in
          Button("Remove \(hotkey.displayName)", systemImage: "xmark", role: .destructive) {
            send(.removeTapped(index))
          }
        }
      }
    } label: {
      Label("More", systemImage: "ellipsis").labelStyle(.iconOnly)
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .disabled(bindings.isRecording)
    .focusable(false)
    .accessibilityIdentifier(menuAccessibilityID)
    .accessibilityLabel("Shortcut actions")
  }

  // MARK: Private

  private var bindings: HotkeyBindingsFeature.State {
    store.settingsPane.bindingEditor(command)
  }

  private var hotkeys: [Hotkey] {
    bindings.hotkeys
  }

  private var menuAccessibilityID: String {
    command.settingsPresentation.menuAccessibilityID
  }

  private func send(_ action: HotkeyBindingsFeature.Action) {
    store.send(
      .settingsPane(.bindingEditors(.element(id: command, action: action))),
    )
  }
}

// MARK: - ShortcutPresentation

private struct ShortcutPresentation {
  let label: String
  let rowAccessibilityID: String
  let rowStateAccessibilityID: String
  let recordingAccessibilityID: String
  let recordingErrorAccessibilityID: String
  let setAccessibilityID: String
  let menuAccessibilityID: String
  let bindingAccessibilityID: (Int) -> String
}

private extension HotkeyCommand {
  var settingsPresentation: ShortcutPresentation {
    switch self {
    case .activate:
      ShortcutPresentation(
        label: "Activate",
        rowAccessibilityID: AccessibilityID.settingsShortcutRow,
        rowStateAccessibilityID: AccessibilityID.settingsShortcutRowState,
        recordingAccessibilityID: AccessibilityID.settingsShortcutRecording,
        recordingErrorAccessibilityID: AccessibilityID.settingsShortcutRecordingError,
        setAccessibilityID: AccessibilityID.settingsShortcutSet,
        menuAccessibilityID: AccessibilityID.settingsShortcutMenu,
        bindingAccessibilityID: AccessibilityID.settingsShortcutBinding,
      )
    case .pasteLastTranscript:
      ShortcutPresentation(
        label: "Paste last transcript",
        rowAccessibilityID: AccessibilityID.settingsPasteLastShortcutRow,
        rowStateAccessibilityID: AccessibilityID.settingsPasteLastShortcutRowState,
        recordingAccessibilityID: AccessibilityID.settingsPasteLastShortcutRecording,
        recordingErrorAccessibilityID: AccessibilityID.settingsPasteLastShortcutRecordingError,
        setAccessibilityID: AccessibilityID.settingsPasteLastShortcutSet,
        menuAccessibilityID: AccessibilityID.settingsPasteLastShortcutMenu,
        bindingAccessibilityID: AccessibilityID.settingsPasteLastShortcutBinding,
      )
    }
  }
}
