// Disposable mock-up of the Profiles pane and the onboarding welcome page, for tickets 47 + 39.
// Not an Xcode target, imports no MiniWhisper code, must not ship. Every value below is invented.
//
//   swiftc -framework AppKit -framework SwiftUI \
//     spikes/profiles-mockup/ProfilesMockup.swift -o .build/profiles-mockup
//   .build/profiles-mockup pane-a           # pane variants: pane-a pane-b pane-c
//   .build/profiles-mockup welcome-a        # profile choice on welcome: welcome-a welcome-b welcome-c
//   .build/profiles-mockup onb-key          # the key step a factory profile adds to the rail
//   .build/profiles-mockup onb-models       # the per-profile model set
//
// Flags, in any order after the screen:
//   full          the lineup as it looks at five profiles, not two
//   needs-setup   the selected factory profile has no key yet
//   overridden    the factory profile's endpoint has been edited in place
//   offline          start on the offline profile (the multi-model download case)
//   custom-selected  start with Custom selected, so its own detail rows are on screen
//   light | dark  force an appearance
//   tall          a settings window tall enough to reach Downloaded models
//
// Written against .agents/skills/native-macos-ui: system containers own the layout, text styles
// instead of point sizes, semantic colors only, no control drawn by hand that AppKit provides.

import AppKit
import SwiftUI

// MARK: - Profile

/// A profile is a whole dictation stack. Engine, vocabulary strategy, cleanup endpoint, model,
/// prompt — one of them active at a time.
struct Profile: Identifiable, Hashable {
  let id: String
  let name: String
  /// One line, the tradeoff, no numbers: measurements rot faster than the UI that quotes them.
  let tagline: String
  let symbol: String
  let isFactory: Bool
  let engine: String
  let vocabulary: String
  let endpoint: String
  let model: String
  /// Whether the profile cannot run until a key exists. Custom's cleanup is optional, so it never
  /// asks for one.
  let needsKey: Bool
  let keyProvider: String
  /// Written as it reads mid-sentence, because "a ElevenLabs and Google key" is what assembling
  /// this from a provider name produces.
  var keyRequirement = ""
  let models: [ModelAsset]
}

struct ModelAsset: Identifiable, Hashable {
  let id: String
  let name: String
  let size: String
  let role: String
}

let parakeet = ModelAsset(
  id: "parakeet", name: "Parakeet TDT v2", size: "550 MB", role: "Speech recognition",
)
let ctcHelper = ModelAsset(
  id: "ctc", name: "Recognition helper", size: "78 MB", role: "Vocabulary boost",
)
let s1mini = ModelAsset(id: "s1", name: "s1-mini", size: "1.2 GB", role: "Local cleanup")

let haikuProfile = Profile(
  id: "haiku", name: "Parakeet + Claude Haiku",
  tagline: "Speech stays on this Mac; transcripts go to Anthropic for cleanup.",
  symbol: "sparkles", isFactory: true, engine: "Parakeet TDT v2",
  vocabulary: "Staged in the cleanup prompt",
  endpoint: "https://api.anthropic.com/v1", model: "claude-haiku-5-5", needsKey: true,
  keyProvider: "Anthropic", keyRequirement: "an Anthropic key", models: [parakeet],
)

let customProfile = Profile(
  id: "custom", name: "Custom",
  tagline: "Any OpenAI-compatible endpoint, or no cleanup at all.",
  symbol: "slider.horizontal.3", isFactory: false, engine: "Parakeet TDT v2",
  vocabulary: "Staged in the cleanup prompt",
  endpoint: "https://gateway.internal/v1", model: "gpt-oss-120b", needsKey: false,
  keyProvider: "your provider", models: [parakeet],
)

