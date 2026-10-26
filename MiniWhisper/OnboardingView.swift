import AppSettings
import ASREngine
import ComposableArchitecture
import HotkeyListener
import SwiftUI

// MARK: - OnboardingCopy

/// Onboarding teaches the shortcut the user actually has, so every sentence naming it is written
/// against the live first binding and has an honest answer for having none.
enum OnboardingCopy {
  static let tryItQuote =
    "“A future is not given to you. It is something you must take for yourself.” — Pod 042"

  static func tryItInstructions(hotkeys: [Hotkey]) -> String {
    guard let name = hotkeys.first?.displayName else {
      return "Set an activation shortcut in Settings before reading the line aloud."
    }
    return "Focus the text box below, hold \(name), and read the line aloud. Release when you're done, or double-tap \(name) to keep recording until you tap it again."
  }

  static func readySummary(hotkeys: [Hotkey]) -> String {
    guard let name = hotkeys.first?.displayName else {
      return "Your first dictation made the full trip. Set an activation shortcut in Settings before using dictation in another text field."
    }
    return "Your first dictation made the full trip. Hold \(name) in any text field and speak."
  }
}

// MARK: - OnboardingFocus

/// Every control in the window that focus can rest on. Pages are never focused as such: a page's
/// keyboard path is whichever of these it lists in `tabCycle`.
enum OnboardingFocus: Hashable {
  case welcomeAction
  case keyField(CredentialSlot)
  case useCustom
  case keysSkip
  case keysContinue
  case permissionsAction
  case shortcutKeycap
  case shortcutContinue
  case modelAction
  case tryItEditor
  case tryItSkip
  case readyAction
}

// MARK: - OnboardingView

struct OnboardingView: View {
  // MARK: Internal

  @Bindable var store: StoreOf<OnboardingFeature>

  var body: some View {
    Group {
      if store.isShowingWelcome {
        OnboardingWelcomePage(store: store, focus: $focus)
      } else {
        HStack(spacing: 0) {
          OnboardingStepRail(store: store)
          Divider()
          VStack(alignment: .leading, spacing: 0) {
            stepContent.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
          }
          .padding(.horizontal, 42)
          .padding(.vertical, 36)
        }
      }
    }
    .frame(width: 720, height: 500)
    .background(.background)
    .background { WindowTabKeys(onTab: handleTab) }
    .task { await store.send(.task).finish() }
    .onExitCommand {
      guard store.isRecordingShortcut else {
        return
      }
      store.send(.shortcutBindings(.cancelRecording))
    }
  }

  // MARK: Private

  /// Only the Try It editor claims focus on arrival, and it claims it itself. Every other page
  /// opens with none: Return already reaches the primary action, so the first Tab is what the
  /// page's other control is waiting for. Focus of a view that goes away goes away with it.
  @FocusState private var focus: OnboardingFocus?

  /// A page's whole rendered keyboard path, in order: Tab walks it forward and Shift-Tab back,
  /// wrapping at either end. A 1-cycle parks on its only stop; a 2-cycle is its own reverse; and an
  /// empty cycle declines the key back to the system. Shortcut recording is the exception because
  /// it owns the keyboard outright.
  private var tabCycle: [OnboardingFocus] {
    guard !store.isShowingWelcome else {
      return [.welcomeAction]
    }
    return switch store.visibleStep {
    case .keys:
      store.missingKeys.map(OnboardingFocus.keyField) + [.useCustom, .keysSkip, .keysContinue]
    case .permissions:
      store.activePermission == nil ? [] : [.permissionsAction]
    case .shortcut:
      store.isRecordingShortcut ? [] : [.shortcutKeycap, .shortcutContinue]
    case .model:
      store.needsModelSetup || store.canContinueFromModel ? [.modelAction] : []
    // Nothing to dictate into yet, so Skip is the page's only control — and still a Tab stop,
    // because a button the keyboard cannot reach is not a way out.
    case .tryIt:
      tryItIsLive ? [.tryItEditor, .tryItSkip] : [.tryItSkip]
    case .ready:
      [.readyAction]
    }
  }

  private var tryItIsLive: Bool {
    store.visibleStep == .tryIt && store.canTryDictation
  }

  @ViewBuilder private var stepContent: some View {
    switch store.visibleStep {
    case .keys:
      OnboardingKeysPage(store: store, focus: $focus)
    case .permissions:
      OnboardingPermissionsPage(store: store, focus: $focus)
    case .shortcut:
      OnboardingShortcutPage(store: store, focus: $focus)
    case .model:
      OnboardingModelPage(store: store)
    case .tryIt:
      OnboardingTryItPage(store: store, focus: $focus)
    case .ready:
      OnboardingReadyPage(store: store)
    }
  }

