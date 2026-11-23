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

    let hostingView = NSHostingView(rootView: PillView(store: store) { [weak self] width in
      self?.resizePanel(width: width)
    })
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
  /// The longest exit PillView animates, with a frame to spare.
  private static let exitDuration = Duration.milliseconds(200)

  private let store: StoreOf<PillFeature>
  private let panel: NonactivatingPillPanel
  private var screenParametersObserver: any NSObjectProtocol?
  private var lastVisibility: Bool?
  private var panelWidth = panelSize.width
  /// Chosen when the pill appears and kept until it is gone: the dictation does not move, so the
  /// pill does not follow the pointer or a later change of focus.
  private var screen: NSScreen?
  private var pendingHide: Task<Void, Never>?

  private func resizePanel(width: CGFloat) {
    guard width > 20, width != panelWidth else {
      return
    }
    panelWidth = width
    positionPanel()
  }

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
    let wasVisible = lastVisibility == true
    lastVisibility = isVisible

    guard isVisible else {
      guard wasVisible else {
        return
      }
      // The view plays its own exit transition; ordering the panel out at once would cut it.
      pendingHide = Task { [weak self] in
        try? await Task.sleep(for: Self.exitDuration)
        guard !Task.isCancelled, let self else {
          return
        }
        panel.orderOut(nil)
        screen = nil
        pendingHide = nil
      }
      return
    }

    if let pendingHide {
      pendingHide.cancel()
      self.pendingHide = nil
    } else {
      screen = PillScreen.atPress()
    }
    positionPanel()
    panel.orderFrontRegardless()
    performanceLogger.notice("benchmark pill-visible")
  }

  private func positionPanel() {
    if let chosen = screen, !NSScreen.screens.contains(chosen) {
      screen = PillScreen.atPress()
    }
    guard let screen = screen ?? NSScreen.screens.first else {
      pillPanelLogger.error("Cannot position the pill because no screen is available")
      panel.orderOut(nil)
      return
    }

    let frame = NSRect(
      x: screen.frame.midX - panelWidth / 2,
      y: screen.visibleFrame.minY + Self.bottomMargin, width: panelWidth,
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
