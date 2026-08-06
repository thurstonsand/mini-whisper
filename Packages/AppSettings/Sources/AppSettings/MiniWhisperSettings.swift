import Foundation
import History
import HotkeyListener

// MARK: - MiniWhisperSettings

/// Every configurable setting the app has, as one value. It is stored whole, so a change to one
/// key can never drop another, and read from state everywhere rather than off the disk.
public struct MiniWhisperSettings: Equatable, Sendable {
  // MARK: Lifecycle

  public init(hotkeys: [Hotkey], soundsEnabled: Bool, retention: RetentionPolicy) {
    self.hotkeys = hotkeys
    self.soundsEnabled = soundsEnabled
    self.retention = retention
  }

  // MARK: Public

  public static let defaults = MiniWhisperSettings(
    hotkeys: [.rightOption], soundsEnabled: true, retention: .defaults,
  )

  public var hotkeys: [Hotkey]
  public var soundsEnabled: Bool
  public var retention: RetentionPolicy
}

// MARK: Codable

extension MiniWhisperSettings: Codable {
  private enum CodingKeys: String, CodingKey {
    case hotkey
    case hotkeys
    case soundsEnabled
    case retention
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    // `hotkey` is the pre-multi-binding shape. It is still read so an existing file keeps its
    // shortcut, and never written, so reading one is what retires it.
    if let hotkeys = try container.decodeIfPresent([Hotkey].self, forKey: .hotkeys) {
      self.hotkeys = hotkeys
    } else {
      hotkeys = try [container.decode(Hotkey.self, forKey: .hotkey)]
    }
    soundsEnabled = try container.decode(Bool.self, forKey: .soundsEnabled)
    // Absent means the user has never configured retention, so the defaults apply — a file
    // written before retention existed must not be treated as corrupt and reset the hotkey.
    retention = try container.decodeIfPresent(RetentionPolicy.self, forKey: .retention)
      ?? .defaults
  }

  /// Hand-written only to keep the legacy `hotkey` key out of everything this app writes.
  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(hotkeys, forKey: .hotkeys)
    try container.encode(soundsEnabled, forKey: .soundsEnabled)
    try container.encode(retention, forKey: .retention)
  }
}

// MARK: - SettingsCoding

/// The on-disk shape of `settings.json`. The file is meant to be opened and edited by hand, so
/// it stays pretty-printed, key-sorted, and newline-terminated.
public enum SettingsCoding {
  public static func decode(_ data: Data) throws -> MiniWhisperSettings {
    try JSONDecoder().decode(MiniWhisperSettings.self, from: data)
  }

  public static func encode(_ settings: MiniWhisperSettings) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    var data = try encoder.encode(settings)
    data.append(0x0A)
    return data
  }
}
