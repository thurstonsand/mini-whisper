import AudioCapture
import ComposableArchitecture
import Foundation
import OSLog

private let captureLogger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "capture")
private let performanceLogger = Logger(
  subsystem: "com.thurstonsand.MiniWhisper", category: "performance")

@Reducer struct RecordingFeature {
  @ObservableState struct State: Equatable {
    enum Phase: Equatable {
      case idle
      case starting(PendingCompletion?)
      case recording
      case stopping(PendingRestart?)
      case cancelling
    }

    enum PendingCompletion: Equatable { case stop, cancel }
    enum PendingRestart: Equatable { case restart }

    var micStatus: MicPermissionStatus = .undetermined
    var phase = Phase.idle
    var latestLevel: Float = 0
    var captureError: AudioCaptureError?
    var captureGeneration = 0
    var captureSessionID: UUID?
  }

  enum Action: Equatable {
    enum Delegate: Equatable {
      case recordingStarted(inputDeviceName: String)
      case levelChanged(Float)
      case completed(CanonicalRecording)
      case discarded
      case failed
    }

    case task
    case micStatusUpdated(MicPermissionStatus)
    case capturePreparationFailed(AudioCaptureError)
    case startRecording
    case stopAndRetain
    case cancelRecording
    case captureSessionStarted(Int, UUID)
    case captureBecameLive(Int, UUID, String)
    case levelUpdated(Int, AudioLevel)
    case captureFailed(Int, AudioCaptureError)
    case captureEventsFinished(Int)
    case captureStopped(Int, CanonicalRecording)
    case captureCancelled(Int)
    case debugWAVWritten(String)
    case debugWAVWriteFailed(AudioCaptureError)
    case delegate(Delegate)
  }

  private enum CancelID { case captureEvents, stop }

  @Dependency(\.audioCapture) var audioCapture
  @Dependency(\.microphonePermission) var microphonePermission

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .task:
        return .merge(
          .run { send in await send(.micStatusUpdated(await microphonePermission.status())) },
          .run { send in
            do { try await audioCapture.prepare() } catch {
              await send(.capturePreparationFailed(captureError(from: error)))
            }
          })
      case .micStatusUpdated(let status):
        state.micStatus = status
        return .none
      case .capturePreparationFailed(let error):
        state.captureError = error
        captureLogger.error(
          "Audio capture preparation failed: \(error.localizedDescription, privacy: .public)")
        return .none
      case .startRecording:
        switch state.phase {
        case .idle:
          performanceLogger.notice("benchmark capture-start-requested")
          state.captureGeneration += 1
          state.captureSessionID = nil
          state.phase = .starting(nil)
          state.latestLevel = 0
          state.captureError = nil
          return startCapture(generation: state.captureGeneration)
        case .starting(.stop):
          state.phase = .starting(nil)
          return .none
        case .stopping:
          state.phase = .stopping(.restart)
          return .none
        case .starting, .recording, .cancelling: return .none
        }
      case .stopAndRetain:
        switch state.phase {
        case .starting(.cancel): return .none
        case .starting:
          state.phase = .starting(.stop)
          return .none
        case .recording:
          guard let sessionID = state.captureSessionID else {
            return missingSessionFailure(generation: state.captureGeneration)
          }
          state.phase = .stopping(nil)
          return stopCapture(generation: state.captureGeneration, sessionID: sessionID)
        case .idle, .stopping, .cancelling: return .none
        }
      case .cancelRecording:
        switch state.phase {
        case .starting:
          if let sessionID = state.captureSessionID {
            state.phase = .cancelling
            return .concatenate(
              .send(.delegate(.discarded)),
              cancelCapture(generation: state.captureGeneration, sessionID: sessionID))
          }
          state.phase = .starting(.cancel)
          return .send(.delegate(.discarded))
        case .recording, .stopping:
          guard let sessionID = state.captureSessionID else {
            return missingSessionFailure(generation: state.captureGeneration)
          }
          state.phase = .cancelling
          return .concatenate(
            .send(.delegate(.discarded)),
            .merge(
              .cancel(id: CancelID.stop),
              cancelCapture(generation: state.captureGeneration, sessionID: sessionID)))
        case .idle, .cancelling: return .none
        }
      case .captureSessionStarted(let generation, let sessionID):
        guard generation == state.captureGeneration,
          case .starting(let pendingCompletion) = state.phase
        else { return cancelCapture(generation: generation, sessionID: sessionID) }

