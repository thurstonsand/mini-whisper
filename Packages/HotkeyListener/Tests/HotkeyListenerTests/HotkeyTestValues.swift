@testable import HotkeyListener

extension Hotkey {
  static let testRightOption = try! Hotkey(modifiers: [.rightOption])
  static let testPasteLastTranscript = try! Hotkey(
    keyCode: 9, modifiers: [.leftOption, .leftCommand],
  )
}
