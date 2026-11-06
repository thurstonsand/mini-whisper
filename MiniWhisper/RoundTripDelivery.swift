import AppKit
import ApplicationServices
import CoreGraphics
import FieldContext

// MARK: - RoundTripDelivery

/// Electron drops every keystroke and Accessibility write while its app is inactive, so a target
/// in one is brought forward for the paste and the user is put back where they were. Whatever
/// they do while it is borrowed is held back from it and replayed into their own app once they
/// are back; if they act before the paste, the paste is called off. It waits for a lull in their
/// typing and clicking first, since a borrow they cut short delivers nothing.
@MainActor enum RoundTripDelivery {
  // MARK: Internal

  enum Outcome: Equatable {
    case delivered(ClipboardRestoration)
    case keysHeld
    /// The user is in the target app, somewhere other than the field; their focus is theirs.
    case targetInUse
    /// The target did not come forward with focus on its field.
    case unreachable
    /// The user never paused, was in MiniWhisper itself, or acted while the target was being
    /// brought forward.
    case interrupted
    case eventCreationFailed
  }

  static func deliver(_ text: String, to target: DeliveryTarget, submits: Bool) async throws
    -> Outcome
  {
    // A web area stands in for whatever field inside it ends up focused, which only a field
    // captured itself rules out.
    guard let processID = target.processID, let role = target.address?.role,
          !FieldTargetPolicy.isContainer(role: role)
    else {
      return .unreachable
    }
    guard await userPaused() else {
      return .interrupted
    }
    guard let user = NSWorkspace.shared.frontmostApplication?.processIdentifier,
          user != ProcessInfo.processInfo.processIdentifier
    else {
      return .interrupted
    }
    guard user != processID else {
      guard let here = FocusSpot.focused(in: processID).finds(target) else {
        return .targetInUse
      }
      return try await outcome(of: ClipboardPaste.paste(text, submits: submits) {
        FocusSpot.frontmost()?.holds(here) == true
      })
    }
    let userSpot = FocusSpot.inside(user)
    guard let hold = InputHold.start() else {
      return .eventCreationFailed
    }
    defer { hold.release() }

    bringForward(processID)
    if let window = target.window?.raw {
      AXUIElementSetMessagingTimeout(window, messagingTimeout)
      AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }
    var found: DeliveryTarget?
    if await becameFrontmost(processID), !hold.isTouched,
       await FocusSpot(target: target).restore()
    {
      found = FocusSpot.focused(in: processID).finds(target)
    }
    guard !hold.isTouched, let found else {
      let outcome: Outcome = hold.isTouched ? .interrupted : .unreachable
      await giveBack(to: userSpot, from: processID)
      return outcome
    }

    let outcome: Outcome
    do {
      outcome = try await self.outcome(of: ClipboardPaste.paste(text, submits: submits) {
        isFrontmost(processID) && !hold.isTouched
          && FocusSpot.focused(in: processID).holds(found)
      })
    } catch {
      await giveBack(to: userSpot, from: processID)
      throw error
    }
    try? await Task.sleep(for: settleDelay)
    await giveBack(to: userSpot, from: processID)
    return outcome
  }

  /// A pause is no recent input and nothing held down: a held hotkey or a drag in progress sends
  /// no events, but the target coming forward under it would take them.
  static func userPaused() async -> Bool {
    let deadline = ContinuousClock.now + pauseBudget
    while isUserActive() {
      guard ContinuousClock.now < deadline else {
        return false
      }
      do { try await Task.sleep(for: pausePoll) } catch { return false }
    }
    return true
  }

  // MARK: Private

  /// Input that ends a pause.
  private static let watched: [CGEventType] = [
    .keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel,
  ]
  private static let mouseButtons: [CGMouseButton] = [.left, .right, .center]
  private static let messagingTimeout: Float = 0.25
  private static let arrivalPoll = Duration.milliseconds(20)
  private static let arrivalBudget = Duration.seconds(1)
  /// Long enough for the app to take the paste before it is sent to the back.
  private static let settleDelay = Duration.milliseconds(250)
  private static let pauseThreshold: CFTimeInterval = 0.5
  private static let pausePoll = Duration.milliseconds(50)
  /// A user who has not stopped for this long keeps the transcript on the clipboard instead.
  private static let pauseBudget = Duration.seconds(10)

  private static func outcome(of paste: ClipboardPaste.Outcome) -> Outcome {
    switch paste {
    case let .pasted(restoration):
      .delivered(restoration)
    case .keysHeld:
      .keysHeld
    case .focusMoved:
      .interrupted
    case .eventCreationFailed:
      .eventCreationFailed
    }
  }

  private static func isFrontmost(_ processID: pid_t) -> Bool {
    NSWorkspace.shared.frontmostApplication?.processIdentifier == processID
  }

  /// Through Accessibility, which brings an app forward from a menu bar app that is not itself
  /// active; `NSRunningApplication.activate` only asks.
  private static func bringForward(_ processID: pid_t) {
    let application = AXUIElementCreateApplication(processID)
    AXUIElementSetMessagingTimeout(application, messagingTimeout)
    AXUIElementSetAttributeValue(application, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
  }

  private static func becameFrontmost(_ processID: pid_t) async -> Bool {
    let deadline = ContinuousClock.now + arrivalBudget
    while !isFrontmost(processID) {
      guard ContinuousClock.now < deadline else {
        return false
      }
      do { try await Task.sleep(for: arrivalPoll) } catch { return false }
    }
    return true
  }

  private static func isUserActive() -> Bool {
    let sinceLastInput = watched.map {
      CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0)
    }
    .min() ?? .infinity
    return sinceLastInput < pauseThreshold || ClipboardPaste.isAnyKeyHeld()
      || mouseButtons.contains { CGEventSource.buttonState(.hidSystemState, button: $0) }
  }

  /// A user who has gone to a third app on their own is left there. Runs to the end even when
  /// the delivery is cancelled, since a user left in the target app is worse than a late one.
  private static func giveBack(to spot: FocusSpot, from processID: pid_t) async {
    await Task {
      guard isFrontmost(processID) else {
        return
      }
      bringForward(spot.processID)
      if let window = spot.window {
        AXUIElementSetMessagingTimeout(window, messagingTimeout)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
      }
      guard await becameFrontmost(spot.processID) else {
        return
      }
      _ = await spot.restore()
    }.value
  }
}
