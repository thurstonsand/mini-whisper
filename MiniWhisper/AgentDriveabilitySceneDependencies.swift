import AppSettings
import ASREngine
import AudioCapture
import ComposableArchitecture
import Foundation
import HotkeyListener
import ModelLibrary
import TranscriptCleanup

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
      dependencies.asrEngine.installAndPrepare = { _ in AsyncStream { $0.finish() } }
      dependencies.asrEngine.unload = { _ in }
      dependencies.asrEngine.verifyKey = { _, key in
        if key.hasPrefix("sk_rejected") {
          throw ASREngineError.credentialRejected
        }
      }
      dependencies.modelLibrary = ModelLibraryClient(
        states: { sceneState.assetStates() },
        delete: { sceneState.deleteAsset($0) },
        install: { sceneState.installAsset($0) },
        isInstalled: { sceneState.isInstalled($0) },
      )
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
      // The pane's key really is read, stored, and re-read; only the Keychain behind it is the
      // scene's, so a UI run cannot leave a credential on the machine.
      dependencies.keychain = KeychainClient(
        store: { secret, slot in sceneState.keys[slot] = secret },
        read: { slot in sceneState.keys[slot] },
        delete: { slot in sceneState.keys[slot] = nil },
      )
      dependencies.cleanup = CleanupClient(
        clean: { _, _, _ in .cleaned("Agent scenes never dictate.") },
        // Each way a Save can fail has an address, a key, or a model that provokes it, so a UI
        // run reaches every failure by typing rather than by a seam.
        verify: { configuration, apiKey in
          let endpoint = configuration.endpoint
          if endpoint.host() == "slow.example" {
            try? await Task.sleep(for: .seconds(30))
            return .cancelled
          }
          if endpoint.port == 11435 {
            return .failed(.unreachable("Connection refused"))
          }
          if endpoint.host() == "needs-key.example", apiKey == nil {
            return .failed(.httpStatus(code: 401, message: nil))
          }
          if apiKey?.hasPrefix("sk-rejected") == true {
            return .failed(.httpStatus(code: 401, message: "invalid x-api-key"))
          }
          if configuration.model == "qwen3:32b" {
            return .failed(.httpStatus(code: 404, message: "model 'qwen3:32b' not found"))
          }
          return .verified
        },
        listModels: { configuration, _ in
          switch configuration.endpoint.host() {
          case "api.anthropic.com":
            .models(["claude-haiku-5-5", "claude-sonnet-5-5"])
          case "generativelanguage.googleapis.com":
            .models(["gemini-3.8-flash", "gemini-3.5-flash-lite"])
          default:
            .models(["gpt-oss-120b", "gpt-oss-20b"])
          }
        },
        cleanLocally: { _, _ in .cleaned("Agent scenes never dictate.") },
        prepareLocal: {},
        unloadLocal: {},
      )
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
      _keys = scene.seededKeys
      _assets = scene.seededAssets
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

    var keys: [CredentialSlot: String] {
      get { lock.withLock { _keys } }
      set { lock.withLock { _keys = newValue } }
    }

    func reseed(for scene: AgentDriveabilityScene) {
      let seeded = scene.initialState
      lock.withLock {
        _microphoneStatus = seeded.health.micStatus
        _accessibilityGranted = seeded.health.accessibilityGranted
        _launchAtLoginRegistered = seeded.settingsWindow.settingsPane.launchAtLoginRegistered
        _keys = scene.seededKeys
        _assets = scene.seededAssets
      }
      broadcastAssets()
    }

    func assetStates() -> AsyncStream<[ModelAsset: AssetState]> {
      AsyncStream { continuation in
        let assets = lock.withLock {
          _assetObservers.append(continuation)
          return _assets
        }
        continuation.yield(assets)
      }
    }

    func deleteAsset(_ asset: ModelAsset) {
      lock.withLock { _assets[asset] = .missing }
      broadcastAssets()
    }

    /// Instant, so a scene never touches the network and still shows where a press lands.
    func installAsset(_ asset: ModelAsset) {
      lock.withLock { _assets[asset] = .installed(bytes: asset.pinnedBytes) }
      broadcastAssets()
    }

    func isInstalled(_ asset: ModelAsset) -> Bool {
      lock.withLock { _assets[asset]?.isInstalled == true }
    }

    // MARK: Private

    private let lock = NSLock()
    private var _microphoneStatus: MicPermissionStatus
    private var _accessibilityGranted: Bool
    private var _launchAtLoginRegistered: Bool
    private var _keys: [CredentialSlot: String]
    private var _assets: [ModelAsset: AssetState]
    private var _assetObservers: [AsyncStream<[ModelAsset: AssetState]>.Continuation] = []

    private func broadcastAssets() {
      let (assets, observers) = lock.withLock { (_assets, _assetObservers) }
      for observer in observers {
        observer.yield(assets)
      }
    }
  }
#endif
