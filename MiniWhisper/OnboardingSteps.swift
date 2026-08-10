import ASREngine
import ComposableArchitecture
import SwiftUI

// MARK: - OnboardingStepPage

/// Every step wears the same silhouette — glyph, heading, a summary that reserves its height so
/// the card never moves, and a 162pt card. Written once so a new step inherits the layout instead
/// of copying it.
struct OnboardingStepPage<Card: View>: View {
  struct Line {
    let text: String
    let identifier: String
    let label: String
  }

  let symbol: String
  let title: Line
  let summary: Line
  var summaryLineLimit: Int?
  var summaryLineSpacing: CGFloat = 0
  var summaryMaxWidth: CGFloat?
  var cardPadding: CGFloat = 0
  var cardAlignment: Alignment = .center
  @ViewBuilder let card: Card

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ZStack {
        RoundedRectangle(cornerRadius: 13).fill(Color.accentColor.opacity(0.12)).frame(
          width: 58, height: 58,
        )
        Image(systemName: symbol).font(.system(size: 24, weight: .medium)).foregroundStyle(
          Color.accentColor,
        )
      }.accessibilityHidden(true)
      SemanticText(title.text, identifier: title.identifier, label: title.label)
        .font(.system(size: 28, weight: .semibold))
        .padding(.top, 20)
      SemanticText(summary.text, identifier: summary.identifier, label: summary.label)
        .font(.system(size: 14))
        .foregroundStyle(.secondary)
        .lineLimit(summaryLineLimit)
        .lineSpacing(summaryLineSpacing)
        .frame(
          maxWidth: summaryMaxWidth, minHeight: 58, maxHeight: 58, alignment: .topLeading,
        )
        .padding(.top, 10)
      card
        .padding(cardPadding)
        .frame(maxWidth: .infinity, minHeight: 162, maxHeight: 162, alignment: cardAlignment)
        .background(
          Color(nsColor: .controlBackgroundColor).opacity(0.5),
          in: RoundedRectangle(cornerRadius: 9),
        )
        .padding(.top, 24)
    }
    .accessibilityElement(children: .contain)
  }
}

// MARK: - OnboardingWelcomePage

struct OnboardingWelcomePage: View {
  let store: StoreOf<OnboardingFeature>

  var body: some View {
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
        .keyboardShortcut(.defaultAction)
        .padding(.top, 30)
        .accessibilityIdentifier(AccessibilityID.onboardingDownloadModel)
        .accessibilityLabel("Download Parakeet v2")
      if let failureMessage = store.failureMessage {
        Label(failureMessage, systemImage: "exclamationmark.triangle.fill")
          .font(.system(size: 12))
          .foregroundStyle(.red)
          .padding(.top, 16)
          .accessibilityElement(children: .ignore)
          .accessibilityIdentifier(AccessibilityID.onboardingWelcomeFailure)
          .accessibilityLabel("Model download error")
          .accessibilityValue(failureMessage)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(AccessibilityID.onboardingWelcome)
    .accessibilityLabel("Welcome to \(Channel.name)")
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

// MARK: - OnboardingStepRail

/// Mouse affordance only: the rail is never a Tab stop, so the keyboard's path through a page is
/// exactly the page's own controls.
struct OnboardingStepRail: View {
  // MARK: Internal

  let store: StoreOf<OnboardingFeature>

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Image(systemName: "mic.fill")
        .font(.system(size: 25, weight: .semibold))
        .foregroundStyle(Color.accentColor)
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
      .fixedSize(horizontal: false, vertical: true)
      .padding(.top, 3)

      VStack(alignment: .leading, spacing: 17) {
        railItem("Permissions", step: .permissions, symbol: "lock.shield")
        railItem("Shortcut", step: .shortcut, symbol: "command")
        railItem("Speech Model", step: .model, symbol: "cpu")
        railItem("Try It", step: .tryIt, symbol: "checkmark.bubble")
      }.padding(.top, 38)

      Spacer()
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(AccessibilityID.onboardingRail)
    .accessibilityLabel("Setup steps")
    .padding(.horizontal, 24)
    .padding(.vertical, 30)
    .frame(width: 210)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.62))
  }

  // MARK: Private

