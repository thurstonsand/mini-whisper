// Disposable mock-up of four Profiles pane layouts. Not an Xcode target, imports no MiniWhisper
// code, must not ship. Every value below is invented or copied from docs/designs/04-profiles.md.
//
//   swiftc -framework AppKit -framework SwiftUI \
//     spikes/profiles-pane-mockup/ProfilesPaneMockup.swift -o .build/profiles-pane-mockup
//   .build/profiles-pane-mockup a              # variants: a b c d
//
// Flags, in any order after the variant:
//   accurate-nokey   Most accurate is active, its ElevenLabs key is missing
//   offline-nos1     Offline is active, S1-mini is not downloaded
//   models           Most accurate is active with every key; the view opens on the models
//   browse           Haiku is active, Most accurate is being looked at (B and C only)
//   downloading      Haiku is active, Parakeet TDT v2 is 42% downloaded
//   custom           Custom is active
//   overridden       Haiku's model has been edited, so Reset to Default exists
//   tall             a window 1400 pt tall, so the whole pane is in one image
//   light | dark     force an appearance
//
// Written against .agents/skills/native-macos-ui: Form + .formStyle(.grouped) owns the layout,
// LabeledContent for every label/value row, text styles not point sizes, semantic colors only.

import AppKit
import SwiftUI

// MARK: - Domain

enum ProfileID: String, CaseIterable, Identifiable, Hashable {
  case haiku, offline, accurate, cerebras, custom
  var id: String { rawValue }
}

enum AssetID: String, CaseIterable, Identifiable, Hashable {
  case gate, parakeet, s1
  var id: String { rawValue }
}

struct Asset {
  let id: AssetID
  let name: String
  let megabytes: Double
  let role: String
  let usedBy: String
  var size: String { formatSize(megabytes) }
}

let assets: [Asset] = [
  Asset(id: .gate, name: "Speech gate", megabytes: 1.1, role: "Silence rejection", usedBy: "Every profile"),
  Asset(
    id: .parakeet, name: "Parakeet TDT v2", megabytes: 567.2, role: "Speech recognition",
    usedBy: "Every profile but Most accurate",
  ),
  Asset(id: .s1, name: "S1-mini", megabytes: 484.2, role: "Cleanup on this Mac", usedBy: "Offline"),
]

func asset(_ id: AssetID) -> Asset { assets.first { $0.id == id }! }

func formatSize(_ megabytes: Double) -> String {
  megabytes >= 1000 ? String(format: "%.2f GB", megabytes / 1000) : String(format: "%.1f MB", megabytes)
}

/// One Keychain slot. A credential belongs to a profile, not to a provider.
struct KeySlot: Hashable {
  let id: String
  let provider: String
  let article: String
  let masked: String
  var label: String { "\(provider) key" }
}

let anthropicKey = KeySlot(id: "haiku.anthropic", provider: "Anthropic", article: "an", masked: "sk-ant-")
let elevenLabsKey = KeySlot(id: "accurate.elevenlabs", provider: "ElevenLabs", article: "an", masked: "sk_")
let googleKey = KeySlot(id: "accurate.google", provider: "Google", article: "a", masked: "AIzaSy")
let cerebrasKey = KeySlot(id: "cerebras.cerebras", provider: "Cerebras", article: "a", masked: "csk-")
let customKey = KeySlot(id: "custom.endpoint", provider: "API", article: "an", masked: "sk-")

enum CleanupLeg {
  case hosted(endpoint: String, model: String, key: KeySlot, provider: String)
  case local
  case custom
}

struct Profile: Identifiable {
  let id: ProfileID
  let name: String
  let tagline: String
  let symbol: String
  let engine: String
  let engineIsHosted: Bool
  var engineKey: KeySlot?
  let vocabulary: String
  let cleanup: CleanupLeg
  let assets: [AssetID]
  let privacy: String
  /// What leaves this Mac, in a word or two, for a column.
  let sendsOut: String

  var isFactory: Bool { id != .custom }

  var requiredKeys: [KeySlot] {
    var keys: [KeySlot] = []
    if let engineKey { keys.append(engineKey) }
    if case let .hosted(_, _, key, _) = cleanup { keys.append(key) }
    return keys
  }
}

let profiles: [Profile] = [
  Profile(
    id: .haiku, name: "Parakeet + Claude Haiku",
    tagline: "Speech stays on this Mac; transcripts go to Anthropic for cleanup.",
    symbol: "sparkles", engine: "Parakeet TDT v2", engineIsHosted: false,
    vocabulary: "In the cleanup prompt",
    cleanup: .hosted(
      endpoint: "https://api.anthropic.com/v1", model: "claude-haiku-5-5", key: anthropicKey,
      provider: "Anthropic",
    ),
    assets: [.gate, .parakeet],
    privacy: "Recorded audio never leaves this Mac. Transcripts go to Anthropic for cleanup.",
    sendsOut: "Transcripts",
  ),
  Profile(
    id: .offline, name: "Offline",
    tagline: "Nothing leaves this Mac. Lighter cleanup, recognition tuned to your words.",
    symbol: "lock.laptopcomputer", engine: "Parakeet TDT v2", engineIsHosted: false,
    vocabulary: "Boosted during recognition", cleanup: .local, assets: [.gate, .parakeet, .s1],
    privacy: "Recorded audio and transcripts never leave this Mac.", sendsOut: "Nothing",
  ),
  Profile(
    id: .accurate, name: "Most accurate",
    tagline: "The fewest mistakes. Your audio goes to ElevenLabs, transcripts to Google.",
    symbol: "scope", engine: "ElevenLabs Scribe v2", engineIsHosted: true, engineKey: elevenLabsKey,
    vocabulary: "Scribe keyterms and the cleanup prompt",
    cleanup: .hosted(
      endpoint: "https://generativelanguage.googleapis.com/v1beta/openai", model: "gemini-3.8-flash",
      key: googleKey, provider: "Google",
    ),
    assets: [.gate],
    privacy: "Recorded audio goes to ElevenLabs. Transcripts go to Google for cleanup.",
    sendsOut: "Audio, transcripts",
  ),
  Profile(
    id: .cerebras, name: "Parakeet + Cerebras",
    tagline: "The quickest cleanup measured, at some cost to accuracy.",
    symbol: "bolt", engine: "Parakeet TDT v2", engineIsHosted: false,
    vocabulary: "In the cleanup prompt",
    cleanup: .hosted(
      endpoint: "https://api.cerebras.ai/v1", model: "gpt-oss-120b", key: cerebrasKey,
      provider: "Cerebras",
    ),
    assets: [.gate, .parakeet],
    privacy: "Recorded audio never leaves this Mac. Transcripts go to Cerebras for cleanup.",
    sendsOut: "Transcripts",
  ),
  Profile(
    id: .custom, name: "Custom", tagline: "Any OpenAI-compatible endpoint, or no cleanup at all.",
    symbol: "slider.horizontal.3", engine: "Parakeet TDT v2", engineIsHosted: false,
    vocabulary: "", cleanup: .custom, assets: [.gate, .parakeet],
    privacy: "Recorded audio never leaves this Mac. Transcripts go to the address above.",
    sendsOut: "Transcripts",
  ),
]

func profile(_ id: ProfileID) -> Profile { profiles.first { $0.id == id }! }

// MARK: - Readiness

enum Readiness: Equatable {
  case ready
  case needs(String)
  case downloading(String, Double)
  /// A calm, grey fact that is not a problem: Custom with no cleanup set up.
  case note(String)
}

enum Variant: String {
  case a, b, c, d
}

/// B's in-pane list: a profile, or the storage entry under them.
enum ListItem: Hashable {
  case profile(ProfileID)
  case models
}

enum Destination: String {
  case settings = "Settings", history = "History", dictionary = "Dictionary"
  case profiles = "Profiles", models = "Models", downloads = "Downloads"
}

// MARK: - Mock

@Observable final class Mock {
  // MARK: Lifecycle

  init() {
    let arguments = CommandLine.arguments.dropFirst().map { $0.lowercased() }
    variant = arguments.compactMap(Variant.init(rawValue:)).first ?? .a
    if arguments.contains("accurate-nokey") {
      active = .accurate
      storedKeys = [anthropicKey.id, googleKey.id, customKey.id]
    }
    if arguments.contains("offline-nos1") {
      active = .offline
      installed.remove(.s1)
    }
    if arguments.contains("models") {
      active = .accurate
      storedKeys = [anthropicKey.id, elevenLabsKey.id, googleKey.id, customKey.id]
      opensOnModels = true
    }
    if arguments.contains("browse") {
      browsed = .accurate
      showsChooser = variant == .c
    }
    if arguments.contains("downloading") {
      installed.remove(.parakeet)
      downloading[.parakeet] = 0.42
      opensOnModels = variant == .d
    }
    if arguments.contains("custom") {
      active = .custom
    }
    if arguments.contains("overridden") {
      modelOverrides[.haiku] = "claude-sonnet-5"
    }
    func number(_ name: String) -> Int {
      arguments.first { $0.hasPrefix(name + "=") }.flatMap { Int($0.dropFirst(name.count + 1)) } ?? 0
    }
    if arguments.contains("r2") {
      round2 = true
      variant = .d
      scopeStyle = number("scope")
      downloadsStyle = number("downloads")
      keyStyle = number("key")
      if downloadsStyle > 0 {
        active = .accurate
        storedKeys = [anthropicKey.id, elevenLabsKey.id, googleKey.id, customKey.id]
      }
      if keyStyle > 0 {
        active = .custom
        storedKeys.remove(customKey.id)
        customEndpoint = "http://localhost:11434/v1"
        customModel = "qwen3:32b"
        noKeyNeeded = keyStyle == 1
        keyRequiredByEndpoint = arguments.contains("key-required")
      }
      if arguments.contains("overridden2") {
        endpointOverrides[.haiku] = "https://llm-gateway.corp.example/anthropic/v1"
        modelOverrides[.haiku] = "anthropic.claude-haiku-5-5-v1:0"
        editingModel = [.haiku]
        typesModelID = [.haiku]
      }
    }
    func value(_ name: String) -> String? {
      arguments.first { $0.hasPrefix(name + "=") }.map { String($0.dropFirst(name.count + 1)) }
    }
    if arguments.contains("r5") {
      round5 = true
    }
    if arguments.contains("r4") || round5 {
      round4 = true
    }
    if arguments.contains("r3") || round4 {
      round2 = true
      round3 = true
      variant = .d
      customEndpoint = "http://localhost:11434/v1"
      customModel = "gpt-oss:20b"
      storedKeys.remove(customKey.id)
      for item in profiles {
        lastVerified[item.id] = (currentModel(item), currentAddress(item))
      }
      switch value("shot") {
      case "offline": active = .offline
      case "custom-boost", "custom-boost-off":
        active = .custom
        customBoost = value("shot") == "custom-boost"
      case "custom-off": active = .custom; customCleanup = false
      case "menu":
        opensMenu = true
        installed.remove(.s1)
        downloading[.s1] = 0.42
        verified.remove(.custom)
      case "model-locked":
        modelOverrides[.haiku] = "claude-sonnet-5"
        lastVerified[.haiku] = ("claude-sonnet-5", "https://api.anthropic.com/v1")
      case "model-locked-both":
        modelOverrides[.haiku] = "anthropic.claude-haiku-5-5-v1:0"
        endpointOverrides[.haiku] = "https://llm-gateway.corp.example/anthropic/v1"
        lastVerified[.haiku] = (modelOverrides[.haiku]!, endpointOverrides[.haiku]!)
      case "override-draft":
        editingModel = [.haiku]
        typesModelID = [.haiku]
        modelOverrides[.haiku] = "anthropic.claude-haiku-5-5-v1:0"
        drafts = [.haiku]
      default: break
      }
      if let step = value("verify") {
        // Custom against Ollama, no key, a configuration that has never verified.
        active = .custom
        verified.remove(.custom)
        drafts = [.custom]
        switch step {
        case "verifying": verifying = [.custom]; freezesVerifying = true
        case "needs-key":
          customEndpoint = "https://gateway.internal/v1"
          customModel = "gpt-oss-120b"
          failures[.custom] = .needsKey
        case "unknown-model":
          typesModelID = [.custom]
          customModel = "qwen3:32b"
          failures[.custom] = .unknownModel
        case "verified", "flash":
          drafts = []
          verified.insert(.custom)
          if step == "flash" { flashVerified = [.custom] }
        default: break
        }
      }
      if let style = value("models") {
        modelsStyle = style
        active = .accurate
        storedKeys = [anthropicKey.id, elevenLabsKey.id, googleKey.id]
        if arguments.contains("states") {
          installed = []
          downloading[.parakeet] = 0.42
          queued = [.s1]
          failed = [.gate]
        }
      }
    }
    if let concept = value("concept") {
      // Round six: Haiku active, gate and Parakeet installed, S1-mini installed but unused.
      modelsStyle = concept
      active = .haiku
      storedKeys = [anthropicKey.id, elevenLabsKey.id, googleKey.id, cerebrasKey.id]
      if arguments.contains("states") {
        active = .offline
        installed = [.gate]
        downloading[.parakeet] = 0.42
        failed = [.s1]
      }
    }
    if round5, let shot = value("r5shot") {
      let ollama = "http://localhost:11434/v1"
      switch shot {
      case "custom-new", "custom-edit", "checking", "fail-unreachable", "fail-needs-key", "fail-unknown-model":
        active = .custom
        customConfigured = false
        if shot != "custom-new" {
          beginEdit(profile(.custom), .address)
          draftAddress = ollama
          draftModel = "gpt-oss:20b"
        }
        switch shot {
        case "checking":
          checking = true
          freezesChecking = true
          focusOn(nil)
        case "fail-unreachable":
          draftAddress = "http://localhost:11435/v1"
          r5Failure = FailureR5(field: .address, message: "Couldn’t reach localhost:11435.")
        case "fail-needs-key":
          draftAddress = "https://gateway.internal/v1"
          draftModel = "gpt-oss-120b"
          r5Failure = FailureR5(field: .key, message: "This endpoint needs an API key.")
          focusOn(.key)
        case "fail-unknown-model":
          draftModel = "qwen3:32b"
          draftTypesID = true
          r5Failure = FailureR5(field: .model, message: "localhost:11434 has no model ‘qwen3:32b’.")
          focusOn(.modelID)
        default: break
        }
      case "custom-verified":
        active = .custom
        customEndpoint = ollama
        customModel = "gpt-oss:20b"
      case "haiku-edit-model":
        beginEdit(profile(.haiku), .model)
      case "haiku-revoked":
        revoked = [.haiku]
      case "sheet":
        sheetMode = true
        beginEdit(profile(.haiku), .model)
      default: break
      }
    }
    if !arguments.contains("browse") {
      browsed = active
    }
    listSelection = opensOnModels ? .models : .profile(browsed)
    destination = opensOnModels && variant == .d ? .models : .profiles
    if round2 {
      destination = downloadsStyle > 0 ? .downloads : arguments.contains("settings") ? .settings : .profiles
    }
    if modelsStyle != nil {
      destination = .models
    }
  }

  // MARK: Internal

  var variant = Variant.a
  var active = ProfileID.haiku
  /// B and C only: the profile being looked at, which is not necessarily the one running.
  var browsed = ProfileID.haiku
  var listSelection: ListItem? = .profile(.haiku)
  var destination = Destination.profiles
  var showsChooser = false
  var opensOnModels = false

  var storedKeys: Set<String> = [anthropicKey.id, customKey.id]
  var keyDrafts: [String: String] = [:]
  var installed = Set(AssetID.allCases)
  var downloading: [AssetID: Double] = [:]
  var modelOverrides: [ProfileID: String] = [:]
  var endpointOverrides: [ProfileID: String] = [:]

  var timeout = 10
  var instructions = ""
  var customCleanup = true
  var customBoost = false
  var customEndpoint = "https://gateway.internal/v1"
  var customModel = "gpt-oss-120b"
  var pendingDeletion: AssetID?
  var confirmsUnused = false

