import AppSettings
import ASREngine
import ComposableArchitecture
import ModelLibrary
import SwiftUI

// MARK: - OnboardingStepPage

/// Shared heading and spacing keep each step aligned without enclosing its controls in cards.
struct OnboardingStepPage<Card: View>: View {
  struct Line {
    let text: String
    let identifier: String
    let label: String
  }

  let symbol: String
  let title: Line
  var summary: Line?
  var summaryLineLimit: Int?
  var summaryLineSpacing: CGFloat = 0
  var summaryMaxWidth: CGFloat?
  var cardPadding: CGFloat = 0
  var cardAlignment: Alignment = .center
  @ViewBuilder let card: Card

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      OnboardingStepHeader(
        symbol: symbol, title: title.text, identifier: title.identifier, label: title.label,
      )
      if let summary {
        SemanticText(summary.text, identifier: summary.identifier, label: summary.label)
          .font(.body)
          .foregroundStyle(.secondary)
          .lineLimit(summaryLineLimit)
          .lineSpacing(summaryLineSpacing)
          .frame(maxWidth: summaryMaxWidth, alignment: .topLeading)
          .padding(.top, 10)
      }
      card
        .padding(cardPadding)
        .frame(maxWidth: .infinity, alignment: cardAlignment)
        .padding(.top, 24)
    }
    .accessibilityElement(children: .contain)
  }
}

// MARK: - OnboardingStepHeader

struct OnboardingStepHeader: View {
  let symbol: String
  let title: String
  let identifier: String
  let label: String

  var body: some View {
    HStack(spacing: 16) {
      Image(systemName: symbol)
        .font(.title.weight(.medium))
        .foregroundStyle(Color.accentColor)
        .frame(width: 58, height: 58)
        .background(.tint.quinary, in: .rect(cornerRadius: 13))
        .accessibilityHidden(true)
      SemanticText(title, identifier: identifier, label: label)
        .font(.title.weight(.semibold))
    }
  }
}

// MARK: - OnboardingWelcomePage

/// Profile selection and its data-sharing facts stay together, before download consent.
struct OnboardingWelcomePage: View {
  // MARK: Internal

  let store: StoreOf<OnboardingFeature>
  var focus: FocusState<OnboardingFocus?>.Binding

