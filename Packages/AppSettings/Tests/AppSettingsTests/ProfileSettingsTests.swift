import AppSettings
import Foundation
import Testing
import TranscriptCleanup

struct ProfileSettingsTests {
  @Test func `the default profile cleans through Google on Hydrogen without reasoning`() throws {
    let target = try #require(MiniWhisperSettings.defaults.cleanupTarget)

    #expect(
      target.configuration.endpoint
        == URL(string: "https://generativelanguage.googleapis.com/v1beta/openai"),
    )
    #expect(target.configuration.model == "gemini-4-hydrogen")
    #expect(target.configuration.reasoningEffort == .off)
    #expect(target.configuration.timeout == CleanupConfiguration.defaultTimeout)
    #expect(target.credential?.account == "profile.everyday.google")
    #expect(MiniWhisperSettings.defaults.activeProfile.engine == .parakeet)
    #expect(!MiniWhisperSettings.defaults.activeProfile.boostsVocabulary)
  }

  /// A file from before Hydrogen replaced Haiku, where the user had pointed Haiku at a proxy and
  /// moved it to Sonnet, and turned its thinking off. The choice it waits on outlives a relaunch.
  @Test func `everyday on haiku waits for a choice, and keeping haiku moves it to custom`() throws {
    let file = Data(#"""
    {"active": "haiku", "overrides": {"haiku": {"endpoint": "https://aig.thurstons.house/v1",
     "model": "claude-sonnet-5-5"},
     "cerebras": {"model": "llama-4-scout"}}, "reasoning": {"haiku": "none"}}
    """#.utf8)

    var profiles = try JSONDecoder().decode(ProfileSettings.self, from: file)
    profiles = try JSONDecoder().decode(ProfileSettings.self, from: JSONEncoder().encode(profiles))

    #expect(profiles.active == .everyday)
    let retired = try #require(profiles.haikuRetirement)
    #expect(retired.endpoint == URL(string: "https://aig.thurstons.house/v1"))
    #expect(retired.model == "claude-sonnet-5-5")
    #expect(retired.reasoningEffort == .off)
    #expect(profiles.profile(.cerebras).endpointLeg?.model == "llama-4-scout")

    var hydrogen = profiles
    hydrogen.acceptHydrogen()
    #expect(hydrogen.haikuRetirement == nil)
    #expect(hydrogen.custom == .defaults)
    #expect(hydrogen.screenContext.isEmpty)

    profiles.keepHaikuInCustom()
    profiles.active = .custom
    let leg = try #require(profiles.activeProfile.endpointLeg)
    #expect(profiles.haikuRetirement == nil)
    #expect(profiles.activeProfile.cleanup == .endpoint(leg))
    #expect(leg.endpoint == URL(string: "https://aig.thurstons.house/v1"))
    #expect(leg.model == "claude-sonnet-5-5")
    #expect(leg.reasoningEffort == .off)
    #expect(!profiles.activeProfile.boostsVocabulary)
    #expect(profiles.screenContextMode(for: .custom) == .screenshot)
    #expect(profiles.screenContextMode(for: .everyday) == .text)
  }

  /// Haiku's settings only matter to someone still on it.
  @Test func `a haiku override on an inactive profile is dropped without asking`() throws {
    let file = Data(#"""
    {"active": "cerebras", "overrides": {"haiku": {"model": "claude-sonnet-5-5"}},
     "reasoning": {"haiku": "none"}}
    """#.utf8)

    let profiles = try JSONDecoder().decode(ProfileSettings.self, from: file)

    #expect(profiles.active == .cerebras)
    #expect(profiles.haikuRetirement == nil)
    #expect(profiles.overrides.isEmpty)
    #expect(profiles.reasoning.isEmpty)
  }

  /// Two keys in two slots of its own, and only the gate on disk: the profile that hears
  /// somewhere else needs nothing of Parakeet's.
  @Test func `most accurate hears through Scribe and cleans through Google`() throws {
    var settings = MiniWhisperSettings.defaults
    settings.profiles.active = .accurate
    let profile = settings.activeProfile
    let target = try #require(settings.cleanupTarget)

    #expect(profile.engine == .scribe)
    #expect(profile.assets == [.gate])
    #expect(profile.credentials.map(\.account) == [
      "profile.accurate.elevenlabs", "profile.accurate.google",
    ])
    #expect(target.configuration.model == "gemini-4-hydrogen")
    #expect(
      target.configuration.endpoint.appending(path: "chat/completions").absoluteString
        == "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
    )
  }

  @Test func `offline needs no key, boosts recognition, and cleans on this Mac`() throws {
    var settings = MiniWhisperSettings.defaults
    settings.profiles.active = .offline
    settings.additionalInstructions = "Keep British spellings."
    settings.profiles.setScreenContextMode(.screenshot, for: .offline)
    let profile = settings.activeProfile
    let target = try #require(settings.cleanupTarget)

    #expect(profile.credentials.isEmpty)
    #expect(profile.boostsVocabulary)
    #expect(profile.assets == [.gate, .parakeet, .s1Mini])
    #expect(target.credential == nil)
    #expect(target.configuration.model == "s1-mini")
    // S1-mini takes no instructions, so the global ones never reach it.
    #expect(target.configuration.additionalInstructions.isEmpty)
    // Nor the screen: whatever mode is stored for it, nothing reads it.
    #expect(settings.screenContextMode == .off)
    settings.profiles.active = .everyday
    #expect(settings.screenContextMode == .text)
  }

  @Test func `the global rows reach whichever profile is active`() throws {
    var settings = MiniWhisperSettings.defaults
    settings.profiles.active = .cerebras
    settings.setCleanupTimeout(30)
    settings.additionalInstructions = "Keep British spellings."

    let configuration = try #require(settings.cleanupTarget).configuration

    #expect(configuration.model == "qwen-3.8-27b")
    #expect(configuration.timeout == 30)
    #expect(configuration.additionalInstructions == "Keep British spellings.")
  }

  @Test func `an override stores only the field that differs from the factory`() throws {
    var profiles = ProfileSettings.defaults
    let factory = try #require(profiles.profile(.cerebras).factory)

    profiles.setEndpoint(factory.endpoint, for: .cerebras)
    profiles.setModel("llama-4-scout", for: .cerebras)

    let encoded = try JSONEncoder().encode(profiles)
    let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let overrides = try #require(object["overrides"] as? [String: [String: Any]])
    #expect(overrides.keys.sorted() == ["cerebras"])
    #expect(overrides["cerebras"]?.keys.sorted() == ["model"])
    #expect(profiles.profile(.cerebras).isModelOverridden)
    #expect(!profiles.profile(.cerebras).isEndpointOverridden)
    #expect(!profiles.profile(.everyday).isModelOverridden)
  }

  @Test func `saving the factory values back is the same as never overriding`() throws {
    var profiles = ProfileSettings.defaults
    let factory = try #require(profiles.profile(.everyday).factory)
    let proxy = try #require(URL(string: "https://aig.thurstons.house/v1"))
    profiles.setEndpoint(proxy, for: .everyday)
    profiles.setModel("claude-sonnet-5-5", for: .everyday)

    profiles.setEndpoint(factory.endpoint, for: .everyday)
    profiles.setModel(factory.model, for: .everyday)

    #expect(profiles == .defaults)
  }

  @Test func `a reasoning effort reaches cleanup and is stored only while it differs`() throws {
    var settings = MiniWhisperSettings.defaults
    settings.profiles.active = .cerebras
    let factory = try #require(settings.activeProfile.factory)

    settings.profiles.setReasoningEffort(.high, for: .cerebras)
    settings.profiles.setReasoningEffort(.off, for: .custom)

    #expect(try #require(settings.cleanupTarget).configuration.reasoningEffort == .high)
    #expect(settings.profiles.profile(.everyday).endpointLeg?.reasoningEffort == .off)
    let decoded = try JSONDecoder().decode(
      ProfileSettings.self, from: JSONEncoder().encode(settings.profiles),
    )
    #expect(decoded.profile(.cerebras).endpointLeg?.reasoningEffort == .high)
    #expect(decoded.profile(.custom).endpointLeg?.reasoningEffort == .off)

    settings.profiles.setReasoningEffort(factory.reasoningEffort, for: .cerebras)
    settings.profiles.setReasoningEffort(.modelDecides, for: .custom)
    #expect(settings.profiles.reasoning.isEmpty)
  }

  @Test func `a screen context mode belongs to its profile and is stored only while it differs`(
  ) throws {
    var settings = MiniWhisperSettings.defaults
    settings.profiles.active = .cerebras
    #expect(settings.screenContextMode == .text)

    settings.profiles.setScreenContextMode(.screenshot, for: .cerebras)
    settings.profiles.setScreenContextMode(.off, for: .accurate)

    #expect(settings.screenContextMode == .screenshot)
    #expect(settings.readsScreen)
    let decoded = try JSONDecoder().decode(
      ProfileSettings.self, from: JSONEncoder().encode(settings.profiles),
    )
    #expect(decoded.screenContextMode(for: .cerebras) == .screenshot)
    #expect(decoded.screenContextMode(for: .accurate) == .off)
    #expect(decoded.screenContextMode(for: .everyday) == .text)
    settings.profiles.active = .accurate
    #expect(!settings.readsScreen)

    settings.profiles.setScreenContextMode(.text, for: .cerebras)
    settings.profiles.setScreenContextMode(.text, for: .accurate)
    #expect(settings.profiles.screenContext.isEmpty)
  }

  @Test func `a model the user picked does not inherit the factory's reasoning level`() throws {
    var profiles = ProfileSettings.defaults
    let factory = try #require(profiles.profile(.cerebras).factory)
    #expect(factory.reasoningEffort != .modelDecides)

    profiles.setModel("llama-4-scout", for: .cerebras)

    #expect(profiles.profile(.cerebras).endpointLeg?.reasoningEffort == .modelDecides)
  }

  @Test func `custom writes the endpoint itself because it has no factory to differ from`() throws {
    var settings = MiniWhisperSettings.defaults
    settings.profiles.active = .custom
    settings.profiles.custom.cleanupEnabled = true
    let gateway = try #require(URL(string: "https://gateway.internal/v1"))

    settings.profiles.setEndpoint(gateway, for: .custom)
    settings.profiles.setModel("gpt-4o-mini", for: .custom)

    let target = try #require(settings.cleanupTarget)
    #expect(target.configuration.endpoint == gateway)
    #expect(target.credential?.account == "profile.custom.endpoint")
    #expect(settings.profiles.custom.boostsVocabulary)
  }

  @Test func `custom with cleanup off has nothing to run and still uses the dictionary`() {
    var settings = MiniWhisperSettings.defaults
    settings.profiles.active = .custom
    settings.profiles.custom.endpoint = URL(string: "https://gateway.internal/v1")
    settings.profiles.custom.model = "gpt-4o-mini"

    #expect(settings.cleanupTarget == nil)
    #expect(settings.activeProfile.usesVocabulary)
  }

  @Test(arguments: [nil, ""])
  func `custom without a model has nothing to run`(model: String?) {
    var settings = MiniWhisperSettings.defaults
    settings.profiles.active = .custom
    settings.profiles.custom = CustomProfileSettings(
      cleanupEnabled: true, endpoint: URL(string: "https://gateway.internal/v1"), model: model,
      boostsVocabulary: true,
    )

    #expect(settings.cleanupTarget == nil)
  }

  @Test func `custom with neither cleanup nor the sidecar ignores the dictionary`() {
    var profiles = ProfileSettings.defaults
    profiles.custom.boostsVocabulary = false

    #expect(!profiles.profile(.custom).usesVocabulary)
  }
}