/// Not shipping in v1. Present under `full` so the picker can be judged at the size it will
/// actually reach rather than at the size it starts.
let futureProfiles = [
  Profile(
    id: "offline", name: "Offline",
    tagline: "Nothing leaves this Mac. Cleanup is simpler and vocabulary is less exact.",
    symbol: "airplane", isFactory: true, engine: "Parakeet TDT v2",
    vocabulary: "Boosted during recognition", endpoint: "On this Mac", model: "s1-mini",
    needsKey: false, keyProvider: "", models: [parakeet, ctcHelper, s1mini],
  ),
  Profile(
    id: "accurate", name: "Most accurate",
    tagline: "The best transcripts measured — your recordings are sent to ElevenLabs.",
    symbol: "target", isFactory: true, engine: "ElevenLabs Scribe v2",
    vocabulary: "Sent to the engine and the prompt",
    endpoint: "https://generativelanguage.googleapis.com", model: "gemini-3.6-flash",
    needsKey: true, keyProvider: "ElevenLabs and Google",
    keyRequirement: "ElevenLabs and Google keys", models: [],
  ),
  Profile(
    id: "cerebras", name: "Parakeet + Cerebras",
    tagline: "The quickest cleanup measured, at some cost to accuracy.",
    symbol: "bolt", isFactory: true, engine: "Parakeet TDT v2",
    vocabulary: "Staged in the cleanup prompt", endpoint: "https://api.cerebras.ai/v1",
    model: "gpt-oss-120b", needsKey: true, keyProvider: "Cerebras",
    keyRequirement: "a Cerebras key", models: [parakeet],
  ),
]

// MARK: - Status

enum ProfileStatus: Equatable {
  case active
  case ready
  case needsSetup(String)
}

// MARK: - Screen

enum Screen: String {
  case paneA = "pane-a"
  case paneB = "pane-b"
  case paneC = "pane-c"
  case welcomeA = "welcome-a"
  case welcomeB = "welcome-b"
  case welcomeC = "welcome-c"
  case onboardingKey = "onb-key"
  case onboardingModels = "onb-models"

  var isOnboarding: Bool {
    switch self {
    case .paneA, .paneB, .paneC: false
    default: true
    }
  }
}

// MARK: - Mock

@Observable final class Mock {
  // MARK: Lifecycle

  init() {
    let arguments = CommandLine.arguments.dropFirst().map { $0.lowercased() }
    screen = arguments.compactMap(Screen.init(rawValue:)).first ?? .paneA
    // The cards page always shows the whole lineup: comparing every option is what it is for.
    showsFullLineup = arguments.contains("full") || screen == .welcomeB
    isOverridden = arguments.contains("overridden")
    if arguments.contains("offline") {
      showsFullLineup = true
      selected = "offline"
    }
    if arguments.contains("custom-selected") {
      selected = "custom"
    }
    if arguments.contains("needs-setup") {
      keyedProfiles.remove("haiku")
    }
  }

  // MARK: Internal

  var screen = Screen.paneA
  var showsFullLineup = false
  var selected = "haiku"
  var keyedProfiles: Set<String> = ["haiku", "custom"]
  var isOverridden = false

  var cleanupEnabled = true
  var sidecarEnabled = false
  var timeout = 10
  var instructions = ""
  var keyEntry = ""
  var onboardingPage = OnboardingPage.welcome

  var profiles: [Profile] {
    showsFullLineup ? [haikuProfile] + futureProfiles + [customProfile] : [haikuProfile, customProfile]
  }

  var selectedProfile: Profile {
    profiles.first { $0.id == selected } ?? haikuProfile
  }

  func status(_ profile: Profile) -> ProfileStatus {
    if profile.needsKey, !keyedProfiles.contains(profile.id) {
      return .needsSetup("Needs \(profile.keyRequirement)")
    }
    if profile.id == "offline", !keyedProfiles.contains("offline-model") {
      return .needsSetup("Needs a 1.2 GB download")
    }
    return profile.id == selected ? .active : .ready
  }
}

enum OnboardingPage {
  case welcome
  case key
  case models
}

// MARK: - Status badge

/// Two facts in one slot: whether this profile is the one running, and whether it could run at
/// all. Colour carries the second because it is the one that costs the user a dictation.
struct StatusBadge: View {
  let status: ProfileStatus

