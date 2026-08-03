import AppKit
import ApplicationServices
import Carbon
import ComposableArchitecture
import CoreGraphics
import Foundation

// MARK: - ClipboardRestoration

enum ClipboardRestoration: Equatable {
  case restored
  case skipped
  case failed
}

// MARK: - DeliveryFallback

enum DeliveryFallback: Equatable {
  case accessibilityPermissionMissing
  case secureInput
  case eventCreationFailed
}

// MARK: - DeliveryOutcome

enum DeliveryOutcome: Equatable {
  case pasted(ClipboardRestoration)
  case copied(DeliveryFallback)
}

// MARK: - DeliveryError

enum DeliveryError: Error, Equatable { case pasteboardWriteFailed }

// MARK: - DeliveryClient

@DependencyClient struct DeliveryClient {
  var hasPasteAccess: @Sendable () -> Bool = { false }
  var requestPasteAccess: @MainActor @Sendable () -> Bool = { false }
  var deliver: @Sendable (String) async throws -> DeliveryOutcome
  var copy: @Sendable (String) async throws -> Void
}

// MARK: DependencyKey

extension DeliveryClient: DependencyKey {
  static let liveValue = Self(
    // CGPreflightPostEventAccess caches its first answer for the life of the process, so a grant
    // made while MiniWhisper runs would need a relaunch to be seen; Accessibility trust is the
    // same permission and reports live.
    hasPasteAccess: { AXIsProcessTrusted() },
    // CGRequestPostEventAccess prompts unreliably and leaves no MiniWhisper row in Accessibility;
    // the Accessibility trust prompt both asks and seeds the row that grants post-event access.
    requestPasteAccess: {
      // kAXTrustedCheckOptionPrompt is imported as shared mutable state, so spell its value out.
      AXIsProcessTrustedWithOptions(
        ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary,
      )
    }, deliver: { transcript in try await TranscriptDelivery.deliver(transcript) },
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

  static func deliver(_ transcript: String) async throws -> DeliveryOutcome {
    let pasteboard = NSPasteboard.general
    let snapshot = snapshot(pasteboard)
    let transcriptChangeCount = try copy(transcript)

    guard !IsSecureEventInputEnabled() else {
      return .copied(.secureInput)
    }
    guard AXIsProcessTrusted() else {
      return .copied(.accessibilityPermissionMissing)
    }
    guard let events = pasteShortcutEvents() else {
      return .copied(.eventCreationFailed)
    }

    for event in events {
      event.post(tap: .cghidEventTap)
      try await Task.sleep(for: pasteShortcutEventDelay)
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
  private static let pasteShortcutEventDelay = Duration.milliseconds(10)

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

  private static func pasteShortcutEvents() -> [CGEvent]? {
    let source = CGEventSource(stateID: .privateState)
    guard let commandDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
          let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
          let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false),
          let commandUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
    else {
      return nil
    }

    commandDown.flags = .maskCommand
    vDown.flags = .maskCommand
    vUp.flags = .maskCommand
    return [commandDown, vDown, vUp, commandUp]
  }
}

// MARK: - PasteboardRepresentation

private struct PasteboardRepresentation {
  var type: NSPasteboard.PasteboardType
  var data: Data
}
