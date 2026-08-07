import AudioCapture
import Foundation
import History
import HotkeyListener

// MARK: - SoundCue

/// The four moments a dictation can announce. Each one owns its label, its default sound, and the
/// identifier slug the settings pane builds its accessibility identifiers from, so adding a cue is
/// one case rather than an edit in every switch that ever mentioned one.
public enum SoundCue: String, CaseIterable, Equatable, Sendable {
  case activate
  case complete
  case cancel
  case error

  // MARK: Public

  public var label: String {
    switch self {
    case .activate:
      "Activate"
    case .complete:
      "Complete"
    case .cancel:
      "Cancel"
    case .error:
      "Error"
    }
  }

  public var defaultName: String {
    switch self {
    case .activate:
      "Tink"
    case .complete:
      "Pop"
    case .cancel:
      "Funk"
    case .error:
      "Basso"
    }
  }

  public var slug: String {
    rawValue
  }
}

// MARK: - SoundSettings

/// One sound name per cue, where absence is silence rather than a missing value.
public struct SoundSettings: Equatable, Sendable {
  // MARK: Lifecycle

  public init(activate: String?, complete: String?, cancel: String?, error: String?) {
    self.activate = activate
    self.complete = complete
    self.cancel = cancel
    self.error = error
  }

  // MARK: Public

  public static let defaults = SoundSettings(
    activate: SoundCue.activate.defaultName, complete: SoundCue.complete.defaultName,
    cancel: SoundCue.cancel.defaultName, error: SoundCue.error.defaultName,
  )
  public static let silent = SoundSettings(
    activate: nil, complete: nil, cancel: nil, error: nil,
  )

  public var activate: String?
  public var complete: String?
  public var cancel: String?
  public var error: String?

  public subscript(cue: SoundCue) -> String? {
    get {
      switch cue {
      case .activate:
        activate
      case .complete:
        complete
      case .cancel:
        cancel
      case .error:
        error
      }
    }
    set {
      switch cue {
      case .activate:
        activate = newValue
      case .complete:
        complete = newValue
      case .cancel:
        cancel = newValue
      case .error:
        error = newValue
      }
    }
  }
}

// MARK: Codable

extension SoundSettings: Codable {
  private enum CodingKeys: String, CodingKey {
    case activate
    case complete
    case cancel
    case error
  }

  /// Hand-written only so silence is written as an explicit null; the synthesized encoding would
  /// omit the key, which reads as "never configured" rather than "deliberately off".
  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(activate, forKey: .activate)
    try container.encode(complete, forKey: .complete)
    try container.encode(cancel, forKey: .cancel)
    try container.encode(error, forKey: .error)
  }
}

// MARK: - MiniWhisperSettings

/// Every configurable setting the app has, as one value. It is stored whole, so a change to one
/// key can never drop another, and read from state everywhere rather than off the disk.
public struct MiniWhisperSettings: Equatable, Sendable {
  // MARK: Lifecycle

  public init(
    hotkeys: [Hotkey], microphone: MicrophoneSelection, sounds: SoundSettings,
    retention: RetentionPolicy,
  ) {
    self.hotkeys = hotkeys
    self.microphone = microphone
    self.sounds = sounds
    self.retention = retention
  }

  // MARK: Public

  public static let defaults = MiniWhisperSettings(
    hotkeys: [.rightOption], microphone: .systemDefault, sounds: .defaults,
    retention: .defaults,
  )

  public var hotkeys: [Hotkey]
  public var microphone: MicrophoneSelection
  public var sounds: SoundSettings
  public var retention: RetentionPolicy
}

// MARK: Codable

extension MiniWhisperSettings: Codable {
  private enum CodingKeys: String, CodingKey {
    case hotkeys
    case microphone
    case sounds
    case retention
  }

  /// The file is meant to be edited by hand, so an absent key means "never configured" and takes
  /// the default rather than treating the file as corrupt.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    hotkeys = try container.decodeIfPresent([Hotkey].self, forKey: .hotkeys) ?? [.rightOption]
    microphone = try container.decodeIfPresent(MicrophoneSelection.self, forKey: .microphone)
      ?? .systemDefault
    sounds = try container.decodeIfPresent(SoundSettings.self, forKey: .sounds) ?? .defaults
    retention = try container.decodeIfPresent(RetentionPolicy.self, forKey: .retention)
      ?? .defaults
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