  // Round two.
  var round2 = false
  /// 1 grouped, 2 tinted rows, 3 the active profile's mark.
  var downloadsStyle = 0
  /// 0 footnote, 1 own section, 2 in Settings, 3 a tag on each row, 4 nested under the profile.
  var scopeStyle = 0
  /// 0 required, 1 "No key needed" checkbox, 2 optional field, 3 add on demand, 4 the endpoint decides.
  var keyStyle = 0
  var noKeyNeeded = false
  var addingKey = false
  var keyRequiredByEndpoint = false
  var editingAddress: Set<ProfileID> = []
  var editingModel: Set<ProfileID> = []
  /// Profiles whose model pop-up is on Custom…, so the Model ID field shows.
  var typesModelID: Set<ProfileID> = []

  // Round three.
  var round3 = false
  /// Per-field reset icons, the boost warning, and no privacy line.
  var round4 = false
  // Round five.
  var round5 = false
  var customConfigured = true
  var sheetMode = false
  var editingGroup: ProfileID?
  var checking = false
  var freezesChecking = false
  var checkToken = 0
  var draftAddress = ""
  var draftKey = ""
  var draftModel = ""
  var draftTypesID = false
  var r5Failure: FailureR5?
  var r5Focus: FieldR5?
  var focusTick = 0
  var revoked: Set<ProfileID> = []
  /// a, b, or c: the other designer's Models page.
  var modelsStyle: String?
  var opensMenu = false
  /// Where the profile pop-up sits, top-left origin, so the menu shot can click it.
  var popUpFrame = CGRect.zero
  var drafts: Set<ProfileID> = []
  /// Profiles whose configuration has verified at least once.
  var verified: Set<ProfileID> = Set(ProfileID.allCases)
  var verifying: Set<ProfileID> = []
  var failures: [ProfileID: VerifyFailure] = [:]
  var flashVerified: Set<ProfileID> = []
  /// What dictation uses while a draft is pending.
  var lastVerified: [ProfileID: (model: String, address: String)] = [:]
  var freezesVerifying = false
  var queued: Set<AssetID> = []
  var failed: Set<AssetID> = []

  /// Whether Custom's cleanup cannot run without a key, under the key treatment being mocked.
  var customNeedsKey: Bool {
    switch keyStyle {
    case 1: !noKeyNeeded
    case 2, 3: false
    case 4: keyRequiredByEndpoint
    default: true
    }
  }

  var activeProfile: Profile { profile(active) }

  func readiness(_ profile: Profile) -> Readiness {
    for id in profile.assets {
      if let fraction = downloading[id] {
        return .downloading("Downloading \(asset(id).name) · \(Int(fraction * 100))%", fraction)
      }
    }
    if let missing = profile.assets.first(where: { !installed.contains($0) }) {
      return .needs("Needs \(asset(missing).name)")
    }
    if round5, revoked.contains(profile.id) {
      return .needs("Key rejected")
    }
    if round5, profile.id == .custom, !customConfigured {
      return .note("No cleanup")
    }
    var keys = profile.requiredKeys
    if profile.id == .custom, customCleanup, customNeedsKey, !round3 {
      keys.append(customKey)
    }
    let missing = keys.filter { !storedKeys.contains($0.id) }
    switch missing.count {
    case 0 where round3 && isVerifiable(self, profile) && !verified.contains(profile.id):
      return .needs("Needs verifying")
    case 0: return .ready
    case 1: return .needs("Needs \(missing[0].article) \(missing[0].label)")
    default: return .needs("Needs \(missing.map(\.provider).joined(separator: " and ")) keys")
    }
  }

  func isOverridden(_ profile: Profile) -> Bool {
    modelOverrides[profile.id] != nil || endpointOverrides[profile.id] != nil
  }

  func vocabulary(_ profile: Profile) -> String {
    guard profile.id == .custom else {
      return profile.vocabulary
    }
    switch (customBoost, customCleanup) {
    case (true, true): return "Boosted during recognition and in the prompt"
    case (true, false): return "Boosted during recognition"
    case (false, true): return "In the cleanup prompt"
    case (false, false): return "Not used"
    }
  }

  func engineSummary(_ profile: Profile) -> String {
    "\(profile.engine) · \(profile.engineIsHosted ? "hosted" : "on this Mac")"
  }

  func cleanupSummary(_ profile: Profile) -> String {
    switch profile.cleanup {
    case let .hosted(_, model, _, provider):
      "\(modelOverrides[profile.id] ?? model) · \(provider)"
    case .local:
      "S1-mini · on this Mac"
    case .custom:
      customCleanup ? "\(customModel) · \(URL(string: customEndpoint)?.host() ?? customEndpoint)" : "Off"
    }
  }

  func privacy(_ profile: Profile) -> String {
    if profile.id == .custom, !customCleanup {
      return "Recorded audio and transcripts never leave this Mac."
    }
    return profile.privacy
  }

  var installedTotal: Double {
    assets.filter { installed.contains($0.id) }.map(\.megabytes).reduce(0, +)
  }

  var unused: [Asset] {
    assets.filter { installed.contains($0.id) && !activeProfile.assets.contains($0.id) }
  }

  func draft(_ slot: KeySlot) -> Binding<String> {
    Binding(get: { self.keyDrafts[slot.id] ?? "" }, set: { self.keyDrafts[slot.id] = $0 })
  }
}

// MARK: - Status label

/// Two facts in one slot: whether this profile is running, and whether it could. Colour carries
/// the second, because that is the one that costs the user a dictation.
struct StatusLabel: View {
  let readiness: Readiness
  let isActive: Bool
  /// A narrow list says what kind of trouble, and leaves the detail to say which.
  var isCompact = false
  /// On a selected row the system wants plain, high-contrast text; status colour would vanish
  /// into the selection.
  @Environment(\.backgroundProminence) private var prominence

  var body: some View {
    label
      .foregroundStyle(prominence == .increased ? AnyShapeStyle(.primary) : tint)
  }

  private var tint: AnyShapeStyle {
    switch readiness {
    case .ready: isActive ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary)
    case .needs: AnyShapeStyle(.orange)
    case .downloading, .note: AnyShapeStyle(.secondary)
    }
  }

  @ViewBuilder private var label: some View {
    switch readiness {
    case .ready:
      if isActive {
        Label("Active", systemImage: "checkmark.circle.fill")
      } else {
        Text("Ready")
      }
    case let .needs(reason):
      Label(isCompact ? "Needs setup" : reason, systemImage: "exclamationmark.triangle.fill")
    case let .note(text):
      Text(text)
    case let .downloading(reason, fraction):
      HStack(spacing: 6) {
        ProgressView(value: fraction)
          .progressViewStyle(.circular)
          .controlSize(.mini)
        Text(isCompact ? "Downloading · \(Int(fraction * 100))%" : reason)
      }
    }
  }
}

// MARK: - Editable field

extension View {
  /// A grouped Form draws a text field as bare right-aligned text, which reads exactly like a fixed
  /// value. A bordered field says "you can change this" by its shape.
  func editableField() -> some View {
    labelsHidden()
      .textFieldStyle(.roundedBorder)
      .multilineTextAlignment(.leading)
      .frame(maxWidth: 420)
  }
}

// MARK: - Key row

struct KeyRow: View {
  @Bindable var mock: Mock
  let slot: KeySlot

  var body: some View {
    if mock.storedKeys.contains(slot.id) {
      LabeledContent(slot.label) {
        HStack(spacing: 12) {
          Text(slot.masked + String(repeating: "•", count: 10))
            .foregroundStyle(.secondary)
          Button("Replace") { mock.storedKeys.remove(slot.id) }
        }
      }
    } else {
      LabeledContent {
        HStack(spacing: 8) {
          SecureField(
            "", text: mock.draft(slot),
            prompt: mock.round2 ? nil : Text("Paste your \(slot.provider) key"),
          )
          .editableField()
          Button("Save") { mock.storedKeys.insert(slot.id) }
            .disabled((mock.keyDrafts[slot.id] ?? "").isEmpty)
        }
      } label: {
        // Round two: the lineup's warning is the one mark; the empty field is the fix, not a
        // second warning.
        if mock.round2 {
          Text(slot.label)
        } else {
          Label {
            Text(slot.label)
          } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
          }
        }
      }
    }
  }
}

// MARK: - Missing model row

/// A profile that cannot run until a model lands says so where the model is used, and offers the
/// download there; the models list is still the one place that deletes.
struct MissingAssetRow: View {
  @Bindable var mock: Mock
  let id: AssetID

  var body: some View {
    let item = asset(id)
    LabeledContent {
      if let fraction = mock.downloading[id] {
        HStack(spacing: 8) {
          ProgressView(value: fraction)
            .frame(width: 140)
          Text("\(Int(fraction * 100))%")
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
      } else {
        HStack(spacing: 12) {
          Text(item.size)
            .monospacedDigit()
            .foregroundStyle(.secondary)
          Button("Download") { mock.downloading[id] = 0.01 }
        }
      }
    } label: {
      if mock.round2 {
        Text(item.name)
      } else {
        Label {
          Text(item.name)
        } icon: {
          Image(systemName: mock.downloading[id] == nil ? "exclamationmark.triangle.fill" : "arrow.down.circle")
            .foregroundStyle(mock.downloading[id] == nil ? Color.orange : Color.secondary)
        }
      }
    }
  }
}

// MARK: - Shared detail sections

/// The stack in pipeline order: what hears you, then what cleans the transcript up. Fixed facts
/// are plain values; anything editable is a control, so "what can I change" is visible by shape.
struct SpeechSection: View {
  @Bindable var mock: Mock
  let profile: Profile

  var body: some View {
    Section("Speech") {
      LabeledContent("Engine", value: mock.engineSummary(profile))
      LabeledContent("Vocabulary", value: mock.vocabulary(profile))
      if let key = profile.engineKey {
        KeyRow(mock: mock, slot: key)
      }
      if profile.assets.contains(.parakeet), !mock.installed.contains(.parakeet) {
        MissingAssetRow(mock: mock, id: .parakeet)
      }
    }
  }
}

struct CleanupSection: View {
  @Bindable var mock: Mock
  let profile: Profile

  var body: some View {
    Section {
      CleanupRows(mock: mock, profile: profile)
      GlobalRows(mock: mock, profile: profile)
    } header: {
      Text("Cleanup")
    } footer: {
      GlobalFooter(profile: profile)
    }
    if profile.id == .custom {
      BoostSection(mock: mock)
    }
  }
}

/// The rows that belong to this profile's cleanup leg alone.
struct CleanupRows: View {
  @Bindable var mock: Mock
  let profile: Profile

