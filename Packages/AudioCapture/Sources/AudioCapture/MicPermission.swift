import AVFoundation

public enum MicPermissionStatus: Sendable {
  case granted
  case denied
  case undetermined
}

public enum MicPermission {
  public static var status: MicPermissionStatus {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized: .granted
    case .denied, .restricted: .denied
    case .notDetermined: .undetermined
    @unknown default: .denied
    }
  }

  @MainActor public static func request() async -> MicPermissionStatus {
    guard status == .undetermined else { return status }
    let granted = await AVCaptureDevice.requestAccess(for: .audio)
    return granted ? .granted : .denied
  }
}
