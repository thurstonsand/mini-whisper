import AppSettings
import ComposableArchitecture
import Foundation
import OSLog
import TranscriptCleanup

private let cleanupPaneLogger = Logger(
  subsystem: "com.thurstonsand.MiniWhisper", category: "cleanup-pane",
)

// MARK: - CleanupFeature

/// The Cleanup pane: the endpoint, the key, the model, and the promise that none of it can cost a
/// dictation. The toggle and the time limit write straight through to settings, because they are
/// answerable on their own; everything the endpoint needs together is written by Save, which is
/// also the only thing that proves the three of them work.
@Reducer struct CleanupFeature {
  // MARK: Internal

  enum CursorMovement: Equatable {
    case previous
    case next
  }

  enum Row: Hashable {
    case enabled
    case timeout
    case endpoint
    case apiKey
    case model
    case customModel
    case instructions
  }

  enum Target: Equatable {
    case enabled
    case timeout
    case endpoint
    case apiKey
    case replaceKey
    case model
    case loadModels
    case customModel
    case save
    case instructions
  }

  /// What the pane knows about the key in the Keychain. Existence is read from the Keychain
  /// itself, never from settings, so the file and the keychain cannot disagree.
  enum KeyState: Equatable {
    case unknown
    case missing
    /// Evidence rather than content: enough of the key to recognise it, and no way to edit it in
    /// place, because a half-edited secret is a secret that no longer works.
    case stored(prefix: String)
    case editing(String)
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

  enum SaveState: Equatable {
    case idle
    case saving
    case saved
    case failed(String)
  }

  enum SaveButton: Equatable {
    case idle
    case armed
    case checking
    case confirmed

    // MARK: Internal

    var title: String {
      switch self {
      case .idle,
           .armed:
        "Save"
      case .checking:
        "Checking…"
      case .confirmed:
        "Saved"
      }
    }

    var isPressable: Bool {
      self == .armed
    }
  }

  struct Cursor: Equatable {
    var row: Row?
    var target = 0
  }

  @ObservableState struct State: Equatable {
    // MARK: Lifecycle

    init(settings: Shared<MiniWhisperSettings>) {
      _settings = settings
      endpointText = EndpointAddress.display(settings.wrappedValue.cleanup.endpoint)
      instructions = settings.wrappedValue.cleanup.additionalInstructions
      // Before a listing exists there is no list to have chosen from, so a stored model is shown
      // as what it is: text the user entered.
      customModel = settings.wrappedValue.cleanup.model ?? ""
      modelChoice = .custom
    }

    // MARK: Internal

    static let timeoutPresets: [TimeInterval] = [5, 10, 20, 30]

    @Shared var settings: MiniWhisperSettings
    var endpointText: String
    var customModel: String
    var instructions: String
    var modelChoice: ModelChoice
    var key = KeyState.unknown
    var listing = ModelListing.notLoaded
    var save = SaveState.idle
    /// Whether anything Save would write has been touched since the last confirmation. It is
    /// what arms the button: the endpoint's facts are only ever written together, so any one of
    /// them being edited is the whole section becoming unsaved.
    var isEndpointDirty = false
    var cursor = Cursor()
    /// The field the user is typing in, if any. The window's letter keys are the pane's grammar
    /// everywhere except inside a field, where they are just letters.
    var editingField: Row?
    /// Return has to reach controls that only answer to a click or a first-responder change, and
    /// a view cannot be told to do the same thing twice by a value that stays the same.
    var timeoutActivation = 0
    var modelActivation = 0
    var endpointActivation = 0
    var keyActivation = 0
    var instructionsActivation = 0

    var isEnabled: Bool {
      settings.cleanup.enabled
    }

    var isEditingField: Bool {
      editingField != nil
    }

    /// A failure leaves something still to save, so it is not a state of the button: the button
    /// stays armed and the sentence goes under the table.
    var saveButton: SaveButton {
      if save == .saving {
        return .checking
      }
      if isEndpointDirty {
        return .armed
      }
      return save == .saved ? .confirmed : .idle
    }

    var timeout: TimeInterval {
      settings.cleanup.timeout
    }

    var listedModels: [String] {
      guard case let .loaded(models) = listing else {
        return []
      }
      return models
    }

