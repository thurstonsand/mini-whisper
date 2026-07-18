import ComposableArchitecture
import Foundation

@Reducer struct SettingsFeature {
  @ObservableState struct State: Equatable {
    var whisperModelSize: WhisperModelSize = .base
    var cleanupEnabled: Bool = false
    var hotkeyEnabled: Bool = true
  }

  enum Action: Equatable { case noop }

  var body: some ReducerOf<Self> {
    Reduce { _, action in
      switch action {
      case .noop: return .none
      }
    }
  }
}

enum WhisperModelSize: String, CaseIterable, Equatable {
  case tiny
  case base
  case small
  case medium
  case large

  var displayName: String { rawValue.capitalized }
}
