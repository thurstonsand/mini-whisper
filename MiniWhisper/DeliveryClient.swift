import AppKit
import Carbon
import ComposableArchitecture
import CoreGraphics
import Foundation

enum ClipboardRestoration: Equatable, Sendable {
  case restored
  case skipped
  case failed
}

enum DeliveryFallback: Equatable, Sendable {
  case accessibilityPermissionMissing
  case secureInput
  case eventCreationFailed
}

enum DeliveryOutcome: Equatable, Sendable {
  case pasted(ClipboardRestoration)
  case copied(DeliveryFallback)
}

enum DeliveryError: Error, Equatable, Sendable { case pasteboardWriteFailed }

@DependencyClient struct DeliveryClient: Sendable {
  var deliver: @Sendable (String) async throws -> DeliveryOutcome
}

extension DeliveryClient: DependencyKey {
  static let liveValue = Self(deliver: { transcript in
    try await TranscriptDelivery.deliver(transcript)
  })
}

extension DependencyValues {
  var delivery: DeliveryClient {
    get { self[DeliveryClient.self] }
    set { self[DeliveryClient.self] = newValue }
  }
}

@MainActor private enum TranscriptDelivery {
  private static let clipboardRestoreDelay = Duration.milliseconds(250)
  private static let pasteShortcutEventDelay = Duration.milliseconds(10)

  static func deliver(_ transcript: String) async throws -> DeliveryOutcome {
    let pasteboard = NSPasteboard.general
    let snapshot = snapshot(pasteboard)

    pasteboard.clearContents()
    guard pasteboard.setString(transcript, forType: .string) else {
      throw DeliveryError.pasteboardWriteFailed
    }
    let transcriptChangeCount = pasteboard.changeCount

    guard !IsSecureEventInputEnabled() else { return .copied(.secureInput) }
    guard CGPreflightPostEventAccess() else {
      _ = CGRequestPostEventAccess()
      return .copied(.accessibilityPermissionMissing)
    }
    guard let events = pasteShortcutEvents() else { return .copied(.eventCreationFailed) }

    for event in events {
      event.post(tap: .cghidEventTap)
      try await Task.sleep(for: pasteShortcutEventDelay)
    }

    try await Task.sleep(for: clipboardRestoreDelay)
    guard pasteboard.changeCount == transcriptChangeCount else { return .pasted(.skipped) }

    pasteboard.clearContents()
    guard snapshot.isEmpty || pasteboard.writeObjects(pasteboardItems(from: snapshot)) else {
      return .pasted(.failed)
    }
    return .pasted(.restored)
  }

  private static func snapshot(_ pasteboard: NSPasteboard) -> [[PasteboardRepresentation]] {
    // Eager resolution preserves every available type; promised data may briefly block delivery.
    (pasteboard.pasteboardItems ?? []).map { item in
      item.types.compactMap { type in
        item.data(forType: type).map { PasteboardRepresentation(type: type, data: $0) }
      }
    }
  }

  private static func pasteboardItems(
    from snapshot: [[PasteboardRepresentation]]
  ) -> [NSPasteboardItem] {
    snapshot.map { representations in
      let item = NSPasteboardItem()
      for representation in representations {
        item.setData(representation.data, forType: representation.type)
      }
      return item
    }
  }

  private static func pasteShortcutEvents() -> [CGEvent]? {
    let source = CGEventSource(stateID: .privateState)
    guard let commandDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
      let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
      let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false),
      let commandUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
    else { return nil }

    commandDown.flags = .maskCommand
    vDown.flags = .maskCommand
    vUp.flags = .maskCommand
    return [commandDown, vDown, vUp, commandUp]
  }
}

private struct PasteboardRepresentation {
  var type: NSPasteboard.PasteboardType
  var data: Data
}
