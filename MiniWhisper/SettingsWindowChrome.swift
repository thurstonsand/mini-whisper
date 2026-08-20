import AppKit
import ComposableArchitecture
import SwiftUI

// MARK: - WindowKeyActions

/// What the settings window's keys mean on one surface. Recognition and last-input ownership stay
/// with the window; this is the only shape that says what a press does, so every surface's whole
/// keymap is one value rather than a switch per key.
struct WindowKeyActions {
  var left: (() -> Void)?
  var down: (() -> Void)?
  var up: (() -> Void)?
  var right: (() -> Void)?
  var press: (() -> Void)?
  var add: (() -> Void)?
  var delete: (() -> Void)?
  var search: (() -> Void)?
  var escape: (() -> Void)?
  /// The grammar's one held meaning: ⌥ down and ⌥ up, for a surface that has something to show
  /// only while the key is down.
  var reveal: ((Bool) -> Void)?
}

// MARK: - FunctionKey

/// The characters AppKit reports for keys that have no letter. Spelling them from AppKit's own
/// constants keeps the grammar's arrows readable where its letters already are.
private enum FunctionKey {
  static let upArrow = character(NSUpArrowFunctionKey)
  static let downArrow = character(NSDownArrowFunctionKey)
  static let leftArrow = character(NSLeftArrowFunctionKey)
  static let rightArrow = character(NSRightArrowFunctionKey)
  static let forwardDelete = character(NSDeleteFunctionKey)

  /// Every one of these constants is in the Unicode private-use area AppKit reserves for them, so
  /// the scalar always exists.
  static func character(_ key: Int) -> String {
    String(UnicodeScalar(UInt32(key))!)
  }
}

// MARK: - WindowKeys

private struct WindowKeys: ViewModifier {
  // MARK: Internal

  let store: StoreOf<SettingsWindowFeature>
  let actions: WindowKeyActions
  let isActive: () -> Bool

  func body(content: Content) -> some View {
    content
      .onKeyPress(.escape) {
        guard let escape = actions.escape else {
          return .ignored
        }
        escape()
        return .handled
      }
      .onKeyPress(.return) {
        // Return belongs to a sheet while one is up: the key window is either the sheet or its
        // parent, and consuming it here would also activate the row behind the sheet.
        guard NSApp.keyWindow?.attachedSheet == nil, NSApp.keyWindow?.sheetParent == nil else {
          return .ignored
        }
        return press(actions.press) ? .handled : .ignored
      }
      .onKeyPress(.tab) {
        store.send(.keyboardModeEntered)
        return .ignored
      }
      .background {
        WindowCharacterKeys { characters in
          guard isActive() else {
            return false
          }
          // The arrows say the same things the letters do. A surface that suppresses the
          // grammar suppresses both at once, so a field being edited keeps its own arrows.
          switch characters {
          case "h",
               FunctionKey.leftArrow:
            return press(actions.left)
          case "j",
               FunctionKey.downArrow:
            return press(actions.down)
          case "k",
               FunctionKey.upArrow:
            return press(actions.up)
          case "l",
               FunctionKey.rightArrow:
            return press(actions.right)
          case "n":
            return press(actions.add)
          case "\u{7f}",
               FunctionKey.forwardDelete:
            return press(actions.delete)
          case "/":
            guard let search = actions.search else {
              return false
            }
            search()
            return true
          default:
            return false
          }
        }
      }
      .background {
        // A peek is not navigation, so it never claims keyboard mode: it shows what the row the
        // user is already on is hiding, whichever way they got there.
        WindowModifierHold(modifier: .option) { isHeld in
          guard let reveal = actions.reveal else {
            return
          }
          reveal(isHeld && isActive())
        }
      }
  }

  // MARK: Private

  /// A surface declines a key by leaving its action nil: the press stays an ordinary character,
  /// which is how `/` reaches a focused search field and how Escape reaches whatever else wants it.
  private func press(_ action: (() -> Void)?) -> Bool {
    guard let action else {
      return false
    }
    store.send(.keyboardModeEntered)
    action()
    return true
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

// MARK: - SettingsListRowMetrics

private enum SettingsListRowMetrics {
  static let contentHeight: CGFloat = 22
  static let verticalPadding: CGFloat = 3
  /// Live insertion otherwise caches AppKit's 24pt estimate; settled hosted content plus native
  /// table chrome has a 33pt pitch in both History and Dictionary.
  static let listPitch: CGFloat = 33
}

// MARK: - SettingsListRowHeight

private struct SettingsListRowHeight: ViewModifier {
  /// A row that wraps its content owns its height; the metric becomes the floor it shares with
  /// every single-line row, so short rows in a growing list still match the rest of the window.
  let grows: Bool

  func body(content: Content) -> some View {
    Group {
      if grows {
        content.frame(minHeight: SettingsListRowMetrics.contentHeight, alignment: .top)
      } else {
        content.frame(height: SettingsListRowMetrics.contentHeight)
      }
    }
    .padding(.vertical, SettingsListRowMetrics.verticalPadding)
  }
}

extension View {
  func windowKeys(
    store: StoreOf<SettingsWindowFeature>, _ actions: WindowKeyActions,
    isActive: @escaping () -> Bool,
  ) -> some View {
    modifier(WindowKeys(store: store, actions: actions, isActive: isActive))
  }

  func settingsListRowHeight(grows: Bool = false) -> some View {
    modifier(SettingsListRowHeight(grows: grows))
  }

  func stableSettingsListRowHeight() -> some View {
    environment(\.defaultMinListRowHeight, SettingsListRowMetrics.listPitch)
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