    /// The model Save would write: whichever of the two fields the choice points at.
    var resolvedModel: String {
      switch modelChoice {
      case let .listed(model):
        model
      case .custom:
        customModel.trimmingCharacters(in: .whitespacesAndNewlines)
      }
    }

    var rows: [Row] {
      var rows: [Row] = [.enabled, .timeout, .endpoint, .apiKey, .model]
      if modelChoice == .custom {
        rows.append(.customModel)
      }
      rows.append(.instructions)
      return rows
    }

    var cursorRow: Row {
      guard let row = cursor.row, rows.contains(row) else {
        return rows[0]
      }
      return row
    }

    var targets: [Target] {
      switch cursorRow {
      case .enabled:
        [.enabled]
      case .timeout:
        [.timeout]
      case .endpoint:
        [.endpoint]
      case .apiKey:
        if case .stored = key {
          [.apiKey, .replaceKey]
        } else {
          [.apiKey]
        }
      case .model:
        [.model, .loadModels, .save]
      case .customModel:
        [.customModel]
      case .instructions:
        [.instructions]
      }
    }

    var cursorTarget: Target {
      targets[min(cursor.target, targets.count - 1)]
    }
  }

  enum Action: Equatable {
    case task
    case keyRead(String?)
    case keyReadFailed(String)
    case enabledToggled(Bool)
    case timeoutSelected(TimeInterval)
    case endpointEdited(String)
    case keyEdited(String)
    case replaceKeyTapped
    case modelSelected(ModelChoice)
    case customModelEdited(String)
    case instructionsEdited(String)
    case loadModelsTapped
    case modelsListed(ModelListing)
    case saveTapped
    case saveCompleted(SaveState)
    case endpointDiscovered(URL)
    case fieldFocusChanged(Row, Bool)
    case rowMoved(CursorMovement)
    case leftPressed
    case rightPressed
    case pressRequested
    case cursorHovered(Row)
  }

