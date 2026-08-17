import AppSettings
import ComposableArchitecture
import Foundation
import History
import SpeechDictionary

// MARK: - SettingsDestination

enum SettingsDestination: String, CaseIterable, Identifiable, Equatable {
  case settings = "Settings"
  case history = "History"
  case model = "Model"
  case dictionary = "Dictionary"
  case cleanup = "Cleanup"

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
    case .model:
      "waveform"
    case .dictionary:
      "character.book.closed"
    case .cleanup:
      "wand.and.sparkles"
    }
  }

  var accessibilityIdentifier: String {
    switch self {
    case .settings:
      AccessibilityID.settingsSidebarSettings
    case .history:
      AccessibilityID.settingsSidebarHistory
    case .model:
      AccessibilityID.settingsSidebarModel
    case .dictionary:
      AccessibilityID.settingsSidebarDictionary
    case .cleanup:
      AccessibilityID.settingsSidebarCleanup
    }
  }

  var placeholderCaption: String {
    switch self {
    case .settings:
      "Dictation controls will appear here."
    case .history:
      "Your dictation history will appear here."
    case .model:
      "Speech model controls will appear here."
    case .dictionary:
      "Custom words and corrections will appear here."
    case .cleanup:
      "Transcript cleanup controls will appear here."
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
struct SettingsWindowInteraction: Equatable {
  enum Mode: Equatable {
    case keyboard
    case mouse
  }

  var focus: SettingsWindowFocus?
  var mode = Mode.mouse

  var keyboardDrivesDetail: Bool {
    mode == .keyboard && focus == .detail
  }

  func showsKeyboardCursor(_ matchesCursor: Bool) -> Bool {
    keyboardDrivesDetail && matchesCursor
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
      self.history = HistoryFeature.State(
        log: history, retention: settings.retention, dictionary: dictionary,
        improveRecognition: settings.improveRecognition,
      )
      self.dictionary = DictionaryFeature.State(
        dictionary: dictionary, improveRecognition: settings.improveRecognition,
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

    func showsHistoryKeyboardCursor(_ id: UUID) -> Bool {
      interaction.showsKeyboardCursor(history.cursorEntry?.id == id)
    }

    func showsDictionaryKeyboardCursor(_ id: DictionaryFeature.EntryID) -> Bool {
      interaction.showsKeyboardCursor(dictionary.cursorEntry?.id == id)
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
  }

  enum Action: Equatable {
    case selectionChanged(SettingsDestination)
    case focusChanged(SettingsWindowFocus?)
    case keyboardModeEntered
    case pointerMoved
    case settingsPane(SettingsPaneFeature.Action)
    case history(HistoryFeature.Action)
    case dictionary(DictionaryFeature.Action)
  }

  var body: some ReducerOf<Self> {
    Scope(state: \.settingsPane, action: \.settingsPane) { SettingsPaneFeature() }
    Scope(state: \.history, action: \.history) { HistoryFeature() }
    Scope(state: \.dictionary, action: \.dictionary) { DictionaryFeature() }

    Reduce { state, action in
      switch action {
      case let .selectionChanged(selection):
        state.selection = selection
        return .none
      case let .focusChanged(focus):
        state.interaction.focus = focus
        return .none
      case .keyboardModeEntered:
        state.interaction.mode = .keyboard
        return .none
      case .pointerMoved:
        state.interaction.mode = .mouse
        return .none
      // The pointer landing on a row is the detail column being driven, so it claims focus the
      // same way an arrow key would. Nobody types and mouses at once, so there is nothing to steal.
      case .settingsPane(.cursorHovered),
           .history(.cursorHovered),
           .dictionary(.cursorHovered):
        state.interaction.focus = .detail
        return .none
      case .settingsPane,
           .history,
           .dictionary:
        return .none
      }
    }
  }
}
