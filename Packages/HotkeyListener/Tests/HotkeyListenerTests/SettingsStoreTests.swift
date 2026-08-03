import Foundation
@testable import HotkeyListener
import Testing

struct SettingsStoreTests {
  // MARK: Internal

  @Test func `missing settings write and return defaults`() throws {
    let location = temporarySettingsURL()
    defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }

    let settings = try SettingsStore(fileURL: location).load()

    #expect(settings == .defaults)
    #expect(FileManager.default.fileExists(atPath: location.path))
    let object = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: location)) as? [String: Any],
    )
    #expect(Set(object.keys) == ["hotkey", "soundsEnabled"])
  }

  @Test func `valid settings are loaded without being rewritten`() throws {
    let location = temporarySettingsURL()
    defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(
      at: location.deletingLastPathComponent(), withIntermediateDirectories: true,
    )
    let original = """
    {"hotkey":{"keyCode":0,"modifiers":["leftCommand"]},"soundsEnabled":false}
    """
    try Data(original.utf8).write(to: location)

    let settings = try SettingsStore(fileURL: location).load()

    #expect(try settings.hotkey == Hotkey(keyCode: 0, modifiers: [.leftCommand]))
    #expect(settings.soundsEnabled == false)
    #expect(try String(contentsOf: location, encoding: .utf8) == original)
  }

  @Test(arguments: ["not json", "{}", #"{"hotkey":{"modifiers":[]},"soundsEnabled":true}"#])
  func `invalid settings are replaced with defaults`(contents: String) throws {
    let location = temporarySettingsURL()
    defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(
      at: location.deletingLastPathComponent(), withIntermediateDirectories: true,
    )
    try Data(contents.utf8).write(to: location)

    let settings = try SettingsStore(fileURL: location).load()

    #expect(settings == .defaults)
    let persisted = try JSONDecoder().decode(
      MiniWhisperSettings.self, from: Data(contentsOf: location),
    )
    #expect(persisted == .defaults)
  }

  @Test func `unknown keys and duplicate modifiers do not destroy valid settings`() throws {
    let location = temporarySettingsURL()
    defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(
      at: location.deletingLastPathComponent(), withIntermediateDirectories: true,
    )
    let original =
      #"{"hotkey":{"modifiers":["rightOption","rightOption"],"typo":1},"soundsEnabled":false,"extra":1}"#
    try Data(original.utf8).write(to: location)

    let settings = try SettingsStore(fileURL: location).load()

    #expect(settings.hotkey == .rightOption)
    #expect(settings.soundsEnabled == false)
    #expect(try String(contentsOf: location, encoding: .utf8) == original)
  }

  @Test func `saving sounds preserves the hotkey and the documented shape`() throws {
    let location = temporarySettingsURL()
    defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(
      at: location.deletingLastPathComponent(), withIntermediateDirectories: true,
    )
    try Data(
      #"{"hotkey":{"keyCode":0,"modifiers":["leftCommand"]},"soundsEnabled":true,"extra":1}"#.utf8,
    ).write(to: location)
    let store = SettingsStore(fileURL: location)

    try store.saveSoundsEnabled(false)

    let settings = try store.load()
    #expect(settings.soundsEnabled == false)
    #expect(try settings.hotkey == Hotkey(keyCode: 0, modifiers: [.leftCommand]))
    let object = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: location)) as? [String: Any],
    )
    #expect(Set(object.keys) == ["hotkey", "soundsEnabled"])
  }

  @Test func `saving sounds onto A missing file starts from defaults`() throws {
    let location = temporarySettingsURL()
    defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }
    let store = SettingsStore(fileURL: location)

    try store.saveSoundsEnabled(false)

    let settings = try store.load()
    #expect(settings.soundsEnabled == false)
    #expect(settings.hotkey == MiniWhisperSettings.defaults.hotkey)
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

  @Test func `default location matches documented application support path`() {
    let suffix = "Library/Application Support/MiniWhisper/settings.json"

    #expect(SettingsStore.defaultFileURL.path.hasSuffix(suffix))
  }

  // MARK: Private

  private func temporarySettingsURL() -> URL {
    FileManager.default
      .temporaryDirectory
      .appending(
        path: UUID().uuidString, directoryHint: .isDirectory,
      )
      .appending(path: "settings.json")
  }
}
