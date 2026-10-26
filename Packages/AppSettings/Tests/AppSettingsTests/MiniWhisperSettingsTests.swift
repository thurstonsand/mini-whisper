@testable import AppSettings
import AudioCapture
import Foundation
import History
import HotkeyListener
import Testing
import TranscriptCleanup

struct MiniWhisperSettingsTests {
  @Test func `the encoded shape stays hand-editable`() throws {
    let data = try SettingsCoding.encode(.defaults)

    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(
      Set(object.keys) == [
        "additionalInstructions", "bindings", "cleanupTimeout", "microphone", "profiles",
        "retention", "sounds",
      ],
    )
    let bindings = try #require(object["bindings"] as? [String: Any])
    #expect(Set(bindings.keys) == ["activate", "pasteLastTranscript"])
    #expect(try SettingsCoding.decode(data) == .defaults)
    let text = try #require(String(data: data, encoding: .utf8))
    #expect(text.hasSuffix("}\n"))
    #expect(text.contains("\n  \"bindings\""))
  }

  @Test func `a hand-edited file with absent keys takes the defaults for them`() throws {
    let data = Data(
      #"{"bindings":{"activate":[{"keyCode":0,"modifiers":["leftCommand"]}]}}"#.utf8,
    )

    let settings = try SettingsCoding.decode(data)

    #expect(
      try settings.bindings.hotkeys(for: .activate)
        == [Hotkey(keyCode: 0, modifiers: [.leftCommand])],
    )
    #expect(
      settings.bindings.hotkeys(for: .pasteLastTranscript)
        == HotkeyBindingsSettings.defaults.hotkeys(for: .pasteLastTranscript),
    )
    #expect(settings.retention == .defaults)
    #expect(settings.microphone == .systemDefault)
    #expect(settings.sounds == .defaults)
    #expect(settings.profiles == .defaults)
    #expect(settings.cleanupTimeout == CleanupConfiguration.defaultTimeout)
  }

  @Test func `an empty file resolves to the defaults`() throws {
    #expect(try SettingsCoding.decode(Data("{}".utf8)) == .defaults)
  }

  @Test func `old and unknown keys are ignored`() throws {
    let data = Data(
      #"{"hotkeys":[{"modifiers":[]}],"pasteLastTranscriptHotkey":{},"extra":1}"#.utf8,
    )

    let settings = try SettingsCoding.decode(data)

    #expect(settings.bindings == .defaults)
    #expect(settings.sounds == .defaults)
  }

  @Test(arguments: ["not json", #"{"bindings":{"activate":[{"modifiers":[]}]}}"#])
  func `settings that cannot be understood fail rather than resolve to something`(
    contents: String,
  ) {
    #expect(throws: (any Error).self) { try SettingsCoding.decode(Data(contents.utf8)) }
  }

  @Test func `duplicate hotkeys fail at the settings boundary`() {
    let duplicate = #"{"bindings":{"activate":[{"modifiers":["rightOption"]}],"pasteLastTranscript":[{"modifiers":["rightOption"]}]}}"#

    #expect(throws: (any Error).self) {
      try SettingsCoding.decode(Data(duplicate.utf8))
    }
  }

  @Test func `binding mutations preserve ownership across commands`() {
    var bindings = HotkeyBindingsSettings.defaults
    let paste = bindings.hotkeys(for: .pasteLastTranscript)[0]

    #expect(bindings.append(paste, for: .activate) == .duplicate)
    #expect(bindings.replace(at: 0, with: paste, for: .activate) == .duplicate)
    #expect(bindings == .defaults)
  }

  @Test func `every setting survives a round trip`() throws {
    let settings = try MiniWhisperSettings(
      bindings: HotkeyBindingsSettings(
        activate: [Hotkey(keyCode: 0, modifiers: [.leftCommand])],
        pasteLastTranscript: [
          Hotkey(keyCode: 9, modifiers: [.rightCommand]),
          Hotkey(keyCode: 8, modifiers: [.leftControl]),
        ],
      ),
      microphone: .device(uid: "studio-mic", lastKnownName: "Studio Microphone"),
      sounds: SoundSettings(
        activate: "Glass", complete: nil, cancel: "Frog", error: "Submarine",
      ),
      retention: RetentionPolicy(transcripts: .ninetyDays, audio: .never),
      profiles: ProfileSettings(
        active: .custom,
        overrides: [.cerebras: EndpointOverride(endpoint: nil, model: "llama-4-scout")],
        custom: CustomProfileSettings(
          cleanupEnabled: true, endpoint: URL(string: "https://gateway.internal/v1"),
          model: "gpt-4o-mini", boostsVocabulary: false,
        ),
      ),
      cleanupTimeout: 20, additionalInstructions: "Keep British spellings.",
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

  @Test func `the defaults write the active profile and nothing the factory owns`() throws {
    let encoded = try SettingsCoding.encode(.defaults)

    let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let profiles = try #require(object["profiles"] as? [String: Any])
    #expect(profiles["active"] as? String == "haiku")
    #expect((profiles["overrides"] as? [String: Any])?.isEmpty == true)
    let custom = try #require(profiles["custom"] as? [String: Any])
    #expect(Set(custom.keys) == ["boostsVocabulary", "cleanupEnabled"])
    #expect(object["cleanupTimeout"] as? TimeInterval == CleanupConfiguration.defaultTimeout)
  }

  @Test func `a partly written profiles section takes the defaults for the rest`() throws {
    let data = Data(#"{"profiles":{"active":"cerebras"}}"#.utf8)

    let profiles = try SettingsCoding.decode(data).profiles

    #expect(profiles.active == .cerebras)
    #expect(profiles.overrides.isEmpty)
    #expect(profiles.custom == .defaults)
  }

  @Test(arguments: ["0", "-5", #""ten""#])
  func `a cleanup timeout that cannot back a request fails`(timeout: String) {
    #expect(throws: (any Error).self) {
      try SettingsCoding.decode(Data(#"{"cleanupTimeout":\#(timeout)}"#.utf8))
    }
  }

  @Test func `an unknown active profile fails rather than picking one`() {
    #expect(throws: (any Error).self) {
      try SettingsCoding.decode(Data(#"{"profiles":{"active":"turbo"}}"#.utf8))
    }
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