  private var footer: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let failureMessage = store.failureMessage {
        Label(failureMessage, systemImage: "exclamationmark.triangle.fill")
          .font(.system(size: 12))
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityElement(children: .ignore)
          .accessibilityIdentifier(AccessibilityID.onboardingFailure)
          .accessibilityLabel("Setup error")
          .accessibilityValue(failureMessage)
      }
      HStack {
        if store.canSkip {
          skipButton
        } else if store.visibleStep == .keys {
          keysSkipButton
        }
        Spacer()
        footerButtons
      }
    }
  }

  private var skipButton: some View {
    secondaryButton("Skip", focus: .tryItSkip) { store.send(.skip) }
      .disabled(store.isMarkingCompletion)
      .accessibilityIdentifier(AccessibilityID.onboardingTryItSkip)
      .accessibilityLabel("Skip test dictation")
      .accessibilityPaintState(
        AccessibilityID.onboardingTryItSkipRing, label: "Skip ring",
        value: focus == .tryItSkip ? "Ring on" : "Ring off",
      )
  }

  /// Possible, not advised: the profile stays Degraded and does not dictate until a key is added.
  private var keysSkipButton: some View {
    secondaryButton("Skip for Now", focus: .keysSkip) { store.send(.keysSkipped) }
      .accessibilityIdentifier(AccessibilityID.onboardingKeysSkip)
  }

  @ViewBuilder private var footerButtons: some View {
    switch store.visibleStep {
    case .keys:
      Button(store.isCheckingKeys ? "Checking…" : "Continue") { store.send(.keysContinueTapped) }
        .buttonStyle(.borderedProminent)
        .focused($focus, equals: .keysContinue)
        .disabled(!store.canContinueFromKeys)
        .keyboardShortcut(.defaultAction)
        .accessibilityIdentifier(AccessibilityID.onboardingKeysContinue)
    case .permissions:
      SemanticText(
        "Continue after granting both",
        identifier: AccessibilityID.onboardingPermissionsGuidance, label: "Permissions guidance",
      )
      .font(.system(size: 12))
      .foregroundStyle(.secondary)
    case .shortcut:
      Button("Continue") { store.send(.shortcutContinueTapped) }
        .buttonStyle(.borderedProminent)
        .focused($focus, equals: .shortcutContinue)
        .disabled(store.isRecordingShortcut)
        .keyboardShortcut(.defaultAction)
        .accessibilityIdentifier(AccessibilityID.onboardingShortcutContinue)
    case .model:
      if store.needsModelSetup {
        Button(
          store.engineReadiness.isFailure ? "Retry Model Setup" : "Download & Prepare",
        ) { store.send(.setupModel) }
          .buttonStyle(.borderedProminent)
          .focused($focus, equals: .modelAction)
          .keyboardShortcut(.defaultAction)
          .accessibilityIdentifier(AccessibilityID.onboardingModelRetry)
      } else if store.canContinueFromModel {
        Button("Continue") { store.send(.modelContinueTapped) }
          .buttonStyle(.borderedProminent)
          .focused($focus, equals: .modelAction)
          .keyboardShortcut(.defaultAction)
          .accessibilityIdentifier(AccessibilityID.onboardingModelContinue)
      }
    case .tryIt:
      // A skipped key leaves nothing to speak into; the card says why and Skip is the way on.
      if store.canTryDictation {
        SemanticText(
          "Speak to complete…", identifier: AccessibilityID.onboardingTryItGuidance,
          label: "Try it guidance",
        )
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
      } else if store.step != .ready, store.step != .tryIt {
        SemanticText(
          "Complete the earlier steps to try a dictation",
          identifier: AccessibilityID.onboardingTryItGuidance, label: "Try it guidance",
        )
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
      }
    case .ready:
      Button("Start Dictating") { store.send(.finish) }
        .buttonStyle(.borderedProminent)
        .focused($focus, equals: .readyAction)
        .keyboardShortcut(.defaultAction)
        .accessibilityIdentifier(AccessibilityID.onboardingReadyFinish)
        .accessibilityLabel("Start Dictating")
    }
  }

  /// The quiet way past a page, beside its primary action.
  private func secondaryButton(
    _ title: String, focus target: OnboardingFocus, action: @escaping () -> Void,
  ) -> some View {
    Button(title, action: action)
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
      .focused($focus, equals: target)
      // The system effect fills a plain button with a solid accent capsule that swallows its
      // label, so the ring is drawn here — from focus state and nothing else.
      .focusEffectDisabled()
      .overlay {
        RoundedRectangle(cornerRadius: 5)
          .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 2)
          .padding(-4)
          .opacity(focus == target ? 1 : 0)
      }
  }

  private func handleTab(backward: Bool) -> Bool {
    let cycle = tabCycle
    guard !cycle.isEmpty else {
      return false
    }
    guard let focus, let index = cycle.firstIndex(of: focus) else {
      focus = cycle.first
      return true
    }
    let step = backward ? cycle.count - 1 : 1
    self.focus = cycle[(index + step) % cycle.count]
    return true
  }
}

private extension EngineReadiness {
  var isFailure: Bool {
    if case .failed = self {
      return true
    }
    return false
  }
}
