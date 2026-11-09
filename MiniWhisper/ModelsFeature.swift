import AppSettings
import ASREngine
import ComposableArchitecture
import Foundation
import ModelLibrary
import OSLog

private let modelsPaneLogger = Logger(
  subsystem: "com.thurstonsand.MiniWhisper", category: "models-pane",
)

// MARK: - ModelsFeature

/// The Models pane: every profile wired to what it runs on, and the one home for what is on disk.
/// Nothing is deleted implicitly, so this is the only place a model goes away.
@Reducer struct ModelsFeature {
  // MARK: Internal

  enum CursorMovement: Equatable {
    case previous
    case next
  }

  enum Row: Hashable {
    case profile(ProfileID)
    case asset(ModelAsset)
    case key(Component)
  }

  /// Something a profile's leg runs on: a model on this Mac, or a service off it.
  enum Component: Hashable {
    case asset(ModelAsset)
    case scribe
    /// A profile's own endpoint. Each factory profile has its own provider, and Custom has the
    /// user's.
    case endpoint(ProfileID)
  }

  enum Leg: Hashable {
    case speech
    case cleanup
  }

  @ObservableState struct State: Equatable {
    // MARK: Lifecycle

    init(settings: Shared<MiniWhisperSettings>, health: Shared<AppHealth>) {
      _settings = settings
      _health = health
    }

    // MARK: Internal

    @Shared var settings: MiniWhisperSettings
    @Shared var health: AppHealth
    /// Empty until the library first answers, and an asset nobody has heard about yet is not
    /// reported missing.
    var assets: [ModelAsset: AssetState] = [:]
    /// The asset whose deletion is waiting on the user, because the active profile needs it.
    var pendingDeletion: ModelAsset?
    /// What the last Delete or Download could not do.
    var assetFailure: String?
    var cursor: Row?
    var previewProfile: ProfileID?
    var isKeyboardPreview = false
    var storedKeys: Set<CredentialSlot>?

    var rows: [Row] {
      ProfileID.allCases.map(Row.profile)
        + ModelAsset.allCases.filter { isDeletable($0) || isDownloadable($0) }.map(Row.asset)
        + ([Component.scribe] + settings.profiles
          .lineup
          .filter { $0.endpointLeg != nil }
          .map { .endpoint($0.id) })
        .filter { keyProblem($0) != nil }
        .map(Row.key)
    }

    var cursorRow: Row {
      guard let cursor, rows.contains(cursor) else {
        return .profile(settings.profiles.active)
      }
      return cursor
    }

    func uses(_ component: Component, profile id: ProfileID) -> Bool {
      let profile = settings.profiles.profile(id)
      return [.speech, .cleanup].contains { self.component($0, of: profile) == component }
    }

    func keyProblem(_ component: Component) -> String? {
      let slot: CredentialSlot
      switch component {
      case .asset:
        return nil
      case .scribe:
        slot = CredentialSlot(profile: .accurate, provider: .elevenlabs)
      case let .endpoint(id):
        guard let leg = settings.profiles.profile(id).endpointLeg else {
          return nil
        }
        slot = leg.credential
      }
      if health.rejectedKeys.contains(slot) {
        return "Key rejected"
      }
      if slot.profile == .custom {
        return nil
      }
      return storedKeys.map { $0.contains(slot) ? nil : "No key" } ?? nil
    }

    func isBroken(_ component: Component) -> Bool {
      if case let .asset(asset) = component {
        return assets[asset]?.isInstalled == false
      }
      return keyProblem(component) != nil
    }

    func component(_ leg: Leg, of profile: Profile) -> Component? {
      switch leg {
      case .speech:
        profile.engine == .scribe ? .scribe : .asset(.parakeet)
      case .cleanup:
        switch profile.cleanup {
        case .none:
          nil
        case .local:
          .asset(.s1Mini)
        case .endpoint:
          .endpoint(profile.id)
        }
      }
    }

    /// Who needs the asset, short enough for a row: one profile by name, more by count. The wires
    /// say which ones.
    func users(of asset: ModelAsset) -> String {
      let users = settings.profiles.lineup.filter { $0.assets.contains(asset) }
      switch users.count {
      case 1:
        return users[0].name
      case ProfileID.allCases.count:
        return "Every profile"
      default:
        return "\(users.count) profiles"
      }
    }

    /// Only an installed asset can be deleted, and not one any engine is loading right now:
    /// pulling its files mid-compile would turn a setup into a failure, and a setup outlives a
    /// switch to another profile.
    func isDeletable(_ asset: ModelAsset) -> Bool {
      guard assets[asset]?.isInstalled == true else {
        return false
      }
      return !SpeechEngine.allCases.contains {
        $0.assets.contains(asset) && health.readinessByEngine[$0]?.isSetupInProgress == true
      }
    }