  var body: some View {
    switch status {
    case .active:
      Label("Active", systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
        .labelStyle(.titleAndIcon)
    case .ready:
      EmptyView()
    case let .needsSetup(reason):
      Label(reason, systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
    }
  }
}

// MARK: - Variant A: rows

/// Every profile is a row, the way installed models are rows: the whole row is the choice, the
/// tagline lives under the name, and status sits at the trailing edge. Scales down the pane as the
/// lineup grows — five profiles is five rows before the details start.
struct ProfilePickerRows: View {
  @Bindable var mock: Mock

  var body: some View {
    Section("Profile") {
      ForEach(mock.profiles) { profile in
        let status = mock.status(profile)
        LabeledContent {
          StatusBadge(status: status)
            .font(.callout)
        } label: {
          HStack(spacing: 10) {
            Image(systemName: status == .active ? "checkmark.circle.fill" : profile.symbol)
              .foregroundStyle(status == .active ? Color.accentColor : Color.secondary)
              .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
              Text(profile.name)
              Text(profile.tagline)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
        .contentShape(.rect)
        .onTapGesture { mock.selected = profile.id }
      }
    }
  }
}

// MARK: - Variant B: pop-up

/// The settings-window default: one pop-up button, one row, constant height however long the
/// lineup gets. The tradeoff line moves under the control as a footer, so it is read once at the
/// moment of choosing rather than compared across rows.
struct ProfilePickerPopUp: View {
  @Bindable var mock: Mock

  var body: some View {
    Section {
      LabeledContent("Profile") {
        HStack(spacing: 10) {
          StatusBadge(status: mock.status(mock.selectedProfile))
            .font(.callout)
          Picker("", selection: $mock.selected) {
            ForEach(mock.profiles) { profile in
              Text(profile.name).tag(profile.id)
            }
          }
          .labelsHidden()
          .fixedSize()
        }
      }
    } footer: {
      Text(mock.selectedProfile.tagline)
    }
  }
}

// MARK: - Variant C: cards

/// Two across, each card a whole stack at a glance. Comparison is the point — the taglines sit
/// side by side rather than stacked — and the cost is vertical: five profiles is three rows of
/// cards before a single detail row appears.
struct ProfilePickerCards: View {
  @Bindable var mock: Mock

  var body: some View {
    Section("Profile") {
      LazyVGrid(
        columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
        spacing: 12,
      ) {
        ForEach(mock.profiles) { profile in
          card(profile)
        }
      }
      .padding(.vertical, 4)
    }
  }

  private func card(_ profile: Profile) -> some View {
    let status = mock.status(profile)
    let isSelected = profile.id == mock.selected
    return VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Image(systemName: profile.symbol)
          .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        Text(profile.name)
          .fontWeight(.medium)
          .lineLimit(1)
        Spacer(minLength: 0)
        if isSelected {
          Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
        }
      }
      Text(profile.tagline)
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
      StatusBadge(status: status)
        .font(.caption)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      Color(nsColor: .controlBackgroundColor).opacity(0.5),
      in: RoundedRectangle(cornerRadius: 8),
    )
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .strokeBorder(
          isSelected ? Color.accentColor : Color.secondary.opacity(0.25),
          lineWidth: isSelected ? 2 : 1,
        )
    }
    .contentShape(.rect)
    .onTapGesture { mock.selected = profile.id }
  }
}

// MARK: - Profiles pane

struct ProfilesPane: View {
  @Bindable var mock: Mock
  let variant: Screen

  var body: some View {
    Form {
      switch variant {
      case .paneB: ProfilePickerPopUp(mock: mock)
      case .paneC: ProfilePickerCards(mock: mock)
      default: ProfilePickerRows(mock: mock)
      }

      if mock.selectedProfile.isFactory {
        FactoryDetail(mock: mock)
      } else {
        CustomDetail(mock: mock)
      }

      Section("All profiles") {
        LabeledContent("Give up after") {
          Picker("", selection: $mock.timeout) {
            ForEach([5, 10, 20, 30], id: \.self) { Text("\($0) seconds").tag($0) }
          }
          .labelsHidden()
          .fixedSize()
        }
        LabeledContent("Additional instructions") {
          TextField(
            "", text: $mock.instructions,
            prompt: Text("keep it casual — lowercase greetings, don’t expand my contractions"),
            axis: .vertical,
          )
          .lineLimit(3, reservesSpace: true)
          .labelsHidden()
        }
      }

      ModelStorage(mock: mock)
    }
    .formStyle(.grouped)
  }
}

// MARK: - Factory detail

/// A factory profile arrives decided. Its rows are still editable — an endpoint that moves is a
/// profile the user can keep rather than abandon — and an edited one gains the way back.
struct FactoryDetail: View {
  @Bindable var mock: Mock

