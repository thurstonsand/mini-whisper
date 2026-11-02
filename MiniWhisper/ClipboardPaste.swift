import AppKit
import Carbon
import CoreGraphics
import HotkeyListener

// MARK: - ClipboardPaste

/// A paste the way a person makes one, into whatever is frontmost: the transcript staged on the
/// clipboard, ⌘V pressed, and the clipboard handed back.
@MainActor enum ClipboardPaste {
  // MARK: Internal

  enum Outcome: Equatable {
    case pasted(ClipboardRestoration)
    /// Keys were still held when the paste was due; ⌘V would have chorded with them.
    case keysHeld
    /// The destination stopped being ready while the clipboard was being staged.
    case focusMoved
    case eventCreationFailed
  }

  @discardableResult static func copy(_ transcript: String) throws -> Int {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    guard pasteboard.setString(transcript, forType: .string) else {
      throw DeliveryError.pasteboardWriteFailed
    }
    return pasteboard.changeCount
  }

  /// Caps Lock is a latch, not a held key, so its state never counts.
  static func isAnyKeyHeld() -> Bool {
    guard CGEventSource.flagsState(.hidSystemState).intersection(heldModifiers).isEmpty else {
      return true
    }
    return (CGKeyCode(0) ..< 128).contains { keyCode in
      keyCode != capsLockKey && CGEventSource.keyState(.hidSystemState, key: keyCode)
    }
  }

  /// `ready` is asked last, right before ⌘V, because staging the clipboard can wait on another
  /// app to hand over promised data while the user moves on.
  static func paste(
    _ transcript: String, submits: Bool, ready: () -> Bool,
  ) async throws -> Outcome {
    guard await waitForKeysReleased() else {
      return .keysHeld
    }
    guard let paste = keyEvents(virtualKey: pasteKey(), flags: .maskCommand),
          let submit = keyEvents(virtualKey: returnKey, flags: [])
    else {
      return .eventCreationFailed
    }

    let pasteboard = NSPasteboard.general
    let snapshot = snapshot(pasteboard)
    let transcriptChangeCount = try stage(transcript)
    guard ready() else {
      return .focusMoved
    }
    try await post(paste)
    if submits {
      // A paste can still be landing when the next key arrives; Return must come after it.
      try await Task.sleep(for: submitDelay)
      try await post(submit)
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

  /// The key that types `character` under `layout` with Command held, which is the key a
  /// shortcut for it is pressed on. Layouts such as "Dvorak - QWERTY ⌘" move a letter's shortcut
  /// to its QWERTY place.
  static func keyCode(typing character: Character, in layout: TISInputSource) -> CGKeyCode? {
    guard let property = TISGetInputSourceProperty(layout, kTISPropertyUnicodeKeyLayoutData) else {
      return nil
    }
    let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
    let wanted = Array(String(character).utf16)
    return data.withUnsafeBytes { bytes -> CGKeyCode? in
      guard let keyboardLayout = bytes.assumingMemoryBound(to: UCKeyboardLayout.self).baseAddress
      else {
        return nil
      }
      for keyCode in CGKeyCode(0) ..< 128 {
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(
          keyboardLayout, keyCode, UInt16(kUCKeyActionDown), UInt32(cmdKey >> 8) & 0xFF,
          UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState,
          characters.count, &length, &characters,
        )
        if status == noErr, Array(characters.prefix(length)) == wanted {
          return keyCode
        }
      }
      return nil
    }
  }

  // MARK: Private

  private static let clipboardRestoreDelay = Duration.milliseconds(250)
  private static let keyEventDelay = Duration.milliseconds(10)
  private static let submitDelay = Duration.milliseconds(50)
  private static let releasePoll = Duration.milliseconds(25)
  private static let releaseBudget = Duration.milliseconds(600)
  private static let qwertyV: CGKeyCode = 0x09
  private static let returnKey: CGKeyCode = 0x24
  private static let commandKey: CGKeyCode = 0x37
  private static let capsLockKey: CGKeyCode = 0x39
  private static let heldModifiers: CGEventFlags = [
    .maskCommand, .maskShift, .maskControl, .maskAlternate, .maskSecondaryFn,
  ]
  /// Clipboard managers leave an item carrying this type out of their history; the transcript
  /// only passes through on its way into the field.
  private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

  /// Waits until no key is held, so a synthetic ⌘V cannot chord with the tail of the user's own
  /// keystrokes. Keys still down at the end of the wait are the user doing something else.
  private static func waitForKeysReleased() async -> Bool {
    let deadline = ContinuousClock.now + releaseBudget
    while isAnyKeyHeld() {
      guard ContinuousClock.now < deadline else {
        return false
      }
      do { try await Task.sleep(for: releasePoll) } catch { return false }
    }
    return true
  }

  /// A layout whose letters are not Latin has no key for "v"; macOS then reads shortcuts off the
  /// ASCII-capable layout beside it.
  private static func pasteKey() -> CGKeyCode {
    for current in [
      TISCopyCurrentKeyboardLayoutInputSource, TISCopyCurrentASCIICapableKeyboardLayoutInputSource,
    ] {
      if let layout = current()?.takeRetainedValue(), let key = keyCode(typing: "v", in: layout) {
        return key
      }
    }
    return qwertyV
  }

  private static func stage(_ transcript: String) throws -> Int {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    let item = NSPasteboardItem()
    item.setString(transcript, forType: .string)
    item.setData(Data(), forType: transientType)
    guard pasteboard.writeObjects([item]) else {
      throw DeliveryError.pasteboardWriteFailed
    }
    return pasteboard.changeCount
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
