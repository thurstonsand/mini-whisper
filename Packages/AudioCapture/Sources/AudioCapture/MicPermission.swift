import AVFoundation

// MARK: - MicPermissionStatus

public enum MicPermissionStatus: Sendable, Equatable {
  case granted
  case denied
  case restricted
  case undetermined
  case unknown
}

// MARK: - MicPermission

public struct MicPermission: Sendable {
  // MARK: Lifecycle

  private init() {}

  // MARK: Public

  public static let shared = MicPermission()

  public var status: MicPermissionStatus {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      .granted
    case .denied:
      .denied
    case .restricted:
      .restricted
    case .notDetermined:
      .undetermined
    @unknown default:
      .unknown
    }
  }

  @MainActor public func requestIfNeeded() async -> MicPermissionStatus {
    guard status == .undetermined else {
      return status
    }
    _ = await AVCaptureDevice.requestAccess(for: .audio)
    return status
  }
}