  var body: some View {
    VStack(spacing: 0) {
      SemanticText(
        Channel.name, identifier: AccessibilityID.onboardingWelcomeTitle,
        label: "Application name",
      )
      .font(.largeTitle.weight(.semibold))
      VStack(alignment: .leading, spacing: 12) {
        profileChoice(lineup[0])
        HStack(spacing: 12) {
          ForEach(lineup.dropFirst()) { profileChoice($0) }
        }
      }
      .frame(width: 660)
      .padding(.top, 24)
      Button(store.welcomeActionTitle) { store.send(.downloadModel) }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(store.isRecordingModelDownloadConsent)
        .focused(focus, equals: .welcomeAction)
        .keyboardShortcut(.defaultAction)
        .padding(.top, 20)
        .accessibilityIdentifier(AccessibilityID.onboardingDownloadModel)
        .accessibilityLabel(store.welcomeActionTitle)
      SemanticText(
        store.welcomeFootnote, identifier: AccessibilityID.onboardingWelcomeModelInfo,
        label: "Model download information",
      )
      .font(.callout)
      .foregroundStyle(.secondary)
      .lineLimit(1)
      .padding(.top, 10)
      if let failureMessage = store.failureMessage {
        Label(failureMessage, systemImage: "exclamationmark.triangle.fill")
          .font(.system(size: 12))
          .foregroundStyle(.red)
          .padding(.top, 10)
          .accessibilityElement(children: .ignore)
          .accessibilityIdentifier(AccessibilityID.onboardingWelcomeFailure)
          .accessibilityLabel("Model download error")
          .accessibilityValue(failureMessage)
      }
    }
    // Tab reaches Continue; arrows choose the profile without starting a download.
    .background {
      WindowCharacterKeys { characters in
        switch characters {
        case FunctionKey.leftArrow,
             FunctionKey.upArrow:
          select(offset: -1)
        case FunctionKey.rightArrow,
             FunctionKey.downArrow:
          select(offset: 1)
        default:
          false
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(AccessibilityID.onboardingWelcome)
    .accessibilityLabel("Welcome to \(Channel.name)")
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: Private

  private var lineup: [Profile] {
    store.settings.profiles.lineup
  }

  private func profileChoice(_ profile: Profile) -> some View {
    let selected = store.profile.id == profile.id
    return Button { store.send(.profileSelected(profile.id)) } label: {
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Label(profile.name, systemImage: profile.symbol)
            .font(profile.id == .haiku ? .title2.weight(.semibold) : .headline)
          if profile.id == .haiku {
            Text("Recommended").font(.caption).foregroundStyle(.tint)
          }
        }
        .foregroundStyle(selected ? Color.accentColor : Color.primary)
        Text(description(profile.id))
          .font(.callout)
          .lineLimit(nil)
          .multilineTextAlignment(.leading)
          .foregroundStyle(Color.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
        if !profile.credentials.isEmpty, !profile.isCustom {
          VStack(alignment: .leading, spacing: 2) {
            Text("Requires:")
            ForEach(profile.credentials, id: \.self) { slot in
              Text("\(slot.provider.displayName) key")
            }
          }
          .font(.callout)
          .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .frame(height: profile.id == .haiku ? 94 : 128, alignment: .topLeading)
      .padding(10)
    }
    .buttonStyle(.bordered)
    .tint(selected ? Color.accentColor : Color.secondary)
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
        .allowsHitTesting(false)
    }
    .focusable(false)
    .accessibilityIdentifier(AccessibilityID.profilesCard(profile.id))
    .accessibilityLabel(choiceTitle(profile))
    .accessibilityValue(selected ? "Selected" : "Not selected")
  }

  private func choiceTitle(_ profile: Profile) -> String {
    profile.id == .haiku ? "\(profile.name) · Recommended" : profile.name
  }

  private func description(_ id: ProfileID) -> String {
    switch id {
    case .haiku:
      "The best balance of speed and accuracy."
    case .offline:
      "The most private. Nothing leaves your Mac."
    case .accurate:
      "The fewest mistakes, a little slower."
    case .cerebras:
      "Gets your words in the quickest."
    case .custom:
      "Your choice."
    }
  }

  private func select(offset: Int) -> Bool {
    guard let index = lineup.firstIndex(where: { $0.id == store.profile.id }),
          lineup.indices.contains(index + offset)
    else {
      return true
    }
    store.send(.profileSelected(lineup[index + offset].id))
    return true
  }
}

// MARK: - OnboardingStepRail

/// Numbered shortcuts revisit steps without lengthening the page's own Tab cycle.
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
        if !store.profile.credentials.isEmpty {
          railItem(
            store.profile.credentials.count == 1 ? "API Key" : "API Keys", step: .keys,
            symbol: "key", shortcut: "1",
          )
        }
        railItem("Permissions", step: .permissions, symbol: "lock.shield",
                 shortcut: store.profile.credentials.isEmpty ? "1" : "2")
        railItem("Shortcut", step: .shortcut, symbol: "command",
                 shortcut: store.profile.credentials.isEmpty ? "2" : "3")
        railItem("Speech Model", step: .model, symbol: "cpu",
                 shortcut: store.profile.credentials.isEmpty ? "3" : "4")
        railItem("Try It", step: .tryIt, symbol: "checkmark.bubble",
                 shortcut: store.profile.credentials.isEmpty ? "4" : "5")
      }.padding(.top, 38)

      Spacer()
      Text(store.profile.credentials.isEmpty ? "⌘1–4 to revisit a step" : "⌘1–5 to revisit a step")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(AccessibilityID.onboardingRail)
    .accessibilityLabel("Setup steps")
    .padding(.horizontal, 24)
    .padding(.vertical, 30)
    .frame(width: 210)
    .background(.background.secondary)
  }

  // MARK: Private

  @ViewBuilder private var compactModelProgress: some View {
    if let fraction = store.modelDownloadProgress {
      Text(DownloadProgress.percentage(fraction))
        .font(.caption2)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: true, vertical: false)
    } else {
      switch store.engineReadiness {
      case .compiling,
           .prewarming:
        ProgressView().controlSize(.mini)
      default:
        EmptyView()
      }
    }
  }