  var body: some View {
    let profile = mock.selectedProfile
    Section {
      LabeledContent("Speech", value: profile.engine)
      LabeledContent("Vocabulary", value: profile.vocabulary)
      if profile.id != "offline" {
        LabeledContent("Address") {
          TextField("", text: .constant(profile.endpoint))
            .labelsHidden()
        }
        KeyRow(mock: mock, profile: profile)
        LabeledContent("Model", value: profile.model)
      }
    } header: {
      HStack {
        Text(profile.name)
        Spacer()
        if mock.isOverridden {
          Button("Reset to Default") { mock.isOverridden = false }
            .controlSize(.small)
        }
      }
    } footer: {
      Text(
        """
        Transcripts are sent to this endpoint. Recorded audio never leaves this Mac. \
        If cleanup fails or runs past the limit, the transcript is delivered as heard.
        """,
      )
    }
  }
}

// MARK: - Custom detail

/// Today's Cleanup pane, unchanged, living inside a profile: cleanup is optional here, which is
/// what makes the sidecar toggle worth showing at all.
struct CustomDetail: View {
  @Bindable var mock: Mock

  var body: some View {
    Section {
      Toggle("Clean up transcripts", isOn: $mock.cleanupEnabled)
      LabeledContent("Address") {
        TextField("", text: .constant("https://gateway.internal/v1"), prompt: Text("https://gateway.example/v1"))
          .labelsHidden()
      }
      KeyRow(mock: mock, profile: mock.selectedProfile)
      LabeledContent("Model") {
        HStack(spacing: 8) {
          Picker("", selection: .constant("gpt-oss-120b")) {
            Text("gpt-oss-120b").tag("gpt-oss-120b")
            Text("claude-haiku-5-5").tag("claude-haiku-5-5")
            Divider()
            Text("Custom…").tag("custom")
          }
          .labelsHidden()
          .fixedSize()
          Button("Load Models") {}
          Button("Save") {}
            .buttonStyle(.bordered)
            .frame(minWidth: 76)
            .disabled(true)
        }
      }
    } header: {
      Text("Custom")
    } footer: {
      Text(
        """
        Transcripts are sent to this endpoint. Recorded audio never leaves this Mac. \
        If cleanup fails or runs past the limit, the transcript is delivered as heard.
        """,
      )
    }

    Section {
      Toggle("Improve recognition", isOn: $mock.sidecarEnabled)
    } footer: {
      Text(
        mock.cleanupEnabled
          ? "Your dictionary already reaches the cleanup model. Turning this on tends to cost more than it recovers."
          : "With cleanup off, this is the only way your dictionary reaches the transcript.",
      )
    }
  }
}

// MARK: - Key row

struct KeyRow: View {
  @Bindable var mock: Mock
  let profile: Profile

