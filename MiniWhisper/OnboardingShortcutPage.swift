import ComposableArchitecture
import HotkeyListener
import SwiftUI

struct OnboardingShortcutPage: View {
  // MARK: Internal

  let store: StoreOf<OnboardingFeature>
  var focus: FocusState<OnboardingFocus?>.Binding
  var warningVisibilityChanged: (Bool) -> Void

  var body: some View {
    OnboardingStepPage(
      symbol: "command",
      title: .init(
        text: "Choose your shortcut", identifier: AccessibilityID.onboardingShortcutTitle,
        label: "Shortcut heading",
      ),
      summary: .init(
        text: "Every dictation starts here.",
        identifier: AccessibilityID.onboardingShortcutSummary, label: "Shortcut information",
      ),
      cardPadding: 0,
    ) {
      VStack(spacing: 14) {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
          ForEach(Array(Self.presets.enumerated()), id: \.offset) { index, hotkey in
            Button { store.send(.shortcutBindings(.presetSelected(hotkey))) } label: {
              HotkeyKeycaps(components: index == 3 ? ["⌃", "⌥", "Space"] : hotkey.displayComponents)
                .frame(maxWidth: .infinity, minHeight: 42)
                .focusable()
                .focused(focus, equals: .shortcutPreset(index))
                .focusEffectDisabled()
                .onKeyPress(keys: [.return, .space]) { _ in
                  store.send(.shortcutBindings(.presetSelected(hotkey)))
                  return .handled
                }
            }
            .buttonStyle(.bordered)
            .tint(store.hotkeys.first == hotkey ? Color.accentColor : Color.secondary)
            .disabled(store.isRecordingShortcut)
            .focusRing(focus.wrappedValue == .shortcutPreset(index))
            .focusable(false)
            .accessibilityIdentifier("miniwhisper.onboarding.shortcut.preset.\(index)")
            .accessibilityLabel(hotkey.displayName)
            .accessibilityValue(store.hotkeys.first == hotkey ? "Selected" : "Not selected")
          }
        }
        keycap
        ShortcutSystemNote(
          hotkeys: store.hotkeys, focus: focus, visibilityChanged: warningVisibilityChanged,
        )

        if let message = store.shortcutBindings.validationMessage {
          SemanticText(
            message, identifier: AccessibilityID.onboardingShortcutError,
            label: "Shortcut recording error",
          )
          .font(.caption)
          .foregroundStyle(.primary)
        }
      }
      .accessibilityPaintState(
        AccessibilityID.onboardingShortcutBindingRing, label: "Dictation shortcut ring",
        value: showsRing ? "Ring on" : "Ring off",
      )
    }
    .animation(.easeInOut(duration: 0.2), value: store.isRecordingShortcut)
    .animation(.easeInOut(duration: 0.2), value: store.shortcutBindings.validationMessage)
    .accessibilityIdentifier(AccessibilityID.onboardingShortcut)
    .accessibilityLabel("Activation shortcut setup")
  }

  // MARK: Private

  private static let presets = [
    try! Hotkey(modifiers: [.rightOption]),
    try! Hotkey(modifiers: [.rightCommand]),
    try! Hotkey(modifiers: [.function]),
    try! Hotkey(keyCode: 49, modifiers: [.leftControl, .leftOption]),
  ]

  /// The ring is focus vocabulary and nothing else, so a recording in flight — which owns the
  /// keyboard outright — never wears one.
  private var showsRing: Bool {
    focus.wrappedValue == .shortcutKeycap && !store.isRecordingShortcut
  }

  private var components: [String] {
    if store.isRecordingShortcut {
      return store.shortcutBindings.liveChord?.displayComponents ?? ["Recording…"]
    }
    return store.hotkeys.first?.displayComponents ?? ["Not set"]
  }

  private var displayName: String {
    if store.isRecordingShortcut {
      return store.shortcutBindings.liveChord?.displayName ?? "Recording…"
    }
    return store.hotkeys.first?.displayName ?? "Not set"
  }

  private var keycap: some View {
    Button { store.send(.shortcutBindings(.primaryBindingTapped)) } label: {
      HStack(spacing: 8) {
        if store.isRecordingShortcut || !Self.presets
          .contains(where: { $0 == store.hotkeys.first })
        {
          HotkeyKeycaps(components: components, ringed: showsRing)
        } else {
          Label("Record your own", systemImage: "record.circle")
        }
      }
      .focusable()
      .focused(focus, equals: .shortcutKeycap)
      .focusEffectDisabled()
      .onKeyPress(keys: [.return, .space]) { _ in
        store.send(.shortcutBindings(.primaryBindingTapped))
        return .handled
      }
    }
    .buttonStyle(.bordered)
    .focusRing(showsRing)
    .focusable(false)
    .accessibilityIdentifier(AccessibilityID.onboardingShortcutBinding)
    .accessibilityLabel("Dictation shortcut")
    .accessibilityValue(displayName)
  }
}
