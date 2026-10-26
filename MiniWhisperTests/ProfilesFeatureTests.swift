import AppSettings
import ASREngine
import ComposableArchitecture
import Foundation
@testable import MiniWhisper
import ModelLibrary
import Sharing
import Testing
import TranscriptCleanup

// MARK: - EndpointAddressTests

struct EndpointAddressTests {
  @Test(arguments: [
    ("https://gateway.example/v1", "https://gateway.example/v1"),
    ("  https://gateway.example/v1  ", "https://gateway.example/v1"),
    ("https://gateway.example/v1/", "https://gateway.example/v1"),
    ("https://gateway.example/v1///", "https://gateway.example/v1"),
    ("gateway.example/v1", "https://gateway.example/v1"),
    ("http://localhost:11434/v1", "http://localhost:11434/v1"),
  ])
  func `a hand-typed address is conformed once, here`(_ typed: String, _ expected: String) {
    #expect(EndpointAddress.conform(typed)?.absoluteString == expected)
  }

  @Test(arguments: ["", "   ", "/v1", "ftp://gateway.example/v1"])
  func `an address that is not one is refused rather than guessed at`(_ typed: String) {
    #expect(EndpointAddress.conform(typed) == nil)
  }

  @Test func `a bare host is a question, and the conventional answer is tried first`() throws {
    let host = try #require(EndpointAddress.conform("aig.thurstons.house"))
    #expect(!EndpointAddress.hasExplicitPath(host))
    #expect(
      EndpointAddress.candidates(for: host).map(\.absoluteString)
        == ["https://aig.thurstons.house/v1", "https://aig.thurstons.house"],
    )
  }

  @Test(arguments: ["https://gateway.example/v1", "https://gateway.example/api/v9"])
  func `an address with a path is taken exactly as typed`(_ typed: String) throws {
    let url = try #require(EndpointAddress.conform(typed))
    #expect(EndpointAddress.hasExplicitPath(url))
    #expect(EndpointAddress.candidates(for: url) == [url])
  }
}

// MARK: - ProfilesFeatureTests

@MainActor struct ProfilesFeatureTests {
  @Test func `the pane reads which keys exist from the Keychain, never from settings`() async {
    let store = profilesStore(keys: [customSlot: storedKey, haikuSlot: "sk-ant-0123"])

    await openPane(store, keys: [customSlot: storedKey, haikuSlot: "sk-ant-0123"])
    #expect(store.state.storedKeys == [customSlot: "sk-liv", haikuSlot: "sk-ant"])
  }

