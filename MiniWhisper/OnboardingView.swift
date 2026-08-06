import AppSettings
import ASREngine
import AudioCapture
import ComposableArchitecture
import HotkeyListener
import SwiftUI

// MARK: - OnboardingCopy

/// Onboarding teaches the shortcut the user actually has, so every sentence naming it is written
/// against the live first binding and has an honest answer for having none.
enum OnboardingCopy {
  static func tryItInstructions(hotkeys: [Hotkey]) -> String {
    guard let name = hotkeys.first?.displayName else {
      return "Set an activation shortcut in Settings before trying dictation here."
    }
    return "Focus the text box below, hold \(name) while you speak, then release. Or double-tap \(name) to keep recording until you tap it again."
  }

  static func readySummary(hotkeys: [Hotkey]) -> String {
    guard let name = hotkeys.first?.displayName else {
      return "Your first dictation made the full trip. Set an activation shortcut in Settings before using dictation in another text field."
    }
    return "Your first dictation made the full trip. Hold \(name) in any text field and speak."
  }
}

// MARK: - OnboardingView

struct OnboardingView: View {
  // MARK: Internal

  @Bindable var store: StoreOf<OnboardingFeature>

  var body: some View {
    Group {
      if store.isShowingWelcome {
        welcomeContent
      } else {
        HStack(spacing: 0) {
          stepRail
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
    .onChange(of: store.visibleStep) {
      _, step in tryItFieldIsFocused = step == .tryIt && store.step == .tryIt
    }
  }

  // MARK: Private

  @FocusState private var tryItFieldIsFocused: Bool
  @State.Shared(.settingsFile) private var settings = MiniWhisperSettings.defaults

  private var activationHotkey: Hotkey? {
    settings.hotkeys.first
  }

  private var welcomeContent: some View {
    VStack(spacing: 0) {
      ZStack {
        RoundedRectangle(cornerRadius: 22).fill(Color.accentColor.opacity(0.12)).frame(
          width: 92, height: 92,
        )
        Image(systemName: "mic.fill").font(.system(size: 42, weight: .semibold)).foregroundStyle(
          Color.accentColor,
        )
      }.accessibilityHidden(true)
      SemanticText(
        Channel.name, identifier: AccessibilityID.onboardingWelcomeTitle,
        label: "Application name",
      )
      .font(.system(size: 34, weight: .semibold))
      .padding(.top, 24)
      SemanticText(
        "Fast, accurate dictation that runs on your Mac.",
        identifier: AccessibilityID.onboardingWelcomeSummary, label: "Welcome summary",
      )
      .font(.system(size: 16))
      .foregroundStyle(.secondary)
      .padding(.top, 8)
      SemanticText(
        "Download the speech model in the background while you finish setup.",
        identifier: AccessibilityID.onboardingWelcomeModelInfo, label: "Model download information",
      )
      .font(.system(size: 13))
      .foregroundStyle(.secondary)
      .lineLimit(1)
      .padding(.top, 12)
      Button("Download Parakeet v2") { store.send(.downloadModel) }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(store.isRecordingModelDownloadConsent)
        .padding(.top, 30)
        .accessibilityIdentifier(AccessibilityID.onboardingDownloadModel)
        .accessibilityLabel(
          "Download Parakeet v2",
        )
      if let failureMessage = store.failureMessage {
        Label(failureMessage, systemImage: "exclamationmark.triangle.fill")
          .font(.system(size: 12))
          .foregroundStyle(.red)
          .padding(.top, 16)
          .accessibilityElement(children: .ignore)
          .accessibilityIdentifier(AccessibilityID.onboardingWelcomeFailure)
          .accessibilityLabel(
            "Model download error",
          )
          .accessibilityValue(failureMessage)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(
      AccessibilityID.onboardingWelcome,
    )
    .accessibilityLabel("Welcome to \(Channel.name)")
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var stepRail: some View {
    VStack(alignment: .leading, spacing: 0) {
      Image(systemName: "mic.fill")
        .font(.system(size: 25, weight: .semibold))
        .foregroundStyle(
          Color.accentColor,
        )
        .accessibilityHidden(true)
      SemanticText(
        Channel.name, identifier: AccessibilityID.onboardingRailBrand, label: "Application name",
      )
      .font(.system(size: 19, weight: .semibold))
      .padding(.top, 10)
      SemanticText(
        "fast and accurate dictation", identifier: AccessibilityID.onboardingRailTagline,
        label: "Application description",
      )
      .font(.system(size: 12))
      .foregroundStyle(.secondary)
      .fixedSize(
        horizontal: false, vertical: true,
      )
      .padding(.top, 3)

      VStack(alignment: .leading, spacing: 17) {
        railItem("Permissions", step: .permissions, symbol: "lock.shield")
        railItem("Speech Model", step: .model, symbol: "cpu")
        railItem("Try It", step: .tryIt, symbol: "checkmark.bubble")
      }.padding(.top, 38)

      Spacer()
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(
      AccessibilityID.onboardingRail,
    )
    .accessibilityLabel("Setup steps")
    .padding(.horizontal, 24)
    .padding(.vertical, 30)
    .frame(
      width: 210,
    )
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.62))
  }

  @ViewBuilder private var compactModelProgress: some View {
    switch store.snapshot.engineReadiness {
    case let .downloading(fraction):
      Text("\(Int(fraction * 100))%").font(.system(size: 10)).monospacedDigit().foregroundStyle(
        .secondary,
      )
    case .compiling,
         .prewarming:
      ProgressView().controlSize(.mini)
    case .modelMissing,
         .ready,
         .failed:
      EmptyView()
    }
  }

  @ViewBuilder private var stepContent: some View {
    switch store.visibleStep {
    case .permissions:
      permissionsContent
    case .model:
      modelContent
    case .tryIt:
      tryItContent
    case .ready:
      readyContent
    }
  }

  private var permissionsContent: some View {
    VStack(alignment: .leading, spacing: 0) {
      stepSymbol("lock.shield")
      SemanticText(
        "We need access to a few things first",
        identifier: AccessibilityID.onboardingPermissionsTitle, label: "Permissions heading",
      )
      .font(.system(size: 28, weight: .semibold))
      .padding(.top, 20)
      SemanticText(
        "macOS prompts for both. Grant them in the order they appear.",
        identifier: AccessibilityID.onboardingPermissionsSummary,
        label: "Permissions information",
      )
      .font(.system(size: 14))
      .foregroundStyle(.secondary)
      .lineLimit(2)
      .frame(
        height: 58, alignment: .topLeading,
      )
      .padding(.top, 10)

      VStack(spacing: 0) {
        permissionRow(
          .microphone, title: "Microphone", symbol: "waveform",
          explanation: "Hear your beautiful voice",
        )
        Divider()
        permissionRow(
          .accessibility, title: "Accessibility", symbol: "keyboard",
          explanation:
          "Watch for the dictation hotkey, paste at your cursor, and read the text around it.",
        )
      }
      .frame(maxWidth: .infinity, minHeight: 162, maxHeight: 162)
      .background(
        Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 9),
      )
      .padding(.top, 24)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(
      AccessibilityID.onboardingPermissions,
    )
    .accessibilityLabel("Permissions setup")
  }

  private var modelContent: some View {
    VStack(alignment: .leading, spacing: 0) {
      stepSymbol("cpu")
      SemanticText(
        "Prepare Parakeet v2", identifier: AccessibilityID.onboardingModelTitle,
        label: "Model setup heading",
      )
      .font(.system(size: 28, weight: .semibold))
      .padding(.top, 20)
      SemanticText(
        "Downloads once (~450 MB), then everything runs on this Mac.",
        identifier: AccessibilityID.onboardingModelSummary, label: "Model setup information",
      )
      .font(.system(size: 14))
      .foregroundStyle(.secondary)
      .lineLimit(1)
      .frame(
        maxWidth: 430, minHeight: 58, maxHeight: 58, alignment: .topLeading,
      )
      .padding(.top, 10)

      VStack(alignment: .leading, spacing: 10) { modelCardContent }
        .padding(18)
        .frame(
          maxWidth: .infinity, minHeight: 162, maxHeight: 162, alignment: .topLeading,
        )
        .background(
          Color(nsColor: .controlBackgroundColor).opacity(0.5),
          in: RoundedRectangle(cornerRadius: 9),
        )
        .padding(.top, 24)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(
      AccessibilityID.onboardingModel,
    )
    .accessibilityLabel("Speech model setup")
  }

  @ViewBuilder private var modelCardContent: some View {
    switch store.snapshot.engineReadiness {
    case let .downloading(fraction):
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          SemanticText(
            "Downloading model", identifier: AccessibilityID.onboardingModelStatus,
            label: "Model status",
          ).font(.system(size: 13, weight: .medium))
          Spacer()
          Text("\(Int(fraction * 100))%")
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
        ProgressView(value: fraction)
          .progressViewStyle(.linear)
          .accessibilityIdentifier(
            AccessibilityID.onboardingModelProgress,
          )
          .accessibilityLabel("Model download")
          .accessibilityValue("\(Int(fraction * 100))%")
      }
    case .compiling:
      progressRow("Compiling Core ML models…", value: "Compiling")
    case .prewarming:
      VStack(alignment: .leading, spacing: 8) {
        progressRow("Optimizing for this Mac…", value: "Prewarming")
        SemanticText(
          "The first specialization can take about 3–4 minutes. Keep \(Channel.name) open.",
          identifier: AccessibilityID.onboardingModelStatus, label: "Model preparation information",
        )
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
      }
    case .modelMissing,
         .failed:
      Label("About 450 MB · downloaded once", systemImage: "internaldrive")
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(AccessibilityID.onboardingModelStatus)
        .accessibilityLabel(
          "Model status",
        )
        .accessibilityValue("Not installed")
    case .ready:
      Label("Parakeet v2 is ready", systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(
          AccessibilityID.onboardingModelStatus,
        )
        .accessibilityLabel("Model status")
        .accessibilityValue("Ready")
    }
  }

  private var tryItContent: some View {
    VStack(alignment: .leading, spacing: 0) {
      stepSymbol("quote.bubble")
      SemanticText(
        "Give it a try", identifier: AccessibilityID.onboardingTryItTitle, label: "Try it heading",
      )
      .font(.system(size: 28, weight: .semibold))
      .padding(.top, 20)
      SemanticText(
        OnboardingCopy.tryItInstructions(hotkeys: settings.hotkeys),
        identifier: AccessibilityID.onboardingTryItInstructions, label: "Try it instructions",
      )
      .font(.system(size: 14))
      .foregroundStyle(.secondary)
      .lineSpacing(3)
      .frame(
        height: 58, alignment: .topLeading,
      )
      .padding(.top, 10)

      VStack(alignment: .leading, spacing: 10) { tryItCardContent }
        .padding(14)
        .frame(
          maxWidth: .infinity, minHeight: 162, maxHeight: 162, alignment: .topLeading,
        )
        .background(
          Color(nsColor: .controlBackgroundColor).opacity(0.5),
          in: RoundedRectangle(cornerRadius: 9),
        )
        .padding(.top, 24)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(
      AccessibilityID.onboardingTryIt,
    )
    .accessibilityLabel("Try \(Channel.name)")
  }

  @ViewBuilder private var tryItCardContent: some View {
    switch store.step {
    case .permissions:
      unavailableContent(
        "Grant both permissions and wait for the speech model to try it.", symbol: "lock.shield",
      )
    case .model:
      unavailableContent(
        "Wait for the speech model to finish before trying a dictation.", symbol: "cpu",
      )
    case .tryIt:
      TextEditor(
        text: Binding(get: { store.tryItText }, set: { store.send(.tryItTextChanged($0)) }),
      )
      .font(.system(size: 15))
      .scrollContentBackground(.hidden)
      .padding(8)
      .frame(height: 96)
      .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
      .overlay {
        RoundedRectangle(cornerRadius: 7).strokeBorder(
          tryItFieldIsFocused ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1,
        )
      }
      .focused($tryItFieldIsFocused)
      .onAppear { tryItFieldIsFocused = true }
      .accessibilityIdentifier(AccessibilityID.onboardingTryItText)
      .accessibilityLabel(
        "Try dictation",
      )
      .accessibilityValue(store.tryItText)
      if let activationHotkey {
        HotkeyKeycaps(components: activationHotkey.displayComponents)
          .accessibilityHidden(true)
          .accessibilityPaintState(
            AccessibilityID.onboardingTryItHotkey, label: "Dictation hotkey",
            value: activationHotkey.displayName,
          )
      } else {
        Text("Activation shortcut not set")
          .font(.callout)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier(
            AccessibilityID.onboardingTryItHotkey,
          )
          .accessibilityLabel("Dictation hotkey")
          .accessibilityValue("Not set")
      }
    case .ready:
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 17))
          .foregroundStyle(
            Color.green,
          )
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

  private var readyContent: some View {
    VStack(alignment: .leading, spacing: 0) {
      ZStack {
        Circle().fill(Color.green.opacity(0.14)).frame(width: 58, height: 58)
        Image(systemName: "checkmark").font(.system(size: 25, weight: .bold)).foregroundStyle(
          .green,
        )
      }.accessibilityHidden(true)
      SemanticText("Ready", identifier: AccessibilityID.onboardingReadyTitle, label: "Setup status")
        .font(.system(size: 32, weight: .semibold))
        .padding(.top, 20)
      SemanticText(
        OnboardingCopy.readySummary(hotkeys: settings.hotkeys),
        identifier: AccessibilityID.onboardingReadySummary, label: "Ready instructions",
      )
      .font(.system(size: 14))
      .foregroundStyle(.secondary)
      .lineSpacing(3)
      .frame(
        maxWidth: 420, alignment: .leading,
      )
      .padding(.top, 10)
      if !store.tryItText.isEmpty {
        Text("“\(store.tryItText)”")
          .font(.system(size: 14))
          .italic()
          .lineLimit(3)
          .padding(.top, 24)
          .accessibilityIdentifier(AccessibilityID.onboardingReadyTranscript)
          .accessibilityLabel(
            "Completed dictation",
          )
          .accessibilityValue(store.tryItText)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(
      AccessibilityID.onboardingReady,
    )
    .accessibilityLabel("\(Channel.name) is ready")
  }

  private var footer: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let failureMessage = store.failureMessage {
        Label(failureMessage, systemImage: "exclamationmark.triangle.fill")
          .font(.system(size: 12))
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityElement(
            children: .ignore,
          )
          .accessibilityIdentifier(AccessibilityID.onboardingFailure)
          .accessibilityLabel(
            "Setup error",
          )
          .accessibilityValue(failureMessage)
      }
      HStack {
        if store.canSkip {
          Button("Skip") { store.send(.skip) }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(store.isMarkingCompletion)
            .accessibilityIdentifier(
              AccessibilityID.onboardingTryItSkip,
            )
            .accessibilityLabel("Skip test dictation")
        }
        Spacer()
        footerButtons
      }
    }
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
    case .model:
      if !store.modelSetupIsInProgress, store.snapshot.engineReadiness != .ready {
        Button(
          store.snapshot.engineReadiness.isFailure ? "Retry Model Setup" : "Download & Prepare",
        ) { store.send(.setupModel) }.buttonStyle(.borderedProminent).accessibilityIdentifier(
          AccessibilityID.onboardingModelRetry,
        )
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
        .accessibilityIdentifier(AccessibilityID.onboardingReadyFinish)
        .accessibilityLabel(
          "Start Dictating",
        )
    }
  }

  private func railItem(_ title: String, step: OnboardingStep, symbol: String) -> some View {
    let isCurrent = store.visibleStep == step || (store.visibleStep == .ready && step == .tryIt)
    let isComplete =
      switch step {
      case .permissions:
        store.snapshot.permissions.allGranted
      case .model:
        store.snapshot.engineReadiness == .ready
      case .tryIt,
           .ready:
        store.snapshot.isCompleted
      }
    return Button {
      store.send(.navigate(step))
    } label: {
      HStack(spacing: 10) {
        Image(systemName: isComplete ? "checkmark.circle.fill" : symbol)
          .frame(width: 18)
          .foregroundStyle(
            isComplete ? Color.green : isCurrent ? Color.accentColor : Color.secondary,
          )
          .accessibilityHidden(true)
        Text(title)
          .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
          .foregroundStyle(isCurrent ? Color.primary : Color.secondary)
        Spacer()
        if step == .model {
          compactModelProgress
        }
      }.contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .focusEffectDisabled()
    .accessibilityIdentifier(railAccessibilityID(step))
    .accessibilityLabel(title)
    .accessibilityValue(
      railAccessibilityValue(step: step, isComplete: isComplete, isCurrent: isCurrent),
    )
  }

  private func permissionRow(
    _ permission: OnboardingPermission, title: String, symbol: String, explanation: String,
  ) -> some View {
    let isGranted = store.snapshot.permissions.isGranted(permission)
    let ownsAction = store.activePermission == permission
    return HStack(spacing: 12) {
      Image(systemName: isGranted ? "checkmark.circle.fill" : symbol)
        .font(.system(size: 15))
        .foregroundStyle(isGranted ? Color.green : Color.accentColor)
        .frame(width: 20)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.system(size: 13, weight: .medium))
        Text(explanation).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(
          horizontal: false, vertical: true,
        )
      }
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier(
        permissionAccessibilityID(permission),
      )
      .accessibilityLabel(title)
      .accessibilityValue(explanation)
      Spacer(minLength: 12)
      let showsSettings =
        store.isRevisitingPermissions || store.state.needsSystemSettings(for: permission)
      let status = permissionStatus(permission, isGranted: isGranted, showsSettings: showsSettings)
      SemanticText(
        status, identifier: permissionStatusAccessibilityID(permission), label: "\(title) status",
      )
      .font(.system(size: 12, weight: .medium))
      .foregroundStyle(
        isGranted ? Color.green : Color.secondary,
      )
      if ownsAction, !isGranted, showsSettings {
        Button("Open Settings") { store.send(.openSystemSettings(permission)) }
          .accessibilityIdentifier(permissionActionAccessibilityID(permission))
          .accessibilityLabel(
            "Open \(title) Settings",
          )
      } else if ownsAction, !isGranted {
        Button("Grant") { store.send(.requestPermission(permission)) }
          .buttonStyle(
            .borderedProminent,
          )
          .disabled(store.requestingPermission != nil)
          .accessibilityIdentifier(
            permissionActionAccessibilityID(permission),
          )
          .accessibilityLabel("Grant \(title)")
      }
    }
    .accessibilityElement(children: .contain)
    .controlSize(.small)
    .padding(.horizontal, 14)
    .padding(
      .vertical, 9,
    )
  }

  private func stepSymbol(_ symbol: String) -> some View {
    ZStack {
      RoundedRectangle(cornerRadius: 13).fill(Color.accentColor.opacity(0.12)).frame(
        width: 58, height: 58,
      )
      Image(systemName: symbol).font(.system(size: 24, weight: .medium)).foregroundStyle(
        Color.accentColor,
      )
    }.accessibilityHidden(true)
  }

  private func progressRow(_ title: String, value: String) -> some View {
    HStack(spacing: 10) {
      ProgressView().controlSize(.small)
      Text(title).font(.system(size: 13, weight: .medium))
    }
    .accessibilityElement(children: .ignore)
    .accessibilityIdentifier(
      AccessibilityID.onboardingModelProgress,
    )
    .accessibilityLabel("Model preparation")
    .accessibilityValue(value)
  }

  private func unavailableContent(_ message: String, symbol: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(Color.accentColor).frame(
        width: 22,
      )
      Text(message).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(
        horizontal: false, vertical: true,
      )
    }
    .accessibilityElement(children: .ignore)
    .accessibilityIdentifier(
      AccessibilityID.onboardingTryItAvailability,
    )
    .accessibilityLabel("Try dictation availability")
    .accessibilityValue(message)
  }

  private func railAccessibilityID(_ step: OnboardingStep) -> String {
    switch step {
    case .permissions:
      AccessibilityID.onboardingRailPermissions
    case .model:
      AccessibilityID.onboardingRailModel
    case .tryIt,
         .ready:
      AccessibilityID.onboardingRailTryIt
    }
  }

  private func railAccessibilityValue(
    step: OnboardingStep, isComplete: Bool, isCurrent: Bool,
  ) -> String {
    if isComplete {
      return "Complete"
    }
    let position = isCurrent ? "Current" : "Available"
    guard step == .model else {
      return position
    }
    switch store.snapshot.engineReadiness {
    case let .downloading(fraction):
      return "\(position); Downloading \(Int(fraction * 100))%"
    case .compiling:
      return "\(position); Compiling"
    case .prewarming:
      return "\(position); Prewarming"
    case .modelMissing:
      return position
    case .ready:
      return "Complete"
    case .failed:
      return "\(position); Setup failed"
    }
  }

  private func permissionAccessibilityID(_ permission: OnboardingPermission) -> String {
    switch permission {
    case .microphone:
      AccessibilityID.onboardingPermissionMicrophone
    case .accessibility:
      AccessibilityID.onboardingPermissionAccessibility
    }
  }

  private func permissionStatusAccessibilityID(_ permission: OnboardingPermission) -> String {
    switch permission {
    case .microphone:
      AccessibilityID.onboardingPermissionMicrophoneStatus
    case .accessibility:
      AccessibilityID.onboardingPermissionAccessibilityStatus
    }
  }

  private func permissionActionAccessibilityID(_ permission: OnboardingPermission) -> String {
    switch permission {
    case .microphone:
      AccessibilityID.onboardingPermissionMicrophoneAction
    case .accessibility:
      AccessibilityID.onboardingPermissionAccessibilityAction
    }
  }

  private func permissionStatus(
    _ permission: OnboardingPermission, isGranted: Bool, showsSettings: Bool,
  ) -> String {
    if isGranted {
      return "Granted"
    }
    if store.requestingPermission == permission {
      return "Waiting"
    }
    if showsSettings {
      return "Needs settings"
    }
    return "Required"
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