  @Dependency(\.cleanup) var cleanupClient
  @Dependency(\.keychain) var keychain

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .task:
        return .run { send in
          do {
            try await send(.keyRead(keychain.read(.cleanupAPIKey)))
          } catch {
            await send(.keyReadFailed(error.localizedDescription))
          }
        }
      case let .keyRead(key):
        state.key = key.map { .stored(prefix: Self.prefix(of: $0)) } ?? .missing
        return .none
      case let .keyReadFailed(message):
        cleanupPaneLogger.error("Cleanup key unreadable: \(message, privacy: .public)")
        // The pane is where a broken keychain is visible; the pill never mentions it.
        state.key = .missing
        state.save = .failed("Couldn’t read the key from the Keychain.")
        return .none
      case let .enabledToggled(enabled):
        state.$settings.withLock { $0.cleanup.enabled = enabled }
        return .none
      case let .timeoutSelected(timeout):
        state.$settings.withLock { $0.cleanup.setTimeout(timeout) }
        return .none
      case let .endpointEdited(text):
        state.endpointText = text
        return arm(&state)
      case let .keyEdited(text):
        state.key = .editing(text)
        return arm(&state)
      case .replaceKeyTapped:
        state.key = .editing("")
        _ = arm(&state)
        // Replace exists to type a new key, so it hands the field the keys — the click path as
        // much as the keyboard one, which is what a ⌘V straight after the button expects.
        state.keyActivation += 1
        // The row's second target belonged to the Replace button, which no longer exists.
        return clampTarget(&state)
      case let .modelSelected(choice):
        state.modelChoice = choice
        _ = arm(&state)
        return clampTarget(&state)
      case let .customModelEdited(text):
        state.customModel = text
        return arm(&state)
      case let .instructionsEdited(text):
        state.instructions = text
        state.$settings.withLock { $0.cleanup.additionalInstructions = text }
        return .none
      case .loadModelsTapped:
        guard let endpoint = EndpointAddress.conform(state.endpointText) else {
          state.listing = .unavailable("Enter the endpoint address first.")
          return .none
        }
        state.listing = .loading
        let candidates = EndpointAddress.candidates(for: endpoint)
        let model = state.resolvedModel
        let typedKey = state.typedKey
        let typedAddress = state.endpointText
        return .run { send in
          let apiKey: String
          switch lookUpKey(typed: typedKey) {
          case let .key(key):
            apiKey = key
          case let .unavailable(reason):
            await send(.modelsListed(.unavailable(reason)))
            return
          }
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
            if base.absoluteString != typedAddress {
              await send(.endpointDiscovered(base))
            }
            await send(.modelsListed(models.isEmpty
                ? .unavailable("This endpoint lists no models.")
                : .loaded(models.sorted())))
          case .cancelled:
            await send(.modelsListed(.notLoaded))
          case let .exhausted(failures):
            await send(
              .modelsListed(
                .unavailable(
                  Self.discoveryMessage(
                    failures, candidates: candidates,
                    exhausted: "Couldn’t find an OpenAI-compatible API at that address.",
                    single: "This endpoint doesn’t list its models.",
                  ),
                ),
              ),
            )
          }
        }
      case let .modelsListed(listing):
        state.listing = listing
        // A model already chosen is now a listed one; a listing that failed leaves the Custom
        // field open with what was typed still in it.
        if case let .loaded(models) = listing, models.contains(state.resolvedModel) {
          state.modelChoice = .listed(state.resolvedModel)
        } else if case .unavailable = listing {
          state.modelChoice = .custom
        }
        return clampTarget(&state)
      case .saveTapped:
        guard let endpoint = EndpointAddress.conform(state.endpointText) else {
          state.save = .failed("Enter an address like https://gateway.example/v1.")
          return .none
        }
        let model = state.resolvedModel
        guard !model.isEmpty else {
          state.save = .failed("Choose a model, or enter one.")
          return .none
        }
        let typedKey = state.typedKey
        if case let .editing(text) = state.key,
           text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
          state.save = .failed("Paste your API key.")
          return .none
        }
        // What the user typed is kept whether or not the endpoint answers: a settings file that
        // silently discards an edit is worse than one that holds an address needing a fix.
        state.endpointText = endpoint.absoluteString
        state.$settings.withLock {
          $0.cleanup.endpoint = endpoint
          $0.cleanup.model = model
          $0.cleanup.additionalInstructions = state.instructions
        }
        state.save = .saving
        let candidates = EndpointAddress.candidates(for: endpoint)
        let typedAddress = state.endpointText
        return .run { send in
          if let typedKey {
            do {
              try keychain.store(typedKey, .cleanupAPIKey)
            } catch {
              await send(
                .saveCompleted(.failed("Couldn’t store the key in the Keychain.")),
              )
              return
            }
          }
          // Read back rather than trusting the write: the Keychain is what the pipeline will
          // ask, so it is what has to answer here.
          let apiKey: String
          switch lookUpKey(typed: nil) {
          case let .key(key):
            apiKey = key
          case let .unavailable(reason):
            await send(.saveCompleted(.failed(reason)))
            return
          }
          await send(.keyRead(apiKey))
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
            if base.absoluteString != typedAddress {
              await send(.endpointDiscovered(base))
            }
            await send(.saveCompleted(.saved))
          case .cancelled:
            await send(.saveCompleted(.idle))
          case let .exhausted(failures):
            await send(
              .saveCompleted(
                .failed(
                  Self.discoveryMessage(
                    failures, candidates: candidates,
                    exhausted: "Couldn’t find an OpenAI-compatible API at that address.",
                    single: failures.first.map(Self.message) ?? "That endpoint didn’t answer.",
                  ),
                ),
              ),
            )
          }
        }.cancellable(id: CancelID.verification, cancelInFlight: true)
      case let .saveCompleted(result):
        state.save = result
        // Only a confirmation disarms the button. A failure leaves the facts unsaved, which is
        // exactly the state the armed button is for.
        if result == .saved {
          state.isEndpointDirty = false
        }
        return .none
      // Whatever base answered is the one the client will use, so it is the one the field and
      // the settings file say.
      case let .endpointDiscovered(endpoint):
        state.endpointText = endpoint.absoluteString
        state.$settings.withLock { $0.cleanup.endpoint = endpoint }
        return .none
      case let .fieldFocusChanged(row, isFocused):
        if isFocused {
          state.editingField = row
          state.cursor.row = row
          state.cursor.target = 0
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
        state.cursor.row = rows[min(max(current + offset, 0), rows.count - 1)]
        state.cursor.target = 0
        return .none
      case .leftPressed:
        state.cursor.target = max(state.cursor.target - 1, 0)
        return .none
      case .rightPressed:
        state.cursor.target = min(state.cursor.target + 1, state.targets.count - 1)
        return .none
      case .pressRequested:
        switch state.cursorTarget {
        case .enabled:
          return .send(.enabledToggled(!state.isEnabled))
        case .timeout:
          state.timeoutActivation += 1
          return .none
        case .endpoint:
          state.endpointActivation += 1
          return .none
        case .apiKey:
          guard case .stored = state.key else {
            state.keyActivation += 1
            return .none
          }
          return .send(.replaceKeyTapped)
        case .replaceKey:
          return .send(.replaceKeyTapped)
        case .model:
          state.modelActivation += 1
          return .none
        case .loadModels:
          return .send(.loadModelsTapped)
        case .customModel:
          state.modelActivation += 1
          return .none
        case .save:
          // The keyboard cannot press what the pointer cannot: a button with nothing to save is
          // disabled in both grammars.
          guard state.saveButton.isPressable else {
            return .none
          }
          return .send(.saveTapped)
        case .instructions:
          state.instructionsActivation += 1
          return .none
        }
      case let .cursorHovered(row):
        state.cursor.row = row
        state.cursor.target = 0
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

  /// The key a request should go out with, or the sentence to show instead. An empty Keychain
  /// and a broken one are different facts, and the difference is the whole of what the user
  /// should do next.
  private enum KeyLookup {
    case key(String)
    case unavailable(String)
  }

  private enum CancelID { case verification }

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

  /// A bare host that answered nowhere is a different fact from a base the user named that could
  /// not list its models, and only the first one is a failure of discovery. A 404 while probing
  /// says "not here", so it is never allowed to stand for what the endpoint can do; any other
  /// failure is the endpoint speaking, and it is reported as itself.
  private static func discoveryMessage(
    _ failures: [CleanupFailure], candidates: [URL], exhausted: String, single: String,
  ) -> String {
    guard candidates.count > 1 else {
      return single
    }
    let speaking = failures.first {
      if case .httpStatus(404, _) = $0 {
        false
      } else {
        true
      }
    }
    return speaking.map(message) ?? exhausted
  }

  /// One sentence the user can act on. The package's own descriptions name the mechanism; this
  /// row has room for the consequence.
  private static func message(for failure: CleanupFailure) -> String {
    switch failure {
    case .unreachable:
      "Couldn’t reach that address."
    case let .httpStatus(code, message):
      switch code {
      case 401,
           403:
        "That endpoint rejected the key."
      case 404:
        "That address has no chat completions endpoint."
      default:
        message ?? "That endpoint answered with HTTP \(code)."
      }
    case .timedOut:
      "That endpoint didn’t answer in time."
    case .degenerateResponse,
         .malformedResponse:
      "That endpoint didn’t answer like an OpenAI-compatible one."
    }
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
        cleanupPaneLogger.error(
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

  private func lookUpKey(typed: String?) -> KeyLookup {
    if let typed {
      return .key(typed)
    }
    do {
      guard let stored = try keychain.read(.cleanupAPIKey) else {
        return .unavailable("Add an API key first.")
      }
      return .key(stored)
    } catch {
      cleanupPaneLogger.error(
        "Cleanup key unreadable: \(error.localizedDescription, privacy: .public)",
      )
      return .unavailable("Couldn’t read the key from the Keychain.")
    }
  }

  /// An edit to any endpoint fact re-arms Save and retires whatever the last press claimed.
  private func arm(_ state: inout State) -> Effect<Action> {
    state.isEndpointDirty = true
    state.save = .idle
    return .none
  }

  private func clampTarget(_ state: inout State) -> Effect<Action> {
    state.cursor.target = min(state.cursor.target, state.targets.count - 1)
    return .none
  }
}

private extension CleanupFeature.State {
  /// The key as it is being typed, or nil when there is nothing new to store.
  var typedKey: String? {
    guard case let .editing(text) = key else {
      return nil
    }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
