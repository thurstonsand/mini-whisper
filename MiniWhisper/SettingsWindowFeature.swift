import AppSettings
import ComposableArchitecture
import Foundation
import History
import ModelLibrary
import SpeechDictionary

// MARK: - SettingsDestination

enum SettingsDestination: String, CaseIterable, Identifiable, Equatable {
  case settings = "Settings"
  case history = "History"
  case dictionary = "Dictionary"
  case profiles = "Profiles"
  case models = "Models"
  case about = "About"

  // MARK: Internal

  var id: Self {
    self
  }

  var symbolName: String {
    switch self {
    case .settings:
      "gearshape"
    case .history:
      "clock.arrow.circlepath"
    case .dictionary:
      "character.book.closed"
    case .profiles:
      "person.crop.rectangle.stack"
    case .models:
      "internaldrive"
    case .about:
      "info.circle"
    }
  }

  var accessibilityIdentifier: String {
    switch self {
    case .settings:
      AccessibilityID.settingsSidebarSettings
    case .history:
      AccessibilityID.settingsSidebarHistory
    case .dictionary:
      AccessibilityID.settingsSidebarDictionary
    case .profiles:
      AccessibilityID.settingsSidebarProfiles
    case .models:
      AccessibilityID.settingsSidebarModels
    case .about:
      AccessibilityID.settingsSidebarAbout
    }
  }
}

// MARK: - SettingsWindowFocus

enum SettingsWindowFocus: Hashable {
  case sidebar
  case detail
}

// MARK: - SettingsWindowInteraction

/// Focus and last-input ownership are one window-level contract. Panes supply only whether a row
/// is their cursor; this decides whether keyboard paint is allowed to exist at all.
@ObservableState struct SettingsWindowInteraction: Equatable {
  enum Mode: Equatable {
    case keyboard
    case mouse
  }

  var focus: SettingsWindowFocus?
  var mode = Mode.mouse

  var keyboardDrivesDetail: Bool {
    mode == .keyboard && focus == .detail
  }

  func showsKeyboardCursor(_ matchesCursor: @autoclosure () -> Bool) -> Bool {
    keyboardDrivesDetail && matchesCursor()
  }
}

// MARK: - SettingsWindowFeature

@Reducer struct SettingsWindowFeature {
  @ObservableState struct State: Equatable {
    // MARK: Lifecycle

    init(
      selection: SettingsDestination = .settings,
      history: Shared<HistoryLog>,
      settings: Shared<MiniWhisperSettings>,
      dictionary: Shared<DictionaryContents>,
      health: Shared<AppHealth>,
    ) {
      self.selection = selection
      settingsPane = SettingsPaneFeature.State(settings: settings, health: health)
      profiles = ProfilesFeature.State(settings: settings, health: health)
      models = ModelsFeature.State(settings: settings, health: health)
      self.history = HistoryFeature.State(
        log: history, retention: settings.retention, dictionary: dictionary, settings: settings,
      )
      self.dictionary = DictionaryFeature.State(
        dictionary: dictionary, profiles: settings.profiles,
      )
    }

    // MARK: Internal

    var selection: SettingsDestination
    /// Which column is focused, mirrored both ways with the view's `@FocusState`: the view reports
    /// what the system did, and a hover claims focus from here. `nil` means focus is somewhere
    /// that is neither column — the search field.
    var interaction = SettingsWindowInteraction()
    var settingsPane: SettingsPaneFeature.State
    var history: HistoryFeature.State
    var dictionary: DictionaryFeature.State
    var profiles: ProfilesFeature.State
    var models: ModelsFeature.State

    func showsHistoryKeyboardCursor(_ id: UUID) -> Bool {
      guard interaction.keyboardDrivesDetail else {
        return false
      }
      if let cursor = history.cursor {
        let entries = history.filteredEntries
        if cursor == id {
          return entries.contains(where: { $0.id == id })
        }
        // Only the first visible entry can fall back when `cursor` is filtered out or deleted.
        guard entries.first?.id == id else {
          return false
        }
        return !entries.contains(where: { $0.id == cursor })
      }
      return history.filteredEntries.first?.id == id
    }

    func showsDictionaryKeyboardCursor(_ id: DictionaryFeature.EntryID) -> Bool {
      guard interaction.keyboardDrivesDetail else {
        return false
      }
      if let cursor = dictionary.cursor {
        let entries = dictionary.visibleEntries
        if cursor == id {
          return entries.contains(where: { $0.id == id })
        }
        guard entries.first?.id == id else {
          return false
        }
        return !entries.contains(where: { $0.id == cursor })
      }
      return dictionary.visibleEntries.first?.id == id
    }

    /// A focused detail column always shows where its single row cursor is; input mode only
    /// decides whether the control within that row also wears its keyboard ring.
    func showsSettingsBar(_ row: SettingsPaneFeature.Row) -> Bool {
      interaction.focus == .detail && settingsPane.cursorRow == row
    }

    func showsSettingsRing(
      _ row: SettingsPaneFeature.Row, target: SettingsPaneFeature.Target,
    ) -> Bool {
      interaction.showsKeyboardCursor(
        settingsPane.cursorRow == row && settingsPane.cursorTarget == target,
      )
    }

    func showsProfilesBar(_ row: ProfilesFeature.Row) -> Bool {
      interaction.focus == .detail && profiles.cursorRow == row
    }

    func showsProfilesRing(_ row: ProfilesFeature.Row, target: ProfilesFeature.Target) -> Bool {
      interaction.showsKeyboardCursor(
        profiles.cursorRow == row && profiles.cursorTarget == target,
      )
    }

