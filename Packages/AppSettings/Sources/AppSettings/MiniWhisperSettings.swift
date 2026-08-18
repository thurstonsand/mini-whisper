import AudioCapture
import Foundation
import History
import HotkeyListener
import TranscriptCleanup

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

// MARK: - HotkeyCommand

public enum HotkeyCommand: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  case activate
  case pasteLastTranscript
}

// MARK: - HotkeyBindingsSettings

public struct HotkeyBindingsSettings: Equatable, Sendable {
  // MARK: Lifecycle

  public init(activate: [Hotkey], pasteLastTranscript: [Hotkey]) {
    precondition(
      Self.hasUniqueHotkeys(activate + pasteLastTranscript),
      "A hotkey can only belong to one command",
    )
    self.activate = activate
    self.pasteLastTranscript = pasteLastTranscript
  }

  // MARK: Public

  public enum UpdateResult: Equatable, Sendable {
    case updated
    case duplicate
    case missingIndex
  }

  public static let defaults = HotkeyBindingsSettings(
    activate: [makeHotkey(modifiers: [.rightOption])],
    pasteLastTranscript: [makeHotkey(keyCode: 9, modifiers: [.leftOption, .leftCommand])],
  )

  public func hotkeys(for command: HotkeyCommand) -> [Hotkey] {
    switch command {
    case .activate:
      activate
    case .pasteLastTranscript:
      pasteLastTranscript
    }
  }

  @discardableResult public mutating func append(
    _ hotkey: Hotkey, for command: HotkeyCommand,
  ) -> UpdateResult {
    guard !contains(hotkey) else {
      return .duplicate
    }
    update(command) { $0.append(hotkey) }
    return .updated
  }

  @discardableResult public mutating func replace(
    at index: Int, with hotkey: Hotkey, for command: HotkeyCommand,
  ) -> UpdateResult {
    guard hotkeys(for: command).indices.contains(index) else {
      return .missingIndex
    }
    guard !contains(hotkey) else {
      return .duplicate
    }
    update(command) { $0[index] = hotkey }
    return .updated
  }

  @discardableResult public mutating func remove(
    at index: Int, for command: HotkeyCommand,
  ) -> UpdateResult {
    guard hotkeys(for: command).indices.contains(index) else {
      return .missingIndex
    }
    update(command) { $0.remove(at: index) }
    return .updated
  }

  // MARK: Private

  private var activate: [Hotkey]
  private var pasteLastTranscript: [Hotkey]

  private static func hasUniqueHotkeys(_ hotkeys: [Hotkey]) -> Bool {
    hotkeys.indices.allSatisfy { index in
      !hotkeys[..<index].contains(hotkeys[index])
    }
  }

  private static func makeHotkey(
    keyCode: UInt16? = nil, modifiers: Set<ModifierKey>,
  ) -> Hotkey {
    do {
      return try Hotkey(keyCode: keyCode, modifiers: modifiers)
    } catch {
      preconditionFailure("Invalid built-in hotkey: \(error)")
    }
  }

  private func contains(_ hotkey: Hotkey) -> Bool {
    HotkeyCommand.allCases.contains { hotkeys(for: $0).contains(hotkey) }
  }

  private mutating func update(
    _ command: HotkeyCommand, _ operation: (inout [Hotkey]) -> Void,
  ) {
    switch command {
    case .activate:
      operation(&activate)
    case .pasteLastTranscript:
      operation(&pasteLastTranscript)
    }
  }
}

// MARK: Codable

extension HotkeyBindingsSettings: Codable {
  private enum CodingKeys: String, CodingKey {
    case activate
    case pasteLastTranscript
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let activate = try container.decodeIfPresent([Hotkey].self, forKey: .activate)
      ?? Self.defaults.hotkeys(for: .activate)
    let pasteLastTranscript = try container.decodeIfPresent(
      [Hotkey].self, forKey: .pasteLastTranscript,
    ) ?? Self.defaults.hotkeys(for: .pasteLastTranscript)
    guard Self.hasUniqueHotkeys(activate + pasteLastTranscript) else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: decoder.codingPath,
          debugDescription: "A hotkey can only belong to one command",
        ),
      )
    }
    self.activate = activate
    self.pasteLastTranscript = pasteLastTranscript
  }
}

// MARK: - MiniWhisperSettings

/// Every configurable setting the app has, as one value. It is stored whole, so a change to one
/// key can never drop another, and read from state everywhere rather than off the disk.
public struct MiniWhisperSettings: Equatable, Sendable {
  // MARK: Lifecycle

  public init(
    bindings: HotkeyBindingsSettings, microphone: MicrophoneSelection, sounds: SoundSettings,
    retention: RetentionPolicy, improveRecognition: Bool, cleanup: CleanupSettings,
  ) {
    self.bindings = bindings
    self.microphone = microphone
    self.sounds = sounds
    self.retention = retention
    self.improveRecognition = improveRecognition
    self.cleanup = cleanup
  }

  // MARK: Public

  public static let defaults = MiniWhisperSettings(
    bindings: .defaults, microphone: .systemDefault, sounds: .defaults, retention: .defaults,
    improveRecognition: true, cleanup: .defaults,
  )

  public var bindings: HotkeyBindingsSettings
  public var microphone: MicrophoneSelection
  public var sounds: SoundSettings
  public var retention: RetentionPolicy
  public var improveRecognition: Bool
  public var cleanup: CleanupSettings
}

// MARK: Codable

extension MiniWhisperSettings: Codable {
  private enum CodingKeys: String, CodingKey {
    case bindings
    case microphone
    case sounds
    case retention
    case improveRecognition
    case cleanup
  }

  /// The file is meant to be edited by hand, so an absent key means "never configured" and takes
  /// the default rather than treating the file as corrupt.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    bindings = try container.decodeIfPresent(HotkeyBindingsSettings.self, forKey: .bindings)
      ?? .defaults
    microphone = try container.decodeIfPresent(MicrophoneSelection.self, forKey: .microphone)
      ?? .systemDefault
    sounds = try container.decodeIfPresent(SoundSettings.self, forKey: .sounds) ?? .defaults
    retention = try container.decodeIfPresent(RetentionPolicy.self, forKey: .retention)
      ?? .defaults
    improveRecognition = try container.decodeIfPresent(Bool.self, forKey: .improveRecognition)
      ?? true
    cleanup = try container.decodeIfPresent(CleanupSettings.self, forKey: .cleanup) ?? .defaults
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
