import AppSettings
import ASREngine
import ComposableArchitecture
import Foundation
import ModelLibrary
import OSLog
import TranscriptCleanup

private let profilesPaneLogger = Logger(
  subsystem: "com.thurstonsand.MiniWhisper", category: "profiles-pane",
)

// MARK: - ProfilesFeature

/// The Profiles pane: which stack dictates, and the endpoint, key, and model behind its cleanup.
/// The picker, the toggles, and the global rows write straight through to settings, because they
/// are answerable on their own. The endpoint's facts are only ever written together, by a Save
/// that proved them first: nothing reaches the Keychain or the settings file that the endpoint has
/// not just answered with.
@Reducer struct ProfilesFeature {
  // MARK: Internal

  enum CursorMovement: Equatable {
    case previous
    case next
  }

  /// What Save writes together, and what a failed Save can blame.
  enum Field: Hashable {
    case engineKey
    case endpoint
    case apiKey
    case model
  }

  enum Row: Hashable {
    case profile
    case enabled
    case engineKey
    case endpoint
    case apiKey
    case model
    case customModel
    /// Set Up at rest, Cancel and Save while editing.
    case actions
    case boostsVocabulary
    case timeout
    case instructions
  }

  enum Target: Equatable {
    case profile
    case enabled
    case edit(Field)
    case reset(Field)
    case field(Field)
    case loadModels
    case customModel
    case setUp
    case cancel
    case save
    case boostsVocabulary
    case timeout
    case instructions
  }

  /// `GET /v1/models` is a convenience. A gateway that does not serve it is not broken, so a
  /// failed listing is a caption beside a Custom field, not an error to fix.
  enum ModelListing: Equatable {
    case notLoaded
    case loading
    case loaded([String])
    case unavailable(String)
  }

  enum ModelChoice: Equatable {
    case listed(String)
    case custom
  }

  /// What a profile says beside its name in the picker. A problem costs the user a dictation or
  /// its cleanup; a note is only worth knowing.
  enum Status: Equatable {
    case ready
    case problem(String)
    case note(String)
  }

  struct Failure: Equatable {
    let field: Field
    let message: String
  }

  /// What a Save proved, and what it stored to prove it.
  struct Saved: Equatable {
    let endpoint: URL
    let model: String
    let storedKeys: [CredentialSlot: String]
  }

  /// The endpoint's facts while they are being changed. Nothing in here is anywhere else yet.
  struct Editor: Equatable {
    var endpointText: String
    /// Empty keeps whatever key is stored; anything typed replaces it.
    var keyText = ""
    var engineKeyText = ""
    var modelChoice: ModelChoice
    var customModel: String
    var listing: ModelListing
    var isChecking = false
    var failure: Failure?
    /// The field asked to take the keys, and a count so asking twice is still a change.
    var focus: Field?
    var focusRequest = 0

    /// The model Save would write: whichever of the two fields the choice points at.
    var resolvedModel: String {
      switch modelChoice {
      case let .listed(model):
        model
      case .custom:
        customModel.trimmingCharacters(in: .whitespacesAndNewlines)
      }
    }

    var listedModels: [String] {
      guard case let .loaded(models) = listing else {
        return []
      }
      return models
    }

    mutating func requestFocus(_ field: Field) {
      focus = field
      focusRequest += 1
    }
  }

  struct Cursor: Equatable {
    var row: Row?
    var target = 0
  }

  @ObservableState struct State: Equatable {
    // MARK: Lifecycle

    init(settings: Shared<MiniWhisperSettings>, health: Shared<AppHealth>) {
      _settings = settings
      _health = health
      instructions = settings.wrappedValue.additionalInstructions
    }

    // MARK: Internal

    static let timeoutPresets: [TimeInterval] = [5, 10, 20, 30]

