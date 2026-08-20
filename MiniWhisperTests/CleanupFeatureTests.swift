import AppSettings
import ComposableArchitecture
import Foundation
@testable import MiniWhisper
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

// MARK: - CleanupFeatureTests

@MainActor struct CleanupFeatureTests {
  @Test func `the pane reads the key from the Keychain, never from settings`() async {
    let store = cleanupStore { $0.keychain.read = { _ in "sk-live-0123456789" } }

    await store.send(.task)
    await store.receive(.keyRead("sk-live-0123456789")) {
      $0.key = .stored(prefix: "sk-liv")
    }
  }

  @Test func `no key stored is a field waiting for one`() async {
    let store = cleanupStore { $0.keychain.read = { _ in nil } }

    await store.send(.task)
    await store.receive(.keyRead(nil)) { $0.key = .missing }
  }

  @Test func `a stored key is replaced outright, never edited in place`() async {
    let store = cleanupStore { $0.keychain.read = { _ in "sk-live-0123456789" } }
    await store.send(.task)
    await store.receive(.keyRead("sk-live-0123456789")) { $0.key = .stored(prefix: "sk-liv") }

    await store.send(.cursorHovered(.apiKey)) { $0.cursor.row = .apiKey }
    // Replace opens the field and hands it the keys, so a paste can follow the button directly.
    await store.send(.replaceKeyTapped) {
      $0.isEndpointDirty = true
      $0.key = .editing("")
      $0.keyActivation = 1
    }
    #expect(store.state.targets == [.apiKey])
  }

  @Test func `Save conforms the address, stores the key, and proves all three together`() async {
    let stored = TestBox<String?>(nil)
    let verified = TestBox<CleanupConfiguration?>(nil)
    let store = cleanupStore {
      $0.keychain.store = { secret, account in
        #expect(account == .cleanupAPIKey)
        stored.value = secret
      }
      $0.keychain.read = { _ in stored.value }
      $0.cleanup.verify = { configuration, apiKey in
        verified.value = configuration
        #expect(apiKey == "sk-typed-0123")
        return .verified
      }
    }

    await store.send(.endpointEdited("gateway.example/v1/")) {
      $0.isEndpointDirty = true
      $0.endpointText = "gateway.example/v1/"
    }
    await store.send(.customModelEdited("gpt-oss-120b")) {
      $0.isEndpointDirty = true
      $0.customModel = "gpt-oss-120b"
    }
    await store.send(.keyEdited("sk-typed-0123")) {
      $0.isEndpointDirty = true
      $0.key = .editing("sk-typed-0123")
    }
    await store.send(.saveTapped) {
      $0.endpointText = "https://gateway.example/v1"
      $0.save = .saving
      $0.$settings.withLock {
        $0.cleanup.endpoint = URL(string: "https://gateway.example/v1")
        $0.cleanup.model = "gpt-oss-120b"
      }
    }
    await store.receive(.keyRead("sk-typed-0123")) { $0.key = .stored(prefix: "sk-typ") }
    await store.receive(.saveCompleted(.saved)) {
      $0.save = .saved
      $0.isEndpointDirty = false
    }

    #expect(stored.value == "sk-typed-0123")
    #expect(verified.value?.endpoint == URL(string: "https://gateway.example/v1"))
    #expect(verified.value?.model == "gpt-oss-120b")
    // The verify answers a person waiting on a button, so it runs on its own short budget.
    #expect(verified.value?.timeout == CleanupConfiguration.verificationTimeout)
    #expect(store.state.settings.cleanup.endpoint == URL(string: "https://gateway.example/v1"))
    #expect(store.state.settings.cleanup.model == "gpt-oss-120b")
  }

  @Test func `an address that is not one never reaches the endpoint`() async {
    let store = cleanupStore {
      $0.cleanup.verify = { _, _ in
        Issue.record("An unusable address must not be proven against")
        return .verified
      }
    }

    await store.send(.customModelEdited("gpt-oss-120b")) {
      $0.isEndpointDirty = true
      $0.customModel = "gpt-oss-120b"
    }
    await store.send(.saveTapped) {
      $0.save = .failed("Enter an address like https://gateway.example/v1.")
    }
  }

  @Test func `a model is required before anything is proven`() async {
    let store = cleanupStore()

    await store.send(.endpointEdited("https://gateway.example/v1")) {
      $0.isEndpointDirty = true
      $0.endpointText = "https://gateway.example/v1"
    }
    await store.send(.saveTapped) { $0.save = .failed("Choose a model, or enter one.") }
  }

