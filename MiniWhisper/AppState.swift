import AudioCapture
import SwiftUI

@MainActor @Observable final class AppState {
  private(set) var micStatus: MicPermissionStatus = MicPermission.status

  func requestMicAccess() async { micStatus = await MicPermission.request() }
}
