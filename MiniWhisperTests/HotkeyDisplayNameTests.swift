import HotkeyListener
@testable import MiniWhisper
import Testing

struct HotkeyDisplayNameTests {
  @Test(arguments: try [
    (Hotkey.testRightOption, "Right ⌥"),
    (Hotkey(modifiers: [.leftOption]), "Left ⌥"),
    (Hotkey(keyCode: 124, modifiers: [.leftOption]), "Left ⌥ →"),
    (Hotkey(modifiers: [.rightCommand]), "Right ⌘"),
    (Hotkey(modifiers: [.leftShift]), "Left ⇧"),
    (Hotkey(modifiers: [.function]), "fn"),
    (Hotkey(keyCode: 15, modifiers: [.rightControl]), "Right ⌃ R"),
    (
      Hotkey(
        keyCode: 0,
        modifiers: [.rightCommand, .leftShift, .rightOption, .leftControl],
      ),
      "Left ⌃ Right ⌥ Left ⇧ Right ⌘ A",
    ),
  ])
  func `hotkeys name sides without confusing arrow keys`(hotkey: Hotkey, expected: String) {
    #expect(hotkey.displayName == expected)
  }

  @Test func `compact names use bare glyphs in canonical order`() throws {
    let paste = try Hotkey(keyCode: 9, modifiers: [.leftOption, .leftCommand])
    let mixed = try Hotkey(
      keyCode: 0, modifiers: [.rightCommand, .leftShift, .rightOption, .leftControl],
    )

    #expect(paste.compactDisplayName == "⌥⌘V")
    #expect(mixed.compactDisplayName == "⌃⌥⇧⌘A")
  }

  @Test func `each modifier and key is A separate display component`() throws {
    let hotkey = try Hotkey(keyCode: 15, modifiers: [.rightControl])

    #expect(hotkey.displayComponents == ["Right ⌃", "R"])
    #expect(
      HotkeyRecordingChord(keyCodes: [15], modifiers: [.rightControl]).displayComponents
        == ["Right ⌃", "R"],
    )
  }

  @Test func `onboarding copy uses the customized first binding`() throws {
    let hotkeys = try [Hotkey(keyCode: 15, modifiers: [.rightControl]), .testRightOption]

    #expect(
      OnboardingCopy.tryItInstructions(hotkeys: hotkeys)
        ==
        "Hold Right ⌃ R and read the line aloud. Release when you're done.",
    )
    #expect(
      OnboardingCopy.readySummary(hotkeys: hotkeys)
        == "Hold Right ⌃ R to dictate into any text field. Release to paste.",
    )
  }

  @Test func `onboarding copy is honest when no binding exists`() {
    #expect(
      OnboardingCopy.tryItInstructions(hotkeys: [])
        == "Set an activation shortcut in Settings before reading the line aloud.",
    )
    #expect(
      OnboardingCopy.readySummary(hotkeys: [])
        ==
        "Set a shortcut in Settings to dictate into other apps.",
    )
  }

  @Test func `no speech retry uses the customized first binding`() throws {
    let hotkey = try Hotkey(keyCode: 15, modifiers: [.rightControl])

    #expect(
      AppFeature.noSpeechRetryMessage(hotkeys: [hotkey, .testRightOption])
        == "No speech was detected. Hold Right ⌃ R and try again.",
    )
  }

  @Test func `no speech retry does not invent an empty binding`() {
    #expect(
      AppFeature.noSpeechRetryMessage(hotkeys: [])
        == "No speech was detected. Set an activation shortcut in Settings before trying again.",
    )
  }
}
