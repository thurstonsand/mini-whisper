import Foundation
import ModelLibrary
import TranscriptCleanup

// MARK: - ProfileID

/// The lineup, in the order it is shown. Factory profiles are compiled in; Custom is the one the
/// user fills.
public enum ProfileID: String, CaseIterable, Codable, CodingKeyRepresentable, Hashable, Sendable {
  case everyday
  case offline
  case accurate
  case cerebras
  case custom
}

// MARK: - SpeechEngine

public enum SpeechEngine: CaseIterable, Hashable, Sendable {
  case parakeet
  /// ElevenLabs Scribe v2, the one engine that hears audio somewhere other than this Mac.
  case scribe

  // MARK: Public

  public var name: String {
    switch self {
    case .parakeet:
      "Parakeet TDT v2"
    case .scribe:
      "ElevenLabs Scribe v2"
    }
  }

  /// What the engine reads from the library. Every engine runs the gate first.
  public var assets: [ModelAsset] {
    switch self {
    case .parakeet:
      [.gate, .parakeet]
    case .scribe:
      [.gate]
    }
  }
}

// MARK: - ScreenContextMode

/// What a profile's cleanup pass is shown of the screen around the target. Text is read from the
/// target itself — its tmux pane, else its window's Accessibility tree, else Vision's reading of
/// a screenshot — and Screenshot sends the window's image instead, which only a model that reads
/// images can use.
public enum ScreenContextMode: String, CaseIterable, Codable, Sendable {
  case off
  case text
  case screenshot

  // MARK: Public

  /// Every profile's, until the user picks another.
  public static let profileDefault = ScreenContextMode.text

  public var title: String {
    switch self {
    case .off:
      "Off"
    case .text:
      "Text"
    case .screenshot:
      "Screenshot"
    }
  }
}

// MARK: - CredentialProvider

/// Who issued a key. It names the key in the pane and in onboarding; the slot it lives in belongs
/// to the profile.
public enum CredentialProvider: String, Equatable, Sendable {
  case elevenlabs
  case google
  case cerebras
  case endpoint

  // MARK: Public

  public var displayName: String {
    switch self {
    case .elevenlabs:
      "ElevenLabs"
    case .google:
      "Google"
    case .cerebras:
      "Cerebras"
    case .endpoint:
      "your endpoint"
    }
  }

  /// The key as a sentence names it: "Needs an Anthropic key".
  public var keyPhrase: String {
    switch self {
    case .elevenlabs:
      "an ElevenLabs key"
    case .google:
      "a Google key"
    case .cerebras:
      "a Cerebras key"
    case .endpoint:
      "an API key"
    }
  }

  public var keyPrompt: String {
    switch self {
    case .elevenlabs:
      "sk_…"
    case .google:
      "AIza…"
    case .cerebras:
      "csk-…"
    case .endpoint:
      "Paste your key"
    }
  }

  /// Where a factory profile's key is issued. Custom's endpoint is the user's own, so there is
  /// nowhere to send them.
  public var keysURL: URL? {
    switch self {
    case .elevenlabs:
      URL(string: "https://elevenlabs.io/app/settings/api-keys")
    case .google:
      URL(string: "https://aistudio.google.com/apikey")
    case .cerebras:
      URL(string: "https://cloud.cerebras.ai")
    case .endpoint:
      nil
    }
  }
}

// MARK: - CredentialSlot

/// One Keychain item. A key belongs to the profile that uses it, so deleting, resetting, or
/// leaving one profile unconfigured never reaches another.
public struct CredentialSlot: Hashable, Sendable {
  // MARK: Lifecycle

  public init(profile: ProfileID, provider: CredentialProvider) {
    self.profile = profile
    self.provider = provider
  }

  // MARK: Public

  public let profile: ProfileID
  public let provider: CredentialProvider

  public var account: String {
    "profile.\(profile.rawValue).\(provider.rawValue)"
  }
}

// MARK: - EndpointLeg

/// A cleanup pass over an OpenAI-compatible endpoint. Endpoint and model are optional because an
/// unfinished Custom profile is a real state; a factory profile always has both.
public struct EndpointLeg: Equatable, Sendable {
  public let endpoint: URL?
  public let model: String?
  public let reasoningEffort: ReasoningEffort
  public let credential: CredentialSlot
}

