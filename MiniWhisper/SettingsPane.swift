import AppSettings
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
    }
    .formStyle(.grouped)
    .focusEffectDisabled()
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
