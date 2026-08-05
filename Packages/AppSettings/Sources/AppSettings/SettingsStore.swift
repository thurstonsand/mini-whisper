import Foundation
import History
import HotkeyListener

// MARK: - MiniWhisperSettings

public struct MiniWhisperSettings: Equatable, Sendable {
  // MARK: Lifecycle

  public init(hotkey: Hotkey, soundsEnabled: Bool, retention: RetentionPolicy) {
    self.hotkey = hotkey
    self.soundsEnabled = soundsEnabled
    self.retention = retention
  }

  // MARK: Public

  public static let defaults = MiniWhisperSettings(
    hotkey: .rightOption, soundsEnabled: true, retention: .defaults,
  )

  public let hotkey: Hotkey
  public let soundsEnabled: Bool
  public let retention: RetentionPolicy
}

// MARK: Codable

extension MiniWhisperSettings: Codable {
  private enum CodingKeys: String, CodingKey {
    case hotkey
    case soundsEnabled
    case retention
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    hotkey = try container.decode(Hotkey.self, forKey: .hotkey)
    soundsEnabled = try container.decode(Bool.self, forKey: .soundsEnabled)
    // Absent means the user has never configured retention, so the defaults apply — a file
    // written before retention existed must not be treated as corrupt and reset the hotkey.
    retention = try container.decodeIfPresent(RetentionPolicy.self, forKey: .retention)
      ?? .defaults
  }
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
      return try JSONDecoder().decode(MiniWhisperSettings.self, from: data)
    } catch {
      try write(.defaults)
      return .defaults
    }
  }

  public func saveSoundsEnabled(_ soundsEnabled: Bool) throws {
    let settings = try load()
    try write(
      MiniWhisperSettings(
        hotkey: settings.hotkey, soundsEnabled: soundsEnabled, retention: settings.retention,
      ),
    )
  }

  public func saveRetention(_ retention: RetentionPolicy) throws {
    let settings = try load()
    try write(
      MiniWhisperSettings(
        hotkey: settings.hotkey, soundsEnabled: settings.soundsEnabled, retention: retention,
      ),
    )
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
