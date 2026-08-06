import ComposableArchitecture
import SwiftUI

// MARK: - SettingsWindowView

struct SettingsWindowView: View {
  // MARK: Internal

  @Bindable var store: StoreOf<SettingsWindowFeature>

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
      .vimKeys(
        store: store,
        onPrevious: { moveDestination(by: -1) },
        onNext: { moveDestination(by: 1) },
        onDescend: { focusedColumn = .detail },
      )
      .toolbar(removing: .sidebarToggle)
      .accessibilityIdentifier(AccessibilityID.settingsSidebar)
      .accessibilityLabel("Settings sections")
    } detail: {
      detail.navigationTitle(store.selection.rawValue)
    }
    .onAppear { focusedColumn = store.selection == .history ? .detail : .sidebar }
    .onChange(of: focusedColumn) { _, focus in store.send(.focusChanged(focus)) }
  }

  // MARK: Private

  @FocusState private var focusedColumn: SettingsWindowFocus?

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

  @ViewBuilder private var detail: some View {
    switch store.selection {
    case .history:
      HistoryPane(store: store, focusedColumn: $focusedColumn)
    case .settings,
         .model,
         .dictionary,
         .cleanup:
      SettingsPlaceholderPane(destination: store.selection)
        .focusable()
        .focused($focusedColumn, equals: .detail)
        .vimKeys(store: store, onAscend: { focusedColumn = .sidebar })
    }
  }

  private func destinationRow(_ destination: SettingsDestination) -> some View {
    Label {
      Text(destination.rawValue)
        .accessibilityIdentifier(destination.accessibilityIdentifier)
        .accessibilityLabel("\(destination.rawValue) section")
        .accessibilityValue(destination.rawValue)
    } icon: {
      Image(systemName: destination.symbolName)
    }
    .tag(destination)
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

// MARK: - VimKeys

/// The window's one h/j/k/l loop. Each column supplies what the four keys mean where it is, and
/// every press marks the window keyboard-driven, so the grey cursor follows focus without any
/// column reaching into another's state.
private struct VimKeys: ViewModifier {
  // MARK: Internal

  let store: StoreOf<SettingsWindowFeature>
  var onPrevious: () -> Void = {}
  var onNext: () -> Void = {}
  var onAscend: () -> Void = {}
  var onDescend: () -> Void = {}

  func body(content: Content) -> some View {
    content
      .onKeyPress(.return) {
        press(onDescend)
      }
      .onKeyPress(characters: .init(charactersIn: "hjkl")) { keyPress in
        switch keyPress.characters {
        case "h":
          press(onAscend)
        case "j":
          press(onNext)
        case "k":
          press(onPrevious)
        case "l":
          press(onDescend)
        default:
          .ignored
        }
      }
  }

  // MARK: Private

  private func press(_ action: () -> Void) -> KeyPress.Result {
    store.send(.keyboardModeEntered)
    action()
    return .handled
  }
}

extension View {
  func vimKeys(
    store: StoreOf<SettingsWindowFeature>,
    onPrevious: @escaping () -> Void = {},
    onNext: @escaping () -> Void = {},
    onAscend: @escaping () -> Void = {},
    onDescend: @escaping () -> Void = {},
  ) -> some View {
    modifier(
      VimKeys(
        store: store, onPrevious: onPrevious, onNext: onNext, onAscend: onAscend,
        onDescend: onDescend,
      ),
    )
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
