import AppKit
import ApplicationServices
import Carbon
import ComposableArchitecture
import CoreGraphics
import Foundation
import HotkeyListener

// MARK: - ClipboardRestoration

enum ClipboardRestoration: Equatable {
  case restored
  case skipped
  case failed
  /// The delivery never touched the clipboard: it was written into a pane.
  case untouched
}

// MARK: - DeliveryFallback

enum DeliveryFallback: Equatable {
  case accessibilityPermissionMissing
  case secureInput
  case eventCreationFailed
  /// The pane closed or the app quit since the dictation started.
  case targetGone
  /// The pane's foreground command changed under a submit.
  case targetChanged
  /// The target could not be given focus back.
  case targetUnreachable
}

// MARK: - NoReceiverReason

enum NoReceiverReason: Equatable {
  case noFocusedElement
  case nonTextElement(role: String?)
}

// MARK: - DeliveryOutcome

enum DeliveryOutcome: Equatable {
  case pasted(ClipboardRestoration)
  case copied(DeliveryFallback)
  case noReceiver(NoReceiverReason)
}

// MARK: - DeliveryError

enum DeliveryError: Error, Equatable { case pasteboardWriteFailed }

// MARK: - DeliveryClient

@DependencyClient struct DeliveryClient {
  /// Writes the text into the target, then Return when it `submits`.
  var deliver: @Sendable (_ text: String, _ target: DeliveryTarget, _ submits: Bool) async throws
    -> DeliveryOutcome
  var copy: @Sendable (String) async throws -> Void
}

// MARK: DependencyKey

extension DeliveryClient: DependencyKey {
  static let liveValue = Self(
    deliver: { text, target, submits in
      guard let pane = target.pane else {
        return try await TranscriptDelivery.deliver(text, to: target, submits: submits)
      }
      switch TmuxPanes.deliver(text, submit: submits, to: pane) {
      case .delivered:
        return .pasted(.untouched)
      case .gone:
        try await TranscriptDelivery.copy(text)
        return .copied(.targetGone)
      case .changed:
        try await TranscriptDelivery.copy(text)
        return .copied(.targetChanged)
      }
    },
    copy: { transcript in try await TranscriptDelivery.copy(transcript) },
  )
}

extension DependencyValues {
  var delivery: DeliveryClient {
    get { self[DeliveryClient.self] }
    set { self[DeliveryClient.self] = newValue }
  }
}

// MARK: - TranscriptDelivery

@MainActor private enum TranscriptDelivery {
  // MARK: Internal

  @discardableResult static func copy(_ transcript: String) throws -> Int {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    guard pasteboard.setString(transcript, forType: .string) else {
      throw DeliveryError.pasteboardWriteFailed
    }
    return pasteboard.changeCount
  }

  /// A GUI target takes a paste where it has focus. One that lost focus gets it back for the
  /// paste and gives it up again: whatever the user is in now is put back as it was. A target that
  /// cannot be focused, or verified as focused, keeps the transcript on the clipboard instead.
  static func deliver(
    _ transcript: String, to target: DeliveryTarget, submits: Bool,
  ) async throws -> DeliveryOutcome {
    let pasteboard = NSPasteboard.general
    let snapshot = snapshot(pasteboard)
    let transcriptChangeCount = try copy(transcript)

    guard !IsSecureEventInputEnabled() else {
      return .copied(.secureInput)
    }
    guard AXIsProcessTrusted() else {
      return .copied(.accessibilityPermissionMissing)
    }
    guard let paste = keyEvents(virtualKey: vKey, flags: .maskCommand),
          let submit = keyEvents(virtualKey: returnKey, flags: [])
    else {
      return .copied(.eventCreationFailed)
    }
    guard let processID = target.processID,
          let application = NSRunningApplication(processIdentifier: processID),
          !application.isTerminated
    else {
      return .copied(.targetGone)
    }

    let previous = FocusSpot.current()
    let needsRoundTrip = previous.map { !$0.holds(target) } ?? true
    if needsRoundTrip {
      FocusSpot.displaced = previous
      guard await FocusSpot(target: target).bring(verifying: true) else {
        _ = await previous?.bring(verifying: false)
        FocusSpot.displaced = nil
        return .copied(.targetUnreachable)
      }
    }
    defer { FocusSpot.displaced = nil }

    try await post(paste)
    if submits {
      // A paste can still be landing when the next key arrives; Return must come after it.
      try await Task.sleep(for: submitDelay)
      try await post(submit)
    }
    if needsRoundTrip, let previous {
      // The events are queued to the target; handing focus away before they drain could
      // deliver them to whatever takes it.
      try await Task.sleep(for: roundTripSettle)
      _ = await previous.bring(verifying: false)
    }

    try await Task.sleep(for: clipboardRestoreDelay)
    guard pasteboard.changeCount == transcriptChangeCount else {
      return .pasted(.skipped)
    }

    pasteboard.clearContents()
    guard snapshot.isEmpty || pasteboard.writeObjects(pasteboardItems(from: snapshot)) else {
      return .pasted(.failed)
    }
    return .pasted(.restored)
  }

  // MARK: Private

  private static let clipboardRestoreDelay = Duration.milliseconds(250)
  private static let keyEventDelay = Duration.milliseconds(10)
  private static let submitDelay = Duration.milliseconds(50)
  private static let roundTripSettle = Duration.milliseconds(150)
  private static let vKey: CGKeyCode = 0x09
  private static let returnKey: CGKeyCode = 0x24
  private static let commandKey: CGKeyCode = 0x37

  private static func snapshot(_ pasteboard: NSPasteboard) -> [[PasteboardRepresentation]] {
    // Eager resolution preserves every available type; promised data may briefly block delivery.
    (pasteboard.pasteboardItems ?? []).map { item in
      item.types.compactMap { type in
        item.data(forType: type).map { PasteboardRepresentation(type: type, data: $0) }
      }
    }
  }

  private static func pasteboardItems(
    from snapshot: [[PasteboardRepresentation]],
  ) -> [NSPasteboardItem] {
    snapshot.map { representations in
      let item = NSPasteboardItem()
      for representation in representations {
        item.setData(representation.data, forType: representation.type)
      }
      return item
    }
  }

  private static func post(_ events: [CGEvent]) async throws {
    for event in events {
      event.post(tap: .cghidEventTap)
      try await Task.sleep(for: keyEventDelay)
    }
  }

  /// One key's down and up, wrapped in Command's when `flags` asks for it.
  private static func keyEvents(virtualKey: CGKeyCode, flags: CGEventFlags) -> [CGEvent]? {
    let source = CGEventSource(stateID: .privateState)
    guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true),
          let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false)
    else {
      return nil
    }
    keyDown.flags = flags
    keyUp.flags = flags
    var events = [keyDown, keyUp]
    if flags.contains(.maskCommand) {
      guard let commandDown = CGEvent(
        keyboardEventSource: source, virtualKey: commandKey, keyDown: true,
      ),
        let commandUp = CGEvent(keyboardEventSource: source, virtualKey: commandKey, keyDown: false)
      else {
        return nil
      }
      commandDown.flags = .maskCommand
      events = [commandDown] + events + [commandUp]
    }
    for event in events {
      event.setIntegerValueField(.eventSourceUserData, value: HotkeyListener.syntheticEventMarker)
    }
    return events
  }
}

// MARK: - PasteboardRepresentation

private struct PasteboardRepresentation {
  var type: NSPasteboard.PasteboardType
  var data: Data
}
