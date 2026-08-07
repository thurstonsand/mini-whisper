import Foundation

// MARK: - MicrophoneSelection

/// The microphone the user picked, as it is stored. The UID is the only key resolution uses; the
/// name is kept solely so the app can speak about a device that is not currently connected.
public enum MicrophoneSelection: Equatable, Hashable, Sendable {
  case systemDefault
  case device(uid: String, lastKnownName: String)
}

// MARK: Codable

extension MicrophoneSelection: Codable {
  private enum Kind: String, Codable {
    case systemDefault
    case device
  }

  private enum CodingKeys: String, CodingKey {
    case kind
    case deviceUID
    case lastKnownName
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .kind) {
    case .systemDefault:
      self = .systemDefault
    case .device:
      self = try .device(
        uid: container.decode(String.self, forKey: .deviceUID),
        lastKnownName: container.decode(String.self, forKey: .lastKnownName),
      )
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .systemDefault:
      try container.encode(Kind.systemDefault, forKey: .kind)
    case let .device(uid, lastKnownName):
      try container.encode(Kind.device, forKey: .kind)
      try container.encode(uid, forKey: .deviceUID)
      try container.encode(lastKnownName, forKey: .lastKnownName)
    }
  }
}

// MARK: - AudioInputTransport

public enum AudioInputTransport: Equatable, Sendable {
  case ordinary
  case aggregate
  case continuityCaptureWired
  case continuityCaptureWireless

  // MARK: Internal

  /// Continuity is unreachable through an app-local HAL binding — the readback succeeds and IO
  /// never starts — so it is never offered as an explicit choice. It remains perfectly usable as
  /// the system default, where coreaudiod owns the wake.
  var supportsExplicitSelection: Bool {
    switch self {
    case .ordinary,
         .aggregate:
      true
    case .continuityCaptureWired,
         .continuityCaptureWireless:
      false
    }
  }
}

// MARK: - AudioInputVisibility

public enum AudioInputVisibility: Equatable, Sendable {
  case visible
  case hidden
  /// An aggregate whose composition declares itself private — AVAudioEngine's own
  /// `CADefaultDeviceAggregate` is one, and it declares `IsHidden = 0`, so hiding alone misses it.
  case privateAggregate
}

// MARK: - AudioInputDevice

public struct AudioInputDevice: Equatable, Identifiable, Sendable {
  // MARK: Lifecycle

  public init(
    uid: String, name: String, transport: AudioInputTransport = .ordinary,
    visibility: AudioInputVisibility = .visible,
  ) {
    self.uid = uid
    self.name = name
    self.transport = transport
    self.visibility = visibility
  }

  // MARK: Public

  public let uid: String
  public let name: String
  public let transport: AudioInputTransport
  public let visibility: AudioInputVisibility

  public var id: String {
    uid
  }
}

// MARK: - AudioInputDeviceSnapshot

public struct AudioInputDeviceSnapshot: Equatable, Sendable {
  // MARK: Lifecycle

  public init(devices: [AudioInputDevice], defaultDevice: AudioInputDevice?) {
    self.devices = devices
    self.defaultDevice = defaultDevice
  }

  // MARK: Public

  public static let empty = Self(devices: [], defaultDevice: nil)

  public let devices: [AudioInputDevice]
  public let defaultDevice: AudioInputDevice?
}

// MARK: - AudioInputDevicePolicy

/// Which devices the app is willing to bind to by name. Filtering is by declared attributes only,
/// never by name, and aggregates stay in: second-guessing a user's audio setup is not this app's
/// business.
public enum AudioInputDevicePolicy {
  public static func isExplicitlySelectable(_ device: AudioInputDevice) -> Bool {
    device.transport.supportsExplicitSelection && device.visibility == .visible
  }

  public static func explicitlySelectableDevices(
    _ devices: [AudioInputDevice],
  ) -> [AudioInputDevice] {
    devices.filter(isExplicitlySelectable)
  }
}

// MARK: - AudioInputRoute

/// Where a selection actually leads. Asking for the system default and asking for a device that
/// cannot be reached are the same route, because both leave the engine unbound and following
/// whatever macOS considers current. A selection is never rewritten to match — it heals when the
/// device comes back.
public enum AudioInputRoute: Equatable, Sendable {
  case systemDefault
  case explicit(AudioInputDevice)

  // MARK: Public

  /// The single policy the picker and the capture path share, so the two can never disagree about
  /// what is selectable.
  public static func resolving(
    _ selection: MicrophoneSelection, selectedDevice: AudioInputDevice?,
  ) -> AudioInputRoute {
    guard case .device = selection, let selectedDevice,
          AudioInputDevicePolicy.isExplicitlySelectable(selectedDevice)
    else {
      return .systemDefault
    }
    return .explicit(selectedDevice)
  }
}
