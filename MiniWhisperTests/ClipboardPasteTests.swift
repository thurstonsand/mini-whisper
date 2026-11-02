import Carbon
@testable import MiniWhisper
import Testing

@MainActor struct ClipboardPasteTests {
  /// ⌘V is pressed where the layout puts V under Command: Dvorak's V sits on QWERTY's period key,
  /// and "Dvorak - QWERTY ⌘" hands Command shortcuts back to QWERTY.
  @Test func `the paste key follows the keyboard layout`() throws {
    func pasteKey(_ id: String) throws -> CGKeyCode? {
      let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
      let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource]
      return try ClipboardPaste.keyCode(typing: "v", in: #require(sources?.first))
    }

    #expect(try pasteKey("com.apple.keylayout.US") == 9)
    #expect(try pasteKey("com.apple.keylayout.Dvorak") == 47)
    #expect(try pasteKey("com.apple.keylayout.DVORAK-QWERTYCMD") == 9)
  }
}
