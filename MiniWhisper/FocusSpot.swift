import AppKit
import ApplicationServices
import History

// MARK: - FocusSpot

/// Where keyboard focus sits: an app, its focused window, and its focused element. A delivery to
/// a target that lost focus remembers the user's spot, brings the target's back, and then puts
/// the user's back.
///
/// Focus moves through Accessibility, not `NSRunningApplication.activate`, which macOS lets an
/// accessory app use only cooperatively. `kAXFrontmostAttribute` brings the app forward,
/// `AXRaise` brings the window — selecting its tab when the window is one of a tab group — and
/// `kAXFocusedAttribute` brings the element.
@MainActor struct FocusSpot {
  // MARK: Lifecycle

  init(processID: pid_t, window: AXUIElement?, element: AXUIElement?) {
    self.processID = processID
    self.window = window
    self.element = element
  }

  init(target: DeliveryTarget) {
    self.init(
      processID: target.processID ?? -1, window: target.window?.raw, element: target.element?.raw,
    )
  }

  // MARK: Internal

  /// The user's spot while a delivery has borrowed focus for a round trip. Whatever is frontmost
  /// then is the delivery's target, not where the user is.
  static var displaced: FocusSpot?

  let processID: pid_t
  let window: AXUIElement?
  let element: AXUIElement?

  /// The target a press made here would capture.
  var target: DeliveryTarget {
    let application = NSRunningApplication(processIdentifier: processID)
    return DeliveryTarget(
      app: application?.bundleIdentifier.map {
        TargetApp(bundleID: $0, name: application?.localizedName)
      },
      processID: processID, window: window.map(AXElement.init(raw:)),
      element: element.map(AXElement.init(raw:)), pane: nil,
    )
  }

  /// Where the user is: their spot, even while a round trip has focus elsewhere.
  static func user() -> FocusSpot? {
    displaced ?? current()
  }

  static func current() -> FocusSpot? {
    guard let frontmost = NSWorkspace.shared.frontmostApplication else {
      return nil
    }
    let application = AXUIElementCreateApplication(frontmost.processIdentifier)
    AXUIElementSetMessagingTimeout(application, Self.messagingTimeout)
    return FocusSpot(
      processID: frontmost.processIdentifier,
      window: try? AXRead.element(application, kAXFocusedWindowAttribute).get(),
      element: FocusedFieldReader.focusedElement(of: frontmost.processIdentifier),
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
    return element.map { FocusedFieldReader.isElement($0, within: captured) } ?? false
  }

  /// Brings this spot's focus back. Verifying waits until the app is frontmost and the element
  /// focused, and reports whether that happened in time.
  func bring(verifying: Bool) async -> Bool {
    let application = AXUIElementCreateApplication(processID)
    AXUIElementSetMessagingTimeout(application, Self.messagingTimeout)
    AXUIElementSetAttributeValue(application, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    if let window {
      AXUIElementSetMessagingTimeout(window, Self.messagingTimeout)
      AXUIElementPerformAction(window, kAXRaiseAction as CFString)
      AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
    }
    if let element {
      AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
      AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }
    guard verifying else {
      return true
    }

    let deadline = ContinuousClock.now + verificationBudget
    while ContinuousClock.now < deadline {
      if isFocused(application) {
        return true
      }
      do { try await Task.sleep(for: verificationPoll) } catch { return false }
    }
    return isFocused(application)
  }

  // MARK: Private

  private static let messagingTimeout: Float = 0.25

  private let verificationBudget = Duration.milliseconds(400)
  private let verificationPoll = Duration.milliseconds(10)

  private func isFocused(_ application: AXUIElement) -> Bool {
    guard (try? AXRead.bool(application, kAXFrontmostAttribute).get()) == true else {
      return false
    }
    guard let element else {
      return true
    }
    return FocusedFieldReader.focusedElement(of: processID).map {
      FocusedFieldReader.isElement($0, within: element)
    } ?? false
  }
}
