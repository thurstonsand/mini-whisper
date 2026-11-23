import AppKit
import ApplicationServices

// MARK: - PillScreen

/// Which display the pill belongs on: the one holding the window the user is typing into, which
/// is where the dictation will land. `NSScreen.main` is not that for a background app — it
/// follows the active menu bar, and is the primary display outright with separate Spaces off or
/// over a full-screen app — so the window is asked directly, and the pointer stands in when the
/// window cannot say.
enum PillScreen {
  // MARK: Internal

  /// Read once, at the press that shows the pill.
  @MainActor static func atPress() -> NSScreen? {
    let screens = NSScreen.screens
    guard screens.count > 1 else {
      return screens.first
    }
    let index = choose(
      windowFrame: focusedWindowFrame(), mouse: NSEvent.mouseLocation,
      screens: screens.map(\.frame),
    )
    return index.map { screens[$0] }
  }

  /// The screen holding most of `windowFrame`, else the one under `mouse`, else the primary.
  /// `windowFrame` is in Accessibility's space — top-left origin on the primary display — and
  /// `screens` in AppKit's, with the primary first.
  static func choose(windowFrame: CGRect?, mouse: CGPoint, screens: [CGRect]) -> Int? {
    guard let primary = screens.first else {
      return nil
    }
    if let windowFrame {
      let flipped = CGRect(
        x: windowFrame.minX, y: primary.maxY - windowFrame.maxY, width: windowFrame.width,
        height: windowFrame.height,
      )
      let overlaps = screens.map { area($0.intersection(flipped)) }
      if let best = overlaps.indices.max(by: { overlaps[$0] < overlaps[$1] }), overlaps[best] > 0 {
        return best
      }
    }
    return screens.firstIndex { $0.contains(mouse) } ?? 0
  }

  // MARK: Private

  /// Two reads stand between the press and the pill, whose whole budget is 25 ms. A window that
  /// cannot answer in time gives way to the pointer.
  private static let messagingTimeout: Float = 0.01

  private static func focusedWindowFrame() -> CGRect? {
    guard let app = NSWorkspace.shared.frontmostApplication else {
      return nil
    }
    let application = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(application, messagingTimeout)
    guard case let .success(window) = AXRead.element(application, kAXFocusedWindowAttribute) else {
      return nil
    }
    AXUIElementSetMessagingTimeout(window, messagingTimeout)
    return AXRead.frame(window)
  }

  private static func area(_ rect: CGRect) -> CGFloat {
    rect.isNull ? 0 : rect.width * rect.height
  }
}