    func isDownloadable(_ asset: ModelAsset) -> Bool {
      assets[asset]?.isDownloadable == true
    }

    /// Losing what the active profile runs on is the one deletion worth a question.
    func asksBeforeDeleting(_ asset: ModelAsset) -> Bool {
      settings.activeProfile.assets.contains(asset)
    }
  }

  enum Action: Equatable {
    case task
    case assetsUpdated([ModelAsset: AssetState])
    case storedKeysRead(Set<CredentialSlot>)
    case cursorHovered(Row)
    case pointerExited
    case previewCleared
    case rowMoved(CursorMovement)
    case pressRequested
    case keyTapped(Component)
    case deleteTapped(ModelAsset)
    case downloadTapped(ModelAsset)
    case deletionConfirmed
    case deletionCancelled
    case assetDeletionFailed(String)
    case assetDownloadFailed(String)
    case delegate(Delegate)

    // MARK: Internal

    enum Delegate: Equatable {
      /// The app owns deletion, because the engine has to let go of an asset before its files go.
      case deleteAsset(ModelAsset)
      /// The app owns downloads too: one the active engine needs is its repair, not the pane's.
      case downloadAsset(ModelAsset)
    }
  }

  @Dependency(\.modelLibrary) var modelLibrary
  @Dependency(\.keychain) var keychain

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .task:
        let slots = Set(state.settings.profiles.lineup.flatMap {
          [$0.engineCredential, $0.endpointLeg?.credential].compactMap(\.self)
        })
        let assets = Effect<Action>.run { send in
          for await states in modelLibrary.states() {
            await send(.assetsUpdated(states))
          }
        }
        .cancellable(id: CancelID.assets, cancelInFlight: true)
        return .merge(assets, .run { send in
          var stored: Set<CredentialSlot> = []
          for slot in slots {
            do {
              if try keychain.read(slot) != nil {
                stored.insert(slot)
              }
            } catch {
              modelsPaneLogger
                .error("Key unreadable: \(error.localizedDescription, privacy: .public)")
            }
          }
          await send(.storedKeysRead(stored))
        })
      case let .assetsUpdated(assets):
        state.assets = assets
        return .none
      case let .storedKeysRead(keys):
        state.storedKeys = keys
        return .none
      case let .cursorHovered(row):
        guard state.rows.contains(row) else {
          return .none
        }
        state.isKeyboardPreview = false
        move(&state, to: row)
        return .none
      case .pointerExited:
        if !state.isKeyboardPreview {
          state.previewProfile = nil
        }
        return .none
      case .previewCleared:
        state.previewProfile = nil
        return .none
      case let .rowMoved(movement):
        let rows = state.rows
        guard let current = rows.firstIndex(of: state.cursorRow) else {
          return .none
        }
        let offset = movement == .next ? 1 : -1
        state.isKeyboardPreview = true
        move(&state, to: rows[min(max(current + offset, 0), rows.count - 1)])
        return .none
      case .pressRequested:
        switch state.cursorRow {
        case .profile:
          return .none
        case let .key(component):
          return .send(.keyTapped(component))
        case let .asset(asset):
          return .send(state.isDownloadable(asset) ? .downloadTapped(asset) : .deleteTapped(asset))
        }
      case let .downloadTapped(asset):
        state.assetFailure = nil
        return .send(.delegate(.downloadAsset(asset)))
      case let .deleteTapped(asset):
        state.assetFailure = nil
        guard state.asksBeforeDeleting(asset) else {
          return .send(.delegate(.deleteAsset(asset)))
        }
        state.pendingDeletion = asset
        return .none
      case .deletionConfirmed:
        guard let asset = state.pendingDeletion else {
          return .none
        }
        state.pendingDeletion = nil
        return .send(.delegate(.deleteAsset(asset)))
      case .deletionCancelled:
        state.pendingDeletion = nil
        return .none
      case let .assetDownloadFailed(message):
        modelsPaneLogger.error("Model download failed: \(message, privacy: .public)")
        state.assetFailure = "Couldn’t download the model."
        return .none
      case let .assetDeletionFailed(message):
        modelsPaneLogger.error("Model deletion failed: \(message, privacy: .public)")
        state.assetFailure = "Couldn’t delete the model."
        return .none
      case .keyTapped,
           .delegate:
        return .none
      }
    }
  }

  // MARK: Private

  private enum CancelID {
    case assets
  }

  private func move(_ state: inout State, to row: Row) {
    state.cursor = row
    if case let .profile(id) = row {
      state.previewProfile = id == state.settings.profiles.active ? nil : id
    }
  }
}
