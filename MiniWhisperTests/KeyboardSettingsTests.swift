import HotkeyListener
@testable import MiniWhisper
import Testing

struct KeyboardSettingsTests {
  @Test func `Globe uses its own action even when Dictation retains an obsolete fn preset`() throws {
    let globe = try Hotkey(modifiers: [.function])
    let stale: [String: Any] = ["164": [
      "enabled": 1, "value": ["type": "modifier", "parameters": [8_388_608]],
    ]]
    #expect(KeyboardShortcutSettings(globeAction: nil, symbolicHotkeys: [:])
      .warning(for: globe) != nil)
    #expect(KeyboardShortcutSettings(globeAction: 0, symbolicHotkeys: stale)
      .warning(for: globe) == nil)
    #expect(KeyboardShortcutSettings(globeAction: 3, symbolicHotkeys: [:])
      .warning(for: globe) != nil)
  }

  @Test(arguments: [
    (262_144, ModifierKey.leftControl, ModifierKey.rightOption),
    (1_048_592, .rightCommand, .leftCommand),
    (1_048_584, .leftCommand, .rightCommand),
    (1_048_576, .rightCommand, .leftControl),
  ])
  func `Dictation conflicts only with enabled matching modifier gestures`(
    preset: Int, matching: ModifierKey, other: ModifierKey,
  ) throws {
    let value: [String: Any] = ["type": "modifier", "parameters": [preset]]
    let enabled = KeyboardShortcutSettings(
      globeAction: 0, symbolicHotkeys: ["164": ["enabled": 1, "value": value]],
    )
    let disabled = KeyboardShortcutSettings(
      globeAction: 0, symbolicHotkeys: ["164": ["enabled": 0, "value": value]],
    )
    #expect(try enabled.warning(for: Hotkey(modifiers: [matching])) != nil)
    #expect(try enabled.warning(for: Hotkey(modifiers: [other])) == nil)
    #expect(try enabled.warning(for: Hotkey(keyCode: 49, modifiers: [matching])) == nil)
    #expect(try disabled.warning(for: Hotkey(modifiers: [matching])) == nil)
  }
}
