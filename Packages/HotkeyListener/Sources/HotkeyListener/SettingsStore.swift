import Foundation

// MARK: - MiniWhisperSettings

public struct MiniWhisperSettings: Equatable, Codable, Sendable {
  // MARK: Lifecycle

  public init(hotkey: Hotkey, soundsEnabled: Bool) {
    self.hotkey = hotkey
    self.soundsEnabled = soundsEnabled
  }

  // MARK: Public

  public static let defaults = MiniWhisperSettings(hotkey: .rightOption, soundsEnabled: true)

  public let hotkey: Hotkey
  public let soundsEnabled: Bool
}

// MARK: - SettingsStore

public struct SettingsStore: Sendable {
  // MARK: Lifecycle

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  // MARK: Public

  public let fileURL: URL

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

  public func saveSoundsEnabled(_ soundsEnabled: Bool) throws {
    let settings = try load()
    try write(MiniWhisperSettings(hotkey: settings.hotkey, soundsEnabled: soundsEnabled))
  }

  // MARK: Private

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
