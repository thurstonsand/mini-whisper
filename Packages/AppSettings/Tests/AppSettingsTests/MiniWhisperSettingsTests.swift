@testable import AppSettings
import Foundation
import History
import HotkeyListener
import Testing

struct MiniWhisperSettingsTests {
  @Test func `the encoded shape stays hand-editable`() throws {
    let data = try SettingsCoding.encode(.defaults)

    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(Set(object.keys) == ["hotkey", "retention", "soundsEnabled"])
    #expect(try SettingsCoding.decode(data) == .defaults)
    let text = try #require(String(data: data, encoding: .utf8))
    #expect(text.hasSuffix("}\n"))
    #expect(text.contains("\n  \"hotkey\""))
  }

  @Test func `a file from before retention existed keeps its hotkey and gains the defaults`(
  ) throws {
    let data = Data(
      #"{"hotkey":{"keyCode":0,"modifiers":["leftCommand"]},"soundsEnabled":false}"#.utf8,
    )

    let settings = try SettingsCoding.decode(data)

    #expect(try settings.hotkey == Hotkey(keyCode: 0, modifiers: [.leftCommand]))
    #expect(settings.retention == .defaults)
    #expect(settings.soundsEnabled == false)
  }

  @Test func `unknown keys and duplicate modifiers do not destroy valid settings`() throws {
    let data = Data(
      #"{"hotkey":{"modifiers":["rightOption","rightOption"],"typo":1},"soundsEnabled":false,"extra":1}"#
        .utf8,
    )

    let settings = try SettingsCoding.decode(data)

    #expect(settings.hotkey == .rightOption)
    #expect(settings.soundsEnabled == false)
  }

  @Test(arguments: ["not json", "{}", #"{"hotkey":{"modifiers":[]},"soundsEnabled":true}"#])
  func `settings that cannot be understood fail rather than resolve to something`(
    contents: String,
  ) {
    #expect(throws: (any Error).self) { try SettingsCoding.decode(Data(contents.utf8)) }
  }

  @Test func `every setting survives a round trip`() throws {
    let settings = try MiniWhisperSettings(
      hotkey: Hotkey(keyCode: 0, modifiers: [.leftCommand]),
      soundsEnabled: false,
      retention: RetentionPolicy(transcripts: .ninetyDays, audio: .never),
    )

    #expect(try SettingsCoding.decode(SettingsCoding.encode(settings)) == settings)
  }

  @Test func `hotkey validation rejects empty and reserved keys`() {
    #expect(throws: HotkeyValidationError.empty) { try Hotkey(modifiers: []) }
    #expect(throws: HotkeyValidationError.reservedKeyCode(PhysicalKey.escapeKeyCode)) {
      try Hotkey(keyCode: PhysicalKey.escapeKeyCode, modifiers: [])
    }
    #expect(throws: HotkeyValidationError.modifierKeyCode(61)) {
      try Hotkey(keyCode: 61, modifiers: [])
    }
    #expect(throws: HotkeyValidationError.unsupportedKeyCode(128)) {
      try Hotkey(keyCode: 128, modifiers: [])
    }
  }
}
