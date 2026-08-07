import AppKit
import ComposableArchitecture
import SwiftUI

// MARK: - WindowKeyActions

/// What the settings window's keys mean on one surface. Recognition and last-input ownership stay
/// with the window; this is the only shape that says what a press does, so every surface's whole
/// keymap is one value rather than a switch per key.
struct WindowKeyActions {
  var left: () -> Void = {}
  var down: () -> Void = {}
  var up: () -> Void = {}
  var right: () -> Void = {}
  var press: () -> Void = {}
  /// The two keys a surface may decline: an ignored press stays an ordinary character, which is
  /// how `/` reaches a focused search field and how Escape reaches whatever else wants it.
  var search: () -> KeyPress.Result = { .ignored }
  var escape: () -> KeyPress.Result = { .ignored }
}

// MARK: - WindowKeys

private struct WindowKeys: ViewModifier {
  // MARK: Internal

  let store: StoreOf<SettingsWindowFeature>
  let actions: WindowKeyActions

  func body(content: Content) -> some View {
    content
      .onKeyPress(.escape) { actions.escape() }
      .onKeyPress(.return) { press(actions.press) }
      .onKeyPress(.tab) {
        store.send(.keyboardModeEntered)
        return .ignored
      }
      .onKeyPress(characters: .init(charactersIn: "hjkl/")) { keyPress in
        switch keyPress.characters {
        case "h":
          press(actions.left)
        case "j":
          press(actions.down)
        case "k":
          press(actions.up)
        case "l":
          press(actions.right)
        case "/":
          actions.search()
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

// MARK: - WindowPointerMovement

/// `onContinuousHover` reports global coordinates. Comparing them prevents a parked pointer from
/// stealing keyboard mode when content moves underneath it — the same law in every pane.
private struct WindowPointerMovement: ViewModifier {
  // MARK: Internal

  let store: StoreOf<SettingsWindowFeature>

  func body(content: Content) -> some View {
    content.onContinuousHover(coordinateSpace: .global) { phase in
      guard case let .active(location) = phase else {
        return
      }
      defer { pointerLocation = location }
      guard let pointerLocation, pointerLocation != location else {
        return
      }
      store.send(.pointerMoved)
    }
  }

  // MARK: Private

  @State private var pointerLocation: CGPoint?
}

extension View {
  func windowKeys(
    store: StoreOf<SettingsWindowFeature>, _ actions: WindowKeyActions,
  ) -> some View {
    modifier(WindowKeys(store: store, actions: actions))
  }

  func windowPointerMovement(store: StoreOf<SettingsWindowFeature>) -> some View {
    modifier(WindowPointerMovement(store: store))
  }
}
