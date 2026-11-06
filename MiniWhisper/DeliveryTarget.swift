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

// MARK: - FieldAddress

/// A field in a web page, named by the page and the field rather than by the element itself.
/// Electron apps build a new editor or composer element whenever the user leaves a document or
/// chat and comes back; the new one sits at the same address.
struct FieldAddress: Equatable {
  var url: String
  var role: String
  var label: String
}

// MARK: - DeliveryTarget

/// Where a dictation delivers, captured at the press that starts it. A pane or a Ghostty terminal,
/// when there is one, is the whole answer; otherwise the app's window, the tabs selected in it,
/// and the focused element are what a delivery has to find again inside that app. The element is
/// the end of the focus chain, and the field's text is read from it only at delivery.
struct DeliveryTarget: Equatable {
  /// Nothing was frontmost, or Accessibility is not granted, so there was nothing to capture.
  static let none = DeliveryTarget(app: nil, processID: nil, window: nil, element: nil, pane: nil)

  var app: TargetApp?
  var processID: pid_t?
  var window: AXElement?
  /// The tabs selected in the window, which a browser needs pressed again before an element in
  /// one of them can take focus.
  var tabs: [AXElement] = []
  var element: AXElement?
  /// Where the element sits in its page, when it sits in one.
  var address: FieldAddress?
  /// The window's title, which is how a person tells one destination in an app from another.
  var title: String?
  var pane: TmuxPane?
  var terminal: GhosttyTerminal?

  /// Whether delivery goes through the app's own windows: everything but a pane or a Ghostty
  /// terminal, which are written to out of band.
  var isGUI: Bool {
    pane == nil && terminal == nil
  }

  /// What the pill calls this destination once the user has looked away from it.
  var destination: String? {
    guard let name = app?.name ?? app?.bundleID else {
      return nil
    }
    // Browsers end their window titles with their own name, which the label already leads with.
    var detail = pane?.session ?? title ?? ""
    for separator in [" - ", " — "] where detail.hasSuffix(separator + name) {
      detail.removeLast(separator.count + name.count)
    }
    guard !detail.isEmpty, detail != name else {
      return name
    }
    return "\(name) · \(detail)"
  }

  /// Whether two targets are one destination. A pane is its server and id, a terminal its id;
  /// anything else is the focused element of one process.
  func isSameDestination(as other: DeliveryTarget) -> Bool {
    if let pane, let otherPane = other.pane {
      return pane.socket == otherPane.socket && pane.paneID == otherPane.paneID
    }
    if let terminal, let otherTerminal = other.terminal {
      return terminal.processID == otherTerminal.processID && terminal.id == otherTerminal.id
    }
    guard pane == nil, other.pane == nil, terminal == nil, other.terminal == nil,
          let processID, processID == other.processID
    else {
      return false
    }
    return element == other.element
  }
}

// MARK: - DeliveryTargetClient

@DependencyClient struct DeliveryTargetClient {
  /// The target in front of the user right now.
  var capture: @Sendable () async -> DeliveryTarget = { .none }
  /// Whether the user is at this target right now, judged as delivery judges it. Synchronous,
  /// because the event tap asks it about a Return before the Return goes anywhere.
  var isCurrent: @Sendable (DeliveryTarget) -> Bool = { _ in false }
}

// MARK: DependencyKey

extension DeliveryTargetClient: DependencyKey {
  static let testValue = Self(capture: { .none }, isCurrent: { _ in false })

  static let liveValue = Self(
    capture: {
      let clock = ContinuousClock()
      let started = clock.now
      let resolved = resolve(FocusedFieldReader.target())
      let duration = started.duration(to: clock.now).components
      let elapsed = Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15
      contextLogger.info(
        "Target capture \(resolved.logDescription, privacy: .public) elapsed=\(elapsed, format: .fixed(precision: 1))ms",
      )
      return resolved
    },
    isCurrent: { target in
      // The cheap answer first: the pill asks this twice a second, the tap on every Return while
      // a dictation is owed, and the user is usually in another app entirely.
      let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
      guard let processID = target.processID, frontmost == processID else {
        return false
      }
      guard target.isGUI else {
        // A pane or terminal is found from the process alone; its focused element is not needed.
        let here = DeliveryTarget(
          app: target.app, processID: processID, window: nil, element: nil, pane: nil,
        )
        return resolve(here).isSameDestination(as: target)
      }
      return FocusSpot.focused(in: processID).finds(target) != nil
    },
  )

  /// A terminal surface's pane or Ghostty terminal is found behind its app's process.
  private static func resolve(_ located: DeliveryTarget) -> DeliveryTarget {
    var resolved = located
    guard let processID = resolved.processID else {
      return resolved
    }
    resolved.pane = TmuxPanes.resolve(under: processID)
    if resolved.pane == nil, resolved.app?.bundleID == GhosttyTerminals.bundleID {
      resolved.terminal = GhosttyTerminals.focused(in: processID)
    }
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
      } else if let terminal {
        "ghostty-terminal=\(terminal.id) foreground=\(terminal.foregroundProcessID)"
      } else {
        "element=\(element == nil ? "none" : "captured")"
      }
    return "bundle=\(app?.bundleID ?? "?") pid=\(processID ?? -1) \(route)"
  }
}