    @Shared var settings: MiniWhisperSettings
    @Shared var health: AppHealth
    /// Empty until the library first answers, and an asset nobody has heard about yet is not
    /// reported missing.
    var assets: [ModelAsset: AssetState] = [:]
    /// The last successful listing per endpoint, so a configured model reads as the listed choice
    /// it was rather than as typed text the moment the editor opens.
    @Shared(.modelListings) var modelListings: [String: [String]] = [:]
    var instructions: String
    /// Enough of each stored key to recognise it, per slot. Read from the Keychain itself, never
    /// from settings, so the file and the keychain cannot disagree; nil until it has answered.
    var storedKeys: [CredentialSlot: String]?
    var editor: Editor?
    var cursor = Cursor()
    /// The field the user is typing in, if any. The window's letter keys are the pane's grammar
    /// everywhere except inside a field, where they are just letters.
    var editingField: Row?
    /// Return has to reach controls that only answer to a click or a first-responder change, and
    /// a view cannot be told to do the same thing twice by a value that stays the same.
    var profileActivation = 0
    var timeoutActivation = 0
    var modelActivation = 0
    var instructionsActivation = 0

    var profile: Profile {
      settings.activeProfile
    }

    var credential: CredentialSlot? {
      profile.endpointLeg?.credential
    }

    var engineCredential: CredentialSlot? {
      profile.engineCredential
    }

    /// Custom has nothing to show until its first Save; every factory profile ships set up.
    var isSetUp: Bool {
      guard let leg = profile.endpointLeg else {
        return true
      }
      return leg.endpoint != nil && leg.model?.isEmpty == false
    }

    var isEditingField: Bool {
      editingField != nil
    }

    var timeout: TimeInterval {
      settings.cleanupTimeout
    }

    /// The limit only binds a profile that cleans at all.
    var showsTimeout: Bool {
      profile.cleanup != .none
    }

    /// Additional instructions reach a model that reads a prompt. S1-mini reads none.
    var hasPromptSurface: Bool {
      if case .endpoint = profile.cleanup {
        return true
      }
      return false
    }

    var rows: [Row] {
      var rows: [Row] = [.profile]
      if profile.isCustom, isSetUp {
        rows.append(.enabled)
      }
      if let editor {
        if engineCredential != nil {
          rows.append(.engineKey)
        }
        rows += [.endpoint, .apiKey, .model]
        if editor.modelChoice == .custom {
          rows.append(.customModel)
        }
        rows.append(.actions)
      } else if profile.endpointLeg != nil {
        if isSetUp {
          if engineCredential != nil {
            rows.append(.engineKey)
          }
          rows += [.endpoint, .apiKey, .model]
        } else {
          rows.append(.actions)
        }
      }
      if profile.isCustom {
        rows.append(.boostsVocabulary)
      }
      if showsTimeout {
        rows.append(.timeout)
      }
      if hasPromptSurface {
        rows.append(.instructions)
      }
      return rows
    }

    var cursorRow: Row {
      guard let row = cursor.row, rows.contains(row) else {
        return rows[0]
      }
      return row
    }

    var targets: [Target] {
      let isEditing = editor != nil
      switch cursorRow {
      case .profile:
        return [.profile]
      case .enabled:
        return [.enabled]
      case .engineKey:
        return isEditing ? [.field(.engineKey)] : [.edit(.engineKey)]
      case .endpoint:
        if isEditing {
          return [.field(.endpoint)]
        }
        return [.edit(.endpoint)] + (profile.isEndpointOverridden ? [.reset(.endpoint)] : [])
      case .apiKey:
        return isEditing ? [.field(.apiKey)] : [.edit(.apiKey)]
      case .model:
        if isEditing {
          return [.field(.model), .loadModels]
        }
        return [.edit(.model)] + (profile.isModelOverridden ? [.reset(.model)] : [])
      case .customModel:
        return [.customModel]
      case .actions:
        return isEditing ? [.cancel, .save] : [.setUp]
      case .boostsVocabulary:
        return [.boostsVocabulary]
      case .timeout:
        return [.timeout]
      case .instructions:
        return [.instructions]
      }
    }

