import Foundation
import Testing
import TranscriptCleanup

struct CleanupSettingsTests {
  @Test func `a configured and enabled cleanup carries every choice into the configuration`(
  ) throws {
    let settings = CleanupSettings(
      enabled: true, endpoint: URL(string: "https://gateway.internal/v1"), model: "gpt-4o-mini",
      timeout: 30, additionalInstructions: "Keep British spellings.",
    )

    let configuration = try #require(settings.configuration)

    #expect(configuration.endpoint == URL(string: "https://gateway.internal/v1"))
    #expect(configuration.model == "gpt-4o-mini")
    #expect(configuration.timeout == 30)
    #expect(configuration.additionalInstructions == "Keep British spellings.")
  }

  @Test func `the timeout changes through its validating boundary`() throws {
    var settings = CleanupSettings(
      enabled: true, endpoint: URL(string: "https://gateway.internal/v1"), model: "gpt-4o-mini",
      timeout: 10, additionalInstructions: "",
    )

    settings.setTimeout(20)

    #expect(try #require(settings.configuration).timeout == 20)
  }

  @Test func `the defaults have nothing to run`() {
    #expect(CleanupSettings.defaults.configuration == nil)
  }

  @Test func `a fully configured cleanup that is switched off has nothing to run`() {
    var settings = CleanupSettings.defaults
    settings.endpoint = URL(string: "https://gateway.internal/v1")
    settings.model = "gpt-4o-mini"

    #expect(settings.configuration == nil)
  }

  @Test func `an enabled cleanup without an endpoint has nothing to run`() {
    var settings = CleanupSettings.defaults
    settings.enabled = true
    settings.model = "gpt-4o-mini"

    #expect(settings.configuration == nil)
  }

  @Test(arguments: [nil, ""])
  func `an enabled cleanup without a model has nothing to run`(model: String?) {
    var settings = CleanupSettings.defaults
    settings.enabled = true
    settings.endpoint = URL(string: "https://gateway.internal/v1")
    settings.model = model

    #expect(settings.configuration == nil)
  }
}
