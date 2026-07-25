import ASREngine
import AudioCapture
import ComposableArchitecture
import Foundation
import HotkeyListener
import OSLog

private let gestureLogger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "gesture")
private let engineLogger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "engine")
private let performanceLogger = Logger(
  subsystem: "com.thurstonsand.MiniWhisper", category: "performance")
private let maximumAccidentalLoneTapDuration: TimeInterval = 0.35

@Reducer struct AppFeature {
  @ObservableState struct State: Equatable {
    var recording = RecordingFeature.State()
    var pill = PillFeature.State()
    var engineReadiness: EngineReadiness = .modelMissing
    var transcriptionGeneration = 0

    var menuBar: MenuBarViewState {
      MenuBarViewState(micStatus: recording.micStatus, engineReadiness: engineReadiness)
    }
  }

  enum Action: Equatable {
    case task
    case recording(RecordingFeature.Action)
    case pill(PillFeature.Action)
    case hotkeyListenerEvent(HotkeyListenerEvent)
    case hotkeyListenerFailed(String)
    case setupEngine
    case engineReadinessUpdated(EngineReadiness)
    case transcriptionCompleted(Int, suppressNoSpeechNotice: Bool, TranscriptionOutcome)
    case transcriptionFailed(Int, String)
  }

  private enum CancelID { case transcription }

  @Dependency(\.asrEngine) var asrEngine
  @Dependency(\.audioCapture) var audioCapture
  @Dependency(\.hotkeyListener) var hotkeyListener

  var body: some ReducerOf<Self> {
    Scope(state: \.recording, action: \.recording) { RecordingFeature() }
    Scope(state: \.pill, action: \.pill) { PillFeature() }

    Reduce { state, action in
      switch action {
      case .task:
        return .merge(
          .send(.recording(.task)),
          .run { send in
            for await readiness in asrEngine.prepareInstalled() {
              await send(.engineReadinessUpdated(readiness))
            }
          },
          .run { send in
            do {
              let events = try await hotkeyListener.events()
              for await event in events { await send(.hotkeyListenerEvent(event)) }
            } catch { await send(.hotkeyListenerFailed(String(describing: error))) }
          })
      case .hotkeyListenerEvent(.inputMonitoringPermissionMissing):
        gestureLogger.error(
          "Input Monitoring permission missing — grant in System Settings and relaunch")
        return .none
      case .hotkeyListenerEvent(.monitoringStarted):
        gestureLogger.notice("Hotkey event tap installed")
        return .none
      case .hotkeyListenerEvent(.monitoringInterrupted(let reason)):
        gestureLogger.error("Hotkey event tap interrupted: \(reason.rawValue, privacy: .public)")
        return .none
      case .hotkeyListenerEvent(.gesture(let event)):
        gestureLogger.notice("\(event.rawValue, privacy: .public)")
        switch event {
        case .startRecording:
          performanceLogger.notice("benchmark app-activation-received")
          state.transcriptionGeneration += 1
          return .concatenate(
            .send(
              .pill(
                .recordingStarting(
                  inputDeviceName: audioCapture.currentInputDeviceName() ?? "Microphone"))),
            .merge(
              .cancel(id: CancelID.transcription), .send(.recording(.startRecording)),
              .run { send in
                for await readiness in asrEngine.prepareForActivation() {
                  await send(.engineReadinessUpdated(readiness))
                }
              }))
        case .stopAndTranscribe:
          performanceLogger.notice("benchmark recording-release-received")
          return .send(.recording(.stopAndRetain))
        case .latchEngaged: return .send(.pill(.latchEngaged))
        case .cancel: return .send(.recording(.cancelRecording))
        }
      case .hotkeyListenerFailed(let error):
        gestureLogger.error("Hotkey listener failed: \(error, privacy: .public)")
        return .none
      case .setupEngine:
        engineLogger.notice("Pinned model setup requested")
        return .run { send in
          for await readiness in asrEngine.installAndPrepare() {
            await send(.engineReadinessUpdated(readiness))
          }
        }
      case .engineReadinessUpdated(let readiness):
        state.engineReadiness = readiness
        switch readiness {
        case .modelMissing: engineLogger.error("Pinned speech models are missing")
        case .downloading(let fraction):
          engineLogger.notice(
            "Pinned model download \(fraction * 100, format: .fixed(precision: 1))%")
        case .compiling: engineLogger.notice("Compiling pinned Core ML models")
        case .prewarming: engineLogger.notice("Prewarming resident speech engine")
        case .ready: engineLogger.notice("Resident speech engine ready")
        case .failed(let message):
          engineLogger.error("Speech engine setup failed: \(message, privacy: .public)")
        }
        return .none
      case .recording(.delegate(.recordingStarted(let inputDeviceName))):
        return .send(.pill(.recordingStarted(inputDeviceName: inputDeviceName)))
      case .recording(.delegate(.levelChanged(let level))):
        return .send(.pill(.levelUpdated(level)))
      case .recording(.delegate(.completed(let recording))):
        let generation = state.transcriptionGeneration
        let suppressNoSpeechNotice = recording.durationSeconds <= maximumAccidentalLoneTapDuration
        return .concatenate(
          .send(.pill(.transcribingStarted)),
          .run { send in
            performanceLogger.notice("benchmark transcription-started")
            do {
              await send(
                .transcriptionCompleted(
                  generation, suppressNoSpeechNotice: suppressNoSpeechNotice,
                  try await asrEngine.submit(recording)))
            } catch { await send(.transcriptionFailed(generation, error.localizedDescription)) }
          }.cancellable(id: CancelID.transcription, cancelInFlight: true))
      case .recording(.delegate(.discarded)): return .send(.pill(.cancel))
      case .recording: return .none
      case .transcriptionCompleted(let generation, _, .transcript(let transcript)):
        guard generation == state.transcriptionGeneration else { return .none }
        engineLogger.notice("Transcript: \(transcript, privacy: .public)")
        return .send(.pill(.dismiss))
      case .transcriptionCompleted(let generation, let suppressNotice, .noSpeech):
        guard generation == state.transcriptionGeneration else { return .none }
        engineLogger.notice("Gate rejected recording: no speech")
        return .send(.pill(suppressNotice ? .dismiss : .noSpeechDetected))
      case .transcriptionCompleted(let generation, _, .engineEmpty):
        guard generation == state.transcriptionGeneration else { return .none }
        engineLogger.notice("Engine accepted speech but returned an empty transcript")
        return .send(.pill(.noSpeechDetected))
      case .transcriptionFailed(let generation, let message):
        guard generation == state.transcriptionGeneration else { return .none }
        state.engineReadiness = .failed(message)
        engineLogger.error("Transcription failed: \(message, privacy: .public)")
        return .send(.pill(.dismiss))
      case .pill: return .none
      }
    }
  }
}

