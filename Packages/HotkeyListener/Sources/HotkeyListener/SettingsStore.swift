import Foundation

public struct MiniWhisperSettings: Equatable, Codable, Sendable {
  public let hotkey: Hotkey
  public let soundsEnabled: Bool

  public init(hotkey: Hotkey, soundsEnabled: Bool) {
    self.hotkey = hotkey
    self.soundsEnabled = soundsEnabled
  }

  public static let defaults = MiniWhisperSettings(hotkey: .rightOption, soundsEnabled: true)
}

public struct SettingsStore: Sendable {
  public let fileURL: URL

  public init(fileURL: URL = SettingsStore.defaultFileURL) { self.fileURL = fileURL }

  public static var defaultFileURL: URL {
    FileManager.default.homeDirectoryForCurrentUser.appending(
      path: "Library/Application Support/MiniWhisper/settings.json")
  }

  public func load() throws -> MiniWhisperSettings {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      try write(.defaults)
      return .defaults
    }

    let data = try Data(contentsOf: fileURL)
    do {
      let settings = try JSONDecoder().decode(MiniWhisperSettings.self, from: data)
      try settings.hotkey.validate()
      return settings
    } catch {
      try write(.defaults)
      return .defaults
    }
  }

  private func write(_ settings: MiniWhisperSettings) throws {
    let directory = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    var data = try encoder.encode(settings)
    data.append(0x0A)
    try data.write(to: fileURL, options: .atomic)
  }
}