  @Test(arguments: [
    (CleanupFailure.unreachable("refused"), "Couldn’t reach that address."),
    (.httpStatus(code: 401, message: "bad key"), "That endpoint rejected the key."),
    (.httpStatus(code: 404, message: nil), "That address has no chat completions endpoint."),
    (.httpStatus(code: 500, message: "overloaded"), "overloaded"),
    (.timedOut(5), "That endpoint didn’t answer in time."),
    (
      .malformedResponse("html"),
      "That endpoint didn’t answer like an OpenAI-compatible one.",
    ),
  ])
  func `a failed proof says what to do about it`(
    _ failure: CleanupFailure, _ message: String,
  ) async {
    let store = cleanupStore {
      $0.keychain.read = { _ in "sk-live-0123456789" }
      $0.cleanup.verify = { _, _ in .failed(failure) }
    }

    await store.send(.endpointEdited("https://gateway.example/v1")) {
      $0.isEndpointDirty = true
      $0.endpointText = "https://gateway.example/v1"
    }
    await store.send(.customModelEdited("gpt-oss-120b")) {
      $0.isEndpointDirty = true
      $0.customModel = "gpt-oss-120b"
    }
    await store.send(.saveTapped) {
      $0.save = .saving
      $0.$settings.withLock {
        $0.cleanup.endpoint = URL(string: "https://gateway.example/v1")
        $0.cleanup.model = "gpt-oss-120b"
      }
    }
    await store.receive(.keyRead("sk-live-0123456789")) { $0.key = .stored(prefix: "sk-liv") }
    await store.receive(.saveCompleted(.failed(message))) { $0.save = .failed(message) }
    // What the user typed is kept: an address that needs fixing is still the address they meant.
    #expect(store.state.settings.cleanup.endpoint == URL(string: "https://gateway.example/v1"))
  }

  @Test func `a listing that succeeds turns the typed model into a chosen one`() async {
    let store = cleanupStore {
      $0.keychain.read = { _ in "sk-live-0123456789" }
      $0.cleanup.listModels = { _, _ in .models(["gpt-oss-20b", "gpt-oss-120b"]) }
    }

    await store.send(.endpointEdited("https://gateway.example/v1")) {
      $0.isEndpointDirty = true
      $0.endpointText = "https://gateway.example/v1"
    }
    await store.send(.customModelEdited("gpt-oss-120b")) {
      $0.isEndpointDirty = true
      $0.customModel = "gpt-oss-120b"
    }
    await store.send(.loadModelsTapped) { $0.listing = .loading }
    await store.receive(.modelsListed(.loaded(["gpt-oss-120b", "gpt-oss-20b"]))) {
      $0.listing = .loaded(["gpt-oss-120b", "gpt-oss-20b"])
      $0.modelChoice = .listed("gpt-oss-120b")
    }
    #expect(!store.state.rows.contains(.customModel))
  }

  @Test func `a bare host discovers its API base, and the pane says where it went`() async throws {
    let probed = TestBox<[String]>([])
    let store = cleanupStore {
      $0.keychain.read = { _ in "sk-live-0123456789" }
      $0.cleanup.listModels = { configuration, _ in
        probed.value.append(configuration.endpoint.absoluteString)
        guard configuration.endpoint.absoluteString == "https://aig.thurstons.house/v1" else {
          return .unavailable(.httpStatus(code: 404, message: nil))
        }
        return .models(["gpt-oss-120b"])
      }
    }

    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.endpointEdited("aig.thurstons.house"))
    await store.send(.loadModelsTapped)
    try await store
      .receive(.endpointDiscovered(#require(URL(string: "https://aig.thurstons.house/v1"))))
    await store.receive(.modelsListed(.loaded(["gpt-oss-120b"])))
    await store.finish()

    // The base that answered is what the field and the file say, because it is what the client
    // will use.
    #expect(store.state.endpointText == "https://aig.thurstons.house/v1")
    #expect(
      store.state.settings.cleanup.endpoint == URL(string: "https://aig.thurstons.house/v1"),
    )
    // The conventional base is asked first, so a gateway that lives there costs one request.
    #expect(probed.value == ["https://aig.thurstons.house/v1"])
  }