        state.captureSessionID = sessionID
        guard pendingCompletion == .cancel else { return .none }
        state.phase = .cancelling
        return cancelCapture(generation: generation, sessionID: sessionID)
      case .captureBecameLive(let generation, let sessionID, let inputDeviceName):
        guard generation == state.captureGeneration, state.captureSessionID == sessionID,
          case .starting(let pendingCompletion) = state.phase
        else { return .none }

        state.phase = .recording
        captureLogger.notice("Audio capture became live")
        switch pendingCompletion {
        case .stop:
          return .concatenate(
            .send(.delegate(.recordingStarted(inputDeviceName: inputDeviceName))),
            .send(.stopAndRetain))
        case .cancel:
          state.phase = .cancelling
          return cancelCapture(generation: generation, sessionID: sessionID)
        case nil: return .send(.delegate(.recordingStarted(inputDeviceName: inputDeviceName)))
        }
      case .levelUpdated(let generation, let level):
        guard generation == state.captureGeneration else { return .none }
        switch state.phase {
        case .recording, .stopping:
          state.latestLevel = level.normalizedPower
          return .send(.delegate(.levelChanged(level.normalizedPower)))
        case .idle, .starting, .cancelling: return .none
        }
      case .captureFailed(let generation, let error):
        guard generation == state.captureGeneration, state.phase != .idle,
          state.phase != .cancelling
        else { return .none }

        state.phase = .cancelling
        state.latestLevel = 0
        state.captureError = error
        if case .microphonePermission(let status) = error { state.micStatus = status }
        captureLogger.error("Audio capture failed: \(error.localizedDescription, privacy: .public)")

        let cleanup: Effect<Action>
        if let sessionID = state.captureSessionID {
          cleanup = cancelCapture(generation: generation, sessionID: sessionID)
        } else {
          cleanup = .send(.captureCancelled(generation))
        }
        return .concatenate(.send(.delegate(.failed)), cleanup)
      case .captureEventsFinished(let generation):
        guard generation == state.captureGeneration else { return .none }
        switch state.phase {
        case .starting, .recording:
          return .send(.captureFailed(generation, .unexpected("Audio capture event stream ended")))
        case .idle, .stopping, .cancelling: return .none
        }
      case .captureStopped(let generation, let recording):
        guard generation == state.captureGeneration,
          case .stopping(let pendingRestart) = state.phase
        else { return .none }
        state.captureSessionID = nil
        state.latestLevel = 0
        if pendingRestart == .restart {
          state.captureGeneration += 1
          state.phase = .starting(nil)
          captureLogger.notice("Restarting audio capture for latch")
          return startCapture(generation: state.captureGeneration)
        }

