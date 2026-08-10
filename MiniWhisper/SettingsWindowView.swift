import ComposableArchitecture
import SwiftUI

// MARK: - SettingsWindowView

struct SettingsWindowView: View {
  // MARK: Internal

  @Bindable var store: StoreOf<SettingsWindowFeature>

  var initialFocus: SettingsWindowFocus?

  var body: some View {
    NavigationSplitView {
      List(selection: selection) {
        destinationRow(.settings)
        Section {
          ForEach(SettingsDestination.allCases.dropFirst()) { destination in
            destinationRow(destination)
          }
        }
      }
      .navigationSplitViewColumnWidth(min: 160, ideal: 176, max: 220)
      .scrollBounceBehavior(.basedOnSize)
      .focused($focusedColumn, equals: .sidebar)
      .windowKeys(store: store, sidebarKeys) {
        store.interaction.focus == .sidebar
      }
      .windowPointerMovement(store: store)
      .toolbar(removing: .sidebarToggle)
      .accessibilityIdentifier(AccessibilityID.settingsSidebar)
      .accessibilityLabel("Settings sections")
      .accessibilityValue(focusedColumn == .sidebar ? "Focused" : "Not focused")
    } detail: {
      ZStack {
        detail.navigationTitle(store.selection.rawValue)
      }
      .focusable()
      .focusEffectDisabled()
      .focused($focusedColumn, equals: .detail)
      .windowKeys(store: store, detailKeys) {
        store.interaction.focus == .detail
      }
      .modifier(
        HistorySearchFocus(
          store: store, isSearchFocused: $isHistorySearchFocused,
          focusedColumn: $focusedColumn,
        ),
      )
    }
    .ignoresSafeArea(.container, edges: .top)
    .toolbarVisibility(.visible, for: .windowToolbar)
    // The keeper item that holds the toolbar alive must not share the trailing glass capsule
    // with a pane's real buttons — a zero-size sibling still widens the capsule and pushes the
    // neighbouring glyph off-centre. `.navigation` keeps it in the leading group, alone.
    .toolbar {
      ToolbarItem(placement: .navigation) {
        Color.clear.frame(width: 0, height: 0)
      }
    }
    .background {
      WindowKeyFocus { applyInitialFocus() }
        .frame(width: 0, height: 0)
    }
    .environment(pointerTracker)
    .onChange(of: focusedColumn) { _, focus in synchronizeFocus(focus) }
    // The other half of the mirror: a hover moves focus in the store, and @FocusState is the only
    // thing that can make it real. Assigning a value it already holds ends the round trip.
    .onChange(of: store.interaction.focus) { _, focus in focusedColumn = focus }
  }

  // MARK: Private

  @FocusState private var focusedColumn: SettingsWindowFocus?
  @FocusState private var isHistorySearchFocused: Bool
  @State private var hasAppliedInitialFocus = false
  @State private var pointerTracker = WindowPointerTracker()

  /// `List` selection is optional and the window's never is, so this is the only place the two
  /// shapes meet: a deselection is simply not a destination change.
  private var selection: Binding<SettingsDestination?> {
    Binding(
      get: { store.selection },
      set: { destination in
        guard let destination else {
          return
        }
        store.send(.selectionChanged(destination))
      },
    )
  }

  private var sidebarKeys: WindowKeyActions {
    WindowKeyActions(
      down: { moveDestination(by: 1) },
      up: { moveDestination(by: -1) },
      right: { setFocus(.detail) },
      press: { setFocus(.detail) },
    )
  }

  /// The detail column's whole keymap, one destination per arm. Panes own meaning; the window owns
  /// recognition, so a new pane is a new arm here rather than an edit in five key handlers.
  private var detailKeys: WindowKeyActions {
    switch store.selection {
    case .settings:
      WindowKeyActions(
        left: {
          // Ascending is the window's move: focus may only be driven by @FocusState, so the edge
          // is read here before the pane is told to step off it.
          let ascends = store.settingsPane.cursor.target == 0
          store.send(.settingsPane(.leftPressed))
          if ascends {
            setFocus(.sidebar)
          }
        },
        down: { store.send(.settingsPane(.rowMoved(.next))) },
        up: { store.send(.settingsPane(.rowMoved(.previous))) },
        right: { store.send(.settingsPane(.rightPressed)) },
        press: { store.send(.settingsPane(.pressRequested)) },
        escape: cancelSettingsRecording,
      )
    case .history:
      WindowKeyActions(
        left: { setFocus(.sidebar) },
        down: { store.send(.history(.cursorMoved(.next))) },
        up: { store.send(.history(.cursorMoved(.previous))) },
        right: { store.send(.history(.copyRequested)) },
        press: { store.send(.history(.copyRequested)) },
        search: {
          guard !isHistorySearchFocused else {
            return .ignored
          }
          isHistorySearchFocused = true
          return .handled
        },
      )
    case .model,
         .dictionary,
         .cleanup:
      WindowKeyActions(left: { setFocus(.sidebar) })
    }
  }

  @ViewBuilder private var detail: some View {
    switch store.selection {
    case .settings:
      SettingsPane(store: store)
    case .history:
      HistoryPane(store: store, searchFocus: $isHistorySearchFocused)
    case .model,
         .dictionary,
         .cleanup:
      SettingsPlaceholderPane(destination: store.selection)
    }
  }

  private func destinationRow(_ destination: SettingsDestination) -> some View {
    Label {
      Text(destination.rawValue)
        .accessibilityIdentifier(destination.accessibilityIdentifier)
        .accessibilityLabel("\(destination.rawValue) section")
        .accessibilityValue(
          destination == store.selection
            ? "\(destination.rawValue); Selected"
            : "\(destination.rawValue); Not selected",
        )
    } icon: {
      Image(systemName: destination.symbolName)
    }
    .tag(destination)
  }

  private func cancelSettingsRecording() -> KeyPress.Result {
    guard store.settingsPane.bindings.isRecording else {
      return .ignored
    }
    store.send(.settingsPane(.bindings(.cancelRecording)))
    return .handled
  }

  private func applyInitialFocus() {
    guard !hasAppliedInitialFocus else {
      return
    }
    hasAppliedInitialFocus = true
    focusedColumn = initialFocus ?? (store.selection == .history ? .detail : .sidebar)
  }

  private func setFocus(_ focus: SettingsWindowFocus) {
    store.send(.focusChanged(focus))
    focusedColumn = focus
  }

  private func synchronizeFocus(_ focus: SettingsWindowFocus?) {
    guard focus == nil, !isHistorySearchFocused, let retainedFocus = store.interaction.focus else {
      store.send(.focusChanged(focus))
      return
    }
    Task { @MainActor in
      guard focusedColumn == nil, !isHistorySearchFocused else {
        return
      }
      focusedColumn = retainedFocus
    }
  }

  private func moveDestination(by offset: Int) {
    let destinations = SettingsDestination.allCases
    guard let current = destinations.firstIndex(of: store.selection) else {
      return
    }
    let next = min(max(current + offset, 0), destinations.count - 1)
    store.send(.selectionChanged(destinations[next]))
  }
}

// MARK: - SettingsPlaceholderPane

private struct SettingsPlaceholderPane: View {
  let destination: SettingsDestination

  var body: some View {
    VStack(spacing: 8) {
      Text(destination.rawValue).font(.title2)
      Text(destination.placeholderCaption).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityElement(children: .ignore)
    .accessibilityIdentifier(AccessibilityID.settingsPlaceholder)
    .accessibilityLabel("\(destination.rawValue). \(destination.placeholderCaption)")
  }
}