  @Test func `Save proves the draft, then stores the key, then the address and model`() async {
    let calls = TestBox<[String]>([])
    let verified = TestBox<CleanupConfiguration?>(nil)
    let (answer, answers) = AsyncStream.makeStream(of: Void.self)
    let store = profilesStore {
      $0.keychain.store = { secret, slot in calls.value.append("store \(slot.account) \(secret)") }
      $0.cleanup.verify = { configuration, apiKey in
        calls.value.append("verify \(apiKey ?? "nil")")
        verified.value = configuration
        for await _ in answer {}
        return .verified
      }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    await openPane(store)

    await store.send(.editTapped(.endpoint))
    await store.send(.endpointEdited("gateway.example/v1/"))
    await store.send(.customModelEdited("gpt-oss-120b"))
    await store.send(.keyEdited("  sk-typed-0123 "))
    await store.send(.saveTapped)
    // Nothing is written while the endpoint has not answered.
    #expect(store.state.editor?.isChecking == true)
    #expect(store.state.settings.profiles.custom.endpoint == nil)
    answers.finish()
    await store.receive(.saveSucceeded(.init(
      endpoint: gateway, model: "gpt-oss-120b", storedKeys: [customSlot: "sk-typ"],
    )))
    await store.receive(.delegate(.keysStored([customSlot])))

    #expect(calls.value == ["verify sk-typed-0123", "store profile.custom.endpoint sk-typed-0123"])
    #expect(verified.value?.endpoint == gateway)
    #expect(verified.value?.model == "gpt-oss-120b")
    // The check answers a person waiting on a button, so it runs on its own short budget.
    #expect(verified.value?.timeout == CleanupConfiguration.verificationTimeout)
    #expect(store.state.settings.profiles.custom.endpoint == gateway)
    #expect(store.state.settings.profiles.custom.model == "gpt-oss-120b")
    #expect(store.state.storedKeys?[customSlot] == "sk-typ")
    #expect(store.state.editor == nil)
  }

  @Test func `a draft the endpoint refuses changes nothing anywhere`() async {
    let stored = TestBox<Int>(0)
    var settings = MiniWhisperSettings.defaults
    let store = profilesStore(settings: settings, keys: [haikuSlot: "sk-ant-old"]) {
      $0.keychain.store = { _, _ in stored.value += 1 }
      $0.cleanup.verify = { _, _ in .failed(.httpStatus(code: 401, message: "invalid x-api-key")) }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    await openPane(store, keys: [haikuSlot: "sk-ant-old"])
    settings = store.state.settings

    await store.send(.editTapped(.apiKey))
    await store.send(.keyEdited("sk-ant-new"))
    await store.send(.customModelEdited("claude-sonnet-5-5"))
    await store.send(.saveTapped)
    await store.receive(.saveFailed(.init(field: .apiKey, message: "Invalid key.")))

    #expect(stored.value == 0)
    #expect(store.state.settings == settings)
    #expect(store.state.storedKeys?[haikuSlot] == "sk-ant")
    // The draft stays to be fixed, and the blamed field is asked to take the keys.
    #expect(store.state.editor?.keyText == "sk-ant-new")
    #expect(store.state.editor?.isChecking == false)
    #expect(store.state.editor?.focus == .apiKey)
  }

  @Test(arguments: [
    (CleanupFailure.unreachable("refused"), true, ProfilesFeature.Field.endpoint,
     "Couldn’t reach gateway.example."),
    (.timedOut(10), true, .endpoint, "Couldn’t reach gateway.example."),
    (.httpStatus(code: 401, message: nil), true, .apiKey, "Invalid key."),
    (.httpStatus(code: 403, message: nil), false, .apiKey, "This endpoint needs an API key."),
    (.httpStatus(code: 400, message: "Please pass a valid API key"), true, .apiKey, "Invalid key."),
    (.httpStatus(code: 400, message: "temperature out of range"), true, .endpoint,
     "temperature out of range"),
    (.httpStatus(code: 404, message: "model 'qwen3:32b' not found"), true, .model,
     "gateway.example has no model ‘qwen3:32b’."),
    (.httpStatus(code: 404, message: "Not Found"), true, .endpoint,
     "gateway.example has no chat completions endpoint."),
    (.httpStatus(code: 500, message: "upstream exploded"), true, .endpoint, "upstream exploded"),
    (.malformedResponse("html"), true, .endpoint,
     "That endpoint didn’t answer like an OpenAI-compatible one."),
  ])
  func `a failed check is one sentence under the field it blames`(
    failure: CleanupFailure, hasKey: Bool, field: ProfilesFeature.Field, message: String,
  ) async {
    let keys = hasKey ? [customSlot: storedKey] : [:]
    let store = profilesStore(settings: configuredCustom, keys: keys) {
      $0.cleanup.verify = { _, _ in .failed(failure) }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    await openPane(store, keys: keys)

    await store.send(.editTapped(.model))
    await store.send(.customModelEdited("qwen3:32b"))
    await store.send(.saveTapped)
    await store.receive(.saveFailed(.init(field: field, message: message)))
  }

  @Test func `an address that is not one, or no model, never reaches the endpoint`() async {
    let store = profilesStore {
      $0.cleanup.verify = { _, _ in
        Issue.record("A draft that cannot be an endpoint is never sent")
        return .verified
      }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    await openPane(store)

    await store.send(.editTapped(.endpoint))
    await store.send(.endpointEdited("ftp://gateway.example"))
    await store.send(.saveTapped)
    #expect(store.state.editor?.failure == .init(
      field: .endpoint, message: "Enter an address like https://gateway.example/v1.",
    ))

    await store.send(.endpointEdited("gateway.example/v1"))
    await store.send(.saveTapped)
    #expect(store.state.editor?.failure == .init(
      field: .model, message: "Choose a model, or enter one.",
    ))
    #expect(store.state.editor?.focus == .model)
    #expect(store.state.cursorRow == .customModel)
  }