// MARK: - CleanupLeg

public enum CleanupLeg: Equatable, Sendable {
  case none
  case endpoint(EndpointLeg)
  /// S1-mini on this Mac. It takes no instructions, so nothing about it is configurable.
  case local
}

// MARK: - FactoryEndpoint

/// What a factory profile's endpoint leg is before the user touches it.
public struct FactoryEndpoint: Equatable, Sendable {
  public let endpoint: URL
  public let model: String
  public let reasoningEffort: ReasoningEffort
  public let provider: CredentialProvider
}

// MARK: - Profile

/// A whole dictation stack, resolved: the factory definition with the user's overrides applied,
/// or Custom as the user filled it.
public struct Profile: Equatable, Identifiable, Sendable {
  public let id: ProfileID
  public let name: String
  /// The tradeoff, in one line and without numbers: measurements rot faster than the copy.
  public let tagline: String
  public let symbol: String
  public let engine: SpeechEngine
  /// The key a hosted engine sends audio with. Nil for an engine that runs on this Mac.
  public let engineCredential: CredentialSlot?
  /// Whether recognition itself is biased toward the dictionary. Off wherever an LLM reads the
  /// DICTIONARY block, because there the sidecar only adds traps.
  public let boostsVocabulary: Bool
  public let cleanup: CleanupLeg
  /// The endpoint the pane edits. Custom keeps its own while its cleanup is off, so turning it
  /// back on is one toggle rather than a form to fill again. Nil where cleanup runs on this Mac.
  public let endpointLeg: EndpointLeg?
  /// The endpoint a factory profile ships with. Nil for Custom, which has no defaults to return
  /// to, and for Offline, which has no endpoint at all.
  public let factory: FactoryEndpoint?
  /// Which of a factory profile's fields the user changed. Each one resets on its own.
  public let isEndpointOverridden: Bool
  public let isModelOverridden: Bool

  public var isCustom: Bool {
    id == .custom
  }

  /// Every key the profile needs, engine first.
  public var credentials: [CredentialSlot] {
    guard case let .endpoint(leg) = cleanup else {
      return [engineCredential].compactMap(\.self)
    }
    return [engineCredential, leg.credential].compactMap(\.self)
  }

  /// Every model the profile needs on disk.
  public var assets: [ModelAsset] {
    cleanup == .local ? engine.assets + [.s1Mini] : engine.assets
  }

  /// Whether the profile's dictations read the dictionary anywhere at all. S1-mini has no prompt
  /// surface, so a local leg reads nothing.
  public var usesVocabulary: Bool {
    if boostsVocabulary {
      return true
    }
    if case .endpoint = cleanup {
      return true
    }
    return false
  }
}

// MARK: - EndpointOverride

/// A factory profile's edits, stored as a delta so a later factory change reaches every field the
/// user never touched.
public struct EndpointOverride: Codable, Equatable, Sendable {
  // MARK: Lifecycle

  public init(endpoint: URL?, model: String?) {
    self.endpoint = endpoint
    self.model = model
  }

  // MARK: Public

  public var endpoint: URL?
  public var model: String?
}

// MARK: - CustomProfileSettings

public struct CustomProfileSettings: Codable, Equatable, Sendable {
  // MARK: Lifecycle

  public init(cleanupEnabled: Bool, endpoint: URL?, model: String?, boostsVocabulary: Bool) {
    self.cleanupEnabled = cleanupEnabled
    self.endpoint = endpoint
    self.model = model
    self.boostsVocabulary = boostsVocabulary
  }

  // MARK: Public

  /// With cleanup off, nothing reads the DICTIONARY block, so the sidecar is the whole vocabulary
  /// story and starts on.
  public static let defaults = CustomProfileSettings(
    cleanupEnabled: false, endpoint: nil, model: nil, boostsVocabulary: true,
  )

  public var cleanupEnabled: Bool
  public var endpoint: URL?
  public var model: String?
  public var boostsVocabulary: Bool
}

// MARK: - ProfileSettings

/// Which profile is active and what the user changed. Factory definitions never reach the file.
public struct ProfileSettings: Codable, Equatable, Sendable {
  // MARK: Lifecycle