struct MenuBarViewState: Equatable {
  var iconSymbolName: String
  var statusText: String
  var engineSetupTitle: String?
  var canSetupEngine = false

  init(micStatus: MicPermissionStatus, engineReadiness: EngineReadiness) {
    switch micStatus {
    case .denied:
      self.iconSymbolName = "mic.slash"
      self.statusText = "Microphone permission required"
    case .restricted:
      self.iconSymbolName = "mic.slash"
      self.statusText = "Microphone access restricted"
    case .undetermined:
      self.iconSymbolName = "mic"
      self.statusText = "Microphone permission not yet requested"
    case .unknown:
      self.iconSymbolName = "mic.slash"
      self.statusText = "Microphone permission unavailable"
    case .granted:
      switch engineReadiness {
      case .modelMissing:
        self.iconSymbolName = "mic.badge.xmark"
        self.statusText = "Parakeet v2 model required"
        self.engineSetupTitle = "Download & Prepare Parakeet v2…"
        self.canSetupEngine = true
      case .downloading(let fraction):
        self.iconSymbolName = "mic.badge.plus"
        self.statusText = "Downloading Parakeet v2 · \(Int(fraction * 100))%"
        self.engineSetupTitle = "Downloading Parakeet v2… \(Int(fraction * 100))%"
      case .compiling:
        self.iconSymbolName = "mic.badge.plus"
        self.statusText = "Compiling Parakeet v2"
        self.engineSetupTitle = "Compiling Parakeet v2…"
      case .prewarming:
        self.iconSymbolName = "mic.badge.plus"
        self.statusText = "Prewarming Parakeet v2"
        self.engineSetupTitle = "Prewarming Parakeet v2…"
      case .ready:
        self.iconSymbolName = "mic"
        self.statusText = "Ready · Parakeet v2"
      case .failed:
        self.iconSymbolName = "mic.badge.xmark"
        self.statusText = "Parakeet v2 setup failed"
        self.engineSetupTitle = "Retry Parakeet v2 Setup…"
        self.canSetupEngine = true
      }
    }
  }
}
