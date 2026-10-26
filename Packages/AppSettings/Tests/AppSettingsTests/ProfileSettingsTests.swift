import AppSettings
import Foundation
import Testing
import TranscriptCleanup

struct ProfileSettingsTests {
  @Test func `the default profile cleans through Anthropic on Haiku 5.5`() throws {
    let target = try #require(MiniWhisperSettings.defaults.cleanupTarget)

    #expect(target.configuration.endpoint == URL(string: "https://api.anthropic.com/v1"))
    #expect(target.configuration.model == "claude-haiku-5-5")
    #expect(target.configuration.timeout == CleanupConfiguration.defaultTimeout)
    #expect(target.credential?.account == "profile.haiku.anthropic")
    #expect(!MiniWhisperSettings.defaults.activeProfile.boostsVocabulary)
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
    #expect(target.configuration.model == "gemini-3.8-flash")
    #expect(
      target.configuration.endpoint.appending(path: "chat/completions").absoluteString
        == "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
    )
  }

  @Test func `offline needs no key, boosts recognition, and cleans on this Mac`() throws {
    var settings = MiniWhisperSettings.defaults
    settings.profiles.active = .offline
    settings.additionalInstructions = "Keep British spellings."
    let profile = settings.activeProfile
    let target = try #require(settings.cleanupTarget)

    #expect(profile.credentials.isEmpty)
    #expect(profile.boostsVocabulary)
    #expect(profile.assets == [.gate, .parakeet, .s1Mini])
    #expect(target.credential == nil)
    #expect(target.configuration.model == "s1-mini")
    // S1-mini takes no instructions, so the global ones never reach it.
    #expect(target.configuration.additionalInstructions.isEmpty)
  }

  @Test func `the global rows reach whichever profile is active`() throws {
    var settings = MiniWhisperSettings.defaults
    settings.profiles.active = .cerebras
    settings.setCleanupTimeout(30)
    settings.additionalInstructions = "Keep British spellings."

    let configuration = try #require(settings.cleanupTarget).configuration

    #expect(configuration.model == "gpt-oss-120b")
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
    #expect(!profiles.profile(.haiku).isModelOverridden)
  }

  @Test func `saving the factory values back is the same as never overriding`() throws {
    var profiles = ProfileSettings.defaults
    let factory = try #require(profiles.profile(.haiku).factory)
    let proxy = try #require(URL(string: "https://aig.thurstons.house/v1"))
    profiles.setEndpoint(proxy, for: .haiku)
    profiles.setModel("claude-sonnet-5-5", for: .haiku)

    profiles.setEndpoint(factory.endpoint, for: .haiku)
    profiles.setModel(factory.model, for: .haiku)

    #expect(profiles == .defaults)
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