  public init(
    active: ProfileID, overrides: [ProfileID: EndpointOverride], custom: CustomProfileSettings,
  ) {
    self.active = active
    self.overrides = overrides
    self.custom = custom
  }

  // MARK: Public

  public static let defaults = ProfileSettings(active: .everyday, overrides: [:], custom: .defaults)

  public var active: ProfileID
  public private(set) var overrides: [ProfileID: EndpointOverride]
  public var custom: CustomProfileSettings
  public var scribeOverride: EndpointOverride?
  /// Each profile's reasoning effort, where the user chose one other than the profile's own:
  /// the factory's for a factory profile, letting the model decide for Custom.
  public private(set) var reasoning: [ProfileID: ReasoningEffort] = [:]
  /// Each profile's Expanded context, where the user chose one other than the default.
  public private(set) var screenContext: [ProfileID: ScreenContextMode] = [:]
  /// Set while a user upgraded from Everyday on Claude Haiku has not yet chosen what replaces it.
  public private(set) var haikuRetirement: HaikuRetirement?

  public var lineup: [Profile] {
    ProfileID.allCases.map(profile)
  }

  public var activeProfile: Profile {
    profile(active)
  }

  public func profile(_ id: ProfileID) -> Profile {
    let definition = Self.definition(id)
    if definition.cleansLocally {
      return Profile(
        id: id, name: definition.name, tagline: definition.tagline, symbol: definition.symbol,
        engine: definition.engine, engineCredential: nil, boostsVocabulary: true,
        cleanup: .local, endpointLeg: nil, factory: nil, isEndpointOverridden: false,
        isModelOverridden: false,
      )
    }
    guard let factory = definition.factory else {
      let leg = EndpointLeg(
        endpoint: custom.endpoint, model: custom.model,
        reasoningEffort: reasoning[id] ?? ownReasoningEffort(id),
        credential: CredentialSlot(profile: id, provider: .endpoint),
      )
      return Profile(
        id: id, name: definition.name, tagline: definition.tagline, symbol: definition.symbol,
        engine: .parakeet, engineCredential: nil, boostsVocabulary: custom.boostsVocabulary,
        cleanup: custom.cleanupEnabled ? .endpoint(leg) : .none, endpointLeg: leg,
        factory: nil, isEndpointOverridden: false, isModelOverridden: false,
      )
    }
    let override = overrides[id]
    let leg = EndpointLeg(
      endpoint: override?.endpoint ?? factory.endpoint, model: override?.model ?? factory.model,
      reasoningEffort: reasoning[id] ?? ownReasoningEffort(id),
      credential: CredentialSlot(profile: id, provider: factory.provider),
    )
    return Profile(
      id: id, name: definition.name, tagline: definition.tagline, symbol: definition.symbol,
      engine: definition.engine,
      engineCredential: definition.engineProvider.map { CredentialSlot(profile: id, provider: $0) },
      boostsVocabulary: false, cleanup: .endpoint(leg), endpointLeg: leg,
      factory: factory, isEndpointOverridden: override?.endpoint != nil,
      isModelOverridden: override?.model != nil,
    )
  }

  /// A factory profile keeps only the fields that differ from its definition, so writing the
  /// defaults back is the same as never having changed them.
  public mutating func setEndpoint(_ endpoint: URL, for id: ProfileID) {
    guard let factory = Self.definition(id).factory else {
      precondition(id == .custom, "\(id) has no endpoint to set")
      custom.endpoint = endpoint
      return
    }
    updateOverride(id) { $0.endpoint = endpoint == factory.endpoint ? nil : endpoint }
  }

  public mutating func setModel(_ model: String, for id: ProfileID) {
    guard let factory = Self.definition(id).factory else {
      precondition(id == .custom, "\(id) has no model to set")
      custom.model = model
      return
    }
    updateOverride(id) { $0.model = model == factory.model ? nil : model }
  }

  /// Like an override, kept only while it differs from what the profile would use without it.
  public mutating func setReasoningEffort(_ effort: ReasoningEffort, for id: ProfileID) {
    reasoning[id] = effort == ownReasoningEffort(id) ? nil : effort
  }

  public func screenContextMode(for id: ProfileID) -> ScreenContextMode {
    screenContext[id] ?? .profileDefault
  }

