import AppSettings
import ASREngine
import ComposableArchitecture
import ModelLibrary
import SwiftUI

// MARK: - OnboardingStepPage

/// Every step wears the same silhouette — glyph, heading, a summary that reserves its height, and
/// an intrinsic card. Written once so a new step inherits the layout instead of copying it.
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
        .frame(maxWidth: .infinity, alignment: cardAlignment)
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

/// The choice and the consent on one page, so the download the profile needs starts on the first
/// click. Three over two, so every tradeoff is on screen at once and compared rather than read in
/// turn.
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
      .font(.system(size: 30, weight: .semibold))
      SemanticText(
        "Fast, accurate dictation that runs on your Mac.",
        identifier: AccessibilityID.onboardingWelcomeSummary, label: "Welcome summary",
      )
      .font(.system(size: 14))
      .foregroundStyle(.secondary)
      .padding(.top, 4)
      VStack(spacing: 10) {
        HStack(spacing: 10) {
          ForEach(lineup.prefix(3)) { card($0) }
        }
        .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 10) {
          ForEach(lineup.dropFirst(3)) { card($0) }
        }
        .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.top, 20)
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
      .font(.system(size: 12))
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
    // The cards are not Tab stops, so Tab still lands on the one button; the arrows choose.
    .background {
      WindowCharacterKeys { characters in
        switch characters {
        case FunctionKey.leftArrow:
          select(offset: -1)
        case FunctionKey.rightArrow:
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

  private func card(_ profile: Profile) -> some View {
    let isSelected = profile.id == store.profile.id
    // Only a key is worth saying here: every profile's downloads are named on the button.
    let note = profile.credentials.isEmpty
      ? nil : "Needs \(OnboardingFeature.State.keysPhrase(profile.credentials))"
    let selection = isSelected ? "Selected" : "Not selected"
    return ProfileCard(profile: profile, isSelected: isSelected) {
      store.send(.profileSelected(profile.id))
    } status: {
      if let note {
        Text(note)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .focusable(false)
    .frame(width: 220)
    .accessibilityValue(note.map { "\(selection); \($0)" } ?? selection)
  }

  private func select(offset: Int) -> Bool {
    guard let index = lineup.firstIndex(where: { $0.id == store.profile.id }),
          lineup.indices.contains(index + offset)
    else {
      return false
    }
    store.send(.profileSelected(lineup[index + offset].id))
    return true
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
        if !store.profile.credentials.isEmpty {
          railItem(
            store.profile.credentials.count == 1 ? "API Key" : "API Keys", step: .keys,
            symbol: "key",
          )
        }
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
      Text("\(Int(fraction * 100))%")
        .font(.caption2)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: true, vertical: false)
    case .compiling,
         .prewarming:
      ProgressView().controlSize(.mini)
    case .modelMissing,
         .credentialMissing,
         .ready,
         .failed:
      EmptyView()
    }
  }

  private func railItem(_ title: String, step: OnboardingStep, symbol: String) -> some View {
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
    .disabled(store.isRecordingShortcut)
    .accessibilityIdentifier(OnboardingAccessibility.railIdentifier(step))
    .accessibilityLabel(title)
    .accessibilityValue(
      OnboardingAccessibility.railValue(
        step: step, engine: store.health.engine, readiness: store.engineReadiness,
        isComplete: isComplete, isCurrent: isCurrent,
      ),
    )
  }
}

// MARK: - OnboardingKeysPage

/// A factory profile is prescriptive, so this page has no Skip. The only way past it is a profile
/// that needs no key, and the link says which one and what it costs.
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
        text: "\(store.profile.tagline) Keys stay in your Keychain and are used only by this profile.",
        identifier: AccessibilityID.onboardingKeysSummary, label: "Keys information",
      ),
      summaryMaxWidth: 430,
      cardPadding: 18,
      cardAlignment: .topLeading,
    ) {
      VStack(alignment: .leading, spacing: 12) {
        ForEach(store.profile.credentials, id: \.self) { slot in
          keyRow(slot)
        }
        Divider()
        Button("Use Custom to skip cleanup") {
          store.send(.useCustomTapped)
        }
        .buttonStyle(.link)
        .focused(focus, equals: .useCustom)
        .accessibilityIdentifier(AccessibilityID.onboardingKeysUseCustom)
      }
    }
    .accessibilityIdentifier(AccessibilityID.onboardingKeys)
    .accessibilityLabel("API keys")
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
        if let url = provider.keysURL {
          Link("Get a key from \(provider.displayName)", destination: url)
            .font(.system(size: 12))
            .focusable(false)
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
          explanation: "Listen for the hotkey and paste at your cursor.",
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
          .lineLimit(1)
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
    let size = Self.size(store.profile.assets)
    guard store.profile.engineCredential == nil else {
      return "Only the \(size) speech gate downloads; \(engineName) transcribes in the cloud."
    }
    return "Downloads once (\(size)), then runs on this Mac."
  }

  @ViewBuilder private var cardContent: some View {
    switch store.engineReadiness {
    case let .downloading(fraction):
      downloadProgress(title: "Downloading \(engineName)…", fraction: fraction)
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
    case .modelMissing,
         .failed:
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
  }

  /// A model no engine owns reports only through the library, so it gets a row of its own under
  /// the engine's status.
  private func partRow(_ asset: ModelAsset) -> some View {
    let state = store.assets[asset]
    let value =
      switch state {
      case let .downloading(fraction):
        "\(Int(fraction * 100))% of \(Self.size([asset]))"
      case .installed:
        "Ready"
      case .failed:
        "Failed"
      case .missing,
           nil:
        Self.size([asset])
      }
    return HStack(spacing: 10) {
      partIcon(state)
        .frame(width: 18)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(asset.name).font(.system(size: 13, weight: .medium))
        Text("Local cleanup").font(.system(size: 11)).foregroundStyle(.secondary)
      }
      Spacer()
      Text(value)
        .font(.system(size: 12))
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityIdentifier(AccessibilityID.onboardingModelPart(asset))
    .accessibilityLabel(asset.name)
    .accessibilityValue(value)
  }

  /// Progress, never an arrow: nothing in this row is a button.
  @ViewBuilder private func partIcon(_ state: AssetState?) -> some View {
    switch state {
    case let .downloading(fraction):
      ProgressView(value: fraction)
        .progressViewStyle(.circular)
        .controlSize(.small)
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

// MARK: - ProfileCard

/// One profile, whole: what it is, what it costs, and what it still needs. The welcome page lays
/// the lineup out as cards so the taglines get compared rather than read in turn.
struct ProfileCard<Status: View>: View {
  let profile: Profile
  let isSelected: Bool
  let select: () -> Void
  @ViewBuilder let status: Status

  var body: some View {
    Button(action: select) {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 8) {
          Image(systemName: profile.symbol)
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
          // A name is never truncated; a long one wraps instead.
          Text(profile.name)
            .fontWeight(.medium)
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 0)
        }
        Text(profile.tagline)
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
        Spacer(minLength: 0)
        status
          .font(.caption)
      }
      .padding(12)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(.quinary, in: .rect(cornerRadius: 8))
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .strokeBorder(
            isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator),
            lineWidth: isSelected ? 2 : 1,
          )
      }
      .contentShape(.rect(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(AccessibilityID.profilesCard(profile.id))
    .accessibilityLabel(profile.name)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