  @ViewBuilder private var compactModelProgress: some View {
    switch store.engineReadiness {
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

  private func railItem(_ title: String, step: OnboardingStep, symbol: String) -> some View {
    let isCurrent = store.visibleStep == step || (store.visibleStep == .ready && step == .tryIt)
    let isComplete =
      switch step {
      case .permissions:
        store.snapshot.permissions.allGranted
      case .shortcut:
        store.hasCompletedShortcut
      case .model:
        store.engineReadiness == .ready
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
    .focusable(false)
    .focusEffectDisabled()
    .disabled(store.isRecordingShortcut)
    .accessibilityIdentifier(OnboardingAccessibility.railIdentifier(step))
    .accessibilityLabel(title)
    .accessibilityValue(
      OnboardingAccessibility.railValue(
        step: step, readiness: store.engineReadiness, isComplete: isComplete,
        isCurrent: isCurrent,
      ),
    )
  }
}

// MARK: - OnboardingPermissionsPage

struct OnboardingPermissionsPage: View {
  // MARK: Internal

  let store: StoreOf<OnboardingFeature>

  var body: some View {
    OnboardingStepPage(
      symbol: "lock.shield",
      title: .init(
        text: "We need access to a few things first",
        identifier: AccessibilityID.onboardingPermissionsTitle, label: "Permissions heading",
      ),
      summary: .init(
        text: "macOS prompts for both. Grant them in the order they appear.",
        identifier: AccessibilityID.onboardingPermissionsSummary,
        label: "Permissions information",
      ),
      summaryLineLimit: 2,
    ) {
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
    }
    .accessibilityIdentifier(AccessibilityID.onboardingPermissions)
    .accessibilityLabel("Permissions setup")
  }

  // MARK: Private

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
      .accessibilityIdentifier(OnboardingAccessibility.permissionIdentifier(permission))
      .accessibilityLabel(title)
      .accessibilityValue(explanation)
      Spacer(minLength: 12)
      // Only an unfulfilled request sends the user to System Settings. Merely coming back to this
      // page is not that: macOS still has a prompt to give, and offering the pane instead strands
      // the user in front of a list the app has not yet earned a row in.
      let showsSettings = store.state.needsSystemSettings(for: permission)
      SemanticText(
        OnboardingAccessibility.permissionStatus(
          isGranted: isGranted, isRequesting: store.requestingPermission == permission,
          showsSettings: showsSettings,
        ),
        identifier: OnboardingAccessibility.permissionStatusIdentifier(permission),
        label: "\(title) status",
      )
      .font(.system(size: 12, weight: .medium))
      .foregroundStyle(isGranted ? Color.green : Color.secondary)
      if ownsAction, !isGranted {
        // The default action follows the row that still needs the user, so Return always means
        // "do the one thing this page is asking for".
        if showsSettings {
          Button("Open Settings") { store.send(.openSystemSettings(permission)) }
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier(
              OnboardingAccessibility.permissionActionIdentifier(permission),
            )
            .accessibilityLabel("Open \(title) Settings")
        } else {
          Button("Grant") { store.send(.requestPermission(permission)) }
            .buttonStyle(.borderedProminent)
            .disabled(store.requestingPermission != nil)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier(
              OnboardingAccessibility.permissionActionIdentifier(permission),
            )
            .accessibilityLabel("Grant \(title)")
        }
      }
    }
    .accessibilityElement(children: .contain)
    .controlSize(.small)
    .padding(.horizontal, 14)
    .padding(.vertical, 9)
  }
}

// MARK: - OnboardingModelPage

struct OnboardingModelPage: View {
  // MARK: Internal

  let store: StoreOf<OnboardingFeature>

  var body: some View {
    OnboardingStepPage(
      symbol: "cpu",
      title: .init(
        text: "Prepare Parakeet v2", identifier: AccessibilityID.onboardingModelTitle,
        label: "Model setup heading",
      ),
      summary: .init(
        text: "Downloads once (~450 MB), then everything runs on this Mac.",
        identifier: AccessibilityID.onboardingModelSummary, label: "Model setup information",
      ),
      summaryLineLimit: 1,
      summaryMaxWidth: 430,
      cardPadding: 18,
      cardAlignment: .topLeading,
    ) {
      VStack(alignment: .leading, spacing: 10) { cardContent }
    }
    .accessibilityIdentifier(AccessibilityID.onboardingModel)
    .accessibilityLabel("Speech model setup")
  }

  // MARK: Private

  @ViewBuilder private var cardContent: some View {
    switch store.engineReadiness {
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
          .accessibilityIdentifier(AccessibilityID.onboardingModelProgress)
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
        .accessibilityLabel("Model status")
        .accessibilityValue("Not installed")
    case .ready:
      Label("Parakeet v2 is ready", systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(AccessibilityID.onboardingModelStatus)
        .accessibilityLabel("Model status")
        .accessibilityValue("Ready")
    }
  }

  private func progressRow(_ title: String, value: String) -> some View {
    HStack(spacing: 10) {
      ProgressView().controlSize(.small)
      Text(title).font(.system(size: 13, weight: .medium))
    }
    .accessibilityElement(children: .ignore)
    .accessibilityIdentifier(AccessibilityID.onboardingModelProgress)
    .accessibilityLabel("Model preparation")
    .accessibilityValue(value)
  }
}

// MARK: - OnboardingReadyPage

struct OnboardingReadyPage: View {
  let store: StoreOf<OnboardingFeature>

  var body: some View {
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
        OnboardingCopy.readySummary(hotkeys: store.hotkeys),
        identifier: AccessibilityID.onboardingReadySummary, label: "Ready instructions",
      )
      .font(.system(size: 14))
      .foregroundStyle(.secondary)
      .lineSpacing(3)
      .frame(maxWidth: 420, alignment: .leading)
      .padding(.top, 10)
      if !store.tryItText.isEmpty {
        Text("“\(store.tryItText)”")
          .font(.system(size: 14))
          .italic()
          .lineLimit(3)
          .padding(.top, 24)
          .accessibilityIdentifier(AccessibilityID.onboardingReadyTranscript)
          .accessibilityLabel("Completed dictation")
          .accessibilityValue(store.tryItText)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(AccessibilityID.onboardingReady)
    .accessibilityLabel("\(Channel.name) is ready")
  }
}