  public mutating func setScreenContextMode(_ mode: ScreenContextMode, for id: ProfileID) {
    screenContext[id] = mode == .profileDefault ? nil : mode
  }

  /// Haiku goes on as the user had it, in Custom, which it replaces. It reads the screen from a
  /// screenshot, where Haiku gains the most. Activating Custom is the
  /// caller's, so it switches the way any other choice of profile does.
  public mutating func keepHaikuInCustom() {
    guard let retired = haikuRetirement else {
      preconditionFailure("No Haiku setup is waiting to be kept")
    }
    custom = CustomProfileSettings(
      cleanupEnabled: true, endpoint: retired.endpoint, model: retired.model,
      boostsVocabulary: false,
    )
    setReasoningEffort(retired.reasoningEffort, for: .custom)
    setScreenContextMode(.screenshot, for: .custom)
    haikuRetirement = nil
  }

  /// Everyday stays on Hydrogen, and the Haiku setup is forgotten.
  public mutating func acceptHydrogen() {
    precondition(haikuRetirement != nil, "No Haiku setup is waiting to be replaced")
    haikuRetirement = nil
  }

  // MARK: Private

  private struct Definition {
    let name: String
    let tagline: String
    let symbol: String
    var engine = SpeechEngine.parakeet
    var engineProvider: CredentialProvider?
    var cleansLocally = false
    var factory: FactoryEndpoint?
  }

  private static func definition(_ id: ProfileID) -> Definition {
    switch id {
    case .everyday:
      Definition(
        name: "Everyday",
        tagline: "Speech stays on this Mac; transcripts go to Google for cleanup.",
        symbol: "sparkles",
        factory: FactoryEndpoint(
          endpoint: URL(string: "https://generativelanguage.googleapis.com/v1beta/openai")!,
          model: "gemini-4-hydrogen", reasoningEffort: .off, provider: .google,
        ),
      )
    case .offline:
      Definition(
        name: "Offline",
        tagline: "Nothing leaves this Mac. Lighter cleanup, recognition tuned to your words.",
        symbol: "lock.laptopcomputer", cleansLocally: true,
      )
    case .accurate:
      Definition(
        name: "Most accurate",
        tagline: "The fewest mistakes. Your audio goes to ElevenLabs, transcripts to Google.",
        symbol: "scope", engine: .scribe, engineProvider: .elevenlabs,
        factory: FactoryEndpoint(
          endpoint: URL(string: "https://generativelanguage.googleapis.com/v1beta/openai")!,
          model: "gemini-4-hydrogen", reasoningEffort: .off, provider: .google,
        ),
      )
    case .cerebras:
      Definition(
        name: "Fastest cleanup",
        tagline: "The quickest cleanup measured, at some cost to accuracy.",
        symbol: "bolt",
        factory: FactoryEndpoint(
          endpoint: URL(string: "https://api.cerebras.ai/v1")!, model: "qwen-3.8-27b",
          reasoningEffort: .low, provider: .cerebras,
        ),
      )
    case .custom:
      Definition(
        name: "Custom", tagline: "Any OpenAI-compatible endpoint, or no cleanup at all.",
        symbol: "slider.horizontal.3",
      )
    }
  }

  /// The factory's level was measured on the factory's model; a model the user picked may not
  /// reason at all, so it starts from letting the model decide.
  private func ownReasoningEffort(_ id: ProfileID) -> ReasoningEffort {
    guard let factory = Self.definition(id).factory, overrides[id]?.model == nil else {
      return .modelDecides
    }
    return factory.reasoningEffort
  }

  private mutating func updateOverride(_ id: ProfileID, _ edit: (inout EndpointOverride) -> Void) {
    var override = overrides[id] ?? EndpointOverride(endpoint: nil, model: nil)
    edit(&override)
    overrides[id] = override.endpoint == nil && override.model == nil ? nil : override
  }
}

// MARK: Codable

