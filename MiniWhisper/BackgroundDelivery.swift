import AppKit
import ApplicationServices
import CoreGraphics
import FieldContext
import History
import HotkeyListener
import OSLog

private let deliveryLogger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "delivery")

// MARK: - BackgroundDelivery

/// Delivers to a GUI target the user has looked away from, without ever changing which app is
/// frontmost. A native text field takes the words through Accessibility, confirmed by reading the
/// field back. Anything else, such as a browser, has its own focus put back on the
/// field inside the app, receives the words as keystrokes posted to its process alone, and then
/// has its focus put back where it was. The user's keyboard keeps going to the app they are in.
@MainActor enum BackgroundDelivery {
  // MARK: Internal

  enum Outcome: Equatable {
    case delivered
    /// The user is in the target app, somewhere other than the field; their focus is theirs.
    case targetInUse
    /// The field could not be given the app's focus again, or ignored the keystrokes.
    case unreachable
    /// The user came back to the target app and moved its focus off the field mid-typing.
    case interrupted
    /// The field changed in a way the words do not explain, so whether they landed is unknown.
    case unconfirmed
  }

  static func deliver(_ text: String, to target: DeliveryTarget, submits: Bool) async -> Outcome {
    // A terminal reads a typed line break as Return, and its screen cannot witness what landed.
    guard let processID = target.processID, let field = target.element?.raw,
          !TerminalBundleIDs.contains(target.app?.bundleID)
    else {
      return .unreachable
    }
    AXUIElementSetMessagingTimeout(field, messagingTimeout)
    // A single-line field takes Return as its form's submit, wherever it falls in the words.
    let text =
      (try? AXRead.string(field, kAXRoleAttribute).get()) == kAXTextFieldRole
        ? text.split(whereSeparator: \.isNewline).joined(separator: " ")
        : text

    // A native field can be written while unfocused, so nothing has to move for the words.
    let written: Bool
    switch await write(text, into: field) {
    case .inserted:
      written = true
    case .unverified:
      return .unconfirmed
    case .notInserted:
      written = false
    }
    guard !written || submits else {
      return .delivered
    }
    guard !isFrontmost(processID) else {
      guard written else {
        return .targetInUse
      }
      await submitBesideUser(field, target: target, processID: processID)
      return .delivered
    }

    let ownSpot = FocusSpot.inside(processID)
    let moved = !ownSpot.holds(target)
    if moved, await !(FocusSpot(target: target).restore()) {
      _ = await ownSpot.restore()
      if written {
        deliveryLogger.notice("Written, but the field would not take focus for Return")
        return .delivered
      }
      return .unreachable
    }
    let outcome = written ? .delivered : await type(
      text,
      into: field,
      of: processID,
      target: target,
    )
    guard outcome == .delivered else {
      // Keystrokes the app has not drained yet would follow its focus; they belong in the field.
      return outcome
    }
    if submits {
      if FocusSpot.focused(in: processID).holds(target) {
        post(key: returnKey, to: processID)
        await settle(field)
      } else {
        deliveryLogger.notice("Delivered; focus left the field, so Return is the user's")
      }
    }
    // Once the user has come back to the app, where its focus sits is theirs again.
    if moved, !isFrontmost(processID) {
      _ = await ownSpot.restore()
    }
    return .delivered
  }

  // MARK: Private

  private enum Write: Equatable {
    case inserted
    case notInserted
    case unverified
  }

  private static let returnKey: CGKeyCode = 0x24
  private static let messagingTimeout: Float = 0.25
  private static let maximumAncestorDepth = 32
  private static let readBackPoll = Duration.milliseconds(30)
  private static let readBackAttempts = 10
  private static let drainPoll = Duration.milliseconds(30)
  /// How long a field may sit unchanged before what it has is all it is going to get.
  private static let drainStillPolls = 5
  private static let drainBudget = Duration.seconds(2)
  /// Keystrokes go out a chunk at a time, each one waiting for the field to show the last, so the
  /// app never holds a backlog: a user who comes back is noticed between chunks, and nothing is
  /// left queued to land after the app's focus is handed back.
  private static let typingChunk = 24

  private static func isFrontmost(_ processID: pid_t) -> Bool {
    NSWorkspace.shared.frontmostApplication?.processIdentifier == processID
  }

  /// The words are in, but the user is in another window of the same app, and Return only goes
  /// where the app's focus is. Once they pause, that focus is borrowed for the one key and put
  /// back; anything they do meanwhile is held, and replayed where they were. Input that arrives
  /// before the key goes out leaves the Return to them.
  private static func submitBesideUser(
    _ field: AXUIElement, target: DeliveryTarget, processID: pid_t,
  ) async {
    guard await RoundTripDelivery.userPaused(), isFrontmost(processID),
          let hold = InputHold.start()
    else {
      deliveryLogger.notice("Written; the user kept working in the app, so Return is theirs")
      return
    }
    defer { hold.release() }
    let userSpot = FocusSpot.inside(processID)
    raise(target.window?.raw)
    let focused = await FocusSpot(target: target).restore()
    if focused, !hold.isTouched, FocusSpot.focused(in: processID).holds(target) {
      post(key: returnKey, to: processID)
      await settle(field)
    } else {
      deliveryLogger.notice("Written; the field could not be borrowed for Return")
    }
    raise(userSpot.window)
    _ = await userSpot.restore()
  }