    var cursorTarget: Target {
      targets[min(cursor.target, targets.count - 1)]
    }

    /// Its models outrank its keys: without them nothing is transcribed at all.
    func status(of profile: Profile) -> Status {
      for asset in profile.assets {
        switch assets[asset] {
        case .missing:
          return .problem("Needs \(asset.name)")
        case .failed:
          return .problem("\(asset.name) failed to download")
        case let .downloading(fraction):
          return .note("Downloading \(asset.name) · \(Int(fraction * 100))%")
        case .installed,
             nil:
          continue
        }
      }
      if let slot = profile.engineCredential, let storedKeys, storedKeys[slot] == nil {
        return .problem("Needs \(slot.provider.keyPhrase)")
      }
      switch profile.cleanup {
      case .none:
        return .note("No cleanup")
      case .local:
        return .ready
      case let .endpoint(leg):
        if leg.endpoint == nil {
          return .problem("Needs an address")
        }
        if leg.model?.isEmpty != false {
          return .problem("Needs a model")
        }
        // Custom's key is optional: plenty of endpoints on this Mac take none.
        if leg.credential.provider != .endpoint, let storedKeys, storedKeys[leg.credential] == nil {
          return .problem("Needs \(leg.credential.provider.keyPhrase)")
        }
        if health.rejectedKeys.contains(leg.credential) {
          return .problem("Invalid key")
        }
        return .ready
      }
    }

    /// Everything the editor shows starts from what the active profile already holds.
    func makeEditor() -> Editor {
      let leg = profile.endpointLeg
      let model = leg?.model ?? ""
      var editor = Editor(
        endpointText: EndpointAddress.display(leg?.endpoint), modelChoice: .custom,
        customModel: model, listing: .notLoaded,
      )
      if let endpoint = leg?.endpoint, let cached = modelListings[endpoint.absoluteString] {
        editor.listing = .loaded(cached)
        editor.modelChoice = cached.contains(model) ? .listed(model) : .custom
      }
      return editor
    }

    func row(for field: Field) -> Row {
      switch field {
      case .engineKey:
        .engineKey
      case .endpoint:
        .endpoint
      case .apiKey:
        .apiKey
      case .model:
        editor?.modelChoice == .custom ? .customModel : .model
      }
    }
  }

  enum Action: Equatable {
    case task
    case paneDisappeared
    case storedKeysRead([CredentialSlot: String])
    case profileSelected(ProfileID)
    case enabledToggled(Bool)
    case boostsVocabularyToggled(Bool)
    case timeoutSelected(TimeInterval)
    case instructionsEdited(String)
    case editTapped(Field)
    case resetTapped(Field)
    case endpointEdited(String)
    case keyEdited(String)
    case engineKeyEdited(String)
    case modelSelected(ModelChoice)
    case customModelEdited(String)
    case loadModelsTapped
    case modelsListed(discovered: URL?, ModelListing)
    case listingRefreshed(URL, [String])
    case saveTapped
    case saveSucceeded(Saved)
    case saveFailed(Failure)
    case cancelTapped
    case fieldFocusChanged(Row, Bool)
    case rowMoved(CursorMovement)
    case leftPressed
    case rightPressed
    case pressRequested
    case cursorHovered(Row)
    case assetsUpdated([ModelAsset: AssetState])
    case delegate(Delegate)

    // MARK: Internal

    enum Delegate: Equatable {
      /// A key the app reads when it needs it only has to be noticed.
      case keysStored(Set<CredentialSlot>)
    }
  }

