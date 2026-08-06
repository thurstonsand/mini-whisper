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

// MARK: - SettingsWindowInputMode

/// Which device the user is driving the window with. Last input wins, and only genuine mouse
/// events count, so scrolling rows under a parked pointer cannot end keyboard mode.
enum SettingsWindowInputMode: Equatable {
  case keyboard
  case mouse
}

// MARK: - SettingsWindowFeature

@Reducer struct SettingsWindowFeature {
  @ObservableState struct State: Equatable {
    // MARK: Lifecycle

    init(
      selection: SettingsDestination = .settings,
      history: Shared<HistoryLog>,
      retention: Shared<RetentionPolicy>,
    ) {
      self.selection = selection
      self.history = HistoryFeature.State(log: history, retention: retention)
    }

    // MARK: Internal

    var selection: SettingsDestination
    /// Reported by the window's focus state, never driven from here. `nil` means focus is
    /// somewhere that is neither column — the search field.
    var focus: SettingsWindowFocus?
    var inputMode = SettingsWindowInputMode.mouse
    var history: HistoryFeature.State

    /// The single grey the window may show: keyboard driving, the detail column focused, and the
    /// row under the cursor. Hover supplies the other one, and never at the same time.
    func showsKeyboardCursor(_ id: UUID) -> Bool {
      inputMode == .keyboard && focus == .detail && history.cursorEntry?.id == id
    }
  }

  enum Action: Equatable {
    case selectionChanged(SettingsDestination)
    case focusChanged(SettingsWindowFocus?)
    case keyboardModeEntered
    case pointerMoved
    case history(HistoryFeature.Action)
  }

  var body: some ReducerOf<Self> {
    Scope(state: \.history, action: \.history) { HistoryFeature() }

    Reduce { state, action in
      switch action {
      case let .selectionChanged(selection):
        state.selection = selection
        return .none
      case let .focusChanged(focus):
        state.focus = focus
        return .none
      case .keyboardModeEntered:
        state.inputMode = .keyboard
        return .none
      case .pointerMoved:
        state.inputMode = .mouse
        return .none
      case .history:
        return .none
      }
    }
  }
}
