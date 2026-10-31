import AppKit
import ApplicationServices

// MARK: - FocusSpot

/// Where keyboard focus sits inside one app: its focused window, the tabs selected in it, and its
/// focused element. Every app keeps its own, frontmost or not, and a background app's can be moved
/// through Accessibility without bringing the app forward — which is the only way MiniWhisper ever
/// moves focus. The app the user is in is never touched.
@MainActor struct FocusSpot {
  // MARK: Lifecycle

  init(processID: pid_t, window: AXUIElement?, tabs: [AXUIElement], element: AXUIElement?) {
    self.processID = processID
    self.window = window
    self.tabs = tabs
    self.element = element
  }

  init(target: DeliveryTarget) {
    self.init(
      processID: target.processID ?? -1, window: target.window?.raw, tabs: target.tabs.map(\.raw),
      element: target.element?.raw,
    )
  }

  // MARK: Internal

  let processID: pid_t
  let window: AXUIElement?
  let tabs: [AXUIElement]
  let element: AXUIElement?

  /// Where the user is, as far as `holds` needs to know.
  static func frontmost() -> FocusSpot? {
    NSWorkspace.shared.frontmostApplication.map { focused(in: $0.processIdentifier) }
  }

  /// Only the focused element of one app: all `holds` reads, and cheap enough to ask often.
  static func focused(in processID: pid_t) -> FocusSpot {
    FocusSpot(
      processID: processID, window: nil, tabs: [],
      element: FocusedFieldReader.focusedElement(of: processID),
    )
  }

  /// One app's whole focus — window, tabs, and element — which is what `restore` puts back.
  static func inside(_ processID: pid_t) -> FocusSpot {
    let application = AXUIElementCreateApplication(processID)
    AXUIElementSetMessagingTimeout(application, messagingTimeout)
    let window = try? AXRead.element(application, kAXFocusedWindowAttribute).get()
    return FocusSpot(
      processID: processID, window: window,
      tabs: window.map(FocusedFieldReader.selectedTabs(in:)) ?? [],
      element: FocusedFieldReader.focusedElement(of: processID),
    )
  }

  /// Whether this spot is the target's: same process, and focus on the element it captured.
  func holds(_ target: DeliveryTarget) -> Bool {
    guard processID == target.processID else {
      return false
    }
    guard let captured = target.element?.raw else {
      return true
    }
    return isFocused(on: captured)
  }

  /// Moves this app's own focus back here, and reports whether its element took it in time. The
  /// window becomes the app's main window without being raised, and its captured tabs are
  /// pressed: a browser brings back the field a tab last had focused. Only an app that names its
  /// focused element in the background has the element focused as well — Safari names none, and
  /// a focus write into it brings it forward.
  func restore() async -> Bool {
    if let window {
      AXUIElementSetMessagingTimeout(window, Self.messagingTimeout)
      AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
    }
    pressUnselectedTabs()
    guard let element else {
      return true
    }
    AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
    var focusWritten = false
    let deadline = ContinuousClock.now + Self.restoreBudget
    while true {
      let now = Self.focused(in: processID)
      if now.isFocused(on: element) {
        return true
      }
      if !focusWritten, now.element != nil {
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        focusWritten = true
        continue
      }
      guard ContinuousClock.now < deadline else {
        return false
      }
      do { try await Task.sleep(for: Self.restorePoll) } catch { return false }
    }
  }

  // MARK: Private

  private static let messagingTimeout: Float = 0.25
  private static let maximumAncestorDepth = 64
  private static let restoreBudget = Duration.milliseconds(400)
  private static let restorePoll = Duration.milliseconds(10)

  private static func hangsUnderWindow(_ element: AXUIElement) -> Bool {
    var current = element
    for _ in 0 ..< maximumAncestorDepth {
      if (try? AXRead.string(current, kAXRoleAttribute).get()) == kAXWindowRole {
        return true
      }
      guard let parent = try? AXRead.element(current, kAXParentAttribute).get() else {
        return false
      }
      current = parent
    }
    return false
  }

  private func isFocused(on captured: AXUIElement) -> Bool {
    if let element {
      return FocusedFieldReader.isElement(element, within: captured)
    }
    // Safari names no focused element while it is in the background. Its field's own `AXFocused`
    // stays true in a hidden tab too, but a hidden tab's elements are cut off from the window;
    // only the selected tab's field still hangs under one.
    return (try? AXRead.bool(captured, kAXFocusedAttribute).get()) == true
      && Self.hangsUnderWindow(captured)
  }

  private func pressUnselectedTabs() {
    for tab in tabs where (try? AXRead.count(tab, kAXValueAttribute).get()) != 1 {
      AXUIElementSetMessagingTimeout(tab, Self.messagingTimeout)
      AXUIElementPerformAction(tab, kAXPressAction as CFString)
    }
  }
}
