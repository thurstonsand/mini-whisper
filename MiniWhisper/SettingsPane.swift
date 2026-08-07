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
    }
    .formStyle(.grouped)
    .focusEffectDisabled()
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
          MicrophonePopUpButton(
            options: options,
            selection: store.settingsPane.microphone,
            activation: store.settingsPane.microphoneActivation,
            onSelection: { store.send(.settingsPane(.microphoneSelected($0))) },
          )
          .fixedSize()
          .overlay {
            RoundedRectangle(cornerRadius: 6)
              .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 2)
              .padding(-1)
              .opacity(store.state.showsSettingsRing(.microphone, target: .microphone) ? 1 : 0)
          }
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
  private var options: [MicrophonePopUpButton.Option] {
    var options = [
      MicrophonePopUpButton.Option(
        selection: .systemDefault, title: "System Default (\(defaultDeviceName))",
      ),
    ]
    options.append(contentsOf: store.settingsPane.inputDevices.devices.map {
      MicrophonePopUpButton.Option(
        selection: .device(uid: $0.uid, lastKnownName: $0.name), title: $0.name,
      )
    })
    if let unavailableName = store.settingsPane.unavailableMicrophoneName {
      options.append(
        MicrophonePopUpButton.Option(
          selection: store.settingsPane.microphone,
          title: "\(unavailableName) (Unavailable)",
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

// MARK: - MicrophonePopUpButton

private struct MicrophonePopUpButton: NSViewRepresentable {
  struct Option: Equatable {
    let selection: MicrophoneSelection
    let title: String
  }

  @MainActor final class Coordinator: NSObject {
    // MARK: Lifecycle

    init(activation: Int, onSelection: @escaping (MicrophoneSelection) -> Void) {
      self.activation = activation
      self.onSelection = onSelection
    }

    // MARK: Internal

    var options: [Option] = []
    var activation: Int
    var onSelection: (MicrophoneSelection) -> Void

    @objc func selectionChanged(_ sender: NSPopUpButton) {
      guard options.indices.contains(sender.indexOfSelectedItem) else {
        return
      }
      onSelection(options[sender.indexOfSelectedItem].selection)
    }
  }

  let options: [Option]
  let selection: MicrophoneSelection
  let activation: Int
  let onSelection: (MicrophoneSelection) -> Void

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
    if let selectedIndex = options.firstIndex(where: { $0.selection == selection }) {
      button.selectItem(at: selectedIndex)
    }
    // Only a click opens a pop-up button, so Return on this row arrives as a changed count.
    guard activation != context.coordinator.activation else {
      return
    }
    context.coordinator.activation = activation
    DispatchQueue.main.async { button.performClick(nil) }
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
      .overlay {
        RoundedRectangle(cornerRadius: 6)
          .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 2)
          .padding(-1)
          .opacity(showsRing(.set) ? 1 : 0)
      }
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
      .windowPointerMovement(store: store)
      .onHover { isHovered in
        store.send(.settingsPane(isHovered ? .rowHovered(row) : .rowExited(row)))
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
