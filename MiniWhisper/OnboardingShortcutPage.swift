import ComposableArchitecture
import SwiftUI

/// The keycap is the button. Clicking it — or pressing Return or Space while it wears the ring —
/// records into the primary binding in place, so there is no second control to explain.
struct OnboardingShortcutPage: View {
  // MARK: Internal

  let store: StoreOf<OnboardingFeature>
  var focus: FocusState<OnboardingFocus?>.Binding

  var body: some View {
    OnboardingStepPage(
      symbol: "command",
      title: .init(
        text: "Activating \(Channel.name)", identifier: AccessibilityID.onboardingShortcutTitle,
        label: "Shortcut heading",
      ),
      summary: .init(
        text: "Shortcut to start dictation.",
        identifier: AccessibilityID.onboardingShortcutSummary, label: "Shortcut information",
      ),
    ) {
      VStack(spacing: 14) {
        keycap
        SemanticText(
          store.isRecordingShortcut ? "Record your shortcut" : "Click the shortcut to change",
          identifier: AccessibilityID.onboardingShortcutCaption, label: "Shortcut guidance",
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        if let message = store.shortcutBindings.validationMessage {
          SemanticText(
            message, identifier: AccessibilityID.onboardingShortcutError,
            label: "Shortcut recording error",
          )
          .font(.caption)
          .foregroundStyle(.orange)
        }
      }
      .accessibilityPaintState(
        AccessibilityID.onboardingShortcutBindingRing, label: "Dictation shortcut ring",
        value: showsRing ? "Ring on" : "Ring off",
      )
    }
    .accessibilityIdentifier(AccessibilityID.onboardingShortcut)
    .accessibilityLabel("Activation shortcut setup")
  }

  // MARK: Private

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
      HotkeyKeycaps(components: components, scale: 1.8, ringed: showsRing)
        .focusable()
        .focused(focus, equals: .shortcutKeycap)
        .focusEffectDisabled()
        .onKeyPress(keys: [.return, .space]) { _ in
          store.send(.shortcutBindings(.primaryBindingTapped))
          return .handled
        }
    }
    .buttonStyle(.plain)
    .focusable(false)
    .accessibilityIdentifier(AccessibilityID.onboardingShortcutBinding)
    .accessibilityLabel("Dictation shortcut")
    .accessibilityValue(displayName)
  }
}