  var body: some View {
    switch profile.cleanup {
    case let .hosted(endpoint, model, key, _):
      LabeledContent("Model") {
        TextField(
          "", text: Binding(
            get: { mock.modelOverrides[profile.id] ?? model },
            set: { mock.modelOverrides[profile.id] = $0 == model ? nil : $0 },
          ),
        )
        .editableField()
      }
      LabeledContent("Address") {
        TextField(
          "", text: Binding(
            get: { mock.endpointOverrides[profile.id] ?? endpoint },
            set: { mock.endpointOverrides[profile.id] = $0 == endpoint ? nil : $0 },
          ),
        )
        .editableField()
      }
      KeyRow(mock: mock, slot: key)
      if mock.isOverridden(profile) {
        LabeledContent("Edited from the defaults") {
          Button("Reset to Default") {
            mock.modelOverrides[profile.id] = nil
            mock.endpointOverrides[profile.id] = nil
          }
        }
      }
    case .local:
      if mock.installed.contains(.s1) {
        LabeledContent("Model", value: "S1-mini · on this Mac")
      } else {
        MissingAssetRow(mock: mock, id: .s1)
      }
    case .custom:
      Toggle("Clean up transcripts", isOn: $mock.customCleanup)
      Group {
        LabeledContent("Address") {
          TextField("", text: $mock.customEndpoint, prompt: Text("https://gateway.example/v1"))
            .editableField()
        }
        KeyRow(mock: mock, slot: customKey)
        LabeledContent("Model") {
          HStack(spacing: 8) {
            Picker("", selection: $mock.customModel) {
              ForEach(["gpt-oss-120b", "llama-4-scout", "qwen3-32b"], id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            Button("Load Models") {}
          }
        }
      }
      .disabled(!mock.customCleanup)
    }
  }
}

/// Timeout and instructions are global; they sit with cleanup because that is what they tune.
struct GlobalRows: View {
  @Bindable var mock: Mock
  let profile: Profile

  var body: some View {
    LabeledContent("Give up after") {
      Picker("", selection: $mock.timeout) {
        ForEach([5, 10, 20, 30], id: \.self) { Text("\($0) seconds").tag($0) }
      }
      .labelsHidden()
      .fixedSize()
    }
    .disabled(profile.id == .custom && !mock.customCleanup)
    if profile.id != .offline {
      LabeledContent("Additional instructions") {
        TextField(
          "", text: $mock.instructions,
          prompt: Text("keep it casual — lowercase greetings, don’t expand my contractions"),
          axis: .vertical,
        )
        .lineLimit(3, reservesSpace: true)
        .editableField()
      }
      .disabled(profile.id == .custom && !mock.customCleanup)
    }
  }
}

/// Prevents the mistake of thinking a timeout set here only applies to this profile.
struct GlobalFooter: View {
  let profile: Profile

  var body: some View {
    Text(
      profile.id == .offline
        ? "Give up after applies to every profile."
        : "Give up after and Additional instructions apply to every profile.",
    )
  }
}

struct BoostSection: View {
  @Bindable var mock: Mock

  var body: some View {
    Section {
      Toggle("Boost vocabulary", isOn: $mock.customBoost)
    } footer: {
      Text(
        mock.customCleanup
          ? "Your dictionary already reaches the cleanup model. Turning this on tends to cost more than it recovers."
          : "With cleanup off, this is the only way your dictionary reaches the transcript.",
      )
    }
  }
}

// MARK: - Model rows

/// Every asset on one list: what it is, who uses it, what it costs, and the one button that
/// matters. A model the active profile does not need says so beside its Delete.
struct ModelRows: View {
  @Bindable var mock: Mock

  var body: some View {
    ForEach(assets, id: \.id) { item in
      LabeledContent {
        HStack(spacing: 12) {
          if let fraction = mock.downloading[item.id] {
            ProgressView(value: fraction)
              .frame(width: 120)
            Text("\(Int(fraction * 100))%")
              .monospacedDigit()
              .foregroundStyle(.secondary)
            Button("Stop") { mock.downloading[item.id] = nil }
          } else if mock.installed.contains(item.id) {
            if !mock.activeProfile.assets.contains(item.id) {
              Text("Not in use")
                .foregroundStyle(.secondary)
            }
            Text(item.size)
              .monospacedDigit()
              .foregroundStyle(.secondary)
            Button("Delete") { mock.pendingDeletion = item.id }
          } else {
            Text("Not downloaded · \(item.size)")
              .foregroundStyle(.secondary)
            Button("Download") { mock.downloading[item.id] = 0.01 }
          }
        }
      } label: {
        VStack(alignment: .leading, spacing: 2) {
          Text(item.name)
          Text("\(item.role) · \(item.usedBy)")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}

struct ModelsSection: View {
  @Bindable var mock: Mock

  var body: some View {
    Section("Models on this Mac") {
      ModelRows(mock: mock)
      LabeledContent("Total", value: formatSize(mock.installedTotal))
    }
    .id("models")
  }
}

// MARK: - Variant A: pop-up, pipeline form

/// One pop-up, and the pane below it is always the profile that is running: picking is
/// activating. Sections follow the pipeline — Speech, Cleanup — and the models list closes the
/// pane. The lineup costs one row however long it grows.
struct PaneA: View {
  @Bindable var mock: Mock

  var body: some View {
    let profile = mock.activeProfile
    ScrollViewReader { proxy in
      Form {
        Section {
          LabeledContent("Profile") {
            HStack(spacing: 12) {
              StatusLabel(readiness: mock.readiness(profile), isActive: true)
              Picker("", selection: $mock.active) {
                ForEach(profiles) { item in
                  Label(item.name, systemImage: item.symbol).tag(item.id)
                }
              }
              .labelsHidden()
              .fixedSize()
            }
          }
        } footer: {
          Text(mock.privacy(profile))
        }
        SpeechSection(mock: mock, profile: profile)
        CleanupSection(mock: mock, profile: profile)
        ModelsSection(mock: mock)
      }
      .formStyle(.grouped)
      .task {
        guard mock.opensOnModels else {
          return
        }
        try? await Task.sleep(for: .milliseconds(300))
        proxy.scrollTo("models", anchor: .bottom)
      }
    }
  }
}

// MARK: - Variant B: master-detail

/// A compact list of profiles down the pane's leading edge, with Models as the last entry. The
/// list selects what is shown; Use This Profile is what makes it run. So a profile can be read,
/// and have its keys added, before it is switched to.
struct PaneB: View {
  @Bindable var mock: Mock

  var body: some View {
    HStack(spacing: 0) {
      List(selection: $mock.listSelection) {
        Section("Profiles") {
          ForEach(profiles) { item in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
              Image(systemName: item.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
              VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                  .lineLimit(1)
                StatusLabel(
                  readiness: mock.readiness(item), isActive: item.id == mock.active, isCompact: true,
                )
                .font(.callout)
              }
            }
            .padding(.vertical, 3)
            .tag(ListItem.profile(item.id))
          }
        }
        Section("Storage") {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "internaldrive")
              .foregroundStyle(.secondary)
              .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
              Text("Models")
              Text(formatSize(mock.installedTotal))
                .font(.callout)
                .foregroundStyle(.secondary)
            }
          }
          .padding(.vertical, 3)
          .tag(ListItem.models)
        }
      }
      .listStyle(.inset)
      .frame(width: 216)
      Divider()
      switch mock.listSelection {
      case .models:
        Form {
          ModelsSection(mock: mock)
        }
        .formStyle(.grouped)
      case let .profile(id):
        ProfileDetailB(mock: mock, profile: profile(id))
      case nil:
        Spacer()
      }
    }
  }
}

struct ProfileDetailB: View {
  @Bindable var mock: Mock
  let profile: Profile

  var body: some View {
    let isActive = profile.id == mock.active
    let readiness = mock.readiness(profile)
    Form {
      Section {
        LabeledContent {
          if isActive {
            Label("Active", systemImage: "checkmark.circle.fill")
              .foregroundStyle(.green)
          } else {
            Button("Use This Profile") { mock.active = profile.id }
          }
        } label: {
          Label {
            VStack(alignment: .leading, spacing: 2) {
              Text(profile.name)
                .font(.headline)
              Text(profile.tagline)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          } icon: {
            Image(systemName: profile.symbol)
          }
        }
        if readiness != .ready {
          LabeledContent("Status") {
            StatusLabel(readiness: readiness, isActive: isActive)
          }
        }
      } footer: {
        Text(mock.privacy(profile))
      }
      SpeechSection(mock: mock, profile: profile)
      CleanupSection(mock: mock, profile: profile)
    }
    .formStyle(.grouped)
  }
}

// MARK: - Variant C: what is running, then what you can change

/// The active profile as a readout — what hears you, what cleans up, where it goes — then only
/// the knobs, then the models. Switching is a deliberate act behind Change Profile…, a sheet that
/// lays the lineup out as a table to compare before committing.
struct PaneC: View {
  @Bindable var mock: Mock

  var body: some View {
    let profile = mock.activeProfile
    let readiness = mock.readiness(profile)
    ScrollViewReader { proxy in
      Form {
        Section("Active profile") {
          LabeledContent {
            Button("Change Profile…") {
              mock.browsed = mock.active
              mock.showsChooser = true
            }
          } label: {
            Label {
              VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                  .font(.headline)
                Text(profile.tagline)
                  .font(.callout)
                  .foregroundStyle(.secondary)
                  .fixedSize(horizontal: false, vertical: true)
              }
            } icon: {
              Image(systemName: profile.symbol)
            }
          }
          if readiness != .ready {
            LabeledContent("Status") {
              StatusLabel(readiness: readiness, isActive: true)
            }
          }
          LabeledContent("Speech", value: mock.engineSummary(profile))
          LabeledContent("Vocabulary", value: mock.vocabulary(profile))
          LabeledContent("Cleanup", value: mock.cleanupSummary(profile))
          LabeledContent("Leaves this Mac", value: profile.id == .custom && !mock.customCleanup ? "Nothing" : profile.sendsOut)
        }
        Section {
          if let key = profile.engineKey {
            KeyRow(mock: mock, slot: key)
          }
          if profile.assets.contains(.parakeet), !mock.installed.contains(.parakeet) {
            MissingAssetRow(mock: mock, id: .parakeet)
          }
          CleanupRows(mock: mock, profile: profile)
          GlobalRows(mock: mock, profile: profile)
        } header: {
          Text("You can change")
        } footer: {
          GlobalFooter(profile: profile)
        }
        if profile.id == .custom {
          BoostSection(mock: mock)
        }
        ModelsSection(mock: mock)
      }
      .formStyle(.grouped)
      .task {
        guard mock.opensOnModels else {
          return
        }
        try? await Task.sleep(for: .milliseconds(300))
        proxy.scrollTo("models", anchor: .bottom)
      }
    }
    .sheet(isPresented: $mock.showsChooser) {
      ProfileChooser(mock: mock)
    }
  }
}

/// The lineup as a table: one row per profile, the columns are the tradeoffs. Selecting a row
/// reads it; only Use makes it run.
struct ProfileChooser: View {
  @Bindable var mock: Mock

  var body: some View {
    let browsed = profile(mock.browsed)
    VStack(alignment: .leading, spacing: 0) {
      Text("Choose a profile")
        .font(.headline)
        .padding([.horizontal, .top], 20)
        .padding(.bottom, 12)
      Table(
        profiles,
        selection: Binding(get: { mock.browsed }, set: { mock.browsed = $0 ?? mock.browsed }),
      ) {
        TableColumn("Profile") { item in
          Label(item.name, systemImage: item.symbol)
        }
        .width(186)
        TableColumn("Speech") { item in
          Text(item.engineIsHosted ? "Scribe v2 · ElevenLabs" : "Parakeet · this Mac")
        }
        .width(138)
        TableColumn("Cleanup") { item in
          Text(chooserCleanup(item))
        }
        .width(172)
        TableColumn("Status") { item in
          StatusLabel(readiness: mock.readiness(item), isActive: item.id == mock.active)
        }
      }
      .frame(height: 172)
      Form {
        Section {
          LabeledContent {
            EmptyView()
          } label: {
            VStack(alignment: .leading, spacing: 2) {
              Text(browsed.name)
                .font(.headline)
              Text(browsed.tagline)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        } footer: {
          Text(mock.privacy(browsed))
        }
      }
      .formStyle(.grouped)
      .scrollDisabled(true)
      .frame(height: 124)
      HStack {
        Spacer()
        Button("Cancel") { mock.showsChooser = false }
          .keyboardShortcut(.cancelAction)
        Button(browsed.id == mock.active ? "Done" : "Use \(browsed.name)") {
          mock.active = browsed.id
          mock.showsChooser = false
        }
        .keyboardShortcut(.defaultAction)
      }
      .padding([.horizontal, .bottom], 20)
    }
    .frame(width: 840)
  }

  /// Provider names say where a transcript goes; "this Mac" says it doesn't.
  private func chooserCleanup(_ item: Profile) -> String {
    switch item.id {
    case .haiku: "Claude Haiku · Anthropic"
    case .offline: "S1-mini · this Mac"
    case .accurate: "Gemini Flash · Google"
    case .cerebras: "gpt-oss · Cerebras"
    case .custom: mock.customCleanup ? "Your endpoint" : "Off"
    }
  }
}

// MARK: - Variant D: radio lineup, models get their own destination

/// The whole lineup as one radio group with status at the trailing edge — five short rows,
/// readable at a glance, and picking is activating. Models leave the pane for a sidebar entry of
/// their own, modelled on Storage settings, so cleaning up disk is never at the bottom of
/// something else.
struct PaneD: View {
  @Bindable var mock: Mock

  var body: some View {
    let profile = mock.activeProfile
    Form {
      Section {
        Picker("Profile", selection: $mock.active) {
          ForEach(profiles) { item in
            HStack {
              Label(item.name, systemImage: item.symbol)
              Spacer()
              StatusLabel(readiness: mock.readiness(item), isActive: item.id == mock.active)
            }
            .tag(item.id)
          }
        }
        .pickerStyle(.radioGroup)
        .labelsHidden()
      } header: {
        Text("Profile")
      } footer: {
        Text(mock.privacy(profile))
      }
      SpeechSection(mock: mock, profile: profile)
      CleanupSection(mock: mock, profile: profile)
      Section {
        LabeledContent {
          Button("Show Models") { mock.destination = .models }
        } label: {
          VStack(alignment: .leading, spacing: 2) {
            Text("Models")
            Text(profile.assets.map { asset($0).name }.joined(separator: ", "))
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
    .formStyle(.grouped)
  }
}

struct ModelsPaneD: View {
  @Bindable var mock: Mock

  var body: some View {
    let unused = mock.unused
    Form {
      Section {
        LabeledContent("Models on this Mac", value: formatSize(mock.installedTotal))
        LabeledContent {
          HStack(spacing: 12) {
            Text(formatSize(unused.map(\.megabytes).reduce(0, +)))
              .monospacedDigit()
              .foregroundStyle(.secondary)
            Button("Delete Unused…") { mock.confirmsUnused = true }
          }
        } label: {
          VStack(alignment: .leading, spacing: 2) {
            Text("Not used by \(mock.activeProfile.name)")
            Text(unused.isEmpty ? "None" : unused.map(\.name).joined(separator: ", "))
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        }
        .disabled(unused.isEmpty)
      }
      Section {
        ModelRows(mock: mock)
      } header: {
        Text("Models")
      } footer: {
        Text("Deleting a model the active profile uses stops dictation until it downloads again.")
      }
    }
    .formStyle(.grouped)
  }
}

// MARK: - Round two: revised D

let customModelTag = "__custom"

/// What each endpoint's model listing returns, loaded optimistically when the pane opens.
func listing(_ id: ProfileID) -> [String] {
  switch id {
  case .haiku: ["claude-haiku-5-5", "claude-sonnet-5", "claude-opus-5"]
  case .accurate: ["gemini-3.8-flash", "gemini-3.8-flash-lite", "gemini-3.8-pro"]
  case .cerebras: ["gpt-oss-120b", "llama-4-scout", "qwen3-235b"]
  case .custom: ["qwen3:32b", "llama3.3:70b", "gpt-oss:20b"]
  case .offline: []
  }
}

func defaultModel(_ profile: Profile) -> String? {
  if case let .hosted(_, model, _, _) = profile.cleanup { return model }
  return nil
}

func defaultEndpoint(_ profile: Profile) -> String? {
  if case let .hosted(endpoint, _, _, _) = profile.cleanup { return endpoint }
  return nil
}

/// The revised D pane. The radio lineup is the only place a profile's state is marked: the filled
/// radio is "active", a warning is "can't run yet", and nothing at all is "ready".
struct PaneR2: View {
  @Bindable var mock: Mock

  var body: some View {
    let profile = mock.activeProfile
    Form {
      if mock.scopeStyle == 4 {
        NestedLineupR2(mock: mock)
      } else {
        LineupR2(mock: mock)
        switch mock.scopeStyle {
        case 1:
          // The heading is the scope: this profile's name, then "All profiles".
          Section(profile.name) {
            ProfileRowsR2(mock: mock, profile: profile)
          }
        default:
          Section("Speech") {
            SpeechRowsR2(mock: mock, profile: profile)
          }
          Section {
            CleanupRowsR2(mock: mock, profile: profile)
            if mock.scopeStyle != 2 {
              GlobalRowsR2(mock: mock, profile: profile)
            }
          } header: {
            Text("Cleanup")
          } footer: {
            if mock.scopeStyle == 0 {
              GlobalFooter(profile: profile)
            }
          }
          if profile.id == .custom {
            BoostSection(mock: mock)
          }
        }
      }
      if mock.scopeStyle == 1 || mock.scopeStyle == 4 {
        Section("All profiles") {
          GlobalRowsR2(mock: mock, profile: profile)
        }
      }
    }
    .formStyle(.grouped)
  }
}

/// One radio per profile, its trouble (and only its trouble) at the trailing edge.
struct LineupR2: View {
  @Bindable var mock: Mock

  var body: some View {
    Section {
      Picker("Profile", selection: $mock.active) {
        ForEach(profiles) { item in
          LineupItemR2(mock: mock, item: item)
            .tag(item.id)
        }
      }
      .pickerStyle(.radioGroup)
      .labelsHidden()
    } header: {
      Text("Profile")
    } footer: {
      Text(privacyR2(mock, mock.activeProfile))
    }
  }
}

struct LineupItemR2: View {
  @Bindable var mock: Mock
  let item: Profile

  var body: some View {
    HStack {
      Label(item.name, systemImage: item.symbol)
      Spacer()
      let readiness = mock.readiness(item)
      if readiness != .ready {
        StatusLabel(readiness: readiness, isActive: item.id == mock.active)
      }
    }
  }
}

/// Custom's address sits below the lineup now, so its privacy line can't point "above".
func privacyR2(_ mock: Mock, _ profile: Profile) -> String {
  if profile.id == .custom, mock.customCleanup {
    return "Recorded audio never leaves this Mac. Transcripts go to the cleanup address below."
  }
  return mock.privacy(profile)
}

/// Scope idea 4: the selected profile's settings sit inside the lineup, under its own radio, so
/// what belongs to it is literally nested in it. Everything after the lineup is for every profile.
struct NestedLineupR2: View {
  @Bindable var mock: Mock

  var body: some View {
    Section {
      ForEach(profiles) { item in
        // One single-option radio group per profile, all bound to the same selection, is how the
        // settings rows can sit between two radios without drawing a radio by hand.
        Picker("", selection: $mock.active) {
          LineupItemR2(mock: mock, item: item)
            .tag(item.id)
        }
        .pickerStyle(.radioGroup)
        .labelsHidden()
        if item.id == mock.active {
          ProfileRowsR2(mock: mock, profile: item)
            .padding(.leading, 26)
        }
      }
    } header: {
      Text("Profile")
    } footer: {
      Text(privacyR2(mock, mock.activeProfile))
    }
  }
}

/// Every row that belongs to one profile, in pipeline order, for layouts that keep them together.
struct ProfileRowsR2: View {
  @Bindable var mock: Mock
  let profile: Profile

  var body: some View {
    SpeechRowsR2(mock: mock, profile: profile)
    CleanupRowsR2(mock: mock, profile: profile)
    if profile.id == .custom {
      Toggle("Boost vocabulary", isOn: $mock.customBoost)
    }
  }
}

/// No Vocabulary row (the Dictionary pane says when the profile ignores the vocabulary) and no
/// "on this Mac" / "hosted" suffix (the privacy line under the lineup already says where audio goes).
struct SpeechRowsR2: View {
  @Bindable var mock: Mock
  let profile: Profile

  var body: some View {
    LabeledContent("Engine", value: profile.engine)
    if let key = profile.engineKey {
      KeyRow(mock: mock, slot: key)
    }
    if profile.assets.contains(.parakeet), !mock.installed.contains(.parakeet) {
      MissingAssetRow(mock: mock, id: .parakeet)
    }
  }
}

struct CleanupRowsR2: View {
  @Bindable var mock: Mock
  let profile: Profile

  var body: some View {
    switch profile.cleanup {
    case let .hosted(_, _, key, _):
      FactoryModelRow(mock: mock, profile: profile)
      FactoryAddressRow(mock: mock, profile: profile)
      KeyRow(mock: mock, slot: key)
    case .local:
      if mock.installed.contains(.s1) {
        LabeledContent("Model", value: "S1-mini")
      } else {
        MissingAssetRow(mock: mock, id: .s1)
      }
    case .custom:
      Toggle("Clean up transcripts", isOn: $mock.customCleanup)
      Group {
        LabeledContent("Address") {
          TextField("", text: $mock.customEndpoint)
            .editableField()
        }
        CustomKeyRow(mock: mock)
        LabeledContent("Model") {
          HStack(spacing: 8) {
            ModelPickerR2(mock: mock, profile: profile)
            Button("Load Models") {}
          }
        }
        if mock.typesModelID.contains(.custom) {
          LabeledContent("Model ID") {
            TextField("", text: $mock.customModel)
              .editableField()
          }
        }
      }
      .disabled(!mock.customCleanup)
    }
  }
}

/// The pop-up Custom uses and a factory profile's Edit opens: the endpoint's listing, then
/// Custom… for an ID the listing doesn't carry (a gateway that renames models).
struct ModelPickerR2: View {
  @Bindable var mock: Mock
  let profile: Profile

  var body: some View {
    Picker("", selection: choice) {
      ForEach(listing(profile.id), id: \.self) { Text($0).tag($0) }
      Divider()
      Text("Custom…").tag(customModelTag)
    }
    .labelsHidden()
    .fixedSize()
  }

  private var choice: Binding<String> {
    Binding(
      get: {
        if mock.typesModelID.contains(profile.id) { return customModelTag }
        return profile.id == .custom
          ? mock.customModel : mock.modelOverrides[profile.id] ?? defaultModel(profile) ?? ""
      },
      set: { value in
        if value == customModelTag {
          mock.typesModelID.insert(profile.id)
          return
        }
        mock.typesModelID.remove(profile.id)
        if profile.id == .custom {
          mock.customModel = value
        } else {
          mock.modelOverrides[profile.id] = value == defaultModel(profile) ? nil : value
        }
      },
    )
  }
}

/// Read-only until Edit; Reset to Default once the value is not the factory one.
struct FactoryModelRow: View {
  @Bindable var mock: Mock
  let profile: Profile

  var body: some View {
    let model = mock.modelOverrides[profile.id] ?? defaultModel(profile) ?? ""
    if mock.editingModel.contains(profile.id) {
      LabeledContent("Model") {
        HStack(spacing: 8) {
          ModelPickerR2(mock: mock, profile: profile)
          Button("Load Models") {}
          Button("Done") { mock.editingModel.remove(profile.id) }
        }
      }
      if mock.typesModelID.contains(profile.id) {
        LabeledContent("Model ID") {
          TextField(
            "", text: Binding(
              get: { mock.modelOverrides[profile.id] ?? "" },
              set: { mock.modelOverrides[profile.id] = $0.isEmpty ? nil : $0 },
            ),
          )
          .editableField()
        }
      }
    } else {
      LabeledContent("Model") {
        HStack(spacing: 12) {
          Text(model)
            .lineLimit(1)
            .truncationMode(.middle)
          Button("Edit") { mock.editingModel.insert(profile.id) }
          if mock.modelOverrides[profile.id] != nil {
            Button("Reset to Default") {
              mock.modelOverrides[profile.id] = nil
              mock.typesModelID.remove(profile.id)
            }
          }
        }
      }
    }
  }
}

struct FactoryAddressRow: View {
  @Bindable var mock: Mock
  let profile: Profile

  var body: some View {
    let endpoint = defaultEndpoint(profile) ?? ""
    if mock.editingAddress.contains(profile.id) {
      LabeledContent("Address") {
        HStack(spacing: 8) {
          TextField(
            "", text: Binding(
              get: { mock.endpointOverrides[profile.id] ?? endpoint },
              set: { mock.endpointOverrides[profile.id] = $0 == endpoint ? nil : $0 },
            ),
          )
          .editableField()
          Button("Done") { mock.editingAddress.remove(profile.id) }
        }
      }
    } else {
      LabeledContent("Address") {
        HStack(spacing: 12) {
          Text(mock.endpointOverrides[profile.id] ?? endpoint)
            .lineLimit(1)
            .truncationMode(.middle)
          Button("Edit") { mock.editingAddress.insert(profile.id) }
          if mock.endpointOverrides[profile.id] != nil {
            Button("Reset to Default") { mock.endpointOverrides[profile.id] = nil }
          }
        }
      }
    }
  }
}

/// Timeout and instructions, with no ghost text in the field. Scope idea 3 tags each one.
struct GlobalRowsR2: View {
  @Bindable var mock: Mock
  let profile: Profile

  var body: some View {
    let isOff = profile.id == .custom && !mock.customCleanup
    LabeledContent {
      Picker("", selection: $mock.timeout) {
        ForEach([5, 10, 20, 30], id: \.self) { Text("\($0) seconds").tag($0) }
      }
      .labelsHidden()
      .fixedSize()
    } label: {
      ScopedLabel(title: "Give up after", isTagged: mock.scopeStyle == 3)
    }
    .disabled(isOff)
    if profile.id != .offline {
      LabeledContent {
        TextField("", text: $mock.instructions, axis: .vertical)
          .lineLimit(3, reservesSpace: true)
          .editableField()
      } label: {
        ScopedLabel(title: "Additional instructions", isTagged: mock.scopeStyle == 3)
      }
      .disabled(isOff)
    }
  }
}

struct ScopedLabel: View {
  let title: String
  let isTagged: Bool

  var body: some View {
    if isTagged {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
        Text("All profiles")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    } else {
      Text(title)
    }
  }
}

// MARK: - Round two: Custom's key

/// Four ways for Custom to say a key is optional or absent, for endpoints like Ollama.
struct CustomKeyRow: View {
  @Bindable var mock: Mock

  var body: some View {
    let stored = mock.storedKeys.contains(customKey.id)
    switch mock.keyStyle {
    case 1 where !stored:
      // 1: an explicit opt-out beside the field, which it greys.
      LabeledContent("API key") {
        HStack(spacing: 8) {
          Group {
            SecureField("", text: mock.draft(customKey))
              .editableField()
            Button("Save") { mock.storedKeys.insert(customKey.id) }
              .disabled((mock.keyDrafts[customKey.id] ?? "").isEmpty)
          }
          .disabled(mock.noKeyNeeded)
          Toggle("No key needed", isOn: $mock.noKeyNeeded)
            .toggleStyle(.checkbox)
        }
      }
    case 2 where !stored:
      // 2: the same field as everywhere else; its label says it may stay empty.
      LabeledContent {
        HStack(spacing: 8) {
          SecureField("", text: mock.draft(customKey))
            .editableField()
          Button("Save") { mock.storedKeys.insert(customKey.id) }
            .disabled((mock.keyDrafts[customKey.id] ?? "").isEmpty)
        }
      } label: {
        VStack(alignment: .leading, spacing: 2) {
          Text("API key")
          Text("Optional")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      }
    case 3 where !stored && !mock.addingKey:
      // 3: no key is the starting state; a field exists only once asked for.
      LabeledContent("API key") {
        HStack(spacing: 12) {
          Text("None")
          Button("Add Key") { mock.addingKey = true }
        }
      }
    case 4 where !stored && !mock.keyRequiredByEndpoint:
      // 4: the endpoint decides. Load Models already calls it; an answer without a 401 means the
      // key row has nothing to ask for.
      LabeledContent("API key") {
        HStack(spacing: 12) {
          Text("Not needed by this endpoint")
          Button("Add Key") { mock.keyRequiredByEndpoint = true }
        }
      }
    default:
      KeyRow(mock: mock, slot: customKey)
    }
  }
}

// MARK: - Round two: Downloads

/// What is on disk, with what the active profile uses picked out. Three treatments of "in use";
/// nothing marks "not in use", because anything unmarked is the answer to "what can I delete".
struct DownloadsR2: View {
  @Bindable var mock: Mock

  var body: some View {
    let active = mock.activeProfile
    let inUse = assets.filter { active.assets.contains($0.id) }
    let others = assets.filter { !active.assets.contains($0.id) }
    let consequence = "Deleting one stops dictation until it downloads again."
    Form {
      Section {
        LabeledContent("On this Mac", value: formatSize(mock.installedTotal))
      }
      switch mock.downloadsStyle {
      case 1:
        // 1: grouped. The warning attaches to the only group it is true of.
        Section {
          ForEach(inUse, id: \.id) { DownloadRowR2(mock: mock, item: $0) }
        } header: {
          Text("Used by \(active.name)")
        } footer: {
          Text(consequence)
        }
        Section("Other downloads") {
          ForEach(others, id: \.id) { DownloadRowR2(mock: mock, item: $0) }
        }
      case 2:
        // 2: one list, the rows in use tinted with the accent colour.
        Section {
          ForEach(assets, id: \.id) { item in
            DownloadRowR2(mock: mock, item: item)
              .background {
                if active.assets.contains(item.id) {
                  RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.quinary)
                    .padding(.horizontal, -8)
                    .padding(.vertical, -5)
                }
              }
          }
        } footer: {
          Text("Highlighted downloads are used by \(active.name). \(consequence)")
        }
      default:
        // 3: the active profile's own symbol beside each download it uses.
        Section {
          ForEach(assets, id: \.id) { item in
            DownloadRowR2(mock: mock, item: item, mark: active.assets.contains(item.id) ? .shown : .hidden)
          }
        } footer: {
          Text("\(Text(Image(systemName: active.symbol)).foregroundStyle(.tint)) Used by \(active.name). \(consequence)")
        }
      }
    }
    .formStyle(.grouped)
  }
}

enum MarkSlot {
  case none, shown, hidden
}

struct DownloadRowR2: View {
  @Bindable var mock: Mock
  let item: Asset
  var mark = MarkSlot.none

  var body: some View {
    LabeledContent {
      HStack(spacing: 12) {
        if let fraction = mock.downloading[item.id] {
          ProgressView(value: fraction)
            .frame(width: 120)
          Text("\(Int(fraction * 100))%")
            .monospacedDigit()
            .foregroundStyle(.secondary)
          Button("Stop") { mock.downloading[item.id] = nil }
        } else if mock.installed.contains(item.id) {
          Text(item.size)
            .monospacedDigit()
            .foregroundStyle(.secondary)
          Button("Delete") { mock.pendingDeletion = item.id }
        } else {
          Text(item.size)
            .monospacedDigit()
            .foregroundStyle(.secondary)
          Button("Download") { mock.downloading[item.id] = 0.01 }
        }
      }
    } label: {
      let text = VStack(alignment: .leading, spacing: 2) {
        Text(item.name)
        Text(item.role)
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      switch mark {
      case .none:
        text
      case .shown, .hidden:
        Label {
          text
        } icon: {
          Image(systemName: mock.activeProfile.symbol)
            .foregroundStyle(.tint)
            .opacity(mark == .shown ? 1 : 0)
        }
      }
    }
  }
}

// MARK: - Round two: global settings in the Settings pane

/// Scope idea 2: the settings that apply to every profile leave the Profiles pane for the main
/// Settings pane, beside the other app-wide behaviour. The rest of this pane is a stand-in.
struct SettingsR2: View {
  @Bindable var mock: Mock
  @State private var input = "default"
  @State private var activateSound = "Tink"
  @State private var completeSound = "Pop"
  @State private var cancelSound = "Funk"

  var body: some View {
    Form {
      Section {
        LabeledContent("Activate", value: "⌥ Right Option")
        LabeledContent("Paste last transcript", value: "⌥⌘V")
      } header: {
        Text("Shortcuts")
      } footer: {
        Text("Hold to dictate, or double-tap to keep recording hands free.")
      }
      Section("Microphone") {
        Picker("Input", selection: $input) {
          Text("System Default (MacBook Pro Microphone)").tag("default")
        }
      }
      Section("Sounds") {
        Picker("Activate", selection: $activateSound) { Text("Tink").tag("Tink") }
        Picker("Complete", selection: $completeSound) { Text("Pop").tag("Pop") }
        Picker("Cancel", selection: $cancelSound) { Text("Funk").tag("Funk") }
      }
      Section {
        GlobalRowsR2(mock: mock, profile: profile(.haiku))
      } header: {
        Text("Cleanup")
      } footer: {
        Text("Offline doesn’t use additional instructions.")
      }
    }
    .formStyle(.grouped)
  }
}

// MARK: - Round three: pop-up picker, nested block, Verify

enum VerifyFailure: Equatable {
  case unreachable, needsKey, rejectedKey, unknownModel
}

/// What Ollama on localhost answers to /v1/models in these shots. qwen3:32b is not pulled.
let ollamaListing = ["gpt-oss:20b", "llama3.3:70b", "qwen2.5:14b"]

func hostOf(_ address: String) -> String {
  guard let url = URL(string: address), let host = url.host() else { return address }
  return url.port.map { "\(host):\($0)" } ?? host
}

/// Whether the profile does any cleanup, and whether that cleanup takes a prompt.
func doesCleanup(_ mock: Mock, _ profile: Profile) -> Bool {
  profile.id != .custom || (mock.customCleanup && (!mock.round5 || mock.customConfigured))
}

func takesPrompt(_ mock: Mock, _ profile: Profile) -> Bool {
  profile.id != .offline && doesCleanup(mock, profile)
}

/// Whether the profile's cleanup is an endpoint that Verify can probe.
func isVerifiable(_ mock: Mock, _ profile: Profile) -> Bool {
  switch profile.cleanup {
  case .hosted: true
  case .local: false
  case .custom: mock.customCleanup
  }
}

extension Mock {
  func currentModel(_ profile: Profile) -> String {
    profile.id == .custom ? customModel : modelOverrides[profile.id] ?? defaultModel(profile) ?? ""
  }

  func currentAddress(_ profile: Profile) -> String {
    profile.id == .custom ? customEndpoint : endpointOverrides[profile.id] ?? defaultEndpoint(profile) ?? ""
  }

  func modelListing(_ profile: Profile) -> [String] {
    guard profile.id == .custom else { return listing(profile.id) }
    return customEndpoint.contains("localhost") ? ollamaListing : ["gpt-oss-120b", "llama-4-scout", "qwen3-32b"]
  }

  /// Any edit to the address, the key, or the model makes the configuration a draft.
  func markDraft(_ id: ProfileID) {
    drafts.insert(id)
    failures[id] = nil
    flashVerified.remove(id)
  }

  func discard(_ id: ProfileID) {
    drafts.remove(id)
    failures[id] = nil
    editingModel.remove(id)
    editingAddress.remove(id)
    typesModelID.remove(id)
    modelOverrides[id] = lastVerified[id]?.model == defaultModel(profile(id)) ? nil : lastVerified[id]?.model
    endpointOverrides[id] = lastVerified[id]?.address == defaultEndpoint(profile(id)) ? nil : lastVerified[id]?.address
    keyDrafts[id == .custom ? customKey.id : ""] = nil
  }

  /// The one round trip `OpenAICompatibleCleanup.verify()` makes, simulated: endpoint, key, and
  /// model are proven together or the failure says which one to fix.
  func verify(_ id: ProfileID) {
    let item = profile(id)
    failures[id] = nil
    verifying.insert(id)
    let typedKey = !(keyDrafts[keySlot(item)?.id ?? ""] ?? "").isEmpty
    let hasKey = typedKey || storedKeys.contains(keySlot(item)?.id ?? "")
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
      guard !self.freezesVerifying else { return }
      self.verifying.remove(id)
      let address = self.currentAddress(item)
      let failure: VerifyFailure? =
        URL(string: address)?.host() == nil ? .unreachable
          : id == .custom && address.contains("gateway") && !hasKey ? .needsKey
          : (self.keyDrafts[self.keySlot(item)?.id ?? ""] ?? "") == "bad" ? .rejectedKey
          : !self.modelListing(item).contains(self.currentModel(item))
          && !(id != .custom && self.typesModelID.contains(id)) ? .unknownModel
          : nil
      if let failure {
        self.failures[id] = failure
        return
      }
      if let slot = self.keySlot(item), typedKey {
        self.storedKeys.insert(slot.id)
        self.keyDrafts[slot.id] = nil
      }
      self.drafts.remove(id)
      self.verified.insert(id)
      self.editingModel.remove(id)
      self.editingAddress.remove(id)
      self.lastVerified[id] = (self.currentModel(item), self.currentAddress(item))
      self.flashVerified.insert(id)
      DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
        withAnimation { _ = self.flashVerified.remove(id) }
      }
    }
  }

  func keySlot(_ profile: Profile) -> KeySlot? {
    switch profile.cleanup {
    case let .hosted(_, _, key, _): key
    case .local: nil
    case .custom: customKey
    }
  }

  /// A factory profile's fields that differ from its defaults, for the one Reset row.
  func overriddenFields(_ profile: Profile) -> String? {
    switch (modelOverrides[profile.id] != nil, endpointOverrides[profile.id] != nil) {
    case (true, true): "Model and address changed from the defaults"
    case (true, false): "Model changed from the default"
    case (false, true): "Address changed from the default"
    case (false, false): nil
    }
  }
}

struct PaneR3: View {
  @Bindable var mock: Mock

  var body: some View {
    let profile = mock.activeProfile
    let showsTimeout = doesCleanup(mock, profile)
    let showsInstructions = takesPrompt(mock, profile)
    Form {
      Section {
        LabeledContent("Profile") {
          ProfilePopUpR3(mock: mock)
        }
        // The selected profile's own settings, nested under the control that chose it.
        if mock.round5 {
          ProfileBlockR5(mock: mock, profile: profile)
            .padding(.leading, 20)
        } else {
          ProfileBlockR3(mock: mock, profile: profile)
            .padding(.leading, 20)
        }
      } footer: {
        if !mock.round4 {
          Text(privacyR2(mock, profile))
        }
      }
      // Only what applies to this profile; with nothing to show, the group is gone.
      if showsTimeout || showsInstructions {
        Section("All profiles") {
          if showsTimeout {
            LabeledContent("Give up after") {
              Picker("", selection: $mock.timeout) {
                ForEach([5, 10, 20, 30], id: \.self) { Text("\($0) seconds").tag($0) }
              }
              .labelsHidden()
              .fixedSize()
            }
          }
          if showsInstructions {
            LabeledContent("Additional instructions") {
              TextField("", text: $mock.instructions, axis: .vertical)
                .lineLimit(3, reservesSpace: true)
                .editableField()
            }
          }
        }
      }
    }
    .formStyle(.grouped)
    .sheet(isPresented: Binding(
      get: { mock.sheetMode && mock.editingGroup != nil },
      set: { if !$0 { mock.editingGroup = nil } },
    )) {
      SheetEditorR5(mock: mock)
    }
  }
}

/// One pop-up. Each item carries its own trouble, so the menu is still where every profile's
/// status can be read; the closed control shows the selected item, trouble included, and that is
/// the selected profile's only status mark.
struct ProfilePopUpR3: View {
  @Bindable var mock: Mock

  var body: some View {
    Picker("", selection: $mock.active) {
      ForEach(profiles) { item in
        Label {
          title(item)
        } icon: {
          Image(systemName: item.symbol)
        }
        .tag(item.id)
      }
    }
    .labelsHidden()
    .fixedSize()
    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { mock.popUpFrame = $0 }
  }

  private func title(_ item: Profile) -> Text {
    switch mock.readiness(item) {
    case .ready:
      Text(item.name)
    case let .needs(reason):
      Text(item.name) + Text("   \(reason)").foregroundStyle(.orange)
    case let .downloading(reason, _), let .note(reason):
      Text(item.name) + Text("   \(reason)").foregroundStyle(.secondary)
    }
  }
}

struct ProfileBlockR3: View {
  @Bindable var mock: Mock
  let profile: Profile

  var body: some View {
    LabeledContent("Engine", value: profile.engine)
    if let key = profile.engineKey {
      KeyRow(mock: mock, slot: key)
    }
    if profile.assets.contains(.parakeet), !mock.installed.contains(.parakeet) {
      MissingAssetRow(mock: mock, id: .parakeet)
    }
    switch profile.cleanup {
    case let .hosted(_, _, key, _):
      ModelRowR3(mock: mock, profile: profile)
      AddressRowR3(mock: mock, profile: profile)
      KeyFieldR3(mock: mock, profile: profile, slot: key, isOptional: false)
      if !mock.round4, !mock.drafts.contains(profile.id), let fields = mock.overriddenFields(profile) {
        // One Reset for the profile, and its label says what it puts back.
        LabeledContent(fields) {
          Button("Reset to Default") {
            mock.modelOverrides[profile.id] = nil
            mock.endpointOverrides[profile.id] = nil
            mock.markDraft(profile.id)
          }
        }
      }
      VerifyBarR3(mock: mock, profile: profile)
    case .local:
      if mock.installed.contains(.s1) {
        LabeledContent("Model", value: "S1-mini")
      } else {
        MissingAssetRow(mock: mock, id: .s1)
      }
    case .custom:
      Toggle("Clean up transcripts", isOn: $mock.customCleanup)
      if mock.customCleanup {
        LabeledContent("Address") {
          TextField("", text: Binding(
            get: { mock.customEndpoint },
            set: {
              guard $0 != mock.customEndpoint else { return }
              mock.customEndpoint = $0
              mock.markDraft(.custom)
            },
          ))
          .editableField()
        }
        KeyFieldR3(mock: mock, profile: profile, slot: customKey, isOptional: true)
        ModelRowR3(mock: mock, profile: profile)
        VerifyBarR3(mock: mock, profile: profile)
      }
      if mock.round4 {
        Toggle(isOn: $mock.customBoost) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Boost vocabulary")
            if mock.customBoost, mock.customCleanup {
              Label("Cleanup usually handles your dictionary better without this.",
                    systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.secondary)
            }
          }
        }
      } else {
      Toggle(isOn: $mock.customBoost) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Boost vocabulary")
          Text(
            mock.customCleanup
              ? "Your dictionary already reaches the cleanup model."
              : "With cleanup off, this is the only way your dictionary reaches the transcript.",
          )
          .font(.callout)
          .foregroundStyle(.secondary)
        }
      }
      }
    }
  }
}

/// Puts one overridden field back to its factory value. It sits before Edit, so Edit keeps its
/// column whether or not the field is overridden.
struct ResetFieldButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Label("Reset to Default", systemImage: "arrow.counterclockwise")
        .labelStyle(.iconOnly)
    }
    .buttonStyle(.borderless)
    .help("Reset to Default")
    .accessibilityLabel("Reset to Default")
  }
}

/// Model: Custom's is always the picker. A factory profile's is a locked value with Edit, exactly
/// like Address; Edit opens the same picker and makes the configuration a draft.
struct ModelRowR3: View {
  @Bindable var mock: Mock
  let profile: Profile