  private static func raise(_ window: AXUIElement?) {
    guard let window else {
      return
    }
    AXUIElementSetMessagingTimeout(window, messagingTimeout)
    AXUIElementPerformAction(window, kAXRaiseAction as CFString)
  }

  /// Inserts at the field's own selection through Accessibility, and reads the field back to
  /// tell an insert from a no-op. Web content acknowledges these writes without applying them,
  /// and a field whose value cannot be read cannot be confirmed, so neither is tried.
  private static func write(_ text: String, into field: AXUIElement) async -> Write {
    var settable = DarwinBoolean(false)
    guard AXUIElementIsAttributeSettable(field, kAXSelectedTextAttribute as CFString, &settable)
      == .success, settable.boolValue, !isWebContent(field),
      let before = try? AXRead.string(field, kAXValueAttribute).get(),
      let range = try? AXRead.range(field, kAXSelectedTextRangeAttribute).get(),
      range.location >= 0, range.location + range.length <= (before as NSString).length
    else {
      return .notInserted
    }
    let expected = (before as NSString).replacingCharacters(
      in: NSRange(location: range.location, length: range.length), with: text,
    )
    AXUIElementSetAttributeValue(field, kAXSelectedTextAttribute as CFString, text as CFString)
    for _ in 0 ..< readBackAttempts {
      let after = try? AXRead.string(field, kAXValueAttribute).get()
      if after == expected {
        return .inserted
      }
      if after != before {
        return .unverified
      }
      do { try await Task.sleep(for: readBackPoll) } catch { return .unverified }
    }
    return .notInserted
  }

  private static func isWebContent(_ element: AXUIElement) -> Bool {
    var current: AXUIElement? = element
    for _ in 0 ..< maximumAncestorDepth {
      guard let candidate = current else {
        return false
      }
      if (try? AXRead.string(candidate, kAXRoleAttribute).get()) == "AXWebArea" {
        return true
      }
      current = try? AXRead.element(candidate, kAXParentAttribute).get()
    }
    return false
  }

  /// One character per event: Chromium takes only the first character of a longer one. A line
  /// break is Shift-Return, which every chat field reads as a new line rather than a send.
  /// Keystrokes are acknowledged whether or not the app acts on them — a background Electron
  /// window drops every one — so the field's length, in UTF-16 units, is the only witness.
  private static func type(
    _ text: String, into field: AXUIElement, of processID: pid_t, target: DeliveryTarget,
  ) async -> Outcome {
    guard let start = characterCount(field),
          let selection = try? AXRead.range(field, kAXSelectedTextRangeAttribute).get()
    else {
      return .unreachable
    }
    var expected = start - selection.length
    var landed = start
    let characters = Array(text)
    for chunkStart in stride(from: 0, to: characters.count, by: typingChunk) {
      // A user who comes back to the field changes nothing: the keys still land there. Focus
      // leaving the field is what stops the typing, wherever the user is.
      guard !Task.isCancelled, FocusSpot.focused(in: processID).holds(target) else {
        if isFrontmost(processID) {
          return .interrupted
        }
        return landed == start ? .unreachable : .unconfirmed
      }
      for character in characters[chunkStart ..< min(chunkStart + typingChunk, characters.count)] {
        if character.isNewline {
          post(key: returnKey, flags: .maskShift, to: processID)
          expected += 1
        } else {
          post(String(character), to: processID)
          expected += String(character).utf16.count
        }
      }
      guard let now = await drain(field, toward: expected), now != landed || now == expected else {
        deliveryLogger.notice("Background keystrokes were not taken")
        return landed == start ? .unreachable : .unconfirmed
      }
      landed = now
    }
    return landed == expected ? .delivered : .unconfirmed
  }

  /// Waits for the app to take what it was sent: until the field is as long as expected, or has
  /// held still long enough that what it has is all it is going to get.
  private static func drain(_ field: AXUIElement, toward expected: Int) async -> Int? {
    var last = characterCount(field)
    var still = 0
    let deadline = ContinuousClock.now + drainBudget
    while last != expected, still < drainStillPolls, ContinuousClock.now < deadline {
      do { try await Task.sleep(for: drainPoll) } catch { return last }
      let now = characterCount(field)
      still = now == last ? still + 1 : 0
      last = now
    }
    return last
  }

  /// Waits until the field stops changing, which is when the app has taken Return.
  private static func settle(_ field: AXUIElement) async {
    _ = await drain(field, toward: -1)
  }

  private static func characterCount(_ field: AXUIElement) -> Int? {
    try? AXRead.count(field, kAXNumberOfCharactersAttribute).get()
  }

  private static func post(_ characters: String, to processID: pid_t) {
    let units = Array(characters.utf16)
    for keyDown in [true, false] {
      guard let event = event(key: 0, keyDown: keyDown, flags: []) else {
        return
      }
      event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
      event.postToPid(processID)
    }
  }

  private static func post(key: CGKeyCode, flags: CGEventFlags = [], to processID: pid_t) {
    for keyDown in [true, false] {
      event(key: key, keyDown: keyDown, flags: flags)?.postToPid(processID)
    }
  }

  /// A private event source, so whatever the user is holding down never leaks into the target.
  private static func event(key: CGKeyCode, keyDown: Bool, flags: CGEventFlags) -> CGEvent? {
    let source = CGEventSource(stateID: .privateState)
    let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: keyDown)
    event?.flags = flags
    event?.setIntegerValueField(.eventSourceUserData, value: HotkeyListener.syntheticEventMarker)
    return event
  }
}
