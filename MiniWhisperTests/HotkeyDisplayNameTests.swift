import HotkeyListener
@testable import MiniWhisper
import Testing

struct HotkeyDisplayNameTests {
  @Test(arguments: try [
    (Hotkey.testRightOption, "⌥ Opt →"),
    (Hotkey(modifiers: [.leftOption]), "⌥ Opt ←"),
    (Hotkey(modifiers: [.rightCommand]), "⌘ Cmd →"),
    (Hotkey(modifiers: [.leftShift]), "⇧ Shift ←"),
    (Hotkey(modifiers: [.function]), "fn"),
    (Hotkey(keyCode: 15, modifiers: [.rightControl]), "⌃ Ctrl → R"),
    (
      Hotkey(
        keyCode: 0,
        modifiers: [.rightCommand, .leftShift, .rightOption, .leftControl],
      ),
      "⌃ Ctrl ← ⌥ Opt → ⇧ Shift ← ⌘ Cmd → A",
    ),
  ])
  func `hotkeys use directional shorthand in canonical order`(hotkey: Hotkey, expected: String) {
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

    #expect(hotkey.displayComponents == ["⌃ Ctrl →", "R"])
    #expect(
      HotkeyRecordingChord(keyCodes: [15], modifiers: [.rightControl]).displayComponents
        == ["⌃ Ctrl →", "R"],
    )
  }

  @Test func `onboarding copy uses the customized first binding`() throws {
    let hotkeys = try [Hotkey(keyCode: 15, modifiers: [.rightControl]), .testRightOption]

    #expect(
      OnboardingCopy.tryItInstructions(hotkeys: hotkeys)
        ==
        "Focus the text box below, hold ⌃ Ctrl → R while you speak, then release. Or double-tap ⌃ Ctrl → R to keep recording until you tap it again.",
    )
    #expect(
      OnboardingCopy.readySummary(hotkeys: hotkeys)
        == "Your first dictation made the full trip. Hold ⌃ Ctrl → R in any text field and speak.",
    )
  }

  @Test func `onboarding copy is honest when no binding exists`() {
    #expect(
      OnboardingCopy.tryItInstructions(hotkeys: [])
        == "Set an activation shortcut in Settings before trying dictation here.",
    )
    #expect(
      OnboardingCopy.readySummary(hotkeys: [])
        ==
        "Your first dictation made the full trip. Set an activation shortcut in Settings before using dictation in another text field.",
    )
  }

  @Test func `no speech retry uses the customized first binding`() throws {
    let hotkey = try Hotkey(keyCode: 15, modifiers: [.rightControl])

    #expect(
      AppFeature.noSpeechRetryMessage(hotkeys: [hotkey, .testRightOption])
        == "No speech was detected. Hold ⌃ Ctrl → R and try again.",
    )
  }

  @Test func `no speech retry does not invent an empty binding`() {
    #expect(
      AppFeature.noSpeechRetryMessage(hotkeys: [])
        == "No speech was detected. Set an activation shortcut in Settings before trying again.",
    )
  }
}