  var body: some View {
    LabeledContent("API key") {
      if mock.keyedProfiles.contains(profile.id) {
        HStack {
          Text("sk-ant-" + String(repeating: "•", count: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
          Button("Replace") { mock.keyedProfiles.remove(profile.id) }
        }
      } else {
        HStack {
          TextField("", text: $mock.keyEntry, prompt: Text("Paste your key"))
            .labelsHidden()
          Button("Save") { mock.keyedProfiles.insert(profile.id) }
            .buttonStyle(.borderedProminent)
        }
      }
    }
  }
}

// MARK: - Model storage

/// Profiles bring models with them, and a profile the user walked away from leaves its download
/// behind. This is the only place that says what is on disk and the only place that deletes it.
struct ModelStorage: View {
  @Bindable var mock: Mock

  var body: some View {
    Section {
      ForEach(installed) { asset in
        LabeledContent {
          HStack(spacing: 12) {
            Text(asset.size).foregroundStyle(.secondary)
            Button("Delete") {}
          }
        } label: {
          VStack(alignment: .leading, spacing: 2) {
            Text(asset.name)
            Text(usedBy(asset))
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        }
      }
      LabeledContent("Total on disk", value: mock.showsFullLineup ? "1.8 GB" : "628 MB")
    } header: {
      Text("Downloaded models")
    }
  }

  private var installed: [ModelAsset] {
    mock.showsFullLineup ? [parakeet, ctcHelper, s1mini] : [parakeet, ctcHelper]
  }

  /// A model the active profile does not use says so, because a download the user walked away
  /// from is exactly what they come here to delete.
  private func usedBy(_ asset: ModelAsset) -> String {
    let users = mock.profiles.filter { $0.models.contains(asset) }.map(\.name)
    let owners = users.isEmpty ? "not used by any profile" : users.joined(separator: ", ")
    let idle = mock.selectedProfile.models.contains(asset) || users.isEmpty ? "" : " — not in use"
    return "\(asset.role) · \(owners)\(idle)"
  }
}

// MARK: - Settings window shell

struct SettingsShell: View {
  @Bindable var mock: Mock
  let variant: Screen

  var body: some View {
    NavigationSplitView {
      List(selection: .constant("Profiles")) {
        Label("Settings", systemImage: "gearshape").tag("Settings")
        Section {
          Label("History", systemImage: "clock.arrow.circlepath").tag("History")
          Label("Dictionary", systemImage: "character.book.closed").tag("Dictionary")
          Label("Profiles", systemImage: "person.crop.rectangle.stack").tag("Profiles")
        }
      }
      .navigationSplitViewColumnWidth(min: 160, ideal: 176, max: 220)
    } detail: {
      ProfilesPane(mock: mock, variant: variant)
        .navigationTitle("Profiles")
    }
  }
}

// MARK: - Onboarding scaffold

/// The onboarding silhouette, replicated: rail, glyph, heading, a summary that reserves its
/// height, one card, one footer button.
struct OnboardingShell<Card: View>: View {
  @Bindable var mock: Mock
  let symbol: String
  let title: String
  let summary: String
  let action: String
  var actionEnabled = true
  var cardPadding: CGFloat = 0
  /// A page whose card needs the room takes it from the header: the glyph goes, the summary
  /// reserves two lines instead of three.
  var compactHeader = false
  @ViewBuilder let card: Card

  var body: some View {
    HStack(spacing: 0) {
      rail
      Divider()
      VStack(alignment: .leading, spacing: 0) {
        VStack(alignment: .leading, spacing: 0) {
          if !compactHeader {
            ZStack {
              RoundedRectangle(cornerRadius: 13).fill(Color.accentColor.opacity(0.12))
                .frame(width: 58, height: 58)
              Image(systemName: symbol)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color.accentColor)
            }
          }
          Text(title)
            .font(.system(size: 28, weight: .semibold))
            .padding(.top, compactHeader ? 0 : 20)
          Text(summary)
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .frame(
              maxWidth: 470, minHeight: compactHeader ? 38 : 58,
              maxHeight: compactHeader ? 38 : 58, alignment: .topLeading,
            )
            .padding(.top, 10)
          card
            .padding(cardPadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
              Color(nsColor: .controlBackgroundColor).opacity(0.5),
              in: RoundedRectangle(cornerRadius: 9),
            )
            .padding(.top, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        HStack {
          Spacer()
          Button(action) { mock.advance() }
            .buttonStyle(.borderedProminent)
            .disabled(!actionEnabled)
        }
      }
      .padding(.horizontal, 42)
      .padding(.vertical, 36)
    }
    .frame(width: 720, height: 500)
    .background(.background)
  }

  private var rail: some View {
    VStack(alignment: .leading, spacing: 0) {
      Image(systemName: "mic.fill")
        .font(.system(size: 25, weight: .semibold))
        .foregroundStyle(Color.accentColor)
      Text("MiniWhisper")
        .font(.system(size: 19, weight: .semibold))
        .padding(.top, 10)
      Text("fast and accurate dictation")
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.top, 3)
      VStack(alignment: .leading, spacing: 17) {
        // The profile was chosen on the welcome page, so it is not a step. Its key is, and only
        // for a profile that has one to ask for.
        if mock.selectedProfile.needsKey {
          railItem("Cleanup Key", symbol: "key.horizontal", step: .key)
        }
        railItem("Permissions", symbol: "lock.shield", step: nil)
        railItem("Shortcut", symbol: "command", step: nil)
        railItem("Speech Model", symbol: "cpu", step: .models)
        railItem("Try It", symbol: "checkmark.bubble", step: nil)
      }
      .padding(.top, 38)
      Spacer()
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 30)
    .frame(width: 210)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.62))
  }

  private func railItem(_ title: String, symbol: String, step: OnboardingPage?) -> some View {
    let isCurrent = step == mock.onboardingPage
    return HStack(spacing: 10) {
      Image(systemName: symbol)
        .frame(width: 18)
        .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
      Text(title)
        .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
        .foregroundStyle(isCurrent ? Color.primary : Color.secondary)
      Spacer()
    }
  }
}

extension Mock {
  /// Choosing a profile decides what onboarding still has to ask for: a key, or nothing.
  func advance() {
    switch onboardingPage {
    case .welcome:
      onboardingPage = selectedProfile.needsKey && !keyedProfiles.contains(selected)
        ? .key : .models
    case .key:
      keyedProfiles.insert(selected)
      onboardingPage = .models
    case .models:
      onboardingPage = .welcome
    }
  }

