@testable import AppSettings
import AudioCapture
import Foundation
import History
import HotkeyListener
import Testing

struct MiniWhisperSettingsTests {
  @Test func `the encoded shape stays hand-editable`() throws {
    let data = try SettingsCoding.encode(.defaults)

    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(Set(object.keys) == ["hotkeys", "microphone", "retention", "sounds"])
    #expect(try SettingsCoding.decode(data) == .defaults)
    let text = try #require(String(data: data, encoding: .utf8))
    #expect(text.hasSuffix("}\n"))
    #expect(text.contains("\n  \"hotkeys\""))
  }

  @Test func `a hand-edited file with absent keys takes the defaults for them`() throws {
    let data = Data(
      #"{"hotkeys":[{"keyCode":0,"modifiers":["leftCommand"]}]}"#.utf8,
    )

    let settings = try SettingsCoding.decode(data)

    #expect(try settings.hotkeys == [Hotkey(keyCode: 0, modifiers: [.leftCommand])])
    #expect(settings.retention == .defaults)
    #expect(settings.microphone == .systemDefault)
    #expect(settings.sounds == .defaults)
  }

  @Test func `an empty file resolves to the defaults`() throws {
    #expect(try SettingsCoding.decode(Data("{}".utf8)) == .defaults)
  }

  @Test func `unknown keys and duplicate modifiers do not destroy valid settings`() throws {
    let data = Data(
      #"{"hotkeys":[{"modifiers":["rightOption","rightOption"],"typo":1}],"extra":1}"#.utf8,
    )

    let settings = try SettingsCoding.decode(data)

    #expect(settings.hotkeys == [.rightOption])
    #expect(settings.sounds == .defaults)
  }

  @Test(arguments: ["not json", #"{"hotkeys":[{"modifiers":[]}]}"#])
  func `settings that cannot be understood fail rather than resolve to something`(
    contents: String,
  ) {
    #expect(throws: (any Error).self) { try SettingsCoding.decode(Data(contents.utf8)) }
  }

  @Test func `every setting survives a round trip`() throws {
    let settings = try MiniWhisperSettings(
      hotkeys: [Hotkey(keyCode: 0, modifiers: [.leftCommand])],
      microphone: .device(uid: "studio-mic", lastKnownName: "Studio Microphone"),
      sounds: SoundSettings(
        activate: "Glass", complete: nil, cancel: "Frog", error: "Submarine",
      ),
      retention: RetentionPolicy(transcripts: .ninetyDays, audio: .never),
    )

    #expect(try SettingsCoding.decode(SettingsCoding.encode(settings)) == settings)
  }

  @Test func `silenced cues are written as explicit nulls`() throws {
    var settings = MiniWhisperSettings.defaults
    settings.sounds = SoundSettings(
      activate: "Glass", complete: nil, cancel: "Frog", error: "Submarine",
    )

    let encoded = try SettingsCoding.encode(settings)
    let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

    let sounds = try #require(object["sounds"] as? [String: Any])
    #expect(Set(sounds.keys) == ["activate", "complete", "cancel", "error"])
    #expect(sounds["complete"] is NSNull)
    #expect(try SettingsCoding.decode(encoded).sounds == settings.sounds)
  }

  @Test func `microphone selection survives A round trip`() throws {
    let selection = MicrophoneSelection.device(
      uid: "usb-audio-device", lastKnownName: "Desk Microphone",
    )
    var settings = MiniWhisperSettings.defaults
    settings.microphone = selection

    #expect(try SettingsCoding.decode(SettingsCoding.encode(settings)).microphone == selection)
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
