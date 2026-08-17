import ComposableArchitecture
import SwiftUI

// MARK: - OnboardingTryItPage

/// The one page whose card is only ever the real thing: an editable field the user dictates into.
/// Until the earlier steps are done it says which one is missing rather than pretending.
struct OnboardingTryItPage: View {
  // MARK: Internal

  let store: StoreOf<OnboardingFeature>
  var focus: FocusState<OnboardingFocus?>.Binding

  var body: some View {
    OnboardingStepPage(
      symbol: "quote.bubble",
      title: .init(
        text: "Give it a try", identifier: AccessibilityID.onboardingTryItTitle,
        label: "Try it heading",
      ),
      summary: .init(
        text: OnboardingCopy.tryItInstructions(hotkeys: store.hotkeys),
        identifier: AccessibilityID.onboardingTryItInstructions, label: "Try it instructions",
      ),
      summaryLineSpacing: 3,
      cardPadding: 14,
      cardAlignment: .topLeading,
    ) {
      VStack(alignment: .leading, spacing: 10) { cardContent }
    }
    .animation(.easeInOut(duration: 0.2), value: store.step)
    .accessibilityIdentifier(AccessibilityID.onboardingTryIt)
    .accessibilityLabel("Try \(Channel.name)")
  }

  // MARK: Private

  @ViewBuilder private var cardContent: some View {
    switch store.step {
    case .permissions:
      unavailable(
        "Grant both permissions and wait for the speech model to try it.", symbol: "lock.shield",
      )
    case .shortcut:
      unavailable(
        "Choose your shortcut and wait for the speech model to try it.",
        symbol: "command",
      )
    case .model:
      unavailable("Wait for the speech model to finish before trying a dictation.", symbol: "cpu")
    case .tryIt:
      editor
      if let hotkey = store.hotkeys.first {
        HotkeyKeycaps(components: hotkey.displayComponents)
          .accessibilityHidden(true)
          .accessibilityPaintState(
            AccessibilityID.onboardingTryItHotkey, label: "Dictation hotkey",
            value: hotkey.displayName,
          )
      } else {
        Text("Activation shortcut not set")
          .font(.callout)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier(AccessibilityID.onboardingTryItHotkey)
          .accessibilityLabel("Dictation hotkey")
          .accessibilityValue("Not set")
      }
    case .ready:
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 17))
          .foregroundStyle(Color.green)
          .frame(width: 22)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 5) {
          SemanticText(
            "Your test dictation is complete",
            identifier: AccessibilityID.onboardingTryItCompletion, label: "Test dictation status",
          ).font(.system(size: 13, weight: .semibold))
          SemanticText(
            "\(Channel.name) is ready to use in any text field.",
            identifier: AccessibilityID.onboardingTryItCompletionSummary, label: "Availability",
          )
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
        }
      }
    }
  }

  private var editor: some View {
    TextField(
      text: Binding(get: { store.tryItText }, set: { store.send(.tryItTextChanged($0)) }),
      prompt: Text(OnboardingCopy.tryItQuote).italic(),
      axis: .vertical,
    ) {
      Text("Try dictation")
    }
    .labelsHidden()
    .textFieldStyle(.plain)
    .font(.body)
    .lineLimit(4, reservesSpace: true)
    .padding(8)
    .frame(height: 96, alignment: .topLeading)
    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
    .overlay {
      RoundedRectangle(cornerRadius: 7).strokeBorder(
        focus.wrappedValue == .tryItEditor ? Color.accentColor : Color.secondary.opacity(0.3),
        lineWidth: 1,
      )
    }
    .focused(focus, equals: .tryItEditor)
    .accessibilityIdentifier(AccessibilityID.onboardingTryItText)
    .accessibilityLabel("Try dictation")
    // Focus is claimed when the field exists, not when the state that summons it changes: a
    // @FocusState assignment aimed at a view SwiftUI has not built yet lands nowhere, and the
    // yield puts this after AppKit has chosen its own first responder.
    .task {
      await Task.yield()
      focus.wrappedValue = .tryItEditor
    }
  }

  private func unavailable(_ message: String, symbol: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(Color.accentColor).frame(
        width: 22,
      )
      Text(message).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(
        horizontal: false, vertical: true,
      )
    }
    .accessibilityElement(children: .ignore)
    .accessibilityIdentifier(AccessibilityID.onboardingTryItAvailability)
    .accessibilityLabel("Try dictation availability")
    .accessibilityValue(message)
  }
}