  private func railItem(
    _ title: String, step: OnboardingStep, symbol: String, shortcut: KeyEquivalent,
  ) -> some View {
    let isCurrent = store.visibleStep == step || (store.visibleStep == .ready && step == .tryIt)
    let isComplete =
      switch step {
      case .keys:
        store.storedKeys != nil && store.missingKeys.isEmpty
      case .permissions:
        store.snapshot.permissions.allGranted
      case .shortcut:
        store.hasCompletedShortcut
      case .model:
        store.isSetUp
      case .tryIt,
           .ready:
        store.snapshot.isCompleted
      }
    let problem: String? =
      switch step {
      case .keys where store.hasSkippedKeys && !store.missingKeys.isEmpty:
        "Needs a key"
      case .model where store.modelSetupFailure != nil:
        "Setup failed"
      default:
        nil
      }
    return Button {
      store.send(.navigate(step))
    } label: {
      HStack(spacing: 10) {
        Image(systemName: problem != nil ? "exclamationmark.triangle.fill"
          : isComplete ? "checkmark.circle.fill" : symbol)
          .frame(width: 18)
          .foregroundStyle(
            problem != nil ? Color.orange
              : isComplete ? Color.green : isCurrent ? Color.accentColor : Color.secondary,
          )
          .accessibilityHidden(true)
        Text(title)
          .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
          .foregroundStyle(isCurrent ? Color.primary : Color.secondary)
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
        Spacer()
        if step == .model {
          compactModelProgress
        }
      }.contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .focusable(false)
    .focusEffectDisabled()
    .keyboardShortcut(shortcut, modifiers: .command)
    .help("Go to \(title) (⌘\(String(shortcut.character)))")
    .disabled(store.isRecordingShortcut)
    .accessibilityIdentifier(OnboardingAccessibility.railIdentifier(step))
    .accessibilityLabel(title)
    .accessibilityValue(
      OnboardingAccessibility.railValue(
        step: step, engine: store.health.engine, readiness: store.engineReadiness,
        isComplete: isComplete, isCurrent: isCurrent, problem: problem,
        downloadProgress: store.cleanupAssets.isEmpty ? nil : store.modelDownloadProgress,
      ),
    )
  }
}

// MARK: - OnboardingKeysPage

/// Each key names its job; on-device dictation is the alternative to providing one.
struct OnboardingKeysPage: View {
  // MARK: Internal

  let store: StoreOf<OnboardingFeature>
  var focus: FocusState<OnboardingFocus?>.Binding

