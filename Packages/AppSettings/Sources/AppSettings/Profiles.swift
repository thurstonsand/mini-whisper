import Foundation
import ModelLibrary
import TranscriptCleanup

// MARK: - ProfileID

/// The lineup, in the order it is shown. Factory profiles are compiled in; Custom is the one the
/// user fills.
public enum ProfileID: String, CaseIterable, Codable, CodingKeyRepresentable, Hashable, Sendable {
  case haiku
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

// MARK: - CredentialProvider

/// Who issued a key. It names the key in the pane and in onboarding; the slot it lives in belongs
/// to the profile.
public enum CredentialProvider: String, Equatable, Sendable {
  case anthropic
  case elevenlabs
  case google
  case cerebras
  case endpoint

  // MARK: Public

  public var displayName: String {
    switch self {
    case .anthropic:
      "Anthropic"
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
    case .anthropic:
      "an Anthropic key"
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
    case .anthropic:
      "sk-ant-…"
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
    case .anthropic:
      URL(string: "https://console.anthropic.com/settings/keys")
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

  public static let defaults = ProfileSettings(active: .haiku, overrides: [:], custom: .defaults)

  public var active: ProfileID
  public private(set) var overrides: [ProfileID: EndpointOverride]
  public var custom: CustomProfileSettings

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
    case .haiku:
      Definition(
        name: "Parakeet + Claude Haiku",
        tagline: "Speech stays on this Mac; transcripts go to Anthropic for cleanup.",
        symbol: "sparkles",
        factory: FactoryEndpoint(
          endpoint: URL(string: "https://api.anthropic.com/v1")!, model: "claude-haiku-5-5",
          provider: .anthropic,
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
          model: "gemini-3.8-flash", provider: .google,
        ),
      )
    case .cerebras:
      Definition(
        name: "Parakeet + Cerebras",
        tagline: "The quickest cleanup measured, at some cost to accuracy.",
        symbol: "bolt",
        factory: FactoryEndpoint(
          endpoint: URL(string: "https://api.cerebras.ai/v1")!, model: "gpt-oss-120b",
          provider: .cerebras,
        ),
      )
    case .custom:
      Definition(
        name: "Custom", tagline: "Any OpenAI-compatible endpoint, or no cleanup at all.",
        symbol: "slider.horizontal.3",
      )
    }
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
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    active = try container.decodeIfPresent(ProfileID.self, forKey: .active) ?? .haiku
    overrides = try container.decodeIfPresent(
      [ProfileID: EndpointOverride].self, forKey: .overrides,
    ) ?? [:]
    custom = try container.decodeIfPresent(CustomProfileSettings.self, forKey: .custom)
      ?? .defaults
  }
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
        model: "s1-mini", timeout: timeout, additionalInstructions: "",
      ),
      credential: nil,
    )
  }
}