  var body: some View {
    let isOpen = profile.id == .custom || mock.editingModel.contains(profile.id)
    if isOpen {
      LabeledContent("Model") {
        HStack(spacing: 8) {
          Picker("", selection: choice) {
            ForEach(mock.modelListing(profile), id: \.self) { Text($0).tag($0) }
            Divider()
            Text("Custom…").tag(customModelTag)
          }
          .labelsHidden()
          .fixedSize()
          Button("Load Models") {}
        }
      }
      if mock.typesModelID.contains(profile.id) {
        LabeledContent("Model ID") {
          TextField("", text: Binding(
            get: { mock.currentModel(profile) },
            set: { value in
              guard value != mock.currentModel(profile) else { return }
              if profile.id == .custom {
                mock.customModel = value
              } else {
                mock.modelOverrides[profile.id] = value == defaultModel(profile) ? nil : value
              }
              mock.markDraft(profile.id)
            },
          ))
          .editableField()
        }
      }
    } else {
      LabeledContent("Model") {
        HStack(spacing: 12) {
          Text(mock.currentModel(profile))
            .lineLimit(1)
            .truncationMode(.middle)
          if mock.round4, mock.modelOverrides[profile.id] != nil {
            ResetFieldButton {
              mock.modelOverrides[profile.id] = nil
              mock.typesModelID.remove(profile.id)
              mock.markDraft(profile.id)
            }
          }
          Button("Edit") {
            mock.editingModel.insert(profile.id)
            mock.markDraft(profile.id)
          }
        }
      }
    }
  }