  /// The welcome button is the download consent, so it names what it downloads. A profile whose
  /// engine is hosted has nothing to download, and the button stops pretending it does.
  var welcomeAction: String {
    switch selectedProfile.models.count {
    case 0: "Get Started"
    case 1: "Download \(selectedProfile.models[0].name)"
    default: "Download \(selectedProfile.models.count) Models"
    }
  }

  var welcomeFootnote: String {
    let profile = selectedProfile
    let download = switch profile.models.count {
    case 0: "Nothing to download."
    case 1: "\(profile.models[0].size) downloads while you finish setup."
    default: "1.8 GB downloads while you finish setup."
    }
    return profile.needsKey ? "\(download) You'll add \(profile.keyRequirement) next." : download
  }
}

// MARK: - Onboarding: welcome

/// Today's welcome page, with the profile choice under the hero and the download consent still the
/// one button. The download starts the moment it is pressed, which is the point of asking here
/// rather than one page later. A variant whose choice needs the room takes it from the hero.
struct WelcomeShell<Choice: View>: View {
  @Bindable var mock: Mock
  var compactHero = false
  @ViewBuilder let choice: Choice

  var body: some View {
    VStack(spacing: 0) {
      if !compactHero {
        ZStack {
          RoundedRectangle(cornerRadius: 18).fill(Color.accentColor.opacity(0.12))
            .frame(width: 72, height: 72)
          Image(systemName: "mic.fill")
            .font(.system(size: 32, weight: .semibold))
            .foregroundStyle(Color.accentColor)
        }
        .padding(.bottom, 18)
      }
      Text("MiniWhisper")
        .font(.system(size: compactHero ? 26 : 30, weight: .semibold))
      Text("Fast, accurate dictation that runs on your Mac.")
        .font(.system(size: compactHero ? 14 : 16))
        .foregroundStyle(.secondary)
        .padding(.top, 6)
      choice
        .padding(.top, compactHero ? 18 : 24)
      Button(mock.welcomeAction) { mock.advance() }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
        .padding(.top, compactHero ? 18 : 24)
      Text(mock.welcomeFootnote)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.top, 10)
    }
    .padding(.horizontal, 42)
    .padding(.vertical, 30)
    .frame(width: 720, height: 500)
    .background(.background)
  }
}

// MARK: - Welcome A: list

/// The pane's row grammar on the welcome page: every profile is a radio row with its tradeoff
/// under its name. At five profiles the hero gives up its glyph and the rows still fit.
struct WelcomeList: View {
  @Bindable var mock: Mock

  var body: some View {
    WelcomeShell(mock: mock, compactHero: mock.profiles.count > 3) {
      VStack(spacing: 0) {
        ForEach(Array(mock.profiles.enumerated()), id: \.element.id) { index, profile in
          if index > 0 {
            Divider()
          }
          row(profile)
        }
      }
      .background(
        Color(nsColor: .controlBackgroundColor).opacity(0.5),
        in: RoundedRectangle(cornerRadius: 9),
      )
      .frame(width: 500)
    }
  }