extension ProfileSettings {
  private enum CodingKeys: String, CodingKey {
    case active
    case overrides
    case custom
    case scribeOverride
    case reasoning
    case screenContext
    case haikuRetirement
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    var overrides = try container.decodeIfPresent(
      [String: EndpointOverride].self, forKey: .overrides,
    ) ?? [:]
    var reasoning = try container.decodeIfPresent(
      [String: ReasoningEffort].self, forKey: .reasoning,
    ) ?? [:]
    let haikuOverride = overrides.removeValue(forKey: HaikuRetirement.profileID)
    let haikuReasoning = reasoning.removeValue(forKey: HaikuRetirement.profileID)
    self.overrides = try Self.keyedByProfile(overrides, forKey: .overrides, in: container)
    self.reasoning = try Self.keyedByProfile(reasoning, forKey: .reasoning, in: container)
    screenContext = try container.decodeIfPresent(
      [ProfileID: ScreenContextMode].self, forKey: .screenContext,
    ) ?? [:]
    custom = try container.decodeIfPresent(CustomProfileSettings.self, forKey: .custom)
      ?? .defaults
    scribeOverride = try container.decodeIfPresent(EndpointOverride.self, forKey: .scribeOverride)
    haikuRetirement = try container.decodeIfPresent(
      HaikuRetirement.self, forKey: .haikuRetirement,
    )
    let active = try container.decodeIfPresent(String.self, forKey: .active)
    if active == HaikuRetirement.profileID {
      self.active = .everyday
      haikuRetirement = HaikuRetirement(
        endpoint: haikuOverride?.endpoint ?? HaikuRetirement.endpoint,
        model: haikuOverride?.model ?? HaikuRetirement.model,
        reasoningEffort: haikuReasoning ?? .modelDecides,
      )
    } else if let active {
      guard let id = ProfileID(rawValue: active) else {
        throw DecodingError.dataCorruptedError(
          forKey: .active, in: container, debugDescription: "No profile \(active)",
        )
      }
      self.active = id
    } else {
      self.active = .everyday
    }
  }

  private static func keyedByProfile<Value>(
    _ values: [String: Value], forKey key: CodingKeys,
    in container: KeyedDecodingContainer<CodingKeys>,
  ) throws -> [ProfileID: Value] {
    try Dictionary(uniqueKeysWithValues: values.map { raw, value in
      guard let id = ProfileID(rawValue: raw) else {
        throw DecodingError.dataCorruptedError(
          forKey: key, in: container, debugDescription: "No profile \(raw)",
        )
      }
      return (id, value)
    })
  }
}

// MARK: - HaikuRetirement

/// Everyday cleaned with Claude Haiku until Gemini 4 Hydrogen replaced it. A settings file from
/// before then that still names the Haiku profile active is read as Everyday plus this: what the
/// user had Haiku set to, held until they choose Hydrogen or keep Haiku in Custom.
public struct HaikuRetirement: Codable, Equatable, Sendable {
  public static let profileID = "haiku"
  public static let endpoint = URL(string: "https://api.anthropic.com/v1")!
  public static let model = "claude-haiku-5-5"
  /// The Keychain account the Haiku profile's key was stored under.
  public static let keyAccount = "profile.haiku.anthropic"

  public let endpoint: URL
  public let model: String
  public let reasoningEffort: ReasoningEffort
}

// MARK: - CleanupTarget

/// What one dictation's cleanup pass runs against: the configuration, and where its key lives.
public struct CleanupTarget: Equatable, Sendable {
  // MARK: Lifecycle

  public init(configuration: CleanupConfiguration, credential: CredentialSlot?) {
    self.configuration = configuration
    self.credential = credential
  }

  // MARK: Public

  public let configuration: CleanupConfiguration
  /// Nil when the pass runs on this Mac and needs no key.
  public let credential: CredentialSlot?

  /// S1-mini, as History records it: the endpoint names the pinned artifact that ran rather
  /// than anywhere a request was sent, because nothing was.
  public static func local(timeout: TimeInterval) -> CleanupTarget {
    let repository = PinnedRepository.s1Mini
    return CleanupTarget(
      configuration: CleanupConfiguration(
        endpoint: URL(
          string: "https://huggingface.co/\(repository.repository)/blob/\(repository.revision)/s1-mini-q4_k_m.gguf",
        )!,
        model: "s1-mini", reasoningEffort: .modelDecides, timeout: timeout,
        additionalInstructions: "",
      ),
      credential: nil,
    )
  }
}