  @Test func `a gateway whose API is at the root is found one probe later`() async throws {
    let probed = TestBox<[String]>([])
    let store = cleanupStore {
      $0.keychain.read = { _ in "sk-live-0123456789" }
      $0.cleanup.listModels = { configuration, _ in
        probed.value.append(configuration.endpoint.absoluteString)
        guard configuration.endpoint.absoluteString == "https://rootly.example" else {
          return .unavailable(.httpStatus(code: 404, message: nil))
        }
        return .models(["rooted"])
      }
    }

    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.endpointEdited("rootly.example"))
    await store.send(.loadModelsTapped)
    try await store.receive(.endpointDiscovered(#require(URL(string: "https://rootly.example"))))
    await store.receive(.modelsListed(.loaded(["rooted"])))
    await store.finish()

    #expect(store.state.endpointText == "https://rootly.example")
    #expect(store.state.settings.cleanup.endpoint == URL(string: "https://rootly.example"))
    #expect(probed.value == ["https://rootly.example/v1", "https://rootly.example"])
  }

  @Test func `an address with a path is never second-guessed`() async {
    let probed = TestBox<[String]>([])
    let store = cleanupStore {
      $0.keychain.read = { _ in "sk-live-0123456789" }
      $0.cleanup.listModels = { configuration, _ in
        probed.value.append(configuration.endpoint.absoluteString)
        return .unavailable(.httpStatus(code: 404, message: nil))
      }
    }

    await store.send(.endpointEdited("https://gateway.example/api/v9")) {
      $0.isEndpointDirty = true
      $0.endpointText = "https://gateway.example/api/v9"
    }
    await store.send(.loadModelsTapped) { $0.listing = .loading }
    // The user named the base, so a 404 is what that base can do — not a reason to go looking.
    await store.receive(.modelsListed(.unavailable("This endpoint doesn’t list its models."))) {
      $0.listing = .unavailable("This endpoint doesn’t list its models.")
    }
    #expect(probed.value == ["https://gateway.example/api/v9"])
  }

  @Test func `a bare host that answers nowhere says so, and does not blame the listing`() async {
    let store = cleanupStore {
      $0.keychain.read = { _ in "sk-live-0123456789" }
      $0.cleanup.listModels = { _, _ in .unavailable(.httpStatus(code: 404, message: nil)) }
    }

    await store.send(.endpointEdited("aig.thurstons.house")) {
      $0.isEndpointDirty = true
      $0.endpointText = "aig.thurstons.house"
    }
    await store.send(.loadModelsTapped) { $0.listing = .loading }
    let message = "Couldn’t find an OpenAI-compatible API at that address."
    await store.receive(.modelsListed(.unavailable(message))) {
      $0.listing = .unavailable(message)
    }
  }

  @Test func `an endpoint that speaks during discovery is reported as itself`() async {
    let store = cleanupStore {
      $0.keychain.read = { _ in "sk-live-0123456789" }
      $0.cleanup.listModels = { _, _ in .unavailable(.httpStatus(code: 401, message: nil)) }
    }

    await store.send(.endpointEdited("aig.thurstons.house")) {
      $0.isEndpointDirty = true
      $0.endpointText = "aig.thurstons.house"
    }
    await store.send(.loadModelsTapped) { $0.listing = .loading }
    await store.receive(.modelsListed(.unavailable("That endpoint rejected the key."))) {
      $0.listing = .unavailable("That endpoint rejected the key.")
    }
  }

  @Test func `Save discovers the base too, and adopts what answered`() async throws {
    let probed = TestBox<[String]>([])
    let store = cleanupStore {
      $0.keychain.read = { _ in "sk-live-0123456789" }
      $0.cleanup.verify = { configuration, _ in
        probed.value.append(configuration.endpoint.absoluteString)
        guard configuration.endpoint.absoluteString == "https://aig.thurstons.house/v1" else {
          return .failed(.httpStatus(code: 404, message: nil))
        }
        return .verified
      }
    }

    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.endpointEdited("aig.thurstons.house"))
    await store.send(.customModelEdited("gpt-oss-120b"))
    await store.send(.saveTapped)
    await store.receive(.keyRead("sk-live-0123456789"))
    try await store
      .receive(.endpointDiscovered(#require(URL(string: "https://aig.thurstons.house/v1"))))
    await store.receive(.saveCompleted(.saved))
    await store.finish()

    #expect(store.state.endpointText == "https://aig.thurstons.house/v1")
    #expect(
      store.state.settings.cleanup.endpoint == URL(string: "https://aig.thurstons.house/v1"),
    )
    #expect(probed.value == ["https://aig.thurstons.house/v1"])
  }

  @Test func `a Save that discovers nothing says the address was never found`() async {
    let store = cleanupStore {
      $0.keychain.read = { _ in "sk-live-0123456789" }
      $0.cleanup.verify = { _, _ in .failed(.httpStatus(code: 404, message: nil)) }
    }

    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.endpointEdited("aig.thurstons.house"))
    await store.send(.customModelEdited("gpt-oss-120b"))
    await store.send(.saveTapped)
    await store.receive(.keyRead("sk-live-0123456789"))
    let message = "Couldn’t find an OpenAI-compatible API at that address."
    await store.receive(.saveCompleted(.failed(message)))
    await store.finish()

    // The address the user typed is still theirs to fix, even though nothing answered at it.
    #expect(store.state.settings.cleanup.endpoint == URL(string: "https://aig.thurstons.house"))
  }