  private var choice: Binding<String> {
    Binding(
      get: {
        mock.typesModelID.contains(profile.id) ? customModelTag : mock.currentModel(profile)
      },
      set: { value in
        guard value != choice.wrappedValue else { return }
        mock.markDraft(profile.id)
        if value == customModelTag {
          mock.typesModelID.insert(profile.id)
          return
        }
        mock.typesModelID.remove(profile.id)
        if profile.id == .custom {
          mock.customModel = value
        } else {
          mock.modelOverrides[profile.id] = value == defaultModel(profile) ? nil : value
        }
      },
    )
  }
}

struct AddressRowR3: View {
  @Bindable var mock: Mock
  let profile: Profile

  var body: some View {
    if mock.editingAddress.contains(profile.id) {
      LabeledContent("Address") {
        TextField("", text: Binding(
          get: { mock.currentAddress(profile) },
          set: {
            guard $0 != mock.currentAddress(profile) else { return }
            mock.endpointOverrides[profile.id] = $0 == defaultEndpoint(profile) ? nil : $0
            mock.markDraft(profile.id)
          },
        ))
        .editableField()
      }
    } else {
      LabeledContent("Address") {
        HStack(spacing: 12) {
          Text(mock.currentAddress(profile))
            .lineLimit(1)
            .truncationMode(.middle)
          if mock.round4, mock.endpointOverrides[profile.id] != nil {
            ResetFieldButton {
              mock.endpointOverrides[profile.id] = nil
              mock.markDraft(profile.id)
            }
          }
          Button("Edit") {
            mock.editingAddress.insert(profile.id)
            mock.markDraft(profile.id)
          }
        }
      }
    }
  }
}

/// A key is a field until one is stored; there is no Save, because Verify is what commits it.
/// Custom's is captioned Optional, for endpoints such as Ollama that take none.
struct KeyFieldR3: View {
  @Bindable var mock: Mock
  let profile: Profile
  let slot: KeySlot
  let isOptional: Bool
  @FocusState private var isFocused: Bool

  var body: some View {
    if mock.storedKeys.contains(slot.id) {
      LabeledContent(slot.label) {
        HStack(spacing: 12) {
          Text(slot.masked + String(repeating: "•", count: 10))
            .foregroundStyle(.secondary)
          Button("Replace") {
            mock.storedKeys.remove(slot.id)
            mock.markDraft(profile.id)
          }
        }
      }
    } else {
      LabeledContent {
        SecureField("", text: Binding(
          get: { mock.keyDrafts[slot.id] ?? "" },
          set: {
            guard $0 != (mock.keyDrafts[slot.id] ?? "") else { return }
            mock.keyDrafts[slot.id] = $0
            mock.markDraft(profile.id)
          },
        ))
        .editableField()
        .focused($isFocused)
      } label: {
        if isOptional {
          VStack(alignment: .leading, spacing: 2) {
            Text(slot.label)
            Text("Optional")
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        } else {
          Text(slot.label)
        }
      }
      .onChange(of: mock.failures[profile.id]) { _, failure in
        if failure == .needsKey { isFocused = true }
      }
      .task {
        // The capture's window settles its first responder at 0.6 s; focus after that.
        guard mock.failures[profile.id] == .needsKey else { return }
        try? await Task.sleep(for: .milliseconds(1200))
        isFocused = true
      }
    }
  }
}

/// Present only while there is something to verify, something verifying, or something to fix.
/// A configuration that verified shows nothing here: no problem is the success.
struct VerifyBarR3: View {
  @Bindable var mock: Mock
  let profile: Profile

  var body: some View {
    let id = profile.id
    let isVerifying = mock.verifying.contains(id)
    let failure = mock.failures[id]
    let isDraft = mock.drafts.contains(id)
    let hasFallback = mock.verified.contains(id) && mock.lastVerified[id] != nil
    if isDraft || isVerifying || failure != nil || mock.flashVerified.contains(id) {
      VStack(alignment: .trailing, spacing: 6) {
        HStack(spacing: 8) {
          if mock.flashVerified.contains(id), !isDraft {
            Label("Verified", systemImage: "checkmark")
              .foregroundStyle(.secondary)
          } else {
            if hasFallback, !isVerifying {
              Button("Discard") { mock.discard(id) }
            }
            Button {
              mock.verify(id)
            } label: {
              HStack(spacing: 6) {
                if isVerifying {
                  ProgressView()
                    .controlSize(.small)
                }
                Text(isVerifying ? "Verifying" : "Verify")
              }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isVerifying)
          }
        }
        if let failure {
          FailureLineR3(mock: mock, profile: profile, failure: failure)
        }
        if isDraft, hasFallback, let last = mock.lastVerified[id] {
          Text("Dictation keeps using \(last.model) at \(hostOf(last.address)) until this verifies.")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .trailing)
    }
  }
}

struct FailureLineR3: View {
  @Bindable var mock: Mock
  let profile: Profile
  let failure: VerifyFailure

  var body: some View {
    let host = hostOf(mock.currentAddress(profile))
    HStack(spacing: 6) {
      Label {
        switch failure {
        case .unreachable: Text("Couldn’t reach \(host). Check the address.")
        case .needsKey: Text("This endpoint needs an API key.")
        case .rejectedKey: Text("The endpoint rejected this key.")
        case .unknownModel: Text("\(host) has no model ‘\(mock.currentModel(profile))’.")
        }
      } icon: {
        Image(systemName: "exclamationmark.triangle.fill")
      }
      .foregroundStyle(.orange)
      if failure == .unknownModel {
        // The endpoint's own listing, one click from the message that needs it.
        Menu {
          ForEach(mock.modelListing(profile), id: \.self) { model in
            Button(model) {
              mock.typesModelID.remove(profile.id)
              if profile.id == .custom {
                mock.customModel = model
              } else {
                mock.modelOverrides[profile.id] = model == defaultModel(profile) ? nil : model
              }
              mock.markDraft(profile.id)
            }
          }
        } label: {
          Text("Choose from its models")
            .foregroundStyle(.link)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
      }
    }
    .font(.callout)
  }
}

// MARK: - Round three: the Models page, three options from another designer

func assetSymbol(_ id: AssetID) -> String {
  switch id {
  case .gate: "waveform"
  case .parakeet: "mic"
  case .s1: "text.badge.checkmark"
  }
}

func assetPurpose(_ id: AssetID) -> String {
  switch id {
  case .gate: "Silence rejection"
  case .parakeet: "Local speech engine"
  case .s1: "Local cleanup"
  }
}

/// Every asset has one fixed-width trailing slot that holds its whole status.
struct StatusSlotR3: View {
  @Bindable var mock: Mock
  let id: AssetID
  /// Option C puts its actions in a bottom bar, so its slot carries no buttons.
  var showsActions = true

  var body: some View {
    let item = asset(id)
    let isNeeded = mock.activeProfile.assets.contains(id)
    HStack(spacing: 10) {
      if let fraction = mock.downloading[id] {
        ProgressView(value: fraction)
          .controlSize(.small)
          .frame(width: 120)
      } else if mock.queued.contains(id) {
        Text("Waiting")
          .foregroundStyle(.secondary)
      } else if mock.failed.contains(id) {
        Label("Couldn’t download", systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
          .fixedSize()
        if showsActions {
          Button("Try Again") {
            mock.failed.remove(id)
            mock.downloading[id] = 0.01
          }
        }
      } else if mock.installed.contains(id) {
        Text(item.size)
          .monospacedDigit()
          .foregroundStyle(.secondary)
        if showsActions {
          Button(isNeeded ? "Delete…" : "Delete") {
            if isNeeded { mock.pendingDeletion = id } else { mock.installed.remove(id) }
          }
        }
      } else if showsActions {
        if isNeeded {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
        }
        Button("Download") { mock.downloading[id] = 0.01 }
      } else {
        if isNeeded {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
        }
        Text("Not downloaded")
          .foregroundStyle(.secondary)
      }
    }
    .frame(width: showsActions ? 290 : 160, alignment: .trailing)
  }
}

/// Option A: inventory. One section, fixed order, rows never move. In use is an accent symbol and
/// a caption naming the profile; nothing says "not in use".
struct ModelsR3A: View {
  @Bindable var mock: Mock

