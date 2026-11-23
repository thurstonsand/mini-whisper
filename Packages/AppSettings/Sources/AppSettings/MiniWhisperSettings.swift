import AudioCapture
import Foundation
import History
import HotkeyListener
import TranscriptCleanup

// MARK: - SoundCue

/// The four moments a dictation can announce.
public enum SoundCue: String, CaseIterable, Equatable, Sendable {
  case activate
  case complete
  case cancel
  case error
}

// MARK: - SoundTheme

/// One family of cues, chosen whole: every theme speaks all four moments in its own voice, so
/// a dictation never mixes two. Silence is a theme too, the deliberate choice of none.
public enum SoundTheme: String, CaseIterable, Codable, Equatable, Sendable {
  case drop
  case pluck
  case hum
  case bloom
  case silent

  // MARK: Public

  public static let `default` = SoundTheme.drop

  public var label: String {
    switch self {
    case .drop:
      "Drop"
    case .pluck:
      "Pluck"
    case .hum:
      "Hum"
    case .bloom:
      "Bloom"
    case .silent:
      "No audio"
    }
  }

  /// The bundled sound file for one cue, named `<theme>-<cue>`; silence has none.
  public func resourceName(for cue: SoundCue) -> String? {
    self == .silent ? nil : "\(rawValue)-\(cue.rawValue)"
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
    bindings: HotkeyBindingsSettings, microphone: MicrophoneSelection, soundTheme: SoundTheme,
    retention: RetentionPolicy, profiles: ProfileSettings, cleanupTimeout: TimeInterval,
    additionalInstructions: String,
  ) {
    precondition(cleanupTimeout > 0)
    self.bindings = bindings
    self.microphone = microphone
    self.soundTheme = soundTheme
    self.retention = retention
    self.profiles = profiles
    self.cleanupTimeout = cleanupTimeout
    self.additionalInstructions = additionalInstructions
  }

  // MARK: Public

  public static let defaults = MiniWhisperSettings(
    bindings: .defaults, microphone: .systemDefault, soundTheme: .default, retention: .defaults,
    profiles: .defaults, cleanupTimeout: CleanupConfiguration.defaultTimeout,
    additionalInstructions: "",
  )

  public var bindings: HotkeyBindingsSettings
  public var microphone: MicrophoneSelection
  public var soundTheme: SoundTheme
  public var retention: RetentionPolicy
  public var profiles: ProfileSettings

  /// The unattended backstop, stored as a plain duration; the pane offers presets over it.
  public private(set) var cleanupTimeout: TimeInterval
  public var additionalInstructions: String

  public var activeProfile: Profile {
    profiles.activeProfile
  }

  /// What the active profile's dictations show cleanup of the screen. Expanded context reaches
  /// only a cleanup pass that reads a prompt; S1-mini reads none, so under Offline, Custom with
  /// its cleanup off, or an endpoint not yet set up, the screen is never read at all.
  public var screenContextMode: ScreenContextMode {
    guard case .endpoint = activeProfile.cleanup, cleanupTarget != nil else {
      return .off
    }
    return profiles.screenContextMode(for: profiles.active)
  }

  public var readsScreen: Bool {
    screenContextMode != .off
  }

  /// What the active profile's cleanup pass runs with, or nil when there is nothing to run — the
  /// one place "needs setup is the same as off" is decided.
  public var cleanupTarget: CleanupTarget? {
    if activeProfile.cleanup == .local {
      return .local(timeout: cleanupTimeout)
    }
    guard case let .endpoint(leg) = activeProfile.cleanup, let endpoint = leg.endpoint,
          let model = leg.model, !model.isEmpty
    else {
      return nil
    }
    return CleanupTarget(
      configuration: CleanupConfiguration(
        endpoint: endpoint, model: model, reasoningEffort: leg.reasoningEffort,
        timeout: cleanupTimeout, additionalInstructions: additionalInstructions,
      ),
      credential: leg.credential,
    )
  }

  public mutating func setCleanupTimeout(_ timeout: TimeInterval) {
    precondition(timeout > 0)
    cleanupTimeout = timeout
  }
}

// MARK: Codable

extension MiniWhisperSettings: Codable {
  private enum CodingKeys: String, CodingKey {
    case bindings
    case microphone
    case soundTheme
    case retention
    case profiles
    case cleanupTimeout
    case additionalInstructions
  }

  /// The file is meant to be edited by hand, so an absent key means "never configured" and takes
  /// the default rather than treating the file as corrupt. A timeout that is present but unusable
  /// is an edit the user meant, so it fails rather than being rounded up.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    bindings = try container.decodeIfPresent(HotkeyBindingsSettings.self, forKey: .bindings)
      ?? .defaults
    microphone = try container.decodeIfPresent(MicrophoneSelection.self, forKey: .microphone)
      ?? .systemDefault
    soundTheme = try container.decodeIfPresent(SoundTheme.self, forKey: .soundTheme) ?? .default
    retention = try container.decodeIfPresent(RetentionPolicy.self, forKey: .retention)
      ?? .defaults
    profiles = try container.decodeIfPresent(ProfileSettings.self, forKey: .profiles)
      ?? .defaults
    cleanupTimeout = try container.decodeIfPresent(TimeInterval.self, forKey: .cleanupTimeout)
      ?? CleanupConfiguration.defaultTimeout
    guard cleanupTimeout > 0 else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: container.codingPath + [CodingKeys.cleanupTimeout],
          debugDescription: "The cleanup timeout must be a positive number of seconds",
        ),
      )
    }
    additionalInstructions = try container.decodeIfPresent(
      String.self, forKey: .additionalInstructions,
    ) ?? ""
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
