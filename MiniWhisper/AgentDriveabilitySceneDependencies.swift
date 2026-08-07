import ASREngine
import AudioCapture
import ComposableArchitecture
import Foundation

#if DEBUG
  extension AgentDriveabilityScene {
    /// The system boundaries a scene cannot cross for real: TCC prompts, model installs, System
    /// Settings. The grants start wherever the scene's seeded state says they are, so driving a
    /// permission through its Grant button moves the same truth the screen was already showing.
    func configure(_ dependencies: inout DependencyValues) {
      let seeded = initialState
      let permissions = AgentPermissionState(
        microphoneStatus: seeded.recording.micStatus,
        accessibilityGranted: seeded.accessibilityGranted,
      )
      dependencies.microphonePermission = MicrophonePermissionClient(
        status: { permissions.microphoneStatus },
        requestIfNeeded: {
          permissions.microphoneStatus = .granted
          return .granted
        },
      )
      dependencies.accessibilityPermission = AccessibilityPermissionClient(
        hasPermission: { permissions.accessibilityGranted },
        requestPermission: {
          permissions.accessibilityGranted = true
          return true
        },
      )
      dependencies.modelDownloadConsent.markConsented = {}
      dependencies.asrEngine.installAndPrepare = { AsyncStream { $0.finish() } }
      let inputDevices = AudioInputDeviceSnapshot(
        devices: [
          AudioInputDevice(uid: "built-in-microphone", name: "MacBook Pro Microphone"),
          AudioInputDevice(uid: "studio-microphone", name: "Studio Microphone"),
        ],
        defaultDevice: AudioInputDevice(
          uid: "built-in-microphone", name: "MacBook Pro Microphone",
        ),
      )
      dependencies.audioInputDevices.snapshots = {
        AsyncStream { continuation in
          continuation.yield(inputDevices)
          continuation.finish()
        }
      }
      dependencies.audioInputLevels.levels = { _ in
        AsyncStream { continuation in
          continuation.yield(AudioLevel(decibels: -34.8, normalizedPower: 0.42))
        }
      }
      // Tink is deliberately absent: the scene proves a cue's default remains selectable even
      // when the system inventory does not report it. What played is read off the pane's own
      // playback paint state, so the scene only has to keep the machine quiet.
      dependencies.sounds.availableNames = { ["Basso", "Funk", "Glass", "Pop"] }
      dependencies.sounds.play = { _ in }
      // No scene may leave the app it is driving. Reporting the refusal is also the only way a
      // test can see that "Open Settings" was the thing that ran.
      dependencies.workspace.open = { _ in throw AgentSceneRefusal.systemSettings }
    }
  }

  // MARK: - AgentSceneRefusal

  private enum AgentSceneRefusal: LocalizedError {
    case systemSettings

    // MARK: Internal

    var errorDescription: String? {
      "Agent scene opened System Settings"
    }
  }

  // MARK: - AgentPermissionState

  /// Grants outlive the reducer that asked for them: the clients are plain closures, so the answer
  /// has to be kept somewhere both of them can reach.
  private final class AgentPermissionState: @unchecked Sendable {
    // MARK: Lifecycle

    init(microphoneStatus: MicPermissionStatus, accessibilityGranted: Bool) {
      _microphoneStatus = microphoneStatus
      _accessibilityGranted = accessibilityGranted
    }

    // MARK: Internal

    var microphoneStatus: MicPermissionStatus {
      get { lock.withLock { _microphoneStatus } }
      set { lock.withLock { _microphoneStatus = newValue } }
    }

    var accessibilityGranted: Bool {
      get { lock.withLock { _accessibilityGranted } }
      set { lock.withLock { _accessibilityGranted = newValue } }
    }

    // MARK: Private

    private let lock = NSLock()
    private var _microphoneStatus: MicPermissionStatus
    private var _accessibilityGranted: Bool
  }
#endif
