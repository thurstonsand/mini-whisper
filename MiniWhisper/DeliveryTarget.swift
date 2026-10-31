import AppKit
import ApplicationServices
import ComposableArchitecture
import FieldContext
import Foundation
import History
import OSLog

// MARK: - AXElement

/// An Accessibility element held across the life of a dictation. Equality is the Accessibility
/// API's own: two references to one element compare equal, which is how delivery tells that the
/// field the user is in now is the field they started in.
struct AXElement: Equatable, @unchecked Sendable {
  let raw: AXUIElement

  static func == (lhs: AXElement, rhs: AXElement) -> Bool {
    CFEqual(lhs.raw, rhs.raw)
  }
}

// MARK: - DeliveryTarget

/// Where a dictation delivers, captured at the press that starts it. A pane, when there is one,
/// is the whole answer; the app, window, and element are what a GUI delivery has to bring back.
/// The element is the end of the focus chain, and the field's text is read from it only at
/// delivery.
struct DeliveryTarget: Equatable {
  /// Nothing was frontmost, or Accessibility is not granted, so there was nothing to capture.
  static let none = DeliveryTarget(app: nil, processID: nil, window: nil, element: nil, pane: nil)

  var app: TargetApp?
  var processID: pid_t?
  var window: AXElement?
  var element: AXElement?
  var pane: TmuxPane?

  /// Whether two targets are one destination. A pane is its server and id; anything else is the
  /// focused element of one process.
  func isSameDestination(as other: DeliveryTarget) -> Bool {
    if let pane, let otherPane = other.pane {
      return pane.socket == otherPane.socket && pane.paneID == otherPane.paneID
    }
    guard pane == nil, other.pane == nil, let processID, processID == other.processID else {
      return false
    }
    return element == other.element
  }
}

// MARK: - DeliveryTargetClient

@DependencyClient struct DeliveryTargetClient {
  /// The target in front of the user right now.
  var capture: @Sendable () async -> DeliveryTarget = { .none }
  /// Whether the user is at this target right now, judged as delivery judges it.
  var isCurrent: @Sendable (DeliveryTarget) async -> Bool = { _ in false }
}

// MARK: DependencyKey

extension DeliveryTargetClient: DependencyKey {
  static let testValue = Self(capture: { .none }, isCurrent: { _ in false })

  static let liveValue = Self(
    capture: { await captureLive() },
    isCurrent: { target in
      guard target.pane == nil else {
        return await captureLive().isSameDestination(as: target)
      }
      return await MainActor.run { FocusSpot.user()?.holds(target) ?? false }
    },
  )

  private static func captureLive() async -> DeliveryTarget {
    let clock = ContinuousClock()
    let started = clock.now
    // A round trip borrows focus for a background delivery; a press then is still where the
    // user is, not in the app the delivery brought forward.
    var resolved = await MainActor.run { FocusSpot.displaced?.target }
      ?? FocusedFieldReader.target()
    if let processID = resolved.processID {
      resolved.pane = TmuxPanes.resolve(under: processID)
    }
    let duration = started.duration(to: clock.now).components
    let elapsed = Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15
    contextLogger.info(
      "Target capture \(resolved.logDescription, privacy: .public) elapsed=\(elapsed, format: .fixed(precision: 1))ms",
    )
    return resolved
  }
}

extension DependencyValues {
  var deliveryTarget: DeliveryTargetClient {
    get { self[DeliveryTargetClient.self] }
    set { self[DeliveryTargetClient.self] = newValue }
  }
}

extension DeliveryTarget {
  /// Log-safe: identities and roles, never field text.
  var logDescription: String {
    let route =
      if let pane {
        "pane=\(pane.paneID) socket=\(pane.socket) command=\(pane.command)"
      } else {
        "element=\(element == nil ? "none" : "captured")"
      }
    return "bundle=\(app?.bundleID ?? "?") pid=\(processID ?? -1) \(route)"
  }
}