  @Test func `a factory profile without a key is told so before anything is sent`() async {
    let store = profilesStore(settings: .defaults) {
      $0.cleanup.verify = { _, _ in
        Issue.record("A factory endpoint is never asked without its key")
        return .verified
      }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    await openPane(store)

    await store.send(.editTapped(.apiKey))
    await store.send(.saveTapped)
    await store.receive(.saveFailed(.init(field: .apiKey, message: "Paste your Anthropic key.")))
  }

  /// Ollama and its kin take no key, so Custom proves itself without one and stores nothing.
  @Test func `Custom's first Save works keyless and turns its cleanup on`() async throws {
    let sentKey = TestBox<String??>(nil)
    let store = profilesStore(settings: notSetUpCustom) {
      $0.keychain.store = { _, _ in Issue.record("No key was typed, so none is stored") }
      $0.cleanup.verify = { _, apiKey in
        sentKey.value = apiKey
        return .verified
      }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    await openPane(store)
    #expect(store.state.status(of: store.state.profile) == .note("No cleanup"))
    #expect(store.state.rows.contains(.enabled) == false)

    await store.send(.editTapped(.endpoint))
    await store.send(.endpointEdited("http://localhost:11434/v1"))
    await store.send(.customModelEdited("gpt-oss:20b"))
    await store.send(.saveTapped)
    try await store.receive(.saveSucceeded(.init(
      endpoint: #require(URL(string: "http://localhost:11434/v1")), model: "gpt-oss:20b",
      storedKeys: [:],
    )))

    #expect(sentKey.value == .some(nil))
    #expect(store.state.settings.profiles.custom.cleanupEnabled)
    #expect(store.state.status(of: store.state.profile) == .ready)
    #expect(store.state.rows.contains(.enabled))
  }

  /// Turning cleanup off is its own decision, and editing the model later does not overrule it.
  @Test func `a later Save leaves Custom's cleanup as the user set it`() async {
    var settings = configuredCustom
    settings.profiles.custom.cleanupEnabled = false
    let store = profilesStore(settings: settings) { $0.cleanup.verify = { _, _ in .verified } }
    store.exhaustivity = .off(showSkippedAssertions: false)
    await openPane(store)

    await store.send(.editTapped(.model))
    await store.send(.customModelEdited("gpt-oss-20b"))
    await store.send(.saveTapped)
    await store.receive(.saveSucceeded(.init(
      endpoint: gateway,
      model: "gpt-oss-20b",
      storedKeys: [:],
    )))

    #expect(store.state.settings.profiles.custom.model == "gpt-oss-20b")
    #expect(!store.state.settings.profiles.custom.cleanupEnabled)
  }

  @Test func `Save discovers a bare host's base, and stores the one that answered`() async throws {
    let probed = TestBox<[String]>([])
    let store = profilesStore {
      $0.cleanup.verify = { configuration, _ in
        probed.value.append(configuration.endpoint.absoluteString)
        guard configuration.endpoint.absoluteString == "https://rootly.example" else {
          return .failed(.httpStatus(code: 404, message: nil))
        }
        return .verified
      }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    await openPane(store)

    await store.send(.editTapped(.endpoint))
    await store.send(.endpointEdited("rootly.example"))
    await store.send(.customModelEdited("rooted"))
    await store.send(.saveTapped)
    try await store.receive(.saveSucceeded(.init(
      endpoint: #require(URL(string: "https://rootly.example")), model: "rooted",
      storedKeys: [:],
    )))

    // The conventional base is asked first; the root answered, so the root is what is stored.
    #expect(probed.value == ["https://rootly.example/v1", "https://rootly.example"])
    #expect(store.state.settings.profiles.custom.endpoint == URL(string: "https://rootly.example"))
  }

  @Test func `a bare host that answers nowhere says the API was never found`() async {
    let store = profilesStore {
      $0.cleanup.verify = { _, _ in .failed(.httpStatus(code: 404, message: nil)) }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    await openPane(store)

    await store.send(.editTapped(.endpoint))
    await store.send(.endpointEdited("nowhere.example"))
    await store.send(.customModelEdited("anything"))
    await store.send(.saveTapped)
    await store.receive(.saveFailed(.init(
      field: .endpoint, message: "Couldn’t find an OpenAI-compatible API at that address.",
    )))
  }

  @Test func `the first Cancel stops the check and keeps the draft, the second discards it`() async {
    let store = profilesStore(settings: configuredCustom) {
      $0.cleanup.verify = { _, _ in
        try? await Task.sleep(for: .seconds(60))
        return .cancelled
      }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    await openPane(store)

    await store.send(.editTapped(.model))
    await store.send(.customModelEdited("gpt-oss-20b"))
    await store.send(.saveTapped)
    #expect(store.state.editor?.isChecking == true)

    await store.send(.cancelTapped)
    #expect(store.state.editor?.isChecking == false)
    #expect(store.state.editor?.customModel == "gpt-oss-20b")

    await store.send(.cancelTapped)
    #expect(store.state.editor == nil)
    #expect(store.state.settings.profiles.custom.model == "gpt-oss-120b")
    await store.finish()
  }

  @Test func `switching profile mid-check abandons the draft and writes nothing`() async {
    let (gate, release) = AsyncStream.makeStream(of: Void.self)
    let store = profilesStore(settings: configuredCustom) {
      $0.cleanup.verify = { _, _ in
        for await _ in gate {}
        return .verified
      }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    await openPane(store)

    await store.send(.editTapped(.model))
    await store.send(.customModelEdited("gpt-oss-20b"))
    await store.send(.saveTapped)
    await store.send(.profileSelected(.haiku))
    release.finish()
    await store.finish()

    #expect(store.state.editor == nil)
    #expect(store.state.settings.profiles.custom.model == "gpt-oss-120b")
    #expect(store.state.settings.profiles.overrides.isEmpty)
  }

  @Test func `leaving the pane discards the draft`() async {
    let store = profilesStore(settings: configuredCustom)
    store.exhaustivity = .off(showSkippedAssertions: false)
    await openPane(store)

    await store.send(.editTapped(.endpoint))
    await store.send(.endpointEdited("https://elsewhere.example/v1"))
    await store.send(.paneDisappeared)
    #expect(store.state.editor == nil)
    #expect(store.state.settings.profiles.custom.endpoint == gateway)
  }

  /// A key the endpoint just answered with is valid, whatever the last dictation was told.
  @Test func `a successful Save clears the key's invalid mark`() async throws {
    var health = AppHealth()
    health.rejectedKeys = [haikuSlot]
    let store = profilesStore(
      settings: .defaults, keys: [haikuSlot: "sk-ant-0123"], health: health,
    ) {
      $0.cleanup.verify = { _, _ in .verified }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    await openPane(store, keys: [haikuSlot: "sk-ant-0123"])
    #expect(store.state.status(of: store.state.profile) == .problem("Invalid key"))

    await store.send(.editTapped(.apiKey))
    await store.send(.keyEdited("sk-ant-fresh"))
    await store.send(.saveTapped)
    try await store.receive(.saveSucceeded(.init(
      endpoint: #require(URL(string: "https://api.anthropic.com/v1")),
      model: "claude-haiku-5-5",
      storedKeys: [haikuSlot: "sk-ant"],
    )))
    await store.receive(.delegate(.keysStored([haikuSlot])))

    #expect(store.state.health.rejectedKeys.isEmpty)
    #expect(store.state.status(of: store.state.profile) == .ready)
  }

  @Test func `a hosted engine's key is stored in its own slot, and only after the check`(
  ) async throws {
    let stored = TestBox<[CredentialSlot: String]>([:])
    var settings = MiniWhisperSettings.defaults
    settings.profiles.active = .accurate
    let store = profilesStore(settings: settings, keys: [googleSlot: "AIza-0123"]) {
      $0.keychain.store = { secret, slot in stored.value[slot] = secret }
      $0.asrEngine.verifyKey = { engine, key in
        #expect(stored.value.isEmpty)
        #expect(engine == .scribe)
        if key == "sk_wrong" {
          throw ASREngineError.credentialRejected
        }
      }
      $0.cleanup.verify = { _, apiKey in
        #expect(stored.value.isEmpty)
        #expect(apiKey == "AIza-0123")
        return .verified
      }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    await openPane(store, keys: [googleSlot: "AIza-0123"])
    #expect(store.state.status(of: store.state.profile) == .problem("Needs an ElevenLabs key"))

    await store.send(.editTapped(.engineKey))
    await store.send(.saveTapped)
    await store.receive(.saveFailed(.init(
      field: .engineKey,
      message: "Paste your ElevenLabs key.",
    )))

    await store.send(.engineKeyEdited("sk_wrong"))
    await store.send(.saveTapped)
    await store.receive(.saveFailed(.init(field: .engineKey, message: "Invalid key.")))
    #expect(stored.value.isEmpty)

    await store.send(.engineKeyEdited("sk_eleven-0123"))
    await store.send(.saveTapped)
    try await store.receive(.saveSucceeded(.init(
      endpoint: #require(
        URL(string: "https://generativelanguage.googleapis.com/v1beta/openai"),
      ),
      model: "gemini-3.8-flash", storedKeys: [elevenLabsSlot: "sk_ele"],
    )))
    await store.receive(.delegate(.keysStored([elevenLabsSlot])))

    #expect(stored.value == [elevenLabsSlot: "sk_eleven-0123"])
  }

  /// A reset is an edit back to the factory's value, so it is proven like any other.
  @Test func `resetting a field proves the factory value and clears only that override`(
  ) async throws {
    var settings = MiniWhisperSettings.defaults
    try settings.profiles.setEndpoint(
      #require(URL(string: "https://aig.thurstons.house/v1")),
      for: .haiku,
    )
    settings.profiles.setModel("claude-sonnet-5-5", for: .haiku)
    let verified = TestBox<CleanupConfiguration?>(nil)
    let store = profilesStore(settings: settings, keys: [haikuSlot: "sk-ant-0123"]) {
      $0.cleanup.verify = { configuration, _ in
        verified.value = configuration
        return .verified
      }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    await openPane(store, keys: [haikuSlot: "sk-ant-0123"])
    #expect(targets(store.state, at: .model) == [.edit(.model), .reset(.model)])

    await store.send(.resetTapped(.model))
    try await store.receive(.saveSucceeded(.init(
      endpoint: #require(URL(string: "https://aig.thurstons.house/v1")),
      model: "claude-haiku-5-5",
      storedKeys: [:],
    )))

    #expect(verified.value?.model == "claude-haiku-5-5")
    #expect(verified.value?.endpoint == URL(string: "https://aig.thurstons.house/v1"))
    #expect(!store.state.profile.isModelOverridden)
    #expect(store.state.profile.isEndpointOverridden)
    #expect(targets(store.state, at: .model) == [.edit(.model)])
  }

  @Test func `a listing fills the editor, and the base it found stays a draft`() async {
    let store = profilesStore {
      $0.cleanup.listModels = { configuration, _ in
        guard configuration.endpoint.absoluteString == "https://aig.thurstons.house/v1" else {
          return .unavailable(.httpStatus(code: 404, message: nil))
        }
        return .models(["gpt-oss-20b", "gpt-oss-120b"])
      }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    await openPane(store)

    await store.send(.editTapped(.endpoint))
    await store.send(.endpointEdited("aig.thurstons.house"))
    await store.send(.customModelEdited("gpt-oss-120b"))
    await store.send(.loadModelsTapped)
    await store.receive(.modelsListed(
      discovered: URL(string: "https://aig.thurstons.house/v1"), .loaded([
        "gpt-oss-120b",
        "gpt-oss-20b",
      ]),
    ))

    #expect(store.state.editor?.endpointText == "https://aig.thurstons.house/v1")
    #expect(store.state.editor?.listing == .loaded(["gpt-oss-120b", "gpt-oss-20b"]))
    #expect(store.state.editor?.modelChoice == .listed("gpt-oss-120b"))
    // Only Save writes: a listing proves nothing about the key or the model.
    #expect(store.state.settings.profiles.custom.endpoint == nil)
  }

  @Test func `a listing that fails leaves the typed model open`() async {
    let store = profilesStore(settings: configuredCustom) {
      $0.cleanup.listModels = { _, _ in .unavailable(.httpStatus(code: 404, message: nil)) }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    await openPane(store)

    await store.send(.editTapped(.model))
    await store.send(.loadModelsTapped)
    await store.receive(
      .modelsListed(discovered: nil, .unavailable("This endpoint doesn’t list its models.")),
    )
    #expect(store.state.editor?.listing == .unavailable("This endpoint doesn’t list its models."))
    #expect(store.state.editor?.modelChoice == .custom)
    #expect(store.state.editor?.customModel == "gpt-oss-120b")
  }

  @Test func `a cached listing opens the editor on the chosen model`() {
    var state = ProfilesFeature.State(
      settings: Shared(value: configuredCustom), health: Shared(value: AppHealth()),
    )
    state.$modelListings.withLock { $0[gateway.absoluteString] = ["gpt-oss-120b", "gpt-oss-20b"] }
    let editor = state.makeEditor()
    #expect(editor.modelChoice == .listed("gpt-oss-120b"))
    #expect(editor.listedModels == ["gpt-oss-120b", "gpt-oss-20b"])
  }

  @Test func `the pane shows the rows that apply to the profile on screen`() {
    func rows(_ settings: MiniWhisperSettings) -> [ProfilesFeature.Row] {
      ProfilesFeature.State(settings: Shared(value: settings), health: Shared(value: AppHealth()))
        .rows
    }
    var offline = MiniWhisperSettings.defaults
    offline.profiles.active = .offline
    var accurate = MiniWhisperSettings.defaults
    accurate.profiles.active = .accurate
    var customOff = configuredCustom
    customOff.profiles.custom.cleanupEnabled = false

    #expect(rows(.defaults) == [.profile, .endpoint, .apiKey, .model, .timeout, .instructions])
    #expect(rows(accurate) == [
      .profile, .engineKey, .endpoint, .apiKey, .model, .timeout, .instructions,
    ])
    // S1-mini reads no prompt, so only the limit applies.
    #expect(rows(offline) == [.profile, .timeout])
    #expect(rows(notSetUpCustom) == [.profile, .actions, .boostsVocabulary])
    // With cleanup off there is no limit to bind and no prompt to read.
    #expect(rows(customOff) == [
      .profile, .enabled, .endpoint, .apiKey, .model, .boostsVocabulary,
    ])
  }

  @Test func `the cursor walks the editor's rows and lands Cancel before Save`() async {
    let store = profilesStore(settings: configuredCustom)
    store.exhaustivity = .off(showSkippedAssertions: false)
    await openPane(store)

    await store.send(.editTapped(.endpoint))
    #expect(store.state.cursorRow == .endpoint)
    #expect(store.state.rows == [
      .profile, .enabled, .endpoint, .apiKey, .model, .customModel, .actions, .boostsVocabulary,
      .timeout, .instructions,
    ])
    for _ in 0 ..< 4 {
      await store.send(.rowMoved(.next))
    }
    #expect(store.state.cursorRow == .actions)
    #expect(store.state.targets == [.cancel, .save])
    await store.send(.rightPressed)
    #expect(store.state.cursorTarget == .save)
  }

  @Test func `the picker says what each profile still needs, models before keys`() {
    var state = ProfilesFeature.State(
      settings: Shared(value: .defaults), health: Shared(value: AppHealth()),
    )
    let lineup = state.settings.profiles.lineup
    func status(_ id: ProfileID) -> ProfilesFeature.Status {
      state.status(of: lineup.first { $0.id == id }!)
    }
    // Unread keys are not missing.
    #expect(status(.haiku) == .ready)

    state.storedKeys = [haikuSlot: "sk-ant"]
    #expect(status(.haiku) == .ready)
    #expect(status(.cerebras) == .problem("Needs a Cerebras key"))
    #expect(status(.accurate) == .problem("Needs an ElevenLabs key"))

    state.assets = [.gate: .installed(bytes: 1), .parakeet: .downloading(0.42), .s1Mini: .missing]
    #expect(status(.haiku) == .note("Downloading Parakeet TDT v2 · 42%"))
    #expect(status(.offline) == .note("Downloading Parakeet TDT v2 · 42%"))
    state.assets[.parakeet] = .installed(bytes: 1)
    #expect(status(.offline) == .problem("Needs S1-mini"))
    // Custom's key is optional, so a set-up Custom without one is ready.
    #expect(status(.custom) == .note("No cleanup"))
  }

  @Test func `choosing a profile writes it at once and closes any draft`() async {
    let store = profilesStore(settings: configuredCustom)
    store.exhaustivity = .off(showSkippedAssertions: false)
    await openPane(store)

    await store.send(.editTapped(.endpoint))
    await store.send(.profileSelected(.offline))
    #expect(store.state.settings.profiles.active == .offline)
    #expect(store.state.editor == nil)
  }
}

// MARK: - TestBox

/// A value written from inside a synchronous dependency closure and read after the fact.
final class TestBox<Value>: @unchecked Sendable {
  // MARK: Lifecycle

  init(_ value: Value) {
    stored = value
  }

  // MARK: Internal

  var value: Value {
    get { lock.withLock { stored } }
    set { lock.withLock { stored = newValue } }
  }

  // MARK: Private

  private let lock = NSLock()
  private var stored: Value
}

private let storedKey = "sk-liv-test-0123"
private let gateway = URL(string: "https://gateway.example/v1")!
private let customSlot = CredentialSlot(profile: .custom, provider: .endpoint)
private let haikuSlot = CredentialSlot(profile: .haiku, provider: .anthropic)
private let elevenLabsSlot = CredentialSlot(profile: .accurate, provider: .elevenlabs)
private let googleSlot = CredentialSlot(profile: .accurate, provider: .google)

/// Custom before its first Save: nothing configured, cleanup off.
private var notSetUpCustom: MiniWhisperSettings {
  var settings = MiniWhisperSettings.defaults
  settings.profiles.active = .custom
  return settings
}

/// Custom set up against a gateway, with its cleanup on.
private var configuredCustom: MiniWhisperSettings {
  var settings = notSetUpCustom
  settings.profiles.custom = CustomProfileSettings(
    cleanupEnabled: true, endpoint: gateway, model: "gpt-oss-120b", boostsVocabulary: false,
  )
  return settings
}

@MainActor private func profilesStore(
  settings: MiniWhisperSettings = notSetUpCustom, keys: [CredentialSlot: String] = [:],
  health: AppHealth = AppHealth(),
  _ dependencies: (inout DependencyValues) -> Void = { _ in },
) -> TestStoreOf<ProfilesFeature> {
  TestStore(initialState: ProfilesFeature.State(
    settings: Shared(value: settings), health: Shared(value: health),
  )) {
    ProfilesFeature()
  } withDependencies: {
    $0.keychain.read = { keys[$0] }
    $0.keychain.store = { _, _ in }
    $0.cleanup.listModels = { _, _ in .cancelled }
    dependencies(&$0)
  }
}

/// Opening the pane reads which slots hold keys, then refreshes the listing quietly; a refresh
/// that lists nothing says nothing.
@MainActor private func openPane(
  _ store: TestStoreOf<ProfilesFeature>, keys: [CredentialSlot: String] = [:],
) async {
  await store.send(.task)
  let slots = Set(store.state.settings.profiles.lineup.flatMap {
    [$0.engineCredential, $0.endpointLeg?.credential].compactMap(\.self)
  })
  let stored = keys.filter { slots.contains($0.key) }.mapValues { String($0.prefix(6)) }
  await store.receive(.storedKeysRead(stored)) { $0.storedKeys = stored }
}

private func targets(
  _ state: ProfilesFeature.State, at row: ProfilesFeature.Row,
) -> [ProfilesFeature.Target] {
  var state = state
  state.cursor = .init(row: row)
  return state.targets
}
