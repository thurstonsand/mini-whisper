import AppKit
import Carbon.HIToolbox
import SwiftUI

// MARK: - WindowKeyMonitor

private struct WindowKeyMonitor: NSViewRepresentable {
  final class MonitorView: NSView {
    // MARK: Lifecycle

    init(handles: @escaping (NSEvent) -> Bool) {
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
      monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
        [weak self, weak window] event in
        guard event.window === window, self?.handles(event) == true else {
          return event
        }
        return nil
      }
    }

    // MARK: Private

    private nonisolated(unsafe) var monitor: Any?
  }

  let handles: (NSEvent) -> Bool

  func makeNSView(context _: Context) -> MonitorView {
    MonitorView(handles: handles)
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
      return modifiers.subtracting(.capsLock).isEmpty
        && event.characters.map(onKey) == true
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
