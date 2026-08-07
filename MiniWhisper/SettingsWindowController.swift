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
    window.titlebarAppearsTransparent = true
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
    window.setContentSize(NSSize(width: 860, height: 620))
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
    handback.giveBack()
  }

  // MARK: Private

  private let store: StoreOf<SettingsWindowFeature>
  private var window: NSWindow?
  private let handback = ActivationHandback()
}
