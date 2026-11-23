import AppKit
import ComposableArchitecture
import SwiftUI

@MainActor final class SettingsWindowController: NSObject, NSWindowDelegate {
  // MARK: Lifecycle

  init(store: StoreOf<SettingsWindowFeature>) {
    self.store = store
  }

  // MARK: Internal

  func present(
    destination: SettingsDestination = .settings, initialFocus: SettingsWindowFocus? = nil,
  ) {
    store.send(.selectionChanged(destination))
    // A menu bar app has no Dock tile, so app switchers have nothing to show for its one real
    // window. It borrows a regular app's presence (Dock icon, menu bar, ⌘-Tab) for exactly as
    // long as the settings window is open.
    NSApp.setActivationPolicy(.regular)
    if let window {
      NSApp.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)
      return
    }

    let window = NSWindow(
      contentRect: .zero,
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false,
    )
    window.title = Channel.name
    // Every pane scrolls its content under the title, which is what macOS windows do — but only
    // a titlebar that paints can be scrolled under. Left transparent, the panes built from a
    // grouped Form ran their rows straight through the title, and each new pane would have had
    // to remember a workaround. This is the whole fix, and it belongs to the window.
    window.titlebarAppearsTransparent = false
    // Automatic is the separator macOS draws for a unified toolbar: a line once content has
    // scrolled under the title, and nothing at all while none has.
    window.titlebarSeparatorStyle = .automatic
    window.toolbarStyle = .unified
    window.toolbar = NSToolbar(identifier: "MiniWhisper Settings Window")
    window.isReleasedWhenClosed = false
    window.collectionBehavior = [.moveToActiveSpace]
    window.minSize = NSSize(width: 680, height: 480)
    window.setAccessibilityIdentifier(AccessibilityID.settingsWindow)
    window.setAccessibilityLabel("\(Channel.name) Settings")
    window.setAccessibilityTitle("\(Channel.name) Settings")
    window.contentView = NSHostingView(
      rootView: SettingsWindowView(store: store, initialFocus: initialFocus),
    )
    window.setContentSize(NSSize(width: 860, height: 680))
    window.center()
    window.delegate = self
    self.window = window

    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  func windowWillClose(_ notification: Notification) {
    guard notification.object as? NSWindow === window else {
      return
    }
    window = nil
    // Focus goes back before the Dock icon does: an app dropping to accessory while still active
    // leaves the menu bar showing its menus over whatever comes forward next.
    handback.giveBack()
    NSApp.setActivationPolicy(.accessory)
  }

  // MARK: Private

  private let store: StoreOf<SettingsWindowFeature>
  private var window: NSWindow?
  private let handback = ActivationHandback()
}
