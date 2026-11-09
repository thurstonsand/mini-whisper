import ComposableArchitecture
import HotkeyListener
import SwiftUI

struct ShortcutSystemNote: View {
  // MARK: Internal

  let hotkeys: [Hotkey]
  var focus: FocusState<OnboardingFocus?>.Binding?
  var visibilityChanged: (Bool) -> Void = { _ in }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let warning {
        VStack(alignment: .leading, spacing: 8) {
          Label(warning, systemImage: "exclamationmark.triangle")
            .fixedSize(horizontal: false, vertical: true)
          if let focus {
            button.focused(focus, equals: .shortcutSettings)
          } else {
            button
          }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("miniwhisper.shortcut.system-note")
      }
    }
    .onChange(of: warning != nil, initial: true) { _, visible in visibilityChanged(visible) }
    .task {
      for await snapshot in keyboardSettings.snapshots() {
        settings = snapshot
      }
    }
  }

  // MARK: Private

  @Environment(\.openURL) private var openURL
  @State private var settings: KeyboardShortcutSettings?

  @Dependency(\.keyboardSettings) private var keyboardSettings

  private var warning: String? {
    hotkeys.compactMap { settings?.warning(for: $0) }.first
  }

  private var button: some View {
    Button("Open Keyboard Settings") {
      openURL(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
    }
  }
}