  var body: some View {
    OnboardingStepPage(
      symbol: "key",
      title: .init(
        text: title,
        identifier: AccessibilityID.onboardingKeysTitle,
        label: "Keys heading",
      ),
      summary: .init(
        text: "\(store.profile.name) needs \(store.profile.credentials.count == 1 ? "this key" : "these keys") before you can dictate. Keys stay in your Keychain.",
        identifier: AccessibilityID.onboardingKeysSummary, label: "Keys information",
      ),
      summaryMaxWidth: 430,
      cardPadding: 0,
      cardAlignment: .topLeading,
    ) {
      VStack(alignment: .leading, spacing: 12) {
        ForEach(store.profile.credentials, id: \.self) { slot in
          keyRow(slot)
        }
        Divider()
        Button("Use on-device dictation") {
          store.send(.useCustomTapped)
        }
        .buttonStyle(.bordered)
        .focused(focus, equals: .useCustom)
        .accessibilityIdentifier(AccessibilityID.onboardingKeysUseCustom)
        Text("Parakeet on this Mac, without cleanup. Downloads its speech model if needed.")
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .accessibilityIdentifier(AccessibilityID.onboardingKeys)
    .accessibilityLabel("API keys")
    .onChange(of: store.keyFailure) { _, failure in
      if let failure {
        focus.wrappedValue = .keyField(failure.slot)
      }
    }
  }

  // MARK: Private

  private var title: String {
    let slots = store.profile.credentials
    return slots.count == 1 ? "Add your \(slots[0].provider.displayName) key" : "Add your keys"
  }

  @ViewBuilder private func keyRow(_ slot: CredentialSlot) -> some View {
    let provider = slot.provider
    if store.missingKeys.contains(slot) {
      VStack(alignment: .leading, spacing: 6) {
        Text("\(provider.displayName) key")
          .font(.body)
        Text(slot == store.profile
          .engineCredential ? "Transcribes your audio." : "Cleans up your transcript.")
          .font(.callout)
          .foregroundStyle(.secondary)
        SecureField(
          "\(provider.displayName) key",
          text: Binding(
            get: { store.keyDrafts[slot] ?? "" },
            set: { store.send(.keyEdited(slot, $0)) },
          ),
          prompt: Text(provider.keyPrompt),
        )
        .textFieldStyle(.roundedBorder)
        .labelsHidden()
        .focused(focus, equals: .keyField(slot))
        .onSubmit { store.send(.keysContinueTapped) }
        .accessibilityIdentifier(AccessibilityID.onboardingKeyField(provider))
        .accessibilityLabel("\(provider.displayName) key")
        if let failure = store.keyFailure, failure.slot == slot {
          Label(failure.message, systemImage: "exclamationmark.circle.fill")
            .font(.callout)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier(AccessibilityID.onboardingFailure)
            .accessibilityLabel("Key error")
            .accessibilityValue(failure.message)
        }
        if let url = provider.keysURL {
          Link("Get a key from \(provider.displayName)", destination: url)
            .font(.system(size: 12))
            .focused(focus, equals: .keyHelp(slot))
            .accessibilityIdentifier(AccessibilityID.onboardingKeyLink(provider))
        }
      }
    } else {
      Label(
        "\(provider.displayName) key saved in your Keychain",
        systemImage: "checkmark.circle.fill",
      )
      .font(.system(size: 13))
      .foregroundStyle(.green)
      .accessibilityElement(children: .ignore)
      .accessibilityIdentifier(AccessibilityID.onboardingKeyField(provider))
      .accessibilityLabel("\(provider.displayName) key")
      .accessibilityValue("Saved")
    }
  }
}

// MARK: - OnboardingPermissionsPage

struct OnboardingPermissionsPage: View {
  // MARK: Internal

  let store: StoreOf<OnboardingFeature>
  var focus: FocusState<OnboardingFocus?>.Binding

  var body: some View {
    OnboardingStepPage(
      symbol: "lock.shield",
      title: .init(
        text: "Allow dictation access",
        identifier: AccessibilityID.onboardingPermissionsTitle, label: "Permissions heading",
      ),
    ) {
      VStack(spacing: 0) {
        permissionRow(
          .microphone, title: "Microphone", symbol: "waveform",
          explanation: "Records your voice while you dictate",
        )
        Divider()
          .padding(.horizontal, 10)
        permissionRow(
          .accessibility, title: "Accessibility", symbol: "keyboard",
          explanation: "Watches for your shortcut and pastes where you're typing",
        )
      }
    }
    .animation(.easeInOut(duration: 0.2), value: store.snapshot.permissions)
    .animation(.easeInOut(duration: 0.2), value: store.requestingPermission)
    .animation(.easeInOut(duration: 0.2), value: store.requestedPermissions)
    .accessibilityIdentifier(AccessibilityID.onboardingPermissions)
    .accessibilityLabel("Permissions setup")
  }

  // MARK: Private

  private func permissionRow(
    _ permission: OnboardingPermission, title: String, symbol: String, explanation: String,
  ) -> some View {
    let isGranted = store.snapshot.permissions.isGranted(permission)
    let ownsAction = store.activePermission == permission
    return HStack(spacing: 8) {
      Image(systemName: isGranted ? "checkmark.circle.fill" : symbol)
        .font(.system(size: 15))
        .foregroundStyle(isGranted ? Color.green : Color.accentColor)
        .frame(width: 20)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.system(size: 13, weight: .medium))
        Text(explanation)
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier(OnboardingAccessibility.permissionIdentifier(permission))
      .accessibilityLabel(title)
      .accessibilityValue(explanation)

      // Only an unfulfilled request sends the user to System Settings. Merely coming back to this
      // page is not that: macOS still has a prompt to give, and offering the pane instead strands
      // the user in front of a list the app has not yet earned a row in.
      let showsSettings = store.state.needsSystemSettings(for: permission)
      HStack(spacing: 8) {
        if !(ownsAction && showsSettings) {
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
        }
        if ownsAction {
          // The default action follows the row that still needs the user, so Return always means
          // "do the one thing this page is asking for".
          if showsSettings {
            Button("Open Settings") { store.send(.openSystemSettings(permission)) }
              .focused(focus, equals: .permissionsAction)
              .keyboardShortcut(.defaultAction)
              .accessibilityIdentifier(
                OnboardingAccessibility.permissionActionIdentifier(permission),
              )
              .accessibilityLabel("Open \(title) Settings")
          } else {
            Button("Grant") { store.send(.requestPermission(permission)) }
              .buttonStyle(.borderedProminent)
              .disabled(store.requestingPermission != nil)
              .focused(focus, equals: .permissionsAction)
              .keyboardShortcut(.defaultAction)
              .accessibilityIdentifier(
                OnboardingAccessibility.permissionActionIdentifier(permission),
              )
              .accessibilityLabel("Grant \(title)")
          }
        }
      }
      .frame(width: 124, alignment: .trailing)
    }
    .accessibilityElement(children: .contain)
    .controlSize(.small)
    .padding(.horizontal, 10)
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
        text: title, identifier: AccessibilityID.onboardingModelTitle,
        label: "Model setup heading",
      ),
      summary: .init(
        text: summary, identifier: AccessibilityID.onboardingModelSummary,
        label: "Model setup information",
      ),
      summaryLineLimit: 1,
      summaryMaxWidth: 430,
      cardPadding: 18,
      cardAlignment: .topLeading,
    ) {
      VStack(alignment: .leading, spacing: 10) {
        cardContent
        ForEach(store.cleanupAssets, id: \.self) { asset in
          Divider()
          partRow(asset)
        }
      }
      .animation(.easeInOut(duration: 0.2), value: store.engineReadiness)
    }
    .accessibilityIdentifier(AccessibilityID.onboardingModel)
    .accessibilityLabel("Speech model setup")
  }

