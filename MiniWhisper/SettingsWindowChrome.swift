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

// MARK: - WindowPointerTracker

@MainActor @Observable final class WindowPointerTracker {
  var location: CGPoint?
}

// MARK: - WindowPointerMovement

/// `onContinuousHover` reports global coordinates. Comparing them prevents a parked pointer from
/// stealing keyboard mode when content moves underneath it — the same law in every pane.
private struct WindowPointerMovement: ViewModifier {
  // MARK: Internal

  let store: StoreOf<SettingsWindowFeature>
  let onMove: () -> Void

  func body(content: Content) -> some View {
    content.onContinuousHover(coordinateSpace: .global) { phase in
      guard case let .active(location) = phase else {
        return
      }
      defer { pointerTracker.location = location }
      guard let pointerLocation = pointerTracker.location, pointerLocation != location else {
        return
      }
      store.send(.pointerMoved)
      onMove()
    }
  }

  // MARK: Private

  @Environment(WindowPointerTracker.self) private var pointerTracker
}

extension View {
  func windowKeys(
    store: StoreOf<SettingsWindowFeature>, _ actions: WindowKeyActions,
  ) -> some View {
    modifier(WindowKeys(store: store, actions: actions))
  }

  func windowPointerMovement(
    store: StoreOf<SettingsWindowFeature>, onMove: @escaping () -> Void = {},
  ) -> some View {
    modifier(WindowPointerMovement(store: store, onMove: onMove))
  }

  /// The window paints its own ring — every focusable control in it has `focusEffectDisabled` —
  /// so this is the one place its shape is decided.
  func focusRing(_ isVisible: Bool) -> some View {
    overlay {
      RoundedRectangle(cornerRadius: 6)
        .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 2)
        .padding(-1)
        .opacity(isVisible ? 1 : 0)
    }
  }
}
