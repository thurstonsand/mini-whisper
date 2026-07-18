import AVFoundation

public enum MicPermissionStatus: Sendable, Equatable {
  case granted
  case denied
  case undetermined
}

public struct MicPermission: Sendable {
  public static let shared = MicPermission()
  private init() {}

  public var status: MicPermissionStatus {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized: .granted
    case .denied, .restricted: .denied
    case .notDetermined: .undetermined
    @unknown default: .denied
    }
  }

  @MainActor public func request() async -> MicPermissionStatus {
    guard status == .undetermined else { return status }
    let granted = await AVCaptureDevice.requestAccess(for: .audio)
    return granted ? .granted : .denied
  }
}
