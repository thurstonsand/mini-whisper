import AppKit
import Carbon.HIToolbox
import SwiftUI

// MARK: - WindowKeyMonitor

private struct WindowKeyMonitor: NSViewRepresentable {
  final class MonitorView: NSView {
    // MARK: Lifecycle

    init(mask: NSEvent.EventTypeMask, handles: @escaping (NSEvent) -> Bool) {
      self.mask = mask
      self.handles = handles
      super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
      fatalError()
    }

    deinit {
      if let monitor {
        NSEvent.removeMonitor(monitor)
      }
    }

    // MARK: Internal

    var handles: (NSEvent) -> Bool

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if let monitor {
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
      }
      guard let window else {
        return
      }
      monitor = NSEvent.addLocalMonitorForEvents(matching: mask) {
        [weak self, weak window] event in
        guard event.window === window, self?.handles(event) == true else {
          return event
        }
        return nil
      }
    }

    // MARK: Private

    private let mask: NSEvent.EventTypeMask
    private nonisolated(unsafe) var monitor: Any?
  }

  var mask: NSEvent.EventTypeMask = .keyDown
  let handles: (NSEvent) -> Bool

  func makeNSView(context _: Context) -> MonitorView {
    MonitorView(mask: mask, handles: handles)
  }

  func updateNSView(_ view: MonitorView, context _: Context) {
    view.handles = handles
  }
}

// MARK: - WindowTabKeys

/// SwiftUI's `.onKeyPress` is deaf until a SwiftUI view owns focus: on entry the AppKit window is
/// still the responder, so native traversal would pick its own first stop before any page could
/// object. A window-scoped monitor gives a page that opens unfocused somewhere to put the very
/// first Tab. Modified Tab passes through untouched, and a page that declines returns `false`.
struct WindowTabKeys: View {
  let onTab: () -> Bool

  var body: some View {
    WindowKeyMonitor { event in
      let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      return event.keyCode == UInt16(kVK_Tab)
        && modifiers.subtracting([.shift, .capsLock]).isEmpty
        && onTab()
    }
  }
}

// MARK: - WindowCharacterKeys

/// Pane replacement can briefly clear SwiftUI focus between consecutive key events. Window-level
/// commands still belong to the column that initiated the navigation, so they cannot depend on a
/// focused descendant surviving the replacement.
struct WindowCharacterKeys: View {
  let onKey: (String) -> Bool

  var body: some View {
    WindowKeyMonitor { event in
      let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      // A bare arrow still arrives flagged: AppKit marks every key that has no letter as
      // function, and the arrow cluster as numeric pad. Neither is a modifier anyone held.
      return modifiers.subtracting([.capsLock, .function, .numericPad]).isEmpty
        && event.characters.map(onKey) == true
    }
  }
}

// MARK: - WindowModifierHold

/// A modifier reported for as long as it is held. Nothing is consumed: a bare modifier is not a
/// command anywhere in this window, and every chord that contains one still needs to see it.
struct WindowModifierHold: View {
  let modifier: NSEvent.ModifierFlags
  let isHeldChanged: (Bool) -> Void

  var body: some View {
    WindowKeyMonitor(mask: .flagsChanged) { event in
      isHeldChanged(event.modifierFlags.contains(modifier))
      return false
    }
  }
}

// MARK: - WindowKeyFocus

/// First focus has to wait for the window to actually become key; applying it any earlier leaves
/// the column focused in SwiftUI's model and unfocused in AppKit's.
struct WindowKeyFocus: NSViewRepresentable {
  final class KeyObserverView: NSView {
    // MARK: Lifecycle

    init(onWindowKey: @escaping () -> Void) {
      self.onWindowKey = onWindowKey
      super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
      fatalError()
    }

    // MARK: Internal

    var onWindowKey: () -> Void

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      NotificationCenter.default.removeObserver(self)
      guard let window else {
        return
      }
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(windowDidBecomeKey),
        name: NSWindow.didBecomeKeyNotification,
        object: window,
      )
    }

    // MARK: Private

    @objc private func windowDidBecomeKey() {
      onWindowKey()
    }
  }

  let onWindowKey: () -> Void

  func makeNSView(context _: Context) -> KeyObserverView {
    KeyObserverView(onWindowKey: onWindowKey)
  }

  func updateNSView(_ view: KeyObserverView, context _: Context) {
    view.onWindowKey = onWindowKey
  }
}
