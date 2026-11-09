import AppSettings
import ASREngine
import ComposableArchitecture
import Foundation
@testable import MiniWhisper
import ModelLibrary
import Sharing
import Testing

// MARK: - ModelsFeatureTests

@MainActor struct ModelsFeatureTests {
  @Test func `deleting what the active profile runs on asks first, anything else goes at once`(
  ) async {
    let store = modelsStore(assets: installed)

    await store.send(.deleteTapped(.s1Mini))
    await store.receive(.delegate(.deleteAsset(.s1Mini)))

    await store.send(.deleteTapped(.parakeet)) { $0.pendingDeletion = .parakeet }
    await store.send(.deletionConfirmed) { $0.pendingDeletion = nil }
    await store.receive(.delegate(.deleteAsset(.parakeet)))
  }

  /// Pulling a model's files mid-compile would turn a setup into a failure.
  @Test func `a model an engine is still loading cannot be deleted`() {
    var health = AppHealth()
    health.readinessByEngine[.parakeet] = .compiling
    let state = ModelsFeature.State(
      settings: Shared(value: .defaults), health: Shared(value: health),
    )
    var loaded = state
    loaded.assets = installed
    #expect(!loaded.isDeletable(.parakeet))
    #expect(loaded.isDeletable(.s1Mini))
    #expect(loaded.rows == ProfileID.allCases.map(ModelsFeature.Row.profile) + [.asset(.s1Mini)])
  }

  @Test func `preview leaves the active profile intact and clears at the pane edge`() async {
    let store = modelsStore(assets: installed)

    await store.send(.cursorHovered(.profile(.offline))) {
      $0.cursor = .profile(.offline)
      $0.previewProfile = .offline
    }
    await store.send(.cursorHovered(.asset(.s1Mini))) { $0.cursor = .asset(.s1Mini) }
    #expect(store.state.previewProfile == .offline)
    #expect(store.state.settings.profiles.active == .haiku)
    await store.send(.pointerExited) { $0.previewProfile = nil }

    // Return on a model row presses its one button.
    await store.send(.pressRequested)
    await store.receive(.deleteTapped(.s1Mini))
    await store.receive(.delegate(.deleteAsset(.s1Mini)))
  }

  @Test func `keyboard preview survives crossing to assets and clears on Escape`() async {
    let store = modelsStore(assets: installed)
    await store.send(.cursorHovered(.profile(.cerebras))) {
      $0.cursor = .profile(.cerebras)
      $0.previewProfile = .cerebras
    }
    await store.send(.rowMoved(.next)) {
      $0.cursor = .profile(.custom)
      $0.previewProfile = .custom
      $0.isKeyboardPreview = true
    }
    await store.send(.rowMoved(.next)) { $0.cursor = .asset(.gate) }
    await store.send(.pointerExited)
    #expect(store.state.previewProfile == .custom)
    await store.send(.previewCleared) { $0.previewProfile = nil }
  }

  @Test func `each leg plugs into what that profile runs on, and nothing when it has none`() {
    let state = ModelsFeature.State(
      settings: Shared(value: .defaults), health: Shared(value: AppHealth()),
    )
    let lineup = state.settings.profiles.lineup
    func plug(_ id: ProfileID, _ leg: ModelsFeature.Leg) -> ModelsFeature.Component? {
      state.component(leg, of: lineup.first { $0.id == id }!)
    }
    #expect(plug(.haiku, .speech) == .asset(.parakeet))
    #expect(plug(.accurate, .speech) == .scribe)
    #expect(plug(.offline, .cleanup) == .asset(.s1Mini))
    #expect(plug(.cerebras, .cleanup) == .endpoint(.cerebras))
    // Custom's cleanup starts off.
    #expect(plug(.custom, .cleanup) == nil)
  }
}

private let installed: [ModelAsset: AssetState] = Dictionary(
  uniqueKeysWithValues: ModelAsset.allCases.map { ($0, .installed(bytes: $0.pinnedBytes)) },
)

@MainActor private func modelsStore(
  assets: [ModelAsset: AssetState],
) -> TestStoreOf<ModelsFeature> {
  var state = ModelsFeature.State(
    settings: Shared(value: .defaults), health: Shared(value: AppHealth()),
  )
  state.assets = assets
  return TestStore(initialState: state) { ModelsFeature() }
}