  var body: some View {
    Form {
      Section {
        ForEach(assets, id: \.id) { item in
          let inUse = mock.activeProfile.assets.contains(item.id)
          LabeledContent {
            StatusSlotR3(mock: mock, id: item.id)
          } label: {
            Label {
              VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                Text(inUse ? "In use by \(mock.activeProfile.name)" : assetPurpose(item.id))
                  .font(.callout)
                  .foregroundStyle(.secondary)
              }
            } icon: {
              Image(systemName: assetSymbol(item.id))
                .foregroundStyle(inUse ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
          }
        }
      }
    }
    .formStyle(.grouped)
  }
}

/// Option B: the active profile's whole pipeline first, hosted legs included, then whatever else
/// is on disk. A missing asset nothing needs is not listed.
struct ModelsR3B: View {
  @Bindable var mock: Mock

  var body: some View {
    let active = mock.activeProfile
    let others = assets.filter {
      !active.assets.contains($0.id)
        && (mock.installed.contains($0.id) || mock.downloading[$0.id] != nil
          || mock.queued.contains($0.id) || mock.failed.contains($0.id))
    }
    Form {
      Section(active.name) {
        ForEach(assets.filter { active.assets.contains($0.id) }, id: \.id) { item in
          row(item.name, caption: assetPurpose(item.id)) { StatusSlotR3(mock: mock, id: item.id) }
        }
        ForEach(hostedLegs(active), id: \.name) { leg in
          row(leg.name, caption: leg.caption) {
            Text("Hosted")
              .foregroundStyle(.secondary)
              .frame(width: 290, alignment: .trailing)
          }
        }
      }
      if !others.isEmpty {
        Section("Other models on this Mac") {
          ForEach(others, id: \.id) { item in
            row(item.name, caption: assetPurpose(item.id)) { StatusSlotR3(mock: mock, id: item.id) }
          }
        }
      }
    }
    .formStyle(.grouped)
  }

  private func row(_ name: String, caption: String, @ViewBuilder slot: () -> some View) -> some View {
    LabeledContent {
      slot()
    } label: {
      VStack(alignment: .leading, spacing: 2) {
        Text(name)
        Text(caption)
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func hostedLegs(_ profile: Profile) -> [(name: String, caption: String)] {
    var legs: [(String, String)] = []
    if profile.engineIsHosted {
      legs.append((profile.engine, "Speech"))
    }
    switch profile.id {
    case .haiku: legs.append(("Claude Haiku", "Cleanup"))
    case .accurate: legs.append(("Gemini", "Cleanup"))
    case .cerebras: legs.append(("gpt-oss-120b", "Cleanup"))
    default: break
    }
    return legs
  }
}

/// Option C: a components table in the manner of Xcode's Settings › Components. The Size column
/// is the status slot; the actions sit in a bottom bar and act on the selected row.
struct ModelsR3C: View {
  @Bindable var mock: Mock
  @State private var selection: AssetID? = .parakeet
  @FocusState private var isTableFocused: Bool

  struct Row: Identifiable {
    let id: AssetID
  }

  var body: some View {
    let selected = selection.map(asset)
    Table(assets.map { Row(id: $0.id) }, selection: $selection) {
      TableColumn("Model") { row in
        Text(asset(row.id).name)
      }
      .width(min: 180, ideal: 220)
      TableColumn("Used by") { row in
        usedBy(row.id)
      }
      .width(min: 180, ideal: 220)
      TableColumn("Size") { row in
        StatusSlotR3(mock: mock, id: row.id, showsActions: false)
      }
      .width(min: 160, ideal: 170)
    }
    .focused($isTableFocused)
    .task {
      try? await Task.sleep(for: .milliseconds(1200))
      isTableFocused = true
    }
    .safeAreaBar(edge: .bottom) {
      HStack(spacing: 8) {
        Spacer()
        Button("Download") {
          if let id = selection { mock.downloading[id] = 0.01 }
        }
        .disabled(selected.map { mock.installed.contains($0.id) || mock.downloading[$0.id] != nil } ?? true)
        Button("Delete…") {
          mock.pendingDeletion = selection
        }
        .disabled(selected.map { !mock.installed.contains($0.id) } ?? true)
      }
      .padding(12)
    }
  }

  private func usedBy(_ id: AssetID) -> Text {
    let users = profiles.filter { $0.assets.contains(id) }
    let active = mock.activeProfile
    if users.contains(where: { $0.id == active.id }) {
      let first = Text(active.name).fontWeight(.medium).foregroundStyle(.primary)
      let rest = users.count - 1
      return rest == 0 ? first : first + Text(" + \(rest) more").foregroundStyle(.secondary)
    }
    let text = users.count == 1 ? users[0].name : "\(users.count) profiles"
    return Text(text).foregroundStyle(.secondary)
  }
}

// MARK: - Round five: inline edit mode, only a verified configuration is ever stored

enum FieldR5: Hashable {
  case address, key, model, modelID
}

struct FailureR5: Equatable {
  let field: FieldR5
  let message: String
}

/// What a stored key looks like inside a secure field: dots, never the key.
let storedKeySentinel = "stored-key-000000"

let launchTime = Date()

extension Mock {
  func endpointListing(for profile: Profile, address: String) -> [String] {
    guard profile.id == .custom else { return listing(profile.id) }
    return address.contains("localhost") ? ollamaListing : ["gpt-oss-120b", "llama-4-scout", "qwen3-32b"]
  }

  func focusOn(_ field: FieldR5?) {
    r5Focus = field
    focusTick += 1
  }

  /// Edit on any row opens the whole endpoint group: address, key, and model verify together.
  func beginEdit(_ profile: Profile, _ field: FieldR5) {
    let isNew = profile.id == .custom && !customConfigured
    editingGroup = profile.id
    r5Failure = nil
    draftAddress = isNew ? "" : currentAddress(profile)
    draftModel = isNew ? "" : currentModel(profile)
    draftKey = keySlot(profile).map { storedKeys.contains($0.id) ? storedKeySentinel : "" } ?? ""
    draftTypesID = !draftModel.isEmpty
      && !endpointListing(for: profile, address: draftAddress).contains(draftModel)
    focusOn(field == .model && draftTypesID ? .modelID : field)
  }

  /// While checking, Cancel stops the check and leaves the fields as typed; otherwise it discards.
  func cancelEdit() {
    if checking {
      checking = false
      checkToken += 1
      return
    }
    editingGroup = nil
    r5Failure = nil
  }

  /// ↺ refills one field with its factory value and saves through the same check.
  func resetField(_ profile: Profile, _ field: FieldR5) {
    beginEdit(profile, field)
    if field == .address {
      draftAddress = defaultEndpoint(profile) ?? ""
    } else {
      draftModel = defaultModel(profile) ?? ""
      draftTypesID = false
    }
    save(profile)
  }

  func save(_ profile: Profile) {
    r5Failure = nil
    checking = true
    checkToken += 1
    let token = checkToken
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
      guard token == self.checkToken, !self.freezesChecking else { return }
      self.checking = false
      if let failure = self.check(profile) {
        self.r5Failure = failure
        self.focusOn(failure.field == .model && self.draftTypesID ? .modelID : failure.field)
        return
      }
      self.commit(profile)
    }
  }

  /// The one round trip `verify()` makes, simulated.
  func check(_ profile: Profile) -> FailureR5? {
    let host = hostOf(draftAddress)
    guard let url = URL(string: draftAddress), url.host() != nil, url.port != 11435 else {
      return FailureR5(field: .address, message: "Couldn’t reach \(host.isEmpty ? "this address" : host).")
    }
    if draftAddress.contains("gateway.internal"), draftKey.isEmpty {
      return FailureR5(field: .key, message: "This endpoint needs an API key.")
    }
    if draftKey == "bad" {
      return FailureR5(field: .key, message: "The endpoint rejected this key.")
    }
    let typedOnFactory = profile.isFactory && draftTypesID
    if !typedOnFactory, !endpointListing(for: profile, address: draftAddress).contains(draftModel) {
      return FailureR5(field: .model, message: "\(host) has no model ‘\(draftModel)’.")
    }
    return nil
  }

  /// Everything at once, or nothing.
  func commit(_ profile: Profile) {
    if let slot = keySlot(profile), draftKey != storedKeySentinel {
      if draftKey.isEmpty { storedKeys.remove(slot.id) } else { storedKeys.insert(slot.id) }
    }
    revoked.remove(profile.id)
    if profile.id == .custom {
      customEndpoint = draftAddress
      customModel = draftModel
      customConfigured = true
      customCleanup = true
    } else {
      modelOverrides[profile.id] = draftModel == defaultModel(profile) ? nil : draftModel
      endpointOverrides[profile.id] = draftAddress == defaultEndpoint(profile) ? nil : draftAddress
    }
    editingGroup = nil
  }
}

struct ProfileBlockR5: View {
  @Bindable var mock: Mock
  let profile: Profile

  var body: some View {
    let isEditing = mock.editingGroup == profile.id && !mock.sheetMode
    LabeledContent("Engine", value: profile.engine)
    if let key = profile.engineKey {
      KeyRow(mock: mock, slot: key)
    }
    if profile.assets.contains(.parakeet), !mock.installed.contains(.parakeet) {
      MissingAssetRow(mock: mock, id: .parakeet)
    }
    switch profile.cleanup {
    case .hosted:
      EndpointRowsR5(mock: mock, profile: profile, isEditing: isEditing)
    case .local:
      if mock.installed.contains(.s1) {
        LabeledContent("Model", value: "S1-mini")
      } else {
        MissingAssetRow(mock: mock, id: .s1)
      }
    case .custom:
      // There is nothing to switch on until a configuration has verified.
      if mock.customConfigured {
        Toggle("Clean up transcripts", isOn: $mock.customCleanup)
          .disabled(isEditing)
      }
      if !mock.customConfigured || mock.customCleanup {
        EndpointRowsR5(mock: mock, profile: profile, isEditing: isEditing)
      }
      Toggle(isOn: $mock.customBoost) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Boost vocabulary")
          if mock.customBoost, doesCleanup(mock, profile) {
            Label("Cleanup usually handles your dictionary better without this.",
                  systemImage: "exclamationmark.triangle")
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }
}

/// The endpoint group: resting values that always verified, or all three fields at once.
struct EndpointRowsR5: View {
  @Bindable var mock: Mock
  let profile: Profile
  let isEditing: Bool
  var showsButtons = true
  @FocusState private var focus: FieldR5?

  var body: some View {
    Group {
      if isEditing {
        editingRows
      } else if profile.id == .custom, !mock.customConfigured {
        // Not set up: a calm resting state, not a warning.
        LabeledContent("Address", value: "None")
        LabeledContent("API key", value: "None")
        LabeledContent("Model", value: "None")
        HStack {
          Spacer()
          Button("Set Up") { mock.beginEdit(profile, .address) }
        }
      } else {
        restingRows
      }
    }
    .task(id: mock.focusTick) {
      // At launch the window settles its own first responder at 0.6 s; focus after that.
      try? await Task.sleep(for: .milliseconds(Date().timeIntervalSince(launchTime) < 1.5 ? 1200 : 50))
      focus = mock.r5Focus
    }
  }

  // MARK: Resting

  @ViewBuilder private var restingRows: some View {
    if profile.id == .custom {
      restingRow("Address", mock.customEndpoint, field: .address, isOverridden: false)
      keyRestRow
      restingRow("Model", mock.customModel, field: .model, isOverridden: false)
    } else {
      restingRow("Model", mock.currentModel(profile), field: .model,
                 isOverridden: mock.modelOverrides[profile.id] != nil)
      restingRow("Address", mock.currentAddress(profile), field: .address,
                 isOverridden: mock.endpointOverrides[profile.id] != nil)
      keyRestRow
    }
  }

  private func restingRow(_ title: String, _ value: String, field: FieldR5, isOverridden: Bool) -> some View {
    LabeledContent(title) {
      HStack(spacing: 12) {
        Text(value)
          .lineLimit(1)
          .truncationMode(.middle)
        if isOverridden {
          ResetFieldButton { mock.resetField(profile, field) }
        }
        Button("Edit") { mock.beginEdit(profile, field) }
      }
    }
  }

  @ViewBuilder private var keyRestRow: some View {
    if let slot = mock.keySlot(profile) {
      let isStored = mock.storedKeys.contains(slot.id)
      LabeledContent {
        HStack(spacing: 12) {
          Text(isStored ? slot.masked + String(repeating: "•", count: 10) : "None")
            .foregroundStyle(.secondary)
          Button(isStored ? "Replace" : "Edit") { mock.beginEdit(profile, .key) }
        }
      } label: {
        if mock.revoked.contains(profile.id) {
          VStack(alignment: .leading, spacing: 2) {
            Text(slot.label)
            Text("\(slot.provider) rejected this key on the last dictation")
              .font(.callout)
              .foregroundStyle(.orange)
          }
        } else {
          Text(slot.label)
        }
      }
    }
  }

  // MARK: Editing

  @ViewBuilder private var editingRows: some View {
    if profile.id == .custom {
      addressField
      keyField
      modelField
    } else {
      modelField
      addressField
      keyField
    }
    if showsButtons {
      HStack(spacing: 8) {
        Spacer()
        SaveCancelR5(mock: mock, profile: profile)
      }
    }
  }

  private var addressField: some View {
    LabeledContent("Address") {
      VStack(alignment: .leading, spacing: 4) {
        TextField("", text: $mock.draftAddress)
          .editableField()
          .focused($focus, equals: .address)
          .disabled(mock.checking)
        failureLine(.address)
      }
    }
  }

  @ViewBuilder private var keyField: some View {
    if let slot = mock.keySlot(profile) {
      LabeledContent {
        VStack(alignment: .leading, spacing: 4) {
          SecureField("", text: $mock.draftKey)
            .editableField()
            .focused($focus, equals: .key)
            .disabled(mock.checking)
          failureLine(.key)
        }
      } label: {
        if profile.id == .custom {
          VStack(alignment: .leading, spacing: 2) {
            Text(slot.label)
            Text("Optional")
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        } else {
          Text(slot.label)
        }
      }
    }
  }

  @ViewBuilder private var modelField: some View {
    LabeledContent("Model") {
      VStack(alignment: .trailing, spacing: 4) {
        HStack(spacing: 8) {
          Picker("", selection: modelChoice) {
            ForEach(mock.endpointListing(for: profile, address: mock.draftAddress), id: \.self) {
              Text($0).tag($0)
            }
            Divider()
            Text("Custom…").tag(customModelTag)
          }
          .labelsHidden()
          .fixedSize()
          .focusable()
          .focused($focus, equals: .model)
          Button("Load Models") {}
        }
        .disabled(mock.checking)
        if !mock.draftTypesID {
          failureLine(.model)
        }
      }
    }
    if mock.draftTypesID {
      LabeledContent("Model ID") {
        VStack(alignment: .leading, spacing: 4) {
          TextField("", text: $mock.draftModel)
            .editableField()
            .focused($focus, equals: .modelID)
            .disabled(mock.checking)
          failureLine(.model)
        }
      }
    }
  }

  private var modelChoice: Binding<String> {
    Binding(
      get: { mock.draftTypesID ? customModelTag : mock.draftModel },
      set: { value in
        if value == customModelTag {
          mock.draftTypesID = true
          mock.focusOn(.modelID)
        } else {
          mock.draftTypesID = false
          mock.draftModel = value
        }
      },
    )
  }

  @ViewBuilder private func failureLine(_ field: FieldR5) -> some View {
    if let failure = mock.r5Failure, failure.field == field {
      Text(failure.message)
        .font(.callout)
        .foregroundStyle(.red)
    }
  }
}

/// Save is the default button (Return); Cancel is the cancel button (Escape) and stops a check.
struct SaveCancelR5: View {
  @Bindable var mock: Mock
  let profile: Profile

  var body: some View {
    Button("Cancel") { mock.cancelEdit() }
      .keyboardShortcut(.cancelAction)
    Button {
      mock.save(profile)
    } label: {
      HStack(spacing: 6) {
        if mock.checking {
          ProgressView()
            .controlSize(.small)
        }
        Text(mock.checking ? "Checking…" : "Save")
      }
    }
    .buttonStyle(.borderedProminent)
    .keyboardShortcut(.defaultAction)
    .disabled(mock.checking)
  }
}

/// For comparison only: the same fields and buttons in a sheet.
struct SheetEditorR5: View {
  @Bindable var mock: Mock

  var body: some View {
    let profile = mock.activeProfile
    VStack(alignment: .leading, spacing: 0) {
      Form {
        Section(profile.name) {
          EndpointRowsR5(mock: mock, profile: profile, isEditing: true, showsButtons: false)
        }
      }
      .formStyle(.grouped)
      .scrollDisabled(true)
      .frame(height: 178)
      HStack(spacing: 8) {
        Spacer()
        SaveCancelR5(mock: mock, profile: profile)
      }
      .padding([.horizontal, .bottom], 20)
    }
    .frame(width: 600)
  }
}

// MARK: - Round six: four Models page concepts from another designer

enum ReceivesR6 {
  case audio, transcript
  var symbol: String { self == .audio ? "waveform" : "text.quote" }
}

/// One stage of a profile's stack: a local asset or a hosted model.
struct ComponentR6: Identifiable {
  let id: String
  let name: String
  let provider: String
  var asset: AssetID?
  var receives: ReceivesR6?
  var isHosted: Bool { asset == nil }
}

let compParakeet = ComponentR6(id: "parakeet", name: "Parakeet TDT v2", provider: "This Mac", asset: .parakeet)
let compS1 = ComponentR6(id: "s1", name: "S1-mini", provider: "This Mac", asset: .s1)
let compScribe = ComponentR6(id: "scribe", name: "ElevenLabs Scribe v2", provider: "ElevenLabs", receives: .audio)
let compHaiku = ComponentR6(id: "haiku", name: "Claude Haiku 5.5", provider: "Anthropic", receives: .transcript)
let compGemini = ComponentR6(id: "gemini", name: "Gemini 3.8 Flash", provider: "Google", receives: .transcript)
let compGptOss = ComponentR6(id: "gptoss", name: "gpt-oss-120b", provider: "Cerebras", receives: .transcript)
let compEndpoint = ComponentR6(id: "endpoint", name: "Your endpoint", provider: "Optional", receives: .transcript)

func speechR6(_ id: ProfileID) -> ComponentR6 { id == .accurate ? compScribe : compParakeet }

func cleanupR6(_ id: ProfileID) -> ComponentR6 {
  switch id {
  case .haiku: compHaiku
  case .offline: compS1
  case .accurate: compGemini
  case .cerebras: compGptOss
  case .custom: compEndpoint
  }
}

/// The order that lets Parakeet be one block across four neighbouring rows.
let blockOrder: [ProfileID] = [.haiku, .cerebras, .custom, .offline, .accurate]

extension Mock {
  func usesR6(_ component: ComponentR6) -> Bool {
    speechR6(active).id == component.id || cleanupR6(active).id == component.id
  }

  var unusedTotal: Double { unused.map(\.megabytes).reduce(0, +) }
}

/// Active is a 2 pt tint stroke; used by the active profile is a tint fill; unused is a quinary
/// fill with a hairline; hosted is a dashed border.
struct CellBackgroundR6: ViewModifier {
  let isUsed: Bool
  var isHosted = false
  var isActive = false

  func body(content: Content) -> some View {
    content
      .background {
        RoundedRectangle(cornerRadius: 8)
          .fill(isUsed ? AnyShapeStyle(.tint.quinary) : AnyShapeStyle(.quinary))
      }
      .overlay {
        if isActive {
          RoundedRectangle(cornerRadius: 8).strokeBorder(.tint, lineWidth: 2)
        } else if isHosted {
          RoundedRectangle(cornerRadius: 8)
            .strokeBorder(.separator, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        } else if !isUsed {
          RoundedRectangle(cornerRadius: 8).strokeBorder(.separator, lineWidth: 1)
        }
      }
  }
}

extension View {
  func cellR6(used: Bool, hosted: Bool = false, active: Bool = false) -> some View {
    modifier(CellBackgroundR6(isUsed: used, isHosted: hosted, isActive: active))
  }
}

/// The shared status rules: size, progress, Waiting, failed with Retry, or Download.
struct LocalStatusR6: View {
  @Bindable var mock: Mock
  let id: AssetID
  var showsSize = true
  var showsDelete = true

  var body: some View {
    let item = asset(id)
    if let fraction = mock.downloading[id] {
      HStack(spacing: 6) {
        ProgressView(value: fraction)
          .controlSize(.small)
          .frame(width: 56)
        Text("\(Int(fraction * 100))%")
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
    } else if mock.queued.contains(id) {
      Label("Waiting", systemImage: "clock")
        .foregroundStyle(.secondary)
    } else if mock.failed.contains(id) {
      HStack(spacing: 6) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.red)
        Button("Retry") {
          mock.failed.remove(id)
          mock.downloading[id] = 0.01
        }
      }
    } else if mock.installed.contains(id) {
      HStack(spacing: 8) {
        if showsSize {
          Text(item.size)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        if showsDelete {
          DeleteButtonR6(mock: mock, id: id)
        }
      }
    } else {
      Button("Download") { mock.downloading[id] = 0.01 }
    }
  }
}

struct DeleteButtonR6: View {
  @Bindable var mock: Mock
  let id: AssetID

  var body: some View {
    let isNeeded = mock.activeProfile.assets.contains(id)
    Button(isNeeded ? "Delete…" : "Delete") {
      if isNeeded { mock.pendingDeletion = id } else { mock.installed.remove(id) }
    }
  }
}

// MARK: Concept 1: Shared blocks

struct BlocksR6: View {
  @Bindable var mock: Mock
  let rowHeight: CGFloat = 56
  let gap: CGFloat = 6

  var body: some View {
    let total = rowHeight * 5 + gap * 4
    ScrollView {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          Color.clear.frame(width: 150, height: 1)
          stageLabel("GATE").frame(width: 44)
          stageLabel("SPEECH").frame(width: 190, alignment: .leading)
          stageLabel("CLEANUP").frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
        }
        HStack(alignment: .top, spacing: 8) {
          VStack(spacing: gap) {
            ForEach(blockOrder) { id in rowHeader(id) }
          }
          .frame(width: 150)
          gateCell
            .frame(width: 44, height: total)
          VStack(spacing: gap) {
            parakeetBlock
              .frame(height: rowHeight * 4 + gap * 3)
            componentCell(
              ComponentR6(id: "scribe", name: "Scribe v2", provider: "ElevenLabs", receives: .audio),
              rows: 4 ..< 5,
            )
              .frame(height: rowHeight)
          }
          .frame(width: 190)
          VStack(spacing: gap) {
            ForEach(Array(blockOrder.enumerated()), id: \.element) { index, id in
              componentCell(cleanupR6(id), rows: index ..< index + 1)
                .frame(height: rowHeight)
            }
          }
          .frame(minWidth: 220, maxWidth: .infinity)
        }
        Text(footer)
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.top, 4)
      }
      .padding(20)
    }
  }

  private var activeRow: Int { blockOrder.firstIndex(of: mock.active) ?? 0 }

  private var footer: String {
    let base = "On this Mac: \(formatSize(mock.installedTotal))"
    let unused = mock.unusedTotal
    return unused > 0 ? "\(base) · \(formatSize(unused)) not used by \(mock.activeProfile.name)" : base
  }

  private func stageLabel(_ text: String) -> some View {
    Text(text)
      .font(.caption)
      .foregroundStyle(.secondary)
  }

  /// 3×24 pt tint capsules, 4 pt inside the leading edge, on every cell of the active row.
  private func marker(_ rows: Range<Int>) -> some View {
    let isOnRow = rows.contains(activeRow)
    let top = CGFloat(activeRow - rows.lowerBound) * (rowHeight + gap) + (rowHeight - 24) / 2
    return Capsule()
      .fill(.tint)
      .frame(width: 3, height: 24)
      .padding(.leading, 4)
      .padding(.top, top)
      .opacity(isOnRow ? 1 : 0)
  }

  private func rowHeader(_ id: ProfileID) -> some View {
    Text(profile(id).name)
      .lineLimit(2)
      .padding(.horizontal, 10)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      .frame(height: rowHeight)
      .cellR6(used: false, active: id == mock.active)
      .contentShape(.rect)
      .onTapGesture { mock.active = id }
  }

  /// A fixed 44 pt cell; the rotated label is an overlay so it can't widen the cell.
  private var gateCell: some View {
    Color.clear
      .overlay {
        Text("Speech gate · 1.1 MB")
          .font(.callout)
          .fixedSize()
          .rotationEffect(.degrees(-90))
      }
      .cellR6(used: true)
      .overlay(alignment: .topLeading) { marker(0 ..< 5) }
  }

  private var parakeetBlock: some View {
    VStack(alignment: .leading, spacing: 6) {
      Label("Parakeet TDT v2", systemImage: "internaldrive")
      Text("This Mac")
        .font(.callout)
        .foregroundStyle(.secondary)
      LocalStatusR6(mock: mock, id: .parakeet, showsDelete: false)
        .font(.callout)
      Text("4 profiles")
        .font(.callout)
        .foregroundStyle(.secondary)
      if mock.installed.contains(.parakeet) {
        DeleteButtonR6(mock: mock, id: .parakeet)
      }
    }
    .padding(.leading, 16)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .cellR6(used: mock.usesR6(compParakeet))
    .overlay(alignment: .topLeading) { marker(0 ..< 4) }
  }

  private func componentCell(_ component: ComponentR6, rows: Range<Int>) -> some View {
    HStack(spacing: 8) {
      Image(systemName: component.isHosted ? "cloud" : "internaldrive")
        .foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 1) {
        Text(component.name)
          .lineLimit(1)
        Text(component.provider)
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 4)
      if let receives = component.receives {
        Image(systemName: receives.symbol)
          .foregroundStyle(.secondary)
      } else if let id = component.asset {
        LocalStatusR6(mock: mock, id: id)
      }
    }
    .padding(.leading, 14)
    .padding(.trailing, 10)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .cellR6(used: mock.usesR6(component), hosted: component.isHosted)
    .overlay(alignment: .topLeading) { marker(rows) }
  }
}

// MARK: Concept 2: Transit map

struct TransitLayoutR6 {
  let width: CGFloat
  let local: CGFloat = 108
  let hosted: CGFloat = 214
  let boundary: CGFloat = 160

  func x(_ fraction: CGFloat) -> CGFloat { 24 + (width - 48) * fraction }

  var mic: CGFloat { x(0) }
  var gate: CGFloat { x(0.15) }
  var speech: CGFloat { x(0.31) }
  var paste: CGFloat { x(1) }

  func cleanup(_ id: ProfileID) -> CGPoint {
    switch id {
    case .offline: CGPoint(x: x(0.62), y: local)
    case .accurate: CGPoint(x: x(0.47), y: hosted)
    case .haiku: CGPoint(x: x(0.62), y: hosted)
    case .cerebras: CGPoint(x: x(0.77), y: hosted)
    case .custom: CGPoint(x: x(0.90), y: hosted)
    }
  }

  func speechPoint(_ id: ProfileID) -> CGPoint {
    CGPoint(x: speech, y: id == .accurate ? hosted : local)
  }

  /// Lines run parallel, 4 pt apart, through the stations they share.
  func offset(_ id: ProfileID, among ids: [ProfileID]) -> CGFloat {
    guard let index = ids.firstIndex(of: id) else { return 0 }
    return (CGFloat(index) - CGFloat(ids.count - 1) / 2) * 4
  }

  func points(_ id: ProfileID) -> [CGPoint] {
    let all = blockOrder
    let onParakeet: [ProfileID] = [.haiku, .cerebras, .custom, .offline]
    let shared = offset(id, among: all)
    let speechPoint = speechPoint(id)
    let speechOffset = id == .accurate ? 0 : offset(id, among: onParakeet)
    return [
      CGPoint(x: mic, y: local + shared),
      CGPoint(x: gate, y: local + shared),
      CGPoint(x: speechPoint.x, y: speechPoint.y + speechOffset),
      cleanup(id),
      CGPoint(x: paste, y: local + shared),
    ]
  }
}

func lineColor(_ id: ProfileID) -> Color {
  switch id {
  case .haiku: .blue
  case .offline: .green
  case .accurate: .purple
  case .cerebras: .orange
  case .custom: .gray
  }
}

struct TransitR6: View {
  @Bindable var mock: Mock

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        GeometryReader { geometry in
          let map = TransitLayoutR6(width: geometry.size.width)
          ZStack(alignment: .topLeading) {
            Canvas { context, size in draw(context, size: size, map: map) }
            Text("This Mac")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text("leaves this Mac")
              .font(.caption)
              .foregroundStyle(.secondary)
              .offset(y: map.boundary + 4)
            stations(map)
          }
        }
        .frame(height: 300)
        legend
      }
      .padding(20)
    }
  }

