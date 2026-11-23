import AppKit
import ComposableArchitecture
import SwiftUI

@MainActor final class SettingsWindowController: NSObject, NSWindowDelegate {
  // MARK: Lifecycle

  init(store: StoreOf<SettingsWindowFeature>) {
    self.store = store
  }

  // MARK: Internal

  /// Without a destination, an open window comes forward as it was left; a new one opens on
  /// Settings.
  func present(
    destination: SettingsDestination? = nil, initialFocus: SettingsWindowFocus? = nil,
  ) {
    if let destination = destination ?? (window == nil ? .settings : nil) {
      store.send(.selectionChanged(destination))
    }
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
    // UI tests drive fixed geometry; a frame left behind by a person would move their targets.
    if AgentDriveabilityScene.current == nil {
      window.setFrameAutosaveName(Self.frameAutosaveName)
    }
    window.delegate = self
    self.window = window

    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  func windowWillClose(_ notification: Notification) {
    guard notification.object as? NSWindow === window else {
      return
    }
    // An autosave name belongs to one live window; release it so the next window can claim it.
    if let window, !window.frameAutosaveName.isEmpty {
      window.saveFrame(usingName: Self.frameAutosaveName)
      window.setFrameAutosaveName("")
    }
    window = nil
    // Focus goes back before the Dock icon does: an app dropping to accessory while still active
    // leaves the menu bar showing its menus over whatever comes forward next.
    handback.giveBack()
    NSApp.setActivationPolicy(.accessory)
  }

  // MARK: Private

  private static let frameAutosaveName = "SettingsWindow"

  private let store: StoreOf<SettingsWindowFeature>
  private var window: NSWindow?
  private let handback = ActivationHandback()
}
