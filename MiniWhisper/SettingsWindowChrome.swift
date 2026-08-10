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
  let isActive: () -> Bool

  func body(content: Content) -> some View {
    content
      .onKeyPress(.escape) { actions.escape() }
      .onKeyPress(.return) { press(actions.press) }
      .onKeyPress(.tab) {
        store.send(.keyboardModeEntered)
        return .ignored
      }
      .background {
        WindowCharacterKeys { characters in
          guard isActive() else {
            return false
          }
          switch characters {
          case "h":
            _ = press(actions.left)
            return true
          case "j":
            _ = press(actions.down)
            return true
          case "k":
            _ = press(actions.up)
            return true
          case "l":
            _ = press(actions.right)
            return true
          case "/":
            return actions.search() == .handled
          default:
            return false
          }
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

// MARK: - KeyboardCursorScroll

private struct KeyboardCursorScroll<Cursor: Hashable>: ViewModifier {
  // MARK: Internal

  let store: StoreOf<SettingsWindowFeature>
  let cursor: Cursor?

  func body(content: Content) -> some View {
    ScrollViewReader { proxy in
      content
        // Only the keyboard moves the viewport. A hover already happened somewhere visible, and
        // scrolling under the pointer would move the row out from under it.
        .onChange(of: cursor) { _, cursor in
          guard store.interaction.mode == .keyboard else {
            return
          }
          scroll(proxy, to: cursor)
        }
        .onChange(of: store.interaction.focus) { _, focus in
          guard focus == .detail, store.interaction.mode == .keyboard else {
            return
          }
          scroll(proxy, to: cursor)
        }
        .onAppear { Task { @MainActor in scroll(proxy, to: cursor) } }
    }
  }

  // MARK: Private

  private func scroll(_ proxy: ScrollViewProxy, to cursor: Cursor?) {
    guard let cursor else {
      return
    }
    proxy.scrollTo(cursor, anchor: .center)
  }
}

extension View {
  func windowKeys(
    store: StoreOf<SettingsWindowFeature>, _ actions: WindowKeyActions,
    isActive: @escaping () -> Bool,
  ) -> some View {
    modifier(WindowKeys(store: store, actions: actions, isActive: isActive))
  }

  /// Apply to the scrolling container itself; every row it holds must carry `.id(cursor)`.
  func keyboardCursorScroll(
    store: StoreOf<SettingsWindowFeature>, cursor: (some Hashable)?,
  ) -> some View {
    modifier(KeyboardCursorScroll(store: store, cursor: cursor))
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