  private func row(_ profile: Profile) -> some View {
    let isSelected = profile.id == mock.selected
    let isCrowded = mock.profiles.count > 3
    return HStack(spacing: 10) {
      Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
        .font(.system(size: 15))
        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        .frame(width: 20)
      VStack(alignment: .leading, spacing: 2) {
        Text(profile.name).font(.system(size: 13, weight: .medium))
        Text(profile.tagline)
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .lineLimit(isCrowded ? 1 : 2)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      if profile.needsKey {
        Text(profile.keyRequirement.hasSuffix("keys") ? "Keys required" : "Key required")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, isCrowded ? 7 : 10)
    .contentShape(.rect)
    .onTapGesture { mock.selected = profile.id }
  }
}

// MARK: - Welcome B: cards

/// Every profile side by side, so the tradeoffs are compared rather than read in turn. Each card
/// ends with what it costs to set up. Five profiles is a row of three over a centered row of two,
/// and no hero glyph.
struct WelcomeCards: View {
  @Bindable var mock: Mock

  var body: some View {
    let isCrowded = mock.profiles.count > 3
    let perRow = isCrowded ? 3 : 2
    let rows = stride(from: 0, to: mock.profiles.count, by: perRow).map {
      Array(mock.profiles[$0 ..< min($0 + perRow, mock.profiles.count)])
    }
    WelcomeShell(mock: mock, compactHero: isCrowded) {
      VStack(spacing: 12) {
        ForEach(rows, id: \.first!.id) { row in
          HStack(spacing: 12) {
            ForEach(row) { profile in
              card(profile, isCrowded: isCrowded)
                .frame(width: isCrowded ? 198 : 254)
            }
          }
          .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  private func card(_ profile: Profile, isCrowded: Bool) -> some View {
    let isSelected = profile.id == mock.selected
    return VStack(alignment: .leading, spacing: isCrowded ? 4 : 6) {
      HStack(spacing: 7) {
        Image(systemName: profile.symbol)
          .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        Text(profile.name)
          .font(.system(size: 13, weight: .semibold))
          .lineLimit(1)
      }
      Text(profile.tagline)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .lineLimit(isCrowded ? 3 : 2)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .topLeading)
      Spacer(minLength: 0)
      Text(profile.needsKey ? "Needs \(profile.keyRequirement)" : "Nothing else to set up")
        .font(.system(size: 11))
        .foregroundStyle(profile.needsKey ? Color.secondary : Color.green)
    }
    .padding(10)
    .frame(maxWidth: .infinity, minHeight: isCrowded ? 92 : 104, maxHeight: .infinity, alignment: .topLeading)
    .background(
      Color(nsColor: .controlBackgroundColor).opacity(0.5),
      in: RoundedRectangle(cornerRadius: 9),
    )
    .overlay {
      RoundedRectangle(cornerRadius: 9)
        .strokeBorder(
          isSelected ? Color.accentColor : Color.secondary.opacity(0.25),
          lineWidth: isSelected ? 2 : 1,
        )
    }
    .contentShape(.rect)
    .onTapGesture { mock.selected = profile.id }
  }
}

// MARK: - Welcome C: pop-up

/// Today's welcome page with one control added: the profile is a pop-up, preselected to the
/// default, its tradeoff underneath. The page looks the same at two profiles and at twenty, and a
/// user who reads nothing gets the default — which is also the lineup nobody compares.
struct WelcomePopUp: View {
  @Bindable var mock: Mock

  var body: some View {
    WelcomeShell(mock: mock) {
      VStack(spacing: 8) {
        Picker("Profile", selection: $mock.selected) {
          ForEach(mock.profiles) { profile in
            Label(profile.name, systemImage: profile.symbol).tag(profile.id)
          }
        }
        .pickerStyle(.menu)
        .fixedSize()
        Text(mock.selectedProfile.tagline)
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .frame(width: 420, height: 32, alignment: .top)
      }
    }
  }
}

// MARK: - Onboarding: key

/// The factory profile is prescriptive, so this page has no Skip: the profile it belongs to cannot
/// run without it. The way past it is back to the picker and a different profile.
struct OnboardingKeyPage: View {
  @Bindable var mock: Mock

  var body: some View {
    let profile = mock.selectedProfile
    return OnboardingShell(
      mock: mock, symbol: "key.horizontal", title: "Add your \(profile.keyProvider) key",
      summary: "\(profile.name) cleans up transcripts with \(profile.model). The key is stored in your Keychain and used only for that.",
      action: "Continue", actionEnabled: !mock.keyEntry.isEmpty, cardPadding: 18,
    ) {
      VStack(alignment: .leading, spacing: 12) {
        TextField("", text: $mock.keyEntry, prompt: Text("sk-ant-…"))
          .textFieldStyle(.roundedBorder)
          .labelsHidden()
        HStack(spacing: 6) {
          Link(
            "Get a key from \(profile.keyProvider)",
            destination: URL(string: "https://console.anthropic.com/settings/keys")!,
          )
          .font(.system(size: 12))
          Text("· takes about a minute")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        Divider()
        // The download already started on the welcome page. Custom runs the same Parakeet, so
        // switching here costs nothing; a profile with a different model set would not be so kind.
        Button("Use the Custom profile instead — no key, no cleanup") {
          mock.selected = "custom"
          mock.onboardingPage = .models
        }
        .buttonStyle(.link)
        .font(.system(size: 12))
      }
    }
  }
}

// MARK: - Onboarding: models

/// One profile, a set of downloads. Today it is one file; the offline profile is three, and the
/// page has to read the same either way — one bar for the whole job, the parts underneath it.
struct OnboardingModelsPage: View {
  @Bindable var mock: Mock

  var body: some View {
    let profile = mock.selectedProfile
    let assets = profile.models.isEmpty ? [parakeet] : profile.models
    return OnboardingShell(
      mock: mock, symbol: "cpu", title: "Prepare \(profile.name)",
      summary: "Downloads once (\(total(assets))), then \(assets.count == 1 ? "it runs" : "they run") on this Mac.",
      action: "Continue", actionEnabled: false, cardPadding: 18,
    ) {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("Downloading…").font(.system(size: 13, weight: .medium))
          Spacer()
          Text("41%").monospacedDigit().foregroundStyle(.secondary)
        }
        ProgressView(value: 0.41).progressViewStyle(.linear)
        VStack(spacing: 0) {
          ForEach(Array(assets.enumerated()), id: \.element.id) { index, asset in
            if index > 0 {
              Divider()
            }
            assetRow(asset, index: index)
          }
        }
        .padding(.top, 2)
      }
    }
  }

  private func total(_ assets: [ModelAsset]) -> String {
    assets.count == 1 ? assets[0].size : "\(assets.count) files, 1.8 GB"
  }

  private func assetRow(_ asset: ModelAsset, index: Int) -> some View {
    HStack(spacing: 10) {
      Image(systemName: index == 0 ? "arrow.down.circle.fill" : "clock")
        .foregroundStyle(index == 0 ? Color.accentColor : Color.secondary)
        .frame(width: 18)
      VStack(alignment: .leading, spacing: 2) {
        Text(asset.name).font(.system(size: 13, weight: .medium))
        Text(asset.role).font(.system(size: 11)).foregroundStyle(.secondary)
      }
      Spacer()
      Text(index == 0 ? "41% of \(asset.size)" : asset.size)
        .font(.system(size: 12))
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }
    .padding(.vertical, 8)
  }
}

// MARK: - Root

struct Root: View {
  @Bindable var mock: Mock
  let variant: Screen

  var body: some View {
    switch mock.onboardingPage {
    case .key where variant.isOnboarding:
      OnboardingKeyPage(mock: mock)
    case .models where variant.isOnboarding:
      OnboardingModelsPage(mock: mock)
    default:
      switch variant {
      case .welcomeA: WelcomeList(mock: mock)
      case .welcomeB: WelcomeCards(mock: mock)
      case .welcomeC: WelcomePopUp(mock: mock)
      case .onboardingKey: OnboardingKeyPage(mock: mock)
      case .onboardingModels: OnboardingModelsPage(mock: mock)
      default: SettingsShell(mock: mock, variant: variant)
      }
    }
  }
}

// MARK: - Host

final class Delegate: NSObject, NSApplicationDelegate {
  let mock = Mock()
  var window: NSWindow!

  func applicationDidFinishLaunching(_: Notification) {
    let arguments = CommandLine.arguments.dropFirst().map { $0.lowercased() }
    if arguments.contains("light") {
      NSApp.appearance = NSAppearance(named: .aqua)
    } else if arguments.contains("dark") {
      NSApp.appearance = NSAppearance(named: .darkAqua)
    }
    switch mock.screen {
    case .onboardingKey: mock.onboardingPage = .key
    case .onboardingModels: mock.onboardingPage = .models
    default: mock.onboardingPage = .welcome
    }
    if mock.screen.isOnboarding {
      window = NSWindow(
        contentRect: .zero, styleMask: [.titled, .fullSizeContentView], backing: .buffered,
        defer: false,
      )
      window.titleVisibility = .hidden
      window.titlebarAppearsTransparent = true
    } else {
      window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 880, height: arguments.contains("tall") ? 1180 : 680),
        styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
        backing: .buffered, defer: false,
      )
      window.title = "MiniWhisper"
      window.toolbarStyle = .unified
    }
    window.contentView = NSHostingView(rootView: Root(mock: mock, variant: mock.screen))
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    // `screencapture -l` wants the CGWindowID, which is exactly this.
    print(window.windowNumber)
    fflush(stdout)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