  private func draw(_ context: GraphicsContext, size: CGSize, map: TransitLayoutR6) {
    var boundary = Path()
    boundary.move(to: CGPoint(x: 0, y: map.boundary))
    boundary.addLine(to: CGPoint(x: size.width, y: map.boundary))
    context.stroke(boundary, with: .style(.separator), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
    let ordered = blockOrder.filter { $0 != mock.active } + [mock.active]
    for id in ordered {
      let points = map.points(id)
      var path = Path()
      path.move(to: points[0])
      for index in 1 ..< points.count {
        let from = points[index - 1], to = points[index]
        let dx = (to.x - from.x) / 2
        path.addCurve(
          to: to, control1: CGPoint(x: from.x + dx, y: from.y), control2: CGPoint(x: to.x - dx, y: to.y),
        )
      }
      let isActive = id == mock.active
      context.stroke(
        path, with: .color(lineColor(id).opacity(isActive ? 1 : 0.35)),
        style: StrokeStyle(lineWidth: isActive ? 6 : 2, lineCap: .round, lineJoin: .round),
      )
    }
  }

  @ViewBuilder private func stations(_ map: TransitLayoutR6) -> some View {
    localStation(filled: true)
      .position(x: map.mic, y: map.local)
    topLabel { Text("Mic") }
      .position(x: map.mic, y: map.local - 30)
    Capsule()
      .fill(.background)
      .overlay { Capsule().strokeBorder(.primary, lineWidth: 2) }
      .frame(width: 14, height: 30)
      .position(x: map.gate, y: map.local)
    topLabel {
      Text("Speech gate")
      Text("every profile · 1.1 MB").foregroundStyle(.secondary).monospacedDigit()
    }
    .position(x: map.gate, y: map.local - 38)
    assetStation(.parakeet, at: CGPoint(x: map.speech, y: map.local))
    assetStation(.s1, at: map.cleanup(.offline))
    localStation(filled: true)
      .position(x: map.paste, y: map.local)
    topLabel {
      Text("Paste")
      Text("Your cursor").foregroundStyle(.secondary)
    }
    .position(x: map.paste - 16, y: map.local - 38)
    hostedStation(compScribe, at: map.speechPoint(.accurate))
    ForEach([ProfileID.accurate, .haiku, .cerebras, .custom]) { id in
      hostedStation(cleanupR6(id), at: map.cleanup(id))
    }
  }

  private func localStation(filled: Bool) -> some View {
    Circle()
      .fill(filled ? AnyShapeStyle(.primary) : AnyShapeStyle(.background))
      .overlay { Circle().strokeBorder(.primary, lineWidth: 2) }
      .frame(width: 14, height: 14)
  }

  @ViewBuilder private func assetStation(_ id: AssetID, at point: CGPoint) -> some View {
    localStation(filled: mock.installed.contains(id))
      .position(point)
    topLabel {
      Label(asset(id).name, systemImage: "internaldrive")
      LocalStatusR6(mock: mock, id: id, showsDelete: false)
    }
    .position(x: point.x, y: point.y - 40)
  }

  @ViewBuilder private func hostedStation(_ component: ComponentR6, at point: CGPoint) -> some View {
    RoundedRectangle(cornerRadius: 4)
      .fill(.background)
      .overlay {
        RoundedRectangle(cornerRadius: 4).strokeBorder(.primary, lineWidth: 1.5)
      }
      .overlay {
        Image(systemName: "cloud")
          .font(.system(size: 8, weight: .semibold))
      }
      .frame(width: 16, height: 16)
      .position(point)
    VStack(spacing: 1) {
      Text(component.name)
      Label(component.provider, systemImage: component.receives?.symbol ?? "cloud")
        .foregroundStyle(.secondary)
    }
    .font(.caption)
    .fixedSize()
    .position(x: point.x, y: point.y + 32)
  }

  private func topLabel(@ViewBuilder _ content: () -> some View) -> some View {
    VStack(spacing: 2) { content() }
      .font(.caption)
      .fixedSize()
  }

  private var legend: some View {
    HStack(spacing: 8) {
      ForEach(blockOrder) { id in
        HStack(spacing: 6) {
          Circle()
            .fill(lineColor(id))
            .frame(width: 8, height: 8)
          Text(profile(id).name)
            .font(.callout)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(.quinary))
        .overlay {
          if id == mock.active {
            Capsule().strokeBorder(.tint, lineWidth: 2)
          }
        }
        .contentShape(.capsule)
        .onTapGesture { mock.active = id }
      }
    }
  }
}

// MARK: Concept 3: Dictation Facts

struct FactsR6: View {
  @Bindable var mock: Mock

