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

  /// A page's whole rendered keyboard path, in order. A 1-cycle parks on its only stop; a 2-cycle
  /// is its own reverse; and an empty cycle declines the key back to the system. Shortcut recording
  /// is the exception because it owns the keyboard outright.
  private var tabCycle: [OnboardingFocus] {
    guard !store.isShowingWelcome else {
      return [.welcomeAction]
    }
    return switch store.visibleStep {
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
    store.visibleStep == .tryIt && store.step == .tryIt
  }

  @ViewBuilder private var stepContent: some View {
    switch store.visibleStep {
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
        }
        Spacer()
        footerButtons
      }
    }
  }

  private var skipButton: some View {
    Button("Skip") { store.send(.skip) }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
      .focused($focus, equals: .tryItSkip)
      // The system effect fills a plain button with a solid accent capsule that swallows its
      // label, so the ring is drawn here — from focus state and nothing else.
      .focusEffectDisabled()
      .overlay {
        RoundedRectangle(cornerRadius: 5)
          .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 2)
          .padding(-4)
          .opacity(focus == .tryItSkip ? 1 : 0)
      }
      .disabled(store.isMarkingCompletion)
      .accessibilityIdentifier(AccessibilityID.onboardingTryItSkip)
      .accessibilityLabel("Skip test dictation")
      .accessibilityPaintState(
        AccessibilityID.onboardingTryItSkipRing, label: "Skip ring",
        value: focus == .tryItSkip ? "Ring on" : "Ring off",
      )
  }

  @ViewBuilder private var footerButtons: some View {
    switch store.visibleStep {
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
      if store.step == .tryIt {
        SemanticText(
          "Speak to complete…", identifier: AccessibilityID.onboardingTryItGuidance,
          label: "Try it guidance",
        )
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
      } else if store.step != .ready {
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

  private func handleTab() -> Bool {
    let cycle = tabCycle
    guard !cycle.isEmpty else {
      return false
    }
    focus = focus == cycle.first ? cycle.last : cycle.first
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