  @Test func `a listing that fails is not an error the user has to fix`() async {
    let store = cleanupStore {
      $0.keychain.read = { _ in "sk-live-0123456789" }
      $0.cleanup.listModels = { _, _ in .unavailable(.httpStatus(code: 404, message: nil)) }
    }

    await store.send(.endpointEdited("https://gateway.example/v1")) {
      $0.isEndpointDirty = true
      $0.endpointText = "https://gateway.example/v1"
    }
    await store.send(.loadModelsTapped) { $0.listing = .loading }
    await store.receive(.modelsListed(.unavailable("This endpoint doesn’t list its models."))) {
      $0.listing = .unavailable("This endpoint doesn’t list its models.")
    }
    #expect(store.state.save == .idle)
    #expect(store.state.rows.contains(.customModel))
  }

  @Test func `the toggle and the time limit answer for themselves`() async {
    let store = cleanupStore()

    await store.send(.enabledToggled(true)) {
      $0.$settings.withLock { $0.cleanup.enabled = true }
    }
    await store.send(.timeoutSelected(30)) {
      $0.$settings.withLock { $0.cleanup.setTimeout(30) }
    }
  }

  @Test func `the cursor walks the rows the pane is actually showing`() async {
    let store = cleanupStore()

    #expect(store.state.cursorRow == .enabled)
    await store.send(.rowMoved(.next)) { $0.cursor.row = .timeout }
    await store.send(.rowMoved(.next)) { $0.cursor.row = .endpoint }
    await store.send(.rowMoved(.previous)) { $0.cursor.row = .timeout }
    // Up from the first row stays put rather than wrapping into the sidebar's business.
    await store.send(.rowMoved(.previous)) { $0.cursor.row = .enabled }
    await store.send(.rowMoved(.previous))
  }

  /// The button is the section's unsaved state made visible: grey until something is edited,
  /// prominent while an edit is pending, and grey again — saying so — once it is confirmed.
  @Test func `Save arms on an edit, disarms on a confirmation, and re-arms on the next`() async {
    let store = cleanupStore {
      $0.keychain.read = { _ in "sk-live-0123456789" }
      $0.cleanup.verify = { _, _ in .verified }
    }
    #expect(store.state.saveButton == .idle)

    await store.send(.endpointEdited("https://gateway.example/v1")) {
      $0.isEndpointDirty = true
      $0.endpointText = "https://gateway.example/v1"
    }
    #expect(store.state.saveButton == .armed)
    #expect(store.state.saveButton.title == "Save")
    #expect(store.state.saveButton.isPressable)

    await store.send(.customModelEdited("gpt-oss-120b")) {
      $0.isEndpointDirty = true
      $0.customModel = "gpt-oss-120b"
    }
    await store.send(.saveTapped) {
      $0.save = .saving
      $0.$settings.withLock {
        $0.cleanup.endpoint = URL(string: "https://gateway.example/v1")
        $0.cleanup.model = "gpt-oss-120b"
      }
    }
    #expect(store.state.saveButton == .checking)
    await store.receive(.keyRead("sk-live-0123456789")) { $0.key = .stored(prefix: "sk-liv") }
    await store.receive(.saveCompleted(.saved)) {
      $0.save = .saved
      $0.isEndpointDirty = false
    }
    #expect(store.state.saveButton == .confirmed)
    #expect(store.state.saveButton.title == "Saved")
    #expect(!store.state.saveButton.isPressable)

    // The next edit retires the confirmation and arms the same slot again.
    await store.send(.modelSelected(.custom)) {
      $0.isEndpointDirty = true
      $0.save = .idle
      $0.modelChoice = .custom
    }
    #expect(store.state.saveButton == .armed)
  }

