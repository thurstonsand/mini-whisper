import ASREngine
import AudioCapture
import ComposableArchitecture
import Foundation
import HotkeyListener

#if DEBUG
  extension AgentDriveabilityScene {
    /// The system boundaries a scene cannot cross for real: TCC prompts, model installs, System
    /// Settings. The grants start wherever the scene's seeded state says they are, so driving a
    /// permission through its Grant button moves the same truth the screen was already showing.
    func configure(_ dependencies: inout DependencyValues) {
      let sceneState = AgentSceneState(scene: self)
      AgentSceneState.current = sceneState
      dependencies.microphonePermission = MicrophonePermissionClient(
        status: { sceneState.microphoneStatus },
        requestIfNeeded: {
          sceneState.microphoneStatus = .granted
          return .granted
        },
      )
      dependencies.accessibilityPermission = AccessibilityPermissionClient(
        hasPermission: { sceneState.accessibilityGranted },
        requestPermission: {
          sceneState.accessibilityGranted = true
          return true
        },
      )
      dependencies.modelDownloadConsent.markConsented = {}
      dependencies.asrEngine.installAndPrepare = { AsyncStream { $0.finish() } }
      dependencies.hotkeyListener.record = { AsyncStream { _ in } }
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
      dependencies.launchAtLogin = LaunchAtLoginClient(
        isRegistered: { sceneState.launchAtLoginRegistered },
        setRegistered: { sceneState.launchAtLoginRegistered = $0 },
      )
      // No scene may leave the app it is driving. Recording the destination is what lets a test
      // see which door was asked for without System Settings ever opening.
      let resultFile = AgentSceneFiles.result
      dependencies.workspace.open = { url in
        try url.absoluteString.write(to: resultFile, atomically: true, encoding: .utf8)
        throw AgentSceneRefusal.systemSettings
      }
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

  // MARK: - AgentSceneState

  /// Everything a seeded client both reads and writes outlives the reducer that asked for it: the
  /// clients are plain closures, so the answers have to be kept somewhere all of them can reach.
  /// When the driver swaps scenes at runtime, the same instance is reseeded so the clients answer
  /// for the scene now on screen rather than the one the process launched with.
  final class AgentSceneState: @unchecked Sendable {
    // MARK: Lifecycle

    init(scene: AgentDriveabilityScene) {
      let seeded = scene.initialState
      _microphoneStatus = seeded.health.micStatus
      _accessibilityGranted = seeded.health.accessibilityGranted
      _launchAtLoginRegistered = seeded.settingsWindow.settingsPane.launchAtLoginRegistered
    }

    // MARK: Internal

    /// Written once at store creation and rewritten only by the driver's scene swaps, both on
    /// the main thread; the instance itself locks.
    nonisolated(unsafe) static var current: AgentSceneState?

    var microphoneStatus: MicPermissionStatus {
      get { lock.withLock { _microphoneStatus } }
      set { lock.withLock { _microphoneStatus = newValue } }
    }

    var accessibilityGranted: Bool {
      get { lock.withLock { _accessibilityGranted } }
      set { lock.withLock { _accessibilityGranted = newValue } }
    }

    var launchAtLoginRegistered: Bool {
      get { lock.withLock { _launchAtLoginRegistered } }
      set { lock.withLock { _launchAtLoginRegistered = newValue } }
    }

    func reseed(for scene: AgentDriveabilityScene) {
      let seeded = scene.initialState
      lock.withLock {
        _microphoneStatus = seeded.health.micStatus
        _accessibilityGranted = seeded.health.accessibilityGranted
        _launchAtLoginRegistered = seeded.settingsWindow.settingsPane.launchAtLoginRegistered
      }
    }

    // MARK: Private

    private let lock = NSLock()
    private var _microphoneStatus: MicPermissionStatus
    private var _accessibilityGranted: Bool
    private var _launchAtLoginRegistered: Bool
  }
#endif