        state.phase = .idle
        captureLogger.notice(
          "Audio capture stopped duration=\(recording.durationSeconds, format: .fixed(precision: 3))s samples=\(recording.samples.count)"
        )
        return .concatenate(.send(.delegate(.completed(recording))), writeDebugWAV(recording))
      case .captureCancelled(let generation):
        guard generation == state.captureGeneration, state.phase == .cancelling else {
          return .none
        }
        state.captureSessionID = nil
        state.phase = .idle
        state.latestLevel = 0
        captureLogger.notice("Audio capture cancelled and discarded")
        return .none
      case .debugWAVWritten(let path):
        captureLogger.notice("Debug capture WAV: \(path, privacy: .public)")
        return .none
      case .debugWAVWriteFailed(let error):
        captureLogger.error(
          "Debug capture WAV write failed: \(error.localizedDescription, privacy: .public)")
        return .none
      case .delegate: return .none
      }
    }
  }

  private func startCapture(generation: Int) -> Effect<Action> {
    let cancellation = CaptureCancellation()
    return .run { send in
      await withTaskCancellationHandler {
        do {
          let session = try await audioCapture.start()
          if cancellation.setSessionID(session.id) {
            await audioCapture.cancel(session.id)
            return
          }
          await send(.captureSessionStarted(generation, session.id))

          var summary = LevelSummary()
          var summaryStartedAt = ContinuousClock.now
          for await event in session.events {
            switch event {
            case .captureBecameLive:
              await send(.captureBecameLive(generation, session.id, session.inputDeviceName))
            case .level(let level):
              await send(.levelUpdated(generation, level))
              summary.add(level)
              let now = ContinuousClock.now
              if summaryStartedAt.duration(to: now) >= .seconds(1) {
                summary.log()
                summary = LevelSummary()
                summaryStartedAt = now
              }
            case .failed(let error): await send(.captureFailed(generation, error))
            }
          }
          summary.log()
          await send(.captureEventsFinished(generation))
        } catch { await send(.captureFailed(generation, captureError(from: error))) }
      } onCancel: {
        guard let sessionID = cancellation.cancel() else { return }
        Task { await audioCapture.cancel(sessionID) }
      }
    }.cancellable(id: CancelID.captureEvents, cancelInFlight: true)
  }

  private func stopCapture(generation: Int, sessionID: UUID) -> Effect<Action> {
    .run { send in
      do { await send(.captureStopped(generation, try await audioCapture.stop(sessionID))) } catch {
        await send(.captureFailed(generation, captureError(from: error)))
      }
    }.cancellable(id: CancelID.stop, cancelInFlight: true)
  }

  private func cancelCapture(generation: Int, sessionID: UUID) -> Effect<Action> {
    .run { send in
      await audioCapture.cancel(sessionID)
      await send(.captureCancelled(generation))
    }
  }

  private func writeDebugWAV(_ recording: CanonicalRecording) -> Effect<Action> {
    .run { send in
      do {
        let url = try await audioCapture.writeDebugWAV(recording)
        await send(.debugWAVWritten(url.path))
      } catch { await send(.debugWAVWriteFailed(captureError(from: error))) }
    }
  }

  private func missingSessionFailure(generation: Int) -> Effect<Action> {
    .send(.captureFailed(generation, .unexpected("Capture state has no session identifier")))
  }
}

private final class CaptureCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var isCancelled = false
  private var sessionID: UUID?

  func setSessionID(_ sessionID: UUID) -> Bool {
    lock.withLock {
      self.sessionID = sessionID
      return isCancelled
    }
  }

  func cancel() -> UUID? {
    lock.withLock {
      isCancelled = true
      return sessionID
    }
  }
}

private struct LevelSummary {
  private var minimum = Float.greatestFiniteMagnitude
  private var maximum = Float.zero
  private var total = Float.zero
  private var count = 0

  mutating func add(_ level: AudioLevel) {
    minimum = min(minimum, level.normalizedPower)
    maximum = max(maximum, level.normalizedPower)
    total += level.normalizedPower
    count += 1
  }

  func log() {
    guard count > 0 else { return }
    captureLogger.info(
      "Audio level summary count=\(count) min=\(minimum, format: .fixed(precision: 2)) avg=\(total / Float(count), format: .fixed(precision: 2)) max=\(maximum, format: .fixed(precision: 2))"
    )
  }
}

private func captureError(from error: any Error) -> AudioCaptureError {
  if let error = error as? AudioCaptureError { return error }
  return .unexpected(error.localizedDescription)
}