  @Test func `a failure leaves the button armed, because there is still something to save`(
  ) async {
    let store = cleanupStore {
      $0.keychain.read = { _ in "sk-live-0123456789" }
      $0.cleanup.verify = { _, _ in .failed(.unreachable("refused")) }
    }

    await store.send(.endpointEdited("https://gateway.example/v1")) {
      $0.isEndpointDirty = true
      $0.endpointText = "https://gateway.example/v1"
    }
    await store.send(.customModelEdited("gpt-oss-120b")) {
      $0.isEndpointDirty = true
      $0.customModel = "gpt-oss-120b"
    }
    await store.send(.saveTapped) {
      $0.save = .saving
      $0.$settings.withLock {
        $0.cleanup.endpoint = URL(string: "https://gateway.example/v1")
        $0.cleanup.model = "gpt-oss-120b"
      }
    }
    await store.receive(.keyRead("sk-live-0123456789")) { $0.key = .stored(prefix: "sk-liv") }
    await store.receive(.saveCompleted(.failed("Couldn’t reach that address."))) {
      $0.save = .failed("Couldn’t reach that address.")
    }
    #expect(store.state.saveButton == .armed)
    #expect(store.state.isEndpointDirty)
  }

  @Test func `Save shares the model row rather than owning a row of its own`() async {
    let store = cleanupStore()

    await store.send(.cursorHovered(.model)) { $0.cursor.row = .model }
    #expect(store.state.targets == [.model, .loadModels, .save])
    await store.send(.rightPressed) { $0.cursor.target = 1 }
    await store.send(.rightPressed) { $0.cursor.target = 2 }
    #expect(store.state.cursorTarget == .save)
    // Return on a button with nothing to save does what clicking it would: nothing.
    await store.send(.pressRequested)

    await store.send(.endpointEdited("not an address")) {
      $0.isEndpointDirty = true
      $0.endpointText = "not an address"
    }
    await store.send(.pressRequested)
    await store.receive(.saveTapped) {
      $0.save = .failed("Enter an address like https://gateway.example/v1.")
    }
    // The model row is followed by the custom-model field, then the prompt — never by a Save row.
    #expect(store.state.rows == [
      .enabled,
      .timeout,
      .endpoint,
      .apiKey,
      .model,
      .customModel,
      .instructions,
    ])
  }

  @Test func `a stored key's row has two targets, a typed one has a single field`() async {
    let store = cleanupStore { $0.keychain.read = { _ in "sk-live-0123456789" } }
    await store.send(.task)
    await store.receive(.keyRead("sk-live-0123456789")) { $0.key = .stored(prefix: "sk-liv") }

    await store.send(.cursorHovered(.apiKey)) { $0.cursor.row = .apiKey }
    #expect(store.state.targets == [.apiKey, .replaceKey])
    await store.send(.rightPressed) { $0.cursor.target = 1 }
    #expect(store.state.cursorTarget == .replaceKey)
    await store.send(.pressRequested)
    await store.receive(.replaceKeyTapped) {
      $0.isEndpointDirty = true
      $0.key = .editing("")
      $0.keyActivation = 1
      $0.cursor.target = 0
    }
  }

  @Test func `Return on a pop-up row is the only thing that can open one`() async {
    let store = cleanupStore()

    await store.send(.cursorHovered(.timeout)) { $0.cursor.row = .timeout }
    await store.send(.pressRequested) { $0.timeoutActivation = 1 }
    await store.send(.cursorHovered(.model)) { $0.cursor.row = .model }
    await store.send(.pressRequested) { $0.modelActivation = 1 }
    await store.send(.rightPressed) { $0.cursor.target = 1 }
    #expect(store.state.cursorTarget == .loadModels)
  }
}

// MARK: - TestBox

/// A value written from inside a synchronous dependency closure and read after the fact.
private final class TestBox<Value>: @unchecked Sendable {
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

@MainActor private func cleanupStore(
  _ dependencies: (inout DependencyValues) -> Void = { _ in },
) -> TestStoreOf<CleanupFeature> {
  let settings = Shared(value: MiniWhisperSettings.defaults)
  return TestStore(initialState: CleanupFeature.State(settings: settings)) {
    CleanupFeature()
  } withDependencies: {
    $0.keychain.read = { _ in nil }
    $0.keychain.store = { _, _ in }
    dependencies(&$0)
  }
}
