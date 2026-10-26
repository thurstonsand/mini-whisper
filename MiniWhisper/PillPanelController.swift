import AppKit
import ComposableArchitecture
import OSLog
import SwiftUI

private let pillPanelLogger = Logger(
  subsystem: "com.thurstonsand.MiniWhisper", category: "pill-panel",
)
private let performanceLogger = Logger(
  subsystem: "com.thurstonsand.MiniWhisper", category: "performance",
)

// MARK: - PillPanelController

@MainActor final class PillPanelController {
  // MARK: Lifecycle

  init(store: StoreOf<PillFeature>) {
    self.store = store
    panel = NonactivatingPillPanel()

    panel.title = "\(Channel.name) dictation"
    panel.setAccessibilityIdentifier(AccessibilityID.pill)
    panel.setAccessibilityLabel("\(Channel.name) dictation")
    panel.setAccessibilityTitle("\(Channel.name) dictation")

    let hostingView = NSHostingView(rootView: PillView(store: store))
    hostingView.frame = NSRect(origin: .zero, size: Self.panelSize)
    panel.contentView = hostingView
    panel.setContentSize(Self.panelSize)

    screenParametersObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main,
    ) { [weak self] _ in MainActor.assumeIsolated { self?.positionPanel() } }

    observeStore()
    render(isVisible: store.presentation != nil)
  }

  isolated deinit {
    if let screenParametersObserver {
      NotificationCenter.default.removeObserver(screenParametersObserver)
    }
  }

  // MARK: Private

  private static let panelSize = NSSize(width: 420, height: 76)
  private static let bottomMargin: CGFloat = 14

  private let store: StoreOf<PillFeature>
  private let panel: NonactivatingPillPanel
  private var screenParametersObserver: (any NSObjectProtocol)?
  private var lastVisibility: Bool?

  private func observeStore() {
    withObservationTracking {
      _ = self.store.presentation
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else {
          return
        }
        observeStore()
        render(isVisible: store.presentation != nil)
      }
    }
  }

  private func render(isVisible: Bool) {
    panel.setAccessibilityValue(isVisible ? "Visible" : "Hidden")
    guard isVisible != lastVisibility else {
      return
    }
    lastVisibility = isVisible

    guard isVisible else {
      panel.orderOut(nil)
      return
    }

    positionPanel()
    panel.orderFrontRegardless()
    performanceLogger.notice("benchmark pill-visible")
  }

  private func positionPanel() {
    guard let screen = NSScreen.screens.first else {
      pillPanelLogger.error("Cannot position the pill because no screen is available")
      panel.orderOut(nil)
      return
    }

    let frame = NSRect(
      x: screen.frame.midX - Self.panelSize.width / 2,
      y: screen.visibleFrame.minY + Self.bottomMargin, width: Self.panelSize.width,
      height: Self.panelSize.height,
    )
    panel.setFrame(frame, display: panel.isVisible)
  }
}

// MARK: - NonactivatingPillPanel

private final class NonactivatingPillPanel: NSPanel {
  // MARK: Lifecycle

  init() {
    super.init(
      contentRect: .zero,
      styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel, .utilityWindow],
      backing: .buffered, defer: false,
    )
    level = .statusBar
    backgroundColor = .clear
    isOpaque = false
    hasShadow = false
    ignoresMouseEvents = true
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
  }

  // MARK: Internal

  override var canBecomeKey: Bool {
    false
  }

  override var canBecomeMain: Bool {
    false
  }
}