  @Dependency(\.asrEngine) var asrEngine
  @Dependency(\.cleanup) var cleanupClient
  @Dependency(\.keychain) var keychain
  @Dependency(\.modelLibrary) var modelLibrary

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .task:
        let slots = Set(state.settings.profiles.lineup.flatMap(\.credentialSlots))
        let assets = Effect<Action>.run { send in
          for await states in modelLibrary.states() {
            await send(.assetsUpdated(states))
          }
        }
        .cancellable(id: CancelID.assets, cancelInFlight: true)
        return .merge(assets, .concatenate(
          .run { send in
            var stored: [CredentialSlot: String] = [:]
            for slot in slots {
              do {
                stored[slot] = try keychain.read(slot).map(Self.prefix)
              } catch {
                profilesPaneLogger.error(
                  "Key unreadable: \(error.localizedDescription, privacy: .public)",
                )
              }
            }
            await send(.storedKeysRead(stored))
          },
          refreshListing(state),
        ))
      // Leaving the pane is leaving the edit: a draft nobody can see is not one to keep.
      case .paneDisappeared:
        return discardEditor(&state)
      case let .storedKeysRead(keys):
        state.storedKeys = keys
        return .none
      case let .profileSelected(id):
        guard id != state.settings.profiles.active else {
          return .none
        }
        let discard = discardEditor(&state)
        state.$settings.withLock { $0.profiles.active = id }
        return .merge(discard, refreshListing(state))
      case let .enabledToggled(enabled):
        state.$settings.withLock { $0.profiles.custom.cleanupEnabled = enabled }
        return clampTarget(&state)
      case let .boostsVocabularyToggled(enabled):
        state.$settings.withLock { $0.profiles.custom.boostsVocabulary = enabled }
        return .none
      case let .timeoutSelected(timeout):
        state.$settings.withLock { $0.setCleanupTimeout(timeout) }
        return .none
      case let .instructionsEdited(text):
        state.instructions = text
        state.$settings.withLock { $0.additionalInstructions = text }
        return .none
      case let .editTapped(field):
        if state.editor == nil {
          state.editor = state.makeEditor()
        }
        state.editor?.requestFocus(field)
        state.cursor = Cursor(row: state.row(for: field))
        return .none
      // A reset is an edit back to the factory value, so it is proven like any other.
      case let .resetTapped(field):
        guard let factory = state.profile.factory else {
          return .none
        }
        var editor = state.makeEditor()
        switch field {
        case .endpoint:
          editor.endpointText = factory.endpoint.absoluteString
        case .model:
          editor.modelChoice =
            editor.listedModels.contains(factory.model) ? .listed(factory.model) : .custom
          editor.customModel = factory.model
        case .engineKey,
             .apiKey:
          preconditionFailure("A key has no factory value to reset to")
        }
        state.editor = editor
        return save(&state)
      case let .endpointEdited(text):
        state.editor?.endpointText = text
        return .none
      case let .keyEdited(text):
        state.editor?.keyText = text
        return .none
      case let .engineKeyEdited(text):
        state.editor?.engineKeyText = text
        return .none
      case let .modelSelected(choice):
        state.editor?.modelChoice = choice
        return clampTarget(&state)
      case let .customModelEdited(text):
        state.editor?.customModel = text
        return .none
      case .loadModelsTapped:
        guard let editor = state.editor, let slot = state.credential else {
          return .none
        }
        guard let endpoint = EndpointAddress.conform(editor.endpointText) else {
          state.editor?.listing = .unavailable("Enter the address first.")
          return .none
        }
        state.editor?.listing = .loading
        let candidates = EndpointAddress.candidates(for: endpoint)
        let model = editor.resolvedModel
        let typedKey = editor.keyText.typedSecret
        return .run { send in
          let apiKey = try typedKey ?? keychain.read(slot)
          let outcome = await probe(candidates, model: model) { configuration in
            switch await cleanupClient.listModels(configuration, apiKey) {
            case let .models(models):
              .answered(models)
            case .cancelled:
              .cancelled
            case let .unavailable(failure):
              .failed(failure)
            }
          }
          switch outcome {
          case let .answered(base, models):
            let discovered = base == endpoint ? nil : base
            guard !models.isEmpty else {
              await send(.modelsListed(
                discovered: discovered, .unavailable("This endpoint lists no models."),
              ))
              return
            }
            await send(.listingRefreshed(base, models.sorted()))
            await send(.modelsListed(discovered: discovered, .loaded(models.sorted())))
          case .cancelled:
            await send(.modelsListed(discovered: nil, .notLoaded))
          case let .exhausted(failures):
            let reason = candidates.count > 1 && failures.allSatisfy(\.isNotFound)
              ? "Couldn’t find an OpenAI-compatible API at that address."
              : "This endpoint doesn’t list its models."
            await send(.modelsListed(discovered: nil, .unavailable(reason)))
          }
        } catch: { error, send in
          profilesPaneLogger.error(
            "Key unreadable: \(error.localizedDescription, privacy: .public)",
          )
          await send(.modelsListed(
            discovered: nil, .unavailable("Couldn’t read the key from the Keychain."),
          ))
        }
        .cancellable(id: CancelID.listing, cancelInFlight: true)
      case let .modelsListed(discovered, listing):
        guard var editor = state.editor else {
          return .none
        }
        // Whatever base answered is the one Save will prove, so it is the one the field says.
        if let discovered {
          editor.endpointText = discovered.absoluteString
        }
        editor.listing = listing
        // A model already chosen is now a listed one, and one the listing no longer offers is
        // shown as what it now is: text. A listing that failed leaves the Custom field open with
        // what was typed still in it.
        let model = editor.resolvedModel
        if case let .loaded(models) = listing, models.contains(model) {
          editor.modelChoice = .listed(model)
        } else if listing != .loading, listing != .notLoaded {
          editor.customModel = model
          editor.modelChoice = .custom
        }
        state.editor = editor
        return clampTarget(&state)
      // The quiet refresh only ever adds what the cache lacked; it never takes over a listing the
      // user is waiting on, and never says anything when it fails.
      case let .listingRefreshed(endpoint, models):
        state.$modelListings.withLock { $0[endpoint.absoluteString] = models }
        guard let editor = state.editor,
              EndpointAddress.conform(editor.endpointText) == endpoint,
              editor.listing != .loading
        else {
          return .none
        }
        return .send(.modelsListed(discovered: nil, .loaded(models)))
      case .saveTapped:
        return save(&state)
      case let .saveSucceeded(saved):
        let id = state.profile.id
        let wasSetUp = state.isSetUp
        state.$settings.withLock {
          $0.profiles.setEndpoint(saved.endpoint, for: id)
          $0.profiles.setModel(saved.model, for: id)
          // Setting Custom up is asking for its cleanup; turning it off later is a separate say.
          if id == .custom, !wasSetUp {
            $0.profiles.custom.cleanupEnabled = true
          }
        }
        state.storedKeys = (state.storedKeys ?? [:]).merging(saved.storedKeys) { $1 }
        // The endpoint just answered with this key, whatever the last dictation was told.
        if let slot = state.credential {
          state.$health.withLock { _ = $0.rejectedKeys.remove(slot) }
        }
        state.editor = nil
        state.editingField = nil
        _ = clampTarget(&state)
        guard !saved.storedKeys.isEmpty else {
          return .none
        }
        return .send(.delegate(.keysStored(Set(saved.storedKeys.keys))))
      case let .saveFailed(failure):
        guard state.editor?.isChecking == true else {
          return .none
        }
        state.editor?.isChecking = false
        state.editor?.failure = failure
        state.editor?.requestFocus(failure.field)
        state.cursor = Cursor(row: state.row(for: failure.field))
        return .none
      // The first Cancel stops a check and keeps what was typed; the next one throws it away.
      case .cancelTapped:
        guard state.editor?.isChecking != true else {
          state.editor?.isChecking = false
          return .cancel(id: CancelID.verification)
        }
        return discardEditor(&state)
      case let .fieldFocusChanged(row, isFocused):
        if isFocused {
          state.editingField = row
          state.cursor = Cursor(row: row)
        } else if state.editingField == row {
          state.editingField = nil
        }
        return .none
      case let .rowMoved(movement):
        let rows = state.rows
        guard let current = rows.firstIndex(of: state.cursorRow) else {
          return .none
        }
        let offset = movement == .next ? 1 : -1
        state.cursor = Cursor(row: rows[min(max(current + offset, 0), rows.count - 1)])
        return .none
      case .leftPressed:
        state.cursor.target = max(state.cursor.target - 1, 0)
        return .none
      case .rightPressed:
        state.cursor.target = min(state.cursor.target + 1, state.targets.count - 1)
        return .none
      case .pressRequested:
        switch state.cursorTarget {
        case .profile:
          state.profileActivation += 1
          return .none
        case .enabled:
          return .send(.enabledToggled(!state.settings.profiles.custom.cleanupEnabled))
        case let .edit(field):
          return .send(.editTapped(field))
        case let .reset(field):
          return .send(.resetTapped(field))
        case .field(.model):
          state.modelActivation += 1
          return .none
        case let .field(field):
          state.editor?.requestFocus(field)
          return .none
        case .customModel:
          state.editor?.requestFocus(.model)
          return .none
        case .loadModels:
          return .send(.loadModelsTapped)
        case .setUp:
          return .send(.editTapped(.endpoint))
        case .cancel:
          return .send(.cancelTapped)
        case .save:
          return .send(.saveTapped)
        case .boostsVocabulary:
          return .send(.boostsVocabularyToggled(!state.settings.profiles.custom.boostsVocabulary))
        case .timeout:
          state.timeoutActivation += 1
          return .none
        case .instructions:
          state.instructionsActivation += 1
          return .none
        }
      case let .cursorHovered(row):
        state.cursor = Cursor(row: row)
        return .none
      case let .assetsUpdated(assets):
        state.assets = assets
        return .none
      case .delegate:
        return .none
      }
    }
  }

  // MARK: Private

  /// How one candidate base answered a question. The client's two questions return different
  /// shapes for the same three outcomes, so the pane names the three once.
  private enum Answer<Success> {
    case answered(Success)
    case cancelled
    case failed(CleanupFailure)
  }

  /// What walking the candidate bases came to.
  private enum Probe<Success> {
    case answered(URL, Success)
    case cancelled
    case exhausted([CleanupFailure])
  }

  private enum CancelID {
    case verification
    case listing
    case refresh
    case assets
  }

  private static func prefix(of key: String) -> String {
    String(key.prefix(6))
  }

  /// Save proves the endpoint, not a dictation, so it runs on the verification budget rather than
  /// the user's own time limit, and the prompt's instructions have no bearing on it.
  private static func configuration(endpoint: URL, model: String) -> CleanupConfiguration {
    CleanupConfiguration(
      endpoint: endpoint, model: model, timeout: CleanupConfiguration.verificationTimeout,
      additionalInstructions: "",
    )
  }

  /// One sentence under the one field it blames. A bare host that answered nowhere is a failure
  /// of discovery, and a 404 while probing only says "not here"; any other failure is the
  /// endpoint speaking, and it is reported as itself.
  private static func failure(
    _ failures: [CleanupFailure], endpoint: URL, model: String, sentKey: Bool,
  ) -> Failure {
    let host = endpoint.port.map { "\(endpoint.host() ?? ""):\($0)" } ?? endpoint.host() ?? ""
    let speaking = failures.first { !$0.isNotFound }
    guard let failure = speaking ?? failures.first else {
      return Failure(field: .endpoint, message: "That endpoint didn’t answer.")
    }
    if failure.rejectsKey {
      return sentKey
        ? Failure(field: .apiKey, message: "Invalid key.")
        : Failure(field: .apiKey, message: "This endpoint needs an API key.")
    }
    switch failure {
    case .unreachable,
         .timedOut:
      return Failure(field: .endpoint, message: "Couldn’t reach \(host).")
    case let .httpStatus(404, message):
      if message?.localizedCaseInsensitiveContains("model") == true {
        return Failure(field: .model, message: "\(host) has no model ‘\(model)’.")
      }
      return Failure(
        field: .endpoint, message: failures.count > 1
          ? "Couldn’t find an OpenAI-compatible API at that address."
          : "\(host) has no chat completions endpoint.",
      )
    case let .httpStatus(code, message):
      return Failure(
        field: .endpoint, message: message ?? "That endpoint answered with HTTP \(code).",
      )
    case .degenerateResponse,
         .malformedResponse,
         .localModel:
      return Failure(
        field: .endpoint, message: "That endpoint didn’t answer like an OpenAI-compatible one.",
      )
    }
  }

  /// Proves the draft, and only then stores it: the keys first, then the address and model the
  /// endpoint answered at. A draft that does not answer leaves everything as it was. A stored key
  /// was proven when it was stored, so only a typed one is checked.
  private func save(_ state: inout State) -> Effect<Action> {
    guard var editor = state.editor, !editor.isChecking, let slot = state.credential else {
      return .none
    }
    func fail(_ field: Field, _ message: String) -> Effect<Action> {
      editor.failure = Failure(field: field, message: message)
      editor.requestFocus(field)
      state.editor = editor
      state.cursor = Cursor(row: state.row(for: field))
      return .none
    }
    guard let endpoint = EndpointAddress.conform(editor.endpointText) else {
      return fail(.endpoint, "Enter an address like https://gateway.example/v1.")
    }
    let model = editor.resolvedModel
    guard !model.isEmpty else {
      return fail(.model, "Choose a model, or enter one.")
    }
    editor.endpointText = endpoint.absoluteString
    editor.isChecking = true
    editor.failure = nil
    state.editor = editor
    let engine = state.profile.engine
    let engineSlot = state.engineCredential
    let typedEngineKey = editor.engineKeyText.typedSecret
    let typedKey = editor.keyText.typedSecret
    let candidates = EndpointAddress.candidates(for: endpoint)
    return .run { send in
      if let engineSlot {
        let provider = engineSlot.provider.displayName
        if let typedEngineKey {
          do {
            try await asrEngine.verifyKey(engine, typedEngineKey)
          } catch ASREngineError.credentialRejected {
            await send(.saveFailed(Failure(field: .engineKey, message: "Invalid key.")))
            return
          } catch is URLError {
            await send(.saveFailed(Failure(
              field: .engineKey, message: "Couldn’t reach \(provider).",
            )))
            return
          } catch {
            profilesPaneLogger.error(
              "Engine key check failed: \(error.localizedDescription, privacy: .public)",
            )
            await send(.saveFailed(Failure(
              field: .engineKey, message: "Couldn’t check the key with \(provider).",
            )))
            return
          }
        } else if try keychain.read(engineSlot) == nil {
          await send(.saveFailed(Failure(
            field: .engineKey, message: "Paste your \(provider) key.",
          )))
          return
        }
      }
      let apiKey = try typedKey ?? keychain.read(slot)
      if apiKey == nil, slot.provider != .endpoint {
        await send(.saveFailed(Failure(
          field: .apiKey, message: "Paste your \(slot.provider.displayName) key.",
        )))
        return
      }
      let outcome = await probe(candidates, model: model) { configuration in
        switch await cleanupClient.verify(configuration, apiKey) {
        case .verified:
          .answered(())
        case .cancelled:
          .cancelled
        case let .failed(failure):
          .failed(failure)
        }
      }
      switch outcome {
      case let .answered(base, _):
        var stored: [CredentialSlot: String] = [:]
        do {
          if let engineSlot, let typedEngineKey {
            try keychain.store(typedEngineKey, engineSlot)
            stored[engineSlot] = Self.prefix(of: typedEngineKey)
          }
          if let typedKey {
            try keychain.store(typedKey, slot)
            stored[slot] = Self.prefix(of: typedKey)
          }
        } catch {
          profilesPaneLogger.error(
            "Key unstorable: \(error.localizedDescription, privacy: .public)",
          )
          await send(.saveFailed(Failure(
            field: stored.isEmpty && typedEngineKey != nil ? .engineKey : .apiKey,
            message: "Couldn’t store the key in the Keychain.",
          )))
          return
        }
        await send(.saveSucceeded(Saved(endpoint: base, model: model, storedKeys: stored)))
      case .cancelled:
        return
      case let .exhausted(failures):
        await send(.saveFailed(
          Self.failure(failures, endpoint: endpoint, model: model, sentKey: apiKey != nil),
        ))
      }
    } catch: { error, send in
      profilesPaneLogger.error("Key unreadable: \(error.localizedDescription, privacy: .public)")
      await send(.saveFailed(Failure(
        field: .apiKey, message: "Couldn’t read the key from the Keychain.",
      )))
    }
    .cancellable(id: CancelID.verification, cancelInFlight: true)
  }

  /// Tries each candidate base in turn and stops at the first that answers. Whichever base that
  /// is comes back with the answer, because it is the base the client will use from here on.
  private func probe<Success>(
    _ candidates: [URL], model: String,
    ask: (CleanupConfiguration) async -> Answer<Success>,
  ) async -> Probe<Success> {
    var failures: [CleanupFailure] = []
    for base in candidates {
      switch await ask(Self.configuration(endpoint: base, model: model)) {
      case let .answered(success):
        return .answered(base, success)
      case .cancelled:
        return .cancelled
      case let .failed(failure):
        profilesPaneLogger.error(
          """
          Cleanup probe failed at \(base.absoluteString, privacy: .public): \
          \(failure.localizedDescription, privacy: .public)
          """,
        )
        failures.append(failure)
      }
    }
    return .exhausted(failures)
  }

  /// Refetches the active endpoint's listing behind the cached one, quietly: a gateway that cannot
  /// list its models has nothing to report to a user who never asked it to.
  private func refreshListing(_ state: State) -> Effect<Action> {
    guard let leg = state.profile.endpointLeg, let endpoint = leg.endpoint else {
      return .none
    }
    let configuration = Self.configuration(endpoint: endpoint, model: leg.model ?? "")
    return .run { send in
      let apiKey = (try? keychain.read(leg.credential)) ?? nil
      // A factory endpoint will only refuse a request without its key.
      if apiKey == nil, leg.credential.provider != .endpoint {
        return
      }
      guard case let .models(models) = await cleanupClient.listModels(configuration, apiKey),
            !models.isEmpty
      else {
        return
      }
      await send(.listingRefreshed(endpoint, models.sorted()))
    }.cancellable(id: CancelID.refresh, cancelInFlight: true)
  }

  private func discardEditor(_ state: inout State) -> Effect<Action> {
    state.editor = nil
    state.editingField = nil
    _ = clampTarget(&state)
    return .merge(.cancel(id: CancelID.verification), .cancel(id: CancelID.listing))
  }

  private func clampTarget(_ state: inout State) -> Effect<Action> {
    state.cursor.target = min(state.cursor.target, state.targets.count - 1)
    return .none
  }
}

private extension Profile {
  /// Every slot the profile could hold a key in, whether or not its cleanup is on.
  var credentialSlots: [CredentialSlot] {
    [engineCredential, endpointLeg?.credential].compactMap(\.self)
  }
}

private extension CleanupFailure {
  var isNotFound: Bool {
    if case .httpStatus(404, _) = self {
      return true
    }
    return false
  }
}

private extension String {
  /// A pasted key, or nil when nothing new was typed.
  var typedSecret: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
