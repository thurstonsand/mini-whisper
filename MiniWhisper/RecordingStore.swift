import AudioCapture
import Observation

@MainActor @Observable final class RecordingStore {
  // MARK: - Dependencies

  @ObservationIgnored private let permissionProvider: any MicPermissionProviding

  // MARK: - Permission State

  private(set) var micStatus: MicPermissionStatus

  // MARK: - Recording State

  private(set) var status: RecordingStatus = .idle
  private(set) var audioLevel: Float = 0

  // MARK: - Transcription State

  private(set) var currentTranscription: String?
  private(set) var lastError: String?

  // MARK: - Init

  init(permissionProvider: any MicPermissionProviding = MicPermission.shared) {
    self.permissionProvider = permissionProvider
    self.micStatus = permissionProvider.status
  }

  // MARK: - Actions

  func requestMicAccess() async { micStatus = await permissionProvider.request() }

  func startRecording() {
    guard micStatus == .granted else { return }
    status = .recording// TODO: Start audio capture
  }

  func stopRecording() {
    guard status == .recording else { return }
    status = .processing// TODO: Stop capture, start transcription
  }

  func reset() {
    status = .idle
    audioLevel = 0
    currentTranscription = nil
    lastError = nil
  }
}

enum RecordingStatus: Equatable {
  case idle
  case recording
  case processing
}
