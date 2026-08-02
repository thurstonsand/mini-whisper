import AppKit
import ComposableArchitecture
import SwiftUI

@MainActor final class OnboardingWindowController {
  private let store: StoreOf<OnboardingFeature>
  private let window: NSWindow
  private var activationObserver: (any NSObjectProtocol)?
  private var renderedVisibility: Bool?
  private var renderedPermissions: OnboardingPermissionStatuses?

  init(store: StoreOf<OnboardingFeature>, observesApplicationActivation: Bool = true) {
    self.store = store
    self.window = NSWindow(
      contentRect: .zero, styleMask: [.titled, .fullSizeContentView], backing: .buffered,
      defer: false)
    window.title = "Set Up MiniWhisper"
    window.setAccessibilityIdentifier(AccessibilityID.onboardingWindow)
    window.setAccessibilityLabel("Set Up MiniWhisper")
    window.setAccessibilityTitle("Set Up MiniWhisper")
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.isMovableByWindowBackground = true
    window.isReleasedWhenClosed = false
    window.collectionBehavior = [.moveToActiveSpace]
    window.contentView = NSHostingView(rootView: OnboardingView(store: store))
    window.setContentSize(NSSize(width: 720, height: 500))

    if observesApplicationActivation {
      activationObserver = NotificationCenter.default.addObserver(
        forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
      ) { [weak self] _ in MainActor.assumeIsolated { self?.applicationBecameActive() } }
    }

    observeStore()
    render()
  }

  isolated deinit {
    if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
  }

  private func observeStore() {
    withObservationTracking {
      _ = self.store.isPresented
      _ = self.store.snapshot.permissions
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.observeStore()
        self.render()
      }
    }
  }

  private func render() {
    let isVisible = store.isPresented
    let permissions = store.snapshot.permissions
    let wasVisible = renderedVisibility
    let visibilityChanged = wasVisible != isVisible
    let permissionsChanged = renderedPermissions != permissions
    renderedVisibility = isVisible
    renderedPermissions = permissions

    guard isVisible else {
      window.orderOut(nil)
      if wasVisible == true { NSApp.hide(nil) }
      return
    }
    guard visibilityChanged || permissionsChanged else { return }
    if visibilityChanged { window.center() }
    activateWindow()
  }

  private func applicationBecameActive() {
    guard store.isPresented else { return }
    store.send(.applicationBecameActive)
    window.makeKeyAndOrderFront(nil)
  }

  private func activateWindow() {
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }
}
