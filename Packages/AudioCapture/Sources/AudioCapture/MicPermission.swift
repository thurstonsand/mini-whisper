import AVFoundation

public enum MicPermissionStatus: Sendable, Equatable {
  case granted
  case denied
  case restricted
  case undetermined
  case unknown
}

public struct MicPermission: Sendable {
  public static let shared = MicPermission()

  private init() {}

  public var status: MicPermissionStatus {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized: .granted
    case .denied: .denied
    case .restricted: .restricted
    case .notDetermined: .undetermined
    @unknown default: .unknown
    }
  }

  @MainActor public func requestIfNeeded() async -> MicPermissionStatus {
    guard status == .undetermined else { return status }
    _ = await AVCaptureDevice.requestAccess(for: .audio)
    return status
  }
}