  var body: some View {
    ScrollView {
      HStack(alignment: .top, spacing: 24) {
        label
        pantry
      }
      .padding(20)
      .frame(maxWidth: .infinity)
    }
  }

  private var label: some View {
    let active = mock.activeProfile
    let local = active.assets.map(asset)
    let disk = local.filter { mock.installed.contains($0.id) }.map(\.megabytes).reduce(0, +)
    let cleanup = cleanupR6(active.id)
    let transcript = cleanup.isHosted ? "→ \(cleanup.id == "endpoint" ? "your endpoint" : cleanup.provider)" : "None"
    let audio = active.engineIsHosted ? "→ ElevenLabs" : "None"
    let leaves = active.engineIsHosted || cleanup.isHosted
    let ingredients = ["Silero speech gate", speechR6(active.id).name]
      + [cleanup.isHosted && cleanup.id != "endpoint" ? "\(cleanup.name) (\(cleanup.provider))" : cleanup.name]
    return VStack(alignment: .leading, spacing: 0) {
      Text("Dictation Facts")
        .font(.title2.weight(.heavy))
      Text(active.name)
        .padding(.bottom, 2)
      rule(8)
      factRow("Serving size", "one dictation", bold: true)
      rule(4)
      factRow("On disk", formatSize(disk), bold: true)
      ForEach(local, id: \.id) { item in
        rule(1)
        factRow(item.name, item.size, indent: true)
      }
      rule(4)
      factRow("Leaves this Mac", "", bold: true)
      rule(1)
      factRow("Audio", audio, indent: true)
      rule(1)
      factRow("Transcript", transcript, indent: true)
      rule(8)
      Text("INGREDIENTS: \(ingredients.joined(separator: ", ")).")
        .font(.caption)
        .padding(.top, 4)
      Text(leaves ? "CONTAINS: INTERNET." : "CONTAINS: NO INTERNET.")
        .font(.caption.weight(.heavy))
        .padding(.top, 4)
    }
    .padding(8)
    .frame(width: 300)
    .overlay { Rectangle().strokeBorder(.primary, lineWidth: 2) }
  }

  private func rule(_ height: CGFloat) -> some View {
    Rectangle()
      .fill(.primary)
      .frame(height: height)
  }

  private func factRow(_ title: String, _ value: String, bold: Bool = false, indent: Bool = false) -> some View {
    HStack {
      Text(title)
        .fontWeight(bold ? .heavy : .regular)
      Spacer()
      Text(value)
        .fontWeight(bold ? .heavy : .regular)
        .monospacedDigit()
    }
    .padding(.leading, indent ? 16 : 0)
    .padding(.vertical, 3)
  }

  private var pantry: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Pantry")
        .font(.headline)
      pantryCell(.gate, usage: "Every profile", deletable: false)
      pantryCell(.parakeet, usage: "4 profiles", deletable: true)
      pantryCell(.s1, usage: "Offline only", deletable: true)
      Text("\(formatSize(mock.installedTotal)) · \(formatSize(mock.unusedTotal)) unused")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(width: 300)
  }

  private func pantryCell(_ id: AssetID, usage: String, deletable: Bool) -> some View {
    HStack(spacing: 8) {
      Image(systemName: "internaldrive")
        .foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 1) {
        Text(asset(id).name)
        Text(usage)
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 4)
      LocalStatusR6(mock: mock, id: id, showsDelete: deletable)
    }
    .padding(10)
    .cellR6(used: mock.activeProfile.assets.contains(id))
  }
}

// MARK: Concept 4: Patch bay

struct PortKeyR6: PreferenceKey {
  static let defaultValue: [String: Anchor<CGPoint>] = [:]

  static func reduce(value: inout [String: Anchor<CGPoint>], nextValue: () -> [String: Anchor<CGPoint>]) {
    value.merge(nextValue()) { $1 }
  }
}

struct PatchBayR6: View {
  @Bindable var mock: Mock

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Label("Speech gate · 1.1 MB · first stop in every profile", systemImage: "internaldrive")
          .padding(10)
          .frame(maxWidth: .infinity, alignment: .leading)
          .cellR6(used: true)
        HStack(alignment: .top, spacing: 0) {
          VStack(spacing: 8) {
            ForEach(blockOrder) { id in card(id) }
          }
          .frame(width: 230)
          Spacer(minLength: 72)
          VStack(alignment: .leading, spacing: 6) {
            groupLabel("On this Mac")
            ForEach([compParakeet, compS1]) { component(of: $0) }
            groupLabel("Off this Mac")
              .padding(.top, 8)
            ForEach([compScribe, compHaiku, compGemini, compGptOss, compEndpoint]) { component(of: $0) }
          }
          .frame(width: 280)
        }
        .overlayPreferenceValue(PortKeyR6.self) { anchors in
          GeometryReader { proxy in
            let links = linkPoints(anchors, proxy)
            Canvas { context, _ in
              for link in links {
                var path = Path()
                path.move(to: link.from)
                let dx = (link.to.x - link.from.x) / 2
                path.addCurve(
                  to: link.to, control1: CGPoint(x: link.from.x + dx, y: link.from.y),
                  control2: CGPoint(x: link.to.x - dx, y: link.to.y),
                )
                context.stroke(
                  path, with: link.isActive ? .style(.tint) : .style(.tertiary), lineWidth: link.isActive ? 2 : 1,
                )
              }
            }
          }
          .allowsHitTesting(false)
        }
      }
      .padding(20)
    }
  }

  private struct Link {
    let from: CGPoint
    let to: CGPoint
    let isActive: Bool
  }

  private func linkPoints(_ anchors: [String: Anchor<CGPoint>], _ proxy: GeometryProxy) -> [Link] {
    var links: [Link] = []
    for id in blockOrder {
      for (stage, component) in [("speech", speechR6(id)), ("cleanup", cleanupR6(id))] {
        guard let from = anchors["p.\(id.rawValue).\(stage)"], let to = anchors["c.\(component.id)"] else { continue }
        links.append(Link(from: proxy[from], to: proxy[to], isActive: id == mock.active))
      }
    }
    return links.filter { !$0.isActive } + links.filter(\.isActive)
  }

  private func groupLabel(_ text: String) -> some View {
    Text(text)
      .font(.caption)
      .foregroundStyle(.secondary)
  }

  private func card(_ id: ProfileID) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(profile(id).name)
      port("Speech", speechR6(id).name, key: "p.\(id.rawValue).speech", isActive: id == mock.active)
      port("Cleanup", cleanupR6(id).name, key: "p.\(id.rawValue).cleanup", isActive: id == mock.active)
    }
    .padding(10)
    .frame(height: 72)
    .frame(maxWidth: .infinity, alignment: .leading)
    .cellR6(used: false, active: id == mock.active)
    .contentShape(.rect)
    .onTapGesture { mock.active = id }
  }

  private func port(_ stage: String, _ model: String, key: String, isActive: Bool) -> some View {
    HStack(spacing: 6) {
      Text(stage)
        .foregroundStyle(.secondary)
        .frame(width: 52, alignment: .leading)
      Text(model)
        .lineLimit(1)
      Spacer(minLength: 4)
      Circle()
        .fill(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
        .frame(width: 7, height: 7)
        .anchorPreference(key: PortKeyR6.self, value: .center) { [key: $0] }
    }
    .font(.callout)
  }

  private func component(of component: ComponentR6) -> some View {
    let isUsed = mock.usesR6(component)
    return HStack(spacing: 8) {
      Circle()
        .fill(isUsed ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
        .frame(width: 7, height: 7)
        .anchorPreference(key: PortKeyR6.self, value: .center) { ["c.\(component.id)": $0] }
      Image(systemName: component.isHosted ? "cloud" : "internaldrive")
        .foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 1) {
        Text(component.isHosted && component.id != "endpoint" ? component.provider : component.name)
          .lineLimit(1)
        if let id = component.asset, mock.installed.contains(id) {
          Text(asset(id).size)
            .font(.callout)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        } else if component.isHosted {
          Text(component.id == "endpoint" ? "Optional" : component.name)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 4)
      if let receives = component.receives {
        Image(systemName: receives.symbol)
          .foregroundStyle(.secondary)
      } else if let id = component.asset {
        LocalStatusR6(mock: mock, id: id, showsSize: false)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .cellR6(used: isUsed, hosted: component.isHosted)
  }
}

// MARK: - Settings window shell

struct SettingsShell: View {
  @Bindable var mock: Mock

  var body: some View {
    NavigationSplitView {
      List(selection: Binding(get: { mock.destination }, set: { mock.destination = $0 ?? .profiles })) {
        Label("Settings", systemImage: "gearshape").tag(Destination.settings)
        Section {
          Label("History", systemImage: "clock.arrow.circlepath").tag(Destination.history)
          Label("Dictionary", systemImage: "character.book.closed").tag(Destination.dictionary)
          Label("Profiles", systemImage: "person.crop.rectangle.stack").tag(Destination.profiles)
          if mock.modelsStyle != nil {
            // The other designer's name for the page: "Downloads" reads as a list of transfers.
            Label("Models", systemImage: "internaldrive").tag(Destination.models)
          } else if mock.round2 {
            Label("Downloads", systemImage: "arrow.down.circle").tag(Destination.downloads)
          } else if mock.variant == .d {
            Label("Models", systemImage: "internaldrive").tag(Destination.models)
          }
        }
      }
      .navigationSplitViewColumnWidth(min: 160, ideal: 176, max: 220)
      .toolbar(removing: .sidebarToggle)
    } detail: {
      ZStack {
        detail
          .navigationTitle(mock.destination.rawValue)
      }
    }
    .toolbar {
      ToolbarItem(placement: .navigation) {
        Color.clear.frame(width: 0, height: 0)
      }
    }
    .confirmationDialog(
      "Delete \(mock.pendingDeletion.map { asset($0).name } ?? "")?",
      isPresented: Binding(get: { mock.pendingDeletion != nil }, set: { if !$0 { mock.pendingDeletion = nil } }),
    ) {
      Button("Delete", role: .destructive) {
        if let id = mock.pendingDeletion {
          mock.installed.remove(id)
        }
      }
    } message: {
      // Which profiles a deletion breaks is said here, at the moment it matters, rather than on
      // every row of the Downloads page.
      if mock.round2, let id = mock.pendingDeletion {
        Text(deletionMessage(id))
      }
    }
    .confirmationDialog(
      "Delete models \(mock.activeProfile.name) doesn’t use?", isPresented: $mock.confirmsUnused,
    ) {
      Button("Delete \(formatSize(mock.unused.map(\.megabytes).reduce(0, +)))", role: .destructive) {
        for item in mock.unused {
          mock.installed.remove(item.id)
        }
      }
    }
  }

  private func deletionMessage(_ id: AssetID) -> String {
    let users = profiles.filter { $0.assets.contains(id) }.map(\.name)
    let list = users.count > 1
      ? users.dropLast().joined(separator: ", ") + ", and " + users.last! : users.joined()
    return "\(list) will download it again when chosen."
  }

  @ViewBuilder private var detail: some View {
    switch (mock.destination, mock.variant) {
    case (.models, _) where mock.modelsStyle == "blocks": BlocksR6(mock: mock)
    case (.models, _) where mock.modelsStyle == "transit": TransitR6(mock: mock)
    case (.models, _) where mock.modelsStyle == "facts": FactsR6(mock: mock)
    case (.models, _) where mock.modelsStyle == "patchbay": PatchBayR6(mock: mock)
    case (.models, _) where mock.modelsStyle == "a": ModelsR3A(mock: mock)
    case (.models, _) where mock.modelsStyle == "b": ModelsR3B(mock: mock)
    case (.models, _) where mock.modelsStyle == "c": ModelsR3C(mock: mock)
    case (.profiles, _) where mock.round3: PaneR3(mock: mock)
    case (.downloads, _): DownloadsR2(mock: mock)
    case (.settings, _) where mock.round2: SettingsR2(mock: mock)
    case (.profiles, _) where mock.round2: PaneR2(mock: mock)
    case (.models, _): ModelsPaneD(mock: mock)
    case (.profiles, .a): PaneA(mock: mock)
    case (.profiles, .b): PaneB(mock: mock)
    case (.profiles, .c): PaneC(mock: mock)
    case (.profiles, .d): PaneD(mock: mock)
    default:
      Text("Not part of this mock-up")
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}

// MARK: - Host

/// The tall captures are taller than the screen; a titled window is normally squeezed onto it.
final class UnconstrainedWindow: NSWindow {
  override func constrainFrameRect(_ frameRect: NSRect, to _: NSScreen?) -> NSRect { frameRect }
}

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
    let height = arguments.first { $0.hasPrefix("h=") }.flatMap { Double($0.dropFirst(2)) }
      ?? (arguments.contains("tall") ? 1400 : 680)
    let isTall = height > 680
    window = UnconstrainedWindow(
      contentRect: NSRect(x: 0, y: 0, width: 860, height: height),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false,
    )
    window.title = "MiniWhisper"
    window.toolbarStyle = .unified
    window.contentView = NSHostingView(rootView: SettingsShell(mock: mock))
    window.setContentSize(NSSize(width: 860, height: height))
    if isTall {
      window.setFrameTopLeftPoint(NSPoint(x: 60, y: (NSScreen.main?.frame.maxY ?? 982) - 30))
    } else {
      window.center()
    }
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    // `screencapture -l` wants the CGWindowID, which is exactly this.
    print(window.windowNumber)
    fflush(stdout)
    if mock.opensMenu {
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { self.clickProfilePopUp() }
    }
    // Nothing is focused when the real pane opens; a mock that rings its first control misleads.
    // Re-assert key status once the previous capture's process has gone, or the shot can catch an
    // inactive window with grey traffic lights.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
      NSApp.activate(ignoringOtherApps: true)
      self.window.makeKeyAndOrderFront(nil)
      self.window.makeFirstResponder(nil)
    }
  }

  /// SwiftUI draws its pop-ups rather than hosting an NSPopUpButton, so the menu is opened the
  /// way a person would: a press on the control, at the frame the pop-up reported.
  func clickProfilePopUp() {
    let frame = mock.popUpFrame
    let target = NSPoint(x: frame.midX, y: window.contentView!.bounds.height - frame.midY)
    // The pointer goes to the pop-up first, so the highlighted item is the selected one.
    let onScreen = window.convertPoint(toScreen: target)
    CGWarpMouseCursorPosition(CGPoint(x: onScreen.x, y: NSScreen.screens[0].frame.maxY - onScreen.y))
    // A held press: the menu opens on mouse-down and stays open while the button is "down".
    for type in [NSEvent.EventType.leftMouseDown] {
      let event = NSEvent.mouseEvent(
        with: type, location: target, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1,
      )!
      NSApp.postEvent(event, atStart: false)
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
