import AppSettings
import ComposableArchitecture
import Foundation
import History

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
    ) {
      self.selection = selection
      settingsPane = SettingsPaneFeature.State(settings: settings)
      self.history = HistoryFeature.State(log: history, retention: settings.retention)
    }

    // MARK: Internal

    var selection: SettingsDestination
    /// Focus is reported by the view's `@FocusState`, never driven from here. `nil` means focus
    /// is somewhere that is neither column — the search field.
    var interaction = SettingsWindowInteraction()
    var settingsPane: SettingsPaneFeature.State
    var history: HistoryFeature.State

    func showsHistoryKeyboardCursor(_ id: UUID) -> Bool {
      interaction.showsKeyboardCursor(history.cursorEntry?.id == id)
    }

    /// A focused detail column always shows where it is; only keyboard mode says which control
    /// within the row is the target. The pointer, while it is the thing driving, outranks both.
    func showsSettingsBar(_ row: SettingsPaneFeature.Row) -> Bool {
      switch interaction.mode {
      case .keyboard:
        interaction.showsKeyboardCursor(settingsPane.cursor.row == row)
      case .mouse:
        if let hoveredRow = settingsPane.hoveredRow {
          hoveredRow == row
        } else {
          interaction.focus == .detail && settingsPane.cursor.row == row
        }
      }
    }

    func showsSettingsRing(
      _ row: SettingsPaneFeature.Row, target: SettingsPaneFeature.Target,
    ) -> Bool {
      interaction.showsKeyboardCursor(
        settingsPane.cursor.row == row && settingsPane.cursorTarget == target,
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
  }

  var body: some ReducerOf<Self> {
    Scope(state: \.settingsPane, action: \.settingsPane) { SettingsPaneFeature() }
    Scope(state: \.history, action: \.history) { HistoryFeature() }

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
      case .settingsPane,
           .history:
        return .none
      }
    }
  }
}
