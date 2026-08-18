import Foundation

// MARK: - CleanupSettings

/// The cleanup pass as it is persisted: what the user chose in the pane, minus the API key, which
/// lives in the Keychain so `settings.json` never carries a credential.
///
/// Endpoint and model are optional because "not configured yet" is a real state the pane shows and
/// the pipeline honours; `configuration` is where that state becomes "nothing to run".
public struct CleanupSettings: Equatable, Sendable {
  // MARK: Lifecycle

  public init(
    enabled: Bool, endpoint: URL?, model: String?, timeout: TimeInterval,
    additionalInstructions: String,
  ) {
    precondition(timeout > 0)
    self.enabled = enabled
    self.endpoint = endpoint
    self.model = model
    self.timeout = timeout
    self.additionalInstructions = additionalInstructions
  }

  // MARK: Public

  public static let defaults = CleanupSettings(
    enabled: false, endpoint: nil, model: nil, timeout: CleanupConfiguration.defaultTimeout,
    additionalInstructions: "",
  )

  public var enabled: Bool
  public var endpoint: URL?
  public var model: String?

  /// The unattended backstop, stored as a plain duration; the pane offers presets over it.
  public private(set) var timeout: TimeInterval
  public var additionalInstructions: String

  /// What the pass runs with, or nil when there is nothing to run — the one place the
  /// "enabled but unconfigured is the same as off" rule is decided.
  public var configuration: CleanupConfiguration? {
    guard enabled, let endpoint, let model, !model.isEmpty else {
      return nil
    }
    return CleanupConfiguration(
      endpoint: endpoint, model: model, timeout: timeout,
      additionalInstructions: additionalInstructions,
    )
  }

  public mutating func setTimeout(_ timeout: TimeInterval) {
    precondition(timeout > 0)
    self.timeout = timeout
  }
}

// MARK: Codable

extension CleanupSettings: Codable {
  private enum CodingKeys: String, CodingKey {
    case enabled
    case endpoint
    case model
    case timeout
    case additionalInstructions
  }

  /// Absent keys take their defaults, as everywhere else in the hand-editable file; a timeout that
  /// is present but unusable is an edit the user meant, so it fails rather than being rounded up.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
    endpoint = try container.decodeIfPresent(URL.self, forKey: .endpoint)
    model = try container.decodeIfPresent(String.self, forKey: .model)
    timeout = try container.decodeIfPresent(TimeInterval.self, forKey: .timeout)
      ?? CleanupConfiguration.defaultTimeout
    guard timeout > 0 else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: container.codingPath + [CodingKeys.timeout],
          debugDescription: "The cleanup timeout must be a positive number of seconds",
        ),
      )
    }
    additionalInstructions = try container.decodeIfPresent(
      String.self, forKey: .additionalInstructions,
    ) ?? ""
  }
}