    /// A card is lit by being pointed at, so only an asset row's button wears a keyboard ring.
    func showsModelsRing(_ asset: ModelAsset) -> Bool {
      interaction.showsKeyboardCursor(models.cursorRow == .asset(asset))
    }
  }

  enum Action: Equatable {
    case selectionChanged(SettingsDestination)
    case focusChanged(SettingsWindowFocus?)
    case keyboardModeEntered
    case pointerMoved
    case settingsPane(SettingsPaneFeature.Action)
    case history(HistoryFeature.Action)
    case dictionary(DictionaryFeature.Action)
    case profiles(ProfilesFeature.Action)
    case models(ModelsFeature.Action)
  }

  var body: some ReducerOf<Self> {
    Scope(state: \.settingsPane, action: \.settingsPane) { SettingsPaneFeature() }
    Scope(state: \.history, action: \.history) { HistoryFeature() }
    Scope(state: \.dictionary, action: \.dictionary) { DictionaryFeature() }
    Scope(state: \.profiles, action: \.profiles) { ProfilesFeature() }
    Scope(state: \.models, action: \.models) { ModelsFeature() }

    Reduce { state, action in
      switch action {
      case let .selectionChanged(selection):
        if state.selection != selection {
          state.selection = selection
        }
        return .none
      case .dictionary(.showVocabularySettings):
        state.profiles.cursor = ProfilesFeature.Cursor(row: .boostsVocabulary)
        state.selection = .profiles
        state.interaction.focus = .detail
        return .none
      case let .profiles(.downloadTapped(asset)):
        return .send(.models(.downloadTapped(asset)))
      case let .models(.keyTapped(component)):
        let profile: ProfileID
        let field: ProfilesFeature.Field
        switch component {
        case .asset:
          return .none
        case .scribe:
          profile = .accurate
          field = .engineKey
        case let .endpoint(id):
          profile = id
          field = .apiKey
        }
        state.selection = .profiles
        state.interaction.focus = .detail
        return .concatenate(
          .send(.profiles(.profileSelected(profile))),
          .send(.profiles(.editTapped(field))),
        )
      case let .focusChanged(focus):
        if state.interaction.focus != focus {
          state.interaction.focus = focus
        }
        return .none
      case .keyboardModeEntered:
        if state.interaction.mode != .keyboard {
          state.interaction.mode = .keyboard
        }
        return .none
      case .pointerMoved:
        if state.interaction.mode != .mouse {
          state.interaction.mode = .mouse
        }
        return .none
      // The pointer landing on a row is the detail column being driven, so it claims focus the
      // same way an arrow key would. Nobody types and mouses at once, so there is nothing to steal.
      case .settingsPane(.cursorHovered),
           .history(.cursorHovered),
           .dictionary(.cursorHovered),
           .profiles(.cursorHovered),
           .models(.cursorHovered):
        if state.interaction.focus != .detail {
          state.interaction.focus = .detail
        }
        return .none
      case .dictionary,
           .history,
           .models,
           .profiles,
           .settingsPane:
        return .none
      }
    }
  }
}

// MARK: - Fine-grained store queries

/// Reads only the specific properties needed for cursor paint rather than `store.state`, which
/// would subscribe every row in every pane to every mutation across the entire window.
extension StoreOf<SettingsWindowFeature> {
  func showsHistoryKeyboardCursor(_ id: UUID) -> Bool {
    let store = self
    guard store.interaction.keyboardDrivesDetail else {
      return false
    }
    if let cursor = store.history.cursor {
      let entries = store.history.filteredEntries
      if cursor == id {
        return entries.contains(where: { $0.id == id })
      }
      guard entries.first?.id == id else {
        return false
      }
      return !entries.contains(where: { $0.id == cursor })
    }
    return store.history.filteredEntries.first?.id == id
  }

  func showsDictionaryKeyboardCursor(_ id: DictionaryFeature.EntryID) -> Bool {
    let store = self
    guard store.interaction.keyboardDrivesDetail else {
      return false
    }
    if let cursor = store.dictionary.cursor {
      let entries = store.dictionary.visibleEntries
      if cursor == id {
        return entries.contains(where: { $0.id == id })
      }
      guard entries.first?.id == id else {
        return false
      }
      return !entries.contains(where: { $0.id == cursor })
    }
    return store.dictionary.visibleEntries.first?.id == id
  }

  func showsSettingsBar(_ row: SettingsPaneFeature.Row) -> Bool {
    let store = self
    return store.interaction.focus == .detail && store.settingsPane.cursorRow == row
  }

  func showsSettingsRing(
    _ row: SettingsPaneFeature.Row, target: SettingsPaneFeature.Target,
  ) -> Bool {
    let store = self
    return store.interaction.showsKeyboardCursor(
      store.settingsPane.cursorRow == row && store.settingsPane.cursorTarget == target,
    )
  }

  func showsProfilesBar(_ row: ProfilesFeature.Row) -> Bool {
    let store = self
    return store.interaction.focus == .detail && store.profiles.cursorRow == row
  }

  func showsProfilesRing(_ row: ProfilesFeature.Row, target: ProfilesFeature.Target) -> Bool {
    let store = self
    return store.interaction.showsKeyboardCursor(
      store.profiles.cursorRow == row && store.profiles.cursorTarget == target,
    )
  }

  func showsModelsRing(_ asset: ModelAsset) -> Bool {
    let store = self
    return store.interaction.showsKeyboardCursor(store.models.cursorRow == .asset(asset))
  }
}
