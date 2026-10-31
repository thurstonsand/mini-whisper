import AppKit
import Carbon
import Foundation
import OSLog

private let deliveryLogger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "delivery")

// MARK: - GhosttyTerminal

/// A Ghostty terminal surface a dictation can be written to by id, whichever tab or window it is
/// in and whatever the user is looking at: Ghostty's scripting dictionary addresses it directly.
struct GhosttyTerminal: Equatable {
  var processID: pid_t
  var id: String
  /// The terminal's foreground process at the press, which a submit must still find running.
  var foregroundProcessID: Int32
}

// MARK: - GhosttyTerminalDelivery

enum GhosttyTerminalDelivery: Equatable {
  case delivered
  /// The terminal closed, or Ghostty quit, since the dictation started.
  case gone
  /// The terminal is running something else now; a submit would run the prompt as a command.
  case changed
  /// Ghostty did not take the text: Automation is not granted, or it did not answer in time.
  case refused
}

// MARK: - GhosttyTerminals

/// Ghostty's AppleScript model, spoken as raw Apple Events to one process id, so a second Ghostty
/// running beside the user's can never be the one that answers. `focused terminal of selected tab
/// of front window` names the surface at the press; `input text` pastes into it the way a
/// terminal paste does, and `send key` presses Return in it. Requires Ghostty 1.4, whose
/// terminals report their foreground process.
enum GhosttyTerminals {
  // MARK: Internal

  static let bundleID = "com.mitchellh.ghostty"

  /// The terminal in front of the user in this Ghostty. The press never waits on the consent
  /// alert: without Automation there is no terminal, and the alert is raised beside the press so
  /// the next dictation has one.
  static func focused(in processID: pid_t) -> GhosttyTerminal? {
    let application = NSAppleEventDescriptor(processIdentifier: processID)
    let status = permission(application, ask: false)
    if status == OSStatus(errAEEventWouldRequireUserConsent) {
      Task.detached {
        _ = permission(NSAppleEventDescriptor(processIdentifier: processID), ask: true)
      }
    }
    guard status == noErr else {
      return nil
    }
    let terminal = property(
      "GTfT", of: property("GWsT", of: property("GFWn", of: .null())),
    )
    guard case let .success(id) = get(property("ID  ", of: terminal), from: application),
          case let .success(foreground) = get(property("Gpid", of: terminal), from: application),
          let id = id.stringValue
    else {
      return nil
    }
    return GhosttyTerminal(
      processID: processID, id: id, foregroundProcessID: foreground.int32Value,
    )
  }

  static func deliver(_ text: String, submit: Bool, to terminal: GhosttyTerminal)
    -> GhosttyTerminalDelivery
  {
    let application = NSAppleEventDescriptor(processIdentifier: terminal.processID)
    let surface = element("Gtrm", id: terminal.id)
    let foreground: Int32
    switch get(property("Gpid", of: surface), from: application) {
    case let .success(reply):
      foreground = reply.int32Value
    case .failure(.noSuchObject):
      return .gone
    case .failure:
      return .refused
    }
    if submit, foreground != terminal.foregroundProcessID {
      return .changed
    }

    let input = command("InTx", direct: NSAppleEventDescriptor(string: text), to: application)
    input.setParam(surface, forKeyword: code("GItT"))
    guard case .success = send(input) else {
      return .refused
    }
    if submit {
      let enter = command("SKey", direct: NSAppleEventDescriptor(string: "enter"), to: application)
      enter.setParam(surface, forKeyword: code("GKeT"))
      // The text is in the terminal either way; a copy of it would only be pasted twice.
      if case .failure = send(enter) {
        deliveryLogger.error("Ghostty took the text but not Return")
      }
    }
    return .delivered
  }

  // MARK: Private

  private enum Failure: Error {
    case noSuchObject
    case refused
  }

  private static let timeout: TimeInterval = 1

  private static func permission(_ application: NSAppleEventDescriptor, ask: Bool) -> OSStatus {
    AEDeterminePermissionToAutomateTarget(
      application.aeDesc, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask,
    )
  }

  private static func code(_ string: String) -> FourCharCode {
    string.utf8.reduce(0) { $0 << 8 | FourCharCode($1) }
  }

  private static func property(_ name: String, of container: NSAppleEventDescriptor)
    -> NSAppleEventDescriptor
  {
    specifier(
      want: FourCharCode(cProperty), form: FourCharCode(formPropertyID),
      data: NSAppleEventDescriptor(typeCode: code(name)), from: container,
    )
  }

  private static func element(_ className: String, id: String) -> NSAppleEventDescriptor {
    specifier(
      want: code(className), form: FourCharCode(formUniqueID),
      data: NSAppleEventDescriptor(string: id), from: .null(),
    )
  }

  private static func specifier(
    want: FourCharCode, form: FourCharCode, data: NSAppleEventDescriptor,
    from container: NSAppleEventDescriptor,
  ) -> NSAppleEventDescriptor {
    let record = NSAppleEventDescriptor.record()
    record.setDescriptor(
      NSAppleEventDescriptor(typeCode: want),
      forKeyword: AEKeyword(keyAEDesiredClass),
    )
    record.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
    record.setDescriptor(
      NSAppleEventDescriptor(enumCode: form),
      forKeyword: AEKeyword(keyAEKeyForm),
    )
    record.setDescriptor(data, forKeyword: AEKeyword(keyAEKeyData))
    return record.coerce(toDescriptorType: DescType(typeObjectSpecifier))!
  }

  private static func get(
    _ specifier: NSAppleEventDescriptor, from application: NSAppleEventDescriptor,
  ) -> Result<NSAppleEventDescriptor, Failure> {
    let event = NSAppleEventDescriptor(
      eventClass: AEEventClass(kAECoreSuite), eventID: AEEventID(kAEGetData),
      targetDescriptor: application, returnID: AEReturnID(kAutoGenerateReturnID),
      transactionID: AETransactionID(kAnyTransactionID),
    )
    event.setParam(specifier, forKeyword: AEKeyword(keyDirectObject))
    return send(event).flatMap { reply in
      reply.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)).map { .success($0) }
        ?? .failure(.refused)
    }
  }

  private static func command(
    _ id: String, direct: NSAppleEventDescriptor, to application: NSAppleEventDescriptor,
  ) -> NSAppleEventDescriptor {
    let event = NSAppleEventDescriptor(
      eventClass: code("Ghst"), eventID: code(id), targetDescriptor: application,
      returnID: AEReturnID(kAutoGenerateReturnID),
      transactionID: AETransactionID(kAnyTransactionID),
    )
    event.setParam(direct, forKeyword: AEKeyword(keyDirectObject))
    return event
  }

  /// The reply; a terminal that no longer exists is told apart from Ghostty refusing, erroring,
  /// or not answering in time.
  private static func send(_ event: NSAppleEventDescriptor)
    -> Result<NSAppleEventDescriptor, Failure>
  {
    guard let reply = try? event.sendEvent(
      options: [.waitForReply, .neverInteract],
      timeout: timeout,
    )
    else {
      return .failure(.refused)
    }
    switch reply.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber))?.int32Value ?? 0 {
    case 0:
      return .success(reply)
    case Int32(errAENoSuchObject):
      return .failure(.noSuchObject)
    default:
      return .failure(.refused)
    }
  }
}