  // MARK: Private

  private var engineName: String {
    store.health.engine.name
  }

  /// One model reads as itself; a set reads as the profile it makes up.
  private var title: String {
    let downloads = store.profile.assets.filter { $0 != .gate }
    return downloads.count == 1
      ? "Prepare \(downloads[0].name)" : "Prepare \(store.profile.name)"
  }

  private var summary: String {
    guard store.profile.engineCredential == nil else {
      return "Only the speech gate downloads; \(engineName) transcribes in the cloud."
    }
    return "Downloads once, then runs on this Mac."
  }

  @ViewBuilder private var cardContent: some View {
    switch store.engineReadiness {
    case let .downloading(fraction):
      downloadProgress(title: engineName, fraction: fraction)
    case .compiling:
      progressRow("Preparing Core ML models…", value: "Compiling")
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
    case let .failed(message):
      Label {
        SemanticText(
          message.hasPrefix("The network connection was lost.")
            ? "The network connection was lost. Check your connection." : message,
          identifier: AccessibilityID.onboardingModelStatus,
          label: "Model status",
        )
      } icon: {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
          .accessibilityHidden(true)
      }
      .font(.body.weight(.medium))
      .foregroundStyle(.primary)
      .fixedSize(horizontal: false, vertical: true)
    case .modelMissing:
      Label(
        "\(Self.size(store.health.engine.assets)) · downloaded once", systemImage: "internaldrive",
      )
      .font(.system(size: 12))
      .foregroundStyle(.secondary)
      .accessibilityElement(children: .ignore)
      .accessibilityIdentifier(AccessibilityID.onboardingModelStatus)
      .accessibilityLabel("Model status")
      .accessibilityValue("Not installed")
    case .credentialMissing:
      Label("Installed · waiting on a key", systemImage: "key")
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(AccessibilityID.onboardingModelStatus)
        .accessibilityLabel("Model status")
        .accessibilityValue("Needs a key")
    case .ready:
      Label("\(engineName) is ready", systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(AccessibilityID.onboardingModelStatus)
        .accessibilityLabel("Model status")
        .accessibilityValue("Ready")
    }
  }

  private func downloadProgress(title: String, fraction: Double) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        SemanticText(
          title, identifier: AccessibilityID.onboardingModelStatus,
          label: "Model status",
        ).font(.body.weight(.medium))
        Spacer()
        Text("\(DownloadProgress.percentage(fraction)) of \(Self.size(store.health.engine.assets))")
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
      }
      ProgressView(value: fraction)
        .progressViewStyle(.linear)
        .accessibilityIdentifier(AccessibilityID.onboardingModelProgress)
        .accessibilityLabel("Model download")
        .accessibilityValue(DownloadProgress.percentage(fraction))
    }
  }

  /// A model no engine owns reports only through the library, so it gets a row of its own under
  /// the engine's status.
  private func partRow(_ asset: ModelAsset) -> some View {
    let state = store.assets[asset]
    let value =
      switch state {
      case let .downloading(fraction):
        "\(DownloadProgress.percentage(fraction)) of \(Self.size([asset]))"
      case .installed:
        "Ready"
      case .failed:
        "Failed"
      case .missing,
           nil:
        Self.size([asset])
      }
    return VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 10) {
        partIcon(state).accessibilityHidden(true)
        Text(asset.name).font(.body.weight(.medium))
        Spacer()
        Text(value)
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
      if case let .downloading(fraction) = state {
        ProgressView(value: fraction).progressViewStyle(.linear)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityIdentifier(AccessibilityID.onboardingModelPart(asset))
    .accessibilityLabel(asset.name)
    .accessibilityValue(value)
  }

  /// Progress, never an arrow: nothing in this row is a button.
  @ViewBuilder private func partIcon(_ state: AssetState?) -> some View {
    switch state {
    case .downloading:
      EmptyView()
    case .installed:
      Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
    case .failed:
      Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
    case .missing,
         nil:
      Image(systemName: "clock").foregroundStyle(.secondary)
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

  private static func size(_ assets: [ModelAsset]) -> String {
    ByteCountFormatter.string(
      fromByteCount: Int64(assets.map(\.pinnedBytes).reduce(0, +)), countStyle: .file,
    )
  }
}

// MARK: - OnboardingReadyPage

struct OnboardingReadyPage: View {
  let store: StoreOf<OnboardingFeature>

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      OnboardingStepHeader(
        symbol: "checkmark", title: "Ready", identifier: AccessibilityID.onboardingReadyTitle,
        label: "Setup status",
      )
      SemanticText(
        OnboardingCopy.readySummary(hotkeys: store.hotkeys),
        identifier: AccessibilityID.onboardingReadySummary, label: "Ready instructions",
      )
      .font(.body)
      .foregroundStyle(.secondary)
      .lineSpacing(3)
      .frame(maxWidth: 420, alignment: .leading)
      .padding(.top, 10)
      Text("\(Channel.name) stays in the menu bar.")
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.top, 8)
      if !store.tryItText.isEmpty {
        Text("“\(store.tryItText)”")
          .font(.body)
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
